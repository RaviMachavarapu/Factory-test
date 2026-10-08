#!/usr/bin/env bash
# REQ-352, REQ-386 (P6 R33): sign and notarize the app bundle a release built, and rewrite its manifest entry.
# Usage: release-sign.sh --stack <tauri|flutter> --dist <dir> --entitlements <plist>
#   Run from the project's root. The bundle is the manifest's one entry of kind bundle, whose filename must be a plain
#   basename (^[A-Za-z0-9._-]+\.(dmg|zip)$, checked before any tool runs; else exit 2).
#   Entitlements (P7 R7): the app is signed with the entitlements the project committed, never with the set its
#   untrusted build embedded: flutter's macos/Runner/Release.entitlements, tauri's src-tauri/tauri.conf.json
#   bundle.macOS.entitlements (relative to src-tauri/), else --entitlements (the pack's file); the debugger entitlement
#   (com.apple.security.get-task-allow) is removed from it: a notarized app must not carry it. A file the project names
#   but lacks, one outside the project, or one that is not a plist dictionary is exit 2. The set the unsigned app
#   embeds (`codesign -d --entitlements :-`) is read only to compare: a key it carries that the committed set lacks, or
#   carries with another value (get-task-allow aside), is exit 1 before anything is signed, naming the keys and the
#   committed file; an app that embeds fewer keys, or none, is signed with the committed set all the same.
#   Nested code first: every Mach-O file inside the .app (by its magic number; the sidecars in Contents/MacOS, the
#   helpers in Contents/Helpers, frameworks' binaries, dylibs) and every .framework/.xpc/.app/.appex bundle, innermost
#   first (deepest path first), with the hardened runtime and a timestamp; the app's main executable is signed with the
#   app, never alone; then the app with the entitlements.
#   tauri (.dmg): attach read-only, copy the .app out, sign it, build a new dmg from a stage holding the .app and the
#     /Applications symlink (the drag-to-install layout), sign the dmg, notarize it, staple it (a .dmg is read-only: its
#     inner app cannot be signed in place).
#   flutter (.zip): extract, sign the .app the same way, zip it (ditto -c -k --sequesterRsrc --keepParent, the hook's
#     flags), notarize the zip, staple the .app (a zip cannot be stapled), zip it again.
#   Notarization passes only when notarytool exits 0 AND its last `status:` line says Accepted (an exit-0 Invalid fails).
# Then release_manifest.py rewrite-entry replaces the bundle with the signed file: new sha256 and size, signed true.
# The caller (release.yml's sign job) has created the keychain, put it on the user search list and holds the
# APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD values in this script's environment; the one Developer ID Application
# identity is found with `security find-identity`. Nothing here echoes an Apple value (set +x throughout; notarytool's
# output is filtered by python3 reading the values from its environment, never from argv). The app-specific password
# does reach notarytool's argv (--password): `notarytool store-credentials` takes it only on argv or at an interactive
# terminal prompt, with no documented environment or stdin path, so a keychain profile would still put it on argv once
# — an ephemeral-runner residual (P6 R33, the threat model): the process list of a single-use GitHub-hosted runner,
# where only this job's own processes run. Exit 0 signed; 2 usage or missing input; 1 on any tool failure, naming the
# step. Optional RELEASE_SIGN_KEYCHAIN: the keychain path, handed to find-identity and every signing codesign call.
# bash 3.2 compatible.
set +x
set -uo pipefail

usage() { echo "usage: release-sign.sh --stack <tauri|flutter> --dist <dir> --entitlements <plist>" >&2; exit 2; }

STACK=""; DIST=""; ENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || usage; STACK="$2"; shift 2 ;;
    --dist) [ $# -ge 2 ] || usage; DIST="$2"; shift 2 ;;
    --entitlements) [ $# -ge 2 ] || usage; ENT="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "$STACK" in tauri | flutter) ;; *) usage ;; esac
[ -n "$DIST" ] && [ -d "$DIST" ] || usage
[ -n "$ENT" ] && [ -f "$ENT" ] || { echo "release-sign: the entitlements file is not a file" >&2; exit 2; }
[ -f "$DIST/manifest.json" ] || { echo "release-sign: $DIST/manifest.json is absent" >&2; exit 2; }
for v in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
  if [ -z "${!v:-}" ]; then echo "release-sign: $v is not set in the environment" >&2; exit 2; fi
done

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/specflow"
KC="${RELEASE_SIGN_KEYCHAIN:-}"
STEP="start"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/specflow-sign.XXXXXX")"
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
die() { echo "release-sign: FAILED at step: $STEP" >&2; exit 1; }
step() { STEP="$1"; echo "release-sign: $1"; }

# The bundle: the manifest's one entry of kind bundle.
NAME="$(python3 -I - "$DIST/manifest.json" <<'PY'
import json, sys
b = [a.get("filename") for a in json.load(open(sys.argv[1]))["artifacts"] if a.get("kind") == "bundle"]
if len(b) != 1 or not isinstance(b[0], str) or "\n" in b[0]:
    sys.exit(1)
print(b[0])
PY
)" || { echo "release-sign: the manifest must hold exactly one bundle entry" >&2; exit 2; }
# A plain basename, before hdiutil, ditto or a copy ever sees it: no slash, no space, no shell or path syntax.
NAME_RX='^[A-Za-z0-9._-]+\.(dmg|zip)$'
if ! [[ "$NAME" =~ $NAME_RX ]]; then
  echo "release-sign: the bundle's filename '$NAME' is not a plain .dmg or .zip basename" >&2
  exit 2
fi
case "$STACK:$NAME" in
  tauri:*.dmg | flutter:*.zip) ;;
  *) echo "release-sign: $NAME is not the $STACK bundle shape (.dmg for tauri, .zip for flutter)" >&2; exit 2 ;;
esac
[ -f "$DIST/$NAME" ] || { echo "release-sign: $DIST/$NAME is absent" >&2; exit 2; }

# The entitlements the tree gives (the committed set): the project's own file, else the pack's; get-task-allow removed.
# Validated here, before anything is mounted or signed; sign_app signs with it and only compares the embedded set.
ENT_TREE="$WORK/entitlements-tree.plist"
python3 -I - "$STACK" "$ENT" "$ENT_TREE" "$ENT_TREE.shown" <<'PY' || exit 2
import json, os, plistlib, sys
stack, fallback, out, shown_out = sys.argv[1:5]
root = os.path.realpath(os.getcwd())
src, shown = fallback, "the pack's entitlements.plist"
if stack == "flutter":
    cand = os.path.join("macos", "Runner", "Release.entitlements")
    if os.path.isfile(cand):
        src, shown = cand, cand
else:
    conf = os.path.join("src-tauri", "tauri.conf.json")
    named = None
    if os.path.isfile(conf):
        try:
            named = (((json.load(open(conf, encoding="utf-8")) or {}).get("bundle") or {}).get("macOS") or {}).get("entitlements")
        except (ValueError, AttributeError):
            sys.exit(f"release-sign: {conf} is not a JSON object")
    if named is not None:
        if not isinstance(named, str) or not named:
            sys.exit(f"release-sign: {conf}'s bundle.macOS.entitlements is not a path")
        cand = os.path.realpath(os.path.join("src-tauri", named))
        if os.path.commonpath([root, cand]) != root:
            sys.exit(f"release-sign: {conf}'s bundle.macOS.entitlements ({named}) is outside the project")
        if not os.path.isfile(cand):
            sys.exit(f"release-sign: {conf} names the entitlements file {named}, which src-tauri/ does not hold")
        src, shown = cand, os.path.relpath(cand, root)
try:
    d = plistlib.load(open(src, "rb"))
except Exception:
    d = None
if not isinstance(d, dict):
    sys.exit(f"release-sign: {shown} is not a plist dictionary")
d.pop("com.apple.security.get-task-allow", None)
with open(out, "wb") as f:
    plistlib.dump(d, f)
open(shown_out, "w").write(shown)
print(f"release-sign: the tree's entitlements: {shown} ({len(d)} key(s); get-task-allow never signed in)")
PY

step "find the Developer ID Application identity"
if [ -n "$KC" ]; then IDOUT="$(security find-identity -v -p codesigning "$KC")" || die
else IDOUT="$(security find-identity -v -p codesigning)" || die; fi
IDS="$(printf '%s\n' "$IDOUT" | grep 'Developer ID Application' | grep -oE '[0-9A-Fa-f]{40}' | sort -u)"
case "$(printf '%s' "$IDS" | grep -c .)" in
  1) ;;
  0) echo "release-sign: no Developer ID Application identity in the keychain" >&2; exit 1 ;;
  *) echo "release-sign: more than one Developer ID Application identity in the keychain; exactly one is expected" >&2; exit 1 ;;
esac
ID="$IDS"

# sign_app APP — compare the app's embedded entitlements with the committed set (refuse a key it does not grant), the
# nested code innermost first, then the app itself with the committed set.
sign_app() {
  local app="$1" n
  set +x
  step "compare the entitlements $(basename "$app") was built with to the committed set"
  ENT_USED="$ENT_TREE"
  codesign -d --entitlements :- "$app" > "$WORK/app-entitlements.raw" 2>/dev/null || : > "$WORK/app-entitlements.raw"
  python3 -I - "$WORK/app-entitlements.raw" "$ENT_TREE" "$ENT_TREE.shown" <<'PY'
import plistlib, sys
raw, tree, shown = sys.argv[1:4]
data = open(raw, "rb").read()
starts = [i for i in (data.find(b"bplist"), data.find(b"<?xml"), data.find(b"<plist")) if i >= 0]
d = None
if starts:
    try:
        d = plistlib.loads(data[min(starts):])
    except Exception:
        d = None
if not (isinstance(d, dict) and d):
    print("release-sign: the app embeds no entitlements: the committed set is used")
    sys.exit(0)
d.pop("com.apple.security.get-task-allow", None)
committed = plistlib.load(open(tree, "rb"))
bad = sorted(k for k, v in d.items() if k not in committed or committed[k] != v)
if bad:
    sys.stderr.write("release-sign: the app embeds entitlements the project's committed file does not grant: "
                     + ", ".join(bad) + " (" + open(shown).read() + "); add them to that file by a reviewed PR, or build without them\n")
    sys.exit(1)
print(f"release-sign: the app's embedded entitlements ({len(d)} key(s)) are within the committed set; signing with the committed set")
PY
  [ $? = 0 ] || { STEP="compare the entitlements"; exit 1; }
  step "find the nested code in $(basename "$app")"
  python3 -I - "$app" > "$WORK/nested.list" <<'PY' || die
import os, plistlib, struct, sys
app = os.path.abspath(sys.argv[1])
main = None
try:
    with open(os.path.join(app, "Contents", "Info.plist"), "rb") as f:
        main = plistlib.load(f).get("CFBundleExecutable")
except Exception:
    main = None
main = os.path.join(app, "Contents", "MacOS", main) if isinstance(main, str) and main else None
THIN = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe"}
FAT = {b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}
def macho(p):
    try:
        with open(p, "rb") as f:
            h = f.read(8)
    except OSError:
        return False
    if h[:4] in THIN:
        return True
    # a fat header's count is small; a Java class file shares the magic with its version (45 or more) there
    return h[:4] in FAT and len(h) == 8 and 0 < struct.unpack(">I", h[4:])[0] < 40
BUNDLES = (".framework", ".xpc", ".app", ".appex")
found = set()
for d, dirs, files in os.walk(app):
    for n in dirs:
        p = os.path.join(d, n)
        if n.endswith(BUNDLES) and not os.path.islink(p):
            found.add(p)
    for n in files:
        p = os.path.join(d, n)
        if not os.path.islink(p) and p != main and (n.endswith(".dylib") or macho(p)):
            found.add(p)
for p in sorted(found, key=lambda p: (-p.count(os.sep), p)):
    print(p)
PY
  step "sign nested code in $(basename "$app")"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    codesign --force --options runtime --timestamp --sign "$ID" ${KC:+--keychain "$KC"} "$n" || die
  done < "$WORK/nested.list"
  step "sign $(basename "$app")"
  codesign --force --options runtime --timestamp --entitlements "$ENT_USED" --sign "$ID" ${KC:+--keychain "$KC"} "$app" || die
}

# notarize FILE — submit, wait up to 30 minutes, and require notarytool's exit 0 AND a last `status:` line of Accepted.
notarize() {
  local f="$1" res rc=0 status
  set +x
  step "notarize $(basename "$f")"
  res="$WORK/notary.out"
  xcrun notarytool submit "$f" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait --timeout 30m > "$res" 2>&1 \
    || rc=$?
  # What the tool printed, minus any line that carries an Apple value: python3 reads the values from its environment.
  python3 -I - "$res" <<'PY' >&2 || true
import os, sys
vals = [os.environ.get(k, "") for k in ("APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_PASSWORD")]
for line in open(sys.argv[1], errors="replace"):
    if not any(v and v in line for v in vals):
        sys.stdout.write(line)
PY
  [ "$rc" = 0 ] || die
  status="$(python3 -I - "$res" <<'PY'
import re, sys
s = [m.group(1).strip() for m in re.finditer(r"(?m)^\s*status:\s*(.*)$", open(sys.argv[1], errors="replace").read())]
print(s[-1] if s else "")
PY
)"
  if [ "$status" != Accepted ]; then
    echo "release-sign: notarization status is '${status:-none}', not Accepted" >&2
    die
  fi
}

OUT="$WORK/out"; mkdir -p "$OUT" "$WORK/stage"
if [ "$STACK" = tauri ]; then
  MOUNT="$WORK/mnt"; mkdir -p "$MOUNT"
  step "attach the dmg read-only"
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DIST/$NAME" >/dev/null || { MOUNT=""; die; }
  APP=""; n=0
  for a in "$MOUNT"/*.app; do [ -d "$a" ] && { n=$((n + 1)); APP="$a"; }; done
  if [ "$n" != 1 ]; then STEP="find the .app in the dmg (found $n)"; die; fi
  step "copy the .app out of the dmg"
  ditto "$APP" "$WORK/stage/$(basename "$APP")" || die
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; MOUNT=""
  APP="$WORK/stage/$(basename "$APP")"
  sign_app "$APP"
  step "stage the drag-to-install layout"
  ln -s /Applications "$WORK/stage/Applications" || die
  step "create the signed dmg"
  hdiutil create -volname "$(basename "$APP" .app)" -srcfolder "$WORK/stage" -ov -format UDZO "$OUT/$NAME" >/dev/null || die
  step "sign the dmg"
  codesign --force --timestamp --sign "$ID" ${KC:+--keychain "$KC"} "$OUT/$NAME" || die
  notarize "$OUT/$NAME"
  step "staple the dmg"
  xcrun stapler staple "$OUT/$NAME" || die
else
  step "extract the zip"
  ditto -x -k "$DIST/$NAME" "$WORK/stage" || die
  APP=""; n=0
  for a in "$WORK/stage"/*.app; do [ -d "$a" ] && { n=$((n + 1)); APP="$a"; }; done
  if [ "$n" != 1 ]; then STEP="find the .app in the zip (found $n)"; die; fi
  sign_app "$APP"
  step "zip the signed app"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize.zip" || die
  notarize "$WORK/notarize.zip"
  step "staple the app"
  xcrun stapler staple "$APP" || die
  step "zip the stapled app"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME" || die
fi

step "rewrite the manifest entry"
python3 -I "$LIB/release_manifest.py" rewrite-entry --manifest "$DIST/manifest.json" --file "$NAME" --from "$OUT/$NAME" --signed || die
echo "release-sign: $NAME signed and notarized (manifest signed: true)"
