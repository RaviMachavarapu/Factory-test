#!/usr/bin/env bash
# REQ-343 (constitution amendment B, with P5's PLAN PR): art-branch-as-state lists both paths' branch names, permits init's
# first commit on main and the doc-only minor exception while every phase transition stays a PR, permits squash merges and
# calls .specflow.yml configuration; art-review-gate states the Dependabot rule P4 shipped and its forgeable-author
# residual, the admin bypass of the required review as well as red checks, and the maintainer's sign-off on solo mode's
# zero required approvals (REQ-314); art-threat-driven-security names the lanes back-edge and the informational 0.0 row;
# art-release-readiness judges "tag missing" after the merge; art-retrospective-cadence triggers on the release PR of
# either path. No interim reading or deadline survives where a session reads the rules. The PR template has one checklist
# per lane (REQ-343), and review-gate.md permits squash merges on both paths (REQ-340).
# Covers: REQ-343
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=constitution.md
art() { awk -v s="slug: $1" '$0 == s {f=1} f && /^---$/ {exit} f' "$C" | tr '\n' ' ' | tr -s ' '; }
bas=$(art art-branch-as-state); rev=$(art art-review-gate); tds=$(art art-threat-driven-security)
rel=$(art art-release-readiness); ret=$(art art-retrospective-cadence)
ck "constitution keeps twelve well-formed articles" bash tests/governance/test_constitution_articles.sh
for b in 'design/<slug>' 'build/<slug>-N' 'ship/<version>' 'build/sec-<id>' 'phase/spec-<slug>' 'phase/arch-<slug>' \
         'phase/plan-<slug>' 'impl/plan-N-<plan slug>' 'impl/sec-<id>' 'phase/validate' 'phase/security' 'phase/release' \
         'patch/<slug>' 'phase/retro-YYYY-MM-DD'; do
  ck "art-branch-as-state names $b" grep -qF -- "$b" <<<"$bas"
done
ck "art-branch-as-state no longer says 'No work on main' (init commits on main; F-21)" no grep -qF 'No work on `main`' <<<"$bas"
ck "art-branch-as-state permits init's first commit and the doc-only minor exception" \
  bash -c 'grep -qF "first commit" <<<"$1" && grep -qi "init" <<<"$1" && grep -qi "minor exception" <<<"$1"' _ "$bas"
ck "art-branch-as-state: every phase transition is still a PR that reaches main, directly or stacked" \
  bash -c 'grep -qF "reaches \`main\`" <<<"$1" && grep -qi "stacked" <<<"$1"' _ "$bas"
ck "art-branch-as-state: squash merges permitted; .specflow.yml is configuration, not state; no state file" \
  bash -c 'grep -qF "Squash merges are permitted" <<<"$1" && grep -qF ".specflow.yml" <<<"$1" && grep -qi "configuration, not state" <<<"$1" && grep -qF "no out-of-band state file" <<<"$1"' _ "$bas"
for w in 'verified' 'web-flow' 'never `.github/`' 'only moves the versions' 'fails closed' 'anyone with write access' 'dfe-13' \
         'without the required approving review' 'nothing server-side' 'Solo sign-off:' 'zero required approvals' 'REQ-314'; do
  ck "art-review-gate says '$w'" grep -qF -- "$w" <<<"$rev"
done
ck "art-review-gate drops the overclaim and the P4 deferral" \
  bash -c '! grep -qF "a commit by anyone else removes the exemption" <<<"$1" && ! grep -qF "deferred to P4" <<<"$1"' _ "$rev"
ck "art-review-gate: the solo marker is an audit trail, not an enforced control, on any GitHub plan (threat model's first residual)" \
  bash -c 'grep -qF "in solo mode, on any GitHub plan, it is a tamper-evident audit trail" <<<"$1" && ! grep -qF "on a free-plan private repository it is a tamper-evident" <<<"$1"' _ "$rev"
ck "art-threat-driven-security: the informational 0.0 row follows the 0.1–3.9 low row" \
  python3 - "$C" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
a = t[t.index("slug: art-threat-driven-security"):]
a = a[: a.index("\n---\n")]
rows = [l.strip() for l in a.splitlines() if l.startswith("| ")]
i = rows.index("| low | 0.1–3.9 |")
assert rows[i + 1] == "| low (informational) | 0.0 |", rows
PY
ck "art-threat-driven-security: an informational finding is recorded as severity low, never a manufactured score" \
  bash -c 'grep -qi "informational" <<<"$1" && grep -qF "severity: low" <<<"$1" && grep -qi "manufactured" <<<"$1"' _ "$tds"
ck "art-threat-driven-security: the back-edge names impl/sec- (regulated) and build/sec- (lanes), resuming phase/security or ship/<version>" \
  bash -c 'grep -qF "impl/sec-<finding-id>" <<<"$1" && grep -qF "build/sec-<finding-id>" <<<"$1" && grep -qF "ship/<version>" <<<"$1"' _ "$tds"
for w in 'after the merge' 'already exists' 'verify-release.sh' 'PR template' 'REQ-350' 'transcribed' 'fallback' 'tag missing'; do
  ck "art-release-readiness says '$w'" grep -qiF -- "$w" <<<"$rel"
done
# Covers: REQ-353
ck "art-release-readiness (superseded by amendment C, REQ-353): CI builds the reproducible subset itself; the local dist/ check stays" \
  bash -c 'grep -qF "the reproducible subset it builds itself from the PR head'"'"'s tree" <<<"$1" && grep -qF "where \`/release\` produced \`dist/manifest.json\` locally" <<<"$1" && ! grep -qF "manifest absent" <<<"$1"' _ "$rel"
ck "art-retrospective-cadence triggers on ship/<version> and phase/release, recommended not automatic" \
  bash -c 'grep -qF "ship/<version>" <<<"$1" && grep -qF "phase/release" <<<"$1" && grep -qF "recommended; not automatic" <<<"$1"' _ "$ret"
for f in "$C" .claude/rules/review-gate.md docs/security/RUBRIC.md .claude/skills/verifier/SKILL.md \
         .github/PULL_REQUEST_TEMPLATE.md schemas/security-disposition-template.md docs/GLOSSARY.md; do
  ck "$f: no interim reading, no override of an article, no amendment-B deadline" \
    bash -c 't=$(tr "\n" " " < "$1"); ! grep -qiF "interim reading" <<<"$t" && ! grep -qF "2026-10-31" <<<"$t" && ! grep -qF "until amendment B" <<<"$t" && ! grep -qF "overrides the article" <<<"$t"' _ "$f"
done
rg=.claude/rules/review-gate.md
ck "review-gate.md: squash merges are permitted on both paths (REQ-340)" \
  grep -qF 'Squash merges are permitted on both paths' <<<"$(awk '/^## Paths and branch names/{f=1; next} /^## /{f=0} f' "$rg" | tr '\n' ' ')"
rel_gate=$(grep -F "RELEASE exit gate" "$rg")
ck "review-gate.md RELEASE exit gate: art-release-readiness judges 'tag missing' after the merge; the control is unchanged" \
  bash -c 'grep -qF "judges \"tag missing\" after the merge" <<<"$1" && grep -qF "PR template" <<<"$1" && grep -qF "git tag -v" <<<"$1"' _ "$rel_gate"
PT=.github/PULL_REQUEST_TEMPLATE.md
for lane in 'Design lane' 'Build lane' 'Ship lane'; do ck "the PR template has a $lane checklist" grep -qE "^#### $lane — " "$PT"; done
for b in 'design/<slug>' 'phase/spec-<slug>' 'phase/plan-<slug>' 'build/<slug>-N' 'impl/plan-N-<plan slug>' 'phase/validate' \
         'ship/<version>' 'phase/security' 'phase/release'; do
  ck "the PR template's lane headings name $b" bash -c 'grep -E "^#### " "$1" | grep -qF -- "$2"' _ "$PT" "$b"
done
# P5 lows patch (PR #48 verifier run 7, finding 4; REQ-340): the Build-lane heading says impl/plan-N-<plan slug>, as
# review-gate.md, CLAUDE.md, README and — since amendment C — the constitution do.
ck "the PR template's lane headings no longer say impl/plan-N-<name>" bash -c '! grep -E "^#### " "$1" | grep -qF "impl/plan-N-<name>"' _ "$PT"
ck "the PR template keeps its SECURITY and RELEASE lines and its plan-style rule" \
  bash -c 'grep -q "^\*\*SECURITY\*\*" "$1" && grep -q "^\*\*RELEASE\*\*" "$1" && grep -qF "implementation as intent" "$1" && grep -qF "implements:" "$1"' _ "$PT"
# PR #47 verifier medium 3 and low 7 (REQ-343): art-branch-as-state's two exceptions carry the admin-bypass convention;
# art-threat-driven-security says an informational low records a real observation, never a placeholder.
# Covers: REQ-343
ck "art-branch-as-state: the two exceptions are followed by the admin-bypass convention, pointing at art-review-gate" \
  grep -qF 'the doc-only minor exception bounded in `.claude/rules/review-gate.md` (a convention where `enforce_admins: false` or a free-plan private repository lets an admin push to `main` directly; see `art-review-gate`).' constitution.md
ck "art-threat-driven-security: an informational low still records a real observation, not a placeholder" \
  grep -qF 'an informational low still records a real observation; it is not a placeholder finding (see "Empty reviews are valid").' constitution.md

# PR #47 verifier medium 2, lows 5 and 8 (REQ-343): the plan's amendment-B text says what amendment B narrowed, which
# documents it edits, which instruction surfaces it touches, and what P6 owes art-release-readiness when REQ-350 ships.
PL=docs/plans/2026-09-28-factory-v3-2-p5-plan.md
if [ -f "$PL" ]; then
  ck "the plan: amendment B weakens no mechanism, and the article's text is narrowed in two places (not 'weakens no control')" \
    bash -c 'grep -qF "It weakens no mechanism (the article'"'"'s text is narrowed in two places: the manifest-absent condition and the GPG-or-SSH fallback)" "$1" && ! grep -qF "It weakens no control" "$1"' _ "$PL"
  ck "the plan's R2: the eight documents amendment B edits besides the constitution, and no 'changes no code and no gate'" \
    bash -c 'grep -qF "the eight documents it edits besides it (review-gate.md, RUBRIC.md, SKILL.md, the PR template, the schema template, GLOSSARY.md, the threat model, the spec)" "$1" && ! grep -qF "six documents" "$1" && ! grep -qF "It changes no code and no gate" "$1"' _ "$PL"
  ck "the plan's R2: SKILL.md step 7 and the PR template are surfaces a human reads as gate code" \
    grep -qF 'It changes no gate script; SKILL.md step 7 and the PR template are verifier-instruction and `.github/` surfaces a human reads as gate code' "$PL"
  ck "the plan's Open → P6: the article update art-release-readiness owes when REQ-350 ships" \
    bash -c 'grep -F -- "- **Open → P6:**" "$1" | grep -qF "expires when REQ-350 ships — P6 (or amendment C) owes the article update"' _ "$PL"
fi

# PR #48 verifier run 2, F1 (REQ-343): the two corrections to amendment B's own text that PR #47's verifier raised (findings
# 3 and 7) are edited on the IMPLEMENT branch; the plan's Compliance line and the spec's P5 IMPLEMENT amended: entry record
# them, and the maintainer signs off in #48's merge comment. REQ-citation low (REQ-343): the plan's context-citation rule
# names Task 11's REQ-332-only commit.
# Covers: REQ-343
if [ -f "$PL" ]; then
  ck "the plan's Compliance line names the two IMPLEMENT-branch corrections, their record and the maintainer's sign-off" \
    grep -qF -- '- **Compliance.** Constitution changes only in the "Amendment B" section, on this branch (amendment PR B); nothing on the IMPLEMENT branch edits `constitution.md`, except the two corrections PR #47'"'"'s verifier raised against amendment B'"'"'s own text (findings 3 and 7: the admin-bypass convention in `art-branch-as-state`; the informational-low-is-not-a-placeholder clause in `art-threat-driven-security`), folded into the stacked IMPLEMENT PR, recorded in the spec'"'"'s P5 IMPLEMENT `amended:` entry and signed off by the maintainer in #48'"'"'s merge comment.' "$PL"
  ck "the plan's context-citation rule names Task 11's REQ-332-only commit" \
    grep -qF "each citing commit also cites the P5 REQ it changes, except Task 11's security-document commit, which cites REQ-332 alone (a P3/P4 hand-off; the plan lists REQ-332 as context)" "$PL"
  # PR #48 verifier run 5, finding 3 (REQ-343): the three test-only maintenance commits of earlier plans' REQs are exceptions too.
  ck "the plan's context-citation rule names the three test-only maintenance commits (fbbfcad, 2b2d34d, 9f5c2f9)" \
    grep -qF "and the three test-only maintenance commits of earlier plans' REQs — fbbfcad (REQ-324 alone), 2b2d34d (REQ-303, an earlier plan's claim, neither a P5 claim nor listed here) and 9f5c2f9 (REQ-360, beside P5's REQ-306) (test-only maintenance of earlier plans' REQs)." "$PL"
fi
SP=docs/specs/2026-09-25-factory-v3-2-design.md
if [ -f "$SP" ]; then
  a5i=$(grep -F 'P5 IMPLEMENT PR' "$SP" || true)
  for w in 'PR #47 verifier findings 3 and 7' 'a convention where `enforce_admins: false` or a free-plan private repository lets an admin push to `main` directly' \
           'an informational low still records a real observation; it is not a placeholder finding' 'signs off on both in #48'"'"'s merge comment'; do
    ck "the spec's P5 IMPLEMENT amended: entry records the constitution edits: '$w'" grep -qF -- "$w" <<<"$a5i"
  done
fi

# PR #48 verifier run 3, findings 1 and 2: the plan that governs #48 says what shipped. Its Spec paragraph and R19 name
# REQ-389's body change (code mode -> full mode, the per-article citation) and the amended: entry that records it; R9 states
# rule 1b as shipped (markers and waivers, both directions, custom roles through the legacy permission field, the base
# binding), and R21(d) and the Interfaces "PR state" paragraph the shipped approval rule.
# Covers: REQ-389
# Covers: REQ-382
# Covers: REQ-341
if [ -f "$PL" ]; then
  ck "the plan's Spec paragraph names REQ-389's body change and its amended: record (not 'No REQ body changes.')" \
    bash -c 'grep -F "**Spec:**" "$1" | grep -qF "No REQ body changes, except REQ-389'"'"'s (PR #48 verifier finding 1: '"'"'code mode'"'"' → '"'"'full mode'"'"', and the per-article citation), recorded in the spec'"'"'s P5 IMPLEMENT \`amended:\` entry." && ! grep -F "**Spec:**" "$1" | grep -qF "No REQ body changes. The PLAN PR"' _ "$PL"
  ck "the plan's R19 says REQ-389's body now names full mode, recorded by the P5 IMPLEMENT amended: entry" \
    bash -c 'grep -F -- "- **R19" "$1" | grep -qF "REQ-389'"'"'s body now reads so (PR #48 verifier finding 1: its '"'"'code mode'"'"' became '"'"'full mode'"'"', with the per-article citation), a REQ body change the spec'"'"'s P5 IMPLEMENT \`amended:\` entry records." && ! grep -qF "Task 16'"'"'s \`amended:\` entry records the reading" "$1"' _ "$PL"
  r9=$(grep -F -- '- **R9 ' "$PL" || true)
  for w in 'a `MEMBER`'"'"'s or `COLLABORATOR`'"'"'s marker or waiver counts only with a writing role' \
           'a custom or empty `role_name` is resolved through the legacy `permission` field' \
           'an unreadable role is never accepted and keeps blocking' \
           'a known `read`, `triage` or `none` role neither accepts nor blocks' \
           '`base-mismatch` refuses only an `APPROVE`'"'"'s acceptance'; do
    ck "the plan's R9 states the shipped rule 1b: '$w'" grep -qF -- "$w" <<<"$r9"
  done
  ck "the plan's R9 no longer says attestation markers are unchanged" bash -c '! grep -qF "Attestation markers are unchanged" <<<"$1"' _ "$r9"
  r21=$(grep -F -- '- **R21 ' "$PL" || true); prs=$(grep -F '**PR state** (Task 6)' "$PL" || true)
  for w in 'an `OWNER`, or a `MEMBER` or `COLLABORATOR` whose repository role is `admin`, `maintain` or `write`' \
           'neither the PR author nor an author or committer of any of its commits' \
           'a reviewer'"'"'s latest review at the head decides' \
           'an undismissed `CHANGES_REQUESTED` at any commit means no approval'; do
    ck "the plan's R21(d) states the shipped approval rule: '$w'" grep -qF -- "$w" <<<"$r21"
    ck "the plan's Interfaces \"PR state\" states the shipped approval rule: '$w'" grep -qF -- "$w" <<<"$prs"
  done
  ck "the plan's R21(d) no longer reads 'at least one reviewer other than the PR author approved'" \
    bash -c '! grep -qF "at least one reviewer other than the PR author approved" <<<"$1"' _ "$r21"
fi

# PR #48 verifier run 4 (REQ-343, REQ-340, REQ-311): finding 3 — the plan's Partial claims say constitution.md on this
# branch is an amendment-B follow-up signed off in #48's merge comment; finding 4 — the Open -> P7 list carries
# art-branch-as-state's impl/plan-N-<plan slug> wording for amendment C; finding 5 — Task 16's Interfaces and the
# "Classifier additions" paragraph say what shipped.
# Covers: REQ-311
if [ -f "$PL" ]; then
  ck "the plan's REQ-343 partial claim: constitution.md on this branch is an amendment-B follow-up, signed off in #48's merge comment" \
    bash -c 'grep -F -- "- **REQ-343:**" "$1" | grep -qF "\`constitution.md\` on this branch is an amendment-B follow-up (two corrections), signed off in #48'"'"'s merge comment"' _ "$PL"
  ck "the plan's Open -> P7: art-branch-as-state's impl/plan-N-<name> -> impl/plan-N-<plan slug> for amendment C" \
    bash -c 'grep -F "**Open → P7:**" "$1" | grep -qF "art-branch-as-state'"'"'s \`impl/plan-N-<name>\` → \`impl/plan-N-<plan slug>\` (N the plan'"'"'s \`## Build N\` section), as review-gate.md, CLAUDE.md and README already say"' _ "$PL"
  t16=$(awk '/^### Task 16:/{f=1} /^- \[[ x]\] \*\*Step 1/{f=0} f' "$PL" | tr '\n' ' ')
  for w in 'phase/security and phase/release' 'REQ bodies unchanged except REQ-389'"'"'s and, synced to what shipped, REQ-311'"'"'s, REQ-340'"'"'s, REQ-382'"'"'s, REQ-385'"'"'s and REQ-393'"'"'s' \
           'final-review rulings' 'rule 1b for markers and waivers' 'fixtures 72–102' 'base binding'; do
    ck "the plan's Task 16 Interfaces says what shipped: '$w'" grep -qF -- "$w" <<<"$t16"
  done
  ck "the plan's Task 16 no longer quotes an entry opening with an unqualified 'REQ bodies unchanged —'" \
    bash -c '! grep -qF "that narrow, extend or read literal REQ text, REQ bodies unchanged — " <<<"$1"' _ "$t16"
  ca=$(grep -F '**Classifier additions**' "$PL" || true)
  for w in 'rule 1b for markers and waivers' 'a known `read`, `triage` or `none` role neither accepts nor blocks' \
           'never accepted and keeps blocking' 'legacy `permission` field' '`base-mismatch`' '`request-changes-base-mismatch`' \
           '`base-lockfile-v1`' 'fixtures 72–102' 'each `MEMBER` or `COLLABORATOR` commenter'"'"'s role'; do
    ck "the plan's Classifier additions say what shipped: '$w'" grep -qF -- "$w" <<<"$ca"
  done
  # Wave-4 re-review low 2 (REQ-385): Interfaces "The wrapper" renders the stacked Merge as two commands, merge first.
  wm=$(grep -F -- '- `Merge(pr)`:' "$PL" || true)
  ck "the plan's 'The wrapper' Merge(pr): the stacked form is the merge, then the retarget to this PR's base (R22)" \
    grep -qF '`gh pr merge <pr> --merge --match-head-commit <head> && gh pr edit <m> --base <this PR'"'"'s base>` (R22: the merge first' <<<"$wm"
  ck "the plan's 'The wrapper' Merge(pr) no longer carries the em-dash prose form" \
    bash -c '! grep -qF -- "— PR #<m> is stacked" <<<"$1" && ! grep -qF "retarget it before deleting this branch" <<<"$1"' _ "$wm"
  # PR #48 verifier run 5, finding 1 (REQ-385): R22(a) opens with the retarget to this PR's base, not to main.
  r22=$(grep -F -- '- **R22 — rendering on stacked PRs.**' "$PL" || true)
  ck "the plan's R22(a): the stacked PR is retargeted to this PR's base, never --base main" \
    bash -c 'grep -qF "followed by the stacked PR'"'"'s retarget (\`gh pr edit <m> --base <this PR'"'"'s base>\`, \`main\` or the branch this PR is itself stacked on, before this branch is deleted)" <<<"$1" && ! grep -qF -- "--base main" <<<"$1"' _ "$r22"
  # PR #48 verifier run 5, low 9 (REQ-343): every task step of the executed plan is ticked, and the Verified against line
  # says the rulings' later anchors were re-verified at the IMPLEMENT branch head.
  ck "the plan: no task step is left unticked, and each of Tasks 1-16 has a ticked step" python3 - "$PL" <<'PYT'
import re, sys
t = open(sys.argv[1]).read()
assert not re.search(r"^- \[ \] \*\*Step", t, re.M), "an unticked step remains"
for n in range(1, 17):
    sec = re.search(r"^### Task %d:.*?(?=^### Task |^## |\Z)" % n, t, re.M | re.S)
    assert sec and re.search(r"^- \[x\] \*\*Step", sec.group(0), re.M), n
PYT
  ck "the plan's Verified against line: the rulings' later anchors re-verified at the IMPLEMENT branch head" \
    bash -c 'grep -F "**Verified against:**" "$1" | grep -qF "; the rulings'"'"' later anchors re-verified at the IMPLEMENT branch head"' _ "$PL"
  ck "the plan's Classifier additions no longer describe waivers only ('each \`MEMBER\` waiver author's role')" \
    bash -c '! grep -qF "each \`MEMBER\` waiver author'"'"'s role" <<<"$1"' _ "$ca"
fi

# P5 lows patch (PR #48 verifier runs 5-7; REQ-306, REQ-343, REQ-382, REQ-340): run 7 finding 3 — the plan's "what the
# user will see" keeps ADR-002 in instances (R11, factory-only.txt, the glossary); finding 5 — Task 4's and Task 9's
# Interfaces and Task 16's Files say what shipped; finding 4 — the Open -> P7 list says the PR template and init's next
# steps were aligned, so the article is the last rule text that says impl/plan-N-<name>.
# Covers: REQ-306
if [ -f "$PL" ]; then
  seen=$(grep -F -- '- *A fresh instance*' "$PL" || true)
  ck "the plan's 'what the user will see': an instance keeps ADR-002 (the disposition gate it runs), loses ADR-003" \
    bash -c 'grep -qF "keeps ADR-002, which defines the disposition gate every instance runs" <<<"$1" && grep -qF "ADR-003" <<<"$1" && ! grep -qF "ADR-002/003" <<<"$1"' _ "$seen"
  t4=$(awk '/^### Task 4:/{f=1} /^- \[[ x]\] \*\*Step 1/{f=0} f' "$PL" | tr '\n' ' ')
  ck "the plan's Task 4 Interfaces: markers take rule 1b's writing role too, never 'author association alone'" \
    bash -c 'grep -qF "a \`MEMBER\`'"'"'s or \`COLLABORATOR\`'"'"'s marker (\`APPROVE\` or \`REQUEST_CHANGES\`) needs the same writing role (rule 1b, R9 as shipped)" <<<"$1" && ! grep -qF "markers are judged by author association alone" <<<"$1"' _ "$t4"
  t9=$(awk '/^### Task 9:/{f=1} /^- \[[ x]\] \*\*Step 1/{f=0} f' "$PL" | tr '\n' ' ')
  ck "the plan's Task 9 Interfaces: R12's prefixes include phase/security and phase/release, as shipped" \
    grep -qF '`github.head_ref` starting with `impl/`, `phase/validate`, `phase/plan-`, `design/`, `build/`, `ship/`, `phase/security` or `phase/release`' <<<"$t9"
  ck "the plan's Task 16 Files: the synced REQ bodies include REQ-382's" \
    bash -c 'grep -F "**Files:**" <<<"$1" | grep -qF "the sync of REQ-311'"'"'s, REQ-340'"'"'s, REQ-382'"'"'s, REQ-385'"'"'s and REQ-393'"'"'s to what shipped"' _ "$t16"
  ck "the plan's Open -> P7: the PR template and init's next steps now say impl/plan-N-<plan slug>; the article is the last" \
    bash -c 'grep -F "**Open → P7:**" "$1" | grep -qF "the PR template'"'"'s Build-lane heading and init'"'"'s next steps say \`impl/plan-N-<plan slug>\` from the P5 lows patch (\`patch/p5-mediums\`) on, so the article is the last rule text that says \`impl/plan-N-<name>\`"' _ "$PL"
fi

# P5 lows patch (PR #48 verifier run 7, code finding 3; REQ-385): the plan's Deferred section records the stale-base note
# next.sh now prints and the signing-key detection residual (it errs toward asking).
# Covers: REQ-385
if [ -f "$PL" ]; then
  dfr=$(awk '/^## Deferred by design/{f=1} f' "$PL" | tr '\n' ' ')
  ck "the plan's Deferred: next.sh never fetches, and a differing baseRefOid prints a note and a why line" \
    grep -qF 'a base tip gh reports (`baseRefOid`) that differs from `origin/<base>` prints a note and a why line' <<<"$dfr"
  ck "the plan's Deferred: signing-key detection reads user.signingkey only, a residual that errs toward asking" \
    bash -c 'grep -qF "**Signing-key detection beyond \`user.signingkey\`**" <<<"$1" && grep -qF "errs toward asking" <<<"$1"' _ "$dfr"
fi

finish test_constitution_amendment_b
