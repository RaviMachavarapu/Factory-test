#!/usr/bin/env bash
# Architecture artifacts kept true to what shipped (P4 walks the full phase path, so its IMPLEMENT branch may update
# them): dfe-2 describes the P2 classifier as shipped; dfe-4, dfe-11 and dfe-13 the P4 rules; the narrative no longer
# says nothing exists; the overview says what P5 extended and created.
# Covers: REQ-311
# Covers: REQ-334
# Covers: REQ-388
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
TM="$ROOT/docs/architecture/2026-09-25-factory-v3-2-threat-model.md"; OV="$ROOT/docs/architecture/2026-09-25-factory-v3-2-overview.md"
[[ -f "$TM" && -f "$OV" ]] || { echo "SKIP: the v3.2 architecture documents are not in this tree"; exit 0; }
row() { grep -E "^\| $1 \|" "$TM" || true; }
r2=$(row dfe-2)
ck "dfe-2 no longer claims only unedited comments are considered" no grep -qF 'accepts only unedited comments' <<<"$r2"
for w in 'names the head' 'mode-mismatch' 'verdict-mismatch' 'digest-mismatch' 'in-session-in-solo' 'blocking'; do ck "dfe-2 states '$w'" grep -qF "$w" <<<"$r2"; done
r13=$(row dfe-13)
for w in 'verification.verified' 'web-flow' '.github/' 'requirements.txt' 'Cargo.lock' 'pubspec.lock' 'fail closed' 'REQ-350' '[patch]' 'dependency_overrides'; do ck "dfe-13 states '$w'" grep -qF "$w" <<<"$r13"; done
# #36 medium 5 (art-review-gate): the accepted residual has an owner, a sign-off and an expiry tied to P6's tag-time
# re-check (REQ-350), like the sign-off REQ-343/REQ-314 require for solo mode's zero-approval rule.
res13=$(sed -n 's/.*Residual (\(.*\)/\1/p' <<<"$r13")
for w in 'owner: kpingali123' 're-accepted' 'expires: 2027-01-31; re-dated 2026-10-05' 'REQ-350'; do ck "dfe-13's accepted residual records '$w'" grep -qF "$w" <<<"$res13"; done
ck "dfe-13 no longer exempts uses: lines" no grep -qF 'and `uses:` lines' <<<"$r13"
r4=$(row dfe-4)
ck "dfe-4 no longer exempts uses: lines for Dependabot" no grep -qF 'and `uses:` lines' <<<"$r4"
ck "dfe-4 names the version-only residuals" bash -c 'grep -q "setup-node" <<<"$1" && grep -q "rustup" <<<"$1" && grep -qi "homebrew" <<<"$1"' _ "$r4"
r11=$(row dfe-11)
for w in 'ignore-gitleaks-allow' 'suppresses:' 'check-suppressions.sh'; do ck "dfe-11 states '$w'" grep -qF -- "$w" <<<"$r11"; done
ck "the narrative no longer says no mitigation exists" no grep -qF 'None of the mitigations below exist today' "$TM"
ck "the overview no longer says P5 creates attestation.py or extends it in the future tense" \
  bash -c '! grep -qF "P5 creates \`attestation.py\`" "$1" && ! grep -qF "P5 extends it for" "$1"' _ "$OV"
ck "the overview says P2 created attestation.py and P5 extended it and created state.py, pipeline.py and next.sh" \
  grep -qE 'P2 created `attestation.py`.*P5 extended it.*`state.py`.*`pipeline.py`.*`next.sh`' "$OV"
ck "the overview records check-architecture.sh's hand-off to P3 (REQ-320)" grep -qE 'check-architecture.sh.*REQ-320' "$OV"

# P3 (REQ-322, REQ-324, REQ-394, REQ-321): the architecture artifacts say what P3 shipped.
# Covers: REQ-322
# Covers: REQ-324
# Covers: REQ-394
r3=$(row dfe-3)
for w in 'check-security-disposition.sh' 'SPECFLOW_BASE_REF' 'carried_from' 'id_removed' 'cvss4.py'; do ck "dfe-3 states '$w'" grep -qF "$w" <<<"$r3"; done
ck "dfe-3's residual states the id_removed recovery for an id the base never had (re-list it, or a PR from a branch rebuilt on the base)" \
  bash -c 'grep -qF "raised in error" <<<"$1" && grep -qF "rebuilt on the base" <<<"$1"' _ "$r3"
ck "dfe-3's residual states that a carried-forward downgrade re-accepted as low has no expiry upper bound" grep -qF 'no expiry upper bound' <<<"$r3"
ck "a residual records the id_removed recovery for an id added and removed within the PR" \
  bash -c 'awk "/^## Residual risks/{f=1} f" "$1" | grep -qF "raised in error"' _ "$TM"
ck "the narrative lists P3 among the shipped plans" grep -qF 'P3 (dfe-3)' "$TM"
ck "the implements: residual names verify-release.sh's ship-time check, not 'until P3'" \
  bash -c '! grep -qF "until P3 this is convention" "$1" && grep -qF "verify-release.sh" "$1"' _ "$TM"
ck "a residual records that check-test-first.sh reads the commits as pushed (REQ-321)" \
  bash -c 'awk "/^## Residual risks/{f=1} f" "$1" | grep -qF "check-test-first.sh"' _ "$TM"
for w in 'not that the test exercises' 'left `status: open`' 'vitest.config.ts'; do
  ck "a residual states '$w'" bash -c 'awk "/^## Residual risks/{f=1} f" "$1" | grep -qF -- "$2"' _ "$TM" "$w"
done
ck "dfe-3 states the open-medium residual and the tag read" bash -c 'grep -qF "open" <<<"$1" && grep -qF "from its tag" <<<"$1"' _ "$r3"
ck "overview: the frontmatter parsers are lifted, not 'to be lifted'" \
  bash -c 'grep -qF "scripts/lib/specflow/frontmatter.py" "$1" && ! grep -qF "to be lifted" "$1"' _ "$OV"
ck "overview: P3 created the disposition modules and the model, as shipped" \
  bash -c 'grep -qE "P3 created .*records.py.*blocks.py.*cvss4.py.*disposition.py" "$1" && ! grep -qF "P3 creates" "$1"' _ "$OV"
ck "overview: check-architecture.sh's scoping is done (P3 scoped it, REQ-320)" \
  bash -c 'grep -qE "P3 scoped .*REQ-320" "$1" && ! grep -qF "P3 scopes it" "$1"' _ "$OV"

# PR #42 findings 1 and 5, code mode (REQ-324, REQ-322, REQ-321): the residuals say what the previous-tag check leaves
# open, carry the open-medium follow-up proposal, and name the head-copy residual of check-test-first.sh.
rr=$(awk '/^## Residual risks/{f=1} f' "$TM")
for w in 'only a WARN when it is missing' 'git tag -v' 'count open mediums toward' 'PR head'"'"'s own `check-test-first.sh`'; do
  ck "a residual states '$w'" grep -qF -- "$w" <<<"$rr"
done
# P6 Task 1.6 (REQ-383; P6 R3): the threat model's release-gates residual states the same clause.
# Covers: REQ-383
ck "the release-gates residual: an SSH signature is checked against allowed_signers at the anchor; only GPG or no anchor key is a WARN" \
  bash -c 'grep -qF "an SSH signature is checked against \`.github/allowed_signers\` as of the newest earlier SSH-signed release tag, itself verified back to trust on first use (\`signers.py\`, P6 R3)" <<<"$1" && ! grep -qF "WARN until P6 (REQ-350, REQ-383)" <<<"$1"' _ "$rr"
# Build 1 final review (REQ-383, REQ-324): the release-gates residual lists every FAIL kind of the previous-tag check,
# names git verify-tag against the anchor's allowed_signers, and points at R3's TOFU caveat (dfe-12, Task 3.6).
ck "the release-gates residual: the FAIL kinds in full, git verify-tag at the anchor, no 'only an unsigned tag … FAILs'" \
  bash -c 'for w in lightweight unlisted tagger-mismatch revoked revocation-unreadable revocation-malformed anchor-off-main anchor-unverified shallow git-error "git verify-tag" "TOFU caveat"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "only an unsigned tag without the recorded fallback, or a BAD signature, FAILs" <<<"$1"' _ "$rr"
# Fix wave 2 (REQ-383; P6 R3, dfe-12): the dfe-12 row states the anchor and the TOFU caveat as the code has it.
# Covers: REQ-383
r12=$(row dfe-12)
factory_doc_ck "dfe-12 states the anchor as signers.py has it: tags, never notes; first-parent; the tagger as git parses it; revocation fails closed" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "newest earlier SSH-signed" "tags, never notes" "first-parent" "tagger" "revocation-unreadable" "revocation-malformed" "gpg.ssh.program"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$r12"
factory_doc_ck "dfe-12 carries the TOFU caveat as the code has it: trust restarts, passed-over tags, removed-but-not-revoked keys, a verdict later commits never change, the notes route closed" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "TOFU caveat" "trust restarts after any first-parent commit" "missing, replaced-unsigned or lightweight" "removed but not revoked" "a later commit never changes a tag'"'"'s verdict" "deleting earlier releases'"'"' notes moves nothing" "ruleset"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "anchor-downgrade" <<<"$1"' _ "$r12"
# Fix wave 2 round 2 (REQ-383; P6 R3, dfe-12): the walk is bounded by commits, but the anchor candidates are the tags that
# exist when the check runs, so replacing or deleting an earlier release tag changes a released tag's verdict (measured:
# v1.2.0 signed with a key the tree had dropped is unlisted against v1.1.0, ssh-good against v1.0.0 once v1.1.0 is
# replaced unsigned). Neither dfe-12 nor R3 says a tag's verdict never changes, unqualified.
# Covers: REQ-383
P6P="$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
factory_doc_ck "dfe-12 says replacing or deleting an earlier release tag can change a tag's verdict (the ruleset is the control), never that it never changes" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'grep -qF "replacing or deleting an earlier release tag can" <<<"$1" && grep -qF "the ruleset is the control" <<<"$1" && ! grep -qiF "a tag'"'"'s verdict never changes after the tag exists" <<<"$1"' _ "$r12"
factory_doc_ck "the P6 plan's TOFU caveat (R3) carries the same qualification" docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  python3 - "$P6P" <<'PY'
import sys; t = open(sys.argv[1]).read()
c = next(l for l in t.splitlines() if "*The TOFU caveat" in l)
assert "A later commit never changes a tag's verdict" in c, c[-400:]
assert "replacing or deleting an earlier release tag can" in c, c[-400:]
assert "a tag's verdict never changes after the tag exists" not in c.lower(), "unqualified 'never changes' survives"
PY
# Build 1 re-review (REQ-383; P6 R3, dfe-12): signers.py's _tofu walks the tag's strict first-parent ancestors newest
# first and stops at the newest key-less commit, so TOFU re-trusts the keys of the NEWEST key-listing run, never the oldest.
# Covers: REQ-383
factory_doc_ck "dfe-12's and R3's TOFU caveat name the newest key-listing run (what _tofu anchors at), never the oldest run" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for t in "$1" "$2"; do grep -qF "the newest key-listing run" <<<"$t" && ! grep -qF "oldest run" <<<"$t" || exit 1; done' _ "$r12" \
  "$(grep -F "*The TOFU caveat" "$P6P")"
# Fix wave 2 round 2 (REQ-383; P6 R28): the R28 boundary's count agrees with its own list and with the preview's total —
# 28 pre-transfer first-parent commits (5b08cb7 and PRs #8, #10–#20, #22–#36) and 9 judged make the 37.
# Covers: REQ-383
factory_doc_ck "the P6 plan's R28 boundary counts 28 pre-transfer and 9 judged first-parent commits, as its own list has them" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md python3 - "$P6P" <<'PY'
import re, sys; t = open(sys.argv[1]).read()
b = next(l for l in t.splitlines() if l.startswith("- **The R28 boundary"))
m = re.search(r"So (\d+) first-parent commits are `pre-transfer` \(`5b08cb7` and PRs ([^)]*)\) and (\d+) are judged \(([^)]*)\)", b)
assert m, "the count sentence is missing"
def n(s):
    k = 0
    for it in re.split(r", | and ", s):
        r = re.fullmatch(r"#(\d+)(?:[–-]#(\d+))?", it.strip())
        assert r, it
        k += int(r[2]) - int(r[1]) + 1 if r[2] else 1
    return k
pre, judged = int(m[1]), int(m[3])
assert pre == 1 + n(m[2]), (pre, 1 + n(m[2]))
assert judged == n(m[4]), (judged, n(m[4]))
shas = re.findall(r"`([0-9a-f]{7})`", b[b.index("`5b08cb7` PR #9"):b.index("**`e88e836`")])  # the header names `45d9525`
assert pre == len(shas), (pre, len(shas))
total = int(re.search(r"`v0\.0\.1-demo\.\.origin/main` holds (\d+) first-parent commits", t)[1])
assert pre + judged == total, (pre, judged, total)
PY
ck "the release-gates residual no longer says only 'a previous release left untagged is a WARN'" \
  no grep -qF 'a previous release left untagged is a WARN on the next ship PR, not a FAIL' <<<"$rr"

# Amendment B (REQ-343): the release-gates residual names the gap art-release-readiness records, not "until amendment B".
# Covers: REQ-343
ck "the release-gates residual no longer waits for amendment B" no grep -qF 'until amendment B' <<<"$rr"
ck "the release-gates residual names the gap art-release-readiness records" grep -qF 'the one gap `art-release-readiness` records' <<<"$rr"

# P5 (REQ-341, REQ-340, REQ-382, REQ-334; H20, H9): the architecture artifacts say what P5 shipped.
# Covers: REQ-341
r7=$(row dfe-7); r10=$(row dfe-10); r2b=$(row dfe-2); r13b=$(row dfe-13)
for w in 'UnknownBranchNeverMerges' 'MergeOnlyWhenApproved' 'both paths'; do ck "dfe-7 states '$w'" grep -qF "$w" <<<"$r7"; done
ck "dfe-7 and dfe-10 are delivered in P5" bash -c 'grep -qE "\| P5 \|$" <<<"$1" && grep -qE "\| P5 \|$" <<<"$2"' _ "$r7" "$r10"
ck "dfe-10: /next lists other users' PRs with the warning and never proposes checking one out" \
  bash -c 'grep -qF "never proposes" <<<"$1" && grep -qF "next.md" <<<"$1"' _ "$r10"
ck "dfe-2: a MEMBER's waiver needs the admin, maintain or write role" grep -qF 'admin, maintain or write' <<<"$r2b"
ck "dfe-13: an npm lockfile gains no entry" grep -qF 'no `node_modules/` entry' <<<"$r13b"
ck "the narrative lists P5 among the shipped plans" grep -qF 'P5 (dfe-7, dfe-10)' "$TM"
# Covers: REQ-326
ck "the open-medium residual: not adopted by amendment C (a kernel change), proposed for v3.3 as BL-002" \
  bash -c 'grep -qF "Not adopted by amendment C" <<<"$1" && grep -qF "BL-002" <<<"$1" && ! grep -qF "Proposed for amendment C / P7" <<<"$1" && ! grep -qF "P5 backlog" <<<"$1"' _ "$rr"
# P7 design review, polish item 3 (REQ-326): the quoted REQ text is P5 R16's, never a bare "R16" a P7 reader takes for P7 R16.
# Covers: REQ-326
ck "the open-medium residual quotes P5 R16's REQ text, not a bare R16" bash -c 'grep -qF "with P5 R16'"'"'s REQ text" <<<"$1" && ! grep -qF "with R16'"'"'s REQ text" <<<"$1"' _ "$rr"
for w in "come from the unverified wrapper" "reads PR state through" "runs the checkout's own code" "from an unreviewed branch"; do ck "a residual states '$w'" grep -qF "$w" <<<"$(awk '/^## Residual risks/{f=1} f' "$TM")"; done
ck "overview: render_step and parse_branch live in pipeline.py" grep -qF 'pipeline.render_step' "$OV"

# P5 final review (REQ-382, REQ-334, REQ-385, REQ-340): markers from a MEMBER or COLLABORATOR need a writing role and
# are bound to their base; a base package-lock.json without packages fails closed; sec- slugs are reserved; the merge
# command /next prints is bound to the judged head.
# Covers: REQ-382
# Covers: REQ-385
r2c=$(row dfe-2); r7c=$(row dfe-7); r13c=$(row dfe-13)
for w in 'marker-not-writer' 'base-mismatch' 'merge base'; do ck "dfe-2 states '$w'" grep -qF "$w" <<<"$r2c"; done
ck "dfe-7: a slug starting with sec- is unknown (build/sec- is the back-edge's name)" grep -qF 'sec-' <<<"$r7c"
ck "dfe-13: a base lockfile without a packages map fails closed; the legacy tree mirrors packages" \
  bash -c 'grep -qF "base-lockfile-v1" <<<"$1" && grep -qF "legacy-dependencies" <<<"$1"' _ "$r13c"
ck "the /next residual: the merge command is bound to the judged head (--match-head-commit)" \
  grep -qF -- '--match-head-commit' <<<"$(awk '/^## Residual risks/{f=1} f' "$TM")"

# PR #48 verifier high and lows 5-7 (REQ-382, REQ-311, REQ-341): dfe-2 states rule 1b in both directions and cites the
# role, base-mismatch and unknown-role fixtures; dfe-7 names the heads the proof jobs run on exactly as verifier.yml
# does; the narrative says P5 ships with PRs #47 and #48.
# Covers: REQ-382, REQ-311, REQ-341
r2d=$(row dfe-2); r7d=$(row dfe-7)
ck "dfe-2: an unreadable role is never accepted and keeps blocking; a known read, triage or none role neither accepts nor blocks; any other role name is resolved through the legacy permission field, else treated as unreadable" \
  grep -qF 'an unreadable role is never accepted and keeps blocking; a known `read`, `triage` or `none` role neither accepts nor blocks; any other role name is resolved through the legacy `permission` field, else treated as unreadable' <<<"$r2d"
ck "dfe-2 cites fixtures 01–35, 72–77, 82–88, 92–102 and 103–114 (100–102: PR #48 verifier run 2; 103–114: P7 R4), not 01–35 alone" \
  bash -c 'grep -qF "fixtures 01–35, 72–77, 82–88, 92–102 and 103–114" <<<"$1" && ! grep -qF "fixtures 01–35)" <<<"$1"' _ "$r2d"
# PR #65 verifier run 1, finding 8 (REQ-382): dfe-2, the row about how waivers are judged, states P7 R4's waiver rules —
# the base-bound waiver judged as a marker, the legacy waiver's timeline read, and the three refusals that never block.
# Covers: REQ-382
ck "dfe-2 states P7 R4's waiver rules: base:<40-hex base> judged as a marker, the legacy waiver's timeline read, waiver-base-mismatch / waiver-unbound-retargeted / waiver-timeline-unknown refused, never blocking" \
  bash -c 'for w in "\`base:<40-hex base>\`" "judged as a marker is" "the PR'"'"'s timeline" "\`waiver-base-mismatch\`" "\`waiver-unbound-retargeted\`" "\`waiver-timeline-unknown\`" "refused, never blocking" "P7 R4"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$r2d"
ck "dfe-7: the proof jobs' heads as verifier.yml lists them, not patch/, and not 'both paths' branches'" \
  bash -c 'grep -qF "design/, build/, ship/, impl/, phase/plan-, phase/validate, phase/security and phase/release heads" <<<"$1" && grep -qF "not patch/" <<<"$1" && ! grep -qF "run on both paths" <<<"$1"' _ "$r7d"
V="$ROOT/.github/workflows/verifier.yml"
for h in design/ build/ ship/ impl/ phase/plan- phase/validate phase/security phase/release; do
  ck "verifier.yml's proof jobs run on $h heads (as dfe-7 says)" grep -qF "startsWith(github.head_ref, '$h')" "$V"
done
ck "verifier.yml's proof jobs do not run on patch/ heads (as dfe-7 says)" no grep -qF "startsWith(github.head_ref, 'patch/')" "$V"
ck "the narrative no longer says P5's parts are true once both PRs merge (PR #48 verifier run 2, F9)" no grep -qF "true once both merge" "$TM"

# PR #48 verifier run 3, finding 6 (REQ-382, REQ-334): a row whose mitigations include P5 work names P5 in its "Delivered
# in" column — dfe-2 (rule 1b, the base binding) reads P2, P5; dfe-13 (the npm new-entry rule, P5 R10) reads P4, P5 —
# and the narrative says so beside P5 (dfe-7, dfe-10).
# Covers: REQ-382
# P7 Build 1 fix wave 2 re-review: the Delivered-in column names the plan that ships each mitigation — dfe-2 gained
# R4's waiver rules and dfe-5 R8's non-root image and hash-pinned lock in P7.
# Covers: REQ-382
# Covers: REQ-351
ck "dfe-2 is delivered in P2, P5, P7 (R4)" bash -c 'grep -qE "\| P2, P5, P7 \(R4\) \|$" <<<"$1"' _ "$(row dfe-2)"
ck "dfe-5 is delivered in P6, P7 (R8)" bash -c 'grep -qE "\| P6, P7 \(R8\) \|$" <<<"$1"' _ "$(row dfe-5)"
ck "dfe-13 is delivered in P4, P5, P6" bash -c 'grep -qE "\| P4, P5, P6 \|$" <<<"$1"' _ "$(row dfe-13)"
ck "the narrative names dfe-2's and dfe-13's P5 parts" \
  grep -qF "dfe-2's rule 1b and base binding and dfe-13's npm new-entry rule are P5's too (their rows read \`P2, P5\` and \`P4, P5\`)" "$TM"

# P5 lows patch (PR #48 verifier run 6 code low; REQ-382): the waiver's head-only binding is a named residual, and
# run 7 finding 9 / run 6 finding 4: the narrative says P5 was delivered, in plain past tense, by the merged PRs.
# Covers: REQ-382
factory_doc_ck "the waiver residual: base binding delivered (P7 R4); what stays is the legacy waiver's timeline read" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "- **A legacy waiver is bound to a head, not a base**" "$1"); grep -qF "P7 R4" <<<"$l" && grep -qF "base_ref_changed" <<<"$l" && ! grep -qF "proposed for P7/amendment C" <<<"$l" && ! grep -qF -- "- **A waiver is bound to a head, not a base**" "$1"' _ "$TM"
# P7 Build 1 final review (findings 2, 7; REQ-382): the residual names GitHub's automatic retarget and a base rewrite.
factory_doc_ck "the legacy waiver residual: every base event counts (automatic_base_change_succeeded, base_ref_force_pushed); a base rewritten with no timeline event stays" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "- **A legacy waiver is bound to a head, not a base**" "$1"); grep -qF "\`automatic_base_change_succeeded\`" <<<"$l" && grep -qF "\`base_ref_force_pushed\`" <<<"$l" && grep -qF "a base rewritten with no timeline event" <<<"$l"' _ "$TM"
ck "the narrative: P5 (dfe-7, dfe-10) was delivered by P5, PRs #47 and #48, merged 2026-09-30" \
  bash -c 'grep -qF "P5 (dfe-7, dfe-10) was delivered by P5, PRs #47 and #48, merged 2026-09-30" "$1" && ! grep -qF "is delivered by the P5 PLAN and IMPLEMENT PRs" "$1"' _ "$TM"
# PR #53 verifier run 1, finding 3 (REQ-383; art-threat-driven-security): dfe-12's accepted TOFU caveat names an owner,
# a sign-off and an expiry, as dfe-13's accepted residual does; and code-mode low (L7): the pre-existing gpg-good residual
# — any key in the local keyring passes, unchecked against allowed_signers or the tagger — is recorded in the row.
# Covers: REQ-383
# PR #54 verifier run 1, finding 5 (REQ-383; art-threat-driven-security): the owner/sign-off/expiry record is added by
# Build 2 (PR #54), not PR #53, so the sign-off is PR #54's merge, and in solo mode the severity is provisional until a
# second reviewer confirms it.
# PR #56 verifier run 1, finding 5 (REQ-383): Build 3 re-accepted the caveat, so the sign-off is PR #56's merge.
factory_doc_ck "dfe-12's accepted TOFU caveat: owner, sign-off (PR #56's merge, Build 3, which re-accepted it; provisional, solo) and a dated expiry" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'grep -qF "**TOFU caveat** (accepted — owner: kpingali123, the maintainer; sign-off: PR #56'"'"'s merge (Build 3, which re-accepted it; Build 2'"'"'s PR #54 added this record, and PR #53 merged the anchor without it); severity provisional until a second reviewer confirms it (solo mode, \`art-threat-driven-security\`): \`CVSS:4.0/AV:N/AC:L/AT:P/PR:H/UI:A/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N\` (5.6, medium" <<<"$1" && ! grep -qF "sign-off: PR #53" <<<"$1" && ! grep -qF "sign-off: PR #54" <<<"$1"' _ "$r12"
factory_doc_ck "dfe-12 records the pre-existing gpg-good residual: any local-keyring key, unchecked against allowed_signers or the tagger; a WARN in CI; release.yml SSH-only (R27)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "pre-existing residual" "\`gpg-good\`" "local keyring" "allowed_signers" "tagger" "WARN" "R27"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$r12"
# PR #53 verifier run 1, finding 2 (REQ-383; P6 R3(i)): one anchor rule in the plan — the superseded "chain" bullet is
# gone, and Task 1.1 Step 3 says what R3(i) and signers.py do: a non-SSH candidate is passed over, never straight to TOFU.
# Covers: REQ-383
factory_doc_ck "the P6 plan: no R3 'chain' bullet; Task 1.1 Step 3 states R3(i) (passed over, anchor-off-main, TOFU only with none)" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md python3 - "$P6P" <<'PY'
import sys; t = open(sys.argv[1]).read(); ls = t.splitlines()
assert not any(l.startswith("  - *The chain, in this order") for l in ls), "the superseded chain bullet survives"
assert "supersedes the chain" not in t, "R3(i) still points at a chain bullet"
s3 = next(l for l in ls if l.startswith("- [ ] **Step 3: Implement (intent).** `signers.py` per Interfaces"))
assert "straight to TOFU" not in s3, s3[:300]
for w in ("R3(i)", "passed over", "anchor-off-main", "anchor-unverified", "strict ancestors"):
    assert w in s3, w
PY
# Build 2 final review (REQ-384, REQ-324; art-threat-driven-security; P6 R26): the architecture artifacts say what
# Build 2 made true — the residual's release-gate clause states R26's rule and its real residuals (the PR head's own
# hook, the constitution clause amendment C rewrites), a data-flow element records the PR-time release build
# (pr-head-to-ci; T: a forged manifest or rows), and the overview no longer calls verify-release.sh a one-clause filter.
# Covers: REQ-384
# Covers: REQ-324
relres=$(grep -F -- "- **Release gates run at PR time and are replayed at the tag**" "$TM" || true)
factory_doc_ck "threat model residual: CI builds the subset and never reads dist/; a tracked dist/ FAILs; the PR-head hook; amendment C's clause" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "builds the reproducible subset itself and compares it row for row (P6 R26)" "never reads \`dist/\`" "a tracked \`dist/\` FAILs" "\`scripts/release-<stack>.sh\`" "\`release_manifest.py\`" "read at the base ref" "amendment C"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "shape-only there until the CI-built manifest" <<<"$1" && ! grep -qF "true-but-stale" <<<"$1"' _ "$relres"
r14=$(row dfe-14)
factory_doc_ck "dfe-14: the PR-time release build (release-build.yml, the gates job's build), pr-head-to-ci, T forged manifest or rows" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "release-build.yml" "verify-release.sh" "pr-head-to-ci" "**T**" "forged" "dist/" "\`scripts/release-<stack>.sh\`" "contents: read" "P6"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$r14"
factory_doc_ck "dfe-14 is a declared external element with a STRIDE letter and is drawn in the data-flow diagram" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'grep -qE "^  - id: dfe-14$" "$1" && grep -qE "^  dfe-14: \[T" "$1" && grep -qF "\"dfe-14\"" "$1"' _ "$TM"
factory_doc_ck "the overview: verify-release.sh runs the stack's release hook to build what it compares (no one-clause filter)" \
  docs/architecture/2026-09-25-factory-v3-2-overview.md \
  bash -c '! grep -qF "\`check-covers.sh\`, \`verify-release.sh\`): one-clause filters over files" "$1" && grep -F "verify-release.sh" "$1" | grep -qF "\`scripts/release-<stack>.sh\`"' _ "$OV"
# PR #54 verifier run 1, finding 1 (REQ-384, REQ-324; art-threat-driven-security): CI reads the base by its full ref,
# refs/remotes/origin/<base> — a tag named origin/<base> would shadow the short name — and the local tools' short name is
# recorded as a convention residual, in dfe-6 (the policy reads) and dfe-14 (the release stack). The enumeration names
# release-tag.sh and run-verifier.sh's own origin/<base> reads too, and that both fail closed (re-review of fix wave 2).
# Covers: REQ-384
r6=$(row dfe-6)
# PR #54 verifier run 2, finding 3 (REQ-385, REQ-313; art-threat-driven-security): since P6 Build 3 the bootstrap is
# printed by the full ref and run-verifier.sh's own base reads use it; what keeps the short name (next.sh, a developer's
# own gates run, release-tag.sh — which fails closed) is a convention residual with an owner, and dfe-6 records the
# pre-fix exposure's provisional CVSS v4.0 vector as history.
# Covers: REQ-385
for id in dfe-6 dfe-14; do
  factory_doc_ck "$id: CI resolves the base by refs/remotes/origin/<base> since Build 2, the bootstrap and run-verifier.sh since Build 3; the rest of the local short name is an owned convention residual" \
    docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
    bash -c 'for w in "refs/remotes/origin/<base>" "a tag named \`origin/<base>\`" "since P6 Build 2" "since P6 Build 3" "\`git show refs/remotes/origin/<base>:scripts/run-verifier.sh | bash -s -- <PR>\`" "\`next.sh\`" "convention residual" "owner: kpingali123" "\`release-tag.sh\`" "fails closed"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "the bootstrap \`git show origin/<base>" <<<"$1" && ! grep -qF "both fail closed" <<<"$1"' _ "$(row "$id")"
done
factory_doc_ck "dfe-6 records the pre-fix bootstrap exposure as history with a provisional CVSS v4.0 vector and its band (cvss4.py)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'v="CVSS:4.0/AV:N/AC:L/AT:P/PR:L/UI:A/VC:H/VI:H/VA:H/SC:H/SI:H/SA:N"; grep -qF "\`$v\` (8.7, high" <<<"$1" && grep -qF "PR #54 verifier run 2, finding 3" <<<"$1" && grep -qF "history" <<<"$1" && [ "$(cd "$2" && python3 -c "import sys, cvss4; print(cvss4.score(sys.argv[1]), cvss4.finding_severity(sys.argv[1]))" "$v")" = "8.7 high" ]' _ "$(row dfe-6)" "$ROOT/scripts/lib/specflow"
factory_doc_ck "the P6 plan's Deferred: the bootstrap's short name is fixed in Build 3, not a proposed patch/ PR; what remains has an owner" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'b=$(grep -F -- "- **The local short-name base**" "$1"); for w in "since Build 3" "\`git show refs/remotes/origin/<base>:scripts/run-verifier.sh | bash -s -- <PR>\`" "owner: kpingali123" "\`release-tag.sh\`" "fails closed"; do grep -qF -- "$w" <<<"$b" || { echo "missing $w"; exit 1; }; done; ! grep -qF "proposed as a \`patch/\` PR" <<<"$b" && ! grep -qF "until then it is a convention residual" <<<"$b"' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
# PR #54 verifier run 1, findings 4, 6 and 7 (REQ-384, REQ-324): dfe-14 records SPECFLOW_RELEASE_BUILD (local-only,
# ignored in CI, and the $GITHUB_ENV route it closes), names packinfo.py among the PR-head code that runs, and its
# threats cross-reference dfe-5 for I and E (the job token and its permissions).
# Covers: REQ-384
# Covers: REQ-324
factory_doc_ck "dfe-14: SPECFLOW_RELEASE_BUILD is local-only and ignored in CI (the \$GITHUB_ENV route); packinfo.py runs from the PR head; I and E are dfe-5's" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "\`SPECFLOW_RELEASE_BUILD=0\`" "local-only" "\`\$GITHUB_ENV\`" "ignored in CI" "\`packinfo.py\`" "**I** and **E**" "dfe-5"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; grep -qF "Residual: the hook, \`release_manifest.py\` and \`packinfo.py\` run from the PR head" <<<"$1"' _ "$r14"
# PR #54 verifier run 2, finding 5 (REQ-384; art-review-gate): the rebase rule Builds 4 and 5 follow rebases onto the full
# ref, as /release's step 4 does — a planted tag named origin/main would otherwise choose the commit rebased onto.
# Covers: REQ-384
factory_doc_ck "the P6 plan's rebase rule rebases onto refs/remotes/origin/main, never the short name" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c '! grep -qF "git rebase origin/main" "$1" && grep -qF "git fetch origin && git rebase refs/remotes/origin/main" "$1"' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
# PR #54 verifier run 2, code-mode low (REQ-324, REQ-384): on a non-PR CI event (an empty SPECFLOW_BASE_REF) the release
# gates default to refs/remotes/origin/main when it exists, so "CI resolves that base by its full ref" holds there too;
# the P6 plan's R18 says the stub hook names its archive after origin's repository (schema 2 has no name field).
# Covers: REQ-384
factory_doc_ck "dfe-14: with no base given the gates default to refs/remotes/origin/main when it exists (P6 Build 3)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'grep -qF "with no base given (a non-PR event, where \`ci.yml\` passes \`SPECFLOW_BASE_REF\` empty) \`verify-release.sh\` and \`check-security-disposition.sh\` default to \`refs/remotes/origin/main\` when it exists since P6 Build 3" <<<"$1"' _ "$(row dfe-14)"
factory_doc_ck "the P6 plan's R18: the stub hook names its archive after remote.origin.url's repository; schema 2 has no name field" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'l=$(grep -F -- "- **R18 " "$1"); for w in "\`remote.origin.url\`" "\`specflow-factory\`" "no \`name\` field" "checkout directory"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
# PR #54 verifier run 2, finding 4 (REQ-383; art-threat-driven-security): dfe-12's accepted TOFU caveat records its
# provisional severity — a CVSS v4.0 base vector and its band, scored by scripts/lib/specflow/cvss4.py — and keeps its expiry.
# Covers: REQ-383
factory_doc_ck "dfe-12's TOFU caveat: a provisional CVSS v4.0 vector whose cvss4.py score and band are the ones quoted (5.6, medium); the expiry re-accepted" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'v="CVSS:4.0/AV:N/AC:L/AT:P/PR:H/UI:A/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N"; grep -qF "\`$v\` (5.6, medium" <<<"$1" && grep -qF "expires: 2027-01-31; re-dated 2026-10-05" <<<"$1" && grep -qF "from 2026-12-15; re-accepted — owner: kpingali123, the maintainer; sign-off: the merge of build/factory-v3-2-p7-1 (P7 Build 1); re-dating sign-off: the merge of patch/post-3-2-1-records (item 7'"'"'s re-dating patch); re-reviewed by the v3.2 retrospective'"'"'s decision on BL-023 (re-accepted by Build 3'"'"'s release.yml, REQ-350, R11)" <<<"$1" && [ "$(cd "$2" && python3 -c "import sys, cvss4; print(cvss4.score(sys.argv[1]), cvss4.finding_severity(sys.argv[1]))" "$v")" = "5.6 medium" ]' _ "$r12" "$ROOT/scripts/lib/specflow"
# PR #54 verifier run 2, findings 1, 2 and 6 (REQ-384, REQ-350; art-specification-primacy): the Builds 4/5 table is one
# table (the Build 2 note below it), the tolerated-set paragraph carves the interim-window edit out of its "neither
# build edits" and "only run" lists whichever build makes it, and the interim window has an owner, a due date and the
# P3 lapse rule, with init's warning in the second build's Files; the plan is re-verified at main 85ede15 for Build 3.
# Covers: REQ-384
factory_doc_ck "the P6 plan's Builds 4/5 table is contiguous (header to the implements: row), the Build 2 note below it" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md python3 - "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md" <<'PYT'
import sys
ls = open(sys.argv[1]).read().split("\n")
h = ls.index("| File | Build 4 | Build 5 |")
end = h
while end + 1 < len(ls) and ls[end + 1].startswith("|"):
    end += 1
rows = ls[h:end + 1]
assert any("threat-model.md" in r for r in rows) and any("(`implements:`)" in r for r in rows), rows[-3:]
note = next(i for i, l in enumerate(ls) if l.startswith("*Not in the table"))
assert note > end, (note, end)
PYT
factory_doc_ck "the P6 plan's tolerated-set paragraph: the interim-window edit, by whichever build merges second, is carved out of 'neither build edits' and 'only run'" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'p=$(grep -F "The intersection is \`README.md\`" "$1"); for w in "**the interim-window edit**" "whichever of Builds 4 and 5 merges second" "Apart from the interim-window edit, neither build edits" "apart from the interim-window edit, of the test files" "are otherwise only run" "\`init-project.sh\`'"'"'s next-steps warning" "\`test_init.sh\`"; do grep -qF -- "$w" <<<"$p" || { echo "missing $w"; exit 1; }; done; ! grep -qF "by Build 5 alone" <<<"$p"' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
factory_doc_ck "the P6 plan's interim window (Partial claims and Deferred): owner kpingali123 is the control, due 2026-10-12, no gate checks the date, init's warning (PR #56 run 1, finding 3)" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'for k in "- **The interim window (Build 2" "- **The interim window** (Partial"; do l=$(grep -F -- "$k" "$1"); ! grep -qF "severity high" <<<"$l" || { echo "$k: still severity high"; exit 1; }; for w in "owner: kpingali123" "due 2026-10-12" "the owner (kpingali123) is the control" "no gate checks the date" "a lapse is recorded in the next ship PR'"'"'s known-limitations" "\`init-project.sh\`"; do grep -qF -- "$w" <<<"$l" || { echo "$k: missing $w"; exit 1; }; done; done' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
factory_doc_ck "Tasks 4.1 and 5.1's Files name the interim-window edit's init warning and test_init.sh" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md python3 - "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md" <<'PYT'
import sys
t = open(sys.argv[1]).read()
for task in ("### Task 4.1:", "### Task 5.1:"):
    s = t[t.index(task):]
    files = next(l for l in s.split("\n") if l.startswith("**Files:**"))
    for w in ("`scripts/init-project.sh`", "`tests/governance/test_init.sh`"):
        assert w in files, (task, w)
PYT
factory_doc_ck "the P6 plan's Verified against: a Build 3 line at main 85ede15" docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  grep -qF -- "- **Build 3, re-verified at main \`85ede15\`**" "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"

# P6 Task 3.6 (REQ-350, REQ-383, REQ-334; P6 R8, R11): the threat model and the overview say what Builds 1–3 delivered.
# Covers: REQ-350
ck "dfe-4 is delivered in P4, P6 (release.yml's job-level elevation)" \
  bash -c 'grep -qE "\| P4, P6 \|$" <<<"$1" && ! grep -qF "release.yml elevation: P6" <<<"$1"' _ "$(row dfe-4)"
ck "dfe-12: the anchor rule, the principal bound to the tagger, the ruleset; delivered in P6" \
  bash -c 'for w in "previous release'"'"'s tag" "trust on first use" "tagger" "signers.py" "release tags"; do grep -qF "$w" <<<"$1" || exit 1; done; ! grep -qF "previous signed tag" <<<"$1" && grep -qE "\| P6 \|$" <<<"$1"' _ "$(row dfe-12)"
ck "dfe-13: release-check applies the same rule at the tag; its residual no longer expires at P6" \
  bash -c 'grep -qF "release-check" <<<"$1" && ! grep -qF "expires: P6" <<<"$1"' _ "$(row dfe-13)"
ck "dfe-12: the anchor is the previous release's tag on a first-parent commit, itself verified; revocation; the TOFU caveat" \
  bash -c 'for w in "first-parent" "revoked_signers" "TOFU"; do grep -qF "$w" <<<"$1" || exit 1; done' _ "$(row dfe-12)"
ck "a residual: release.yml binds only tags on reviewed commits; the ruleset and the offline-verifiable signed tag are the controls (R31)" \
  bash -c 'grep -qF "release.yml\` binds only tags on reviewed commits" "$1" && grep -qF "Verify this release" "$1" && grep -qF "a workflow that is not \`main\`'"'"'s" "$1"' _ "$TM"
ck "the release-gates residual: replayed at the tag; no 'until P6' left in the threat model" \
  bash -c 'grep -qF "Release gates run at PR time and are replayed at the tag" "$1" && ! grep -qF "until P6" "$1"' _ "$TM"
ck "the release-gates residual: the replay's run date is bounded by the tagged commit's committer date; a tag backdated within that bound is the residual (PR #52 run 1, finding 5)" \
  bash -c 'l=$(grep -F "Release gates run at PR time and are replayed at the tag" "$1"); grep -qF "the later of the tagger date and the tagged commit'"'"'s committer date" <<<"$l" && grep -qF "backdate" <<<"$l"' _ "$TM"
ck "the overview: what P6 created and extended, and that no kernel module changed" \
  bash -c 'grep -qE "P6 created .*signers\.py.*release_manifest\.py.*release\.yml" "$1" && grep -qF "no kernel module changed" "$1"' _ "$OV"
# Covers: REQ-334
ck "dfe-13: the residual is re-accepted with an owner and a sign-off; the narrative says P6 was delivered by Builds 1-3" \
  bash -c 'grep -qF "Residual (**S**, re-accepted — owner: kpingali123, the maintainer; sign-off: PR #56'"'"'s merge (Build 3; P6 R11" <<<"$1" && grep -qF "dfe-12, dfe-13'"'"'s tag-time re-check) was delivered by Builds 1–3" "$2"' _ "$(row dfe-13)" "$TM"
ck "the residual for R28's boundary: attestation_since, pre-transfer, an instance judges every merge" \
  bash -c 'grep -qF "attestation_since" "$1" && grep -qF "pre-transfer" "$1" && grep -qF "an instance whose pack carries the key is refused (exit 2)" "$1"' _ "$TM"
# Build 3 final review (REQ-350; findings 5, 6, 7, 8, 19, 20): the residuals say what is enforced and what remains, each
# remaining risk with an owner, a sign-off, an expiry and a provisional CVSS v4.0 vector.
# Covers: REQ-350
factory_doc_ck "dfe-12's Boundary residual: introduced once and never moved (exit 2); the introducing PR can be the ship PR; owner, sign-off, expiry, CVSS" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'b=${1#*\*\*Boundary residual\*\*}; for w in "introduced once and never moves" "the ship PR itself" "owner: kpingali123" "sign-off: PR #56'"'"'s merge (Build 3)" "expires: 2026-12-15" "CVSS:4.0/AV:N/AC:L/AT:P/PR:H/UI:A/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N"; do grep -qF "$w" <<<"$b" || { echo "missing $w"; exit 1; }; done; ! grep -qF "moves only forward by review" <<<"$b"' _ "$(row dfe-12)"
factory_doc_ck "the release-gates residual: release.yml replays gates section 7 only, names the sections it does not replay, reads the base-side inputs at the tag's parent and tags only the notes-adding merge" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F "Release gates run at PR time and are replayed at the tag" "$1"); for w in "what gates section 7 would have" "not replayed" "the tagged commit'"'"'s first parent" "the newest first-parent commit of \`main\` that added"; do grep -qF "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done; ! grep -qF "refuses at the tag what the PR-time gate would have" <<<"$l"' _ "$TM"
# PR #56 verifier run 1, finding 5 (REQ-350; art-threat-driven-security): the 6.9 is computed by cvss4.py, as the 8.7
# and 5.6 are, and the expiry is a date.
factory_doc_ck "the release.yml residual: an admin bypasses the ruleset, and the re-check runs the tagged commit's own code (circular for a direct push); owner, sign-off, dated expiry, CVSS (cvss4.py: 6.9, medium)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F "binds only tags on reviewed commits" "$1"); v="CVSS:4.0/AV:N/AC:L/AT:N/PR:H/UI:N/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N"; for w in "an admin can bypass it" "the tagged commit'"'"'s own" "owner: kpingali123" "sign-off: PR #56'"'"'s merge (Build 3)" "expires: 2027-01-31; re-dated 2026-10-05" "\`$v\` (6.9, medium"; do grep -qF "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done; [ "$(cd "$2" && python3 -c "import sys, cvss4; print(cvss4.score(sys.argv[1]), cvss4.finding_severity(sys.argv[1]))" "$v")" = "6.9 medium" ]' _ "$TM" "$ROOT/scripts/lib/specflow"

# Build 3 final review (REQ-350; findings 6, 7, 8, 11, 13, 14, 15, 17, 19, 20): the P6 plan's rulings carry the corrections.
# Covers: REQ-350
factory_doc_ck "the P6 plan: R28 (published-Release range, content tie, minor exception, attestation-missing, never moves), R29 (three REQ bodies), R30 (gates section 7 only), R31 (admin bypass), REQ-385's Not-claimed reason" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md python3 - "$P6P" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
def rule(n):
    m = re.search(r"(?m)^- \*\*R%d — .*$" % n, t); assert m, n; return m.group(0)
r28, r29, r30, r31 = rule(28), rule(29), rule(30), rule(31)
for w in ("published GitHub Release", "merge-content-mismatch", "minor exception", "phase artifact", "attestation-missing", "never moves", "the ship PR itself"):
    assert w in r28, ("R28", w)
assert "moves only forward by review" not in r28 and "lists no code path (the doc-only minor exception)" not in r28, "R28 old wording"
assert "Exactly one does" not in r29 and "REQ-384" in r29 and "REQ-385" in r29, "R29"
assert "gates section 7" in r30 and "whose required `gates` run already passed" not in r30, "R30"
assert "an admin can bypass it" in r31, "R31"
nc = re.search(r"(?m)^- \*\*Not claimed, with the reason:\*\*.*$", t).group(0)
assert "REQ-385 — the verifier instruction and the merge command are unchanged" not in nc, "Not claimed"
PY
# Fix wave 1, L and G (REQ-350, REQ-383; P6 R28, R30, R31): dfe-12 and dfe-14 say a reviewed ship PR that edits
# release.yml, attestation.py or template-pack.yml is bound only by that PR's review, and that a consumer can check the
# tag with the Release body's verify command or main's own copy of the checks; dfe-14 carries no "from Build 3 on"; the
# release-gates residual reads the stack at the tag's tree and the documents only from the tag's tree.
# Covers: REQ-350
for id in dfe-12 dfe-14; do
  factory_doc_ck "$id: a reviewed ship PR editing release.yml, attestation.py or template-pack.yml is bound only by that PR's review; the Release body's verify command and main's copy" \
    docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
    bash -c 'for w in "\`release.yml\`, \`attestation.py\` and \`scripts/template-pack.yml\`" "bound only by that PR'"'"'s own review" "Release body'"'"'s verify command" "\`main\`'"'"'s own copy of the checks"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "from Build 3 on" <<<"$1"' _ "$(row "$id")"
done
factory_doc_ck "the release-gates residual: the app-stack rule's stack at the tag's tree; the documents only from the tag's tree (git status --porcelain)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F "Release gates run at PR time and are replayed at the tag" "$1"); grep -qF "the app-stack rule'"'"'s stack at the tag'"'"'s tree" <<<"$l" && grep -qF "\`git status --porcelain\` empty" <<<"$l"' _ "$TM"
# PR #56 verifier run 1, finding 4 (REQ-383; art-threat-driven-security): release-tag.sh passes the full
# refs/remotes/<remote>/main to signers.py and release-check, so dfe-6, dfe-14 and the plan's Deferred list only the reads
# that keep the short name.
# Covers: REQ-383
for id in dfe-6 dfe-14; do
  factory_doc_ck "$id: release-tag.sh's short-name reads are exactly its HEAD check, choice of M, docs comparison, recorded-fallback read and next: line" \
    docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
    bash -c 'grep -qF "reads the short \`<remote>/main\` only for its HEAD check, the choice of \`M\`, the docs comparison, the recorded-fallback read and the advisory \`next:\` line — its \`signers.py\` and \`release-check\` calls take the full \`refs/remotes/<remote>/main\`" <<<"$1" && ! grep -qF "the recorded fallback and \`signers.py --base-ref\`" <<<"$1"' _ "$(row "$id")"
done
factory_doc_ck "the P6 plan's Deferred short-name base: release-tag.sh's short-name reads only; signers.py and release-check take the full ref" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'l=$(grep -F -- "- **The local short-name base**" "$1"); grep -qF "the choice of \`M\`" <<<"$l" && grep -qF "its \`signers.py\` and \`release-check\` calls take the full \`refs/remotes/<remote>/main\`" <<<"$l" && ! grep -qF "\`fallback_recorded\` and \`signers.py --base-ref\`" <<<"$l"' _ "$P6P"
# PR #56 verifier run 1, finding 5 (REQ-350; art-threat-driven-security): every P6 residual's expiry is a date, never an
# event — the short-name convention residual (dfe-6, dfe-14) included.
# Covers: REQ-350
factory_doc_ck "the threat model: no residual expires at an event ('expires: the P7 retrospective'); the short-name residual expires 2027-01-31 (P7 R9; re-dated 2026-10-05 to the 3.2.1 disposition's date)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c '! grep -qF "expires: the P7 retrospective" "$1" && ! grep -qF "maintainer; the P7 retrospective reviews it)" "$1" && for id in dfe-6 dfe-14; do grep -F "| $id |" "$1" | grep -qF "a convention residual (owner: kpingali123, the maintainer; expires: 2027-01-31; re-dated 2026-10-05" || exit 1; done' _ "$TM"
# PR #56 verifier run 1, finding 6 (REQ-350, REQ-383, REQ-390; art-kernel-boundary): release.yml publishes with write
# permissions and release-tag.sh signs and pushes — not one-clause filters over files; the overview gives them a sentence
# of their own, and says no kernel module changed.
# Covers: REQ-350
factory_doc_ck "the overview: release.yml, release-tag.sh, release-smoke.sh, signers.py and release_manifest.py in a sentence of their own (REQ-350, REQ-383, REQ-390), not among the one-clause filters" \
  docs/architecture/2026-09-25-factory-v3-2-overview.md \
  bash -c 'f=$(grep -F -- "- **Every other v3.2 script**" "$1"); ! grep -qE "release\.yml|release-tag\.sh|release-smoke\.sh|signers\.py|release_manifest\.py" <<<"$f" || { echo "still among the filters"; exit 1; }; p=$(grep -F -- "- **P6'"'"'s release path**" "$1"); for w in "\`release.yml\`" "\`release-tag.sh\`" "\`release-smoke.sh\`" "\`signers.py\`" "\`release_manifest.py\`" "write permissions" "signs and pushes" "REQ-350" "REQ-383" "REQ-390" "no kernel module changed"; do grep -qF -- "$w" <<<"$p" || { echo "missing $w"; exit 1; }; done' _ "$OV"
# PR #57 fix wave 1, item 6 (REQ-351; art-threat-driven-security): the GHCR residual carries an owner, a sign-off, a dated
# expiry and a provisional CVSS v4.0 vector whose score cvss4.py computes, as the other P6 residuals; it and dfe-5 name the
# first-release measurement gap — the job token's answer for a never-pushed package is unmeasured, so a first release
# reads nothing from the registry before its push, and the first real push is the measurement.
# Covers: REQ-351
factory_doc_ck "the GHCR residual: unmeasured until the first real push; owner, sign-off PR #57's merge, expiry 2027-01-31 (P7 R9; re-dated to the 3.2.1 disposition's), CVSS as cvss4.py scores it" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" "$ROOT/scripts/lib/specflow" <<'PYG'
import sys
sys.path.insert(0, sys.argv[2]); import cvss4
L = [l for l in open(sys.argv[1]).read().splitlines() if l.startswith("- **")]
g = next(l for l in L if l.startswith("- **GHCR is proved only by an instance's ship**"))
v = "CVSS:4.0/AV:N/AC:H/AT:P/PR:H/UI:N/VC:N/VI:L/VA:L/SC:N/SI:N/SA:N"
for w in ("never pushed", "the first real push is the measurement", "`github.sha`", "owner: kpingali123", "sign-off: PR #57's merge",
          "expires: 2027-01-31; re-dated 2026-10-05 by the post-3.2.1 records patch to the 3.2.1 disposition's date (`docs/security/3.2.1-disposition.md`), from 2026-12-15; re-accepted", f"`{v}` ({cvss4.score(v)}, {cvss4.finding_severity(v)}"):
    assert w in g, w
PYG
factory_doc_ck "dfe-5 names the first-release measurement gap: the anonymous 403 measured, the job token's answer unmeasured, no registry read before a first release's push" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "403 Forbidden" "measured 2026-10-02" "unmeasured" "a first release" "reads nothing from the registry before its push" "the first real push is the measurement"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$(row dfe-5)"
# The second-to-merge fold (P6 R35; PR #57 verifier run 1, findings 4 and 5; PR #58 verifier run 1, finding 3):
# every P6 residual names its sign-off one way — "sign-off: PR #<n>'s merge (Build <N>…" — never "Build <N>'s merge";
# Build 5's three residuals carry an owner, a sign-off, a dated expiry and a provisional CVSS v4.0 vector that cvss4.py
# scores; deploy-local.sh's replace-before-start is a recorded residual (start-then-swap does not fit the contract: a
# DEPLOY_RUN_ARGS-published host port cannot be bound by two containers at once).
# Covers: REQ-352
# Covers: REQ-351
factory_doc_ck "P6 residuals: one sign-off form, 'sign-off: PR #<n>'s merge (Build <N>' — never 'sign-off: Build <N>'s merge'" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" <<'PYS'
import re, sys
t = open(sys.argv[1]).read()
assert not re.search(r"sign-off: Build \d", t), re.findall(r".{60}sign-off: Build \d.{20}", t)
for b in ("Boundary residual", "binds only tags on reviewed commits", "re-pinned by hand", "deploy contract's test runs",
          "The python image runs as a non-root user", "GHCR is proved only", "Apple secrets need the", "restores the package registries",
          "signed path is exercised only by stubs", "replaces the running container before"):
    l = next(x for x in t.splitlines() if b in x)
    seg = l[l.index(b):] if b == "Boundary residual" else l
    assert re.search(r"sign-off: PR #5[678]'s merge \(Build [345]", seg), b
PYS
factory_doc_ck "Build 5's three residuals: owner, sign-off PR #58's merge (Build 5), expiry 2027-01-31 (P7 R9; re-dated to the 3.2.1 disposition's), a CVSS v4.0 vector as cvss4.py scores it" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" "$ROOT/scripts/lib/specflow" <<'PYB'
import sys
sys.path.insert(0, sys.argv[2]); import cvss4
L = [l for l in open(sys.argv[1]).read().splitlines() if l.startswith("- **")]
for head, v in (("- **The Apple secrets need the `release` environment**", "CVSS:4.0/AV:L/AC:H/AT:P/PR:H/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N"),
                ("- **The app bundle restores the package registries from a cache**", "CVSS:4.0/AV:N/AC:H/AT:P/PR:H/UI:N/VC:N/VI:H/VA:N/SC:N/SI:L/SA:N"),
                ("- **The signed path is exercised only by stubs until an instance ships**", "CVSS:4.0/AV:N/AC:H/AT:P/PR:H/UI:N/VC:N/VI:L/VA:L/SC:N/SI:N/SA:N")):
    l = next(x for x in L if x.startswith(head))
    for w in ("owner: kpingali123", "sign-off: PR #58's merge (Build 5)", "expires: 2027-01-31; re-dated 2026-10-05 by the post-3.2.1 records patch to the 3.2.1 disposition's date (`docs/security/3.2.1-disposition.md`), from 2026-12-15; re-accepted",
              "severity provisional", f"`{v}` ({cvss4.score(v)}, {cvss4.finding_severity(v)}"):
        assert w in l, (head, w)
    assert l.rstrip().endswith("."), head
PYB
factory_doc_ck "deploy-local.sh's replace-before-start is a residual: owner, sign-off, dated expiry, CVSS; the recovery is deploy <older version> by hand" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" "$ROOT/scripts/lib/specflow" <<'PYD'
import sys
sys.path.insert(0, sys.argv[2]); import cvss4
l = next(x for x in open(sys.argv[1]).read().splitlines() if x.startswith("- **`deploy-local.sh` replaces the running container before the new one starts**"))
v = "CVSS:4.0/AV:L/AC:L/AT:P/PR:H/UI:N/VC:N/VI:N/VA:L/SC:N/SI:N/SA:N"
for w in ("docker rm -f", "start-then-swap", "DEPLOY_RUN_ARGS", "rollback", "deploy <older version>", "owner: kpingali123",
          "sign-off: PR #58's merge (Build 5)", "expires: 2027-01-31; re-dated 2026-10-05 by the post-3.2.1 records patch to the 3.2.1 disposition's date (`docs/security/3.2.1-disposition.md`), from 2026-12-15", f"`{v}` ({cvss4.score(v)}, {cvss4.finding_severity(v)}"):
    assert w in l, w
PYD
# The interim window closed with the second of Builds 4 and 5 (Build 5, PR #58, 2026-10-03; R35's interim-window edit):
# the plan's interim-window rows say so, owner kpingali123 (PR #57 and #58's verifier runs, the fold of R35).
# Covers: REQ-352
factory_doc_ck "the P6 plan's interim-window rows: closed on 2026-10-03 when Build 5 (PR #58), the second of Builds 4 and 5, merged; owner kpingali123" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'for k in "- **The interim window (Build 2" "- **The interim window** (Partial"; do l=$(grep -F -- "$k" "$1"); for w in "Closed on 2026-10-03" "the second of Builds 4 and 5 to merge" "PR #58" "owner: kpingali123" "removed README"; do grep -qF -- "$w" <<<"$l" || { echo "$k: missing $w"; exit 1; }; done; done' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
# PR #58 verifier run 1, finding 1 (REQ-386; art-specification-primacy): the plan's "neither build changes" sentences
# name the footnote's exception, and release-publish.sh's Interfaces entry lists assemble's provenance flags. PR #57
# verifier run 1, finding 3 (REQ-390): the release-smoke.sh python Interfaces line carries R19's flags and the overrun
# kill. PR #58 verifier run 1, finding 2 (REQ-386): R33's signing steps name the entitlements' first source.
# Covers: REQ-386
# Covers: REQ-390
factory_doc_ck "the P6 plan: the 'neither build edits' paragraph and release-publish.sh's Interfaces name Build 5's sanctioned fix-wave-1 exception and --signed-bundle|--unsigned-bundle" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md python3 - "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md" <<'PYP'
import sys
t = open(sys.argv[1]).read().splitlines()
para = next(l for l in t if l.startswith("The intersection is `README.md`"))
assert "except Build 5's fix wave 1 in `release-publish.sh` and `release_manifest.py`" in para, para[-400:]
pub = next(l for l in t if l.startswith("**`scripts/release-publish.sh --version"))
assert "Builds 4 and 5 never change it" not in pub, "still never"
for w in ("Build 5's fix wave 1", "--signed-bundle", "--unsigned-bundle", "R33"):
    assert w in pub, w
c = next(l for l in t if l.startswith("# The parts (F22; R35"))
assert "never change release-publish.sh" not in c or "fix wave 1" in c, c
PYP
factory_doc_ck "the P6 plan's release-smoke.sh Interfaces: python runs docker run --network none --pull never --name <container>, docker kill on overrun (R19)" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'l=$(grep -F "**\`scripts/release-smoke.sh --stack <s>" "$1"); for w in "docker run --network none --pull never --name <container> --rm -e SPECFLOW_SMOKE=1 <image>" "docker kill <container>" "R19"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done; ! grep -qF "python — \`docker run --rm -e SPECFLOW_SMOKE=1 <image>\`" <<<"$l"' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
factory_doc_ck "the P6 plan's R33: the app is signed with its own entitlements first (codesign -d --entitlements :-), else the project's file, else the pack's" \
  docs/plans/2026-10-01-factory-v3-2-p6-plan.md \
  bash -c 'l=$(grep -F -- "- **R33 — signing is a script" "$1"); grep -qF -- "--entitlements <the app'"'"'s own entitlements (those its unsigned build embedded, \`codesign -d --entitlements :-\`), else the project'"'"'s file, else the pack'"'"'s>" <<<"$l" && ! grep -qF -- "--entitlements <the pack'"'"'s entitlements file>" <<<"$l"' _ "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
# SEC-004 (high, CVSS 7.0; dfe-9, dfe-10; REQ-385, REQ-313): the 3.2.0 security review's back-edge. dfe-9's bootstrap is
# main's reviewed copy for every PR, executing only main's code; dfe-10 names the stacked base as never executed; P5 R22's
# residual is recorded as fixed by the back-edge (build/sec-SEC-004), the ship PR's merge the sign-off.
# Covers: REQ-385
# Covers: REQ-313
factory_doc_ck "dfe-9: the bootstrap is main's reviewed copy for every PR, main's code alone executes, the base supplies data (SEC-004)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "\`git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>\`" "for every PR, stacked or not" "SEC-004" "build/sec-SEC-004" "\`attestation.py\`" "data"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "origin/<base>:scripts/run-verifier" <<<"$1"' _ "$(row dfe-9)"
factory_doc_ck "dfe-10: a stacked PR's unreviewed base is never executed by the verifier bootstrap (SEC-004)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "SEC-004" "stacked" "never executed"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$(row dfe-10)"
factory_doc_ck "the P5 R22 residual is fixed by the SEC-004 back-edge, the ship PR's merge its sign-off" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "- **A stacked PR'"'"'s verifier instruction" "$1"); for w in "(P5 R22)" "fixed by the SEC-004 back-edge" "build/sec-SEC-004" "sign-off: the ship PR'"'"'s merge" "\`git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>\`" "the base PR #<n> is unreviewed; its diff is reviewed by its own PR"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done; ! grep -qF "asks the maintainer to read the script first" <<<"$l"' _ "$TM"
# SEC-004 review round 2, finding 2: the R22 residual's 'What stays' names both merges — a squash merge of the base PR
# makes the stacked marker base-mismatch and the PR is reviewed again; the merge-commit merge /next prints leaves the
# merge base unchanged, so the marker survives the retarget and the base content that steered it is the base PR's, which
# that PR's own review covered before its merge. It never claims every retarget re-reviews the stacked PR.
factory_doc_ck "the P5 R22 residual's 'What stays' names both merges: squash re-reviews, the merge commit /next prints keeps the marker (SEC-004 round 2)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "- **A stacked PR'"'"'s verifier instruction" "$1"); for w in "After a squash merge of the base PR" "makes the marker \`base-mismatch\`" "the merge-commit merge \`/next\` prints" "the merge base is unchanged, so the marker survives the retarget" "reviewed by the base PR before its merge" "an earlier state"; do grep -qF -- "$w" <<<"$l" || { echo "missing $w"; exit 1; }; done; ! grep -qF "a retarget to \`main\` makes it \`base-mismatch\`, so the PR is reviewed again" <<<"$l"' _ "$TM"
for id in dfe-6 dfe-14; do
  factory_doc_ck "$id: since the SEC-004 back-edge the bootstrap names main for every PR (its Build 3 history kept)" \
    docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
    bash -c 'grep -qF "since the SEC-004 back-edge" <<<"$1" && grep -qF "\`git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>\`" <<<"$1"' _ "$(row "$id")"
done
# SEC-004 re-review, minor (REQ-385; dfe-10, dfe-2): on a stacked PR CI's verifier job runs the base's own attestation.py,
# so the bootstrap hint printed in its log is the unreviewed base's text. dfe-10 records it as a residual beside the fix:
# owner, sign-off, expiry, a provisional CVSS v4.0 vector scored through cvss4.py, and the never-copy-from-a-log mitigation.
# Covers: REQ-385
factory_doc_ck "dfe-10: a stacked PR's CI log bootstrap line is the unreviewed base's — a residual with owner, sign-off, expiry, CVSS and the never-copy mitigation (SEC-004 re-review)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" "$ROOT/scripts/lib/specflow" <<'PYS'
import sys
sys.path.insert(0, sys.argv[2]); import cvss4
l = next(x for x in open(sys.argv[1]).read().splitlines() if x.startswith("| dfe-10 |"))
r = l[l.index("Residual (the SEC-004 back-edge's re-review)"):]
v = "CVSS:4.0/AV:N/AC:L/AT:P/PR:L/UI:A/VC:N/VI:L/VA:N/SC:H/SI:H/SA:H"
assert cvss4.score(v) < cvss4.score("CVSS:4.0/AV:L/AC:L/AT:P/PR:L/UI:A/VC:H/VI:H/VA:H/SC:H/SI:H/SA:N"), "not below SEC-004"
for w in ("stacked", "base's own `attestation.py`", "CI log", "pipe-to-bash", "documented and `/next`-rendered bootstraps",
          "never copy the bootstrap from a CI log; use the rendered line", "`review-gate.md` step 3", "glossary",
          "owner: kpingali123", "sign-off: the ship PR's merge", "expires: 2027-01-31; re-dated 2026-10-05 by the post-3.2.1 records patch to the 3.2.1 disposition's date (`docs/security/3.2.1-disposition.md`), from 2026-12-15", "severity provisional",
          f"`{v}` ({cvss4.score(v)}, {cvss4.finding_severity(v)}"):
    assert w in r, w
PYS
# P7 Build 1 final review (finding 5; SEC-020; REQ-385): dfe-10 says the stacked base's text is printed with each \r a
# space, inside a ::stop-commands:: pair, and that this covers the text the classifier prints, not its code.
# Covers: REQ-385
factory_doc_ck "dfe-10: the base's classifier text has each carriage return a space and sits inside a stop-commands pair; its code can still reach the log" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "carriage return" "\`::stop-commands::\`" "the text it prints" "its code runs in the job"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$(row dfe-10)"
# Amendment C (REQ-353; P6 R10): dfe-14 and the release-gates residual say art-release-readiness states the CI
# comparison and the tag-time replay as settled text, no longer a true-but-stale clause amendment C rewrites.
# Covers: REQ-353
factory_doc_ck "dfe-14 and the release-gates residual: art-release-readiness states the CI comparison and the replay as settled text (amendment C)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for l in "$(grep -F "| dfe-14 |" "$1")" "$(grep -F -- "- **Release gates run at PR time and are replayed at the tag**" "$1")"; do grep -qF "settled text (amendment C, REQ-353)" <<<"$l" && ! grep -qF "amendment C (P7, REQ-353) rewrites" <<<"$l" || exit 1; done' _ "$TM"
# P7 Build 1 corrections (SEC-020; PR #61 run 1, code-mode low; REQ-385, REQ-313): dfe-10 records that verifier.yml now
# prints the fixed bootstrap line itself and labels a stacked base's classifier output, and the prompt_sha256 residual:
# the marker's prompt hash comes from main's attestation.py while a stacked PR's CI judges with the base's, so a base that
# changes the hashing fails closed (a mismatch), never open.
# Covers: REQ-385
# Covers: REQ-313
factory_doc_ck "dfe-10: verifier.yml prints the bootstrap line itself (SEC-020), and the prompt_sha256 residual fails closed" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "SEC-020" "prints the fixed bootstrap line itself" "labels the base'"'"'s classifier output" "defangs workflow commands" "Residual (prompt hash)" "prompt-hash --ref <base>" "a base that changes the hashing fails closed" "prompt-mismatch"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$(row dfe-10)"
# P7 Build 1 fix wave 1, FIX 4 (REQ-385, REQ-351; art-threat-driven-security): the records claim no more than holds. In
# solo mode no second reviewer confirmed the python image residual's severity; and verifier.yml's fixed line does not
# take the hint out of the stacked base's hands — the base's text is still printed beside it — while on the bootstrap
# path the PR head's own classifier text is labelled the same way and the fixed line names the --bootstrap route.
# Covers: REQ-385
factory_doc_ck "dfe-10's SEC-020 update: the stacked base's text is still printed, labelled, beside the fixed line; the bootstrap path labels the head's text and names --bootstrap" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for w in "the stacked base'"'"'s own text is still printed — labelled, indented, inside the stop-commands pair — beside the fixed line" "on the bootstrap path the PR head'"'"'s own classifier text is labelled and defanged the same way" "the fixed line names the \`--bootstrap\` route"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "no longer the base'"'"'s to choose" <<<"$1"' _ "$(row dfe-10)"
# Covers: REQ-351
factory_doc_ck "the python image residual: severity provisional, confirmed by no one yet (solo mode), never 'until a second reviewer confirmed it'" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F "**The python image runs as a non-root user from a hash-pinned runtime lock**" "$1"); grep -qF "severity provisional, confirmed by no one yet (solo mode" <<<"$l" && ! grep -qF "until a second reviewer confirmed it" <<<"$l"' _ "$TM"
# P7 R9 (REQ-350, REQ-334; H6): no residual of the threat model expires on or before 2026-10-12; every re-accepted one
# names its owner, P7 Build 1's merge as sign-off, 2026-12-15 and its backlog id — an id docs/BACKLOG.md lists — or, where
# no backlog entry covers it yet, the P7 retrospective's reference (fix wave 1, FIX 2); the closed ones say so. The
# residuals pinned here are the tag-time re-check's (dfe-12, REQ-350) and the Dependabot exemption's (dfe-13, REQ-334).
# Covers: REQ-350
# Covers: REQ-334
factory_doc_ck "the threat model: no 'expires: 2026-10-12' is left; each P7 re-acceptance names owner, sign-off, 2026-12-15 and a BL id docs/BACKLOG.md lists, or the retrospective's reference" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" "$ROOT/scripts/lib/specflow" "$ROOT/docs/BACKLOG.md" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[2]); import cvss4
t = open(sys.argv[1]).read()
bl = set(re.findall(r"^### (BL-\d{3}) ", open(sys.argv[3]).read(), re.M))
assert "expires: 2026-10-12" not in t, "an expiry of 2026-10-12 is left"
RETRO = "the P7 retrospective (plan Build 1, Deferred corrections)"
RD = "2027-01-31; re-dated 2026-10-05 by the post-3.2.1 records patch to the 3.2.1 disposition's date (`docs/security/3.2.1-disposition.md`), from 2026-12-15"
ra = re.findall(r"expires: (?:2026-12-15|" + re.escape(RD) + "); re-accepted — owner: kpingali123, the maintainer; sign-off: the merge of build/factory-v3-2-p7-1 \(P7 Build 1\)(?:; re-dating sign-off: the merge of patch/post-3-2-1-records \(item 7's re-dating patch\))?; re-reviewed by (?:the v3\.2 retrospective's decision on (BL-\d{3})|" + re.escape(RETRO) + ")", t)
assert len(ra) >= 13, ra
for b in ra:
    assert b == "" or b in bl, f"{b} is not listed in docs/BACKLOG.md"
# fix wave 1, FIX 2: BL-028 is the wrong-branch guard and BL-023 the forged-anchor residual — neither is dfe-10's CI-log
# hint nor dfe-12's attestation_since boundary, which wait for backlog entries the retrospective lists.
dfe10 = next(l for l in t.splitlines() if l.startswith("| dfe-10 |"))
assert "BL-028" not in dfe10 and RETRO in dfe10, "dfe-10's residual cites the retrospective's reference, never BL-028"
dfe12 = next(l for l in t.splitlines() if l.startswith("| dfe-12 |"))
boundary = dfe12[dfe12.index("**Boundary residual**"):dfe12.index("**Tagged-tree residual**")]
assert "BL-023" not in boundary and RETRO in boundary, "dfe-12's Boundary residual cites the retrospective's reference, never BL-023"
tofu = dfe12[dfe12.index("**TOFU caveat**"):dfe12.index("**GPG residual**")]
assert "decision on BL-023" in tofu, "the TOFU caveat (the forged-anchor residual) keeps BL-023"
tagged = next(l for l in t.splitlines() if "**Tagged-tree residual**" in l)
seg = tagged[tagged.index("**Tagged-tree residual**"):]
assert "decision on BL-013" in seg[: seg.index("): ") + 3], "the Tagged-tree residual carries its own re-acceptance, BL-013"
assert not re.search(r"sign-off: PR #\d+'s merge \(P7", t), "a P7 sign-off names the branch, never a PR number"
for v in re.findall(r"`(CVSS:4\.0/[^`]+)` \(([\d.]+), (\w+)", t):
    assert f"{cvss4.score(v[0])}" == v[1] and cvss4.finding_severity(v[0]) == v[2], v
for k in ("closed by P7 Build 1", "BL-007", "BL-009", "BL-013", "BL-014", "BL-015", "BL-016", "BL-017", "BL-018", "BL-023"):
    assert k in t, k
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
ck "threat model, the legacy-waiver residual: M0b dated 2026-10-04 UTC, measured under pull_request; the tag-time read unmeasured, owned, with R4's recovery and the pre-ship check" m0b_precise "$TM" "- **A legacy waiver is bound to a head, not a base**"
# The post-3.2.1 records patch (patch/post-3-2-1-records, 2026-10-05; REQ-382, REQ-322, BL-022; the retrospective's
# Proposed Changes item 7, D18): the 3.2.1 disposition re-accepted every carried residual to 2027-01-31 (ADR-002 rule 5),
# so each threat-model record of a residual it re-accepted is re-dated to that date, its old date kept as history; the
# Boundary residual (SEC-008's closed half, BL-038), which the disposition did not re-accept, keeps 2026-12-15. dfe-3's
# residual carries SEC-022's vector and score from docs/security/3.2.1-review.md, and dfe-10's records the trigger that
# confirms SEC-020's provisional score (the #77 verifier's ask).
# Covers: REQ-382
# Covers: REQ-322
factory_doc_ck "the threat model: every residual the 3.2.1 disposition re-accepted is re-dated to 2027-01-31 (its old date kept); only the Boundary residual keeps 2026-12-15, marked closed and not carried" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" <<'PYR'
import sys
t = open(sys.argv[1]).read()
RD = "expires: 2027-01-31; re-dated 2026-10-05 by the post-3.2.1 records patch to the 3.2.1 disposition's date (`docs/security/3.2.1-disposition.md`), from "
assert t.count(RD + "2026-12-15") == 13, t.count(RD + "2026-12-15")
assert t.count(RD + "2026-11-15") == 2, t.count(RD + "2026-11-15")
assert t.count("expires: 2026-12-15") == 1, t.count("expires: 2026-12-15")
assert "expires: 2026-11-15" not in t
dfe12 = next(l for l in t.splitlines() if l.startswith("| dfe-12 |"))
bnd = dfe12[dfe12.index("**Boundary residual**"):dfe12.index("**Tagged-tree residual**")]
assert "re-reviewed by the P7 retrospective (plan Build 1, Deferred corrections); closed, not carried: the 3.2.1 disposition (`docs/security/3.2.1-disposition.md`, SEC-008) records this half closed (BL-038) and re-accepts only the Tagged-tree residual, so this expiry is history and nothing lapses on it" in bnd, bnd
L = [l for l in t.splitlines() if l.startswith("- **")]
for head in ("- **The python image's base is re-pinned by hand**", "- **The deploy contract's test runs an instance's deploy scripts**"):
    assert RD + "2026-11-15" in next(l for l in L if l.startswith(head)), head
PYR
factory_doc_ck "dfe-3's residual carries SEC-022's vector and score (cvss4.py), provisional (solo mode) until the next second reviewer confirms; no longer 'not scored'" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" "$ROOT/scripts/lib/specflow" <<'PY3'
import sys
sys.path.insert(0, sys.argv[2]); import cvss4
r = next(l for l in open(sys.argv[1]).read().splitlines() if l.startswith("| dfe-3 |"))
r = r[r.index("Residual (PR #74, BL-040"):]
v = "CVSS:4.0/AV:N/AC:L/AT:P/PR:L/UI:A/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N"
assert (cvss4.score(v), cvss4.finding_severity(v)) == (2.0, "low"), cvss4.score(v)
for w in ("scored by the 3.2.1 review as SEC-022 (`docs/security/3.2.1-review.md`)", f"`{v}` (2.0, low",
          "provisional (solo mode) until the next second reviewer confirms"):
    assert w in r, w
assert "not scored" not in r and "records no scored CVSS vector" not in r
PY3
factory_doc_ck "dfe-10 records SEC-020's confirmation trigger: the next ship verifier run or retrospective re-scores it choosing the vulnerable system; if high, ADR-002 rule 2 needs a fix before that ship" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'grep -qF "confirmation trigger: the next verifier run on a ship/<version> PR, or the next retrospective, whichever first, re-scores SEC-020 from its vector choosing the vulnerable system explicitly (CI job: 5.2 medium; workstation: 7.0 high); if high, ADR-002 rule 2 requires a fix before that ship, since a shipped release has accepted it as medium" <<<"$1"' _ "$(row dfe-10)"
# PR #78 verifier run 1 (REQ-382; BL-022): item 7's remaining duties — every re-dated residual names the re-dating patch's
# merge as its sign-off, dfe-10 cites BL-037 with the re-decided severity, dfe-9 records SEC-021's headless-prompt.md half.
# Covers: REQ-382
factory_doc_ck "the threat model: every re-dated residual names the merge of patch/post-3-2-1-records; dfe-10 cites BL-037; dfe-9 records SEC-021's half to 2027-01-31" "$TM" \
  python3 - "$TM" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
n_re = len(re.findall(r"re-dated 2026-10-05 by the post-3\.2\.1 records patch", t))
n_so = len(re.findall(r"re-dating sign-off: the merge of patch/post-3-2-1-records", t))
assert n_re >= 13 and n_so == n_re, (n_re, n_so)
d10 = next(l for l in t.splitlines() if l.startswith("| dfe-10 "))
assert "BL-037" in d10 and "5.2 medium, provisional" in d10, "dfe-10"
d9 = next(l for l in t.splitlines() if l.startswith("| dfe-9 "))
assert "SEC-021" in d9 and "headless-prompt.md" in d9 and "expires: 2027-01-31" in d9, "dfe-9"
assert "CVSS:4.0/AV:N/AC:L/AT:P/PR:L/UI:A/VC:L/VI:N/VA:N/SC:L/SI:N/SA:N" in d9 and "sign-off: the merge of patch/post-3-2-1-records" in d9, "dfe-9 vector and sign-off"
assert d9.split("|")[-2].strip() == "P2", "dfe-9: the residual sits in Mitigations, the Delivered-in cell is P2 alone"
PY

finish test_threat_model_current
