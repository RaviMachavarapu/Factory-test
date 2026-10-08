#!/usr/bin/env bash
# run-instance-tests.sh — run the new or changed governance tests inside a scaffolded instance (BL-021).
# Usage: run-instance-tests.sh [--base <ref>] [--stack python|tauri|flutter ...] [--all] [TEST ...]
# Copies the working tree as tests/governance/lib/check.sh's copy_template does (tracked and untracked
# non-ignored files, no .git), runs scripts/init-project.sh for each stack (python by default; tauri and
# flutter with SPECFLOW_NO_SCAFFOLD=1, since no toolchain is needed), runs each listed test there with the
# caller's PATH (GITHUB_HEAD_REF, SPECFLOW_HEAD_BRANCH and SPECFLOW_QG_RUNNING unset, so a PR's branch name never
# leaks into the instance: P6's lesson), prints every SKIP line, and exits 1 if any test fails (2 for a usage error).
# Tests: those changed since --base (default refs/remotes/origin/main; git diff --name-only <base>...HEAD
# -- tests/governance/test_*.sh) plus any named; every test with --all. Stacks: those given with --stack, else
# python plus every stack whose stacks/<stack>/ files changed since --base ("init per touched stack", BL-021).
# Tested by tests/governance/test_run_instance_tests.sh.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="refs/remotes/origin/main"; ALL=0; STACKS=""; NAMED=""
die() { echo "run-instance-tests: $*" >&2; exit 2; }
# The script ships to every instance (init removes only the template's own pack files) but scaffolds instances from
# the template source: in an instance init-project.sh refuses a second init, so refuse first, plainly.
if [[ -f "$ROOT/.specflow.yml" || -f "$ROOT/.stack" ]]; then
  die "template source only — this tree is an instance (.specflow.yml or .stack present); its governance tests already run in its own gates (bash scripts/run-quality-gates.sh)"
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) [[ $# -ge 2 ]] || die "--base needs a value"; BASE="$2"; shift 2 ;;
    --stack)
      [[ $# -ge 2 ]] || die "--stack needs a value"
      case "$2" in python|tauri|flutter) STACKS="$STACKS $2" ;; *) die "--stack: invalid value '$2' (python, tauri or flutter)" ;; esac
      shift 2 ;;
    --all) ALL=1; shift ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) NAMED="$NAMED $1"; shift ;;
  esac
done
if [[ -z "$STACKS" ]]; then
  STACKS=" python"
  for s in tauri flutter; do
    if [[ -d "$ROOT/stacks/$s" ]] && [[ -n "$(cd "$ROOT" && git diff --name-only "$BASE...HEAD" -- "stacks/$s" 2>/dev/null)" ]]; then STACKS="$STACKS $s"; fi
  done
fi
TESTS=""
if [[ $ALL -eq 1 ]]; then
  for f in "$ROOT"/tests/governance/test_*.sh; do TESTS="$TESTS tests/governance/$(basename "$f")"; done
else
  CH=$(cd "$ROOT" && git diff --name-only "$BASE...HEAD" -- 'tests/governance/test_*.sh' 2>&1) || die "cannot diff against $BASE: $CH"
  for f in $CH; do [[ -f "$ROOT/$f" ]] && TESTS="$TESTS $f"; done
fi
for n in $NAMED; do
  n="${n#"$ROOT"/}"; [[ -f "$ROOT/$n" ]] || n="tests/governance/${n##*/}"
  [[ -f "$ROOT/$n" ]] || die "no such test: $n"
  case " $TESTS " in *" $n "*) ;; *) TESTS="$TESTS $n" ;; esac
done
if [[ -z "${TESTS// /}" ]]; then echo "run-instance-tests: no new or changed governance tests since $BASE"; exit 0; fi
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
STATUS=0
for s in $STACKS; do
  D="$WORK/$s/acme"; mkdir -p "$D"
  (cd "$ROOT" && git ls-files -z --cached --others --exclude-standard \
     | while IFS= read -r -d '' f; do if [[ -e "$f" ]]; then printf '%s\0' "$f"; fi; done \
     | tar -cf - --null -T -) | (cd "$D" && tar -xf -)
  NS="${SPECFLOW_NO_SCAFFOLD:-}"; [[ $s != python ]] && NS=1
  echo "=== $s: init ==="
  if ! (cd "$D" && SPECFLOW_NO_SCAFFOLD="$NS" bash scripts/init-project.sh --name Acme --stack "$s" --profile engineer --path lanes --solo true </dev/null >"$WORK/$s.init" 2>&1); then
    tail -20 "$WORK/$s.init"; echo "FAIL $s: init-project.sh failed"; echo "$s: init failed"; STATUS=1; continue
  fi
  n=0; failed=0; skips=0
  for t in $TESTS; do
    n=$((n + 1)); echo "RUN $t ($s)"
    rc=0; (cd "$D" && env -u SPECFLOW_QG_RUNNING -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH bash "$t") >"$WORK/out" 2>&1 || rc=$?
    k=$(grep -c '^SKIP' "$WORK/out" || true); skips=$((skips + k))
    if [[ $k -gt 0 ]]; then grep '^SKIP' "$WORK/out"; fi
    if [[ $rc -ne 0 ]]; then failed=$((failed + 1)); echo "FAIL $t ($s): exit $rc"; tail -15 "$WORK/out" | sed 's/^/    | /'; fi
  done
  echo "$s: $n test(s), $failed failed, $skips SKIP"
  [[ $failed -eq 0 ]] || STATUS=1
done
exit $STATUS
