#!/usr/bin/env bash
# flutter stack pack — VALIDATE hook (REQ-303). cwd = instance root.
set -euo pipefail
FAIL=0

if flutter pub get --enforce-lockfile; then
  echo "PASS flutter pub get --enforce-lockfile"
else
  echo "FAIL flutter pub get --enforce-lockfile"
  FAIL=1
fi

if dart analyze --fatal-infos; then
  echo "PASS dart analyze --fatal-infos"
else
  echo "FAIL dart analyze --fatal-infos"
  FAIL=1
fi

# REQ-325: MIN is coverage.sh's resolved floor — the highest of SPECFLOW_COVERAGE_MIN, the working tree's and the
# base ref's coverage_min (the env can raise it, never lower it);
# exclusions come from pack.yml's coverage_exclude (never a literal list), one --exclude per entry.
if MIN_LINE="$(source scripts/lib/specflow/coverage.sh; coverage_min_resolve)"; then
  MIN="${MIN_LINE%% *}"
else
  echo "FAIL coverage_min does not resolve"
  exit 1
fi

if flutter test --coverage; then
  echo "PASS flutter test --coverage"
else
  echo "FAIL flutter test --coverage"
  FAIL=1
fi

if DART_EXCLUDE="$(source scripts/lib/specflow/coverage.sh; pack_coverage_exclude)"; then
  EXCLUDE_ARGS=()
  while IFS= read -r e; do [[ -n "$e" ]] && EXCLUDE_ARGS+=(--exclude "$e"); done <<<"$DART_EXCLUDE"
  if scripts/lcov-threshold.sh coverage/lcov.info "$MIN" ${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"}; then
    echo "PASS lcov-threshold.sh coverage/lcov.info $MIN"
  else
    echo "FAIL lcov-threshold.sh coverage/lcov.info $MIN"
    FAIL=1
  fi
else
  echo "$DART_EXCLUDE"
  FAIL=1
fi

exit $FAIL
