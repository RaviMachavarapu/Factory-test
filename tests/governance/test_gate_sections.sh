#!/usr/bin/env bash
# REQ-320 (and the P3 gate wiring): run-quality-gates.sh runs the document checkers as section 6 — check-traceability.sh,
# analyze-adr-plan-linkage.sh, check-architecture.sh (check-covers.sh joins in Task 13) — each failure a gate failure,
# listed apart from the floor. Sections 1–5 keep their numbers (docs cite "section 5" for the floor); 6 and 7 follow it.
# Section 3 runs the governance tests in parallel (SPECFLOW_GOV_JOBS), printing them in order.
# Covers: REQ-320
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
G="$ROOT/scripts/run-quality-gates.sh"
sec() { awk -v h="$1" 'index($0, "SECTION \"" h "\"") {f=1; next} /SECTION "/ {f=0} f' "$G"; }
d=$(sec "Document gates")
ck "run-quality-gates.sh has section 6, Document gates" bash -c 'grep -qE "^# 6\. Document gates" "$1" && grep -qF "SECTION \"Document gates\"" "$1"' _ "$G"
for s in check-traceability.sh analyze-adr-plan-linkage.sh check-architecture.sh; do
  ck "Document gates runs scripts/$s" grep -qF "scripts/$s" <<<"$d"
done
ck "a document-gate failure is recorded with gate_fail (a gate failure, not a floor failure)" grep -q 'gate_fail' <<<"$d"
ck "the floor keeps section 5" grep -qE '^# 5\. Security floor' "$G"
ck "Document gates follow the floor and precede the Summary" python3 - "$G" <<'PY'
import sys; t = open(sys.argv[1]).read()
assert t.index('SECTION "Security floor"') < t.index('SECTION "Document gates"') < t.index('SECTION "Summary"')
PY

# REQ-322: section 7, Release gates, runs the disposition wrapper as a gate.
# Covers: REQ-322
r=$(sec "Release gates")
ck "run-quality-gates.sh has section 7, Release gates" bash -c 'grep -qE "^# 7\. Release gates" "$1"' _ "$G"
ck "Release gates runs scripts/check-security-disposition.sh with gate_fail" bash -c 'grep -qF "scripts/check-security-disposition.sh" <<<"$1" && grep -q gate_fail <<<"$1"' _ "$r"
ck "Release gates also runs scripts/verify-release.sh (REQ-324)" grep -qF "scripts/verify-release.sh" <<<"$r"
ck "Document gates runs scripts/check-covers.sh" grep -qF "scripts/check-covers.sh" <<<"$d"

# The 3-minute budget (final review): section 3 runs the governance tests SPECFLOW_GOV_JOBS at a time (default 4;
# 1 is the old serial run), each test's output buffered and printed, with its PASS/FAIL line, in glob order. The fixture's
# tests each wait for the others to have started, so a serial run cannot pass them.
F="$(mktemp -d)"; trap 'rm_tree "$F"' EXIT; mkdir -p "$F/scripts" "$F/tests/governance"; cp "$G" "$F/scripts/"
for x in a c; do printf '#!/usr/bin/env bash\ntouch "%s/%s.start"; echo %s-out\nfor i in $(seq 100); do [ -e "%s/a.start" ] && [ -e "%s/c.start" ] && exit 0; sleep 0.1; done; exit 1\n' \
  "$F" "$x" "$x" "$F" "$F" > "$F/tests/governance/test_$x.sh"; done
printf '#!/usr/bin/env bash\necho b-out; exit 1\n' > "$F/tests/governance/test_b.sh"
gv() { rm -f "$F"/*.start; rc=0; out=$(cd "$F" && env -u SPECFLOW_QG_RUNNING SPECFLOW_GOV_JOBS="$1" bash scripts/run-quality-gates.sh 2>&1) || rc=$?
  gov=$(awk '/=== Governance tests ===/{f=1; next} /^=== /{f=0} f' <<<"$out"); }
gv 3
ck "governance tests run concurrently (SPECFLOW_GOV_JOBS=3: tests that wait for each other pass)" \
  bash -c 'grep -q "^PASS tests/governance/test_a.sh" <<<"$1" && grep -q "^PASS tests/governance/test_c.sh" <<<"$1"' _ "$gov"
ck "…each test's output and verdict print in glob order, a failure listed under Gate failures" python3 - "$gov" "$out" <<'PY'
import sys
g, out = sys.argv[1].splitlines(), sys.argv[2]
want = ["a-out", "PASS tests/governance/test_a.sh", "b-out", "FAIL tests/governance/test_b.sh", "c-out", "PASS tests/governance/test_c.sh"]
got = [l for l in g if l in want]
assert got == want, got
assert "  FAIL tests/governance/test_b.sh" in out.split("=== Summary ===")[1]
PY
gv 1
ck "SPECFLOW_GOV_JOBS=1 is the serial run (the waiting tests time out)" grep -q "^FAIL tests/governance/test_a.sh" <<<"$gov"
ck "the default is 4 jobs" grep -qF 'SPECFLOW_GOV_JOBS:-4' "$G"
# Build 3 final review, finding 1 (REQ-320; P6 R21's 3-minute budget): the longest tests start first — a fixed list in
# section 3 (test_verify_release first) — so the last test still running is not a long one that sorts late; their output
# and verdicts still print in glob order. The fixture's tests record the order they start in (a serial run shows it).
F2="$(mktemp -d)"; mkdir -p "$F2/scripts" "$F2/tests/governance"; cp "$G" "$F2/scripts/"
for x in a verify_release z; do printf '#!/usr/bin/env bash\necho %s >> "%s/order"; echo %s-out\n' "$x" "$F2" "$x" > "$F2/tests/governance/test_$x.sh"; done
out=$(cd "$F2" && env -u SPECFLOW_QG_RUNNING SPECFLOW_GOV_JOBS=1 bash scripts/run-quality-gates.sh 2>&1) || true
ck "section 3 starts test_verify_release before the tests that sort ahead of it" bash -c '[ "$(tr "\n" " " < "$1/order")" = "verify_release a z " ]' _ "$F2"
ck "…and still prints each test's output and verdict in glob order" python3 - "$out" <<'PY2'
import sys
want = ["a-out", "PASS tests/governance/test_a.sh", "verify_release-out", "PASS tests/governance/test_verify_release.sh", "z-out", "PASS tests/governance/test_z.sh"]
got = [l for l in sys.argv[1].splitlines() if l in want]
assert got == want, got
PY2
rm_tree "$F2"
finish test_gate_sections
