#!/usr/bin/env bash
# REQ-384 (P6 R2, R18): the template source's release stack is `template` — scripts/template-pack.yml says so and
# packinfo.py prints it, never through a .specflow.yml — and scripts/release-template.sh writes one reproducible artifact:
# the uncompressed source archive of HEAD's tree, without docs/releases/ and docs/security/, every mtime the notes' date:,
# so the ship PR's head and the commit main gets give the same bytes. REQ-303: the pack metadata. REQ-306: an instance
# holds no release-template.sh and resolves its own stack.
# Covers: REQ-384
# Covers: REQ-303
# Covers: REQ-306
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
P="$ROOT/scripts/lib/specflow/packinfo.py"
if ! instance; then
  ck "scripts/template-pack.yml: stack: template" grep -qx 'stack: template' "$ROOT/scripts/template-pack.yml"
  ck "packinfo.py --root <template source> stack → template" [ "$(python3 "$P" --root "$ROOT" stack)" = template ]
  ck "packinfo.py --root <template source> get python_version prints scripts/template-pack.yml's value (P6 Task 2.4, F36)" \
    bash -c 'want=$(python3 "$2" --file "$3/scripts/template-pack.yml" get python_version); [ -n "$want" ] && [ "$(python3 "$1" --root "$3" get python_version)" = "$want" ]' _ "$P" "$ROOT/scripts/lib/specflow/config.py" "$ROOT"
  ck "config.py still refuses stack: template in a .specflow.yml (the template never becomes an instance)" \
    bash -c 'printf "stack: template\n" > "$1/c.yml"; ! python3 "$2" --file "$1/c.yml" validate 2>/dev/null' _ "$W" "$ROOT/scripts/lib/specflow/config.py"
fi
if instance; then
  echo "SKIP: scripts/release-template.sh and scripts/template-pack.yml live in the template source (init removes both)"
else
R="$W/r"; mkdir -p "$R"
(cd "$R" && git init -q -b main && cp -R "$ROOT/scripts" . && find scripts -name __pycache__ -prune -exec rm -rf {} + \
  && cp "$ROOT/scripts/template-pack.yml" scripts/template-pack.yml && mkdir -p docs/releases docs/security \
  && printf -- '---\nversion: 1.0.0\ndate: 2026-10-05\n---\n# Notes\n' > docs/releases/1.0.0-notes.md && echo r > docs/security/1.0.0-review.md \
  && git add -A && git commit -qm base)
rel() { rm -rf "$W/dist"; (cd "$R" && VERSION=1.0.0 DIST_DIR="$W/dist" RELEASE_PARTS="${1:-all}" bash scripts/release-template.sh) >/dev/null 2>&1; }
sha() { shasum -a 256 "$W/dist/specflow-factory-1.0.0-source.tar" | cut -d' ' -f1; }
rel; A="$W/dist/specflow-factory-1.0.0-source.tar"
ck "release-template.sh: one reproducible source archive and a schema-2 manifest, stack template, signed null" python3 - "$W/dist/manifest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "specflow-manifest/2" and d["stack"] == "template" and d["signed"] is None, d
assert [(a["filename"], a["kind"], a["reproducible"]) for a in d["artifacts"]] == [("specflow-factory-1.0.0-source.tar", "source-archive", True)], d
PY
tar -tf "$A" > "$W/list"
ck "the archive holds HEAD's tree under specflow-factory-1.0.0/, without docs/releases/ or docs/security/" \
  bash -c 'grep -qx "specflow-factory-1.0.0/scripts/release-template.sh" "$1" && ! grep -q "/docs/releases/" "$1" && ! grep -q "/docs/security/" "$1"' _ "$W/list"
ck "…every member's mtime is the notes' date (2026-10-05 00:00 UTC)" python3 - "$A" <<'PY'
import sys, tarfile
assert {m.mtime for m in tarfile.open(sys.argv[1]).getmembers()} == {1791158400}
PY
S1=$(sha)
ck "…every member's mode is 0644 or 0755 (R18: tar.umask pinned)" python3 - "$A" <<'PY'
import sys, tarfile
assert {m.mode for m in tarfile.open(sys.argv[1]).getmembers()} <= {0o644, 0o755}
PY
(cd "$R" && git config tar.umask 0002 && git config core.autocrlf true); rel
ck "a machine's tar.umask 0002 and core.autocrlf true change no byte: the hook pins both (R18)" [ "$(sha)" = "$S1" ]
(cd "$R" && git config --unset tar.umask && git config --unset core.autocrlf)
(cd "$R" && echo stray > scripts/zz-uncommitted.sh); rel; rm "$R/scripts/zz-uncommitted.sh"
ck "the working tree is never archived: an uncommitted file changes nothing" [ "$(sha)" = "$S1" ]
(cd "$R" && printf '| `x` | `%s` | 1 |\n' "$S1" >> docs/releases/1.0.0-notes.md && echo r2 >> docs/security/1.0.0-review.md && git commit -qam "transcribe the rows"); rel
ck "a ship-PR commit touching only docs/releases/ and docs/security/ leaves the bytes unchanged (no fixpoint, R18 (i))" [ "$(sha)" = "$S1" ]
(cd "$R" && git checkout -q -b squash && git reset -q --soft main~1 && git commit -qm "squash: the same tree, another commit"); rel
ck "another commit with the same tree — a squash merge's — gives the same bytes (R18 (ii), (iii))" [ "$(sha)" = "$S1" ]
rel; ck "building twice from the same commit gives identical bytes (sha256)" [ "$(sha)" = "$S1" ]
git clone -q "$R" "$W/another-dir-name"; rm -rf "$W/dist"; (cd "$W/another-dir-name" && VERSION=1.0.0 DIST_DIR="$W/dist" bash scripts/release-template.sh) >/dev/null 2>&1
ck "a clone under another directory name gives the same bytes: the template's archive is named specflow-factory, never the directory (REQ-384)" [ "$(sha)" = "$S1" ]
(cd "$R" && git checkout -q main && echo "# a change" >> scripts/release-template.sh && git commit -qam "a source change"); rel
ck "…while a change to an archived path changes them" [ "$(sha)" != "$S1" ]
(cd "$R" && git rm -q docs/releases/1.0.0-notes.md && git commit -qm "no notes")
rc=0; (cd "$R" && VERSION=1.0.0 DIST_DIR="$W/d2" bash scripts/release-template.sh) >/dev/null 2>&1 || rc=$?
ck "no docs/releases/1.0.0-notes.md and no SOURCE_DATE_EPOCH: exit 2" [ "$rc" = 2 ]
rc=0; (cd "$R" && SOURCE_DATE_EPOCH=1791158400 VERSION=1.0.0 DIST_DIR="$W/d2" bash scripts/release-template.sh) >/dev/null 2>&1 || rc=$?
ck "…with SOURCE_DATE_EPOCH set (a dry run): exit 0" [ "$rc" = 0 ]
# Fix wave 1 (REQ-384): a RELEASE_COMMIT that names no commit here says so (exit 2), never "no notes".
# Covers: REQ-384
for e in "" "SOURCE_DATE_EPOCH=1791158400"; do
  rc=0; o=$(cd "$R" && env $e RELEASE_COMMIT=0123456789abcdef0123456789abcdef01234567 VERSION=1.0.0 DIST_DIR="$W/d3" bash scripts/release-template.sh 2>&1) || rc=$?
  ck "RELEASE_COMMIT naming no commit${e:+ ($e)}: exit 2, saying it is not a commit in this repository" \
    bash -c '[ "$1" = 2 ] && grep -qF "RELEASE_COMMIT 0123456789abcdef0123456789abcdef01234567 is not a commit in this repository (SPECFLOW_HEAD_SHA set wrongly?)" <<<"$2" && ! grep -qF "no docs/releases" <<<"$2"' _ "$rc" "$o"
done
fi
if ! instance; then
  D="$W/inst"; copy_template "$D"
  ck "init (scaffold-free) exits 0" bash -c "cd '$D' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Rel --profile engineer --stack python </dev/null >/dev/null 2>&1"
  ck "an instance holds no scripts/release-template.sh (REQ-306) and has its stack's hook" \
    bash -c '[ ! -e "$1/scripts/release-template.sh" ] && [ -x "$1/scripts/release-python.sh" ]' _ "$D"
  ck "packinfo.py --root <instance> stack → python (.specflow/pack.yml)" [ "$(python3 "$D/scripts/lib/specflow/packinfo.py" --root "$D" stack)" = python ]
  ck "this test passes inside that instance — its template-only checks SKIP there (F3, F16; the P5 regression)" \
    bash -c 'cd "$1" && bash tests/governance/test_release_template.sh >/dev/null 2>&1' _ "$D"
fi
# PR #54 verifier run 2, code-mode low (REQ-384; P6 R18): the stub hook names the archive and its in-tar prefix after the
# repository — remote.origin.url's last path component without .git — never the checkout directory, so a laptop clone
# under another directory name gives CI's bytes (CI checks out into a directory named after the repository); with no
# origin the directory name is the fallback.
# Covers: REQ-384
if [ -f "$ROOT/scripts/release-stack.sh.template" ]; then
  O="$W/named"; mkdir -p "$O/src"
  (cd "$O/src" && git init -q -b main && cp "$ROOT/scripts/release-stack.sh.template" hook.sh && mkdir -p scripts && cp -R "$ROOT/scripts/lib" scripts/ \
    && find scripts -name __pycache__ -prune -exec rm -rf {} + && git add -A && git commit -qm base)
  git clone -q --bare "$O/src" "$O/acme-app.git"; git clone -q "$O/acme-app.git" "$O/acme-app"; git clone -q "$O/acme-app.git" "$O/laptop-copy"
  git -C "$O/laptop-copy" remote set-url origin git@github.com:o/acme-app.git
  stub() { rm -rf "$O/d-$1"; (cd "$O/$1" && SOURCE_DATE_EPOCH=1791158400 VERSION=1.0.0 DIST_DIR="$O/d-$1" bash hook.sh >/dev/null 2>&1) || true
    ls "$O/d-$1" 2>/dev/null | grep -- '-source\.tar$' || true; }
  n1=$(stub acme-app); n2=$(stub laptop-copy); n3=$(stub src)
  ck "the stub hook names the archive after origin's repository: acme-app-1.0.0-source.tar in ./acme-app and in ./laptop-copy (scp-style origin)" \
    bash -c '[ "$1" = acme-app-1.0.0-source.tar ] && [ "$2" = acme-app-1.0.0-source.tar ]' _ "$n1" "$n2"
  ck "…the two clones' archives are byte-identical, the in-tar prefix acme-app-1.0.0/" \
    bash -c 'cmp -s "$1" "$2" && tar -tf "$2" | head -1 | grep -q "^acme-app-1.0.0/"' _ "$O/d-acme-app/acme-app-1.0.0-source.tar" "$O/d-laptop-copy/acme-app-1.0.0-source.tar"
  ck "…with no origin the checkout directory's name is the fallback (src-1.0.0-source.tar)" [ "$n3" = src-1.0.0-source.tar ]
fi
# Build 2 final review (REQ-384, REQ-303; P6 R2): with --ref <base>, packinfo.py reads instance-ness and the pack at
# that ref, as load_at_ref does for the test-first policy, so a branch that adds or deletes .specflow.yml or .stack cannot
# swap which release hook runs; without --ref it reads the checkout. An unresolvable ref fails (exit 2).
# Covers: REQ-384
# Covers: REQ-303
K="$W/pk"; mkdir -p "$K/scripts"
(cd "$K" && git init -q -b main && printf 'stack: template\npython_version: "3.12"\n' > scripts/template-pack.yml && git add -A && git commit -qm base \
  && git checkout -qb ship/1.0.0 && printf 'stack: tauri\n' > .specflow.yml && printf 'stack: flutter\npython_version: "3.11"\n' > scripts/template-pack.yml \
  && git add -A && git commit -qm "a marker and a pack edit")
ck "packinfo.py --ref main stack: the template source at the base, though the head adds .specflow.yml → template" [ "$(python3 "$P" --root "$K" --ref main stack)" = template ]
ck "…without --ref the checkout is read (the head's .specflow.yml → tauri)" [ "$(python3 "$P" --root "$K" stack)" = tauri ]
ck "packinfo.py --ref main get python_version reads the base's pack, not the head's edit" [ "$(python3 "$P" --root "$K" --ref main get python_version)" = 3.12 ]
I="$W/pi"; mkdir -p "$I/.specflow"
(cd "$I" && git init -q -b main && printf 'stack: python\n' > .specflow.yml && printf 'stack: python\npython_version: "3.12"\n' > .specflow/pack.yml \
  && git add -A && git commit -qm base && git checkout -qb ship/1.0.0 && git rm -q .specflow.yml && git commit -qm "drop the marker")
ck "packinfo.py --ref main stack: an instance at the base whose head deletes .specflow.yml → python (.specflow/pack.yml at the base)" \
  [ "$(python3 "$P" --root "$I" --ref main stack)" = python ]
(cd "$I" && git checkout -q main && git rm -q .specflow/pack.yml && git commit -qm "no pack" && printf 'flutter\n' > .stack && git rm -q .specflow.yml \
  && git add .stack && git commit -qm "legacy .stack")
ck "…an instance at the base with only a legacy .stack: its stack (config.load's fallback, at the ref)" [ "$(python3 "$P" --root "$I" --ref main stack)" = flutter ]
ck "packinfo.py --ref <unresolvable> stack: exit 2" bash -c 'python3 "$1" --root "$2" --ref nope stack >/dev/null 2>&1; [ $? = 2 ]' _ "$P" "$I"
# Build 2 fix wave 2 (REQ-384, REQ-303; PR #54 verifier run 1, finding 1): a tag literally named origin/main (checkout's
# fetch-depth: 0 brings tags; a short name resolves refs/tags/ before refs/remotes/) must not change what packinfo.py
# reads when it is given ci.yml's base ref, refs/remotes/origin/<base>; the short origin/main is shadowed (the local
# residual). The form is read from ci.yml's gates step, so this check follows what CI actually passes.
# Covers: REQ-384
# Covers: REQ-303
CIB=$(python3 - "$ROOT/.github/workflows/ci.yml" <<'PYB'
import re, sys
m = re.search(r"SPECFLOW_BASE_REF: \$\{\{ github\.event_name == 'pull_request' && format\('([^']*)', github\.base_ref\)", open(sys.argv[1]).read())
print(m.group(1).replace("{0}", "main") if m else "")
PYB
)
T="$W/pt"; mkdir -p "$T/scripts"
(cd "$T" && git init -q -b main && printf 'stack: template\npython_version: "3.12"\n' > scripts/template-pack.yml && git add -A && git commit -qm base \
  && git update-ref refs/remotes/origin/main HEAD && git checkout -qb decoy && mkdir -p .specflow && printf 'stack: tauri\n' > .specflow.yml \
  && printf 'stack: tauri\npython_version: "3.9"\n' > .specflow/pack.yml && git add -A && git commit -qm decoy && git tag origin/main \
  && git checkout -q main && git branch -q -D decoy)
ck "packinfo.py --ref <ci.yml's base ref, $CIB> stack, a tag named origin/main on a tauri instance: the branch's template" \
  bash -c '[ "$2" = refs/remotes/origin/main ] && [ "$(python3 "$1" --root "$3" --ref "$2" stack)" = template ] && [ "$(python3 "$1" --root "$3" --ref "$2" get python_version)" = 3.12 ]' _ "$P" "$CIB" "$T"
ck "…the short origin/main is shadowed by that tag (a local run's residual): tauri" \
  bash -c '[ "$(python3 "$1" --root "$2" --ref origin/main stack 2>/dev/null)" = tauri ]' _ "$P" "$T"
# Build 2 fix wave 2 (REQ-384, REQ-303; PR #54 verifier run 1, code-mode low): packinfo.stack fails closed when an
# instance's .specflow/pack.yml or .specflow.yml cannot be parsed (at the ref or in the checkout) — exit 2 naming the
# file — never a silent fall-back to python, which would pick the python hook for another stack's release. (.specflow.yml
# is read when the pack names no stack:, so that case's pack carries none.)
# Covers: REQ-384
# Covers: REQ-303
for f in .specflow/pack.yml .specflow.yml; do
  B="$W/bad-$(basename "$f")"; mkdir -p "$B/.specflow"
  (cd "$B" && git init -q -b main && printf 'stack: tauri\n' > .specflow.yml && printf 'python_version: "3.12"\n' > .specflow/pack.yml \
    && printf 'stack: tauri\n  nested: yes\n' > "$f" && git add -A && git commit -qm "an unparseable $f")
  for r in "--ref main" ""; do
    rc=0; o=$(python3 "$P" --root "$B" $r stack 2>&1) || rc=$?
    ck "packinfo.py ${r:+$r }stack, an instance whose $f does not parse: exit 2 naming it, never python" \
      bash -c '[ "$1" = 2 ] && grep -qF "$3" <<<"$2" && ! grep -qx python <<<"$2"' _ "$rc" "$o" "$f"
  done
done
finish test_release_template
