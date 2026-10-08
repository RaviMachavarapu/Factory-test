---
type: plan
phase: PLAN
spec: 2026-09-25-factory-v3-2
decisions: []
implements: [REQ-380, REQ-327]
created: "2026-09-25"
---

# Factory v3.2 — P0: Plan-Scoped Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the factory's gates scope to the REQs a plan actually claims, and fix the two traceability-checker bugs, so a spec delivered by many plans never turns `main` red and a draft spec can merge before its proofs exist.

**Architecture:** Two existing Python-in-bash scripts gain one new input, a plan's `implements:` frontmatter list, and one parser fix (empty-quoted YAML values are empty). `analyze-adr-plan-linkage.sh` checks ADR coverage per plan, for the verifiable REQs that plan implements; `check-traceability.sh` demands a `// Proves:` proof only for verifiable REQs in the union of every plan's `implements:` (a plan without the field is walked whole, which the demo relies on). A plan template documents the field. Governance tests with synthetic fixtures are written first for every behaviour.

**Plan style (decision 2026-09-25, REQ-380):** this plan carries the failing test code, because the tests are the behavioural spec and are written first anyway; implementation steps describe intent, never bodies. The demo plan's note, the new template and the PR template are updated in Task 3 to say the same.

**Path note:** the factory walks its own regulated path for P0–P5 (REQ-381); the `## Build N:` section shape the template introduces applies to lanes-path plans from P5 on (REQ-340), so this plan uses tasks.

**Tech Stack:** bash + embedded python3 (stdlib only: `re`, `glob`, `os`, `sys`), governance tests in `tests/governance/test_*.sh` run by `scripts/run-quality-gates.sh`.

**Spec:** `docs/specs/2026-09-25-factory-v3-2-design.md` — REQ-380 (plan `implements:`; per-plan linkage scoping; union proof scoping; own-spec rule; missing `spec:` is an error; present-but-empty `implements:` is an error; comments stripped; brainstorms are not live specs; `implements:` mandatory by `created:` date; plan template; plan-style rule) and REQ-327 (proof owed only once implemented; empty-quoted frontmatter is empty; both in one commit). REQ-394 (the P3 checkers reading `implements:`) is explicitly **not** claimed here.

**Tier (settled):** this is an IMPLEMENT-phase PR on `impl/plan-0-plan-scoping` that carries its own plan, by the exemption REQ-381 records: the gates cannot accept any plan for this spec until P0's scoping lands. It is not patch tier (it edits the review-gate rule text and relaxes when proofs are owed). Base branch is `phase/spec-factory-v3-2` until PR #20 merges, then `main`.

**Verified against:** `1b88f40` (spec branch head) / `831a25d` (this branch after the final-review fix wave). Line anchors were checked by a dry run at `bc84bd2`; the post-implementation additions (traceability cases 9–11, linkage D6–D9, comment stripping, empty-value rejection, `created:`-date enforcement, brainstorm exclusion) are recorded in the task Interfaces below. Re-verify anchors after the rebase in Task 4.

## Global Constraints

- Only python3 stdlib inside the scripts; no PyYAML (spec §Assumptions: flat `key: value` parsing).
- REQ ids are three digits; the fixture ids used here (`REQ-951`, `REQ-952`, `REQ-959`, `REQ-901`, `REQ-902`) exist only inside temporary fixture directories, never in `docs/`.
- A plan without `implements:` is walked whole (demo compatibility, REQ-380); an explicit `implements: []` is an error in both scripts.
- `verification/example.dfy` stays exempt from the `Proves:` scan (`check-traceability.sh` line 49).
- Every script change has a governance test that fails before the change and passes after (`art-test-first`, `.claude/rules/tdd.md`).
- REQ-327's two checker changes land in **one** commit (spec clause), so the checker is never in the intermediate state where a draft spec cannot merge.
- Only the intended red steps leave the branch red: at HEAD the live linkage check fails because this plan exists with `decisions: []`; Task 1 fixes it first.
- No file under `src/` changes; this is `scripts/`, `tests/governance/`, `schemas/`, `.claude/rules/`, `.github/`, `docs/plans/`.
- Prerequisite before opening the PR: PRs #19 (objective review) and #20 (v3.2 spec) merged, then rebase this branch onto `main`.

## Review Focus

1. A plan whose `implements:` names a REQ that no live spec defines (typo) — reported as an error, not silently treated as covered. Pinned in Task 2 (case 6, with the proof present so the typo is the only possible failure).
2. A spec with `extended_by: ""` (the template default) — walked like any live spec, not skipped. Pinned in Task 2 (case 1).
3. Two plans for the same spec, one with `implements:` and one without — the one without walks the whole spec. Pinned in Task 2 (case 7).
4. `implements:` written with quotes or extra spaces (`[ "REQ-902" ]`) — parsed; and `implements: []` — rejected. Pinned in Task 1 (cases D4, D5) and Task 2 (case 8).
5. The demo plan (no `implements:`) — REQ-200 still owes its proof after the change. Pinned in Task 2 (case 7 is the same shape) and re-checked live in Task 4.

---

### Task 1: `analyze-adr-plan-linkage.sh` — ADR coverage scoped per plan to `implements:`

**Files:**
- Modify: `tests/governance/test_analyze_adr_plan_linkage.sh:46-63` (add fixtures D1–D5 after Case B, before `# Live repo run.` at line 64)
- Modify: `scripts/analyze-adr-plan-linkage.sh:20-36` (`parse_frontmatter`, `parse_list`) and `:61-88` (plan walk)

**Interfaces:**
- Consumes: plan frontmatter `implements: [REQ-NNN, …]`.
- Produces: per-plan scoping: the plan's ADR check covers `verifiable_reqs(spec) ∩ implements` when the field is present, the whole spec otherwise; `implements: []`, a bare `implements:` or `implements: ""` is a FAIL naming the plan; items that are not `REQ-NNN` are a FAIL; a `spec:` that resolves to no file is a FAIL; `parse_frontmatter` and `parse_list` strip surrounding single or double quotes and trailing `#` comments from values and list items. Fixtures D1–D9 (D6 nonexistent spec, D7 inline comment, D8 malformed item, D9 bare key were added after the final review and verifier findings).

- [x] **Step 1: Add the failing fixtures**

Insert after the Case B block (line 63) and update the header comment's case list with `D. implements: scoping (REQ-380): D1 PASS, D2 FAIL (regression pin for quote parsing), D3 PASS, D4 PASS, D5 FAIL`:

```bash
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
```

- [x] **Step 2: Run to verify the new cases fail**

Run: `bash tests/governance/test_analyze_adr_plan_linkage.sh`
Expected: A+C ok; B ok; **D1 FAIL** (whole spec checked, REQ-901 uncovered); D2 ok (for the old reason); D3 ok; **D4 FAIL**; **D5 FAIL** (`[]` is currently an empty list, so the plan passes); live repo run **FAIL** naming REQ-322 and REQ-341 for this plan.

- [x] **Step 3: Implement per-plan scoping (intent)**

In `scripts/analyze-adr-plan-linkage.sh`:
- `parse_frontmatter`: strip surrounding double and single quotes from each value, so `key: ""` is empty (REQ-327 convention shared with Task 2).
- `parse_list`: strip surrounding quotes from each item and drop empty items.
- In the plan walk, after `reqs = verifiable_reqs(spec_path)` (line 75) and before the `if not reqs: continue` guard: read `implements` via `parse_list(fm.get("implements", ""))`. If the raw frontmatter value is present but the parsed list is empty (the `implements: []` case), append an error naming the plan and continue. If the list is non-empty, keep only the REQs whose `REQ-NNN` form appears in it. Leave the counting logic where it is: a plan scoped entirely to untagged REQs is `continue`d before `checked += 1`, so it is not counted as "verified" (accepted; the count is informational).

- [x] **Step 4: Run the linkage test and the live check**

Run: `bash tests/governance/test_analyze_adr_plan_linkage.sh`
Expected: A+C, B, D1–D5 all `ok:`; `live repo linkage check passes`; summary `PASS: ADR-PLAN linkage check (REQ-126) — 1 plan(s) verified, 0 skipped` (the demo plan; this plan scopes to untagged REQs and is not counted).

- [x] **Step 5: Commit**

```bash
git add tests/governance/test_analyze_adr_plan_linkage.sh scripts/analyze-adr-plan-linkage.sh
git commit -m "feat(analyze): ADR linkage scoped per plan to implements:; [] rejected (REQ-380)"
```

---

### Task 2: `check-traceability.sh` — frontmatter fix, fixture override, proofs owed only when implemented (one commit)

**Files:**
- Create: `tests/governance/test_traceability_scoping.sh`
- Modify: `scripts/check-traceability.sh:13-14` (ROOT/cd), `:26-27` (`frontmatter()` assignment), `:46-61` (proof-obligation block; keep the comment on line 58 about backtick-quoted tags being prose)

**Interfaces:**
- Consumes: nothing from Task 1 except the parsing convention (quotes stripped; same `parse_list` shape).
- Produces: env var `TRACE_BASE_DIR` (fixture override, same convention as `LINKAGE_BASE_DIR`); the sets `implemented` (REQ numbers claimed by any plan's `implements:`) and `walked_whole_specs` (spec slugs of plans without the field); proof owed iff a tagged REQ is in `implemented` or its spec is in `walked_whole_specs`; errors for `implements:` items that are not `REQ-NNN`, that no live spec defines, that a spec other than the plan's own `spec:` defines, or for a present-but-empty `implements:`; `type: brainstorm` files are not live specs; summary line reports `N claimed by plans`. Fixtures 1–11 (case 9 cross-spec claim, case 10 inline comment, case 11 bare key were added after the final review and verifier findings).

- [x] **Step 1: Write the failing governance test (all eight cases at once)**

```bash
cat > tests/governance/test_traceability_scoping.sh <<'EOS'
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
  echo "$TMP"
}
proof() { printf -- '// verification/fixture.dfy\n// Proves: REQ-951\nlemma L() ensures true {}\n' > "$1/verification/fixture.dfy"; }
plan()  { printf -- '---\ntype: plan\nspec: 2026-01-01-fixture\ndecisions: []\n%s---\n# plan\n' "$2" > "$1/docs/plans/$3"; }

expect_fail() { if TRACE_BASE_DIR="$1" bash "$SCRIPT" >/dev/null 2>&1; then fail "$2 — passed but must FAIL"; else pass "$2"; fi; }
expect_pass() { if TRACE_BASE_DIR="$1" bash "$SCRIPT" >/dev/null 2>&1; then pass "$2"; else fail "$2 — failed but must PASS"; fi; }

T=$(fresh); plan "$T" "" p.md
expect_fail "$T" "case 1 — extended_by: \"\" is empty; whole-spec plan owes a proof"; rm -rf "$T"

T=$(fresh)
expect_pass "$T" "case 2 — no plan: proof not yet owed"; rm -rf "$T"

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

[[ $FAIL -eq 0 ]] || { echo "test_traceability_scoping: FAILED"; exit 1; }
echo "test_traceability_scoping: all checks passed"
EOS
chmod +x tests/governance/test_traceability_scoping.sh
```

- [x] **Step 2: Run it to verify it fails**

Run: `bash tests/governance/test_traceability_scoping.sh`
Expected (the checker ignores `TRACE_BASE_DIR` today and walks the real repo, which passes): cases 1, 4, 6, 7, 8 report `passed but must FAIL`; cases 2, 3, 5 report ok. Exit 1.

- [x] **Step 3: Implement both REQ-327 changes and the scoping (intent, one commit)**

In `scripts/check-traceability.sh`:
- Lines 13–14: honour `TRACE_BASE_DIR` as the directory to walk, defaulting to the repo root (comment: same convention as `LINKAGE_BASE_DIR`).
- `frontmatter()` line 26–27: strip surrounding double and single quotes from each value so `key: ""` is empty (comment cites REQ-327).
- Add a `parse_list()` helper with the same semantics as Task 1's.
- Before the proof-obligation block: walk `docs/plans/*.md`; for a plan whose raw `implements` value is present, parse it; an empty parsed list is an error naming the plan; each item must match `REQ-NNN` exactly (else error) and its number must be in `defined` (else error "which no live spec defines"); add the number to `implemented`. A plan with no `implements` value but a `spec:` value adds that slug to `walked_whole_specs`.
- In the proof-obligation loop (keep the existing backtick-prose comment above the regex): derive each live spec's slug from its filename (strip `-design.md`), and require a proof only when the tagged REQ is in `implemented` or the slug is in `walked_whole_specs`; the error message says "is [verifiable*] and implemented but no proof carries …".
- Summary line: add `{len(implemented)} claimed by plans`.

- [x] **Step 4: Run the fixture test, the live checker, and the existing traceability test**

Run: `bash tests/governance/test_traceability_scoping.sh`
Expected: all eight cases `ok:`; `all checks passed`.

Run: `bash scripts/check-traceability.sh`
Expected: `PASS: traceability — 57 REQs across 4 live specs, 1 proven, 2 claimed by plans, no duplicates or dangling references` (REQ-380/327 claimed by this plan; REQ-200 owed via the demo plan's whole-spec walk and proven).

Run: `bash tests/governance/test_traceability.sh`
Expected: `test_traceability: all checks passed`.

- [x] **Step 5: Commit (one commit for both REQ-327 changes plus scoping)**

```bash
git add tests/governance/test_traceability_scoping.sh scripts/check-traceability.sh
git commit -m "feat(traceability): empty-quoted frontmatter is empty; proofs owed only for implemented REQs (REQ-327, REQ-380)"
```

---

### Task 3: Plan template, plan-style rule, and gate wording

**Files:**
- Create: `schemas/plan-template.md`
- Create: `tests/governance/test_plan_template.sh`
- Modify: `.claude/rules/review-gate.md` (Phase-specific gate rules: add a PLAN line)
- Modify: `.github/PULL_REQUEST_TEMPLATE.md:19` (PLAN/ANALYZE line)
- Modify: `docs/plans/2026-05-28-demo-greeting-plan.md:13` (the "never in this PLAN document" note)

**Interfaces:**
- Produces: `schemas/plan-template.md` with frontmatter `spec`, `decisions`, `implements`, `created` and a `## Build 1: <name>` section; the plan-style rule text used in three places.

- [x] **Step 1: Write the failing governance test**

```bash
cat > tests/governance/test_plan_template.sh <<'EOS'
#!/usr/bin/env bash
# REQ-380: the plan template documents implements: and the Build-N shape,
# every plan that carries implements: lists only REQ-NNN ids (and not an
# empty list), and the plan-style rule is stated where plans are reviewed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"
FAIL=0; pass() { echo "ok:   $1"; }; fail() { echo "FAIL: $1"; FAIL=1; }

T=schemas/plan-template.md
if [[ -f $T ]]; then pass "$T exists"; else fail "$T missing"; fi
for key in 'spec:' 'decisions:' 'implements:' 'created:'; do
  if grep -q "^$key" "$T" 2>/dev/null; then pass "template has $key"; else fail "template lacks $key"; fi
done
if grep -q '^## Build 1: ' "$T" 2>/dev/null; then pass "template has '## Build 1:' section"; else fail "template lacks '## Build 1:'"; fi

for p in docs/plans/*.md; do
  line=$(awk '/^---$/{n++; next} n==1 && /^implements:/{print; exit}' "$p")
  [[ -z "$line" ]] && continue
  items=$(echo "$line" | sed 's/^implements:[[:space:]]*//' | tr -d '[]"'"'"' ' | tr ',' '\n' | sed '/^$/d')
  if [[ -z "$items" ]]; then
    fail "$p implements: is an empty list"
  elif echo "$items" | grep -vqE '^REQ-[0-9]{3}$'; then
    fail "$p implements: has a non-REQ-NNN entry: $line"
  else
    pass "$p implements: well-formed"
  fi
done

for f in .claude/rules/review-gate.md .github/PULL_REQUEST_TEMPLATE.md docs/plans/2026-05-28-demo-greeting-plan.md; do
  if grep -q 'implementation as intent' "$f"; then pass "$f states the plan-style rule"; else fail "$f does not state the plan-style rule"; fi
done
if grep -q 'implements:' .claude/rules/review-gate.md; then pass "review-gate.md documents implements:"; else fail "review-gate.md does not mention implements:"; fi
if grep -q 'implements:' .github/PULL_REQUEST_TEMPLATE.md; then pass "PR template mentions implements:"; else fail "PR template does not mention implements:"; fi

[[ $FAIL -eq 0 ]] || { echo "test_plan_template: FAILED"; exit 1; }
echo "test_plan_template: all checks passed"
EOS
chmod +x tests/governance/test_plan_template.sh
```

- [x] **Step 2: Run to verify it fails**

Run: `bash tests/governance/test_plan_template.sh`
Expected: `FAIL: schemas/plan-template.md missing`; the four key checks and the `## Build 1:` check fail; `ok: docs/plans/2026-09-25-factory-v3-2-p0-plan.md implements: well-formed`; the three plan-style-rule checks fail; review-gate and PR-template `implements:` checks fail. Exit 1.

- [x] **Step 3: Create the template and update the three documents (intent)**

- `schemas/plan-template.md`: frontmatter `type: plan`, `phase: PLAN`, `spec: <date>-<slug>`, `decisions: [ADR-NNN]`, `implements: [REQ-NNN]` (comment: the REQs this plan delivers; gates scope to this list, REQ-380 — parsers strip trailing `#` comments), `created: ""`. Body: title, an "Implements REQ-…" line, a **plan-style note** — "Plans may carry the failing test code (the tests are the behavioural spec and are written first) and describe implementation as intent, never bodies (`art-test-first`)" — a `## Files` section, and a `## Build 1: <name>` section explaining that one build lane implements it and further units are `## Build 2:` and so on, contiguous from 1, with a `### Task 1.1:` stub.
- `.claude/rules/review-gate.md`, Phase-specific gate rules, after the ARCHITECTURE bullet: "PLAN exit gate: plan frontmatter carries `spec:`, `decisions:`, and `implements:` (mandatory for plans created from v3.2 on; the demo plan is grandfathered and walked whole); `scripts/analyze-adr-plan-linkage.sh` scopes per plan and `scripts/check-traceability.sh` to the union across plans (REQ-380); an explicit empty `implements:` list is an error. Plans may carry test code and describe implementation as intent, never bodies (`art-test-first`)."
- `.github/PULL_REQUEST_TEMPLATE.md` line 19: "**PLAN/ANALYZE** — plan frontmatter has `spec:` + `decisions:` + `implements:`; `bash scripts/analyze-adr-plan-linkage.sh` passes; the plan may carry test code and implementation as intent, no implementation bodies."
- `docs/plans/2026-05-28-demo-greeting-plan.md` line 13: reword the note to "The runnable implementation lives in IMPLEMENT (`src/`, `verification/`), never in this PLAN document; a plan may carry the failing test code and describes implementation as intent (decision 2026-09-25, REQ-380). Embedding implementation bodies here would let an implementer skip TDD (`art-test-first`)."

- [ ] **Step 4: Run the test and the citation guard**

Run: `bash tests/governance/test_plan_template.sh`
Expected: all `ok:`; `all checks passed`.

Run: `bash tests/governance/test_review_gate_citations.sh` and `bash tests/governance/test_reviews_use_slugs.sh`
Expected: both still pass.

- [ ] **Step 5: Commit**

```bash
git add schemas/plan-template.md tests/governance/test_plan_template.sh .claude/rules/review-gate.md .github/PULL_REQUEST_TEMPLATE.md docs/plans/2026-05-28-demo-greeting-plan.md
git commit -m "docs(plan): plan template with implements:; plan-style rule in gate, PR template and demo plan (REQ-380)"
```

---

### Task 4: Whole-branch verification and PR

**Files:**
- No new committed files; regression guard and PR only.

- [x] **Step 1: Run the full quality gates**

Run: `bash scripts/run-quality-gates.sh`
Expected: `All quality gates passed`, including the two new governance tests and the live linkage/traceability runs with this plan present.

- [x] **Step 2: Live regression guard for the demo**

```bash
G=$(mktemp -d); mv verification/demo_greeting/greeting.dfy "$G/g.dfy" && bash scripts/check-traceability.sh; mv "$G/g.dfy" verification/demo_greeting/greeting.dfy; rmdir "$G"
```

Expected: FAIL naming `REQ-200` while the proof is moved; PASS after restoring.

- [ ] **Step 3: Rebase onto main once PRs #19 and #20 have merged, re-verify anchors, re-run gates, push**

```bash
git fetch origin main && git rebase origin/main && bash scripts/run-quality-gates.sh
git push -u origin impl/plan-0-plan-scoping
```

Update the plan's `Verified against:` line to the post-rebase SHA if any anchored file changed.

- [ ] **Step 4: Open the PR (body written outside the repo)**

Write the body to `"$(mktemp)"` and pass it with `--body-file`. Content: What (P0 of Factory v3.2; plan path; the four deliverables); the tier statement — "IMPLEMENT-phase PR carrying its plan by the REQ-381 exemption; not patch tier (edits the review-gate rule and relaxes when proofs are owed)"; the gate checklist with boxes ticked only for checks actually run; the PLAN/ANALYZE phase line; Tier: Full phase PR; the attribution footer.

- [ ] **Step 5: Run the verifier from a second terminal**

Run (outside Claude Code): `scripts/run-verifier.sh <PR#>`
Expected: findings posted; "Verifier findings posted" check green.
