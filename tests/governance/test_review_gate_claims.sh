#!/usr/bin/env bash
# REQ-314 (amendment A, H2): art-review-gate says what the gate is in each mode, honestly; review-gate.md maps every
# claim to the file that enforces it (and every such file exists); tdd.md stops promising a verifier check that
# does not exist.
# Covers: REQ-314, REQ-311, REQ-382, REQ-321, REQ-322, REQ-324
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
art=$(awk '/^slug: art-review-gate$/{f=1} f && /^---$/{exit} f' constitution.md)
for p in 'solo' 'APPROVE' 'recorded second review' 'tamper-evident' 'not an enforced control' 'one human approval' \
         'other than the author' 'waive' '20 characters' 'base' 'doc-only' 'admin'; do
  ck "art-review-gate says '$p'" grep -qi -- "$p" <<<"$art"
done
ck "constitution keeps twelve well-formed articles" bash tests/governance/test_constitution_articles.sh
R=.claude/rules/review-gate.md
# SEC-004 (high; dfe-9, dfe-10; REQ-313, REQ-385 as amended by the SEC-004 back-edge): the bootstrap is main's reviewed
# copy for every PR — a stacked PR's base is an unreviewed branch its author chose, so its script is never piped into bash.
# Covers: REQ-313
# Covers: REQ-385
ck "step 3 bootstraps the verifier from main's reviewed copy, by its full ref, for every PR (dfe-9; PR #54 verifier run 2, finding 3; SEC-004)" grep -qF 'git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>' "$R"
st3=$(awk '/^3\. /{f=1} /^4\. /{f=0} f' "$R" | tr '\n' ' ')
ck "step 3: stacked or not, main's copy; the stacked base supplies data only and is never executed (SEC-004)" \
  bash -c 'for w in "for every PR, stacked or not" "SEC-004" "never piped into bash" "read at \`refs/remotes/origin/<base>\`" "\`main\`'"'"'s"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$st3"
ck "review-gate.md never pipes a base branch's run-verifier.sh (SEC-004)" no grep -qE 'origin/<base>:scripts/run-verifier' "$R"
# SEC-004 review round 2, finding 2: step 3 says what the retarget does after each merge — a squash merge re-reviews,
# the merge commit /next prints keeps the marker (step 6) — never that merging first always re-reviews against main.
ck "step 3: after a squash merge the stacked PR is reviewed again; after the merge commit /next prints the marker survives (SEC-004 round 2)" \
  bash -c 'for w in "after a squash merge" "after the merge commit \`/next\` prints" "the marker survives (step 6)" "reviewed by the base PR before its merge"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "retargeting, reviews the stacked PR against \`main\`" <<<"$1"' _ "$st3"
ck "the isolation row: the self-comparison is with main's copy, and the code run is main's (SEC-004)" \
  bash -c 'l=$(grep -F "| Verifier isolation" "$1"); grep -qF "comparison of itself with \`main\`'"'"'s copy" <<<"$l" && grep -qF "\`attestation.py\` and \`config.py\` are \`main\`'"'"'s" <<<"$l"' _ "$R"
# SEC-021 (PR #62 review; PR #61 run 1 finding 1; REQ-313): the isolation row lists the base-read inputs that remain and
# says the findings scan's .gitleaks.toml is main's, never the unreviewed stacked base's.
# Covers: REQ-313
ck "the isolation row lists the base-read inputs that remain (policy, prompt, skill, constitution, deny-list additions) and says .gitleaks.toml is main's (SEC-021)" \
  bash -c 'l=$(grep -F "| Verifier isolation" "$1"); for w in "the base-read inputs that remain" "policy keys" "prompt template" "the skill" "the constitution" "deny-list additions" "\`.gitleaks.toml\` is \`main\`'"'"'s (SEC-021)"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ "$R"
ck "review-gate.md no longer says the check ignores the verdict" no grep -q 'does not parse the verdict' "$R"
ck "review-gate.md documents in-session attestation for team mode only" bash -c 'grep -q -- "--from-file" "$1" && grep -q -- "--print-prompt" "$1" && grep -q "solo: false" "$1"' _ "$R"
ck "review-gate.md gives the bound waiver grammar" grep -qF 'specflow-verifier:waive sha:<40-hex head> base:<40-hex base>' "$R"
ck "the claim→file table exists and every file in it exists (REQ-314)" python3 - "$R" <<'PY'
import os, re, sys
t = open(sys.argv[1]).read()
m = re.search(r"^## What enforces each claim\n(.*?)(?=^## |\Z)", t, re.S | re.M)
assert m, "no '## What enforces each claim' section"
rows = [l for l in m.group(1).splitlines() if l.startswith("|")][2:]
assert len(rows) >= 10, f"only {len(rows)} rows"
for r in rows:
    cells = [c.strip() for c in r.strip().strip("|").split("|")]
    assert len(cells) == 3, r
    paths = re.findall(r"`([^`]+)`", cells[2])
    assert paths or cells[1].lower().startswith("convention"), r
    for p in paths:
        assert os.path.exists(p), f"{p} does not exist (row: {cells[0]})"
PY
tbl=$(awk '/^## What enforces each claim/{f=1; next} /^## /{f=0} f' "$R")
for c in 'second review' 'waiver' 'base' 'isolat' 'test-first' 'any base' 'admin'; do ck "the table covers '$c'" grep -qi -- "$c" <<<"$tbl"; done

# Verifier findings on #32/#33 (REQ-314, REQ-395, REQ-382): amendment A covers stacking and says what is convention.
bas=$(awk '/^slug: art-branch-as-state$/{f=1} f && /^---$/{exit} f' constitution.md)
ck "art-branch-as-state: a phase transition is a PR that reaches main, directly or stacked (REQ-395)" \
  bash -c 'grep -q "reaches \`main\`" <<<"$1" && grep -qi "stacked" <<<"$1" && ! grep -q "is a PR to \`main\`\." <<<"$1"' _ "$bas"
ck "art-review-gate team mode needs the verifier's APPROVE (or a maintainer waiver) and one human approval" \
  grep -qF 'the verifier'"'"'s `APPROVE` (or a maintainer waiver) and one human approval' <<<"$(tr '\n' ' ' <<<"$art" | tr -s ' ')"
ck "art-review-gate states the Dependabot exemption" bash -c 'grep -qF "dependabot[bot]" <<<"$1" && grep -qi "no second review" <<<"$1"' _ "$art"
ck "art-review-gate says the waiver's PR-body link is convention, not checked" bash -c 'grep -qi "convention" <<<"$1" && grep -qi "not checked" <<<"$1"' _ "$art"
ck "step 2 allows a PR stacked on an open phase PR" grep -qiE '^2\..*stacked' <<<"$(awk '/^2\. /{f=1} /^3\. /{f=0} f' "$R" | tr '\n' ' ')"
# PR #48 verifier run 5, finding 1 (REQ-385, art-branch-as-state): step 6 retargets a stacked PR to the merged PR's own
# base, as pipeline.py renders it — never to main unconditionally (on a three-deep stack that would change the merge base).
# Covers: REQ-385
st6=$(awk '/^6\. /{f=1} /^This is the operational rule/{f=0} f' "$R" | tr '\n' ' ' | tr -s ' ')
ck "step 6 retargets a stacked PR to the merged PR's base (main, or the branch it was itself stacked on) before that base branch is deleted" \
  grep -qF 'A stacked PR must be retargeted to the merged PR'"'"'s base (`main`, or the branch it was itself stacked on) before that base branch is deleted.' <<<"$st6"
ck "step 6 no longer retargets every stacked PR to main" bash -c '! grep -qF "must be retargeted to \`main\` before its base branch is deleted" <<<"$1"' _ "$st6"
# PR #48 verifier run 5, finding 2 (REQ-382): the waiver row and the glossary's Waiver entry record the PR #50 measurement.
# Covers: REQ-382
pm='measured 2026-09-29 (PR #50): under the workflow'"'"'s `GITHUB_TOKEN` a member whose organisation membership is private reads as `COLLABORATOR`'
pm2='a `COLLABORATOR`'"'"'s waiver is refused (`waiver-not-maintainer`)'
ck "review-gate.md's waiver row records the private-membership measurement (PR #50)" \
  bash -c 'grep -F "| Waivers need a maintainer" "$1" | grep -qF "$2" && grep -F "| Waivers need a maintainer" "$1" | grep -qF "$3"' _ "$R" "$pm" "$pm2"
# Scoped re-review of wave 5, low (REQ-382): both name the command that makes the membership public.
pmc='`gh api -X PUT orgs/<org>/public_members/<login>`'
ck "review-gate.md's waiver row names the fix command (publicise the organisation membership)" \
  bash -c 'grep -F "| Waivers need a maintainer" "$1" | grep -qF "$2"' _ "$R" "$pmc"
ck "the glossary's Waiver entry names the fix command (publicise the organisation membership)" \
  bash -c 'awk "\$0==\"### Waiver\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " " | grep -qF "$1"' _ "$pmc"
ck "the glossary's Waiver entry records the private-membership measurement (PR #50)" \
  bash -c 'b=$(awk "\$0==\"### Waiver\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " "); grep -qF "$1" <<<"$b" && grep -qF "$2" <<<"$b"' _ "$pm" "$pm2"
row1=$(grep -F '| A verifier comment exists for the head' "$R" || true)
ck "table row 1: the job runs the base's classifier; the workflow file still comes from the PR (#33 high)" \
  bash -c 'grep -qF "verifier.yml" <<<"$1" && grep -qi "base" <<<"$1" && grep -qF "pull_request_target" <<<"$1" && grep -qi "gate code" <<<"$1"' _ "$row1"
ck "table: the waiver row marks the PR-body link as convention" grep -qF 'PR-body link: convention' <<<"$tbl"
ck "table: the solo self-waiver route is named, convention, tamper-evident only" \
  bash -c 'grep -qi "solo waiver" <<<"$1" && grep -qi "self-posted" <<<"$1" && grep -qi "tamper-evident only" <<<"$1"' _ "$tbl"
ck "table: personal repositories need an organisation or a second OWNER for team-mode waivers" \
  bash -c 'grep -qF "COLLABORATOR" <<<"$1" && grep -qi "organisation" <<<"$1" && grep -qi "second OWNER" <<<"$1"' _ "$tbl"
ck "table: the Dependabot exemption is a row" grep -qF 'dependabot[bot]' <<<"$tbl"
ck "patch tier: a human other than the author approves in team mode; solo's second review is the APPROVE" \
  bash -c 'grep -qi "in team mode a human other than the author approves" <<<"$1" && grep -qi "in solo mode the verifier.s APPROVE is the second review" <<<"$1" && ! grep -qi "human still approves" <<<"$1"' _ "$(awk '/^## Patch tier/{f=1} /^## Minor exception/{f=0} f' "$R" | tr '\n' ' ' | tr -s ' ')"
for f in README.md "$R" scripts/run-verifier.sh; do
  ck "$f never claims run-verifier.sh refuses to run as any other copy" no grep -qiE 'refuses to run as any copy|otherwise it refuses' "$f"
done
ck "run-verifier.sh's header calls its self-check a guard, not a control (bash -s bypasses it)" \
  bash -c 'h=$(sed -n "1,40p" scripts/run-verifier.sh); grep -qi "guard" <<<"$h" && grep -qi "not a control" <<<"$h" && grep -qF "bash -s" <<<"$h"'
ck "the table's isolation row calls the entry-point check a guard, not a control" grep -qi 'guard against running the checkout' <<<"$tbl"
# PR #33 bootstrap verifier findings (REQ-314, REQ-382): honest bootstrap wording, the minor exception defined,
# the marker records rather than binds, the waiver re-runs the check, stacked PRs and branch protection.
artf=$(tr '\n' ' ' <<<"$art" | tr -s ' ')
ck "art-review-gate defines the minor exception it keeps (doc finding 2)" \
  grep -qF 'Minor doc-only fixes (typos, formatting, broken links) may merge directly to `main` within the bounds in `.claude/rules/review-gate.md`.' <<<"$artf"
ck "art-review-gate: the marker records head and base SHAs, it does not bind them (doc finding 4)" \
  bash -c 'grep -qF "records head and base SHAs" <<<"$1" && ! grep -qF "binds head" <<<"$1"' _ "$artf"
ck "art-review-gate: in both modes the marker is tamper-evident, not bound to a model run (doc finding 1)" \
  bash -c 'grep -qiF "in both modes the marker is tamper-evident, not bound to a model run" <<<"$1" && grep -qi "hand-post" <<<"$1" && grep -qi "re-roll" <<<"$1"' _ "$artf"
ck "art-review-gate: in team mode the non-author human approval is the actual control" \
  grep -qiF 'in team mode the human approval from someone other than the author is the actual control' <<<"$artf"
ck "table row 1: the bootstrap path runs the PR head's own classifier, which is not a control" \
  bash -c 'grep -qF "PR head'"'"'s own classifier" <<<"$1" && grep -qi "not a control" <<<"$1" && grep -qi "honest PR" <<<"$1" && ! grep -qi "only route" <<<"$1"' _ "$row1"
step4=$(awk '/^4\. /{f=1} /^5\. /{f=0} f' "$R" | tr '\n' ' ' | tr -s ' ')
ck "step 4: after the waiver, re-run the verifier workflow (gh run rerun or an edited PR body) (doc finding 9)" \
  bash -c 'grep -qF "gh run rerun" <<<"$1" && grep -qF "edited" <<<"$1" && grep -qi "re-run the \`verifier\` workflow" <<<"$1"' _ "$step4"
gw=$(awk '/^### Waiver$/{f=1; next} /^### /{f=0} f' docs/GLOSSARY.md | tr '\n' ' ' | tr -s ' ')
ck "GLOSSARY Waiver: posting it does not re-run the check; re-run the verifier workflow" \
  bash -c 'grep -qF "gh run rerun" <<<"$1" && grep -qF "edited" <<<"$1"' _ "$gw"
# P7 Build 1 fix wave 1, FIX 9 (REQ-382): a classifier from before P7 rejects the bound grammar as malformed, and a PR is
# judged by its base's classifier — so this build's own PR (judged by main's) and an instance's first upgrade PR after
# v3.2.0 must carry the legacy form. Step 4 and the glossary's Waiver entry both say so.
# Covers: REQ-382
for w in "On a PR whose base's classifier predates P7" "rejects the bound form as \`malformed\`" "post the legacy \`sha:<head>\` form" "an instance's first upgrade PR after v3.2.0" "accepted once the base carries this classifier"; do
  ck "step 4 says when to post the legacy waiver: '$w'" grep -qF -- "$w" <<<"$step4"
  ck "GLOSSARY Waiver says when to post the legacy waiver: '$w'" grep -qF -- "$w" <<<"$gw"
done
step2=$(awk '/^2\. /{f=1} /^3\. /{f=0} f' "$R" | tr '\n' ' ' | tr -s ' ')
ck "step 2: configure-repo.sh protects only main; a stacked PR merges with no required checks; the final PR covers the combined diff" \
  bash -c 'grep -qF "configure-repo.sh" <<<"$1" && grep -qi "only \`main\`" <<<"$1" && grep -qi "no required checks" <<<"$1" && grep -qi "combined diff" <<<"$1"' _ "$step2"
ck "README: fork PRs are unsupported by run-verifier.sh" grep -qiE 'fork PRs are (not supported|unsupported)' README.md
# PR #33 third bootstrap findings (REQ-311, REQ-312, REQ-314, REQ-382): the Dependabot exemption needs Dependabot-only
# commits; "other than the author" covers commit authors and the last pusher; a waiver's limits; solo self-waiver;
# stacked PRs' base; the bootstrap path's isolation; the glossary points at the full rule set.
# Amendment B (REQ-343): P4 shipped the committer/verified check and the dependency-only diff rule (REQ-334), so the
# article states them instead of deferring them to P4.
ck "art-review-gate: Dependabot is exempt only when every commit is Dependabot's, GitHub-verified and committed by dependabot[bot] or web-flow" \
  grep -qF 'only when every commit is authored by `dependabot[bot]`, verified by GitHub, and committed by `dependabot[bot]` or `web-flow`' <<<"$artf"
ck "art-review-gate: the exemption is limited to dependency-only diffs (REQ-334), no longer deferred to P4" \
  bash -c 'grep -qF "only moves the versions of dependencies the base already lists" <<<"$1" && grep -qF "(REQ-334)" <<<"$1" && ! grep -qF "deferred to P4" <<<"$1"' _ "$artf"
ck "art-review-gate: a team-mode waiver comes from neither the PR author nor an author of its commits" \
  grep -qF 'from someone who is neither the PR author nor an author of any of its commits' <<<"$artf"
ck "art-review-gate: the team-mode approval comes from someone other than the last pusher" \
  grep -qF 'other than the last pusher (`require_last_push_approval`)' <<<"$artf"
ck "art-review-gate: in solo mode the author may self-waive, and the second review is then absent" \
  grep -qF 'In solo mode the author may instead self-waive; the second review is then absent, recorded only by the waiver'"'"'s rationale.' <<<"$artf"
tblf=$(tr '\n' ' ' <<<"$tbl" | tr -s ' ')
dep=$(grep -F 'dependabot[bot]' <<<"$tbl" || true)
ck "table: the Dependabot row requires every commit to be authored by dependabot[bot], verified, and committed by dependabot[bot] or web-flow" \
  bash -c 'grep -qi "authored by \`dependabot\[bot\]\`" <<<"$1" && grep -qi "verified" <<<"$1" && grep -qF "web-flow" <<<"$1"' _ "$dep"
# P4 (REQ-334, dfe-13): the row states the rule as shipped — verified commits, a dependency-only, version-only
# diff, .github/ always reviewed, fail closed — not the pre-P4 forgeable-author-mapping residual.
ck "table: the Dependabot row states the dependency-only, version-only diff restriction and .github/ (REQ-334, dfe-13)" \
  bash -c 'grep -qi "dependency" <<<"$1" && grep -qi "version" <<<"$1" && grep -qF ".github/" <<<"$1"' _ "$dep"
ck "table: the Dependabot row claims commit verification, as shipped" grep -qi 'verified' <<<"$dep"
wrow=$(grep -F '| Waivers need a maintainer' "$R" || true)
ck "table: the waiver row excludes commit authors and names require_last_push_approval" \
  bash -c 'grep -qF "neither the PR author nor an author of any of its commits" <<<"$1" && grep -qF "require_last_push_approval" <<<"$1"' _ "$wrow"
# #33 fourth run finding 4: MEMBER is any organisation member, not a repository role.
ck "table: the waiver row says MEMBER is any organisation member, the maintainers included, and needs the admin, maintain or write role (R9)" \
  bash -c 'grep -qF "any organisation member" <<<"$1" && grep -qi "read-only" <<<"$1" && grep -qF "admin, maintain or write" <<<"$1" && grep -qF "the maintainers themselves are \`MEMBER\`" <<<"$1"' _ "$wrow"
# #33 fourth run finding 2: enforce_admins: false lets an admin skip the required review too.
harow=$(grep -F '| Human approval in team mode' "$R" || true)
ck "table: the team-approval row says enforce_admins: false lets an admin skip the required approving review too" \
  bash -c 'grep -qF "enforce_admins: false" <<<"$1" && grep -qF "required approving review" <<<"$1" && grep -qi "red checks" <<<"$1"' _ "$harow"
stk='(for a PR to `main`; on a stacked PR the base is itself unreviewed)'
ck "table row 1: the base's classifier is a control only for a PR to main" grep -qF "$stk" <<<"$row1"
prow=$(grep -F '| Policy keys' "$R" || true)
ck "table: the policy-keys row says the same for stacked PRs and the bootstrap path" \
  bash -c 'grep -qF "$2" <<<"$1" && grep -qi "bootstrap" <<<"$1"' _ "$prow" "$stk"
irow=$(grep -F '| Verifier isolation' "$R" || true)
ck "table: the isolation row says --bootstrap gives the model the head's skill and constitution; its markers are never accepted" \
  bash -c 'grep -qF "Under \`--bootstrap\` the model is given the PR head'"'"'s own skill and constitution" <<<"$1" && grep -qF "bootstrap markers are never accepted" <<<"$1"' _ "$irow"
ck "step 4: a waiver does not override a blocking comment, which must be deleted" \
  bash -c 'grep -qF "A waiver does not override a blocking comment" <<<"$1" && grep -qF "must be deleted" <<<"$1"' _ "$step4"
ck "step 4: a waiver wins only while it is the newest accepted comment" \
  bash -c 'grep -qF "only while it is the newest accepted comment" <<<"$1" && grep -qF "supersedes it" <<<"$1"' _ "$step4"
ck "step 4: a team-mode waiver comes from neither the PR author nor a commit author" grep -qF 'neither the PR author nor an author of any of its commits' <<<"$step4"
ck "GLOSSARY Waiver: does not override a blocking comment; wins only while newest" \
  bash -c 'grep -qF "does not override a blocking comment" <<<"$1" && grep -qF "only while it is the newest accepted comment" <<<"$1" && grep -qF "neither the PR author nor an author of any of its commits" <<<"$1"' _ "$gw"
gam=$(awk '/^### Attestation marker$/{f=1; next} /^### /{f=0} f' docs/GLOSSARY.md | tr '\n' ' ' | tr -s ' ')
ck "GLOSSARY Attestation marker: points at attestation.py and the claim table as the full rule set, no partial restatement" \
  bash -c 'grep -qF "full rule set" <<<"$1" && grep -qF "scripts/lib/specflow/attestation.py" <<<"$1" && grep -qF ".claude/rules/review-gate.md" <<<"$1" && ! grep -qF "from an OWNER, MEMBER or COLLABORATOR" <<<"$1"' _ "$gam"
gdb=$(awk '/^### Dependabot exemption$/{f=1; next} /^### /{f=0} f' docs/GLOSSARY.md | tr '\n' ' ' | tr -s ' ')
# P4 (REQ-334, dfe-13): the entry states the rule as shipped, not the pre-P4 forgeable-author-mapping residual.
ck "GLOSSARY Dependabot exemption: every commit verified, committed by dependabot[bot] or web-flow (REQ-334, dfe-13)" \
  bash -c 'grep -qF "every commit" <<<"$1" && grep -qi "verified" <<<"$1" && grep -qF "web-flow" <<<"$1"' _ "$gdb"
ck "GLOSSARY Dependabot exemption: claims commit verification, as shipped" grep -qi 'verified' <<<"$gdb"
# #33 fourth run finding 8: a waiver has three uses, not one.
ck "GLOSSARY Waiver: covers REQUEST_CHANGES, a bootstrap PR with no acceptable marker, and a gitleaks false positive" \
  bash -c 'grep -qF "REQUEST_CHANGES" <<<"$1" && grep -qi "bootstrap" <<<"$1" && grep -qi "no acceptable marker" <<<"$1" && grep -qF "gitleaks" <<<"$1" && grep -qi "false positive" <<<"$1"' _ "$gw"
ck "GLOSSARY Waiver: MEMBER means any organisation member" grep -qF 'any organisation member' <<<"$gw"
# #33 fourth run finding 10: instruction Markdown that instances load as session instructions is code too.
gcm=$(awk '/^### Code mode$/{f=1; next} /^### /{f=0} f' docs/GLOSSARY.md | tr '\n' ' ' | tr -s ' ')
ck "GLOSSARY Code mode: names root CLAUDE.md, stacks' CLAUDE.md/overlay/skeleton Markdown and templates/ Markdown" \
  bash -c 'grep -qF "CLAUDE.md" <<<"$1" && grep -qF "stacks/" <<<"$1" && grep -qF "overlay/" <<<"$1" && grep -qF "skeleton/" <<<"$1" && grep -qF "templates/" <<<"$1"' _ "$gcm"
T=.claude/rules/tdd.md
ck "tdd.md drops the false 'verifier flags' promise (H2)" no grep -qi 'verifier flags' "$T"
ck "tdd.md points at REQ-321's checker" bash -c 'grep -qF "scripts/check-test-first.sh" "$1" && grep -q "REQ-321" "$1"' _ "$T"
ck "tdd.md says the checker is live, run by CI, not a later plan" \
  bash -c 'grep -qF "scripts/check-test-first.sh" "$1" && grep -qF "ci.yml" "$1" && ! grep -qiE "later v3\.2 plan|not yet mechanically checked" "$1"' _ "$T"
# (PR #34 third-run high: these checks sat after finish and could never fail; finish is now last.)
# PR #34 second-run finding 3: model-instruction Markdown is gate code (REQ-310), so the minor doc-only exception
# may not touch it — it needs a PR and a verifier run.
minor=$(awk '/^## Minor exception/{f=1; next} /^## /{f=0} f' "$R" | tr '\n' ' ' | tr -s ' ')
for t in 'any `CLAUDE.md`' '`CLAUDE.local.md`' 'any depth' '`stacks/<stack>/overlay/**`' '`stacks/<stack>/skeleton/**`' '`templates/**/*.md`' 'REQ-310'; do
  ck "minor exception excludes $t" grep -qF -- "$t" <<<"$minor"
done
# P4 (REQ-334, dfe-13) and amendment B (REQ-343): the wording states the shipped verified-commit rule, fails closed on any
# mismatch, and says art-review-gate states the same rule — no overclaim is left to track.
# Covers: REQ-343
DEPFAIL='fails? closed'
DEPCON='`art-review-gate` states this rule and its forgeable-author residual (amendment B, REQ-343)'
for pair in "GLOSSARY:$gdb" "table row:$dep"; do
  where=${pair%%:*}; txt=${pair#*:}; txt=$(tr '\n' ' ' <<<"$txt" | tr -s ' ')
  ck "$where Dependabot: any failure — unverified, a foreign committer, .github/, or a non-version edit — fails closed" grep -qiE "$DEPFAIL" <<<"$txt"
  ck "$where Dependabot: art-review-gate states the same rule (amendment B), no tracked overclaim" \
    bash -c 'grep -qF "$1" <<<"$2" && ! grep -qF "overclaims" <<<"$2"' _ "$DEPCON" "$txt"
done
ck "GLOSSARY Dependabot: no longer says flatly 'A commit by anyone else'" no grep -qF 'A commit by anyone else,' <<<"$gdb"
# P4 final review (PR #34 verifier high 1 reintroduced): GitHub gives every commit made through its API or UI
# committer web-flow and verified=true, with a caller-chosen author, so the verified/web-flow check does not tie
# a commit to Dependabot. Every statement of the rule says so, names the content rule as the real limit, records
# the measured committer, and never calls the committer identity unforgeable.
TM=docs/architecture/2026-09-25-factory-v3-2-threat-model.md
dfe13=""   # the threat model ships only in the template source (P5 R11)
TMPAIR=""
if [ -f "$TM" ]; then dfe13=$(grep -F '| dfe-13 |' "$TM" || true); TMPAIR="threat model dfe-13:$dfe13"; fi
DEPGAP='does not tie a commit to Dependabot'
DEPWHY='anyone with write access can create such a commit through the GitHub API'
DEPLIMIT='the real limit is the content rule'
for pair in "GLOSSARY:$gdb" "table row:$dep" ${TMPAIR:+"$TMPAIR"}; do
  where=${pair%%:*}; txt=${pair#*:}; txt=$(tr '\n' ' ' <<<"$txt" | tr -s ' ')
  ck "$where Dependabot: the verified/web-flow check $DEPGAP" grep -qiF "$DEPGAP" <<<"$txt"
  ck "$where Dependabot: $DEPWHY" grep -qiF "$DEPWHY" <<<"$txt"
  ck "$where Dependabot: $DEPLIMIT" grep -qiF "$DEPLIMIT" <<<"$txt"
  ck "$where Dependabot: never calls the committer identity unforgeable" no grep -qiE 'not forgeable|unforgeable|forgeable that way' <<<"$txt"
done
# #36 high (REQ-334, dfe-13): the npm lockfile rule fails closed and binds each resolved URL to its entry's own
# package, and a new lockfile is refused, so every statement of the residual names exactly what is left: moving an
# existing dependency to another registry version of the same package — not any registry tarball.
DEPRES='another registry version of the same package'
for pair in "GLOSSARY:$gdb" "table row:$dep" ${TMPAIR:+"$TMPAIR"}; do
  where=${pair%%:*}; txt=${pair#*:}; txt=$(tr '\n' ' ' <<<"$txt" | tr -s ' ')
  ck "$where Dependabot: the residual is '$DEPRES'" grep -qiF "$DEPRES" <<<"$txt"
  ck "$where Dependabot: a lockfileVersion 1 npm lockfile is refused" grep -qiF 'lockfileVersion 1' <<<"$txt"
  ck "$where Dependabot: a resolved URL must be the entry's own package's registry tarball" grep -qiF "own package" <<<"$txt"
  ck "$where Dependabot: a new lockfile is refused" grep -qiF 'new lockfile' <<<"$txt"
done
# PR #36 second run, high (REQ-334, dfe-13): the content rules compare base and head both ways, so every statement of
# the rule says what is now refused — a line the head removes (a pip option, a source sub-key), a hash changed at an
# unchanged version — and the residual stays on the same source.
for pair in "GLOSSARY:$gdb" "table row:$dep" ${TMPAIR:+"$TMPAIR"} "attestation.py:$(cat scripts/lib/specflow/attestation.py)"; do
  where=${pair%%:*}; txt=${pair#*:}; txt=$(tr '\n' ' ' <<<"$txt" | tr -s ' ')
  for w in 'both ways' 'a line the head removes' 'only for a dependency whose version changed' 'on the same source' \
           '--index-url' 'hosted:'; do
    ck "$where Dependabot: states the both-ways rule: '$w'" grep -qiF -- "$w" <<<"$txt"
  done
done
ck "attestation.py's module docstring states the same residual" grep -qF "$DEPRES" scripts/lib/specflow/attestation.py
[ -f "$TM" ] && ck "threat model dfe-13: the forged API commit is a recorded residual" grep -qiF 'residual' <<<"$dfe13"
ck "GLOSSARY Dependabot: records the measured committer of real Dependabot commits (web-flow)" grep -qF 'measured' <<<"$gdb"
ck "attestation.py never calls the committer identity unforgeable" \
  no grep -qiE 'not forgeable|unforgeable|forgeable that way|GitHub.s verified committer is not' scripts/lib/specflow/attestation.py
# P6 Task 1.6 (REQ-383, REQ-324; P6 R3): the review-gate rows state the SSH previous-tag clause.
# Covers: REQ-383
ck "review-gate.md's verify-release.sh row and RELEASE exit gate: an SSH signature is checked against allowed_signers at the anchor (P6 R3)" \
  bash -c 'for p in "| At PR time, a ship PR" "RELEASE exit gate"; do grep -F "$p" "$1" | grep -qF "an SSH signature is checked against \`.github/allowed_signers\` as of the newest earlier SSH-signed release tag, itself verified back to trust on first use (\`signers.py\`, P6 R3)" || exit 1; done; ! grep -qF "a WARN until P6 (REQ-350, REQ-383)" "$1" && ! grep -qF "as of the previous signed tag" "$1"' _ "$R"
# Build 1 final review (REQ-383, REQ-324; art-review-gate): the verify-release.sh row and the RELEASE exit gate list every
# FAIL kind check_previous_tag gives, name signers.verify (git verify-tag against the anchor's allowed_signers, never the
# local file) for an SSH signature, and the row names signers.py, which CI runs from the PR head, in its Files column.
r83=$(grep -F "| At PR time, a ship PR" "$R" || true); rxg=$(grep -F "RELEASE exit gate" "$R" || true)
for p in r83 rxg; do
  ck "review-gate.md ($p): the previous-tag FAIL kinds are listed in full; no 'only an unsigned tag … FAILs'" \
    bash -c 'for w in lightweight unlisted tagger-mismatch revoked revocation-unreadable revocation-malformed anchor-off-main anchor-unverified shallow git-error "git verify-tag"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "only an unsigned tag without the recorded fallback, or a BAD signature, FAILs" <<<"$1"' _ "${!p}"
done
ck "review-gate.md: the verify-release.sh row names signers.py in its Files column and says CI runs the head's copy" \
  bash -c 'grep -qE "\`scripts/lib/specflow/signers.py\` \|[[:space:]]*$" <<<"$1" && grep -qF "the PR head'"'"'s own \`signers.py\`" <<<"$1"' _ "$r83"
# PR #42 third verifier run, high 1 (REQ-321, REQ-310): every script a claim row relies on (its Files column under
# scripts/), and every other gate script CI runs from the PR head, is on code mode's gate-code list, so "code mode
# names that edit as gate code" is true of each.
gcl=$(grep -F 'as a gate-code change a human must read' .claude/skills/verifier/SKILL.md || true)
ck "SKILL.md code mode has a gate-code list" test -n "$gcl"
claim_scripts=$(grep '^|' <<<"$tbl" | sed 's/.*|\(.*\)|[[:space:]]*$/\1/' | grep -oE '`scripts/[^`]+`' | tr -d '`' | sort -u)
ck "the claim table names scripts under scripts/" test -n "$claim_scripts"
for f in $claim_scripts scripts/check-test-first.sh scripts/lib/specflow/packinfo.py scripts/lib/specflow/disposition_gate.py \
  scripts/lib/specflow/signers.py scripts/lib/specflow/release_manifest.py scripts/release-template.sh \
  'scripts/release-<stack>.sh' scripts/release-stack.sh.template \
  scripts/lib/specflow/blocks.py scripts/lib/specflow/cvss4.py scripts/lib/specflow/frontmatter.py \
  scripts/lib/specflow/config.py scripts/lib/specflow/architecture.py scripts/check-covers.sh \
  scripts/lib/specflow/coverage.sh scripts/check-architecture.sh scripts/check-traceability.sh \
  'stacks/<stack>/gates.sh' stacks/flutter/lcov-threshold.sh scripts/lcov-threshold.sh \
  pytest.ini tox.ini setup.cfg pyproject.toml conftest.py vitest.config.ts; do
  ck "SKILL.md code mode names $f as gate code a human must read" grep -qF "\`$f\`" <<<"$gcl"
done
# PR #42 fourth verifier run, doc medium 2 / code medium 3 (REQ-325, REQ-310): the stack hooks run scripts and read
# configs from the PR head (flutter's gates.sh runs lcov-threshold.sh; pytest and vitest read their configs), pinned
# above; the python floor isolates pytest's configuration, and the one residual (a conftest.py monkeypatching coverage
# internals) is stated in the coverage claim row and the threat model's residuals.
CONFTEST_RES='a `conftest.py` is arbitrary code and can still monkeypatch pytest-cov or coverage internals; code mode reads pytest configuration and `conftest.py` edits'
covrow=$(grep -F '| The coverage floor' "$R" || true)
ck "review-gate.md has a coverage-floor claim row naming coverage.sh" grep -qF '`scripts/lib/specflow/coverage.sh`' <<<"$covrow"
ck "the coverage-floor row: pytest runs with the gate's own -c ini (never addopts) and -p no:cacheprovider" \
  bash -c 'grep -qF -- "-c <temp ini>" <<<"$1" && grep -qF "never \`addopts\`" <<<"$1" && grep -qF -- "-p no:cacheprovider" <<<"$1"' _ "$covrow"
CPAIRS=("coverage row:$covrow")
[ -f "$TM" ] && CPAIRS+=("threat model:$(tr '\n' ' ' < "$TM")")
for pair in "${CPAIRS[@]}"; do
  ck "${pair%%:*} states the conftest.py residual" grep -qF -- "$CONFTEST_RES" <<<"${pair#*:}"
done
# PR #42 third and fourth verifier runs (REQ-324, REQ-322): P3 R19/R20's interim readings carried a deadline; amendment B
# (REQ-343) landed with P5's PLAN PR, so the deadline and its lapse rule leave every document a session reads and stay
# only in the history (the spec's P3 amended: entry and the P3 plan, both fenced out of instances by P5 R11).
AMB_DL='amendment B (REQ-343) lands with P5'"'"'s PLAN PR, no later than 2026-10-31'
for f in "$R" docs/security/RUBRIC.md .claude/skills/verifier/SKILL.md .github/PULL_REQUEST_TEMPLATE.md \
         schemas/security-disposition-template.md docs/GLOSSARY.md; do
  ft=$(tr '\n' ' ' < "$f" | tr -s ' ')
  ck "$f no longer carries amendment B's deadline or its lapse rule" \
    bash -c '! grep -qF "$1" <<<"$2" && ! grep -qF "2026-10-31" <<<"$2" && ! grep -qF "lapsed, unextended date" <<<"$2"' _ "$AMB_DL" "$ft"
done
for f in docs/specs/2026-09-25-factory-v3-2-design.md docs/plans/2026-09-27-factory-v3-2-p3-plan.md; do
  [ -f "$f" ] || continue
  ck "$f keeps amendment B's deadline as history" grep -qF "no later than 2026-10-31" "$f"
done
# PR #42 third verifier run, code medium/lows (REQ-321, REQ-322): the test-first disclosure says a rule stays satisfied
# for every later commit once any matching test gained a line, and the residuals name merge commits and pushed tags.
TF_STICKY="a rule is satisfied for every later commit once any matching test gained a line; the per-change pairing is code mode's second pass"
tfrow=$(grep -F '| Test-first per commit |' "$R" || true)
tdd=$(tr '\n' ' ' < .claude/rules/tdd.md | tr -s ' ')
for pair in "Test-first row:$tfrow" "tdd.md:$tdd"; do
  where=${pair%%:*}; txt=${pair#*:}
  ck "$where: $TF_STICKY" grep -qF -- "$TF_STICKY" <<<"$txt"
  ck "$where: rev-list --no-merges skips conflict resolutions made in merge commits" \
    bash -c 'grep -qF "rev-list --no-merges" <<<"$1" && grep -qF "conflict resolutions made in merge commits" <<<"$1"' _ "$txt"
done
drow=$(grep -F '| At PR time, a PR that changes a security document' "$R" || true)
ck "disposition row: a pushed v<version> tag makes disposition_gate skip that version's current review/disposition as released" \
  bash -c 'grep -qF "a pushed \`v<version>\` tag makes \`disposition_gate\` skip that version" <<<"$1" && grep -qF "enforce_admins: false" <<<"$1"' _ "$drow"
# PR #42 fourth verifier run, doc lows 6, 7, 9 (REQ-321, REQ-310): the plan says which REQs it cites as context, not
# claims; R15 and the spec's P3 amended: entry record base-ref policy, instance detection and the template-pack bootstrap;
# SKILL.md step 7 cites art-release-readiness for "tag missing".
P3P=docs/plans/2026-09-27-factory-v3-2-p3-plan.md
if [ -f "$P3P" ]; then   # an instance may delete the factory plan
  pc=$(awk '/^\*\*Partial claims:\*\*/{f=1; next} /^## /{f=0} f' "$P3P")
  ck "the P3 plan's Partial claims: REQ-380, 327, 343, 388, 360 and 310 are cited as context, not claims" \
    bash -c 'grep -qF "cited as context, not claims" <<<"$1" && for r in 380 327 343 388 360 310; do grep -qF "REQ-$r" <<<"$1" || exit 1; done' _ "$pc"
  # PR #42 fifth verifier run, finding 3 (REQ-389): R4's grandfathering is keyed on inherited slugs, not a date cutoff,
  # so the plan's test snippets name the slug rule.
  ck "the P3 plan's test snippets use the slug rule, not the retired 2026-09-27 cutoff" \
    bash -c '! grep -qF "created after the 2026-09-27 cutoff is not grandfathered" "$1" && ! grep -qF "after-cutoff cases" "$1" && grep -qF "a spec whose slug is not in the inherited list is not grandfathered" "$1"' _ "$P3P"
  r15=$(grep '^- \*\*R15 ' "$P3P" || true)
  ck "plan R15 has an As implemented note: policy and instance detection at the base ref, the template-pack bootstrap" \
    bash -c 'grep -qF "**As implemented**" <<<"$1" && grep -qF "at the base ref" <<<"$1" && grep -qF "scripts/template-pack.yml" <<<"$1" && grep -qF "bootstrap" <<<"$1"' _ "$r15"
fi
if [ -f docs/specs/2026-09-25-factory-v3-2-design.md ]; then
  p3a=$(grep -F 'P3 IMPLEMENT PR' docs/specs/2026-09-25-factory-v3-2-design.md || true)
  ck "the spec's P3 amended: entry records R15's base-ref policy, instance detection and bootstrap" \
    bash -c 'grep -qF "read at the base ref" <<<"$1" && grep -qF "whether the tree is an instance" <<<"$1" && grep -qF "judged by its own copy (bootstrap)" <<<"$1"' _ "$p3a"
  # PR #42 fifth verifier run, finding 2 (REQ-322): the P3 entry records R9 as implemented — severity is the base
  # score, so a finding's cvss_vector is the 11 base metrics only and any other metric is a parser error.
  ck "the spec's P3 amended: entry records R9's base-metrics-only rule (Threat, Environmental or Supplemental metric = parser error)" \
    bash -c 'grep -qF "the 11 base metrics only" <<<"$1" && grep -qF "any Threat, Environmental or Supplemental metric is a parser error" <<<"$1" && grep -qF "severity is the base score" <<<"$1"' _ "$p3a"
fi
s7=$(grep -E '^7\. ' .claude/skills/verifier/SKILL.md || true)
ck "SKILL.md step 7 attributes 'tag missing' to art-release-readiness, not art-review-gate" \
  bash -c 'grep -qF "\`art-release-readiness\`'"'"'s RELEASE exit gate" <<<"$1" && ! grep -qF "\`art-review-gate\`'"'"'s RELEASE exit gate" <<<"$1"' _ "$s7"
# P5 final review (REQ-385, REQ-341, art-review-gate): /next's guarantees are claims with rows; its derivation reads
# branch names, PRs and the tree; a retargeted PR keeps its marker only while its merge base is unchanged; a marker
# from a MEMBER or COLLABORATOR needs a writing role; sec- slugs are reserved for the back-edge.
for c in 'never runs the verifier' 'merge command' 'Other users' ; do ck "the table has a /next row: '$c'" bash -c 'grep -F "/next" <<<"$1" | grep -qiF -- "$2"' _ "$tbl" "$c"; done
nrows=$(grep -F '/next' <<<"$tbl" || true)
ck "the /next rows name the shipped files and the checkout-copy residual" \
  bash -c 'for s in scripts/lib/specflow/pipeline.py scripts/lib/specflow/state.py .claude/commands/next.md tests/governance/test_next_prs.sh tests/governance/test_next_render.sh tests/governance/test_state_kernel.sh; do grep -qF -- "\`$s\`" <<<"$1" || exit 1; done; grep -qi "checkout" <<<"$1" && grep -qF -- "--match-head-commit" <<<"$1" && grep -qF "MergeOnlyWhenApproved" <<<"$1" && grep -qF "OtherUsersPrsNeverBlock" <<<"$1"' _ "$nrows"
pb=$(awk '/^## Paths and branch names/{f=1; next} /^## /{f=0} f' "$R" | tr '\n' ' ' | tr -s ' ')
ck "paths: /next derives state from the branch name, its PRs (open, merged or closed) and the tree — not 'branch names alone'" \
  bash -c 'grep -qF "from the branch name, its PRs (open, merged or closed) and the tree" <<<"$1" && ! grep -qF "branch names alone" <<<"$1"' _ "$pb"
ck "paths: a slug may not start with sec- (build/sec-<id> is the back-edge's name)" grep -qF 'may not start with `sec-`' <<<"$pb"
step6=$(awk '/^6\. /{f=1} /^This is the operational rule/{f=0} f' "$R" | tr '\n' ' ' | tr -s ' ')
ck "step 6: a retargeted PR keeps its marker only while its merge base is unchanged; otherwise the verifier runs again" \
  bash -c 'grep -qF "base-mismatch" <<<"$1" && grep -qi "merge base" <<<"$1" && grep -qi "verifier again" <<<"$1" && ! grep -qF "so both checks re-run against the new base)" <<<"$1"' _ "$step6"
wrow2=$(grep -F '| Waivers need a maintainer' "$R" || true)
ck "waiver row: markers from a MEMBER or COLLABORATOR need a writing role too; no 'judged by author association alone'" \
  bash -c 'grep -qF "marker-not-writer" <<<"$1" && ! grep -qF "judged by author association alone" <<<"$1"' _ "$wrow2"
# PR #48 verifier run 4, code low (REQ-382): `attestation.py check --permissions` is a test-only injection of roles; the
# waiver row says so and names any workflow that passes it as gate code. test_attestation.sh asserts verifier.yml (and
# every workflow) never passes it.
ck "waiver row: --permissions is a test-only injection of roles; verifier.yml never passes it; a workflow that does is gate code" \
  grep -qF '`--permissions` is a test-only injection of roles; `verifier.yml` never passes it and any workflow that does is gate code' <<<"$wrow2"
# Run 7 finding 6 (REQ-385, REQ-395): step 6 — the marker survives the retarget, but the update-branch strict protection
# requires creates a new head, which needs a fresh verifier run or a waiver (PR #48: 40049ad -> ab16c32).
# Covers: REQ-385
# P7 R4 (REQ-382): a waiver binds a base as markers do; a legacy waiver stands only until a retarget after it.
# Covers: REQ-382
ck "waiver row: a bound waiver is judged by the marker's base rule; a legacy one is refused after a later retarget (P7 R4)" \
  bash -c 'for w in "waiver-base-mismatch" "waiver-unbound-retargeted" "waiver-timeline-unknown" "\`base_ref_changed\`"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "proposed for P7/amendment C" <<<"$1"' _ "$wrow2"
ck "glossary Waiver: the bound grammar, the base rule, the legacy timeline rule; no P7/amendment C proposal" \
  bash -c 'b=$(awk "\$0==\"### Waiver\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " "); grep -qF "base:<40-hex base>" <<<"$b" && grep -qF "waiver-unbound-retargeted" <<<"$b" && ! grep -qF "P7/amendment C" <<<"$b"'
ck "review-gate.md step 4 and the glossary's Waiver: a merged PR's refused legacy waiver is cleared by a bound waiver naming the merge's first parent (P7 R4)" \
  bash -c 's=$(awk "/^4\\. If \`REQUEST_CHANGES\`/{f=1} /^5\\. /{f=0} f" "$1" | tr "\n" " "); b=$(awk "\$0==\"### Waiver\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " "); for x in "$s" "$b"; do grep -qF "first parent" <<<"$x" && grep -qF "waiver-unbound-retargeted" <<<"$x" || exit 1; done' _ "$R"
ck "review-gate.md step 6: a retarget refuses a legacy waiver posted before it and a bound waiver naming another merge base; post a bound one after (P7 R4)" \
  bash -c 's=$(awk "/^6\\. After merge/{f=1} /^This is the operational rule/{f=0} f" "$1" | tr "\n" " " | tr -s " "); for w in "waiver-base-mismatch" "waiver-unbound-retargeted" "post a bound waiver naming the new base after retargeting"; do grep -qF -- "$w" <<<"$s" || exit 1; done' _ "$R"
# P7 Build 1 final review (findings 2, 7; REQ-382): the legacy waiver's timeline rule counts GitHub's automatic retarget
# (automatic_base_change_succeeded) and a base rewrite's base_ref_force_pushed, not base_ref_changed alone, and the row
# names what stays: a base rewritten with no timeline event leaves a legacy waiver standing.
# Covers: REQ-382
ck "waiver row, step 6 and the glossary: the timeline rule counts every base event, GitHub's automatic retarget included; the row names a base rewrite with no event as the residual" \
  bash -c 's=$(awk "/^6\\. After merge/{f=1} /^This is the operational rule/{f=0} f" "$1" | tr "\n" " " | tr -s " "); b=$(awk "\$0==\"### Waiver\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " "); for x in "$2" "$s" "$b"; do grep -qF "\`automatic_base_change_succeeded\`" <<<"$x" && grep -qF "\`base_ref_force_pushed\`" <<<"$x" || exit 1; done; grep -qF "a base rewritten with no timeline event" <<<"$2"' _ "$R" "$wrow2"
# PR #65 verifier run 1, finding 7 (REQ-382): the glossary's legacy-waiver sentence names the same timeline events and the
# same fail-closed reasons as review-gate.md's waiver row — the two lists are compared, not each pinned alone.
# Covers: REQ-382
ck "GLOSSARY Waiver and review-gate.md's waiver row: the legacy timeline rule names the same events and the same fail-closed reasons (PR #65 run 1 finding 7)" python3 - "$R" <<'PY2'
import re, sys
def legacy(text, end):
    t = " ".join(text.split())
    i = t.index("A legacy waiver (no `base:`)")
    return t[i: t.index(end, i) + len(end)]
row = next(l for l in open(sys.argv[1]) if l.startswith("| Waivers need a maintainer"))
g = open("docs/GLOSSARY.md").read()
g = g[g.index("\n### Waiver\n"):]; g = re.split(r"\n#{1,3} ", g[5:])[0]
r, b = legacy(row, "first parent."), legacy(g, "after retargeting.")
pat = re.compile(r"`((?:base_ref_|automatic_base_change|_failed|waiver-)[^`]*)`")
tr, tb = set(pat.findall(r)), set(pat.findall(b))
assert tr == tb, ("row only", sorted(tr - tb), "glossary only", sorted(tb - tr))
for w in ("at or after the second it was posted", "an unreadable timeline, or a base event with no time", "fail closed"):
    assert w in r and w in b, w
PY2
ck "review-gate.md: pull_request_target is BL-012, not 'deferred to the P7 retrospective'" \
  bash -c 'grep -qF "BL-012" "$1" && ! grep -qF "deferred to the P7 retrospective" "$1"' _ "$R"
# PR #65 verifier run 1, finding 1 (REQ-382): the patch tier states the /release follow-up once, as the exception inside
# "Does not qualify" — never a bullet admitting a release artifact beside a bullet refusing every release artifact.
# Covers: REQ-382
ck "review-gate.md patch tier: the /release fallback-line follow-up is stated once, as the exception inside 'Does not qualify' (P7 R11; PR #65 run 1 finding 1)" \
  bash -c 't=$(awk "/^## Patch tier/{f=1; next} /^## /{f=0} f" "$1"); d=$(awk "/^- \*\*Does not qualify:\*\*/{f=1; print; next} f && /^(- |\$|## )/{f=0} f" <<<"$t" | tr "\n" " " | tr -s " "); for w in "or release artifacts — those take the full phase path — except the known-limitations fallback-line follow-up" "the \`/release\` follow-up that records or removes a release'"'"'s annotated-tag fallback line" "rides a \`patch/<slug>\` PR" "a documents-only edit the release rules permit"; do grep -qF -- "$w" <<<"$d" || { echo "missing $w"; exit 1; }; done; ! grep -qE "^- The \`/release\` follow-up" <<<"$t" && [ "$(grep -o "annotated-tag fallback line" <<<"$t" | wc -l | tr -d " ")" = 1 ]' _ "$R"
ck "step 6: the marker survives the retarget; an update-branch required by strict protection creates a new head (fresh run or waiver)" \
  bash -c 'grep -qF "the marker survives the retarget; an update-branch required by strict protection" <<<"$1" && grep -qF "creates a new head, which needs a fresh verifier run or a waiver" <<<"$1" && ! grep -qF "the marker stands." <<<"$1"' _ "$step6"
# P6 Task 2.6 (REQ-324, REQ-384; P6 R26): in CI the release gate compares the notes with a CI build, never shape-only.
# Covers: REQ-324
ck "review-gate.md's release row and RELEASE exit gate: CI builds the reproducible subset and compares row for row (P6 R26)" \
  bash -c 'for p in "| At PR time, a ship PR" "RELEASE exit gate"; do grep -F "$p" "$1" | grep -qF "builds the reproducible subset itself and compares it row for row (P6 R26)" || exit 1; done; ! grep -qF "until the CI-built manifest (REQ-384, P6)" "$1" && ! grep -qF "until REQ-384 (P6)" "$1"' _ "$R"
# Build 2 final review (REQ-324, REQ-384; art-release-readiness, art-review-gate): the release row and the RELEASE exit
# gate state the rule that holds — in CI the gate never reads dist/ and a tracked dist/ FAILs — and the row's residual
# names the PR-head code the gates check now runs to build the subset (the stack's hook, release_manifest.py), with
# the stack read at the base ref; both are on code mode's gate-code list (above).
# Covers: REQ-324
ck "review-gate.md's release row and RELEASE exit gate: in CI dist/ is never read; a tracked dist/ FAILs" \
  bash -c 'for p in "| At PR time, a ship PR" "RELEASE exit gate"; do l=$(grep -F "$p" "$1"); grep -qF "never reads \`dist/\`" <<<"$l" && grep -qF "a tracked \`dist/\` FAILs" <<<"$l" || exit 1; done; ! grep -qF "in CI \`dist/\` is gitignored and \`dist/manifest.json\` is absent, so" "$1"' _ "$R"
ck "review-gate.md's release row: CI runs the PR head's release hook and release_manifest.py; the stack is read at the base ref" \
  bash -c 'l=$(grep -F "| At PR time, a ship PR" "$1"); for w in "\`scripts/release-<stack>.sh\`" "\`scripts/release-template.sh\`" "\`release_manifest.py\`" "read at the base ref" "gate code"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ "$R"
# PR #54 verifier run 1, finding 1 (REQ-384, REQ-324, REQ-311; art-review-gate): the rows that read the base say how CI
# resolves it — the full ref refs/remotes/origin/<base> since P6 Build 2's fix wave 2, a tag named origin/<base> otherwise
# shadowing the short name — and that a local run's short origin/main is a convention residual.
# Covers: REQ-384
# Covers: REQ-311
ck "review-gate.md: the verifier, coverage and release rows resolve the base in CI by refs/remotes/origin/<base>; the local short name is a convention residual" \
  bash -c 'for p in "| A verifier comment exists for the head" "| The coverage floor measures" "| At PR time, a ship PR"; do l=$(grep -F "$p" "$1"); for w in "refs/remotes/origin/<base>" "a tag named \`origin/<base>\`" "convention residual"; do grep -qF -- "$w" <<<"$l" || { echo "$p: missing $w"; exit 1; }; done; done; ! grep -qF "(materialised with \`git show origin/<base>:…\`)" "$1"' _ "$R"
# Re-review of fix wave 2 (REQ-384): the verifier row says run-verifier.sh's own origin/<base> reads fail closed, and the
# release row names release-tag.sh among the local short-name readers, which fails closed too.
# Covers: REQ-384
# PR #54 verifier run 2, finding 3 (REQ-385, REQ-313): since P6 Build 3 the bootstrap and run-verifier.sh's own base reads
# use the full ref too; release-tag.sh keeps the short name and fails closed.
# Covers: REQ-385
# Covers: REQ-313
ck "review-gate.md: the bootstrap and run-verifier.sh's own base reads use refs/remotes/origin/<base> (P6 Build 3); release-tag.sh's short-name reads fail closed" \
  bash -c 'l=$(grep -F "| A verifier comment exists for the head" "$1"); grep -qF "\`run-verifier.sh\`'"'"'s own base reads use the full ref too since P6 Build 3" <<<"$l" && ! grep -qF "still uses the short name" <<<"$l" && grep -F "| At PR time, a ship PR" "$1" | grep -F "\`release-tag.sh\`" | grep -qF "fails closed"' _ "$R"
ck "review-gate.md: step 3's --from-file line, the /next row and the patch tier print main's bootstrap by refs/remotes/origin/main; no short-name or base-branch bootstrap survives (SEC-004)" \
  bash -c 'grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR> --from-file" "$1" && grep -F "| \`/next\` never runs the verifier" "$1" | grep -qF "\`refs/remotes/origin/main:scripts/run-verifier.sh\`" && [ "$(grep -cF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>" "$1")" -ge 3 ] && ! grep -qE "git show origin/[^ ]*:scripts/run-verifier|origin/<base>:scripts/run-verifier" "$1"' _ "$R"
ck "review-gate.md's test-first row: in CI the base is the event's base SHA, never a name a tag could shadow" \
  bash -c 'grep -F "| Test-first per commit |" "$1" | grep -qF "the event'"'"'s base SHA"' _ "$R"
# PR #54 verifier run 1, finding 4 (REQ-324, REQ-384): the release row records SPECFLOW_RELEASE_BUILD — a local-only
# switch, ignored in CI, since PR-head code in an earlier gates step could write it into $GITHUB_ENV.
# Covers: REQ-324
ck "review-gate.md's release row: SPECFLOW_RELEASE_BUILD=0 is local-only and ignored in CI (the \$GITHUB_ENV route)" \
  bash -c 'l=$(grep -F "| At PR time, a ship PR" "$1"); for w in "\`SPECFLOW_RELEASE_BUILD=0\`" "local-only" "ignored in CI" "\`\$GITHUB_ENV\`"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ "$R"
# P6 Task 3.5 (REQ-350, REQ-324; P6 R8, R10): the sentences release.yml settles — the tag-time replay exists; the PR
# template's checkbox asks what is left for a human; waiver base binding is P7's.
# Covers: REQ-350
for f in "$R" .claude/skills/verifier/SKILL.md .github/PULL_REQUEST_TEMPLATE.md docs/GLOSSARY.md; do
  ck "$f: no 'until P6', P6's release.yml, 'P6/amendment C' or '(P6/P7)' forward reference" \
    bash -c '! grep -qE "until P6|P6.s .?release\.yml|P6/amendment C|\(P6/P7\)" "$1"' _ "$f"
done
ck "review-gate.md's disposition and release rows: release.yml replays them at the tag before anything is published" \
  bash -c 'for p in "| At PR time, a PR that changes a security document" "| At PR time, a ship PR"; do grep -F "$p" "$1" | grep -qF "replays it at the tag (\`--at-tag\`) before anything is published (REQ-350, P6 R30)" || exit 1; done' _ "$R"
# PR #56 verifier run 1, finding 2 (REQ-350, REQ-324; art-release-readiness): the checkbox asks what the residuals leave to a
# human — the previous tag signed (or the recorded fallback) on that release's merge commit, and the previous ship PR's
# gates and test-first checks green at its merge (sections 1-6 are not replayed) — never "release.yml published the
# Release" alone; test_verifier_skill_modes.sh pins step 7 to the same sentence.
ck "the PR template's RELEASE checkbox: the previous tag is signed on its merge commit, and the previous ship PR's gates and test-first checks were green (P6 R10, R30)" \
  bash -c 'l=$(grep -E "^- \[ \] \(RELEASE\) " "$1"); grep -qE "previous release.*tag.*art-release-readiness" <<<"$l" && for w in "is on that release'"'"'s merge commit" "is signed (or annotated with the fallback recorded" "the previous ship PR'"'"'s \`gates\` and test-first checks were green at its merge" "never sections 1–6 or \`check-test-first.sh\`" "a published Release alone proves neither"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done; ! grep -qF "run published the Release" <<<"$l"' _ .github/PULL_REQUEST_TEMPLATE.md
s7=$(grep -E '^7\. ' .claude/skills/verifier/SKILL.md || true)
ck "SKILL.md step 7: release.yml refuses to publish a bad tag on a reviewed commit (R31); the step still depends only on what the headless verifier sees" \
  bash -c 'grep -qF "\`release.yml\` refuses to publish" <<<"$1" && grep -qF "for a tag on a reviewed commit" <<<"$1" && grep -qF "standing informational finding" <<<"$1" && ! grep -qiF "PR body" <<<"$1"' _ "$s7"
# Build 3 final review, finding 7 (REQ-350, REQ-383; P6 R31): the ruleset keeps tags from non-admins out, and an admin
# bypasses it (bypass_actors: admin, always) — step 7 never says it keeps other tags out.
# Covers: REQ-350
ck "SKILL.md step 7: the release tags ruleset keeps v* tags from non-admins out and an admin can bypass it; never 'keeps other tags out'" \
  bash -c 'grep -qF "keeps \`v*\` tags from non-admins out" <<<"$1" && grep -qF "an admin can bypass it" <<<"$1" && ! grep -qF "keeps other tags out" <<<"$1"' _ "$s7"
# Fix wave 1, I (REQ-313, REQ-350; P6 R28, R31): the tag-time re-check has a claim row of its own — its mechanism
# (release-check in release.yml and release-tag.sh) and its residuals: the boundary read at the tag's tree, doc-only
# direct pushes, the admin's ruleset bypass, the classifier from the tagged tree (a reviewed ship PR editing it is bound
# only by that review), and the GITHUB_TOKEN reading a private-membership maintainer as COLLABORATOR.
# Covers: REQ-313
ck "review-gate.md: a claim row for the tag-time re-check, with its mechanism, files and residuals" \
  bash -c 'l=$(grep -F "| At the tag, every first-parent commit of \`main\`" "$1"); [ -n "$l" ] || exit 1
    for w in "attestation.py release-check" "release.yml" "release-tag.sh" "merge_commit_sha" "attestation_since" "tag'"'"'s tree" "doc-only direct pushes" \
             "admin can bypass the \`release tags\` ruleset" "classifier runs from the tagged tree" "bound only by that PR'"'"'s own review" \
             "\`scripts/template-pack.yml\`" "GITHUB_TOKEN" "COLLABORATOR" "membership public" "\`tests/governance/test_release_check.sh\`"; do
      grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ "$R"
# Build 3 re-review (REQ-350, REQ-312; P6 R28): rebase-merge is disabled by configure-repo.sh, and a rebase-merged code
# commit needs a commit-level waiver — said in the tag-time re-check row's mechanism column and in R28.
# Covers: REQ-350
ck "review-gate.md's tag-time re-check row: rebase-merge is disabled by configure-repo.sh; a rebase-merged code commit needs a commit-level waiver" \
  bash -c 'l=$(grep -F "| At the tag, every first-parent commit of \`main\`" "$1"); grep -qF "rebase-merge is disabled by \`configure-repo.sh\` (\`allow_rebase_merge: false\`), so the factory merges by squash or merge commit; a rebase-merged code commit needs a commit-level waiver" <<<"$l"' _ "$R"
if [ -f docs/plans/2026-10-01-factory-v3-2-p6-plan.md ]; then   # an instance has the factory plan fenced out
  ck "the P6 plan's R28: rebase-merge is disabled by configure-repo.sh; a rebase-merged code commit needs a commit-level waiver" \
    bash -c 'l=$(grep -F "**R28 — what the tag-time re-check judges.**" docs/plans/2026-10-01-factory-v3-2-p6-plan.md); grep -qF "rebase-merge is disabled by \`configure-repo.sh\` (\`allow_rebase_merge: false\`), so the factory merges by squash or merge commit; a rebase-merged code commit needs a commit-level waiver" <<<"$l" && grep -qF "\`refs/remotes/<remote>/\` (any remote)" <<<"$l"'
fi
# PR #56 verifier run 1, finding 1 (REQ-350; art-specification-primacy): configure-repo.sh's merge-methods PATCH is R28's
# clause of REQ-350 — README's configure-repo.sh row says so; the plan's "Not claimed" keeps REQ-312's branch-protection
# request unchanged and names the PATCH as REQ-350's, and Partial claims explains the commits that cite REQ-312, REQ-313
# and REQ-320 as history.
# Covers: REQ-350
ck "README's configure-repo.sh row: rebase-merge is turned off (allow_rebase_merge: false; squash and merge commits stay on), REQ-350's R28 clause" \
  bash -c 'l=$(grep -F "| \`scripts/configure-repo.sh\` |" "$1"); for w in "\`allow_rebase_merge: false\`" "squash and merge commits stay on" "REQ-350" "R28"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ README.md
if [ -f docs/plans/2026-10-01-factory-v3-2-p6-plan.md ]; then   # an instance has the factory plan fenced out
  ck "the P6 plan's Not claimed: REQ-312's branch-protection request unchanged; the merge-methods PATCH is REQ-350's R28 clause" \
    bash -c 'l=$(grep -F -- "- **Not claimed, with the reason:**" "$1"); grep -qF "REQ-312 — \`configure-repo.sh\`'"'"'s branch-protection request is unchanged" <<<"$l" && grep -qF "its merge-methods PATCH (\`allow_rebase_merge: false\`) is REQ-350'"'"'s R28 clause" <<<"$l"' _ docs/plans/2026-10-01-factory-v3-2-p6-plan.md
  ck "the P6 plan's Partial claims: the commits citing REQ-312 (6d2e1ae), REQ-313 (edd7522) and REQ-320 (86515bc) are explained as history" \
    bash -c 'l=$(grep -F -- "- **History citations (PR #56 verifier run 1, finding 1):**" "$1"); for w in "\`6d2e1ae\`" "REQ-312" "\`edd7522\`" "REQ-313" "REQ-385" "\`86515bc\`" "REQ-320" "\`test_gate_sections.sh\`" "stand in history"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ docs/plans/2026-10-01-factory-v3-2-p6-plan.md
fi
# PR #56 verifier run 1, finding 4 (REQ-383; art-threat-driven-security): release-tag.sh passes the full
# refs/remotes/<remote>/main to signers.py and release-check; the release row lists only the reads that keep the short name.
# Covers: REQ-383
ck "review-gate.md's release row: release-tag.sh's short-name reads are its HEAD check, choice of M, docs comparison, recorded-fallback read and next: line; signers.py and release-check take the full ref" \
  bash -c 'l=$(grep -F "| At PR time, a ship PR" "$1"); grep -qF "\`release-tag.sh\`'"'"'s HEAD check, choice of \`M\`, docs comparison, recorded-fallback read and advisory \`next:\` line — its \`signers.py\` and \`release-check\` calls take the full \`refs/remotes/<remote>/main\`" <<<"$l"' _ "$R"
# PR #57 fix wave 1, item 7 (REQ-350, REQ-313; art-release-readiness): review-gate.md's RELEASE exit gate and its ship-PR
# row say what the PR template's RELEASE checkbox and SKILL.md step 7 ask — the previous tag signed on that release's merge
# commit, and the previous ship PR's gates and test-first checks green at its merge, since release.yml replays only gates
# section 7 at the tag — never only "confirms the previous release's tag by hand".
# Covers: REQ-350
# Covers: REQ-313
ck "review-gate.md's RELEASE exit gate and ship-PR row carry the checkbox's confirmation sentence (sections 1–6 and check-test-first.sh not replayed)" python3 - "$R" <<'PYR'
import sys
s = ("confirms by hand that the previous release's tag exists, is signed (or annotated with the fallback recorded in that version's known-limitations) "
     "and is on that release's merge commit, and the previous ship PR's `gates` and test-first checks were green at its merge — "
     "`release.yml` replays gates section 7 at the tag, never sections 1–6 or `check-test-first.sh`, so a published Release alone proves neither")
L = open(sys.argv[1]).read().splitlines()
gate = next(l for l in L if l.startswith("- RELEASE exit gate, at PR time"))
row = next(l for l in L if l.startswith("| At PR time, a ship PR"))
assert "RELEASE checkbox, where the maintainer " + s in gate, "exit gate"
assert "RELEASE checkbox is where the maintainer " + s in row, "ship-PR row"
assert "where the maintainer confirms the previous release's tag by hand (convention)" not in gate, "the old sentence"
PYR
# SEC-004 re-review, minor (REQ-385): on a stacked PR the verifier job's log hint is printed by the unreviewed base's
# attestation.py, so step 3 and the glossary's Verifier entry say never to copy the bootstrap from a CI log.
# Covers: REQ-385
ck "review-gate.md step 3: never copy the bootstrap from a CI log; use the rendered line (SEC-004 re-review)" \
  bash -c 's=$(awk "/^3\\. Run the verifier/{f=1} /^4\\. /{f=0} f" "$1" | tr "\n" " " | tr -s " "); grep -qF "Never copy the bootstrap from a CI log; use the rendered line" <<<"$s" && grep -qF "unreviewed base" <<<"$s"' _ "$R"
ck "GLOSSARY Verifier: never copy the bootstrap from a CI log; use the rendered line (SEC-004 re-review)" \
  bash -c 's=$(awk "/^### Verifier\$/{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " "); grep -qF "Never copy the bootstrap from a CI log; use the rendered line" <<<"$s"'
# Amendment C (REQ-326): art-review-gate's How to apply names files, and every one of them is in review-gate.md's
# claim→file table (the article and the rule agree on what enforces it).
# Covers: REQ-326
ck "every file art-review-gate's How to apply names is in review-gate.md's claim→file table" python3 - <<'PY'
import re
c = open("constitution.md").read()
a = c[c.index("slug: art-review-gate"):]; a = a[: a.index("\n---\n")]
how = a.split("**How to apply:**", 1)[1]
named = [t for t in re.findall(r"`([^`\s]+)`", how) if "/" in t and "." in t.split("/")[-1]]
assert named, how
table = "\n".join(l for l in open(".claude/rules/review-gate.md") if l.startswith("| "))
missing = [n for n in named if n not in table]
assert not missing, missing
PY
# P7 retrospective documentation patch (BL-041; PR #68 verifier run 1, findings 1–2): M0b's date is UTC (the probe ran on
# the local evening of 2026-10-03) and the read was measured under a pull_request event only; the tag-time read is unmeasured,
# owned by kpingali123, with R4's bound-waiver recovery and the 3.2.1 pre-ship check (PR #71 verifier run 1, finding 4).
# Covers: REQ-382
m0b_precise() {  # m0b_precise FILE MARKER — the line naming MARKER dates M0b in UTC and says what it did not measure
  python3 - "$1" "$2" <<'PY'
import sys
ls = [l for l in open(sys.argv[1]) if l.startswith(sys.argv[2])]
assert len(ls) == 1, len(ls)
l = ls[0]
for w in ("P7 M0b, PR #67, run 37169624336, 2026-10-04 UTC", "measured under `pull_request`",
          "the tag-time read (`release.yml`'s verify job, the same read permissions) is unmeasured",
          # PR #71 verifier run 1, finding 4: the unmeasured read has an owner, R4's recovery and the pre-ship check.
          "owner kpingali123", "a bound waiver naming the merge commit's first parent clears a refused legacy waiver at the tag",
          "`scripts/release-tag.sh 3.2.1 --dry-run`", "does not measure the workflow token",
          "measured by the first `release.yml` run itself", "`waiver-timeline-unknown`"):
    assert w in l, w
assert "run 37169624336, 2026-10-04:" not in l
PY
}
ck "review-gate.md waiver row: M0b dated 2026-10-04 UTC, measured under pull_request; the tag-time read unmeasured, owned, with R4's recovery and the pre-ship check" m0b_precise "$R" "| Waivers need a maintainer"
finish test_review_gate_claims
