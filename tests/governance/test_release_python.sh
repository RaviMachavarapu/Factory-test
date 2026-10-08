#!/usr/bin/env bash
# REQ-384, REQ-305 (P6 R18, R20): the python hook builds the sdist and the wheel from HEAD's committed tree, with the
# notes' date: as SOURCE_DATE_EPOCH and the version pinned to VERSION, re-packs the sdist deterministically and marks
# both reproducible; a docs-only commit leaves both byte-identical. Opt-in (SPECFLOW_DOCKER=1, about 3 minutes, Docker
# Desktop running): the image built from the wheel passes release-smoke.sh.
# Covers: REQ-384
# Covers: REQ-305
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
if instance; then
  echo "SKIP: the python pack lives in the template source (stacks/python)"
else
  D="$W/py"; copy_template "$D"
  ck "init (python) exits 0" bash -c "cd '$D' && bash scripts/init-project.sh --name 'Acme Tools' --profile engineer --stack python </dev/null >/dev/null 2>&1"
  pv=$(python3 "$ROOT/scripts/lib/specflow/packinfo.py" --root "$D" get python_version || true)
  ck "the PR-time and tag-time builds agree (F36): an exact 3.12 patch, ci.yml on ubuntu-24.04 with it, both release workflows reading it from the pack" \
    bash -c '[[ $1 =~ ^3\.12\.[0-9]+$ ]] && grep -qE "^    runs-on: ubuntu-24\.04 # specflow:runs-on$" "$2/.github/workflows/ci.yml" && grep -qF "python-version: \"$1\" # specflow:python-version" "$2/.github/workflows/ci.yml" && ! grep -qE "python-version: \"3\.12\"( |$)" "$2/.github/workflows/ci.yml" && grep -qF "packinfo.py --root . get python_version" "$2/.github/workflows/release.yml" && grep -qF "packinfo.py --root . --ref \"\$base\" get python_version" "$2/.github/workflows/release-build.yml"' _ "$pv" "$D"
fi
if instance || ! python3 -c 'import build, setuptools, wheel' 2>/dev/null; then
  echo "SKIP: the python builds need the template source and build, setuptools and wheel importable (ci.yml installs scripts/requirements.txt)"
else
  (cd "$D" && { [ -d .git ] || git init -q -b main .; } && mkdir -p docs/releases && printf -- '---\nversion: 0.1.0\ndate: 2026-10-05\n---\n# Notes\n' > docs/releases/0.1.0-notes.md \
    && git add -A && git commit -qm notes)
  rel() { rm -rf "$1"; (cd "$D" && VERSION=0.1.0 DIST_DIR="$1" RELEASE_PARTS=reproducible bash scripts/release-python.sh) >/dev/null 2>&1; }
  rel "$W/a"
  ck "the python hook: an sdist and a wheel, both reproducible, in a schema-2 manifest (signed null, the notes' epoch)" python3 - "$W/a/manifest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "specflow-manifest/2" and d["stack"] == "python" and d["signed"] is None and d["source_date_epoch"] == 1791158400, d
assert sorted((a["kind"], a["reproducible"]) for a in d["artifacts"]) == [("sdist", True), ("wheel", True)], d
PY
  (cd "$D" && echo "- more" >> docs/releases/0.1.0-notes.md && mkdir -p docs/security && echo r > docs/security/0.1.0-review.md \
    && git add -A && git commit -qm "docs only"); rel "$W/b"
  ck "a docs-only commit leaves the sdist and the wheel byte-identical (R18)" \
    bash -c 'cd "$1" && for f in *.whl *.tar.gz; do cmp -s "$f" "$2/$f" || exit 1; done' _ "$W/a" "$W/b"
  ck "the sdist's members carry the epoch and no owner" python3 - "$W/a" <<'PY'
import glob, sys, tarfile
for m in tarfile.open(glob.glob(sys.argv[1] + "/*.tar.gz")[0]).getmembers():
    assert (m.mtime, m.uid, m.uname) == (1791158400, 0, ""), m
PY
  (cd "$D" && echo "# local edit" >> src/acme_tools/__main__.py); rel "$W/c"; (cd "$D" && git checkout -q -- src)
  ck "an uncommitted source edit is never packaged (the committed tree is)" bash -c 'cmp -s "$1"/*.whl "$2"/*.whl' _ "$W/a" "$W/c"
  rc=0; (cd "$D" && VERSION=9.9.9 DIST_DIR="$W/d" bash scripts/release-python.sh) >/dev/null 2>&1 || rc=$?
  ck "VERSION must equal pyproject's version: exit non-zero" [ "$rc" != 0 ]
  if [ "${SPECFLOW_DOCKER:-}" = 1 ]; then
    ck "opt-in: the image built from the wheel passes release-smoke.sh within 60 s" \
      bash -c 'cd "$1" && mkdir -p dist && cp "$2"/*.whl dist/ && docker build -q -t specflow-smoke:0.1.0 . >/dev/null && bash scripts/release-smoke.sh --stack python --dist dist --image specflow-smoke:0.1.0' _ "$D" "$W/a"
    ck "opt-in: the image's process runs as uid 10001, never root" \
      bash -c 'cd "$1" && [ "$(docker run --rm --entrypoint id specflow-smoke:0.1.0 -u)" = 10001 ]' _ "$D"
    # PR #65 verifier run 1, code mode (REQ-351): USER 10001 must own its WORKDIR, or an app that writes under its
    # working directory fails at runtime.
    # Covers: REQ-351
    ck "opt-in: the image's working directory /app is writable by uid 10001" \
      bash -c '[ "$(docker run --rm --entrypoint sh specflow-smoke:0.1.0 -c "pwd; touch ./.w && rm ./.w && echo w")" = "$(printf "/app\nw")" ]'
    ck "opt-in: the pinned base's pip accepts the empty runtime lock (exit 0, nothing installed)" \
      bash -c 'cd "$1" && test -n "$(ls dist/*.whl)" && docker build -q -t specflow-smoke-empty:0.1.0 . >/dev/null' _ "$D"
    ck "opt-in: release-image.sh build (a clean checkout at RELEASE_COMMIT, the one wheel, the labels, then the smoke) passes against the real docker, with the pinned base" \
      bash -c 'cd "$1" && rm -rf dist "$3" && mkdir -p "$3" && cp "$2"/*.whl "$3"/ && RELEASE_COMMIT="$(git rev-parse HEAD)" bash scripts/release-image.sh build --image ghcr.io/o/r --version 0.1.0 --tag v0.1.0 --out "$3/image.json" --source-url https://github.com/o/r && docker image inspect specflow-release-local:0.1.0 --format "{{index .Config.Labels \"org.opencontainers.image.source\"}} {{index .Config.Labels \"org.opencontainers.image.version\"}}" | grep -qx "https://github.com/o/r 0.1.0"' _ "$D" "$W/a" "$W/imgdist"
    (cd "$D" && sed -i.bak 's/^dependencies = \[\]$/dependencies = ["six"]/' pyproject.toml && rm -f pyproject.toml.bak && git add -A && git commit -qm "a runtime dependency"); rel "$W/e"
    ck "opt-in: a wheel declaring a dependency the image lacks fails the image build (pip check; nothing from PyPI)" \
      bash -c 'cd "$1" && rm -rf dist && mkdir -p dist && cp "$2"/*.whl dist/ && ! docker build -q -t specflow-smoke-deps:0.1.0 . >/dev/null 2>&1' _ "$D" "$W/e"
    (cd "$D" && sed -i.bak 's/^dependencies = \["six"\]$/dependencies = []/' pyproject.toml && rm -f pyproject.toml.bak && git add -A && git commit -qm "no runtime dependency")
    (cd "$D" && sed -i.bak 's/^dependencies = \[\]$/dependencies = ["six"]/' pyproject.toml && rm -f pyproject.toml.bak \
      && docker run --rm -v "$PWD:/w" -w /w "$(sed -n 's/^FROM //p' Dockerfile)" sh -c 'pip download -q --no-deps six==1.17.0 -d /tmp/d && python3 -m pip hash /tmp/d/*.whl' \
         | awk '/--hash=/{print "six==1.17.0 \\\n    " $0}' > requirements-runtime.txt \
      && git add -A && git commit -qm "a hashed runtime dependency"); rel "$W/f"
    ck "opt-in: a wheel whose runtime dependency is in the hashed runtime lock builds and passes pip check and the smoke" \
      bash -c 'cd "$1" && rm -rf dist && mkdir -p dist && cp "$2"/*.whl dist/ && docker build -q -t specflow-smoke-deps2:0.1.0 . >/dev/null && bash scripts/release-smoke.sh --stack python --dist dist --image specflow-smoke-deps2:0.1.0' _ "$D" "$W/f"
    (cd "$D" && git revert --no-edit HEAD >/dev/null)
    # P7 Build 1 final review (findings 1, 8): a lock whose only hash is an sdist's fails the build (--only-binary :all:)
    # rather than building it under build isolation from unhashed build requirements (measured 2026-10-03 in the pinned
    # base: without the flag pip builds six's sdist and exits 0; with it, the wheel's hash mismatches and nothing installs).
    (cd "$D" && sed -i.bak 's/^dependencies = \[\]$/dependencies = ["six"]/' pyproject.toml && rm -f pyproject.toml.bak \
      && docker run --rm "$(sed -n 's/^FROM //p' Dockerfile)" sh -c 'pip download -q --no-deps --no-binary :all: six==1.17.0 -d /tmp/d && python3 -m pip hash /tmp/d/*.tar.gz' \
         | awk '/--hash=/{print "six==1.17.0 \\\n    " $0}' > requirements-runtime.txt \
      && grep -q -- "--hash=sha256:" requirements-runtime.txt && git add -A && git commit -qm "an sdist-only runtime lock"); rel "$W/g"
    ck "opt-in: a runtime lock whose only hash is an sdist's fails the image build (wheels only; no build isolation from unhashed build requirements)" \
      bash -c 'cd "$1" && rm -rf dist && mkdir -p dist && cp "$2"/*.whl dist/ && ! docker build -q -t specflow-smoke-sdist:0.1.0 . >/dev/null 2>&1' _ "$D" "$W/g"
    (cd "$D" && git revert --no-edit HEAD >/dev/null)
  fi
fi
# P6 Task 4.3 (REQ-351, REQ-390; P6 R20, R35, dfe-5; F22, F23, F32): python's release action — the parts Build 3's image and
# prune jobs call — and the scripts behind them: the prior digest read from the existing Release (no registry), the
# build and smoke with no token, the registry read only after login and fail-closed, a re-run's published image reused
# never replaced, the digest and the superseded version recorded, and only that version deleted — a refusal there only a
# warning. The base image pinned by digest. "No such manifest" (PR #57 fix wave 1) is an exact rule: the inspect's whole
# error, one line, is "ERROR: <ref>: not found", "ERROR: <ref>: manifest unknown", "ERROR: manifest unknown",
# "ERROR: <ref>: MANIFEST_UNKNOWN: manifest unknown" or "ERROR: MANIFEST_UNKNOWN: manifest unknown" (<ref> the reference
# inspected); any other failure fails closed. An anonymous inspect of a package that does not exist is refused at the
# token endpoint (403, measured 2026-10-02); the job token's answer for a never-pushed package is unmeasured, so a first
# release (no earlier published Release records an image) reads nothing from the registry before its push.
# Covers: REQ-351
# Covers: REQ-390
if instance; then
  echo "SKIP: the python pack's release action and Dockerfile live in the template source (an instance has them installed)"
else
  PA="$ROOT/stacks/python/release/action.yml"
  ck "stacks/python/release/action.yml: a composite action with the fixed inputs and outputs and the four python parts (R35)" python3 - "$PA" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
assert re.search(r"(?m)^  using: \"?composite\"?$", t), "composite"
ins, outs = t.split("\ninputs:\n", 1)[1].split("\noutputs:\n", 1)[0], t.split("\noutputs:\n", 1)[1].split("\nruns:\n", 1)[0]
for i in ("part", "version", "tag", "dist", "image", "source-url", "prior", "superseded", "token"):
    assert re.search(rf"(?m)^  {re.escape(i)}:$", ins), i
for o in ("prior", "superseded"):
    assert re.search(rf"(?m)^  {o}:$", outs), o
for p in ("image-prior", "image-build", "image-publish", "prune"):
    assert f"'{p}'" in t, p
assert "unknown part" in t, "an unknown part fails the action"
PY
  ck "…its parts call release-image.sh prior, build and publish and release-ghcr-prune.sh" \
    bash -c 'for w in "release-image.sh prior" "release-image.sh build" "release-image.sh publish" "release-ghcr-prune.sh"; do grep -qF "$w" "$1" || exit 1; done' _ "$PA"
  ck "…no GitHub expression inside a run: block; the image-build step never receives the token (it runs project code)" python3 - "$PA" <<'PY'
import re, sys
t = open(sys.argv[1]).read(); steps = re.split(r"(?m)^    - ", t.split("\nruns:\n", 1)[1])[1:]
for s in steps:
    run = s.split("run: |", 1)[1] if "run: |" in s else ""
    assert "$" + "{{" not in run, s
    if "'image-build'" in s:
        assert "token" not in s, s
PY
  ck "init (python) installs it as .github/actions/release/action.yml (Build 3's init copy; the tree the first check initialised)" \
    cmp -s "$PA" "$D/.github/actions/release/action.yml"
  ck "Dockerfile: the base image is pinned by digest" grep -qE '^FROM python:3\.12-slim@sha256:[0-9a-f]{64}$' "$ROOT/stacks/python/Dockerfile"
  ck "Dockerfile: no 'built in P6' header" no grep -qF 'built in P6' "$ROOT/stacks/python/Dockerfile"
  DF="$ROOT/stacks/python/Dockerfile"
  # P7 R8 (REQ-351, REQ-390; dfe-5): the freeze lifts — runtime dependencies from the hash-pinned runtime lock, then the
  # wheel alone, then pip check; the release's code runs as a numeric non-root user.
  # Covers: REQ-351
  # P7 Build 1 final review (findings 1, 8): wheels only. pip builds an sdist under build isolation, whose build
  # requirements it installs from PyPI unhashed (--require-hashes does not reach them), so the lock installs
  # --only-binary :all: and a dependency with no wheel for the image's platform fails the build instead.
  ck "Dockerfile: the runtime lock, hash-pinned, --no-deps and wheels only (--only-binary :all:), before the wheel alone (--no-deps --no-index), then pip check" python3 - "$DF" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
a = re.search(r"(?m)^RUN .*pip install --no-cache-dir --require-hashes --no-deps --only-binary :all: -r /tmp/requirements-runtime\.txt", t)
b = re.search(r"(?m)^RUN .*pip install --no-cache-dir --no-deps --no-index /tmp/\*\.whl && pip check", t)
assert a and b and a.start() < b.start(), (a, b)
assert not re.search(r"pip install(?! --no-cache-dir (--require-hashes --no-deps --only-binary :all: -r /tmp/requirements-runtime\.txt|--no-deps --no-index /tmp/\*\.whl))", t)
PY
  ck "Dockerfile: USER is numeric and not 0, after the installs and before CMD" python3 - "$DF" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
u = list(re.finditer(r"(?m)^USER\s+(\S+)\s*$", t))
assert u and u[-1].group(1).isdigit() and u[-1].group(1) != "0", u
assert t.rindex("pip check") < u[-1].start() < t.index("CMD ["), "order"
PY
  ck "the skeleton ships requirements-runtime.in and its uv-generated hashed lock; the pack lists both lockfiles" \
    bash -c 'test -f "$1/skeleton/requirements-runtime.in" && grep -qF "wheels only" "$1/skeleton/requirements-runtime.in" && head -2 "$1/skeleton/requirements-runtime.txt" | grep -qF -- "--generate-hashes" && grep -qE "^lockfiles: \[requirements\.txt, requirements-runtime\.txt\]$" "$1/pack.yml"' _ "$ROOT/stacks/python"
  ck "README's python deploy subsection: runtime dependencies go in requirements-runtime.in, locked with hashes" \
    bash -c 'grep -qF "requirements-runtime.in" "$1" && grep -qF "requirements-runtime.txt" "$1" && grep -qF -- "--generate-hashes" "$1" && grep -qF -- "--only-binary :all:" "$1" && grep -qF "ships no wheel" "$1"' _ "$ROOT/README.md"
  # Fix wave 2, item 2 (REQ-351): only run and _read print a command — the docker, gh and migrate commands, never the git,
  # mktemp and python3 calls — and DEPLOY_DIGEST overrides the Release's digest for smoke as well as deploy.
  ck "deploy.sh's header: only the docker, gh and migrate commands are printed (never 'every command')" \
    bash -c 'h=$(awk "NR>1 && !/^#/{exit} NR>1" "$1" | tr "\n" " "); grep -qF "Only the docker, gh and migrate commands are printed" <<<"$h" && ! grep -qiF "every command" <<<"$h"' _ "$ROOT/stacks/python/deploy.sh"
  ck "README's python deploy subsection: DRY_RUN=1 prints the docker, gh and migrate commands; DEPLOY_DIGEST serves deploy and smoke" \
    bash -c 'b=$(awk "/^#### Deploying a python instance\$/{f=1} f" "$1" | tr "\n" " " | tr -s " "); grep -qF "\`DRY_RUN=1\` prints the docker, gh and migrate commands" <<<"$b" && ! grep -qF "prints every command" <<<"$b" && grep -qF "\`DEPLOY_DIGEST\`, when set, is the digest \`deploy\` and \`smoke\` run" <<<"$b"' _ "$ROOT/README.md"
fi
G="$W/ghcr"; mkdir -p "$G/bin"
# The stub gh: release download serves $STUB_DIR/rel-<tag>.json as that Release's manifest.json ("release not found"
# when absent; gh's "no assets match the file pattern" when it holds NOASSET); release list serves releases.json (or
# STUB_LIST_ERR); the package listing answers on orgs/ and users/ (or STUB_ORGS_ERR / STUB_USERS_ERR); a DELETE
# succeeds unless STUB_PRUNE_ERR.
cat > "$G/bin/gh" <<'EOF2'
#!/usr/bin/env bash
{ printf '%s\n' "$@"; echo ---; } >> "$STUB_DIR/gh.argv"
case "$*" in
  *"--method DELETE"*) if [ -n "${STUB_PRUNE_ERR:-}" ]; then printf '%s\n' "$STUB_PRUNE_ERR" >&2; exit 1; fi; exit 0 ;;
  *orgs/o/packages/container/r/versions*) if [ -n "${STUB_ORGS_ERR:-}" ]; then printf '%s\n' "$STUB_ORGS_ERR" >&2; exit 1; fi; cat "$STUB_DIR/versions.json" ;;
  *users/o/packages/container/r/versions*) if [ -n "${STUB_USERS_ERR:-}" ]; then printf '%s\n' "$STUB_USERS_ERR" >&2; exit 1; fi; cat "$STUB_DIR/versions.json" ;;
  "release list"*) if [ -n "${STUB_LIST_ERR:-}" ]; then printf '%s\n' "$STUB_LIST_ERR" >&2; exit 1; fi
    if [ -f "$STUB_DIR/releases.json" ]; then cat "$STUB_DIR/releases.json"; else echo '[]'; fi ;;
  "release download"*) f="$STUB_DIR/rel-$3.json"; [ -f "$f" ] || { echo "release not found" >&2; exit 1; }
    if [ "$(cat "$f")" = NOASSET ]; then echo "no assets match the file pattern" >&2; exit 1; fi
    d=.; prev=""; for a in "$@"; do [ "$prev" = --dir ] && d="$a"; prev="$a"; done; cp "$f" "$d/manifest.json" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 64 ;;
esac
EOF2
# The stub docker: imagetools inspect serves remote.digest (or STUB_INSPECT_ERR, exit STUB_INSPECT_RC); push prints
# docker's "<tag>: digest: sha256:<64 hex> size: N" line (STUB_PUSH_DIGEST, or no line with STUB_PUSH_SILENT=1) and moves
# the registry's <version> to STUB_REMOTE_AFTER_PUSH (default the pushed digest); image inspect serves STUB_REPO_DIGEST;
# build lists its context directory (the last argument) into ctx.list.
cat > "$G/bin/docker" <<'EOF2'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_DIR/docker.argv"
case "$1 $2 $3" in
  "buildx imagetools inspect") if [ -f "$STUB_DIR/remote.digest" ]; then printf 'Name: %s\nDigest: %s\n' "$4" "$(cat "$STUB_DIR/remote.digest")"; else printf '%b\n' "${STUB_INSPECT_ERR:-ERROR: manifest unknown}" >&2; exit "${STUB_INSPECT_RC:-1}"; fi ;;
esac
case "$1 $2" in
  "image inspect") [ -z "${STUB_REPO_DIGEST:-}" ] || printf '%s\n' "$STUB_REPO_DIGEST"; exit 0 ;;
esac
case "$1" in
  build) for c; do :; done; (cd "$c" && find . -type f | sed 's#^\./##' | LC_ALL=C sort) > "$STUB_DIR/ctx.list" ;;
  push) p="${STUB_PUSH_DIGEST:-$STUB_DEFAULT_DIGEST}"; [ "${STUB_PUSH_SILENT:-}" = 1 ] || printf 'The push refers to repository [%s]\n%s: digest: %s size: 1234\n' "${2%:*}" "${2##*:}" "$p"
    printf '%s\n' "${STUB_REMOTE_AFTER_PUSH:-$p}" > "$STUB_DIR/remote.digest" ;;
esac
exit 0
EOF2
chmod +x "$G/bin/gh" "$G/bin/docker"
DN="sha256:$(printf '%064d' 0 | tr 0 a)"; DO="sha256:$(printf '%064d' 0 | tr 0 b)"; DX="sha256:$(printf '%064d' 0 | tr 0 c)"
# A checkout of the release commit: a committed Dockerfile, dist/ ignored; the release's one wheel in the --out
# directory ($G), and a stale wheel in the checkout's own dist/ that must never reach the image.
R="$G/repo"; git init -q -b main "$R"
(cd "$R" && printf 'FROM scratch\nCOPY dist/*.whl /tmp/\n' > Dockerfile && echo "# lock" > requirements-runtime.txt && printf 'dist/\n' > .gitignore && git add -A && git commit -qm one \
  && echo "# two" >> Dockerfile && git commit -qam two && mkdir -p dist && echo stale > dist/stale-0.0.1-py3-none-any.whl)
RC1=$(git -C "$R" rev-parse HEAD~1); RC2=$(git -C "$R" rev-parse HEAD)
echo wheel > "$G/acme-1.0.0-py3-none-any.whl"
img() { rc=0; : > "$G/docker.argv"; : > "$G/gh.argv"; rm -f "$G/image.json" "$G/ctx.list"; out=$(cd "$R" && STUB_DIR="$G" STUB_DEFAULT_DIGEST="$DN" RELEASE_COMMIT="${RCOMMIT-$RC2}" PATH="$G/bin:$PATH" bash "$ROOT/scripts/release-image.sh" "$@" --image ghcr.io/o/r --version 1.0.0 --tag v1.0.0 --out "$G/image.json" 2>&1) || rc=$?; }
nostate() { rm -f "$G/image-prior.json" "$G/remote.digest" "$G"/rel-*.json "$G/releases.json"; }
nostate
img prior; ck "release-image.sh prior with no Release: none, and no registry call" bash -c '[ "$1" = 0 ] && grep -qx "none" <<<"$2" && [ ! -s "$3" ]' _ "$rc" "$out" "$G/docker.argv"
# Fix wave 1, item 3 (REQ-351, REQ-390; dfe-5): the build of record — a context holding only the committed Dockerfile and
# the release's one wheel (never the checkout's dist/), --no-cache, the source and version labels, refused on a dirty tree
# or a HEAD other than RELEASE_COMMIT (the --at-tag guard); then the smoke, offline and never pulling.
img build --source-url https://github.com/o/r
ck "release-image.sh build: docker build --no-cache with the source and version labels, then the smoke (docker run --network none --pull never --name … --rm -e SPECFLOW_SMOKE=1)" \
  bash -c '[ "$1" = 0 ] && grep -E "^docker build " "$2" | grep -qF -- "--no-cache" && grep -qF "org.opencontainers.image.source=https://github.com/o/r" "$2" && grep -qF "org.opencontainers.image.version=1.0.0" "$2" && grep -qE "^docker run --network none --pull never --name specflow-smoke-[0-9]+-[0-9]+ --rm -e SPECFLOW_SMOKE=1 specflow-release-local:1\.0\.0$" "$2"' _ "$rc" "$G/docker.argv"
ck "…its context is a temporary directory holding only the Dockerfile, the runtime lock and the one wheel — the checkout's stale dist/ wheel never reaches it" \
  bash -c '[ "$(cat "$1")" = "$(printf "Dockerfile\ndist/acme-1.0.0-py3-none-any.whl\nrequirements-runtime.txt")" ] && ! grep -E "^docker build " "$2" | grep -qE " \.$"' _ "$G/ctx.list" "$G/docker.argv"
(cd "$R" && git rm -q requirements-runtime.txt && git commit -qm "no runtime lock")
RCOMMIT="$(git -C "$R" rev-parse HEAD)" img build --source-url https://github.com/o/r
ck "release-image.sh build: a tagged tree without requirements-runtime.txt fails before docker build, naming it" \
  bash -c '[ "$1" != 0 ] && grep -qF "requirements-runtime.txt" <<<"$2" && ! grep -qF "is not RELEASE_COMMIT" <<<"$2" && ! grep -q "^docker build " "$3"' _ "$rc" "$out" "$G/docker.argv"
git -C "$R" reset -q --hard "$RC2"
(cd "$R" && echo "# dirty" >> Dockerfile); img build --source-url https://github.com/o/r; (cd "$R" && git checkout -q -- Dockerfile)
ck "…a working tree with an uncommitted edit: refused, exit 1, nothing built" bash -c '[ "$1" = 1 ] && ! grep -q "^docker build" "$2"' _ "$rc" "$G/docker.argv"
(cd "$R" && echo x > untracked.txt); img build --source-url https://github.com/o/r; rm -f "$R/untracked.txt"
ck "…an untracked file in the working tree: refused, exit 1, nothing built" bash -c '[ "$1" = 1 ] && ! grep -q "^docker build" "$2"' _ "$rc" "$G/docker.argv"
RCOMMIT="$RC1" img build --source-url https://github.com/o/r
ck "…HEAD is not RELEASE_COMMIT: refused, exit 1, nothing built" bash -c '[ "$1" = 1 ] && ! grep -q "^docker build" "$2" && grep -qF "RELEASE_COMMIT" <<<"$3"' _ "$rc" "$G/docker.argv" "$out"
RCOMMIT="" img build --source-url https://github.com/o/r
ck "…no RELEASE_COMMIT: refused, exit 1, nothing built" bash -c '[ "$1" = 1 ] && ! grep -q "^docker build" "$2"' _ "$rc" "$G/docker.argv"
echo wheel2 > "$G/acme-1.0.0-py3-none-any.whl.2.whl"; img build --source-url https://github.com/o/r; rm -f "$G/acme-1.0.0-py3-none-any.whl.2.whl"
ck "…two wheels in the release's directory: refused, exit 1, nothing built" bash -c '[ "$1" = 1 ] && ! grep -q "^docker build" "$2"' _ "$rc" "$G/docker.argv"
# Fix wave 1, item 1 (REQ-390; dfe-5): the inspect's "no such manifest" is an exact rule — the whole error, one line, is one
# of the five strings below; any other failure (an authorisation error, "not found" elsewhere, another reference, a
# missing docker, a network error, two lines) fails closed. With no image-prior state the registry is read before the push.
for e in "ERROR: ghcr.io/o/r:1.0.0: not found" "ERROR: ghcr.io/o/r:1.0.0: manifest unknown" "ERROR: manifest unknown" \
         "ERROR: ghcr.io/o/r:1.0.0: MANIFEST_UNKNOWN: manifest unknown" "ERROR: MANIFEST_UNKNOWN: manifest unknown"; do
  nostate; STUB_INSPECT_ERR="$e" img publish --prior none
  ck "publish: the inspect error '$e' is none — pushed, exit 0" bash -c '[ "$1" = 0 ] && grep -q "^docker push" "$2"' _ "$rc" "$G/docker.argv"
done
for e in "ERROR: unauthorized: authentication required" \
         "ERROR: failed to authorize: failed to fetch oauth token: unexpected status from GET request to https://ghcr.io/token?scope=repository%3Ao%2Fr%3Apull&service=ghcr.io: 403 Forbidden" \
         "ERROR: failed to authorize: failed to fetch oauth token: unexpected status from GET request to https://ghcr.io/token: 404 Not Found" \
         "ERROR: unexpected status code 404 Not Found" "ERROR: ghcr.io/o/other:1.0.0: not found" "ERROR: denied: manifest unknown" \
         "ERROR: manifest unknownx" "ERROR: manifest unknown\nERROR: unauthorized" "bash: docker: command not found" \
         "ERROR: dial tcp: lookup ghcr.io: no such host" "ERROR: ghcr.io/o/r:1.0.0: not found (retrying)"; do
  nostate; STUB_INSPECT_ERR="$e" img publish --prior none
  ck "publish: the inspect error '$e' fails closed — exit 1, nothing pushed" bash -c '[ "$1" = 1 ] && ! grep -q "^docker push" "$2"' _ "$rc" "$G/docker.argv"
done
nostate; STUB_INSPECT_ERR="docker: 'buildx' is not a docker command." STUB_INSPECT_RC=127 img publish --prior none
ck "publish: no buildx (exit 127) fails closed — exit 1, nothing pushed" bash -c '[ "$1" = 1 ] && ! grep -q "^docker push" "$2"' _ "$rc" "$G/docker.argv"
nostate; img publish --prior none
ck "…'manifest unknown' is none: pushed, the digest recorded, superseded none" python3 - "$G/image.json" "$DN" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert (d["name"], d["tag"], d["digest"], d["superseded"]) == ("ghcr.io/o/r", "1.0.0", sys.argv[2], "none"), d
PY
# Fix wave 1, item 1 (REQ-351, REQ-390; dfe-5): an anonymous inspect of a package that does not exist is refused at the
# token endpoint (403); what the job's token gets for a never-pushed package is unmeasured — so on a first release (no
# earlier published Release records an image in its manifest.json) publish reads nothing from the registry before the
# push: prior none by construction, nothing superseded. A later release reads it, under the exact rule above.
nostate; img prior
ck "prior, no Release at all: none, and the image-prior state says first" python3 - "$G/image-prior.json" "$out" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == {"prior": "none", "first": True}, open(sys.argv[1]).read()
assert sys.argv[2].strip() == "none", sys.argv[2]
PY
STUB_INSPECT_ERR="ERROR: denied: requested access to the resource is denied" img publish --prior none
ck "…a first release's publish never inspects before the push (a denied inspect is not reached): pushed, read back, superseded none" python3 - "$G/docker.argv" "$G/image.json" "$DN" "$rc" <<'PY'
import json, sys
a = open(sys.argv[1]).read().splitlines()
assert sys.argv[4] == "0", sys.argv[4]
p = next(i for i, l in enumerate(a) if l.startswith("docker push "))
assert not any(l.startswith("docker buildx imagetools inspect") for l in a[:p]), a
assert any(l.startswith("docker buildx imagetools inspect") for l in a[p:]), a
d = json.load(open(sys.argv[2])); assert (d["digest"], d["superseded"]) == (sys.argv[3], "none"), d
PY
nostate; printf '[{"tagName": "v0.9.0", "isDraft": false, "publishedAt": "2026-09-01T00:00:00Z"}, {"tagName": "v0.9.1", "isDraft": true, "publishedAt": null}]\n' > "$G/releases.json"
printf '{"image": {"name": "ghcr.io/o/r", "tag": "0.9.0", "digest": "%s"}}\n' "$DO" > "$G/rel-v0.9.0.json"
img prior; ck "prior, an earlier published Release records an image: none, and the state says not first" \
  bash -c '[ "$1" = 0 ] && python3 -c "import json,sys; assert json.load(open(sys.argv[1])) == {\"prior\": \"none\", \"first\": False}" "$2"' _ "$rc" "$G/image-prior.json"
STUB_INSPECT_ERR="ERROR: denied: requested access to the resource is denied" img publish --prior none
ck "…then publish reads the registry before the push, and a denied inspect fails closed — exit 1, nothing pushed" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^docker push" "$2"' _ "$rc" "$G/docker.argv"
echo NOASSET > "$G/rel-v0.9.0.json"; img prior
ck "prior, the earlier Release has no manifest.json asset (no recorded image): first" \
  bash -c '[ "$1" = 0 ] && python3 -c "import json,sys; assert json.load(open(sys.argv[1]))[\"first\"] is True" "$2"' _ "$rc" "$G/image-prior.json"
# Fix wave 1 round 2 (REQ-351; dfe-5): first means no earlier published Release records an image — prior walks every
# published Release in the listing, newest first, until one's manifest.json records an image.digest; a newer Release
# without a manifest.json asset, or whose manifest records no image, does not hide an older one that does.
nostate; printf '[{"tagName": "v0.9.0", "isDraft": false, "publishedAt": "2026-09-01T00:00:00Z"}, {"tagName": "v0.9.2", "isDraft": false, "publishedAt": "2026-09-20T00:00:00Z"}, {"tagName": "v0.9.1", "isDraft": false, "publishedAt": "2026-09-10T00:00:00Z"}, {"tagName": "v0.9.3", "isDraft": true, "publishedAt": null}]\n' > "$G/releases.json"
printf '{"image": {"name": "ghcr.io/o/r", "tag": "0.9.0", "digest": "%s"}}\n' "$DO" > "$G/rel-v0.9.0.json"
echo NOASSET > "$G/rel-v0.9.1.json"; printf '{"schema": 2}\n' > "$G/rel-v0.9.2.json"
img prior; ck "prior: the newest Releases record no image (no manifest.json asset, no image.digest), an older one does — not first; walked newest first" \
  python3 - "$rc" "$G/image-prior.json" "$G/gh.argv" <<'PY2'
import json, sys
assert sys.argv[1] == "0", sys.argv[1]
assert json.load(open(sys.argv[2])) == {"prior": "none", "first": False}, open(sys.argv[2]).read()
calls = [c.split("\n") for c in open(sys.argv[3]).read().split("---\n") if c.strip()]
dl = [c[2] for c in calls if c[:2] == ["release", "download"]]
assert dl == ["v1.0.0", "v0.9.2", "v0.9.1", "v0.9.0"], dl
PY2
printf '{"image": {"digest": "%s"}}\n' "$DX" > "$G/rel-v0.9.2.json"; img prior
ck "…the walk stops at the newest Release that records an image (no older download)" \
  bash -c '[ "$1" = 0 ] && ! grep -qx "v0.9.1" "$2" && ! grep -qx "v0.9.0" "$2" && python3 -c "import json,sys; assert json.load(open(sys.argv[1]))[\"first\"] is False" "$3"' _ "$rc" "$G/gh.argv" "$G/image-prior.json"
echo NOASSET > "$G/rel-v0.9.0.json"; printf '{"schema": 2}\n' > "$G/rel-v0.9.2.json"; img prior
ck "…no published Release in the listing records an image: first" \
  bash -c '[ "$1" = 0 ] && python3 -c "import json,sys; assert json.load(open(sys.argv[1])) == {\"prior\": \"none\", \"first\": True}" "$2"' _ "$rc" "$G/image-prior.json"
printf '{"image": {"digest": "sha256:short"}}\n' > "$G/rel-v0.9.0.json"; img prior
ck "…an older Release's tampered manifest digest, reached by the walk — exit 1, no state written" \
  bash -c '[ "$1" = 1 ] && [ ! -e "$2" ]' _ "$rc" "$G/image-prior.json"
nostate; STUB_LIST_ERR="gh: Server Error (HTTP 502)" img prior
ck "prior: the Release listing fails — exit 1, no state written (first is never guessed)" bash -c '[ "$1" = 1 ] && [ ! -e "$2" ]' _ "$rc" "$G/image-prior.json"
nostate; echo NOASSET > "$G/rel-v1.0.0.json"; img prior
ck "prior: the tag's own Release exists with no manifest.json asset — exit 1 (a draft an earlier publish left: inspect it by hand)" \
  bash -c '[ "$1" = 1 ] && grep -qF "manifest.json" <<<"$2"' _ "$rc" "$out"
# Fix wave 1, item 2 (REQ-351; dfe-5): every digest that reaches GITHUB_OUTPUT, image.json or a flag is sha256:<64 hex>.
nostate; printf '{"image": {"digest": "sha256:short"}}\n' > "$G/rel-v1.0.0.json"; img prior
ck "prior: a tampered manifest asset (a digest that is not sha256:<64 hex>) — exit 1, no digest printed" bash -c '[ "$1" = 1 ] && ! grep -qx "sha256:short" <<<"$2"' _ "$rc" "$out"
python3 -c 'import json,sys; json.dump({"image": {"digest": sys.argv[1] + "\nsuperseded=x"}}, open(sys.argv[2], "w"))' "$DN" "$G/rel-v1.0.0.json"; img prior
ck "prior: a manifest digest carrying a newline — exit 1, nothing printed that could reach GITHUB_OUTPUT" bash -c '[ "$1" = 1 ] && ! grep -q "superseded=x" <<<"$2"' _ "$rc" "$out"
nostate; img publish --prior "sha256:abc"
ck "publish --prior that is neither none nor sha256:<64 hex>: exit 1, no registry call" bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$rc" "$G/docker.argv"
nostate; echo "sha256:zz" > "$G/remote.digest"; img publish --prior "$DN"
ck "publish: an inspect Digest: that is not sha256:<64 hex> fails closed — exit 1" [ "$rc" = 1 ]
# Final review, findings 4 and 7 (REQ-351, REQ-390; dfe-5): the digest recorded is the one the push itself printed (else
# the local image's RepoDigests entry for <image>), and the registry's read-back must equal it — a <version> moved between
# the push and the read-back exits 1 and records nothing.
nostate; STUB_REMOTE_AFTER_PUSH="$DO" img publish --prior none
ck "publish: the read-back names another digest than the push printed (the tag moved) — exit 1, no image.json" \
  bash -c '[ "$1" = 1 ] && [ ! -e "$2" ] && grep -qF "${3#sha256:}" <<<"$4"' _ "$rc" "$G/image.json" "$DO" "$out"
nostate; STUB_PUSH_SILENT=1 STUB_REPO_DIGEST="ghcr.io/o/r@$DN" img publish --prior none
ck "…no digest line from the push: the local image's RepoDigests entry for <image> is the pushed digest, recorded" python3 - "$G/image.json" "$DN" "$rc" <<'PY'
import json, sys
assert sys.argv[3] == "0", sys.argv[3]
assert json.load(open(sys.argv[1]))["digest"] == sys.argv[2]
PY
nostate; STUB_PUSH_SILENT=1 STUB_REPO_DIGEST="ghcr.io/other/x@$DX" img publish --prior none
ck "…no digest from the push and no RepoDigests entry for <image>: exit 1, never the registry's answer" \
  bash -c '[ "$1" = 1 ] && [ ! -e "$2" ]' _ "$rc" "$G/image.json"
nostate; STUB_PUSH_DIGEST="sha256:short" img publish --prior none
ck "…a pushed digest that is not sha256:<64 hex> (and no RepoDigests entry): exit 1" \
  bash -c '[ "$1" = 1 ] && [ ! -e "$2" ]' _ "$rc" "$G/image.json"
nostate; echo "$DO" > "$G/remote.digest"; img publish --prior none
ck "publish over a <version> another run pushed: the superseded digest recorded" \
  bash -c '[ "$1" = 0 ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert (d[\"digest\"], d[\"superseded\"]) == (sys.argv[2], sys.argv[3]), d" "$2" "$3" "$4"' _ "$rc" "$G/image.json" "$DN" "$DO"
nostate; echo "$DN" > "$G/remote.digest"   # the registry as the first release left it
printf '{"image": {"name": "ghcr.io/o/r", "tag": "1.0.0", "digest": "%s"}}\n' "$DN" > "$G/rel-v1.0.0.json"
img prior; ck "release-image.sh prior on a re-run: the published digest, read from the Release's manifest.json (gh release download --dir)" grep -qxF "$DN" <<<"$out"
img publish --prior "$DN"
ck "…publish --prior that digest, still tagged 1.0.0: reused — no build, no push, superseded none (F32 (a))" \
  bash -c '[ "$1" = 0 ] && ! grep -qE "^docker (build|push) " "$2" && grep -qF "reused" <<<"$3"' _ "$rc" "$G/docker.argv" "$out"
ck "…the reuse path's image.json: name, tag, the published digest, superseded none" python3 - "$G/image.json" "$DN" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == {"name": "ghcr.io/o/r", "tag": "1.0.0", "digest": sys.argv[2], "superseded": "none"}, open(sys.argv[1]).read()
PY
echo "$DO" > "$G/remote.digest"; img publish --prior "$DN"
ck "…a recorded digest that <version> no longer names: exit 1, never a silent rebuild" [ "$rc" = 1 ]
nostate
# Fix wave 1, item 5 (REQ-351; dfe-5; F32 (c)): after publish the Release exists, so every GitHub failure in the prune —
# a 401, 403, 404 on both scopes, 429, 5xx, a network error, an unreadable listing, a refused delete — is a ::warning:: and
# exit 0; only bad arguments exit 1.
printf '[{"id": 1, "name": "%s", "metadata": {"container": {"tags": []}}}, {"id": 2, "name": "%s", "metadata": {"container": {"tags": []}}}, {"id": 3, "name": "%s", "metadata": {"container": {"tags": ["1.0.0"]}}}]\n' "$DN" "$DO" "$DX" > "$G/versions.json"
prune() { rc=0; : > "$G/gh.argv"; out=$(STUB_DIR="$G" PATH="$G/bin:$PATH" bash "$ROOT/scripts/release-ghcr-prune.sh" --owner o --package r "$@" 2>&1) || rc=$?; }
prune --superseded none
ck "prune, nothing superseded: no API call, exit 0" bash -c '[ "$1" = 0 ] && [ ! -s "$2" ]' _ "$rc" "$G/gh.argv"
prune --superseded "$DN"
ck "prune: deletes exactly the superseded, now-untagged version (id 1), never the other untagged one (id 2) (dfe-5)" \
  bash -c '[ "$1" = 0 ] && grep -qx "orgs/o/packages/container/r/versions/1" "$2" && ! grep -q "versions/2$" "$2"' _ "$rc" "$G/gh.argv"
prune --superseded "$DX"
ck "prune: a superseded digest that still carries a tag is kept" bash -c '[ "$1" = 0 ] && ! grep -qx DELETE "$2"' _ "$rc" "$G/gh.argv"
STUB_ORGS_ERR="gh: Not Found (HTTP 404)" prune --superseded "$DN"
ck "prune: orgs/ answers 404, users/ answers — the users/ version is deleted" \
  bash -c '[ "$1" = 0 ] && grep -qx "users/o/packages/container/r/versions/1" "$2" && grep -qx DELETE "$2"' _ "$rc" "$G/gh.argv"
for e in "gh: Forbidden (HTTP 403)" "gh: Bad credentials (HTTP 401)" "gh: Server Error (HTTP 502)" "gh: API rate limit exceeded (HTTP 429)" "error connecting to api.github.com"; do
  STUB_ORGS_ERR="$e" prune --superseded "$DN"
  ck "prune: the listing fails ($e) — a ::warning::, exit 0, nothing deleted" \
    bash -c '[ "$1" = 0 ] && grep -qF "::warning::" <<<"$2" && ! grep -qx DELETE "$3"' _ "$rc" "$out" "$G/gh.argv"
done
STUB_ORGS_ERR="gh: Not Found (HTTP 404)" STUB_USERS_ERR="gh: Not Found (HTTP 404)" prune --superseded "$DN"
ck "prune: 404 on orgs/ and users/ — a ::warning::, exit 0" bash -c '[ "$1" = 0 ] && grep -qF "::warning::" <<<"$2"' _ "$rc" "$out"
cp "$G/versions.json" "$G/versions.good"; echo "<html>busy</html>" > "$G/versions.json"; prune --superseded "$DN"; cp "$G/versions.good" "$G/versions.json"
ck "prune: an unreadable listing — a ::warning::, exit 0, nothing deleted" \
  bash -c '[ "$1" = 0 ] && grep -qF "::warning::" <<<"$2" && ! grep -qx DELETE "$3"' _ "$rc" "$out" "$G/gh.argv"
for e in "gh: Forbidden (HTTP 403)" "gh: Server Error (HTTP 500)"; do
  STUB_PRUNE_ERR="$e" prune --superseded "$DN"
  ck "prune: GitHub refuses or fails the delete ($e) — a warning, exit 0 (F32 (c))" bash -c '[ "$1" = 0 ] && grep -qF "::warning::" <<<"$2"' _ "$rc" "$out"
done
prune --superseded "sha256:aaa"
ck "prune: a --superseded that is neither none nor sha256:<64 hex> is a programming error — exit 1, no API call" bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$rc" "$G/gh.argv"
rc=0; STUB_DIR="$G" PATH="$G/bin:$PATH" bash "$ROOT/scripts/release-ghcr-prune.sh" --owner o >/dev/null 2>&1 || rc=$?
ck "prune: missing arguments — exit 1" [ "$rc" = 1 ]
# Fix wave 1, item 5 (REQ-351; dfe-5; P6 R35): the action's run: blocks are executed — each extracted from the action
# and run under bash -eo pipefail with the env the action gives it, as test_release_workflow.sh runs release.yml's steps.
if instance; then PA2="$ROOT/.github/actions/release/action.yml"; else PA2="$ROOT/stacks/python/release/action.yml"; fi
step_body() { python3 - "$1" "$2" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines(); name = sys.argv[2]
i = next(k for k, l in enumerate(lines) if re.match(r"^\s*- name: " + re.escape(name) + r"\s*$", l))
ind = len(lines[i]) - len(lines[i].lstrip())
for k in range(i + 1, len(lines)):
    l = lines[k]
    if l.strip() and len(l) - len(l.lstrip()) <= ind:
        sys.exit("the step has no run: | body")
    m = re.match(r"^(\s*)run: \|\s*$", l)
    if m:
        rind = len(m.group(1)); out = []
        for l2 in lines[k + 1:]:
            if l2.strip() and len(l2) - len(l2.lstrip()) <= rind:
                break
            out.append(l2[rind + 2:] if l2.strip() else "")
        print("\n".join(out)); sys.exit(0)
sys.exit("no run: | body")
PY
}
if [ -f "$PA2" ] && grep -qF "image-publish" "$PA2"; then
  A="$G/act"; mkdir -p "$A" "$G/actdist"; ln -s "$ROOT/scripts" "$A/scripts"
  step_body "$PA2" "Read the existing Release's image digest" > "$G/s-prior.sh"
  step_body "$PA2" "Push the image, or reuse the published one" > "$G/s-publish.sh"
  step_body "$PA2" "Delete the version this run superseded" > "$G/s-prune.sh"
  astep() {  # astep BODY DIR VAR=VALUE... — the step body under bash -eo pipefail in DIR; rc, out, $G/gho
    : > "$G/gho"; : > "$G/gh.argv"; : > "$G/docker.argv"; rc=0
    out=$(cd "$2" && env -i PATH="$G/bin:$PATH" HOME="$HOME" STUB_DIR="$G" STUB_DEFAULT_DIGEST="$DN" GITHUB_OUTPUT="$G/gho" "${@:3}" bash --noprofile --norc -eo pipefail "$1" 2>&1) || rc=$?; }
  nostate; printf '{"image": {"digest": "%s"}}\n' "$DN" > "$G/rel-v1.0.0.json"
  astep "$G/s-prior.sh" "$A" VERSION=1.0.0 TAG=v1.0.0 DIST="$G/actdist" IMAGE=ghcr.io/o/r GH_TOKEN=t
  ck "action image-prior: GITHUB_OUTPUT is exactly prior=<the Release's digest>" bash -c '[ "$1" = 0 ] && [ "$(cat "$2")" = "prior=$3" ]' _ "$rc" "$G/gho" "$DN"
  python3 -c 'import json,sys; json.dump({"image": {"digest": sys.argv[1] + "\nsuperseded=x"}}, open(sys.argv[2], "w"))' "$DN" "$G/rel-v1.0.0.json"
  astep "$G/s-prior.sh" "$A" VERSION=1.0.0 TAG=v1.0.0 DIST="$G/actdist" IMAGE=ghcr.io/o/r GH_TOKEN=t
  ck "action image-prior: a tampered manifest asset fails the step and writes no GITHUB_OUTPUT line" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$G/gho"
  nostate; echo "$DN" > "$G/remote.digest"
  astep "$G/s-publish.sh" "$A" VERSION=1.0.0 TAG=v1.0.0 DIST="$G/actdist" IMAGE=ghcr.io/o/r SOURCE_URL=https://github.com/o/r PRIOR="$DN"
  ck "action image-publish (reuse): its python read of image.json writes exactly superseded=none" bash -c '[ "$1" = 0 ] && [ "$(cat "$2")" = "superseded=none" ]' _ "$rc" "$G/gho"
  astep "$G/s-publish.sh" "$A" VERSION=1.0.0 TAG=v1.0.0 DIST="$G/actdist" IMAGE=ghcr.io/o/r SOURCE_URL=https://github.com/o/r PRIOR="$DN
superseded=x"
  ck "action image-publish: a PRIOR carrying a newline fails before any registry call, no GITHUB_OUTPUT line" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ] && [ ! -s "$3" ]' _ "$rc" "$G/gho" "$G/docker.argv"
  F="$G/fake"; mkdir -p "$F/scripts"
  printf '%s\n' '#!/usr/bin/env bash' 'o=""; while [ $# -gt 0 ]; do [ "$1" = --out ] && o="$2"; shift; done' \
    'python3 -c "import json,sys; json.dump({\"name\": \"ghcr.io/o/r\", \"tag\": \"1.0.0\", \"digest\": sys.argv[1], \"superseded\": \"sha256:x\\nprior=evil\"}, open(sys.argv[2], \"w\"))" "$STUB_DEFAULT_DIGEST" "$o"' > "$F/scripts/release-image.sh"
  astep "$G/s-publish.sh" "$F" VERSION=1.0.0 TAG=v1.0.0 DIST="$G/actdist" IMAGE=ghcr.io/o/r SOURCE_URL=https://github.com/o/r PRIOR=none
  ck "action image-publish: an image.json whose superseded is not none or sha256:<64 hex> fails the step, no GITHUB_OUTPUT line" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$G/gho"
  astep "$G/s-prune.sh" "$A" IMAGE=ghcr.io/o/r SUPERSEDED="$DN" GH_TOKEN=t
  ck "action prune: IMAGE ghcr.io/o/r splits into --owner o --package r (the listing on orgs/o/packages/container/r)" \
    bash -c '[ "$1" = 0 ] && grep -qx "orgs/o/packages/container/r/versions" "$2"' _ "$rc" "$G/gh.argv"
  for bad in ghcr.io/o docker.io/o/r "ghcr.io/o/r/x" "ghcr.io/O/r"; do
    astep "$G/s-prune.sh" "$A" IMAGE="$bad" SUPERSEDED="$DN" GH_TOKEN=t
    ck "action prune: IMAGE '$bad' is not ghcr.io/<owner>/<repo> lower-cased — exit 1, no API call" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$G/gh.argv"
  done
  # Fix wave 2, item 1 (REQ-351; dfe-5): the image-build step's env maps RELEASE_COMMIT to github.sha — the tagged commit,
  # the only HEAD release-image.sh builds from — and its run: block, executed with that env (github.sha substituted) and
  # the stub docker in a clean checkout, builds at that commit and refuses any other.
  step_env() {  # step_env ACTION STEP [EXPR=VALUE...] — the step's env: as KEY=VALUE lines, each ${{ EXPR }} substituted
    python3 - "$@" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines(); name = sys.argv[2]
sub = dict(a.split("=", 1) for a in sys.argv[3:])
i = next(k for k, l in enumerate(lines) if re.match(r"^\s*- name: " + re.escape(name) + r"\s*$", l))
ind = len(lines[i]) - len(lines[i].lstrip()); env = None; out = []
for l in lines[i + 1:]:
    if l.strip() and len(l) - len(l.lstrip()) <= ind:
        break
    m = re.match(r"^(\s*)env:\s*$", l)
    if m:
        env = len(m.group(1)); continue
    if env is not None and l.strip() and not l.strip().startswith("#"):
        if len(l) - len(l.lstrip()) <= env:
            break
        k, v = l.strip().split(": ", 1)
        def rep(e):
            x = e.group(1)
            if x not in sub:
                sys.exit("unsubstituted expression: " + x)
            return sub[x]
        out.append(k + "=" + re.sub(r"\$\{\{\s*([^}]*?)\s*\}\}", rep, v))
if env is None:
    sys.exit("the step has no env:")
print("\n".join(out))
PY
  }
  ck "action image-build: its env maps RELEASE_COMMIT to github.sha (the tagged commit release-image.sh builds from)" \
    bash -c 'grep -qx "RELEASE_COMMIT=SHA" <<<"$1"' _ "$(step_env "$PA2" "Build the image and smoke it" github.sha=SHA inputs.version=V inputs.tag=T inputs.dist=D inputs.image=I inputs.source-url=S 2>&1)"
  step_body "$PA2" "Build the image and smoke it" > "$G/s-build.sh"
  B="$G/bld"; git init -q -b main "$B"; mkdir -p "$G/bdist"; echo wheel > "$G/bdist/acme-1.0.0-py3-none-any.whl"
  (cd "$B" && printf 'FROM scratch\nCOPY dist/*.whl /tmp/\n' > Dockerfile && echo "# lock" > requirements-runtime.txt && ln -s "$ROOT/scripts" scripts && git add -A && git commit -qm one \
    && echo "# two" >> Dockerfile && git commit -qam two)
  bstep() {  # bstep SHA — the image-build body in $B with the env the action gives it, github.sha=SHA
    local ev=() l
    while IFS= read -r l; do [ -n "$l" ] && ev+=("$l"); done < <(step_env "$PA2" "Build the image and smoke it" github.sha="$1" \
      inputs.version=1.0.0 inputs.tag=v1.0.0 inputs.dist="$G/bdist" inputs.image=ghcr.io/o/r inputs.source-url=https://github.com/o/r)
    rm -f "$G/ctx.list"; astep "$G/s-build.sh" "$B" ${ev[@]+"${ev[@]}"}; }
  bstep "$(git -C "$B" rev-parse HEAD)"
  ck "action image-build (executed, github.sha the checkout's HEAD): docker build of the committed Dockerfile and the one wheel, then the smoke" \
    bash -c '[ "$1" = 0 ] && grep -q "^docker build " "$2" && grep -q "^docker run --network none --pull never " "$2" && [ "$(cat "$3")" = "$(printf "Dockerfile\ndist/acme-1.0.0-py3-none-any.whl\nrequirements-runtime.txt")" ]' _ "$rc" "$G/docker.argv" "$G/ctx.list"
  bstep "$(git -C "$B" rev-parse HEAD~1)"
  ck "action image-build (executed, github.sha another commit): refused, nothing built" \
    bash -c '[ "$1" != 0 ] && ! grep -q "^docker build" "$2" && grep -qF "RELEASE_COMMIT" <<<"$3"' _ "$rc" "$G/docker.argv" "$out"
else
  echo "SKIP: no python release action here (not the template source or a python instance)"
fi
nostate
# P6 Task 4.4 (REQ-351; dfe-5; P6 R29, R35): dfe-5 as shipped, the GHCR residual in Build 4's region, and the spec entry's
# Build 4 sentence — pinned here, not in test_threat_model_current.sh or test_spec_lifecycle.sh, so Build 5 (in parallel)
# shares no test line.
# Covers: REQ-351
TM="$ROOT/docs/architecture/2026-09-25-factory-v3-2-threat-model.md"; SP="$ROOT/docs/specs/2026-09-25-factory-v3-2-design.md"
r5=$(grep -E '^\| dfe-5 \|' "$TM" 2>/dev/null || true)
factory_doc_ck "dfe-5: on a reviewed commit's tag only image and prune elevate; smoke before login; reuse on a re-run; superseded-only deletion; delivered in P6 and P7 (R8)" "$TM" \
  bash -c 'for w in "image" "packages: write" "reviewed commit" "superseded" "untagged" "reuses" "GitHub Environments"; do grep -qF "$w" <<<"$1" || exit 1; done; grep -qE "\| P6, P7 \(R8\) \|$" <<<"$1"' _ "$r5"
factory_doc_ck "a residual says GHCR is proved only by an instance's ship, directly above the release-gates residual (R35)" "$TM" python3 - "$TM" <<'PY'
import sys
L = [l for l in open(sys.argv[1]).read().splitlines() if l.startswith("- **")]
i = next(n for n, l in enumerate(L) if "GHCR is proved only by an instance's ship" in l)
assert "Release gates run at PR time and are replayed at the tag" in L[i + 1], L[i + 1]
PY
a6=$(awk '/^---$/{n++; next} n==1' "$SP" 2>/dev/null | grep -F 'P6 builds (lanes' || true)
factory_doc_ck "the spec's P6 builds entry carries Build 4's sentence (R20: GHCR, the superseded version, the deploy contract)" "$SP" \
  bash -c 'for w in "Build 4 (python; R20):" "GHCR" "superseded" "deploy-local.sh"; do grep -qF -- "$w" <<<"$1" || exit 1; done' _ "$a6"
# Final review, findings 2–5, and PR #57 fix wave 1, items 1–4 and 9 (REQ-351, REQ-390; dfe-5; art-threat-driven-security):
# dfe-5 says what the code does — "no such manifest" as an exact rule (its five strings), any other failure fail closed, no
# registry read before a first release's push, every digest checked as a whole string, the build of record from a clean
# release commit, the push's own digest checked against the read-back, the wheel alone on the pinned base, the deploy
# test's PATH, the consumer running the image by digest — and the residuals carry the base image's re-pin, the deploy
# test's limits and the image's root user, each with an owner, a date and a computed CVSS.
# Covers: REQ-390
factory_doc_ck "dfe-5 as fixed: the exact 'no such manifest' rule, any other failure fail closed, no read before a first release's push, digests validated, a clean release-commit build, the push's digest read back equal, the wheel alone, the deploy test's PATH, deploy by digest" "$TM" \
  bash -c 'for w in "\`ERROR: <ref>: not found\`" "\`ERROR: <ref>: manifest unknown\`" "\`ERROR: manifest unknown\`" "\`ERROR: <ref>: MANIFEST_UNKNOWN: manifest unknown\`" "\`ERROR: MANIFEST_UNKNOWN: manifest unknown\`" "any other failure" "fails the job closed" "a first release" "\`sha256:<64 hex>\`" "\`RELEASE_COMMIT\`" "\`--no-cache\`" "the digest the push itself printed" "\`RepoDigests\`" "must equal it" "\`pip install --no-deps --no-index\`" "\`pip check\`" "a fixed allowlist" "\`deploy-local.sh\`" "@<digest>"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "an authorisation failure first" <<<"$1" && ! grep -qF "only \`manifest unknown\` or buildx" <<<"$1"' _ "$r5"
factory_doc_ck "the python image residual is closed by P7 Build 1 (non-root, hash-pinned runtime lock); what stays is named" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "- **The python image" "$1"); grep -qF "closed by P7 Build 1" <<<"$l" && grep -qF "USER 10001" <<<"$l" && grep -qF "requirements-runtime.txt" <<<"$l" && grep -qF -- "--only-binary :all:" <<<"$l" && grep -qF "ships no wheel" <<<"$l" && ! grep -qF "expires: 2026-10-12" <<<"$l"' _ "$TM"
factory_doc_ck "dfe-5's row: the build context holds the Dockerfile, the runtime lock and the one wheel; only hash-pinned files download at tag time" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "| dfe-5 |" "$1"); grep -qF "requirements-runtime.txt" <<<"$l" && grep -qF -- "--require-hashes --no-deps --only-binary :all:" <<<"$l" && grep -qF "build isolation" <<<"$l" && ! grep -qF "holding only the committed \`Dockerfile\` and the release'"'"'s one wheel" <<<"$l"' _ "$TM"
factory_doc_ck "residuals above the GHCR one: the base image re-pinned by hand and the deploy test's limits — owner, date, CVSS as cvss4.py scores it" "$TM" python3 - "$TM" "$ROOT/scripts/lib/specflow" <<'PY'
import sys
sys.path.insert(0, sys.argv[2]); import cvss4
L = [l for l in open(sys.argv[1]).read().splitlines() if l.startswith("- **")]
g = next(n for n, l in enumerate(L) if "GHCR is proved only by an instance's ship" in l)
base = next(l for l in L if l.startswith("- **The python image's base is re-pinned by hand**"))
dep = next(l for l in L if l.startswith("- **The deploy contract's test runs an instance's deploy scripts**"))
assert L.index(base) < g and L.index(dep) < g, "above the GHCR residual"
for l, v in ((base, "CVSS:4.0/AV:N/AC:H/AT:P/PR:N/UI:N/VC:L/VI:L/VA:L/SC:N/SI:N/SA:N"), (dep, "CVSS:4.0/AV:L/AC:L/AT:P/PR:H/UI:A/VC:N/VI:H/VA:H/SC:N/SI:N/SA:N")):
    assert "owner: kpingali123" in l and "expires: 2027-01-31; re-dated 2026-10-05 by the post-3.2.1 records patch to the 3.2.1 disposition's date (`docs/security/3.2.1-disposition.md`), from 2026-11-15" in l, l
    assert f"`{v}` ({cvss4.score(v)}, {cvss4.finding_severity(v)}" in l, (v, cvss4.score(v))
assert "/retrospective" in base and "2027-02-13" in base and "Dependabot" in base
assert "absolute path" in dep and "DRY_RUN=1" in dep
PY
ck "/retrospective's pinned-download bump lists the python image's base digest (Dockerfile), with an owner and a deadline" \
  bash -c 'l=$(tr "\n" " " < "$1"); grep -qF "python:3.12-slim" <<<"$l" && grep -qF "docker buildx imagetools inspect python:3.12-slim" <<<"$l" && grep -qF "stacks/python/Dockerfile" <<<"$l"' _ "$ROOT/.claude/commands/retrospective.md"
# Final review, finding 6 (REQ-351; art-specification-primacy): R35 and Task 4.4 say Build 4 carries PR #56's run-1 fold —
# its files listed — and how the second-merging build's interim-window edit meets it; R20 and the Interfaces say what
# release-image.sh does now.
P6P="$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
factory_doc_ck "the P6 plan's R35: Build 4 also carries PR #56's run-1 fold, its files listed, the interim-window paragraph and its pin left as main has them" "$P6P" \
  bash -c 'l=$(grep -F -- "- **Build 4 also carries PR #56'"'"'s verifier run-1 fold" "$1"); for w in "e15fbb7" "f28713b" "\`.github/PULL_REQUEST_TEMPLATE.md\`" "\`.claude/skills/verifier/SKILL.md\`" "\`.claude/rules/review-gate.md\`" "\`scripts/lib/specflow/attestation.py\`" "\`tests/governance/test_threat_model_current.sh\`" "\`tests/governance/test_spec_lifecycle.sh\`" "\`.claude/commands/retrospective.md\`" "\`test_onboarding_surface.sh\`" "as \`main\` has them" "interim-window edit"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ "$P6P"
factory_doc_ck "the P6 plan's Task 4.4: Step 4's name-only list is Build 4's column plus R35's fold list" "$P6P" \
  bash -c 'grep -qF "lists only Build 4'"'"'s column of the table \"Build 4 ∩ Build 5\" plus the fold'"'"'s files R35 lists" "$1"' _ "$P6P"
# PR #57 fix wave 1, items 1–5, 8 and 10 (REQ-351, REQ-390; art-specification-primacy): R19, R20, R35 and the Interfaces
# say what the scripts do now — the exact rule, the first release, the validated digests, the build of record, the
# prune's warnings, the deploy contract by digest, the smoke's flags — and R35's footnote names the files outside the table.
factory_doc_ck "the P6 plan's R20 and Interfaces: the exact 'no such manifest' rule; no read before a first release's push; the push's digest checked against the read-back; the wheel alone" "$P6P" \
  bash -c '! grep -qF "only \`manifest unknown\` or buildx" "$1" && for k in "- **R20 — python (H20).**" "**\`scripts/release-image.sh <prior|build|publish>"; do l=$(grep -F -- "$k" "$1"); for w in "\`ERROR: <ref>: not found\`" "\`ERROR: MANIFEST_UNKNOWN: manifest unknown\`" "a first release" "\`RELEASE_COMMIT\`" "--no-cache" "the digest the push printed" "read-back"; do grep -qF -- "$w" <<<"$l" || { echo "$k: missing $w"; exit 1; }; done; done; grep -F -- "- **R20 — python (H20).**" "$1" | grep -qF "\`--no-deps --no-index\`"' _ "$P6P"
factory_doc_ck "the P6 plan's Interfaces: the prune warns on every GitHub failure; the deploy contract runs by digest, rolls back below the running label, DEPLOY_RUN_ARGS, DRY_RUN prints every command" "$P6P" \
  bash -c 'p=$(grep -F -- "**\`scripts/release-ghcr-prune.sh --owner" "$1"); d=$(grep -F -- "**Deploy contract** (Task 4.2; REQ-351)." "$1"); for w in "429" "5xx" "an unreadable listing" "only bad arguments"; do grep -qF -- "$w" <<<"$p" || { echo "prune: missing $w"; exit 1; }; done; for w in "by digest" "\`DEPLOY_DIGEST\`" "\`DEPLOY_RUN_ARGS\`" "\`org.opencontainers.image.version\`" "the release before the one running now" "never sets \`-euo pipefail\` in the caller" "\`docker rm\` included"; do grep -qF -- "$w" <<<"$d" || { echo "deploy: missing $w"; exit 1; }; done; ! grep -qF "redeploys the previous \`vX.Y.Z\` tag" <<<"$d"' _ "$P6P"
factory_doc_ck "the P6 plan's R19 notes the python smoke's --network none --pull never (a Build 3 file, only those flags); R35's footnote names the corrections commit's two tests and the smoke files" "$P6P" \
  bash -c 'r=$(grep -F -- "- **R19 — the template" "$1"); grep -qF "\`docker run --network none --pull never\`" <<<"$r" && grep -qF "Build 3 file" <<<"$r" && f=$(grep -F -- "*Not in the table — Build 4'"'"'s corrections" "$1") && for w in "\`e15fbb7\`" "\`tests/governance/test_threat_model_current.sh\`" "\`tests/governance/test_spec_lifecycle.sh\`" "sanctioned by that fold" "neither is a Build 5 file" "\`scripts/release-smoke.sh\`" "\`tests/governance/test_release_smoke.sh\`"; do grep -qF -- "$w" <<<"$f" || { echo "missing $w"; exit 1; }; done' _ "$P6P"
# PR #57 fix wave 1 round 2 (REQ-351; dfe-5; art-specification-primacy): "no earlier published Release records an image"
# is what prior checks — dfe-5, R20 and the Interfaces say it walks every published Release in the listing, newest first,
# until one records an image, and none says only the newest other Release is read.
# Covers: REQ-351
factory_doc_ck "dfe-5, the P6 plan's R20 and Interfaces: a first release is decided by walking every published Release in the listing, newest first" "$P6P" \
  bash -c 'for l in "$(grep -E "^\| dfe-5 \|" "$2")" "$(grep -F -- "- **R20 — python (H20).**" "$1")" "$(grep -F -- "**\`scripts/release-image.sh <prior|build|publish>" "$1")"; do for w in "every published Release" "\`gh release list --limit 100\`" "newest first"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done; ! grep -qF "the newest other published Release (\`gh release list\`) records no image" <<<"$l" || exit 1; done' _ "$P6P" "$TM"
finish test_release_python
