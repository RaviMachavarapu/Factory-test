"""scripts/lib/specflow/records.py — the kernels' data model (REQ-322, ADR-002; REQ-341, ADR-003).

Frozen dataclasses and string-valued enums, named exactly as the Dafny models name their datatypes
(verification/factory_v3_2/disposition.dfy, state.dfy), so the Python twins (disposition.py, state.py) and the models
share vocabulary. The disposition records are the pure inputs and outputs of decide(); the state records (Path,
Attestation, Branch, PR, Facts, Step, Result, ...) are the pure inputs and output of state.derive() — nothing here is
persisted, since pipeline state is derived from branches, PRs and the tree (art-branch-as-state).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import Enum
from typing import Any, Optional


class Severity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class Status(Enum):
    OPEN = "open"
    FIXED = "fixed"
    ACCEPTED = "accepted"
    DEFERRED = "deferred"


class Rule(Enum):
    SET_EQUALITY = "set_equality"
    SEVERE_NOT_FIXED = "severe_not_fixed"
    MEDIUM_CAP = "medium_cap"
    CARRY_FORWARD = "carry_forward"
    EXPIRY_WINDOW = "expiry_window"


@dataclass(frozen=True)
class Finding:
    id: str
    severity: Severity
    cvss_vector: str


@dataclass(frozen=True)
class Entry:
    id: str
    status: Status
    owner: str  # "" means none
    expiry: date | None
    rationale: str
    reclassified_by: str | None


@dataclass(frozen=True)
class PriorEntry:
    id: str
    severity: Severity
    status: Status
    expiry: date | None
    version: str


@dataclass(frozen=True)
class Violation:
    id: str
    rule: Rule


@dataclass(frozen=True)
class Verdict:
    passed: bool
    violations: tuple[Violation, ...]  # sorted by (id, rule.value)


# ---- The state kernel's records (REQ-341, ADR-003; twin of verification/factory_v3_2/state.dfy) ------------------


class Path(Enum):
    lanes = "lanes"
    regulated = "regulated"


class Attestation(Enum):  # model: NoMarker | Approve | RequestChanges | Waiver
    none = "none"
    approve = "approve"
    request_changes = "request_changes"
    waiver = "waiver"


class BranchKind(Enum):
    Main = "Main"
    Design = "Design"
    Build = "Build"
    BuildSec = "BuildSec"
    Ship = "Ship"
    Patch = "Patch"
    PhaseSpec = "PhaseSpec"
    PhaseArch = "PhaseArch"
    PhasePlan = "PhasePlan"
    Impl = "Impl"
    ImplSec = "ImplSec"
    PhaseValidate = "PhaseValidate"
    PhaseSecurity = "PhaseSecurity"
    PhaseRelease = "PhaseRelease"
    Unknown = "Unknown"


@dataclass(frozen=True)
class Branch:
    kind: BranchKind
    slug: str = ""
    n: int = 0
    id: str = ""
    version: str = ""
    plan: str = ""
    name: str = ""


@dataclass(frozen=True)
class PR:
    number: int
    open: bool
    merged: bool
    closed: bool
    human_approved: bool
    attestation: Attestation
    mine: bool


class RegShip(Enum):
    validate = "validate"
    security = "security"
    release = "release"


@dataclass(frozen=True)
class Facts:
    has_brainstorm: bool = False
    has_spec: bool = False
    spec_has_tagged_reqs: bool = False
    arch_complete: bool = False
    has_plan: bool = False
    build_sections: frozenset = frozenset()
    analyze_ok: bool = False
    has_source_diff: bool = False
    gates_pass: bool = False
    has_security_docs: bool = False
    has_release_docs: bool = False
    signing_key_present: bool = False
    pr_state_known: bool = False
    unbuilt: tuple = ()  # tuple[tuple[str, int], ...], sorted by (slug, n)
    untagged_ship: Optional[str] = None
    next_version: Optional[str] = None
    ship_phases_merged: frozenset = frozenset()  # frozenset[RegShip]


class Lane(Enum):
    none = "none"
    design = "design"
    build = "build"
    ship = "ship"
    spec = "spec"
    arch = "arch"
    plan = "plan"
    impl = "impl"
    validate = "validate"
    security = "security"
    release = "release"


class Phase(Enum):
    brainstorm = "brainstorm"
    specify = "specify"
    architecture = "architecture"
    plan = "plan"
    analyze = "analyze"
    implement = "implement"
    gates = "gates"
    security = "security"
    release = "release"
    open_pr = "open-pr"
    unknown_build = "unknown-build"
    awaiting_verifier = "awaiting-verifier"
    awaiting_human_review = "awaiting-human-review"
    awaiting_merge = "awaiting-merge"
    blocked = "blocked"
    merged = "merged"
    closed = "closed"
    tag = "tag"
    next_build = "next-build"
    ready_to_ship = "ready-to-ship"
    idle = "idle"
    unknown_branch = "unknown-branch"


class ProposalKind(Enum):
    ProposeDesign = "ProposeDesign"
    ProposeBuild = "ProposeBuild"
    ProposeShip = "ProposeShip"
    ProposeSpec = "ProposeSpec"
    ProposeImpl = "ProposeImpl"
    ProposeValidate = "ProposeValidate"
    ProposeSecurity = "ProposeSecurity"
    ProposeRelease = "ProposeRelease"


@dataclass(frozen=True)
class Proposal:
    kind: ProposalKind
    slug: str = ""
    n: int = 0
    version: str = ""


class TargetKind(Enum):
    Section = "Section"
    SecFix = "SecFix"
    PatchTier = "PatchTier"
    PlanTarget = "PlanTarget"


@dataclass(frozen=True)
class ImplTarget:
    kind: TargetKind
    n: int = 0
    id: str = ""
    plan: str = ""
    name: str = ""


class Why(Enum):
    PrStateUnknown = "PrStateUnknown"
    BranchUnknown = "BranchUnknown"
    BuildUnknown = "BuildUnknown"
    PrClosed = "PrClosed"


class StepKind(Enum):
    RunBrainstorm = "RunBrainstorm"
    RunSpecify = "RunSpecify"
    RunArchitecture = "RunArchitecture"
    RunPlan = "RunPlan"
    RunAnalyze = "RunAnalyze"
    RunImplement = "RunImplement"
    RunGates = "RunGates"
    RunSecurityReview = "RunSecurityReview"
    RunRelease = "RunRelease"
    CreatePr = "CreatePr"
    RunVerifier = "RunVerifier"
    RequestReview = "RequestReview"
    Merge = "Merge"
    Checkout = "Checkout"
    CheckoutMain = "CheckoutMain"
    NewBranch = "NewBranch"
    AddressFindings = "AddressFindings"
    TagRelease = "TagRelease"
    ExplainUnknown = "ExplainUnknown"


@dataclass(frozen=True)
class Step:
    kind: StepKind
    pr: int = 0
    proposal: Optional[Proposal] = None
    target: Optional[ImplTarget] = None
    version: str = ""
    why: Optional[Why] = None


@dataclass(frozen=True)
class Result:
    lane: Lane
    phase: Phase
    step: Step
    open_lanes: tuple  # tuple[int, ...], sorted ascending


# ---- JSON helpers (pure): the JSON spelling of a kind is the model's constructor name --------------------------------


def _drop_defaults(obj: Any, skip: tuple = ("kind",)) -> dict:
    out = {}
    for f in obj.__dataclass_fields__:
        v = getattr(obj, f)
        if f in skip:
            continue
        if v in ("", 0, None):
            continue
        out[f] = v
    return out


def branch_to_json(b: Branch) -> dict:
    return {"kind": b.kind.value, **_drop_defaults(b)}


def branch_from_json(d: dict) -> Branch:
    return Branch(BranchKind(d["kind"]), d.get("slug", ""), d.get("n", 0), d.get("id", ""), d.get("version", ""),
                  d.get("plan", ""), d.get("name", ""))


def pr_from_json(d: dict) -> PR:
    return PR(int(d["number"]), bool(d.get("open", False)), bool(d.get("merged", False)),
              bool(d.get("closed", False)), bool(d.get("human_approved", False)),
              Attestation(d.get("attestation", "none")), bool(d.get("mine", False)))


def pr_to_json(p: PR) -> dict:
    return {"number": p.number, "open": p.open, "merged": p.merged, "closed": p.closed,
            "human_approved": p.human_approved, "attestation": p.attestation.value, "mine": p.mine}


def facts_from_json(d: dict) -> Facts:
    kw: dict = {}
    for f in Facts.__dataclass_fields__:
        if f not in d:
            continue
        v = d[f]
        if f == "build_sections":
            v = frozenset(int(x) for x in v)
        elif f == "unbuilt":
            v = tuple((str(x[0]), int(x[1])) for x in v)
        elif f == "ship_phases_merged":
            v = frozenset(RegShip(x) for x in v)
        kw[f] = v
    return Facts(**kw)


def proposal_to_json(p: Proposal) -> dict:
    return {"kind": p.kind.value, **_drop_defaults(p)}


def proposal_from_json(d: dict) -> Proposal:
    return Proposal(ProposalKind(d["kind"]), d.get("slug", ""), d.get("n", 0), d.get("version", ""))


def target_to_json(t: ImplTarget) -> dict:
    return {"kind": t.kind.value, **_drop_defaults(t)}


def target_from_json(d: dict) -> ImplTarget:
    return ImplTarget(TargetKind(d["kind"]), d.get("n", 0), d.get("id", ""), d.get("plan", ""), d.get("name", ""))


def step_to_json(s: Step) -> dict:
    out: dict = {"kind": s.kind.value}
    if s.pr:
        out["pr"] = s.pr
    if s.proposal is not None:
        out["proposal"] = proposal_to_json(s.proposal)
    if s.target is not None:
        out["target"] = target_to_json(s.target)
    if s.version:
        out["version"] = s.version
    if s.why is not None:
        out["why"] = s.why.value
    return out


def step_from_json(d: dict) -> Step:
    return Step(StepKind(d["kind"]), d.get("pr", 0),
                proposal_from_json(d["proposal"]) if "proposal" in d else None,
                target_from_json(d["target"]) if "target" in d else None,
                d.get("version", ""), Why(d["why"]) if "why" in d else None)


def result_to_json(r: Result) -> dict:
    return {"lane": r.lane.value, "phase": r.phase.value, "step": step_to_json(r.step),
            "open_lanes": list(r.open_lanes)}
