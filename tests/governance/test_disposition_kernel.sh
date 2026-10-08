#!/usr/bin/env bash
# REQ-322 (ADR-002): decide() is a pure function over the review findings, the disposition entries and the latest prior
# entry per id: PASS iff rules 1–5 hold; order-independent; lows with fresh ids never affect rules 2–5; zero findings with
# no due carry-forward pass; a precondition violation raises ValueError (exit 2 in the wrapper), never FAIL. It is the
# twin of verification/factory_v3_2/disposition.dfy: the rule functions carry the model's predicate names, and the
# fixtures mirror the model — one per rule and sub-clause, the downgrade path, the expired-prior carry-forward, a
# lows-only case, the zero-findings case — each also run under five shuffles of every input.
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; K="$LIB/disposition.py"; FX="$ROOT/tests/governance/fixtures/disposition"
DFY="$ROOT/verification/factory_v3_2/disposition.dfy"
ck "records.py and disposition.py exist" test -f "$LIB/records.py" -a -f "$K"
# P5 R11: the model ships only in the template source; an instance keeps the twin and its fixtures.
if [[ -f "$DFY" ]]; then
  ck "the model carries its Proves header in the first five lines" bash -c 'head -5 "$1" | grep -qx "// Proves: REQ-322"' _ "$DFY"
  for p in Rule1SetEquality Rule2SevereFixed Rule3MediumCap Rule4CarryForward Rule5ExpiryWindow AllRulesHold Pre Decide \
           SevIs JoinedSevere JoinedAtLeastMedium RankedBelow Due Lapsed ReclassOk EntryCarries CarriedOk InWindow MediumsAD \
           V1 V2 V3 V4 V5 Violations2to5 Violations; do
    ck "the model defines $p" grep -qE "(predicate|function) $p[(<]" "$DFY"
  done
  for l in DecidePassIffAllRulesHold DecidePermutationInvariant LowsInertForRules2to5 ZeroFindingsPass \
           InWindowBoundaries DueBoundaries LapsedBoundaries DowngradeByOwnerNotCarried SeverePriorLeftAcceptedNotCarried \
           MediumsADCountsOnlyAcceptedDeferredMediums Fixture13 Fixture19 Fixture20 Fixture24 Fixture25 Fixture33 Fixture34; do
    ck "the model proves $l" grep -qE "lemma $l[(<]" "$DFY"
  done
  ck "each FixtureNN lemma of the model has its fixture NN-*.json" bash -c \
    'for n in $(grep -oE "lemma Fixture[0-9]+" "$1" | grep -oE "[0-9]+"); do ls "$2/$n-"*.json >/dev/null 2>&1 || exit 1; done' _ "$DFY" "$FX"
  ck "the model assumes nothing (no {:axiom}, no assume statement)" no grep -qE '\{:axiom\}|^[[:space:]]*assume[[:space:]]' "$DFY"
fi
for f in rule1_set_equality rule2_severe_fixed rule3_medium_cap rule4_carry_forward rule5_expiry_window all_rules_hold pre decide \
         sev_is joined_severe joined_at_least_medium ranked_below due lapsed reclass_ok entry_carries carried_ok in_window mediums_ad \
         v1 v2 v3 v4 v5 violations_2to5 violations; do
  ck "the twin defines $f (the model's name, snake_case)" grep -qE "^def $f\(" "$K"
done
ck "the kernel is pure: no I/O imports, no open/print/input" python3 - "$K" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
allowed = {"__future__", "dataclasses", "datetime", "enum", "typing", "records", "cvss4"}
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        assert {a.name.split(".")[0] for a in n.names} <= allowed, [a.name for a in n.names]
    if isinstance(n, ast.ImportFrom):
        assert (n.module or "").split(".")[0] in allowed, n.module
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
        assert n.func.id not in ("open", "print", "input", "exec", "eval"), n.func.id
PY
n=$(find "$FX" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
ck "at least 34 kernel fixtures ($n)" [ "${n:-0}" -ge 34 ]
for r in set_equality severe_not_fixed medium_cap carry_forward expiry_window; do
  ck "some fixture expects a $r violation" bash -c 'grep -l "\"$1\"" "$2"/*.json 2>/dev/null | grep -q .' _ "$r" "$FX"
done
report=$(python3 - "$LIB" "$FX" "$ROOT/tests/governance/fixtures/cvss4/vectors.json" <<'PY'
import datetime, glob, json, os, random, sys
sys.path.insert(0, sys.argv[1]); import records as R, disposition as D
vec = {}
for c in json.load(open(sys.argv[3]))["vectors"]:
    vec.setdefault(c["severity"], c["vector"])
day = lambda s: datetime.date.fromisoformat(s) if s else None
def load(fx):
    v = lambda s: vec[s[1:]] if s.startswith("@") else s
    rv = [R.Finding(f["id"], R.Severity(f["severity"]), v(f["cvss_vector"])) for f in fx["review"]]
    dp = [R.Entry(e["id"], R.Status(e["status"]), e.get("owner", ""), day(e.get("expiry")), e.get("rationale", ""),
                  e.get("reclassified_by")) for e in fx["disposition"]]
    pr = [R.PriorEntry(p["id"], R.Severity(p["severity"]), R.Status(p["status"]), day(p.get("expiry")), p["version"])
          for p in fx["prior"]]
    return rv, dp, pr, fx["medium_cap"], fx["expiry_horizon_days"], day(fx["run_date"])
def run(args):
    try:
        v = D.decide(*args)
        return {"passed": v.passed, "violations": [[x.id, x.rule.value] for x in v.violations]}
    except ValueError:
        return {"error": "ValueError"}
bad = []
for p in sorted(glob.glob(os.path.join(sys.argv[2], "*.json"))):
    name = os.path.basename(p); fx = json.load(open(p)); args = load(fx); got = run(args)
    if got != fx["expect"]:
        bad.append(f"{name}: got {got}, want {fx['expect']}"); continue
    if "passed" in got and got["passed"] != D.all_rules_hold(*args):
        bad.append(f"{name}: decide().passed != all_rules_hold() (theorem 1's twin)")
    for seed in range(5):
        rng = random.Random(seed); sh = [list(a) for a in args[:3]]
        for s in sh: rng.shuffle(s)
        if run((sh[0], sh[1], sh[2]) + args[3:]) != got:
            bad.append(f"{name}: verdict changes under shuffle seed {seed}")
print("\n".join(bad))
PY
)
ck "every fixture's verdict matches, equals all_rules_hold, and survives five shuffles${report:+: $report}" [ -z "$report" ]
finish test_disposition_kernel
