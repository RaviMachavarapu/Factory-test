// verification/factory_v3_2/state.dfy — ADR-003's pipeline-state derivation as a pure, total function.
// Proves: REQ-341
// Twin: scripts/lib/specflow/state.py (derive); fixtures: tests/governance/fixtures/state/.
//
// REQ-341 (ADR-003, refined by the P5 plan's R5 and R6), restated. Derive(branch, branchPr, openLanePrs, facts,
// path, solo) returns exactly one Result(lane, phase, step, openLanes); openLanes is every open lane PR's number.
//   R5(d). An Unknown branch derives (none, unknown-branch, ExplainUnknown) before any PR is looked at (dfe-7).
//   3. Main (branchPr is None there, R5(e)): an open lane PR of the current user -> (none, awaiting-merge,
//      Checkout(lowest own number)); other users' PRs never block. Else an untagged merged ship -> (ship | release,
//      tag, TagRelease). Else an unbuilt "## Build N" -> (none, next-build, NewBranch(build/<slug>-N |
//      impl/plan-N-<slug>)) for the lowest (slug, n). Else a next version -> (none, ready-to-ship,
//      NewBranch(ship/<version>)), or under regulated (R6) the first of phase/validate, phase/security,
//      phase/release not yet merged. Else (none, idle, NewBranch(design/<slug> | phase/spec-<slug>)).
//   1. branchPr open -> the PR substate: RequestChanges -> blocked (AddressFindings); NoMarker -> awaiting-verifier
//      (RunVerifier); Approve or Waiver -> awaiting-merge (Merge) when solo or human-approved, else
//      awaiting-human-review (RequestReview).
//   2. branchPr merged -> (lane, merged, CheckoutMain); closed unmerged -> (lane, closed, ExplainUnknown).
//   R5(f). build/<slug>-N with N not a "## Build N" section -> (build, unknown-build, ExplainUnknown), checked after
//      precedence 1 and 2 so an open PR still reports its substate.
//   4. A lane branch's phase is the first missing artifact after the last present one in the lane's ordered list,
//      except that on design/<slug> a spec with tagged REQs and incomplete architecture derives architecture.
//   5. At open-pr, CreatePr only when pr_state_known; otherwise ExplainUnknown.
// State tables. Lanes: design/<slug> brainstorm, specify, [architecture], plan, analyze, open-pr; build/<slug>-N,
// build/sec-<id> and patch/<slug> implement, open-pr; ship/<version> security, release, open-pr. Regulated:
// phase/spec-<slug> brainstorm, specify; phase/arch-<slug> architecture; phase/plan-<slug> plan, analyze;
// impl/plan-N-<name> and impl/sec-<id> implement; phase/validate gates; phase/security security; phase/release
// release; each then open-pr. Both paths' branches are recognised whatever the configured path (REQ-340); the
// path only chooses which branch names Main proposes.
// Modelling choices. Slugs, ids, versions and plan tokens are opaque strings; the kernel decides order and
// precedence, never whether an artifact is complete (the wrapper computes Facts). Steps carry datatypes, never
// command text (render_step is the wrapper's). openLanes is a set<nat> here and a sorted tuple in the twin.
// unbuilt is taken at its head; Pre requires it sorted by (slug, n), which the wrapper does. Pre is the twin's
// precondition (derive() raises ValueError outside it); Derive itself is total. Totality and determinism follow
// from Derive being a Dafny function over these datatypes, so they are stated here and not laboured.
// Three layers (verification/README.md): this proof; derive()'s precondition checks; the fixtures that mirror it.

module PipelineState {

  datatype Option<T> = None | Some(value: T)

  datatype Path = Lanes | Regulated

  datatype Attestation = NoMarker | Approve | RequestChanges | Waiver

  datatype Branch = Main | Design(slug: string) | Build(slug: string, n: nat) | BuildSec(id: string)
                  | Ship(version: string) | Patch(slug: string) | PhaseSpec(slug: string) | PhaseArch(slug: string)
                  | PhasePlan(slug: string) | Impl(plan: string, name: string) | ImplSec(id: string)
                  | PhaseValidate | PhaseSecurity | PhaseRelease | Unknown

  datatype PR = PR(number: nat, open: bool, merged: bool, closed: bool, humanApproved: bool,
                   attestation: Attestation, mine: bool)

  datatype RegShip = RValidate | RSecurity | RRelease

  datatype Unbuilt = Unbuilt(slug: string, n: nat)

  datatype Facts = Facts(hasBrainstorm: bool, hasSpec: bool, specHasTaggedReqs: bool, archComplete: bool,
                         hasPlan: bool, buildSections: set<nat>, analyzeOk: bool, hasSourceDiff: bool,
                         gatesPass: bool, hasSecurityDocs: bool, hasReleaseDocs: bool, signingKeyPresent: bool,
                         prStateKnown: bool, unbuilt: seq<Unbuilt>, untaggedShip: Option<string>,
                         nextVersion: Option<string>, shipPhasesMerged: set<RegShip>)

  datatype Lane = NoLane | DesignLane | BuildLane | ShipLane | SpecLane | ArchLane | PlanLane | ImplLane
                | ValidateLane | SecurityLane | ReleaseLane

  datatype Phase = Brainstorm | Specify | Architecture | PlanPhase | Analyze | Implement | Gates | Security | Release
                 | OpenPr | UnknownBuild | AwaitingVerifier | AwaitingHumanReview | AwaitingMerge | Blocked
                 | Merged | Closed | Tag | NextBuild | ReadyToShip | Idle | UnknownBranch

  datatype Proposal = ProposeDesign | ProposeBuild(slug: string, n: nat) | ProposeShip(version: string)
                    | ProposeSpec | ProposeImpl(slug: string, n: nat) | ProposeValidate | ProposeSecurity
                    | ProposeRelease

  datatype ImplTarget = Section(n: nat) | SecFix(id: string) | PatchTier | PlanTarget(plan: string, name: string)

  datatype Why = PrStateUnknown | BranchUnknown | BuildUnknown | PrClosed

  datatype Step = RunBrainstorm | RunSpecify | RunArchitecture | RunPlan | RunAnalyze | RunImplement(target: ImplTarget)
                | RunGates | RunSecurityReview | RunRelease | CreatePr | RunVerifier(pr: nat) | RequestReview(pr: nat)
                | Merge(pr: nat) | Checkout(pr: nat) | CheckoutMain | NewBranch(p: Proposal)
                | AddressFindings(pr: nat) | TagRelease(version: string) | ExplainUnknown(why: Why)

  datatype Result = Result(lane: Lane, phase: Phase, step: Step, openLanes: set<nat>)

  // ---- The precondition (R5): the twin raises ValueError outside it -----------------------------------------

  // A PR is in exactly one state and carries a real number.
  predicate WellFormedPr(pr: PR) {
    pr.number >= 1
    && ((pr.open && !pr.merged && !pr.closed) || (!pr.open && pr.merged && !pr.closed)
        || (!pr.open && !pr.merged && pr.closed))
  }
  predicate IsLaneBranch(b: Branch) { !b.Main? && !b.Unknown? }
  // Python's str ordering (code points), so "sorted by (slug, n)" means the same thing in both layers.
  predicate StrLe(a: string, b: string) decreases |a| {
    |a| == 0 || (|b| > 0 && (a[0] < b[0] || (a[0] == b[0] && StrLe(a[1..], b[1..]))))
  }
  predicate UnbuiltLe(u: Unbuilt, v: Unbuilt) {
    (u.slug != v.slug && StrLe(u.slug, v.slug)) || (u.slug == v.slug && u.n <= v.n)
  }
  predicate Pre(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path, solo: bool) {
    (branchPr.Some? ==> WellFormedPr(branchPr.value))
    && (forall i :: 0 <= i < |openLanePrs| ==> WellFormedPr(openLanePrs[i]) && openLanePrs[i].open)
    && (forall i, j :: 0 <= i < j < |openLanePrs| ==> openLanePrs[i].number != openLanePrs[j].number)
    && (branch.Main? ==> branchPr.None?)                                                        // R5(e)
    && (!facts.prStateKnown ==> branchPr.None? && |openLanePrs| == 0)                           // R5(h)
    && (branch.Build? ==> branch.n >= 1)
    && (forall k :: k in facts.buildSections ==> k >= 1)
    && (forall i :: 0 <= i < |facts.unbuilt| ==> facts.unbuilt[i].n >= 1)
    && (forall i :: 0 <= i < |facts.unbuilt| - 1 ==> UnbuiltLe(facts.unbuilt[i], facts.unbuilt[i + 1]))
    && (facts.specHasTaggedReqs ==> facts.hasSpec)
    && (facts.untaggedShip.Some? ==> |facts.untaggedShip.value| > 0)
    && (facts.nextVersion.Some? ==> |facts.nextVersion.value| > 0)
  }

  // ---- Helpers ----------------------------------------------------------------------------------------------

  function NumbersOf(prs: seq<PR>): set<nat> { set i | 0 <= i < |prs| :: prs[i].number }
  function OwnNumbers(prs: seq<PR>): seq<nat> {
    if |prs| == 0 then [] else (if prs[0].mine then [prs[0].number] else []) + OwnNumbers(prs[1..])
  }
  function MinOf(xs: seq<nat>): nat requires |xs| > 0 {
    if |xs| == 1 then xs[0] else (var m := MinOf(xs[1..]); if xs[0] <= m then xs[0] else m)
  }
  function LaneOf(b: Branch): Lane {
    match b
    case Design(_) => DesignLane
    case Build(_, _) => BuildLane
    case BuildSec(_) => BuildLane
    case Patch(_) => BuildLane
    case Ship(_) => ShipLane
    case PhaseSpec(_) => SpecLane
    case PhaseArch(_) => ArchLane
    case PhasePlan(_) => PlanLane
    case Impl(_, _) => ImplLane
    case ImplSec(_) => ImplLane
    case PhaseValidate => ValidateLane
    case PhaseSecurity => SecurityLane
    case PhaseRelease => ReleaseLane
    case Main => NoLane
    case Unknown => NoLane
  }
  predicate LanesProposal(p: Proposal) { p.ProposeDesign? || p.ProposeBuild? || p.ProposeShip? }
  predicate RegulatedProposal(p: Proposal) {
    p.ProposeSpec? || p.ProposeImpl? || p.ProposeValidate? || p.ProposeSecurity? || p.ProposeRelease?
  }

  // ---- Lane branches: precedence 4 and 5, both state tables -------------------------------------------------

  // Each lane's ordered artifact list: (the phase that produces it, whether it is present).
  function LaneList(b: Branch, f: Facts): seq<(Phase, bool)> {
    match b
    case Design(_) =>                                                          // lanes: design/<slug>
      [(Brainstorm, f.hasBrainstorm), (Specify, f.hasSpec)]
      + (if f.specHasTaggedReqs then [(Architecture, f.archComplete)] else [])
      + [(PlanPhase, f.hasPlan), (Analyze, f.analyzeOk)]
    case PhaseSpec(_) => [(Brainstorm, f.hasBrainstorm), (Specify, f.hasSpec)]  // regulated: phase/spec-<slug>
    case PhaseArch(_) => [(Architecture, f.archComplete)]                      // regulated: phase/arch-<slug>
    case PhasePlan(_) => [(PlanPhase, f.hasPlan), (Analyze, f.analyzeOk)]      // regulated: phase/plan-<slug>
    case Build(_, _) => [(Implement, f.hasSourceDiff)]                         // lanes: build/<slug>-N
    case BuildSec(_) => [(Implement, f.hasSourceDiff)]                         // lanes: build/sec-<id>
    case Patch(_) => [(Implement, f.hasSourceDiff)]                            // both: patch/<slug>
    case Impl(_, _) => [(Implement, f.hasSourceDiff)]                          // regulated: impl/plan-N-<name>
    case ImplSec(_) => [(Implement, f.hasSourceDiff)]                          // regulated: impl/sec-<id>
    case PhaseValidate => [(Gates, f.gatesPass)]                               // regulated: phase/validate
    case Ship(_) => [(Security, f.hasSecurityDocs), (Release, f.hasReleaseDocs)] // lanes: ship/<version>
    case PhaseSecurity => [(Security, f.hasSecurityDocs)]                      // regulated: phase/security
    case PhaseRelease => [(Release, f.hasReleaseDocs)]                         // regulated: phase/release
    case Main => []
    case Unknown => []
  }
  // Scanning from the end: `after` is the phase that follows the suffix already scanned (all of it missing).
  function ScanBack(l: seq<(Phase, bool)>, after: Phase): Phase decreases |l| {
    if |l| == 0 || l[|l| - 1].1 then after else ScanBack(l[..|l| - 1], l[|l| - 1].0)
  }
  // Precedence 4: the entry after the last present one, or OpenPr when none follows (an existing spec with no
  // brainstorm does not send the user back).
  function FirstMissingAfterLastPresent(l: seq<(Phase, bool)>): Phase { ScanBack(l, OpenPr) }
  function LanePhase(b: Branch, f: Facts): Phase {
    if b.Design? && f.specHasTaggedReqs && !f.archComplete then Architecture   // precedence 4's exception (REQ-320)
    else FirstMissingAfterLastPresent(LaneList(b, f))
  }
  function ImplTargetOf(b: Branch): ImplTarget {
    match b
    case Build(_, n) => Section(n)
    case BuildSec(id) => SecFix(id)                                            // the back-edge, art-threat-driven-security
    case ImplSec(id) => SecFix(id)
    case Impl(plan, name) => PlanTarget(plan, name)
    case _ => PatchTier                                                        // patch/<slug>; no other lane implements
  }
  function PhaseStep(phase: Phase, b: Branch, f: Facts): Step {
    match phase
    case Brainstorm => RunBrainstorm
    case Specify => RunSpecify
    case Architecture => RunArchitecture
    case PlanPhase => RunPlan
    case Analyze => RunAnalyze
    case Implement => RunImplement(ImplTargetOf(b))
    case Gates => RunGates
    case Security => RunSecurityReview
    case Release => RunRelease
    case OpenPr => if f.prStateKnown then CreatePr else ExplainUnknown(PrStateUnknown)   // precedence 5
    case _ => ExplainUnknown(BranchUnknown)                                    // no lane list yields another phase
  }

  // ---- PR substates: precedence 1 ---------------------------------------------------------------------------

  function PrSubstate(lane: Lane, pr: PR, solo: bool, ol: set<nat>): Result {
    if pr.attestation == RequestChanges then Result(lane, Blocked, AddressFindings(pr.number), ol)
    else if pr.attestation == NoMarker then Result(lane, AwaitingVerifier, RunVerifier(pr.number), ol)
    else if solo || pr.humanApproved then Result(lane, AwaitingMerge, Merge(pr.number), ol)  // Approve or Waiver
    else Result(lane, AwaitingHumanReview, RequestReview(pr.number), ol)
  }

  // ---- Main: precedence 3, both paths (R6) ------------------------------------------------------------------

  function RegulatedShipProposal(m: set<RegShip>): Proposal {
    if RValidate !in m then ProposeValidate else if RSecurity !in m then ProposeSecurity else ProposeRelease
  }
  function MainResult(prs: seq<PR>, f: Facts, path: Path): Result {
    var ol := NumbersOf(prs);
    var own := OwnNumbers(prs);
    if |own| > 0 then Result(NoLane, AwaitingMerge, Checkout(MinOf(own)), ol)
    else if f.untaggedShip.Some? then
      Result(if path == Lanes then ShipLane else ReleaseLane, Tag, TagRelease(f.untaggedShip.value), ol)
    else if |f.unbuilt| > 0 then
      var u := f.unbuilt[0];
      Result(NoLane, NextBuild, NewBranch(if path == Lanes then ProposeBuild(u.slug, u.n) else ProposeImpl(u.slug, u.n)), ol)
    else if f.nextVersion.Some? then
      Result(NoLane, ReadyToShip,
             NewBranch(if path == Lanes then ProposeShip(f.nextVersion.value)
                       else RegulatedShipProposal(f.shipPhasesMerged)), ol)
    else Result(NoLane, Idle, NewBranch(if path == Lanes then ProposeDesign else ProposeSpec), ol)
  }

  // ---- The state machine ------------------------------------------------------------------------------------

  function Derive(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path,
                  solo: bool): Result {
    var ol := NumbersOf(openLanePrs);
    if branch.Unknown? then Result(NoLane, UnknownBranch, ExplainUnknown(BranchUnknown), ol)    // R5(d)
    else if branch.Main? then MainResult(openLanePrs, facts, path)                             // precedence 3
    else if branchPr.Some? && branchPr.value.open then
      PrSubstate(LaneOf(branch), branchPr.value, solo, ol)                                       // precedence 1
    else if branchPr.Some? && branchPr.value.merged then
      Result(LaneOf(branch), Merged, CheckoutMain, ol)                                           // precedence 2
    else if branchPr.Some? then Result(LaneOf(branch), Closed, ExplainUnknown(PrClosed), ol)     // precedence 2
    else if branch.Build? && branch.n !in facts.buildSections then
      Result(BuildLane, UnknownBuild, ExplainUnknown(BuildUnknown), ol)                          // R5(f)
    else
      var p := LanePhase(branch, facts);                                                         // precedence 4, 5
      Result(LaneOf(branch), p, PhaseStep(p, branch, facts), ol)
  }

  // ---- Progress's vocabulary --------------------------------------------------------------------------------

  function PhaseOrder(p: Phase): nat {
    match p
    case Brainstorm => 0
    case Specify => 1
    case Architecture => 2
    case PlanPhase => 3
    case Analyze => 4
    case Implement => 5
    case Gates => 6
    case Security => 7
    case Release => 8
    case OpenPr => 9
    case _ => 10
  }
  predicate ArtifactPhase(p: Phase) {
    p.Brainstorm? || p.Specify? || p.Architecture? || p.PlanPhase? || p.Analyze? || p.Implement? || p.Gates?
    || p.Security? || p.Release?
  }
  // The "next fact" function: supplying the artifact that phase p produces.
  function SetFact(f: Facts, p: Phase): Facts {
    match p
    case Brainstorm => f.(hasBrainstorm := true)
    case Specify => f.(hasSpec := true)
    case Architecture => f.(archComplete := true)
    case PlanPhase => f.(hasPlan := true)
    case Analyze => f.(analyzeOk := true)
    case Implement => f.(hasSourceDiff := true)
    case Gates => f.(gatesPass := true)
    case Security => f.(hasSecurityDocs := true)
    case Release => f.(hasReleaseDocs := true)
    case _ => f
  }

  // ---- The five theorems (ADR-003 "Proof obligations") ------------------------------------------------------

  // MergeOnlyWhenApproved (REQ-385, art-review-gate): a Merge step names the branch's own open PR, whose attestation
  // is Approve or Waiver, and requires solo mode or a human approval; it never occurs on main or an unknown branch.
  lemma MergeOnlyWhenApproved(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path,
                              solo: bool)
    requires Pre(branch, branchPr, openLanePrs, facts, path, solo)
    requires Derive(branch, branchPr, openLanePrs, facts, path, solo).step.Merge?
    ensures branchPr.Some? && branchPr.value.open
    ensures branchPr.value.attestation == Approve || branchPr.value.attestation == Waiver
    ensures Derive(branch, branchPr, openLanePrs, facts, path, solo).step.pr == branchPr.value.number
    ensures solo || branchPr.value.humanApproved
    ensures IsLaneBranch(branch)
  {
  }

  // NoBlindCreatePr (precedence 5): CreatePr is never emitted when the PR state is unknown.
  lemma NoBlindCreatePr(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path,
                        solo: bool)
    requires Pre(branch, branchPr, openLanePrs, facts, path, solo)
    requires !facts.prStateKnown
    ensures Derive(branch, branchPr, openLanePrs, facts, path, solo).step != CreatePr
  {
  }

  // PathClosure (REQ-340): a proposed branch belongs to the configured path's grammar.
  lemma PathClosure(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path,
                    solo: bool)
    requires Pre(branch, branchPr, openLanePrs, facts, path, solo)
    requires Derive(branch, branchPr, openLanePrs, facts, path, solo).step.NewBranch?
    ensures path == Lanes ==> LanesProposal(Derive(branch, branchPr, openLanePrs, facts, path, solo).step.p)
    ensures path == Regulated ==> RegulatedProposal(Derive(branch, branchPr, openLanePrs, facts, path, solo).step.p)
  {
  }

  // PrPrecedence (precedence 1): an open PR on a lane branch always yields one of the four PR substates, in the
  // branch's lane, whatever the facts say.
  lemma PrPrecedence(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path,
                     solo: bool)
    requires Pre(branch, branchPr, openLanePrs, facts, path, solo)
    requires IsLaneBranch(branch) && branchPr.Some? && branchPr.value.open
    ensures var r := Derive(branch, branchPr, openLanePrs, facts, path, solo);
            r.phase in {AwaitingVerifier, AwaitingHumanReview, AwaitingMerge, Blocked}
            && (r.phase == Blocked <==> branchPr.value.attestation == RequestChanges)
            && (r.phase == AwaitingVerifier <==> branchPr.value.attestation == NoMarker)
            && r.lane == LaneOf(branch)
  {
  }

  // Progress (precedence 4): on a lane branch with no PR (and, for build/<slug>-N, a "## Build N" section), when
  // the derived phase p is an artifact phase, supplying its fact (SetFact, the "next fact" function) keeps Pre and
  // moves the derived phase strictly forward in PhaseOrder, in the lane's own order: the new phase stays in the
  // branch's lane and is one of the lane's artifact phases or OpenPr (9), the end of every lane's order. PhaseOrder
  // maps every non-lane phase to 10, so without the last conjunct a jump out of the lane would count as progress.
  lemma Progress(branch: Branch, openLanePrs: seq<PR>, facts: Facts, path: Path, solo: bool)
    requires Pre(branch, None, openLanePrs, facts, path, solo)
    requires IsLaneBranch(branch)
    requires branch.Build? ==> branch.n in facts.buildSections
    requires ArtifactPhase(Derive(branch, None, openLanePrs, facts, path, solo).phase)
    ensures var p := Derive(branch, None, openLanePrs, facts, path, solo).phase;
            Pre(branch, None, openLanePrs, SetFact(facts, p), path, solo)
            && PhaseOrder(Derive(branch, None, openLanePrs, SetFact(facts, p), path, solo).phase) > PhaseOrder(p)
            && (var q := Derive(branch, None, openLanePrs, SetFact(facts, p), path, solo);
                q.lane == LaneOf(branch) && (ArtifactPhase(q.phase) || q.phase == OpenPr))
  {
    var p := Derive(branch, None, openLanePrs, facts, path, solo).phase;
    var f' := SetFact(facts, p);
    LaneProgress(branch, facts);
    LanePhaseKinds(branch, f');
    assert Derive(branch, None, openLanePrs, f', path, solo).phase == LanePhase(branch, f');
  }

  // Progress per lane list: LanePhase moves forward when the fact of the phase it derives is supplied.
  lemma LaneProgress(b: Branch, f: Facts)
    requires IsLaneBranch(b) && ArtifactPhase(LanePhase(b, f))
    ensures PhaseOrder(LanePhase(b, SetFact(f, LanePhase(b, f)))) > PhaseOrder(LanePhase(b, f))
  {
    var q := LanePhase(b, f);
    var l, l' := LaneList(b, f), LaneList(b, SetFact(f, q));
    ListAscending(b, f);
    ListAscending(b, SetFact(f, q));
    if b.Design? && f.specHasTaggedReqs && !f.archComplete {
      // The architecture gate: once the architecture is complete, the phase lies after it in the list.
      assert l'[2] == (Architecture, true);
      ScanBackPassesPresent(l', OpenPr, 2);
    } else {
      assert |l'| == |l| && forall j :: 0 <= j < |l| ==> l'[j] == (l[j].0, l[j].1 || l[j].0 == q);
      ScanBackForward(l, l', OpenPr);
    }
  }

  // Each lane list is strictly ascending in PhaseOrder and lies before OpenPr.
  predicate Ascending(l: seq<(Phase, bool)>, a: Phase) {
    (forall i, j :: 0 <= i < j < |l| ==> PhaseOrder(l[i].0) < PhaseOrder(l[j].0))
    && (forall i :: 0 <= i < |l| ==> PhaseOrder(l[i].0) < PhaseOrder(a))
  }
  lemma ListAscending(b: Branch, f: Facts)
    ensures Ascending(LaneList(b, f), OpenPr)
  {
  }

  // ScanBack's result lies after every present entry.
  lemma ScanBackPassesPresent(l: seq<(Phase, bool)>, a: Phase, k: nat)
    requires Ascending(l, a) && k < |l| && l[k].1
    ensures PhaseOrder(ScanBack(l, a)) > PhaseOrder(l[k].0)
    decreases |l|
  {
    var n := |l| - 1;
    if !l[n].1 {
      assert Ascending(l[..n], l[n].0);
      ScanBackPassesPresent(l[..n], l[n].0, k);
    }
  }

  // Supplying the fact of the phase ScanBack derives (l' is l with that entry present) moves ScanBack forward.
  lemma ScanBackForward(l: seq<(Phase, bool)>, l': seq<(Phase, bool)>, a: Phase)
    requires Ascending(l, a) && ScanBack(l, a) != a
    requires |l'| == |l| && forall j :: 0 <= j < |l| ==> l'[j] == (l[j].0, l[j].1 || l[j].0 == ScanBack(l, a))
    ensures PhaseOrder(ScanBack(l', a)) > PhaseOrder(ScanBack(l, a))
    decreases |l|
  {
    var n := |l| - 1;
    var q := ScanBack(l[..n], l[n].0);
    assert Ascending(l[..n], l[n].0);
    if q != l[n].0 {
      assert !l'[n].1;
      assert l'[..n] == seq(n, j requires 0 <= j < n => (l[j].0, l[j].1 || l[j].0 == q));
      ScanBackForward(l[..n], l'[..n], l[n].0);
    }
  }

  // ---- Further lemmas: the plan's named edge properties ----------------------------------------------------

  // dfe-7: an unknown branch never merges, whatever PR carries its name.
  lemma UnknownBranchNeverMerges(branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path, solo: bool)
    requires Pre(Unknown, branchPr, openLanePrs, facts, path, solo)
    ensures Derive(Unknown, branchPr, openLanePrs, facts, path, solo)
            == Result(NoLane, UnknownBranch, ExplainUnknown(BranchUnknown), NumbersOf(openLanePrs))
  {
  }

  // With no view of PRs, no PR substate is ever claimed.
  lemma UnknownPrStateNeverAwaitsVerifier(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts,
                                          path: Path, solo: bool)
    requires Pre(branch, branchPr, openLanePrs, facts, path, solo)
    requires !facts.prStateKnown
    ensures Derive(branch, branchPr, openLanePrs, facts, path, solo).phase
            !in {AwaitingVerifier, AwaitingHumanReview, AwaitingMerge, Blocked, Merged, Closed}
  {
    if IsLaneBranch(branch) { LanePhaseKinds(branch, facts); }
  }
  // A lane branch's phase is one of its list's artifact phases or OpenPr.
  lemma LanePhaseKinds(b: Branch, f: Facts)
    ensures ArtifactPhase(LanePhase(b, f)) || LanePhase(b, f) == OpenPr
  {
    ScanBackRange(LaneList(b, f), OpenPr);
  }
  lemma ScanBackRange(l: seq<(Phase, bool)>, a: Phase)
    ensures ScanBack(l, a) == a || exists i :: 0 <= i < |l| && ScanBack(l, a) == l[i].0
    decreases |l|
  {
    var n := |l| - 1;
    if |l| > 0 && !l[n].1 {
      ScanBackRange(l[..n], l[n].0);
    }
  }

  // REQ-393 (P5 R4): main in a remote-less instance with nothing built is idle and proposes the path's first branch.
  lemma RemoteLessMainIsIdle(facts: Facts, path: Path, solo: bool)
    requires Pre(Main, None, [], facts, path, solo)
    requires !facts.prStateKnown && facts.unbuilt == [] && facts.untaggedShip.None? && facts.nextVersion.None?
    ensures Derive(Main, None, [], facts, path, solo)
            == Result(NoLane, Idle, NewBranch(if path == Lanes then ProposeDesign else ProposeSpec), {})
  {
  }

  // Precedence 3: other users' open lane PRs are listed, never checked out and never block.
  lemma OtherUsersPrsNeverBlock(openLanePrs: seq<PR>, facts: Facts, path: Path, solo: bool)
    requires Pre(Main, None, openLanePrs, facts, path, solo)
    requires forall i :: 0 <= i < |openLanePrs| ==> !openLanePrs[i].mine
    ensures Derive(Main, None, openLanePrs, facts, path, solo).phase != AwaitingMerge
    ensures !Derive(Main, None, openLanePrs, facts, path, solo).step.Checkout?
  {
    NoOwnNumbers(openLanePrs);
  }
  lemma NoOwnNumbers(prs: seq<PR>)
    requires forall i :: 0 <= i < |prs| ==> !prs[i].mine
    ensures OwnNumbers(prs) == []
  {
    if |prs| > 0 { NoOwnNumbers(prs[1..]); }
  }

  // Precedence 3 (dfe-10): main's Checkout names an open lane PR of the current user, the lowest-numbered such PR,
  // never another user's (checking one out runs its code on the maintainer's machine).
  lemma MainChecksOutLowestOwn(openLanePrs: seq<PR>, facts: Facts, path: Path, solo: bool)
    requires Pre(Main, None, openLanePrs, facts, path, solo)
    requires Derive(Main, None, openLanePrs, facts, path, solo).step.Checkout?
    ensures var n := Derive(Main, None, openLanePrs, facts, path, solo).step.pr;
            (exists i :: 0 <= i < |openLanePrs| && openLanePrs[i].mine && openLanePrs[i].number == n)
            && (forall i :: 0 <= i < |openLanePrs| && openLanePrs[i].mine ==> n <= openLanePrs[i].number)
  {
    var own := OwnNumbers(openLanePrs);
    assert |own| > 0;
    MinOfSpec(own);
    OwnNumbersSpec(openLanePrs, MinOf(own));
    forall i | 0 <= i < |openLanePrs| && openLanePrs[i].mine
      ensures MinOf(own) <= openLanePrs[i].number
    {
      OwnNumbersSpec(openLanePrs, openLanePrs[i].number);
    }
  }
  // OwnNumbers lists exactly the numbers of the current user's PRs.
  lemma OwnNumbersSpec(prs: seq<PR>, x: nat)
    ensures x in OwnNumbers(prs) <==> exists i :: 0 <= i < |prs| && prs[i].mine && prs[i].number == x
    decreases |prs|
  {
    if |prs| > 0 {
      OwnNumbersSpec(prs[1..], x);
      if x in OwnNumbers(prs[1..]) {
        var i :| 0 <= i < |prs[1..]| && prs[1..][i].mine && prs[1..][i].number == x;
        assert prs[i + 1] == prs[1..][i];
      }
      if exists i :: 0 <= i < |prs| && prs[i].mine && prs[i].number == x {
        var i :| 0 <= i < |prs| && prs[i].mine && prs[i].number == x;
        if i > 0 { assert prs[1..][i - 1] == prs[i]; }
      }
    }
  }
  // MinOf is an element of its sequence and no greater than any element.
  lemma MinOfSpec(xs: seq<nat>)
    requires |xs| > 0
    ensures MinOf(xs) in xs && forall i :: 0 <= i < |xs| ==> MinOf(xs) <= xs[i]
    decreases |xs|
  {
    if |xs| > 1 {
      MinOfSpec(xs[1..]);
      var m := MinOf(xs[1..]);
      var j :| 0 <= j < |xs[1..]| && xs[1..][j] == m;
      assert xs[j + 1] == m;
      forall i | 1 <= i < |xs| ensures m <= xs[i] { assert xs[i] == xs[1..][i - 1]; }
    }
  }

  // ---- Fixture lemmas: the model's own result on the kernel fixtures (tests/governance/fixtures/state/) -----
  // Each FixtureNN states the inputs of fixture NN and the Result the model derives; the Python fixture of the same
  // number carries the same inputs (NoFacts with the fields named) and expects the same Result.

  lemma NumbersOfOne(pr: PR)
    ensures NumbersOf([pr]) == {pr.number}
  {
    assert [pr][0] == pr;
  }

  // ScanBack over a list with nothing present is its first phase; after a present entry followed only by missing
  // ones, it is the entry after the present one.
  lemma ScanBackAllMissing(l: seq<(Phase, bool)>, a: Phase)
    requires forall i :: 0 <= i < |l| ==> !l[i].1
    ensures ScanBack(l, a) == if |l| == 0 then a else l[0].0
    decreases |l|
  {
    if |l| > 0 { ScanBackAllMissing(l[..|l| - 1], l[|l| - 1].0); }
  }
  lemma ScanBackAfterPresent(l: seq<(Phase, bool)>, a: Phase, k: nat)
    requires k < |l| && l[k].1 && forall i :: k < i < |l| ==> !l[i].1
    ensures ScanBack(l, a) == if k + 1 < |l| then l[k + 1].0 else a
    decreases |l|
  {
    if k + 1 < |l| { ScanBackAfterPresent(l[..|l| - 1], l[|l| - 1].0, k); }
  }

  // A fixture's inputs satisfy Pre (the twin does not raise) and derive the expected Result.
  predicate Case(branch: Branch, branchPr: Option<PR>, openLanePrs: seq<PR>, facts: Facts, path: Path, solo: bool,
                 want: Result) {
    Pre(branch, branchPr, openLanePrs, facts, path, solo)
    && Derive(branch, branchPr, openLanePrs, facts, path, solo) == want
  }

  const NoFacts := Facts(false, false, false, false, false, {}, false, false, false, false, false, false, false, [],
                         None, None, {})

  // 01 and 02: a Progress witness — design lane, nothing present: brainstorm; supplying the brainstorm (SetFact)
  // derives specify, the next phase in the design lane's order.
  lemma Fixture01()
    ensures Case(Design("habit-tracker"), None, [], NoFacts.(prStateKnown := true), Lanes, true,
                 Result(DesignLane, Brainstorm, RunBrainstorm, {}))
  {
    ScanBackAllMissing(LaneList(Design("habit-tracker"), NoFacts.(prStateKnown := true)), OpenPr);
  }
  lemma Fixture02()
    ensures SetFact(NoFacts.(prStateKnown := true), Brainstorm) == NoFacts.(prStateKnown := true, hasBrainstorm := true)
    ensures Case(Design("habit-tracker"), None, [], NoFacts.(prStateKnown := true, hasBrainstorm := true), Lanes, true,
                 Result(DesignLane, Specify, RunSpecify, {}))
  {
    ScanBackAfterPresent(LaneList(Design("habit-tracker"), NoFacts.(prStateKnown := true, hasBrainstorm := true)),
                         OpenPr, 0);
  }

  // 04: design lane, tagged REQs, architecture incomplete, a plan already present: architecture, not analyze.
  lemma Fixture04()
    ensures Case(Design("habit-tracker"), None, [], NoFacts.(hasBrainstorm := true, hasSpec := true,
                 specHasTaggedReqs := true, hasPlan := true, prStateKnown := true), Lanes, true,
                 Result(DesignLane, Architecture, RunArchitecture, {}))
  {
  }

  // 09: design lane complete, no view of PRs: open-pr, explained, never CreatePr.
  lemma Fixture09()
    ensures Case(Design("habit-tracker"), None, [], NoFacts.(hasBrainstorm := true, hasSpec := true, hasPlan := true,
                 analyzeOk := true), Lanes, true, Result(DesignLane, OpenPr, ExplainUnknown(PrStateUnknown), {}))
  {
  }

  // 20: build lane, its open PR #12 has no marker: awaiting the verifier.
  lemma Fixture20()
    ensures var pr := PR(12, true, false, false, false, NoMarker, true);
            Case(Build("habit-tracker", 1), Some(pr), [pr], NoFacts.(buildSections := {1}, hasSourceDiff := true,
                 prStateKnown := true), Lanes, true, Result(BuildLane, AwaitingVerifier, RunVerifier(12), {12}))
  {
    NumbersOfOne(PR(12, true, false, false, false, NoMarker, true));
  }

  // 22: build lane, open PR #14 approved by the verifier, solo mode: merge.
  lemma Fixture22()
    ensures var pr := PR(14, true, false, false, false, Approve, true);
            Case(Build("habit-tracker", 1), Some(pr), [pr], NoFacts.(buildSections := {1}, hasSourceDiff := true,
                 prStateKnown := true), Lanes, true, Result(BuildLane, AwaitingMerge, Merge(14), {14}))
  {
    NumbersOfOne(PR(14, true, false, false, false, Approve, true));
  }

  // 24: the same PR in team mode with no human approval: awaiting human review, never merge.
  lemma Fixture24()
    ensures var pr := PR(14, true, false, false, false, Approve, true);
            Case(Build("habit-tracker", 1), Some(pr), [pr], NoFacts.(buildSections := {1}, hasSourceDiff := true,
                 prStateKnown := true), Lanes, false, Result(BuildLane, AwaitingHumanReview, RequestReview(14), {14}))
  {
    NumbersOfOne(PR(14, true, false, false, false, Approve, true));
  }

  // 30: main, another user's open lane PR #9 only: idle, #9 listed.
  lemma Fixture30()
    ensures var pr := PR(9, true, false, false, false, NoMarker, false);
            Case(Main, None, [pr], NoFacts.(prStateKnown := true), Lanes, true,
                 Result(NoLane, Idle, NewBranch(ProposeDesign), {9}))
  {
    NumbersOfOne(PR(9, true, false, false, false, NoMarker, false));
    NoOwnNumbers([PR(9, true, false, false, false, NoMarker, false)]);
  }

  // 41: main in a remote-less lanes instance (REQ-393): idle, design first.
  lemma Fixture41()
    ensures Case(Main, None, [], NoFacts, Lanes, true, Result(NoLane, Idle, NewBranch(ProposeDesign), {}))
  {
  }

  // 42: main in a remote-less regulated instance (REQ-393): idle, phase/spec-<slug> first (a regulated PathClosure
  // witness).
  lemma Fixture42()
    ensures Case(Main, None, [], NoFacts, Regulated, true, Result(NoLane, Idle, NewBranch(ProposeSpec), {}))
  {
  }

  // 62: an unknown branch whose PR #7 is approved and human-approved: explained, never merged (dfe-7).
  lemma Fixture62()
    ensures var pr := PR(7, true, false, false, true, Approve, true);
            Case(Unknown, Some(pr), [pr], NoFacts.(prStateKnown := true), Lanes, true,
                 Result(NoLane, UnknownBranch, ExplainUnknown(BranchUnknown), {7}))
  {
    NumbersOfOne(PR(7, true, false, false, true, Approve, true));
  }
}
