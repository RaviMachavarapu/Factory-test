#!/usr/bin/env bash
# REQ-333: the ARCHITECTURE exit-gate checker (.claude/rules/review-gate.md) — thin
# wrapper over scripts/lib/specflow/architecture.py check (the one home of the rule).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ARCH_BASE_DIR lets the fixture test point the walker at synthetic docs
# (same convention as TRACE_BASE_DIR in check-traceability.sh).
cd "${ARCH_BASE_DIR:-$ROOT}"

exec python3 "$ROOT/scripts/lib/specflow/architecture.py" check
