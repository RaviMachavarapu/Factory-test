// verification/factory_v3_2/disposition.dfy — ADR-002's security-disposition decision as a pure function.
// Proves: REQ-322
// Twin: scripts/lib/specflow/disposition.py (decide); fixtures: tests/governance/fixtures/disposition/.
//
// REQ-322 (ADR-002), restated. The release of a version may proceed (Pass) iff all five rules hold:
//   1. Set equality: the review's finding ids equal the disposition's entry ids.
//   2. Critical and high are fixed: every entry joined (by id) to a critical or high finding is Fixed.
//   3. Medium cap: the entries joined to a medium finding with status Accepted or Deferred number at most the cap
//      (per release; rule 4 forces still-accepted prior mediums to be re-listed and so counted).
//   4. Carry-forward: every latest prior entry that is due (status Open, Accepted or Deferred, severity medium or
//      above) appears in the current disposition; a prior critical/high is now Fixed; a prior Accepted/Deferred
//      whose expiry is on or before the run date is now Fixed or re-accepted/re-deferred with an expiry after it;
//      and a finding re-listed at a lower severity than its prior entry carries reclassified_by (a second reviewer,
//      not the owner) and a rationale.
//   5. Expiry window: every Accepted/Deferred entry joined to a medium-or-above finding has
//      run date < expiry <= run date + expiry horizon.
// Otherwise Fail names each violating (id, rule). Lows never affect rules 2-5; zero findings with no due
// carry-forward pass; the verdict is independent of input order.
//
// Modelling choices. Severity is the review's, derived from the CVSS vector outside the model (the parser, and
// decide()'s runtime re-check, R9); entries carry none and are joined to the review by id. Dates are day
// ordinals (int), as date.toordinal() in the twin. Every rule reads its inputs only through sequence membership,
// so the order of the sequences cannot matter. Pre is the twin's precondition (decide() raises ValueError outside
// it); the theorems range over it, although their proofs do not need it.
// Three layers (verification/README.md): this proof; decide()'s precondition checks; the fixtures that mirror it.
// Beside the theorems: boundary lemmas pin each shared helper (InWindow, Due, Lapsed, EntryCarries, MediumsAD) to
// the ADR-002 clause it encodes, since the theorems cannot see a wrong helper; FixtureNN lemmas state the model's
// verdict on the Python boundary fixtures of the same number (13, 19, 20, 24, 25, 33, 34).

module SecurityDisposition {

  datatype Severity = Critical | High | Medium | Low
  datatype Status = Open | Fixed | Accepted | Deferred
  datatype Rule = SetEquality | SevereNotFixed | MediumCap | CarryForward | ExpiryWindow
  datatype Option<T> = None | Some(value: T)

  datatype Finding = Finding(id: string, severity: Severity)
  datatype Entry = Entry(id: string, status: Status, owner: string, expiry: Option<int>, rationale: string,
                         reclassifiedBy: Option<string>)
  datatype PriorEntry = PriorEntry(id: string, severity: Severity, status: Status, expiry: Option<int>)
  datatype Violation = Violation(id: string, rule: Rule)
  datatype Verdict = Pass | Fail(violations: set<Violation>)

  // ---- Helpers --------------------------------------------------------------------------------------------

  function Rank(s: Severity): nat {
    match s
    case Critical => 3
    case High => 2
    case Medium => 1
    case Low => 0
  }
  predicate AtLeastMedium(s: Severity) { Rank(s) >= 1 }
  predicate Severe(s: Severity) { Rank(s) >= 2 }
  predicate AcceptedOrDeferred(st: Status) { st == Accepted || st == Deferred }

  function IdsR(review: seq<Finding>): set<string> { set f | f in review :: f.id }
  function IdsD(disposition: seq<Entry>): set<string> { set e | e in disposition :: e.id }

  // The join: the review finding with this id has a severity satisfying the test. Under Pre (unique ids) there is
  // at most one such finding, so this is the twin's sev_of(review, id).
  predicate SevIs(review: seq<Finding>, id: string, s: Severity) {
    exists f :: f in review && f.id == id && f.severity == s
  }
  predicate JoinedSevere(review: seq<Finding>, id: string) {
    exists f :: f in review && f.id == id && Severe(f.severity)
  }
  predicate JoinedAtLeastMedium(review: seq<Finding>, id: string) {
    exists f :: f in review && f.id == id && AtLeastMedium(f.severity)
  }
  predicate RankedBelow(review: seq<Finding>, p: PriorEntry) {
    exists f :: f in review && f.id == p.id && Rank(f.severity) < Rank(p.severity)
  }

  // A latest prior entry is due for carry-forward (rule 4's trigger).
  predicate Due(p: PriorEntry) {
    (p.status == Open || AcceptedOrDeferred(p.status)) && AtLeastMedium(p.severity)
  }
  // A prior acceptance/deferral has lapsed by the run date. A missing expiry is treated as lapsed (fail closed).
  predicate Lapsed(p: PriorEntry, today: int) {
    AcceptedOrDeferred(p.status) && (p.expiry.None? || p.expiry.value <= today)
  }
  // The constitution's downgrade path: a second reviewer other than the owner, and a rationale.
  predicate ReclassOk(e: Entry) {
    e.reclassifiedBy.Some? && |e.reclassifiedBy.value| > 0 && e.reclassifiedBy.value != e.owner
    && |e.rationale| > 0
  }
  predicate EntryCarries(review: seq<Finding>, e: Entry, p: PriorEntry, today: int) {
    e.id == p.id
    && (Severe(p.severity) ==> e.status == Fixed)
    && (Lapsed(p, today) ==>
          e.status == Fixed || (AcceptedOrDeferred(e.status) && e.expiry.Some? && e.expiry.value > today))
    && (RankedBelow(review, p) ==> ReclassOk(e))
  }
  predicate CarriedOk(review: seq<Finding>, disposition: seq<Entry>, p: PriorEntry, today: int) {
    exists e :: e in disposition && EntryCarries(review, e, p, today)
  }
  predicate InWindow(e: Entry, today: int, horizon: nat) {
    e.expiry.Some? && today < e.expiry.value <= today + horizon
  }
  function MediumsAD(review: seq<Finding>, disposition: seq<Entry>): set<string> {
    set e | e in disposition && AcceptedOrDeferred(e.status) && SevIs(review, e.id, Medium) :: e.id
  }

  // ---- The rules (ADR-002 "Rules", 1-5) -------------------------------------------------------------------

  // Rule 1: set equality.
  predicate Rule1SetEquality(review: seq<Finding>, disposition: seq<Entry>) {
    IdsR(review) == IdsD(disposition)
  }
  // Rule 2: critical and high are fixed.
  predicate Rule2SevereFixed(review: seq<Finding>, disposition: seq<Entry>) {
    forall e :: e in disposition && JoinedSevere(review, e.id) ==> e.status == Fixed
  }
  // Rule 3: accepted/deferred mediums within the per-release cap.
  predicate Rule3MediumCap(review: seq<Finding>, disposition: seq<Entry>, cap: nat) {
    |MediumsAD(review, disposition)| <= cap
  }
  // Rule 4: every due latest prior entry is carried forward correctly.
  predicate Rule4CarryForward(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>, today: int) {
    forall p :: p in prior && Due(p) ==> CarriedOk(review, disposition, p, today)
  }
  // Rule 5: accepted/deferred medium-or-above entries expire inside (today, today + horizon].
  predicate Rule5ExpiryWindow(review: seq<Finding>, disposition: seq<Entry>, today: int, horizon: nat) {
    forall e :: e in disposition && AcceptedOrDeferred(e.status) && JoinedAtLeastMedium(review, e.id)
      ==> InWindow(e, today, horizon)
  }
  predicate AllRulesHold(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>,
                         cap: nat, horizon: nat, today: int) {
    Rule1SetEquality(review, disposition) && Rule2SevereFixed(review, disposition)
    && Rule3MediumCap(review, disposition, cap) && Rule4CarryForward(review, disposition, prior, today)
    && Rule5ExpiryWindow(review, disposition, today, horizon)
  }

  // The precondition (parser errors, exit 2, never Fail): unique ids within each input; an owner and an expiry on
  // every accepted/deferred entry joined to a medium-or-above finding (lows need neither). cap and horizon are nat.
  predicate UniqueFindingIds(s: seq<Finding>) { forall i, j :: 0 <= i < j < |s| ==> s[i].id != s[j].id }
  predicate UniqueEntryIds(s: seq<Entry>) { forall i, j :: 0 <= i < j < |s| ==> s[i].id != s[j].id }
  predicate UniquePriorIds(s: seq<PriorEntry>) { forall i, j :: 0 <= i < j < |s| ==> s[i].id != s[j].id }
  predicate Pre(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>) {
    UniqueFindingIds(review) && UniqueEntryIds(disposition) && UniquePriorIds(prior)
    && (forall e :: e in disposition && AcceptedOrDeferred(e.status) && JoinedAtLeastMedium(review, e.id)
          ==> e.owner != "" && e.expiry.Some?)
  }

  // ---- Violations and the decision ------------------------------------------------------------------------

  function V1(review: seq<Finding>, disposition: seq<Entry>): set<Violation> {
    set id | id in (IdsR(review) - IdsD(disposition)) + (IdsD(disposition) - IdsR(review))
      :: Violation(id, SetEquality)
  }
  function V2(review: seq<Finding>, disposition: seq<Entry>): set<Violation> {
    set e | e in disposition && JoinedSevere(review, e.id) && e.status != Fixed :: Violation(e.id, SevereNotFixed)
  }
  // Over the cap, every accepted/deferred medium is named.
  function V3(review: seq<Finding>, disposition: seq<Entry>, cap: nat): set<Violation> {
    var m := MediumsAD(review, disposition);
    if |m| > cap then (set id | id in m :: Violation(id, MediumCap)) else {}
  }
  function V4(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>, today: int): set<Violation> {
    set p | p in prior && Due(p) && !CarriedOk(review, disposition, p, today) :: Violation(p.id, CarryForward)
  }
  function V5(review: seq<Finding>, disposition: seq<Entry>, today: int, horizon: nat): set<Violation> {
    set e | e in disposition && AcceptedOrDeferred(e.status) && JoinedAtLeastMedium(review, e.id)
              && !InWindow(e, today, horizon) :: Violation(e.id, ExpiryWindow)
  }
  function Violations2to5(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>,
                          cap: nat, horizon: nat, today: int): set<Violation> {
    V2(review, disposition) + V3(review, disposition, cap) + V4(review, disposition, prior, today)
    + V5(review, disposition, today, horizon)
  }
  function Violations(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>,
                      cap: nat, horizon: nat, today: int): set<Violation> {
    V1(review, disposition) + Violations2to5(review, disposition, prior, cap, horizon, today)
  }
  function Decide(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>,
                  cap: nat, horizon: nat, today: int): Verdict {
    var v := Violations(review, disposition, prior, cap, horizon, today);
    if v == {} then Pass else Fail(v)
  }

  // ---- Theorems -------------------------------------------------------------------------------------------

  // Each rule holds exactly when its violation set is empty (used by theorem 1).
  lemma RuleIffNoViolations(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>,
                            cap: nat, horizon: nat, today: int)
    ensures Rule1SetEquality(review, disposition) <==> V1(review, disposition) == {}
    ensures Rule2SevereFixed(review, disposition) <==> V2(review, disposition) == {}
    ensures Rule3MediumCap(review, disposition, cap) <==> V3(review, disposition, cap) == {}
    ensures Rule4CarryForward(review, disposition, prior, today) <==> V4(review, disposition, prior, today) == {}
    ensures Rule5ExpiryWindow(review, disposition, today, horizon) <==> V5(review, disposition, today, horizon) == {}
  {
    var r, d := IdsR(review), IdsD(disposition);
    if r != d {
      var id :| id in (r - d) + (d - r);
      assert Violation(id, SetEquality) in V1(review, disposition);
    }
    if !Rule2SevereFixed(review, disposition) {
      var e :| e in disposition && JoinedSevere(review, e.id) && e.status != Fixed;
      assert Violation(e.id, SevereNotFixed) in V2(review, disposition);
    }
    var m := MediumsAD(review, disposition);
    if |m| > cap {
      var id :| id in m;
      assert Violation(id, MediumCap) in V3(review, disposition, cap);
    }
    if !Rule4CarryForward(review, disposition, prior, today) {
      var p :| p in prior && Due(p) && !CarriedOk(review, disposition, p, today);
      assert Violation(p.id, CarryForward) in V4(review, disposition, prior, today);
    }
    if !Rule5ExpiryWindow(review, disposition, today, horizon) {
      var e :| e in disposition && AcceptedOrDeferred(e.status) && JoinedAtLeastMedium(review, e.id)
                 && !InWindow(e, today, horizon);
      assert Violation(e.id, ExpiryWindow) in V5(review, disposition, today, horizon);
    }
  }

  // Theorem 1 (ADR-002 Consequences): Decide == Pass <==> AllRulesHold.
  lemma DecidePassIffAllRulesHold(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>,
                                  cap: nat, horizon: nat, today: int)
    requires Pre(review, disposition, prior)
    ensures Decide(review, disposition, prior, cap, horizon, today) == Pass
            <==> AllRulesHold(review, disposition, prior, cap, horizon, today)
  {
    RuleIffNoViolations(review, disposition, prior, cap, horizon, today);
  }

  // Theorem 2: permutation invariance. Inputs are sequences (the twin takes Python sequences); two orderings of
  // the same elements are sequences with equal multisets, and Decide returns the same verdict for both.
  lemma DecidePermutationInvariant(r1: seq<Finding>, d1: seq<Entry>, p1: seq<PriorEntry>,
                                   r2: seq<Finding>, d2: seq<Entry>, p2: seq<PriorEntry>,
                                   cap: nat, horizon: nat, today: int)
    requires Pre(r1, d1, p1)
    requires multiset(r1) == multiset(r2) && multiset(d1) == multiset(d2) && multiset(p1) == multiset(p2)
    ensures Decide(r1, d1, p1, cap, horizon, today) == Decide(r2, d2, p2, cap, horizon, today)
  {
    // Equal multisets have equal members, and every rule reads its inputs only through membership.
    assert forall x :: x in r1 <==> x in multiset(r1);
    assert forall x :: x in r2 <==> x in multiset(r2);
    assert forall x :: x in d1 <==> x in multiset(d1);
    assert forall x :: x in d2 <==> x in multiset(d2);
    assert forall x :: x in p1 <==> x in multiset(p1);
    assert forall x :: x in p2 <==> x in multiset(p2);
    assert MediumsAD(r1, d1) == MediumsAD(r2, d2);
    assert forall p :: CarriedOk(r1, d1, p, today) <==> CarriedOk(r2, d2, p, today);
    assert V1(r1, d1) == V1(r2, d2) && V2(r1, d1) == V2(r2, d2) && V3(r1, d1, cap) == V3(r2, d2, cap);
    assert V4(r1, d1, p1, today) == V4(r2, d2, p2, today) && V5(r1, d1, today, horizon) == V5(r2, d2, today, horizon);
  }

  // Theorem 3 (R10): lows do not influence rules 2-5. Adding a Low finding f and its entry e, with an id new to
  // both files and no due prior entry under it, leaves each of rules 2-5 and their violations unchanged; read
  // right to left, removing such a pair does too. (A due prior medium re-listed as Low is rule 4's downgrade,
  // which is why the fresh-id and not-due conditions are part of the statement.)
  lemma LowsInertForRules2to5(review: seq<Finding>, disposition: seq<Entry>, prior: seq<PriorEntry>,
                              cap: nat, horizon: nat, today: int, f: Finding, e: Entry)
    requires Pre(review, disposition, prior) && Pre(review + [f], disposition + [e], prior)
    requires f.severity == Low && e.id == f.id
    requires f.id !in IdsR(review) && f.id !in IdsD(disposition)
    requires forall p :: p in prior && Due(p) ==> p.id != f.id
    ensures V2(review + [f], disposition + [e]) == V2(review, disposition)
    ensures V3(review + [f], disposition + [e], cap) == V3(review, disposition, cap)
    ensures V4(review + [f], disposition + [e], prior, today) == V4(review, disposition, prior, today)
    ensures V5(review + [f], disposition + [e], today, horizon) == V5(review, disposition, today, horizon)
    ensures Violations2to5(review + [f], disposition + [e], prior, cap, horizon, today)
            == Violations2to5(review, disposition, prior, cap, horizon, today)
    ensures Rule2SevereFixed(review + [f], disposition + [e]) == Rule2SevereFixed(review, disposition)
    ensures Rule3MediumCap(review + [f], disposition + [e], cap) == Rule3MediumCap(review, disposition, cap)
    ensures Rule4CarryForward(review + [f], disposition + [e], prior, today)
            == Rule4CarryForward(review, disposition, prior, today)
    ensures Rule5ExpiryWindow(review + [f], disposition + [e], today, horizon)
            == Rule5ExpiryWindow(review, disposition, today, horizon)
  {
    var r2, d2 := review + [f], disposition + [e];
    assert forall x :: x in r2 <==> x in review || x == f;
    assert forall x :: x in d2 <==> x in disposition || x == e;
    // Old entries never join to f (its id is fresh); e joins only to f, a Low.
    assert forall x :: x in disposition ==> x.id != f.id;
    assert forall id :: id != f.id ==> (JoinedSevere(r2, id) <==> JoinedSevere(review, id));
    assert forall id :: id != f.id ==> (JoinedAtLeastMedium(r2, id) <==> JoinedAtLeastMedium(review, id));
    assert forall id, s :: id != f.id ==> (SevIs(r2, id, s) <==> SevIs(review, id, s));
    assert !JoinedSevere(r2, f.id) && !JoinedAtLeastMedium(r2, f.id) && !SevIs(r2, f.id, Medium);
    assert MediumsAD(r2, d2) == MediumsAD(review, disposition);
    assert forall p :: p in prior && Due(p) ==>
      (CarriedOk(r2, d2, p, today) <==> CarriedOk(review, disposition, p, today));
    assert V2(r2, d2) == V2(review, disposition) && V4(r2, d2, prior, today) == V4(review, disposition, prior, today);
    assert V5(r2, d2, today, horizon) == V5(review, disposition, today, horizon);
    RuleIffNoViolations(r2, d2, prior, cap, horizon, today);
    RuleIffNoViolations(review, disposition, prior, cap, horizon, today);
  }

  // ---- Boundary lemmas: each helper against ADR-002's wording, at its edges ------------------------------
  // The theorems above relate Decide to the rule predicates; both sides share the helpers, so a wrong helper
  // would be invisible to them. These lemmas pin each helper to the ADR-002 clause it encodes.

  // Rule 5 is strict below and inclusive above: run date < expiry <= run date + horizon; no expiry is outside.
  lemma InWindowBoundaries(e: Entry, today: int, horizon: nat)
    ensures e.expiry == Some(today) ==> !InWindow(e, today, horizon)
    ensures e.expiry == Some(today + horizon) && horizon > 0 ==> InWindow(e, today, horizon)
    ensures e.expiry == Some(today + horizon + 1) ==> !InWindow(e, today, horizon)
    ensures e.expiry.None? ==> !InWindow(e, today, horizon)
  {}

  // Rule 4's trigger: open, accepted or deferred, and medium or above; fixed or low is never due.
  lemma DueBoundaries(id: string, x: Option<int>)
    ensures Due(PriorEntry(id, Medium, Open, x)) && Due(PriorEntry(id, High, Deferred, x))
    ensures !Due(PriorEntry(id, Low, Open, x)) && !Due(PriorEntry(id, Low, Accepted, x))
    ensures !Due(PriorEntry(id, Critical, Fixed, x))
  {}

  // A prior acceptance lapses when its expiry is on or before the run date, or when it has none (fail closed);
  // an open or fixed prior entry never lapses (rule 4's other clauses govern it).
  lemma LapsedBoundaries(p: PriorEntry, today: int)
    ensures AcceptedOrDeferred(p.status) && p.expiry == Some(today) ==> Lapsed(p, today)
    ensures AcceptedOrDeferred(p.status) && p.expiry == Some(today + 1) ==> !Lapsed(p, today)
    ensures AcceptedOrDeferred(p.status) && p.expiry.None? ==> Lapsed(p, today)
    ensures p.status == Open || p.status == Fixed ==> !Lapsed(p, today)
  {}

  // The downgrade path needs a second reviewer who is not the owner, and a rationale.
  lemma DowngradeByOwnerNotCarried(review: seq<Finding>, e: Entry, p: PriorEntry, today: int)
    requires RankedBelow(review, p) && e.reclassifiedBy == Some(e.owner)
    ensures !EntryCarries(review, e, p, today)
  {}
  lemma DowngradeWithoutRationaleNotCarried(review: seq<Finding>, e: Entry, p: PriorEntry, today: int)
    requires RankedBelow(review, p) && e.rationale == ""
    ensures !EntryCarries(review, e, p, today)
  {}

  // A prior critical/high must now be fixed: a reclassified (ReclassOk) downgrade left accepted is not carried.
  lemma SeverePriorLeftAcceptedNotCarried(review: seq<Finding>, e: Entry, p: PriorEntry, today: int)
    requires Severe(p.severity) && ReclassOk(e) && e.status == Accepted
    ensures !EntryCarries(review, e, p, today)
  {}

  // Rule 3 counts accepted/deferred mediums only: an accepted high (rule 2's) and an open medium are not counted.
  lemma MediumsADCountsOnlyAcceptedDeferredMediums(review: seq<Finding>, disposition: seq<Entry>, id: string)
    requires UniqueFindingIds(review)
    ensures (exists f :: f in review && f.id == id && f.severity != Medium) ==> id !in MediumsAD(review, disposition)
    ensures (forall e :: e in disposition && e.id == id ==> !AcceptedOrDeferred(e.status))
            ==> id !in MediumsAD(review, disposition)
  {
    if exists f :: f in review && f.id == id && f.severity != Medium {
      var f :| f in review && f.id == id && f.severity != Medium;
      forall g | g in review && g.id == id ensures g.severity != Medium {
        var i :| 0 <= i < |review| && review[i] == f;
        var j :| 0 <= j < |review| && review[j] == g;
        if i != j {
          if i < j { assert review[i].id != review[j].id; } else { assert review[j].id != review[i].id; }
        }
      }
      assert !SevIs(review, id, Medium);
    }
  }

  // ---- Fixture lemmas: the model's own verdict on the boundary fixtures (tests/governance/fixtures/disposition/)
  // Each FixtureNN states the inputs of fixture NN (dates as run date + k days) and the verdict the model gives;
  // the Python fixture of the same number carries the same inputs and expects the same verdict.

  // 13: a prior medium re-listed as low, reclassified by its own owner: not a second reviewer.
  lemma Fixture13(today: int)
    ensures Decide([Finding("SEC-001", Low)],
                   [Entry("SEC-001", Accepted, "alice", None, "no secrets in scope", Some("alice"))],
                   [PriorEntry("SEC-001", Medium, Accepted, Some(today + 30))], 5, 180, today)
            == Fail({Violation("SEC-001", CarryForward)})
  {
    var r := [Finding("SEC-001", Low)];
    var d := [Entry("SEC-001", Accepted, "alice", None, "no secrets in scope", Some("alice"))];
    var p := [PriorEntry("SEC-001", Medium, Accepted, Some(today + 30))];
    assert IdsR(r) == {"SEC-001"} by { assert r[0] in r; }
    assert IdsD(d) == {"SEC-001"} by { assert d[0] in d; }
    assert RankedBelow(r, p[0]) by { assert r[0] in r; }
    assert !CarriedOk(r, d, p[0], today);
    assert V4(r, d, p, today) == {Violation("SEC-001", CarryForward)} by { assert p[0] in p; }
    assert MediumsAD(r, d) == {};
    assert V2(r, d) == {} && V5(r, d, today, 180) == {};
  }

  // 19: an accepted medium expiring exactly at run date + horizon passes (inclusive above).
  lemma Fixture19(today: int)
    ensures Decide([Finding("SEC-001", Medium)],
                   [Entry("SEC-001", Accepted, "alice", Some(today + 180), "within the horizon", None)],
                   [], 5, 180, today)
            == Pass
  {
    var r := [Finding("SEC-001", Medium)];
    var d := [Entry("SEC-001", Accepted, "alice", Some(today + 180), "within the horizon", None)];
    assert IdsR(r) == {"SEC-001"} by { assert r[0] in r; }
    assert IdsD(d) == {"SEC-001"} by { assert d[0] in d; }
    assert MediumsAD(r, d) == {"SEC-001"} by { assert r[0] in r; assert d[0] in d; }
    assert V5(r, d, today, 180) == {};
    assert V2(r, d) == {};
  }

  // 20: an accepted medium expiring on the run date fails rule 5 (strict below).
  lemma Fixture20(today: int)
    ensures Decide([Finding("SEC-001", Medium)],
                   [Entry("SEC-001", Accepted, "alice", Some(today), "expires today", None)],
                   [], 5, 180, today)
            == Fail({Violation("SEC-001", ExpiryWindow)})
  {
    var r := [Finding("SEC-001", Medium)];
    var d := [Entry("SEC-001", Accepted, "alice", Some(today), "expires today", None)];
    assert IdsR(r) == {"SEC-001"} by { assert r[0] in r; }
    assert IdsD(d) == {"SEC-001"} by { assert d[0] in d; }
    assert MediumsAD(r, d) == {"SEC-001"} by { assert r[0] in r; assert d[0] in d; }
    assert JoinedAtLeastMedium(r, "SEC-001") by { assert r[0] in r; }
    assert V5(r, d, today, 180) == {Violation("SEC-001", ExpiryWindow)} by { assert d[0] in d; }
    assert V2(r, d) == {};
  }

  // 24: a prior medium re-listed as low without reclassified_by fails rule 4 (R10's boundary).
  lemma Fixture24(today: int)
    ensures Decide([Finding("SEC-001", Low)],
                   [Entry("SEC-001", Accepted, "alice", None, "now low", None)],
                   [PriorEntry("SEC-001", Medium, Accepted, Some(today + 30))], 5, 180, today)
            == Fail({Violation("SEC-001", CarryForward)})
  {
    var r := [Finding("SEC-001", Low)];
    var d := [Entry("SEC-001", Accepted, "alice", None, "now low", None)];
    var p := [PriorEntry("SEC-001", Medium, Accepted, Some(today + 30))];
    assert IdsR(r) == {"SEC-001"} by { assert r[0] in r; }
    assert IdsD(d) == {"SEC-001"} by { assert d[0] in d; }
    assert RankedBelow(r, p[0]) by { assert r[0] in r; }
    assert !CarriedOk(r, d, p[0], today);
    assert V4(r, d, p, today) == {Violation("SEC-001", CarryForward)} by { assert p[0] in p; }
    assert MediumsAD(r, d) == {};
    assert V2(r, d) == {} && V5(r, d, today, 180) == {};
  }

  // 25: every rule violated at once; every violating (id, rule) is named.
  lemma Fixture25(today: int)
    ensures Decide([Finding("SEC-001", High), Finding("SEC-002", Medium), Finding("SEC-003", Medium),
                    Finding("SEC-005", Low)],
                   [Entry("SEC-001", Accepted, "alice", Some(today + 10), "not fixed", None),
                    Entry("SEC-002", Accepted, "alice", Some(today + 10), "one of two", None),
                    Entry("SEC-003", Deferred, "alice", Some(today + 400), "too far out", None),
                    Entry("SEC-006", Fixed, "", None, "no such finding", None)],
                   [PriorEntry("SEC-004", Medium, Open, None)], 1, 180, today)
            == Fail({Violation("SEC-001", SevereNotFixed), Violation("SEC-002", MediumCap),
                     Violation("SEC-003", MediumCap), Violation("SEC-003", ExpiryWindow),
                     Violation("SEC-004", CarryForward), Violation("SEC-005", SetEquality),
                     Violation("SEC-006", SetEquality)})
  {
    var r := [Finding("SEC-001", High), Finding("SEC-002", Medium), Finding("SEC-003", Medium),
              Finding("SEC-005", Low)];
    var d := [Entry("SEC-001", Accepted, "alice", Some(today + 10), "not fixed", None),
              Entry("SEC-002", Accepted, "alice", Some(today + 10), "one of two", None),
              Entry("SEC-003", Deferred, "alice", Some(today + 400), "too far out", None),
              Entry("SEC-006", Fixed, "", None, "no such finding", None)];
    var p := [PriorEntry("SEC-004", Medium, Open, None)];
    assert IdsR(r) == {"SEC-001", "SEC-002", "SEC-003", "SEC-005"}
      by { assert r[0] in r && r[1] in r && r[2] in r && r[3] in r; }
    assert IdsD(d) == {"SEC-001", "SEC-002", "SEC-003", "SEC-006"}
      by { assert d[0] in d && d[1] in d && d[2] in d && d[3] in d; }
    assert V1(r, d) == {Violation("SEC-005", SetEquality), Violation("SEC-006", SetEquality)};
    assert JoinedSevere(r, "SEC-001") by { assert r[0] in r; }
    assert !JoinedSevere(r, "SEC-002") && !JoinedSevere(r, "SEC-003") && !JoinedSevere(r, "SEC-006");
    assert V2(r, d) == {Violation("SEC-001", SevereNotFixed)} by { assert d[0] in d; }
    assert SevIs(r, "SEC-002", Medium) && SevIs(r, "SEC-003", Medium) by { assert r[1] in r && r[2] in r; }
    assert !SevIs(r, "SEC-001", Medium);
    assert MediumsAD(r, d) == {"SEC-002", "SEC-003"} by { assert d[1] in d && d[2] in d; }
    assert V3(r, d, 1) == {Violation("SEC-002", MediumCap), Violation("SEC-003", MediumCap)};
    assert !CarriedOk(r, d, p[0], today);
    assert V4(r, d, p, today) == {Violation("SEC-004", CarryForward)} by { assert p[0] in p; }
    assert JoinedAtLeastMedium(r, "SEC-001") && JoinedAtLeastMedium(r, "SEC-002")
           && JoinedAtLeastMedium(r, "SEC-003") by { assert r[0] in r && r[1] in r && r[2] in r; }
    assert V5(r, d, today, 180) == {Violation("SEC-003", ExpiryWindow)} by { assert d[2] in d; }
    var want := {Violation("SEC-001", SevereNotFixed), Violation("SEC-002", MediumCap),
                 Violation("SEC-003", MediumCap), Violation("SEC-003", ExpiryWindow),
                 Violation("SEC-004", CarryForward), Violation("SEC-005", SetEquality),
                 Violation("SEC-006", SetEquality)};
    assert Violations2to5(r, d, p, 1, 180, today)
           == {Violation("SEC-001", SevereNotFixed), Violation("SEC-002", MediumCap),
               Violation("SEC-003", MediumCap), Violation("SEC-004", CarryForward),
               Violation("SEC-003", ExpiryWindow)};
    assert Violations(r, d, p, 1, 180, today) == want;
    assert Decide(r, d, p, 1, 180, today) == Fail(want);
  }

  // 33: a prior accepted medium with no expiry counts as lapsed; re-accepted with an expiry inside the window passes.
  lemma Fixture33(today: int)
    ensures Decide([Finding("SEC-001", Medium)],
                   [Entry("SEC-001", Accepted, "alice", Some(today + 30), "re-accepted", None)],
                   [PriorEntry("SEC-001", Medium, Accepted, None)], 5, 180, today)
            == Pass
  {
    var r := [Finding("SEC-001", Medium)];
    var d := [Entry("SEC-001", Accepted, "alice", Some(today + 30), "re-accepted", None)];
    var p := [PriorEntry("SEC-001", Medium, Accepted, None)];
    assert IdsR(r) == {"SEC-001"} by { assert r[0] in r; }
    assert IdsD(d) == {"SEC-001"} by { assert d[0] in d; }
    assert MediumsAD(r, d) == {"SEC-001"} by { assert r[0] in r; assert d[0] in d; }
    assert !RankedBelow(r, p[0]);
    assert EntryCarries(r, d[0], p[0], today);
    assert CarriedOk(r, d, p[0], today) by { assert d[0] in d; }
    assert V4(r, d, p, today) == {};
    assert V2(r, d) == {} && V5(r, d, today, 180) == {};
  }

  // 34: the same prior entry, now left open: not fixed and not re-accepted, so rule 4 fails.
  lemma Fixture34(today: int)
    ensures Decide([Finding("SEC-001", Medium)],
                   [Entry("SEC-001", Open, "alice", None, "still open", None)],
                   [PriorEntry("SEC-001", Medium, Accepted, None)], 5, 180, today)
            == Fail({Violation("SEC-001", CarryForward)})
  {
    var r := [Finding("SEC-001", Medium)];
    var d := [Entry("SEC-001", Open, "alice", None, "still open", None)];
    var p := [PriorEntry("SEC-001", Medium, Accepted, None)];
    assert IdsR(r) == {"SEC-001"} by { assert r[0] in r; }
    assert IdsD(d) == {"SEC-001"} by { assert d[0] in d; }
    assert MediumsAD(r, d) == {};
    assert !CarriedOk(r, d, p[0], today);
    assert V4(r, d, p, today) == {Violation("SEC-001", CarryForward)} by { assert p[0] in p; }
    assert V2(r, d) == {} && V5(r, d, today, 180) == {};
  }

  // Corollary (REQ-322's invariant): zero findings and no due carry-forward pass.
  lemma ZeroFindingsPass(prior: seq<PriorEntry>, cap: nat, horizon: nat, today: int)
    requires forall p :: p in prior ==> !Due(p)
    ensures Decide([], [], prior, cap, horizon, today) == Pass
  {
    assert IdsR([]) == {} && IdsD([]) == {};
    assert MediumsAD([], []) == {};
    assert V4([], [], prior, today) == {};
  }
}
