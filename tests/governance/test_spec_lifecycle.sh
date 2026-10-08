#!/usr/bin/env bash
# Governance test: spec lifecycle + constitution/spec consistency (P2 of the
# 2026-06-09 review). Guards: every spec carries a status; superseded specs
# say what superseded them; the constitution defines every verification tag
# actually in use; review-gate.md states the same RELEASE gate as the
# constitution.
# Covers: REQ-310, REQ-311, REQ-313, REQ-382, REQ-322, REQ-324
# Covers: REQ-343, REQ-341, REQ-385
# Covers: REQ-389
# Covers: REQ-380, REQ-371
# (checks 6 and 7 guard the spec's record of P2's departures from REQ-310's code-mode scope, REQ-311's attestation.py
# placement and multiple-markers scoping, and REQ-313's gitleaks invocation)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }
pass() { echo "ok:   $1"; }

# 1. Every spec has YAML frontmatter with a valid status. (REQ-306:
#    shopt -s nullglob so an instance with no specs left — every example
#    removed, or docs/specs/ emptied outright — passes vacuously instead of
#    iterating over the literal, non-matching glob pattern.)
shopt -s nullglob
for f in docs/specs/*.md; do
  if [[ "$(head -1 "$f")" != "---" ]]; then
    fail "$f has no YAML frontmatter"
    continue
  fi
  status=$(awk '/^---$/{n++; next} n==1 && /^status:/{print $2; exit}' "$f")
  case "$status" in
    draft|accepted|superseded) pass "$f status: $status" ;;
    *) fail "$f has invalid/missing status: '$status'" ;;
  esac
  if [[ "$status" == "superseded" ]]; then
    sup=$(awk '/^---$/{n++; next} n==1 && /^superseded_by:/{print $2; exit}' "$f")
    if [[ -n "$sup" && "$sup" != '""' ]]; then
      pass "$f names superseded_by"
    else
      fail "$f is superseded but superseded_by is empty"
    fi
  fi
done

# 2. The constitution defines [verifiable-model] — the tag in actual use.
if grep -q 'verifiable-model' constitution.md; then
  pass "constitution defines [verifiable-model]"
else
  fail "constitution does not define [verifiable-model] (every tagged REQ in the repo uses it)"
fi

# 3. review-gate.md RELEASE gate matches the constitution: annotated-tag
#    fallback and manifest transcription must both be stated.
if grep -A3 'RELEASE exit gate' .claude/rules/review-gate.md | grep -q 'fallback' && \
   grep -A3 'RELEASE exit gate' .claude/rules/review-gate.md | grep -q 'transcribed'; then
  pass "review-gate RELEASE gate states fallback + manifest transcription"
else
  fail "review-gate RELEASE gate missing annotated-fallback or manifest-transcription clause (would fail the compliant v0.0.1-demo)"
fi

# 4. review-gate back-edge has the spec's 6 steps.
steps=$(awk '/## Back-edge protocol/,/## Minor exception/' .claude/rules/review-gate.md | grep -cE '^[0-9]+\.')
if [[ "$steps" -eq 6 ]]; then
  pass "review-gate back-edge has 6 steps"
else
  fail "review-gate back-edge has $steps steps (spec REQ-102 mandates 6)"
fi

# 5. The /retrospective command requires recording decisions on prior
#    proposals (closes the art-retrospective-cadence loop).
if grep -qi 'decision' .claude/commands/retrospective.md; then
  pass "/retrospective requires proposal decisions"
else
  fail "/retrospective never records accept/reject decisions — the retro loop stays half-closed"
fi

# 6. The spec template must use reserved placeholder IDs (REQ-XXX), not
#    real-looking IDs that collide with the globally-unique namespace.
if grep -qE '\*\*REQ-00[0-9]' schemas/spec-template.md; then
  fail "spec template uses REQ-00N placeholders that collide with real globally-unique IDs"
else
  pass "spec template placeholders don't collide with real REQ IDs"
fi

# 6. art-specification-primacy: the v3.2 spec records P2's deliberate departures (#32 finding 5) in its
#    frontmatter amendment list, so P4/P5 authors reading the spec first see them.
V32=docs/specs/2026-09-25-factory-v3-2-design.md
if [[ -f $V32 ]]; then
  fm=$(awk '/^---$/{n++; next} n==1' "$V32")
  if grep -qF 'PR #33' <<<"$fm" && grep -qF '2026-09-26' <<<"$fm" && grep -qF 'attestation.py' <<<"$fm" \
     && grep -qF 'gitleaks dir' <<<"$fm" && grep -qi 'every non-document path' <<<"$fm" \
     && grep -qF 'multiple-markers' <<<"$fm" && grep -qi 'names the head' <<<"$fm"; then
    pass "v3.2 spec frontmatter records P2's departures (PR #33)"
  else
    fail "v3.2 spec frontmatter lacks the PR #33 amendment (attestation.py in P2, gitleaks dir, code-mode scope, multiple-markers scoping)"
  fi
  # #33 third bootstrap F3: the amendment lists every classifier departure from the REQ-311/313 bodies.
  a33=$(grep -F 'PR #33' <<<"$fm" || true); miss=""
  for t in 'edited comment' mode-mismatch verdict-mismatch in-session-in-solo 'blocking comments take precedence' \
           'every commit' '--bootstrap' 'never accepted'; do grep -qF -- "$t" <<<"$a33" || miss="$miss [$t]"; done
  if [[ -z $miss ]]; then pass "the PR #33 amendment lists the classifier's departures from REQ-311/313"
  else fail "the PR #33 amendment omits:$miss"; fi
  # 7. art-specification-primacy (#33 fourth-run finding 1): the REQ bodies themselves describe P2's shipped
  #    behaviour; the frontmatter no longer says the bodies were left unchanged, and the patch PR is recorded.
  #    PR #34 verifier finding 6: history is not rewritten — the PR #33 entry keeps its own words, the patch PR's
  #    entry follows it, and nothing is dated after today (2026-09-26).
  #    A stated deadline ("no later than YYYY-MM-DD", amendment B's, PR #42 third run finding 4) is a commitment, not a
  #    history date, so it is the one future date allowed.
  today=$(date -u +%Y-%m-%d); future=""
  for d in $(sed -E 's/no later than [0-9]{4}-[0-9]{2}-[0-9]{2}//g' <<<"$fm" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u); do [[ "$d" > "$today" ]] && future="$future $d"; done
  if [[ -n $future ]]; then fail "the v3.2 spec frontmatter carries a future date (after $today):$future"
  else pass "the v3.2 spec frontmatter carries no date after today ($today)"; fi
  if grep -qF 'bootstrap markers are never accepted (REQ text bodies unchanged)"' <<<"$a33"; then
    pass "the PR #33 amended: entry keeps its original text"
  else fail "the PR #33 amended: entry was rewritten after the fact"; fi
  ap=$(grep -F 'patch/p2-mediums PR' <<<"$fm" || true)
  if grep -qF '2026-09-26' <<<"$ap" && grep -qi 'REQ bodies' <<<"$ap" && ! grep -qi 'verified' <<<"$ap" \
     && [[ $(grep -nF 'PR #33' <<<"$fm" | cut -d: -f1) -lt $(grep -nF 'patch/p2-mediums PR' <<<"$fm" | cut -d: -f1) ]]; then
    pass "an amended: entry (2026-09-26), below PR #33's, records the patch PR that synced the REQ bodies"
  else fail "no amended: entry (2026-09-26, below PR #33's, no verified-commit wording) for the patch PR"; fi
  # PR #34 second-run finding 2: the entry is honest about what is new — it syncs the bodies to what PR #33 shipped
  # AND names the two behaviours this PR adds, which the "already shipped" list must not claim.
  NEW34="two behaviours are new in this PR, not shipped by P2's IMPLEMENT PR: model-instruction Markdown in code-mode scope (REQ-310) and the re-run chosen by PR number, failing loudly when it cannot be found (REQ-311)"
  if grep -qF "$NEW34" <<<"$ap" && [[ $(grep -o 'model-instruction Markdown' <<<"$ap" | wc -l | tr -d ' ') = 1 ]] \
     && [[ $(grep -o 'by PR number' <<<"$ap" | wc -l | tr -d ' ') = 1 ]] && ! grep -qF 'not a new rule' <<<"$ap"; then
    pass "the patch PR's amended: entry names its two new behaviours as new, not as already shipped"
  else fail "the patch PR's amended: entry claims model-instruction Markdown scope or PR-number re-run as already shipped"; fi
  # PR #35 verifier medium 2 (art-specification-primacy): P4's rulings that depart from literal REQ text are recorded in
  # an amended: entry for its IMPLEMENT PR (#36), below the patch PR's, with the REQ bodies left unchanged.
  a36=$(grep -F 'P4 IMPLEMENT PR #36' <<<"$fm" || true); miss=""
  for t in '2026-09-27' 'REQ-330' 'exit 128' 'FAIL when tracked lockfiles exist' 'PASS with a note only when none exist' \
           'REQ-334' 'any change under `.github/`' 'REQ-388' '`gitleaks:allow`' '--ignore-gitleaks-allow' 'baseline entry' \
           'REQ-332' '`lockfiles:`' 'R3' 'R8' 'R11' 'R13' 'R16' 'REQ bodies unchanged'; do
    grep -qF -- "$t" <<<"$a36" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "an amended: entry for P4 IMPLEMENT PR #36 records the rulings that depart from REQ-330/332/334/388's text"
  else fail "the P4 IMPLEMENT PR #36 amended: entry is missing or omits:$miss"; fi
  if [[ -n $a36 ]] && [[ $(grep -nF 'patch/p2-mediums PR' <<<"$fm" | cut -d: -f1) -lt $(grep -nF 'P4 IMPLEMENT PR #36' <<<"$fm" | cut -d: -f1) ]]; then
    pass "the P4 IMPLEMENT entry follows the patch PR's (history is appended, never rewritten)"
  else fail "the P4 IMPLEMENT amended: entry is not below the patch PR's"; fi
  req() { grep -E "^- \*\*$1:\*\*" "$V32" || true; }
  P2_LABEL="P2's shipped behaviour"; BODY_LABEL=$P2_LABEL
  body_has() {  # body_has REQ TERM... — every TERM appears in the REQ's body
    local r="$1" b miss=""; shift; b=$(req "$r")
    [[ -n $b ]] || { fail "$r: body not found in the v3.2 spec"; return; }
    for t in "$@"; do grep -qF -- "$t" <<<"$b" || miss="$miss [$t]"; done
    if [[ -z $miss ]]; then pass "$r's body describes $BODY_LABEL"; else fail "$r's body omits:$miss"; fi
  }
  # P6 Task 1.6 (REQ-383, REQ-353; P6 R3, R10, R29): the P6 builds entry records Build 1's readings and REQ-353's
  # deferral; REQ-383's body carries the one As amended by P6 sentence its contradicted clauses need.
  # Covers: REQ-383
  a6=$(grep -F 'P6 builds (lanes' <<<"$fm" || true); miss=""
  for t in 'REQ-383' 'R3' 'R17' 'R27' 'principal' 'tagger' 'newest earlier SSH-signed' 'trust on first use' 'first-parent' \
           'revoked_signers' 'REQ-342' 'REQ-341' 'R9' 'REQ-353' 'amendment C' 'REQ bodies unchanged except REQ-383' \
           'passed over' "the tag's own strict ancestors" 'shallow' 'tags, never notes' 'signing_key_present' 'R28' 'pre-transfer' \
           'attestation_since'; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the spec's P6 builds amended: entry records Build 1's readings"; else fail "the P6 builds amended: entry is missing or omits:$miss"; fi
  # P6 Task 2.6 (REQ-384, REQ-305; P6 R18, R26): Build 2's readings join the same entry.
  # Covers: REQ-384
  # Covers: REQ-305
  miss=""
  for t in 'R18' 'from the committed tree' 'notes' 'R26' 'release-build' 'REQ-305' 'RELEASE_PARTS'; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the spec's P6 builds entry records Build 2's readings"; else fail "the P6 builds entry omits Build 2's readings:$miss"; fi
  # Fix wave 1 (REQ-384; P6 R18): only docs/releases/ and docs/security/ are excluded from the archive — a docs/specs or
  # README commit changes its bytes — and the interim window between Build 2 and Builds 4/5 is recorded.
  # Covers: REQ-384
  miss=""
  grep -qF 'interim window' <<<"$a6" || miss="$miss [no interim window]"
  grep -qF 'docs-only commit changes nothing' <<<"$a6" && miss="$miss [still: a docs-only commit changes nothing]"
  grep -qF 'stays.;' <<<"$a6" && miss="$miss [the stray 'stays.;']"
  if [[ -z $miss ]]; then pass "the P6 entry's Build 2 readings: the archive's exclusions stated exactly, the interim window recorded"; else fail "the P6 entry's Build 2 readings:$miss"; fi
  # P6 Task 3.7 (REQ-350, REQ-322, REQ-334, REQ-390; P6 R11, R19, R27, R28, R30): Build 3's readings join the same entry.
  # Covers: REQ-350
  miss=""
  for t in 'R28' 'predates-attestation' 'R30' '--at-tag' 'tagger date' 'committer date' 'R11' 'R19'; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the spec's P6 builds entry records Build 3's readings (re-check range, --at-tag, run-date bound, dfe-13, smoke)"; else fail "the P6 builds entry omits Build 3's readings:$miss"; fi
  # Build 3 final review (REQ-350; findings 13, 15, 17, 19, 20): the entry states the corrected R28/R30 — the range from the
  # newest published Release, the content tie, the minor exception, the boundary that never moves, the notes-adding merge.
  # Covers: REQ-350
  miss=""
  for t in 'published GitHub Release' 'merge-content-mismatch' 'minor exception' 'phase artifact' 'never moves' \
           'added the notes' "the tagged commit's first parent" 'gates section 7'; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  grep -qF 'previous release tag..the tag commit' <<<"$a6" && miss="$miss [still: previous release tag..the tag commit]"
  if [[ -z $miss ]]; then pass "the P6 entry's Build 3 readings carry the final review's corrections"; else fail "the P6 entry's Build 3 readings:$miss"; fi
  # Fix wave 1, H (REQ-350, REQ-354, REQ-352; P6 R22, R23, R31, R34): the Build 3 sentence names what the build also
  # ruled — R31's binding, R34's dispatch, R23's narrowing, R22's app-stack checks, the refusal of a missing previous tag
  # at the tag — and fix wave 1's exact-PR rule and tag-tree reading.
  # Covers: REQ-350
  miss=""
  for t in '(R31)' 'reviewed commit' '(R34)' '30-day' 'workflow_dispatch' '(R23)' 'signing: none|apple' '(R22)' \
           'macOS distribution checklist' 'missing previous release tag' 'stricter than the PR-time WARN' 'merge_commit_sha' \
           'never by containment' 'git status --porcelain' "the app-stack rule's stack at the tag's tree"; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P6 entry's Build 3 sentence records R31, R34, R23, R22, the previous-tag refusal and fix wave 1's readings"; else fail "the P6 entry's Build 3 sentence:$miss"; fi
  # PR #54 verifier run 1, finding 2 (REQ-384; art-specification-primacy; P6 R18): the epoch rule replaces REQ-384's
  # "from the commit", so REQ-384's body carries an "As amended by P6 (build 2):" sentence stating it (the PR #48 run 4
  # precedent), and the P6 entry names REQ-384 among the REQ bodies it changes.
  # Covers: REQ-384
  r384=$(req REQ-384); miss=""
  for t in 'As amended by P6 (build 2):' 'SOURCE_DATE_EPOCH' '00:00 UTC' "the release notes' frontmatter \`date:\`" 'committed tree' \
           'docs/releases/' 'docs/security/' 'dry run'; do
    grep -qF -- "$t" <<<"$r384" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "REQ-384's body carries its As amended by P6 (build 2) sentence: the epoch is 00:00 UTC of the notes' date:"; else fail "REQ-384's body lacks the P6 (build 2) sentence or omits:$miss"; fi
  if grep -qF "REQ bodies unchanged except REQ-383's (its As amended by P6 (build 1) sentence), REQ-384's (its As amended by P6 (build 2) sentence) and REQ-385's (its As amended by P6 (build 3) sentence)" <<<"$a6"; then
    pass "the P6 entry names REQ-384 among the REQ bodies it changes"
  else
    fail "the P6 entry still says REQ bodies are unchanged except REQ-383's"
  fi
  if grep -qF 'as of the previous signed tag' <<<"$a6"; then fail "the P6 builds entry still states the old anchor rule"; else pass "the P6 builds entry states R3's anchor, never 'as of the previous signed tag'"; fi
  # PR #54 verifier run 2, finding 3 (REQ-385, REQ-313; dfe-6): REQ-385's "origin/<base>" (itself an amendment of the
  # literal origin/main) is read as the full ref refs/remotes/origin/<base>; REQ-385's body carries the sentence, and the
  # P6 entry records the reading with its reason.
  # Covers: REQ-385
  r385=$(req REQ-385); miss=""
  for t in 'As amended by P6 (build 3):' 'refs/remotes/origin/<base>' 'git show refs/remotes/origin/<base>:scripts/run-verifier.sh | bash -s -- <PR>' \
           'auto-follows'; do
    grep -qF -- "$t" <<<"$r385" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "REQ-385's body carries its As amended by P6 (build 3) sentence: the bootstrap by the full ref"; else fail "REQ-385's body lacks the P6 (build 3) sentence or omits:$miss"; fi
  miss=""
  for t in 'REQ-385 (build 3; PR #54 verifier run 2, finding 3)' 'refs/remotes/origin/<base>' 'auto-follows' 'into bash'; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P6 entry records REQ-385's full-ref reading and its reason"; else fail "the P6 entry omits REQ-385's full-ref reading:$miss"; fi
  # PR #54 verifier run 2, finding 2 (REQ-384; art-release-readiness): the interim window carries an owner, a due date
  # and the P3 IMPLEMENT entry's lapse rule, and init warns during it.
  # Covers: REQ-384
  miss=""
  # PR #56 verifier run 1, finding 3 (REQ-384; art-review-gate): no skill text carries a lapse finding, so the owner is
  # the control, no gate checks the date, and a lapse is recorded in the next ship PR's known-limitations.
  for t in 'owner: kpingali123' 'due no later than 2026-10-12' 'the owner (kpingali123) is the control' 'no gate checks the date' \
           "a lapse is recorded in the next ship PR's known-limitations" "init-project.sh's next steps end with a one-line warning"; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  grep -qF 'severity high' <<<"$a6" && miss="$miss [still: the verifier reports a lapse as a finding of severity high]"
  if [[ -z $miss ]]; then pass "the P6 entry's interim window: owner as the control, due date, no gate on the date, init's warning"; else fail "the P6 entry's interim window omits:$miss"; fi
  # P6 R35's interim-window edit (REQ-352, REQ-384): the window closed when the second of Builds 4 and 5 merged — the
  # P6 entry says so, with the date and the owner, and that the notes and init's warning are gone.
  # Covers: REQ-352
  miss=""
  for t in 'the interim window closed on 2026-10-03' 'the second of Builds 4 and 5 to merge (Build 5, PR #58)' \
           'owner: kpingali123' "README's paragraph, /release's step-4 sentence and init-project.sh's warning are removed"; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P6 entry: the interim window closed on 2026-10-03 with Build 5's merge (owner kpingali123)"; else fail "the P6 entry omits the interim window's closure:$miss"; fi
  # PR #57 verifier run 1, finding 2 (REQ-351; art-specification-primacy, P6 R29): REQ-351's "rollback redeploys the
  # previous tag" is read, and the reading recorded in the P6 entry: the release below the running one, deployed by
  # digest, never by tag.
  # Covers: REQ-351
  miss=""
  for t in "REQ-351's rollback redeploys the previous tag (its body's words) is read as the release below the running one" \
           'org.opencontainers.image.version' 'the highest vX.Y.Z tag below that version' 'deployed by its digest, never by tag' \
           '<image>@<digest>, never :<version>' 'only vX.Y.Z tags count'; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P6 entry records REQ-351's rollback reading: the release below the running one, by digest, never by tag"; else fail "the P6 entry omits REQ-351's rollback reading:$miss"; fi
  # PR #56 verifier run 1, finding 1 (REQ-350; art-specification-primacy): configure-repo.sh's merge-methods PATCH is
  # recorded under REQ-350 (R28's clause) in the P6 entry; REQ-312's branch-protection request is unchanged.
  # Covers: REQ-350
  miss=""
  for t in 'configure-repo.sh' 'allow_rebase_merge false' 'squash and merge commits stay on' "REQ-312's branch-protection request is unchanged"; do
    grep -qF -- "$t" <<<"$a6" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P6 entry records configure-repo.sh's merge-methods change under REQ-350"; else fail "the P6 entry omits the merge-methods change:$miss"; fi
  r383=$(req REQ-383); miss=""
  # Build 1 final review (REQ-383; P6 R3 as corrected): the anchor never falls back past an SSH-signed release, and TOFU
  # is bounded to the tag's own history.
  for t in 'As amended by P6 (build 1):' 'SSH signatures only' 'newest earlier SSH-signed' 'trust on first use' 'tagger' 'unsigned-tag' 'follow-up docs PR' \
           'passed over' "the tag's own strict ancestors" 'no signer at all'; do
    grep -qF -- "$t" <<<"$r383" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "REQ-383's body carries its As amended by P6 (build 1) sentence (R29)"; else fail "REQ-383's body lacks the P6 sentence or omits:$miss"; fi
  if grep -qF 'anchor-downgrade' <<<"$a6$r383"; then fail "the P6 entry or REQ-383's body still names anchor-downgrade"; else pass "the P6 entry and REQ-383's body no longer name anchor-downgrade (fix wave 2)"; fi
  # PR #53 verifier run 1, finding 1 (REQ-383; P6 R3(i)): the anchor is the newest earlier SSH-signed v<X.Y.Z> tag among
  # the tag's strict ancestors — tags, never notes; an SSH-signed candidate off the first-parent chain is refused
  # (anchor-off-main), never passed over — so neither text names "the previous release's tag" as a first choice.
  # Covers: REQ-383
  for s in "$a6" "$r383"; do
    miss=""
    for t in 'newest earlier SSH-signed' 'strict ancestors' 'tags, never notes' 'anchor-off-main' 'passed over'; do
      grep -qF -- "$t" <<<"$s" || miss="$miss [$t]"
    done
    grep -qF "previous release's tag" <<<"$s" && miss="$miss [still names the previous release's tag]"
    if [[ -z $miss ]]; then pass "R3(i)'s anchor rule, in the P6 entry and REQ-383's body alike"; else fail "the anchor rule (P6 entry or REQ-383's body):$miss"; fi
  done
  body_lacks() {  # body_lacks REQ TERM... — no TERM survives in the REQ's body
    local r="$1" b hit=""; shift; b=$(req "$r")
    for t in "$@"; do grep -qF -- "$t" <<<"$b" && hit="$hit [$t]"; done
    if [[ -z $hit ]]; then pass "$r's body drops the stale wording"; else fail "$r's body still says:$hit"; fi
  }
  body_has REQ-310 'every non-document path' '.editorconfig' 'LICENSE' '`--bootstrap`' 'PR head' 'never accepted' \
    'model-instruction' 'any `CLAUDE.md` or `CLAUDE.local.md`' 'at any depth'
  body_lacks REQ-310 'any `CLAUDE.md` under `stacks/`'
  # PR #34 third-run finding 2: the constitution corrections the glossary and claim table say are "tracked for
  # amendment PR B" must be owned by REQ-343, which defines amendment B.
  body_has REQ-343 'also corrects `art-review-gate`' 'Dependabot' 'enforce_admins' 'REQ-334' 'REQ-314'
  body_lacks REQ-310 'touches the pack'"'"'s `source_roots`, `tests/`, or `verification/`'
  body_has REQ-311 'created in P2' 'P5 extends it' 'names the head' 'mode-mismatch' 'verdict-mismatch' 'digest-mismatch' \
    'in-session-in-solo' 'take precedence' 'every commit author' 'dependabot[bot]' \
    "GitHub maps the author login from the commit's author email, which anyone with push access can set; a committer/signature check and the dependency-only diff restriction are P4's (REQ-334, threat-model dfe-13)"
  body_lacks REQ-311 '(created in P5)' 'considers only unedited comments' 'fails if a comment carries more than one marker' \
    'verified'
  body_has REQ-313 '--restricted' '--safe-mode' '--setting-sources user' '--mcp-config' '--strict-mcp-config' '--tools' \
    '--allowedTools' '--disallowedTools' '--permission-mode dontAsk' '--no-session-persistence' '--add-dir' \
    'gitleaks dir' '`--bootstrap`'
  body_lacks REQ-313 'gitleaks detect --no-git'
  body_has REQ-382 'convention' 'PR template' 'not checked' 'does not override a blocking comment' \
    'newest accepted comment' 'MEMBER' 'any organisation member' 'P5' 'any commit author'
  body_lacks REQ-382 'and the PR body records the waiver'
  # P5 PLAN PR (REQ-343; P5 R4, R5): amendment B, the idle-step reading and the record refinements, below the P3 entry.
  a5=$(grep -F 'P5 PLAN PR' <<<"$fm" || true); miss=""
  for t in '2026-09-28' 'amendment B' 'REQ-343' 'art-branch-as-state' 'art-review-gate' 'art-threat-driven-security' \
           'art-release-readiness' 'art-retrospective-cadence' 'REQ-393' 'NewBranch(ProposeDesign)' 'RunBrainstorm' \
           'REQ-341' 'ADR-003 unchanged' 'ship_phases_merged' 'REQ bodies unchanged'; do
    grep -qF -- "$t" <<<"$a5" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P5 PLAN PR amended: entry records amendment B, R4's idle step and R5/R6"
  else fail "the P5 PLAN PR amended: entry is missing or omits:$miss"; fi
  if [[ -n $a5 ]] && [[ $(grep -nF 'P3 IMPLEMENT PR' <<<"$fm" | cut -d: -f1) -lt $(grep -nF 'P5 PLAN PR' <<<"$fm" | cut -d: -f1) ]]; then
    pass "the P5 PLAN entry follows the P3 IMPLEMENT entry (history is appended)"
  else fail "the P5 PLAN amended: entry is not below the P3 IMPLEMENT entry"; fi
  # P5 IMPLEMENT PR (REQ-341, 382, 334, 306, 340, 389, 310, 385): the wrapper rulings, below the P5 PLAN entry.
  a5i=$(grep -F 'P5 IMPLEMENT PR' <<<"$fm" || true); miss=""
  for t in 'REQ-341' 'REQ-382' 'REQ-334' 'REQ-306' 'REQ-340' 'REQ-389' 'REQ-310' 'REQ-385' 'R9' 'R11' 'R12' 'R19' 'R21' 'R22' \
           'full mode' 'origin/<base>' 'REQ bodies unchanged'; do
    grep -qF -- "$t" <<<"$a5i" || miss="$miss [$t]"
  done
  if [[ -z $miss ]] && [[ $(grep -nF 'P5 PLAN PR' <<<"$fm" | cut -d: -f1) -lt $(grep -nF 'P5 IMPLEMENT PR' <<<"$fm" | cut -d: -f1) ]]; then
    pass "the P5 IMPLEMENT amended: entry records the wrapper rulings, below the P5 PLAN entry"
  else fail "the P5 IMPLEMENT amended: entry is missing, out of order, or omits:$miss"; fi
  # P5 final review: the IMPLEMENT entry records the final-review rulings (markers need a writing role and are bound to
  # their base, the merge command is bound to the head, next_version on phase/security and phase/release, sec- slugs).
  miss=""
  for t in 'marker-not-writer' 'base-mismatch' '--match-head-commit' 'next_version' 'sec-' 'base-lockfile-v1' 'fork'; do
    grep -qF -- "$t" <<<"$a5i" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P5 IMPLEMENT amended: entry records the final-review rulings"
  else fail "the P5 IMPLEMENT amended: entry omits the final-review rulings:$miss"; fi
  # PR #48 verifier medium 1 (art-specification-primacy): REQ-389's body says full mode confirms the acknowledgements,
  # and the IMPLEMENT entry says that body changed here (no unqualified "REQ bodies unchanged"). PR #47 verifier mediums
  # 1-2: the entry records amendment B's two narrowings of art-release-readiness. PR #48 verifier high: rule 1b.
  b389=$(req REQ-389)
  if grep -qF "which the verifier's full mode" <<<"$b389" && grep -qF 'code mode never sees them' <<<"$b389" \
     && ! grep -qF "which the verifier's code mode confirms" <<<"$b389"; then pass "REQ-389's body: the verifier's full mode confirms the acknowledgements"
  else fail "REQ-389's body still says code mode confirms the acknowledgements"; fi
  if grep -qF 'closed: verifier full mode' docs/specs/2026-09-25-factory-v3-2-design.md; then pass "Open Question 4 is closed by full mode"
  else fail "Open Question 4 still names code mode"; fi
  miss=""
  for t in "REQ bodies unchanged except REQ-389's" "REQ-389's body changed here" 'GPG-only' 'GPG or SSH' \
           'dist/manifest.json' 'blocks nothing at PR time' 'REQ-384' 'request-changes-permission-unknown' \
           'never accepted and keeps blocking'; do
    grep -qF -- "$t" <<<"$a5i" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P5 IMPLEMENT amended: entry records REQ-389's body change, amendment B's two narrowings and rule 1b"
  else fail "the P5 IMPLEMENT amended: entry omits:$miss"; fi
  # PR #48 verifier run 2 (REQ-389, REQ-385, REQ-382): F5 — REQ-389's body cites each acknowledgement's own article, and
  # the entry says so; F7 — REQ-385's 'APPROVE marker' is read as including an accepted waiver; code-mode high — the
  # entry states in one sentence that rule 1b narrows the pre-P5 rule for known non-writing roles, and why.
  if grep -qF "citing each acknowledgement's own article (\`[verifiable-model]\` tags \`art-formal-verification\`, the kernel boundary \`art-kernel-boundary\`, severity and dispositions \`art-threat-driven-security\`)" <<<"$b389" \
     && ! grep -qF 'recorded as provisional under `art-threat-driven-security`' <<<"$b389"; then pass "REQ-389's body cites each acknowledgement's own article"
  else fail "REQ-389's body still records the confirmation under art-threat-driven-security alone"; fi
  miss=""
  for t in "cites each acknowledgement's own article" "REQ-385's 'APPROVE marker' is read as 'APPROVE marker or an accepted waiver'" \
           'MergeOnlyWhenApproved' "This narrows the pre-P5 rule, under which a MEMBER's comment blocked regardless of repository role"; do
    grep -qF -- "$t" <<<"$a5i" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P5 IMPLEMENT amended: entry records F5, F7 and the read-only narrowing"
  else fail "the P5 IMPLEMENT amended: entry omits:$miss"; fi
  # PR #48 verifier run 4, findings 1 and 2 (art-specification-primacy): REQ-311, REQ-340, REQ-385 and REQ-393's bodies
  # state what P5 shipped in one appended "As amended by P5 (PR #48):" sentence each, their original text kept; the
  # P5 IMPLEMENT entry names the four synced bodies beside REQ-389's (the patch/p2-mediums precedent of a spec sync).
  BODY_LABEL="what P5 shipped (PR #48)"
  body_has REQ-311 'The script, not the model, writes the marker' 'As amended by P5 (PR #48):' 'apply after rule 1b' \
    'only with a writing repository role (`admin`, `maintain` or `write`' 'legacy `permission` field' \
    'an unreadable role is never accepted and keeps blocking' 'a known `read`, `triage` or `none` role neither accepts nor blocks' \
    'bound to the merge base it reviewed' '`base:` must be 40 hex' '`base-mismatch` refuses only an `APPROVE`' \
    '`request-changes-base-mismatch`' 'a fork PR is never the branch'"'"'s PR'
  body_has REQ-340 'With `path: lanes`, branches are' 'As amended by P5 (PR #48):' '`impl/plan-N-<plan slug>`' \
    'the plan'"'"'s `## Build N` section' 'only when `<plan slug>` names the plan' 'The `sec-` prefix is reserved' \
    '`build/sec-<id>` and `impl/sec-<id>` are parsed first' 'may not begin with `sec-`' 'is not tracked'
  body_has REQ-385 'In `awaiting-verifier`, `next_step` is the literal' 'As amended by P5 (PR #48):' \
    '"an `APPROVE` marker or an accepted waiver"' '`gh pr merge <N> --squash --match-head-commit <40-hex head>`' \
    '`gh pr merge <N> --merge --match-head-commit <40-hex head> && gh pr edit <m> --base <this PR'"'"'s base>` (a merge commit first, which keeps the stacked PR'"'"'s recorded merge base, then each stacked PR retargeted; the explanation is a note line)' \
    '`origin/<base>`' 'not literally `origin/main`' 'warned when it is not `main`' \
    'neither the PR author nor an author or committer of any of its commits' 'latest review at the head' \
    'a `CHANGES_REQUESTED` at any commit that is neither dismissed nor followed by that reviewer'"'"'s approval means no approval'
  body_has REQ-393 'derives `(none, idle, "run /specify <slug>")`' 'As amended by P5 (PR #48):' 'ADR-003' \
    '`design/<slug>`' '`phase/spec-<slug>`' '/superpowers:brainstorming' 'in place of the literal'
  # PR #48 verifier run 5, finding 2 (art-specification-primacy): REQ-382's body no longer says the role check is
  # deferred to P5 — its appended sentence states rule 1b as shipped and the PR #50 measurement (a private organisation
  # membership reads as COLLABORATOR under the workflow token, whose waiver rule 6 refuses).
  body_has REQ-382 'A maintainer may post' 'is deferred to P5.' 'As amended by P5 (PR #48): the check ships as rule 1b' \
    'a `MEMBER`'"'"'s waiver, and a `MEMBER`'"'"'s or `COLLABORATOR`'"'"'s marker, counts only with a writing repository role (`admin`, `maintain`, `write`, read through `repos/<repo>/collaborators/<login>/permission`' \
    'a custom role name resolved through the legacy `permission` field' 'an unreadable role never accepted and still blocking' \
    'a known `read`, `triage` or `none` role neither' 'measured 2026-09-29 (PR #50)' \
    'a member whose organisation membership is private reads as `COLLABORATOR`' '(`waiver-not-maintainer`; a read-role collaborator is refused earlier as `waiver-not-writer`)'
  BODY_LABEL=$P2_LABEL
  miss=""
  for t in "REQ bodies unchanged except REQ-389's and, synced to what shipped, REQ-311's, REQ-340's, REQ-382's, REQ-385's and REQ-393's" \
           'PR #48 verifier run 5 (finding 2, art-specification-primacy): REQ-382'"'"'s body is synced the same way' \
           'PR #48 verifier run 4 (findings 1 and 2, art-specification-primacy' 'patch/p2-mediums precedent' \
           "'As amended by P5 (PR #48):'" 'the team-mode human-approval rule is in REQ-385'; do
    grep -qF -- "$t" <<<"$a5i" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P5 IMPLEMENT amended: entry records the four REQ bodies synced to what shipped"
  else fail "the P5 IMPLEMENT amended: entry omits the REQ-body sync:$miss"; fi
  if ! grep -qF 'P5 IMPLEMENT PR (2026-09-28 plan): rulings of the P5 plan (docs/plans/2026-09-28-factory-v3-2-p5-plan.md) that narrow, extend or read literal REQ text, REQ bodies unchanged —' <<<"$a5i"; then
    pass "the P5 IMPLEMENT entry no longer opens with an unqualified 'REQ bodies unchanged'"
  else fail "the P5 IMPLEMENT entry still claims 'REQ bodies unchanged' unqualified"; fi
  # SEC-004 (high; dfe-9, dfe-10; REQ-385): the 3.2.0 security review's back-edge amends REQ-385 — the bootstrap is main's
  # reviewed copy for every PR, and a stacked PR's instruction names its unreviewed base PR. REQ-385's body carries the
  # sentence; a new amended: item (two-space indented, after the P6 builds entry, which stays as it was) records it.
  # Covers: REQ-385
  r385=$(req REQ-385); miss=""
  for t in 'As amended by the SEC-004 back-edge (2026-10-03):' 'git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>' \
           'for every PR' 'the base PR #<n> is unreviewed; its diff is reviewed by its own PR' 'never piped into bash'; do
    grep -qF -- "$t" <<<"$r385" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "REQ-385's body carries its As amended by the SEC-004 back-edge sentence"; else fail "REQ-385's body lacks the SEC-004 sentence or omits:$miss"; fi
  asec=$(grep -E '^  - "SEC-004 back-edge' "$V32" || true); miss=""
  for t in 'build/sec-SEC-004' 'REQ-385' 'refs/remotes/origin/main' 'dfe-9' 'dfe-10' 'CWE-494'; do
    grep -qF -- "$t" <<<"$asec" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "an amended: item records the SEC-004 back-edge's REQ-385 amendment"; else fail "the SEC-004 amended: item is missing or omits:$miss"; fi
  # SEC-004 review round 2, finding 1 (art-specification-primacy): REQ-313's own text said the verifier script is read
  # from the base branch and quoted the base-ref bootstrap, which the P6 builds entry reads as refs/remotes/origin/<base>
  # — exactly what SEC-004 removes. Its body gains its own As amended by the SEC-004 back-edge sentence (the code run is
  # main's for every PR; the skill, constitution and policy still read at the base as data), and the amended: item rules
  # on REQ-313's text instead of calling it unchanged.
  # Covers: REQ-313
  BODY_LABEL="the SEC-004 back-edge's bootstrap"
  body_has REQ-313 'As amended by the SEC-004 back-edge (2026-10-03):' 'git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>' \
    'for every PR' '`attestation.py`' "still read at the PR's base" 'as data' 'the marker records that base'
  BODY_LABEL=$P2_LABEL
  miss=""
  for t in 'REQ-385'"'"'s and REQ-313'"'"'s bodies each gain' 'REQ-313'"'"'s parenthetical bootstrap' 'read from the base branch' \
           'main'"'"'s reviewed copy for every PR' 'the code run is main'"'"'s'; do
    grep -qF -- "$t" <<<"$asec" || miss="$miss [$t]"
  done
  if [[ -z $miss ]] && ! grep -qF 'REQ-313'"'"'s unchanged' <<<"$asec"; then
    pass "the SEC-004 amended: item rules on REQ-313's base-branch text, never calling it unchanged"
  else fail "the SEC-004 amended: item still calls REQ-313 unchanged or omits:$miss"; fi
  if [[ "$(grep -nE '^- "P6 builds \(lanes' "$V32" | cut -d: -f1)" -lt "$(grep -nE '^  - "SEC-004 back-edge' "$V32" | cut -d: -f1 || echo 0)" ]]; then
    pass "the SEC-004 item follows the P6 builds entry"
  else fail "the SEC-004 item does not follow the P6 builds entry"; fi
fi

# 8. extends / extended_by symmetry (BL-032, REQ-380, REQ-371): every live spec whose
#    frontmatter says `extends: <spec>` names an extended spec that exists and lists
#    this spec under `extended_by:`, and vice versa. The two keys are read through
#    scripts/lib/specflow/frontmatter.py (REQ-380's reader: surrounding quotes and a
#    trailing `# comment` stripped, as schemas/spec-template.md writes them), item by
#    item for an inline list (`[a, b]` or `a, b`) or a block list (`key:` then `  - a`
#    lines); "" or empty means none. A reference is a spec's file name, with or without
#    `.md` (any directory part dropped), so the template's documented form
#    (`extends: "<file>.md"`) and the bare name both resolve. Behaviour is run against
#    scratch docs/specs trees, then the real one.
# Covers: REQ-380
# Covers: REQ-371
extends_symmetry() { # <specs dir>; prints ok:/FAIL: lines, returns 1 on any asymmetry
  python3 - "$ROOT" "$1" <<'PYX'
import glob, os, re, sys
sys.path.insert(0, os.path.join(sys.argv[1], "scripts/lib/specflow"))
import frontmatter as fmr
d = sys.argv[2]

def norm(ref):
    b = os.path.basename(ref.strip())
    return b[:-3] if b.endswith(".md") else b

def refs(path, key):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        return []
    items = fmr.parse_list(fmr.parse_text(text).get(key, ""))
    if not items:  # a block list: `key:` (nothing, or only a comment, after it) then `  - item` lines
        lines = m.group(1).splitlines()
        for i, line in enumerate(lines):
            if re.match(r"^" + re.escape(key) + r":\s*(#.*)?$", line):
                for nxt in lines[i + 1:]:
                    mm = re.match(r"^\s*-\s+(.*)$", nxt)
                    if not mm:
                        break
                    it = fmr.strip_quotes(fmr.strip_comment(mm.group(1)).strip())
                    if it:
                        items.append(it)
                break
    return [norm(x) for x in items if norm(x)]

rc = 0
for f in sorted(glob.glob(os.path.join(d, "*.md"))):
    if open(f, encoding="utf-8").readline().rstrip("\n") != "---":
        continue
    me = norm(f)
    for key, back, verb, says, ok in (("extends", "extended_by", "extends", "list it under extended_by", "lists it"),
                                      ("extended_by", "extends", "is extended_by", "say extends: " + me, "extends it")):
        for ref in refs(f, key):
            other = os.path.join(d, ref + ".md")
            if not os.path.isfile(other):
                print(f"FAIL: {f} {verb} {ref} but {other} does not exist"); rc = 1
            elif me not in refs(other, back):
                print(f"FAIL: {f} {verb} {ref} but {other} does not {says}"); rc = 1
            else:
                print(f"ok:   {f} {verb} {ref} and {other} {ok}")
sys.exit(rc)
PYX
}
mkspec() { # <dir> <name> <extends> <extended_by>
  printf -- '---\ntype: spec\nstatus: accepted\nextends: "%s"\nextended_by: "%s"\n---\nbody\n' "$3" "$4" > "$1/$2.md"
}
XS=$(mktemp -d)
mkdir -p "$XS/sym" "$XS/asym" "$XS/dangling"
mkspec "$XS/sym" base "" "ext"; mkspec "$XS/sym" ext "base" ""
mkspec "$XS/asym" base "" ""; mkspec "$XS/asym" ext "base" ""
mkspec "$XS/dangling" ext "gone" ""
if out=$(extends_symmetry "$XS/sym"); then pass "extends/extended_by: a symmetric pair passes"
else fail "extends/extended_by: a symmetric pair was refused: $out"; fi
if out=$(extends_symmetry "$XS/asym"); then fail "extends/extended_by: an asymmetric pair passed"
elif grep -q 'ext.md extends base but .*base.md does not list it' <<<"$out" && grep -q 'base.md' <<<"$out"; then
  pass "extends/extended_by: an asymmetric pair fails, naming both files"
else fail "extends/extended_by: the asymmetric failure does not name both files: $out"; fi
mkspec "$XS/asym" base "" "ext"; mkspec "$XS/asym" ext "" ""
if out=$(extends_symmetry "$XS/asym"); then fail "extends/extended_by: the reverse asymmetry passed"
elif grep -q 'base.md is extended_by ext but .*ext.md does not say extends' <<<"$out"; then
  pass "extends/extended_by: the reverse asymmetry fails, naming both files"
else fail "extends/extended_by: the reverse failure does not name both files: $out"; fi
if out=$(extends_symmetry "$XS/dangling"); then fail "extends/extended_by: a missing extended spec passed"
else pass "extends/extended_by: an extends naming no existing spec fails"; fi
# Final review findings 1 and 5: the forms schemas/spec-template.md documents (a value followed by a `# comment`, a
# spec's file name with `.md`) and a block list must pass, as /specify writes specs from that template.
mkdir -p "$XS/tmpl" "$XS/mdpair" "$XS/block"
sed 's/^created: ""/created: "2026-10-04"/' schemas/spec-template.md > "$XS/tmpl/2026-10-04-widget-design.md"
if out=$(extends_symmetry "$XS/tmpl"); then pass "extends/extended_by: a spec copied from schemas/spec-template.md, comments kept, passes"
else fail "extends/extended_by: a template-derived spec was refused: $out"; fi
printf -- '---\ntype: spec\nstatus: accepted\nextends: ""   # filename of the spec this builds on, if any\nextended_by: "2026-10-04-b-design.md"   # mirror of extends\n---\nbody\n' > "$XS/mdpair/2026-10-04-a-design.md"
printf -- '---\ntype: spec\nstatus: accepted\nextends: "2026-10-04-a-design.md"   # filename of the spec this builds on\nextended_by: ""\n---\nbody\n' > "$XS/mdpair/2026-10-04-b-design.md"
if out=$(extends_symmetry "$XS/mdpair"); then pass "extends/extended_by: a symmetric pair written as file names with .md passes"
else fail "extends/extended_by: a symmetric pair written with .md file names was refused: $out"; fi
printf -- '---\ntype: spec\nstatus: accepted\nextends: ""\nextended_by:\n  - ext\n  - "ext2.md"   # the second extension\nnext: x\n---\nbody\n' > "$XS/block/base.md"
mkspec "$XS/block" ext "base" ""; mkspec "$XS/block" ext2 "base.md" ""
if out=$(extends_symmetry "$XS/block"); then pass "extends/extended_by: a block-list extended_by passes"
else fail "extends/extended_by: a block-list extended_by was refused: $out"; fi
rm -f "$XS/block/ext2.md"
if out=$(extends_symmetry "$XS/block"); then fail "extends/extended_by: a block-list item naming no spec passed"
elif grep -q 'base.md is extended_by ext2 but .*ext2.md does not exist' <<<"$out"; then
  pass "extends/extended_by: a block-list item naming no spec fails, naming it"
else fail "extends/extended_by: the block-list failure does not name the missing spec: $out"; fi
if out=$(extends_symmetry docs/specs); then pass "extends/extended_by: every live spec in docs/specs is symmetric"
else fail "extends/extended_by: docs/specs has an asymmetry: $out"; fi
rm -rf "$XS"

# 9. BL-035 (REQ-380, REQ-371): pins for the two spec-frontmatter defect shapes
#    frontmatter.py's first-colon split never notices — an `amended:` item at
#    column 0, and an unescaped double quote inside a double-quoted item.
#    The second is invalid YAML; the first is invalid only when mixed with
#    indented items (a list entirely at column 0 is valid compact YAML), so
#    that rule is a style pin stricter than YAML: every item sits under
#    amended:, as the live specs write it. Not a YAML parse
#    (python3 stdlib only; the strict parse is v3.3's). Behaviour is run
#    against scratch spec trees, then the live specs.
# Covers: REQ-380, REQ-371
amended_shapes() { # <dir> — prints "<file>:<line>: <why>" per defect; exit 1 if any
  local f out="" rc=0
  for f in "$1"/*.md; do
    [[ -f "$f" ]] || continue
    out=$(awk -v F="$f" '
      NR==1 && $0!="---" {exit}
      NR>1 && $0=="---" {exit}
      /^amended:/ {inb=1; next}
      inb && /^[A-Za-z_][A-Za-z0-9_-]*:/ {inb=0}
      inb && /^- "/ {print F ":" NR ": amended item at column 0 (not indented under amended:)"; next}
      inb && /^  - "/ {
        s=$0; gsub(/\\"/, "", s); n=gsub(/"/, "\"", s)
        if (n > 2) print F ":" NR ": unescaped double quote inside a double-quoted amended item"
      }' "$f")
    if [[ -n "$out" ]]; then echo "$out"; rc=1; fi
  done
  return $rc
}
AS=$(mktemp -d)
mkdir -p "$AS/good" "$AS/col0" "$AS/quote"
printf -- '---\nstatus: accepted\namended:\n  - "PR #1: a \\"quoted\\" word"\n  - "PR #2: plain"\nnext: x\n---\nbody\n' > "$AS/good/s.md"
printf -- '---\nstatus: accepted\namended:\n  - "PR #1: ok"\n- "PR #2: at column zero"\n---\nbody\n' > "$AS/col0/s.md"
printf -- '---\nstatus: accepted\namended:\n  - "PR #1: ok"\n  - "PR #2: an "inner" quote"\n---\nbody\n' > "$AS/quote/s.md"
if out=$(amended_shapes "$AS/good"); then pass "amended shapes: a well-formed list (escaped quotes) passes"
else fail "amended shapes: a well-formed list was refused: $out"; fi
if out=$(amended_shapes "$AS/col0"); then fail "amended shapes: a column-0 item passed"
elif grep -q 's.md:5: amended item at column 0' <<<"$out"; then pass "amended shapes: a column-0 item fails, naming file and line"
else fail "amended shapes: the column-0 failure does not name file and line: $out"; fi
if out=$(amended_shapes "$AS/quote"); then fail "amended shapes: an unescaped inner quote passed"
elif grep -q 's.md:5: unescaped double quote' <<<"$out"; then pass "amended shapes: an unescaped inner quote fails, naming file and line"
else fail "amended shapes: the inner-quote failure does not name file and line: $out"; fi
if out=$(amended_shapes docs/specs); then pass "amended shapes: every live spec's amended: list is well-formed"
else fail "amended shapes: a live spec has a defect: $out"; fi
rm -rf "$AS"

if [[ $FAIL -ne 0 ]]; then
  echo "test_spec_lifecycle: FAILED"
  exit 1
fi
echo "test_spec_lifecycle: all checks passed"
