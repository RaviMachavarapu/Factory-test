---
id: ADR-002
status: accepted
date: 2026-09-25
addresses: [REQ-322]
---

# ADR-002: Security-disposition gate is a pure decision function over parsed finding records

## Context
`art-threat-driven-security` promises that RELEASE is blocked while a critical or high finding is not `fixed`, that accepted or deferred mediums are capped, and that expiries mean something. Nothing mechanical checks any of it today: `scripts/verify-release.sh` greps a five-line window for `status:` and only confirms that accepted/deferred ids appear in known-limitations. The spec review found that "expiry must be in the future" turns merged releases red on a calendar date, and the ARCHITECTURE review of this ADR's first draft found three ways to ship an open critical while satisfying its rules: relabel the severity (a free-text field), delete the finding from both files, or leave it open in a version that is never tagged. REQ-322 tags the decision `[verifiable-model]`, so its logic is a model Dafny proves and tests call directly; everything that needs files, git or dates is outside the kernel and fixture-tested.

## Decision

### Kernel
`scripts/lib/specflow/disposition.py` exposes one pure function:

```
decide(review: Sequence[Finding], disposition: Sequence[Entry], prior: Sequence[PriorEntry],
       medium_cap: int, expiry_horizon_days: int, run_date: date) -> Verdict
```

- `Finding(id, severity, cvss_vector)` comes from the review; **severity is derived from the required CVSS v4.0 vector** by the parser (bands per `docs/security/RUBRIC.md`), so it cannot be relabelled independently.
- `Entry(id, status, owner, expiry, rationale, reclassified_by)` comes from the disposition; it carries no severity — `decide` joins each entry to the review finding with the same id, so the review's severity is the only one. `reclassified_by` is an optional second-reviewer handle (constitution: a downgrade requires the second reviewer's handle and rationale).
- `PriorEntry(id, severity, status, expiry, version)` is the **latest prior entry per id** across every earlier version's disposition, versions ordered by semver; the wrapper reduces to one entry per id and takes each prior entry's severity from that version's review (a prior disposition whose review is missing or has no vector is a parser error; pre-v3.2 prose dispositions define no findings and contribute nothing).
- `Verdict = PASS | FAIL(violations)` where `violations` is a set of `(id, rule)`; the result does not depend on input order.
- Preconditions (parser errors, exit 2, never FAIL): unique ids within each file; every accepted/deferred entry of severity **medium or above** has non-empty `owner` and an `expiry` (lows need neither, per the constitution); every review finding has a valid CVSS vector; `medium_cap ≥ 0`.
- **CVSS v4.0 scoring** is not a formula: `scripts/lib/specflow/cvss4.py` vendors FIRST's macro-vector lookup table as data and interpolates per the specification; it ships with conformance fixtures generated from the FIRST calculator. This is the largest single piece of P3 (size M on its own) and is outside the kernel.

### Rules (all evaluated; every violating id is named)
1. **Set equality:** `ids(review) == ids(disposition)`.
2. **Critical and high are fixed:** every current finding with derived severity critical or high has `status: fixed`.
3. **Medium cap:** the number of current mediums with `status ∈ {accepted, deferred}` is `≤ medium_cap` (the cap is per release, as the constitution and rubric say). Spreading acceptances across versions is prevented by rule 4, which forces every still-accepted prior medium to be re-listed and therefore counted.
4. **Carry-forward:** every latest prior entry with `status ∈ {open, accepted, deferred}` and severity ≥ medium must appear in the current disposition; a prior critical/high must now be `fixed`; a prior accepted/deferred whose `expiry ≤ run_date` must now be `fixed` or re-accepted/re-deferred with a fresh expiry; re-listing a carried-forward finding at a lower severity than its prior entry is a violation **unless** the current entry records `reclassified_by` (a second reviewer's handle, different from `owner`) and a rationale, which is the downgrade path `art-threat-driven-security` allows.
5. **Expiry window:** every current accepted/deferred entry of severity ≥ medium has `run_date < expiry ≤ run_date + expiry_horizon_days` (`RUBRIC.md` default 180).
6. **Lows** never affect rules 2–5; they must still satisfy rule 1.

`PASS` **iff** rules 1–5 hold; a disposition with zero findings and no due carry-forwards passes.

### Wrapper (`scripts/check-security-disposition.sh`, unverified, fixture-tested)
- Takes `--version`; defaults to the `ship/<version>` (or `phase/security`/`phase/release` with `next_version`) branch name; on any other branch it evaluates only when the PR's diff touches `docs/security/` or `docs/releases/`, using the version those files name; otherwise it exits 0 with a printed skip. It never re-evaluates an already-tagged version, and a merged-but-untagged version does not turn unrelated PRs red.
- Parses YAML blocks with `scripts/lib/specflow/blocks.py` (stdlib) per `schemas/security-disposition-template.md` (created in P3).
- Reads `medium_cap` and `expiry_horizon_days` **from the base ref** in CI, so the PR under review cannot raise its own cap.
- Ids may only be added to a version's review, never removed: the wrapper walks the PR's commit range (`git log -p <base>..HEAD -- docs/security/<version>-review.md`) and errors if any commit removes an id present in an earlier commit or at the base. This covers the lanes path, where the review is first created inside the ship PR; it cannot see a squash that happened before push, which the threat model records as a residual.
- Passes `run_date = today` (overridable for fixtures).

## Consequences
- The gate is provable: `verification/factory_v3_2/disposition.dfy` (`// Proves: REQ-322`) models the datatypes above and proves `Decide == Pass <==> AllRulesHold`, permutation invariance, and that lows do not influence rules 2–5. The reviewer's sketch verified in about 60 lines.
- REQ-322's text is amended in this PR to match: set equality is rule 1 (not a precondition), duplicates are parser errors, severity is derived from a required CVSS vector, the postcondition is an iff, the invariant reads "lows never affect rules 2–5".
- Existing dispositions (`docs/security/0.0.1-demo-disposition.md`, prose only) are migrated to the block schema in P3; the demo has zero findings, so that is a header-only change.
- `verify-release.sh` and `/security-review` call the wrapper (REQ-324, REQ-332); the solo author's severity remains provisional and is recorded as such (REQ-389).
- A disposition can never go red on a calendar date after release; it can only block the *next* release until carry-forwards are re-dispositioned.

## Alternatives Considered
- **Keep grep in `verify-release.sh`**: rejected; it cannot express set equality, carry-forward or the cap, and is unprovable.
- **Expiry as a validity window (fail when past)**: rejected; retroactively fails merged releases.
- **Carry forward every prior accepted/deferred entry (first draft)**: rejected; an expired entry stayed due forever even after a later version fixed it. Latest-entry-per-id fixes that.
- **Decision inside the bash wrapper**: rejected; Dafny cannot model bash and tests could not call the rule without file fixtures.
- **Write the kernel in Dafny and compile to Python**: rejected for v3.2; Dafny's Python backend adds a generated-code runtime and a build step to every instance's gate, and the model is small enough that a hand-written Python twin plus a permutation/truth-table fixture set keeps the two aligned. Revisit if a divergence is ever found.
