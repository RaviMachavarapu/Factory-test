#!/usr/bin/env bash
# python stack pack — SECURITY hook (REQ-331). cwd = instance root.
#
# pip-audit on the product lockfile (requirements.txt), or on
# scripts/requirements.txt with a printed note when there is no product
# lockfile (H16); bandit once per existing source_roots entry. Every ignore
# comes from `floor.py ignores`, never from reading osv-scanner.toml here
# (only ids whose ignoreUntil is still in date — the Ruling on expiry).
set -euo pipefail
ROOT="$(pwd)"
source "$ROOT/scripts/lib/specflow/floor.sh"
CFG="$ROOT/scripts/lib/specflow/config.py"

FLOOR_FAIL=0
PIP_AUDIT_HINT="pip install --require-hashes -r requirements.txt"

LOCKFILE="requirements.txt"
if [ ! -f "$LOCKFILE" ]; then
  echo "note: no product lockfile (requirements.txt); auditing the factory tooling lockfile scripts/requirements.txt"
  LOCKFILE="scripts/requirements.txt"
fi

ignore_args=()
while IFS= read -r id; do
  [ -n "$id" ] && ignore_args+=(--ignore-vuln "$id")
done < <(_floor_py ignores --root . --source osv)

if ! floor_tool --online pip-audit "$LOCKFILE" 'python3 -m pip_audit --version' "$PIP_AUDIT_HINT" -- \
    python3 -m pip_audit -r "$LOCKFILE" --strict --disable-pip --progress-spinner off \
    ${ignore_args[@]+"${ignore_args[@]}"}; then
  FLOOR_FAIL=1
fi

roots=()
while IFS= read -r sr; do [ -n "$sr" ] && roots+=("$sr"); done \
  < <(python3 "$CFG" --file .specflow/pack.yml getlist source_roots 2>/dev/null || echo src)
[ "${#roots[@]}" -gt 0 ] || roots=(src)

for sr in "${roots[@]}"; do
  [ -d "$sr" ] || continue
  if ! floor_tool bandit "$sr" 'python3 -m bandit --version' "$PIP_AUDIT_HINT" -- \
      python3 -m bandit -r "$sr" --severity-level high --confidence-level medium -q; then
    FLOOR_FAIL=1
  fi
done

[ "$FLOOR_FAIL" -eq 0 ] && exit 0
exit 1
