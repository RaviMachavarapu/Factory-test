#!/usr/bin/env bash
# REQ-352, REQ-305: test_first_run.sh's manifest helper (tests/governance/lib/first_run_manifest.py) on scratch manifests
# of both schemas. The app hooks write schema 2 through release_manifest.py write (one bundle entry, and under the
# default RELEASE_PARTS=all the source archive too); the schema-1 shape ({version, artifacts: [{filename, sha256, size}]})
# is still read. The first-run cases are opt-in and macOS-only, so the helper's rule is pinned here, in the default gates
# (the regression: every app first-run job failed on a schema-2 manifest with two entries).
# Covers: REQ-352
# Covers: REQ-305
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
H="$ROOT/tests/governance/lib/first_run_manifest.py"
RM="$ROOT/scripts/lib/specflow/release_manifest.py"
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT
mk() {  # mk DIR FILE... — each FILE with distinct content
  mkdir -p "$1"; local d="$1"; shift
  for f in "$@"; do printf 'content of %s\n' "$f" > "$d/$f"; done
}
v1() {  # v1 DIR VERSION FILE... — a schema-1 manifest of the files
  python3 - "$@" <<'PY'
import hashlib, json, os, sys
d, v, *fs = sys.argv[1:]
arts = [{"filename": f, "sha256": hashlib.sha256(open(os.path.join(d, f), "rb").read()).hexdigest(),
         "size": os.path.getsize(os.path.join(d, f))} for f in fs]
json.dump({"version": v, "artifacts": arts}, open(os.path.join(d, "manifest.json"), "w"))
PY
}
TREE=0123456789abcdef0123456789abcdef01234567
# schema 1
D="$WORK/s1"; mk "$D" app.dmg; v1 "$D" 0.1.0 app.dmg
ck "schema 1: one .dmg whose sha256 and size verify is accepted" python3 "$H" "$D" 0.1.0 .dmg
ck "schema 1: the wrong version is refused" no python3 "$H" "$D" 0.2.0 .dmg
ck "schema 1: the wrong suffix is refused" no python3 "$H" "$D" 0.1.0 .zip
D="$WORK/s1-bad"; mk "$D" app.dmg; v1 "$D" 0.1.0 app.dmg; echo tampered >> "$D/app.dmg"
ck "schema 1: a file that no longer hashes to its entry is refused" no python3 "$H" "$D" 0.1.0 .dmg
D="$WORK/s1-two"; mk "$D" app.dmg b.dmg; v1 "$D" 0.1.0 app.dmg b.dmg
ck "schema 1: two artifacts are refused" no python3 "$H" "$D" 0.1.0 .dmg
# schema 2, RELEASE_PARTS=all (the hooks' default): the source archive and the bundle
D="$WORK/s2"; mk "$D" acme-0.1.0-source.tar Acme_0.1.0_aarch64.dmg
python3 "$RM" write --dist "$D" --version 0.1.0 --stack tauri --epoch 1791158400 --tree "$TREE" \
  --artifact acme-0.1.0-source.tar source-archive 1 --artifact Acme_0.1.0_aarch64.dmg bundle 0 >/dev/null
ck "schema 2 (all): the source archive and one .dmg bundle, each verifying, are accepted" python3 "$H" "$D" 0.1.0 .dmg
ck "schema 2 (all): the default parts are all" python3 "$H" "$D" 0.1.0 .dmg all
ck "schema 2 (all): the wrong suffix is refused" no python3 "$H" "$D" 0.1.0 .zip
ck "schema 2 (all): the wrong version is refused" no python3 "$H" "$D" 0.2.0 .dmg
ck "schema 2 (all): RELEASE_PARTS=bundle refuses the extra source archive" no python3 "$H" "$D" 0.1.0 .dmg bundle
cp -R "$D" "$WORK/s2-src"; echo tampered >> "$WORK/s2-src/acme-0.1.0-source.tar"
ck "schema 2 (all): a source archive that no longer hashes to its entry is refused" no python3 "$H" "$WORK/s2-src" 0.1.0 .dmg
cp -R "$D" "$WORK/s2-dmg"; echo tampered >> "$WORK/s2-dmg/Acme_0.1.0_aarch64.dmg"
ck "schema 2 (all): a bundle that no longer hashes to its entry is refused" no python3 "$H" "$WORK/s2-dmg" 0.1.0 .dmg
cp -R "$D" "$WORK/s2-sig"; python3 -c 'import json, sys; p = sys.argv[1]; m = json.load(open(p)); m["signed"] = True; json.dump(m, open(p, "w"))' "$WORK/s2-sig/manifest.json"
ck "schema 2 (all): a top-level signed that is not the bundle's is refused" no python3 "$H" "$WORK/s2-sig" 0.1.0 .dmg
D="$WORK/s2-nosrc"; mk "$D" Acme_0.1.0_aarch64.dmg
python3 "$RM" write --dist "$D" --version 0.1.0 --stack tauri --epoch 1791158400 --tree "$TREE" --artifact Acme_0.1.0_aarch64.dmg bundle 0 >/dev/null
ck "schema 2 (all): a manifest without the source archive is refused" no python3 "$H" "$D" 0.1.0 .dmg
D="$WORK/s2-noepoch"; mk "$D" acme-0.1.0-source.tar Acme_0.1.0_aarch64.dmg
python3 "$RM" write --dist "$D" --version 0.1.0 --stack tauri --artifact acme-0.1.0-source.tar source-archive 1 --artifact Acme_0.1.0_aarch64.dmg bundle 0 >/dev/null
ck "schema 2 (all): the source part without its epoch and tree is refused" no python3 "$H" "$D" 0.1.0 .dmg
D="$WORK/s2-two"; mk "$D" acme-0.1.0-source.tar a.zip b.zip
python3 "$RM" write --dist "$D" --version 0.1.0 --stack flutter --epoch 1791158400 --tree "$TREE" \
  --artifact acme-0.1.0-source.tar source-archive 1 --artifact a.zip bundle 0 --artifact b.zip bundle 0 >/dev/null
ck "schema 2 (all): two bundle entries are refused" no python3 "$H" "$D" 0.1.0 .zip
# schema 2, RELEASE_PARTS=bundle: the bundle alone, epoch and tree null
D="$WORK/s2-bundle"; mk "$D" acme_notes-0.1.0-macos.zip
python3 "$RM" write --dist "$D" --version 0.1.0 --stack flutter --artifact acme_notes-0.1.0-macos.zip bundle 0 >/dev/null
ck "schema 2 (bundle): the one .zip bundle is accepted" python3 "$H" "$D" 0.1.0 .zip bundle
ck "schema 2 (bundle): RELEASE_PARTS=all refuses it (no source archive)" no python3 "$H" "$D" 0.1.0 .zip all
ck "an unknown parts value is refused" no python3 "$H" "$D" 0.1.0 .zip everything
ck "test_first_run.sh's manifest helper calls this checker" grep -q 'tests/governance/lib/first_run_manifest.py' "$ROOT/tests/governance/test_first_run.sh"
finish test_first_run_manifest
