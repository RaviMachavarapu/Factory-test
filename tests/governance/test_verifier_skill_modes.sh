#!/usr/bin/env bash
# REQ-310: the verifier skill's code mode has fixed headings; REQ-313: the headless prompt is a base-ref template
# that declares reviewed content to be data. Both files feed prompt_sha256.
# Covers: REQ-310
# Covers: REQ-313
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
K=.claude/skills/verifier/SKILL.md; P=.claude/skills/verifier/headless-prompt.md
ck "SKILL.md has a code mode" grep -q '^## Mode: code' "$K"
code=$(awk '/^## Mode: code/{f=1; next} /^## /{f=0} f' "$K")
for h in 'Test-first per commit' 'REQ citations' 'Covers annotations' 'Proof headers' 'Verdict'; do
  ck "code mode fixes the heading '### $h'" grep -qx "### $h" <<<"$code"
done
ck "code mode headings are in the fixed order" python3 - "$K" <<'PY'
import re, sys
t = open(sys.argv[1]).read().split("## Mode: code", 1)[1].split("\n## ", 1)[0]
want = ["Test-first per commit", "REQ citations", "Covers annotations", "Proof headers", "Verdict"]
got = [h for h in re.findall(r"^### (.+)$", t, re.M) if h in want]
sys.exit(0 if got == want else 1)
PY
ck "code mode reads diff.patch and commits.txt" bash -c 'grep -q diff.patch <<<"$1" && grep -q commits.txt <<<"$1"' _ "$code"
ck "code mode names the P3 checker it stands in for (REQ-321)" grep -qF 'check-test-first.sh' <<<"$code"
ck "code mode flags gate-code changes for a human" bash -c 'grep -qF ".github/" <<<"$1" && grep -qF "attestation.py" <<<"$1"' _ "$code"
codef=$(tr '\n' ' ' <<<"$code" | tr -s ' ')
ck "code mode rates any gate-weakening change high by rule (doc finding 5)" \
  bash -c 'grep -qiF "high by rule" <<<"$1" && for s in "\`verifier\`" "\`gates\`" "attestation.py" "run-verifier.sh" "deny list" "isolation flags" "REQUEST_CHANGES" "waiver"; do grep -qF -- "$s" <<<"$1" || exit 1; done' _ "$codef"
ck "every mode ends with the one-line verdict" grep -qE 'exactly `APPROVE` or `REQUEST_CHANGES`' "$K"
ck "SKILL.md no longer says the verifier never approves" no grep -q 'Never approve your own findings' "$K"
ck "SKILL.md no longer labels full mode as CI" no grep -qE '^## Mode: full \(CI' "$K"
ck "the headless prompt template exists" test -f "$P"
for t in @MODE@ @BASE@ @DOCS@ @CODE@ @INPUT_DIR@; do ck "the template carries $t" grep -qF "$t" "$P"; done
ck "the prompt declares reviewed content to be data (REQ-313)" grep -qi 'data, not instructions' "$P"
ck "the prompt says the appended skill and constitution come from the base branch" grep -qF 'from the base branch' "$P"
ck "the prompt forbids HTML comments in the output" grep -qi 'HTML comment' "$P"
ck "the template has no double-brace placeholders" no grep -qF '{''{' "$P"
# #33 fourth run finding 9: code mode says where "the PR's plan" is, and what to do when there is none.
# PR #34 verifier finding 8: the headless prompt has no PR-body slot and the body is author-controlled, so the plan
# is found from the commits alone; a PR no plan covers (patch tier) still gets its REQ citations checked.
ck "code mode: the plan lookup never uses the PR body" no grep -qF 'PR body' <<<"$codef"
ck "code mode: the plan is the newest docs/plans/*.md whose implements: covers the commits' REQs" \
  bash -c 'grep -qF "newest \`docs/plans/*.md\`" <<<"$1" && grep -qF "implements:" <<<"$1" && grep -qF "commits.txt" <<<"$1"' _ "$codef"
ck "code mode: no covering plan (patch tier) → every cited REQ must exist in the spec; say no plan governs the PR" \
  bash -c 'grep -qi "patch-tier" <<<"$1" && grep -qi "exists in the spec" <<<"$1" && grep -qF "under \`### REQ citations\`" <<<"$1" && grep -qi "no plan governs the PR" <<<"$1" && ! grep -qi "rate nothing on that basis" <<<"$1"' _ "$codef"
# #33 fourth run finding 10: instruction Markdown that instances load as session instructions is gate code too.
ck "code mode's gate-code list names model-instruction Markdown (any CLAUDE.md/CLAUDE.local.md, stacks overlay/skeleton, templates/)" \
  bash -c 'for s in "CLAUDE.md" "CLAUDE.local.md" "any depth" "stacks/" "overlay/" "skeleton/" "templates/"; do grep -qF -- "$s" <<<"$1" || exit 1; done' _ "$codef"
# Second-run finding 7 (double review): each part sees both lists; the other part's list is context only.
ck "the prompt says the other part's list is context only and must not be judged in this part" \
  bash -c 'grep -qi "context only" "$1" && grep -qi "must not be judged in this part" "$1"' _ "$P"
# PR #34 verifier finding 7: a document-versus-code conflict must not fall between the two parts.
ck "the prompt keeps cross-checks of a document's claims against the code in full mode (step 3)" \
  bash -c 'grep -qF "Cross-checks that compare a document'"'"'s claims with the code remain in scope for the full-mode part (full mode'"'"'s step 3)" "$1"' _ "$P"
# PR #34 second-run finding 6: the no-plan fallback is for patch/<slug> head branches only, and REQs split across
# plans are judged per commit; the headless prompt names the head branch so the model can tell.
ck "code mode: the no-plan fallback applies only when the head branch is patch/<slug>" \
  bash -c 'grep -qF "only when the PR'"'"'s head branch is \`patch/<slug>\`" <<<"$1" && grep -qiF "on any other branch a cited REQ that no plan'"'"'s \`implements:\` covers is a finding (\`art-specification-primacy\`)" <<<"$1"' _ "$codef"
ck "code mode: REQs covered by more than one plan are judged per commit, naming which plan governed which commit" \
  bash -c 'grep -qF "covered by more than one plan" <<<"$1" && grep -qF "judge each commit against the plan that covers the REQs it cites" <<<"$1" && grep -qF "which plan governed which commit" <<<"$1"' _ "$codef"
ck "the template carries @HEAD_BRANCH@" grep -qF '@HEAD_BRANCH@' "$P"
# P5 final review: /next's own code is gate code where branch protection is absent (REQ-385) — it runs from the checkout.
ck "code mode's gate-code list names /next's code: scripts/next.sh, pipeline.py, state.py and .claude/commands/next.md" \
  bash -c 'for s in "scripts/next.sh" "scripts/lib/specflow/pipeline.py" "scripts/lib/specflow/state.py" ".claude/commands/next.md"; do grep -qF -- "\`$s\`" <<<"$1" || exit 1; done' _ "$codef"
# PR #56 verifier run 1, finding 2 (REQ-350; art-release-readiness): full mode's step 7 asks the maintainer to confirm
# what the PR template's RELEASE checkbox asks, in the same sentence — the previous tag signed on its release's merge
# commit and the previous ship PR's gates and test-first checks green at its merge, since release.yml replays only
# gates section 7 at the tag.
# Covers: REQ-350
ck "SKILL.md step 7 and the PR template's RELEASE checkbox carry the same confirmation sentence" python3 - "$K" .github/PULL_REQUEST_TEMPLATE.md <<'PYS'
import re, sys
s = ("the previous release's tag exists, is signed (or annotated with the fallback recorded in that version's known-limitations) "
     "and is on that release's merge commit, and the previous ship PR's `gates` and test-first checks were green at its merge — "
     "`release.yml` replays gates section 7 at the tag, never sections 1–6 or `check-test-first.sh`, so a published Release alone proves neither")
step7 = next(l for l in open(sys.argv[1]).read().splitlines() if l.startswith("7. "))
box = next(l for l in open(sys.argv[2]).read().splitlines() if l.startswith("- [ ] (RELEASE) "))
assert "ask the maintainer to confirm by hand that " + s in step7, "step 7"
assert "confirmed by hand that " + s in box, "template"
PYS
# PR #57 fix wave 1, item 7 (REQ-350; art-release-readiness): step 7's sentence ends after "proves neither"; the
# verify-release.sh clause that follows is a sentence of its own, never what "neither" is attached to by a colon.
# Covers: REQ-350
ck "SKILL.md step 7: 'proves neither.' ends the sentence; the verify-release.sh clause starts the next" \
  bash -c 's=$(grep -E "^7\. " "$1"); grep -qF "so a published Release alone proves neither. \`verify-release.sh\` FAILs a wrong previous tag" <<<"$s" && ! grep -qF "proves neither:" <<<"$s"' _ "$K"
finish test_verifier_skill_modes
