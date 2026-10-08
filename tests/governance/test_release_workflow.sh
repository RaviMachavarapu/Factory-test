#!/usr/bin/env bash
# REQ-384 (P6 R15, R26): release-build.yml builds the reproducible subset on every ship PR (and on workflow_dispatch) from a
# fresh checkout of the PR head, reads no secret, and uploads it as release-dist-<version>. REQ-334: SHA-pinned actions,
# a read-only top-level permissions block, no job elevation, every expression that reaches run: through env.
# Covers: REQ-384
# Covers: REQ-334
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
RB=.github/workflows/release-build.yml
job() { awk -v j="  $2:" '$0==j{f=1; print; next} f && /^  [a-z]/{f=0} f' "$1"; }
no_expr_in_run() { python3 - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines(); i = 0; bad = []
while i < len(lines):
    m = re.match(r"^(\s*)(- )?run: ?(.*)$", lines[i])
    if not m:
        i += 1; continue
    ind = len(m.group(1)) + (2 if m.group(2) else 0); block = [m.group(3)]; i += 1
    while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > ind):
        block.append(lines[i]); i += 1
    if any("$" + "{{" in l for l in block):
        bad.append(block[0])
assert not bad, bad
PY
}
ck "$RB exists and actionlint accepts it" bash -c 'test -f "$1" && { ! command -v actionlint >/dev/null || actionlint "$1"; }' _ "$RB"
ck "$RB: on pull_request with no branch filter, and workflow_dispatch with a version input" python3 - "$RB" <<'PY'
import sys
t = open(sys.argv[1]).read(); on = t[t.index("\non:"):t.index("\npermissions:")]
assert "pull_request:" in on and "branches:" not in on and "workflow_dispatch:" in on and "version:" in on, on
PY
j=$(job "$RB" release-build)
ck "$RB: job release-build runs for ship/ heads, phase/release, or a dispatch" \
  bash -c 'grep -qF "startsWith(github.head_ref, '"'"'ship/'"'"')" <<<"$1" && grep -qF "github.head_ref == '"'"'phase/release'"'"'" <<<"$1" && grep -qF "github.event_name == '"'"'workflow_dispatch'"'"'" <<<"$1"' _ "$j"
ck "$RB: on ubuntu-24.04 (pinned), checking out the PR head SHA with fetch-depth 0, never the merge ref" \
  bash -c 'grep -qE "runs-on: ubuntu-24\.04" <<<"$1" && grep -qF "github.event.pull_request.head.sha" <<<"$1" && grep -qF "fetch-depth: 0" <<<"$1"' _ "$j"
ck "$RB: reads no secret, never elevates, read-only at the top" \
  bash -c '! grep -qF "secrets." "$1" && ! grep -qE "^[[:space:]]+[a-z-]+:[[:space:]]*write" "$1" && grep -qE "^permissions:" "$1"' _ "$RB"
ck "$RB: the stack's hook through packinfo.py with RELEASE_PARTS reproducible; release-dist-<version> uploaded by a pinned action" \
  bash -c 'grep -qF "RELEASE_PARTS: reproducible" "$1" && grep -qF "packinfo.py --root . --ref \"\$base\" stack" "$1" && grep -qF "release-dist-" "$1" && grep -qE "uses: actions/upload-artifact@[0-9a-f]{40} # v[0-9]" "$1"' _ "$RB"
ck "$RB: no GitHub expression inside a run: block (every value reaches run: through env:)" no_expr_in_run "$RB"
every_job() { python3 - "$1" "$2" <<'PY'
import re, sys
body = open(sys.argv[1]).read().split("\njobs:\n", 1)[1]
parts = re.split(r"(?m)^  ([a-z][a-z-]*):\n", body)[1:]
bad = [n for n, b in zip(parts[::2], parts[1::2]) if not re.search(sys.argv[2], b)]
assert not bad, bad
PY
}
ck "$RB: every job declares timeout-minutes (F34)" every_job "$RB" '(?m)^    timeout-minutes: [0-9]+$'
ck "$RB: every actions/checkout sets persist-credentials: false — no token in .git/config (F9, F21)" python3 - "$RB" <<'PY'
import re, sys
t = open(sys.argv[1]).read(); steps = re.split(r"(?m)^      - ", t)
co = [s for s in steps if re.match(r"(name: [^\n]*\n\s*)?uses: actions/checkout@", s)]
assert co and all(re.search(r"(?m)^\s+persist-credentials: false$", s) for s in co), co
PY
ck "$RB: the reproducible subset uses setup-python with the pack's python_version and scripts/requirements.txt, never the stack toolchain (F35)" \
  bash -c 'grep -qE "uses: actions/setup-python@[0-9a-f]{40}" "$1" && grep -qF "packinfo.py --root . --ref \"\$base\" get python_version" "$1" && grep -qF -- "--require-hashes -r scripts/requirements.txt" "$1" && ! grep -qF "./.github/actions/toolchain" "$1"' _ "$RB"
# Build 2 final review (REQ-384, REQ-334; P6 R15): the "Read the governing pack" and "Resolve the version" steps are
# executable shell, so they are run here — each step's run: body extracted and executed in a scratch repository with the
# env the workflow gives it — never only grepped. The version is validated as a whole string (a multi-line dispatch input
# would otherwise pass a line-by-line grep and inject GITHUB_OUTPUT lines); the regulated path's phase/release head reads
# origin/<base> from the checkout (fetch-depth: 0) and never fetches (persist-credentials: false leaves no credentials, so
# a fetch from a private repository fails); a packinfo.py failure stops the step; the stack is read at the base ref.
# Covers: REQ-384
# Covers: REQ-334
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
step_body "$RB" "Read the governing pack (python_version, stack)" > "$W/pack.sh"
step_body "$RB" "Resolve the version" > "$W/version.sh"
ck "the two steps' run: bodies extract" bash -c 'grep -q "packinfo.py" "$1" && grep -q "GITHUB_OUTPUT" "$2"' _ "$W/pack.sh" "$W/version.sh"
# A template-source scratch repository: main carries scripts/lib and a scripts/template-pack.yml of its own (written here,
# never copied: an instance has none — init removes it — and this test ships to instances, fix wave 1: PR #54's First run
# jobs failed on the copy); its origin is then moved to a path that does not exist, as a credential-less fetch from a
# private repository fails; origin/main stays.
S="$W/scratch"; mkdir -p "$S"
(cd "$S" && git init -q -b main && mkdir -p scripts && cp -R "$ROOT/scripts/lib" scripts/ && find scripts -name __pycache__ -prune -exec rm -rf {} + \
  && printf 'stack: template\npython_version: "3.12"\n' > scripts/template-pack.yml && git add -A && git commit -qm base)
git clone -q "$S" "$W/c"; C="$W/c"; git -C "$C" remote set-url origin "$W/nowhere.git"
(cd "$C" && git checkout -qb phase/release && mkdir -p docs/releases && printf -- '---\ndate: 2026-10-05\n---\n' > docs/releases/1.2.3-notes.md \
  && git add -A && git commit -qm "release docs (REQ-384)")
# Build 2 re-review (REQ-384; P6 R15): fetch-depth: 0 brings tags too, and a tag literally named origin/main outranks the
# remote-tracking ref in a short-name lookup (git warns "refname is ambiguous" and takes the tag), so whoever can push such
# a tag would pick the pack and the notes diff. The decoy tag names a child of the release-docs commit carrying another
# pack (stack decoy, python 3.9): read through it, the pack step reports that stack and the version step's diff is empty.
# Every step below must still resolve the branch, refs/remotes/origin/<base>.
# Covers: REQ-384
(cd "$C" && git checkout -q -b decoy && printf 'stack: decoy\npython_version: "3.9"\n' > scripts/template-pack.yml \
  && git commit -qam "a decoy pack (REQ-384)" && git tag origin/main && git checkout -q phase/release && git branch -q -D decoy)
runstep() {  # runstep SCRIPT VAR=VALUE... — the step body under bash in $C; rc, out and $W/out (its GITHUB_OUTPUT)
  : > "$W/out"; rc=0; out=$(cd "$C" && env -i PATH="$PATH" HOME="$HOME" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GITHUB_OUTPUT="$W/out" GITHUB_STEP_SUMMARY="$W/summary" "${@:2}" bash -e "$1" 2>&1) || rc=$?; }
H=$(git -C "$C" rev-parse HEAD)
runstep "$W/pack.sh" BASE_REF=main DEFAULT_BRANCH=main
ck "pack step (template source, a PR to main), a tag named origin/main present: base=refs/remotes/origin/main, python_version from the branch's pack, release_stack=template" \
  bash -c '[ "$1" = 0 ] && grep -qx "base=refs/remotes/origin/main" "$2" && grep -qx "python_version=3.12" "$2" && grep -qx "release_stack=template" "$2"' _ "$rc" "$W/out"
PB=$(sed -n 's/^base=//p' "$W/out")
runstep "$W/pack.sh" BASE_REF= DEFAULT_BRANCH=main
ck "pack step on a dispatch (no base_ref): the repository's default branch is the base" bash -c '[ "$1" = 0 ] && grep -qx "base=refs/remotes/origin/main" "$2" && grep -qx "release_stack=template" "$2"' _ "$rc" "$W/out"
(cd "$C" && printf 'stack: python\n' > .specflow.yml && git add .specflow.yml && git commit -qm "an instance marker (REQ-384)")
runstep "$W/pack.sh" BASE_REF=main DEFAULT_BRANCH=main
ck "pack step: a head that adds .specflow.yml cannot swap the stack — instance-ness and the pack are read at the base" \
  bash -c '[ "$1" = 0 ] && grep -qx "release_stack=template" "$2"' _ "$rc" "$W/out"
(cd "$C" && git rm -q .specflow.yml && git commit -qm "drop the marker (REQ-384)")
runstep "$W/pack.sh" BASE_REF=nope DEFAULT_BRANCH=main
ck "pack step: a base the checkout lacks fails the step, writing nothing" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$W/out"
git -C "$C" update-ref refs/remotes/origin/bare "$(git -C "$C" commit-tree -m bare "$(git -C "$C" mktree </dev/null)")"
runstep "$W/pack.sh" BASE_REF=bare DEFAULT_BRANCH=main
ck "pack step: packinfo.py failing at the base (no scripts/template-pack.yml there) fails the step — no empty python_version" \
  bash -c '[ "$1" != 0 ] && ! grep -q "^python_version=" "$2" && ! grep -q "^release_stack=" "$2"' _ "$rc" "$W/out"
# Fix wave 1 (REQ-384; P6 R15, R35): a pack without python_version prints an empty value with exit 0 (packinfo.py get), so
# the step itself refuses an empty python_version — setup-python given "" would use whatever Python is on PATH; and every
# app-stack instance's pack, read at the base, now carries one.
# Covers: REQ-384
(cd "$C" && git checkout -q -b nopy refs/remotes/origin/main && printf 'stack: template\n' > scripts/template-pack.yml && git commit -qam "a pack without python_version (REQ-384)" \
  && git update-ref refs/remotes/origin/nopy HEAD && git checkout -q phase/release && git branch -q -D nopy)
runstep "$W/pack.sh" BASE_REF=nopy DEFAULT_BRANCH=main
ck "pack step: a governing pack with no python_version fails the step, naming the key — never an empty setup-python input" \
  bash -c '[ "$1" != 0 ] && ! grep -q "^python_version=" "$2" && grep -qF "python_version" <<<"$3"' _ "$rc" "$W/out" "$out"
for s in tauri flutter; do
  if [ ! -f "$ROOT/stacks/$s/pack.yml" ]; then echo "SKIP: stacks/$s/pack.yml (init removes stacks/)"; continue; fi
  (cd "$C" && git checkout -q -b "inst-$s" refs/remotes/origin/main && mkdir -p .specflow && printf 'stack: %s\n' "$s" > .specflow.yml \
    && cp "$ROOT/stacks/$s/pack.yml" .specflow/pack.yml && git add -A && git commit -qm "a $s instance (REQ-384)" \
    && git update-ref "refs/remotes/origin/inst-$s" HEAD && git checkout -q phase/release && git branch -q -D "inst-$s")
  runstep "$W/pack.sh" BASE_REF="inst-$s" DEFAULT_BRANCH=main
  ck "pack step, a $s instance at the base: python_version from its pack, release_stack=$s" \
    bash -c '[ "$1" = 0 ] && grep -qE "^python_version=3\.[0-9]+" "$2" && grep -qx "release_stack=$3" "$2"' _ "$rc" "$W/out" "$s"
done
ck "$RB: no git fetch anywhere (persist-credentials: false leaves no credentials; fetch-depth: 0 already holds origin/<base>)" \
  bash -c '! grep -qE "git[[:space:]]+fetch" "$1"' _ "$RB"
ck "$RB: the upload states retention-days: 90 (90 days, the public-repository maximum; a private repository may allow up to 400)" grep -qE '^          retention-days: 90$' "$RB"
ck "$RB: a dispatch's concurrency group includes its version input (two versions on one ref never cancel each other)" \
  bash -c 'g=$(grep -E "^  group: " "$1"); grep -qF "inputs.version" <<<"$g" && grep -qF "github.event.pull_request.number" <<<"$g"' _ "$RB"
H=$(git -C "$C" rev-parse HEAD)
runstep "$W/version.sh" EVENT_NAME=pull_request HEAD_REF=phase/release BASE_REF=main BASE="$PB" HEAD_SHA="$H" INPUT_VERSION=
ck "version step, regulated phase/release head, origin unreachable, a tag named origin/main present: no fetch — the pack step's base (refs/remotes/origin/<base>) from the checkout; version 1.2.3, not a dry run" \
  bash -c '[ "$1" = 0 ] && grep -qx "version=1.2.3" "$2" && grep -qx "dry_run=false" "$2"' _ "$rc" "$W/out"
(cd "$C" && git checkout -q -b ship/1.2.3)
runstep "$W/version.sh" EVENT_NAME=pull_request HEAD_REF=ship/1.2.3 BASE_REF=main BASE="$PB" HEAD_SHA="$H" INPUT_VERSION=
ck "version step, lanes ship/1.2.3 head: version 1.2.3" bash -c '[ "$1" = 0 ] && grep -qx "version=1.2.3" "$2" && grep -qx "dry_run=false" "$2"' _ "$rc" "$W/out"
runstep "$W/version.sh" EVENT_NAME=workflow_dispatch HEAD_REF= BASE_REF= BASE="$PB" HEAD_SHA="$H" INPUT_VERSION=9.9.9
ck "version step, a dispatch with no notes for its version: a dry run whose epoch is the head commit's committer date" \
  bash -c '[ "$1" = 0 ] && grep -qx "version=9.9.9" "$2" && grep -qx "dry_run=true" "$2" && grep -qx "epoch=$(git -C "$3" log -1 --format=%ct "$4")" "$2"' _ "$rc" "$W/out" "$C" "$H"
runstep "$W/version.sh" EVENT_NAME=workflow_dispatch HEAD_REF= BASE_REF= BASE="$PB" HEAD_SHA="$H" INPUT_VERSION=$'1.2.3\ndry_run=false'
ck "version step: a multi-line dispatch input fails before any use and writes no GITHUB_OUTPUT line (no injected key)" \
  bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$rc" "$W/out"
runstep "$W/version.sh" EVENT_NAME=workflow_dispatch HEAD_REF= BASE_REF= BASE="$PB" HEAD_SHA="$H" INPUT_VERSION=1.2
ck "version step: a dispatch input that is not X.Y.Z fails, writing nothing" bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$rc" "$W/out"
(cd "$C" && git checkout -q -b phase/release-2 main 2>/dev/null || git checkout -q -b phase/release-2 refs/remotes/origin/main)
runstep "$W/version.sh" EVENT_NAME=pull_request HEAD_REF=phase/release BASE_REF=main BASE="$PB" HEAD_SHA="$(git -C "$C" rev-parse HEAD)" INPUT_VERSION=
ck "version step: a phase/release head that changes no docs/releases/<v>-notes.md fails, writing nothing" bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$rc" "$W/out"
# Build 2 fix wave 2 (REQ-384; PR #54 verifier run 1, code-mode low): a phase/release head whose diff changes more than
# one version's notes is refused with a message naming them — never the first one taken silently.
# Covers: REQ-384
(cd "$C" && git checkout -q phase/release && git checkout -q -b phase/release-3 && printf -- '---\ndate: 2026-10-06\n---\n' > docs/releases/1.2.4-notes.md \
  && git add -A && git commit -qm "a second version's notes (REQ-384)")
runstep "$W/version.sh" EVENT_NAME=pull_request HEAD_REF=phase/release BASE_REF=main BASE="$PB" HEAD_SHA="$(git -C "$C" rev-parse HEAD)" INPUT_VERSION=
ck "version step: a phase/release head changing two versions' notes (1.2.3, 1.2.4) fails naming both, writing nothing" \
  bash -c '[ "$1" = 1 ] && [ ! -s "$2" ] && grep -qF "1.2.3" <<<"$3" && grep -qF "1.2.4" <<<"$3" && grep -qF "more than one" <<<"$3"' _ "$rc" "$W/out" "$out"

# P6 Task 3.4 (REQ-350, REQ-383, REQ-384; P6 R15, R27, R28, R30, R31, R34, R35): release.yml on a v* tag, or dispatched on
# one — the tag name validated, the tag object re-fetched, the ancestry, the anchor, the markers since the previous
# release, the release checks and the tag's signature at the tag; a clean build of verify's commit compared with the
# tagged notes; every stack job a thin shell over the release action; a draft Release with every artifact and
# manifest.json, published only once complete, refused when the tag moved. REQ-334: only publish (contents) and image and
# prune (packages) elevate — no write-all, no id-token; no secret outside signing-probe and sign; no persisted token; no
# cache; every job bounded.
# Covers: REQ-350
# Covers: REQ-383
RY=.github/workflows/release.yml
ck "$RY exists and actionlint accepts it" bash -c 'test -f "$1" && { ! command -v actionlint >/dev/null || actionlint "$1"; }' _ "$RY"
ck "$RY: on push of tags v*, and workflow_dispatch (no branch filter, never pull_request) — R34" python3 - "$RY" <<'PY'
import sys
t = open(sys.argv[1]).read(); on = t[t.index("\non:"):t.index("\npermissions:")]
assert "push:" in on and "tags:" in on and "'v*'" in on and "workflow_dispatch:" in on, on
assert "pull_request" not in on and "branches:" not in on, on
PY
v=$(job "$RY" verify)
ck "verify: the tag name and the ref type reach shell through env only; the dispatch is accepted only on a tag ref (R34)" \
  bash -c 'grep -qF "TAG: " <<<"$1" && grep -qF "github.ref_name" <<<"$1" && grep -qF "REF_TYPE: " <<<"$1" && grep -qF "github.ref_type" <<<"$1" && grep -qF "^v[0-9]+\.[0-9]+\.[0-9]+\$" <<<"$1"' _ "$v"
ck "verify: fetch-depth 0, the tag object re-fetched, main and the PR heads fetched, refs/tags/\$TAG^{commit} a first-parent commit of origin/main" \
  bash -c 'grep -qF "fetch-depth: 0" <<<"$1" && grep -qF "git fetch --force --no-tags origin \"+refs/tags/\$TAG:refs/tags/\$TAG\"" <<<"$1" && grep -qF "refs/pull/*/head" <<<"$1" && grep -qF "refs/tags/\$TAG^{commit}" <<<"$1" && grep -qF "git rev-list --first-parent refs/remotes/origin/main" <<<"$1"' _ "$v"
ck "verify: release-check --version, then verify-release.sh --at-tag (which skips the build; no SPECFLOW_RELEASE_BUILD, ignored in CI) with the base by its full ref; never run-quality-gates.sh or a deploy hook" \
  bash -c 'grep -qF "attestation.py release-check" <<<"$1" && grep -qF -- "--version" <<<"$1" && grep -qF -- "--at-tag" <<<"$1" && ! grep -qF "SPECFLOW_RELEASE_BUILD" <<<"$1" && grep -qF "SPECFLOW_BASE_REF: refs/remotes/origin/main" <<<"$1" && ! grep -qF "run-quality-gates.sh" "$2" && ! grep -qE "deploy-[a-z]+\.sh" "$2"' _ "$v" "$RY"
ck "verify: reads PRs and comments, writes nothing" bash -c 'grep -qE "pull-requests: read" <<<"$1" && grep -qE "issues: read" <<<"$1" && ! grep -qE ":[[:space:]]*write" <<<"$1"' _ "$v"
b=$(job "$RY" build-source)
ck "build-source: checks out verify's commit (never the tag name), setup-python, RELEASE_PARTS reproducible, --artifacts-only, the template smoke" \
  bash -c 'grep -qE "uses: actions/checkout@[0-9a-f]{40}" <<<"$1" && grep -qF "needs.verify.outputs.commit" <<<"$1" && grep -qF "RELEASE_PARTS: reproducible" <<<"$1" && grep -qF -- "--artifacts-only" <<<"$1" && grep -qF "release-smoke.sh" <<<"$1" && ! grep -qF "./.github/actions/toolchain" <<<"$1"' _ "$b"
ck "$RY: no job restores a cache — build-source's archive is the artifact of record (the app action caches registries only, R15)" \
  no grep -qE 'uses: actions/cache[@/]' "$RY"
p=$(job "$RY" publish)
ck "publish: contents: write, verify's commit, release-publish.sh --commit — gh release create, no third-party release action" \
  bash -c 'grep -qE "contents: write" <<<"$1" && grep -qF "needs.verify.outputs.commit" <<<"$1" && grep -qF "release-publish.sh" <<<"$1" && grep -qF -- "--commit" <<<"$1" && ! grep -qiE "uses: [^ ]*(release-action|action-gh-release|create-release)" "$2"' _ "$p" "$RY"
ck "publish: needs every build job, runs when they are skipped and never after a failure; each part downloaded only when its job succeeded" \
  bash -c 'for n in build-source image bundle sign verify-signed; do grep -qF "$n" <<<"$1" || exit 1; done; grep -qF "!failure()" <<<"$1" && grep -qF "!cancelled()" <<<"$1" && grep -qF "needs.image.result == '"'"'success'"'"'" <<<"$1" && grep -qF "needs.verify-signed.result == '"'"'success'"'"'" <<<"$1"' _ "$p"
ck "$RY: read-only at the top; only publish (contents) and image and prune (packages) elevate; no write-all, no id-token (REQ-334)" python3 - "$RY" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
top = t[t.index("\npermissions:"):t.index("\njobs:")]
assert re.findall(r"(?m)^  ([a-z-]+):\s*(\S+)\s*$", top) == [("contents", "read")], top
assert not re.search(r"(?m)^\s*permissions:\s*write-all\s*$", t), "write-all"
assert not re.search(r"(?m)^\s*id-token:\s*write\s*$", t), "id-token: write"
body = t.split("\njobs:\n", 1)[1]
parts = re.split(r"(?m)^  ([a-z][a-z-]*):\n", body)[1:]
w = {n: set(re.findall(r"(?m)^\s+([a-z-]+):\s*write\s*$", b)) for n, b in zip(parts[::2], parts[1::2])}
assert w.get("publish") == {"contents"}, w
assert w.get("image") == {"packages"} and w.get("prune") == {"packages"}, w
assert all(not s for n, s in w.items() if n not in ("publish", "image", "prune")), w
PY
ck "$RY: secrets. appears only in signing-probe and sign" python3 - "$RY" <<'PY'
import re, sys
body = open(sys.argv[1]).read().split("\njobs:\n", 1)[1]
parts = re.split(r"(?m)^  ([a-z][a-z-]*):\n", body)[1:]
bad = [n for n, b in zip(parts[::2], parts[1::2]) if "secrets." in b and n not in ("signing-probe", "sign")]
assert not bad, bad
PY
ck "$RY: every job declares timeout-minutes (F34)" every_job "$RY" '(?m)^    timeout-minutes: [0-9]+$'
ck "$RY: every actions/checkout sets persist-credentials: false (F9, F21)" python3 - "$RY" <<'PY'
import re, sys
t = open(sys.argv[1]).read(); steps = re.split(r"(?m)^      - ", t)
co = [s for s in steps if re.match(r"(name: [^\n]*\n\s*)?uses: actions/checkout@", s)]
assert len(co) >= 8 and all(re.search(r"(?m)^\s+persist-credentials: false$", s) for s in co), co
PY
ck "$RY: no GitHub expression inside a run: block" no_expr_in_run "$RY"
ck "$RY: never macos-latest" no grep -qF 'macos-latest' "$RY"
# R35: the six stack jobs are thin shells — guarded by verify's stack output, calling the release action with a fixed part.
for jp in "image python image-prior" "image python image-build" "image python image-publish" "prune python prune" \
          "bundle tauri bundle" "bundle flutter bundle" "sign tauri sign" "verify-signed flutter verify-signed"; do
  set -- $jp; jb=$(job "$RY" "$1")
  ck "$1: guarded by stack $2, checks out verify's commit, calls ./.github/actions/release with part: $3 (R35)" \
    bash -c 'grep -qF "needs.verify.outputs.stack == '"'"'$2'"'"'" <<<"$1" && grep -qF "needs.verify.outputs.commit" <<<"$1" && grep -qF "uses: ./.github/actions/release" <<<"$1" && grep -qE "^ +part: $3\$" <<<"$1"' _ "$jb" "$2" "$3"
done
set --
i=$(job "$RY" image)
ck "image: packages: write; the prior read, then build and smoke with no token, then the login (actor, job token), then publish (F23)" python3 -c '
import re, sys; j = sys.argv[1]
assert re.search(r"packages: write", j) and re.search(r"uses: docker/login-action@[0-9a-f]{40} # v[0-9]", j), j
assert "registry: ghcr.io" in j and "github.actor" in j and "github.token" in j, j
idx = [j.index(w) for w in ("part: image-prior", "part: image-build", "docker/login-action", "part: image-publish")]
assert idx == sorted(idx), idx
build = j[idx[1]:idx[2]]; assert "token" not in build, "the build-and-smoke step carries no token"' "$i"
ck "prune: its own job after publish, packages: write" \
  bash -c 'grep -qE "needs: \[?[^]]*publish" <<<"$1" && grep -qE "packages: write" <<<"$1"' _ "$(job "$RY" prune)"
bj=$(job "$RY" bundle)
ck "bundle: macos-15, no secrets, no environment, the unsigned bundle uploaded" \
  bash -c 'grep -qF "runs-on: macos-15" <<<"$1" && ! grep -qF "secrets." <<<"$1" && ! grep -qF "environment:" <<<"$1" && grep -qF "release-bundle-unsigned" <<<"$1"' _ "$bj"
for jn in signing-probe sign; do
  jb=$(job "$RY" "$jn")
  ck "$jn: environment: release (R32)" grep -qE "^    environment: release$" <<<"$jb"
  for s in APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
    ck "$jn: maps secrets.$s into env" grep -qF "secrets.$s" <<<"$jb"
  done
done
ck "$RY: only signing-probe and sign declare an environment (R32)" python3 - "$RY" <<'PY'
import re, sys
body = open(sys.argv[1]).read().split("\njobs:\n", 1)[1]
parts = re.split(r"(?m)^  ([a-z][a-z-]*):\n", body)[1:]
envs = {n for n, b in zip(parts[::2], parts[1::2]) if re.search(r"(?m)^    environment:", b)}
assert envs == {"signing-probe", "sign"}, envs
PY
ck "$RY: no if: mentions secrets (they are not available there)" no grep -qE '^[[:space:]]*if:.*secrets\.' "$RY"
ck "$RY: no echo or printf of an APPLE_ variable anywhere (the probe outputs only a boolean)" no grep -qE '(echo|printf)[^|>]*\$\{?APPLE_' "$RY"
ck "signing-probe: its body only tests the five variables are non-empty and writes present=" python3 - "$RY" <<'PY'
import re, sys
t = open(sys.argv[1]).read(); i = t.index("      - name: Probe the signing secrets\n")
run = re.search(r"(?m)^        run: \|\n((?:          .*\n|[ \t]*\n)+)", t[i:]).group(1)
assert "set +x" in run and run.count('[ -n "$APPLE_') == 5 and "present=true" in run and "present=false" in run, run
PY
sj=$(job "$RY" sign)
ck "sign: only when signing-probe found all five; the p12 decoded from the environment by python3 into RUNNER_TEMP; the keychain path only; removed always()" \
  bash -c 'grep -qF "needs.signing-probe.outputs.present == '"'"'true'"'"'" <<<"$1" && grep -qF "set +x" <<<"$1" && grep -qF "os.environ[" <<<"$1" && grep -qF "release-signing.keychain-db" <<<"$1" && grep -qF "openssl rand" <<<"$1" && ! grep -qF "login.keychain" <<<"$1" && grep -qF "delete-keychain" <<<"$1" && grep -qF "always()" <<<"$1"' _ "$sj"
ck "sign: the always() step is the one that deletes the keychain" python3 -c '
import re, sys; j = sys.argv[1]
steps = re.split(r"(?m)^      - ", j)
assert any("always()" in s and "delete-keychain" in s for s in steps), steps' "$sj"
vs=$(job "$RY" verify-signed)
ck "verify-signed: macos-15, no secret, no environment, after sign" \
  bash -c 'grep -qF "runs-on: macos-15" <<<"$1" && ! grep -qF "secrets." <<<"$1" && ! grep -qF "environment:" <<<"$1" && grep -qE "needs: \[?[^]]*sign" <<<"$1"' _ "$vs"
# F29: verify's security-critical steps are shell that can run — extracted from the workflow and run, as
# test_workflow_health.sh's vtry runs verifier.yml's step.
vstep() { python3 - "$RY" "$1" <<'PY'
import re, sys, textwrap
t = open(sys.argv[1]).read(); i = t.index("      - name: " + sys.argv[2] + "\n")
m = re.search(r"(?m)^        run: \|\n((?:          .*\n|[ \t]*\n)+)", t[i:])
print(textwrap.dedent(m.group(1)))
PY
}
vstep "Validate the tag name" > "$W/validate.sh"; vstep "Re-fetch the tag object" > "$W/refetch.sh"; vstep "The tag is on main" > "$W/onmain.sh"
vstep "Find the signing anchor" > "$W/anchor.sh"
for bad in "v1.0.0;touch $W/pwned" "v1.0.0\$(touch $W/pwned)" 'v1.0' 'v0.0.1-demo'; do
  : > "$W/gho"; rc=0; (cd "$W" && TAG="$bad" REF_TYPE=tag GITHUB_OUTPUT="$W/gho" bash -e "$W/validate.sh") >/dev/null 2>&1 || rc=$?
  ck "verify's 'Validate the tag name' on '$bad': release=false, exit 0, nothing of the value run" \
    bash -c '[ "$1" = 0 ] && grep -qx "release=false" "$2" && ! grep -q "^version=" "$2" && [ ! -e "$3/pwned" ]' _ "$rc" "$W/gho" "$W"
done
: > "$W/gho"; (cd "$W" && TAG=v1.0.0 REF_TYPE=branch GITHUB_OUTPUT="$W/gho" bash -e "$W/validate.sh") >/dev/null 2>&1 || true
ck "…a dispatch on a branch ref (ref type branch): release=false (R34)" grep -qx "release=false" "$W/gho"
: > "$W/gho"; (cd "$W" && TAG=v1.0.0 REF_TYPE=tag GITHUB_OUTPUT="$W/gho" bash -e "$W/validate.sh") >/dev/null 2>&1 || true
ck "…v1.0.0 on a tag ref: release=true, version=1.0.0" bash -c 'grep -qx "release=true" "$1" && grep -qx "version=1.0.0" "$1"' _ "$W/gho"
O="$W/tagorigin"; git init -q -b main "$O"; (cd "$O" && echo a > f && mkdir -p docs/releases && echo n > docs/releases/1.0.0-notes.md && git add -A && git commit -qm a && git tag -a -m r v1.0.0 \
  && git checkout -q --detach && git commit -q --allow-empty -m "off main" && git tag -a -m r v1.0.1 && git checkout -q main \
  && git checkout -qb feat && git commit -q --allow-empty -m "PR commit 1" && git tag -a -m r v1.0.2 \
  && git commit -q --allow-empty -m "PR commit 2" && git checkout -q main && git merge -q --no-ff feat -m "Merge pull request #2")
co() {  # co TAG — what actions/checkout leaves on a tag push: a depth-1 fetch of the tag's commit as a lightweight ref
  rm -rf "$W/co"; git init -q -b main "$W/co"; git -C "$W/co" remote add origin "file://$O"
  git -C "$W/co" fetch -q --no-tags --depth=1 origin "+$(git -C "$O" rev-parse "$1^{commit}"):refs/tags/$1"; git -C "$W/co" checkout -q "refs/tags/$1"
}
co v1.0.0; ck "a depth-1 checkout of a tag leaves a lightweight ref (what signers.verify would call lightweight)" [ "$(git -C "$W/co" cat-file -t refs/tags/v1.0.0)" = commit ]
rc=0; (cd "$W/co" && TAG=v1.0.0 bash -e "$W/refetch.sh") >/dev/null 2>&1 || rc=$?
ck "…'Re-fetch the tag object' restores the tag object and passes its own cat-file check (F21, F28)" \
  bash -c '[ "$1" = 0 ] && [ "$(git -C "$2" cat-file -t refs/tags/v1.0.0)" = tag ]' _ "$rc" "$W/co"
git -C "$W/co" fetch -q --unshallow origin '+refs/heads/main:refs/remotes/origin/main'   # verify's fetch-depth 0 and its fetch of main
: > "$W/gho"; rc=0; (cd "$W/co" && TAG=v1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/onmain.sh") >/dev/null 2>&1 || rc=$?
ck "…'The tag is on main' for a tag on main: exit 0, commit= the tag's commit" \
  bash -c '[ "$1" = 0 ] && grep -qx "commit=$3" "$2"' _ "$rc" "$W/gho" "$(git -C "$O" rev-parse 'v1.0.0^{commit}')"
# B2: the anchor lookup is its own step — signers.py's ref, '-' for no anchor (exit 3), and a refusal (exit 1) fails it.
mkdir -p "$W/co/scripts/lib/specflow"
printf 'import os, sys\nrc = int(os.environ.get("STUB_RC", "0"))\nprint({0: "anchor: v0.9.0 (previous-release)", 1: "anchor-off-main", 3: "no anchor"}[rc])\nsys.exit(rc)\n' \
  > "$W/co/scripts/lib/specflow/signers.py"
for x in "0 anchor=v0.9.0" "3 anchor=-"; do
  : > "$W/gho"; rc=0; (cd "$W/co" && STUB_RC="${x%% *}" TAG=v1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/anchor.sh") >/dev/null 2>&1 || rc=$?
  ck "'Find the signing anchor' when signers.py exits ${x%% *}: exit 0, ${x#* }" bash -c '[ "$1" = 0 ] && grep -qxF "$3" "$2"' _ "$rc" "$W/gho" "${x#* }"
done
: > "$W/gho"; rc=0; (cd "$W/co" && STUB_RC=1 TAG=v1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/anchor.sh") >/dev/null 2>&1 || rc=$?
ck "…when signers.py refuses (exit 1, anchor-off-main): the step fails — a refusal is a finding, not an absence" \
  bash -c '[ "$1" != 0 ] && ! grep -q "^anchor=" "$2"' _ "$rc" "$W/gho"
# Wave 1 round 2 (REQ-350, REQ-383; P6 R31): the Release body's 'Verify this release' follows the TAG's own verdict, never
# the existence of an anchor (a TOFU anchor exists once allowed_signers lists a key, and an annotated, unsigned tag with
# its fallback recorded still passes --at-tag). 'Read the tag's own signature' runs signers.py verify at tag time (the
# base's revocations included: no --released) and outputs tag_kind — ssh-good (exit 0, its anchor the anchor step's) or
# unsigned (exit 3); any other verdict, or an ssh-good against another anchor, fails the step and outputs nothing.
# Covers: REQ-350
# Covers: REQ-383
vstep "Read the tag's own signature" > "$W/tagsig.sh"
printf 'import os, sys\nopen(os.environ["STUB_ARGV"], "w").write(" ".join(sys.argv[1:]))\nprint(os.environ["STUB_OUT"])\nsys.exit(int(os.environ["STUB_RC"]))\n' \
  > "$W/co/scripts/lib/specflow/signers.py"
tagsig() {  # tagsig RC OUT [ANCHOR]
  : > "$W/gho"; : > "$W/sargv"; rc=0
  (cd "$W/co" && STUB_RC="$1" STUB_OUT="$2" STUB_ARGV="$W/sargv" TAG=v1.0.0 ANCHOR="${3-v0.9.0}" GITHUB_OUTPUT="$W/gho" bash -e "$W/tagsig.sh") >/dev/null 2>&1 || rc=$?
}
tagsig 0 "kind: ssh-good principal: m@example.invalid tagger: m@example.invalid anchor: v0.9.0"
ck "'Read the tag's own signature': ssh-good (exit 0) against the anchor step's anchor → tag_kind=ssh-good; signers.py verify --tag at tag time against refs/remotes/origin/main" \
  bash -c '[ "$1" = 0 ] && grep -qx "tag_kind=ssh-good" "$2" && grep -qF -- "--base-ref refs/remotes/origin/main verify --tag v1.0.0" "$3" && ! grep -qF -- "--released" "$3"' _ "$rc" "$W/gho" "$W/sargv"
for a in v0.9.0 -; do
  tagsig 3 "kind: unsigned principal: - tagger: m@example.invalid anchor: -" "$a"
  ck "…unsigned (exit 3) with anchor '$a' → tag_kind=unsigned: the body's annotated text, whether or not an anchor exists" \
    bash -c '[ "$1" = 0 ] && grep -qx "tag_kind=unsigned" "$2"' _ "$rc" "$W/gho"
done
for x in "0|kind: gpg-good principal: m tagger: m anchor: -" "1|kind: unlisted principal: - tagger: m anchor: v0.9.0" \
         "4|kind: no-anchor principal: - tagger: m anchor: -" "1|kind: bad principal: - tagger: m anchor: v0.9.0" \
         "0|kind: ssh-good principal: m tagger: m anchor: v0.8.0" "3|kind: ssh-good principal: m tagger: m anchor: v0.9.0" "0|"; do
  tagsig "${x%%|*}" "${x#*|}"
  ck "…signers.py exit ${x%%|*}, '${x#*|}': the step fails, no tag_kind written (only ssh-good against the anchor, or unsigned, reaches the body)" \
    bash -c '[ "$1" != 0 ] && ! grep -q "^tag_kind=" "$2"' _ "$rc" "$W/gho"
done
co v1.0.1; (cd "$W/co" && TAG=v1.0.1 bash -e "$W/refetch.sh" && git fetch -q --unshallow origin '+refs/heads/main:refs/remotes/origin/main') >/dev/null 2>&1 || true
rc=0; (cd "$W/co" && TAG=v1.0.1 GITHUB_OUTPUT="$W/gho" bash -e "$W/onmain.sh") >/dev/null 2>&1 || rc=$?
ck "…for a tag on a commit main does not contain: the step fails" [ "$rc" != 0 ]
# PR #52 verifier run 1, finding 3: a tag on a merged PR's intermediate commit — an ancestor of main, never a first-parent
# commit of it, so never the reviewed head — is refused too: the anchor's first-parent rule (R3), not plain ancestry.
co v1.0.2; (cd "$W/co" && TAG=v1.0.2 bash -e "$W/refetch.sh" && git fetch -q --unshallow origin '+refs/heads/main:refs/remotes/origin/main') >/dev/null 2>&1 || true
ck "…v1.0.2 sits on a merged PR's intermediate commit: an ancestor of origin/main, not a first-parent commit of it" \
  bash -c 'c=$(git -C "$1" rev-parse "v1.0.2^{commit}"); git -C "$1" merge-base --is-ancestor "$c" main && ! git -C "$1" rev-list --first-parent main | grep -qx "$c"' _ "$O"
: > "$W/gho"; rc=0; (cd "$W/co" && TAG=v1.0.2 GITHUB_OUTPUT="$W/gho" bash -e "$W/onmain.sh") >/dev/null 2>&1 || rc=$?
ck "…'The tag is on main' for a tag on a merged PR's intermediate commit: the step fails, no commit= written (first-parent commits of main only)" \
  bash -c '[ "$1" != 0 ] && ! grep -q "^commit=" "$2"' _ "$rc" "$W/gho"
# release-publish.sh: refuses a moved tag; creates a draft, uploads every asset, then publishes; a re-run completes a
# draft or replaces a published Release's assets and body in place — never create, delete or a return to draft (R15).
mkdir -p "$W/ghbin" "$W/parts/source"
cat > "$W/ghbin/gh" <<'EOF2'
#!/usr/bin/env bash
{ printf '%s\n' "$@"; echo ---; } >> "$STUB_DIR/gh.argv"
prev=""; for a in "$@"; do [ "$prev" = --notes-file ] && cp "$a" "$STUB_DIR/body.md"; prev="$a"; done
case "$1 $2" in
  "release view") if [ -f "$STUB_DIR/release.exists" ]; then printf '{"tagName": "v1.0.0", "isDraft": %s, "assets": %s}\n' "$(cat "$STUB_DIR/release.exists")" "$(cat "$STUB_DIR/assets.json" 2>/dev/null || echo '[]')"; else echo 'release not found' >&2; exit 1; fi ;;
  "release create"|"release upload"|"release edit"|"release delete-asset") exit 0 ;;
  *) echo "stub gh: unexpected $*" >&2; exit 64 ;;
esac
EOF2
chmod +x "$W/ghbin/gh"; printf a > "$W/parts/source/x-1.0.0-source.tar"
python3 - "$ROOT/scripts/lib/specflow" "$W/parts/source" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
m.write(sys.argv[2], "1.0.0", "template", 1791158400, "a" * 40, [("x-1.0.0-source.tar", "source-archive", True)])
PY
printf -- '---\nversion: 1.0.0\ndate: 2026-10-05\n---\n# Notes\n' > "$W/notes.md"
TC=$(git -C "$O" rev-parse 'v1.0.0^{commit}'); TO=$(git -C "$O" rev-parse 'refs/tags/v1.0.0'); git clone -q "$O" "$W/pubrepo"
pub() { rc=0; k="${PUB_KIND-ssh-good}"; : > "$W/gh.argv"; out=$(cd "$W/pubrepo" && STUB_DIR="$W" PATH="$W/ghbin:$PATH" GITHUB_RUN_ID=77 \
  bash "$ROOT/scripts/release-publish.sh" --version 1.0.0 --tag v1.0.0 --commit "${1:-$TC}" --tag-object "${2:-$TO}" --anchor v0.9.0 ${k:+--tag-kind "$k"} --parts "$W/parts" --notes "$W/notes.md" 2>&1) || rc=$?
  python3 - "$W/gh.argv" > "$W/calls" <<'PY'
import sys
for c in open(sys.argv[1]).read().split("---\n"):
    a = [w for w in c.split("\n") if w]
    if a: print(" ".join(a))
PY
}
pub "$(git -C "$O" rev-parse 'v1.0.1^{commit}')"
ck "release-publish.sh: the remote tag no longer names verify's commit — exit 1, no gh call, nothing published (F30)" \
  bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$rc" "$W/gh.argv"
pub
ck "release-publish.sh, first run: exit 0 — a draft created with no asset, every asset uploaded to it, then published, in that order" python3 - "$rc" "$W/calls" <<'PY'
import sys
assert sys.argv[1] == "0", sys.argv[1]
c = open(sys.argv[2]).read().splitlines(); kinds = [l.split()[1] for l in c]
assert kinds == ["view", "create", "upload", "edit"], c
cr, up, ed = (l.split() for l in c[1:])
assert "--draft" in cr and "--verify-tag" in cr and not any(w.endswith(".tar") for w in cr), cr
assert "--clobber" in up and any(w.endswith("x-1.0.0-source.tar") for w in up) and any(w.endswith("/manifest.json") for w in up), up
assert "--draft=false" in ed, ed
PY
ck "…the attached manifest.json is the job's: tag, verify's commit, run, the reproducible entry" python3 - "$W/parts/manifest.json" "$TC" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["tag"] == "v1.0.0" and d["commit"] == sys.argv[2] and d["run"] == "77", d
assert [(a["filename"], a["reproducible"]) for a in d["artifacts"]] == [("x-1.0.0-source.tar", True)], d
PY
# Wave 1 round 2 (REQ-350; P6 R31): release-publish.sh takes the tag's verdict (--tag-kind) and the body follows it:
# ssh-good → the verify-tag text at the anchor; unsigned → the annotated text even with an anchor. No verdict, or any
# other, is usage: exit 2 before any gh call.
# Covers: REQ-350
ck "release-publish.sh --anchor v0.9.0 --tag-kind ssh-good: the body gives the verify-tag command at the anchor" \
  bash -c '[ "$1" = 0 ] && grep -qF "verify-tag v1.0.0" "$2" && grep -qF "git show v0.9.0:.github/allowed_signers" "$2"' _ "$rc" "$W/body.md"
rm -f "$W/body.md"; PUB_KIND=unsigned pub
ck "release-publish.sh --anchor v0.9.0 --tag-kind unsigned: published, the body says annotated with no signature to verify — no verify-tag, no 'verified against'" \
  bash -c '[ "$1" = 0 ] && grep -qF "no signature to verify" "$2" && ! grep -qF "verify-tag" "$2" && ! grep -qF "verified against" "$2"' _ "$rc" "$W/body.md"
for k in "" gpg-good; do
  PUB_KIND="$k" pub
  ck "release-publish.sh with tag kind '${k:-<none>}': exit 2, no gh call" bash -c '[ "$1" = 2 ] && [ ! -s "$2" ]' _ "$rc" "$W/gh.argv"
done
rm -f "$W/release.exists"
printf true > "$W/release.exists"; pub
ck "release-publish.sh, a re-run that finds a draft (an earlier run stopped mid-upload): upload, then publish it — no second create" \
  bash -c '[ "$1" = 0 ] && [ "$(cut -d" " -f2 "$2" | tr "\n" " ")" = "view upload edit " ] && grep -q "^release edit .*--draft=false" "$2"' _ "$rc" "$W/calls"
printf false > "$W/release.exists"; pub
ck "release-publish.sh, a re-run of a published Release: upload --clobber and edit the body — never create, delete or --draft (P6 R15)" \
  bash -c '[ "$1" = 0 ] && [ "$(cut -d" " -f2 "$2" | tr "\n" " ")" = "view upload edit " ] && grep -q "^release upload .*--clobber" "$2" && grep -q "^release edit .*--notes-file" "$2" && ! grep -qF -- "--draft" "$2"' _ "$rc" "$W/calls"
# Fix wave 1, D (REQ-350; P6 R15, R31): (2) a re-run deletes, logged, every asset of the Release that the current
# manifest's set does not name — after the upload, so manifest.json always matches the Release's assets.
printf '[{"name": "x-1.0.0-source.tar"}, {"name": "manifest.json"}, {"name": "old-1.0.0.dmg"}]\n' > "$W/assets.json"; pub
ck "release-publish.sh, a re-run of a published Release with a stale asset: upload, then delete-asset old-1.0.0.dmg only (logged), then edit" \
  bash -c '[ "$1" = 0 ] && [ "$(cut -d" " -f2 "$2" | tr "\n" " ")" = "view upload delete-asset edit " ] && grep -q "^release delete-asset v1.0.0 old-1.0.0.dmg --yes$" "$2" && [ "$(grep -c "^release delete-asset" "$2")" = 1 ] && grep -qF "deleted the stale asset old-1.0.0.dmg" <<<"$3"' _ "$rc" "$W/calls" "$out"
printf true > "$W/release.exists"; pub
ck "…a draft re-run deletes it too, before the publication" \
  bash -c '[ "$1" = 0 ] && [ "$(cut -d" " -f2 "$2" | tr "\n" " ")" = "view upload delete-asset edit " ]' _ "$rc" "$W/calls"
rm -f "$W/assets.json" "$W/release.exists"
# (3) --latest: true only when v<version> is the highest vX.Y.Z tag on the remote. origin here carries v1.0.1 and
# v1.0.2 above v1.0.0, so 1.0.0 is not the latest; a remote whose highest tag is v1.0.0 makes it the latest.
pub
ck "release-publish.sh: v1.0.1 and v1.0.2 on the remote — the publication says --latest=false" grep -q "^release edit v1.0.0 .*--draft=false --latest=false" "$W/calls"
O2="$W/latest.git"; git clone -q --bare "$O" "$O2"; git -C "$O2" tag -d v1.0.1 v1.0.2 >/dev/null; git -C "$W/pubrepo" remote set-url origin "$O2"; pub
ck "…v1.0.0 the highest vX.Y.Z tag on the remote — --latest=true" grep -q "^release edit v1.0.0 .*--draft=false --latest=true" "$W/calls"
# (1) the moved-tag guard compares the tag OBJECT: a tag replaced by another tag object on the same commit is refused.
git -C "$O2" tag -f -a -m "a replaced tag object" v1.0.0 "$TC" >/dev/null; pub
ck "release-publish.sh: v1.0.0 replaced by another tag object on the same commit — exit 1, no gh call, naming the tag object" \
  bash -c '[ "$1" = 1 ] && [ ! -s "$2" ] && grep -qF "tag object" <<<"$3"' _ "$rc" "$W/gh.argv" "$out"
pub "$TC" "$(git -C "$O2" rev-parse refs/tags/v1.0.0)"
ck "…with --tag-object naming that object (what verify verified): published" bash -c '[ "$1" = 0 ]' _ "$rc"
git -C "$W/pubrepo" remote set-url origin "$O"
ck "release.yml: verify outputs the tag's own verdict (steps.tagsig); publish passes it as --tag-kind (env only) — wave 1 round 2" \
  bash -c 'grep -qF "tag_kind: \${{ steps.tagsig.outputs.tag_kind }}" <<<"$1" && grep -qF "id: tagsig" <<<"$1" && grep -qF "TAG_KIND: \${{ needs.verify.outputs.tag_kind }}" <<<"$2" && grep -qF -- "--tag-kind \"\$TAG_KIND\"" <<<"$2"' _ "$(job "$RY" verify)" "$(job "$RY" publish)"
ck "release.yml: verify outputs the tag object it verified; publish passes it as --tag-object (env only)" \
  bash -c 'grep -qF "tag_object: \${{ steps.main.outputs.tag_object }}" <<<"$1" && grep -qF "echo \"tag_object=" <<<"$1" && grep -qF "TAG_OBJECT: \${{ needs.verify.outputs.tag_object }}" <<<"$2" && grep -qF -- "--tag-object \"\$TAG_OBJECT\"" <<<"$2"' _ "$(job "$RY" verify)" "$(job "$RY" publish)"
# The parts (F22; R35: final here, so Builds 4 and 5 never change release-publish.sh).
mkdir -p "$W/parts/image"; printf '{"name": "ghcr.io/o/r", "tag": "1.0.0", "digest": "sha256:%s", "superseded": "none"}\n' "$(printf 'd%.0s' $(seq 64))" > "$W/parts/image/image.json"
pub
ck "release-publish.sh: the image part is image/image.json, passed as --image-json — the Release manifest records the digest, never an image 'manifest' (F22)" \
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d["image"]["digest"] == "sha256:" + "d" * 64 and all(a["kind"] != "image" for a in d["artifacts"]), d' "$W/parts/manifest.json"
rm -rf "$W/parts/image"
mkdir -p "$W/parts/bundle-unsigned" "$W/parts/bundle-signed"; printf u > "$W/parts/bundle-unsigned/x.dmg"; printf ss > "$W/parts/bundle-signed/x.dmg"
python3 - "$ROOT/scripts/lib/specflow" "$W/parts" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
m.write(sys.argv[2] + "/bundle-unsigned", "1.0.0", "tauri", 1791158400, "a" * 40, [("x.dmg", "bundle", False, False)])
m.write(sys.argv[2] + "/bundle-signed", "1.0.0", "tauri", 1791158400, "a" * 40, [("x.dmg", "bundle", False, True)])
PY
pub
ck "release-publish.sh with both bundle parts: one bundle entry, the signed one (signed true, its size), one x.dmg uploaded (F22)" \
  bash -c 'python3 -c "import json, sys; d = json.load(open(sys.argv[1])); b = [a for a in d[\"artifacts\"] if a[\"kind\"] == \"bundle\"]; assert len(b) == 1 and b[0][\"signed\"] is True and b[0][\"size\"] == 2 and d[\"signed\"] is True, d" "$1" && [ "$(grep -c "x.dmg$" "$2")" = 1 ] && grep -q "bundle-signed/x.dmg$" "$2"' _ "$W/parts/manifest.json" "$W/gh.argv"
rm -rf "$W/parts/bundle-unsigned" "$W/parts/bundle-signed"


# Build 3 review (REQ-350, REQ-334; P6 R15, R35): fetch-depth 0 brings tags too, and a tag literally named origin/main
# outranks the remote-tracking ref in a short-name lookup — so the ancestry step reads refs/remotes/origin/main, and a
# decoy tag naming an off-main commit does not make that commit a first-parent commit of main.
# Covers: REQ-350
co v1.0.1; (cd "$W/co" && TAG=v1.0.1 bash -e "$W/refetch.sh" && git fetch -q --unshallow origin '+refs/heads/main:refs/remotes/origin/main') >/dev/null 2>&1 || true
git -C "$W/co" tag origin/main "$(git -C "$O" rev-parse 'v1.0.1^{commit}')"
: > "$W/gho"; rc=0; (cd "$W/co" && TAG=v1.0.1 GITHUB_OUTPUT="$W/gho" bash -e "$W/onmain.sh") >/dev/null 2>&1 || rc=$?
ck "'The tag is on main' with a decoy tag named origin/main on the off-main commit: still refused, no commit= written" \
  bash -c '[ "$1" != 0 ] && ! grep -q "^commit=" "$2"' _ "$rc" "$W/gho"
# The previous release is resolved at the tag: none → prev empty and the stack from the pack; notes on main with no tag →
# the step fails (a refusal at the tag, never the PR-time warning); an annotated tag → prev=v<that>.
# Covers: REQ-350
vstep "Resolve the stack and the previous release" > "$W/resolve.sh"
R="$W/resolvecase"; git init -q -b main "$R"
(cd "$R" && mkdir -p scripts docs/releases && cp -R "$ROOT/scripts/lib" scripts/ && find scripts -name __pycache__ -prune -exec rm -rf {} + \
  && printf 'stack: template\npython_version: "3.12"\n' > scripts/template-pack.yml && printf -- '---\ndate: 2026-09-01\n---\n' > docs/releases/0.9.0-notes.md \
  && git add -A && git commit -qm "release 0.9.0 docs" && git update-ref refs/remotes/origin/main HEAD)
rm -f "$R/docs/releases/0.9.0-notes.md" "$R/.git/refs/heads/none"; (cd "$R" && git rm -q -r --cached docs >/dev/null && git commit -qm "no earlier notes" && git update-ref refs/remotes/origin/main HEAD)
: > "$W/gho"; rc=0; (cd "$R" && VERSION=1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/resolve.sh") >/dev/null 2>&1 || rc=$?
ck "'Resolve the stack and the previous release', no earlier release notes: stack=template, prev empty" \
  bash -c '[ "$1" = 0 ] && grep -qx "stack=template" "$2" && grep -qx "prev=" "$2"' _ "$rc" "$W/gho"
(cd "$R" && mkdir -p docs/releases && printf -- '---\ndate: 2026-09-01\n---\n' > docs/releases/0.9.0-notes.md && git add -A && git commit -qm "release 0.9.0 docs again" && git update-ref refs/remotes/origin/main HEAD)
: > "$W/gho"; rc=0; (cd "$R" && VERSION=1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/resolve.sh") >/dev/null 2>&1 || rc=$?
ck "…the previous release's notes on main but no v0.9.0 tag: the step fails, writing nothing" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$W/gho"
(cd "$R" && git tag -a -m "0.9.0" v0.9.0)
: > "$W/gho"; rc=0; (cd "$R" && VERSION=1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/resolve.sh") >/dev/null 2>&1 || rc=$?
ck "…with an annotated v0.9.0 tag: prev=v0.9.0" bash -c '[ "$1" = 0 ] && grep -qx "prev=v0.9.0" "$2" && grep -qx "stack=template" "$2"' _ "$rc" "$W/gho"
# Fix wave 1, B (REQ-383): the refusal branch — a previous tag that does not verify as released (a lightweight one here)
# fails the step through the same function release-tag.sh runs (signers.py previous), writing nothing.
(cd "$R" && git tag -d v0.9.0 >/dev/null && git tag v0.9.0)
: > "$W/gho"; rc=0; out=$(cd "$R" && VERSION=1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/resolve.sh" 2>&1) || rc=$?
ck "…a lightweight v0.9.0: the step fails naming lightweight, writing nothing (the refusal branch)" \
  bash -c '[ "$1" != 0 ] && [ ! -s "$2" ] && grep -qF "previous-refused: v0.9.0 lightweight" <<<"$3"' _ "$rc" "$W/gho" "$out"
(cd "$R" && git tag -d v0.9.0 >/dev/null && git tag -a -m "0.9.0" v0.9.0)

# Build 3 final review, finding 2 (REQ-350; P6 R35): every stack job checks, right after its checkout, that the stack's
# release action is installed, and fails with a message of its own naming the stack and the build that adds it — never
# GitHub's "Did you forget to run actions/checkout" from the local-action resolver. Extracted and run.
# Covers: REQ-350
ck "image, bundle, sign, verify-signed and prune each check for .github/actions/release/action.yml before their first use of it" python3 - "$RY" <<'PY'
import re, sys
body = open(sys.argv[1]).read().split("\njobs:\n", 1)[1]
parts = re.split(r"(?m)^  ([a-z][a-z-]*):\n", body)[1:]
jobs = dict(zip(parts[::2], parts[1::2]))
for n in ("image", "bundle", "sign", "verify-signed", "prune"):
    j = jobs[n]; i = j.index("- name: The stack's release action is installed"); u = j.index("uses: ./.github/actions/release")
    assert j.index("uses: actions/checkout@") < i < u, n
    assert "STACK: ${{ needs.verify.outputs.stack }}" in j[i:u], n
PY
vstep "The stack's release action is installed" > "$W/action.sh"; mkdir -p "$W/noaction" "$W/withaction/.github/actions/release"
rc=0; out=$(cd "$W/noaction" && STACK=python bash -e "$W/action.sh" 2>&1) || rc=$?
ck "…no .github/actions/release/action.yml (a python instance initialised before Build 4): the step fails, naming the stack and that nothing is published" \
  bash -c '[ "$1" != 0 ] && grep -qF "::error::no release action for stack python" <<<"$2" && grep -qF "nothing is published" <<<"$2"' _ "$rc" "$out"
: > "$W/withaction/.github/actions/release/action.yml"
rc=0; (cd "$W/withaction" && STACK=python bash -e "$W/action.sh") >/dev/null 2>&1 || rc=$?
ck "…with the action installed: exit 0" [ "$rc" = 0 ]
# Finding 17 (REQ-350; P6 R28 as corrected): release.yml passes no --since — release-check starts at the newest earlier
# release whose GitHub Release is published, so a tag whose own run refused excuses nothing.
ck "verify: release-check is called without --since (the published-Release start is release-check's own)" \
  bash -c 's=$(sed -n "/- name: Re-check the merged PRs since the previous release/,/- name: Replay/p" "$1"); grep -qF "attestation.py release-check" <<<"$s" && ! grep -qF -- "--since" <<<"$s"' _ "$RY"
# Finding 20 (REQ-350; P6 R30): the tagged commit is the newest first-parent commit of main that added
# docs/releases/<v>-notes.md — release-tag.sh's rule — so a tag on a later (possibly backdated) direct push is refused.
S="$W/shipcase"; git init -q -b main "$S"
(cd "$S" && echo a > a && git add -A && git commit -qm base && mkdir -p docs/releases && echo n > docs/releases/1.0.0-notes.md && git add -A \
  && git commit -qm "Merge ship/1.0.0" && git tag -a -m r v1.0.0 && echo x > docs/x.md && git add -A \
  && GIT_COMMITTER_DATE="2026-09-01T12:00:00Z" git commit -qm "a later direct push, backdated" \
  && GIT_COMMITTER_DATE="2026-09-01T12:00:00Z" git tag -a -m r v1.0.1 && git tag -a -m r v2.0.0 HEAD~1 && git update-ref refs/remotes/origin/main HEAD)
: > "$W/gho"; rc=0; (cd "$S" && TAG=v1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/onmain.sh") >/dev/null 2>&1 || rc=$?
ck "'The tag is on main': v1.0.0 on the first-parent commit that added docs/releases/1.0.0-notes.md: exit 0, commit=" \
  bash -c '[ "$1" = 0 ] && grep -q "^commit=" "$2"' _ "$rc" "$W/gho"
(cd "$S" && git tag -d v1.0.0 >/dev/null && GIT_COMMITTER_DATE="2026-09-01T12:00:00Z" git tag -a -m r v1.0.0 HEAD)
: > "$W/gho"; rc=0; out=$(cd "$S" && TAG=v1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/onmain.sh" 2>&1) || rc=$?
ck "…v1.0.0 moved to a later, backdated direct push on main: the step fails, naming the notes, no commit= written" \
  bash -c '[ "$1" != 0 ] && ! grep -q "^commit=" "$2" && grep -qF "docs/releases/1.0.0-notes.md" <<<"$3"' _ "$rc" "$W/gho" "$out"
: > "$W/gho"; rc=0; (cd "$S" && TAG=v2.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/onmain.sh") >/dev/null 2>&1 || rc=$?
ck "…v2.0.0, with no 2.0.0 notes on main: the step fails" bash -c '[ "$1" != 0 ] && ! grep -q "^commit=" "$2"' _ "$rc" "$W/gho"
# Findings 10, 12 (REQ-386, REQ-354; P6 R23): the policy committed at the tag binds the release. verify outputs signing
# (config.py at the tag); signing-probe fails when it is apple and the five secrets are not all present, so sign,
# verify-signed and — through !failure() — publish never release an unsigned bundle against a signing: apple policy.
# Covers: REQ-386
# Covers: REQ-354
ck "verify outputs signing from the resolve step; signing-probe reads it through env (SIGNING)" \
  bash -c 'grep -qF "signing: \${{ steps.resolve.outputs.signing }}" <<<"$1" && grep -qF "SIGNING: \${{ needs.verify.outputs.signing }}" <<<"$2"' _ "$(job "$RY" verify)" "$(job "$RY" signing-probe)"
vstep "Probe the signing secrets" > "$W/probe.sh"
probe() { : > "$W/gho"; rc=0; out=$(cd "$W" && env -i PATH="$PATH" GITHUB_OUTPUT="$W/gho" "$@" bash -e "$W/probe.sh" 2>&1) || rc=$?; }
probe SIGNING=apple
ck "signing-probe, signing: apple and no secret: the job fails, naming the policy (publish is then skipped)" \
  bash -c '[ "$1" != 0 ] && grep -qF "signing: apple" <<<"$2"' _ "$rc" "$out"
probe SIGNING=none
ck "…signing: none and no secret: present=false, exit 0 (the unsigned path, tester instructions required by release-publish.sh)" \
  bash -c '[ "$1" = 0 ] && grep -qx "present=false" "$2"' _ "$rc" "$W/gho"
probe SIGNING=apple APPLE_CERTIFICATE_P12=x APPLE_CERTIFICATE_PASSWORD=x APPLE_ID=x APPLE_TEAM_ID=x APPLE_APP_PASSWORD=x
ck "…signing: apple with all five: present=true, exit 0" bash -c '[ "$1" = 0 ] && grep -qx "present=true" "$2"' _ "$rc" "$W/gho"
: > "$W/gho"; rc=0; (cd "$R" && VERSION=1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/resolve.sh") >/dev/null 2>&1 || rc=$?
ck "'Resolve the stack and the previous release' (template source, no .specflow.yml): signing=none (config.py's default)" \
  bash -c '[ "$1" = 0 ] && grep -qx "signing=none" "$2"' _ "$rc" "$W/gho"
(cd "$R" && printf 'stack: tauri\nsigning: apple\n' > .specflow.yml && git add -A && git commit -qm "an app instance" && git update-ref refs/remotes/origin/main HEAD)
: > "$W/gho"; rc=0; (cd "$R" && VERSION=1.0.0 GITHUB_OUTPUT="$W/gho" bash -e "$W/resolve.sh") >/dev/null 2>&1 || rc=$?
ck "…an instance whose .specflow.yml says signing: apple: stack=tauri, signing=apple" \
  bash -c '[ "$1" = 0 ] && grep -qx "stack=tauri" "$2" && grep -qx "signing=apple" "$2"' _ "$rc" "$W/gho"
# release-publish.sh refuses an unsigned bundle without its tester instructions (REQ-386), before any gh call.
mkdir -p "$W/parts/bundle-unsigned"; printf u > "$W/parts/bundle-unsigned/x.dmg"
python3 - "$ROOT/scripts/lib/specflow" "$W/parts" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
m.write(sys.argv[2] + "/bundle-unsigned", "1.0.0", "tauri", 1791158400, "a" * 40, [("x.dmg", "bundle", False, False)])
PY
pub
ck "release-publish.sh: an unsigned bundle and no docs/releases/1.0.0-tester-instructions.md at the tag: exit 1, no gh call, naming the file" \
  bash -c '[ "$1" = 1 ] && [ ! -s "$2" ] && grep -qF "1.0.0-tester-instructions.md" <<<"$3"' _ "$rc" "$W/gh.argv" "$out"
mkdir -p "$W/pubrepo/docs/releases"; printf '# Opening an unsigned app\n' > "$W/pubrepo/docs/releases/1.0.0-tester-instructions.md"; pub
ck "…with the tester instructions present: published (a draft created, then the publication)" \
  bash -c '[ "$1" = 0 ] && grep -q "^release create" "$2"' _ "$rc" "$W/calls"
rm -rf "$W/parts/bundle-unsigned" "$W/pubrepo/docs"
# Build 5 fix wave 1, A (REQ-386; P6 R33, R35): the selected part's provenance decides `signed`, never the part's own
# manifest. bundle-unsigned/ is written by the bundle job after third-party build code ran (npm lifecycle scripts,
# build.rs, pub hooks), so its manifest saying signed: true still publishes signed: false — the entry and the top level
# — with the tester instructions required and appended as for any unsigned release; bundle-signed/ reaches publish only
# when verify-signed succeeded (release.yml downloads it on that job's success alone), and its entry must say signed:
# true, else nothing is published.
# Covers: REQ-386
mkdir -p "$W/parts/bundle-unsigned" "$W/pubrepo/docs/releases"; printf u > "$W/parts/bundle-unsigned/x.dmg"
printf '# Opening an unsigned app\n\nForged-or-not marker text.\n' > "$W/pubrepo/docs/releases/1.0.0-tester-instructions.md"
python3 - "$ROOT/scripts/lib/specflow" "$W/parts" <<'PY'
import json, sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
m.write(sys.argv[2] + "/bundle-unsigned", "1.0.0", "tauri", 1791158400, "a" * 40, [("x.dmg", "bundle", False, True)])
assert json.load(open(sys.argv[2] + "/bundle-unsigned/manifest.json"))["signed"] is True  # the forged claim
PY
rm -f "$W/body.md"; pub
ck "release-publish.sh: bundle-unsigned/manifest.json claims signed: true — published, but the entry and the top level say signed: false" \
  bash -c '[ "$1" = 0 ] && python3 -c "import json, sys; d = json.load(open(sys.argv[1])); b = [a for a in d[\"artifacts\"] if a[\"kind\"] == \"bundle\"]; assert len(b) == 1 and b[0][\"signed\"] is False and d[\"signed\"] is False, d" "$2"' _ "$rc" "$W/parts/manifest.json"
ck "…and the body carries the tester instructions under 'Opening this unsigned app'" \
  bash -c 'grep -qF "## Opening this unsigned app" "$1" && grep -qF "Forged-or-not marker text." "$1"' _ "$W/body.md"
rm -rf "$W/pubrepo/docs"; pub
ck "…and without docs/releases/1.0.0-tester-instructions.md it is refused as unsigned: exit 1, no gh call" \
  bash -c '[ "$1" = 1 ] && [ ! -s "$2" ] && grep -qF "1.0.0-tester-instructions.md" <<<"$3"' _ "$rc" "$W/gh.argv" "$out"
rm -rf "$W/parts/bundle-unsigned"; mkdir -p "$W/parts/bundle-signed"; printf ss > "$W/parts/bundle-signed/x.dmg"
python3 - "$ROOT/scripts/lib/specflow" "$W/parts" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
m.write(sys.argv[2] + "/bundle-signed", "1.0.0", "tauri", 1791158400, "a" * 40, [("x.dmg", "bundle", False, False)])
PY
pub
ck "release-publish.sh: a bundle-signed/ part whose entry does not say signed: true — exit 1, no gh call, naming verify-signed" \
  bash -c '[ "$1" = 1 ] && [ ! -s "$2" ] && grep -qF "verify-signed" <<<"$3"' _ "$rc" "$W/gh.argv" "$out"
rm -rf "$W/parts/bundle-signed"
# Fix wave 1, J (REQ-334, REQ-350; P6 R35): every release composite action — .github/actions/release/action.yml and
# stacks/*/release/action.yml, which Builds 4 and 5 add in parallel — passes values to run: through env only (no
# ${{ inputs.* }}, ${{ github.* }} or ${{ secrets.* }} inside a run: block), names no secret, and pins every uses: to a
# commit SHA (or a local ./ path). None exists yet: the rule iterates the glob, and a fixture under $W proves the
# detector through the same function.
# Covers: REQ-334
action_rule() { python3 - "$@" <<'PY'
import re, sys
bad = []
for path in sys.argv[1:]:
    lines = open(path).read().splitlines(); i = 0
    while i < len(lines):
        l = lines[i]
        if re.search(r"\bsecrets\.", l):
            bad.append(f"{path}:{i + 1}: names a secret")
        m = re.match(r"^\s*(- )?uses:\s*(\S+)", l)
        if m and not m.group(2).startswith("./") and not re.search(r"@[0-9a-f]{40}$", m.group(2)):
            bad.append(f"{path}:{i + 1}: uses: not pinned to a commit SHA ({m.group(2)})")
        elif m and not m.group(2).startswith("./") and not re.search(r"@[0-9a-f]{40}\s+#\s+v[0-9]+(\.[0-9]+)*\s*$", l):
            bad.append(f"{path}:{i + 1}: uses: pinned without its '# vX.Y.Z' version comment ({m.group(2)})")
        r = re.match(r"^(\s*)(- )?run: ?(.*)$", l)
        if not r:
            i += 1; continue
        ind = len(r.group(1)) + (2 if r.group(2) else 0); block = [(i, r.group(3))]; i += 1
        while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > ind):
            block.append((i, lines[i])); i += 1
        for n, b in block:
            if re.search(r"\$\{\{\s*(inputs|github|secrets)\.", b):
                bad.append(f"{path}:{n + 1}: an expression inside run: (pass it through env:)")
if bad:
    print("\n".join(bad)); sys.exit(1)
PY
}
export -f action_rule
mkdir -p "$W/act/bad" "$W/act/good"
cat > "$W/act/bad/action.yml" <<'EOF2'
name: bad
inputs:
  version: {required: true}
runs:
  using: composite
  steps:
    - uses: actions/checkout@v4
    - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9
    - shell: bash
      env:
        TOKEN: ${{ secrets.GITHUB_TOKEN }}
      run: |
        echo "${{ inputs.version }}"
        echo "${{ github.ref_name }}"
EOF2
cat > "$W/act/good/action.yml" <<'EOF2'
name: good
inputs:
  version: {required: true}
runs:
  using: composite
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    - shell: bash
      env:
        VERSION: ${{ inputs.version }}
      run: |
        echo "$VERSION"
EOF2
rc=0; out=$(action_rule "$W/act/bad/action.yml") || rc=$?
ck "the composite-action rule refuses a fixture with an unpinned uses:, a secret, and inputs/github expressions inside run:" \
  bash -c '[ "$1" = 1 ] && grep -qF "not pinned" <<<"$2" && grep -qF "names a secret" <<<"$2" && [ "$(grep -c "inside run:" <<<"$2")" = 2 ]' _ "$rc" "$out"
# Build 5 fix wave 1, F (REQ-334): a SHA pin needs its '# vX.Y.Z' comment too, as test_action_pins.sh asks of workflows.
# Covers: REQ-334
ck "…and a SHA-pinned uses: without its '# vX.Y.Z' comment" grep -qF "without its '# vX.Y.Z' version comment (actions/cache@" <<<"$out"
ck "…and accepts one that pins its uses: and passes inputs through env:" action_rule "$W/act/good/action.yml"
ACTS=(); for a in "$ROOT"/.github/actions/release/action.yml "$ROOT"/stacks/*/release/action.yml; do [ ! -f "$a" ] || ACTS+=("$a"); done
ck "every release composite action in the tree (${#ACTS[@]} today; Builds 4 and 5 add them) passes the rule" \
  bash -c '[ "$#" = 0 ] || action_rule "$@"' _ "${ACTS[@]+"${ACTS[@]}"}"
finish test_release_workflow
