#!/usr/bin/env bash
# Governance test: the Python files this template SHIPS (src/, tests/) must pass
# the ruff + black gate that init-project.sh generates for the `python` stack.
# Otherwise a fresh python-stack instance fails its very first VALIDATE run on
# the shipped code (the failure class found by the end-to-end clone check).
#
# The factory's own template source has no .specflow.yml/.stack, so its
# per-stack hook never lint/format-checks these files — this test is what
# keeps the shipped Python clean. In an instantiated instance (.specflow.yml
# or a legacy .stack present) the per-stack hook owns lint/format for the
# user's chosen stack, so skip here (a non-python instance has no ruff/black).
# Covers: REQ-334
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }
pass() { echo "ok:   $1"; }

if [[ -f .specflow.yml || -f .stack ]]; then
  pass "instantiated instance (.specflow.yml or .stack present) — per-stack hook owns lint/format; skipping"
  echo "test_python_lint_format: all checks passed"
  exit 0
fi

# Template source: src/ tests/ is exactly the scope quality-gates-python.sh checks.
if ! python3 -m ruff --version >/dev/null 2>&1; then
  fail "ruff not installed — run 'pip install -r scripts/requirements.txt' (gate dependency)"
elif out=$(python3 -m ruff check src/ tests/ 2>&1); then
  pass "ruff: shipped src/ tests/ clean"
else
  fail "ruff found issues in shipped src/ tests/ (a python-stack instance would fail its gate):"
  printf '%s\n' "$out" | sed 's/^/    /'
fi

if ! python3 -m black --version >/dev/null 2>&1; then
  fail "black not installed — run 'pip install -r scripts/requirements.txt' (gate dependency)"
elif out=$(python3 -m black --check src/ tests/ 2>&1); then
  pass "black: shipped src/ tests/ clean"
else
  fail "black would reformat shipped src/ tests/ (a python-stack instance would fail its gate):"
  printf '%s\n' "$out" | sed 's/^/    /'
fi

# REQ-334: the installed ruff and black satisfy the ranges in scripts/requirements.in (this test's range source).
range_report=$(python3 - <<'PY'
import re, subprocess, sys
def ver(t):
    p = subprocess.run([sys.executable, "-m", t, "--version"], capture_output=True, text=True)
    m = re.search(r"(\d+\.\d+(?:\.\d+)?)", p.stdout + p.stderr)
    return tuple(int(x) for x in m.group(1).split(".")) if m else None
def ok(v, spec):
    for part in spec.split(","):
        m = re.match(r"\s*(>=|<=|==|<|>)\s*([\d.]+)\s*$", part)
        if not m:
            return False
        w = tuple(int(x) for x in m.group(2).split("."))
        n = max(len(v), len(w)); a = v + (0,) * (n - len(v)); b = w + (0,) * (n - len(w))
        if not {">=": a >= b, "<=": a <= b, "==": a == b, "<": a < b, ">": a > b}[m.group(1)]:
            return False
    return True
out, seen = [], set()
for line in open("scripts/requirements.in"):
    m = re.match(r"^(ruff|black)\s*([<>=!~].*)$", line.strip())
    if m:
        seen.add(m.group(1)); v = ver(m.group(1))
        if v is None or not ok(v, m.group(2)):
            out.append(f"{m.group(1)} {'.'.join(map(str, v)) if v else 'missing'} does not satisfy {m.group(2)}")
if seen != {"ruff", "black"}:
    out.append("scripts/requirements.in lacks a ruff or black range")
print("; ".join(out))
PY
)
if [[ -z "$range_report" ]]; then pass "ruff and black satisfy scripts/requirements.in"
else fail "$range_report — run: pip install --require-hashes -r scripts/requirements.txt"; fi

if [[ $FAIL -ne 0 ]]; then
  echo "test_python_lint_format: FAILED"
  exit 1
fi
echo "test_python_lint_format: all checks passed"
