# SpecFlow Factory Constitution

This file lists the twelve non-negotiable articles that govern every spec, plan, and PR in this repository. Read this first every session.

Each article has a stable **slug** (e.g., `art-kernel-boundary`). Verifier blocking findings cite article by slug, never by Roman numeral. Roman numerals are display-only and may be reassigned without breaking citations.

---

## I — Specification Primacy

```yaml
roman: I
slug: art-specification-primacy
title: Specification Primacy
status: active
```

Spec changes happen at the spec layer first; code regenerates to match the spec. No code change is valid without a corresponding spec entry.

**Why:** prevents code from drifting away from intent.
**How to apply:** a PR that changes a source file under the stack pack's `source_roots` cites a `REQ-NNN` in one of its commits or in its body — `scripts/check-test-first.sh`, a step of the `gates` job in `.github/workflows/ci.yml`; every REQ a plan's `implements:` claims is defined by that plan's spec (`scripts/check-traceability.sh`) and cited by a test (`scripts/check-covers.sh`), both in gates section 6 of `scripts/run-quality-gates.sh`. That the code does what the cited REQ says is the verifier's code mode (`.claude/skills/verifier/SKILL.md`), a review, not a mechanism.

---

## II — Branch-as-State

```yaml
roman: II
slug: art-branch-as-state
title: Branch-as-State
status: active
```

Work reaches `main` only through a PR, with two exceptions: init's first commit (the new instance's starting tree, with nothing yet to review) and the doc-only minor exception bounded in `.claude/rules/review-gate.md` (a convention where `enforce_admins: false` or a free-plan private repository lets an admin push to `main` directly; see `art-review-gate`). Each phase has a named branch on either path — lanes: `design/<slug>`, `build/<slug>-N`, `ship/<version>`, and `build/sec-<id>` for the security back-edge; regulated: `phase/spec-<slug>`, `phase/arch-<slug>`, `phase/plan-<slug>`, `impl/plan-N-<plan slug>`, `phase/validate`, `phase/security`, `phase/release`, and `impl/sec-<id>` for the security back-edge; both paths: `patch/<slug>` (the patch tier) and `phase/retro-YYYY-MM-DD` (retrospectives). State of work is the set of branches and their PRs — open, merged or closed — and the tree; it is derived from them, and there is no out-of-band state file. Squash merges are permitted: state is read from PRs, not from branch ancestry. `.specflow.yml` is configuration, not state: its `path` chooses which branch names are proposed, and nothing records progress in it.

**Why:** branches and PRs are auditable, ordered, and tool-native.
**How to apply:** every phase transition is a PR that reaches `main`, directly or stacked on an open phase PR (REQ-395); both paths' branch names and the lane-to-phase mapping are listed in `.claude/rules/review-gate.md`, and `/next` derives the state from branches, PRs and the tree alone (`scripts/next.sh`, its kernel `scripts/lib/specflow/state.py`). `scripts/configure-repo.sh` requires a PR for `main` where GitHub's branch protection is available; where it is not (a free-plan private repository), and for an admin (`enforce_admins: false`), reaching `main` only through a PR is convention (no mechanism).

---

## III — Review Gate

```yaml
roman: III
slug: art-review-gate
title: Review Gate
status: active
```

Every phase transition is a PR that reaches `main` — directly or stacked on
another phase PR — with a recorded verifier review for its head and a review
gate set by `.specflow.yml`'s `solo`, read from the PR's base. **Team
(`solo: false`):** the verifier's `APPROVE` (or a maintainer waiver) and
one human approval other than the author (the review headless, or
in-session marked `origin:in-session`). **Solo (`solo: true`):** the
verifier's `APPROVE`, produced by a headless run outside the author's
session and posted under the author's own identity, is the recorded second review; in solo mode, on any GitHub
plan, it is a tamper-evident audit trail — the marker records head and base SHAs,
the base-branch prompt hash and a findings digest — **not an enforced control**:
the author can forge, re-roll or delete it. In solo mode the author may
instead self-waive; the second review is then absent, recorded only by the
waiver's rationale. In both modes the marker is
tamper-evident, not bound to a model run: the author can hand-post an
accepted marker or re-roll the review, so in team mode the human approval
from someone other than the author is the actual control. **Waiver:** a
maintainer may waive the verifier for one head SHA with a written rationale
of at least 20 characters; in team mode the waiver must come from someone
who is neither the PR author nor an author of any of its commits, and the
human approval from someone other than the last pusher
(`require_last_push_approval`). Linking the waiver from the PR body is convention (the
PR template's checkbox), not checked. **Dependabot:** a PR opened by
`dependabot[bot]` passes the verifier check without a marker only when every
commit is authored by `dependabot[bot]`, verified by GitHub, and committed by
`dependabot[bot]` or `web-flow`, and its diff touches only dependency
manifests and lockfiles — never `.github/` — and only moves the versions of
dependencies the base already lists; anything else fails closed, and the
verifier must review it (REQ-334). In solo mode such a PR merges with
no second review. The identity checks do not tie a commit to Dependabot: anyone
with write access can create, through GitHub's API, a commit GitHub marks
verified and committed by `web-flow` under an author of their choosing, so
the content rule is the real limit, and a forged commit can still move an
existing dependency to another registry version of the same package,
unreviewed (threat-model dfe-13's residual). Minor doc-only fixes (typos,
formatting, broken links) may merge directly to `main` within the bounds in
`.claude/rules/review-gate.md`. The doc-only minor exception
stays, and with it `enforce_admins: false`: even where branch protection
works, a repository admin (a solo owner always is one) can merge past red
`gates` or `verifier` checks and without the required approving review; on a
free-plan private repository nothing server-side enforces the checks or the
review. **Solo sign-off:** zero required approvals in solo mode (REQ-314) is
the maintainer's explicit decision — the verifier, not a person, is the
second review — signed off by merging constitution amendment PR B (REQ-343).

**Why:** prevents bypass of the gates that the rest of the constitution depends on.
**How to apply:** if a change touches a source file under the stack pack's `source_roots`, `verification/`, or a phase artifact, it goes through a PR; the required `verifier` check (`.github/workflows/verifier.yml`) passes only on an accepted marker for the PR's head (the form `scripts/run-verifier.sh` writes; tamper-evident, not bound to a model run), a maintainer waiver, or the Dependabot exemption, as `scripts/lib/specflow/attestation.py` judges them, and `scripts/configure-repo.sh` requires the `gates` and `verifier` checks and the approval count where GitHub's branch protection is available; see `.claude/rules/review-gate.md`'s claim→file table for what enforces each part of this article.

---

## IV — Test-First Discipline

```yaml
roman: IV
slug: art-test-first
title: Test-First Discipline
status: active
```

No production code is written before a failing test exists.

**Why:** tests written after code tend to confirm what the code does rather than what it should do.
**How to apply:** every PR that adds source code under the stack pack's `source_roots` adds a test in the same commit or earlier in the branch — `scripts/check-test-first.sh` (a step of the `gates` job in `.github/workflows/ci.yml`), which proves that a matching test file gained a line, not that the test exercises the change; that pairing is the verifier's code mode (`.claude/skills/verifier/SKILL.md`), and `.claude/rules/tdd.md` is the rule each session loads.

---

## V — Formal Verification

```yaml
roman: V
slug: art-formal-verification
title: Formal Verification
status: active
```

Two verification tags exist (amended 2026-06-09 per retro proposal #7):

- `[verifiable]` — full verification: a Dafny proof in `verification/` **plus** a runtime contract in `src/contracts/` extracted from the proven specification.
- `[verifiable-model]` — model verification: a Dafny proof in `verification/` that verifies a contract *model* of the behavior (not the production code), paired with a test that exercises the real implementation.

Runtime-contract extraction for `[verifiable]` is deferred to v3.3 (the v3.2 spec's Scope, REQ-326; first deferred by the v3.1 spec's Open Question #1a). Until it lands, tag requirements `[verifiable-model]` — the tag is honest about scope: the proof governs the model, tests govern the code.

**Why:** TDD proves cases pass; Dafny proves the contract is sound for all inputs.
**How to apply:** during IMPLEMENT, every `[verifiable]` or `[verifiable-model]` REQ a plan implements adds a `.dfy` file in `verification/` whose `// Proves:` header names it — `scripts/check-traceability.sh` (gates section 6) fails a claimed REQ with no proof, and gates section 2 of `scripts/run-quality-gates.sh` and the `gates` job of `.github/workflows/ci.yml` run Dafny on every proof (proofs present with Dafny missing fail); `[verifiable]` additionally adds a contract extraction step (v3.3+); until then no REQ carries `[verifiable]` and the step does not apply (no mechanism).

---

## VI — Architectural Kernel Boundary

```yaml
roman: VI
slug: art-kernel-boundary
title: Architectural Kernel Boundary
status: active
```

The ARCHITECTURE phase defines a verified-kernel boundary. Every `[verifiable]` or `[verifiable-model]` REQ maps to a module inside that boundary. Every external dependency crossing the boundary has a written justification in `docs/architecture/<spec-slug>-overview.md`.

**Why:** verification confidence is a function of where the kernel ends — without an explicit boundary, the kernel implicitly grows or shrinks per implementer mood.
**How to apply:** `scripts/check-architecture.sh` (gates section 6; the rule in `scripts/lib/specflow/architecture.py`) fails an overview whose `kernel_modules[].req_map` misses a REQ it owes: every `[verifiable]` or `[verifiable-model]` REQ of its spec while no plan names that spec (the ARCHITECTURE PR), then every tagged REQ that a plan naming the spec implements — all of them for a plan without `implements:`. That each boundary-crossing dependency has a written justification in the overview is convention (no mechanism): no script reads for it, and the verifier's skill (`.claude/skills/verifier/SKILL.md`) does not ask for it — a reviewer who reads the overview is the only check.

---

## VII — Threat-Model Driven Security

```yaml
roman: VII
slug: art-threat-driven-security
title: Threat-Model Driven Security
status: active
```

The threat model produced in ARCHITECTURE (per `docs/architecture/<spec-slug>-threat-model.md`) drives the SECURITY phase. Every SECURITY finding cites a threat-model item, a CWE, or an OWASP reference. The severity rubric is **CVSS v4.0 base score**:

| Severity | CVSS v4.0 Base |
|---|---|
| critical | 9.0–10.0 |
| high | 7.0–8.9 |
| medium | 4.0–6.9 |
| low | 0.1–3.9 |
| low (informational) | 0.0 |

A finding with no impact on any system (every impact metric `N`) scores 0.0 and is recorded as `severity: low`, its body saying it is informational; inventing an impact to reach 0.1 is a manufactured score, and an informational low still records a real observation; it is not a placeholder finding (see "Empty reviews are valid").

Severity is assigned during PR review by someone other than the finding's author when the team is ≥2 people. For solo teams, the author records `severity` provisionally; the next available second reviewer (next release cycle is acceptable) confirms or downgrades. Reclassification (downgrading) requires the second reviewer's handle and rationale to be recorded in the disposition's `rationale:` field. There is no CWE → CVSS auto-mapping (CWE is structural; CVSS is contextual).

**Empty reviews are valid.** A project with no findings produces `docs/security/<version>-review.md` whose body reads "0 findings; threat model `dfe-1..dfe-N` reviewed; no exposures identified." Manufacturing placeholder low-severity findings to "exercise" the gate is explicitly disallowed.

**Why:** absent a rubric, authors mark their own findings low and the gate becomes theater. Allowing empty reviews removes the perverse incentive to invent findings.
**How to apply:**
- SECURITY blocks RELEASE while any finding has `severity: critical, status: open` or `severity: high, status: open`.
- **Critical and high findings must reach `status: fixed`. They cannot be `accepted` or `deferred`** — RELEASE blocks if a critical or high carries those statuses regardless of expiry.
- **Mediums** with `status: accepted` or `status: deferred` are capped at 5 per release (override in `docs/security/RUBRIC.md`'s `medium_cap:` field).
- **Lows** do not count toward the cap and do not require an `expiry:`.
- `scripts/check-security-disposition.sh` (gates section 7, replayed at the tag by `.github/workflows/release.yml`; the decision function `scripts/lib/specflow/disposition.py`, ADR-002) enforces the rules above for the version under release; `scripts/run-security-floor.sh` (gates section 5) runs the tool floor the review's `## Tools run` records, and `scripts/check-suppressions.sh` (run by `tests/governance/test_suppressions.sh`, gates section 3, and by `/security-review`) requires every suppression to cite a live `SEC-NNN`; who assigns or confirms a severity is convention (no mechanism), except that in guided solo mode the verifier's full mode confirms severities and dispositions provisionally (`.claude/skills/verifier/SKILL.md`, REQ-389), a review, not a mechanism.

If SECURITY surfaces a critical or high finding requiring code change, spawn `impl/sec-<finding-id>` (regulated path) or `build/sec-<finding-id>` (lanes path) from main, fix with TDD, merge, re-run VALIDATE (on the lanes path, CI on that build PR), then resume `phase/security` or `ship/<version>` with `status: fixed`. SECURITY artifacts are versioned per re-entry.

---

## VIII — Release Readiness

```yaml
roman: VIII
slug: art-release-readiness
title: Release Readiness
status: active
```

RELEASE produces three docs (`<version>-notes.md`, `<version>-migration.md`, `<version>-known-limitations.md`) on the release PR and, after the merge, a tag `v<version>` on that PR's merge commit — SSH-signed and verified against `.github/allowed_signers` (annotated permitted only when no signer at all — SSH, GPG or X.509 — is configured or held, in which case the fallback is recorded in `<version>-known-limitations.md` plus a follow-up to re-tag signed; a GPG-signed tag is refused at the tag, since the Release job holds no GPG keyring). A release is **shipped** when the Release job succeeded from that tag: the artifacts and `manifest.json` (one entry per file, with SHA-256 checksum + size) attached to the GitHub Release, the source manifest reproduced in CI from the tagged tree, the tag an ancestor of `main` and its signature verified (or, annotated, the fallback recorded in known-limitations), and (python) the image pushed; the laptop-built `dist/` is not the artifact of record. **The manifest's reproducible subset is transcribed into `<version>-notes.md`** (filename + sha256 + size for each artifact) so an auditor at the tag commit can check the Release's artifacts against it without re-running the hook. The known-limitations doc auto-includes every `accepted` or `deferred` finding from `docs/security/<version>-disposition.md`.

**Why:** "tests pass" is not the same as "shipped"; the user needs the changelog, the migration steps, and a verifiable artifact built from the tag by a job, not on a laptop, whose checksums the tagged notes carry.
**How to apply:** at PR time the RELEASE-phase gate (`scripts/verify-release.sh`, gates section 7 of `scripts/run-quality-gates.sh`) blocks merge if any of: gates non-zero; the notes' Artifacts rows differ from the reproducible subset it builds itself from the PR head's tree (in CI it never reads `dist/`, and a tracked `dist/` fails; where `/release` produced `dist/manifest.json` locally, each file's checksum and its transcription are checked too); known-limitations missing a SEC-NNN that is accepted or deferred; the disposition gate (`scripts/check-security-disposition.sh`) failing; the tag `v<version>` already exists (the release PR never carries its own tag). "Tag missing" is judged after the merge: a merged release whose merge commit has no tag, or whose tag is annotated without the fallback recorded in known-limitations, is incomplete. At the tag, the Release job (`.github/workflows/release.yml`, REQ-350) publishes nothing unless: the tagged commit is the newest first-parent commit of `main` that added `<version>-notes.md` (the ship PR's merge); its signature verifies against the anchored `.github/allowed_signers` (`scripts/lib/specflow/signers.py`) — or, unsigned, its fallback is recorded in `<version>-known-limitations.md` — and a GPG signature fails; the previous release, when there is one, is tagged and its tag reads as released (`signers.py previous`: a missing, lightweight, GPG-unverifiable, unanchored or otherwise refused previous tag fails here, where the PR-time check only warns on a missing or uncheckable one); every first-parent commit of `main` since the newest earlier release whose GitHub Release is published is judged by `scripts/lib/specflow/attestation.py`'s `release-check` — a merged PR by an accepted marker, a waiver or the Dependabot exemption, a direct push of code by a maintainer waiver on the commit, the commits before the pack's attestation boundary listed as skipped; `scripts/verify-release.sh --at-tag` passes on the tagged tree — the three documents, known-limitations, the Artifacts table's shape, the app-stack rules, the REQ claims and proofs, the previous release's tag, and the disposition gate replayed through `scripts/check-security-disposition.sh --at-tag`; and the reproducible artifacts the job rebuilds from the tagged tree equal the notes' rows (`scripts/verify-release.sh --artifacts-only`). Neither `--at-tag` nor `--artifacts-only` re-runs the gates: the job replays gates section 7 only, never sections 1–6 or `scripts/check-test-first.sh`. The next release PR's `verify-release.sh` fails a previous release tag that is lightweight, unsigned without the recorded fallback, badly signed or not an ancestor of its base, and warns when it is missing; the PR template's RELEASE checkbox asks the maintainer to confirm by hand what no job replays (convention): that the previous release's tag exists on its merge commit, and that the previous ship PR's `gates` and test-first checks were green at its merge.

---

## IX — Repository Singleton

```yaml
roman: IX
slug: art-repository-singleton
title: Repository Singleton
status: active
```

All code, specs, plans, proofs, ADRs, threat models, and release artifacts live in this repository.

**Why:** split repos lose traceability and break the verifier's ability to walk REQ → ADR → task → code → proof.
**How to apply:** convention (no mechanism): no PR introduces a remote submodule or splits a sub-project out as its own repository; the verifier and the human reviewer read for it.

---

## X — Naming & Tagging

```yaml
roman: X
slug: art-naming-tagging
title: Naming & Tagging
status: active
```

- Requirements: `REQ-NNN` (three-digit zero-padded, globally unique).
- Tasks: `Task N.M` — the M-th task of a plan's `## Build N` section; a project may instead number tasks `TASK-NNN` (three-digit zero-padded, globally unique), the form `scripts/render_dashboard.py` reads from `# Task:` references.
- ADRs: `ADR-NNN` (globally unique).
- Findings: `SEC-NNN` (globally unique).
- Backlog proposals: `BL-NNN` (three-digit zero-padded, globally unique, never reused) in `docs/BACKLOG.md` (REQ-371).
- Verification tags: `[verifiable]` (full: proof + runtime contract) and `[verifiable-model]` (model proof + test) on requirements needing Dafny proofs — semantics in `art-formal-verification`.
- Article citations: `art-<kebab>` slug. Never Roman numeral.

**Why:** stable IDs make traceability mechanical.
**How to apply:** `scripts/check-traceability.sh` (gates section 6) fails a `REQ-NNN` defined in two live specs and a duplicate `ADR-NNN` or `SEC-NNN`; `tests/governance/test_backlog.sh` fails a duplicate `BL-NNN`; `tests/governance/test_reviews_use_slugs.sh` fails, anywhere in `docs/` (`docs/examples/` included) and in the files a session reads as instructions, except an archived review (`docs/reviews/archive-*`) and a document with a `status: superseded` line in its first 20 lines, an article cited by Roman numeral or by an `art-*` slug that `constitution.md` does not define. The task-id form (`Task N.M`, or `TASK-NNN`) is convention (no mechanism).

---

## XI — Secrets Hygiene

```yaml
roman: XI
slug: art-secrets-hygiene
title: Secrets Hygiene
status: active
```

Never commit `.env`, credentials, signing keys, or production tokens. Secrets live in GitHub Secrets; local development uses a `.env.local` listed in `.gitignore`.

**Why:** every credentialed commit is one `git log` away from a leak.
**How to apply:** `.gitignore` excludes `.env*` (except `.env.example`); the security floor's gitleaks (`scripts/run-security-floor.sh`, gates section 5, over the full history with `.gitleaks.toml`) fails a committed secret anywhere outside its allowlist (`.env.example`, `docs/**/examples/`, test fixtures); Claude sessions are denied reads of `.env` and `.env.*` (`.claude/settings.json`), and the verifier every `.env*` name (`scripts/run-verifier.sh`'s deny list); a committed `.env` file holding no detectable secret is caught by review alone — convention (no mechanism).

---

## XII — Retrospective Cadence

```yaml
roman: XII
slug: art-retrospective-cadence
title: Retrospective Cadence
status: active
```

Run `/retrospective` after every release PR merges — `ship/<version>` on the lanes path, `phase/release` on the regulated path (recommended; not automatic). Retros land on a `phase/retro-YYYY-MM-DD` branch and produce `docs/retrospectives/YYYY-MM-DD-<topic>.md` proposing — not executing — updates to constitution, templates, and governance tests.

**Why:** a factory that doesn't fold lessons back drifts toward the lessons it forgot.
**How to apply:** after the `ship/<version>` (lanes) or `phase/release` (regulated) PR merges, create `phase/retro-YYYY-MM-DD`, run `/retrospective`, open a PR with the proposed-changes doc; apply changes in a follow-up PR if accepted. Running it is convention (no mechanism); once it runs, `/retrospective` (`.claude/commands/retrospective.md`) requires a decision line for every open id in `docs/BACKLOG.md`, and `tests/governance/test_backlog.sh` fails a retrospective that leaves one out.
