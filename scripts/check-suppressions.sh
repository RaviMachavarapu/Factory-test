#!/usr/bin/env bash
# REQ-388: thin wrapper over `floor.py suppressions` (the one home of the rule).
# Usage: check-suppressions.sh [--root DIR] [--json]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
root="$ROOT"
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      root="$2"; shift 2 ;;
    *)
      args+=("$1"); shift ;;
  esac
done
exec python3 "$ROOT/scripts/lib/specflow/floor.py" suppressions --root "$root" ${args[@]+"${args[@]}"}
