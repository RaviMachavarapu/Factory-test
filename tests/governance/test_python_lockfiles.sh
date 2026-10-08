#!/usr/bin/env bash
# REQ-334: ranges live in scripts/requirements.in; scripts/requirements.txt is pip-compile --generate-hashes output
# installed with --require-hashes. REQ-330's first task: the pins clear the floor (black >= 26.3.1 fixes
# PYSEC-2026-2120/2121, reported by osv-scanner and pip-audit on 2026-09-26). The python pack's lockfile carries the
# stack's floor tools (pip-audit, bandit) and the same gate-tool pins as the template's.
# Covers: REQ-334
# Covers: REQ-330
# Covers: REQ-325
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
IN=scripts/requirements.in; TXT=scripts/requirements.txt; SK=stacks/python/skeleton
ck "$IN exists" test -f "$IN"
for t in pytest pytest-cov ruff black build setuptools wheel; do
  ck "$IN: $t as a range, never '=='" bash -c 'grep -qiE "^$2([<>=!~ ]|$)" "$1" && ! grep -qiE "^$2==" "$1"' _ "$IN" "$t"
done
ck "$TXT is pip-compile --generate-hashes output" bash -c 'grep -q "pip-compile" "$1" && grep -q -- "--generate-hashes" "$1"' _ "$TXT"
pins() { python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read().replace("\\\n", " ")
for line in text.splitlines():
    m = re.match(r"^([A-Za-z0-9_.-]+)==([^ ;\\]+)(.*)$", line)
    if m:
        print(m.group(1).lower(), m.group(2), "hashed" if "--hash=sha256:" in m.group(3) else "unhashed")
PY
}
tp=$(pins "$TXT")
for t in pytest pytest-cov ruff black build setuptools wheel; do ck "$TXT pins $t" grep -q "^$t " <<<"$tp"; done
ck "$TXT: every pin carries a sha256 hash" no grep -q ' unhashed$' <<<"$tp"
ck "$TXT: no requirement line without '=='" python3 - "$TXT" <<'PY'
import re, sys
text = open(sys.argv[1]).read().replace("\\\n", " ")
bad = [l for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#") and not re.match(r"^[A-Za-z0-9_.-]+==", l)]
assert not bad, bad
PY
vge() { python3 -c 'import sys; a, b = ([int(x) for x in v.split(".")[:3]] for v in sys.argv[1:3]); sys.exit(0 if a >= b else 1)' "$1" "$2"; }
for f in "$TXT" $( [ -d "$SK" ] && echo "$SK/requirements.txt" ); do
  b=$(pins "$f" | awk '$1 == "black" {print $2}')
  ck "$f: black ${b:-none} >= 26.3.1 (PYSEC-2026-2120, PYSEC-2026-2121)" vge "${b:-0}" 26.3.1
done
if [ -d "$SK" ]; then
  sp=$(pins "$SK/requirements.txt")
  for t in pip-audit bandit; do
    ck "$SK/requirements.in lists $t (a python instance's floor tools come from its own lockfile)" grep -qiE "^$t([<>=!~ ]|$)" "$SK/requirements.in"
    ck "$SK/requirements.txt pins $t with a hash" grep -q "^$t [^ ]* hashed$" <<<"$sp"
  done
  for t in ruff black pytest pytest-cov; do
    ck "gate tool $t: one pin in both lockfiles (the template's lint equals an instance's)" \
      [ "$(awk -v t="$t" '$1 == t {print $2}' <<<"$tp")" = "$(awk -v t="$t" '$1 == t {print $2}' <<<"$sp")" ]
  done
  ck "the python pack action installs scripts/requirements.txt with --require-hashes" grep -qF 'pip install --require-hashes -r scripts/requirements.txt' stacks/python/action.yml
fi
ck "ci.yml installs the gate tools with --require-hashes" grep -qF 'pip install --require-hashes -r scripts/requirements.txt' .github/workflows/ci.yml
ck "*.lock is not ignored (REQ-334's first clause, landed in P1b)" no git check-ignore -q --no-index x.lock
finish test_python_lockfiles
