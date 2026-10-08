#!/usr/bin/env bash
# REQ-326, REQ-353, REQ-371 (constitution amendment C, with P7's design PR): every article's How to apply names its
# enforcing files or says "convention (no mechanism)" (the counts are test_constitution_articles.sh's);
# art-release-readiness defines "shipped" as the Release job succeeding from the tag and states the CI comparison and
# the tag-time replay as settled text (P6 R10's two clauses gone); signing is SSH (P6 R27); art-branch-as-state says
# impl/plan-N-<plan slug>; art-formal-verification defers extraction to v3.3 everywhere a user reads it;
# art-naming-tagging gains the docs-wide slug check and BL-NNN; art-retrospective-cadence names the backlog. The spec
# records it.
# Covers: REQ-326
# Covers: REQ-353
# Covers: REQ-371
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=constitution.md
art() { awk -v s="slug: $1" '$0 == s {f=1} f && /^---$/ {exit} f' "$C" | tr '\n' ' ' | tr -s ' '; }
how() { art "$1" | sed -n 's/.*\*\*How to apply:\*\*//p'; }
ck "constitution keeps twelve articles; every How to apply names a file or says convention" bash tests/governance/test_constitution_articles.sh
while read -r slug files; do
  h=$(how "$slug")
  for f in ${files//,/ }; do ck "$slug's How to apply names $f" grep -qF -- "\`$f\`" <<<"$h"; done
done <<'EOF'
art-specification-primacy scripts/check-test-first.sh,.github/workflows/ci.yml,scripts/check-traceability.sh,scripts/check-covers.sh
art-branch-as-state .claude/rules/review-gate.md,scripts/next.sh,scripts/lib/specflow/state.py,scripts/configure-repo.sh
art-review-gate .github/workflows/verifier.yml,scripts/run-verifier.sh,scripts/lib/specflow/attestation.py,scripts/configure-repo.sh,.claude/rules/review-gate.md
art-test-first scripts/check-test-first.sh,.github/workflows/ci.yml,.claude/rules/tdd.md
art-formal-verification scripts/check-traceability.sh,scripts/run-quality-gates.sh,.github/workflows/ci.yml
art-kernel-boundary scripts/check-architecture.sh,scripts/lib/specflow/architecture.py
art-threat-driven-security scripts/check-security-disposition.sh,scripts/lib/specflow/disposition.py,scripts/run-security-floor.sh,scripts/check-suppressions.sh,.claude/skills/verifier/SKILL.md
art-release-readiness scripts/verify-release.sh,.github/workflows/release.yml,scripts/lib/specflow/signers.py,scripts/lib/specflow/attestation.py,scripts/check-security-disposition.sh
art-naming-tagging scripts/check-traceability.sh,tests/governance/test_backlog.sh,tests/governance/test_reviews_use_slugs.sh
art-secrets-hygiene .gitignore,scripts/run-security-floor.sh,.gitleaks.toml,.claude/settings.json,scripts/run-verifier.sh
art-retrospective-cadence .claude/commands/retrospective.md,docs/BACKLOG.md,tests/governance/test_backlog.sh
EOF
for s in art-repository-singleton art-secrets-hygiene art-retrospective-cadence art-branch-as-state art-threat-driven-security art-kernel-boundary; do
  ck "$s's How to apply says convention (no mechanism) for what nothing enforces" grep -qF "convention (no mechanism)" <<<"$(how "$s")"
done
rel=$(art art-release-readiness)
ck "art-release-readiness: shipped means the Release job succeeded from the tag (REQ-353)" \
  grep -qF 'A release is **shipped** when the Release job succeeded from that tag' <<<"$rel"
for w in 'the artifacts and `manifest.json`' 'the source manifest reproduced in CI from the tagged tree' \
         'the tag an ancestor of `main` and its signature verified' '(python) the image pushed' \
         'the laptop-built `dist/` is not the artifact of record'; do
  ck "art-release-readiness's shipped clause says '$w'" grep -qF -- "$w" <<<"$rel"
done
ck "art-release-readiness: P6 R10 clause (a) — no shape-only CI check, no 'until the CI-built manifest'" \
  bash -c '! grep -qF "only the Artifacts table'"'"'s shape is checked" <<<"$1" && ! grep -qF "until the CI-built manifest" <<<"$1" && grep -qF "the reproducible subset it builds itself from the PR head'"'"'s tree" <<<"$1" && grep -qF "a tracked \`dist/\` fails" <<<"$1"' _ "$rel"
ck "art-release-readiness: P6 R10 clause (b) — no 'until release.yml replays', no 'only check between a merge'" \
  bash -c '! grep -qF "until \`release.yml\` replays" <<<"$1" && ! grep -qF "the only check between a merge and the next release PR" <<<"$1"' _ "$rel"
for w in 'publishes nothing unless' '`scripts/verify-release.sh --at-tag`' '`scripts/check-security-disposition.sh --at-tag`' \
         'replays gates section 7 only, never sections 1–6 or `scripts/check-test-first.sh`' 'what no job replays (convention)'; do
  ck "art-release-readiness's How to apply says '$w'" grep -qF -- "$w" <<<"$rel"
done
ck "art-release-readiness: SSH-signed against .github/allowed_signers; annotated only with no signer; GPG refused at the tag (P6 R27)" \
  bash -c 'grep -qF "SSH-signed and verified against \`.github/allowed_signers\`" <<<"$1" && grep -qF "no signer at all — SSH, GPG or X.509" <<<"$1" && grep -qF "a GPG-signed tag is refused at the tag" <<<"$1" && ! grep -qF "neither GPG nor SSH signing is verifiably available" <<<"$1"' _ "$rel"
# P7 fresh-eyes review, finding 19 (REQ-353; P6 R10): the annotated fallback is the one exception to "signature verified",
# in the shipped clause and at the tag — release.yml's tagsig step accepts an unsigned tag whose fallback is recorded, and
# verify-release.sh --at-tag passes it.
ck "art-release-readiness's shipped clause names the annotated fallback as the exception to a verified signature" \
  grep -qF 'the tag an ancestor of `main` and its signature verified (or, annotated, the fallback recorded in known-limitations)' <<<"$rel"
ck "art-release-readiness's How to apply: at the tag the signature verifies or, unsigned, its fallback is recorded" \
  grep -qF 'its signature verifies against the anchored `.github/allowed_signers` (`scripts/lib/specflow/signers.py`) — or, unsigned, its fallback is recorded in `<version>-known-limitations.md`' <<<"$rel"
# P7 fresh-eyes review, finding 18 (REQ-326; REQ-334): art-review-gate claims no control the classifier lacks — an accepted
# marker is the form run-verifier.sh writes, tamper-evident and not bound to a model run — and names the Dependabot route.
rg=$(how art-review-gate)
ck "art-review-gate's How to apply: an accepted marker (tamper-evident, not bound to a model run), a waiver, or the Dependabot exemption" \
  bash -c 'grep -qF "passes only on an accepted marker for the PR'"'"'s head (the form \`scripts/run-verifier.sh\` writes; tamper-evident, not bound to a model run), a maintainer waiver, or the Dependabot exemption" <<<"$1" && ! grep -qF "passes only on a marker \`scripts/run-verifier.sh\` wrote" <<<"$1"' _ "$rg"
# P7 fresh-eyes review, finding 8 (REQ-326; P7 R2(g)): art-kernel-boundary states the req_map obligation as
# architecture.py's _req_map_obligation computes it — every tagged REQ while no plan names the spec.
kb=$(how art-kernel-boundary)
ck "art-kernel-boundary's How to apply: every tagged REQ while no plan names the spec, then what the plans implement" \
  bash -c 'grep -qF "every \`[verifiable]\` or \`[verifiable-model]\` REQ of its spec while no plan names that spec (the ARCHITECTURE PR)" <<<"$1" && grep -qF "a plan without \`implements:\`" <<<"$1" && ! grep -qF "REQ of its spec that a plan implements;" <<<"$1"' _ "$kb"
# P7 design review, polish item 1 (REQ-326; P7 R2(g)): the justification of a boundary-crossing dependency is read by no
# script, and .claude/skills/verifier/SKILL.md says nothing of it — so the article calls it convention, never a review
# that skill performs (architecture.py's _req_map_obligation checks req_map only).
ck "art-kernel-boundary's How to apply: the written justification is convention (no mechanism), never credited to the verifier's skill" \
  bash -c 'grep -qF "has a written justification in the overview is convention (no mechanism): no script reads for it, and the verifier'"'"'s skill (\`.claude/skills/verifier/SKILL.md\`) does not ask for it" <<<"$1" && ! grep -qF "justification is read by the verifier'"'"'s full mode" <<<"$1"' _ "$kb"
ck "…and the skill indeed names no boundary-crossing justification (the article's claim about it holds)" \
  bash -c '! grep -qiE "justif" "$1"' _ .claude/skills/verifier/SKILL.md
# P7 design review, polish item 1 (REQ-353, REQ-350; P6 R30): the tag-time sentences say what release.yml and
# verify-release.sh do — the tag on the ship PR's merge, signers.py previous, release-check's first-parent walk, the
# --at-tag replay's checks, --artifacts-only's comparison, and neither re-running the gates (verify-release.sh:13-19).
for w in 'the tagged commit is the newest first-parent commit of `main` that added `<version>-notes.md` (the ship PR'"'"'s merge)' \
         'a GPG signature fails' 'the previous release, when there is one, is tagged and its tag reads as released (`signers.py previous`: a missing, lightweight, GPG-unverifiable, unanchored or otherwise refused previous tag fails here, where the PR-time check only warns on a missing or uncheckable one)' \
         'every first-parent commit of `main` since the newest earlier release whose GitHub Release is published is judged by `scripts/lib/specflow/attestation.py`'"'"'s `release-check`' \
         'the disposition gate replayed through `scripts/check-security-disposition.sh --at-tag`' \
         '(`scripts/verify-release.sh --artifacts-only`)' 'Neither `--at-tag` nor `--artifacts-only` re-runs the gates'; do
  ck "art-release-readiness's tag-time sentences say '$w'" grep -qF -- "$w" <<<"$rel"
done
ck "art-release-readiness: no 'the tag's commit is on main', no 'every PR merged since the previous release carries', no 'the release gates pass again'" \
  bash -c '! grep -qF "the tag'"'"'s commit is on \`main\`" <<<"$1" && ! grep -qF "every PR merged since the previous release carries" <<<"$1" && ! grep -qF "the release gates pass again at the tag" <<<"$1"' _ "$rel"
ck "…and the code says so: verify-release.sh exits before the gates under --at-tag or --artifacts-only; release.yml runs --at-tag, --artifacts-only, signers.py previous and release-check" \
  bash -c 'grep -qF -- "--at-tag (release.yml'"'"'s replay) and --artifacts-only (build-source'"'"'s comparison) never re-run the gates" scripts/verify-release.sh && for w in "verify-release.sh --version \"\$VERSION\" --at-tag" "--artifacts-only" "signers.py --root . --base-ref refs/remotes/origin/main previous" "attestation.py release-check"; do grep -qF -- "$w" .github/workflows/release.yml || { echo "missing $w"; exit 1; }; done'
# P7 fresh-eyes review, finding 23 (REQ-326; REQ-389): the guided-solo severity confirmation is the verifier's full mode,
# a review, named as other articles name reviews.
ck "art-threat-driven-security's How to apply: guided solo mode's provisional confirmation by the verifier's full mode (REQ-389)" \
  bash -c 'grep -qF "in guided solo mode the verifier'"'"'s full mode confirms severities and dispositions provisionally (\`.claude/skills/verifier/SKILL.md\`, REQ-389), a review, not a mechanism" <<<"$1"' _ "$(how art-threat-driven-security)"
# P7 fresh-eyes review, finding 20 (REQ-326): art-naming-tagging says the Roman-numeral ban covers the instruction files;
# test_reviews_use_slugs.sh must then fail a Roman-numeral citation planted in a .claude/ rule, not only one in docs/.
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT; copy_template "$W/t"
mkdir -p "$W/t/.claude/rules"; printf 'Cite Article %s here.\n' IV > "$W/t/.claude/rules/planted-roman.md"
ck "test_reviews_use_slugs.sh fails a Roman-numeral citation planted in a .claude/ rule" no bash "$W/t/tests/governance/test_reviews_use_slugs.sh"
rm -f "$W/t/.claude/rules/planted-roman.md"
ck "…and passes the same copy without it" bash "$W/t/tests/governance/test_reviews_use_slugs.sh"
bas=$(art art-branch-as-state)
ck "art-branch-as-state names impl/plan-N-<plan slug>, never impl/plan-N-<name>" \
  bash -c 'grep -qF "impl/plan-N-<plan slug>" <<<"$1" && ! grep -qF "impl/plan-N-<name>" <<<"$1"' _ "$bas"
fv=$(art art-formal-verification)
ck "art-formal-verification: extraction deferred to v3.3; no v3.2 promise left" \
  bash -c 'grep -qF "deferred to v3.3" <<<"$1" && grep -qF "(v3.3+)" <<<"$1" && ! grep -qF "deferred to v3.2" <<<"$1" && ! grep -qF "(v3.2+)" <<<"$1"' _ "$fv"
ck "README and the spec template defer [verifiable]'s extraction to v3.3, never 'a later v3.2 plan' or 'lands in v3.2'" \
  bash -c '! grep -qE "later v3\.2 plan|lands in v3\.2" README.md schemas/spec-template.md && grep -qF "v3.3" schemas/spec-template.md && [ "$(grep -c "deferred to v3.3" README.md)" -ge 2 ]'
nt=$(art art-naming-tagging)
ck "art-naming-tagging: Task N.M, TASK-NNN as the dashboard's form, BL-NNN in docs/BACKLOG.md" \
  bash -c 'grep -qF "\`Task N.M\`" <<<"$1" && grep -qF "\`TASK-NNN\`" <<<"$1" && grep -qF "\`BL-NNN\`" <<<"$1" && grep -qF "(REQ-371)" <<<"$1"' _ "$nt"
ck "templates/BACKLOG.md exists (an instance's backlog starts from it)" test -f templates/BACKLOG.md
SP=docs/specs/2026-09-25-factory-v3-2-design.md
p7=$(grep -F -- '- "P7 design lane' "$SP" 2>/dev/null || true)
for w in 'constitution amendment C (REQ-326, REQ-353; REQ-371)' 'convention (no mechanism)' 'impl/plan-N-<plan slug>' 'v3.3' \
         'scripts/lib/' 'Success Metric 2' 'REQ-382 (R4)' 'REQ-391 (R10, R11)' 'REQ-392 (R12)' "REQ bodies unchanged except REQ-382's"; do
  factory_doc_ck "the spec's P7 entry records '$w'" "$SP" grep -qF -- "$w" <<<"$p7"
done
factory_doc_ck "the spec's P7 entry follows the P6 entry; the P6 entry is not edited here" "$SP" \
  python3 - "$SP" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
i6 = next(i for i, l in enumerate(lines) if l.lstrip().startswith('- "P6 builds'))
i7 = next(i for i, l in enumerate(lines) if l.lstrip().startswith('- "P7 design lane'))
assert i7 > i6, (i6, i7)
PY
factory_doc_ck "REQ-382's body carries the As amended by P7 (R4) sentence" "$SP" \
  bash -c 'grep -E "^- \*\*REQ-382:\*\*" "$1" | grep -qF "As amended by P7 (R4): a waiver may name the PR'"'"'s base"' _ "$SP"
# P7 retrospective documentation patch (BL-042; docs/retrospectives/2026-10-04-v3-2-closeout.md, Proposed Changes, item 5;
# PR #71 verifier run 1, finding 5): the readings of REQ-382 (D2, moot), REQ-385 (D9), REQ-313 (D10), SEC-021's inputs and
# REQ-391 (Build 2's M6 copy rule) are their own amended: item right after the P7 entry, signed off by the patch's merge,
# not the design PR's; the P7 entry keeps its text; each stays one double-quoted YAML item (no inner quote, no escape).
# Covers: REQ-385, REQ-313, REQ-391
pd=$(grep -F -- '- "P7 closeout documentation patch (patch/p7-closeout-docs;' "$SP" 2>/dev/null || true)
for w in 'signed off by this patch' "not the design PR's" 'REQ-382 (D2): moot' 'REQ-385 (D9)' 'base_pr == 0' 'read as the same instruction' \
         'REQ-313 (D10)' 'the policy, the prompt template, the skill, the constitution and the pack' 'deny-list additions' \
         ".gitleaks.toml is main's since SEC-021's fix (PR #65)" 'SEC-021:' 'headless-prompt.md' 'REQ-391 (M6)' \
         'never docs/examples/' 'REQ bodies unchanged."'; do
  factory_doc_ck "the spec's P7 closeout-patch amended: item records '$w'" "$SP" grep -qF -- "$w" <<<"$pd"
done
factory_doc_ck "the P7 entry keeps its design-lane text: no closeout-patch reading inside it" "$SP" \
  python3 -c 'import sys; l = sys.argv[1]; assert "patch/p7-closeout-docs" not in l; assert l.rstrip().endswith("else carried by BL-019 to the retrospective. REQ bodies unchanged except REQ-382" + chr(39) + "s." + chr(34))' "$p7"
factory_doc_ck "the closeout-patch item directly follows the P7 entry" "$SP" \
  python3 -c 'import sys; L = open(sys.argv[1]).read().splitlines(); i = next(i for i, l in enumerate(L) if l.lstrip().startswith("- \"P7 design lane")); assert L[i + 1].lstrip().startswith("- \"P7 closeout documentation patch (patch/p7-closeout-docs;"), L[i + 1][:60]' "$SP"
for item in "$p7" "$pd"; do
  factory_doc_ck "an amended: item is one double-quoted YAML item, no inner double quote, no backslash: ${item:5:24}" "$SP" \
    python3 -c 'import sys; l = sys.argv[1].strip(); assert l.startswith("- \"") and l.endswith("\""), l[:40]; b = l[3:-1]; assert "\"" not in b and "\\" not in b' "$item"
done
finish test_constitution_amendment_c
