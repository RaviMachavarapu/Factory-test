#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R5, R8): parse_branch is total over both paths' names — build/sec-<id> before the build split,
# build/<slug>-N on the last '-', impl/plan-<token>-<name> with the factory's 1a/1b tokens, legacy phase/spec, retro and
# foreign prefixes Unknown — and every kernel fixture's branch_name parses to its branch. REQ-385: the awaiting-verifier
# step renders the complete second-terminal instruction, verbatim, piping main's reviewed copy of the script for EVERY PR
# (the SEC-004 back-edge: a stacked PR's base is an unreviewed branch its author chose, so its run-verifier.sh is never
# piped into bash) and, for a stacked PR, one more sentence naming the unreviewed base PR (P5 R22's warning, superseded)
# — main read by its full ref refs/remotes/origin/main, never the tag-shadowable short name (P6 build 3, PR #54 verifier
# run 2, finding 3); blocked never renders a merge, and a merge with a PR stacked on the branch keeps a merge commit: two
# commands, the merge first, then the retarget, the prose in a notes line (PR #48 verifier run 4, finding 6).
# REQ-340: both paths' proposals render to branch names that parse back. REQ-342's confirmation points are pure
# functions of the Result's lane and phase (never its step), the facts and the profile. REQ-308: every glossary term /next prints links to a real heading.
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-340
# Covers: REQ-308
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; P="$LIB/pipeline.py"; FX="$ROOT/tests/governance/fixtures/state"
ck "pipeline.py exists" test -f "$P"
ck "parse-branch prints Branch JSON" bash -c 'python3 "$1" parse-branch build/sec-SEC-004 | grep -qF "\"BuildSec\""' _ "$P"
REPORT="$(mktemp)"
python3 - "$LIB" "$FX" "$ROOT/docs/GLOSSARY.md" > "$REPORT" <<'PY'
import dataclasses, glob, json, os, re, sys
sys.path.insert(0, sys.argv[1])
import records as R, pipeline as P
bad = []
TABLE = """main|{"kind": "Main"}
design/habit-tracker|{"kind": "Design", "slug": "habit-tracker"}
build/habit-tracker-2|{"kind": "Build", "slug": "habit-tracker", "n": 2}
build/a-b-10|{"kind": "Build", "slug": "a-b", "n": 10}
build/sec-SEC-004|{"kind": "BuildSec", "id": "SEC-004"}
build/sec-4|{"kind": "BuildSec", "id": "4"}
build/habit-tracker|{"kind": "Unknown"}
build/habit-tracker-0|{"kind": "Unknown"}
ship/0.2.0|{"kind": "Ship", "version": "0.2.0"}
ship/1.0.0-rc.1|{"kind": "Ship", "version": "1.0.0-rc.1"}
ship/v1.0.0|{"kind": "Unknown"}
patch/first-run-argmax|{"kind": "Patch", "slug": "first-run-argmax"}
phase/spec-factory-v3-2|{"kind": "PhaseSpec", "slug": "factory-v3-2"}
phase/spec-v3.1|{"kind": "PhaseSpec", "slug": "v3.1"}
phase/arch-factory-v3-2-fixes|{"kind": "PhaseArch", "slug": "factory-v3-2-fixes"}
phase/plan-factory-v3-2-p5|{"kind": "PhasePlan", "slug": "factory-v3-2-p5"}
impl/plan-5-orchestrator|{"kind": "Impl", "plan": "5", "name": "orchestrator"}
impl/plan-1a-first-run|{"kind": "Impl", "plan": "1a", "name": "first-run"}
impl/plan-0-plan-scoping|{"kind": "Impl", "plan": "0", "name": "plan-scoping"}
impl/sec-SEC-004|{"kind": "ImplSec", "id": "SEC-004"}
phase/validate|{"kind": "PhaseValidate"}
phase/security|{"kind": "PhaseSecurity"}
phase/release|{"kind": "PhaseRelease"}
phase/spec|{"kind": "Unknown"}
phase/retro-2026-06-09|{"kind": "Unknown"}
impl/fix-p0-ci-enforcement|{"kind": "Unknown"}
impl/p1-adoption-path|{"kind": "Unknown"}
chore/template-cleanup|{"kind": "Unknown"}
diag/first-run-floor|{"kind": "Unknown"}
dependabot/pip/scripts/ruff-0.16.8|{"kind": "Unknown"}
design/|{"kind": "Unknown"}
design/sec-x|{"kind": "Unknown"}
patch/sec-x|{"kind": "Unknown"}
phase/spec-sec-x|{"kind": "Unknown"}
phase/arch-sec-x|{"kind": "Unknown"}
phase/plan-sec-x|{"kind": "Unknown"}
design/secure-login|{"kind": "Design", "slug": "secure-login"}
build/sec-x-1|{"kind": "BuildSec", "id": "x-1"}
design/a/b|{"kind": "Unknown"}
HEAD|{"kind": "Unknown"}"""
for row in TABLE.splitlines():
    name, want = row.split("|", 1)
    got = R.branch_to_json(P.parse_branch(name))
    if got != json.loads(want):
        bad.append(f"parse_branch({name!r}) = {got}, want {want}")
for p in sorted(glob.glob(os.path.join(sys.argv[2], "*.json"))):
    fx = json.load(open(p))
    if "branch_name" in fx and R.branch_to_json(P.parse_branch(fx["branch_name"])) != fx["branch"]:
        bad.append(f"{os.path.basename(p)}: branch_name {fx['branch_name']!r} does not parse to its branch")
ctx = P.RenderCtx(repo="/work/my repo", branch="design/habit", base="main", slug="habit", version="0.2.0",
                  plan_path="docs/plans/2026-09-28-habit-plan.md", spec_slug="2026-09-28-habit", head_oid="a" * 40)
St, SK = R.Step, R.StepKind
want = ("In a second terminal, not inside Claude — open a new terminal window (Terminal.app or your shell) and run: "
        "cd '/work/my repo' && git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7; "
        "when it prints \"Findings posted to PR #7\", return here and run /next.")
if P.render_step(St(SK.RunVerifier, pr=7), ctx) != want:
    bad.append("RunVerifier does not render REQ-385's instruction verbatim: " + P.render_step(St(SK.RunVerifier, pr=7), ctx))
# SEC-004 (high, dfe-9/dfe-10; REQ-385 as amended by the SEC-004 back-edge): a stacked PR's instruction pipes main's
# reviewed run-verifier.sh, never its base's, and adds one sentence naming the unreviewed base PR — on the same line.
stacked = dataclasses.replace(ctx, repo="/w", base="phase/plan-factory-v3-2-p5", base_pr=46)
sv = P.render_step(St(SK.RunVerifier, pr=47), stacked)
want_sv = ("In a second terminal, not inside Claude — open a new terminal window (Terminal.app or your shell) and run: "
           "cd /w && git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 47; "
           "when it prints \"Findings posted to PR #47\", return here and run /next.")
if not sv.startswith(want_sv):
    bad.append("RunVerifier on a stacked PR does not pipe main's reviewed copy (SEC-004): " + sv)
if "origin/phase/plan-factory-v3-2-p5:" in sv or "Warning:" in sv or "read it first" in sv:
    bad.append("RunVerifier on a stacked PR still names the base's run-verifier.sh (SEC-004): " + sv)
if "the base PR #46 is unreviewed; its diff is reviewed by its own PR" not in sv or "\n" in sv:
    bad.append("RunVerifier on a stacked PR does not name, on the same line, the unreviewed base PR #46 (SEC-004): " + sv)
if "merge #46 first, then retarget" not in sv:
    bad.append("RunVerifier on a stacked PR does not say merge the base PR first, then retarget (SEC-004): " + sv)
# SEC-004 review round 2, finding 2: the merge commit /next prints for #46 keeps the merge base, so the marker carries
# over rather than the PR being reviewed against main; only a squash merge needs the verifier again.
if "to review it against main" in sv or "carry over" not in sv or "after a squash merge, run the verifier again" not in sv:
    bad.append("RunVerifier on a stacked PR misstates what the retarget does (merge commit: carries over; squash: re-run) (SEC-004 round 2): " + sv)
nopr = P.render_step(St(SK.RunVerifier, pr=47), dataclasses.replace(stacked, base_pr=0))
if not nopr.startswith(want_sv) or "phase/plan-factory-v3-2-p5" not in nopr or "unreviewed" not in nopr or "PR #0" in nopr:
    bad.append("a stacked PR whose base has no open PR does not name the base branch as unreviewed (SEC-004): " + nopr)
if P.render_step(St(SK.Merge, pr=12), ctx) != "gh pr merge 12 --squash --match-head-commit " + "a" * 40:
    bad.append("Merge does not render 'gh pr merge 12 --squash --match-head-commit <head>' (bound to the attested head)")
# PR #48 verifier run 4, finding 6 (W5): the stacked merge is shell commands joined by ' && ', the merge commit FIRST
# (no --delete-branch: the branch survives, so the stacked PR keeps the merge base its marker recorded), then each
# retarget; the prose moves to a notes line.
import shlex
sm = P.render_step(St(SK.Merge, pr=12), dataclasses.replace(ctx, stacked=(47,)))
if sm != "gh pr merge 12 --merge --match-head-commit " + "a" * 40 + " && gh pr edit 47 --base main":
    bad.append(f"Merge with PR #47 stacked on the branch renders {sm!r}, not 'gh pr merge 12 --merge --match-head-commit <head> && gh pr edit 47 --base main'")
if "\u2014" in sm or shlex.split(sm) != ["gh", "pr", "merge", "12", "--merge", "--match-head-commit", "a" * 40, "&&",
                                       "gh", "pr", "edit", "47", "--base", "main"] or "--delete-branch" in sm:
    bad.append(f"the stacked merge line is not exactly the two commands (shlex.split, no em dash, no --delete-branch): {sm!r}")
sm2 = P.render_step(St(SK.Merge, pr=12), dataclasses.replace(ctx, stacked=(47, 49)))
if sm2 != "gh pr merge 12 --merge --match-head-commit " + "a" * 40 + " && gh pr edit 47 --base main && gh pr edit 49 --base main":
    bad.append(f"Merge with PRs #47 and #49 stacked renders {sm2!r}, not the merge then both retargets")
note = P.stacked_merge_note(dataclasses.replace(ctx, stacked=(47,)))
for t in ("PR #47 is stacked on this branch", "merges first", "merge commit", "keeps", "merge base", "then retargeted",
          "never delete", "before the retarget", "up to date", "gh pr update-branch 47"):
    if t not in (note or ""):
        bad.append(f"the stacked-merge note lacks {t!r}: {note!r}")
# Wave-4 re-review low 1 (REQ-385): a nested stack retargets to THIS PR's own base (shell-quoted), never main; nit 3: the
# note says the update-branch makes a new head, so the stacked PR needs a fresh verifier run.
nest = dataclasses.replace(ctx, base="build/x-1", stacked=(47,))
if P.render_step(St(SK.Merge, pr=12), nest) != "gh pr merge 12 --merge --match-head-commit " + "a" * 40 + " && gh pr edit 47 --base build/x-1":
    bad.append(f"a nested stacked merge does not retarget #47 to this PR's base: {P.render_step(St(SK.Merge, pr=12), nest)!r}")
qb = P.render_step(St(SK.Merge, pr=12), dataclasses.replace(nest, base="x;touch y"))
if not qb.endswith("gh pr edit 47 --base 'x;touch y'"):
    bad.append(f"the retarget's base is not shell-quoted: {qb!r}")
nn = P.stacked_merge_note(nest) or ""
if "retargeted to build/x-1" not in nn or "retargeted to main" in nn:
    bad.append(f"the nested note does not name this PR's base: {nn!r}")
for t in ("the update creates a new head, so the stacked PR needs a fresh verifier run (/next shows awaiting-verifier)",):
    if t not in (note or ""):
        bad.append(f"the stacked-merge note lacks {t!r}")
if P.stacked_merge_note(ctx) is not None:
    bad.append("a merge with nothing stacked carries a stacked-merge note")
evil = dataclasses.replace(ctx, repo="/w", base="plan;touch${IFS}pwned;x")
ev = P.render_step(St(SK.RunVerifier, pr=7), evil)
if "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7" not in ev \
        or "'plan;touch${IFS}pwned;x'" not in ev or re.search(r"(^|[\s/])plan;", ev) or "pwned;x:scripts" in ev:
    bad.append(f"RunVerifier interpolates a base name with shell metacharacters unquoted, or pipes the base's script: {ev!r}")
if "design/sec-x" not in P.render_step(St(SK.ExplainUnknown, why=R.Why.BranchUnknown), dataclasses.replace(ctx, branch="design/sec-x")) \
        or "sec-" not in P.render_step(St(SK.ExplainUnknown, why=R.Why.BranchUnknown), dataclasses.replace(ctx, branch="design/sec-x")).split("design/sec-x", 1)[1]:
    bad.append("a design/sec-<slug> branch is not explained as the sec- slug collision")
if "gh pr merge" in P.render_step(St(SK.AddressFindings, pr=12), ctx):
    bad.append("AddressFindings renders a merge command")
PK, Pr = R.ProposalKind, R.Proposal
props = {PK.ProposeDesign: ("git checkout -b design/<slug>", "Design"), PK.ProposeSpec: ("git checkout -b phase/spec-<slug>", "PhaseSpec"),
         PK.ProposeValidate: ("git checkout -b phase/validate", "PhaseValidate"),
         PK.ProposeSecurity: ("git checkout -b phase/security", "PhaseSecurity"),
         PK.ProposeRelease: ("git checkout -b phase/release", "PhaseRelease")}
for kind, (text, parsed) in props.items():
    out = P.render_step(St(SK.NewBranch, proposal=Pr(kind)), ctx)
    if text not in out:
        bad.append(f"{kind.value} renders {out!r}, lacking {text!r}")
    name = out.split("git checkout -b ", 1)[1].split()[0].replace("<slug>", "x")
    if R.branch_to_json(P.parse_branch(name))["kind"] != parsed:
        bad.append(f"{kind.value}'s branch {name} does not parse to {parsed}")
for kind in (PK.ProposeDesign, PK.ProposeSpec):
    if "/superpowers:brainstorming" not in P.render_step(St(SK.NewBranch, proposal=Pr(kind)), ctx):
        bad.append(f"{kind.value} does not follow the branch with brainstorming (ADR-003; P5 R4)")
for pr, text, parsed in ((Pr(PK.ProposeBuild, slug="habit", n=2), "git checkout -b build/habit-2", "Build"),
                         (Pr(PK.ProposeImpl, slug="habit", n=2), "git checkout -b impl/plan-2-habit", "Impl"),
                         (Pr(PK.ProposeShip, version="0.2.0"), "git checkout -b ship/0.2.0", "Ship")):
    out = P.render_step(St(SK.NewBranch, proposal=pr), ctx)
    if text not in out or R.branch_to_json(P.parse_branch(text.split()[-1]))["kind"] != parsed:
        bad.append(f"{pr} renders {out!r}")
# PR #48 verifier run 3, code low c: a proposal whose slug is not a branch-name token renders no command.
for kind in (PK.ProposeBuild, PK.ProposeImpl):
    out = P.render_step(St(SK.NewBranch, proposal=Pr(kind, slug="a;touch x", n=1)), ctx)
    if "git checkout" in out:
        bad.append(f"{kind.value} with slug 'a;touch x' renders a command: {out!r}")
for k in SK:
    step = St(k, pr=7, proposal=Pr(PK.ProposeDesign), target=R.ImplTarget(R.TargetKind.Section, n=1), version="0.2.0",
              why=R.Why.BranchUnknown)
    if not P.render_step(step, ctx).strip():
        bad.append(f"{k.value} renders nothing")
retro = dataclasses.replace(ctx, branch="phase/retro-2026-06-09")
if "/retrospective" not in P.render_step(St(SK.ExplainUnknown, why=R.Why.BranchUnknown), retro):
    bad.append("a retrospective branch is not explained as one (P5 R8)")
if "gh auth status" not in P.render_step(St(SK.ExplainUnknown, why=R.Why.PrStateUnknown), ctx):
    bad.append("PrStateUnknown does not say how to restore PR state")
L, Ph = R.Lane, R.Phase
def res(lane, phase, step):
    return R.Result(L(lane), Ph(phase), step, ())
F0 = R.facts_from_json({})
FS = R.facts_from_json({"signing_key_present": True})
cases = [(res("design", "specify", St(SK.RunSpecify)), F0, "brainstorm-end"),
         (res("design", "open-pr", St(SK.CreatePr)), F0, "design-pr"),
         (res("design", "open-pr", St(SK.ExplainUnknown, why=R.Why.PrStateUnknown)), F0, "design-pr"),
         (res("build", "open-pr", St(SK.ExplainUnknown, why=R.Why.PrStateUnknown)), F0, "build-pr"),
         (res("ship", "open-pr", St(SK.ExplainUnknown, why=R.Why.PrStateUnknown)), F0, "ship-pr"),
         (res("spec", "open-pr", St(SK.CreatePr)), F0, "design-pr"),
         (res("plan", "open-pr", St(SK.CreatePr)), F0, "design-pr"),
         (res("build", "open-pr", St(SK.CreatePr)), F0, "build-pr"),
         (res("impl", "open-pr", St(SK.CreatePr)), F0, "build-pr"),
         (res("validate", "open-pr", St(SK.CreatePr)), F0, "build-pr"),
         (res("ship", "open-pr", St(SK.CreatePr)), F0, "ship-pr"),
         (res("release", "open-pr", St(SK.CreatePr)), F0, "ship-pr"),
         (res("build", "awaiting-verifier", St(SK.RunVerifier, pr=7)), F0, "awaiting-verifier"),
         (res("build", "awaiting-merge", St(SK.Merge, pr=7)), F0, "merge"),
         (res("ship", "tag", St(SK.TagRelease, version="0.2.0")), F0, "unsigned-tag"),
         (res("ship", "tag", St(SK.TagRelease, version="0.2.0")), FS, None),
         (res("build", "implement", St(SK.RunImplement, target=R.ImplTarget(R.TargetKind.Section, n=1))), F0, None)]
for result, facts, want in cases:
    if P.confirmation_point(result, facts, "guided") != want:
        bad.append(f"guided confirmation_point({result.lane.value}, {result.phase.value}) = "
                   f"{P.confirmation_point(result, facts, 'guided')}, want {want}")
    if P.confirmation_point(result, facts, "engineer") is not None:
        bad.append(f"engineer profile pauses at {result.phase.value}")
anchors = set()
for line in open(sys.argv[3]):
    if line.startswith("### "):
        anchors.add(re.sub(r"[^a-z0-9 -]", "", line[4:].strip().lower()).replace(" ", "-"))
for term, anchor in P.GLOSSARY_TERMS:
    if anchor not in anchors:
        bad.append(f"glossary term {term!r} links #{anchor}, which docs/GLOSSARY.md has no heading for")
for need in ("/next", "Awaiting verifier", "Confirmation point", "Derive", "Facts"):
    if need not in dict(P.GLOSSARY_TERMS):
        bad.append(f"GLOSSARY_TERMS lacks {need}")
t = P.terms_for(res("design", "awaiting-verifier", St(SK.RunVerifier, pr=7)))
if len(t) != len(set(t)):
    bad.append("terms_for repeats a term (REQ-308: linked on first use, once)")
print("\n".join(bad), end="")
PY
ck "parse_branch, render_step, confirmation_point and the glossary links behave as Interfaces 'The wrapper' says" [ ! -s "$REPORT" ]
if [ -s "$REPORT" ]; then head -20 "$REPORT"; fi
rm -f "$REPORT"
finish test_next_render
