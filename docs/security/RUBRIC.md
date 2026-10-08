# Security Severity Rubric

Referenced by `art-threat-driven-security` and REQ-114. This file is the
canonical location for the disposition caps and the scoring worked example.

```yaml
medium_cap: 5             # max accepted|deferred mediums per release (override here, with PR review)
expiry_horizon_days: 180  # rule 5 (ADR-002): an accepted/deferred entry's expiry must be within this many days of the run date
```

Override record (`art-threat-driven-security`: the cap is overridden only in this
`medium_cap:` field, by its own reviewed PR — ADR-002):

- 2026-10-03, maintainer decision for v3.2.0: raised from 5 to 10 — the 3.2.0
  review carries nine accepted or deferred mediums (SEC-006, SEC-007, SEC-008,
  SEC-009, SEC-010, SEC-011, SEC-012, SEC-013, SEC-014), eight of them the threat
  model's recorded acceptances (owner kpingali123, expiry 2026-10-12, CVSS v4.0
  vectors). The override was to return to 5 by 2026-10-12 unless re-decided at the
  P7 retrospective; it returned to 5 on 2026-10-04 by PR #70, before that date. Its
  lapse rule in `tests/governance/test_security_schema_docs.sh` (the gates failed
  once the date had passed with `medium_cap` still 10) was retired to a fixture by
  that PR and re-armed by the v3.2.1 record's PR below. This record is the
  template source's alone: `scripts/init-project.sh` gives a new instance
  `medium_cap: 5` and no override record.
- 2026-10-04, P7 retrospective (`docs/retrospectives/2026-10-04-v3-2-closeout.md`,
  PR #69): restored to 5 by this record's own reviewed PR, as promised; the lapse
  rule in `tests/governance/test_security_schema_docs.sh` is retired to a fixture.
  The 3.2.0 pair is released (`v3.2.0`), so the gate no longer evaluates it on
  `main`; the next ship brings the mediums within 5 by fixes or the cap is
  re-decided by its own reviewed PR (BL-022) — re-decided: the 2026-10-04 v3.2.1
  record below. If a future override is needed, it records a dated end the same way.
- 2026-10-04, maintainer decision for v3.2.1: raised from 5 to 8. The 3.2.1
  disposition will carry forward (ADR-002 rule 4) seven accepted or deferred mediums
  (SEC-007, SEC-008, SEC-009, SEC-010, SEC-012, SEC-013, SEC-014); PR #65 removed
  the causes of SEC-006 and SEC-011, and the 3.2.1 review is expected to record them fixed. The P7 retrospective deferred the related backlog
  items, BL-013 and BL-023 (the v3.3 design lane) and BL-016 and BL-017 (the first
  signed instance release known to the maintainer), and the seven are carried at
  their recorded expiries: 2026-11-15 for SEC-010 and SEC-012, the other five
  re-accepted in the threat model to 2026-12-15 (corrected 2026-10-05: the 3.2.1
  disposition re-accepted all eight, the seven and SEC-020, to 2027-01-31 (within
  ADR-002 rule 5 window from the review run date, with the margin past the tag
  date the #76 verifier asked for), and the post-3.2.1 records patch re-aligns
  the threat model to it). The seven are not fixed in 3.2.1:
  their fixes are deferred to the v3.3 design lane (BL-013, BL-023) or to the
  first signed instance release (BL-016, BL-017), and the cap is raised instead
  of fixing them before the ship. The record reserves the eighth place for SEC-020
  should that review accept or defer it (medium 5.2, provisional, BL-037; an open
  SEC-020 does not count): `verifier.yml` still prints a stacked base's own
  classifier text, labelled and defanged, beside the fixed bootstrap line, so the
  3.2.1 review cannot record SEC-020 fixed (7 + 1 = 8). The arithmetic has no
  headroom and rests on the provisional 5.2 score: it is valid only while the 3.2.1
  review records SEC-006 and SEC-011 fixed (PR #65 removed their causes), SEC-005
  fixed or left open, and SEC-021 low; otherwise the cap is re-decided by a
  reviewed PR. PR #76 (`patch/ship-3-2-1-prereqs`) is the 'own reviewed PR' ADR-002
  names, merged before the ship PR it governs because the gate reads the cap from
  the base ref. The decision covers the 3.2.1 ship alone: a further ship before the
  end needs its own reviewed PR. The override returns to 5 by a reduction PR right
  after the 3.2.1 Release is published, and by 2026-12-15 at the latest; the
  Release end is convention (no mechanism); only the date is enforced. Its lapse rule was re-armed on
  2026-10-04 (retired to a fixture again by the 2026-10-05 line below):
  `tests/governance/test_security_schema_docs.sh` fails the gates once 2026-12-15
  has passed with `medium_cap` still raised. This record is the template source's
  alone: `scripts/init-project.sh` gives a new instance `medium_cap: 5` and no
  override record.
- 2026-10-05, after the v3.2.1 Release (run 37302823217, tag `v3.2.1` on
  `609abbc`): returned to 5 by this record's own reduction PR
  (`patch/post-3-2-1-records`), as promised; the lapse rule is retired to a fixture
  again. The 3.2.1 disposition still carries eight accepted mediums (SEC-007,
  SEC-008, SEC-009, SEC-010, SEC-012, SEC-013, SEC-014, SEC-020) to 2027-01-31, so
  the next ship brings them within 5 by fixes or downgrades or re-decides the cap
  by its own reviewed PR (BL-046).

## Severity bands (CVSS v4.0 base score)

| Severity | CVSS v4.0 Base |
|---|---|
| critical | 9.0–10.0 |
| high | 7.0–8.9 |
| medium | 4.0–6.9 |
| low | 0.1–3.9 |
| low (informational) | 0.0 |

A finding's `cvss_vector` carries base metrics only — the eleven base
metrics AV, AC, AT, PR, UI, VC, VI, VA, SC, SI, SA and nothing else. A
Threat (`E`), Environmental (`CR`, `IR`, `AR`, `MAV` … `MSA`) or
Supplemental (`S`, `AU`, `R`, `V`, `RE`, `U`) metric is a parser error in
`blocks.py` and in the disposition kernel (`cvss4.base_only`), because it
can move the score below the base score this table bands.

A finding with no impact on any system (all six impact metrics `N`) scores
0.0 (FIRST's no-impact shortcut) and is recorded as `severity: low`, its
body saying it is informational: `cvss4.finding_severity(vector)` maps band
`none` to `low` (R20), so a 0.0 vector is never recorded as anything but
`low`, and inventing an impact to reach 0.1 would be a manufactured score
(`art-threat-driven-security`).

The 0.0 row is `art-threat-driven-security`'s own (constitution amendment B, REQ-343).

Rules (see `art-threat-driven-security` for the full text):
- Critical/high must reach `status: fixed` — never accepted/deferred.
- Accepted/deferred mediums are capped at `medium_cap` per release and need `owner:` + `expiry:`, with `expiry` within `expiry_horizon_days` of the run date.
- Lows need no expiry and don't count toward the cap.
- A medium left `status: open` is not counted toward `medium_cap` and needs no owner or expiry (ADR-002 rule 3 counts accepted/deferred mediums only), and carry-forward re-lists it at every release; reviewers look for long-open mediums.
- A lapsed prior medium carried forward and re-accepted as low (a downgrade with `reclassified_by:`) has no expiry upper bound: rule 4 needs only an expiry after the run date and rule 5 covers mediums only, so the reviewer checks its expiry.
- No CWE→CVSS auto-mapping: CWE is structural, CVSS is contextual.
- Solo teams: author scores provisionally; the next available second reviewer confirms or downgrades. A downgrade needs both `reclassified_by:` (the second reviewer's handle, never the `owner:`) and a `rationale:` that names that reviewer.

## Worked example

Finding: the release hook (`scripts/release-<stack>.sh`) makes an outbound
network call introduced by a malicious dependency update.

CVSS v4.0 vector reasoning, metric by metric:

| Metric | Value | Why |
|---|---|---|
| Attack Vector | Network (AV:N) | exfiltration target is remote |
| Attack Complexity | Low (AC:L) | no special conditions once the hook runs |
| Attack Requirements | Present (AT:P) | requires a poisoned dependency to land first |
| Privileges Required | None (PR:N) | hook runs with the developer's ambient credentials |
| User Interaction | Passive (UI:P) | a maintainer must run the release |
| Vulnerable system C/I/A | High/High/None | artifacts + signing context exposed/modifiable |

Vector: `CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:H/VI:H/VA:N/SC:N/SI:N/SA:N`

Score 7.6 (FIRST's calculator) → **high** → must be `fixed` before RELEASE
(back-edge: `impl/sec-<finding-id>`), regardless of how inconvenient that is.

Counter-example: the same outbound call in the *dashboard renderer* (no
secrets in scope, output is gitignored HTML) — vulnerable-system
confidentiality is lowered to None per that "no secrets in scope" reasoning;
integrity stays High because the renderer still writes the HTML the attacker
controls.

Vector: `CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N`

Score 6.0 (FIRST's calculator) → **medium** → eligible for `accepted` with
owner + expiry, within the cap.

The point of the pair: identical CWE (CWE-829), two different severities —
context decides, which is why there is no CWE→CVSS auto-mapping.
