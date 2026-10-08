#!/usr/bin/env bash
# The security floor's one tool-running contract (REQ-330, REQ-360). Sourced by
# scripts/run-security-floor.sh and by each instance's scripts/security-<stack>.sh.
#
# floor_tool [--online] TOOL SCOPE VERSION_CMD INSTALL_HINT -- CMD ARGS…
#
# Prints exactly one "Floor lines" line (see the P4 plan's Interfaces) and returns
# 0 or 1. Only this function prints those lines; only floor.py writes the summary.
#
# Env:
#   SPECFLOW_FLOOR_OFFLINE=1   — with --online, skip CMD (print SKIP, return 0).
#   SPECFLOW_FLOOR_RECORD=FILE — append this outcome via `floor.py record`.

floor_offline() { [ "${SPECFLOW_FLOOR_OFFLINE:-0}" = 1 ]; }

_floor_py() {
  python3 "$(dirname "${BASH_SOURCE[0]}")/floor.py" "$@"
}

_floor_first_error_line() {
  # The first line matching the network-error pattern, else the last non-empty
  # line, cut to 160 characters.
  local text="$1"
  local pat='connection (refused|reset|error|aborted)|could not resolve|no such host|name or service not known|temporary failure in name resolution|timed out|network is unreachable|failed to fetch|HTTPSConnectionPool|ENOTFOUND|ECONNREFUSED|ECONNRESET|EAI_AGAIN|ETIMEDOUT'
  local hit
  hit=$(printf '%s\n' "$text" | grep -iE "$pat" | head -1 || true)
  if [ -z "$hit" ]; then
    hit=$(printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | tail -1 || true)
  fi
  printf '%.160s' "$hit"
}

_floor_is_network_error() {
  printf '%s\n' "$1" | grep -qiE 'connection (refused|reset|error|aborted)|could not resolve|no such host|name or service not known|temporary failure in name resolution|timed out|network is unreachable|failed to fetch|HTTPSConnectionPool|ENOTFOUND|ECONNREFUSED|ECONNRESET|EAI_AGAIN|ETIMEDOUT'
}

floor_emit() {  # floor_emit STATUS TOOL SCOPE VERSION EXIT RESULT — for results a script computes itself (npm filter)
  local status="$1" tool="$2" scope="$3" version="$4" exit_code="$5" result="$6"
  case "$status" in
    pass) printf 'PASS floor %s [%s] (%s, exit %s): %s\n' "$tool" "$scope" "$version" "$exit_code" "$result" ;;
    *)    printf 'FAIL floor %s [%s] (%s, exit %s): %s\n' "$tool" "$scope" "$version" "$exit_code" "$result" ;;
  esac
  if [ -n "${SPECFLOW_FLOOR_RECORD:-}" ]; then
    local exit_arg="$exit_code"; [ "$exit_arg" = "-" ] && exit_arg="-"
    _floor_py record --file "$SPECFLOW_FLOOR_RECORD" --tool "$tool" --scope "$scope" --version "$version" \
      --exit "$exit_arg" --status "$status" --result "$result" --command "" || true
  fi
  [ "$status" = pass ] || [ "$status" = not-applicable ]
}

floor_tool() {
  local online=0
  if [ "${1:-}" = --online ]; then online=1; shift; fi
  local tool="$1" scope="$2" version_cmd="$3" install_hint="$4"; shift 4
  [ "${1:-}" = -- ] || { echo "floor_tool: expected -- before the command" >&2; return 2; }
  shift

  local vout vrc=0
  vout=$(eval "$version_cmd" 2>/dev/null) || vrc=$?
  if [ $vrc -ne 0 ] || [ -z "$vout" ]; then
    printf 'FAIL floor %s [%s] (missing): not installed — %s; see bash scripts/init-project.sh --doctor\n' "$tool" "$scope" "$install_hint"
    if [ -n "${SPECFLOW_FLOOR_RECORD:-}" ]; then
      _floor_py record --file "$SPECFLOW_FLOOR_RECORD" --tool "$tool" --scope "$scope" --version "-" \
        --exit - --status missing --result "not installed — $install_hint" --command "$*" || true
    fi
    return 1
  fi
  local version
  version=$(printf '%s' "$vout" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
  [ -n "$version" ] || version="$vout"

  if [ "$online" = 1 ] && floor_offline; then
    printf 'SKIP floor %s [%s] (%s, offline): SPECFLOW_FLOOR_OFFLINE=1 — advisory lookup not run; not valid evidence for /security-review\n' \
      "$tool" "$scope" "$version"
    if [ -n "${SPECFLOW_FLOOR_RECORD:-}" ]; then
      _floor_py record --file "$SPECFLOW_FLOOR_RECORD" --tool "$tool" --scope "$scope" --version "$version" \
        --exit - --status skipped-offline --result "not run — offline" --command "$*" || true
    fi
    return 0
  fi

  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  local status result
  if [ "$rc" -eq 0 ]; then
    status=pass; result=clean
  else
    if [ "$online" = 1 ] && _floor_is_network_error "$out"; then
      status=lookup-failed
      result="lookup failed — $(_floor_first_error_line "$out"); rerun online, or set SPECFLOW_FLOOR_OFFLINE=1 to skip lookups (not evidence)"
    elif [ "$rc" != 1 ]; then
      status=error
      result="error, not findings — $(_floor_first_error_line "$out")"
    else
      status=fail
      result="findings — see the tool output above"
    fi
  fi

  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$status" = pass ]; then
    printf 'PASS floor %s [%s] (%s, exit %s): %s\n' "$tool" "$scope" "$version" "$rc" "$result"
  else
    printf 'FAIL floor %s [%s] (%s, exit %s): %s\n' "$tool" "$scope" "$version" "$rc" "$result"
  fi
  if [ -n "${SPECFLOW_FLOOR_RECORD:-}" ]; then
    _floor_py record --file "$SPECFLOW_FLOOR_RECORD" --tool "$tool" --scope "$scope" --version "$version" \
      --exit "$rc" --status "$status" --result "$result" --command "$*" || true
  fi
  [ "$status" = pass ]
}
