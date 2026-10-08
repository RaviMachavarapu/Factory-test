#!/usr/bin/env bash
# REQ-126: fixture test for scripts/analyze-adr-plan-linkage.sh (retro
# 2026-05-28 proposal #1 — "test the validator"), plus a live-repo run.
# Fixture cases:
#   A. valid linkage                      -> must PASS
#   B. [verifiable] REQ with no ADR      -> must FAIL
#   C. prose mentioning `[verifiable]` in backticks (the REQ-126 false-tag
#      bug found 2026-06-09)             -> must NOT count as a tag
#   D. implements: scoping (REQ-380): D1 PASS, D2 FAIL (regression pin for
#      quote parsing), D3 PASS, D4 PASS, D5 FAIL, D6 FAIL (spec: names a
#      nonexistent spec file), D7 FAIL (inline YAML comment must not swallow
#      the last implements: item), D8 FAIL (non-REQ-NNN implements: item),
#      D9 FAIL (bare implements: is an empty-value silent opt-out)
# Covers: REQ-380
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../scripts/analyze-adr-plan-linkage.sh"
source "$HERE/lib/check.sh"  # rm_tree, git maintenance off (REQ-360)

TMP="$(mktemp -d)"
trap 'rm_tree "$TMP"' EXIT
mkdir -p "$TMP/docs/specs" "$TMP/docs/plans" "$TMP/docs/adr"

cat > "$TMP/docs/specs/2026-01-01-fixture-design.md" <<'EOF'
---
type: spec
status: accepted
---
# Fixture spec
- **REQ-901:** [verifiable-model] A real tagged requirement.
- **REQ-902:** An untagged requirement; the checker walks any `[verifiable]` REQ — this backtick mention is prose, not a tag.
EOF

cat > "$TMP/docs/adr/001-fixture.md" <<'EOF'
---
id: ADR-901
status: accepted
addresses: [REQ-901]
---
# fixture ADR
EOF

cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: [ADR-901]
---
# fixture plan
EOF

FAIL=0
# Case A+C: REQ-901 covered; REQ-902's backtick mention must not need an ADR.
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "ok:   fixture A+C — valid linkage passes; backtick-quoted tag mention ignored"
else
  echo "FAIL: fixture A+C — valid fixture rejected (backtick prose counted as a tag?)"
  FAIL=1
fi

# Case B: drop the ADR coverage -> must fail.
sed -i.bak 's/addresses: \[REQ-901\]/addresses: []/' "$TMP/docs/adr/001-fixture.md"
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: fixture B — uncovered [verifiable-model] REQ was not rejected"
  FAIL=1
else
  echo "ok:   fixture B — uncovered REQ correctly rejected"
fi

# Restore ADR coverage for the scoping cases.
sed -i.bak 's/addresses: \[\]/addresses: [REQ-901]/' "$TMP/docs/adr/001-fixture.md"

# Case D1: plan implements only REQ-902 (untagged), decisions empty -> must PASS.
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: []
implements: [REQ-902]
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "ok:   fixture D1 — implements: excludes the tagged REQ; no ADR needed"
else
  echo "FAIL: fixture D1 — plan scoped away from REQ-901 was still rejected"
  FAIL=1
fi

# Case D2: quoted/spaced list, implements the tagged REQ, no ADR -> must FAIL.
# (Red today for the whole-spec reason; after Task 1 it pins quote parsing:
# a quote-mangling parse_list would scope REQ-901 away and wrongly PASS.)
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: []
implements: [ "REQ-901" , 'REQ-902' ]
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: fixture D2 — implemented tagged REQ without ADR was not rejected"
  FAIL=1
else
  echo "ok:   fixture D2 — quoted implements: parsed; uncovered REQ rejected"
fi

# Case D3: same plan with the ADR in decisions -> must PASS.
sed -i.bak 's/decisions: \[\]/decisions: [ADR-901]/' "$TMP/docs/plans/2026-01-01-fixture-plan.md"
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "ok:   fixture D3 — implemented tagged REQ covered by ADR"
else
  echo "FAIL: fixture D3 — covered plan rejected"
  FAIL=1
fi

# Case D4: quoted untagged-only list, decisions empty -> must PASS.
# Passes ONLY when quotes are stripped ("REQ-902" != REQ-902 otherwise
# scopes nothing away and the whole spec is walked).
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: []
implements: [ "REQ-902" ]
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "ok:   fixture D4 — quoted implements: item stripped and honoured"
else
  echo "FAIL: fixture D4 — quoted implements: item not stripped (whole spec walked)"
  FAIL=1
fi

# Case D5: explicit empty list -> must FAIL (silent opt-out is not allowed).
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: [ADR-901]
implements: []
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: fixture D5 — implements: [] was accepted as a silent opt-out"
  FAIL=1
else
  echo "ok:   fixture D5 — implements: [] rejected"
fi

# Case D6: plan's spec: names a spec file that does not exist -> must FAIL.
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-nope
decisions: [ADR-901]
implements: [REQ-901]
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: fixture D6 — plan with nonexistent spec: was not rejected"
  FAIL=1
else
  echo "ok:   fixture D6 — plan with nonexistent spec: rejected"
fi

# Case D7: inline YAML comment after the implements: list. A parser that
# fails to strip it reads the last item as "REQ-901]  # the REQs this plan
# delivers", which never matches "REQ-901" and silently scopes the tagged
# REQ away -> wrongly PASS. Correct parsing keeps REQ-901 in scope with
# decisions: [] (no ADR) -> must FAIL.
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: []
implements: [REQ-902, REQ-901]  # the REQs this plan delivers
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: fixture D7 — inline comment swallowed the last implements: item"
  FAIL=1
else
  echo "ok:   fixture D7 — inline YAML comment stripped; REQ-901 still in scope and rejected"
fi

# Case D8: a non-REQ-NNN implements: item must be rejected, not silently
# narrow scope to nothing.
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: [ADR-901]
implements: [REQ-90x]
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: fixture D8 — malformed implements: item 'REQ-90x' was not rejected"
  FAIL=1
else
  echo "ok:   fixture D8 — malformed implements: item rejected"
fi

# Case D9: bare implements: (no value at all) is an empty-value silent
# opt-out, same as implements: [].
cat > "$TMP/docs/plans/2026-01-01-fixture-plan.md" <<'EOF'
---
type: plan
spec: 2026-01-01-fixture
decisions: [ADR-901]
implements:
---
# fixture plan
EOF
if LINKAGE_BASE_DIR="$TMP" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: fixture D9 — bare implements: was accepted as a silent opt-out"
  FAIL=1
else
  echo "ok:   fixture D9 — bare implements: rejected"
fi

# Live repo run.
if bash "$SCRIPT"; then
  echo "ok:   live repo linkage check passes"
else
  echo "FAIL: live repo linkage check failed"
  FAIL=1
fi

[[ $FAIL -eq 0 ]] || { echo "test_analyze_adr_plan_linkage: FAILED"; exit 1; }
echo "test_analyze_adr_plan_linkage: all checks passed"
