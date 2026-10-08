#!/usr/bin/env bash
# REQ-327 / REQ-380: fixture tests for scripts/check-traceability.sh.
# Cases:
#   1. spec with extended_by: "" and a tagged REQ, plan WITHOUT implements:,
#      no proof                                   -> must FAIL (not skipped)
#   2. same spec, no plan at all                 -> must PASS (proof not yet owed)
#   3. plan implements a different REQ           -> must PASS
#   4. plan implements the tagged REQ, no proof  -> must FAIL
#   5. plan implements the tagged REQ, proof present -> must PASS
#   6. plan implements a REQ no live spec defines (proof present, so the
#      typo is the only possible failure)        -> must FAIL
#   7. two plans, one without implements:        -> whole spec walked -> FAIL
#   8. plan with implements: [] (proof present)  -> must FAIL (no silent opt-out)
#   9. plan's spec: points elsewhere but implements: names a REQ defined in
#      a DIFFERENT live spec (proof present)     -> must FAIL (cross-spec bypass)
#  10. implements: [REQ-951]  # comment (inline YAML comment) -> no proof
#      must FAIL; same plan with proof present    -> must PASS
#  11. bare implements: (no value), proof present -> must FAIL (empty-value
#      silent opt-out)
# Covers: REQ-327
# Covers: REQ-380
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../scripts/check-traceability.sh"

FAIL=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

fresh() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/docs/specs" "$TMP/docs/plans" "$TMP/docs/adr" "$TMP/docs/security" "$TMP/verification"
  cat > "$TMP/docs/specs/2026-01-01-fixture-design.md" <<'EOF'
---
type: spec
status: draft
extended_by: ""
---
# Fixture spec
- **REQ-951:** A tagged requirement. [verifiable-model]
- **REQ-952:** An untagged requirement.
EOF
  cat > "$TMP/docs/specs/2026-01-01-fixture-brainstorm.md" <<'EOF'
---
type: brainstorm
status: draft
---
# Fixture brainstorm
Notes only; not a live spec and must not count toward the live-spec total.
EOF
  echo "$TMP"
}
proof() { printf -- '// verification/fixture.dfy\n// Proves: REQ-951\nlemma L() ensures true {}\n' > "$1/verification/fixture.dfy"; }
plan()  { printf -- '---\ntype: plan\nspec: 2026-01-01-fixture\ndecisions: []\n%s---\n# plan\n' "$2" > "$1/docs/plans/$3"; }

expect_fail() { if TRACE_BASE_DIR="$1" bash "$SCRIPT" >/dev/null 2>&1; then fail "$2 — passed but must FAIL"; else pass "$2"; fi; }
expect_pass() { if TRACE_BASE_DIR="$1" bash "$SCRIPT" >/dev/null 2>&1; then pass "$2"; else fail "$2 — failed but must PASS"; fi; }

T=$(fresh); plan "$T" "" p.md
expect_fail "$T" "case 1 — extended_by: \"\" is empty; whole-spec plan owes a proof"; rm -rf "$T"

T=$(fresh)
OUT=$(TRACE_BASE_DIR="$T" bash "$SCRIPT" 2>&1); RC=$?
if [[ $RC -eq 0 ]]; then pass "case 2 — no plan: proof not yet owed"; else fail "case 2 — no plan: proof not yet owed — failed but must PASS"; fi
if echo "$OUT" | grep -q '1 live spec'; then
  pass "case 2 — brainstorm excluded from live-spec inventory (1 live spec)"
else
  fail "case 2 — expected '1 live spec' in summary; got: $OUT"
fi
rm -rf "$T"

T=$(fresh); plan "$T" $'implements: [REQ-952]\n' p.md
expect_pass "$T" "case 3 — plan implements an untagged REQ only"; rm -rf "$T"

T=$(fresh); plan "$T" $'implements: [REQ-951]\n' p.md
expect_fail "$T" "case 4 — implemented tagged REQ without proof"
proof "$T"
expect_pass "$T" "case 5 — implemented tagged REQ with proof"; rm -rf "$T"

T=$(fresh); proof "$T"; plan "$T" $'implements: [REQ-959]\n' p.md
expect_fail "$T" "case 6 — implements: names a REQ no live spec defines"; rm -rf "$T"

T=$(fresh); plan "$T" $'implements: [REQ-952]\n' a.md; plan "$T" "" b.md
expect_fail "$T" "case 7 — a plan without implements: walks the whole spec"; rm -rf "$T"

T=$(fresh); proof "$T"; plan "$T" $'implements: []\n' p.md
expect_fail "$T" "case 8 — implements: [] rejected"; rm -rf "$T"

T=$(fresh)
cat > "$T/docs/specs/2026-01-02-other-design.md" <<'EOF'
---
type: spec
status: draft
---
# Other fixture spec
- **REQ-953:** Untagged.
EOF
cat > "$T/docs/plans/p.md" <<'EOF'
---
type: plan
spec: 2026-01-02-other
decisions: []
implements: [REQ-951]
---
# plan
EOF
proof "$T"
expect_fail "$T" "case 9 — implements: REQ-951 is defined in a different spec than this plan's own spec:"; rm -rf "$T"

T=$(fresh); plan "$T" $'implements: [REQ-951]  # comment\n' p.md
expect_fail "$T" "case 10 — inline YAML comment after implements: list; no proof"
proof "$T"
expect_pass "$T" "case 10 — inline YAML comment after implements: list; proof present"; rm -rf "$T"

T=$(fresh); proof "$T"; plan "$T" $'implements:\n' p.md
expect_fail "$T" "case 11 — bare implements: (empty value) rejected as silent opt-out"; rm -rf "$T"

[[ $FAIL -eq 0 ]] || { echo "test_traceability_scoping: FAILED"; exit 1; }
echo "test_traceability_scoping: all checks passed"
