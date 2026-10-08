# The security document schema (`specflow-security/1`)

REQ-322, REQ-332. This is the schema `scripts/lib/specflow/blocks.py` reads
— the one parser of `docs/security/*-review.md` and `*-disposition.md`
(R5). Every review and disposition opens with a header block at line 1,
followed by prose and blocks. A block is a `---` line, flat `key: value`
lines (`config.parse` — one line per key, no nested YAML), and a closing
`---` line. An opening `---` with no closing `---` is a parser error
("unterminated disposition block"), never silently dropped.

## The header block (line 1 of every review and disposition)

```
---
schema: specflow-security/1
kind: review                 # review | disposition (matches the file name)
version: 1.2.0               # the file name's version
confirmed_by: octocat 2026-09-29   # optional: guided profile only (below)
---
```

`confirmed_by:` is an optional header key (guided profile, REQ-389: `<handle> <YYYY-MM-DD>`, written by `/next` at `ship-pr`); the header's other keys are `schema`, `kind` and `version`. It belongs to the header only, never to a finding or disposition block.

`kind` must match the file's own kind (a `<version>-review.md` file's
header carries `kind: review`; a `<version>-disposition.md` file's header
carries `kind: disposition`) and `version` must equal the version the
file name carries. In **gate mode** (`blocks.py check`, the disposition
gate, `verify-release.sh`) the header is required: a file with no `schema:`
key in its first block is a parser error naming the schema
(`<file>:1: no schema header (schemas/security-disposition-template.md)`),
and nothing else in the file is read. In **floor mode** (the suppression
scan, the expiry notice) the header is optional, for backward compatibility
with documents written before this schema.

## A review finding block (in `<version>-review.md`)

Followed by its prose body (at most 200 words), which should include the
metric-by-metric CVSS reasoning table `docs/security/RUBRIC.md`'s worked
example uses.

```
---
id: SEC-004
severity: medium             # must equal cvss4.finding_severity(cvss_vector): its band; a 0.0 vector reads as low (R20)
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N
cite: [dfe-3, CWE-20]        # at least one
affects: [src/app/x.py:12]
carried_from: 1.1.0          # only on a re-listed prior finding (R6); must name an earlier version
---

<the finding's body>
```

`cvss_vector` carries base metrics only: the eleven base metrics (AV, AC,
AT, PR, UI, VC, VI, VA, SC, SI, SA) and nothing else. Severity is the CVSS
v4.0 base score (`art-threat-driven-security`, `docs/security/RUBRIC.md`),
so a Threat (`E`), Environmental (`CR`, `IR`, `AR`, `MAV` … `MSA`) or
Supplemental (`S`, `AU`, `R`, `V`, `RE`, `U`) metric — even with value `X` —
is a parser error naming the metric (`cvss4.base_only`): appending
`MVC:N/MVI:N/MVA:N` to a 9.3 vector would otherwise score it 0.0 and record
a critical as low.

`severity` is checked against `cvss4.finding_severity(cvss_vector)` — the
score's band, with an informational (all-impact-`N`, 0.0) vector reading as
`low` rather than `none` (R20, so an informational finding is never
invented an impact just to leave `none` behind). A mismatch is a parser
error naming the finding's id, the stated severity and the vector's score
and band.

## A disposition entry block (in `<version>-disposition.md`)

```
---
id: SEC-004
status: accepted             # open | fixed | accepted | deferred
owner: alice                 # required for accepted/deferred, when the joined finding is medium severity or above
expiry: 2026-12-01           # YYYY-MM-DD; same rule as owner
rationale: "…"               # >= 10 characters (gate mode)
reclassified_by: bob         # required on a downgrade: the second reviewer (never the owner)
suppresses: [GHSA-…]         # optional (REQ-388); inline list, JSON-quoted items when they hold , " space or #
inherited: "…"                # optional (a pack's skeleton entry)
---
```

A downgrade needs both `reclassified_by:` (the second reviewer's handle, never the `owner:`) and a `rationale:` that names that reviewer. `disposition.py`'s rule 4 checks `reclassified_by:` against `owner:`
on a carried-forward downgrade; that the rationale names the reviewer, and
a downgrade within one release before it ships, are the reviewer's to check.

Keys outside the lists above are parser errors naming the unknown key (a
typo, such as `expirey:` for `expiry:`, never silently drops the field it
meant). Several entries for one id may appear across versions — a
carried-forward finding is re-listed in the review with `carried_from:`,
never redefined (R6) — and, in floor mode, within one file the later block
wins. The gate (`blocks.py check`) requires unique ids within each current
file: two blocks with the same `id:` in one review, or one disposition, is
a parser error naming the id.

## Rules blocks.py enforces, joined across the pair

- **Bands come from RUBRIC.md** via `cvss4.py`: `none` 0.0 (an
  informational finding recorded as `severity: low` —
  `art-threat-driven-security`'s informational row), `low` 0.1–3.9, `medium`
  4.0–6.9, `high` 7.0–8.9, `critical` 9.0–10.0.
- **Carried findings** are re-listed, not redefined: a finding whose block
  carries `carried_from: <version>` must name a version earlier than the
  file's own (R6); the block is not counted as a fresh definition of the
  id for the SEC-uniqueness check.
- **The downgrade path**: a prior medium-or-above finding re-listed at a
  lower severity, or accepted/deferred with an expired date, still carries
  forward through the disposition kernel's rule 4 (`disposition.py`,
  proved by the template's own Dafny model) — `blocks.py` itself only
  parses and validates the pair; rules 1–5 are `decide()`'s.
- **Lows** never need `owner:`/`expiry:` — those are required only when an
  `accepted`/`deferred` entry joins (by id) a finding of severity medium or
  above.
- **Floor mode** (the suppression scan, `scripts/check-suppressions.sh`;
  the expiry notice): the header is optional, but entries are still
  checked for known keys and a valid `status:` value — an unknown key is a
  parser error just as in gate mode (the caller, not `blocks.py`, checks
  `expiry:`'s date format) — floor mode reads only disposition files,
  never review files.
- **Gate mode** (`blocks.py check REVIEW DISPOSITION`; the disposition gate,
  `scripts/check-security-disposition.sh`; `scripts/verify-release.sh`): the
  header is required, ids are unique per current file, and every
  accepted/deferred entry joined to a medium-or-above finding carries
  `owner:` and `expiry:`, with `rationale:` at least 10 characters.
