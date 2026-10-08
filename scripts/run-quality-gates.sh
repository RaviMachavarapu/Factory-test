#!/usr/bin/env bash
# Orchestrates: pytest, Dafny verification, governance tests, optional per-stack hook.
# Used by VALIDATE and again in RELEASE. Treats absence of a category as pass.
# Implements the quality-gate exit semantics (art-formal-verification, art-release-readiness).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Recursion guard: governance tests glob includes any test_*.sh, and the smoke
# test for THIS orchestrator re-invokes it. Export a sentinel so the smoke
# test can short-circuit when it sees itself running inside us.
export SPECFLOW_QG_RUNNING=1

FAIL=0
GATE_FAIL_LINES=""
SECTION() { printf '\n=== %s ===\n' "$1"; }
gate_fail() {  # gate_fail LINE — record a section 1-4 failure line for the Summary's "Gate failures" (REQ-360)
  GATE_FAIL_LINES="${GATE_FAIL_LINES}${1}"$'\n'
}

# Resolved once, ahead of sections 1 and 4: the stack (section 4 reuses it) and, for python, the
# coverage floor (REQ-325, R16) — the higher of the working tree's and the base ref's coverage_min,
# exported so the pack hooks (Task 12) read the same value.
set +e
STACK="$(python3 "$ROOT/scripts/lib/specflow/config.py" --root . get stack --default none)"
CFG_RC=$?
set -e
if [[ $CFG_RC -ne 0 ]]; then
  echo "FAIL config (unreadable .specflow.yml)"
  gate_fail "FAIL config (unreadable .specflow.yml)"
  FAIL=1
  STACK="none"
fi

# A curated fixture that copies run-quality-gates.sh without its lib/ (test_security_floor.sh's
# isolated floor scenario) has no coverage.sh; section 1 then falls back to the pre-REQ-325 plain
# pytest run below, never a hard failure over a missing library file.
COVERAGE_SH_OK=0
if [[ -f "$ROOT/scripts/lib/specflow/coverage.sh" ]]; then
  source "$ROOT/scripts/lib/specflow/coverage.sh"
  set +e
  COVERAGE_MIN_LINE="$(coverage_min_resolve)"
  CV_RC=$?
  set -e
  if [[ $CV_RC -ne 0 ]]; then
    echo "$COVERAGE_MIN_LINE"
    gate_fail "FAIL coverage_min ($COVERAGE_MIN_LINE)"
    FAIL=1
    COVERAGE_MIN_LINE="80 (default, unresolved)"
  fi
  export SPECFLOW_COVERAGE_MIN="${COVERAGE_MIN_LINE%% *}"
  COVERAGE_SH_OK=1
fi

# 1. Python tests
SECTION "Python tests (pytest)"
if [[ "$COVERAGE_SH_OK" == 1 ]] && find src -type f -name '*.py' 2>/dev/null | grep -q . && { [[ "$STACK" == python ]] || [[ "$STACK" == none ]]; }; then
  echo "coverage_min $COVERAGE_MIN_LINE"
  if pytest_cov "$SPECFLOW_COVERAGE_MIN"; then
    echo "PASS pytest (coverage_min $SPECFLOW_COVERAGE_MIN)"
  else
    echo "FAIL pytest (coverage_min $SPECFLOW_COVERAGE_MIN)"
    gate_fail "FAIL pytest (coverage_min $SPECFLOW_COVERAGE_MIN)"
    FAIL=1
  fi
elif [[ -d tests ]] && find tests -type f -name 'test_*.py' | grep -q .; then
  if python3 -m pytest tests/ -q; then
    echo "PASS pytest"
  else
    echo "FAIL pytest"
    gate_fail "FAIL pytest"
    FAIL=1
  fi
else
  echo "SKIP pytest (no test_*.py files)"
fi

# 2. Dafny verification
# Policy: if .dfy files exist but dafny is not installed, this is a hard fail
# (missing dependency), not a skip. Absence of the tool with proofs present
# silently passing would violate art-formal-verification.
SECTION "Dafny verification"
if find verification -type f -name '*.dfy' 2>/dev/null | grep -q .; then
  if command -v dafny >/dev/null 2>&1; then
    if dafny verify $(find verification -name '*.dfy'); then
      echo "PASS dafny"
    else
      echo "FAIL dafny"
      gate_fail "FAIL dafny"
      FAIL=1
    fi
  else
    echo "FAIL dafny (binary not installed but .dfy files present — install Dafny or remove proofs)"
    gate_fail "FAIL dafny (binary not installed but .dfy files present — install Dafny or remove proofs)"
    FAIL=1
  fi
else
  echo "SKIP dafny (no .dfy files)"
fi

# 3. Governance tests — SPECFLOW_GOV_JOBS at a time (default 4; 1 is a serial run), to keep the gates inside
# their 3-minute budget, the longest first. Each test's output is buffered and printed with its PASS/FAIL line in glob order, so the
# log reads as a serial run's would. Every test works under its own mktemp directory — none writes a shared repo path
# (.specflow/, dist/, coverage/; checked 2026-09-28), which is what makes running four at once safe.
SECTION "Governance tests"
if [[ -d tests/governance ]] && find tests/governance -type f -name 'test_*.sh' | grep -q .; then
  GOV_JOBS="${SPECFLOW_GOV_JOBS:-4}"
  [[ "$GOV_JOBS" =~ ^[1-9][0-9]*$ ]] || GOV_JOBS=4
  GOV_DIR="$(mktemp -d)"
  # The longest tests start first (measured 4-wide, P6 Build 3 final review): a long test that sorts late would otherwise
  # be the last one running, alone, and its length would land on the wall-clock. Then the rest, in glob order.
  GOV_FIRST="test_verify_release test_fenced_instance_gates test_verifier_run test_release_tag test_next_prs test_init test_release_smoke test_attestation test_security_disposition_gate test_verifier_isolation"
  GOV_ORDER=""
  for s in $GOV_FIRST; do
    if [[ -f "tests/governance/$s.sh" ]]; then GOV_ORDER="$GOV_ORDER tests/governance/$s.sh"; fi
  done
  for t in tests/governance/test_*.sh; do
    case " $GOV_ORDER " in *" $t "*) ;; *) GOV_ORDER="$GOV_ORDER $t" ;; esac
  done
  for t in $GOV_ORDER; do
    while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$GOV_JOBS" ]]; do sleep 0.1; done
    gk="$(basename "$t" .sh)"
    ( rc=0; bash "$t" > "$GOV_DIR/$gk.out" 2>&1 < /dev/null || rc=$?; echo "$rc" > "$GOV_DIR/$gk.rc" ) &
  done
  wait
  for t in tests/governance/test_*.sh; do
    gk="$(basename "$t" .sh)"
    cat "$GOV_DIR/$gk.out"
    if [[ "$(cat "$GOV_DIR/$gk.rc" 2>/dev/null || echo 1)" == 0 ]]; then
      echo "PASS $t"
    else
      echo "FAIL $t"
      gate_fail "FAIL $t"
      FAIL=1
    fi
  done
  rm -rf "$GOV_DIR"
else
  echo "SKIP governance (no test_*.sh files)"
fi

# 4. Per-stack hook (optional). STACK was resolved once above, ahead of section 1.
SECTION "Per-stack hook"
HOOK="scripts/quality-gates-${STACK}.sh"
if [[ "$STACK" == "none" ]]; then
  echo "SKIP per-stack hook (stack: none)"
elif [[ -x "$HOOK" ]]; then
  if "$HOOK"; then
    echo "PASS $HOOK"
  else
    echo "FAIL $HOOK"
    gate_fail "FAIL $HOOK"
    FAIL=1
  fi
else
  # A configured stack with no working hook is a gate failure, not a silent
  # SKIP (W-5) — lint/format would otherwise stop gating with no signal.
  echo "FAIL $HOOK (not present or not executable, but stack '$STACK' is configured)"
  gate_fail "FAIL $HOOK (not present or not executable, but stack '$STACK' is configured)"
  FAIL=1
fi

# 5. Security floor (REQ-330, REQ-360). Its own failures are listed apart from
# the gate failures above: a new advisory, a leak or a missing floor tool is a
# different signal from a broken test or lint hook.
SECTION "Security floor"
set +e
FLOOR_OUT=$(bash scripts/run-security-floor.sh 2>&1)
FLOOR_RC=$?
set -e
printf '%s\n' "$FLOOR_OUT"
if [[ $FLOOR_RC -ne 0 ]]; then
  FAIL=1
fi
FLOOR_FAIL_LINES=$(printf '%s\n' "$FLOOR_OUT" | grep '^FAIL floor' || true)

# 6. Document gates (REQ-320, REQ-327, REQ-380, REQ-323, REQ-306, REQ-394).
SECTION "Document gates"
for s in scripts/check-traceability.sh scripts/analyze-adr-plan-linkage.sh scripts/check-architecture.sh scripts/check-covers.sh; do
  [[ -f "$s" ]] || continue
  if bash "$s"; then
    echo "PASS $s"
  else
    echo "FAIL $s"
    gate_fail "FAIL $s"
    FAIL=1
  fi
done

# 7. Release gates (REQ-322, REQ-324). check-security-disposition.sh is the
# disposition wrapper; verify-release.sh is the PR-time release gate (it sees
# SPECFLOW_QG_RUNNING=1, exported above, and does not re-invoke the gates).
SECTION "Release gates"
for s in scripts/check-security-disposition.sh scripts/verify-release.sh; do
  [[ -f "$s" ]] || continue
  if bash "$s"; then
    echo "PASS $s"
  else
    echo "FAIL $s"
    gate_fail "FAIL $s"
    FAIL=1
  fi
done

SECTION "Summary"
if [[ -z "$GATE_FAIL_LINES" ]]; then
  echo "Gate failures: none"
else
  n=$(printf '%s' "$GATE_FAIL_LINES" | grep -c '^FAIL')
  echo "Gate failures ($n):"
  printf '%s' "$GATE_FAIL_LINES" | sed 's/^/  /'
fi
if [[ -z "$FLOOR_FAIL_LINES" ]]; then
  echo "Floor failures: none"
else
  n=$(printf '%s\n' "$FLOOR_FAIL_LINES" | grep -c '^FAIL')
  echo "Floor failures ($n) — advisories, a leak, a failed lookup or tool error, or a missing floor tool (see === Security floor ===):"
  printf '%s\n' "$FLOOR_FAIL_LINES" | sed 's/^/  /'
fi

if [[ $FAIL -eq 0 ]]; then
  echo "All quality gates passed"
  exit 0
fi
echo "One or more gates failed"
exit 1
