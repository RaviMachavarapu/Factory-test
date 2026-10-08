#!/usr/bin/env bash
# REQ-352 (P6 R18, R22): the tauri and flutter hooks split their parts — RELEASE_PARTS=reproducible writes the source
# archive of the committed tree (no toolchain needed), the bundle part the .dmg or zipped .app (reproducible false,
# signed false until release.yml's sign job) — and their store checklists end with the re-run sentence (REQ-386).
# Covers: REQ-352
# Covers: REQ-386
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
if instance; then echo "SKIP: the app packs live in the template source"; else
  mk() {  # mk DIR — a toolchain-free app tree: the version files the hooks read, scripts/, the notes
    mkdir -p "$1/src-tauri" "$1/docs/releases"; cp -R "$ROOT/scripts" "$1/"
    printf '{"name": "habit", "version": "1.0.0"}\n' > "$1/package.json"; printf '{"version": "1.0.0"}\n' > "$1/src-tauri/tauri.conf.json"
    printf 'name: habit\nversion: 1.0.0+1\n' > "$1/pubspec.yaml"
    printf -- '---\nversion: 1.0.0\ndate: 2026-10-05\n---\n# Notes\n' > "$1/docs/releases/1.0.0-notes.md"
    (cd "$1" && git init -q -b main && git add -A && git commit -qm base)
  }
  for s in tauri flutter; do
    mk "$W/$s"
    rc=0; (cd "$W/$s" && VERSION=1.0.0 DIST_DIR="$W/$s-dist" RELEASE_PARTS=reproducible bash "$ROOT/stacks/$s/release.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: RELEASE_PARTS=reproducible needs no toolchain and writes habit-1.0.0-source.tar, reproducible" \
      bash -c '[ "$1" = 0 ] && python3 -c "import json, sys; d = json.load(open(sys.argv[1])); assert [(a[\"filename\"], a[\"kind\"], a[\"reproducible\"]) for a in d[\"artifacts\"]] == [(\"habit-1.0.0-source.tar\", \"source-archive\", True)], d" "$2/manifest.json"' _ "$rc" "$W/$s-dist"
    last=$(grep -v '^[[:space:]]*$' "$ROOT/stacks/$s/store-checklist.md" | tail -1)
    ck "$s: the checklist's last line is the re-run sentence (REQ-386)" [ "$last" = 'Re-run the tag after adding the secrets and observe `signed: true`.' ]
    ck "$s: the line above it says how — Re-run all jobs within 30 days, or dispatch release.yml on the tag (R34, F10, F31)" \
      bash -c 'p=$(grep -v "^[[:space:]]*$" "$1" | tail -2 | head -1); grep -qF "Re-run all jobs" <<<"$p" && grep -qF "30 days" <<<"$p" && grep -qF "gh workflow run release.yml --ref v<version>" <<<"$p"' _ "$ROOT/stacks/$s/store-checklist.md"
    ck "$s: the checklist names the Apple secrets as environment secrets of release, never repository secrets (R32)" \
      bash -c 'grep -qF "environment secrets" "$1" && grep -qF "\`release\` environment" "$1"' _ "$ROOT/stacks/$s/store-checklist.md"
    ck "$s: the checklist's first item states the Apple Developer Program cost and lead time" \
      bash -c 'grep -E "^1\. " "$1" | grep -qF "US\$99/year" && grep -A1 -E "^1\. " "$1" | grep -qiE "day|week"' _ "$ROOT/stacks/$s/store-checklist.md"
    ck "$s: the checklist names no P6 forward reference" no grep -qw P6 "$ROOT/stacks/$s/store-checklist.md"
  done
  # Build 5 fix wave 1, G (REQ-352; P6 R18): the hooks write every manifest through release_manifest.py write — the
  # bundle part alone too, its epoch and tree unknown (null) — never a schema of their own; the reproducible part is
  # byte-identical across two runs and has release-template.sh's archive form (the same members, modes, mtimes and
  # bytes under its own prefix).
  # Covers: REQ-352
  mkdir -p "$W/hbin"
  printf '#!/usr/bin/env bash\nd="${CARGO_TARGET_DIR:-src-tauri/target}/release/bundle/dmg"; mkdir -p "$d"; echo dmg-bytes > "$d/Habit_1.0.0_aarch64.dmg"\n' > "$W/hbin/npm"
  printf '#!/usr/bin/env bash\nmkdir -p build/macos/Build/Products/Release/habit.app/Contents/MacOS; echo exe > build/macos/Build/Products/Release/habit.app/Contents/MacOS/habit\n' > "$W/hbin/flutter"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nfor a in "$@"; do f="$a"; done; echo zip-bytes > "$f"\n' "$W/ditto.log" > "$W/hbin/ditto"
  chmod +x "$W/hbin"/*
  for s in tauri flutter; do
    ck "$s: the hook writes its manifest through release_manifest.py write, with no schema of its own" \
      bash -c 'grep -qF "release_manifest.py\" write" "$1" && ! grep -qF "specflow-manifest/2" "$1" && ! grep -qF "json.dump" "$1"' _ "$ROOT/stacks/$s/release.sh"
    rc=0; (cd "$W/$s" && VERSION=1.0.0 DIST_DIR="$W/$s-dist2" RELEASE_PARTS=reproducible bash "$ROOT/stacks/$s/release.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: the reproducible part is byte-identical across two runs (the archive and the manifest)" \
      bash -c '[ "$1" = 0 ] && cmp -s "$2/habit-1.0.0-source.tar" "$3/habit-1.0.0-source.tar" && cmp -s "$2/manifest.json" "$3/manifest.json"' _ "$rc" "$W/$s-dist" "$W/$s-dist2"
    rc=0; (cd "$W/$s" && VERSION=1.0.0 DIST_DIR="$W/$s-tdist" bash scripts/release-template.sh) >/dev/null 2>&1 || rc=$?
    ck "$s: …and has release-template.sh's archive form: the same members, modes, mtimes, owners and bytes under each prefix" \
      python3 - "$rc" "$W/$s-dist/habit-1.0.0-source.tar" "$W/$s-tdist/specflow-factory-1.0.0-source.tar" <<'PY'
import sys, tarfile
assert sys.argv[1] == "0", "release-template.sh failed"
def form(p, prefix):
    with tarfile.open(p) as t:
        out = []
        for m in t.getmembers():
            if m.name == "pax_global_header" or m.type == tarfile.XGLTYPE:
                continue
            assert m.name.startswith(prefix) or m.name == prefix.rstrip("/"), m.name
            data = t.extractfile(m).read() if m.isfile() else b""
            out.append((m.name[len(prefix):] if m.name.startswith(prefix) else "", m.mode, m.mtime, m.uid, m.gid, m.uname, m.gname, m.type, data))
        return out
a, b = form(sys.argv[2], "habit-1.0.0/"), form(sys.argv[3], "specflow-factory-1.0.0/")
assert a and a == b, "archive forms differ"
PY
    rm -rf "$W/$s/node_modules"; mkdir -p "$W/$s/node_modules"
    rc=0; (cd "$W/$s" && PATH="$W/hbin:$PATH" VERSION=1.0.0 DIST_DIR="$W/$s-bdist" RELEASE_PARTS=bundle bash "$ROOT/stacks/$s/release.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: the bundle part alone (stub toolchain) — schema 2 through write: one bundle entry, signed false, reproducible false; epoch and tree null" \
      python3 - "$rc" "$W/$s-bdist/manifest.json" "$s" <<'PY'
import hashlib, json, os, sys
assert sys.argv[1] == "0", "the hook failed"
m = json.load(open(sys.argv[2])); s = sys.argv[3]
assert m["schema"] == "specflow-manifest/2" and m["version"] == "1.0.0" and m["stack"] == s, m
assert m["source_date_epoch"] is None and m["tree"] is None and m["signed"] is False, m
(a,) = m["artifacts"]
assert a["kind"] == "bundle" and a["signed"] is False and a["reproducible"] is False, a
assert a["filename"] == ("Habit_1.0.0_aarch64.dmg" if s == "tauri" else "habit-1.0.0-macos-arm64.zip"), a
p = os.path.join(os.path.dirname(sys.argv[2]), a["filename"])
assert a["sha256"] == hashlib.sha256(open(p, "rb").read()).hexdigest() and a["size"] == os.path.getsize(p), a
PY
    rm -rf "$W/$s/node_modules" "$W/$s/build" "$W/$s/src-tauri/target"
  done
  ck "flutter: the bundle is zipped with ditto -c -k --sequesterRsrc --keepParent (the flags release-sign.sh re-zips with)" \
    grep -q -- "^-c -k --sequesterRsrc --keepParent " "$W/ditto.log"
fi
# P6 Task 5.2 (REQ-352, REQ-386, REQ-390; P6 R15, R33, R35): the tauri and flutter release actions — the parts Build 3's
# bundle, sign and verify-signed jobs call: the bundle with the pack's pinned toolchain, the package registries cached
# and nothing else, the hook's bundle part and the 60 s smoke; signing through release-sign.sh (the project's
# entitlements, the pack's file as the fallback); the signed bundle verified with no secret. No expression in a run:
# block, no APPLE_ value echoed.
# Covers: REQ-352
# Covers: REQ-390
if instance; then echo "SKIP: the app packs' release actions live in the template source"; else
  # caches.py ACTION TOOLCHAIN STACK — every cache the action's steps restore, its nested local actions' included (the
  # instance's ./.github/actions/toolchain is the pack's action.yml, given here), must be the stack's package registries:
  # actions/cache paths only, never rust-cache, never a setup-* action's cache: input, never an unresolvable local action.
  cat > "$W/caches.py" <<'PY'
import re, sys
action, toolchain, stack = sys.argv[1:4]
# Build 5 fix wave 1, F (R15): the registries' archives and indexes only, as cargo's own CI guidance caches them —
# never ~/.cargo/registry/src or ~/.cargo/git/checkouts (sources re-extracted from the archives), never ~/.cargo/bin;
# pub's hosted packages and their hashes only — never ~/.pub-cache/bin or global_packages (executables).
want = {"tauri": {"~/.cargo/registry/index", "~/.cargo/registry/cache", "~/.cargo/git/db"},
        "flutter": {"~/.pub-cache/hosted", "~/.pub-cache/hosted-hashes"}}[stack]
local = {"./.github/actions/toolchain": toolchain, "./.github/actions/release": action}
paths, seen, bad = [], set(), []
def walk(f):
    if f in seen:
        return
    seen.add(f)
    for b in re.split(r"(?m)^\s*- (?=\S)", open(f).read()):
        u = re.search(r"(?m)^\s*uses:\s*(\S+)", b)
        if not u:
            continue
        u = u.group(1)
        if u.startswith("./"):
            if u not in local:
                bad.append(f"{f}: an unresolvable local action {u}")
            else:
                walk(local[u])
        elif u.startswith("actions/cache@") or u.startswith("actions/cache/restore@"):
            body = b.split("path:", 1)[1].split("key:", 1)[0]
            first = body.split("\n", 1)[0].strip()
            got = [first] if first and first != "|" else [p.strip() for p in body.split("\n")[1:] if p.strip()]
            paths.extend(got if f == action else [f"{p} (through {f})" for p in got])
        elif "rust-cache@" in u:
            bad.append(f"{f}: rust-cache keeps the target directory")
        elif re.match(r"actions/setup-\w+@", u) and re.search(r"(?m)^\s+cache:", b):
            bad.append(f"{f}: {u} restores a cache")
walk(action)
assert not bad, bad
assert set(paths) == want, paths
PY
  mkdir -p "$W/cfx"
  printf 'runs:\n  using: composite\n  steps:\n    - uses: ./.github/actions/toolchain\n    - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9\n      with:\n        path: ~/.pub-cache\n        key: k\n' > "$W/cfx/action.yml"
  printf 'runs:\n  using: composite\n  steps:\n    - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9\n      with:\n        path: ~/flutter-sdk\n        key: k\n' > "$W/cfx/toolchain.yml"
  ck "the cache check refuses a release action whose nested toolchain action restores an SDK cache (final review 2)" \
    no python3 "$W/caches.py" "$W/cfx/action.yml" "$W/cfx/toolchain.yml" flutter
  printf 'runs:\n  using: composite\n  steps:\n    - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9\n      with:\n        path: ~/.pub-cache\n        key: k\n    - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020\n      with:\n        cache: npm\n' > "$W/cfx/action2.yml"
  ck "…and one whose setup-node restores npm's cache" no python3 "$W/caches.py" "$W/cfx/action2.yml" "$W/cfx/toolchain.yml" flutter
  printf 'runs:\n  using: composite\n  steps:\n    - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9\n      with:\n        path: |\n          ~/.pub-cache/hosted\n          ~/.pub-cache/hosted-hashes\n        key: k\n' > "$W/cfx/action3.yml"
  ck "…and accepts the registry cache alone" python3 "$W/caches.py" "$W/cfx/action3.yml" "$W/cfx/toolchain.yml" flutter
  for s in tauri flutter; do
    A="$ROOT/stacks/$s/release/action.yml"
    ck "$s: release/action.yml is a composite action with the fixed inputs and the three app parts (R35)" python3 - "$A" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
assert re.search(r"(?m)^  using: \"?composite\"?$", t), "composite"
ins = t.split("\ninputs:\n", 1)[1].split("\nruns:\n", 1)[0]
for i in ("part", "version", "tag", "dist", "keychain"):
    assert re.search(rf"(?m)^  {i}:$", ins), i
# Final review, finding 7: release.yml's python jobs pass image/token/source-url/prior/superseded and read the outputs
# prior and superseded through the one ./.github/actions/release; an app action declares them (optional, ignored), and
# dist is not required (prune passes none), so actionlint accepts an app instance's release.yml.
for i in ("image", "token", "source-url", "prior", "superseded"):
    m = re.search(rf"(?m)^  {i}:\n((?:    .*\n)+)", ins)
    assert m and re.search(r"(?m)^    required: false$", m.group(1)), i + " declared, optional"
d = re.search(r"(?m)^  dist:\n((?:    .*\n)+)", ins)
assert d and re.search(r"(?m)^    required: false$", d.group(1)), "dist optional (prune passes none)"
outs = t.split("\noutputs:\n", 1)[1].split("\nruns:\n", 1)[0] if "\noutputs:\n" in t else ""
for o in ("prior", "superseded"):
    assert re.search(rf"(?m)^  {o}:$", outs), "output " + o
assert "requires dist" in t, "a part that needs dist fails at run time without it"
for p in ("bundle", "sign", "verify-signed"):
    assert f"'{p}'" in t, p
assert "unknown part" in t, "an unknown part fails the action"
PY
    ck "$s: the bundle part — the pack's pinned toolchain read with packinfo.py, the hook with RELEASE_PARTS=bundle, release-smoke.sh" \
      bash -c 'grep -qF "packinfo.py --root . get" "$1" && grep -qF "RELEASE_PARTS: bundle" "$1" && grep -qF "release-smoke.sh --stack" "$1"' _ "$A"
    ck "$s: the bundle part restores the package registries only — none through a nested local action, no setup-* cache (R15; final review 2)" \
      python3 "$W/caches.py" "$A" "$ROOT/stacks/$s/action.yml" "$s"
    ck "$s: the sign part runs release-sign.sh with the entitlements beside the action" \
      bash -c 'grep -qF "release-sign.sh --stack" "$1" && grep -qF "GITHUB_ACTION_PATH" "$1" && grep -qF "entitlements.plist" "$1"' _ "$A"
    ck "$s: no echo or printf of an APPLE_ value in the action" no grep -qE '(echo|printf)[^|>]*\$\{?APPLE_' "$A"
    ck "$s: the verify-signed part — codesign --verify --deep --strict, spctl -a -vv, stapler validate, the smoke on the signed bundle (R33)" \
      bash -c 'for w in "codesign --verify --deep --strict" "spctl -a -vv" "stapler validate" "release-smoke.sh"; do grep -qF -- "$w" "$1" || exit 1; done' _ "$A"
    ck "$s: no GitHub expression inside a run: block of the action" python3 - "$A" <<'PY'
import sys
t = open(sys.argv[1]).read().split("\nruns:\n", 1)[1]
for s in t.split("\n    - ")[1:]:
    run = s.split("run: |", 1)[1] if "run: |" in s else ""
    assert "$" + "{{" not in run, s
PY
    ck "$s: release/entitlements.plist is a plist and grants no get-task-allow (a notarized app must not)" \
      bash -c 'python3 -c "import plistlib, sys; d = plistlib.load(open(sys.argv[1], \"rb\")); assert isinstance(d, dict) and \"com.apple.security.get-task-allow\" not in d" "$1"' _ "$ROOT/stacks/$s/release/entitlements.plist"
    own=$([ "$s" = flutter ] && echo "macos/Runner/Release.entitlements" || echo "bundle.macOS.entitlements")
    ck "$s: the pack's entitlements file and the checklist say the project's own $own signs the app, the pack's file only without one (final review 1)" \
      bash -c 'grep -qF "$2" "$1" && grep -qiF "fallback" "$1" && grep -qF "$2" "$3" && grep -qiF "sandbox" "$3"' _ "$ROOT/stacks/$s/release/entitlements.plist" "$own" "$ROOT/stacks/$s/store-checklist.md"
  done
  # P7 R7 (REQ-386): the checklist and the pack's file say the committed set signs the app — tauri.conf.json's
  # bundle.macOS.entitlements, else this fallback — and the embedded set is only compared.
  # Covers: REQ-386
  ck "tauri: the checklist and the pack's entitlements file name the committed set (tauri.conf.json's, then the fallback) and the embedded set as compared, never signed" python3 - \
    "$ROOT/stacks/tauri/store-checklist.md" "$ROOT/stacks/tauri/release/entitlements.plist" <<'PYE'
import sys
for f in sys.argv[1:]:
    t = " ".join(open(f).read().split())
    b, c = t.find("bundle.macOS.entitlements"), t.rfind("fallback")
    assert -1 < b < c and "compare" in t and "already embeds" not in t, (f, b, c)
PYE
  # P7 Build 1 fix wave 1, FIX 7 (REQ-386, REQ-352): both checklists' Entitlements item says what release-sign.sh does
  # with an embedded key the committed set lacks — it stops the signing (exit 1, naming the key) — not only tauri's.
  # Covers: REQ-386
  for s in tauri flutter; do
    # PR #65 verifier run 2, finding 5: release-sign.sh also refuses a key carried with another value (R7).
    ck "$s: the checklist's Entitlements item says an embedded key the committed set lacks, or carries with another value, stops the signing (exit 1)" \
      bash -c 'item=$(awk "/\*\*Entitlements\*\*/{f=1} f&&/^[[:space:]]*$/{exit} f" "$1" | tr -s " \n" "  "); grep -qF "that the committed set lacks, or carries with another value, stops the signing (exit 1, naming the key)" <<<"$item" && grep -qF "by a reviewed PR" <<<"$item"' _ "$ROOT/stacks/$s/store-checklist.md"
  done
  # Final review, finding 5 (REQ-390, R33): the verify-signed step's run: block, extracted from the action and run against
  # stub codesign, spctl, xcrun, hdiutil and ditto: a signed manifest passes through every check in order; a manifest
  # that says unsigned, or a codesign --verify that fails, fails the step.
  # Covers: REQ-390
  mkdir -p "$W/vbin"; VLOG="$W/v.log"
  for t in codesign spctl xcrun; do printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n[ "%s:${STUB_FAIL:-}" != "%s:%s" ]\n' "$t" "$VLOG" "$t" "$t" "$t" > "$W/vbin/$t"; done
  printf '#!/usr/bin/env bash\necho "hdiutil $*" >> "%s"\nif [ "$1" = attach ]; then while [ $# -gt 0 ]; do [ "$1" = -mountpoint ] && m="$2"; shift; done; mkdir -p "$m/Habit.app/Contents"; [ -z "${STUB_TWO_APPS:-}" ] || mkdir -p "$m/Other.app/Contents"; fi\n' "$VLOG" > "$W/vbin/hdiutil"
  printf '#!/usr/bin/env bash\necho "ditto $*" >> "%s"\nif [ "$1" = -x ]; then mkdir -p "$4/Habit.app/Contents"; [ -z "${STUB_TWO_APPS:-}" ] || mkdir -p "$4/Other.app/Contents"; fi\nexit 0\n' "$VLOG" > "$W/vbin/ditto"
  chmod +x "$W/vbin"/*
  vstep() {  # vstep ACTION — the dedented run: block of the step named "Verify the signed bundle"
    python3 - "$1" <<'PY'
import sys
L = open(sys.argv[1]).read().split("\n"); i = L.index("    - name: Verify the signed bundle")
while L[i].strip() != "run: |":
    i += 1
out = []
for l in L[i + 1:]:
    if l.strip() and not l.startswith("        "):
        break
    out.append(l[8:])
print("\n".join(out))
PY
  }
  vdist() {  # vdist DIR FILE SIGNED — a downloaded release-bundle-signed artifact
    mkdir -p "$1"; echo bytes > "$1/$2"
    python3 -c 'import json, sys; s = sys.argv[3] == "true"; json.dump({"artifacts": [{"filename": sys.argv[2], "kind": "bundle", "signed": s}], "signed": s}, open(sys.argv[1] + "/manifest.json", "w"))' "$1" "$2" "$3"
  }
  for s in tauri flutter; do
    vstep "$ROOT/stacks/$s/release/action.yml" > "$W/vs-$s.sh"
    f=$([ "$s" = tauri ] && echo Habit_1.0.0_aarch64.dmg || echo habit-1.0.0-macos-arm64.zip)
    vdist "$W/vd-$s" "$f" true; : > "$VLOG"; rc=0; (PATH="$W/vbin:$PATH" DIST="$W/vd-$s" bash "$W/vs-$s.sh") >/dev/null 2>&1 || rc=$?
    if [ "$s" = tauri ]; then
      ck "tauri: verify-signed, run against stubs: attach the dmg read-only, codesign --verify --deep --strict and spctl on the .app, spctl on the dmg, stapler validate the dmg" \
        bash -c '[ "$1" = 0 ] && python3 - "$2" <<'"'"'PY'"'"'
import re, sys
L = open(sys.argv[1]).read().splitlines(); i = 0
for pat in (r"^hdiutil attach .*-readonly", r"^codesign --verify --deep --strict .*Habit\.app$", r"^spctl -a -vv .*Habit\.app$",
            r"^spctl -a -vv -t open --context context:primary-signature .*\.dmg$", r"^xcrun stapler validate .*\.dmg$"):
    while i < len(L) and not re.search(pat, L[i]):
        i += 1
    assert i < len(L), pat
    i += 1
PY' _ "$rc" "$VLOG"
    else
      ck "flutter: verify-signed, run against stubs: extract the zip, codesign --verify --deep --strict, spctl, stapler validate on the .app" \
        bash -c '[ "$1" = 0 ] && python3 - "$2" <<'"'"'PY'"'"'
import re, sys
L = open(sys.argv[1]).read().splitlines(); i = 0
for pat in (r"^ditto -x -k ", r"^codesign --verify --deep --strict .*Habit\.app$", r"^spctl -a -vv .*Habit\.app$", r"^xcrun stapler validate .*Habit\.app$"):
    while i < len(L) and not re.search(pat, L[i]):
        i += 1
    assert i < len(L), pat
    i += 1
PY' _ "$rc" "$VLOG"
    fi
    vdist "$W/vu-$s" "$f" false; : > "$VLOG"; rc=0; (PATH="$W/vbin:$PATH" DIST="$W/vu-$s" bash "$W/vs-$s.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: verify-signed fails on a manifest that says the bundle is unsigned, before any tool runs" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$VLOG"
    : > "$VLOG"; rc=0; (PATH="$W/vbin:$PATH" STUB_FAIL=codesign DIST="$W/vd-$s" bash "$W/vs-$s.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: verify-signed fails when codesign --verify fails, and stapler never runs" bash -c '[ "$1" != 0 ] && ! grep -q stapler "$2"' _ "$rc" "$VLOG"
    # Build 5 fix wave 1, B (REQ-390; P6 R33): the step's fail-closed guard, executed — exactly one bundle file of the
    # stack's shape in the part and exactly one .app inside it, else it fails before codesign runs; its python3 is -I.
    # Covers: REQ-390
    ext=${f##*.}; cp "$W/vd-$s/$f" "$W/vd-$s/Second.$ext"; : > "$VLOG"; rc=0
    (PATH="$W/vbin:$PATH" DIST="$W/vd-$s" bash "$W/vs-$s.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: verify-signed fails on two .$ext files in the part, before any tool runs" bash -c '[ "$1" != 0 ] && ! grep -qE "^(codesign|spctl|xcrun|hdiutil|ditto) " "$2"' _ "$rc" "$VLOG"
    rm -f "$W/vd-$s/Second.$ext" "$W/vd-$s/$f"; : > "$VLOG"; rc=0
    (PATH="$W/vbin:$PATH" DIST="$W/vd-$s" bash "$W/vs-$s.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: verify-signed fails on no .$ext file in the part, before any tool runs" bash -c '[ "$1" != 0 ] && ! grep -qE "^(codesign|spctl|xcrun|hdiutil|ditto) " "$2"' _ "$rc" "$VLOG"
    echo bytes > "$W/vd-$s/$f"; : > "$VLOG"; rc=0
    (PATH="$W/vbin:$PATH" STUB_TWO_APPS=1 DIST="$W/vd-$s" bash "$W/vs-$s.sh") >/dev/null 2>&1 || rc=$?
    ck "$s: verify-signed fails on two .app bundles inside the .$ext, before codesign runs" bash -c '[ "$1" != 0 ] && ! grep -q "^codesign" "$2"' _ "$rc" "$VLOG"
    ck "$s: verify-signed's python3 runs isolated (-I)" bash -c 'grep -q "python3 -I - " "$1" && ! grep -qE "python3 - " "$1"' _ "$W/vs-$s.sh"
  done
  D3="$W/tinst"; copy_template "$D3"
  ck "init (tauri, scaffold-free) installs the tauri release action and its entitlements as .github/actions/release/ (Build 3's copy)" \
    bash -c "cd '$D3' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name App --profile engineer --stack tauri </dev/null >/dev/null 2>&1 && test -f .github/actions/release/action.yml && test -f .github/actions/release/entitlements.plist"
  # Final review, finding 7 (REQ-390, R35): with the app action installed, actionlint resolves ./.github/actions/release
  # and checks every call release.yml makes — the python jobs' inputs and outputs included — in a tauri and a flutter
  # instance (actionlint is not installed in CI; where it is absent the check says so).
  # Covers: REQ-390
  D4="$W/finst"; copy_template "$D4"
  (cd "$D4" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name App --profile engineer --stack flutter </dev/null >/dev/null 2>&1) || true
  if command -v actionlint >/dev/null 2>&1; then
    for d in "$D3" "$D4"; do
      ck "$(basename "$d"): actionlint accepts the instance's workflows against its installed release action" \
        bash -c 'cd "$1" && test -f .github/actions/release/action.yml && actionlint .github/workflows/*.yml' _ "$d"
    done
  else
    echo "SKIP: actionlint is not on PATH; the instance release.yml lint runs where it is"
  fi
fi
# P6 Task 5.3 (REQ-386, REQ-303; P6 R23): each app pack's tester instructions say exactly how to open an unsigned app on
# macOS 15 and on macOS 14 and earlier, and init installs them where /release reads them.
# Covers: REQ-386
# Covers: REQ-303
if instance; then echo "SKIP: the app packs' tester instructions live in the template source"; else
  for s in tauri flutter; do
    ck "$s: tester-instructions.md names macOS 15's Open Anyway, the Control-click path, xattr, and the <version> and <app> tokens" \
      bash -c 'grep -qF "Open Anyway" "$1" && grep -qiF "control-click" "$1" && grep -qF "xattr -dr com.apple.quarantine" "$1" && grep -qF "<version>" "$1" && grep -qF "<app>" "$1"' _ "$ROOT/stacks/$s/tester-instructions.md"
    # Final review, finding 4 (REQ-386; R18, R26): the notes transcribe only the reproducible subset, so the bundle's
    # SHA-256 is in the Release's attached manifest.json — the text says so, gives the command, and says how to install.
    inst=$([ "$s" = tauri ] && echo "drag" || echo "double-click the .zip")
    ck "$s: the tester instructions check the download against the attached manifest.json with shasum -a 256, never 'the release notes', then say how to install ($inst)" \
      bash -c 't=$(tr "\n" " " < "$1"); grep -qF "manifest.json" <<<"$t" && grep -qF "shasum -a 256" <<<"$t" && ! grep -qiE "checksum in the release notes|in the release notes" <<<"$t" && ! grep -qF "the a " <<<"$t" && grep -qiF "Applications" <<<"$t" && grep -qiF "$2" <<<"$t"' _ "$ROOT/stacks/$s/tester-instructions.md" "$inst"
  done
  ck "init (tauri) installs docs/releases/tester-instructions.md beside the store checklist (Build 3's *.md copy)" \
    bash -c 'cmp -s "$1/stacks/tauri/tester-instructions.md" "$2/docs/releases/tester-instructions.md" && test -f "$2/docs/releases/store-checklist.md"' _ "$ROOT" "$W/tinst"
fi
# P6 Task 5.7 (REQ-352, REQ-386; P6 R29, R32, R33, R35): the threat model's two app residuals, appended after its last
# residual (Build 5's region), and the spec entry's Build 5 sentence — pinned here, not in test_threat_model_current.sh or
# test_spec_lifecycle.sh, so Build 4 (in parallel) shares no test line.
# Covers: REQ-352
TM="$ROOT/docs/architecture/2026-09-25-factory-v3-2-threat-model.md"; SP="$ROOT/docs/specs/2026-09-25-factory-v3-2-design.md"
factory_doc_ck "the threat model ends with the app residuals: the release environment, the bundle's registry caches, then the stub-only signed path (R35)" "$TM" python3 - "$TM" <<'PY'
import sys
L = [l for l in open(sys.argv[1]).read().splitlines() if l.startswith("- **")]
assert "The Apple secrets need the `release` environment" in L[-3] and "GitHub Free" in L[-3], L[-3]
# Build 5 fix wave 1, B (REQ-386; P6 R33): the app-specific password on notarytool's argv is recorded as the
# ephemeral-runner residual, beside the environment it comes from.
assert "notarytool" in L[-3] and "argv" in L[-3] and "single-use GitHub-hosted runner" in L[-3], L[-3]
# Build 5 re-review, finding 3: release.yml's sign-job keychain step passes the certificate's password on argv too
# (`security import … -P`) — the same ephemeral-runner exposure, both secrets recorded in one sentence.
assert "`security import`" in L[-3] and "`-P`" in L[-3] and "`APPLE_CERTIFICATE_PASSWORD`" in L[-3], L[-3]
assert "both secrets" in L[-3], L[-3]
assert "The signed path is exercised only by stubs until an instance ships" in L[-1], L[-1]
# Final review, finding 5: release-sign.sh and the verify-signed step run against stub tools; actionlint lints the
# action's wiring only inside a scaffolded instance — never "proved against stub tools and actionlint".
assert "proved against stub tools and actionlint" not in L[-1], L[-1]
for w in ("`release-sign.sh`", "`verify-signed`", "stub", "scaffolded instance"):
    assert w in L[-1], w
# Final review, finding 2: the bundle part's registry caches, recorded against release.yml's "no job restores a cache".
assert "package registries" in L[-2] and "no job restores a cache" in L[-2], L[-2]
assert "The test-first policy is read at the base ref" in L[-4], L[-4]
PY
# Build 5 wave 1 round 2 (REQ-352, REQ-386; P6 R15, R35): the governing plan says what ships — R15's Caches sentence and
# Task 5.2's Interfaces bundle clause: the pack's pinned toolchain set up by the part itself (no toolchain action, no
# rust_cache input), the registry archives, indexes and hashes only; Task 5.2's test sketch marked superseded by caches.py.
# Build 5 re-review, finding 1: the Interfaces paragraph "The release action" is held to the same asserts.
# Covers: REQ-352
P6P="$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
factory_doc_ck "the P6 plan's R15 Caches sentence, Task 5.2's bundle clause and the release action paragraph say what ships (final review 2, fix wave 1 F, re-review 1)" "$P6P" python3 - "$P6P" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
r15 = next(l for l in t.splitlines() if l.startswith("- **R15 "))
c = r15.split("**Caches:**", 1)[1].split("**", 1)[0]
i = t.split("### Task 5.2:", 1)[1].split("### Task 5.3", 1)[0]
b = i.split("**Interfaces:**", 1)[1].split("**`sign`**", 1)[0]
# Build 5 re-review, finding 1: the Interfaces paragraph "The release action" says the same as R15 and Task 5.2.
ra = next(l for l in t.splitlines() if l.startswith("**The release action** "))
ra = ra.split("tauri's and flutter's `bundle`", 1)[1].split("`sign` runs", 1)[0]
for s, name in ((c, "R15"), (b, "Task 5.2 Interfaces"), (ra, "The release action")):
    assert "rust_cache" not in s and "./.github/actions/toolchain" not in s, name + ": the toolchain action"
    assert "calls the toolchain action" not in s and "runs the toolchain action" not in s, name
    for w in ("pinned toolchain", "final review, finding 2", "`~/.cargo/registry/index`", "`~/.cargo/registry/cache`",
              "`~/.cargo/git/db`", "`~/.pub-cache/hosted`", "`~/.pub-cache/hosted-hashes`"):
        assert w in s, (name, w)
    assert not re.search(r"`~/\.cargo/registry`|`~/\.cargo/git`|`~/\.pub-cache`", s), name + ": the old cache set"
assert "superseded by `test_release_apps.sh`'s `caches.py`" in i, "the Task 5.2 test sketch is marked superseded"
PY
a6=$(awk '/^---$/{n++; next} n==1' "$SP" 2>/dev/null | grep -F 'P6 builds (lanes' || true)
factory_doc_ck "the spec's P6 builds entry carries Build 5's sentence (R22, R23, R13, R32, R33, R34, R4)" "$SP" \
  bash -c 'for w in "Build 5 (app stacks;" "store-checklist" "signing:" "R13" "R32" "R33" "R34" "follow-on design lane"; do grep -qF -- "$w" <<<"$1" || exit 1; done' _ "$a6"
# The second-to-merge fold's re-review, finding 1 (REQ-352; P6 R35, art-specification-primacy): the fold Build 5 made
# after Build 4's merge edits test_spec_lifecycle.sh and test_threat_model_current.sh and rewrites Build 3's and Build
# 4's residual sign-offs. A third footnote at R35's anchor sanctions it, and the three scope sentences that said Build 5
# never edits those tests (Build 4's fold bullet, "otherwise only run", Task 5.7's and Task 4.4's "Not edited here") name
# the exception (the rebase re-review); Build 5's Files name the fence entry (Task 5.5) and the manifest helper (Task 5.7).
# Covers: REQ-352
factory_doc_ck "the P6 plan sanctions the second-to-merge fold's edits (test_spec_lifecycle.sh, test_threat_model_current.sh, the Build 3 and 4 sign-offs) and its scope sentences name the exception" "$P6P" python3 - "$P6P" <<'PY'
import sys
L = open(sys.argv[1]).read().splitlines()
K = "*Sanctioned for the second-to-merge fold"
i = next(n for n, l in enumerate(L) if l.startswith(K))
o = next(n for n, l in enumerate(L) if l.startswith("*Outside Build 5's column, sanctioned for its fix wave 1"))
p = next(n for n, l in enumerate(L) if l.startswith("The intersection is `README.md`"))
assert o < i < p, "the footnote sits at R35's anchor, after Build 5's fix-wave-1 footnote"
f = L[i]
for w in ("`42990d0`", "`tests/governance/test_spec_lifecycle.sh`", "`tests/governance/test_threat_model_current.sh`",
          "the interim window's closure", "REQ-351's rollback reading", "PR #57's and PR #58's verifier run 1",
          "`sign-off: PR #56's merge (Build 3`", "`sign-off: PR #57's merge (Build 4`", "three existing sign-off pins",
          "ended with Build 4's merge", "Step 4 name-only check"):
    assert w in f, ("footnote", w)
assert "except Build 5's second-to-merge fold, which edits the last two (the footnote above)" in L[p] and L[p].rstrip().endswith("are otherwise only run."), "the intersection paragraph"
b4 = next(l for l in L if l.startswith("  - **Build 4 also carries PR #56's verifier run-1 fold"))
assert "Build 5 edits none of these, except as the second to merge: " in b4 and K in b4, "Build 4's fold bullet"
t57 = L[next(n for n, l in enumerate(L) if l.startswith("### Task 5.7")):]
ne = next(l for l in t57 if l.startswith("**Not edited here (R35):** `test_spec_lifecycle.sh`"))
assert "until Build 4 has merged" in ne and K in ne, "Task 5.7's Not edited here"
t44 = L[next(n for n, l in enumerate(L) if l.startswith("### Task 4.4")):]
n44 = next(l for l in t44 if l.startswith("**Not edited here (R35):** `test_threat_model_current.sh`"))
assert "until Build 4 has merged" in n44 and K in n44 and "dfe-12's Boundary-residual" in n44, "Task 4.4's Not edited here"
f55 = next(l for l in L[next(n for n, l in enumerate(L) if l.startswith("### Task 5.5")):] if l.startswith("**Files:**"))
assert "`scripts/factory-only.txt`" in f55 and "`tests/unit/test_render_dashboard.py`" in f55, "Task 5.5's Files: the fence entry"
f57 = next(l for l in t57 if l.startswith("**Files:**"))
assert "`tests/governance/lib/first_run_manifest.py`" in f57 and "`tests/governance/test_first_run_manifest.sh`" in f57, "Task 5.7's Files: the manifest helper"
PY
# P7 (REQ-352; PR #58 verifier run 2): the flutter checklist never tells anyone to staple a zip.
# Covers: REQ-352
if instance; then echo "SKIP: the flutter pack's checklist lives in the template source"; else
ck "flutter checklist: staple the .app and re-zip it; a zip cannot be stapled" \
  bash -c 't=$(tr "\n" " " < "$1" | tr -s " "); ! grep -qF "(or the zip" <<<"$t" && grep -qF "a zip cannot be stapled" <<<"$t" && grep -qF "\`xcrun stapler staple\` on the \`.app\`" <<<"$t"' _ "$ROOT/stacks/flutter/store-checklist.md"
fi
finish test_release_apps
