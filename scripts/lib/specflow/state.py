"""scripts/lib/specflow/state.py — ADR-003's pipeline-state derivation (REQ-341, REQ-385, REQ-340).

The Python twin of verification/factory_v3_2/state.dfy: one function per model function, named as the model's in
snake_case, over the pure records in records.py. derive() is a total function on inputs satisfying pre() and raises
ValueError outside it. Pure: no I/O, no strings for the user (render_step in the wrapper owns those), no imports beyond
records and the stdlib (dataclasses, enum, typing) — the wrapper (pipeline.py) does the I/O and computes Facts.
"""

from __future__ import annotations

from dataclasses import replace
from typing import Optional

from records import (
    PR,
    Attestation,
    Branch,
    BranchKind as K,
    Facts,
    ImplTarget,
    Lane,
    Path,
    Phase,
    Proposal,
    ProposalKind as PK,
    RegShip,
    Result,
    Step,
    StepKind as SK,
    TargetKind,
    Why,
)

_LANE_BRANCHES = frozenset(k for k in K if k not in (K.Main, K.Unknown))


def _well_formed_pr(pr: PR) -> bool:
    states = (pr.open, pr.merged, pr.closed)
    return pr.number >= 1 and sum(1 for s in states if s) == 1


def _pre_violation(branch: Branch, branch_pr: Optional[PR], open_lane_prs, facts: Facts, path: Path,
                   solo: bool) -> Optional[str]:
    """The first violated precondition clause, or None (the model's Pre)."""
    if branch_pr is not None and not _well_formed_pr(branch_pr):
        return "the branch PR is not well formed (exactly one of open/merged/closed, number >= 1)"
    for p in open_lane_prs:
        if not _well_formed_pr(p) or not p.open:
            return "an open lane PR is not well formed and open"
    nums = [p.number for p in open_lane_prs]
    if len(set(nums)) != len(nums):
        return "open lane PR numbers are not distinct"
    if branch.kind is K.Main and branch_pr is not None:
        return "Main has no branch PR"
    if not facts.pr_state_known and (branch_pr is not None or len(open_lane_prs) > 0):
        return "pr_state_known is false but a PR is given"
    if branch.kind is K.Build and branch.n < 1:
        return "a Build branch needs n >= 1"
    if any(k < 1 for k in facts.build_sections):
        return "a build section number is below 1"
    if any(n < 1 for (_s, n) in facts.unbuilt):
        return "an unbuilt section number is below 1"
    ub = list(facts.unbuilt)
    if any(ub[i] > ub[i + 1] for i in range(len(ub) - 1)):
        return "unbuilt is not sorted ascending by (slug, n)"
    if facts.spec_has_tagged_reqs and not facts.has_spec:
        return "spec_has_tagged_reqs without has_spec"
    if facts.untagged_ship is not None and facts.untagged_ship == "":
        return "untagged_ship is empty"
    if facts.next_version is not None and facts.next_version == "":
        return "next_version is empty"
    return None


def pre(branch: Branch, branch_pr: Optional[PR], open_lane_prs, facts: Facts, path: Path, solo: bool) -> bool:
    return _pre_violation(branch, branch_pr, open_lane_prs, facts, path, solo) is None


def numbers_of(prs) -> tuple:
    return tuple(sorted({p.number for p in prs}))


def own_numbers(prs) -> tuple:
    """The numbers of the current user's PRs, in the given order."""
    return tuple(p.number for p in prs if p.mine)


def min_of(xs) -> int:
    return min(xs)


_LANE_OF = {
    K.Design: Lane.design, K.Build: Lane.build, K.BuildSec: Lane.build, K.Patch: Lane.build, K.Ship: Lane.ship,
    K.PhaseSpec: Lane.spec, K.PhaseArch: Lane.arch, K.PhasePlan: Lane.plan, K.Impl: Lane.impl,
    K.ImplSec: Lane.impl, K.PhaseValidate: Lane.validate, K.PhaseSecurity: Lane.security,
    K.PhaseRelease: Lane.release, K.Main: Lane.none, K.Unknown: Lane.none,
}


def lane_of(b: Branch) -> Lane:
    return _LANE_OF[b.kind]


def lanes_proposal(p: Proposal) -> bool:
    return p.kind in (PK.ProposeDesign, PK.ProposeBuild, PK.ProposeShip)


def regulated_proposal(p: Proposal) -> bool:
    return p.kind in (PK.ProposeSpec, PK.ProposeImpl, PK.ProposeValidate, PK.ProposeSecurity, PK.ProposeRelease)


def lane_list(b: Branch, f: Facts) -> list:
    """The lane's ordered artifact list: (the phase that produces it, whether it is present)."""
    P = Phase
    k = b.kind
    if k is K.Design:
        out = [(P.brainstorm, f.has_brainstorm), (P.specify, f.has_spec)]
        if f.spec_has_tagged_reqs:
            out.append((P.architecture, f.arch_complete))
        return out + [(P.plan, f.has_plan), (P.analyze, f.analyze_ok)]
    if k is K.PhaseSpec:
        return [(P.brainstorm, f.has_brainstorm), (P.specify, f.has_spec)]
    if k is K.PhaseArch:
        return [(P.architecture, f.arch_complete)]
    if k is K.PhasePlan:
        return [(P.plan, f.has_plan), (P.analyze, f.analyze_ok)]
    if k in (K.Build, K.BuildSec, K.Patch, K.Impl, K.ImplSec):
        return [(P.implement, f.has_source_diff)]
    if k is K.PhaseValidate:
        return [(P.gates, f.gates_pass)]
    if k is K.Ship:
        return [(P.security, f.has_security_docs), (P.release, f.has_release_docs)]
    if k is K.PhaseSecurity:
        return [(P.security, f.has_security_docs)]
    if k is K.PhaseRelease:
        return [(P.release, f.has_release_docs)]
    return []


def first_missing_after_last_present(lst) -> Phase:
    """The entry after the last present one, or open-pr when none follows."""
    after = Phase.open_pr
    for phase, present in reversed(lst):
        if present:
            return after
        after = phase
    return after


def lane_phase(b: Branch, f: Facts) -> Phase:
    if b.kind is K.Design and f.spec_has_tagged_reqs and not f.arch_complete:
        return Phase.architecture
    return first_missing_after_last_present(lane_list(b, f))


def impl_target_of(b: Branch) -> ImplTarget:
    if b.kind is K.Build:
        return ImplTarget(TargetKind.Section, n=b.n)
    if b.kind in (K.BuildSec, K.ImplSec):
        return ImplTarget(TargetKind.SecFix, id=b.id)
    if b.kind is K.Impl:
        return ImplTarget(TargetKind.PlanTarget, plan=b.plan, name=b.name)
    return ImplTarget(TargetKind.PatchTier)


_PHASE_STEP = {
    Phase.brainstorm: SK.RunBrainstorm, Phase.specify: SK.RunSpecify, Phase.architecture: SK.RunArchitecture,
    Phase.plan: SK.RunPlan, Phase.analyze: SK.RunAnalyze, Phase.gates: SK.RunGates,
    Phase.security: SK.RunSecurityReview, Phase.release: SK.RunRelease,
}


def phase_step(phase: Phase, b: Branch, f: Facts) -> Step:
    if phase in _PHASE_STEP:
        return Step(_PHASE_STEP[phase])
    if phase is Phase.implement:
        return Step(SK.RunImplement, target=impl_target_of(b))
    if phase is Phase.open_pr:
        return Step(SK.CreatePr) if f.pr_state_known else Step(SK.ExplainUnknown, why=Why.PrStateUnknown)
    return Step(SK.ExplainUnknown, why=Why.BranchUnknown)


def pr_substate(lane: Lane, pr: PR, solo: bool, ol: tuple) -> Result:
    if pr.attestation is Attestation.request_changes:
        return Result(lane, Phase.blocked, Step(SK.AddressFindings, pr=pr.number), ol)
    if pr.attestation is Attestation.none:
        return Result(lane, Phase.awaiting_verifier, Step(SK.RunVerifier, pr=pr.number), ol)
    if solo or pr.human_approved:
        return Result(lane, Phase.awaiting_merge, Step(SK.Merge, pr=pr.number), ol)
    return Result(lane, Phase.awaiting_human_review, Step(SK.RequestReview, pr=pr.number), ol)


def regulated_ship_proposal(m) -> Proposal:
    if RegShip.validate not in m:
        return Proposal(PK.ProposeValidate)
    if RegShip.security not in m:
        return Proposal(PK.ProposeSecurity)
    return Proposal(PK.ProposeRelease)


def main_result(prs, f: Facts, path: Path) -> Result:
    lanes = path is Path.lanes
    ol = numbers_of(prs)
    own = own_numbers(prs)
    if own:
        return Result(Lane.none, Phase.awaiting_merge, Step(SK.Checkout, pr=min_of(own)), ol)
    if f.untagged_ship is not None:
        return Result(Lane.ship if lanes else Lane.release, Phase.tag,
                      Step(SK.TagRelease, version=f.untagged_ship), ol)
    if f.unbuilt:
        slug, n = f.unbuilt[0]
        return Result(Lane.none, Phase.next_build,
                      Step(SK.NewBranch, proposal=Proposal(PK.ProposeBuild if lanes else PK.ProposeImpl, slug=slug,
                                                           n=n)), ol)
    if f.next_version is not None:
        prop = Proposal(PK.ProposeShip, version=f.next_version) if lanes else regulated_ship_proposal(
            f.ship_phases_merged)
        return Result(Lane.none, Phase.ready_to_ship, Step(SK.NewBranch, proposal=prop), ol)
    return Result(Lane.none, Phase.idle,
                  Step(SK.NewBranch, proposal=Proposal(PK.ProposeDesign if lanes else PK.ProposeSpec)), ol)


def derive(branch: Branch, branch_pr: Optional[PR], open_lane_prs, facts: Facts, path: Path, solo: bool) -> Result:
    bad = _pre_violation(branch, branch_pr, open_lane_prs, facts, path, solo)
    if bad is not None:
        raise ValueError(bad)
    ol = numbers_of(open_lane_prs)
    if branch.kind is K.Unknown:
        return Result(Lane.none, Phase.unknown_branch, Step(SK.ExplainUnknown, why=Why.BranchUnknown), ol)
    if branch.kind is K.Main:
        return main_result(open_lane_prs, facts, path)
    lane = lane_of(branch)
    if branch_pr is not None and branch_pr.open:
        return pr_substate(lane, branch_pr, solo, ol)
    if branch_pr is not None and branch_pr.merged:
        return Result(lane, Phase.merged, Step(SK.CheckoutMain), ol)
    if branch_pr is not None:
        return Result(lane, Phase.closed, Step(SK.ExplainUnknown, why=Why.PrClosed), ol)
    if branch.kind is K.Build and branch.n not in facts.build_sections:
        return Result(Lane.build, Phase.unknown_build, Step(SK.ExplainUnknown, why=Why.BuildUnknown), ol)
    p = lane_phase(branch, facts)
    return Result(lane, p, phase_step(p, branch, facts), ol)


_ORDER = {Phase.brainstorm: 0, Phase.specify: 1, Phase.architecture: 2, Phase.plan: 3, Phase.analyze: 4,
          Phase.implement: 5, Phase.gates: 6, Phase.security: 7, Phase.release: 8, Phase.open_pr: 9}


def phase_order(p: Phase) -> int:
    return _ORDER.get(p, 10)


_FACT_OF = {Phase.brainstorm: "has_brainstorm", Phase.specify: "has_spec", Phase.architecture: "arch_complete",
            Phase.plan: "has_plan", Phase.analyze: "analyze_ok", Phase.implement: "has_source_diff",
            Phase.gates: "gates_pass", Phase.security: "has_security_docs", Phase.release: "has_release_docs"}


def set_fact(f: Facts, phase: Phase) -> Facts:
    """Supply the artifact that phase produces."""
    return replace(f, **{_FACT_OF[phase]: True}) if phase in _FACT_OF else f
