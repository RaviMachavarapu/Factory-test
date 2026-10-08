#!/usr/bin/env bash
# flutter stack pack — SECURITY hook (REQ-331). cwd = instance root.
#
# osv-scanner on pubspec.lock only, with the instance's osv-scanner.toml (or
# an empty temp config when there is none). Static hygiene (dart's own
# analyzer, fatal on infos) already runs in the gates hook (R7) and is not
# run a second time here.
set -euo pipefail
ROOT="$(pwd)"
source "$ROOT/scripts/lib/specflow/floor.sh"

FLOOR_FAIL=0
OSV_HINT='bash scripts/install-pinned-tool.sh osv-scanner --dest "$HOME/.local/bin"'
[ "$(uname -s)" = Darwin ] && OSV_HINT="$OSV_HINT, or brew install osv-scanner (Homebrew's version)"

CFG_FILE="osv-scanner.toml"
TMP_CFG=""
if [ ! -f "$CFG_FILE" ]; then
  TMP_CFG="$(mktemp)"; : > "$TMP_CFG"; CFG_FILE="$TMP_CFG"
fi

if ! floor_tool --online osv-scanner pubspec.lock 'osv-scanner --version' "$OSV_HINT" -- \
    osv-scanner scan source --config "$CFG_FILE" -L pubspec.lock; then
  FLOOR_FAIL=1
fi
[ -z "$TMP_CFG" ] || rm -f "$TMP_CFG"

[ "$FLOOR_FAIL" -eq 0 ] && exit 0
exit 1
