"""scripts/lib/specflow/pipeline.py — the /next wrapper's pure layer (REQ-341, REQ-385, REQ-340, REQ-308).

parse_branch turns a branch name into the kernel's Branch record (total, never raises); render_step turns a Step into
the one line /next prints; confirmation_point names the guided profile's pause for a Result; GLOSSARY_TERMS and
terms_for link the terms /next prints to docs/GLOSSARY.md. Every function here is pure: no I/O. The kernel's
derivation is state.py (the twin of verification/factory_v3_2/state.dfy); this module owns every user-facing string
(ADR-003: strings stay out of the kernel). The derive subcommand (the second half of this file) is the impure layer:
it reads the configuration, the branch and the tree, computes the Facts the branch's lane reads, calls state.derive and
prints the result. It writes nothing. CLI: `python3 pipeline.py derive [...]` and `python3 pipeline.py parse-branch NAME`.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import attestation  # noqa: E402
import config  # noqa: E402
import floor  # noqa: E402
import frontmatter  # noqa: E402
import packinfo  # noqa: E402
import release_gate  # noqa: E402
import signers  # noqa: E402
import state  # noqa: E402
from records import (  # noqa: E402
    Attestation,
    Branch,
    BranchKind as K,
    Facts,
    Lane,
    PR,
    Path as PathKind,
    Phase,
    Proposal,
    ProposalKind as PK,
    RegShip,
    Result,
    Step,
    StepKind as SK,
    TargetKind,
    Why,
    branch_to_json,
    result_to_json,
    step_to_json,
)

# Copied, not imported: this module must not depend on the disposition gate (its VERSION_RE grammar).
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$")
_TOKEN = r"[A-Za-z0-9][A-Za-z0-9._-]*"
_TOKEN_RE = re.compile("^" + _TOKEN + "$")
_BUILD_RE = re.compile("^build/(" + _TOKEN + r")-([1-9][0-9]*)$")
_IMPL_RE = re.compile("^impl/plan-([0-9]+[a-z]?)-(" + _TOKEN + ")$")


def _tok(s: str) -> bool:
    return bool(_TOKEN_RE.match(s))


def _slug(s: str) -> bool:
    """A lane or phase slug: a token that does not start with sec- — build/sec-<id> is the back-edge's name, so a
    design slug sec-x would make its build branch build/sec-x-N parse as BuildSec (P5 final review, dfe-7)."""
    return _tok(s) and not s.startswith("sec-")


def reserved_slug(name: str) -> bool:
    """A design/, patch/ or phase/{spec,arch,plan}- branch whose slug starts with sec- (Unknown, explained)."""
    for lead in ("design/", "patch/", "phase/spec-", "phase/arch-", "phase/plan-"):
        if isinstance(name, str) and name.startswith(lead) and name[len(lead):].startswith("sec-"):
            return True
    return False


def base_name(ref: Optional[str]) -> str:
    """The base branch a base ref names: `refs/remotes/origin/<b>` (ci.yml's SPECFLOW_BASE_REF since Build 2's fix wave 2:
    a tag named origin/<b> shadows the short name) and `origin/<b>` give `<b>`; any other ref is itself; none gives main."""
    if not ref:
        return "main"
    for prefix in ("refs/remotes/origin/", "origin/"):
        if ref.startswith(prefix):
            return ref[len(prefix):]
    return ref


def parse_branch(name: str) -> Branch:
    """Total over both paths' branch names; anything else is Unknown."""
    unknown = Branch(K.Unknown)
    if not isinstance(name, str):
        return unknown
    if name == "main":
        return Branch(K.Main)
    if name in ("phase/validate", "phase/security", "phase/release"):
        return Branch({"validate": K.PhaseValidate, "security": K.PhaseSecurity, "release": K.PhaseRelease}[name[6:]])
    if "/" not in name:
        return unknown
    prefix, rest = name.split("/", 1)
    if prefix == "design" and _slug(rest):
        return Branch(K.Design, slug=rest)
    if prefix == "patch" and _slug(rest):
        return Branch(K.Patch, slug=rest)
    if prefix == "ship" and VERSION_RE.match(rest):
        return Branch(K.Ship, version=rest)
    if prefix == "build":
        if rest.startswith("sec-") and _tok(rest[4:]):
            return Branch(K.BuildSec, id=rest[4:])
        m = _BUILD_RE.match(name)
        if m:
            return Branch(K.Build, slug=m.group(1), n=int(m.group(2)))
        return unknown
    if prefix == "impl":
        if rest.startswith("sec-") and _tok(rest[4:]):
            return Branch(K.ImplSec, id=rest[4:])
        m = _IMPL_RE.match(name)
        if m:
            return Branch(K.Impl, plan=m.group(1), name=m.group(2))
        return unknown
    if prefix == "phase":
        for lead, kind in (("spec-", K.PhaseSpec), ("arch-", K.PhaseArch), ("plan-", K.PhasePlan)):
            if rest.startswith(lead) and _slug(rest[len(lead):]):
                return Branch(kind, slug=rest[len(lead):])
    return unknown


@dataclass(frozen=True)
class RenderCtx:
    repo: str
    branch: str
    base: str
    slug: str
    version: str
    plan_path: str
    spec_slug: str
    n: int = 0
    stacked: tuple = ()
    head_oid: str = ""
    base_pr: int = 0  # the open PR (this repository's) whose head is a stacked PR's base; 0 when none is known


# The verifier bootstrap pipes main's reviewed copy of the script into bash for EVERY PR (the SEC-004 back-edge; REQ-385
# as amended): a stacked PR's base is a branch no review has approved, which the PR's author chose, so its
# run-verifier.sh is never piped into bash on the maintainer's workstation. main is read by its full ref (P6 build 3; PR
# #54 verifier run 2, finding 3): git resolves a short name's refs/tags/<name> before refs/remotes/<name>, so a tag
# named origin/main that git fetch auto-follows into the clone would otherwise choose the script. run-verifier.sh itself
# reads the PR's base from gh and reviews against it.
_VERIFIER_OBJ = "refs/remotes/origin/main:scripts/run-verifier.sh"


def _verifier_line(pr: int, ctx: RenderCtx) -> str:
    out = (
        "In a second terminal, not inside Claude — open a new terminal window (Terminal.app or your shell) and run: "
        f"cd {shlex.quote(ctx.repo)} && git show {_VERIFIER_OBJ} | bash -s -- {pr}; "
        f'when it prints "Findings posted to PR #{pr}", return here and run /next.'
    )
    if ctx.base != "main":
        # The base name is chosen by whoever opened or retargeted the PR, and git allows ; $() and backticks in a
        # branch name: it is shell-quoted in this prose too, since the user pastes from this line (P5 final review).
        base = shlex.quote(ctx.base)
        if ctx.base_pr:
            out += (f" Note: this PR is stacked on {base}: the base PR #{ctx.base_pr} is unreviewed; its diff is "
                    "reviewed by its own PR, and the command above runs main's reviewed run-verifier.sh, never the "
                    f"base's — merge #{ctx.base_pr} first, then retarget this PR: after the merge commit /next prints for "
                    f"#{ctx.base_pr} this PR's diff and its marker carry over; after a squash merge, run the verifier "
                    "again.")
        else:
            out += (f" Note: this PR is stacked on {base}, which is unreviewed and has no open PR in this view; its "
                    "diff is reviewed by its own PR, and the command above runs main's reviewed run-verifier.sh, "
                    "never the base's.")
    return out


def _merge_line(pr: int, ctx: RenderCtx) -> str:
    # Bound to the head whose attestation was judged: gh refuses the merge if the PR's head has moved since
    # (--match-head-commit), so a push after the APPROVE never merges unattested (P5 final review).
    head = ctx.head_oid if re.fullmatch(r"[0-9a-f]{40}", ctx.head_oid or "") else "HEAD_SHA_UNKNOWN"
    bind = f"--match-head-commit {head}"
    if not ctx.stacked:
        return f"gh pr merge {pr} --squash {bind}"
    # PR #48 verifier run 4, finding 6: only shell commands on this line, joined by ' && ' in the order they must run —
    # the merge commit FIRST, with no --delete-branch (the branch survives, the stacked PR is not auto-closed, and
    # merge-base(stacked head, main) stays the branch tip its marker recorded, so its APPROVE is not base-mismatch),
    # then each stacked PR retargeted to THIS PR's own base (main, or the branch this PR is itself stacked on — a
    # retarget to main from a nested stack would turn the stacked PR's marker base-mismatch; wave-4 re-review low 1),
    # shell-quoted as the verifier line's base is; the explanation is stacked_merge_note's, printed as a note line.
    base = shlex.quote(ctx.base)
    return " && ".join([f"gh pr merge {pr} --merge {bind}"] + [f"gh pr edit {m} --base {base}" for m in ctx.stacked])


def stacked_merge_note(ctx: RenderCtx) -> Optional[str]:
    """The prose that goes with a stacked merge line (a notes entry, never part of the command); None when nothing is
    stacked on the branch."""
    if not ctx.stacked:
        return None
    prs = ", ".join(f"#{m}" for m in ctx.stacked)
    upd = " / ".join(f"gh pr update-branch {m}" for m in ctx.stacked)
    many = len(ctx.stacked) > 1
    return (f"{'PRs' if many else 'PR'} {prs} {'are' if many else 'is'} stacked on this branch: the merge step is "
            f"{'several commands' if many else 'two commands'} run in order — this PR merges first, with a merge "
            "commit and without deleting this branch, which keeps this branch's commits out of the stacked PR's diff "
            "and keeps the merge base its verifier marker recorded (a retarget before the merge would make that "
            f"marker base-mismatch); {'each' if many else 'it'} is then retargeted to {ctx.base} (this PR's own base); "
            f"never delete this branch before the retarget; where {ctx.base}'s protection requires branches to be up to "
            f"date, update the stacked PR afterwards ({upd}) before it can merge — the update creates a new head, so the "
            "stacked PR needs a fresh verifier run (/next shows awaiting-verifier)")


def _new_branch(p: Optional[Proposal]) -> str:
    if p is None:
        return "no branch to propose"
    k = p.kind
    if k is PK.ProposeDesign:
        return "git checkout -b design/<slug> (choose a short name for the idea), then run /superpowers:brainstorming"
    if k is PK.ProposeSpec:
        return "git checkout -b phase/spec-<slug> (choose a short name for the idea), then run /superpowers:brainstorming"
    if k in (PK.ProposeBuild, PK.ProposeImpl):
        # PR #48 verifier run 3 (code low c): the slug comes from a plan's file name, so it is checked as a branch-name
        # token and the branch name shell-quoted; a slug that fails renders no command.
        if not _slug(p.slug or ""):
            return bad_plan_slug_text(p.slug or "", None)
        name = f"build/{p.slug}-{p.n}" if k is PK.ProposeBuild else f"impl/plan-{p.n}-{p.slug}"
        return f"git checkout -b {shlex.quote(name)}"
    if k is PK.ProposeShip:
        return f"git checkout -b ship/{p.version}"
    return {
        PK.ProposeValidate: "git checkout -b phase/validate",
        PK.ProposeSecurity: "git checkout -b phase/security",
        PK.ProposeRelease: "git checkout -b phase/release",
    }[k]


def bad_plan_slug_text(slug: str, path: Optional[str]) -> str:
    """The explanation for a plan whose file-name slug is not a branch-name token (never a command)."""
    where = path or f"the plan with slug {slug!r}"
    return (f"{where}: its slug {slug!r} is not a branch-name token ([A-Za-z0-9][A-Za-z0-9._-]*, not starting with "
            "sec-), so /next renders no branch command for it — rename the plan file through a design PR")


def guard_plan_slug(result: Result, bad_plans: dict) -> tuple:
    """(result, text): a NewBranch proposing a build of a plan whose slug fails _slug becomes ExplainUnknown in state
    build unknown-build (never next-build: nothing is proposed; scoped re-review N4) — the lane state.dfy's UnknownBuild
    row uses; a wrapper-side fail-safe outside the kernel (round 3b re-review D2) — its text naming the plan file (PR #48
    verifier run 3, code low c); any other result is returned unchanged, text None."""
    st_, p = result.step, result.step.proposal
    if st_.kind is not SK.NewBranch or p is None or p.kind not in (PK.ProposeBuild, PK.ProposeImpl) \
            or _slug(p.slug or ""):
        return result, None
    return (Result(Lane.build, Phase.unknown_build, Step(SK.ExplainUnknown), result.open_lanes),
            bad_plan_slug_text(p.slug or "", bad_plans.get(p.slug)))


def guard_release_version(result: Result, bad_release: Optional[tuple], lanes: bool) -> tuple:
    """(result, text): on main, a merged, unreleased phase/release PR whose docs/releases/<v>-notes.md names no release
    version (VERSION_RE, as ship/<version>), with no later merged phase/release PR naming a valid one, derives
    ExplainUnknown in the tag phase, its text naming the file: /next cannot tell whether that release is tagged (scoped
    re-review N5). The lane mirrors the kernel's tag row — ship on the lanes path, release on the regulated path — a
    wrapper-side fail-safe outside state.dfy (round 3b re-review D2). Without one: the result unchanged, text None."""
    if bad_release is None:
        return result, None
    path, number = bad_release
    return (Result(Lane.ship if lanes else Lane.release, Phase.tag, Step(SK.ExplainUnknown), result.open_lanes),
            f"PR #{number} merged {path!r}, whose version is not a release version (<major>.<minor>.<patch>"
            "[-<pre>]): /next cannot tell whether that release is tagged — a later reviewed phase/release PR that "
            "adds the notes file under its version (docs/releases/<version>-notes.md) clears this, and so does "
            "that release's merge commit being in a v<version> tag; then run /next")


def _implement(step: Step, ctx: RenderCtx) -> str:
    t = step.target
    if t is None:
        return f"/superpowers:subagent-driven-development on {ctx.plan_path} (test first, art-test-first)"
    if t.kind is TargetKind.Section:
        return (
            f'/superpowers:subagent-driven-development for "## Build {t.n}" of {ctx.plan_path} '
            "(test first, art-test-first)"
        )
    if t.kind is TargetKind.SecFix:
        return (
            f"/superpowers:subagent-driven-development for the fix of {t.id} in {ctx.plan_path} "
            "(the back-edge, art-threat-driven-security; test first, art-test-first)"
        )
    if t.kind is TargetKind.PatchTier:
        return "write the spec delta and its implementation, test first (art-test-first), in this one patch PR"
    return f"/superpowers:subagent-driven-development on the tasks of {ctx.plan_path} (test first, art-test-first)"


def _explain(why: Optional[Why], ctx: RenderCtx) -> str:
    if why is Why.PrStateUnknown:
        return "cannot see PRs: check gh auth status and the remote (git remote -v), then run /next"
    if why is Why.BuildUnknown:
        return 'the plan has no "## Build <n>": add it through a design PR, or check out an existing build'
    if why is Why.PrClosed:
        return "the PR was closed without merging: reopen it or delete the branch"
    if ctx.branch.startswith("phase/retro-"):
        return "a retrospective branch: run /retrospective, then open its PR (art-retrospective-cadence)"
    if reserved_slug(ctx.branch):
        return (
            f"{ctx.branch}: a slug may not start with sec- — its build branch would be build/sec-<slug>-N, the "
            "back-edge's name (.claude/rules/review-gate.md); rename the branch (git branch -m <new name>)"
        )
    return (
        "this branch is not a pipeline branch (.claude/rules/review-gate.md lists both paths' names): "
        "check out main, or a branch /next knows"
    )


def render_step(step: Step, ctx: RenderCtx) -> str:
    """One line, exactly as Interfaces 'The wrapper' specifies."""
    k = step.kind
    if k is SK.RunVerifier:
        return _verifier_line(step.pr, ctx)
    if k is SK.Merge:
        return _merge_line(step.pr, ctx)
    if k is SK.AddressFindings:
        return (
            f"address the findings on PR #{step.pr} (listed above), push, then run /next — "
            "there is no merge until an APPROVE marker for the new head exists"
        )
    if k is SK.RequestReview:
        return f"ask a teammate who is not the author to approve PR #{step.pr} (gh pr view {step.pr} --web)"
    if k is SK.Checkout:
        return f"gh pr checkout {step.pr}"
    if k is SK.CheckoutMain:
        return "git checkout main && git pull --ff-only"
    if k is SK.CreatePr:
        return f"git push -u origin {shlex.quote(ctx.branch)} && gh pr create --base {shlex.quote(ctx.base)} --fill"
    if k is SK.NewBranch:
        return _new_branch(step.proposal)
    if k is SK.RunBrainstorm:
        return f"run /superpowers:brainstorming and save the notes as docs/specs/<today>-{ctx.slug}-brainstorm.md"
    if k is SK.RunSpecify:
        return f"/specify {ctx.slug}"
    if k is SK.RunArchitecture:
        return f"/architecture {ctx.spec_slug}"
    if k is SK.RunPlan:
        return f"/specflow-plan {ctx.slug}"
    if k is SK.RunAnalyze:
        return f"/analyze {ctx.slug}"
    if k is SK.RunImplement:
        return _implement(step, ctx)
    if k is SK.RunGates:
        return "bash scripts/next.sh --gates"
    if k is SK.RunSecurityReview:
        return f"/security-review {step.version or ctx.version}"
    if k is SK.RunRelease:
        return f"/release {step.version or ctx.version}"
    if k is SK.TagRelease:
        v = step.version or ctx.version
        return f"/release --tag {v}"
    return _explain(step.why, ctx)  # ExplainUnknown


_PR_LANES = {
    Lane.design: "design-pr", Lane.spec: "design-pr", Lane.arch: "design-pr", Lane.plan: "design-pr",
    Lane.build: "build-pr", Lane.impl: "build-pr", Lane.validate: "build-pr",
    Lane.ship: "ship-pr", Lane.security: "ship-pr", Lane.release: "ship-pr",
}

CONFIRM_TEXT = {
    "brainstorm-end": "confirm the product scope with the user before /specify",
    "design-pr": "show the spec summary and the REQ-389 acknowledgements, write confirmed_by: into the spec and, where "
                 "they exist, the overview, the threat model and the ADRs (regulated path: phase/spec-<slug> writes the "
                 "spec's only, phase/arch-<slug> the architecture files', and phase/plan-<slug> "
                 "writes none), then run the gates as next.sh renders them (bash scripts/next.sh --gates), then "
                 "git add all of the lane's artifacts (new and edited) — exactly the spec and the brainstorm notes "
                 "under docs/specs/, the overview and the threat model under docs/architecture/, the ADRs under "
                 "docs/adr/, the plan under docs/plans/ and the proofs under verification/, nothing else — and commit "
                 "them (git commit -m "
                 "\"docs(guided): confirmed_by: <handle> <date> — acknowledgements at design-pr (REQ-389)\"), "
                 "then push the design PR",
    "build-pr": "show what was built, in the user's terms, before the build PR is pushed",
    "ship-pr": "show the severity scores and the dispositions (acknowledgements) and write confirmed_by: into the "
               "security review and the disposition; then show the release notes, ask go or no-go (the user's "
               "decision) and record the answer under ### Guided proposals in the release notes (regulated path: "
               "phase/security's point writes the security review's and disposition's confirmed_by: only, and "
               "phase/release's asks go or no-go and records it under ### Guided proposals in the release notes); "
               "then show, as a further acknowledgement, each suppression entry added since the ship reference (the "
               "previous release tag, else origin/<base>; listed in ship.suppressions_added), with the SEC id it cites — "
               "shown before it is committed; then run the gates as next.sh renders them (bash scripts/next.sh --gates), then git add all of the "
               "lane's artifacts (new and edited) — exactly docs/security/<version>-review.md, "
               "docs/security/<version>-disposition.md, docs/releases/<version>-{notes,migration,known-limitations}.md "
               "and any suppression entry that cites a SEC id (.gitleaks.toml, osv-scanner.toml, the pack's audit "
               "config), nothing else — and commit them (git commit -m \"docs(guided): confirmed_by: "
               "<handle> <date> — acknowledgements at ship-pr (REQ-389)\"), then push the ship PR",
    "awaiting-verifier": "print the second-terminal command; never run the verifier here",
    "merge": "ask before running the merge command",
    "unsigned-tag": "no signing key: confirm the annotated-tag fallback before tagging",
}


def confirmation_point(result: Result, facts: Facts, profile: str) -> Optional[str]:
    """The guided profile's pause, keyed on the Result's lane and phase (never the step); None for engineers."""
    if profile != "guided":
        return None
    if result.step.kind is SK.Merge:
        return "merge"
    if result.phase is Phase.specify:
        return "brainstorm-end"
    if result.phase is Phase.awaiting_verifier:
        return "awaiting-verifier"
    if result.phase is Phase.open_pr:
        return _PR_LANES.get(result.lane)
    if result.step.kind is SK.TagRelease and not facts.signing_key_present:
        return "unsigned-tag"
    return None


def guided_command(command: str, step: Step, cid: Optional[str]) -> str:
    """The guided profile's command (PR #48 verifier run 3, finding 3; scoped re-review N2): at design-pr and ship-pr,
    create-pr refuses to push while git status --porcelain lists anything — a tracked file's uncommitted edit or an
    untracked file (the guided flow's commands create the spec, the ADRs, the plan and the release docs): the lane's
    artifacts must be committed first, or CI reads a pushed branch without them. A stray file that is not the lane's
    is removed or gitignored, never committed to satisfy the guard (round 3b D3). Any other step or point: the
    engineer profile's command, unchanged."""
    if step.kind is not SK.CreatePr or cid not in ("design-pr", "ship-pr"):
        return command
    return (f'if [ -z "$(git status --porcelain)" ]; then {command}; else echo "uncommitted or untracked changes: '
            f'commit the lane\'s artifacts first; remove or gitignore files that are not the lane\'s; never commit them '
            f'to satisfy the guard (confirm: {cid})" >&2; false; fi')


def confirm_line(cid: str) -> str:
    return f"confirm: {cid} — {CONFIRM_TEXT[cid]}"


GLOSSARY_TERMS = tuple(
    (t, re.sub(r"[^a-z0-9 -]", "", t.lower()).replace(" ", "-"))
    for t in (
        "Lane", "Design lane", "Build lane", "Ship lane", "Patch tier", "Back-edge", "Waiver",
        "Attestation marker", "/next", "Derive", "Facts", "Confirmation point", "Awaiting verifier",
    )
)
_ANCHOR = dict(GLOSSARY_TERMS)


def terms_for(result: Result) -> list:
    """The glossary terms a rendering of this Result uses, each once (REQ-308: linked on first use)."""
    names = ["/next", "Derive", "Facts", "Lane"]
    lane_term = {"design": "Design lane", "spec": "Design lane", "arch": "Design lane", "plan": "Design lane",
                 "build": "Build lane", "impl": "Build lane", "validate": "Build lane",
                 "ship": "Ship lane", "security": "Ship lane", "release": "Ship lane"}.get(result.lane.value)
    if lane_term:
        names.append(lane_term)
    if result.phase is Phase.awaiting_verifier:
        names += ["Awaiting verifier", "Attestation marker"]
    if result.phase is Phase.blocked:
        names += ["Attestation marker", "Waiver"]
    t = result.step.target
    if t is not None and t.kind is TargetKind.SecFix:
        names.append("Back-edge")
    if t is not None and t.kind is TargetKind.PatchTier:
        names.append("Patch tier")
    if result.step.kind is SK.Merge or result.phase is Phase.open_pr:
        names.append("Confirmation point")
    seen, out = set(), []
    for n in names:
        if n not in seen:
            seen.add(n)
            out.append((n, _ANCHOR[n]))
    return out


def terms_line(terms: list) -> str:
    return "terms: " + ", ".join(f"{t} (docs/GLOSSARY.md#{a})" for t, a in terms)


# ---- derive: the impure layer (facts from the tree, configuration, output) ---------------------------------------


class NextError(Exception):
    """A usage, configuration or git error: printed as `ERROR next: ...`, exit 2."""


_FACT_NAMES = tuple(Facts.__dataclass_fields__)
_DESIGN_FACTS = ("has_brainstorm", "has_spec", "spec_has_tagged_reqs", "arch_complete", "has_plan", "analyze_ok")
_READS = {
    K.Main: ("unbuilt", "untagged_ship", "next_version", "ship_phases_merged", "signing_key_present"),
    K.Design: _DESIGN_FACTS,
    K.PhaseSpec: ("has_brainstorm", "has_spec", "spec_has_tagged_reqs"),
    K.PhaseArch: ("has_spec", "spec_has_tagged_reqs", "arch_complete"),
    K.PhasePlan: ("has_spec", "spec_has_tagged_reqs", "has_plan", "analyze_ok"),
    K.Build: ("build_sections", "has_source_diff"),
    K.BuildSec: ("has_source_diff",),
    K.Patch: ("has_source_diff",),
    K.Impl: ("has_source_diff",),
    K.ImplSec: ("has_source_diff",),
    K.PhaseValidate: ("gates_pass",),
    K.Ship: ("has_security_docs", "has_release_docs"),
    K.PhaseSecurity: ("has_security_docs",),
    K.PhaseRelease: ("has_release_docs",),
    K.Unknown: (),
}
_RELEASE_DOCS = ("notes", "migration", "known-limitations")
_TEMPLATE_NOTE = (
    "template source (no .specflow.yml): profile guided, path lanes are the defaults; the factory walks the lanes "
    "path from P6 (REQ-381); run with --path regulated to see P0–P5's phase branches"
)


def _git(root: str, *args: str) -> tuple:
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    try:
        p = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, env=env)
    except OSError as e:
        return 127, str(e)
    return p.returncode, p.stdout.strip()


_CONFIRMED_BY_MISSING = "confirmed_by: missing or empty (profile: guided, REQ-389)"


def _run(root: str, argv: list, full: bool = False) -> tuple:
    """(exit status, last lines of output — all of it with full) of a repository script run from the root; (None, why)
    when it is absent."""
    script = os.path.join(root, argv[0])
    if not os.path.isfile(script):
        return None, f"{argv[0]} is not in this repository"
    p = subprocess.run(["bash", script, *argv[1:]], cwd=root, capture_output=True, text=True,
                       env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
    if full:
        return p.returncode, p.stdout + p.stderr
    tail = " | ".join((p.stdout + p.stderr).strip().splitlines()[-3:])
    return p.returncode, tail


def _files(root: str, pattern: str) -> list:
    return sorted(os.path.relpath(p, root) for p in glob.glob(os.path.join(root, pattern)))


def _read(root: str, rel: str) -> str:
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        return f.read()


class Collector:
    """The Facts the branch's lane reads, each with the reason it has that value (for --explain)."""

    def __init__(self, root: str, branch: Branch, base_ref: Optional[str], run_gates: bool):
        self.root, self.b, self.base_ref, self.run_gates = root, branch, base_ref, run_gates
        self.facts: dict = {}
        self.why: list = []
        self.notes: list = []
        self.slug = branch.slug or (branch.name if branch.kind is K.Impl else "")
        self.spec_slug = self.slug
        self.plan_path = ""
        self.version = branch.version
        self._spec_text = ""
        self.resolved_plan = ""

    def _fact(self, name: str, value, why: str) -> None:
        self.facts[name] = value
        self.why.append(f"{name} is {value!r}: {why}")

    # -- artifacts by slug
    def _spec_files(self, suffix: str) -> list:
        if self.resolved_plan:  # P6 R4: the spec slug is already dated
            rx = re.compile("^" + re.escape(self.spec_slug) + "-" + suffix + r"\.md$")
        else:
            rx = re.compile(r"^\d{4}-\d{2}-\d{2}-" + re.escape(self.slug) + "-" + suffix + r"\.md$")
        return [p for p in _files(self.root, "docs/specs/*.md") if rx.match(os.path.basename(p))]

    def _plans(self) -> list:
        out = []
        rx = re.compile(r"^\d{4}-\d{2}-\d{2}-" + re.escape(self.slug) + r"-plan\.md$")
        for p in _files(self.root, "docs/plans/*.md"):
            fm, _ = frontmatter.read(os.path.join(self.root, p))
            if self.resolved_plan:  # F17: the design slug's own plan file alone
                if rx.match(os.path.basename(p)):
                    out.append(p)
            elif rx.match(os.path.basename(p)) or (self.spec_has_file and fm.get("spec", "") == self.spec_slug):
                out.append(p)
        return out

    def spec(self) -> None:
        self.spec_has_file = False
        if not self.slug:
            return
        specs = self._spec_files("design")
        if specs:
            self.spec_has_file = True
            self.spec_slug = os.path.basename(specs[-1])[: -len("-design.md")]
            self._spec_text = _read(self.root, specs[-1])
        self.spec_path = specs[-1] if specs else ""
        if not specs and self.b.kind is K.Design:
            self._resolve_through_plan()

    def _resolve_through_plan(self) -> None:
        """P6 R4 (design lane only, F17): a follow-on lane of an existing spec has no spec of its own slug; when its plan
        docs/plans/<date>-<slug>-plan.md exists, that plan's spec: names the spec the lane's facts read — the NEWEST
        such plan when there are several, as plan_path picks it (Build 5 fix wave 1, D). Advisory, like all of /next:
        any design/<slug> lane may name any live spec in its plan's spec:, and the verifier reads the documents."""
        rx = re.compile(r"^\d{4}-\d{2}-\d{2}-" + re.escape(self.slug) + r"-plan\.md$")
        for p in reversed(_files(self.root, "docs/plans/*.md")):
            if not rx.match(os.path.basename(p)):
                continue
            fm, _ = frontmatter.read(os.path.join(self.root, p))
            named = fm.get("spec", "")
            live = frontmatter.live_specs(self.root)
            if named and named in live:
                self.spec_slug = named
                self.spec_has_file = True
                self.spec_path = f"docs/specs/{named}-design.md"
                if not os.path.isfile(os.path.join(self.root, self.spec_path)):
                    self.spec_path = next((q for q in _files(self.root, "docs/specs/*.md")
                                           if frontmatter.spec_slug(q) == named), self.spec_path)
                self._spec_text = live[named][1]
                self.resolved_plan = p
                self.why.append(f"spec {named} resolved through {p}'s spec: (a follow-on design lane, P6 R4)")
            else:
                self.why.append(f"{p}'s spec: {named or '(none)'} names no live spec — the design slug's own spec is used")
            return

    def want(self, name: str) -> bool:
        return name in _READS[self.b.kind]

    def collect(self) -> None:
        self.spec()
        if self.want("has_brainstorm"):
            bs = self._spec_files("brainstorm") if self.slug else []
            self._fact("has_brainstorm", bool(bs), bs[-1] if bs else f"no docs/specs/<date>-{self.slug}-brainstorm.md")
        if self.want("has_spec"):
            self._fact("has_spec", self.spec_has_file,
                       self.spec_path or f"no docs/specs/<date>-{self.slug}-design.md (the spec)")
        if self.want("spec_has_tagged_reqs"):
            tagged = frontmatter.tagged_reqs(self._spec_text)
            self._fact("spec_has_tagged_reqs", bool(tagged),
                       f"tagged REQs in the spec: {', '.join(sorted(tagged)) or 'none'} (frontmatter.tagged_reqs)")
        plans = self._plans() if self.slug else []
        if plans:
            self.plan_path = plans[-1]
        if self.want("arch_complete"):
            self._arch()
        if self.want("has_plan"):
            self._fact("has_plan", bool(plans), ", ".join(plans) or f"no docs/plans/<date>-{self.slug}-plan.md")
        if self.want("analyze_ok"):
            self._analyze(bool(plans))
        if self.want("build_sections"):
            self._builds(plans)
        if self.want("has_source_diff"):
            self._diff()
        if self.want("gates_pass"):
            self._gates()
        if self.want("has_security_docs") or self.want("has_release_docs"):
            self._ship_docs()
        if self.want("signing_key_present"):
            kind, reason = signers.signing_kind(self.root)
            # Any signer counts (Build 1 final review): only `none` — no signer at all — reaches the unsigned-tag
            # point; a GPG or X.509 signer goes to /release --tag, which stops at exit 5 with the SSH set-up steps.
            self._fact("signing_key_present", kind != "none", f"signers.py signing-kind: {kind} ({reason})")
        # The why line for unbuilt, untagged_ship, next_version and ship_phases_merged is written by main(), which
        # knows whether the PR state was read (round 3b re-review D4).

    def ship(self):
        """R9's explain-only object for --json and the text line: the ship reference and the suppression entries added
        since it. None off the ship lane. Not a kernel fact."""
        if self.b.kind not in (K.Ship, K.PhaseSecurity, K.PhaseRelease):
            return None
        root = pathlib.Path(self.root)
        ref, kind = self.base_ref or "origin/main", "base"
        v = self.version or self.b.version
        if v and self.base_ref:
            prev = release_gate.previous_release(root, v, self.base_ref)
            if prev and _git(self.root, "tag", "--list", f"v{prev}")[1] != "":
                ref, kind = f"v{prev}", "previous-tag"
        old: set = set()
        tmp = tempfile.mkdtemp(prefix="specflow-ship-")
        try:
            arc = subprocess.run(["git", "-C", self.root, "archive", ref], capture_output=True)
            if arc.returncode == 0:
                subprocess.run(["tar", "-x", "-C", tmp], input=arc.stdout, capture_output=True)
                old = {(s["file"], s["kind"], s["id"]) for s in floor.suppressions_scan(pathlib.Path(tmp))[1]}
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        added = [{k: s[k] for k in ("file", "line", "kind", "id", "sec")}
                 for s in floor.suppressions_scan(root)[1] if (s["file"], s["kind"], s["id"]) not in old]
        return {"reference": ref, "reference_kind": kind, "suppressions_added": added}

    def _arch(self) -> None:
        tagged = frontmatter.tagged_reqs(self._spec_text)
        addressed: set = set()
        for p in _files(self.root, "docs/adr/*.md"):
            fm, _ = frontmatter.read(os.path.join(self.root, p))
            addressed |= set(frontmatter.parse_list(fm.get("addresses", "")))
        ov = f"docs/architecture/{self.spec_slug}-overview.md"
        tm = f"docs/architecture/{self.spec_slug}-threat-model.md"
        have = self.spec_has_file and os.path.isfile(os.path.join(self.root, ov)) and \
            os.path.isfile(os.path.join(self.root, tm))
        missing = sorted(tagged - addressed)
        ok = False
        detail = ""
        if have and not missing:
            rc, out = _run(self.root, ["scripts/check-architecture.sh"], full=True)
            lines = [ln for ln in out.splitlines() if ln.strip()]
            ok = rc == 0
            # Every real error first, then at most two of the expected confirmed_by: lines (a real error is never
            # hidden behind them).
            errs = [ln for ln in lines if not ln.endswith(_CONFIRMED_BY_MISSING)]
            cby = [ln for ln in lines if ln.endswith(_CONFIRMED_BY_MISSING)]
            shown = errs + cby[:2] + ([f"… {len(cby) - 2} more confirmed_by: line(s)"] if len(cby) > 2 else [])
            detail = f"scripts/check-architecture.sh exit {rc} ({' | '.join(shown)})"
            if rc == 1 and lines and all(ln.endswith(_CONFIRMED_BY_MISSING) for ln in lines):
                # R19 / PR #48 verifier medium 2: under the guided profile confirmed_by: is written by /next at design-pr,
                # after the acknowledgements are shown and before the gates run — the architecture is otherwise complete.
                ok = True
                detail = (f"scripts/check-architecture.sh reports only confirmed_by: missing ({len(lines)} file(s)): "
                          "architecture complete; confirmed_by: is written by /next at design-pr, just before the gates "
                          "and create-pr")
        elif not have:
            detail = f"the spec, {ov} or {tm} is missing"
        else:
            detail = f"no ADR addresses {', '.join(missing)}"
        self._fact("arch_complete", ok, detail)

    def _analyze(self, has_plan: bool) -> None:
        if not has_plan:
            self._fact("analyze_ok", False, "no plan to analyze")
            return
        rc1, t1 = _run(self.root, ["scripts/analyze-adr-plan-linkage.sh"])
        rc2, t2 = _run(self.root, ["scripts/check-traceability.sh"])
        self._fact("analyze_ok", rc1 == 0 and rc2 == 0,
                   f"analyze-adr-plan-linkage.sh exit {rc1} ({t1}); check-traceability.sh exit {rc2} ({t2})")

    def _builds(self, plans: list) -> None:
        nums: set = set()
        for p in plans:
            found = sorted({int(n) for n in re.findall(r"(?m)^## Build ([1-9][0-9]*):", _read(self.root, p))})
            if found and found != list(range(1, max(found) + 1)):
                self.notes.append(f"{p}: builds are numbered from 1 with no gap (REQ-340); found {found}")
            nums |= set(found)
            if self.b.kind is K.Build and self.b.n in found and not self.plan_path_for_build:
                self.plan_path_for_build = p
        if self.plan_path_for_build:
            self.plan_path = self.plan_path_for_build
        self._fact("build_sections", frozenset(nums), f"## Build N sections in {', '.join(plans) or 'no plan'}")
        if self.b.kind is K.Build and self.b.n not in nums:
            self.notes.append(f'{self.b.slug}-{self.b.n} needs "## Build {self.b.n}" in a plan named '
                              f"docs/plans/<date>-{self.b.slug}-plan.md")

    plan_path_for_build = ""

    def _diff(self) -> None:
        try:
            pack = packinfo.load(self.root)
        except packinfo.PackError as e:
            self._fact("has_source_diff", False, f"no pack metadata ({e})")
            return
        paths: set = set()
        if self.base_ref:
            rc, out = _git(self.root, "diff", "--name-only", f"{self.base_ref}...HEAD")
            if rc == 0:
                paths |= set(out.splitlines())
        _, out = _git(self.root, "diff", "--name-only", "HEAD")
        paths |= set(out.splitlines())
        _, out = _git(self.root, "ls-files", "--others", "--exclude-standard")
        paths |= set(out.splitlines())
        hit = sorted(p for p in paths if p and (packinfo.is_source(pack, p) or packinfo.is_test(pack, p)))
        self._fact("has_source_diff", bool(hit),
                   f"{len(hit)} source or test path(s) differ from {self.base_ref or 'no base'}"
                   + (f": {', '.join(hit[:5])}" if hit else ""))

    def _gates(self) -> None:
        if not self.run_gates:
            self._fact("gates_pass", False, "not run: pass --gates to run scripts/run-quality-gates.sh")
            return
        rc, tail = _run(self.root, ["scripts/run-quality-gates.sh"])
        self._fact("gates_pass", rc == 0, f"scripts/run-quality-gates.sh exit {rc} ({tail})")

    def _tagged(self, v: str) -> bool:
        return _git(self.root, "tag", "--list", f"v{v}")[1] != ""

    def _ship_docs(self) -> None:
        k = self.b.kind
        if k is K.Ship:
            versions = [self.b.version]
        else:
            # phase/security and phase/release carry no version: they take next_version (ADR-003), the version after
            # the newest vX.Y.Z tag — never an earlier release's untagged documents (an instance keeps the demo's
            # 0.0.1-demo docs without its tag).
            tag = _release_tag(self.root)
            v = "0.1.0" if tag is None else f"{tag[0]}.{tag[1] + 1}.0"
            self.version = v
            self.why.append(f"{self.b.kind.value} takes its version from next_version (ADR-003): "
                            + (f"v{tag[0]}.{tag[1]}.{tag[2]} is the newest release tag" if tag else "no vX.Y.Z tag yet")
                            + f", so {v}; documents of any other version are not read")
            versions = [v]
        sec = rel = False
        for v in versions:
            s = all(os.path.isfile(os.path.join(self.root, f"docs/security/{v}-{x}.md")) for x in ("review", "disposition"))
            r = all(os.path.isfile(os.path.join(self.root, f"docs/releases/{v}-{x}.md")) for x in _RELEASE_DOCS)
            if s or r:
                self.version = self.version or v
            sec, rel = sec or s, rel or r
        if k is K.Ship and not self.version:
            self.version = self.b.version
        if self.want("has_security_docs"):
            self._fact("has_security_docs", sec, f"docs/security/<v>-{{review,disposition}}.md for {versions or 'no version'}")
        if self.want("has_release_docs"):
            self._fact("has_release_docs", rel, f"docs/releases/<v>-{{{','.join(_RELEASE_DOCS)}}}.md for {versions or 'no version'}")


# ---- PR state: gh, read-only, fail safe (P5 R5-R7, R20-R22) ------------------------------------------------------


class PrStateError(Exception):
    """gh or its output could not be used: PR state is unknown, and nothing that needs a PR is proposed."""


def _gh_json(root: str, *args: str):
    try:
        p = subprocess.run(["gh", *args], cwd=root, capture_output=True, text=True, env=dict(os.environ))
    except OSError as e:
        raise PrStateError(f"gh is not runnable: {e}")
    if p.returncode != 0:
        first = (p.stderr.strip().splitlines() or [f"gh exited {p.returncode}"])[0]
        raise PrStateError(first)
    try:
        return json.loads(p.stdout)
    except ValueError:
        raise PrStateError("gh printed something that is not JSON")


def _login(d: dict) -> str:
    """The login as the CI check sees it: gh lists a bot as app/<name>, the API as <name>[bot]."""
    raw = ((d.get("author") or {}).get("login")) or ""
    return raw[len("app/"):] + "[bot]" if raw.startswith("app/") else raw


class RawPr:
    def __init__(self, d: dict):
        try:
            self.number = int(d["number"])
            self.head = str(d["headRefName"])
            self.base = str(d.get("baseRefName") or "main")
            self.state = str(d["state"]).upper()
            self.head_oid = str(d.get("headRefOid") or "")
            self.base_oid = str(d.get("baseRefOid") or "")
            self.review_decision = str(d.get("reviewDecision") or "")
            self.url = str(d.get("url") or "")
            self.body = str(d.get("body") or "")
            self.author = _login(d)
            self.merge_oid = str(((d.get("mergeCommit") or {}).get("oid")) or "")
            self.cross = bool(d.get("isCrossRepository"))
            self.head_owner = str(((d.get("headRepositoryOwner") or {}).get("login")) or "")
        except (KeyError, TypeError, ValueError, AttributeError):
            raise PrStateError("gh pr list printed an entry without number, headRefName or state")
        if self.state not in ("OPEN", "MERGED", "CLOSED"):
            raise PrStateError(f"PR #{self.number} has state {self.state}")

    @property
    def is_open(self) -> bool:
        return self.state == "OPEN"

    @property
    def is_merged(self) -> bool:
        return self.state == "MERGED"


class PrState:
    """What gh said, reduced to the kernel's inputs. known is False on any failure (fail safe)."""

    def __init__(self) -> None:
        self.known = False
        self.note = ""
        self.stale = ""  # a note: the checkout's origin/<base> differs from the base tip gh reports
        self.repo = ""
        self.login = ""
        self.prs: list = []
        self.branch_pr: Optional[PR] = None
        self.branch_raw: Optional[RawPr] = None
        self.open_lane_prs: tuple = ()
        self.open_lanes_info: list = []
        self.stacked: tuple = ()
        self.solo: Optional[bool] = None
        self.comment: Optional[dict] = None
        self.why: list = []
        self.facts: dict = {}
        self.bad_plans: dict = {}  # slug -> plan path, for a file-name slug that is not a branch-name token
        self.bad_release: Optional[tuple] = None  # (notes path, PR number): a release version that fails VERSION_RE


def _reviews_approve(root: str, st: "PrState", pr: RawPr) -> bool:
    """R21(d) as amended by the P5 final review: with an empty reviewDecision, each reviewer's latest review at the
    head; no change request (one at ANY commit that was not dismissed or followed by that reviewer's approval counts,
    PR #48 verifier run 2), and an approval that counts — from an OWNER, or a MEMBER or COLLABORATOR whose repository
    role is admin, maintain or write (unreadable fails closed, as a waiver does), who is neither the PR's author nor an
    author or committer of any of its commits (so neither the last pusher of their own commits)."""
    d = _gh_json(root, "pr", "view", str(pr.number), "--json", "reviews")
    latest: dict = {}
    latest_any: dict = {}
    assoc: dict = {}
    reviews = [r for r in d.get("reviews") or [] if r.get("state") in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED")]
    for i, r in sorted(enumerate(reviews), key=lambda p: (str(p[1].get("submittedAt") or ""), p[0])):
        who = ((r.get("author") or {}).get("login")) or ""
        # PR #48 verifier run 2 (conservative): a change request at ANY commit stands until the same reviewer approves
        # or it is dismissed (GitHub then reports it as DISMISSED), whatever reviewDecision says.
        latest_any[who] = r.get("state")
        if ((r.get("commit") or {}).get("oid")) != pr.head_oid:
            continue
        latest[who] = r.get("state")
        assoc[who] = str(r.get("authorAssociation") or "")
    pending = sorted(w for w, s in latest_any.items() if s == "CHANGES_REQUESTED")
    if pending:
        st.why.append(f"{', '.join(pending)} requested changes (a review not dismissed, at any commit): no human "
                      "approval")
        return False
    try:
        commits = attestation._gh_json_list(f"repos/{st.repo}/pulls/{pr.number}/commits")
    except attestation.AttestationError as e:
        raise PrStateError(f"the PR's commits could not be read ({e})")
    excluded = {pr.author} | {attestation.commit_author(c) for c in commits} | \
        {attestation.commit_committer(c) for c in commits}
    ok = False
    for who, s in sorted(latest.items()):
        if s != "APPROVED":
            continue
        a = assoc.get(who, "")
        if who in excluded:
            st.why.append(f"{who}'s approval does not count: the PR's author or an author or committer of one of its "
                          "commits")
        elif a == "OWNER":
            ok = True
        elif a in ("MEMBER", "COLLABORATOR"):
            role = attestation.repo_role(st.repo, who)
            if role in attestation.WRITER_ROLES:
                ok = True
            else:
                st.why.append(f"{who}'s approval does not count: {a} with repository role {role or 'unknown'} "
                              "(admin, maintain or write needed; unreadable fails closed)")
        else:
            st.why.append(f"{who}'s approval does not count: association {a or 'unknown'} (OWNER, or a MEMBER or "
                          "COLLABORATOR with a writing role, needed)")
    return ok


def _local_commit(root: str, ref: str) -> bool:
    return _git(root, "rev-parse", "--verify", "-q", ref + "^{commit}")[0] == 0


def _stale_base(root: str, st: PrState, pr: RawPr) -> None:
    """PR #48 verifier run 7 (code finding 3): next.sh never fetches, so the policy, the prompt hash and the marker's
    base are read at this checkout's origin/<base>. When gh reports another base tip (baseRefOid), say so — a note and a
    why line; the derivation is unchanged (the merge command stays bound by --match-head-commit)."""
    if not re.fullmatch(r"[0-9a-f]{40}", pr.base_oid):
        return
    rc, local = _git(root, "rev-parse", f"origin/{pr.base}")
    if rc != 0 or local == pr.base_oid:
        return
    st.stale = (f"origin/{pr.base} here is at {local[:7]}, but GitHub's {pr.base} is at {pr.base_oid[:7]}: this "
                f"checkout's base is stale (git fetch origin {pr.base}), so run /next again after fetching")
    st.why.append(f"the base policy, the prompt hash and the marker's base were judged at this checkout's "
                  f"origin/{pr.base}, not the base CI reads ({pr.base_oid[:7]}): fetch before merging")


def _branch_pr(root: str, st: PrState, branch: Branch, branch_name: str, wt_solo: bool) -> None:
    if branch.kind in (K.Main, K.Unknown):
        return
    _, head = _git(root, "rev-parse", "HEAD")
    chosen = None
    for pr in sorted((p for p in st.prs if p.head == branch_name), key=lambda p: -p.number):
        if pr.cross:
            st.why.append(f"PR #{pr.number} comes from a fork ({pr.head_owner or pr.author}), not this repository's "
                          f"{branch_name}: never this branch's PR")
            continue
        if pr.is_open or pr.head_oid == head:
            chosen = chosen or pr
        else:
            st.why.append(f"PR #{pr.number} ({pr.state.lower()}) is an earlier use of this branch name — its head "
                          f"{pr.head_oid[:7]} is not HEAD")
    if chosen is None:
        return
    st.branch_raw = chosen
    att, decision = Attestation.none, chosen.review_decision == "APPROVED"
    if chosen.is_open:
        # PR #48 verifier run 2 (code-mode low): whenever the base's policy is not read, solo fails safe to team
        # mode — never the working tree's .specflow.yml.
        if not chosen.head_oid or not _local_commit(root, chosen.head_oid):
            st.solo = False
            st.why.append(f"the PR head {chosen.head_oid[:7]} is not in this checkout (pull or push first): "
                          "attestation none; team mode assumed (solo false, fail safe; never the working tree's policy)")
        elif not _local_commit(root, f"origin/{chosen.base}"):
            st.solo = False
            st.why.append(f"base origin/{chosen.base} not in this checkout (git fetch origin {chosen.base}): no marker "
                          "is read, attestation none; team mode assumed (solo false, fail safe; never the working "
                          "tree's policy)")
        else:
            _stale_base(root, st, chosen)
            try:
                r = attestation.pr_attestation(repo=st.repo, pr=chosen.number, head=chosen.head_oid,
                                               base_ref=f"origin/{chosen.base}", pr_author=chosen.author)
            except attestation.AttestationError as e:
                st.solo = False
                st.why.append(f"the PR's attestation could not be read ({e}): attestation none; team mode assumed "
                              "(solo false, fail safe; never the working tree's policy)")
            else:
                att = Attestation(r["state"])
                if r.get("solo") is not None:
                    st.solo = bool(r["solo"])
                else:
                    # Never the checkout's .specflow.yml for a policy key (PR #48 verifier low): fail safe to team mode.
                    st.solo = False
                    st.why.append("could not read solo from the base's .specflow.yml: team mode assumed (solo false, "
                                  "fail safe; never the working tree's policy)")
                for login, why in sorted((r.get("role_unknown") or {}).items()):
                    st.why.append(f"{login}'s repository role could not be read ({why}): their marker or waiver is "
                                  "never accepted, and a blocking one still blocks (REQ-382, R9)")
                st.comment = r.get("comment")
                st.why.append(f"attestation {att.value} ({r.get('reason')}) through attestation.pr_attestation")
                cm = st.comment or {}
                if cm.get("login"):
                    st.why.append(f"the decisive comment {cm.get('html_url') or cm.get('id')} was posted by "
                                  f"{cm['login']} ({cm.get('association') or 'unknown'}"
                                  + (f", role {cm['role']}" if cm.get("role") else "") + ")")
                for cid, url, reason in r.get("judged") or []:
                    verb = "counted as a request for changes" if reason.startswith("request-changes-") \
                        else "not accepted"
                    st.why.append(f"comment {url or cid} {verb}: {reason}")
                if att is Attestation.waiver and st.comment and st.comment.get("html_url") \
                        and st.comment["html_url"] not in chosen.body:
                    st.why.append(f"waiver accepted ({st.comment['html_url']}), not linked from the PR body — "
                                  "REQ-382's convention, the PR template's checkbox")
        solo = st.solo if st.solo is not None else wt_solo
        if not decision and not chosen.review_decision and not solo:
            st.why.append("reviewDecision is empty (no required review on the base): the human approval is read from "
                          "the reviews at the head, and nothing server-side enforces it")
            try:
                decision = _reviews_approve(root, st, chosen)
            except PrStateError as e:
                st.why.append(f"the PR's reviews could not be read ({e}): no human approval assumed")
    st.branch_pr = PR(chosen.number, chosen.is_open, chosen.is_merged, chosen.state == "CLOSED", decision, att,
                      bool(st.login) and chosen.author == st.login)


def _release_tag(root: str) -> Optional[tuple]:
    best = None
    for t in _git(root, "tag", "--list", "v*")[1].splitlines():
        m = re.match(r"^v(\d+)\.(\d+)\.(\d+)$", t)
        if m:
            k = tuple(int(x) for x in m.groups())
            best = k if best is None or k > best else best
    return best


def _plan_sections(root: str, st: PrState) -> dict:
    out: dict = {}
    for p in _files(root, "docs/plans/*.md"):
        m = re.match(r"^\d{4}-\d{2}-\d{2}-(.+)-plan\.md$", os.path.basename(p))
        nums = sorted({int(n) for n in re.findall(r"(?m)^## Build ([1-9][0-9]*):", _read(root, p))})
        if not nums:
            st.why.append(f"{p} has no \"## Build N\" section: /next does not track it (P5 R6)")
            continue
        spec = frontmatter.read(os.path.join(root, p))[0].get("spec", "")
        slug = m.group(1) if m else re.sub(r"^\d{4}-\d{2}-\d{2}-", "", spec)
        if slug.startswith("sec-"):
            st.why.append(f"{p}: its slug {slug} starts with sec-, so its builds would be build/sec-{slug[4:]}-N, the "
                          "back-edge's name: /next does not track it (rename the plan's slug)")
            continue
        if slug and not _slug(slug):
            st.bad_plans[slug] = p
            st.why.append(f"{p}: its slug {slug!r} is not a branch-name token: /next explains it and renders no "
                          "command for its builds")
        if slug:
            out.setdefault(slug, set()).update(nums)
    return out


def _release_facts(root: str, st: PrState) -> dict:
    """unbuilt, untagged_ship, next_version and ship_phases_merged, from the merged PRs and the tags (R6, R21(c))."""
    merged = [(p, parse_branch(p.head)) for p in st.prs if p.is_merged]
    tag = _release_tag(root)

    def released(pr: RawPr) -> bool:
        if not pr.merge_oid or not _local_commit(root, pr.merge_oid):
            st.why.append(f"the merge commit {pr.merge_oid[:7] or '(none)'} of PR #{pr.number} is not in this "
                          "checkout: counted as not released (git pull)")
            return False
        return tag is not None and _git(root, "merge-base", "--is-ancestor", pr.merge_oid,
                                        "v%d.%d.%d" % tag)[0] == 0

    build_kinds = (K.Build, K.BuildSec, K.Patch, K.Impl, K.ImplSec)
    unreleased = [p for p, b in merged if b.kind in build_kinds and not released(p)]
    sections = _plan_sections(root, st)
    done = {(b.slug, b.n) for _, b in merged if b.kind is K.Build}
    # PR #48 scoped re-review N1 (strict rule): a merged impl/plan-<token>-<name> marks done Build <token> of the plan
    # whose slug is <name> only, the token compared as a string (1a, 1b and 1 are three tokens). An impl PR whose name
    # matches no plan slug counts for nothing: a merged impl/plan-1-foundation of an earlier cycle never marks another
    # plan's Build 1 done, so no build is skipped.
    for p, b in merged:
        if b.kind is not K.Impl:
            continue
        if b.name not in sections:
            st.why.append(f"PR #{p.number}: merged {p.head} matches no plan slug; the regulated impl branch is "
                          f"impl/plan-N-<plan slug>: no build marked done")
        elif any(str(n) == b.plan for n in sections[b.name]):
            done.add((b.name, int(b.plan)))
        else:
            st.why.append(f"PR #{p.number}: merged {p.head}: the {b.name} plan has no \"## Build {b.plan}\" section: "
                          "no build marked done")
    unbuilt = tuple(sorted((s, n) for s, ns in sections.items() for n in ns if (s, n) not in done))
    versions = set()
    bad: list = []    # (PR number, notes path) of unreleased phase/release PRs naming no valid version
    good: list = []   # PR numbers of phase/release PRs naming a valid version
    for p, b in merged:
        if b.kind is K.Ship:
            versions.add(b.version)
        elif b.kind is K.PhaseRelease:
            try:
                files = _gh_json(root, "pr", "view", str(p.number), "--json", "files").get("files") or []
            except PrStateError as e:
                st.why.append(f"PR #{p.number}'s files could not be read ({e}): its release version is unknown")
                continue
            named, invalid = False, None
            for f in files:
                m = re.match(r"^docs/releases/(.+)-notes\.md$", str(f.get("path", "")))
                if m and VERSION_RE.match(m.group(1)):
                    versions.add(m.group(1))
                    named = True
                elif m:
                    # Scoped re-review N5: validated as ship/<version> is; never a git tag --list pattern.
                    invalid = invalid or m.group(0)
                    st.why.append(f"PR #{p.number} added {m.group(0)!r}: its version is not a release version "
                                  "(<major>.<minor>.<patch>[-<pre>]): not read as a release")
            if named:
                good.append(p.number)
            elif invalid and not released(p):
                bad.append((p.number, invalid))
    # Round 3b re-review D1: a bad notes file blocks only while its PR is unreleased and no later merged phase/release
    # PR (a higher number) names a valid version — the follow-up the explanation asks for clears it.
    for number, path in sorted(bad):
        if not any(g > number for g in good):
            st.bad_release = (path, number)
            break
    untagged = sorted((v for v in versions if not _git(root, "tag", "--list", f"v{v}")[1]),
                      key=lambda v: ([int(x) for x in re.findall(r"\d+", v)[:3]], v))
    next_version = None
    if unreleased:
        next_version = "0.1.0" if tag is None else f"{tag[0]}.{tag[1] + 1}.0"
    phases = frozenset(RegShip(b.kind.value[len("Phase"):].lower()) for p, b in merged
                       if b.kind in (K.PhaseValidate, K.PhaseSecurity, K.PhaseRelease) and not released(p))
    return {"unbuilt": unbuilt, "untagged_ship": untagged[0] if untagged else None, "next_version": next_version,
            "ship_phases_merged": phases}


def collect_pr_state(root: str, branch: Branch, branch_name: str, wt_solo: bool) -> PrState:
    st = PrState()
    rc, _ = _git(root, "remote", "get-url", "origin")
    if rc != 0:
        st.note = "cannot see PRs (no origin remote) — /next will not propose creating a PR"
        return st
    try:
        st.repo = _gh_json(root, "repo", "view", "--json", "nameWithOwner")["nameWithOwner"]
        st.login = _gh_json(root, "api", "user")["login"]
        listing = _gh_json(root, "pr", "list", "--state", "all", "--limit", "1000", "--json",
                           "number,headRefName,baseRefName,state,author,mergedAt,mergeCommit,reviewDecision,isDraft,"
                           "headRefOid,baseRefOid,url,body,isCrossRepository,headRepositoryOwner")
        if not isinstance(listing, list):
            raise PrStateError("gh pr list did not print a list")
        st.prs = [RawPr(d) for d in listing]
        _branch_pr(root, st, branch, branch_name, wt_solo)
        lanes = []
        for p in sorted((p for p in st.prs if p.is_open), key=lambda p: p.number):
            if parse_branch(p.head).kind in (K.Main, K.Unknown):
                continue
            mine = p.author == st.login and not p.cross
            rec = st.branch_pr if st.branch_raw is p else PR(p.number, True, False, False, False, Attestation.none, mine)
            lanes.append(rec)
            st.open_lanes_info.append({"number": p.number, "author": p.author, "head": p.head, "mine": mine,
                                       "fork": p.cross})
        st.open_lane_prs = tuple(lanes)
        st.stacked = tuple(sorted(p.number for p in st.prs if p.is_open and p.base == branch_name and not p.cross))
        if branch.kind is K.Main:
            st.facts = _release_facts(root, st)
    except (PrStateError, KeyError, TypeError) as e:
        n = PrState()
        n.note = f"cannot see PRs ({e}) — /next will not propose creating a PR"
        return n
    st.known = True
    st.why.insert(0, f"PR state: {len(st.prs)} PRs read through gh for {st.repo}, current user {st.login}")
    return st


def _findings_block(text: str) -> str:
    url, _, body = text.partition("\n")
    return "findings: " + url + "".join("\n  " + ln for ln in body.splitlines())


def open_lanes_line(info: list) -> str:
    parts = []
    for i in info:
        if i["mine"]:
            parts.append(f"#{i['number']} (yours, {i['head']})")
        else:
            src = "a fork" if i.get("fork") else "not yours"
            parts.append(f"#{i['number']} ({i['author']}, {i['head']} — {src}: checking it out runs its code on "
                         "your machine; let CI run the gates first, dfe-10)")
    return "open lanes: " + ", ".join(parts)


def findings_text(comment: Optional[dict]) -> Optional[str]:
    """The REQUEST_CHANGES comment's URL, then its body without the marker line, at most 60 lines."""
    if not comment:
        return None
    lines = (comment.get("body") or "").splitlines()
    if lines and lines[0].lstrip().startswith("<!--"):
        lines = lines[1:]
    if len(lines) > 59:
        lines = lines[:59] + ["… (truncated: read the rest at the URL above)"]
    return "\n".join([comment.get("html_url") or ""] + lines)


class _Parser(argparse.ArgumentParser):
    def error(self, message: str):
        raise NextError(f"usage: {message}")


def _facts_json(all_facts: Facts, kind: K) -> dict:
    out: dict = {}
    for name in _FACT_NAMES:
        v = getattr(all_facts, name)
        if name != "pr_state_known" and name not in _READS[kind]:
            out[name] = None
        elif name == "build_sections":
            out[name] = sorted(v)
        elif name == "unbuilt":
            out[name] = [list(x) for x in v]
        elif name == "ship_phases_merged":
            out[name] = sorted(x.value for x in v)
        else:
            out[name] = v
    return out



def derive_cmd(argv: list) -> int:
    ap = _Parser(prog="pipeline.py derive", add_help=True)
    ap.add_argument("--root", default=".")
    ap.add_argument("--explain", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--gates", action="store_true")
    ap.add_argument("--profile", choices=("guided", "engineer"))
    ap.add_argument("--path", choices=("lanes", "regulated"))
    ap.add_argument("--base")
    args = ap.parse_args(argv)

    rc, top = _git(args.root, "rev-parse", "--show-toplevel")
    if rc != 0 or not top:
        raise NextError("not a git repository (run /next inside the project)")
    root = top
    os.chdir(root)  # attestation.pr_attestation runs git in the working directory
    # PR #48 env audit (REQ-341): GH_REPO would point every gh call (pipeline's and attestation's) at another
    # repository — /next reads the PRs of this checkout's own, so it is dropped for this process and its children.
    os.environ.pop("GH_REPO", None)
    try:
        cfg = dict(config.DEFAULTS, **config.load(pathlib.Path(root)))
    except config.ConfigError as e:
        raise NextError(f".specflow.yml: {e}")
    if args.path:
        cfg["path"] = args.path
    if args.profile:
        cfg["profile"] = args.profile
    errors = config.validate(cfg)
    if errors:
        raise NextError("; ".join(errors))
    path, profile, wt_solo = cfg["path"], cfg["profile"], cfg["solo"] == "true"

    notes: list = []
    explain: list = []
    template = not (os.path.isfile(os.path.join(root, ".specflow.yml")) or os.path.isfile(os.path.join(root, ".stack")))
    if template:
        notes.append(_TEMPLATE_NOTE)
    if args.path:
        notes.append(f"path {args.path} (--path) overrides the configured path for this run")
    if args.profile:
        notes.append(f"profile {args.profile} (--profile) overrides the configured profile for this run")

    rc, name = _git(root, "symbolic-ref", "--short", "-q", "HEAD")
    branch_name = name if rc == 0 and name else "HEAD"
    if branch_name == "HEAD":
        notes.append("detached HEAD: not on a branch")
    branch = parse_branch(branch_name)

    ps = collect_pr_state(root, branch, branch_name, wt_solo)
    if ps.note:
        notes.append(ps.note)
    if ps.stale:
        notes.append(ps.stale)
    solo = ps.solo if ps.solo is not None else wt_solo
    pr_base = f"origin/{ps.branch_raw.base}" if ps.branch_raw else None

    # An explicit --base that is not here is an error (the user asked for it). SPECFLOW_BASE_REF is ci.yml's variable
    # for its gate scripts (refs/remotes/origin/<PR base>; base_name reads either form): one that is not in this checkout is skipped, with a why: line, and the
    # next candidate used — /next is a local tool, and the environment never makes it fail (PR #48 CI, REQ-341).
    env_base = os.environ.get("SPECFLOW_BASE_REF") or None
    base_ref, env_base_skipped = None, False
    for cand, src in ((args.base, "--base"), (env_base, "env"), (pr_base, ""), ("origin/main", ""), ("main", "")):
        if not cand:
            continue
        if _git(root, "rev-parse", "--verify", "-q", cand + "^{commit}")[0] == 0:
            base_ref = cand
            break
        if src == "--base":
            raise NextError(f"base ref {cand} is not in this checkout")
        if src == "env":
            env_base_skipped = True

    col = Collector(root, branch, base_ref, args.gates)
    col.collect()
    notes += col.notes

    facts = Facts(**dict(col.facts, **ps.facts, pr_state_known=ps.known))
    known = ps.known
    try:
        result = state.derive(branch, ps.branch_pr, ps.open_lane_prs, facts, PathKind(path), solo)
    except ValueError as e:
        raise NextError(f"derive precondition: {e}")

    base_name_ = ps.branch_raw.base if ps.branch_raw else base_name(base_ref)
    # SEC-004: a stacked PR's instruction names the base's own open PR (this repository's, never a fork's).
    base_pr = min((p.number for p in ps.prs if p.is_open and not p.cross and p.head == base_name_), default=0) \
        if base_name_ != "main" else 0
    ctx = RenderCtx(repo=root, branch=branch_name, base=base_name_, slug=col.slug, version=col.version or "<version>",
                    plan_path=col.plan_path or "the plan", spec_slug=col.spec_slug, n=branch.n, stacked=ps.stacked,
                    head_oid=ps.branch_raw.head_oid if ps.branch_raw else "", base_pr=base_pr)
    findings = findings_text(ps.comment) if result.phase is Phase.blocked else None
    result, bad_text = guard_plan_slug(result, ps.bad_plans)
    if bad_text is None and branch.kind is K.Main:
        result, bad_text = guard_release_version(result, ps.bad_release, path == "lanes")
    next_step = bad_text if bad_text is not None else render_step(result.step, ctx)
    if bad_text is None and result.step.kind is SK.Merge:
        sn = stacked_merge_note(ctx)
        if sn:
            notes.append(sn)
    confirm = confirmation_point(result, facts, profile)
    next_step = guided_command(next_step, result.step, confirm)

    explain.append(f"branch {branch_name} parses as {branch.kind.value}; path {path}, profile {profile}, "
                   f"solo {str(solo).lower()}")
    if base_ref:
        rc, line = _git(root, "log", "-1", "--format=%h, committed %cs", base_ref)
        explain.append(f"base {base_ref} at {line} (this checkout's view; next.sh never fetches)")
    if env_base_skipped:
        explain.append(f"SPECFLOW_BASE_REF={env_base} is not in this checkout (set for CI's gate scripts); ignored, "
                       f"base {base_ref or '(none)'} used")
    explain += ps.why + col.why
    if col.want("unbuilt"):
        # Round 3b re-review D4: say where the release facts came from — never "not collected here".
        explain.append("unbuilt, untagged_ship, next_version, ship_phases_merged: " + (
            f"derived from the {sum(1 for p in ps.prs if p.is_merged)} merged PRs read through gh and this "
            "checkout's v<version> tags (PR state)" if ps.known else
            "they need the merged PRs, and the PR state could not be read — left empty"))

    if col.want("signing_key_present") or branch.kind in (K.Ship, K.PhaseSecurity, K.PhaseRelease):
        tk, tr = signers.signing_kind(root)
        explain.append(f"tag kind: {tk} ({tr})")
    # P6 R23 (REQ-354): say what release.yml does with signing: (explain-only; the kernel never sees it). Stack-aware
    # (Build 5 fix wave 1, C): python and the template build no bundle, so nothing is signed and no tester instructions
    # are attached there; for an app stack the line says what release.yml's signing-probe decides from the secrets.
    if template:
        explain.append("signing none (template source: config.DEFAULTS; no bundle to sign)")
    elif cfg.get("stack") not in ("tauri", "flutter"):
        explain.append(f"signing {cfg['signing']} (.specflow.yml; REQ-354): stack {cfg.get('stack') or 'python'} builds no "
                       "bundle (R23): nothing to sign or notarize")
    elif cfg["signing"] == "apple":
        explain.append("signing apple (.specflow.yml; REQ-354): release.yml signs and notarizes, and publishes nothing when "
                       "the release environment lacks any of the five APPLE_* secrets (signing-probe fails)")
    else:
        explain.append("signing none (.specflow.yml; REQ-354): release.yml records signed: false and attaches tester "
                       "instructions, unless the release environment holds all five APPLE_* secrets: then signing-probe "
                       "reports present and sign runs (signed: true)")
    ship = col.ship()
    if ship:
        if ship["reference_kind"] == "previous-tag":
            # P6 R9 (fix wave 2): /next reads the tag as this checkout sees it and never verifies it; release-tag.sh
            # verifies tags (signers.py), and release.yml does too. A convention point: the reference is advisory.
            explain.append(f"ship reference: {ship['reference']} (unverified: the tag as this checkout sees it — /next "
                           "never verifies it; release-tag.sh and release.yml verify release tags)")
        else:
            explain.append(f"ship reference: {ship['reference']} (the base: no previous release tag in this checkout)")
        n = len(ship["suppressions_added"])
        what = "previous release tag" if ship["reference_kind"] == "previous-tag" else "base"
        ship_line = (f"ship: reference {ship['reference']} ({what}); {n} suppression "
                     f"{'entry' if n == 1 else 'entries'} added")
    else:
        ship_line = None

    if args.json:
        out = {
            "ship": ship,
            "state": {"lane": result.lane.value, "phase": result.phase.value},
            "step": step_to_json(result.step),
            "next_step": next_step,
            "open_lanes": list(result.open_lanes),
            "open_lane_prs": ps.open_lanes_info,
            "confirm": confirm,
            "pr_state_known": known,
            "path": path,
            "profile": profile,
            "facts": _facts_json(facts, branch.kind),
            "findings": findings,
            "explain": explain,
            "notes": notes,
            "terms": [{"term": t, "anchor": a} for t, a in terms_for(result)],
        }
        print(json.dumps(out, sort_keys=True))
        return 0
    print(f"state: {result.lane.value} {result.phase.value}")
    print(f"next: {next_step}")
    if confirm:
        print(confirm_line(confirm))
    if ship_line:
        print(ship_line)
    if ps.open_lanes_info:
        print(open_lanes_line(ps.open_lanes_info))
    if findings:
        print(_findings_block(findings))
    print(terms_line(terms_for(result)))
    for n in notes:
        print(f"note: {n}")
    if args.explain:
        for w in explain:
            print(f"why: {w}")
    return 0


def main(argv: list) -> int:
    if len(argv) == 3 and argv[1] == "parse-branch":
        print(json.dumps(branch_to_json(parse_branch(argv[2])), sort_keys=True))
        return 0
    if len(argv) >= 2 and argv[1] == "derive":
        try:
            return derive_cmd(argv[2:])
        except NextError as e:
            print(f"ERROR next: {e}", file=sys.stderr)
            return 2
    print("usage: pipeline.py derive [...] | parse-branch NAME", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
