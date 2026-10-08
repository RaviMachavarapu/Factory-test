#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R1, R5, R6): the Dafny model of derive() — verification/factory_v3_2/state.dfy — carries its
# Proves header, every Branch constructor ADR-003 lists, the PR, Facts, Step and Result records, the phase order the
# Progress theorem needs, and the five theorems by name, with nothing assumed. Progress keeps the derived phase in the
# branch's lane (ADR-003: "in the lane's order"), and main's Checkout names the lowest open lane PR of the current user
# (dfe-10). REQ-385: MergeOnlyWhenApproved carries the human-approval conjunct. REQ-340: one Branch datatype holds both
# paths' constructors, and PathClosure ties proposals to the configured path. Gates section 2 verifies the file; this
# test pins its shape.
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
DFY="$ROOT/verification/factory_v3_2/state.dfy"
[[ -f "$DFY" ]] || { echo "SKIP: the factory's state model ships only in the template source (P5 R11 fences it out of instances)"; exit 0; }
block() {  # the datatype's declaration, up to a blank line or the next declaration
  awk -v n="$1" 'f && (/^[[:space:]]*$/ || /^[[:space:]]*(datatype|function|predicate|lemma) /) {exit}
                 $0 ~ ("^[[:space:]]*datatype " n "[ <=]") {f=1} f' "$DFY" | tr '\n' ' '
}
head_of() {  # a lemma's signature and contract, up to the line that opens its body
  awk -v n="$1" '$0 ~ ("lemma " n "[(<]") {f=1} f && /^[[:space:]]*\{/ {exit} f' "$DFY" | tr '\n' ' '
}
ck "the Proves header is in the first five lines" bash -c 'head -5 "$1" | grep -qx "// Proves: REQ-341"' _ "$DFY"
ck "module PipelineState" grep -qE '^module PipelineState' "$DFY"
for d in Option Path Attestation Branch PR RegShip Unbuilt Facts Lane Phase Proposal ImplTarget Why Step Result; do
  ck "datatype $d" grep -qE "^[[:space:]]*datatype $d( |<)" "$DFY"
done
br=$(block Branch)
for c in Main Design Build BuildSec Ship Patch PhaseSpec PhaseArch PhasePlan Impl ImplSec PhaseValidate PhaseSecurity PhaseRelease Unknown; do
  ck "Branch has $c (ADR-003)" grep -qE "(=|\|)[[:space:]]*$c([[:space:]]|[(]|$)" <<<"$br"
done
st=$(block Step)
for c in RunBrainstorm RunSpecify RunArchitecture RunPlan RunAnalyze RunImplement RunGates RunSecurityReview RunRelease \
         CreatePr RunVerifier RequestReview Merge Checkout CheckoutMain NewBranch AddressFindings TagRelease ExplainUnknown; do
  ck "Step has $c" grep -qE "(=|\|)[[:space:]]*$c([[:space:]]|[(]|$)" <<<"$st"
done
fa=$(block Facts)
for f in hasBrainstorm hasSpec specHasTaggedReqs archComplete hasPlan buildSections analyzeOk hasSourceDiff gatesPass \
         hasSecurityDocs hasReleaseDocs signingKeyPresent prStateKnown unbuilt untaggedShip nextVersion shipPhasesMerged; do
  ck "Facts has $f" grep -qE "$f:" <<<"$fa"
done
pr=$(block PR)
for f in number open merged closed humanApproved attestation mine; do ck "PR has $f" grep -qE "$f:" <<<"$pr"; done
for fn in WellFormedPr IsLaneBranch Pre NumbersOf OwnNumbers MinOf LaneOf LaneList FirstMissingAfterLastPresent LanePhase \
          PhaseStep ImplTargetOf PrSubstate MainResult RegulatedShipProposal Derive PhaseOrder ArtifactPhase SetFact \
          LanesProposal RegulatedProposal; do
  ck "the model defines $fn" grep -qE "(function|predicate) $fn[(<]" "$DFY"
done
for l in MergeOnlyWhenApproved NoBlindCreatePr PathClosure PrPrecedence Progress UnknownBranchNeverMerges \
         UnknownPrStateNeverAwaitsVerifier RemoteLessMainIsIdle OtherUsersPrsNeverBlock OwnNumbersSpec MinOfSpec \
         MainChecksOutLowestOwn; do
  ck "the model proves $l" grep -qE "lemma $l[(<]" "$DFY"
done
mo=$(head_of MergeOnlyWhenApproved)
ck "MergeOnlyWhenApproved's conclusion carries the human-approval conjunct (solo || humanApproved)" \
  bash -c 'grep -qF "humanApproved" <<<"$1" && grep -qF "solo" <<<"$1" && grep -qF "Waiver" <<<"$1"' _ "$mo"
pc=$(head_of PathClosure)
ck "PathClosure speaks of both paths" bash -c 'grep -qF "Lanes" <<<"$1" && grep -qF "Regulated" <<<"$1"' _ "$pc"
pg=$(head_of Progress)
ck "Progress keeps the new phase in the branch's lane, an artifact phase or OpenPr (ADR-003: 'in the lane's order')" \
  bash -c 'grep -qF "LaneOf(branch)" <<<"$1" && grep -qF "ArtifactPhase(q.phase) || q.phase == OpenPr" <<<"$1"' _ "$pg"
mc=$(head_of MainChecksOutLowestOwn)
ck "MainChecksOutLowestOwn: main's Checkout names an open lane PR of the current user, the lowest such (dfe-10)" \
  bash -c 'grep -qF "Checkout?" <<<"$1" && grep -qF ".mine" <<<"$1" && grep -qF "<=" <<<"$1"' _ "$mc"
ck "at least ten FixtureNN lemmas" [ "$(grep -cE 'lemma Fixture[0-9]+' "$DFY")" -ge 10 ]
f2=$(head_of Fixture02)
ck "a Progress witness: Fixture02's facts are SetFact of Fixture01's, and its phase follows" \
  bash -c 'grep -qF "SetFact(" <<<"$1" && grep -qF "Brainstorm" <<<"$1" && grep -qF "Specify" <<<"$1"' _ "$f2"
ck "a regulated PathClosure witness: Fixture42 is the regulated remote-less idle (REQ-393)" \
  bash -c 'grep -qF "Regulated" <<<"$1" && grep -qF "ProposeSpec" <<<"$1"' _ "$(head_of Fixture42)"
ck "the model assumes nothing (no {:axiom}, no assume statement, no {:verify false})" \
  no grep -qE '\{:axiom\}|\{:verify false\}|^[[:space:]]*assume[[:space:]]' "$DFY"
finish test_state_model
