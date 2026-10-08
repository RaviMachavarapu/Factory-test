#!/usr/bin/env bash
# REQ-396 (constitution amendment D, its own design lane after the v3.2 retrospective, BL-041): the wording the P7 builds
# deferred, as docs/retrospectives/2026-10-04-v3-2-closeout.md's Proposed Changes item 3 settles it — D1 and D5
# (art-naming-tagging), D4 (art-secrets-hygiene), D7 (art-threat-driven-security, art-review-gate,
# art-formal-verification) — and item 2's patch-tier bullet in .claude/rules/review-gate.md (a rubric-only medium_cap
# reduction to the default, a narrowing of item 2's 'toward'). Each reworded sentence is pinned against what the file it names actually does: the deny
# lists, the slug test's exemptions, the suppression test and gates section 3. Twelve articles still; amendment C's pins
# still hold. The spec records it (REQ-396, an amended: item, the Compliance line's four amendment PRs).
# Covers: REQ-396
# Covers: REQ-371
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=constitution.md
art() { awk -v s="slug: $1" '$0 == s {f=1} f && /^---$/ {exit} f' "$C" | tr '\n' ' ' | tr -s ' '; }
how() { art "$1" | sed -n 's/.*\*\*How to apply:\*\*//p'; }
has() { grep -qF -- "$1" <<<"$2"; }
lacks() { ! grep -qF -- "$1" <<<"$2"; }

# (a) twelve articles; every How to apply names an existing enforcing file or says convention (no mechanism).
ck "constitution keeps twelve articles; every How to apply names a file or says convention" bash tests/governance/test_constitution_articles.sh

# (b) D1: the task-id form is convention.
nt=$(how art-naming-tagging)
ck "D1: art-naming-tagging's How to apply says the task-id form is convention (no mechanism)" \
  has 'The task-id form (`Task N.M`, or `TASK-NNN`) is convention (no mechanism)' "$nt"

# (c) D4: the claim narrowed to what the two deny lists say.
sh=$(how art-secrets-hygiene)
ck "D4: art-secrets-hygiene's How to apply: sessions denied .env and .env.*, the verifier every .env* name" \
  has 'Claude sessions are denied reads of `.env` and `.env.*` (`.claude/settings.json`), and the verifier every `.env*` name (`scripts/run-verifier.sh`'"'"'s deny list)' "$sh"
ck "D4: the old wider claim (sessions and the verifier denied .env* reads) is gone" lacks 'are denied `.env*` reads' "$sh"
ck "D4 holds: .claude/settings.json's deny list denies exactly Read(./.env) and Read(./.env.*) among the .env rules" \
  python3 - .claude/settings.json <<'PY'
import json, sys
deny = json.load(open(sys.argv[1]))["permissions"]["deny"]
env = sorted(r for r in deny if ".env" in r)
assert env == ["Read(./.env)", "Read(./.env.*)"], env
PY
ck "D4 holds: scripts/run-verifier.sh's deny list names Read(./.env*)" grep -qF '"Read(./.env*)",' scripts/run-verifier.sh

# (d) D5: the slug check's exemptions, as test_reviews_use_slugs.sh applies them (both of its scans).
ck "D5: art-naming-tagging's How to apply names the slug check's two exemptions" \
  has 'anywhere in `docs/` (`docs/examples/` included) and in the files a session reads as instructions, except an archived review (`docs/reviews/archive-*`) and a document with a `status: superseded` line in its first 20 lines' "$nt"
SL=tests/governance/test_reviews_use_slugs.sh
ck "D5 holds: test_reviews_use_slugs.sh's Roman-numeral scan exempts docs/reviews/archive-* and status: superseded" \
  bash -c 'grep -qF "docs/reviews/archive-*) return 0 ;;" "$1" && grep -qF "grep -q '"'"'^status: superseded'"'"'" "$1"' _ "$SL"
ck "D5 holds: test_reviews_use_slugs.sh's slug-existence scan applies the same two exemptions" \
  bash -c 'grep -qF "if f.startswith(\"docs/reviews/archive-\"):" "$1" && grep -qF "re.search(r\"(?m)^status: superseded\", head)" "$1"' _ "$SL"

# (e) D7: three sentences.
td=$(how art-threat-driven-security)
ck "D7: art-threat-driven-security names test_suppressions.sh and gates section 3 as what runs check-suppressions.sh" \
  has '`scripts/check-suppressions.sh` (run by `tests/governance/test_suppressions.sh`, gates section 3, and by `/security-review`) requires every suppression to cite a live `SEC-NNN`' "$td"
ck "D7 holds: /security-review lists 'bash scripts/check-suppressions.sh passes' among its pass conditions" grep -qF -- '- `bash scripts/check-suppressions.sh` passes.' .claude/commands/security-review.md
ck "D7 holds: test_suppressions.sh runs scripts/check-suppressions.sh" \
  bash -c 'grep -qF "CS=\"\$ROOT/scripts/check-suppressions.sh\"" "$1" && grep -qF "bash \"\$CS\"" "$1"' _ tests/governance/test_suppressions.sh
ck "D7 holds: gates section 3 of run-quality-gates.sh runs tests/governance/test_*.sh" \
  bash -c 'grep -qF "# 3. Governance tests" "$1" && grep -qF "for t in tests/governance/test_*.sh; do" "$1"' _ scripts/run-quality-gates.sh
rg=$(how art-review-gate)
ck "D7: art-review-gate's How to apply: a source file under the stack pack's source_roots, verification/, or a phase artifact" \
  has 'if a change touches a source file under the stack pack'"'"'s `source_roots`, `verification/`, or a phase artifact, it goes through a PR' "$rg"
ck "D7: art-review-gate no longer says a change touching src/" lacks 'if a change touches `src/`' "$rg"
fv=$(how art-formal-verification)
ck "D7: art-formal-verification: the contract extraction step is convention (no mechanism) until v3.3" \
  has '`[verifiable]` additionally adds a contract extraction step (v3.3+); until then no REQ carries `[verifiable]` and the step does not apply (no mechanism)' "$fv"

# (f) the spec records amendment D (the spec is a factory document, fenced out of every instance).
SP=docs/specs/2026-09-25-factory-v3-2-design.md
factory_doc_ck "the spec defines REQ-396" "$SP" grep -qE '^- \*\*REQ-396:\*\*' "$SP"
factory_doc_ck "REQ-396 names amendment D, design/amendment-d and BL-041" "$SP" \
  bash -c 'l=$(grep -E "^- \*\*REQ-396:\*\*" "$1"); for w in "amendment PR D" "design/amendment-d" "BL-041" "art-naming-tagging" "art-secrets-hygiene" "art-threat-driven-security" "art-review-gate" "art-formal-verification" "medium_cap"; do grep -qF -- "$w" <<<"$l" || exit 1; done' _ "$SP"
ad=$(grep -F -- '- "amendment D (design/amendment-d' "$SP" 2>/dev/null || true)
factory_doc_ck "the spec's amended: list has an amendment D entry naming REQ-396" "$SP" \
  bash -c 'grep -qF "amendment D" <<<"$1" && grep -qF "REQ-396" <<<"$1"' _ "$ad"
factory_doc_ck "the amendment D item is one double-quoted YAML item indented under amended:, no inner double quote, no backslash" "$SP" \
  python3 -c 'import sys; l = sys.argv[1]; assert l.startswith("  - \""), l[:20]; s = l.strip(); assert s.endswith("\""); b = s[3:-1]; assert "\"" not in b and "\\" not in b' "$ad"
factory_doc_ck "the Compliance line says four amendment PRs, D in its own design lane" "$SP" \
  bash -c 'l=$(grep -F "**Compliance:**" "$1"); grep -qF "one of four amendment PRs (A with P2, B with P5, C in P7, D in its own design lane after the v3.2 retrospective)" <<<"$l" && ! grep -qF "three amendment PRs" <<<"$l"' _ "$SP"

# (g) review-gate.md's patch tier admits a rubric-only medium_cap reduction to the default (item 2, narrowed), and
#     routes any other cap change to its own patch/<slug> PR as a named exception (D's addition); the exceptions agree.
pt=$(awk '/^## Patch tier/{f=1; next} /^## /{f=0} f' .claude/rules/review-gate.md | tr '\n' ' ' | tr -s ' ')
for w in 'a reduction of `medium_cap` in `docs/security/RUBRIC.md` to the constitution'"'"'s default (5' \
         'from above it, with the kernel (`scripts/lib/specflow/disposition.py`) and the spec untouched, takes the patch tier' \
         'qualifying is convention (no mechanism): a reviewer reads the diff; the verifier skill does not check it (BL-045)' \
         'Any other change of `medium_cap` — one that does not reduce it to 5 from above — takes its own reviewed PR on a `patch/<slug>` branch that carries no other security artifact, under this tier'"'"'s Process bullet (TDD, green gates, the verifier'"'"'s review), merged before the ship PR it governs (ADR-002: the gate reads the cap from the base ref, so a PR cannot raise its own' \
         'a narrowing of the retrospective'"'"'s item 2' \
         'amendment D'"'"'s addition beyond it' \
         '- **Does not qualify:** anything touching `[verifiable*]` REQs, ADRs, the constitution, security artifacts, or release artifacts — those take the full phase path — except the known-limitations fallback-line follow-up' \
         'the rubric-only `medium_cap` reduction to the default (the bullet above)' \
         'a `medium_cap` change other than a reduction to the default, on its own `patch/<slug>` PR that carries no other security artifact (the same bullet)' \
         'three exceptions, each under the Process bullet' \
         'the first of the three security-artifact exceptions'; do
  ck "review-gate.md's patch tier says '$w'" has "$w" "$pt"
done

# (i) the P7 plan-header items still owed under BL-041 (item 4 of the retrospective's Proposed Changes), each a dated
# correction in place, and three documentation carry-overs from PR #74 run 4.
# Covers: REQ-371
PL=docs/plans/2026-10-03-factory-v3-2-p7-plan.md
AT=scripts/lib/specflow/attestation.py
planline() { grep -E -- "$1" "$PL" | tr '\n' ' ' | tr -s ' '; }
factory_doc_ck "the docs/examples reader corrections say gates section 3 (the governance tests), never section 4 (the per-stack hook)" "$PL" \
  bash -c 'c=$(grep -F "test_reviews_use_slugs.sh" "$1" | grep -F "amendment D"); [ -n "$c" ] && grep -qF "gates section 3" <<<"$c" && ! grep -qF "gates section 4" <<<"$c"' _ "$PL"
# 2026-10-05 (the post-3.2.1 records patch; REQ-382, BL-022): the 3.2.1 review scored the dfe-3 residual as SEC-022, so
# the row now carries that vector instead of amendment D's "not scored" note, and the 3.2.1 disposition's date.
factory_doc_ck "the dfe-3 residual carries the vector the 3.2.1 review scored it with (SEC-022), no longer amendment D's 'not scored' note" docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 's=$(grep -E "^\| dfe-3 " "$1"); grep -qF "scored by the 3.2.1 review as SEC-022" <<<"$s" && ! grep -qF "This row records no scored CVSS vector (unlike dfe-10)" <<<"$s"' _ docs/architecture/2026-09-25-factory-v3-2-threat-model.md
factory_doc_ck "D13 holds: attestation.py counts base_ref_* and automatic_base_change* events at or after the waiver's second, no-time reads waiver-timeline-unknown" "$AT" \
  bash -c 'grep -qF "name.startswith(\"base_ref_\") or name.startswith(\"automatic_base_change\")" "$1" && grep -qF "if any(t >= created_at for t in base_changes)" "$1" && grep -qF "return judged(\"waiver-timeline-unknown\")" "$1"' _ "$AT"
factory_doc_ck "D13: the plan's R4 names every base_ref_* and automatic_base_change* event at or after the waiver's created_at, and the no-time case" "$PL" \
  bash -c 's=$(grep -E "^- \*\*R4 — " "$1"); for w in "every \`base_ref_*\` and \`automatic_base_change*\` timeline event" "at or after the waiver'"'"'s \`created_at\`" "no ISO-8601 UTC second time reads \`waiver-timeline-unknown\`"; do grep -qF -- "$w" <<<"$s" || { echo "$w"; exit 1; }; done' _ "$PL"
factory_doc_ck "D13: the plan's Interfaces paragraph names every base_ref_* and automatic_base_change* event, at or after" "$PL" \
  bash -c 's=$(grep -E "^then a rationale of at least 20 char" "$1"); for w in "every \`base_ref_*\` and \`automatic_base_change*\` timeline event" "at or after it, the same second counting" "reads \`waiver-timeline-unknown\`"; do grep -qF -- "$w" <<<"$s" || { echo "$w"; exit 1; }; done' _ "$PL"
factory_doc_ck "D19: the plan's implements: lists REQ-313 and REQ-385" "$PL" \
  bash -c 'l=$(grep -m1 "^implements:" "$1"); grep -qF "REQ-313" <<<"$l" && grep -qF "REQ-385" <<<"$l"' _ "$PL"
factory_doc_ck "item 3: the readers paragraph and Review Focus 5 say test_reviews_use_slugs.sh reads docs/examples/" "$PL" \
  bash -c 'for k in "^- \*\*Instance-visible readers of" "^5\. \*\*The example is inert"; do l=$(grep -E "$k" "$1"); grep -qF "test_reviews_use_slugs.sh" <<<"$l" && grep -qF "docs/examples/" <<<"$l" && grep -qF "amendment D" <<<"$l" || { echo "$k"; exit 1; }; done' _ "$PL"
factory_doc_ck "item 4: R10 lists the eleven documents a tauri instance inherits under docs/" "$PL" \
  bash -c 's=$(grep -E "^- \*\*R10 — " "$1"); for w in docs/BACKLOG.md docs/GLOSSARY.md docs/adr/002-security-disposition-decision.md docs/adr/README.md docs/architecture/README.md docs/releases/README.md docs/releases/store-checklist.md docs/releases/tester-instructions.md docs/retrospectives/README.md docs/security/README.md docs/security/RUBRIC.md docs/getting-started.html; do grep -qF -- "\`$w\`" <<<"$s" || { echo "$w"; exit 1; }; done' _ "$PL"
factory_doc_ck "item 5: R2(g) says amendment D records the task-id form as convention (no mechanism)" "$PL" \
  bash -c 's=$(grep -E "^- \*\*R2 — " "$1"); grep -qF "records the task-id form as convention (no mechanism)" <<<"$s"' _ "$PL"
factory_doc_ck "item 6: the plan's M6 carries the article-citation step" "$PL" \
  bash -c 's=$(grep -E "^- \*\*M6 — " "$1"); grep -qF "bash tests/governance/test_reviews_use_slugs.sh" <<<"$s" && grep -qF "Roman numeral" <<<"$s"' _ "$PL"
factory_doc_ck "item 6: the index folded its separate 'Added to M6' paragraph into M6" docs/examples/README.md \
  bash -c '! grep -qF "Added to M6 by this build" "$1"' _ docs/examples/README.md
TM=docs/architecture/2026-09-25-factory-v3-2-threat-model.md
factory_doc_ck "carry-over: dfe-10's PR #74 update names the .claude/settings.json hooks, not a PostToolUse hook" "$TM" \
  bash -c 's=$(grep -E "^\| dfe-10 " "$1"); grep -qF "the same surface as the \`.claude/settings.json\` hooks this row already names" <<<"$s" && ! grep -qF "PostToolUse" <<<"$s"' _ "$TM"
factory_doc_ck "carry-over: dfe-3 records that a shipped review's provenance commit is unchecked and the digest is the evidence (BL-040)" "$TM" \
  bash -c 's=$(grep -E "^\| dfe-3 " "$1"); for w in "provenance commit" "any other value both pass" "recompute" "BL-040" "SEC-022"; do grep -qF -- "$w" <<<"$s" || { echo "$w"; exit 1; }; done' _ "$TM"
ck "carry-over: README's run-instance-tests row says --stack replaces the touched-stack default" \
  bash -c 'grep -F "scripts/run-instance-tests.sh [--base" "$1" | grep -qF "\`--stack\` replaces that touched-stack default"' _ README.md
factory_doc_ck "BL-041's Planned line records amendment D's PR and stays open" docs/BACKLOG.md \
  bash -c 's=$(awk "/^### BL-041 /{f=1; next} /^### /{f=0} f" "$1"); grep -qF -- "- **Planned:** carried by design/amendment-d (PR #75, 2026-10-04; open as this line is written): the constitution items (item 3), the review-gate patch-tier bullet (item 2) and the plan-header items (item 4); the next retrospective records it once merged." <<<"$s" && grep -qF -- "- **Status:** open" <<<"$s"' _ docs/BACKLOG.md

# (h) amendment C's pins still hold.
ck "test_constitution_amendment_c.sh still passes" bash tests/governance/test_constitution_amendment_c.sh
# PR #75 verifier run 1: REQ-396 is claimed by the P7 plan (the spec groups it under P7; the design lane adds no plan);
# the dfe-3 residual carries an owner and an expiry; the plan's "Still owed" paragraph records that amendment D applied
# the items; BL-045 records the verifier-skill check the patch-tier exception relies on.
# Covers: REQ-396
factory_doc_ck "the P7 plan's implements: claims REQ-396" "$PL" \
  bash -c 'grep -E "^implements:" "$1" | grep -qF "REQ-396"' _ "$PL"
factory_doc_ck "the dfe-3 residual carries an owner, an expiry (re-dated to the 3.2.1 disposition's) and its provisional score (the next second reviewer confirms it)" "$TM" \
  bash -c 's=$(grep -E "^\| dfe-3 " "$1"); for w in "owner: kpingali123" "expires: 2027-01-31; re-dated 2026-10-05" "provisional (solo mode) until the next second reviewer confirms"; do grep -qF -- "$w" <<<"$s" || { echo "$w"; exit 1; }; done' _ "$TM"
factory_doc_ck "the plan's Still-owed paragraph says amendment D's PR applied the items" "$PL" \
  bash -c 'grep -F "Still owed under BL-041" "$1" | grep -qF "applied by amendment D'"'"'s PR #75"' _ "$PL"
factory_doc_ck "BL-045 asks the verifier skill to check the patch-tier medium_cap exception" docs/BACKLOG.md \
  bash -c 'awk "/^### BL-045 /{f=1; next} /^### /{f=0} f" "$1" | grep -qF "SKILL.md"' _ docs/BACKLOG.md

factory_doc_ck "the P7 plan's Verified-against paragraph anchors amendment D's corrections" "$PL" \
  bash -c 'grep -F "**Verified against:**" "$1" | grep -qF "design/amendment-d"' _ "$PL"

finish test_constitution_amendment_d
