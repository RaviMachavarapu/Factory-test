#!/usr/bin/env bash
# REQ-341 (ADR-003), REQ-340: /next's wrapper — thin over scripts/lib/specflow/pipeline.py derive, the one home of the
# fact collection and the output (the check-security-disposition.sh shape). It writes nothing: no file, index or ref
# (no git fetch, no bytecode, no optional index refresh) and, without an origin remote, never calls gh.
set -euo pipefail

export PYTHONDONTWRITEBYTECODE=1 GIT_OPTIONAL_LOCKS=0
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/specflow/pipeline.py" derive "$@"
