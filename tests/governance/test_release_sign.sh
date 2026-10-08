#!/usr/bin/env bash
# REQ-352, REQ-386 (P6 R33): scripts/release-sign.sh signs and notarizes the app bundle through the macOS tools, all
# stubbed here (security, codesign, xcrun, hdiutil, ditto: each appends its argv to a log; no Apple secret exists, and
# none is ever used). A dmg (tauri): attach read-only, copy the .app out, sign it with the hardened runtime and the
# pack's entitlements, build a new dmg, sign it, notarize with the Apple values from the environment, staple the dmg. A
# zip (flutter): extract, sign the .app, zip it, notarize the zip, staple the .app (a zip cannot be stapled), re-zip.
# The manifest entry is rewritten with the new sha256 and size and signed true; a notarization failure exits non-zero
# naming the step and leaves the manifest and the bundle as they were; no marker value appears in the script's output.
# Covers: REQ-352
# Covers: REQ-386
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
SIGN="$ROOT/scripts/release-sign.sh"
LOG="$W/calls.log"
mkdir -p "$W/bin"
stub() { printf '%s\n' '#!/usr/bin/env bash' "echo \"$1 \$*\" >> \"$LOG\"" "${@:2}" > "$W/bin/$1"; chmod +x "$W/bin/$1"; }
# mkapp APP — a stub app with nested code (Build 5 fix wave 1, B): the main executable, a sidecar beside it in
# Contents/MacOS, a framework (its binary under Versions/A, the top-level symlink), a dylib, a helper app in
# Contents/Helpers, and a resource that is not Mach-O. Each Mach-O file starts with the 64-bit magic.
cat > "$W/mkapp.sh" <<'EOF'
#!/usr/bin/env bash
a="$1"; mo() { mkdir -p "$(dirname "$1")"; printf '\xcf\xfa\xed\xfe\x0c\x00\x00\x01' > "$1"; }
mkdir -p "$a/Contents/Resources" "$a/Contents/Frameworks/Foo.framework/Versions/A"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleExecutable</key><string>habit</string></dict></plist>\n' > "$a/Contents/Info.plist"
mo "$a/Contents/MacOS/habit"; mo "$a/Contents/MacOS/habit-sidecar-aarch64-apple-darwin"
mo "$a/Contents/Frameworks/Foo.framework/Versions/A/Foo"; ln -s A "$a/Contents/Frameworks/Foo.framework/Versions/Current"
ln -s Versions/Current/Foo "$a/Contents/Frameworks/Foo.framework/Foo"; mo "$a/Contents/Frameworks/libbar.dylib"
mo "$a/Contents/Helpers/Helper.app/Contents/MacOS/Helper"; echo text > "$a/Contents/Resources/data.txt"
EOF
chmod +x "$W/mkapp.sh"
stub security 'if [ "$1" = find-identity ]; then if [ "${STUB_NO_IDENTITY:-0}" = 1 ]; then echo "     0 valid identities found"; else echo "  1) 0123456789ABCDEF0123456789ABCDEF01234567 \"Developer ID Application: Acme (TEAM123456)\""; echo "     1 valid identities found"; fi; fi'
stub codesign 'if [ "$1" = -d ]; then if [ -n "${STUB_APP_ENT:-}" ]; then cat "$STUB_APP_ENT"; exit 0; fi; echo "code object is not signed at all" >&2; exit 1; fi
p=""; for a in "$@"; do if [ "$p" = --entitlements ]; then cp "$a" "$ENT_SEEN"; fi; p="$a"; done; exit 0'
stub hdiutil 'case "$1" in
  attach) while [ $# -gt 0 ]; do [ "$1" = -mountpoint ] && m="$2"; shift; done; bash "'"$W"'/mkapp.sh" "$m/Habit.app" ;;
  create) s=""; p=""; for a in "$@"; do [ "$p" = -srcfolder ] && s="$a"; p="$a"; f="$a"; done
    echo "stage: $(cd "$s" && ls -A | tr "\n" " ")applications->$(readlink "$s/Applications")" >> "'"$LOG"'"; echo "new dmg bytes" > "$f" ;;
esac'
stub ditto 'case "$1" in
  -x) bash "'"$W"'/mkapp.sh" "$4/Habit.app" ;;
  -c) for a in "$@"; do f="$a"; done; echo "new zip bytes" > "$f" ;;
  *) cp -R "$1" "$2" ;;
esac'
stub xcrun 'if [ "$1" = notarytool ]; then if [ "${STUB_NOTARY_FAIL:-0}" = 1 ]; then echo "Error: notarization rejected"; exit 1; fi; echo "  status: ${STUB_NOTARY_STATUS:-Accepted}"; fi'
# The pack's entitlements file (the fallback): one key of its own, and the debugger entitlement, never signed in.
python3 -c 'import plistlib, sys; plistlib.dump({"com.apple.security.network.client": True, "com.apple.security.get-task-allow": True}, open(sys.argv[1], "wb"))' "$W/ent.plist"
mkdir -p "$W/proj"
M1=idmarker-AAAA; M2=teammarker-BBBB; M3=pwmarker-CCCC
fixture() {  # fixture DIR STACK FILENAME — a dist with a bundle and a schema 2 manifest
  mkdir -p "$1"; echo "old bytes" > "$1/$3"
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib, json, os, sys
d, stack, name = sys.argv[1:4]
p = os.path.join(d, name); b = open(p, "rb").read()
json.dump({"schema": "specflow-manifest/2", "version": "1.0.0", "stack": stack, "source_date_epoch": None, "tree": None,
           "artifacts": [{"filename": name, "sha256": hashlib.sha256(b).hexdigest(), "size": len(b), "kind": "bundle",
                          "reproducible": False, "signed": False}], "signed": False},
          open(os.path.join(d, "manifest.json"), "w"), indent=2)
PY
}
sign() {  # sign ARGS… — the script under the stubs and the marker environment, run in the project $PROJ; sets rc, out
  : > "$LOG"; rm -f "$W/ent.seen"; rc=0
  out=$(cd "${PROJ:-$W/proj}" && PATH="$W/bin:$PATH" ENT_SEEN="$W/ent.seen" APPLE_ID=$M1 APPLE_TEAM_ID=$M2 APPLE_APP_PASSWORD=$M3 bash "$SIGN" "$@" 2>&1) || rc=$?
}
granted() {  # granted SPEC… — the entitlements codesign was handed for the .app: KEY must be granted (true), !KEY absent
  python3 - "$W/ent.seen" "$@" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
for spec in sys.argv[2:]:
    if spec.startswith("!"):
        assert spec[1:] not in d, (spec, d)
    else:
        assert d.get(spec) is True, (spec, d)
PY
}
export -f granted; export W
order() {  # order PATTERN… — each extended regex matches a log line, in this order
  python3 - "$LOG" "$@" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines(); i = 0
for pat in sys.argv[2:]:
    while i < len(lines) and not re.search(pat, lines[i]):
        i += 1
    assert i < len(lines), "missing, or out of order: " + pat
    i += 1
PY
}
entry_ok() {  # entry_ok DIR FILE SIGNED — the manifest's entry matches the file on disk and says signed SIGNED
  python3 - "$@" <<'PY'
import hashlib, json, os, sys
d, name, signed = sys.argv[1:4]
m = json.load(open(os.path.join(d, "manifest.json"))); e = m["artifacts"][0]; b = open(os.path.join(d, name), "rb").read()
assert e["sha256"] == hashlib.sha256(b).hexdigest() and e["size"] == len(b), "sha256 or size"
assert e["signed"] is (signed == "true") and m["signed"] is (signed == "true"), "signed"
PY
}

fixture "$W/dmg" tauri Habit_1.0.0_aarch64.dmg
OLD=$(shasum "$W/dmg/Habit_1.0.0_aarch64.dmg" | cut -d' ' -f1)
sign --stack tauri --dist "$W/dmg" --entitlements "$W/ent.plist"
ck "dmg: exits 0" [ "$rc" = 0 ]
ck "dmg: attach read-only, sign the .app (hardened runtime, timestamp, the entitlements), create, sign the dmg, notarize, staple the dmg" \
  order '^hdiutil attach .*-nobrowse.* -readonly|^hdiutil attach .*-readonly.*-nobrowse' \
        '^codesign --force --options runtime --timestamp --entitlements [^ ]+ .*Habit\.app' \
        '^hdiutil create' '^codesign .*\.dmg' \
        '^xcrun notarytool submit .*--apple-id '$M1' --team-id '$M2' --password '$M3' --wait --timeout 30m' \
        '^xcrun stapler staple .*\.dmg'
ck "dmg: the identity is the one Developer ID Application from security find-identity" \
  bash -c 'grep -q "^security find-identity -v -p codesigning" "$1" && grep -q "^codesign .*0123456789ABCDEF0123456789ABCDEF01234567" "$1"' _ "$LOG"
ck "dmg: the manifest entry has the new file's sha256 and size and signed true" entry_ok "$W/dmg" Habit_1.0.0_aarch64.dmg true
ck "dmg: the bundle is the new bytes, not the old" bash -c '[ "$(shasum "$1" | cut -d" " -f1)" != "$2" ]' _ "$W/dmg/Habit_1.0.0_aarch64.dmg" "$OLD"
ck "dmg: the output holds no Apple value (no secret echoed)" no grep -qE "$M1|$M2|$M3" <<<"$out"
ck "dmg: a project with no entitlements of its own is signed with the pack's file, minus get-task-allow (final review 1)" \
  granted com.apple.security.network.client '!com.apple.security.get-task-allow'

fixture "$W/zip" flutter habit-1.0.0-macos-arm64.zip
sign --stack flutter --dist "$W/zip" --entitlements "$W/ent.plist"
ck "zip: exits 0" [ "$rc" = 0 ]
ck "zip: extract, sign the .app, zip it, notarize the zip, staple the .app, re-zip" \
  order '^ditto -x -k' '^codesign --force --options runtime --timestamp --entitlements [^ ]+ .*Habit\.app' \
        '^ditto -c -k --sequesterRsrc --keepParent' '^xcrun notarytool submit .*\.zip .*--wait --timeout 30m' \
        '^xcrun stapler staple .*Habit\.app' '^ditto -c -k --sequesterRsrc --keepParent'
ck "zip: stapler never touches the zip" no grep -qE '^xcrun stapler staple .*\.zip' "$LOG"
ck "zip: the manifest entry has the new file's sha256 and size and signed true" entry_ok "$W/zip" habit-1.0.0-macos-arm64.zip true
ck "zip: the output holds no Apple value" no grep -qE "$M1|$M2|$M3" <<<"$out"
# Final review, finding 1 (REQ-352): the signed app keeps the entitlements the project builds with — flutter's
# macos/Runner/Release.entitlements (the sandbox its unsigned build has), tauri's bundle.macOS.entitlements — never the
# pack's fallback in their place, and never the debugger entitlement.
# Covers: REQ-352
mkdir -p "$W/fproj/macos/Runner"
python3 -c 'import plistlib, sys; plistlib.dump({"com.apple.security.app-sandbox": True, "com.apple.security.get-task-allow": True}, open(sys.argv[1], "wb"))' "$W/fproj/macos/Runner/Release.entitlements"
fixture "$W/fzip" flutter habit-1.0.0-macos-arm64.zip
PROJ="$W/fproj" sign --stack flutter --dist "$W/fzip" --entitlements "$W/ent.plist"
ck "flutter: macos/Runner/Release.entitlements signs the .app — app-sandbox granted, get-task-allow dropped, not the pack's keys" \
  bash -c '[ "$1" = 0 ] && granted com.apple.security.app-sandbox "!com.apple.security.get-task-allow" "!com.apple.security.network.client"' _ "$rc"
ck "…and the output names the project's file as the entitlements' source" grep -qF "macos/Runner/Release.entitlements" <<<"$out"
mkdir -p "$W/tproj/src-tauri"
printf '{"bundle": {"macOS": {"entitlements": "./Entitlements.plist"}}}\n' > "$W/tproj/src-tauri/tauri.conf.json"
python3 -c 'import plistlib, sys; plistlib.dump({"com.apple.security.device.camera": True}, open(sys.argv[1], "wb"))' "$W/tproj/src-tauri/Entitlements.plist"
fixture "$W/tdmg" tauri Habit_1.0.0_aarch64.dmg
PROJ="$W/tproj" sign --stack tauri --dist "$W/tdmg" --entitlements "$W/ent.plist"
ck "tauri: tauri.conf.json's bundle.macOS.entitlements (relative to src-tauri/) signs the .app, not the pack's file" \
  bash -c '[ "$1" = 0 ] && granted com.apple.security.device.camera "!com.apple.security.network.client"' _ "$rc"
fixture "$W/tdmg2" tauri Habit_1.0.0_aarch64.dmg
printf '{"bundle": {"macOS": {"entitlements": "Missing.plist"}}}\n' > "$W/tproj/src-tauri/tauri.conf.json"
PROJ="$W/tproj" sign --stack tauri --dist "$W/tdmg2" --entitlements "$W/ent.plist"
ck "tauri: an entitlements file tauri.conf.json names but the tree lacks: exit 2 naming it, nothing signed" \
  bash -c '[ "$1" = 2 ] && grep -qF "Missing.plist" <<<"$2" && ! grep -q "^codesign" "$3"' _ "$rc" "$out" "$LOG"
printf '{"bundle": {"macOS": {"entitlements": "../../ent.plist"}}}\n' > "$W/tproj/src-tauri/tauri.conf.json"
PROJ="$W/tproj" sign --stack tauri --dist "$W/tdmg2" --entitlements "$W/ent.plist"
ck "tauri: an entitlements path outside the project: exit 2, nothing signed" bash -c '[ "$1" = 2 ] && ! grep -q "^codesign" "$2"' _ "$rc" "$LOG"
fixture "$W/fzip2" flutter habit-1.0.0-macos-arm64.zip
printf 'not a plist\n' > "$W/fproj/macos/Runner/Release.entitlements"
PROJ="$W/fproj" sign --stack flutter --dist "$W/fzip2" --entitlements "$W/ent.plist"
ck "flutter: a Release.entitlements that is not a plist dictionary: exit 2, nothing signed" \
  bash -c '[ "$1" = 2 ] && ! grep -q "^codesign" "$2"' _ "$rc" "$LOG"

fixture "$W/bad" tauri Habit_1.0.0_aarch64.dmg
cp "$W/bad/manifest.json" "$W/bad.manifest"; cp "$W/bad/Habit_1.0.0_aarch64.dmg" "$W/bad.dmg"
STUB_NOTARY_FAIL=1 sign --stack tauri --dist "$W/bad" --entitlements "$W/ent.plist"
ck "a failing notarytool exits non-zero naming the step" bash -c '[ "$1" != 0 ] && grep -qi "notariz" <<<"$2"' _ "$rc" "$out"
ck "…leaves the manifest and the bundle unchanged, and staples nothing" \
  bash -c 'cmp -s "$1/manifest.json" "$2" && cmp -s "$1/Habit_1.0.0_aarch64.dmg" "$3" && ! grep -q "stapler" "$4"' _ "$W/bad" "$W/bad.manifest" "$W/bad.dmg" "$LOG"
ck "…and prints no Apple value" no grep -qE "$M1|$M2|$M3" <<<"$out"

fixture "$W/noid" tauri Habit_1.0.0_aarch64.dmg
STUB_NO_IDENTITY=1 sign --stack tauri --dist "$W/noid" --entitlements "$W/ent.plist"
ck "no Developer ID Application identity in the keychain: non-zero, naming it, nothing signed" \
  bash -c '[ "$1" != 0 ] && grep -q "Developer ID Application" <<<"$2" && ! grep -q "^codesign" "$3"' _ "$rc" "$out" "$LOG"
rc=0; out=$(PATH="$W/bin:$PATH" env -u APPLE_APP_PASSWORD APPLE_ID=$M1 APPLE_TEAM_ID=$M2 bash "$SIGN" --stack tauri --dist "$W/noid" --entitlements "$W/ent.plist" 2>&1) || rc=$?
ck "a missing APPLE_APP_PASSWORD exits non-zero, naming the variable" bash -c '[ "$1" != 0 ] && grep -qF APPLE_APP_PASSWORD <<<"$2"' _ "$rc" "$out"
sign --stack python --dist "$W/noid" --entitlements "$W/ent.plist"
ck "a stack that is not tauri or flutter is a usage error (exit 2)" [ "$rc" = 2 ]
sign --stack tauri --dist "$W/noid" --entitlements "$W/missing.plist"
ck "an entitlements file that does not exist is a usage error (exit 2)" [ "$rc" = 2 ]
ck "the script runs under set +x and echoes no APPLE_ value" bash -c 'grep -q "^set +x" "$1" && ! grep -qE "(echo|printf)[^|>]*\$\{?APPLE_" "$1"' _ "$SIGN"
# Build 5 fix wave 1, B (REQ-386; P6 R33): release-sign.sh's hygiene — the one script that holds APPLE_ID, APPLE_TEAM_ID
# and APPLE_APP_PASSWORD.
# Covers: REQ-386
ck "every python3 call runs isolated (python3 -I)" bash -c '! grep -nE "python3( |$)" "$1" | grep -vE "python3 -I( |$)" | grep -vE "^[0-9]+:[[:space:]]*#"' _ "$SIGN"
ck "no Apple value is handed to grep (or any filter) on its argv" no grep -qE 'grep[^#]*\$\{?APPLE_' "$SIGN"
for bad in '../Habit.dmg' 'sub/Habit.dmg' 'Habit dmg.dmg' 'Habit.dmg;x' 'Habit.exe'; do
  fixture "$W/badname" tauri "x.dmg"
  python3 -c 'import json, sys; p = sys.argv[1] + "/manifest.json"; m = json.load(open(p)); m["artifacts"][0]["filename"] = sys.argv[2]; json.dump(m, open(p, "w"))' "$W/badname" "$bad"
  mkdir -p "$(dirname "$W/badname/$bad")"; echo bytes > "$W/badname/$bad"  # the file exists: only the name refuses it
  sign --stack tauri --dist "$W/badname" --entitlements "$W/ent.plist"
  ck "a bundle name '$bad' that is not a plain .dmg/.zip basename: exit 2 before any tool runs" bash -c '[ "$1" = 2 ] && ! grep -qE "^(hdiutil|codesign|ditto|xcrun|security) " "$2"' _ "$rc" "$LOG"
  rm -rf "$W/badname" "$W/Habit.dmg"
done
# The nested code: every Mach-O file and every .framework/.xpc/.app/.dylib inside the app, innermost first, the
# sidecar in Contents/MacOS and the helper in Contents/Helpers included; the main executable is signed with the app,
# never on its own; a resource that is not Mach-O is never signed; the app last, with the entitlements.
nested_ok() {  # nested_ok APPNAME — the codesign --force calls on paths inside APPNAME, from the log
  python3 - "$LOG" "$1" <<'PY'
import re, sys
log, app = sys.argv[1], sys.argv[2]
signed = [l.split()[-1] for l in open(log).read().splitlines() if l.startswith("codesign --force") and ("/" + app) in l]
rel = [s.split("/" + app, 1)[1] for s in signed]
want = {"/Contents/MacOS/habit-sidecar-aarch64-apple-darwin", "/Contents/Frameworks/Foo.framework/Versions/A/Foo",
        "/Contents/Frameworks/Foo.framework", "/Contents/Frameworks/libbar.dylib",
        "/Contents/Helpers/Helper.app/Contents/MacOS/Helper", "/Contents/Helpers/Helper.app", ""}
assert set(rel) == want and len(rel) == len(want), rel
assert rel[-1] == "", "the app is signed last"
for i, r in enumerate(rel):
    for inner in rel[i + 1:]:
        assert not (r and inner.startswith(r + "/")), (inner, "signed after its container", r)
PY
}
export -f nested_ok; export LOG
fixture "$W/nest" tauri Habit_1.0.0_aarch64.dmg
sign --stack tauri --dist "$W/nest" --entitlements "$W/ent.plist"
ck "dmg: every nested Mach-O and bundle is signed innermost first (sidecar, framework, dylib, helper), the main executable and the resource never alone, the app last" \
  bash -c '[ "$1" = 0 ] && nested_ok Habit.app' _ "$rc"
ck "dmg: the nested code is signed with the hardened runtime and a timestamp, without the app's entitlements" \
  bash -c 'grep "^codesign --force" "$1" | grep "Helper.app$" | grep -q -- "--options runtime --timestamp" && ! grep "^codesign --force" "$1" | grep "Helper.app$" | grep -q -- --entitlements' _ "$LOG"
ck "dmg: the signed dmg is re-created from a stage holding the .app and the /Applications symlink (the drag-to-install layout)" \
  grep -qx 'stage: Applications Habit.app applications->/Applications' "$LOG"
fixture "$W/nestz" flutter habit-1.0.0-macos-arm64.zip
sign --stack flutter --dist "$W/nestz" --entitlements "$W/ent.plist"
ck "zip: the same nested signing, innermost first" bash -c '[ "$1" = 0 ] && nested_ok Habit.app' _ "$rc"
ck "zip: both zips are made with ditto -c -k --sequesterRsrc --keepParent, the hook's flags" \
  bash -c '[ "$(grep -c "^ditto -c -k --sequesterRsrc --keepParent " "$1")" = 2 ] && ! grep -qE "^ditto -c -k --keepParent" "$1"' _ "$LOG"
# The keychain: RELEASE_SIGN_KEYCHAIN reaches find-identity and every signing codesign call.
fixture "$W/kc" tauri Habit_1.0.0_aarch64.dmg
RELEASE_SIGN_KEYCHAIN="$W/release-signing.keychain-db" sign --stack tauri --dist "$W/kc" --entitlements "$W/ent.plist"
ck "RELEASE_SIGN_KEYCHAIN: find-identity reads that keychain, and every codesign --force names it with --keychain" \
  bash -c '[ "$1" = 0 ] && grep -q "^security find-identity -v -p codesigning $2$" "$3" && [ "$(grep -c "^codesign --force" "$3")" -ge 8 ] && ! grep "^codesign --force" "$3" | grep -vqF -- "--keychain $2 "' _ "$rc" "$W/release-signing.keychain-db" "$LOG"
# P7 R7 (REQ-352, REQ-386; PR #58 verifier run 2): the app is signed with the entitlements the project committed, never
# with the set the untrusted build embedded; an embedded key the committed file does not grant (or grants another
# value) stops the script before anything is signed, naming the key and the file.
# Covers: REQ-352
# Covers: REQ-386
python3 -c 'import plistlib, sys; sys.stdout.buffer.write(plistlib.dumps({"com.apple.security.app-sandbox": True, "com.apple.security.files.user-selected.read-only": True, "com.apple.security.get-task-allow": True}))' > "$W/app-ent.plist"
fixture "$W/own" flutter habit-1.0.0-macos-arm64.zip
STUB_APP_ENT="$W/app-ent.plist" sign --stack flutter --dist "$W/own" --entitlements "$W/ent.plist"
ck "an embedded key the committed set lacks (the pack's file grants only network.client): exit 1, nothing signed, the keys and the file named" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^codesign --force" "$2" && grep -qF "com.apple.security.app-sandbox" <<<"$3" && grep -qF "com.apple.security.files.user-selected.read-only" <<<"$3" && grep -qF "entitlements.plist" <<<"$3" && ! grep -qF "get-task-allow" <<<"$(grep "does not grant" <<<"$3")"' _ "$rc" "$LOG" "$out"
mkdir -p "$W/fl/macos/Runner"
python3 -c 'import plistlib, sys; plistlib.dump({"com.apple.security.app-sandbox": True, "com.apple.security.files.user-selected.read-only": True, "com.apple.security.network.client": True}, open(sys.argv[1], "wb"))' "$W/fl/macos/Runner/Release.entitlements"
fixture "$W/own2" flutter habit-1.0.0-macos-arm64.zip
PROJ="$W/fl" STUB_APP_ENT="$W/app-ent.plist" sign --stack flutter --dist "$W/own2" --entitlements "$W/ent.plist"
ck "the embedded keys within the committed Release.entitlements: signed with the committed set (network.client too), get-task-allow never" \
  bash -c '[ "$1" = 0 ] && granted com.apple.security.app-sandbox com.apple.security.files.user-selected.read-only com.apple.security.network.client "!com.apple.security.get-task-allow"' _ "$rc"
python3 -c 'import plistlib, sys; sys.stdout.buffer.write(plistlib.dumps({"com.apple.security.app-sandbox": True, "com.apple.security.application-groups": ["X.group"]}))' > "$W/app-ent2.plist"
python3 -c 'import plistlib, sys; plistlib.dump({"com.apple.security.app-sandbox": True, "com.apple.security.application-groups": ["Y.group"]}, open(sys.argv[1], "wb"))' "$W/fl/macos/Runner/Release.entitlements"
fixture "$W/own3" flutter habit-1.0.0-macos-arm64.zip
PROJ="$W/fl" STUB_APP_ENT="$W/app-ent2.plist" sign --stack flutter --dist "$W/own3" --entitlements "$W/ent.plist"
ck "an embedded key with another value than the committed one: exit 1, nothing signed, the key named" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^codesign --force" "$2" && grep -qF "com.apple.security.application-groups" <<<"$3"' _ "$rc" "$LOG" "$out"
ck "the header no longer says the embedded set is signed in; it says the committed set is" \
  bash -c '! grep -qF "the app'"'"'s own — those its unsigned build embedded" "$1" && grep -qF "committed" "$1"' _ "$SIGN"
# notarytool exiting 0 with a status other than Accepted fails: nothing is stapled or rewritten.
fixture "$W/inv" tauri Habit_1.0.0_aarch64.dmg; cp "$W/inv/manifest.json" "$W/inv.manifest"
STUB_NOTARY_STATUS=Invalid sign --stack tauri --dist "$W/inv" --entitlements "$W/ent.plist"
ck "notarytool exit 0 with 'status: Invalid': non-zero, naming the status; nothing stapled, the manifest unchanged" \
  bash -c '[ "$1" != 0 ] && grep -qF "Invalid" <<<"$2" && ! grep -q stapler "$3" && cmp -s "$4/manifest.json" "$5"' _ "$rc" "$out" "$LOG" "$W/inv" "$W/inv.manifest"
finish test_release_sign
