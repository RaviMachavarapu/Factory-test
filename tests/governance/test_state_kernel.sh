#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R5, R6): derive() is a pure, total function over the parsed branch, the branch's newest PR, the
# open lane PRs, the Facts record, the path and solo — exactly one Result for every input satisfying pre(), ValueError
# outside it. It is the twin of verification/factory_v3_2/state.dfy (one function per model function, the model's names
# in snake_case), and the fixtures mirror the model: one per state-table row, precedence rule and theorem, the factory's
# own mixed history, and the model's FixtureNN lemmas. A generated truth table over every Branch constructor x PR state
# x attestation x path x solo x human approval x three open-lane-PR sets x eight fact sets (main's tag, next-build,
# ready-to-ship and each regulated ship proposal reached) checks the theorems' twins. REQ-385: no Merge step
# without an open PR's APPROVE or waiver and, in team mode, a human approval. REQ-340: both paths' constructors, path
# closure of every proposal.
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; K="$LIB/state.py"; FX="$ROOT/tests/governance/fixtures/state"
DFY="$ROOT/verification/factory_v3_2/state.dfy"
ck "records.py and state.py exist" test -f "$LIB/records.py" -a -f "$K"
for f in pre numbers_of own_numbers min_of lane_of lane_list first_missing_after_last_present lane_phase phase_step \
         impl_target_of pr_substate main_result regulated_ship_proposal phase_order set_fact lanes_proposal \
         regulated_proposal derive; do
  ck "the twin defines $f (the model's name, snake_case)" grep -qE "^def $f\(" "$K"
done
if [[ -f "$DFY" ]]; then   # the model ships only in the template source (P5 R11)
  ck "each FixtureNN lemma of the model has its fixture NN-*.json, which names the lemma" bash -c \
    'for n in $(grep -oE "lemma Fixture[0-9]+" "$1" | grep -oE "[0-9]+"); do f=$(ls "$2/$n-"*.json 2>/dev/null | head -1); [ -n "$f" ] && grep -qF "\"Fixture$n\"" "$f" || exit 1; done' _ "$DFY" "$FX"
fi
ck "the kernel is pure: it imports only records and typing/dataclasses/enum, and calls no I/O" python3 - "$K" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
allowed = {"__future__", "dataclasses", "enum", "typing", "records"}
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        assert {a.name.split(".")[0] for a in n.names} <= allowed, [a.name for a in n.names]
    if isinstance(n, ast.ImportFrom):
        assert (n.module or "").split(".")[0] in allowed, n.module
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
        assert n.func.id not in ("open", "print", "input", "exec", "eval", "__import__"), n.func.id
PY
n=$(find "$FX" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
ck "at least 76 kernel fixtures ($n)" [ "${n:-0}" -ge 76 ]
for k in Main Design Build BuildSec Ship Patch PhaseSpec PhaseArch PhasePlan Impl ImplSec PhaseValidate PhaseSecurity PhaseRelease Unknown; do
  ck "some fixture's branch is $k" bash -c 'grep -lE "\"kind\": \"$1\"" "$2"/*.json 2>/dev/null | grep -q .' _ "$k" "$FX"
done
REPORT="$(mktemp)"
python3 - "$LIB" "$FX" > "$REPORT" <<'PY'
import glob, itertools, json, os, sys
sys.path.insert(0, sys.argv[1])
import records as R, state as S
bad = []
def run(fx):
    try:
        r = S.derive(R.branch_from_json(fx["branch"]), R.pr_from_json(fx["branch_pr"]) if fx["branch_pr"] else None,
                     tuple(R.pr_from_json(p) for p in fx["open_lane_prs"]), R.facts_from_json(fx["facts"]),
                     R.Path(fx["path"]), fx["solo"])
        return R.result_to_json(r)
    except ValueError:
        return {"error": "ValueError"}
for p in sorted(glob.glob(os.path.join(sys.argv[2], "*.json"))):
    fx = json.load(open(p)); got = run(fx)
    if got != fx["expect"]:
        bad.append(f"{os.path.basename(p)}: got {got}, want {fx['expect']}")
    if run(fx) != got:
        bad.append(f"{os.path.basename(p)}: not deterministic")
K = R.BranchKind
B = [R.Branch(K.Main), R.Branch(K.Design, slug="a"), R.Branch(K.Build, slug="a", n=1), R.Branch(K.Build, slug="a", n=3),
     R.Branch(K.BuildSec, id="SEC-004"), R.Branch(K.Ship, version="0.2.0"), R.Branch(K.Patch, slug="a"),
     R.Branch(K.PhaseSpec, slug="a"), R.Branch(K.PhaseArch, slug="a"), R.Branch(K.PhasePlan, slug="a"),
     R.Branch(K.Impl, plan="1a", name="a"), R.Branch(K.ImplSec, id="SEC-004"), R.Branch(K.PhaseValidate),
     R.Branch(K.PhaseSecurity), R.Branch(K.PhaseRelease), R.Branch(K.Unknown)]
def facts(**kw):
    base = dict(has_brainstorm=False, has_spec=False, spec_has_tagged_reqs=False, arch_complete=False, has_plan=False,
                build_sections=frozenset({1}), analyze_ok=False, has_source_diff=False, gates_pass=False,
                has_security_docs=False, has_release_docs=False, signing_key_present=False, pr_state_known=True,
                unbuilt=(), untagged_ship=None, next_version=None, ship_phases_merged=frozenset())
    base.update(kw)
    return R.Facts(**base)
RS = R.RegShip
F = [facts(), facts(pr_state_known=False),
     facts(has_brainstorm=True, has_spec=True, spec_has_tagged_reqs=True, has_plan=True),
     facts(has_brainstorm=True, has_spec=True, has_plan=True, analyze_ok=True, has_source_diff=True, gates_pass=True,
           has_security_docs=True, has_release_docs=True, unbuilt=(("a", 2),), next_version="0.2.0"),
     facts(untagged_ship="0.1.0", next_version="0.2.0"),                          # main: tag
     facts(next_version="0.2.0"),                                                 # main: ready-to-ship, validate
     facts(next_version="0.2.0", ship_phases_merged=frozenset({RS.validate})),    # … security
     facts(next_version="0.2.0", ship_phases_merged=frozenset({RS.validate, RS.security}))]  # … release
SUB = {"request_changes": "blocked", "none": "awaiting-verifier"}
OWN12 = R.PR(12, True, False, False, False, R.Attestation.none, True)
OWN15 = R.PR(15, True, False, False, False, R.Attestation.none, True)
OTHER9 = R.PR(9, True, False, False, False, R.Attestation.none, False)
OLP = [(), (OTHER9,), (OWN15, OTHER9, OWN12)]   # none; another user's only; two own PRs and a lower foreign one
rows = 0
seen = set()
for b, f, path, solo, human, att, st, olp in itertools.product(B, F, list(R.Path), (True, False), (True, False),
                                                              list(R.Attestation), ("none", "open", "merged", "closed"), OLP):
    pr = None if st == "none" else R.PR(7, st == "open", st == "merged", st == "closed", human, att, True)
    args = (b, pr, olp, f, path, solo)
    if not S.pre(*args):
        try:
            S.derive(*args); bad.append(f"no ValueError outside pre: {args}")
        except ValueError:
            pass
        continue
    r = S.derive(*args); rows += 1; k = r.step.kind.value
    seen.add((b.kind.value, r.phase.value, k, r.step.proposal.kind.value if r.step.proposal else ""))
    lane_branch = b.kind not in (K.Main, K.Unknown)
    if k == "Merge" and not (pr and pr.open and pr.attestation in (R.Attestation.approve, R.Attestation.waiver)
                             and r.step.pr == pr.number and (solo or pr.human_approved) and lane_branch):
        bad.append(f"MergeOnlyWhenApproved: {args} -> {r}")
    if not f.pr_state_known and k == "CreatePr":
        bad.append(f"NoBlindCreatePr: {args} -> {r}")
    if k == "NewBranch" and not (S.lanes_proposal(r.step.proposal) if path is R.Path.lanes else S.regulated_proposal(r.step.proposal)):
        bad.append(f"PathClosure: {args} -> {r}")
    if b.kind is K.Unknown and (r.phase.value, k) != ("unknown-branch", "ExplainUnknown"):
        bad.append(f"UnknownBranchNeverMerges: {args} -> {r}")
    if pr and pr.open and lane_branch:
        want = SUB.get(att.value) or ("awaiting-merge" if solo or human else "awaiting-human-review")
        if r.phase.value != want or r.lane is not S.lane_of(b):
            bad.append(f"PrPrecedence: {args} -> {r}")
    if pr is None and lane_branch and S.phase_order(r.phase) < 9:
        g = S.set_fact(f, r.phase)
        new = S.derive(b, None, olp, g, path, solo) if S.pre(b, None, olp, g, path, solo) else None
        if new is None or not (S.phase_order(r.phase) < S.phase_order(new.phase) <= 9) or new.lane is not S.lane_of(b):
            bad.append(f"Progress (forward, in the lane's order): {args} -> {r} -> {new}")
    own = [p.number for p in olp if p.mine]
    if b.kind is K.Main and k == "Checkout" and (not own or r.step.pr != min(own)):
        bad.append(f"MainChecksOutLowestOwn: main checks out the lowest own PR, never another user's: {args} -> {r}")
    if b.kind is K.Main and not own and (k == "Checkout" or r.phase.value == "awaiting-merge"):
        bad.append(f"OtherUsersPrsNeverBlock: {args} -> {r}")
    if b.kind is K.Main and k == "TagRelease" and r.lane is not (R.Lane.ship if path is R.Path.lanes else R.Lane.release):
        bad.append(f"main's tag step is in the path's ship lane: {args} -> {r}")
    if r.open_lanes != tuple(sorted(p.number for p in olp)):
        bad.append(f"open_lanes: {r}")
if rows < 40000:
    bad.append(f"only {rows} truth-table rows satisfied pre")
for want in (("Main", "tag", "TagRelease", ""), ("Main", "next-build", "NewBranch", "ProposeBuild"),
             ("Main", "next-build", "NewBranch", "ProposeImpl"), ("Main", "ready-to-ship", "NewBranch", "ProposeShip"),
             ("Main", "ready-to-ship", "NewBranch", "ProposeValidate"), ("Main", "ready-to-ship", "NewBranch", "ProposeSecurity"),
             ("Main", "ready-to-ship", "NewBranch", "ProposeRelease"), ("Main", "awaiting-merge", "Checkout", ""),
             ("Main", "idle", "NewBranch", "ProposeDesign"), ("Main", "idle", "NewBranch", "ProposeSpec")):
    if want not in seen:
        bad.append(f"the truth table never reaches {want}: the PathClosure and main twins are not exercised there")
if bad:
    print("\n".join(bad))
PY
ck "every fixture's Result matches and repeats; the truth table satisfies the five theorems' twins" [ ! -s "$REPORT" ]
if [ -s "$REPORT" ]; then head -20 "$REPORT"; fi
rm -f "$REPORT"
finish test_state_kernel
