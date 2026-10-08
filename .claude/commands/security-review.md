---
name: security-review
description: SECURITY phase — produce severity-rated review and per-finding disposition.
argument-hint: <version>
---

You are entering the SECURITY phase for release `v$ARGUMENTS`.

Read `constitution.md` article `art-threat-driven-security` (severity rubric is CVSS v4.0 base score). Read the threat model: `docs/architecture/<spec-slug>-threat-model.md` for the spec that drove this release.

0. Run `bash scripts/run-security-floor.sh` online (never with `SPECFLOW_FLOOR_OFFLINE=1`). A floor failure becomes a finding — never paper over it with a suppression that lacks a `SEC-NNN`. If any tool line reads `lookup failed` or `error, not findings`, rerun online; never paste a lookup failure into the review.

0a. Once, outside the floor, run each thresholded tool one level below the floor's threshold: `bandit -r src --severity-level medium --confidence-level medium` (python) and `npm audit --audit-level=moderate` (tauri). Record each result as a finding with its own CVSS vector (or "none found" in the review). A finding below the floor's threshold needs no `SEC-NNN` suppression, because the floor never fails on it.

Produce in order:

1. `docs/security/$ARGUMENTS-review.md`. It opens with the schema header block (`schemas/security-disposition-template.md`):
   ```yaml
   ---
   schema: specflow-security/1
   kind: review
   version: $ARGUMENTS
   ---
   ```
   Each finding is a markdown subsection with YAML frontmatter:
   ```yaml
   ---
   id: SEC-NNN
   severity: critical | high | medium | low   # the vector's band — RUBRIC.md
   cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N   # required; base metrics only; severity must equal its band
   cite: [<threat-id>, <CWE-NNN>, <OWASP-ref>]   # ≥1
   affects: [<path>:<line>, ...]
   carried_from: <prior version>   # only on a re-listed prior finding of medium or above (ADR-002 rule 4)
   ---
   ```
   The vector is base metrics only — the eleven base metrics, nothing else: severity is the CVSS v4.0 base
   score (RUBRIC.md), so a Threat (`E`), Environmental (`CR`/`IR`/`AR`/`M*`) or Supplemental (`S`, `AU`, `R`,
   `V`, `RE`, `U`) metric is a parser error.
   Body: ≤200 words on the finding, evidence, suggested remediation, with the metric-by-metric CVSS reasoning table (RUBRIC.md's worked example). New ids continue after the highest `id: SEC-NNN` defined under `docs/security/`; never reuse an id, even one from a superseded review.

   Before writing findings, re-list every latest prior entry of severity medium or above whose status is
   `open`, `accepted` or `deferred`. `python3 scripts/lib/specflow/blocks.py latest docs/security --before $ARGUMENTS --base "${SPECFLOW_BASE_REF:-origin/main}"`
   prints `<id> <version> <status> <severity>` for the latest prior entry per id — earlier versions only, each
   read as the disposition gate reads it (a tagged version from its tag, else the working tree, else the base
   branch) and joined to
   its version's review for the severity. Each listed line of severity medium or above whose status is `open`,
   `accepted` or `deferred` gets a finding block in this review carrying `carried_from: <the prior version>` (ADR-002 rule 4 requires
   it in the current disposition, which requires it in the current review).

   Ids are only ever added (R12): `check-security-disposition.sh` fails `id_removed` on any commit of the PR
   that drops an id from any review or disposition, even an id an earlier commit of this same PR added and the
   base never had. To withdraw an id added by mistake, either keep it — the finding block stays, and its
   disposition entry is `status: fixed` with a rationale saying it was raised in error (naming the id it
   duplicates, if any) — or close this PR and open a new one from a branch rebuilt on the base without the id,
   linking the closed PR in its body so the reviewer sees what was withdrawn. Never squash or force-push the
   open PR to hide it: the walk cannot see a rewritten history (dfe-3's residual).

   The review also carries a mandatory `## Tools run` section (REQ-332). Paste the output of
   `python3 scripts/lib/specflow/floor.py render --summary .specflow/floor-summary.json --root .`
   verbatim — editing a row breaks the evidence digest. A suppression added for a finding gets a
   disposition entry whose `suppresses:` names the entry (see the suppression rules in
   `docs/security/README.md`), and the suppression itself cites that SEC id
   (REQ-388).

2. `docs/security/$ARGUMENTS-disposition.md`. It opens with the schema header block (`schemas/security-disposition-template.md`, `kind: disposition`). Per finding YAML frontmatter:
   ```yaml
   ---
   id: SEC-NNN
   status: open | fixed | accepted | deferred
   owner: <github-handle>
   expiry: YYYY-MM-DD   # required if accepted or deferred, medium or above
   rationale: "..."     # ≥10 chars
   reclassified_by: <github-handle>   # required on a downgrade: the second reviewer (never the owner)
   suppresses: [<advisory id>, <allowlist string>, <fingerprint>, <file>:<config key>[<digest>], ...]  # names every entry this id excuses (REQ-388); check-suppressions.sh prints each name
   ---
   ```
   A downgrade needs both `reclassified_by:` (the second reviewer's handle, never the `owner:`) and a `rationale:` that names that reviewer. The second reviewer confirms or lowers the author's provisional severity; a downgrade within this
   release, before it ships, is recorded the same way — the gate checks `reclassified_by:` against `owner:` on a
   carried-forward downgrade (ADR-002 rule 4), and the reviewer checks the rest.

   An entry marked `inherited:` came with the stack pack (a skeleton disposition) and is not yet this
   project's decision: in this review's disposition, carry it forward with `owner:` set to this
   project's maintainer, drop the `inherited:` line, and confirm, change or fix it.

Before opening the PR:
- `python3 scripts/lib/specflow/floor.py check-review docs/security/$ARGUMENTS-review.md --root .` passes.
- `bash scripts/check-suppressions.sh` passes.
- `bash scripts/check-security-disposition.sh --version $ARGUMENTS` passes.

Gate: `bash scripts/check-security-disposition.sh --version $ARGUMENTS` (ADR-002 rules 1–5: zero open
critical/high; mediums within `medium_cap` and the expiry horizon, read from `docs/security/RUBRIC.md` at
the base; every carried-forward finding of medium or above re-listed).

If any critical or high finding requires code change: open `impl/sec-<finding-id>` (regulated) or `build/sec-<finding-id>` (lanes) from main, fix with TDD, merge, re-run VALIDATE, then resume here with `status: fixed`.

Push and open PR per `.claude/rules/review-gate.md`.

## Guided profile

Read only when `python3 scripts/lib/specflow/config.py get profile --default guided` prints `guided`. Ask or show only when the user ran `/security-review` directly. When `/next` ran this command it asks nothing here: at `ship-pr` `/next` shows the severity scores and the dispositions (acknowledgements), writes `confirmed_by:` into the frontmatter of the security review and the disposition, asks go or no-go (the decision) and records the answer under `### Guided proposals` in the release notes; on the regulated path `phase/security`'s point writes the security review's and disposition's `confirmed_by:` only, and `phase/release`'s asks go or no-go and records it under `### Guided proposals` in the release notes (REQ-342 allows no other pause). At `design-pr` and `ship-pr`, after writing `confirmed_by:` (and, at `ship-pr`, the go/no-go answer) and running the gates green as `next.sh` renders them (`bash scripts/next.sh --gates`), `/next` runs `git add` on all of the lane's artifacts (new and edited) — exactly the path sets `next.md` names at that point, nothing else — and commits them — `git commit -m "docs(guided): confirmed_by: <handle> <date> — acknowledgements at design-pr (REQ-389)"`, or `…at ship-pr (REQ-389)` — and only then runs `create-pr`, so the pushed branch carries what the gates checked. Under a `### Guided proposals` heading, give each proposal a `Rationale (plain English):` line and a `What this means for you:` line, in words a non-engineer follows. Each finding's severity and each disposition are **acknowledgements**: show them with the vector and the rule behind them, do not ask. Record them in the review's prose under `### Guided proposals` — not a block key: the schema's keys are fixed (`schemas/security-disposition-template.md`), so nothing is added to a finding or disposition block. The verifier's full mode confirms them provisionally in guided solo mode (`art-threat-driven-security`).
