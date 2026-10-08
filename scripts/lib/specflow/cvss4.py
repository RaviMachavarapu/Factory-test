"""scripts/lib/specflow/cvss4.py — CVSS v4.0 scoring (REQ-322, ADR-002; R8, R9, R20).

Ports FIRST's own algorithm (macroVector(), m(), getEQMaxes(), extractValueMetric(), cvss_score()) from cvss_score.js,
line by line, over the vendored lookup data in cvss4_data.py (vendored once, at authoring time, from
https://github.com/FIRSTdotorg/cvss-v4-calculator at commit c5b0d409ae9f57c44264c6ce5f27d89298e1d32a; BSD-2-Clause,
notice in cvss4_LICENSE). Pure: no network, no file I/O, no imports beyond cvss4_data and the stdlib — this module is
imported by the disposition kernel (scripts/lib/specflow/disposition.py), which must itself stay pure.

Rounding follows JavaScript's `Math.round(value * 10) / 10` exactly (round-half-up, never Python's banker's rounding):
reproduced as `math.floor(value * 10 + 0.5) / 10`.
"""

from __future__ import annotations

import math

from cvss4_data import LOOKUP, MAX_COMPOSED, MAX_SEVERITY, METRIC_ORDER, METRIC_VALUES

BASE_METRICS = METRIC_ORDER[:11]


class CvssError(ValueError):
    """A CVSS v4.0 vector string is malformed or uses a value outside the specification."""


# --- parsing -----------------------------------------------------------------------------------------------------


def parse(vector: str) -> dict:
    """Parse a `CVSS:4.0/...` vector string into a metric -> value dict.

    The eleven base metrics are mandatory, in the specification's order (METRIC_ORDER[:11]); optional metrics
    (Threat, Environmental, Supplemental) may follow, also in order. Unknown metric, invalid value, a duplicate
    metric, a missing base metric, an out-of-order metric, an empty segment or a trailing "/" all raise CvssError.
    """
    if not isinstance(vector, str) or not vector.startswith("CVSS:4.0/"):
        raise CvssError(f"not a CVSS:4.0 vector: {vector!r}")
    body = vector[len("CVSS:4.0/") :]
    if body == "" or body.endswith("/"):
        raise CvssError(f"empty or trailing segment: {vector!r}")
    segments = body.split("/")

    seen: dict = {}
    last_index = -1
    for seg in segments:
        if seg == "" or ":" not in seg:
            raise CvssError(f"malformed segment {seg!r} in {vector!r}")
        key, _, value = seg.partition(":")
        if key not in METRIC_ORDER:
            raise CvssError(f"unknown metric {key!r} in {vector!r}")
        if key in seen:
            raise CvssError(f"duplicate metric {key!r} in {vector!r}")
        if value not in METRIC_VALUES[key]:
            raise CvssError(f"invalid value {value!r} for metric {key!r} in {vector!r}")
        index = METRIC_ORDER.index(key)
        if index < last_index:
            raise CvssError(f"metric {key!r} out of order in {vector!r}")
        last_index = index
        seen[key] = value

    missing = [m for m in BASE_METRICS if m not in seen]
    if missing:
        raise CvssError(f"missing base metric(s) {missing} in {vector!r}")

    selected = {m: "X" for m in METRIC_ORDER}
    selected.update(seen)
    return selected


# --- FIRST's algorithm, ported line by line from cvss_score.js -------------------------------------------------


def _m(cvss_selected: dict, metric: str) -> str:
    selected = cvss_selected[metric]
    if metric == "E" and selected == "X":
        return "A"
    if metric == "CR" and selected == "X":
        return "H"
    if metric == "IR" and selected == "X":
        return "H"
    if metric == "AR" and selected == "X":
        return "H"
    modified_key = "M" + metric
    if modified_key in cvss_selected:
        modified_selected = cvss_selected[modified_key]
        if modified_selected != "X":
            return modified_selected
    return selected


def macro_vector(cvss_selected: dict) -> str:
    """The six-digit EQ1..EQ6 macro-vector, per FIRST's macroVector()."""
    av, pr, ui = _m(cvss_selected, "AV"), _m(cvss_selected, "PR"), _m(cvss_selected, "UI")
    if av == "N" and pr == "N" and ui == "N":
        eq1 = "0"
    elif (av == "N" or pr == "N" or ui == "N") and not (av == "N" and pr == "N" and ui == "N") and av != "P":
        eq1 = "1"
    else:
        eq1 = "2"

    ac, at = _m(cvss_selected, "AC"), _m(cvss_selected, "AT")
    eq2 = "0" if (ac == "L" and at == "N") else "1"

    vc, vi, va = _m(cvss_selected, "VC"), _m(cvss_selected, "VI"), _m(cvss_selected, "VA")
    if vc == "H" and vi == "H":
        eq3 = "0"
    elif not (vc == "H" and vi == "H") and (vc == "H" or vi == "H" or va == "H"):
        eq3 = "1"
    else:
        eq3 = "2"

    sc, si, sa = _m(cvss_selected, "SC"), _m(cvss_selected, "SI"), _m(cvss_selected, "SA")
    msi, msa = _m(cvss_selected, "MSI"), _m(cvss_selected, "MSA")
    if msi == "S" or msa == "S":
        eq4 = "0"
    elif not (msi == "S" or msa == "S") and (sc == "H" or si == "H" or sa == "H"):
        eq4 = "1"
    else:
        eq4 = "2"

    e = _m(cvss_selected, "E")
    eq5 = {"A": "0", "P": "1", "U": "2"}[e]

    cr, ir, ar = _m(cvss_selected, "CR"), _m(cvss_selected, "IR"), _m(cvss_selected, "AR")
    if (cr == "H" and vc == "H") or (ir == "H" and vi == "H") or (ar == "H" and va == "H"):
        eq6 = "0"
    else:
        eq6 = "1"

    return eq1 + eq2 + eq3 + eq4 + eq5 + eq6


def _get_eq_maxes(macro_vector_result: str, eq: int):
    return MAX_COMPOSED[f"eq{eq}"][macro_vector_result[eq - 1]]


def extract_value_metric(metric: str, s: str) -> str:
    i = s.index(metric)
    extracted = s[i + len(metric) + 1 :]
    slash = extracted.find("/")
    if slash > 0:
        return extracted[:slash]
    return extracted


_LEVELS = {
    "AV": {"N": 0.0, "A": 0.1, "L": 0.2, "P": 0.3},
    "PR": {"N": 0.0, "L": 0.1, "H": 0.2},
    "UI": {"N": 0.0, "P": 0.1, "A": 0.2},
    "AC": {"L": 0.0, "H": 0.1},
    "AT": {"N": 0.0, "P": 0.1},
    "VC": {"H": 0.0, "L": 0.1, "N": 0.2},
    "VI": {"H": 0.0, "L": 0.1, "N": 0.2},
    "VA": {"H": 0.0, "L": 0.1, "N": 0.2},
    "SC": {"H": 0.1, "L": 0.2, "N": 0.3},
    "SI": {"S": 0.0, "H": 0.1, "L": 0.2, "N": 0.3},
    "SA": {"S": 0.0, "H": 0.1, "L": 0.2, "N": 0.3},
    "CR": {"H": 0.0, "M": 0.1, "L": 0.2},
    "IR": {"H": 0.0, "M": 0.1, "L": 0.2},
    "AR": {"H": 0.0, "M": 0.1, "L": 0.2},
}

_DISTANCE_METRICS = ("AV", "PR", "UI", "AC", "AT", "VC", "VI", "VA", "SC", "SI", "SA", "CR", "IR", "AR")


def _js_round1(value: float) -> float:
    # JavaScript's Math.round(value * 10) / 10 — round-half-up, never Python's round() (banker's rounding).
    return math.floor(value * 10 + 0.5) / 10


def score(vector: str) -> float:
    """FIRST's cvss_score(): the base score, 0.0-10.0, rounded to one decimal place with JS rounding."""
    selected = parse(vector)

    # Exception for no impact on system (shortcut).
    if all(_m(selected, metric) == "N" for metric in ("VC", "VI", "VA", "SC", "SI", "SA")):
        return 0.0

    mv = macro_vector(selected)
    value = LOOKUP[mv]

    eq = [int(c) for c in mv]
    eq1, eq2, eq3, eq4, eq5, eq6 = eq

    eq1_next_lower = f"{eq1 + 1}{eq2}{eq3}{eq4}{eq5}{eq6}"
    eq2_next_lower = f"{eq1}{eq2 + 1}{eq3}{eq4}{eq5}{eq6}"

    if eq3 == 1 and eq6 == 1:
        eq3eq6_next_lower = [f"{eq1}{eq2}{eq3 + 1}{eq4}{eq5}{eq6}"]
    elif eq3 == 0 and eq6 == 1:
        eq3eq6_next_lower = [f"{eq1}{eq2}{eq3 + 1}{eq4}{eq5}{eq6}"]
    elif eq3 == 1 and eq6 == 0:
        eq3eq6_next_lower = [f"{eq1}{eq2}{eq3}{eq4}{eq5}{eq6 + 1}"]
    elif eq3 == 0 and eq6 == 0:
        eq3eq6_next_lower = [f"{eq1}{eq2}{eq3}{eq4}{eq5}{eq6 + 1}", f"{eq1}{eq2}{eq3 + 1}{eq4}{eq5}{eq6}"]
    else:
        eq3eq6_next_lower = [f"{eq1}{eq2}{eq3 + 1}{eq4}{eq5}{eq6 + 1}"]

    eq4_next_lower = f"{eq1}{eq2}{eq3}{eq4 + 1}{eq5}{eq6}"
    eq5_next_lower = f"{eq1}{eq2}{eq3}{eq4}{eq5 + 1}{eq6}"

    score_eq1_next_lower = LOOKUP.get(eq1_next_lower)
    score_eq2_next_lower = LOOKUP.get(eq2_next_lower)
    if len(eq3eq6_next_lower) == 2:
        left = LOOKUP.get(eq3eq6_next_lower[0])
        right = LOOKUP.get(eq3eq6_next_lower[1])
        if left is None and right is None:
            score_eq3eq6_next_lower = None
        elif left is None:
            score_eq3eq6_next_lower = right
        elif right is None:
            score_eq3eq6_next_lower = left
        else:
            score_eq3eq6_next_lower = left if left > right else right
    else:
        score_eq3eq6_next_lower = LOOKUP.get(eq3eq6_next_lower[0])
    score_eq4_next_lower = LOOKUP.get(eq4_next_lower)
    score_eq5_next_lower = LOOKUP.get(eq5_next_lower)

    eq1_maxes = _get_eq_maxes(mv, 1)
    eq2_maxes = _get_eq_maxes(mv, 2)
    eq3_eq6_maxes = _get_eq_maxes(mv, 3)[mv[5]]
    eq4_maxes = _get_eq_maxes(mv, 4)
    eq5_maxes = _get_eq_maxes(mv, 5)

    max_vectors = [
        eq1_max + eq2_max + eq3_eq6_max + eq4_max + eq5_max
        for eq1_max in eq1_maxes
        for eq2_max in eq2_maxes
        for eq3_eq6_max in eq3_eq6_maxes
        for eq4_max in eq4_maxes
        for eq5_max in eq5_maxes
    ]

    distances = {}
    for max_vector in max_vectors:
        candidate = {}
        ok = True
        for metric in _DISTANCE_METRICS:
            levels = _LEVELS[metric]
            d = levels[_m(selected, metric)] - levels[extract_value_metric(metric, max_vector)]
            candidate[metric] = d
            if d < 0:
                ok = False
        if ok:
            distances = candidate
            break
        distances = candidate  # FIRST keeps the last candidate even if every one fails (should not happen)

    current_eq1 = distances["AV"] + distances["PR"] + distances["UI"]
    current_eq2 = distances["AC"] + distances["AT"]
    current_eq3eq6 = (
        distances["VC"] + distances["VI"] + distances["VA"] + distances["CR"] + distances["IR"] + distances["AR"]
    )
    current_eq4 = distances["SC"] + distances["SI"] + distances["SA"]
    current_eq5 = 0.0

    step = 0.1
    max_sev_eq1 = MAX_SEVERITY["eq1"][str(eq1)] * step
    max_sev_eq2 = MAX_SEVERITY["eq2"][str(eq2)] * step
    max_sev_eq3eq6 = MAX_SEVERITY["eq3eq6"][str(eq3)][str(eq6)] * step
    max_sev_eq4 = MAX_SEVERITY["eq4"][str(eq4)] * step

    n_existing_lower = 0
    normalized = 0.0

    if score_eq1_next_lower is not None:
        n_existing_lower += 1
        available = value - score_eq1_next_lower
        normalized += available * (current_eq1 / max_sev_eq1)
    if score_eq2_next_lower is not None:
        n_existing_lower += 1
        available = value - score_eq2_next_lower
        normalized += available * (current_eq2 / max_sev_eq2)
    if score_eq3eq6_next_lower is not None:
        n_existing_lower += 1
        available = value - score_eq3eq6_next_lower
        normalized += available * (current_eq3eq6 / max_sev_eq3eq6)
    if score_eq4_next_lower is not None:
        n_existing_lower += 1
        available = value - score_eq4_next_lower
        normalized += available * (current_eq4 / max_sev_eq4)
    if score_eq5_next_lower is not None:
        n_existing_lower += 1
        available = value - score_eq5_next_lower
        normalized += available * 0.0  # percent_to_next_eq5_severity is always 0

    mean_distance = 0.0 if n_existing_lower == 0 else normalized / n_existing_lower

    value -= mean_distance
    if value < 0:
        value = 0.0
    if value > 10:
        value = 10.0
    return _js_round1(value)


# --- severity bands (RUBRIC.md) -----------------------------------------------------------------------------------


def severity(s: float) -> str:
    """The CVSS v4.0 base score's severity band (RUBRIC.md's table)."""
    if s == 0.0:
        return "none"
    if s <= 3.9:
        return "low"
    if s <= 6.9:
        return "medium"
    if s <= 8.9:
        return "high"
    return "critical"


def band(vector: str) -> str:
    return severity(score(vector))


def base_only(vector: str) -> str:
    """`vector`, unchanged, when it is a valid vector carrying exactly the eleven base metrics; else CvssError.

    A finding's severity is the CVSS v4.0 BASE score (constitution `art-threat-driven-security`, docs/security/RUBRIC.md).
    score() also takes the optional metrics, which FIRST's conformance vectors exercise, but a Threat (E), Environmental
    (CR, IR, AR, M*) or Supplemental (S, AU, R, V, RE, U) metric can move the score below the base score (MVC:N/MVI:N/MVA:N
    turns a 9.3 into 0.0), so a finding's `cvss_vector` carrying any of them — even with value X — is refused.
    """
    parse(vector)  # malformed vectors raise first
    for seg in vector[len("CVSS:4.0/") :].split("/"):
        key = seg.partition(":")[0]
        if key not in BASE_METRICS:
            group = _GROUP.get(key, "optional")
            raise CvssError(
                f"{group} metric {key!r} in a finding's cvss_vector: severity is the CVSS v4.0 base score "
                f"(art-threat-driven-security, docs/security/RUBRIC.md), so the vector carries the eleven base "
                f"metrics {'/'.join(BASE_METRICS)} and nothing else: {vector!r}"
            )
    return vector


_GROUP = {"E": "Threat"}
_GROUP.update({m: "Environmental" for m in METRIC_ORDER[12:26]})
_GROUP.update({m: "Supplemental" for m in METRIC_ORDER[26:]})


def finding_severity(vector: str) -> str:
    """A finding's severity: band(vector) of a base-only vector (base_only; any other metric is CvssError), with
    "none" read as "low" (R20: an informational finding with no impact is recorded as low)."""
    b = band(base_only(vector))
    return "low" if b == "none" else b
