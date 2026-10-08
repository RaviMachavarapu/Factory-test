#!/usr/bin/env bash
# REQ-360: test_first_run.sh gates a throwaway instance, which is never on a ship branch. The release gates read the
# head branch from SPECFLOW_HEAD_BRANCH, else GITHUB_HEAD_REF, else the checkout (disposition_gate.ship_branch_version,
# P6 R11), so on the factory's own ship PR the first-run jobs inherited GITHUB_HEAD_REF=ship/3.2.0 from CI, the
# instance's gates evaluated 3.2.0, and the fenced release records were "missing" (PR #62, every ubuntu first-run job
# red). The harness must run the instance's gates with both variables unset; the first-run cases are opt-in, so the
# rule is pinned here, in the default gates.
# Covers: REQ-360
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
T="$ROOT/tests/governance/test_first_run.sh"
DG="$ROOT/scripts/lib/specflow/disposition_gate.py"
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT

# The mechanism: a scratch repository on main names a ship version only through the environment.
git -C "$WORK" init -q -b main && git -C "$WORK" commit -q --allow-empty -m init
ship_version() {  # ship_version — prints what the gate derives for $WORK under the caller's environment
  python3 - "$WORK" "$(dirname "$DG")" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[2]); import disposition_gate
print(disposition_gate.ship_branch_version(Path(sys.argv[1])))
PY
}
ck "a checkout on main with neither variable set names no ship version" \
  bash -c '[[ "$(env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH bash -c "$1")" == None ]]' _ "$(declare -f ship_version); WORK='$WORK'; DG='$DG'; ship_version"
ck "GITHUB_HEAD_REF=ship/9.9.9 alone makes the same checkout evaluate 9.9.9 (the CI leak)" \
  bash -c '[[ "$(env -u SPECFLOW_HEAD_BRANCH GITHUB_HEAD_REF=ship/9.9.9 bash -c "$1")" == 9.9.9 ]]' _ "$(declare -f ship_version); WORK='$WORK'; DG='$DG'; ship_version"
ck "SPECFLOW_HEAD_BRANCH=ship/8.8.8 wins over GITHUB_HEAD_REF" \
  bash -c '[[ "$(SPECFLOW_HEAD_BRANCH=ship/8.8.8 GITHUB_HEAD_REF=ship/9.9.9 bash -c "$1")" == 8.8.8 ]]' _ "$(declare -f ship_version); WORK='$WORK'; DG='$DG'; ship_version"

# The harness: the one place test_first_run.sh runs the instance's gates unsets both, beside the recursion guards.
ck "test_first_run.sh runs the instance's gates with GITHUB_HEAD_REF and SPECFLOW_HEAD_BRANCH unset" \
  bash -c 'l=$(grep -F "bash scripts/run-quality-gates.sh" "$1" | grep -F "env -u"); [[ -n "$l" ]] && grep -qF -- "-u GITHUB_HEAD_REF" <<<"$l" && grep -qF -- "-u SPECFLOW_HEAD_BRANCH" <<<"$l" && grep -qF -- "-u SPECFLOW_QG_RUNNING" <<<"$l" && grep -qF -- "-u SPECFLOW_FIRST_RUN" <<<"$l"' _ "$T"
ck "test_first_run.sh's header records why (the ship-PR leak, REQ-360)" \
  bash -c 'grep -qF "GITHUB_HEAD_REF" "$1" && grep -qiF "ship" "$1"' _ "$T"
finish test_first_run_env
