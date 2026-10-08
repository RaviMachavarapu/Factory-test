#!/usr/bin/env bash
# REQ-322 (ADR-002): the PR-time security-disposition gate — thin wrapper over
# scripts/lib/specflow/disposition_gate.py, gate section 7. See R11-R13.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# --root points the gate at a data tree that need not be $ROOT (e.g. a pack's
# skeleton, stacks/tauri/overlay); the script itself always runs from ROOT.
DATA_ROOT="$ROOT"
prev=""
for a in "$@"; do
  if [ "$prev" = "--root" ]; then
    DATA_ROOT="$a"
  fi
  prev="$a"
done
cd "$DATA_ROOT"

exec python3 "$ROOT/scripts/lib/specflow/disposition_gate.py" "$@"
