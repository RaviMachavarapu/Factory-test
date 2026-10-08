# scripts/lib/specflow/coverage.sh — REQ-325's coverage floor, python (R16). Sourced by
# run-quality-gates.sh (section 1) and, from Task 12, the app-stack pack hooks; never executed
# directly. `coverage_min` and `coverage_exclude` are read at the base ref with plain `git show`
# plus config.py — never through the verifier's policy classifier (R16: a coverage key must never
# turn the `verifier` check red, and that classifier stays solo/profile/path only).
CV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CV_CFG="$CV_DIR/config.py"

_cv_is_int() {  # _cv_is_int VALUE — 0-100
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -le 100 ]
}

_cv_base_get() {  # _cv_base_get REF FILE KEY DEFAULT — KEY's value in FILE at REF (git show), or DEFAULT
  local ref="$1" file="$2" key="$3" def="$4" tmp
  tmp="$(mktemp)" || { printf '%s\n' "$def"; return 0; }
  if git show "${ref}:${file}" > "$tmp" 2>/dev/null; then
    python3 "$CV_CFG" --file "$tmp" get "$key" --default "$def"
  else
    printf '%s\n' "$def"
  fi
  rm -f "$tmp"
}

_cv_base_getlist() {  # _cv_base_getlist REF FILE KEY — one item per line (empty output: none, or FILE/KEY absent at REF)
  local ref="$1" file="$2" key="$3" tmp
  tmp="$(mktemp)" || return 0
  if git show "${ref}:${file}" > "$tmp" 2>/dev/null; then
    python3 "$CV_CFG" --file "$tmp" getlist "$key" 2>/dev/null || true
  fi
  rm -f "$tmp"
}

coverage_min_resolve() {  # prints "<n> (<source>)": the highest of SPECFLOW_COVERAGE_MIN (when set), the working
  # tree's coverage_min and, with SPECFLOW_BASE_REF, the base ref's — the env can raise the floor, never lower it
  local own base env max src
  own="$(python3 "$CV_CFG" get coverage_min --default 80)"
  if ! _cv_is_int "$own"; then
    echo "coverage_min: $own (working tree .specflow.yml) must be an integer 0-100" >&2
    return 2
  fi
  max="$own"; src="working tree"
  if [[ -n "${SPECFLOW_BASE_REF:-}" ]]; then
    base="$(_cv_base_get "$SPECFLOW_BASE_REF" .specflow.yml coverage_min 80)"
    if ! _cv_is_int "$base"; then
      echo "coverage_min: $base ($SPECFLOW_BASE_REF:.specflow.yml) must be an integer 0-100" >&2
      return 2
    fi
    if [ "$base" -gt "$max" ]; then
      max="$base"; src="base $SPECFLOW_BASE_REF"
    fi
  fi
  if [[ -n "${SPECFLOW_COVERAGE_MIN:-}" ]]; then
    env="$SPECFLOW_COVERAGE_MIN"
    if ! _cv_is_int "$env"; then
      echo "coverage_min: SPECFLOW_COVERAGE_MIN=$env must be an integer 0-100" >&2
      return 2
    fi
    if [ "$env" -gt "$max" ]; then
      max="$env"; src="env SPECFLOW_COVERAGE_MIN"
    fi
  fi
  printf '%s (%s)\n' "$max" "$src"
}

pack_coverage_exclude() {  # one coverage_exclude entry per line (none in the template source: no .specflow/pack.yml);
  # FAILs and returns 1 when the working tree names an entry the base ref's pack.yml does not (R16).
  local own base entry found other
  own=""
  if [[ -f .specflow/pack.yml ]]; then
    own="$(python3 "$CV_CFG" --file .specflow/pack.yml getlist coverage_exclude 2>/dev/null || true)"
  fi
  if [[ -n "${SPECFLOW_BASE_REF:-}" ]] && git show "${SPECFLOW_BASE_REF}:.specflow/pack.yml" > /dev/null 2>&1; then
    base="$(_cv_base_getlist "$SPECFLOW_BASE_REF" .specflow/pack.yml coverage_exclude)"
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      found=0
      while IFS= read -r other; do
        [[ "$entry" == "$other" ]] && { found=1; break; }
      done <<<"$base"
      if [[ $found -eq 0 ]]; then
        echo "FAIL coverage_exclude gains $entry — a PR cannot widen its own exclusions (base ${SPECFLOW_BASE_REF})"
        return 1
      fi
    done <<<"$own"
  fi
  [[ -n "$own" ]] && printf '%s\n' "$own"
  return 0
}

_cv_pytest_ini() {  # _cv_pytest_ini FILE — the gate's own pytest ini: [pytest] carrying only the allowlisted keys
  # (pythonpath) from pyproject.toml's [tool.pytest.ini_options], as absolute paths inside the working tree. Never
  # addopts, never any other key: a PR's pytest.ini, tox.ini, setup.cfg or pyproject.toml cannot switch measurement off.
  python3 - "$1" <<'PY'
import os, shlex, sys
root = os.path.realpath(os.getcwd())
keep = []
try:
    import tomllib
    with open("pyproject.toml", "rb") as fh:
        opts = tomllib.load(fh).get("tool", {}).get("pytest", {}).get("ini_options", {})
except (ImportError, OSError, ValueError):
    opts = {}
pp = opts.get("pythonpath", [])
if isinstance(pp, str):
    pp = pp.split()
for e in pp if isinstance(pp, list) else []:
    full = os.path.realpath(os.path.join(root, str(e)))
    if full == root or full.startswith(root + os.sep):
        keep.append(full)
    else:
        print(f"coverage: pythonpath entry {e!r} leaves the working tree - not carried", file=sys.stderr)
with open(sys.argv[1], "w") as out:
    out.write("[pytest]\n")
    if keep:
        out.write("pythonpath = " + " ".join(shlex.quote(k) for k in keep) + "\n")
PY
}

pytest_cov() {  # pytest_cov MIN — pytest tests/ with --cov=src --cov-fail-under=MIN and this file's own
  # --cov-config (never a repository .coveragerc/setup.cfg/pyproject.toml; no exclude_lines, so no
  # '# pragma: no cover' is honoured), COVERAGE_FILE under mktemp -d
  # so no .coverage file is left in the tree. pytest's own configuration is the gate's too: -c <temp ini> (only the
  # allowlisted pythonpath carried, never addopts), --rootdir the working tree, -p no:cacheprovider, PYTEST_ADDOPTS
  # unset. Residual: a conftest.py is arbitrary code and can still monkeypatch pytest-cov or coverage internals —
  # code mode names pytest config and conftest.py edits as gate code.
  local min="$1" omit rc covdir covcfg pyini
  if ! python3 -c 'import pytest_cov' >/dev/null 2>&1; then
    echo "FAIL pytest-cov missing — pip install --require-hashes -r scripts/requirements.txt"
    return 1
  fi
  omit="$(pack_coverage_exclude)" || { printf '%s\n' "$omit"; return 1; }
  covdir="$(mktemp -d)"
  covcfg="$(mktemp)"
  {
    echo "[run]"
    if [[ -n "$omit" ]]; then
      echo "omit ="
      while IFS= read -r e; do [[ -n "$e" ]] && printf '    %s\n' "$e"; done <<<"$omit"
    fi
    # An empty exclude_lines replaces coverage.py's default (which honours '# pragma: no cover'), so no
    # in-source pragma can narrow what the floor measures; the pack's coverage_exclude is the only exclusion.
    echo "[report]"
    echo "exclude_lines ="
  } > "$covcfg"
  pyini="$covdir/pytest.ini"
  _cv_pytest_ini "$pyini" || { rm -rf "$covdir" "$covcfg"; echo "FAIL could not write the gate's pytest ini"; return 1; }
  rc=0
  env -u PYTEST_ADDOPTS COVERAGE_FILE="$covdir/.coverage" python3 -m pytest -c "$pyini" --rootdir "$PWD" \
    -p no:cacheprovider tests/ -q --cov=src --cov-config="$covcfg" \
    --cov-report=term-missing:skip-covered --cov-fail-under="$min" || rc=$?
  rm -rf "$covdir" "$covcfg"
  return $rc
}
