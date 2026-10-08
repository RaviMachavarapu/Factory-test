#!/usr/bin/env bash
# tauri stack pack — SECURITY hook (REQ-331). cwd = instance root.
#
# cargo-audit against src-tauri/Cargo.lock, with src-tauri/audit.toml's still-
# in-date ignore ids passed as --ignore (R4: cargo-audit itself never reads
# that file's ignoreUntil comments — floor.py ignores does). npm has no
# ignore file or --ignore flag, so its --json output is filtered here against
# osv-scanner.toml's still-in-date ids (R6); npm's own "error" object (a
# network failure) fails closed as "lookup failed", never as "no findings",
# and a high/critical advisory with no identifiable, ignored GHSA id fails.
set -euo pipefail
ROOT="$(pwd)"
source "$ROOT/scripts/lib/specflow/floor.sh"
CFG="$ROOT/scripts/lib/specflow/config.py"

FLOOR_FAIL=0

CARGO_AUDIT_VERSION="$(python3 "$CFG" --file .specflow/pack.yml get cargo_audit_version 2>/dev/null || true)"
CARGO_HINT="cargo install cargo-audit --locked --version ${CARGO_AUDIT_VERSION:-<pinned>}"

cargo_ignore_args=()
while IFS= read -r id; do
  [ -n "$id" ] && cargo_ignore_args+=(--ignore "$id")
done < <(_floor_py ignores --root . --source cargo)

if ! floor_tool --online cargo-audit . 'cargo audit --version' "$CARGO_HINT" -- \
    cargo audit --deny warnings --file src-tauri/Cargo.lock \
    ${cargo_ignore_args[@]+"${cargo_ignore_args[@]}"}; then
  FLOOR_FAIL=1
fi

# npm audit has no ignore file of its own; filter its JSON against
# osv-scanner.toml's still-in-date ids ourselves (R6). floor_emit is the
# shared grammar for a script that judges its own result.
osv_ignore_ids="$(_floor_py ignores --root . --source osv | tr '\n' ' ')"
NPM_VERSION="$(npm --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"

if [ -z "$NPM_VERSION" ]; then
  echo "FAIL floor npm-audit [.] (missing): not installed — install Node (npm ships with it); see bash scripts/init-project.sh --doctor"
  if [ -n "${SPECFLOW_FLOOR_RECORD:-}" ]; then
    _floor_py record --file "$SPECFLOW_FLOOR_RECORD" --tool npm-audit --scope . --version - --exit - \
      --status missing --result "not installed — install Node (npm ships with it)" --command "" || true
  fi
  FLOOR_FAIL=1
elif floor_offline; then
  printf 'SKIP floor npm-audit [.] (%s, offline): SPECFLOW_FLOOR_OFFLINE=1 — advisory lookup not run; not valid evidence for /security-review\n' "$NPM_VERSION"
  if [ -n "${SPECFLOW_FLOOR_RECORD:-}" ]; then
    _floor_py record --file "$SPECFLOW_FLOOR_RECORD" --tool npm-audit --scope . --version "$NPM_VERSION" --exit - \
      --status skipped-offline --result "not run — offline" --command "" || true
  fi
else
  NPM_RC=0
  NPM_ERR_FILE="$(mktemp)"
  # stderr apart from the JSON: npm's ordinary warnings must not turn a clean
  # report into unparsable output ("error, not findings").
  NPM_OUT=$(npm audit --audit-level=high --json 2>"$NPM_ERR_FILE") || NPM_RC=$?
  NPM_ERR="$(cat "$NPM_ERR_FILE")"; rm -f "$NPM_ERR_FILE"
  FILTER_OUT=$(NPM_JSON="$NPM_OUT" NPM_STDERR="$NPM_ERR" NPM_IGNORE="$osv_ignore_ids" python3 <<'PY'
import json, os, re, sys

raw = os.environ.get("NPM_JSON", "")
stderr = os.environ.get("NPM_STDERR", "")
ignore = set(os.environ.get("NPM_IGNORE", "").split())
NET = re.compile(
    r"connection (refused|reset|error|aborted)|could not resolve|no such host|"
    r"name or service not known|temporary failure in name resolution|timed out|"
    r"network is unreachable|failed to fetch|HTTPSConnectionPool|ENOTFOUND|"
    r"ECONNREFUSED|ECONNRESET|EAI_AGAIN|ETIMEDOUT",
    re.I,
)


def emit(status, detail):
    print(status)
    print((detail or "(no output)").strip().replace("\n", " ")[:160])
    sys.exit(0)


try:
    data = json.loads(raw)
except (json.JSONDecodeError, TypeError):
    both = (raw + " " + stderr).strip()
    emit("lookup-failed" if NET.search(both) else "error", both)

if not isinstance(data, dict):
    emit("error", raw)

if isinstance(data.get("error"), dict):
    text = json.dumps(data["error"])
    emit("lookup-failed" if NET.search(text) else "error", text)

# Fail closed: a high or critical entry passes only when every advisory behind
# it is identified by a GHSA id the ignore list names. A dict `via` is an
# advisory (its GHSA id comes from its url; none, or npm's own advisory url,
# is unidentifiable and fails); a string `via` names another package in this
# report, which is judged on its own entry — one the report does not list fails.
vulns = data.get("vulnerabilities") or {}
if not isinstance(vulns, dict):
    emit("error", raw)
bad = set()
for pkg, info in vulns.items():
    if not isinstance(info, dict):
        bad.add(f"{pkg} (unreadable entry)")
        continue
    if info.get("severity") not in ("high", "critical"):
        continue
    vias = info.get("via") or []
    if not vias:
        bad.add(f"{pkg} (no advisory named)")
    for via in vias:
        if isinstance(via, str):
            if via not in vulns:
                bad.add(f"{pkg} (via {via}, not in the report)")
            continue
        if not isinstance(via, dict):
            bad.add(f"{pkg} (unreadable via)")
            continue
        m = re.search(r"(GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4})", str(via.get("url") or ""))
        if not m:
            bad.add(f"{pkg} (advisory {via.get('source', '?')} has no GHSA id)")
        elif m.group(1) not in ignore:
            bad.add(m.group(1))
if bad:
    emit("fail", "unignored advisories: " + ", ".join(sorted(bad)))
emit("pass", "clean")
PY
  )
  NPM_STATUS=$(sed -n 1p <<<"$FILTER_OUT")
  NPM_DETAIL=$(sed -n 2p <<<"$FILTER_OUT")
  case "$NPM_STATUS" in
    pass) NPM_RESULT="clean" ;;
    fail) NPM_RESULT="findings — $NPM_DETAIL" ;;
    lookup-failed) NPM_RESULT="lookup failed — $NPM_DETAIL; rerun online, or set SPECFLOW_FLOOR_OFFLINE=1 to skip lookups (not evidence)" ;;
    *) NPM_STATUS=error; NPM_RESULT="error, not findings — $NPM_DETAIL" ;;
  esac
  if ! floor_emit "$NPM_STATUS" npm-audit . "$NPM_VERSION" "$NPM_RC" "$NPM_RESULT"; then
    FLOOR_FAIL=1
  fi
fi

[ "$FLOOR_FAIL" -eq 0 ] && exit 0
exit 1
