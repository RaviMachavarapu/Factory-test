#!/usr/bin/env bash
# The governance harness itself (tests/governance/lib/check.sh): a check placed after `finish` must fail the
# script loudly, so no governance check can be decorative (PR #34 third-run high: checks appended after finish
# could set FAIL=1 and still exit 0). "Test the validator."
# Covers: REQ-306
set -uo pipefail
source "$(dirname "$0")/lib/check.sh"
H="$ROOT/tests/governance/lib/check.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/harness.XXXXXX"); trap 'rm_tree "$W"' EXIT
mk() { printf '#!/usr/bin/env bash\nset -uo pipefail\nsource "%s"\n%s\n' "$H" "$2" > "$W/$1"; }
run() { out=$(bash "$W/$1" 2>&1); rc=$?; }
mk normal 'ck "a" true; finish normal'
run normal
ck "a script whose finish is last: exit 0 and 'all checks passed'" bash -c '[ "$1" = 0 ] && grep -q "all checks passed" <<<"$2"' _ "$rc" "$out"
mk late_fail 'ck "a" true; finish late; ck "late and failing" false'
run late_fail
ck "a failing check after finish: exit 1" [ "$rc" = 1 ]
ck "…and the output names the misplaced check and says it sits after finish" bash -c 'grep -qF "late and failing" <<<"$1" && grep -qi "after finish" <<<"$1"' _ "$out"
mk late_pass 'ck "a" true; finish late; ck "late but passing" true'
run late_pass
ck "even a passing check after finish: exit 1 (finish must be the last line, so nothing is decorative)" [ "$rc" = 1 ]
mk late_fail_fn 'ck "a" true; finish late; fail "raw fail after finish"'
run late_fail_fn
ck "a raw fail after finish: exit 1" [ "$rc" = 1 ]
# A captured gates output must never be passed as one argv to bash -c: the instance's output is well over
# 2,000 lines, and Linux caps a single argument at 128 KiB (MAX_ARG_STRLEN), so the exec fails and the check
# reads as a failure on CI while macOS (no per-argument cap) passes — the first-run jobs on main after PR #43.
# Grep a file instead (REQ-360).
ck "no governance test passes \$GATES_OUT as an argv to bash -c (Linux MAX_ARG_STRLEN)" no grep -qE 'bash -c .*_ "\$GATES_OUT"' tests/governance/test_first_run.sh
# H10 (REQ-360, REQ-306): an EXIT trap never fails a test after "all checks passed". git's automatic gc and maintenance
# are off for every git a governance test runs (a detached `git maintenance run --auto` still writing into a temp
# repository made rm -rf meet "Directory not empty" on macOS), and rm_tree retries, then never fails.
# Covers: REQ-360
ck "check.sh turns git's automatic gc and maintenance off for every test (GIT_CONFIG_COUNT)" bash -c \
  'source "$1" >/dev/null; [ "$(git config --get gc.auto)" = 0 ] && [ "$(git config --get maintenance.auto)" = false ]' _ "$H"
ST="$W/stuck"; mkdir -p "$ST/locked"; : > "$ST/locked/f"; chmod 500 "$ST/locked"
mk trap_stuck 'set -e; trap "rm_tree \"$STUCK\"" EXIT; ck "a" true; finish stuck'
out=$(STUCK="$ST" RM_TREE_TRIES=2 bash "$W/trap_stuck" 2>&1); rc=$?
chmod 700 "$ST/locked"
ck "a passing test whose EXIT trap cannot remove its temp tree still exits 0 (rm_tree never fails, even under set -e)" \
  bash -c '[ "$1" = 0 ] && grep -q "all checks passed" <<<"$2"' _ "$rc" "$out"
ck "every governance test's EXIT trap removes its temp tree with rm_tree, never a bare rm -rf" python3 - "$ROOT/tests/governance" <<'PY'
import glob, os, re, sys
bad = [f"{os.path.basename(p)}:{i}" for p in sorted(glob.glob(os.path.join(sys.argv[1], "test_*.sh")))
       for i, line in enumerate(open(p), 1) if re.search(r"trap\s+'rm -rf", line)]
assert not bad, bad
PY
finish test_check_harness
