# Security

Per-release security review and disposition. Naming: `<version>-review.md` and `<version>-disposition.md`. Severity rubric: CVSS v4.0 (article `art-threat-driven-security`). Per-finding frontmatter required: see `schemas/security-disposition-template.md`, the block schema `scripts/lib/specflow/blocks.py` reads.

## Schema migrations

A released review or disposition is not edited after its tag except to move
it into a new schema version's syntax: no SEC id is added, removed or
re-scored, no text about the release changes, and a key is renamed only
where that schema version's entry below lists the rename explicitly
(`old:` → `new:`) — a rename no entry lists is not a migration. This is a
schema migration, not an addendum (the "Post-tag addendum" section below is
for a different, dated exception) — the migrated file still carries
whatever addendum it already had. Each
migration is listed here with its date and the plan that made it.

This standing exception was introduced by P3 (plan R7), in the same PR that
first used it on the released demo pair (a header-only change; the demo has
0 findings). Every PR that uses it needs the maintainer's confirmation,
stated in the merge or approval comment of the PR that uses the exception
(the PR template's SECURITY checkbox says the same). PR #42's confirmation
is the merge commit message of PR #42 (1ee84c8).

- **2026-09-27 (P3, `specflow-security/1`):** `docs/security/0.0.1-demo-review.md`
  and `docs/security/0.0.1-demo-disposition.md` gain the schema header block
  (`schema: specflow-security/1`) only, so they parse under
  `scripts/lib/specflow/blocks.py`'s gate mode; the demo has 0 findings, so
  no SEC id is touched. `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md`
  and `stacks/tauri/overlay/docs/security/0.0.0-skeleton-disposition.md`
  (a pack document, never tagged) gain the header block, rename `vector:` to
  `cvss_vector:`, and add the previously-pending `cvss_vector:` for SEC-002
  and SEC-003 (both informational, R20); no SEC id is added or removed.
  Key renames: `vector:` → `cvss_vector:` (the tauri skeleton only; the
  tagged demo pair renames nothing).
- **2026-09-29 (P5, header and prose only):**
  `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md` cites its
  rulings by plan (`R12` becomes `P4 R12`; each `R20` becomes
  `art-threat-driven-security`'s informational row, amendment B) and labels
  SEC-002's and SEC-003's exploitability tables "recorded for the vector's
  shape only: with every impact metric `N` the vector scores 0.0 whatever
  these rows say". No SEC id is added, removed or re-scored and no vector
  changes; the maintainer confirms the exception in the merge comment.

## `## Tools run`

Every `<version>-review.md` carries a mandatory `## Tools run` section,
rendered — never hand-written — from the security floor's last summary with
`python3 scripts/lib/specflow/floor.py render`. It lists each floor tool
(gitleaks, osv-scanner, and the stack's own audits) and its result, plus an
evidence line: a sha256 digest over the summary's commit and the rendered
rows. `python3 scripts/lib/specflow/floor.py check-review` recomputes that
digest and requires the summary's commit to be HEAD or an ancestor of it in
the repository's history, which catches a paraphrased or hand-edited table
(it does not stop someone who recomputes it on purpose — the reviewer and the
verifier still read for that). One exception, the provenance path: a shipped
review is rendered on a scratch instance whose summary commit no repository
holds, so its "scratch instance of template commit <sha>" line names the
commit named instead — and a provenance commit a shipped review names is not
checked against history: it need not be in the instance's history, nor in
`main`'s (a squash merge removes the template branch's commits, and whether a
clone still holds the object is immaterial), so for such a review the rows'
tamper evidence is the digest (PR #74; `--root` must still be a git work
tree, and a shipped review with no provenance line is ancestry-checked like
any other). The provenance line counts for shipped reviews only — a pack's
review under `stacks/*/overlay/docs/security/` (checked with `--pack`), the
`*-skeleton-review.md` an instance received from its pack, and a review
CLAUDE.md's Canonical Example lists (today only
`docs/security/0.0.1-demo-review.md`, whose addendum is generated from a
scratch instance by design). In every other review check-review ignores the
line: its `Floor summary:` commit must be HEAD or an ancestor of it, so a
provenance phrase cannot excuse a summary taken from another tree. check-review does not
compare the Active suppressions table with the repository's current
suppressions; `check-suppressions.sh` judges those. `render` refuses an offline, stale, or dirty
summary, or one holding a tool that produced no real evidence.

### Thresholds and the lower-level runs

The floor's thresholds are REQ-331's (`bandit --severity-level high`,
`npm audit --audit-level=high`; a threshold applies only where the tool
supports one). The floor's pass is not the review: `/security-review` runs
each thresholded tool once more a level lower (`bandit -r src
--severity-level medium --confidence-level medium`, `npm audit
--audit-level=moderate`) and records what it finds as findings. A finding
below the floor's threshold needs no `SEC-NNN` suppression, because the
floor never fails on it.

A table-less `## Tools run` is conformant where the product has no pack
lockfile (REQ-332's own exception: `scripts/requirements.txt` alone does not
count), which is the template source's case, its product being the demo.

## Post-tag addendum: a one-off exception for the demo

A released review is not edited after its tag: SECURITY artifacts are
versioned per re-entry (`art-threat-driven-security`), so every later
release produces a new versioned review (`<version>-review.md`), never an
addendum to an old one. `0.0.1-demo-review.md` is the single, deliberate
exception: it carries a floor addendum on `main` after its tag. The reason
is that the demo is the template's canonical example, which REQ-332's
`check-review` walks on every gates run, and the security floor (P4) did
not exist when the demo was released (2026-05-28); cutting a new demo
release only to carry a floor table would add a version with no change to
review. The addendum is dated, says the tag's copy has no addendum, and
adds no `SEC-NNN`. An auditor reading the signed `v0.0.1-demo` tag sees the
review as released; one reading `main` sees the same review plus the dated
floor run. No other review may carry a post-tag addendum.

## Suppressions

Every suppression that hides a finding from a floor tool — an ignore entry,
allowlist string, fingerprint, `# nosec`, or configuration key — must cite a
`SEC-NNN` whose latest disposition entry here is `accepted` or `deferred`
and must name that entry in its own `suppresses:` list. `check-suppressions.sh`
enforces this against every suppression file in scope; an advisory
suppression stops working once its `ignoreUntil` date passes. See
`docs/GLOSSARY.md`, Suppression.
