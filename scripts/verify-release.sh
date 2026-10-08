#!/usr/bin/env bash
# REQ-324: the PR-time release gate — thin wrapper over
# scripts/lib/specflow/release_gate.py, gate section 7. See R14.
# Usage: scripts/verify-release.sh [--version V | V] [--base REF]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RC=0
python3 "$ROOT/scripts/lib/specflow/release_gate.py" "$@" || RC=$?

# P6 R30: --at-tag (release.yml's replay) and --artifacts-only (build-source's comparison) never re-run the gates: the
# tagged tree is the ship PR's head tree, whose required gates run already passed.
for a in "$@"; do
  if [[ "$a" == "--at-tag" || "$a" == "--artifacts-only" ]]; then
    exit "$RC"
  fi
done

# R14: when run from inside run-quality-gates.sh (which exported this
# sentinel before any section ran), the gates are already running — do not
# re-invoke them (that would recurse). Run alone, run them last, as before.
if [[ "${SPECFLOW_QG_RUNNING:-}" == "1" ]]; then
  echo "note: under run-quality-gates.sh — not re-running the gates"
else
  if ! bash "$ROOT/scripts/run-quality-gates.sh"; then
    RC=1
  fi
fi

exit "$RC"
