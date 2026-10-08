#!/usr/bin/env bash
# tauri stack pack — VALIDATE hook (REQ-303). cwd = instance root.
set -euo pipefail
FAIL=0

if npm ci; then
  echo "PASS npm ci"
else
  echo "FAIL npm ci"
  FAIL=1
fi

if npx --no tsc; then
  echo "PASS tsc"
else
  echo "FAIL tsc"
  FAIL=1
fi

# REQ-325: MIN is coverage.sh's resolved floor — the highest of SPECFLOW_COVERAGE_MIN, the working tree's and the
# base ref's coverage_min (the env can raise it, never lower it); exclusions
# come from pack.yml's coverage_exclude (never a literal list) via pack_coverage_exclude.
if MIN_LINE="$(source scripts/lib/specflow/coverage.sh; coverage_min_resolve)"; then
  MIN="${MIN_LINE%% *}"
else
  echo "FAIL coverage_min does not resolve"
  exit 1
fi

if npx --no vitest run --coverage "--coverage.thresholds.lines=$MIN"; then
  echo "PASS vitest run --coverage.thresholds.lines=$MIN"
else
  echo "FAIL vitest run --coverage.thresholds.lines=$MIN"
  FAIL=1
fi

if RS_EXCLUDE="$(source scripts/lib/specflow/coverage.sh; pack_coverage_exclude)"; then
  IGNORE_RX="$(python3 - "$RS_EXCLUDE" <<'PY'
import re, sys
entries = sys.argv[1].split()
rs = [e for e in entries if e.endswith(".rs")]
print("|".join(f"(^|/){re.escape(e)}$" for e in rs))
PY
)"
else
  echo "$RS_EXCLUDE"
  FAIL=1
  IGNORE_RX=""
fi

# An empty --ignore-filename-regex would join cargo-llvm-cov's defaults as an empty alternative that matches every
# path, so the flag is passed only when coverage_exclude names a .rs file.
LLVM_COV_ARGS=(--locked --fail-under-lines "$MIN")
if [[ -n "$IGNORE_RX" ]]; then
  LLVM_COV_ARGS+=(--ignore-filename-regex "$IGNORE_RX")
fi
if (cd src-tauri && cargo llvm-cov "${LLVM_COV_ARGS[@]}"); then
  echo "PASS cargo llvm-cov --fail-under-lines $MIN (src-tauri)"
else
  echo "FAIL cargo llvm-cov --fail-under-lines $MIN (src-tauri)"
  FAIL=1
fi

exit $FAIL
