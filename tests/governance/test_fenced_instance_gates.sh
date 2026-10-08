#!/usr/bin/env bash
# REQ-306 (P5 R11): init-project.sh fences the factory's own design documents and proofs out of a new instance
# (scripts/factory-only.txt). REQ-360: a new instance's gates are green. Together: every governance test whose source
# names a fenced path passes inside a freshly fenced python instance, so a pin on a factory document that an instance
# no longer has fails here, in the template source's default gates, and not first in CI's first-run jobs (the wave-1
# regression of PR #48: test_attestation.sh grepped the threat model and the spec, and every new instance went red).
# The list is computed at run time from factory-only.txt, so a test added later that names a fenced path is covered.
# Covers: REQ-306
# Covers: REQ-360
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: runs in the template source (an instance has no factory-only.txt)"; finish test_fenced_instance_gates; exit 0; }
ME="$(basename "${BASH_SOURCE[0]}")"
# Search terms per manifest glob: its longest literal run (trailing / dropped); that run's basename when it has at
# least 8 characters; for a literal file whose name starts NNN- (an ADR), its directory and that prefix.
LIST="$(python3 - "$ROOT/scripts/factory-only.txt" "$ROOT/tests/governance" "$ME" <<'PY'
import os, re, sys
man, tdir, me = sys.argv[1:]
terms = set()
for l in open(man):
    g = l.strip()
    if not g or g.startswith("#"):
        continue
    seg = max(g.split("*"), key=len).rstrip("/")
    terms.add(seg)
    base = seg.rsplit("/", 1)[-1]
    if len(base) >= 8:
        terms.add(base)
    m = "*" not in g and re.match(r"(.*/)(\d+-)[^/]*$", g)
    if m:
        terms.add(m.group(1) + m.group(2))
for t in sorted(os.listdir(tdir)):
    if t.startswith("test_") and t.endswith(".sh") and t != me:
        if any(x in open(os.path.join(tdir, t)).read() for x in terms):
            print(t)
PY
)"
ck "the fenced-path test list is computed from factory-only.txt and is not empty" test -n "$LIST"
ck "the list holds the tests known to read fenced documents (attestation, state model, threat model)" bash -c \
  'for t in test_attestation.sh test_state_model.sh test_threat_model_current.sh test_spec_lifecycle.sh; do grep -qx "$t" <<<"$1" || exit 1; done' _ "$LIST"
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT
D="$WORK/py"; copy_template "$D"
# --name Acme, not Py: a py package would shadow the legacy py module and break pytest collection in the instance.
ck "python instance: init exits 0" bash -c "cd '$D' && bash scripts/init-project.sh --name Acme </dev/null >/dev/null 2>&1"
ck "python instance: the package is acme, not a py package that shadows the legacy py module" bash -c 'test -d "$1/src/acme" && ! test -e "$1/src/py"' _ "$D"
ck "python instance: the fence ran (factory-only.txt and the factory spec are gone)" \
  bash -c 'cd "$1" && [ ! -e scripts/factory-only.txt ] && ! ls docs/specs/2026-09-25-factory-v3-2-* >/dev/null 2>&1' _ "$D"
# Run them four at a time (the slowest, test_verify_release.sh, sets the wall-clock); each result is checked in list order.
OUT="$WORK/out"; mkdir -p "$OUT"
for t in $LIST; do
  while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge 4 ]]; do sleep 0.1; done
  ( rc=0; cd "$D" && bash "tests/governance/$t" > "$OUT/$t.out" 2>&1 < /dev/null || rc=$?; echo "$rc" > "$OUT/$t.rc" ) &
done
wait
for t in $LIST; do
  if [[ "$(cat "$OUT/$t.rc" 2>/dev/null || echo 1)" == 0 ]] && ! grep -q '^FAIL' "$OUT/$t.out"; then
    pass "python instance: $t passes with the factory documents fenced out"
  else
    fail "python instance: $t passes with the factory documents fenced out"; grep '^FAIL' "$OUT/$t.out" | sed 's/^/    /' || true
  fi
done
finish test_fenced_instance_gates
