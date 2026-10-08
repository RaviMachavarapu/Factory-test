#!/usr/bin/env bash
# The security floor (REQ-330, REQ-360): gitleaks over the full git history with
# the repository's own .gitleaks.toml, osv-scanner over every tracked lockfile
# with one config, then (in an instance) the stack's own security-<stack>.sh.
# A missing floor tool is a hard FAIL with an install hint, exactly as a missing
# Dafny already is. Writes a machine-readable summary for /security-review.
#
# Usage: run-security-floor.sh [--summary PATH]
#
# Exit 0 iff no "FAIL floor" line was printed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/lib/specflow/floor.sh"

SUMMARY_PATH=".specflow/floor-summary.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --summary) SUMMARY_PATH="$2"; shift 2 ;;
    *) echo "run-security-floor: unknown option: $1" >&2; exit 2 ;;
  esac
done

RECORD_FILE="$(mktemp)"
trap 'rm -f "$RECORD_FILE"' EXIT
export SPECFLOW_FLOOR_RECORD="$RECORD_FILE"

FLOOR_FAIL=0
FLOOR_MODE=online
[ "${SPECFLOW_FLOOR_OFFLINE:-0}" = 1 ] && FLOOR_MODE=offline

instance() { [ -f .specflow.yml ] || [ -f .stack ]; }
is_template_source() { [ ! -f .specflow.yml ] && [ ! -f .stack ] && [ -d stacks ]; }

_write_summary() {
  _floor_py summarize --records "$RECORD_FILE" --out "$SUMMARY_PATH" --mode "$FLOOR_MODE" --root . || true
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL floor gitleaks [.] (missing): not a git work tree — the floor needs git history; see bash scripts/init-project.sh --doctor"
  _floor_py record --file "$RECORD_FILE" --tool gitleaks --scope . --version - --exit - --status error \
    --result "not a git work tree" --command "" || true
  _write_summary
  exit 1
fi

GITLEAKS_HINT='bash scripts/install-pinned-tool.sh gitleaks --dest "$HOME/.local/bin"'
OSV_HINT='bash scripts/install-pinned-tool.sh osv-scanner --dest "$HOME/.local/bin"'
if [ "$(uname -s)" = Darwin ]; then
  GITLEAKS_HINT="$GITLEAKS_HINT, or brew install gitleaks (Homebrew's version)"
  OSV_HINT="$OSV_HINT, or brew install osv-scanner (Homebrew's version)"
fi

# 1. gitleaks — the full history, the repository's own .gitleaks.toml (R8, R16).
GL_CONFIG=""
[ -f .gitleaks.toml ] && GL_CONFIG="--config .gitleaks.toml"
if ! floor_tool gitleaks . 'env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML gitleaks version' "$GITLEAKS_HINT" -- \
    env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML gitleaks git --no-banner --redact --log-level warn \
    --ignore-gitleaks-allow --exit-code 1 $GL_CONFIG .; then
  FLOOR_FAIL=1
fi

# 2. osv-scanner — tracked lockfiles only (R3).
LOCKFILE_PATTERN='^(requirements(-runtime)?\.txt|uv\.lock|poetry\.lock|Pipfile\.lock|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|pubspec\.lock|Gemfile\.lock|composer\.lock|go\.mod)$'

osv_lockfiles() {  # osv_lockfiles DIR EXCLUDE_STACKS(0|1) — tracked lockfiles under DIR, relative to the repo root
  local dir="$1" exclude_stacks="$2" f b
  git ls-files -- "$dir" 2>/dev/null | while IFS= read -r f; do
    if [ "$exclude_stacks" = 1 ]; then
      case "$f" in stacks/*) continue ;; esac
    fi
    b="$(basename "$f")"
    if [[ "$b" =~ $LOCKFILE_PATTERN ]]; then printf '%s\n' "$f"; fi
  done
}

osv_lists_no_package() {  # osv_lists_no_package FILE — true for a requirements*.txt with no requirement line (comments and
  # blank lines only): osv-scanner exits 128 ("No package sources found") when every lockfile it is given is such a file
  # (the python skeleton's requirements-runtime.txt before any runtime dependency), so the floor leaves it out, noted.
  case "$(basename "$1")" in requirements*.txt) ;; *) return 1 ;; esac
  ! grep -qvE '^[[:space:]]*(#.*)?$' "$1"
}

osv_scan() {  # osv_scan DIR SCOPE EXCLUDE_STACKS(0|1)
  local dir="$1" scope="$2" exclude_stacks="$3"
  local vout vrc=0
  vout=$(osv-scanner --version 2>/dev/null) || vrc=$?
  if [ $vrc -ne 0 ] || [ -z "$vout" ]; then
    echo "FAIL floor osv-scanner [$scope] (missing): not installed — $OSV_HINT; see bash scripts/init-project.sh --doctor"
    _floor_py record --file "$RECORD_FILE" --tool osv-scanner --scope "$scope" --version - --exit - --status missing \
      --result "not installed — $OSV_HINT" --command "" || true
    FLOOR_FAIL=1
    return
  fi
  local version
  version=$(printf '%s' "$vout" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
  [ -n "$version" ] || version="$vout"

  local locks=() omitted=() f tracked=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    tracked=1
    if osv_lists_no_package "$f"; then
      echo "NOTE floor osv-scanner [$scope]: $f lists no package — not scanned (osv-scanner finds no package source in it)"
      omitted+=("$f")
      continue
    fi
    locks+=("$f")
  done < <(osv_lockfiles "$dir" "$exclude_stacks")

  if [ "${#locks[@]}" -eq 0 ]; then
    local why="not run — no tracked lockfile"
    [ "$tracked" = 0 ] || why="not run — no tracked lockfile lists a package"
    echo "PASS floor osv-scanner [$scope] ($version, not run): $why"
    # The record carries the one not-run result floor.py check-review accepts beside exit '-' (floor.py NOT_RUN_RESULT):
    # a lockfile that lists no package is no lockfile to scan; the printed line above says which case it was.
    _floor_py record --file "$RECORD_FILE" --tool osv-scanner --scope "$scope" --version "$version" --exit - \
      --status not-applicable --result "not run — no tracked lockfile" --command "" || true
    return
  fi

  local cfg tmp_cfg=""
  if [ "$dir" = "." ]; then cfg="osv-scanner.toml"; else cfg="$dir/osv-scanner.toml"; fi
  if [ ! -f "$cfg" ]; then
    tmp_cfg="$(mktemp)"; : > "$tmp_cfg"; cfg="$tmp_cfg"
  fi
  local largs=()
  for f in "${locks[@]}"; do largs+=(-L "$f"); done
  if ! floor_tool --online osv-scanner "$scope" "echo $version" "$OSV_HINT" -- \
      osv-scanner scan source --config "$cfg" "${largs[@]}"; then
    FLOOR_FAIL=1
  fi
  [ -z "$tmp_cfg" ] || rm -f "$tmp_cfg"
  # A lockfile left out above is named in the record the review's '## Tools run' renders, not on stdout alone: the
  # record floor_tool just appended for this scope gains the suffix (a later record for a tool and scope replaces it).
  if [ "${#omitted[@]}" -gt 0 ]; then
    python3 - "$RECORD_FILE" "$scope" "${omitted[@]}" <<'PY' || { echo "FAIL floor osv-scanner [$scope]: the omission could not be recorded"; FLOOR_FAIL=1; }
import json, sys
path, scope, files = sys.argv[1], sys.argv[2], sys.argv[3:]
lines = open(path).read().splitlines()
rec = json.loads(lines[-1])
assert (rec["tool"], rec["scope"]) == ("osv-scanner", scope), rec
noun = "empty lockfile" if len(files) == 1 else "empty lockfiles"
rec["result"] = f"{rec['result']}; {noun} {', '.join(files)} omitted"
lines[-1] = json.dumps(rec)
open(path, "w").write("\n".join(lines) + "\n")
PY
  fi
}

if is_template_source; then
  osv_scan . . 1
  shopt -s nullglob
  for d in stacks/*/overlay stacks/*/skeleton; do
    [ -d "$d" ] || continue
    osv_scan "$d" "$d" 0
  done
  shopt -u nullglob
else
  osv_scan . . 0
fi

# 3. The stack's own security script (instances only).
if instance; then
  STACK="$(python3 "$ROOT/scripts/lib/specflow/config.py" --root . get stack --default none)"
  if [ -n "$STACK" ] && [ "$STACK" != none ]; then
    SEC_SCRIPT="scripts/security-${STACK}.sh"
    if [ -x "$SEC_SCRIPT" ]; then
      if ! bash "$SEC_SCRIPT"; then
        FLOOR_FAIL=1
      fi
    else
      echo "FAIL floor security-${STACK}.sh [.] (missing): not present or not executable — chmod +x $SEC_SCRIPT; see bash scripts/init-project.sh --doctor"
      _floor_py record --file "$RECORD_FILE" --tool "security-${STACK}.sh" --scope . --version - --exit - \
        --status missing --result "not present or not executable" --command "" || true
      FLOOR_FAIL=1
    fi
  fi
fi

# 4. The summary.
_write_summary

[ "$FLOOR_FAIL" -eq 0 ] && exit 0
exit 1
