#!/usr/bin/env bash
# REQ-394 / REQ-380: one frontmatter reader. scripts/lib/specflow/frontmatter.py holds parse_text()/read(), parse_list(),
# the strip-quotes / strip-comment rules REQ-380 established, the tag regex and the plan claims; check-traceability.sh,
# analyze-adr-plan-linkage.sh and architecture.py import it instead of carrying copies (check-covers.sh does too, Task 13).
# config.py and attestation.py keep their own reader: CI and run-verifier.sh materialise each alone from the base ref.
# Covers: REQ-394
# Covers: REQ-380
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; FM="$LIB/frontmatter.py"
ck "scripts/lib/specflow/frontmatter.py exists" test -f "$FM"
ck "frontmatter.parse_text/parse_list: the REQ-380 conventions" python3 - "$LIB" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import frontmatter as f
t = ('---\ntype: plan\nspec: "2026-01-01-x"  # a comment\nextended_by: ""\nimplements: [REQ-001, "REQ-002"]  # c\n'
     'bare:\nurl: a#b\nq: "x # y"\n---\n# body\n')
fm = f.parse_text(t)
assert fm["spec"] == "2026-01-01-x", fm
assert fm["extended_by"] == "" and fm["bare"] == "", fm      # REQ-327: an empty-quoted value is empty
assert fm["url"] == "a#b" and fm["q"] == "x # y", fm         # a glued or quoted '#' is not a comment
assert f.parse_list(fm["implements"]) == ["REQ-001", "REQ-002"]
assert f.parse_list("[]") == [] and f.parse_list("") == []
assert f.parse_text("# no frontmatter\n") == {}
assert f.tagged_reqs("- **REQ-901:** x. [verifiable-model]\n- **REQ-902:** names the `[verifiable]` tag.\n") == {"REQ-901"}
PY
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
mkdir -p "$W/docs/specs" "$W/docs/plans"
printf -- '---\ntype: spec\nstatus: accepted\n---\n- **REQ-901:** x. [verifiable-model]\n- **REQ-902:** y.\n' > "$W/docs/specs/2099-01-01-a-design.md"
printf -- '---\ntype: spec\nstatus: superseded\n---\n- **REQ-903:** z.\n' > "$W/docs/specs/2099-01-01-b-design.md"
printf -- '---\ntype: brainstorm\n---\nnotes\n' > "$W/docs/specs/2099-01-01-a-brainstorm.md"
printf -- '---\ntype: plan\nspec: 2099-01-01-a\nimplements: [REQ-902, not-a-req]  # one\n---\n' > "$W/docs/plans/p1.md"
printf -- '---\ntype: plan\nspec: 2099-01-01-a\n---\n' > "$W/docs/plans/p0.md"
ck "frontmatter.claims and live_specs: the union, whole-walked and named specs; live excludes superseded and brainstorm" \
  python3 - "$LIB" "$W" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import frontmatter as f
c = f.claims(sys.argv[2])
assert c.implemented == {"REQ-902"}, c.implemented          # lenient: a malformed item is not a claim
assert c.whole_specs == {"2099-01-01-a"} and c.named_specs == {"2099-01-01-a"}, c
assert sorted(p.implements is None for p in c.plans) == [False, True]
assert sorted(f.live_specs(sys.argv[2])) == ["2099-01-01-a"]
PY
for s in scripts/check-traceability.sh scripts/analyze-adr-plan-linkage.sh scripts/lib/specflow/architecture.py; do
  ck "$s imports frontmatter.py" grep -qE '^[[:space:]]*(import frontmatter|from frontmatter import)' "$ROOT/$s"
  ck "$s carries no copy of the parsers" \
    no grep -qE 'def (strip_comment|_strip_comment|strip_quotes|_strip_quotes|parse_list|frontmatter|parse_frontmatter|flat_frontmatter)\(' "$ROOT/$s"
  ck "$s carries no copy of the tag regex" no grep -qF 'verifiable(?:-model)?' "$ROOT/$s"
done
for s in config.py attestation.py; do
  ck "$s stays self-contained (materialised alone from the base ref)" no grep -qE '^[[:space:]]*(import frontmatter|from frontmatter)' "$LIB/$s"
done
finish test_frontmatter
