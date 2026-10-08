"""scripts/lib/specflow/disposition.py — the security-disposition decision kernel (REQ-322, ADR-002).

The Python twin of verification/factory_v3_2/disposition.dfy: one function per model predicate or function, named
as the model's in snake_case, over the pure inputs in records.py. Pure: no I/O, no imports beyond records, cvss4
and the stdlib (dataclasses, datetime, enum, typing) — this module is itself imported by scripts that do I/O, never
the other way around.

decide() is REQ-322's gate function: PASS iff all five ADR-002 rules hold over the review findings, the disposition
entries and the latest prior entry per id. decide(...).passed == all_rules_hold(...) for every input satisfying
pre(...) (the model's theorem 1); a precondition violation raises ValueError, never a FAIL verdict — the caller
(scripts/lib/specflow/disposition_gate.py, a later task) maps that to exit 2, distinct from exit 1 (a FAIL).
"""

from __future__ import annotations

from datetime import timedelta

import cvss4
from records import (
    Entry,
    Finding,
    PriorEntry,
    Rule,
    Severity,
    Status,
    Verdict,
    Violation,
)

RANK = {Severity.CRITICAL: 3, Severity.HIGH: 2, Severity.MEDIUM: 1, Severity.LOW: 0}


def _rank(s: Severity) -> int:
    return RANK[s]


def _at_least_medium(s: Severity) -> bool:
    return _rank(s) >= 1


def _severe(s: Severity) -> bool:
    return _rank(s) >= 2


def _accepted_or_deferred(status: Status) -> bool:
    return status in (Status.ACCEPTED, Status.DEFERRED)


def _ids_r(review: list[Finding]) -> set[str]:
    return {f.id for f in review}


def _ids_d(disposition: list[Entry]) -> set[str]:
    return {e.id for e in disposition}


# ---- Helpers (the model's SevIs, JoinedSevere, ... in snake_case) -------------------------------------------


def sev_is(review: list[Finding], id: str, severity: Severity) -> bool:
    return any(f.id == id and f.severity == severity for f in review)


def joined_severe(review: list[Finding], id: str) -> bool:
    return any(f.id == id and _severe(f.severity) for f in review)


def joined_at_least_medium(review: list[Finding], id: str) -> bool:
    return any(f.id == id and _at_least_medium(f.severity) for f in review)


def ranked_below(review: list[Finding], p: PriorEntry) -> bool:
    return any(f.id == p.id and _rank(f.severity) < _rank(p.severity) for f in review)


def due(p: PriorEntry) -> bool:
    return (
        p.status == Status.OPEN or _accepted_or_deferred(p.status)
    ) and _at_least_medium(p.severity)


def lapsed(p: PriorEntry, run_date) -> bool:
    # An accepted/deferred prior with no expiry is treated as lapsed (fail closed), never a TypeError.
    return _accepted_or_deferred(p.status) and (
        p.expiry is None or p.expiry <= run_date
    )


def reclass_ok(e: Entry) -> bool:
    return (
        e.reclassified_by is not None
        and len(e.reclassified_by) > 0
        and e.reclassified_by != e.owner
        and len(e.rationale) > 0
    )


def entry_carries(review: list[Finding], e: Entry, p: PriorEntry, run_date) -> bool:
    if e.id != p.id:
        return False
    if _severe(p.severity) and e.status != Status.FIXED:
        return False
    if lapsed(p, run_date) and not (
        e.status == Status.FIXED
        or (
            _accepted_or_deferred(e.status)
            and e.expiry is not None
            and e.expiry > run_date
        )
    ):
        return False
    if ranked_below(review, p) and not reclass_ok(e):
        return False
    return True


def carried_ok(
    review: list[Finding], disposition: list[Entry], p: PriorEntry, run_date
) -> bool:
    return any(entry_carries(review, e, p, run_date) for e in disposition)


def in_window(e: Entry, run_date, horizon: int) -> bool:
    return e.expiry is not None and run_date < e.expiry <= run_date + timedelta(
        days=horizon
    )


def mediums_ad(review: list[Finding], disposition: list[Entry]) -> set[str]:
    return {
        e.id
        for e in disposition
        if _accepted_or_deferred(e.status) and sev_is(review, e.id, Severity.MEDIUM)
    }


# ---- The rules (ADR-002 "Rules", 1-5) ---------------------------------------------------------------------


def rule1_set_equality(review: list[Finding], disposition: list[Entry]) -> bool:
    return _ids_r(review) == _ids_d(disposition)


def rule2_severe_fixed(review: list[Finding], disposition: list[Entry]) -> bool:
    return all(
        e.status == Status.FIXED for e in disposition if joined_severe(review, e.id)
    )


def rule3_medium_cap(review: list[Finding], disposition: list[Entry], cap: int) -> bool:
    return len(mediums_ad(review, disposition)) <= cap


def rule4_carry_forward(
    review: list[Finding], disposition: list[Entry], prior: list[PriorEntry], run_date
) -> bool:
    return all(carried_ok(review, disposition, p, run_date) for p in prior if due(p))


def rule5_expiry_window(
    review: list[Finding], disposition: list[Entry], run_date, horizon: int
) -> bool:
    return all(
        in_window(e, run_date, horizon)
        for e in disposition
        if _accepted_or_deferred(e.status) and joined_at_least_medium(review, e.id)
    )


def all_rules_hold(
    review: list[Finding],
    disposition: list[Entry],
    prior: list[PriorEntry],
    cap: int,
    horizon: int,
    run_date,
) -> bool:
    return (
        rule1_set_equality(review, disposition)
        and rule2_severe_fixed(review, disposition)
        and rule3_medium_cap(review, disposition, cap)
        and rule4_carry_forward(review, disposition, prior, run_date)
        and rule5_expiry_window(review, disposition, run_date, horizon)
    )


# ---- The precondition (pre) -------------------------------------------------------------------------------


def _unique_ids(items) -> bool:
    ids = [x.id for x in items]
    return len(ids) == len(set(ids))


def pre(
    review: list[Finding], disposition: list[Entry], prior: list[PriorEntry]
) -> bool:
    if not _unique_ids(review):
        return False
    if not _unique_ids(disposition):
        return False
    if not _unique_ids(prior):
        return False
    for e in disposition:
        if _accepted_or_deferred(e.status) and joined_at_least_medium(review, e.id):
            if e.owner == "" or e.expiry is None:
                return False
    return True


# ---- Violations and the decision --------------------------------------------------------------------------


def v1(review: list[Finding], disposition: list[Entry]) -> set[Violation]:
    r, d = _ids_r(review), _ids_d(disposition)
    return {Violation(id, Rule.SET_EQUALITY) for id in (r - d) | (d - r)}


def v2(review: list[Finding], disposition: list[Entry]) -> set[Violation]:
    return {
        Violation(e.id, Rule.SEVERE_NOT_FIXED)
        for e in disposition
        if joined_severe(review, e.id) and e.status != Status.FIXED
    }


def v3(review: list[Finding], disposition: list[Entry], cap: int) -> set[Violation]:
    m = mediums_ad(review, disposition)
    if len(m) > cap:
        return {Violation(id, Rule.MEDIUM_CAP) for id in m}
    return set()


def v4(
    review: list[Finding], disposition: list[Entry], prior: list[PriorEntry], run_date
) -> set[Violation]:
    return {
        Violation(p.id, Rule.CARRY_FORWARD)
        for p in prior
        if due(p) and not carried_ok(review, disposition, p, run_date)
    }


def v5(
    review: list[Finding], disposition: list[Entry], run_date, horizon: int
) -> set[Violation]:
    return {
        Violation(e.id, Rule.EXPIRY_WINDOW)
        for e in disposition
        if _accepted_or_deferred(e.status)
        and joined_at_least_medium(review, e.id)
        and not in_window(e, run_date, horizon)
    }


def violations_2to5(
    review: list[Finding],
    disposition: list[Entry],
    prior: list[PriorEntry],
    cap: int,
    horizon: int,
    run_date,
) -> set[Violation]:
    return (
        v2(review, disposition)
        | v3(review, disposition, cap)
        | v4(review, disposition, prior, run_date)
        | v5(review, disposition, run_date, horizon)
    )


def violations(
    review: list[Finding],
    disposition: list[Entry],
    prior: list[PriorEntry],
    cap: int,
    horizon: int,
    run_date,
) -> set[Violation]:
    return v1(review, disposition) | violations_2to5(
        review, disposition, prior, cap, horizon, run_date
    )


def decide(
    review: list[Finding],
    disposition: list[Entry],
    prior: list[PriorEntry],
    medium_cap: int,
    expiry_horizon_days: int,
    run_date,
) -> Verdict:
    """PASS iff rules 1-5 hold; raises ValueError on a precondition violation (R9, ADR-002's pre)."""
    if not _unique_ids(review):
        raise ValueError("duplicate id in review")
    if not _unique_ids(disposition):
        raise ValueError("duplicate id in disposition")
    if not _unique_ids(prior):
        raise ValueError("duplicate id in prior")
    for (
        f
    ) in (
        review
    ):  # R9: the runtime re-check that severity matches the band cvss4 derives from the vector — base metrics only
        try:
            band = cvss4.finding_severity(f.cvss_vector)
        except cvss4.CvssError as e:
            raise ValueError(f"{f.id}: cvss_vector: {e}") from e
        if band != f.severity.value:
            raise ValueError(
                f"{f.id}: severity {f.severity.value} but cvss_vector scores {band}"
            )
    if medium_cap < 0:
        raise ValueError("medium_cap < 0")
    if expiry_horizon_days < 0:
        raise ValueError("expiry_horizon_days < 0")
    if not pre(review, disposition, prior):
        raise ValueError(
            "an accepted/deferred entry joined to a medium-or-above finding needs an owner and an expiry"
        )

    v = violations(
        review, disposition, prior, medium_cap, expiry_horizon_days, run_date
    )
    return Verdict(
        passed=len(v) == 0,
        violations=tuple(sorted(v, key=lambda x: (x.id, x.rule.value))),
    )
