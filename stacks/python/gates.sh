#!/usr/bin/env bash
# python stack pack — VALIDATE hook (REQ-303). pytest itself stays in the
# core gates (run-quality-gates.sh §1); this hook covers lint + format.
set -euo pipefail
FAIL=0
if python3 -m ruff check src tests; then
  echo "PASS ruff"
else
  echo "FAIL ruff"
  FAIL=1
fi
if python3 -m black --check src tests; then
  echo "PASS black"
else
  echo "FAIL black"
  FAIL=1
fi
exit $FAIL
