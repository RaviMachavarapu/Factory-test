---
type: plan
phase: PLAN
spec: 2026-09-25-factory-v3-2
decisions: []
implements: [REQ-326, REQ-353, REQ-371, REQ-382, REQ-311, REQ-352, REQ-386, REQ-351, REQ-390, REQ-303, REQ-308, REQ-306, REQ-324, REQ-391, REQ-392, REQ-313, REQ-385, REQ-396]
created: "2026-10-03"
---

# Factory v3.2 — P7: Closeout (Amendment C, the Gate and Release Leftovers, the Habit-Tracker Example, the Backlog, the Retrospective) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** close v3.2. The constitution stops promising what nothing enforces: amendment C (REQ-326, REQ-353) makes every article's "How to apply" name the file that enforces it or say "convention (no mechanism)", defines "shipped" as the Release job succeeding from the tag, settles the two `art-release-readiness` clauses P6 left true-but-stale (P6 R10), moves `[verifiable]`'s contract extraction to v3.3, and gives `art-naming-tagging` a docs-wide slug-existence check — twelve articles still. Deferred proposals get a home with ids and a decision line per id at every retrospective (REQ-371, `docs/BACKLOG.md`). Build 1 closes the gate and release leftovers P6 handed on: waivers bound to a base like markers (P6 R8), `release-sign.sh` refusing entitlements the project never committed, the python image off root with a hash-pinned runtime lock (P6 R20's freeze lifted), and the surfaces PR #58's verifier named; it re-reviews every accepted residual that expires on 2026-10-12. Build 2 ships what the factory owes the maintainer-driven closeout: the documents-only habit-tracker example's home and manifest entry, the demo tag's re-tag follow-up path, and REQ-392's record. The maintainer walks the habit tracker (REQ-391) and an external product (REQ-392) by hand, re-tags `v0.0.1-demo` signed, and runs the retrospective.

**Architecture:** no kernel change. `scripts/lib/specflow/state.py`, `scripts/lib/specflow/records.py`, `scripts/lib/specflow/disposition.py` and `verification/` are untouched (each build's whole-build `git diff refs/remotes/origin/main --stat` proves it), and no `[verifiable*]` REQ is in `implements:`, so no proof step and no proof changes. Gate code P7 changes, each an unverified, fixture-tested wrapper: `scripts/lib/specflow/attestation.py` (the waiver's base binding — the classifier, dfe-2, under the verifier's severity floor, R4), `scripts/run-verifier.sh` (one printed waiver line), `scripts/release-sign.sh` (the entitlements refusal, R7), `scripts/release-image.sh` (its build context, R8), `stacks/python/Dockerfile` and `stacks/python/deploy.sh` (R8), `scripts/init-project.sh` (an instance's empty backlog, amendment C) and the governance tests named per task. `pipeline.py`, `signers.py`, `release_gate.py`, `release.yml` and every workflow are unchanged (R5, R6, R11).

**Plan style (REQ-380):** test code included (governance tests, fixture files, stub tools); implementation as intent, never bodies. Documents are described by the content the tests pin, and the constitution's amended sentences are given in full because the sentences are the deliverable. Rulings of this plan are `R1`–`R18`; outside this document they are cited as "P7 R<n>" (P3, P5 and P6 have their own R-numbers, cited "P6 R<n>").

**Tier and path:** the lanes path (REQ-381). This document is the design lane's plan on `design/factory-v3-2-p7`, one PR to `main` that carries this plan and the section "Amendment C" (executed on this branch by the next step of this workflow, P5's amendment-B precedent) and nothing else. The builds are `build/factory-v3-2-p7-1` and `build/factory-v3-2-p7-2`, one per `## Build N` section below, both cut from `main` once this PR has merged and worked in parallel on disjoint files (R1). The ship lane `ship/3.2.0` runs concurrently in `.claude/worktrees/p6` (it creates `v3.2.0`); this branch and both builds never touch `docs/security/`, `docs/releases/` or the spec's P6 `amended:` entry. The retrospective runs on `phase/retro-YYYY-MM-DD` after the ship PR merges (section "Retrospective"). Every PR gets a real headless marker: `git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>`.

**Spec:** `docs/specs/2026-09-25-factory-v3-2-design.md`, "Must Have — P7" (REQ-326, REQ-391, REQ-392), REQ-353 (listed under "Must Have — P6", deferred to amendment C by P6 R10), "Should Have" REQ-371, REQ-306's REQ-391 clause ("the REQ-391 example's artifacts when `stack != tauri`"), Success Metrics 2 and 3, and the P7 slices of REQ-382, REQ-311, REQ-352, REQ-386, REQ-351, REQ-390, REQ-303, REQ-308 and REQ-324 (below). The amendment-C step appends one `amended:` item to the spec ("P7 design lane", R16) recording amendment C and every reading this plan makes of literal REQ text, for both builds, and gives REQ-382's body one "As amended by P7 (R4):" sentence; neither build edits the spec unless a fix wave changes a reading (R1's rebase rule).

**Partial claims:**
- **Claimed from this commit, cited from the amendment-C commit (P5's precedent, not P6 R25's staging):** REQ-326, REQ-353 and REQ-371 are delivered on this branch by the amendment-C step, which adds their first citing tests (`test_constitution_articles.sh`, `test_constitution_amendment_c.sh`, `test_reviews_use_slugs.sh`, `test_backlog.sh`). At this plan's own commit `check-covers.sh` (gates section 6) fails for those three alone — the same state P5's plan commit `6d072e2` left for REQ-343 before amendment B's tests; the PR head is green from the amendment-C commit on, and the design PR is never opened before it.
- **Staged (P6 R25):** REQ-391 and REQ-392 join `implements:` in Build 2's Task 2.1 commit, the one that adds their first citing test (`test_examples.sh`); before it no test cites them and a claim would turn `main`'s gates red. Build 1 adds no claim: every REQ it changes is cited on `main @ fbd432a` (measured: `git grep -lP "Covers:.*REQ-<n>(?!\d)" -- tests` is non-empty for REQ-382, REQ-311, REQ-352, REQ-386, REQ-351, REQ-390, REQ-303, REQ-308, REQ-306 and REQ-324), so only Build 2 edits the `implements:` line (R1).
- **REQ-326:** delivered by amendment C — every article's "How to apply" names its enforcing files or says "convention (no mechanism)" per the spec review's clause table (`docs/reviews/2026-09-25-factory-v3-2-spec-review.md`, Appendix); `test_constitution_articles.sh` asserts each named file exists and each named `scripts/*.sh` is executable (R2's reading); `art-formal-verification`'s extraction promise moves to v3.3; `art-naming-tagging` gains the docs-wide slug-existence check in `test_reviews_use_slugs.sh`; twelve articles. Success Metric 2 is measured on `constitution.md` by `test_constitution_articles.sh` (R2): the dated review is a record and is not edited.
- **REQ-353:** delivered by amendment C — "shipped" means the Release job succeeded from the tag (REQ-353's text, R3), and P6 R10's two clauses are rewritten as settled text that matches `release.yml` and `verify-release.sh` on `main`.
- **REQ-371:** delivered on this branch by amendment C, because `art-retrospective-cadence`'s amended "How to apply" names `docs/BACKLOG.md` and `test_constitution_articles.sh` requires every named file to exist (R13): `docs/BACKLOG.md` with an id per deferred proposal (Interfaces, "The backlog": the P5/P6 rulings and residuals, and every proposal the two prior retrospectives deferred or left undecided, R17), `/retrospective` requiring a decision line per open id, `test_backlog.sh`, and an instance's empty backlog from `templates/BACKLOG.md`.
- **Slices (Build 1):** REQ-382 and REQ-311 (the waiver's base binding, the classifier's new reasons, the printed waiver line; Tasks 1.1, 1.2); REQ-352 and REQ-386 (the entitlements refusal, the flutter checklist's staple line; Tasks 1.3, 1.5); REQ-351 and REQ-390 (the non-root image, the runtime lock, the build context, `rollback`'s message; Task 1.4); REQ-303 (the python pack's `lockfiles:` and skeleton; Task 1.4); REQ-308 (README's Signing row, `CLAUDE.md:72`; Task 1.5).
- **Slices (Build 2):** REQ-306 (the habit-tracker example in the manifest, kept by a tauri instance and removed by every other stack's init, inert to the gates; Task 2.1); REQ-324 (the demo's released known-limitations may lose its stale fallback section once its tag is SSH-signed — the `/release` follow-up exception, Task 2.2).
- **REQ-391 and REQ-392 — what the factory ships, and what makes them met (R10, R12).** The factory ships: `docs/examples/habit-tracker/` with its README (layout, provenance, the evidence it holds once walked, its status — no maintainer instructions, since it ships to tauri instances), the walk's checklist in the factory-only `docs/examples/README.md`, the `### habit_tracker (stack: tauri)` manifest subsection (REQ-306's removal rule already acts on it), the tests that keep the example documents-only and inert, the demo re-tag's follow-up path (Task 2.2) and its exact commands (section "Maintainer checklist", M7), and `docs/examples/README.md`'s REQ-392 record. **REQ-391 is met** when the maintainer's walk (M1–M6) has produced a published GitHub Release in a throwaway instance repository, the bundle opened on a second Mac by the tester instructions, the instance's `docs/` and every `/next` transcript copied back under `docs/examples/habit-tracker/` by a reviewed PR, and `v0.0.1-demo` re-tagged signed (M7–M8). **REQ-392 is met** when R12's definition holds; otherwise `v3.2.0`'s known-limitations (the ship lane's) records it open and `docs/BACKLOG.md` BL-019 carries it to the retrospective. Build 2's claim covers the shipped parts only; the walk is evidence, recorded where R10 and R12 say.
- **Not claimed, with the reason:** REQ-341 and REQ-342 — `/next` is unchanged (R5, R6); REQ-383 and REQ-350 — `signers.py` and `release.yml` are unchanged, and `release-tag.sh` is unchanged except its header comment (R11, R15; corrected by the P7 retrospective's documentation patch, D3: amendment C's PR #60 rewrote that comment's signing text in commit `a465147`, which cites REQ-383 for that comment-only edit; the only workflow P7 changed is `.github/workflows/verifier.yml`, Build 1's Correction 2, SEC-020, PR #65); REQ-334 — the Dependabot rules are unchanged (a Dependabot PR touching the new `requirements-runtime.txt` is not a manifest the content rule knows, so it fails closed to a verifier review, R8); REQ-313 — `run-verifier.sh`'s isolation is unchanged (one printed waiver line, REQ-382's); REQ-381 — exempt; REQ-322 — `disposition.py` and ADR-002 are unchanged (BL-002 stays open, R13). Corrected by the retrospective's D19 (2026-10-04; BL-041; amendment D's PR): REQ-313 is no longer unclaimed — Build 1's SEC-020/SEC-021 corrections (`verifier.yml`, `run-verifier.sh`'s `.gitleaks.toml` read) cite REQ-313 and REQ-385, so both are in `implements:` (PR #65 verifier run 1, code-mode low). REQ-396 (amendment D) is claimed here since amendment D's PR, 2026-10-04 (PR #75 verifier run 1, finding 1): the spec groups it under P7 and the design lane adds no plan of its own.

**ARCHITECTURE artifacts:** no ADR is added or changed (R5: ADR-003's derived `next_version` stands, so `decisions: []`: no `[verifiable*]` REQ is implemented and no ADR governs a P7 change — `analyze-adr-plan-linkage.sh` checks only `[verifiable*]` REQs in `implements:`). Threat-model edits, each its own task with a governance test, named in that PR body under **Architecture-artifact updates**: the amendment-C step — the open-medium residual (`:198`, "Proposed for amendment C / P7" → BL-002) and the release-gates residual (`:211`) and dfe-14 (`:126`), whose "amendment C (P7, REQ-353) rewrites" becomes the settled clause; Task 1.2 — the waiver residual (`:202`); Task 1.4 — the Dockerfile residual (`:209`), closed; Task 1.6 — every other residual that expires on 2026-10-12 (dfe-6 `:118`, dfe-12 `:124` — its TOFU caveat, Boundary and Tagged-tree residuals —, dfe-13 `:125`, dfe-14 `:126` and the six other residuals among `:208`–`:216`), the deploy-local residual (`:208`) narrowed. Build 2 edits no architecture artifact.

**Measured 2026-10-03 (the hand-offs' facts):**
- **`/next` before this plan** (`GH_TOKEN=… bash scripts/next.sh --explain` on `design/factory-v3-2-p7` at `fbd432a`, the template source's defaults): `state: design brainstorm`; `next: run /superpowers:brainstorming and save the notes as docs/specs/<today>-factory-v3-2-p7-brainstorm.md`; why lines: `has_brainstorm is False`, `has_spec is False: no docs/specs/<date>-factory-v3-2-p7-design.md (the spec)`, `has_plan is False`, `analyze_ok is False: no plan to analyze`; path lanes, profile guided, solo true; 58 PRs read. With no plan, P6 R4's follow-on rule (the spec resolved through the plan's `spec:`) has nothing to read, so the lane reads as a new design. **After this plan:** see "Verified against" — Task 5.6's first field test of P6 R4.
- **R5's fact:** `pipeline._release_tag` reads only tags matching `^v(\d+)\.(\d+)\.(\d+)$`; `v0.0.1-demo` does not match (a suffix), so with no `vX.Y.Z` tag `next_version` is the first-release default `0.1.0` (`pipeline.py:1134`); once `v3.2.0` exists it is `3.3.0`.
- **Repository settings** (read-only `gh api`, kpingali123): `allow_rebase_merge: true`, `allow_squash_merge: true`, `allow_merge_commit: true`, private; the `release tags` ruleset (id 24361770) is active on `refs/tags/v*` with rules creation, update, deletion, non_fast_forward and the admin role as an always-bypass actor; the `release` environment exists; `orgs/Apps-Consultants/public_members/kpingali123` answers 204 (public); no open PR; the only tag is `v0.0.1-demo` (a tag object `42f72a4`, annotated, no signature, on commit `792cecb`).
- **The demo tag under the anchor rule:** `792cecb` carries `.github/workflows/ci.yml` and `verifier.yml` only — no `release.yml` — so pushing a re-signed `v0.0.1-demo` runs no Release job (GitHub runs the workflow stored at the tagged commit). An SSH-signed `v0.0.1-demo` reads `no-anchor` under `signers.verify` (no earlier `vX.Y.Z` tag, and no `.github/allowed_signers` key among its strict ancestors), so `signers.previous_release_check` refuses it; `v3.2.0`'s own `release.yml` (which runs `v3.2.0`'s own `signers.py`) treats `v0.0.1-demo` as the previous release, so after the re-tag `v3.2.0`'s run can no longer be re-run or dispatched (R11). For every later release the previous release is `v3.2.0` or newer.
- **Instance-visible readers of `docs/`:** every gate script globs top-level pipeline directories only — corrected by amendment D's PR (2026-10-04; BL-041): except `tests/governance/test_reviews_use_slugs.sh`, which gates section 3 (the governance tests; section 4 is the per-stack hook — R10 and Build 2's Deferred corrections said 4 until amendment D's PR corrected the number, 2026-10-04; this sentence named no section before) runs and which walks every `docs/**/*.md`, `docs/examples/` included (measured in a scratch tauri instance, Build 2's Deferred corrections) — (`check-traceability.sh`: `docs/specs/*.md`, `docs/plans/*.md`, `docs/adr/*.md`, `docs/security/*-review.md`; `architecture.py`, `check-covers.sh`, the disposition gate likewise); the walkers of all of `docs/` are `test_reviews_use_slugs.sh` (`find docs -name '*.md'`) and `test_next.sh:192` (a fixture walk). `.gitleaks.toml` allowlists `^docs/(.*/)?examples/` (pinned by `test_suppressions.sh:24`), so the floor's gitleaks never scans the example documents a maintainer copies back (R10).
- **pip and an empty hashed lock:** `pip install --no-cache-dir --require-hashes --no-deps -r <a file of comments only>` exits 0 with pip 24.0 (a scratch venv, nothing installed); the pinned `python:3.12-slim` image's pip is measured by Task 1.4's opt-in docker case before the Dockerfile relies on it (R8).
- **Two promises outside the measured grep** that amendment C's v3.3 move owns: `README.md:75-76` ("runtime-contract extraction, which lands in a later v3.2 plan"), `README.md:265` ("or, from a later v3.2 plan, `[verifiable]`") and `schemas/spec-template.md:73` ("contract extraction lands in v3.2").
- **The demo's released known-limitations** is pinned unchanged since its tag by `test_verify_release.sh:163-165`; the `/release` follow-up that removes its stale fallback section needs that pin narrowed first (Task 2.2).
- **The PR timeline, read with the maintainer's token** (fresh-eyes review, finding 3): `gh api --paginate repos/Apps-Consultants/factory/issues/<n>/timeline` answers for every PR read (#45, #47, #48, #51–#58); its `base_ref_changed` events carry `created_at` and `event` (no base names); only #48 has one (`2026-09-30T11:25:56Z`, the merge-first-then-retarget of P5). #48's three legacy waivers were posted at `2026-09-29T20:30:15Z` and `2026-09-30T10:59:35Z` (both before the retarget, for heads that were superseded) and `2026-09-30T13:16:13Z` for the merged head `ab16c32` (after it) — so the timeline rule keeps accepting #48. The same read under `verifier.yml`'s and `release.yml` verify job's read-only `GITHUB_TOKEN` is **not** measured yet: Task 1.1's Step 0 (M0b) measures it before the classifier relies on it.
- **R28's preview, before P7** (fresh-eyes review, finding 14; read-only, `GH_TOKEN=… python3 scripts/lib/specflow/attestation.py release-check --repo Apps-Consultants/factory --version 3.3.0 --tag-commit refs/remotes/origin/main --since v0.0.1-demo`, exit 0, 33 s): `43 first-parent commits since v0.0.1-demo: 15 ok, 28 skipped (root 0, predates-attestation 0, pre-transfer 28), 0 FAIL` — #41–#44, #46, #47, #51–#58 `ok … approve`, #48 `ok #48 waiver e337b41`. (`release-check` requires `--repo` and `--tag-commit`; the command in this plan's first draft omitted both and exits 2.)
- **The floor's lockfile discovery** (fresh-eyes review, finding 11): `scripts/run-security-floor.sh:65`'s `LOCKFILE_PATTERN` admits a lockfile by basename only (`requirements.txt`, `uv.lock`, …); `stacks/python/pack.yml`'s `lockfiles:` is read only by `floor.py`'s `has_lockfile`, and `stacks/python/security.sh` audits `requirements.txt` alone — so a `requirements-runtime.txt` is scanned by nothing today. osv-scanner 2.6.0 parses a uv-generated hashed `requirements-runtime.txt` when passed `-L requirements-runtime.txt` (measured on a scratch file: "found 1 package", exit 0).

**Rulings** (decided here; amendment C and the builds implement them):
- **R1 — two builds in parallel, on disjoint files (H13; P6 R35's precedent).** Build 1 (gate code, release leftovers, the threat model) and Build 2 (the example, the demo follow-up path, REQ-392's record) are both cut from `main` once this design PR merges, worked in two worktrees, and may merge in either order. The tolerated overlap is exactly two files, each by region: `CLAUDE.md` (Build 1 edits `:72`, Build 2 the `## Canonical Example` section from `:108` on — 36 lines apart, git merges both) and this plan (each build ticks and corrects only its own `## Build N` section; only Build 2 edits the `implements:` line). Neither build edits the spec (R16). **The rebase rule:** the second to merge runs `git fetch origin && git rebase refs/remotes/origin/main` on its own branch; resolves any conflict in this plan by keeping both builds' text in its own section, and in the spec (only if a fix wave appended a reading to the P7 entry) by keeping both sentences, the first-merged build's first; runs the gates; force-pushes its own unattested head (`git push --force-with-lease origin build/factory-v3-2-p7-<N>`); and gets a fresh verifier run on the new head. Each build's whole-build task checks `git diff refs/remotes/origin/main --name-only` against its column of the table below.
- **R2 — amendment C's scope and readings (H1; REQ-326).** (a) Every article's "How to apply" names, as backticked repository paths, the files that enforce it, or says "convention (no mechanism)"; an article enforced in part does both. (b) A **named file** is a backticked token whose first word is a path whose first segment is a repository root directory (`scripts`, `.github`, `.claude`, `tests`, `docs`, `schemas`, `templates`, `stacks`, `src`, `verification`) and whose last segment contains a dot, or one of the root files `.gitignore`, `.gitleaks.toml`, `constitution.md`, `CLAUDE.md`, `README.md`; placeholders (`<…>`, `*`, `YYYY`), branch names, slash commands and directories are not files. (c) REQ-326's "when under `scripts/`, is executable" is read as: every named `scripts/*.sh` is executable (the entry points a user, CI or a hook runs); a module under `scripts/lib/` is imported or run with `python3 -I`, is stored `100644` on `main` (measured: `git ls-files -s scripts/lib`), and must exist — a reading recorded in the spec's P7 entry. (d) Success Metric 2 ("the enforcement table … shows 12 of 12 articles with a named mechanism or an explicit 'convention' label") is measured on `constitution.md` by `test_constitution_articles.sh`; the 2026-09-25 reviews are dated records and are not edited. (e) The article count stays twelve. (f) Recording, as amendments A and B did: no per-article amendment marker; amendment C is recorded by the spec's P7 `amended:` entry, the commit subject `constitution: amendment C — …`, this section and the maintainer's merge of the design PR, which is the sign-off. (g) Amendment C weakens no control: every rule an article states stays, each "How to apply" only names what already enforces it or says that nothing does, `art-release-readiness`'s new text describes `release.yml` and `verify-release.sh` as they are on `main` (stronger than the text it replaces), its signing clause narrows to SSH (R3), `art-naming-tagging` adds a check, and `art-specification-primacy` and `art-test-first` widen `src/` to the pack's `source_roots`. Amendment C made `Task N.M` the default task id, which is not globally unique; that is a rule change, which the retrospective lists under amendment D (BL-041, D1). Amendment D's PR (2026-10-04; BL-041) records the task-id form as convention (no mechanism) in `art-naming-tagging`'s How to apply, so the default `Task N.M` and the optional `TASK-NNN` are both unenforced (D1's plan half).
- **R3 — REQ-353, P6 R10's clauses and P6 R27 (H1, H5).** `art-release-readiness` defines **shipped** as REQ-353 words it: the Release job succeeded from the tag — artifacts and `manifest.json` attached, the source manifest reproduced in CI, the tag an ancestor of `main` and its signature verified, and (python) the image pushed — and the laptop-built `dist/` is not the artifact of record. P6 R10's clause (a) ("checked only where `dist/manifest.json` exists — … in CI, where `dist/` is gitignored, only the Artifacts table's shape is checked, until the CI-built manifest, REQ-384") and clause (b) ("which the PR template's RELEASE checkbox asks the maintainer to confirm by hand; until `release.yml` replays these checks at the tag (REQ-350), that checkbox is the only check between a merge and the next release PR.") are both expired since P6 Builds 2 and 3 and are rewritten as settled text (section "Amendment C", the settled sentences). P6 R27 — `release.yml` accepts SSH signatures only — is stated in the article: "signed" reads SSH-signed and verified against `.github/allowed_signers`, the annotated fallback is permitted only with no signer at all (SSH, GPG or X.509), and a GPG-signed tag is refused at the tag. P7 adds no GPG support: CI holds no GPG keyring and `allowed_signers` lists SSH keys; GPG support is BL-008 for v3.3.
- **R4 — waivers bind a base, as markers do (H4; P6 R8; REQ-382, REQ-311; dfe-2).** A waiver may name the PR's base: `<!-- specflow-verifier:waive sha:<40-hex head> base:<40-hex base> -->`. A **bound** waiver is judged by the marker's base rule (its base is the PR's current base tip or gives the head the same merge base as the current base) and is otherwise refused as `waiver-base-mismatch` — refused, never blocking. A **legacy** waiver (no `base:`) is accepted only while the PR's timeline (`gh api repos/<repo>/issues/<pr>/timeline`, paginated) has no `base_ref_changed` event after the waiver's `created_at`; a later one refuses it as `waiver-unbound-retargeted`, and an unreadable timeline refuses it as `waiver-timeline-unknown` (fail closed, never blocking). Corrected by Build 1's classifier and the retrospective's D13 (2026-10-04; BL-041; amendment D's PR): the rule counts every `base_ref_*` and `automatic_base_change*` timeline event (`base_ref_changed`, `base_ref_force_pushed`, `base_ref_deleted`, `automatic_base_change_succeeded` and `_failed`, and any later event of either family), not only `base_ref_changed`, at or after the waiver's `created_at` (the same second counts), and an event, or a waiver, with no ISO-8601 UTC second time reads `waiver-timeline-unknown`; this is what `attestation.py`'s `_is_base_event` (the two prefixes) and `classify` (`t >= created_at`) do, and the retrospective's D13 says the same, so the code and the retrospective do not differ. A **commit-level** waiver (on a direct push, which `attestation.py release-check` judges) has no timeline and no retarget: a bound one must name the commit's first parent, a legacy one is accepted as before. **Remedy for a merged PR** (fresh-eyes review, finding 15): an instance that waived a stacked PR and then retargeted it (the documented merge-first-then-retarget flow, or GitHub's automatic retarget when the base branch is deleted) finds that PR refused at its next tag (`release-check` judges a merged PR through its PR comments, `waiver-unbound-retargeted`); the remedy is a bound waiver posted on that merged PR naming its merge commit's first parent — `release-check` judges the PR against that parent (`base_ref=parent`), so the bound waiver passes the base rule — and `release-check`'s FAIL line, `review-gate.md` step 4 and the glossary's Waiver entry say so. **The timeline read is measured first** (fresh-eyes review, finding 3): Task 1.1's Step 0 is the maintainer's draft-PR probe (P5 PR #49's precedent, M0b) of `gh api --paginate repos/<repo>/issues/<pr>/timeline` under `verifier.yml`'s and `release.yml` verify job's read-only `GITHUB_TOKEN` (`contents`, `issues`, `pull-requests: read`), on a PR with a `base_ref_changed` event. If the read answers, R4 stands as written. If it fails, every legacy waiver would be refused (`waiver-timeline-unknown`), the release-check over `v3.2.0..v3.3.0` included — Build 1's own PR, judged by `main`'s classifier, can carry only a legacy waiver — so the timeline rule is then dropped instead: legacy waivers are judged as before P7, bound waivers by the base rule, the residual stays ("a legacy waiver is bound to a head, not a base", re-accepted with BL-005) and the fix wave records the change as a ruling and in the spec's P7 entry (R1's rebase rule). `run-verifier.sh`, the classifier's message, `review-gate.md` step 4, the glossary and the PR-facing texts print the bound grammar. No rule weakens: every waiver accepted after P7 was accepted before it, so the release range `v3.2.0..v3.3.0` judges P7's earlier waivers by the timeline rule, which accepts a waiver on a PR never retargeted after it — the factory's own case. **Severity floor:** this edits the classifier rules in `attestation.py`, which the verifier's code mode rates high by rule when they are removed or weakened (`.claude/skills/verifier/SKILL.md`, "Severity floor for gate-weakening edits"); R4 only tightens, and Build 1's PR body says so with the fixture list. If the verifier still rates it high, the maintainer's waiver (posted by the user after the run, membership public) is the route.
- **R5 — `next_version` stays derived (H2; P6 R5).** No configured override, no ADR touch. The discrepancy P6 R5 recorded (`/next` on `main` proposes `ship/0.1.0` while the factory ships `3.2.0`) heals itself once `v3.2.0` is tagged: from then on `/next` proposes `ship/3.3.0`. A release of another version (P7's own fixes as `3.2.1`, BL-022) starts its `ship/<version>` branch by hand, which the glossary's Ship lane entry already says. An override would be configuration deciding pipeline state (`art-branch-as-state`: `.specflow.yml` chooses names, never records progress) and an ADR-003 revision for one transitional mismatch. BL-003 records the decision for the retrospective.
- **R6 — the template source's profile stays a convention (H3; P6 R6).** The factory runs `bash scripts/next.sh --profile engineer --explain` (`docs/GLOSSARY.md:9-12` already says so); a committed `.specflow.yml` would make the template an instance (P6 R2), and a `profile:` key in `scripts/template-pack.yml` would put an `.specflow.yml` key into pack metadata. No edit; BL-004.
- **R7 — `release-sign.sh` signs only with entitlements the project committed (H6; PR #58 verifier run 2; REQ-352, REQ-386).** The committed set is the file the tree gives today (flutter's `macos/Runner/Release.entitlements`; tauri's `src-tauri/tauri.conf.json` `bundle.macOS.entitlements`; else the pack's `.github/actions/release/entitlements.plist`), `com.apple.security.get-task-allow` removed. The set the unsigned app embeds (`codesign -d --entitlements :-`) is read only to compare: any key it carries that the committed set lacks, or carries with another value (get-task-allow aside), stops the script with exit 1 before anything is signed — `release-sign: the app embeds entitlements the project's committed file does not grant: <keys> (<file>); add them to that file by a reviewed PR, or build without them` — and the app is always signed with the committed set, never the embedded one. An app that embeds fewer keys than the committed file is signed with the committed file (reviewed); an app that embeds none is signed with it as today.
- **R8 — the python image (H7; P6 R20's freeze lifted; REQ-351, REQ-390; dfe-5).** The skeleton gains `requirements-runtime.in` (the project's runtime dependencies, empty) and `requirements-runtime.txt` (its hash-pinned lock, `uv pip compile --generate-hashes --universal --python-version 3.12`, generated, never hand-written); the pack's `lockfiles:` lists both lockfiles, and `scripts/run-security-floor.sh`'s `LOCKFILE_PATTERN` (which, not `lockfiles:`, decides what osv-scanner reads — measured) widens from `requirements\.txt` to `requirements(-runtime)?\.txt`, so the floor's osv-scanner scans the runtime lock; `stacks/python/security.sh`'s pip-audit stays on `requirements.txt` (osv-scanner is the floor's scanner for every lockfile). The Dockerfile installs the runtime lock with `--require-hashes --no-deps` (files whose bytes are pinned; an empty lock installs nothing), then the release's wheel alone (`--no-deps --no-index`), then `pip check`, and runs as a numeric non-root user created in the image (`USER 10001`). `release-image.sh build`'s temporary context gains the committed `requirements-runtime.txt` from the tagged tree beside the `Dockerfile` and the one wheel (absent from the tree → the build fails, naming it). `deploy-local.sh` keeps its stop-then-start cut-over (P6 recorded why start-then-swap does not fit: a published host port cannot be bound twice, and `--rm` deletes the old container); `rollback`'s failure when nothing runs names the recovery, `deploy <X.Y.Z>` of an earlier release. A Dependabot PR that moves `requirements-runtime.txt` fails closed to a verifier review (REQ-334's content rule knows `requirements.txt` by name only).
- **R9 — the residuals that expire on 2026-10-12 (H6, H12).** Owner: kpingali123, the maintainer. Build 1's Task 1.6 re-reviews each one before that date: closed where Build 1 closes it (the Dockerfile residual, by Task 1.4; dfe-12's boundary residual, once `v3.2.0` is published — the boundary is then fixed by the tag, else re-dated), narrowed where it narrows (deploy-local), and every other one re-accepted. **The form appends, never replaces** (fresh-eyes review, finding 12): each residual keeps its P6 acceptance parenthesis — its owner, its P6 sign-off (`sign-off: PR #5x's merge (Build N…`, which `test_threat_model_current.sh:213`, `:359` and `:459-469` pin) and its CVSS vector — and only its clause `expires: 2026-10-12, …` becomes `expires: 2026-12-15; re-accepted — owner: kpingali123, the maintainer; sign-off: the merge of build/factory-v3-2-p7-1 (P7 Build 1); re-reviewed by the v3.2 retrospective's decision on BL-0NN`. **The sign-off names the branch, not a PR number** (fresh-eyes review, finding 13): agents never open PRs or push, so a PR number exists only after the head an agent would commit is pushed; the branch's merge is the same event, and the merged PR is found from it. **Fallback:** if Build 1 has not merged by 2026-10-11, the maintainer re-dates the open residuals by a reviewed `patch/` PR before 2026-10-12 (P6's interim-window precedent: a lapse changes no code; no gate checks the date; the owner is the control), with the sign-off `the merge of patch/<slug>` — and the same fallback covers the released `v3.2.0` disposition's SEC entries that record these residuals (R18): they need no edit, since a released disposition is never edited after its tag, and the next ship carries them forward.
- **R10 — REQ-391: what the factory ships and what the maintainer does (H10).** The walk is the maintainer's, in a throwaway instance repository created from `v3.2.0` (the P6-merged release; from `fbd432a` if the walk starts before `v3.2.0` is tagged — the evidence records which), never inside the template source: tauri stack, `profile: guided`, `solo: true`, the lanes path driven by `/next`, through `ship/0.1.0` to a published GitHub Release whose unsigned bundle is opened on a second Mac by following the generated tester instructions. Its `docs/` artifacts and the transcript of every `/next` output are copied back under `docs/examples/habit-tracker/` by a reviewed `patch/habit-tracker-example` PR (documents only: `.md` and `.txt`; no second stack skeleton). Before committing the copy, the maintainer runs gitleaks over it with no allowlist (the template's `.gitleaks.toml` allowlists `docs/**/examples/`), and replaces every home-directory path with `~` in every copied file, transcripts and `docs/` alike (a CI path such as `/home/runner/…` too: `test_examples.sh` greps the whole tree, fresh-eyes review, finding 17); `test_examples.sh` repeats both checks (Task 2.1). The example is inert to the pipeline gates, which glob top-level pipeline directories only; `tests/governance/test_reviews_use_slugs.sh` (gates section 3) also reads `docs/examples/`, applying the Roman-numeral ban and the slug-existence check to the example tree (Build 2's Deferred corrections). **What a tauri instance inherits under `docs/` (corrected by amendment D's PR, 2026-10-04; BL-041; Build 2's finding 11, re-measured):** a scratch tauri instance (`copy_template` of the amendment D branch, then `SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Habit --stack tauri`) holds under `docs/` eleven Markdown documents, `docs/BACKLOG.md`, `docs/GLOSSARY.md`, `docs/adr/002-security-disposition-decision.md`, `docs/adr/README.md`, `docs/architecture/README.md`, `docs/releases/README.md`, `docs/releases/store-checklist.md`, `docs/releases/tester-instructions.md`, `docs/retrospectives/README.md`, `docs/security/README.md` and `docs/security/RUBRIC.md` (exactly Build 2's list), plus `docs/getting-started.html` and the example's `docs/examples/habit-tracker/README.md`, and nothing else (the factory's own specs, plans, reviews, and security and release records are fenced out). M6's copy rule (`docs/examples/README.md`) excludes the eleven, and `test_examples.sh` measures the set.
- **R11 — the demo tag re-tag (H10; REQ-391's last sentence).** `v0.0.1-demo` is re-created SSH-signed on the same commit `792cecb`, by the maintainer (M7), **after** `v3.2.0`'s Release is published and checked: the re-signed demo tag reads `no-anchor` under `v3.2.0`'s own `signers.py`, so from then on `v3.2.0`'s `release.yml` cannot be re-run or dispatched (P6 R34's recovery for that one release ends; BL-020). No code change helps: a re-run runs the tagged commit's `signers.py`, never `main`'s. The push runs no Release job (`792cecb` has no `release.yml`) and needs the admin bypass of the `release tags` ruleset (update). The demo's released known-limitations then loses its stale "Unsigned tag (follow-up required)" section by the `/release` follow-up (`release.md`: "the removal of a stale fallback line once a signed tag was created"), on a `patch/demo-retag-followup` PR, which Task 2.2's narrowed pin admits only once the tag carries an SSH signature and only as the removal of exactly that section.
- **R12 — REQ-392: what "met" looks like and what the factory records (H11).** Met: a repository other than the factory and other than R10's throwaway habit tracker (unless the maintainer decides at the retrospective to keep the habit tracker as the product, recorded on BL-019), created from `v3.2.0` (or `fbd432a`), driven by the maintainer through the lanes path via `/next` (design → build(s) → ship), whose `release.yml` run published a non-draft GitHub Release from a `v<X.Y.Z>` tag on its `main`. Recorded either way: `docs/examples/README.md`'s "External product (REQ-392)" section (Build 2) gains, by a reviewed `patch/` PR, the repository (or a description, if private), the Release URL, the `release.yml` run id and the manifest's `signed` value — or stays "not met"; BL-019's decision line at the retrospective says met (with that record) or deferred with a trigger; `v3.2.0`'s known-limitations (the ship lane's) already records REQ-392 open and is never edited after its tag.
- **R13 — REQ-371 lands with amendment C (H9).** `art-retrospective-cadence`'s "How to apply" names `docs/BACKLOG.md`, `.claude/commands/retrospective.md` and `tests/governance/test_backlog.sh`, and `test_constitution_articles.sh` requires named files to exist, so the backlog, the command's decision-line rule and its test land with the article, on this branch. `art-naming-tagging` gains backlog ids `BL-NNN` (three-digit, globally unique; `test_backlog.sh` fails a duplicate). An instance receives an empty backlog: `init-project.sh` writes `docs/BACKLOG.md` from `templates/BACKLOG.md`, replacing the factory's (whose ids are the factory's). The builds do not edit `docs/BACKLOG.md`: decision lines are the retrospective's.
- **R14 — the python GHCR path stays unproved until a python instance ships (H8).** No python example walk in P7: REQ-391 names tauri, and one more instance repository and ship is a second multi-day maintainer walk. BL-009 (the GHCR proof) and BL-010 (the job token's answer for a never-pushed package, the delete right, the read-back) carry it to the retrospective with v3.3 as the proposed trigger; the GHCR residual is re-accepted by Task 1.6.
- **R15 — P6 R14, R27 and R28 (H5).** The `release tags` ruleset and the `release` environment exist on the factory (measured). `allow_rebase_merge` is still `true`: the maintainer re-runs `bash scripts/configure-repo.sh` (M0) — no code change. R27 is R3's. R28's pre-transfer boundary (`attestation_since: e88e8361ef913ca7ac7475e506610003be7574bb` in `scripts/template-pack.yml`) stays as recorded; once `v3.2.0`'s tagged tree carries it, the never-moves rule fixes it, and Task 1.6 closes dfe-12's boundary residual then (R9). Restricting `refs/tags/origin/**` in the ruleset, which would narrow the short-name base residual (dfe-6, dfe-14), is BL-007 for the retrospective.
- **R16 — the spec entry is written once, on this branch.** The amendment-C step appends one item, `- "P7 design lane (lanes; docs/plans/2026-10-03-factory-v3-2-p7-plan.md): …"`, after the P6 entry (the ship lane edits the P6 line concurrently; whichever of the ship PR and this PR merges second resolves the adjacent-line conflict by keeping both lines, P6's first), recording amendment C (REQ-326, REQ-353, REQ-371) and the readings of R2(c), R3, R4, R8, R10, R11, R12, R13 and R17 for both builds (the fresh-eyes revision adds R17's reading and REQ-382's merged-PR remedy), and gives REQ-382's body the sentence "As amended by P7 (R4): …" (Interfaces, "The spec's P7 entry"). Spec first, code after (`art-specification-primacy`): the builds implement what the entry already says.
- **R17 — the prior retrospectives' deferred proposals (REQ-371; fresh-eyes review, finding 1).** REQ-371 says "every deferred proposal from prior retrospectives". The factory's two retrospectives were removed from the tree by `02677f8` (the template clean-up) and are read at `02677f8^`: the 2026-05-28 one deferred proposals #5, #6, #8 and #10 ("revisit at the v3.2 retro"); the 2026-06-09 one made five proposals with no recorded decision and carried the `v0.0.1-demo` re-tag as an open item. Each gets an id, BL-024 … BL-033, whose **Source:** names the historical path at `02677f8^` and the proposal's number. Where the v3.2 spec already delivers a proposal in whole or in part, the entry says so in an **Absorbed:** line citing the REQ — REQ-380 (#5 in part), REQ-321 (#6 in part), REQ-395 (#8 in part; and the 2026-06-09 #2 with `review-gate.md` step 6), REQ-310 (the wrong-branch guard), REQ-382 and REQ-311 (recorded waivers), REQ-324 (`/release` delegating to `verify-release.sh`) — and each stays **Status:** open: only a retrospective writes decisions (R13), so the v3.2 retrospective records `accepted (landed: …)` for an absorbed one. `test_backlog.sh` pins the ten sources by number (Amendment C, Step A5). The retrospectives' open questions are not proposals and get no id.
- **R18 — which record of a residual governs between releases (fresh-eyes review, finding 4).** The ship lane's `docs/security/3.2.0-disposition.md` (on `ship/3.2.0`) records SEC-006 … SEC-019, most with `expiry: 2026-10-12` (SEC-010 and SEC-012: 2026-11-15) — the same residuals Task 1.6 re-accepts in the threat model to 2026-12-15. A released disposition is never edited after its tag, so after `v3.2.0` the two records disagree on the date. The threat model governs between releases: it is the living architecture artifact and the owner's re-acceptance lands there (Task 1.6, or R9's fallback); a released disposition records the decision at its tag, and a lapsed expiry there means "due at the next ship". The next ship's disposition (`3.2.1` or `3.3.0`, BL-022) carries each of these SEC ids forward (ADR-002 rule 4, `check-security-disposition.sh`) with Task 1.6's expiry and its BL id in the rationale, or `status: fixed` where Build 1 closed it (SEC-006, waiver base binding, by Tasks 1.1–1.2; the python image residual by Task 1.4), within `expiry_horizon_days: 180`. If the ship lane has not merged when Task 1.6 lands, adopting 2026-12-15 in `3.2.0`'s own disposition is the ship lane's call, never this plan's (it does not touch `docs/security/`). The Retrospective inputs name this. (corrected by the post-3.2.1 records patch, 2026-10-05; BL-022) In the event the 3.2.1 ship carried each of these residuals to 2027-01-31, not Task 1.6's 2026-12-15: within ADR-002 rule 5's window from the review's run date, the date was a choice for margin past the planned tag date and past the cap override's end (the PR #76 verifier's margin finding: a ship tagged on a carried expiry's own date would fail at the tag), so `docs/security/3.2.1-disposition.md` re-accepted every accepted entry of severity medium or above to 2027-01-31 (the lows carry the same date by choice; rule 5 does not bind them) and the threat model is re-aligned to it by the same patch (PR #78, item 7's re-dating patch).

**Build 1 ∩ Build 2** (every file a task of either build names under **Files:**):

| File | Build 1 | Build 2 |
|---|---|---|
| `scripts/lib/specflow/attestation.py`, `tests/governance/fixtures/attestation/103-*.json` … `109-*.json` (new), `tests/governance/test_attestation.sh`, `scripts/run-verifier.sh`, `tests/governance/test_verifier_run.sh`, `tests/governance/lib/check.sh` (the stub `gh`'s timeline arm), `tests/governance/test_next_prs.sh`, `tests/governance/test_release_check.sh` | 1.1 | — |
| `.claude/rules/review-gate.md`, `docs/GLOSSARY.md`, `tests/governance/test_review_gate_claims.sh` | 1.2 | — |
| `scripts/release-sign.sh`, `tests/governance/test_release_sign.sh`, `stacks/tauri/release/entitlements.plist`, `stacks/flutter/release/entitlements.plist`, `stacks/tauri/store-checklist.md` | 1.3 | — |
| `stacks/python/Dockerfile`, `stacks/python/pack.yml`, `stacks/python/skeleton/requirements-runtime.in` and `.txt` (new), `stacks/python/deploy.sh`, `scripts/release-image.sh`, `scripts/run-security-floor.sh` (`LOCKFILE_PATTERN`), `tests/governance/test_release_python.sh`, `tests/governance/test_deploy_contract.sh`, `tests/governance/test_first_run.sh`, `tests/governance/test_stack_packs.sh` | 1.4 | — |
| `stacks/flutter/store-checklist.md`, `tests/governance/test_release_apps.sh`, `tests/governance/test_onboarding_surface.sh` | 1.3, 1.5 | — |
| `README.md` | 1.4 (the python deploy subsection), 1.5 (the Signing row) | — |
| `docs/architecture/2026-09-25-factory-v3-2-threat-model.md`, `tests/governance/test_threat_model_current.sh` | 1.2, 1.4 (dfe-5's row `:117` and its python image residual `:209`, closed; the `:465` lookup), 1.6 | — |
| `CLAUDE.md` | 1.5 (`:72` only) | 2.1 (the `## Canonical Example` section only) |
| `docs/examples/README.md`, `docs/examples/habit-tracker/README.md` (new), `scripts/factory-only.txt`, `tests/governance/test_examples.sh` | — | 2.1 |
| `tests/governance/test_verify_release.sh` | — | 2.2 |
| `docs/plans/2026-10-03-factory-v3-2-p7-plan.md` | its own `## Build 1` section | its own `## Build 2` section; `implements:` |

The intersection is `CLAUDE.md` (by region) and this plan (by section) — the tolerated set. Neither build edits the constitution, the spec, `docs/BACKLOG.md`, `docs/security/`, `docs/releases/`, `scripts/init-project.sh`, `scripts/lib/specflow/pipeline.py`, `signers.py`, `release_gate.py` or any workflow — no longer true for Build 1: its sanctioned corrections touched `.github/workflows/verifier.yml` and `scripts/init-project.sh`, and Build 2's touched `docs/BACKLOG.md` (the dated note below); `tests/governance/lib/check.sh` gains one arm in its stub `gh` (Task 1.1: the timeline read, answering `$S/timeline.json` or `[]`), and Build 2 does not touch it.

**Corrected by the P7 retrospective's documentation patch (2026-10-04; `docs/retrospectives/2026-10-04-v3-2-closeout.md`, What Didn't, item 4 and Proposed Changes, item 4; D15; BL-041).** The table above is kept as reviewed. Build 1's sanctioned corrections (PR #65, `151a1e7`; its Corrections 2 and 9 and the lows of items 4, 6, 7 and 8) also touched files outside its column: `.github/workflows/verifier.yml` (item 2), `scripts/init-project.sh` (item 9), `tests/governance/test_workflow_health.sh` (item 2), `tests/governance/test_backlog.sh` (item 9), `tests/governance/test_constitution_articles.sh` (item 7), `tests/governance/test_constitution_amendment_b.sh` (item 6), `tests/governance/test_reviews_use_slugs.sh` (item 8) and `tests/governance/test_spec_commands.sh` (item 4). Build 2's sanctioned BL-028…BL-031 corrections (PR #64, `096899a`) touched `docs/BACKLOG.md` and `tests/governance/test_backlog.sh`, outside its column (Build 2's Deferred corrections), so `tests/governance/test_backlog.sh` is in both builds' files. No other workflow changed: `.github/workflows/release.yml` was last changed by P6 Build 3 (PR #56). Still owed under BL-041 (owner kpingali123, before the 3.2.1 ship), not applied by this patch (PR #71 verifier run 1, finding 3): D13 (R4 and the Interfaces paragraph name every `base_ref_*` and `automatic_base_change*` event at or after the waiver's second, and the no-time case `waiver-timeline-unknown`); D19 (REQ-313 and REQ-385 in `implements:`); Review Focus 5 (that `tests/governance/test_reviews_use_slugs.sh` reads `docs/examples/`); R10's account of the documents an instance inherits; and the Maintainer checklist's M6 article-citation step. This patch applied D1's sentence, D3, D14's wording, D15, D17's precisions, R10's slug-scan sentence and Build 2's two accepted readings. All five were applied by amendment D's PR #75 (2026-10-04): this paragraph is kept as history.

**Verified against:** 2026-10-03 @ main `fbd432a` (worktree `.claude/worktrees/p7`, branch `design/factory-v3-2-p7`); every `file:line` anchor below was checked there. Revised the same day after the design PR's fresh-eyes review (23 findings; R17, R18 added; Amendment C's Step A5): every anchor the review named was re-checked at `fbd432a` — `test_release_sign.sh:229-234`, `README.md:541-546`, `CLAUDE.md:108`, `test_threat_model_current.sh:213`, `:359`, `:459-469`, `test_release_python.sh:46-56`, `:159`, `test_first_run.sh:58-72`, `run-security-floor.sh:65`, `tests/governance/lib/check.sh:49-125`, `test_next_prs.sh:24-46`, `:120-121`, `test_attestation.sh:460`, `:513-530`, `attestation.py:2298-2309`, `release.yml:460`, `:491`, `init-project.sh:684-694`. Polished the same day after the design workflow's reviews (design review, polish items 1–3), at `0cd6d23`: every anchor in Build 1's Tasks 1.1–1.4 Step 1 and Task 2.1's `CLAUDE.md` anchor re-read and corrected where it was wrong (`test_attestation.sh:511-516`, `:357`; `test_next_prs.sh:42`; `test_release_check.sh:98`; `review-gate.md:29-43`, `:48-61`; `GLOSSARY.md:424`, `:431`, `:448-451`; `test_release_sign.sh:153-157`; `test_release_apps.sh:191-202`; `README.md:305-307`; `test_release_python.sh:46-55`, `:51-54`, `:101-106`, `:175-184`, `:478-489`; `test_stack_packs.sh:15-16`, `:40-41`; threat model `:117`; `CLAUDE.md:108`, `:115-126`, `:128`), Task 1.1's red prediction measured, Task 2.1's inert check and Task 2.2's narrowed rule measured. **`/next` after this plan** (the same command, this file on disk; P6 R4's first field test — it passes): `state: design open-pr`; `why: spec 2026-09-25-factory-v3-2 resolved through docs/plans/2026-10-03-factory-v3-2-p7-plan.md's spec: (a follow-on design lane, P6 R4)`; `has_brainstorm is True` (`docs/specs/2026-09-25-factory-v3-2-brainstorm.md`), `has_spec is True`, `spec_has_tagged_reqs is True: REQ-322, REQ-341`, `arch_complete is True` (`check-architecture.sh` exit 0), `has_plan is True`, `analyze_ok is True` (linkage and traceability exit 0); `confirm: design-pr` (the template source's guided default — the factory runs `--profile engineer`, R6, and writes no `confirmed_by:`). Two readings for the maintainer: (a) `/next` derives `open-pr` before amendment C exists, because the kernel has no fact for a plan's on-branch section — that the design PR is opened only after the amendment-C commits is this workflow's convention, and the pushed head is what the verifier and the gates judge; (b) at this commit `check-covers.sh` fails for REQ-326, REQ-353 and REQ-371 alone (measured), as "Partial claims" says; `/next` does not run it. Amendment D's dated corrections (2026-10-04; BL-041) were checked on branch `design/amendment-d` (worktree `.claude/worktrees/amend`, cut from main `7cda6aa`): `attestation.py`'s `_is_base_event` and `classify`, the tauri instance's inherited documents, `run-quality-gates.sh`'s section numbers.

**Hits (H1–H13's grep, measured with `git grep -nE "P7|amendment C|2026-10-12|v3\.3|REQ-326|REQ-353|REQ-391|REQ-392|REQ-371" -- constitution.md .claude scripts docs/architecture docs/GLOSSARY.md README.md CLAUDE.md tests/governance`: 59 hits in 8 files; `constitution.md`, `scripts/`, `README.md` and `CLAUDE.md` have none):**

| Where | Hit | Owner or reason kept |
|---|---|---|
| `.claude/rules/review-gate.md:70` | `pull_request_target` "deferred to the P7 retrospective" | Task 1.2 → "proposed in `docs/BACKLOG.md` (BL-012)" |
| `.claude/rules/review-gate.md:74` | waiver base binding "proposed for P7/amendment C (P6 R8)" | Task 1.2 (R4 delivers it) |
| `docs/GLOSSARY.md:451` | the same, in the Waiver entry | Task 1.2 |
| threat model `:118` (dfe-6), `:126` (dfe-14) | the short-name convention residual, "expires: 2026-10-12, when the P7 retrospective reviews it" | Task 1.6 (re-accepted to 2026-12-15, BL-007) |
| threat model `:124` (dfe-12) | three residuals "expires: 2026-10-12": the TOFU caveat (the forged-anchor residual), the Boundary residual and the Tagged-tree residual ("accepted with the Boundary residual") | Task 1.6 (the TOFU caveat re-accepted, BL-023; the Boundary residual closed at `v3.2.0`, R9; the Tagged-tree residual re-accepted, BL-013 — it is a property of every tag, not of the boundary, so `v3.2.0` does not close it) |
| threat model `:125` (dfe-13) | the Dependabot residual, "expires: 2026-10-12" | Task 1.6 (re-accepted, BL-014) |
| threat model `:126` (dfe-14), `:211` | "amendment C (P7, REQ-353) rewrites (P6 R10)" | amendment-C step (the settled clause) |
| threat model `:198` | the open-medium residual, "Proposed for amendment C / P7" | amendment-C step (not adopted: a REQ-322 kernel and ADR-002 change → BL-002) |
| threat model `:202` | the waiver residual, "proposed for P7/amendment C (P6 R8)" | Task 1.2 (R4 closes it; a narrower residual stays: a legacy waiver's timeline read) |
| threat model `:208`–`:216` | seven residuals "expires: 2026-10-12, re-reviewed at the P7 retrospective" (`:208`, `:209`, `:210`, `:212`, `:214`, `:215`, `:216`; `:211` and `:213` carry none); `:209` "P7 owes `--no-deps` with the hashed `requirements.txt`…"; `:210` "P7's habit-tracker is tauri" | Task 1.4 (`:209` closed); Task 1.6 (`:210` kept as a fact, re-dated; the others re-accepted) |
| `tests/governance/test_threat_model_current.sh:21`, `:301`, `:367`, `:375`, `:423-425`, `:438`, `:446`, `:471-492` | pins on the residuals' 2026-10-12 expiry | Task 1.6 (rewritten first) |
| `tests/governance/test_threat_model_current.sh:213`, `:359`, `:459-469` (outside the grep) | the P6 sign-offs of dfe-12's TOFU caveat, dfe-13's residual and ten P6 residuals; `:465` finds one residual by the text "runs as root" | kept: R9's form appends, so every P6 sign-off stays; `:465`'s lookup follows the heading Task 1.4 gives the closed python image residual (Task 1.4) |
| `tests/governance/test_threat_model_current.sh:151-152`, `:232-239` | the open-medium proposal; dfe-14's "amendment C" clause | amendment-C step |
| `tests/governance/test_threat_model_current.sh:199-200` | the waiver residual's "P7/amendment C (P6 R8)" | Task 1.2 |
| `tests/governance/test_threat_model_current.sh:323-325` | the P6 plan's interim window (closed 2026-10-03), "due 2026-10-12" | kept: history — the P6 plan's closed row |
| `tests/governance/test_release_python.sh:478`, `:487` | the Dockerfile residual's expiry pin | Task 1.4 (the residual closes) |
| `tests/governance/test_review_gate_claims.sh:364-372`, `:414-418` | the waiver row's and glossary's "P7/amendment C (P6 R8)"; the no-"P6/amendment C" scan | Task 1.2 (`:364-372` flipped; `:414-418` kept: it forbids P6 forward references and still holds) |
| `tests/governance/test_spec_lifecycle.sh:150-155`, `:242` | pins on the spec's P6 entry ("REQ-353", "amendment C", "due no later than 2026-10-12") | kept: history — the P6 entry is the ship lane's and is never edited here |
| `tests/governance/test_constitution_amendment_b.sh:18-20` (the `impl/plan-N-<name>` loop item), `:78` | art-branch-as-state's `impl/plan-N-<name>` "for amendment C" | amendment-C step (the pin rewritten to `impl/plan-N-<plan slug>`) |
| `tests/governance/test_constitution_amendment_b.sh:101`, `:161-169`, `:211`, `:226-227` | pins on the P5 plan's "Open → P6/P7" text | kept: history — the P5 plan is executed and fenced |
| `README.md:75-76`, `:265`; `schemas/spec-template.md:73` (outside the grep) | "a later v3.2 plan" / "lands in v3.2" for `[verifiable]` | amendment-C step (→ v3.3) |

**Hand-offs (H1–H13), each owned or ruled out:** H1 → section "Amendment C" (R2, R3, R16); H2 → R5 (no change, BL-003); H3 → R6 (no change, BL-004); H4 → R4, Tasks 1.1–1.2; H5 → R3, R15 (M0; BL-006, BL-007, BL-008); H6 → R7 Task 1.3, Task 1.5 (staple line, Signing row, `CLAUDE.md:72`), R9 Task 1.6 and the Retrospective; H7 → R8, Task 1.4; H8 → R14 (BL-009, BL-010); H9 → R13, section "Amendment C"; H10 → R10, R11, Build 2, M1–M8; H11 → R12, Task 2.1, M9; H12 → section "Retrospective"; H13 → R1.

## Global Constraints

- **Where:** only the worktree `.claude/worktrees/p7` (this branch) and the builds' own worktrees; never the main checkout, never `.claude/worktrees/p6`. No `git stash`, no history rewrite except R1's force-push of an unattested build head, no tag, no write to GitHub from an agent (read-only `gh` calls are fine, each prefixed `GH_TOKEN="$(gh auth token --user kpingali123)"`; never `gh api -X/--method PUT|POST|PATCH|DELETE`). Merges, waivers, tags and repository settings are the user's.
- **The ship lane's files are untouched:** no edit to `docs/security/`, `docs/releases/` or the spec's P6 `amended:` entry from this branch or either build. The demo follow-up (M8) and REQ-392's record (M9) are the maintainer's PRs after the ship lane merges.
- **Constitution:** no `constitution.md` change outside the section "Amendment C" (on this branch). A build that finds an article wrong records it for the retrospective (a BL id via the retrospective), never edits the article.
- **Test first (`art-test-first`, `.claude/rules/tdd.md`):** each task's test changes come first, run red, then the change, then green; governance tests in `tests/governance/test_*.sh` are the test layer for `constitution.md`, the rule files, `scripts/`, `.claude/`, `.github/` and the stack packs. New checks go **above** `finish`. Every new check carries a `# Covers: REQ-NNN` line naming a REQ this plan claims (or a REQ the touched file already covers). A pin on a document `scripts/factory-only.txt` fences out of instances (the spec, the threat model, the plans, the reviews, ADR-003, this plan, `docs/examples/README.md` once fenced) goes through `factory_doc_ck`. A governance test never copies a template-only file (`scripts/template-pack.yml`, `scripts/factory-only.txt`, `stacks/`, the factory's documents) into an instance fixture (P6's first instance regression). A `# Covers:` line outside `tests/governance/` never cites a factory REQ (P6's second).
- **Every final review runs the new and changed tests inside a scaffolded instance** (P6's lesson): each build's whole-build task copies the template (`copy_template`), runs `init-project.sh` for each stack its files touch (`SPECFLOW_NO_SCAFFOLD=1` for tauri and flutter), and runs each new or changed governance test there; an instance SKIP is printed, never silent.
- **No kernel change:** `state.py`, `records.py`, `disposition.py`, `verification/` untouched — checked by `git diff refs/remotes/origin/main --stat` in each whole-build task.
- **Gate code:** `attestation.py`'s classifier, `run-verifier.sh`, `release-sign.sh`, `release-image.sh`, `init-project.sh` and model-instruction Markdown (`.claude/**`, `CLAUDE.md`) are gate code a human reads; each PR body lists them under **Gate code**.
- **Commits:** every subject cites a REQ id; every body ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. The gates: `PATH="$HOME/.venvs/factory-tools/bin:$PATH" bash scripts/run-quality-gates.sh` (about 3 minutes; log under `$TMPDIR`); the new tests keep the gates inside P6 R21's three-minute budget (docker cases opt-in, `SPECFLOW_DOCKER=1`).
- **Expiries:** the residuals expiring on 2026-10-12 are re-reviewed by Build 1 before that date, or re-dated by R9's fallback; the threat model governs between releases and `v3.2.0`'s released disposition is never edited (R18); the tauri skeleton re-pin stays due 2026-11-15 (`retrospective.md`), untouched here.

## Interfaces shared by the tasks

**Branches.** Design lane `design/factory-v3-2-p7` (this PR: the plan, then amendment C). Builds `build/factory-v3-2-p7-1`, `build/factory-v3-2-p7-2` (R1). Maintainer PRs after the builds: `patch/habit-tracker-example` (M6), `patch/demo-retag-followup` (M8), `patch/req-392-record` (M9, only if met). Retrospective `phase/retro-YYYY-MM-DD` (section "Retrospective").

**The waiver grammar and its judgement (Tasks 1.1, 1.2; R4).** First line, exactly one of:
- bound: `<!-- specflow-verifier:waive sha:<40 lowercase hex head> base:<40 lowercase hex base> -->`
- legacy: `<!-- specflow-verifier:waive sha:<40 lowercase hex head> -->`

then a rationale of at least 20 characters. Any other first line starting `<!-- specflow-verifier:waive` is `malformed`. Rules before the base, unchanged (maintainer, rule 1b's writing role, rationale, team-mode self-waiver). Then: bound → `bases[base]` (the same map `_marker_bases` builds for markers, now over waiver bases too) false → `waiver-base-mismatch`; legacy → `base_changes` (a list of ISO-8601 `created_at` times of the PR's `base_ref_changed` timeline events — corrected by amendment D's PR (2026-10-04; BL-041) to the `created_at` of every `base_ref_*` and `automatic_base_change*` timeline event) holds a time later than the waiver's `created_at` (corrected: at or after it, the same second counting; a time, or a waiver `created_at`, that is not an ISO-8601 UTC second reads `waiver-timeline-unknown`, as does an unreadable timeline) → `waiver-unbound-retargeted`, or is the string `"unknown"` (the timeline read failed) → `waiver-timeline-unknown`. All three refuse and never block. `classify(…, base_changes=None)`: `None` skips the timeline rule, exactly as `bases=None` skips the base rule (fixtures 1–102 and the `classify` CLI, which have no repository). `pr_attestation` reads the timeline (`gh_json(f"repos/{repo}/issues/{pr}/timeline")`, paginated like the comments read) only when some comment's first line is a legacy waiver for the head, and passes `[]` for a commit-level judgement (`pr=None`). The fixture runner (`attestation.py fixture <file>`) passes `context["base_changes"]` when the key is present. `release-check`'s FAIL line for a merged PR refused as `waiver-unbound-retargeted` or `waiver-timeline-unknown` appends the remedy: `; remedy: a maintainer posts on PR #<n> <!-- specflow-verifier:waive sha:<head> base:<the merge's first parent> --> with a rationale` (R4).

**Entitlements (Task 1.3; R7).** As R7. The message names each refused key in sorted order and the committed file by its repository-relative path (`the pack's entitlements.plist` for the fallback). Exit codes unchanged: 2 usage or missing input, 1 any refusal or tool failure.

**The python image (Task 1.4; R8).** Skeleton `requirements-runtime.in` (a comment line naming its purpose) and `requirements-runtime.txt` (the uv header, no requirement). Dockerfile, in order: the pinned base (unchanged digest), `WORKDIR /app`, a system user `app` with uid and gid 10001 and no home, `COPY requirements-runtime.txt /tmp/`, the hashed `--no-deps` install of it, `COPY dist/*.whl /tmp/`, the wheel `--no-deps --no-index`, `pip check`, the temporary files removed, `USER 10001`, `CMD ["python", "-m", "__PKG__"]`. `release-image.sh build`: the context holds exactly `Dockerfile`, `requirements-runtime.txt` and `dist/<the one wheel>`, the first two from `git show <RELEASE_COMMIT>:<path>`. `deploy.sh` `rollback`'s nothing-runs message: `rollback: no running <name> container to roll back from; deploy an earlier release by hand: scripts/deploy-local.sh deploy <X.Y.Z>`.

**The example (Task 2.1; R10).**
```
docs/examples/README.md                  (factory-only: the index, the habit-tracker walk's checklist M1–M6, REQ-392's record)
docs/examples/habit-tracker/README.md    (ships to tauri instances: what this is, its provenance, the layout, the evidence
                                          it holds once walked, its status — no maintainer instructions)
docs/examples/habit-tracker/docs/...     (after M6: the instance's docs/ tree, as committed in the instance at its Release)
docs/examples/habit-tracker/transcripts/NN-<where>.txt   (after M6: every /next output, NN two digits in run order,
                                          <where> the branch with / replaced by _, e.g. 03-design_habit-tracker.txt)
```
`README.md`'s status line is exactly `Status: pending the maintainer's walk (REQ-391).` until M6, then `Status: walked on YYYY-MM-DD from <v3.2.0|fbd432a>; Release: <URL>.` The manifest subsection in `CLAUDE.md`:
```
### habit_tracker (stack: tauri)

The second worked example (REQ-391): a macOS habit tracker taken through the lanes path in `profile: guided`, `solo: true`,
in a throwaway instance repository, to a GitHub Release whose unsigned bundle a tester opened on a second Mac. Documents
only — the instance's docs artifacts and the transcript of every next-step run; no second stack skeleton ships. Its home
and how it was made: `docs/examples/habit-tracker/README.md`; the tree: `docs/examples/habit-tracker/`.
```
Every backticked token containing a slash in a manifest subsection is a path init deletes in an instance of another stack (`examples.py`'s `PATH_RE`), so the subsection names no other path — a backticked `docs/` there would delete an instance's whole `docs/` tree; Task 2.1's "the example's paths are its README and its tree" check pins exactly two paths.

**The backlog (amendment C; R13).** `docs/BACKLOG.md`: a title, a paragraph (what it is; ids `BL-NNN` are never reused; the retrospective writes the decisions), then one entry per id:
```
### BL-001 — <title>
- **Source:** <where it was proposed: plan and ruling, residual, or retrospective>
- **Listed:** 2026-10-03
- **Proposal:** <one or two sentences>
- **Planned:** <optional: the P7 task that carries it>
- **Status:** open
```
and, once decided, `- **Decision:** <accepted (landed: <PR/commit>) | accepted (target: <PR/owner>) | rejected (<why>) | deferred (<trigger>)> — docs/retrospectives/<file>.md` with `Status: decided`. The ids listed at amendment C: BL-001 a `permissions.ask` rule (or hook) for `gh pr merge` and pushes to `main` (P5 H5, P5 R14); BL-002 open mediums count toward `medium_cap` and need an owner (P5 H9, P5 R16; the threat model's open-medium residual) — a REQ-322 kernel, Dafny and ADR-002 change; BL-003 a configured `next_version` override (P6 R5; P7 R5 proposes rejection); BL-004 a `profile:` for the template source (P6 R6; P7 R6 proposes the convention); BL-005 waiver base binding (P6 R8; planned: P7 Build 1, Tasks 1.1–1.2); BL-006 merge methods and the `release tags` ruleset (P6 R14; `allow_rebase_merge` until M0); BL-007 the ruleset also restricting `refs/tags/origin/**` (the short-name base residual, dfe-6, dfe-14); BL-008 GPG-signed release tags (P6 R27); BL-009 the python GHCR proof by an example instance (P6 R20, P7 R14); BL-010 the first-release registry measurement (the job token's read of a never-pushed package, the delete right, the read-back); BL-011 the Dockerfile freeze (P6 R20; planned: P7 Build 1, Task 1.4); BL-012 `pull_request_target` for `verifier.yml` (`review-gate.md`'s row); BL-013 `release.yml` running the classifier from the previous published release's tag (the residual on what `release.yml` binds; P6 Build 3 final review, finding 6); BL-014 whether the Dependabot exemption is still worth its residual (dfe-13); BL-015 `deploy-local.sh`'s cut-over and `rollback` with an explicit version (PR #57 verifier run 1, finding 5); BL-016 the Apple secrets on argv and the `release` environment (P6 R32 residual); BL-017 registry caches in the app bundle (P6 R15 residual); BL-018 the signed path exercised only by stubs until an instance's first signed release (P6 R33); BL-019 REQ-392's external product (Success Metric 3, P7 R12); BL-020 `v3.2.0`'s re-run path after the demo re-tag (P7 R11); BL-021 a script that runs the new tests inside a scaffolded instance in every final review (P6's lesson); BL-022 the factory's next release after P7 (`3.2.1` by hand or the derived `3.3.0`, P7 R5); BL-023 dfe-12's forged-anchor residual (a merger's key trusted from the release after the one that lists it). From the two prior retrospectives (R17; Source `02677f8^:docs/retrospectives/<file>`, proposal number): BL-024 PLAN-phase no-code reminders in `/architecture` and the writing-plans skill (2026-05-28 #5; absorbed in part by REQ-380); BL-025 TDD evidence in implementer reports (2026-05-28 #6; in part REQ-321); BL-026 a sequential-chain verifier mode (2026-05-28 #8; in part REQ-395); BL-027 a legacy-file inventory when a plan tightens a gate (2026-05-28 #10); BL-028 `run-verifier.sh`'s wrong-branch guard (2026-06-09 #1; absorbed by REQ-310); BL-029 a stacked-PR merge protocol (2026-06-09 #2; `review-gate.md` step 6, REQ-395); BL-030 recorded verdict waivers (2026-06-09 #3; REQ-382, REQ-311); BL-031 `/release` delegating to `verify-release.sh` (2026-06-09 #4; REQ-324); BL-032 `extends`/`extended_by` symmetry in `test_spec_lifecycle.sh` (2026-06-09 #5); BL-033 the `v0.0.1-demo` re-tag, signed (2026-06-09's carried open item; planned: M7–M8, R11). An entry a v3.2 REQ delivers carries an `**Absorbed:**` line and stays open until the retrospective decides it.

**The spec's P7 entry (amendment-C step; R16).** One YAML list item after the P6 entry, starting `- "P7 design lane (lanes; docs/plans/2026-10-03-factory-v3-2-p7-plan.md): constitution amendment C (REQ-326, REQ-353; REQ-371) lands with this PR` and naming, in order: amendment C's edits per article (each article's "How to apply" names its enforcing files or says convention (no mechanism); art-release-readiness's shipped definition and P6 R10's two clauses settled; SSH-only signing (P6 R27); art-branch-as-state's impl/plan-N-<plan slug>; art-formal-verification's extraction to v3.3; art-naming-tagging's docs-wide slug check and BL-NNN); the readings — REQ-326 (R2(c)): a named scripts/*.sh is executable, a module under scripts/lib/ need only exist; Success Metric 2 measured on constitution.md; REQ-371 (R13): the backlog lands with amendment C, an instance gets an empty one; REQ-382 (R4): its As amended by P7 sentence; REQ-351 (R8): the image installs a hash-pinned runtime lock and runs as a non-root user; REQ-391 (R10, R11): maintainer-driven, from v3.2.0, documents only, the re-tag after v3.2.0's Release; REQ-392 (R12): what met looks like and where it is recorded; REQ bodies unchanged except REQ-382's. REQ-382's sentence, appended to its body: "As amended by P7 (R4): a waiver may name the PR's base — `<!-- specflow-verifier:waive sha:<head> base:<base> -->` — and is then judged by the marker's base rule, refused as `waiver-base-mismatch` (never blocking) when that base gives the head another merge base than the PR's current base; a waiver without `base:` is accepted only while the PR's timeline shows no base change after it was posted (`waiver-unbound-retargeted`; an unreadable timeline refuses it, `waiver-timeline-unknown`); a commit-level waiver on a direct push has no timeline and a bound one names the commit's first parent."

## Amendment C — on this branch, after this plan, before the builds (REQ-326, REQ-353; REQ-371)

Executed by the next step of this workflow on `design/factory-v3-2-p7`, P5's amendment-B precedent: tests first (every superseded pin rewritten, never deleted), red, the constitution and its companions, green, one commit for the tests and one for the edits. The design PR carries the plan and this.

**Files:** `constitution.md`; `tests/governance/test_constitution_articles.sh`, `tests/governance/test_reviews_use_slugs.sh`, `tests/governance/test_constitution_amendment_c.sh` (new), `tests/governance/test_constitution_amendment_b.sh`, `tests/governance/test_review_gate_claims.sh`, `tests/governance/test_threat_model_current.sh`, `tests/governance/test_backlog.sh` (new); `docs/BACKLOG.md` (new), `templates/BACKLOG.md` (new), `scripts/init-project.sh` (writes `docs/BACKLOG.md` from the template after the fence, before the first commit), `.claude/commands/retrospective.md`, `docs/retrospectives/README.md`; `README.md` (`:75-76`, `:265`), `schemas/spec-template.md` (`:73`); `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` (`:126` dfe-14's clause, `:198`, `:211`) — an architecture-artifact update; `docs/specs/2026-09-25-factory-v3-2-design.md` (the P7 entry and REQ-382's sentence, R16); `.claude/rules/review-gate.md` (one claim row — the review procedure itself, convention, naming `.claude/rules/review-gate.md` and `constitution.md` — so the file `art-review-gate`'s How to apply names is in the claim→file table `test_review_gate_claims.sh` reads; and, after the fresh-eyes review, the RELEASE exit gate's fallback condition at `:162`); `.claude/commands/release.md` (`:26`, `:29`: the fallback's condition) and `scripts/release-tag.sh` (`:34`, a header comment quoting the article) with `tests/governance/test_release_commands.sh` (`:45-53`, narrowed first; after the design review, polish item 2, the three also say what Builds 1–3 shipped — `release-tag.sh` refuses with no signer (exit 3) rather than falling back, the annotated path is the engineer's explicit `--annotated` with the fallback already on `main` (exit 4 otherwise), and the guided confirmation point is `/next`'s `unsigned-tag` — pinned in `test_release_commands.sh` first) — the fresh-eyes review's finding 21: the rule file that loads at every session start, `/release` and the script's header said "neither GPG nor SSH signing verifiably available", which tells a maintainer holding only a GPG key to sign with it, and `release.yml` then refuses that tag.

**The settled sentences.** Each replaces the article's text named; everything not named stays byte-identical.

- **`art-specification-primacy`, How to apply:** "**How to apply:** a PR that changes a source file under the stack pack's `source_roots` cites a `REQ-NNN` in one of its commits or in its body — `scripts/check-test-first.sh`, a step of the `gates` job in `.github/workflows/ci.yml`; every REQ a plan's `implements:` claims is defined by that plan's spec (`scripts/check-traceability.sh`) and cited by a test (`scripts/check-covers.sh`), both in gates section 6 of `scripts/run-quality-gates.sh`. That the code does what the cited REQ says is the verifier's code mode (`.claude/skills/verifier/SKILL.md`), a review, not a mechanism."
- **`art-branch-as-state`, body:** `impl/plan-N-<name>` → `impl/plan-N-<plan slug>` (N the plan's `## Build N` section, as `review-gate.md`, `CLAUDE.md`, README and the PR template already say). **How to apply:** "**How to apply:** every phase transition is a PR that reaches `main`, directly or stacked on an open phase PR (REQ-395); both paths' branch names and the lane-to-phase mapping are listed in `.claude/rules/review-gate.md`, and `/next` derives the state from branches, PRs and the tree alone (`scripts/next.sh`, its kernel `scripts/lib/specflow/state.py`). `scripts/configure-repo.sh` requires a PR for `main` where GitHub's branch protection is available; where it is not (a free-plan private repository), and for an admin (`enforce_admins: false`), reaching `main` only through a PR is convention (no mechanism)."
- **`art-review-gate`, How to apply:** "**How to apply:** if a change touches `src/`, `verification/`, or a phase artifact, it goes through a PR; the required `verifier` check (`.github/workflows/verifier.yml`) passes only on an accepted marker for the PR's head (the form `scripts/run-verifier.sh` writes; tamper-evident, not bound to a model run), a maintainer waiver, or the Dependabot exemption, as `scripts/lib/specflow/attestation.py` judges them, and `scripts/configure-repo.sh` requires the `gates` and `verifier` checks and the approval count where GitHub's branch protection is available; see `.claude/rules/review-gate.md`'s claim→file table for what enforces each part of this article."
- **`art-test-first`, How to apply:** "**How to apply:** every PR that adds source code under the stack pack's `source_roots` adds a test in the same commit or earlier in the branch — `scripts/check-test-first.sh` (a step of the `gates` job in `.github/workflows/ci.yml`), which proves that a matching test file gained a line, not that the test exercises the change; that pairing is the verifier's code mode (`.claude/skills/verifier/SKILL.md`), and `.claude/rules/tdd.md` is the rule each session loads."
- **`art-formal-verification`, body:** "Runtime-contract extraction for `[verifiable]` is deferred to v3.2 (v3.1 spec Open Question #1a)." → "Runtime-contract extraction for `[verifiable]` is deferred to v3.3 (the v3.2 spec's Scope, REQ-326; first deferred by the v3.1 spec's Open Question #1a)." **How to apply:** "**How to apply:** during IMPLEMENT, every `[verifiable]` or `[verifiable-model]` REQ a plan implements adds a `.dfy` file in `verification/` whose `// Proves:` header names it — `scripts/check-traceability.sh` (gates section 6) fails a claimed REQ with no proof, and gates section 2 of `scripts/run-quality-gates.sh` and the `gates` job of `.github/workflows/ci.yml` run Dafny on every proof (proofs present with Dafny missing fail); `[verifiable]` additionally adds a contract extraction step (v3.3+)."
- **`art-kernel-boundary`, How to apply:** "**How to apply:** `scripts/check-architecture.sh` (gates section 6; the rule in `scripts/lib/specflow/architecture.py`) fails an overview whose `kernel_modules[].req_map` misses a REQ it owes: every `[verifiable]` or `[verifiable-model]` REQ of its spec while no plan names that spec (the ARCHITECTURE PR), then every tagged REQ that a plan naming the spec implements — all of them for a plan without `implements:`. That each boundary-crossing dependency has a written justification in the overview is convention (no mechanism): no script reads for it, and the verifier's skill (`.claude/skills/verifier/SKILL.md`) does not ask for it — a reviewer who reads the overview is the only check." (revised after the design review, polish item 1: an earlier draft credited `.claude/skills/verifier/SKILL.md` with reading the justification, which it does not ask for.)
- **`art-threat-driven-security`, How to apply:** the four bullets stay; a fifth bullet is added after them: "- `scripts/check-security-disposition.sh` (gates section 7, replayed at the tag by `.github/workflows/release.yml`; the decision function `scripts/lib/specflow/disposition.py`, ADR-002) enforces the rules above for the version under release; `scripts/run-security-floor.sh` (gates section 5) runs the tool floor the review's `## Tools run` records, and `scripts/check-suppressions.sh` requires every suppression to cite a live `SEC-NNN`; who assigns or confirms a severity is convention (no mechanism), except that in guided solo mode the verifier's full mode confirms severities and dispositions provisionally (`.claude/skills/verifier/SKILL.md`, REQ-389), a review, not a mechanism." The back-edge paragraph after the bullets stays.
- **`art-release-readiness`, body (REQ-353, R3):** "RELEASE produces three docs (`<version>-notes.md`, `<version>-migration.md`, `<version>-known-limitations.md`) on the release PR and, after the merge, a tag `v<version>` on that PR's merge commit — SSH-signed and verified against `.github/allowed_signers` (annotated permitted only when no signer at all — SSH, GPG or X.509 — is configured or held, in which case the fallback is recorded in `<version>-known-limitations.md` plus a follow-up to re-tag signed; a GPG-signed tag is refused at the tag, since the Release job holds no GPG keyring). A release is **shipped** when the Release job succeeded from that tag: the artifacts and `manifest.json` (one entry per file, with SHA-256 checksum + size) attached to the GitHub Release, the source manifest reproduced in CI from the tagged tree, the tag an ancestor of `main` and its signature verified (or, annotated, the fallback recorded in known-limitations), and (python) the image pushed; the laptop-built `dist/` is not the artifact of record. **The manifest's reproducible subset is transcribed into `<version>-notes.md`** (filename + sha256 + size for each artifact) so an auditor at the tag commit can check the Release's artifacts against it without re-running the hook. The known-limitations doc auto-includes every `accepted` or `deferred` finding from `docs/security/<version>-disposition.md`." **Why:** "**Why:** "tests pass" is not the same as "shipped"; the user needs the changelog, the migration steps, and a verifiable artifact built from the tag by a job, not on a laptop, whose checksums the tagged notes carry." **How to apply:** "**How to apply:** at PR time the RELEASE-phase gate (`scripts/verify-release.sh`, gates section 7 of `scripts/run-quality-gates.sh`) blocks merge if any of: gates non-zero; the notes' Artifacts rows differ from the reproducible subset it builds itself from the PR head's tree (in CI it never reads `dist/`, and a tracked `dist/` fails; where `/release` produced `dist/manifest.json` locally, each file's checksum and its transcription are checked too); known-limitations missing a SEC-NNN that is accepted or deferred; the disposition gate (`scripts/check-security-disposition.sh`) failing; the tag `v<version>` already exists (the release PR never carries its own tag). "Tag missing" is judged after the merge: a merged release whose merge commit has no tag, or whose tag is annotated without the fallback recorded in known-limitations, is incomplete. At the tag, the Release job (`.github/workflows/release.yml`, REQ-350) publishes nothing unless: the tagged commit is the newest first-parent commit of `main` that added `<version>-notes.md` (the ship PR's merge); its signature verifies against the anchored `.github/allowed_signers` (`scripts/lib/specflow/signers.py`) — or, unsigned, its fallback is recorded in `<version>-known-limitations.md` — and a GPG signature fails; the previous release, when there is one, is tagged and its tag reads as released (`signers.py previous`: a missing, lightweight, GPG-unverifiable, unanchored or otherwise refused previous tag fails here, where the PR-time check only warns on a missing or uncheckable one); every first-parent commit of `main` since the newest earlier release whose GitHub Release is published is judged by `scripts/lib/specflow/attestation.py`'s `release-check` — a merged PR by an accepted marker, a waiver or the Dependabot exemption, a direct push of code by a maintainer waiver on the commit, the commits before the pack's attestation boundary listed as skipped; `scripts/verify-release.sh --at-tag` passes on the tagged tree — the three documents, known-limitations, the Artifacts table's shape, the app-stack rules, the REQ claims and proofs, the previous release's tag, and the disposition gate replayed through `scripts/check-security-disposition.sh --at-tag`; and the reproducible artifacts the job rebuilds from the tagged tree equal the notes' rows (`scripts/verify-release.sh --artifacts-only`). Neither `--at-tag` nor `--artifacts-only` re-runs the gates: the job replays gates section 7 only, never sections 1–6 or `scripts/check-test-first.sh`. The next release PR's `verify-release.sh` fails a previous release tag that is lightweight, unsigned without the recorded fallback, badly signed or not an ancestor of its base, and warns when it is missing; the PR template's RELEASE checkbox asks the maintainer to confirm by hand what no job replays (convention): that the previous release's tag exists on its merge commit, and that the previous ship PR's `gates` and test-first checks were green at its merge." (The tag-time sentences revised after the design review, polish item 1, to say what `release.yml` and `verify-release.sh` do: the tag on the ship PR's merge, `signers.py previous`, `release-check`'s first-parent walk, what `--at-tag` replays, `--artifacts-only`'s comparison, neither re-running the gates.)
- **`art-repository-singleton`, How to apply:** "**How to apply:** convention (no mechanism): no PR introduces a remote submodule or splits a sub-project out as its own repository; the verifier and the human reviewer read for it."
- **`art-naming-tagging`, body:** the Tasks bullet becomes "- Tasks: `Task N.M` — the M-th task of a plan's `## Build N` section; a project may instead number tasks `TASK-NNN` (three-digit zero-padded, globally unique), the form `scripts/render_dashboard.py` reads from `# Task:` references." and a bullet is added after Findings: "- Backlog proposals: `BL-NNN` (three-digit zero-padded, globally unique, never reused) in `docs/BACKLOG.md` (REQ-371)." **How to apply:** "**How to apply:** `scripts/check-traceability.sh` (gates section 6) fails a `REQ-NNN` defined in two live specs and a duplicate `ADR-NNN` or `SEC-NNN`; `tests/governance/test_backlog.sh` fails a duplicate `BL-NNN`; `tests/governance/test_reviews_use_slugs.sh` fails, anywhere in `docs/` and in the files a session reads as instructions, an article cited by Roman numeral or by an `art-*` slug that `constitution.md` does not define."
- **`art-secrets-hygiene`, How to apply:** "**How to apply:** `.gitignore` excludes `.env*` (except `.env.example`); the security floor's gitleaks (`scripts/run-security-floor.sh`, gates section 5, over the full history with `.gitleaks.toml`) fails a committed secret anywhere outside its allowlist (`.env.example`, `docs/**/examples/`, test fixtures); Claude sessions and the verifier are denied `.env*` reads (`.claude/settings.json`, and `scripts/run-verifier.sh`'s deny list); a committed `.env` file holding no detectable secret is caught by review alone — convention (no mechanism)."
- **`art-retrospective-cadence`, How to apply:** "**How to apply:** after the `ship/<version>` (lanes) or `phase/release` (regulated) PR merges, create `phase/retro-YYYY-MM-DD`, run `/retrospective`, open a PR with the proposed-changes doc; apply changes in a follow-up PR if accepted. Running it is convention (no mechanism); once it runs, `/retrospective` (`.claude/commands/retrospective.md`) requires a decision line for every open id in `docs/BACKLOG.md`, and `tests/governance/test_backlog.sh` fails a retrospective that leaves one out."

The enforcement table after amendment C (Success Metric 2; what `test_constitution_articles.sh` checks): specification-primacy — `check-test-first.sh`, `check-traceability.sh`, `check-covers.sh` (+ review); branch-as-state — `review-gate.md`, `next.sh`/`state.py`, `configure-repo.sh` (+ convention where protection is absent); review-gate — `verifier.yml`, `run-verifier.sh`, `attestation.py`, `configure-repo.sh`, `review-gate.md`; test-first — `check-test-first.sh`, `ci.yml`, `tdd.md` (+ review); formal-verification — `check-traceability.sh`, `run-quality-gates.sh`, `ci.yml`; kernel-boundary — `check-architecture.sh`, `architecture.py` (the obligation as `_req_map_obligation` computes it) (+ convention for the boundary-crossing justification); threat-driven-security — `check-security-disposition.sh`, `disposition.py`, `run-security-floor.sh`, `check-suppressions.sh`, `release.yml` (+ convention for severity; + review: guided solo mode's provisional confirmation, `SKILL.md`, REQ-389); release-readiness — `verify-release.sh`, `run-quality-gates.sh`, `release.yml`, `signers.py`, `attestation.py`, `check-security-disposition.sh`, `allowed_signers` (+ convention for the checkbox); repository-singleton — convention; naming-tagging — `check-traceability.sh`, `test_backlog.sh`, `test_reviews_use_slugs.sh`; secrets-hygiene — `.gitignore`, `run-security-floor.sh`, `.gitleaks.toml`, `.claude/settings.json`, `run-verifier.sh` (+ convention); retrospective-cadence — `retrospective.md`, `BACKLOG.md`, `test_backlog.sh` (+ convention for the trigger). Twelve of twelve.

**The companions.** `README.md:75-76` → "The full `[verifiable]` tag additionally requires runtime-contract extraction, which is deferred to v3.3 — until then use the model tag (`art-formal-verification`)."; `README.md:265` → "Tag critical requirements `[verifiable-model]` in your spec (`[verifiable]`, which adds runtime-contract extraction, is deferred to v3.3)."; `schemas/spec-template.md:73` → "(contract extraction is deferred to v3.3 — until then use the model tag)". The threat model: dfe-14's and the release-gates residual's "a true-but-stale description of a weaker state that amendment C (P7, REQ-353) rewrites (P6 R10)" → "`art-release-readiness` states the CI comparison and the tag-time replay as settled text (amendment C, REQ-353)"; the open-medium residual's "Proposed for amendment C / P7, to count open mediums …" → "Not adopted by amendment C (it revises ADR-002 rule 3 and REQ-322's Dafny model, a kernel change): proposed for v3.3 as `docs/BACKLOG.md` BL-002, with P5 R16's REQ text: …" (the quoted REQ text kept; "P5 R16", since a bare "R16" here reads as this plan's R16). `.claude/commands/retrospective.md`: "Read:" gains "4. `docs/BACKLOG.md` — every deferred proposal, by id."; "Closing the loop" gains, as its first sentence: "Walk every id `docs/BACKLOG.md` lists with **Status:** open and record one line per id in `## Decisions on Prior Proposals`, exactly `- BL-NNN: accepted (landed: <PR/commit>) | accepted (target: <PR/owner>) | rejected (<why>) | deferred (<trigger>)`; in the same PR, mark each decided entry `**Status:** decided` with its `**Decision:**` line naming this retrospective's file, and add every new proposal this retrospective defers as a new `BL-NNN` (the next unused number; create `docs/BACKLOG.md` from `templates/BACKLOG.md` if it is absent)." — the existing walk of the previous retrospective's proposals stays. `docs/retrospectives/README.md` gains: "Deferred proposals live in `docs/BACKLOG.md` with an id each; every retrospective records a decision line per open id (REQ-371)." `templates/BACKLOG.md`: the title and paragraph of `docs/BACKLOG.md`, no entry. `init-project.sh`: after the fence, `cp templates/BACKLOG.md docs/BACKLOG.md` (an instance's backlog starts empty).

- [x] **Step A1: Write the failing tests.**

`tests/governance/test_constitution_articles.sh` (rewritten; the four existing checks stay, the How-to-apply check is added):
```bash
#!/usr/bin/env bash
# Verifies constitution.md has exactly 12 articles with unique slug fields matching ^art-[a-z0-9-]+$, and (REQ-326,
# amendment C) that every article's "How to apply" names the files that enforce it — each named file exists, each
# named scripts/*.sh is executable (P7 R2(c): a module under scripts/lib/ is imported, and need only exist) — or says
# "convention (no mechanism)". Runs in the template source and in every instance (the constitution ships).
# Covers: REQ-326
set -euo pipefail
FILE="constitution.md"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
ARTICLE_COUNT=$(grep -cE '^## [IVX]+ — ' "$FILE" || true)
[[ "$ARTICLE_COUNT" == "12" ]] || { echo "FAIL: expected 12 articles, found $ARTICLE_COUNT"; exit 1; }
SLUGS=$(grep -oE '^slug: art-[a-z0-9-]+$' "$FILE" || true)
SLUG_COUNT=$(echo "$SLUGS" | grep -c '^slug:' || true)
[[ "$SLUG_COUNT" == "12" ]] || { echo "FAIL: expected 12 slug fields, found $SLUG_COUNT"; exit 1; }
DUPES=$(echo "$SLUGS" | sort | uniq -d || true)
[[ -z "$DUPES" ]] || { echo "FAIL: duplicate slugs: $DUPES"; exit 1; }
python3 - "$FILE" <<'PY' || exit 1
import os, re, sys
t = open(sys.argv[1]).read()
arts = re.split(r"(?m)^## [IVX]+ — ", t)[1:]
ROOTS = {"scripts", ".github", ".claude", "tests", "docs", "schemas", "templates", "stacks", "src", "verification"}
ROOT_FILES = {".gitignore", ".gitleaks.toml", "constitution.md", "CLAUDE.md", "README.md"}
def named(how):
    out = []
    for tok in re.findall(r"`([^`]+)`", how):
        w = tok.split()[0]
        if re.search(r"[<>*]|YYYY", w) or w.startswith("/"):
            continue
        if w in ROOT_FILES or (w.split("/")[0] in ROOTS and "/" in w and "." in w.rstrip("/").split("/")[-1]):
            out.append(w)
    return out
bad = []
for a in arts:
    slug = re.search(r"(?m)^slug: (art-[a-z0-9-]+)$", a).group(1)
    m = re.search(r"\*\*How to apply:\*\*(.*?)(?=\n---\n|\Z)", a, re.S)
    if not m:
        bad.append(f"{slug}: no How to apply"); continue
    how, files = m.group(1), named(m.group(1))
    if not files and "convention (no mechanism)" not in how:
        bad.append(f"{slug}: names no enforcing file and does not say 'convention (no mechanism)'")
    for p in files:
        if not os.path.exists(p):
            bad.append(f"{slug}: names {p}, which does not exist")
        elif re.fullmatch(r"scripts/[^/]+\.sh", p) and not os.access(p, os.X_OK):
            bad.append(f"{slug}: {p} is not executable")
if bad:
    print("FAIL: " + "\nFAIL: ".join(bad)); sys.exit(1)
PY
echo "PASS: constitution.md has 12 articles with unique well-formed slugs; every How to apply names an existing enforcing file or says convention (no mechanism)"
```

`tests/governance/test_reviews_use_slugs.sh` — the Roman-numeral scan stays; the slug-existence scan is added above the final verdict:
```bash
# REQ-326 (amendment C; art-naming-tagging): docs-wide slug existence — every art-* slug cited anywhere in docs/ and in
# the files a session reads as instructions names an article constitution.md defines. A placeholder (<art-slug>,
# art-<kebab>, art-*) is not a citation. Same exemptions as above.
# Covers: REQ-326
if ! python3 - <<'PY'
import os, re, sys
slugs = set(re.findall(r"(?m)^slug: (art-[a-z0-9-]+)$", open("constitution.md").read()))
assert len(slugs) == 12, slugs
files = [f for f in ("constitution.md", "CLAUDE.md", "README.md") if os.path.isfile(f)]
for r in ("docs", ".claude", ".github", "schemas", "templates", "stacks"):
    for d, _, ns in os.walk(r):
        files += [os.path.join(d, n) for n in ns if n.endswith(".md")]
def exempt(f):
    if f.startswith("docs/reviews/archive-"):
        return True
    head = "".join(open(f, errors="ignore").readlines()[:20])
    return re.search(r"(?m)^status: superseded", head) is not None
bad = []
for f in sorted(files):
    if exempt(f):
        continue
    for i, line in enumerate(open(f, errors="ignore"), 1):
        for m in re.finditer(r"(?<![<\w-])art-[a-z0-9]+(?:-[a-z0-9]+)*", line):
            if m.group(0) not in slugs:
                bad.append(f"{f}:{i}: {m.group(0)}")
for b in bad:
    print(f"FAIL: cites an article slug constitution.md does not define: {b}")
sys.exit(1 if bad else 0)
PY
then
  VIOLATIONS=1
fi
```

`tests/governance/test_constitution_amendment_c.sh` (new):
```bash
#!/usr/bin/env bash
# REQ-326, REQ-353, REQ-371 (constitution amendment C, with P7's design PR): every article's How to apply names its
# enforcing files or says "convention (no mechanism)" (the counts are test_constitution_articles.sh's);
# art-release-readiness defines "shipped" as the Release job succeeding from the tag and states the CI comparison and
# the tag-time replay as settled text (P6 R10's two clauses gone); signing is SSH (P6 R27); art-branch-as-state says
# impl/plan-N-<plan slug>; art-formal-verification defers extraction to v3.3 everywhere a user reads it;
# art-naming-tagging gains the docs-wide slug check and BL-NNN; art-retrospective-cadence names the backlog. The spec
# records it.
# Covers: REQ-326
# Covers: REQ-353
# Covers: REQ-371
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=constitution.md
art() { awk -v s="slug: $1" '$0 == s {f=1} f && /^---$/ {exit} f' "$C" | tr '\n' ' ' | tr -s ' '; }
how() { art "$1" | sed -n 's/.*\*\*How to apply:\*\*//p'; }
ck "constitution keeps twelve articles; every How to apply names a file or says convention" bash tests/governance/test_constitution_articles.sh
while read -r slug files; do
  h=$(how "$slug")
  for f in ${files//,/ }; do ck "$slug's How to apply names $f" grep -qF -- "\`$f\`" <<<"$h"; done
done <<'EOF'
art-specification-primacy scripts/check-test-first.sh,.github/workflows/ci.yml,scripts/check-traceability.sh,scripts/check-covers.sh
art-branch-as-state .claude/rules/review-gate.md,scripts/next.sh,scripts/lib/specflow/state.py,scripts/configure-repo.sh
art-review-gate .github/workflows/verifier.yml,scripts/run-verifier.sh,scripts/lib/specflow/attestation.py,scripts/configure-repo.sh,.claude/rules/review-gate.md
art-test-first scripts/check-test-first.sh,.github/workflows/ci.yml,.claude/rules/tdd.md
art-formal-verification scripts/check-traceability.sh,scripts/run-quality-gates.sh,.github/workflows/ci.yml
art-kernel-boundary scripts/check-architecture.sh,scripts/lib/specflow/architecture.py
art-threat-driven-security scripts/check-security-disposition.sh,scripts/lib/specflow/disposition.py,scripts/run-security-floor.sh,scripts/check-suppressions.sh
art-release-readiness scripts/verify-release.sh,.github/workflows/release.yml,scripts/lib/specflow/signers.py,scripts/lib/specflow/attestation.py,scripts/check-security-disposition.sh
art-naming-tagging scripts/check-traceability.sh,tests/governance/test_backlog.sh,tests/governance/test_reviews_use_slugs.sh
art-secrets-hygiene .gitignore,scripts/run-security-floor.sh,.gitleaks.toml,.claude/settings.json,scripts/run-verifier.sh
art-retrospective-cadence .claude/commands/retrospective.md,docs/BACKLOG.md,tests/governance/test_backlog.sh
EOF
for s in art-repository-singleton art-secrets-hygiene art-retrospective-cadence art-branch-as-state art-threat-driven-security; do
  ck "$s's How to apply says convention (no mechanism) for what nothing enforces" grep -qF "convention (no mechanism)" <<<"$(how "$s")"
done
rel=$(art art-release-readiness)
ck "art-release-readiness: shipped means the Release job succeeded from the tag (REQ-353)" \
  grep -qF 'A release is **shipped** when the Release job succeeded from that tag' <<<"$rel"
for w in 'the artifacts and `manifest.json`' 'the source manifest reproduced in CI from the tagged tree' \
         'the tag an ancestor of `main` and its signature verified' '(python) the image pushed' \
         'the laptop-built `dist/` is not the artifact of record'; do
  ck "art-release-readiness's shipped clause says '$w'" grep -qF -- "$w" <<<"$rel"
done
ck "art-release-readiness: P6 R10 clause (a) — no shape-only CI check, no 'until the CI-built manifest'" \
  bash -c '! grep -qF "only the Artifacts table'"'"'s shape is checked" <<<"$1" && ! grep -qF "until the CI-built manifest" <<<"$1" && grep -qF "the reproducible subset it builds itself from the PR head'"'"'s tree" <<<"$1" && grep -qF "a tracked \`dist/\` fails" <<<"$1"' _ "$rel"
ck "art-release-readiness: P6 R10 clause (b) — no 'until release.yml replays', no 'only check between a merge'" \
  bash -c '! grep -qF "until \`release.yml\` replays" <<<"$1" && ! grep -qF "the only check between a merge and the next release PR" <<<"$1"' _ "$rel"
for w in 'publishes nothing unless' '`scripts/verify-release.sh --at-tag`' '`scripts/check-security-disposition.sh --at-tag`' \
         'replays gates section 7 only, never sections 1–6 or `scripts/check-test-first.sh`' 'what no job replays (convention)'; do
  ck "art-release-readiness's How to apply says '$w'" grep -qF -- "$w" <<<"$rel"
done
ck "art-release-readiness: SSH-signed against .github/allowed_signers; annotated only with no signer; GPG refused at the tag (P6 R27)" \
  bash -c 'grep -qF "SSH-signed and verified against \`.github/allowed_signers\`" <<<"$1" && grep -qF "no signer at all — SSH, GPG or X.509" <<<"$1" && grep -qF "a GPG-signed tag is refused at the tag" <<<"$1" && ! grep -qF "neither GPG nor SSH signing is verifiably available" <<<"$1"' _ "$rel"
bas=$(art art-branch-as-state)
ck "art-branch-as-state names impl/plan-N-<plan slug>, never impl/plan-N-<name>" \
  bash -c 'grep -qF "impl/plan-N-<plan slug>" <<<"$1" && ! grep -qF "impl/plan-N-<name>" <<<"$1"' _ "$bas"
fv=$(art art-formal-verification)
ck "art-formal-verification: extraction deferred to v3.3; no v3.2 promise left" \
  bash -c 'grep -qF "deferred to v3.3" <<<"$1" && grep -qF "(v3.3+)" <<<"$1" && ! grep -qF "deferred to v3.2" <<<"$1" && ! grep -qF "(v3.2+)" <<<"$1"' _ "$fv"
ck "README and the spec template defer [verifiable]'s extraction to v3.3, never 'a later v3.2 plan' or 'lands in v3.2'" \
  bash -c '! grep -qE "later v3\.2 plan|lands in v3\.2" README.md schemas/spec-template.md && grep -qF "v3.3" schemas/spec-template.md && [ "$(grep -c "deferred to v3.3" README.md)" -ge 2 ]'
nt=$(art art-naming-tagging)
ck "art-naming-tagging: Task N.M, TASK-NNN as the dashboard's form, BL-NNN in docs/BACKLOG.md" \
  bash -c 'grep -qF "\`Task N.M\`" <<<"$1" && grep -qF "\`TASK-NNN\`" <<<"$1" && grep -qF "\`BL-NNN\`" <<<"$1" && grep -qF "(REQ-371)" <<<"$1"' _ "$nt"
ck "templates/BACKLOG.md exists (an instance's backlog starts from it)" test -f templates/BACKLOG.md
SP=docs/specs/2026-09-25-factory-v3-2-design.md
p7=$(grep -F -- '- "P7 design lane' "$SP" 2>/dev/null || true)
for w in 'constitution amendment C (REQ-326, REQ-353; REQ-371)' 'convention (no mechanism)' 'impl/plan-N-<plan slug>' 'v3.3' \
         'scripts/lib/' 'Success Metric 2' 'REQ-382 (R4)' 'REQ-391 (R10, R11)' 'REQ-392 (R12)' "REQ bodies unchanged except REQ-382's"; do
  factory_doc_ck "the spec's P7 entry records '$w'" "$SP" grep -qF -- "$w" <<<"$p7"
done
factory_doc_ck "the spec's P7 entry follows the P6 entry; the P6 entry is not edited here" "$SP" \
  python3 - "$SP" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
i6 = next(i for i, l in enumerate(lines) if l.startswith('- "P6 builds'))
i7 = next(i for i, l in enumerate(lines) if l.startswith('- "P7 design lane'))
assert i7 > i6, (i6, i7)
PY
factory_doc_ck "REQ-382's body carries the As amended by P7 (R4) sentence" "$SP" \
  bash -c 'grep -E "^- \*\*REQ-382:\*\*" "$1" | grep -qF "As amended by P7 (R4): a waiver may name the PR'"'"'s base"' _ "$SP"
finish test_constitution_amendment_c
```

`tests/governance/test_constitution_amendment_b.sh` — the superseded pins rewritten, the rest unchanged: in the branch-name loop (`:18-20`) the item `'impl/plan-N-<name>'` becomes `'impl/plan-N-<plan slug>'`; the comment at `:77-78` becomes "# P5 lows patch (PR #48 verifier run 7, finding 4; REQ-340): the Build-lane heading says impl/plan-N-<plan slug>, as review-gate.md, CLAUDE.md, README and — since amendment C — the constitution do."; the check at `:46-47` ("the manifest is compared only where dist/manifest.json exists …") becomes, since amendment C supersedes it:
```bash
ck "art-release-readiness (superseded by amendment C, REQ-353): CI builds the reproducible subset itself; the local dist/ check stays" \
  bash -c 'grep -qF "the reproducible subset it builds itself from the PR head'"'"'s tree" <<<"$1" && grep -qF "where \`/release\` produced \`dist/manifest.json\` locally" <<<"$1" && ! grep -qF "manifest absent" <<<"$1"' _ "$rel"
```
and the word list at `:44` keeps `'REQ-350'` (the new text names `release.yml, REQ-350`).

`tests/governance/test_review_gate_claims.sh` — added above `finish`:
```bash
# Amendment C (REQ-326): art-review-gate's How to apply names files, and every one of them is in review-gate.md's
# claim→file table (the article and the rule agree on what enforces it).
# Covers: REQ-326
ck "every file art-review-gate's How to apply names is in review-gate.md's claim→file table" python3 - <<'PY'
import re
c = open("constitution.md").read()
a = c[c.index("slug: art-review-gate"):]; a = a[: a.index("\n---\n")]
how = a.split("**How to apply:**", 1)[1]
named = [t for t in re.findall(r"`([^`\s]+)`", how) if "/" in t and "." in t.split("/")[-1]]
assert named, how
table = "\n".join(l for l in open(".claude/rules/review-gate.md") if l.startswith("| "))
missing = [n for n in named if n not in table]
assert not missing, missing
PY
```

`tests/governance/test_threat_model_current.sh` — `:151-152` becomes:
```bash
  ck "the open-medium residual: not adopted by amendment C (a kernel change), proposed for v3.3 as BL-002" \
    bash -c 'grep -qF "Not adopted by amendment C" <<<"$1" && grep -qF "BL-002" <<<"$1" && ! grep -qF "Proposed for amendment C / P7" <<<"$1" && ! grep -qF "P5 backlog" <<<"$1"' _ "$rr"
```
and in `:237-239`'s word list `"amendment C"` stays and the scan gains `! grep -qF "true-but-stale" <<<"$1"`, with a twin check on dfe-14's row:
```bash
factory_doc_ck "dfe-14 and the release-gates residual: art-release-readiness states the CI comparison and the replay as settled text (amendment C)" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'for l in "$(grep -F "| dfe-14 |" "$1")" "$(grep -F -- "- **Release gates run at PR time and are replayed at the tag**" "$1")"; do grep -qF "settled text (amendment C, REQ-353)" <<<"$l" && ! grep -qF "amendment C (P7, REQ-353) rewrites" <<<"$l" || exit 1; done' _ "$TM"
```

`tests/governance/test_backlog.sh` (new):
```bash
#!/usr/bin/env bash
# REQ-371: docs/BACKLOG.md lists every deferred proposal with an id (BL-NNN, unique, never reused — art-naming-tagging);
# each entry has a source, a listed date, a proposal and a status, and a decided one a decision line in the grammar
# naming the retrospective that decided it; every retrospective dated after an id was listed records one decision line
# for that id; /retrospective requires it; an instance starts from templates/BACKLOG.md with no entry.
# Covers: REQ-371
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
B=docs/BACKLOG.md
ck "docs/BACKLOG.md exists" test -f "$B"
ck "templates/BACKLOG.md exists and lists no entry" bash -c 'test -f templates/BACKLOG.md && ! grep -qE "^### BL-[0-9]{3}" templates/BACKLOG.md'
ck "every entry is well-formed; ids unique; decided entries name an existing retrospective" python3 - "$B" <<'PY'
import os, re, sys
t = open(sys.argv[1]).read()
ents = re.split(r"(?m)^(?=### BL-\d{3} — )", t)[1:]
ids = [re.match(r"### (BL-\d{3}) — \S", e).group(1) for e in ents]
assert len(ids) == len(set(ids)), [i for i in ids if ids.count(i) > 1]
assert ids == sorted(ids), ids
DEC = r"(accepted \(landed: [^)]+\)|accepted \(target: [^)]+\)|rejected \([^)]+\)|deferred \([^)]+\))"
for i, e in zip(ids, ents):
    for f in ("Source", "Listed", "Proposal", "Status"):
        assert re.search(rf"(?m)^- \*\*{f}:\*\* \S", e), (i, f)
    assert re.search(r"(?m)^- \*\*Listed:\*\* \d{4}-\d{2}-\d{2}$", e), i
    st = re.search(r"(?m)^- \*\*Status:\*\* (open|decided)$", e)
    assert st, (i, "status")
    d = re.search(rf"(?m)^- \*\*Decision:\*\* {DEC} — (docs/retrospectives/\S+\.md)$", e)
    assert (st.group(1) == "decided") == bool(d), (i, "decided needs exactly one Decision line")
    if d:
        assert os.path.isfile(d.group(2)), (i, d.group(2))
PY
ck "every retrospective dated after an id was listed records one decision line for it" python3 - "$B" <<'PY'
import glob, os, re, sys
t = open(sys.argv[1]).read()
listed = dict(re.findall(r"(?m)^### (BL-\d{3}) — .*?^- \*\*Listed:\*\* (\d{4}-\d{2}-\d{2})$", t, re.S))
DEC = r"(accepted \(landed: [^)]+\)|accepted \(target: [^)]+\)|rejected \([^)]+\)|deferred \([^)]+\))"
for r in sorted(glob.glob("docs/retrospectives/[0-9]*-*.md")):
    date = os.path.basename(r)[:10]
    body = open(r).read()
    sec = re.search(r"(?ms)^## Decisions on Prior Proposals\s*$(.*?)(?=^## |\Z)", body)
    for i, d in listed.items():
        if d < date:
            assert sec and re.search(rf"(?m)^- {i}: {DEC}", sec.group(1)), (r, i)
PY
R=.claude/commands/retrospective.md
ck "/retrospective reads docs/BACKLOG.md and requires one decision line per open id, in the grammar" \
  bash -c 't=$(tr "\n" " " < "$1"); grep -qF "docs/BACKLOG.md" <<<"$t" && grep -qF "one line per id" <<<"$t" && grep -qF -- "- BL-NNN: accepted (landed:" <<<"$t" && grep -qF "new \`BL-NNN\`" <<<"$t" && grep -qF "templates/BACKLOG.md" <<<"$t"' _ "$R"
ck "docs/retrospectives/README.md points at the backlog (REQ-371)" grep -qF 'docs/BACKLOG.md' docs/retrospectives/README.md
for w in 'gh pr merge' 'medium_cap' 'next_version' 'profile' 'base binding' 'ruleset' 'GPG' 'GHCR' 'never-pushed' 'Dockerfile' \
         'pull_request_target' 'REQ-392' 'v0.0.1-demo'; do
  factory_doc_ck "the factory's backlog lists the deferred proposal on '$w'" "$B" grep -qF -- "$w" "$B"
done
if ! instance; then
  W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
  D="$W/i"; copy_template "$D"
  ck "init: an instance's docs/BACKLOG.md is templates/BACKLOG.md (the factory's ids are not the instance's)" \
    bash -c 'cd "$1" && bash scripts/init-project.sh --name Py </dev/null >/dev/null 2>&1 && cmp -s docs/BACKLOG.md templates/BACKLOG.md' _ "$D"
  ck "…and the instance passes this test" bash -c 'cd "$1" && bash tests/governance/test_backlog.sh >/dev/null' _ "$D"
fi
finish test_backlog
```

- [x] **Step A2: Run them red.** `for t in constitution_articles reviews_use_slugs constitution_amendment_c constitution_amendment_b review_gate_claims threat_model_current backlog; do bash tests/governance/test_$t.sh; done` — expected: `test_constitution_articles.sh` FAILs naming seven articles whose How to apply names no file and says no convention today — `art-specification-primacy`, `art-test-first`, `art-formal-verification`, `art-kernel-boundary`, `art-repository-singleton`, `art-naming-tagging`, `art-retrospective-cadence` (measured: the parser above run on `fbd432a`'s constitution finds only `review-gate.md`, `RUBRIC.md`, `verify-release.sh` and `.gitignore` named); `test_constitution_amendment_c.sh` and `test_backlog.sh` FAIL (no amended text, no backlog); `test_constitution_amendment_b.sh` FAILs the rewritten `impl/plan-N-<plan slug>` and dist checks; `test_review_gate_claims.sh` FAILs the new check (no file named yet); `test_threat_model_current.sh` FAILs the two rewritten checks; `test_reviews_use_slugs.sh` passes (measured: no undefined slug today) — its check is the guard for later edits. Commit the tests: `test(amendment-c): pin amendment C's settled text, the docs-wide slug check and the backlog first (REQ-326, REQ-353, REQ-371)`.

- [x] **Step A3: Edit**, as intent: the twelve articles' settled sentences above; the companions; `docs/BACKLOG.md` (the 23 entries of Interfaces, "The backlog", each **Status:** open, BL-005 and BL-011 with their **Planned:** line); `templates/BACKLOG.md`; `init-project.sh`'s copy; `retrospective.md`; `docs/retrospectives/README.md`; the threat model's three sentences; the spec's P7 entry and REQ-382's sentence (R16).

- [x] **Step A4: Run green.** The seven tests above, then `bash tests/governance/test_spec_lifecycle.sh`, `bash tests/governance/test_init.sh`, `bash tests/governance/test_examples.sh`, then the gates (`PATH="$HOME/.venvs/factory-tools/bin:$PATH" bash scripts/run-quality-gates.sh > $TMPDIR/p7-amendC-gates.log 2>&1`, exit 0; `check-covers.sh` now passes for REQ-326, REQ-353, REQ-371). Re-run `bash scripts/next.sh --profile engineer --explain` and quote it in the commit body. Commit: `constitution: amendment C — every How to apply names its enforcer or says convention; shipped means the Release job succeeded from the tag; the backlog (REQ-326, REQ-353, REQ-371)`.
- [x] **Step A5: Revised after the design PR's fresh-eyes review** (findings 1, 2, 7, 8, 18–23; tests first, red, then the edits, then green; one commit, `constitution(p7): amendment C revised after review (REQ-326, REQ-353)`). The settled sentences above are the revised ones: `art-review-gate` (finding 18: an accepted marker — the form `run-verifier.sh` writes, tamper-evident, not bound to a model run —, a waiver, or the Dependabot exemption; the old "only on a marker `scripts/run-verifier.sh` wrote" claimed a control the classifier lacks and left out REQ-334), `art-kernel-boundary` (finding 8: the obligation as `architecture.py`'s `_req_map_obligation` computes it), `art-threat-driven-security`'s fifth bullet (finding 23: guided solo mode's provisional confirmation by the verifier's full mode, REQ-389, a review), `art-release-readiness` (finding 19: the annotated fallback is the one exception to "signature verified", in the shipped clause and at the tag, as `release.yml`'s tagsig step and `verify-release.sh --at-tag` accept it; finding 7: the disposition gate among the PR-time blockers, as the amendment-C commit `427afee` already had it). The tests, added above `finish`:

`tests/governance/test_constitution_amendment_c.sh` — the art-threat-driven-security row of the named-file table gains `.claude/skills/verifier/SKILL.md`, and:
```bash
ck "art-release-readiness's shipped clause names the annotated fallback as the exception to a verified signature" \
  grep -qF 'the tag an ancestor of `main` and its signature verified (or, annotated, the fallback recorded in known-limitations)' <<<"$rel"
ck "art-release-readiness's How to apply: at the tag the signature verifies or, unsigned, its fallback is recorded" \
  grep -qF 'its signature verifies against the anchored `.github/allowed_signers` (`scripts/lib/specflow/signers.py`) — or, unsigned, its fallback is recorded in `<version>-known-limitations.md`' <<<"$rel"
rg=$(how art-review-gate)
ck "art-review-gate's How to apply: an accepted marker (tamper-evident, not bound to a model run), a waiver, or the Dependabot exemption" \
  bash -c 'grep -qF "passes only on an accepted marker for the PR'"'"'s head (the form \`scripts/run-verifier.sh\` writes; tamper-evident, not bound to a model run), a maintainer waiver, or the Dependabot exemption" <<<"$1" && ! grep -qF "passes only on a marker \`scripts/run-verifier.sh\` wrote" <<<"$1"' _ "$rg"
kb=$(how art-kernel-boundary)
ck "art-kernel-boundary's How to apply: every tagged REQ while no plan names the spec, then what the plans implement" \
  bash -c 'grep -qF "every \`[verifiable]\` or \`[verifiable-model]\` REQ of its spec while no plan names that spec (the ARCHITECTURE PR)" <<<"$1" && grep -qF "a plan without \`implements:\`" <<<"$1" && ! grep -qF "REQ of its spec that a plan implements;" <<<"$1"' _ "$kb"
ck "art-threat-driven-security's How to apply: guided solo mode's provisional confirmation by the verifier's full mode (REQ-389)" \
  bash -c 'grep -qF "in guided solo mode the verifier'"'"'s full mode confirms severities and dispositions provisionally (\`.claude/skills/verifier/SKILL.md\`, REQ-389), a review, not a mechanism" <<<"$1"' _ "$(how art-threat-driven-security)"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT; copy_template "$W/t"
mkdir -p "$W/t/.claude/rules"; printf 'Cite Article %s here.\n' IV > "$W/t/.claude/rules/planted-roman.md"
ck "test_reviews_use_slugs.sh fails a Roman-numeral citation planted in a .claude/ rule" no bash "$W/t/tests/governance/test_reviews_use_slugs.sh"
rm -f "$W/t/.claude/rules/planted-roman.md"
ck "…and passes the same copy without it" bash "$W/t/tests/governance/test_reviews_use_slugs.sh"
```
`tests/governance/test_reviews_use_slugs.sh` (finding 20) — the Roman-numeral scan walks `roman_files` (`docs/**/*.md`, `constitution.md`, `CLAUDE.md`, `README.md`, and the Markdown under `.claude/`, `.github/`, `schemas/`, `templates/`, `stacks/` — the slug check's set), filtering `constitution.md`'s own `## IV — ` headings and `roman:` fields, with a `# Covers: REQ-326` line; measured red: the pre-revision script passes a copy with a Roman-numeral citation ("Cite Article" and the numeral four) planted in `.claude/rules/`, the revised one fails it.

`tests/governance/test_backlog.sh` (findings 1, 2, 22) — the decision-line check becomes `decision_lines ROOT`: a retrospective records **exactly one** line for each id still open at its date — listed before it and not decided by an earlier retrospective (the date of the file its Decision line names); fixture cases in a temporary root with two retrospectives (an id the first decided needs no line in the second: passes; the second missing the open id's line: refused; two lines for one id: refused; the deciding retrospective without its line: refused). And:
```bash
factory_doc_ck "the backlog lists every proposal the two prior retrospectives deferred or left undecided, by number" "$B" python3 - "$B" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
src = re.findall(r"(?m)^- \*\*Source:\*\* retrospective `02677f8\^:docs/retrospectives/(2026-05-28-v3-1-cutover|2026-06-09-enforcement-remediation)\.md`, (proposal #\d+|the carried open item)\b", t)
want = {("2026-05-28-v3-1-cutover", f"proposal #{n}") for n in (5, 6, 8, 10)} \
     | {("2026-06-09-enforcement-remediation", f"proposal #{n}") for n in (1, 2, 3, 4, 5)} \
     | {("2026-06-09-enforcement-remediation", "the carried open item")}
assert set(src) == want and len(src) == len(want), sorted(want ^ set(src))
for req in ("REQ-310", "REQ-395", "REQ-382", "REQ-324"):
    assert re.search(rf"(?m)^- \*\*Absorbed:\*\* .*{req}", t), req
PY
```
`tests/governance/test_release_commands.sh` `:45-53` (finding 21) — review-gate.md's RELEASE exit gate says "is created and signed on the merge commit, with SSH — annotated permitted only when no signer at all (SSH, GPG or X.509) is configured or held, the fallback recorded in known-limitations; a GPG-signed tag is refused at the tag"; `/release` says "if no signer at all — SSH, GPG or X.509 — is configured or held in this environment" and its fallback line "(no signer — SSH, GPG or X.509 — at tag time)"; `release-tag.sh`'s header "(art-release-readiness: no signer at all — SSH, GPG or X.509 — configured or held)"; none keeps "neither GPG nor SSH" (`# Covers: REQ-343, REQ-324, REQ-353`).

The edits: the constitution's four sentences; `docs/BACKLOG.md` BL-024 … BL-033 (R17) and the optional `**Absorbed:**` field in its and `templates/BACKLOG.md`'s paragraph; `review-gate.md:162`, `release.md:26,29`, `release-tag.sh:34`; the spec's P7 entry (the revised edits; REQ-371's reading of "prior retrospectives", R17) and REQ-382's sentence (the merged-PR remedy, R4).

**The design PR's body** lists under **Gate code**: `constitution.md`; `.claude/rules/review-gate.md` (the claim row and the RELEASE exit gate's fallback condition); `.claude/commands/retrospective.md`; `.claude/commands/release.md`; `scripts/init-project.sh` (the instance's empty backlog); `scripts/release-tag.sh` (a header comment only); the governance tests above; and under **Architecture-artifact updates**: the threat model's three sentences.

## Build 1: The gate and release leftovers — waiver base binding, the entitlements refusal, the python image, the surfaces, the expiring residuals (REQ-382, REQ-311, REQ-352, REQ-386, REQ-351, REQ-390, REQ-303, REQ-308 slices)

Cut `build/factory-v3-2-p7-1` from `main` after the design PR merges. Re-verify every anchor below at that `main` first (Build 2 may merge first; R1).

### Task 1.1: Waivers bind a base — the classifier, the fixtures, the printed waiver line (REQ-382, REQ-311; R4)

**Files:** `scripts/lib/specflow/attestation.py` (`WAIVER_RE` → the two forms; `_judge_rules`' waiver branch; `_marker_base` reads a waiver's base too; `classify`/`explain`/`_judge_all` gain `base_changes=None`; `pr_attestation` reads the timeline when a legacy waiver names the head, `[]` for `pr=None`; the fixture runner passes `context["base_changes"]`; the message at `:1679` prints the bound form; `release_check`'s FAIL line for a merged PR refused as `waiver-unbound-retargeted` or `waiver-timeline-unknown` names the remedy, R4); `scripts/run-verifier.sh` (`:512`, the printed waiver line gains `base:$base_oid`); `tests/governance/fixtures/attestation/103-waiver-bound-accepted.json` … `109-waiver-bound-base-malformed.json` (new); `tests/governance/test_attestation.sh` (the new checks; `:460`, the base-predates message's waiver line, rewritten to the bound form); `tests/governance/lib/check.sh` (the stub `gh` gains a `*/issues/*/timeline*` arm answering `$S/timeline.json`, else `[]` — without it the stub exits 64 on the new read, every legacy waiver driven through `check` reads `waiver-timeline-unknown`, and `test_attestation.sh:517-530` goes red); `tests/governance/test_next_prs.sh` (its own stub `gh` gains the same arm, `$S/timeline-<n>.json` else `[]`, and two `/next` cases); `tests/governance/test_release_check.sh` (the commit-level rule and the merged-PR remedy); `tests/governance/test_verifier_run.sh` (`:225`).

**Interfaces:** "The waiver grammar and its judgement" under Interfaces.

- [x] **Step 0: The timeline read under the workflows' token (R4; fresh-eyes review, finding 3).** **Measured 2026-10-04 UTC (M0b done; the local evening of 2026-10-03):** probe PR #67 (branch `probe/timeline-token`, closed unmerged, branch deleted), run 37169624336, under a workflow with `permissions: contents: read, issues: read, pull-requests: read` and the job's `GITHUB_TOKEN` as `GH_TOKEN`: `GET repos/Apps-Consultants/factory/issues/48/timeline` answered **HTTP 200**; the paginated `base_ref_changed` query returned `["2026-09-30T11:25:56Z"]`, exit 0 — **readable: R4's timeline rule stands.** The probe's run (01:58Z) finished before PR #65 merged (02:23Z). The read was measured under a `pull_request` event only: `release.yml`'s verify job holds the same read permissions, but the read under its tag-push event is not measured (PR #68 verifier run 1, findings 1–2; recorded by the P7 retrospective's documentation patch). Owner: kpingali123. Recovery (R4): a bound waiver naming the merge commit's first parent clears a refused legacy waiver at the tag. Pre-ship check: before the 3.2.1 tag the maintainer runs `scripts/release-tag.sh 3.2.1 --dry-run`, which runs `release-check` with the maintainer's token and so does not measure the workflow token; the tag-push read is measured by the first `release.yml` run itself, fail-closed: a refusal is `waiver-timeline-unknown`, recoverable by the bound waiver (PR #71 verifier run 1, finding 4). The probe was run by the agent on the maintainer's explicit instruction (2026-10-04), the one exception to "agents never push or open PRs" below. Before any code: the maintainer's draft-PR probe (M0b; P5 PR #49's precedent — agents never push or open PRs) runs, in a throwaway workflow with `permissions: contents: read, issues: read, pull-requests: read` (`verifier.yml`'s and `release.yml` verify job's), `gh api --paginate "repos/$GITHUB_REPOSITORY/issues/48/timeline" --jq '[.[] | select(.event == "base_ref_changed") | .created_at]'` and records the HTTP status and the answer (expected `["2026-09-30T11:25:56Z"]`, the read measured with the maintainer's token on 2026-10-03). The PR is closed unmerged; the run id goes in Build 1's PR body. If the read fails, R4's fallback applies (the timeline rule dropped, the residual re-accepted with BL-005) and the fixtures 105–108 and the timeline checks below are not written. *(The probe and its two outcomes, as written before the measurement: a throwaway branch `probe/timeline-token` from `main` with a one-step workflow (`on: pull_request`; `permissions: contents: read, issues: read, pull-requests: read`; the job's `GITHUB_TOKEN` as `GH_TOKEN`) reading `issues/<pr>/timeline` for a retargeted PR, opened as a draft PR, the run read, the PR closed unmerged, the branch deleted; readable → R4's timeline rule stands; unreadable → R4's fallback, the timeline rule dropped, the base binding kept, REQ-382's "As amended by P7" sentence revised by the owning PR (D2). Outcome: readable, see the lead above.)*
- [x] **Step 1: Write the failing tests.** The fixtures, generated once by this script (run from the repository root; commit the JSON it writes, never the script):
```python
import json
H, B, B2, P = "1" * 40, "3" * 40, "5" * 40, "4" * 64
def ctx(**k):
    c = {"head": H, "prompt_sha256": P, "solo": True, "pr_author": "alice", "required_mode": "full"}
    c.update(k); return c
def waiver(i, base=None, at="2026-10-05T10:00:00Z", rationale="Reviewed by hand: a maintainer-decided waiver."):
    line = f"<!-- specflow-verifier:waive sha:{H}" + (f" base:{base}" if base else "") + " -->"
    return {"id": i, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": at, "updated_at": at,
            "html_url": f"https://github.com/o/r/pull/7#issuecomment-{i}", "body": line + "\n" + rationale}
FX = {
 "103-waiver-bound-accepted": ("a waiver naming the PR's current base is accepted (R4)",
     ctx(bases={B: True}), [waiver(1, B)], {"state": "waiver", "reason": "accepted", "comment_id": 1}),
 "104-waiver-bound-base-mismatch": ("a bound waiver whose base gives the head another merge base is refused, never blocking",
     ctx(bases={B2: False}), [waiver(1, B2)], {"state": "none", "reason": "waiver-base-mismatch", "comment_id": None}),
 "105-waiver-unbound-no-retarget": ("a legacy waiver on a PR never retargeted after it is accepted",
     ctx(base_changes=[]), [waiver(1)], {"state": "waiver", "reason": "accepted", "comment_id": 1}),
 "106-waiver-unbound-retargeted": ("a legacy waiver posted before a base change is refused, never blocking",
     ctx(base_changes=["2026-10-05T11:00:00Z"]), [waiver(1)], {"state": "none", "reason": "waiver-unbound-retargeted", "comment_id": None}),
 "107-waiver-unbound-retarget-before": ("a base change before the legacy waiver was posted leaves it accepted",
     ctx(base_changes=["2026-10-05T09:00:00Z"]), [waiver(1)], {"state": "waiver", "reason": "accepted", "comment_id": 1}),
 "108-waiver-unbound-timeline-unknown": ("an unreadable timeline refuses a legacy waiver (fail closed), never blocking",
     ctx(base_changes="unknown"), [waiver(1)], {"state": "none", "reason": "waiver-timeline-unknown", "comment_id": None}),
 "109-waiver-bound-base-malformed": ("a waiver line whose base is not 40 lowercase hex is malformed",
     ctx(bases={}), [waiver(1, "ABC")], {"state": "none", "reason": "malformed", "comment_id": None}),
}
for name, (rule, c, comments, expect) in FX.items():
    json.dump({"rule": rule, "context": c, "comments": comments, "expect": expect},
              open(f"tests/governance/fixtures/attestation/{name}.json", "w"), indent=2)
```
(A refused, non-blocking comment alone reduces to `comment_id: null`, as `05-stale-sha.json`, `11-malformed.json` and `19-waiver-short.json` do — measured.) In `tests/governance/test_attestation.sh`, above `finish`:
```bash
# P7 R4 (REQ-382, REQ-311; dfe-2): waivers bind a base as markers do. A bound waiver is judged by the marker's base rule
# (waiver-base-mismatch); a legacy waiver stands only while the PR's timeline shows no base change after it
# (waiver-unbound-retargeted; waiver-timeline-unknown when the timeline cannot be read). Each refuses, never blocks.
# Covers: REQ-382
# Covers: REQ-311
for r in waiver-bound-accepted waiver-bound-base-mismatch waiver-unbound-no-retarget waiver-unbound-retargeted \
         waiver-unbound-retarget-before waiver-unbound-timeline-unknown waiver-bound-base-malformed; do
  ck "a fixture covers rule '$r'" bash -c 'ls "$1"/[0-9][0-9][0-9]-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
ck "109 or more fixtures" [ "$(ls "$FX"/*.json | wc -l)" -ge 109 ]
ck "a refused waiver never blocks: an older accepted APPROVE stands over a newer mismatched or retargeted waiver" python3 - "$ROOT/scripts/lib/specflow" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
H, B, B2, P = "1" * 40, "3" * 40, "5" * 40, "4" * 64
tail = "\n## SpecFlow verifier (full mode)\n\nNo findings.\nAPPROVE"
appr = a.make_marker(mode="full", sha=H, base=B, prompt_sha256=P, model="opus", verdict="APPROVE",
                     digest=a.digest(tail), origin="headless")
c1 = {"id": 1, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-05T09:00:00Z",
      "updated_at": "2026-10-05T09:00:00Z", "html_url": "u1", "body": appr + tail}
for line, kw in ((f"<!-- specflow-verifier:waive sha:{H} base:{B2} -->", {"bases": {B: True, B2: False}}),
                 (f"<!-- specflow-verifier:waive sha:{H} -->", {"bases": {B: True}, "base_changes": ["2026-10-05T11:00:00Z"]})):
    c2 = {"id": 2, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-05T10:00:00Z",
          "updated_at": "2026-10-05T10:00:00Z", "html_url": "u2", "body": line + "\nReviewed by hand: a maintainer-decided waiver."}
    r = a.classify([c1, c2], H, P, True, "alice", "full", **kw)
    assert r["state"] == "approve" and r["comment_id"] == 1, r
PY
ck "pr_attestation reads the timeline only for a legacy waiver naming the head: [] keeps it, a later base_ref_changed or a failed read refuses it" \
  python3 - "$ROOT/scripts/lib/specflow" "$G" "$GB" "$GH" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); os.chdir(sys.argv[2]); import attestation as a
GB, GH = sys.argv[3:5]
def w(line):
    return [{"id": 5, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-05T10:00:00Z",
             "updated_at": "2026-10-05T10:00:00Z", "html_url": "u5", "body": line + "\nReviewed by hand: a maintainer-decided waiver."}]
legacy = f"<!-- specflow-verifier:waive sha:{GH} -->"
bound = f"<!-- specflow-verifier:waive sha:{GH} base:{a._git_rev_parse(GB)} -->"
def run(comments, timeline):
    calls = []
    def gh(ep):
        calls.append(ep)
        if ep.endswith("/timeline"):
            if isinstance(timeline, Exception):
                raise timeline
            return timeline
        assert ep.endswith("/comments"), ep
        return comments
    r = a.pr_attestation(repo="o/r", pr=7, head=GH, base_ref=GB, pr_author="alice", gh_json=gh, commits=[], permissions={})
    return r, [c for c in calls if c.endswith("/timeline")]
ev = lambda at: {"event": "base_ref_changed", "created_at": at}
r, tl = run(w(legacy), [])
assert (r["state"], r["reason"]) == ("waiver", "accepted") and tl == ["repos/o/r/issues/7/timeline"], (r, tl)
r, _ = run(w(legacy), [{"event": "labeled", "created_at": "2026-10-05T12:00:00Z"}, ev("2026-10-05T09:00:00Z")])
assert r["state"] == "waiver", r
r, _ = run(w(legacy), [ev("2026-10-05T11:00:00Z")])
assert (r["state"], r["reason"]) == ("none", "waiver-unbound-retargeted"), r
r, _ = run(w(legacy), a.AttestationError("gh: Server Error (HTTP 502)", code=2))
assert (r["state"], r["reason"]) == ("none", "waiver-timeline-unknown"), r
r, tl = run(w(bound), [ev("2026-10-05T11:00:00Z")])
assert r["state"] == "waiver" and tl == [], (r, tl)
r, tl = run([], [])
assert tl == [], tl
PY
printf '[{"event": "labeled", "created_at": "2026-09-28T09:00:00Z"}]\n[{"event": "base_ref_changed", "created_at": "2026-09-28T11:00:00Z"}]\n' > "$S/timeline.json"
waiver alice OWNER; chk
ck "check: a legacy waiver whose PR timeline's second page holds a later base_ref_changed fails as waiver-unbound-retargeted (gh --paginate pages are flattened)" \
  bash -c '[ "$1" = 1 ] && grep -q "waiver-unbound-retargeted" <<<"$2" && grep -q "repos/o/r/issues/7/timeline" "$3"' _ "$rc" "$out" "$S/gh.argv"
rm -f "$S/timeline.json"; chk
ck "…with no timeline event the same waiver passes (the stub answers [])" [ "$rc" = 0 ]
ck "the classifier's waiver message prints the bound form, base included" \
  grep -qF 'specflow-verifier:waive sha:{head} base:{' "$ROOT/scripts/lib/specflow/attestation.py"
```
(The marker's tail and digest follow `make_marker` and `digest` as fixture `01-approve.json`'s body does; the implementer checks the form against that fixture.) In `tests/governance/test_verifier_run.sh` at `:225`: `ck "…explaining the waiver bootstrap with the base bound (REQ-382, P7 R4)" bash -c 'grep -qF "specflow-verifier:waive sha:" <<<"$1" && grep -qE "waive sha:[0-9a-f]{40} base:[0-9a-f]{40}" <<<"$1"' _ "$out"`. In `tests/governance/test_attestation.sh` `:460` becomes `ck "…giving the bound waiver line for this head" grep -qE "<!-- specflow-verifier:waive sha:$GH base:[0-9a-f]{40} -->" <<<"$out"`. (The `waiver` helper (`:511-516`) and `chk` (`:357`) are the file's own, and the legacy-waiver cases they drive are `:517-530`; the stub arm is check.sh's.)

In `tests/governance/test_next_prs.sh` — its stub `gh` gains, in its `api` case before that case's `*)` arm (`:42`; the outer `*)` at `:44` is another arm), `*/issues/*/timeline*) n=$(sed -E 's#.*/issues/([0-9]+)/timeline.*#\1#' <<<"$*"); f="$S/timeline-$n.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;`; its `comment` helper gains `waive:<BASE_REF>` (a bound waiver naming `git rev-parse <BASE_REF>`); and, after the `:120-121` waiver case:
```bash
# P7 R4 (REQ-382, REQ-385): /next uses the classifier's waiver rules — a legacy waiver followed by a retarget, or a bound
# waiver whose base gives the head another merge base, never reaches awaiting-merge.
# Covers: REQ-382
printf '[{"event": "base_ref_changed", "created_at": "2026-09-28T11:00:00Z"}]\n' > "$S/timeline-7.json"
prs "7 design/x main OPEN alice $HEAD_SHA"; comment waive; nx --explain
ck "a legacy waiver posted before a later base_ref_changed: never awaiting-merge, --explain names waiver-unbound-retargeted" \
  bash -c '! grep -q "^state: design awaiting-merge" "$1" && grep -qF "waiver-unbound-retargeted" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
rm -f "$S/timeline-7.json"; comment "waive:$(git -C "$D" rev-list --max-parents=0 HEAD)"; nx --explain
ck "a bound waiver whose base gives the head another merge base: never awaiting-merge, --explain names waiver-base-mismatch" \
  bash -c '! grep -q "^state: design awaiting-merge" "$1" && grep -qF "waiver-base-mismatch" "$1"' _ "$W/out"
```
(The bound waiver names the seed's root commit, an ancestor whose merge base with the head differs from `origin/main`'s; the implementer confirms it differs in this fixture.)

In `tests/governance/test_release_check.sh`, after R28's remedy cases (`:75-97`), with the file's own `rch`, `prs`, `$F/comments`, `$F/commits` and `$GHFX` (its stub `gh` answers `$GHFX/<endpoint with / as _>.json`, else `[]`):
```bash
# P7 R4 (REQ-382, REQ-311): a commit-level waiver has no timeline; a bound one is judged by the base rule against the
# commit's first parent — naming the parent passes, naming another commit is refused; a legacy one passes as before.
# Covers: REQ-382
cw() { python3 - "$F" "$C6" "$1" <<'PY'
import json, sys
F, c6, base = sys.argv[1:4]
line = f"<!-- specflow-verifier:waive sha:{c6}" + (f" base:{base}" if base != "-" else "") + " -->"
json.dump([{"id": 9, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T11:00:00Z",
            "updated_at": "2026-10-01T11:00:00Z", "html_url": f"https://github.com/o/r/commit/{c6}#commitcomment-9",
            "body": line + "\nPushed past protection during an outage; reviewed after the fact by the maintainer."}],
          open(f"{F}/comments/commit-{c6}.json", "w"))
json.dump([{"sha": c6, "author": {"login": "alice"}, "committer": {"login": "alice"}, "commit": {"verification": {"verified": False}}}],
          open(f"{F}/commits/commit-{c6}.json", "w"))
PY
}
cw "$C5"; rch "$C6"
ck "a bound waiver on the pushed commit naming its first parent: ok direct-push waiver" bash -c '[ "$1" = 0 ] && grep -q "^ok ${3:0:7} direct-push waiver" <<<"$2"' _ "$rc" "$out" "$C6"
cw "$C4"; rch "$C6"
ck "…naming another commit (an older first-parent commit): FAIL direct-push, waiver-base-mismatch" bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push .*waiver-base-mismatch" <<<"$2"' _ "$rc" "$out" "$C6"
cw -; rch "$C6"
ck "…a legacy waiver on the commit: ok, and no timeline is read for a commit" bash -c '[ "$1" = 0 ] && ! grep -q "/timeline" "$3"' _ "$rc" "$out" "$W/gh.log"
rm -f "$F/comments/commit-$C6.json" "$F/commits/commit-$C6.json"
# P7 R4, the remedy (fresh-eyes review, finding 15): a merged PR whose legacy waiver precedes a retarget FAILs, naming the
# remedy; a bound waiver posted on that PR naming the merge's first parent clears it.
python3 - "$F" "$H3" <<'PY'
import json, sys
F, h3 = sys.argv[1:3]
json.dump([{"id": 3, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T10:00:00Z",
            "updated_at": "2026-10-01T10:00:00Z", "html_url": "https://github.com/o/r/pull/3#issuecomment-3",
            "body": f"<!-- specflow-verifier:waive sha:{h3} -->\nReviewed by hand: a maintainer-decided waiver."}], open(f"{F}/comments/3.json", "w"))
PY
printf '[{"event": "base_ref_changed", "created_at": "2026-10-01T11:00:00Z"}]\n' > "$GHFX/repos_o_r_issues_3_timeline.json"; rch "$C5"
ck "a merged PR whose legacy waiver precedes a retarget: FAIL #3 none (waiver-unbound-retargeted), naming the bound-waiver remedy with the merge's parent" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL #3 none (waiver-unbound-retargeted)" <<<"$2" && grep -qF "remedy" <<<"$2" && grep -qF "base:$3" <<<"$2"' _ "$rc" "$out" "$C2"
python3 - "$F" "$H3" "$C2" <<'PY'
import json, sys
F, h3, parent = sys.argv[1:4]; p = f"{F}/comments/3.json"; c = json.load(open(p))
c.append({"id": 4, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-06T10:00:00Z",
          "updated_at": "2026-10-06T10:00:00Z", "html_url": "https://github.com/o/r/pull/3#issuecomment-4",
          "body": f"<!-- specflow-verifier:waive sha:{h3} base:{parent} -->\nRe-waived after the retarget: the merged diff was re-read."})
json.dump(c, open(p, "w"))
PY
rch "$C5"
ck "…a bound waiver on PR #3 naming its merge's first parent clears it: ok #3 waiver" bash -c '[ "$1" = 0 ] && grep -q "^ok #3 waiver" <<<"$2"' _ "$rc" "$out"
rm -f "$GHFX/repos_o_r_issues_3_timeline.json"
```
(These cases restore `$F/comments/3.json` to the APPROVE the file's setup wrote before its next case, exactly as `:98` empties it; the implementer places them where that holds — between `:97` and `:98`.)
- [x] **Step 2: Run red.** `bash tests/governance/test_attestation.sh` — four of the seven new fixtures FAIL: 103 and 104 read `malformed` (`WAIVER_RE` does not match the bound form) and 106 and 108 read `accepted`; 105, 107 and 109 already pass and pin outcomes R4 keeps — 105 and 107 a legacy waiver accepted, 109 a malformed base read `malformed` (measured 2026-10-03: the generator above run in a scratch directory, `attestation.py fixture` on each file at `0cd6d23`). The `pr_attestation` timeline check, the paginated-timeline check, the message checks and `:460` FAIL too; `bash tests/governance/test_verifier_run.sh` FAILs the `:225` check; `bash tests/governance/test_next_prs.sh` FAILs both new cases (today each waiver reaches `awaiting-merge`); `bash tests/governance/test_release_check.sh` FAILs the bound-waiver cases (a bound line is `malformed`) and the remedy case (a legacy waiver is accepted today).
- [x] **Step 3: Implement**, as intent: the two waiver forms; the base rule over waiver bases through the existing `bases` map; the timeline rule from `base_changes`; the read of `repos/<repo>/issues/<pr>/timeline` (paginated, `event == "base_ref_changed"`, its `created_at`) only when a legacy waiver names the head, an error → `"unknown"`; `[]` for `pr=None`; the bound form in both printed lines.
- [x] **Step 4: Run green**, plus `bash tests/governance/test_release_check.sh`, `bash tests/governance/test_next_prs.sh` and `bash tests/governance/test_release_tag.sh` (their legacy commit-level and PR waivers still accepted). **R28's preview, twice** (fresh-eyes review, finding 14): run `GH_TOKEN="$(gh auth token --user kpingali123)" python3 scripts/lib/specflow/attestation.py release-check --repo Apps-Consultants/factory --version 3.3.0 --tag-commit refs/remotes/origin/main --since v0.0.1-demo > $TMPDIR/p7-r28-before.txt` before Step 3 (read-only; on 2026-10-03 at `fbd432a` it printed 15 ok, 28 pre-transfer, 0 FAIL — "Measured") and the same command after Step 3 into `$TMPDIR/p7-r28-after.txt`; `diff` the two, and quote both summaries in the PR body. **If a PR the first run accepted is refused by the second** (a P5/P6 PR that was stacked, legacy-waived and later retargeted): the historical range is never re-judged by a release (`v3.2.0` fixes the next range's start, and #48, the one retargeted PR, merged under a waiver posted after its retarget — "Measured"), so no code changes for it; the PR body lists it with its timeline and waiver times, and the maintainer decides whether to post R4's remedy on it (a bound waiver naming its merge's first parent), which only a later preview reads.
- [x] **Step 5: Commit:** `attestation: waivers bind a base as markers do — waiver-base-mismatch, the legacy waiver's timeline rule (REQ-382, REQ-311)`.

### Task 1.2: The waiver's documents — review-gate.md, the glossary, the threat model; the /release follow-up on a patch PR (REQ-382; R4, R11) — architecture-artifact update

**Files:** `.claude/rules/review-gate.md` (step 4 `:29-43`, its grammar line `:32`: the bound grammar, and the remedy for a merged PR whose legacy waiver the tag-time re-check refuses — a bound waiver posted on that PR naming its merge commit's first parent (R4; fresh-eyes review, finding 15); step 6 `:48-61`: R4 changes what a retarget does to a waiver, so after "until a newer accepted `APPROVE` or waiver supersedes it." it says so — "A waiver is judged the same way since P7 (R4): a bound waiver whose base gives the head another merge base than the new base is refused (`waiver-base-mismatch`), and a legacy waiver (no `base:`) posted before the retarget is refused once the PR's timeline records the `base_ref_changed` (`waiver-unbound-retargeted`) — so post a bound waiver naming the new base after retargeting." (design review, polish item 3); the RELEASE exit gate's fallback condition at `:162` is amendment C's, already synced; the waiver row `:74`: "a waiver names a head only …" → the bound/legacy rule; `:70`: "`pull_request_target` is deferred to the P7 retrospective (P6 does not change `verifier.yml`)" → "`pull_request_target` is proposed in `docs/BACKLOG.md` (BL-012)"; "Patch tier": a sentence after "Does not qualify" — "The `/release` follow-up that records or removes a release's annotated-tag fallback line (`.claude/commands/release.md`) rides a `patch/<slug>` PR: a documents-only edit of a released known-limitations file the release rules permit."); `docs/GLOSSARY.md` (Waiver, `### Waiver` at `:424`: its grammar line `:431` and the head-only sentence `:448-451` become the bound grammar, the base rule, the legacy timeline rule and the merged-PR remedy); `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` (`:202`); `tests/governance/test_review_gate_claims.sh` (`:18`, `:364-372`); `tests/governance/test_threat_model_current.sh` (`:199-200`).

- [x] **Step 1: Write the failing tests.** In `test_review_gate_claims.sh`, `:18` becomes `ck "review-gate.md gives the bound waiver grammar" grep -qF 'specflow-verifier:waive sha:<40-hex head> base:<40-hex base>' "$R"`, and `:364-372` become:
```bash
# P7 R4 (REQ-382): a waiver binds a base as markers do; a legacy waiver stands only until a retarget after it.
# Covers: REQ-382
ck "waiver row: a bound waiver is judged by the marker's base rule; a legacy one is refused after a later retarget (P7 R4)" \
  bash -c 'for w in "waiver-base-mismatch" "waiver-unbound-retargeted" "waiver-timeline-unknown" "\`base_ref_changed\`"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done; ! grep -qF "proposed for P7/amendment C" <<<"$1"' _ "$wrow2"
ck "glossary Waiver: the bound grammar, the base rule, the legacy timeline rule; no P7/amendment C proposal" \
  bash -c 'b=$(awk "\$0==\"### Waiver\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " "); grep -qF "base:<40-hex base>" <<<"$b" && grep -qF "waiver-unbound-retargeted" <<<"$b" && ! grep -qF "P7/amendment C" <<<"$b"'
ck "review-gate.md step 4 and the glossary's Waiver: a merged PR's refused legacy waiver is cleared by a bound waiver naming the merge's first parent (P7 R4)" \
  bash -c 's=$(awk "/^4\\. If \`REQUEST_CHANGES\`/{f=1} /^5\\. /{f=0} f" "$1" | tr "\n" " "); b=$(awk "\$0==\"### Waiver\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " "); for x in "$s" "$b"; do grep -qF "first parent" <<<"$x" && grep -qF "waiver-unbound-retargeted" <<<"$x" || exit 1; done' _ "$R"
ck "review-gate.md step 6: a retarget refuses a legacy waiver posted before it and a bound waiver naming another merge base; post a bound one after (P7 R4)" \
  bash -c 's=$(awk "/^6\\. After merge/{f=1} /^This is the operational rule/{f=0} f" "$1" | tr "\n" " " | tr -s " "); for w in "waiver-base-mismatch" "waiver-unbound-retargeted" "post a bound waiver naming the new base after retargeting"; do grep -qF -- "$w" <<<"$s" || exit 1; done' _ "$R"
ck "review-gate.md: pull_request_target is BL-012, not 'deferred to the P7 retrospective'" \
  bash -c 'grep -qF "BL-012" "$1" && ! grep -qF "deferred to the P7 retrospective" "$1"' _ "$R"
ck "review-gate.md patch tier: the /release follow-up rides a patch/ PR (P7 R11)" \
  grep -qF 'The `/release` follow-up that records or removes a release'"'"'s annotated-tag fallback line' <<<"$(awk '/^## Patch tier/{f=1; next} /^## /{f=0} f' "$R" | tr '\n' ' ')"
```
In `test_threat_model_current.sh`, `:199-200` become:
```bash
factory_doc_ck "the waiver residual: base binding delivered (P7 R4); what stays is the legacy waiver's timeline read" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "- **A legacy waiver is bound to a head, not a base**" "$1"); grep -qF "P7 R4" <<<"$l" && grep -qF "base_ref_changed" <<<"$l" && ! grep -qF "proposed for P7/amendment C" <<<"$l" && ! grep -qF -- "- **A waiver is bound to a head, not a base**" "$1"' _ "$TM"
```
- [x] **Step 2: Run red.** Both tests FAIL on the new checks.
- [x] **Step 3: Edit**, as intent: the texts above (step 6's sentence among them); the threat model's residual heading becomes "**A legacy waiver is bound to a head, not a base**" (the pin above reads it by that heading) and says: since P7 (R4) a waiver may bind the base and is then judged as a marker is; a legacy waiver stands until the PR's timeline shows a `base_ref_changed` after it, refused once it does or when the timeline cannot be read; what remains is the timeline read itself (GitHub's record of a retarget) — a residual with no expiry (a property of the platform, not a deferral).
- [x] **Step 4: Run green.**
- [x] **Step 5: Commit:** `review-gate, glossary, threat model: the bound waiver and the legacy waiver's retarget rule; the /release follow-up rides a patch PR (REQ-382)`.

### Task 1.3: `release-sign.sh` signs only with the entitlements the project committed (REQ-352, REQ-386; R7)

**Files:** `scripts/release-sign.sh` (the header's entitlements paragraph; `sign_app`'s entitlements step: compare, refuse, sign with the committed set); `tests/governance/test_release_sign.sh`; `stacks/tauri/release/entitlements.plist` and `stacks/flutter/release/entitlements.plist` (their comments: the fallback is the committed set when the project names none; the embedded set is compared, never used); `stacks/tauri/store-checklist.md` (item 9); `tests/governance/test_release_apps.sh` (`:191-202`, the order pin "already embeds … bundle.macOS.entitlements … fallback" becomes the committed-set rule; `:188-189`, "the project's own … signs the app, the pack's file only", still holds and stays).

- [x] **Step 1: Write the failing tests.** In `test_release_sign.sh`, the comment and check at `:229-234` ("# The app's own entitlements … are kept" and "the app's own entitlements (codesign -d --entitlements :- on the unsigned app) sign it …") are replaced by the block below — `:153-157` (its fixture and the check "a Release.entitlements that is not a plist dictionary: exit 2", `:156-157`) is a different check and stays:
```bash
# P7 R7 (REQ-352, REQ-386; PR #58 verifier run 2): the app is signed with the entitlements the project committed, never
# with the set the untrusted build embedded; an embedded key the committed file does not grant (or grants another
# value) stops the script before anything is signed, naming the key and the file.
# Covers: REQ-352
# Covers: REQ-386
python3 -c 'import plistlib, sys; sys.stdout.buffer.write(plistlib.dumps({"com.apple.security.app-sandbox": True, "com.apple.security.files.user-selected.read-only": True, "com.apple.security.get-task-allow": True}))' > "$W/app-ent.plist"
fixture "$W/own" flutter habit-1.0.0-macos-arm64.zip
STUB_APP_ENT="$W/app-ent.plist" sign --stack flutter --dist "$W/own" --entitlements "$W/ent.plist"
ck "an embedded key the committed set lacks (the pack's file grants only network.client): exit 1, nothing signed, the keys and the file named" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^codesign --force" "$2" && grep -qF "com.apple.security.app-sandbox" <<<"$3" && grep -qF "com.apple.security.files.user-selected.read-only" <<<"$3" && grep -qF "entitlements.plist" <<<"$3" && ! grep -qF "get-task-allow" <<<"$(grep "does not grant" <<<"$3")"' _ "$rc" "$LOG" "$out"
mkdir -p "$W/fl/macos/Runner"
python3 -c 'import plistlib, sys; plistlib.dump({"com.apple.security.app-sandbox": True, "com.apple.security.files.user-selected.read-only": True, "com.apple.security.network.client": True}, open(sys.argv[1], "wb"))' "$W/fl/macos/Runner/Release.entitlements"
fixture "$W/own2" flutter habit-1.0.0-macos-arm64.zip
PROJ="$W/fl" STUB_APP_ENT="$W/app-ent.plist" sign --stack flutter --dist "$W/own2" --entitlements "$W/ent.plist"
ck "the embedded keys within the committed Release.entitlements: signed with the committed set (network.client too), get-task-allow never" \
  bash -c '[ "$1" = 0 ] && granted com.apple.security.app-sandbox com.apple.security.files.user-selected.read-only com.apple.security.network.client "!com.apple.security.get-task-allow"' _ "$rc"
python3 -c 'import plistlib, sys; sys.stdout.buffer.write(plistlib.dumps({"com.apple.security.app-sandbox": True, "com.apple.security.application-groups": ["X.group"]}))' > "$W/app-ent2.plist"
python3 -c 'import plistlib, sys; plistlib.dump({"com.apple.security.app-sandbox": True, "com.apple.security.application-groups": ["Y.group"]}, open(sys.argv[1], "wb"))' "$W/fl/macos/Runner/Release.entitlements"
fixture "$W/own3" flutter habit-1.0.0-macos-arm64.zip
PROJ="$W/fl" STUB_APP_ENT="$W/app-ent2.plist" sign --stack flutter --dist "$W/own3" --entitlements "$W/ent.plist"
ck "an embedded key with another value than the committed one: exit 1, nothing signed, the key named" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^codesign --force" "$2" && grep -qF "com.apple.security.application-groups" <<<"$3"' _ "$rc" "$LOG" "$out"
ck "the header no longer says the embedded set is signed in; it says the committed set is" \
  bash -c '! grep -qF "the app'"'"'s own — those its unsigned build embedded" "$1" && grep -qF "committed" "$1"' _ "$SIGN"
```
In `test_release_apps.sh`, the tauri order check (`:191-202`, its comment through `PYE`) becomes:
```bash
  # P7 R7 (REQ-386): the checklist and the pack's file say the committed set signs the app — tauri.conf.json's
  # bundle.macOS.entitlements, else this fallback — and the embedded set is only compared.
  # Covers: REQ-386
  ck "tauri: the checklist and the pack's entitlements file name the committed set (tauri.conf.json's, then the fallback) and the embedded set as compared, never signed" python3 - \
    "$ROOT/stacks/tauri/store-checklist.md" "$ROOT/stacks/tauri/release/entitlements.plist" <<'PYE'
import sys
for f in sys.argv[1:]:
    t = " ".join(open(f).read().split())
    b, c = t.find("bundle.macOS.entitlements"), t.rfind("fallback")
    assert -1 < b < c and "compare" in t and "already embeds" not in t, (f, b, c)
PYE
```
- [x] **Step 2: Run red.** The four new `test_release_sign.sh` checks FAIL (today the embedded set signs), the tauri check FAILs.
- [x] **Step 3: Implement**, as intent: R7 in `sign_app` (the embedded set read as today, compared with the tree's set from the validation step, a refusal exit 1 with the message of Interfaces; `codesign --entitlements` always the tree's set); the header, the two plist comments and the checklist item rewritten to the rule.
- [x] **Step 4: Run green**, plus `bash tests/governance/test_release_apps.sh`.
- [x] **Step 5: Commit:** `release-sign: sign with the committed entitlements only; refuse a key the build embedded that the project never granted (REQ-352, REQ-386)`.

### Task 1.4: The python image — a non-root user, a hash-pinned runtime lock, the build context; `rollback`'s recovery line (REQ-351, REQ-390, REQ-303; R8) — closes the Dockerfile residual

**Files:** `stacks/python/Dockerfile`; `stacks/python/skeleton/requirements-runtime.in`, `stacks/python/skeleton/requirements-runtime.txt` (new; the `.txt` generated by `uv pip compile --generate-hashes --universal --python-version 3.12 requirements-runtime.in -o requirements-runtime.txt`); `stacks/python/pack.yml` (`lockfiles: [requirements.txt, requirements-runtime.txt]`); `scripts/release-image.sh` (`build`'s context); `stacks/python/deploy.sh` (`rollback`'s message); `README.md` (the python deploy subsection's runtime-dependency sentences, `:541-546` — "An instance that adds runtime dependencies installs them in its `Dockerfile` from a hash-pinned lock first …"; `:305-307` is the pip-audit and bandit floor text and stays); `scripts/run-security-floor.sh` (`:65`, `LOCKFILE_PATTERN`: `requirements\.txt` → `requirements(-runtime)?\.txt`, R8); `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` — an architecture-artifact update: Task 1.4 closes dfe-5's residual, so it owns both of dfe-5's lines: the residual `:209` ("The python image runs as root …"), closed, and dfe-5's row `:117`, whose "a temporary context holding only the committed `Dockerfile` and the release's one wheel" and "so nothing resolves from PyPI at tag time" become the three-file context and the runtime lock's hash-pinned downloads (design review, polish item 3); `tests/governance/test_threat_model_current.sh` (`:465`, the list item "runs as root" becomes the closed residual's new heading text, "The python image runs as a non-root user"); `tests/governance/test_release_python.sh` (`:99-106`, `:159`, `:173-174`, `:435`, `:443-444`, `:478-489`, the opt-in block `:46-55`); `tests/governance/test_deploy_contract.sh`; `tests/governance/test_first_run.sh` (the `guided` case, docker opt-in); `tests/governance/test_stack_packs.sh` (the skeleton's runtime lock; the floor's pattern admits every lockfile a pack lists).

- [x] **Step 1: Write the failing tests.** In `test_release_python.sh`, `:101-106` (the "Final review, finding 5" comment `:101-102`, the wheel-alone check `:103-104` and the README check `:105-106`) are replaced by:
```bash
  DF="$ROOT/stacks/python/Dockerfile"
  # P7 R8 (REQ-351, REQ-390; dfe-5): the freeze lifts — runtime dependencies from the hash-pinned runtime lock, then the
  # wheel alone, then pip check; the release's code runs as a numeric non-root user.
  # Covers: REQ-351
  ck "Dockerfile: the runtime lock, hash-pinned and --no-deps, before the wheel alone (--no-deps --no-index), then pip check" python3 - "$DF" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
a = re.search(r"(?m)^RUN .*pip install --no-cache-dir --require-hashes --no-deps -r /tmp/requirements-runtime\.txt", t)
b = re.search(r"(?m)^RUN .*pip install --no-cache-dir --no-deps --no-index /tmp/\*\.whl && pip check", t)
assert a and b and a.start() < b.start(), (a, b)
assert not re.search(r"pip install(?! --no-cache-dir (--require-hashes --no-deps -r /tmp/requirements-runtime\.txt|--no-deps --no-index /tmp/\*\.whl))", t)
PY
  ck "Dockerfile: USER is numeric and not 0, after the installs and before CMD" python3 - "$DF" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
u = list(re.finditer(r"(?m)^USER\s+(\S+)\s*$", t))
assert u and u[-1].group(1).isdigit() and u[-1].group(1) != "0", u
assert t.rindex("pip check") < u[-1].start() < t.index("CMD ["), "order"
PY
  ck "the skeleton ships requirements-runtime.in and its uv-generated hashed lock; the pack lists both lockfiles" \
    bash -c 'test -f "$1/skeleton/requirements-runtime.in" && head -2 "$1/skeleton/requirements-runtime.txt" | grep -qF -- "--generate-hashes" && grep -qE "^lockfiles: \[requirements\.txt, requirements-runtime\.txt\]$" "$1/pack.yml"' _ "$ROOT/stacks/python"
  ck "README's python deploy subsection: runtime dependencies go in requirements-runtime.in, locked with hashes" \
    bash -c 'grep -qF "requirements-runtime.in" "$1" && grep -qF "requirements-runtime.txt" "$1" && grep -qF -- "--generate-hashes" "$1"' _ "$ROOT/README.md"
```
`:173-174`'s context pin becomes `[ "$(cat "$1")" = "$(printf "Dockerfile\ndist/acme-1.0.0-py3-none-any.whl\nrequirements-runtime.txt")" ]` (sorted listing), with the fixture repository committing a `requirements-runtime.txt` beside its `Dockerfile` in its first commit `one` (`:159`, so `RC1` and `RC2` both carry it; likewise `:435`), and one more check, directly after the `:173-174` pin — run at the new commit as `RELEASE_COMMIT`, so the refusal is the missing lock's and never "HEAD … is not RELEASE_COMMIT", then `$R` reset to `RC2` so every later `img build` (`:175-184`) runs where it did (fresh-eyes review, finding 10):
```bash
(cd "$R" && git rm -q requirements-runtime.txt && git commit -qm "no runtime lock")
RCOMMIT="$(git -C "$R" rev-parse HEAD)" img build --source-url https://github.com/o/r
ck "release-image.sh build: a tagged tree without requirements-runtime.txt fails before docker build, naming it" \
  bash -c '[ "$1" != 0 ] && grep -qF "requirements-runtime.txt" <<<"$2" && ! grep -qF "is not RELEASE_COMMIT" <<<"$2" && ! grep -q "^docker build " "$3"' _ "$rc" "$out" "$G/docker.argv"
git -C "$R" reset -q --hard "$RC2"
```
`:478-489` (the Dockerfile residual's expiry) become a pin that the residual is closed, and dfe-5's row is pinned beside it:
```bash
factory_doc_ck "the python image residual is closed by P7 Build 1 (non-root, hash-pinned runtime lock); what stays is named" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "- **The python image" "$1"); grep -qF "closed by P7 Build 1" <<<"$l" && grep -qF "USER 10001" <<<"$l" && grep -qF "requirements-runtime.txt" <<<"$l" && ! grep -qF "expires: 2026-10-12" <<<"$l"' _ "$TM"
factory_doc_ck "dfe-5's row: the build context holds the Dockerfile, the runtime lock and the one wheel; only hash-pinned files download at tag time" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'l=$(grep -F -- "| dfe-5 |" "$1"); grep -qF "requirements-runtime.txt" <<<"$l" && grep -qF -- "--require-hashes" <<<"$l" && ! grep -qF "holding only the committed \`Dockerfile\` and the release'"'"'s one wheel" <<<"$l"' _ "$TM"
```
The opt-in docker block (`:46-55`) gains, inside `if [ "${SPECFLOW_DOCKER:-}" = 1 ]`, two checks **directly after the first opt-in check (`:47-48`)** — where `$D/dist/` holds the no-dependency wheel and `specflow-smoke:0.1.0` exists; `:50`'s `rm -rf dist` runs after them (fresh-eyes review, finding 16):
```bash
    ck "opt-in: the image's process runs as uid 10001, never root" \
      bash -c 'cd "$1" && [ "$(docker run --rm --entrypoint id specflow-smoke:0.1.0 -u)" = 10001 ]' _ "$D"
    ck "opt-in: the pinned base's pip accepts the empty runtime lock (exit 0, nothing installed)" \
      bash -c 'cd "$1" && test -n "$(ls dist/*.whl)" && docker build -q -t specflow-smoke-empty:0.1.0 . >/dev/null' _ "$D"
```
and, **after the existing six block (`:51-54`, which ends with `pyproject.toml` back to `dependencies = []`)**, still inside the opt-in block:
```bash
    (cd "$D" && sed -i.bak 's/^dependencies = \[\]$/dependencies = ["six"]/' pyproject.toml && rm -f pyproject.toml.bak \
      && docker run --rm -v "$PWD:/w" -w /w "$(sed -n 's/^FROM //p' Dockerfile)" sh -c 'pip download -q --no-deps six==1.17.0 -d /tmp/d && python -m pip hash /tmp/d/*.whl' \
         | awk '/--hash=/{print "six==1.17.0 \\\n    " $0}' > requirements-runtime.txt \
      && git add -A && git commit -qm "a hashed runtime dependency"); rel "$W/f"
    ck "opt-in: a wheel whose runtime dependency is in the hashed runtime lock builds and passes pip check and the smoke" \
      bash -c 'cd "$1" && rm -rf dist && mkdir -p dist && cp "$2"/*.whl dist/ && docker build -q -t specflow-smoke-deps2:0.1.0 . >/dev/null && bash scripts/release-smoke.sh --stack python --dist dist --image specflow-smoke-deps2:0.1.0' _ "$D" "$W/f"
    (cd "$D" && git revert --no-edit HEAD >/dev/null)
```
**These docker cases are opt-in only** (design review, polish item 3): every one sits inside the existing guard `if [ "${SPECFLOW_DOCKER:-}" = 1 ]` (and `test_first_run.sh`'s below inside the same guard), so a default run and the gates never start them and keep P6 R21's three-minute budget. They need Docker Desktop running **and the network**: the pinned `python:3.12-slim` base is pulled on a cold cache, and the six case's `pip download six==1.17.0` reads PyPI. Expected wall-clock with `SPECFLOW_DOCKER=1`: about 3–6 minutes for `test_release_python.sh` on a warm base-image cache (four image builds and two smokes), longer on a cold one; the implementer records the measured time with the opt-in run's result in the PR body (Step 4), and the maintainer's M0 run records its own.
In `test_deploy_contract.sh`, inside the per-script loop, directly after the nothing-running rollback checks (`:97-101`), with the file's own `dr` helper and stub docker (`STUB_DEPLOYED` empty: `docker inspect` answers "No such object"):
```bash
  # P7 R8 (REQ-351; PR #57 verifier run 1, finding 5): stop-then-start stays; with nothing running, rollback names the
  # recovery — a deploy of an earlier release by its version.
  # Covers: REQ-351
  DEPLOY_CALL="rollback" dr env STUB_DEPLOYED=""
  ck "$l: rollback with nothing running names the recovery, deploy <X.Y.Z> of an earlier release" \
    grep -qF "deploy an earlier release by hand: scripts/deploy-local.sh deploy <X.Y.Z>" <<<"$out"
``` In `test_first_run.sh`'s `guided` case (there is no "python case": the python cases are `guided` and `engineer`; the scratch root is `$WORK`), directly after "guided: dist/manifest.json verifies" (`:65-72`, which reads `$WORK/dist`, written by `:64` with `SOURCE_DATE_EPOCH`) and before the examples are removed: `if [ "${SPECFLOW_DOCKER:-}" = 1 ]; then ck "guided (opt-in docker): the instance's image builds from its own Dockerfile and runs as uid 10001" bash -c 'cd "$1" && mkdir -p dist && cp "$2"/*.whl dist/ && docker build -q -t fr-py:0.1.0 . >/dev/null && u=$(docker run --rm --entrypoint id fr-py:0.1.0 -u); rm -rf dist; [ "$u" = 10001 ]' _ "$D" "$WORK/dist"; fi` (the copied `dist/` is removed, so the later gates run on the tree as before). In `test_stack_packs.sh` — which has no list of required skeleton files (`:15-16`'s `req` names each pack's top-level files: `init.sh`, `gates.sh`, …, and python's `Dockerfile` and `deploy.sh`) — directly after the python lockfile checks (`:40-41`, "lockfile is hash-pinned" and "lockfile made by uv pip compile --universal"), one check:
```bash
ck "runtime lock: skeleton/requirements-runtime.in and its lock, made by uv pip compile --generate-hashes" \
  bash -c 'test -f "$1/skeleton/requirements-runtime.in" && grep -qE "uv pip compile .*--generate-hashes" "$1/skeleton/requirements-runtime.txt"' _ "$P"
```
And, above `finish` (fresh-eyes review, finding 11):
```bash
# P7 R8 (REQ-303, REQ-351): the floor's osv-scanner reads every lockfile a pack lists — run-security-floor.sh admits a
# lockfile by basename (LOCKFILE_PATTERN), not by the pack's lockfiles:, so the pattern must match each listed basename.
# Covers: REQ-303
ck "every lockfile a pack's lockfiles: lists matches run-security-floor.sh's LOCKFILE_PATTERN (osv-scanner scans it)" python3 - "$ROOT" <<'PY'
import glob, os, re, subprocess, sys
root = sys.argv[1]
pat = re.search(r"(?m)^LOCKFILE_PATTERN='([^']+)'$", open(os.path.join(root, "scripts/run-security-floor.sh")).read()).group(1)
packs = glob.glob(os.path.join(root, "stacks/*/pack.yml")) + [p for p in (os.path.join(root, ".specflow/pack.yml"),) if os.path.isfile(p)]
assert packs, "no pack"
for pk in packs:
    lfs = subprocess.run([sys.executable, os.path.join(root, "scripts/lib/specflow/config.py"), "--file", pk, "getlist", "lockfiles"],
                         capture_output=True, text=True, check=True).stdout.split()
    for lf in lfs:
        assert re.match(pat, os.path.basename(lf)), (pk, lf)
PY
```
(In the template source it reads every `stacks/*/pack.yml`; in an instance, `.specflow/pack.yml`.)
- [x] **Step 2: Run red.** `bash tests/governance/test_release_python.sh`, `test_deploy_contract.sh`, `test_stack_packs.sh` FAIL on the new checks; with `SPECFLOW_DOCKER=1` (Docker Desktop running, the network up) the uid check FAILs (root).
- [x] **Step 3: Implement**, as intent: R8 and Interfaces "The python image"; generate the lock with `uv` (never by hand; never `pip install` into the host python); `run-security-floor.sh`'s `LOCKFILE_PATTERN`; dfe-5's row (`:117`): the context holds the committed `Dockerfile`, the committed `requirements-runtime.txt` and the release's one wheel, and the image installs the runtime lock `--require-hashes --no-deps` (its files download from PyPI at tag time, each pinned by hash) before the wheel alone — the rest of the row unchanged; the threat model's Dockerfile residual (`:209`) closed here — its heading becomes "**The python image runs as a non-root user from a hash-pinned runtime lock**", its P6 parenthesis kept (owner, `sign-off: PR #57's merge (Build 4…`, CVSS) and its `expires: 2026-10-12, …` clause replaced by "closed by P7 Build 1 (Task 1.4): `USER 10001`, `requirements-runtime.txt` installed `--require-hashes --no-deps`", and `test_threat_model_current.sh:465`'s list item follows the new heading —, naming what stays (the runtime lock's files download from PyPI at tag time, pinned by hash; a project that adds a dependency regenerates the lock by `uv pip compile --generate-hashes`).
- [x] **Step 4: Run green**, and once with `SPECFLOW_DOCKER=1` (record the result in the PR body; if Docker Desktop is stopped, say so and leave the opt-in run to the maintainer, M0).
- [x] **Step 5: Commit:** `python image: a non-root user and a hash-pinned runtime lock; the build context carries it; rollback names the recovery (REQ-351, REQ-390, REQ-303)`.

### Task 1.5: The surfaces — the flutter checklist's staple line, README's Signing row, `CLAUDE.md:72` (REQ-308, REQ-352; PR #58 verifier run 2)

**Files:** `stacks/flutter/store-checklist.md` (`:21-23`); `README.md` (`:28`, the Signing row); `CLAUDE.md` (`:72` only); `tests/governance/test_release_apps.sh`; `tests/governance/test_onboarding_surface.sh` (`:358-361`, `:383`).

**Interfaces:** the settled texts: the flutter item 4 becomes "4. **Notarization** — `xcrun notarytool submit --wait` on a zip of the signed `.app`, then `xcrun stapler staple` on the `.app` itself and a fresh zip of the stapled app (a zip cannot be stapled; `release-sign.sh` does exactly this)."; the Signing row's first cell becomes "macOS signing and notarization when `signing: apple` and the five Apple secrets exist — environment secrets of the `release` environment, which a GitHub Free private repository cannot hold; with `signing: apple` and any secret missing the release fails and publishes nothing; with `signing: none`, an unsigned bundle with tester instructions; SSH-signed release tags"; `CLAUDE.md:72` becomes "- `docs/releases/store-checklist.md` — app stacks: the macOS distribution checklist (signing, notarization, packaging), appended to each release's notes by `/release` under `## macOS distribution checklist`; `verify-release.sh` and `release.yml` refuse an app-stack release whose notes lack that heading (REQ-352)".

- [x] **Step 1: Write the failing tests.** In `test_release_apps.sh`, above `finish`:
```bash
# P7 (REQ-352; PR #58 verifier run 2): the flutter checklist never tells anyone to staple a zip.
# Covers: REQ-352
ck "flutter checklist: staple the .app and re-zip it; a zip cannot be stapled" \
  bash -c 't=$(tr "\n" " " < "$1" | tr -s " "); ! grep -qF "(or the zip" <<<"$t" && grep -qF "a zip cannot be stapled" <<<"$t" && grep -qF "\`xcrun stapler staple\` on the \`.app\`" <<<"$t"' _ "$ROOT/stacks/flutter/store-checklist.md"
```
In `test_onboarding_surface.sh`, `:358-359` becomes:
```bash
ck "CLAUDE.md: the checklist goes under ## macOS distribution checklist; verify-release.sh and release.yml refuse notes that lack that heading (P6 R22)" \
  bash -c 'l=$(grep -F "docs/releases/store-checklist.md" "$1"); grep -qF "appended to each release'"'"'s notes by \`/release\` under \`## macOS distribution checklist\`" <<<"$l" && grep -qF "whose notes lack that heading" <<<"$l" && ! grep -qF "refuses an app release without it" <<<"$l"' _ CLAUDE.md
```
and above `finish`:
```bash
# PR #58 verifier run 2 (REQ-308): the Signing row says what signing: apple with a missing secret does — nothing published.
# Covers: REQ-308
ck "README Signing row: signing: apple with any secret missing fails the release and publishes nothing; signing: none ships unsigned" \
  bash -c 'l=$(grep -F "| **Signing** |" "$1"); grep -qF "\`signing: apple\` and any secret missing the release fails and publishes nothing" <<<"$l" && grep -qF "\`signing: none\`" <<<"$l"' _ README.md
```
- [x] **Step 2: Run red.**
- [x] **Step 3: Edit**, as intent: the three settled texts.
- [x] **Step 4: Run green.**
- [x] **Step 5: Commit:** `surfaces: the flutter checklist staples the .app, the Signing row's missing-secret case, CLAUDE.md's checklist heading (REQ-308, REQ-352)`.

### Task 1.6: The residuals that expire on 2026-10-12, re-reviewed (R9; H6) — architecture-artifact update

**Files:** `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` (dfe-6 `:118`; dfe-12 `:124` — its three expiring residuals: the TOFU caveat, the Boundary residual, the Tagged-tree residual; dfe-13 `:125`; dfe-14 `:126`; `:208`, `:210`, `:212`, `:214`, `:215`, `:216` — `:209` is Task 1.4's); `tests/governance/test_threat_model_current.sh` (`:21`, `:301`, `:367`, `:375`, `:423-425`, `:438-446`, `:471-492`; and, read but kept by the append form, `:213` — the TOFU caveat's `sign-off: PR #56's merge (Build 3` —, `:359` — dfe-13's `re-accepted … sign-off: PR #56's merge (Build 3; P6 R11` — and `:459-469` — `sign-off: PR #5[678]'s merge (Build [345]` for ten residuals, whose `:465` lookup Task 1.4 already moved to the python image residual's new heading).

**Interfaces:** R9's one form. The decisions: dfe-6/dfe-14's short-name convention residual → re-accepted (BL-007); dfe-12's TOFU caveat (the forged-anchor residual) → re-accepted (BL-023); dfe-12's Tagged-tree residual ("accepted with the Boundary residual"; fresh-eyes review, findings 5 and 12) → re-accepted (BL-013, the classifier from the previous published release's tag — what would narrow it; `v3.2.0` does not close it, since every tag runs its own `release.yml`, `attestation.py` and `template-pack.yml`), its own expiry clause rewritten, never left under the Boundary residual's; dfe-12's boundary residual → closed if `v3.2.0` is published when this task runs ("closed at `v3.2.0`: its tagged tree carries `attestation_since`, so the never-moves rule fixes the boundary"), else re-accepted; dfe-13 → re-accepted (BL-014); deploy-local (`:208`) → re-accepted, narrowed (stop-then-start stays; `rollback` names the recovery; BL-015); the python image (`:209`) → closed by Task 1.4 (Task 1.4 wrote it, in the same append form); GHCR (`:210`) → re-accepted (BL-009, BL-010); `release.yml` binds only reviewed tags (`:212`) → re-accepted (BL-013); the Apple secrets (`:214`) → re-accepted (BL-016); registry caches (`:215`) → re-accepted (BL-017); the signed path (`:216`) → re-accepted (BL-018). CVSS vectors unchanged; "severity provisional (solo mode, `art-threat-driven-security`)" unchanged. **R9's form appends:** each residual keeps its P6 parenthesis (owner, P6 sign-off, CVSS), and only `expires: 2026-10-12, …` becomes `expires: 2026-12-15; re-accepted — owner: kpingali123, the maintainer; sign-off: the merge of build/factory-v3-2-p7-1 (P7 Build 1); re-reviewed by the v3.2 retrospective's decision on BL-0NN`.

- [x] **Step 1: Write the failing tests.** Every pin above that names `"expires: 2026-10-12"` or `"sign-off: PR #5x's merge (Build N)"` on these residuals becomes the re-accepted form; in one place, above `finish`:
```bash
# P7 R9 (REQ-351, REQ-352, REQ-350, REQ-334; H6): no residual of the threat model expires on or before 2026-10-12; every
# re-accepted one names its owner, P7 Build 1's merge as sign-off, 2026-12-15 and its backlog id; the closed ones say so.
# Covers: REQ-351
# Covers: REQ-352
factory_doc_ck "the threat model: no 'expires: 2026-10-12' is left; each P7 re-acceptance names owner, sign-off, 2026-12-15 and a BL id" \
  docs/architecture/2026-09-25-factory-v3-2-threat-model.md python3 - "$TM" "$ROOT/scripts/lib/specflow" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[2]); import cvss4
t = open(sys.argv[1]).read()
assert "expires: 2026-10-12" not in t, "an expiry of 2026-10-12 is left"
ra = re.findall(r"expires: 2026-12-15; re-accepted — owner: kpingali123, the maintainer; sign-off: the merge of build/factory-v3-2-p7-1 \(P7 Build 1\); re-reviewed by the v3\.2 retrospective's decision on (BL-\d{3})", t)
assert len(ra) >= 10, ra
tagged = next(l for l in t.splitlines() if "**Tagged-tree residual**" in l)
seg = tagged[tagged.index("**Tagged-tree residual**"):]
assert "decision on BL-013" in seg[: seg.index("): ") + 3], "the Tagged-tree residual carries its own re-acceptance, BL-013"
assert not re.search(r"sign-off: PR #\d+'s merge \(P7", t), "a P7 sign-off names the branch, never a PR number"
for v in re.findall(r"`(CVSS:4\.0/[^`]+)` \(([\d.]+), (\w+)", t):
    assert f"{cvss4.score(v[0])}" == v[1] and cvss4.finding_severity(v[0]) == v[2], v
for k in ("closed by P7 Build 1", "BL-007", "BL-009", "BL-013", "BL-014", "BL-015", "BL-016", "BL-017", "BL-018", "BL-023"):
    assert k in t, k
PY
```
(The sign-off names the branch, never a PR number (R9; fresh-eyes review, finding 13): agents never open PRs or push, so no commit an agent makes can know the number.)
- [x] **Step 2: Run red.**
- [x] **Step 3: Edit**, as intent: each residual's `expires: 2026-10-12, …` clause rewritten to R9's appended form with its BL id (the P6 parenthesis kept); the closed ones say what closed them; the dfe-12 boundary decision by whether `GH_TOKEN=… gh release view v3.2.0 --json isDraft` answers `false`.
- [x] **Step 4: Run green**, `bash tests/governance/test_release_python.sh` too.
- [x] **Step 5: Commit:** `threat model: the residuals that expire on 2026-10-12 re-reviewed — closed, narrowed or re-accepted to 2026-12-15 with a backlog id (REQ-351, REQ-352)`.

### Task 1.7: Build 1's whole-build verification

**Files:** this plan's `## Build 1` section (ticks; corrections as fix waves require).

- [x] **Step 1:** `git diff refs/remotes/origin/main --stat` — no `state.py`, `records.py`, `disposition.py`, `verification/`, `constitution.md`, spec, `docs/BACKLOG.md`, `docs/security/`, `docs/releases/`; `git diff refs/remotes/origin/main --name-only` ⊆ Build 1's column of the table (plus this plan).
- [x] **Step 2: Inside scaffolded instances** (P6's lesson): `copy_template` into `$TMPDIR/p7b1-py`, `-tauri`, `-flutter`; `bash scripts/init-project.sh --name Acme --stack <s>` (`SPECFLOW_NO_SCAFFOLD=1` for tauri and flutter); in each, run `test_attestation.sh`, `test_review_gate_claims.sh`, `test_release_sign.sh`, `test_release_apps.sh`, `test_release_python.sh`, `test_deploy_contract.sh`, `test_onboarding_surface.sh`, `test_threat_model_current.sh`, `test_stack_packs.sh`; every one passes or prints a visible SKIP; the python instance's `requirements-runtime.txt` exists and its gates pass (`bash scripts/run-quality-gates.sh`).
- [x] **Step 3:** the gates on the build branch (exit 0, under 3:15); `bash scripts/check-test-first.sh --base refs/remotes/origin/main`; `actionlint`.
- [x] **Step 4: The final review** (the P5/P6 pattern, as run): the whole-branch, verifier-dry-run and gate-code lenses ran at the build's final review (three opus agents), the fix waves had scoped re-reviews, and the headless verifier is the second review in solo mode; the agent writes the PR body to `$TMPDIR/p7-build1-pr-body.md` and the maintainer pushes the branch and opens the PR from it (agents never push or open PRs) — the body carries **Gate code** (`attestation.py`, `run-verifier.sh`, `release-sign.sh`, `release-image.sh`, `run-security-floor.sh`, `tests/governance/lib/check.sh`, `.claude/rules/review-gate.md`, `CLAUDE.md`), **Architecture-artifact updates** (Tasks 1.2, 1.4, 1.6), R4's severity-floor paragraph and fixture list, M0b's probe run id and R28's two preview summaries; read completed CI after every push.

### Corrections (from the #60/#61/#62 verifier runs)

Each was fixed test-first (the pin written and seen red, then the change). Gate code outside the table's Build 1 column is named in the PR body: `.github/workflows/verifier.yml` (item 2) and `scripts/init-project.sh` (item 9).

1. **SEC-021 (PR #62 review; PR #61 run 1 finding 1).** `scripts/run-verifier.sh:620` reads `.gitleaks.toml` at `$code_ref` (main's; the head's under `--bootstrap`), no longer at the stacked base (`$src_ref`); the header comments at `:19` and `:602` say so. Pinned in `tests/governance/test_verifier_run.sh:166-170` with a stacked-base fixture whose `.gitleaks.toml` allowlists every string (the stub gitleaks' recorded config is main's, not the base's). `.claude/rules/review-gate.md:86` (isolation row) lists the base-read inputs that remain (policy keys, prompt template, skill, constitution, deny-list additions), pinned in `tests/governance/test_review_gate_claims.sh:30-34`.
2. **SEC-020 (PR #62 review; PR #61 run 1 finding 2).** `.github/workflows/verifier.yml:99-118` (the "Check the attestation" step) captures the classifier's output, prints the fixed bootstrap line `git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- $PR` itself on every failure (a literal; `$PR` comes from `env:`), and on a non-main base prefixes the output with a label ("printed by the stacked base's own classifier ... unreviewed") and indents every line so a `::workflow-command::` in it never runs. Pinned by behaviour in `tests/governance/test_workflow_health.sh:188-` (a stacked base whose classifier prints a hostile hint and an injected `::error::`; a PR to main; a passing check); the existing `origin/main` grep (`:67`) now ignores the one sanctioned mention. actionlint and `test_action_pins.sh` clean. The threat model's dfe-10 row records the update (SEC-020's cause is removed; its severity and sign-off stay the retrospective's).
3. **PR #61 run 1, code-mode low.** `tests/governance/test_verifier_run.sh:187-` carries the fixture for `$main_full carries no P2 verifier entry point` (the base has the entry point, main's copy lost it): exit 1, the message names main, no model run.
4. **PR #61 run 1, code-mode low.** `# Covers: REQ-385` at `tests/governance/test_onboarding_surface.sh:136`; `# Covers: REQ-313` at `tests/governance/test_spec_commands.sh:28`.
5. **PR #61 run 1, code-mode low (prompt_sha256).** The threat model's dfe-10 row (`docs/architecture/2026-09-25-factory-v3-2-threat-model.md`) states the residual: main's `prompt-hash --ref <base>` against the base's own classifier in CI; a changed hashing fails closed (`prompt-mismatch`). Pinned in `tests/governance/test_threat_model_current.sh:559-` (REQ-385, REQ-313).
6. **PR #60 run 1, lows.** `# Covers: REQ-353` at `tests/governance/test_constitution_amendment_b.sh:56`; `# Covers: REQ-326` at `tests/governance/test_threat_model_current.sh:151`.
7. **PR #60 run 1, low.** `tests/governance/test_constitution_articles.sh` now checks dotless named paths (`.github/allowed_signers`) exist; pinned with a scratch constitution naming a missing dotless path (`CONSTITUTION_FILE` override).
8. **PR #60 run 1, low.** `tests/governance/test_reviews_use_slugs.sh` scans every `CLAUDE.md` / `CLAUDE.local.md` at any depth (worktrees, `node_modules`, `target`, venvs pruned) in both the Roman-numeral and slug scans; pinned with a scratch tree carrying a nested `tests/deep/CLAUDE.md` (`SLUGS_TEST_ROOT` override).
9. **PR #60 run 1, low.** `scripts/init-project.sh:691` dies (`precondition_err`, exit 1) when `templates/BACKLOG.md` is missing instead of skipping the copy; pinned in `tests/governance/test_backlog.sh:103-`.

### Deferred corrections (for the retrospective or the owning PR)

- D1. [PR #60 run 2, medium] `art-naming-tagging` now makes `Task N.M` the default task id (not globally unique) while R2(g) says amendment C changes no rule; the task-id rule is neither enforced nor labelled convention — constitution and plan header: retrospective (BL id).
- D2. [PR #60 run 2, medium] REQ-382's "As amended by P7 (R4)" sentence names the timeline rule (`waiver-unbound-retargeted`, `waiver-timeline-unknown`) that R4's fallback drops if M0b fails; if Task 1.1's Step 0 finds the read impossible under the workflow token, the owning PR revises the spec sentence (a build does not edit the spec); record M0b's measured result in the PR body either way.
- D3. [PR #60 runs 1+2, low/medium] The plan's line 33 "Not claimed" says `release-tag.sh` is unchanged though its header comment changed in #60 and commit a465147 cites REQ-383 — plan header: retrospective or a doc patch.
- D4. [PR #60 run 1, low] `art-secrets-hygiene` says `.env*` reads are denied while `.claude/settings.json` denies `./.env` and `./.env.*` only (`.envrc` escapes) — constitution wording or a wider deny rule: retrospective.
- D5. [PR #60 run 1, low] `art-naming-tagging` says Roman numerals are banned "anywhere in docs/" but `test_reviews_use_slugs.sh` exempts superseded specs, archived reviews and plans for superseded specs — constitution: retrospective.
- D6. [PR #60 run 1, low] `review-gate.md`'s new "Convention" row satisfies the claim-to-file test for the rule file itself — accepted as a pinned cross-reference, not enforcement; recorded.
- D7. [PR #60 run 2, lows] `art-threat-driven-security` names `check-suppressions.sh` without its runner (`tests/governance/test_suppressions.sh`, gates section 3); `art-review-gate` still says `src/` where two other articles say `source_roots`; `[verifiable]`'s contract-extraction step is neither enforced nor labelled convention — constitution: retrospective.
- D8. [PR #60 run 2, low] `docs/BACKLOG.md`'s BL-028..031 "Absorbed" lines read in the present tense as if a retrospective had already recorded `accepted` — Build 2's column (docs under its ownership) or the retrospective; Build 2 may fix it.
- D9. [PR #61 run 1, finding 4] REQ-385's amendment describes only the named-base-PR wording; `pipeline.py`'s `base_pr == 0` branch prints different text — the spec is not edited by a build: owning PR or retrospective.
- D10. [PR #61 run 1, finding 5] REQ-313's amendment lists fewer base-read inputs (skill, constitution, policy) than `review-gate.md` and `run-verifier.sh`'s header (plus the prompt template, deny-list additions; `.gitleaks.toml` is now main's) — spec: owning PR or retrospective; this build aligned `review-gate.md` and the threat model only (corrections 1 and 5).
- D11. [PR #59 run 2, mediums; ship review] The `medium_cap` override's calendar dependence after 2026-10-12 and the cap of 10 against nine ids; SEC-020 was recorded open because `test_security_schema_docs.sh` pins the nine accepted ids — the retrospective re-decides the cap (restore 5 or re-record) before 2026-10-12; this build only removes SEC-020's cause (correction 2).
- D12. [Task 1.1, Step 0 (M0b)] Measured on 2026-10-03 with the maintainer's repo-scoped token (not read-only: its `X-Oauth-Scopes` carry `repo`) (`gh api --paginate repos/Apps-Consultants/factory/issues/48/timeline`, the only retargeted PR in the measured range #45–#58; a read-only scan of #1–#63 on 2026-10-03 finds `base_ref_changed` also on #11, #12, #25, #30, #31, #33, #36 and #42, and `base_ref_deleted` on #11 and #21 — each pre-transfer or judged by an `APPROVE` marker, so the timeline is never read for them — and no `automatic_base_change*` event): `["2026-09-30T11:25:56Z"]`, the expected answer. The read under `verifier.yml`'s and `release.yml` verify job's read-only `GITHUB_TOKEN` was measured on 2026-10-04 (Step 0 above: probe PR #67, run 37169624336, HTTP 200, the expected answer; the timeline rule stands). Before that measurement the classifier was written as R4 stands: the classifier is written as R4 stands (the timeline rule in); if the probe fails, R4's fallback applies and the owning PR drops the timeline rule and revises REQ-382's "As amended by P7" sentence (D2). The R28 preview over `v3.2.0..` (`--since v0.0.1-demo`, 3.3.0 at `refs/remotes/origin/main`) before and after Task 1.1: identical, 18 ok, 28 pre-transfer, 0 FAIL (#48's waiver still accepted). Fixtures 105/107/109 pass before and after, as R4 predicted. `test_next_prs.sh`'s bound-waiver case names the head itself rather than the seed's root commit, since the seed has one commit and its root is origin/main's tip.
- D13. [Build 1 final review, findings 2 and 7] R4 and the Interfaces paragraph (plan header, `:54`, `:138`) name only `base_ref_changed` and "later than" the waiver; Build 1's classifier counts every `base_ref_*` and `automatic_base_change*` timeline event (GitHub's automatic retarget when a base branch is deleted, a base force-push) at or after the waiver's second, and a base event with no time reads as `waiver-timeline-unknown` — the plan header (and REQ-382's "As amended by P7" sentence, if it is read as naming the event) follows in the retrospective or the owning PR.
- D14. [Build 1 final review, findings 3 and 6] The maintainer checklist's M0b (plan header, `:1133`) says "before Build 1's classifier change"; the classifier was written first, so M0b is now a merge precondition of Build 1's PR (Step 0 above, the PR body's checklist) — the plan header's wording: retrospective. The gate time budget (PR #65 verifier run 1, finding 9; Task 1.7 Step 3's "under 3:15") stays recorded here and in D16 as not demonstrated: fix wave 1 took 3:15 (195 s), fix wave 2's measured wall-clock and load are in its Results below.
- D15. [Fix wave 1, D13 of its task list] The plan header's "Neither build edits `scripts/init-project.sh` or any workflow" and the R1 table are now false for Build 1: the sanctioned corrections touched `.github/workflows/verifier.yml`, `scripts/init-project.sh`, `tests/governance/test_workflow_health.sh`, `tests/governance/test_backlog.sh` and `tests/governance/test_constitution_articles.sh` — the header is the retrospective's. `test_backlog.sh` borders Build 2's backlog area: a merge-conflict risk, resolved by the second-to-merge build's rebase.
- D16. [Fix wave 1, D14 of its task list] The gates took 4:32–5:05 at load averages 17–41 while concurrent sessions ran; the three-minute budget is not demonstrated on this branch — re-measure idle at the retrospective. Fix wave 1's own gates run is recorded under "Fix wave 1" below, its `uptime` load beside it.
- D17. [Fix wave 1, D15 of its task list] M0b (the timeline read under the workflows' read-only `GITHUB_TOKEN`) was measured on 2026-10-04 UTC, the local evening of 2026-10-03 (Task 1.1 Step 0: probe PR #67, run 37169624336 at 01:58Z, before PR #65 merged at 02:23Z; HTTP 200, the expected answer): the timeline rule stands and no fallback applies. It was measured under a `pull_request` event only: the read under the tag-push event of `release.yml`'s verify job, which holds the same read permissions, is not measured (PR #68 verifier run 1, findings 1–2). Owner: kpingali123. Recovery (R4): a bound waiver naming the merge commit's first parent clears a refused legacy waiver at the tag. Pre-ship check: before the 3.2.1 tag the maintainer runs `scripts/release-tag.sh 3.2.1 --dry-run`, which runs `release-check` with the maintainer's token and so does not measure the workflow token; the tag-push read is measured by the first `release.yml` run itself, fail-closed: a refusal is `waiver-timeline-unknown`, recoverable by the bound waiver (PR #71 verifier run 1, finding 4). The date is a day after this plan's `created:` date because the probe ran after Build 1's first verifier run; the plan header's "before Build 1's classifier change" wording is the retrospective's (D14). Closed.
- D18. [Fix wave 1, D16 of its task list; FIX 2] dfe-10's CI-log hint residual and dfe-12's Boundary residual (the `attestation_since` boundary) name no backlog entry: none of BL-001…BL-033 covers either (BL-028 is the wrong-branch guard, BL-023 the forged-anchor residual — the ids they cited before fix wave 1). Both now cite "the P7 retrospective (plan Build 1, Deferred corrections)"; the retrospective lists two BL entries for them (`docs/BACKLOG.md` is not Build 1's to edit) and re-points the two residuals at the new ids.
- D19. [PR #65 verifier run 1, code-mode low] The SEC-020/SEC-021 corrections (`verifier.yml`, `run-verifier.sh`'s `.gitleaks.toml`) cite REQ-313 and REQ-385, which are not in this plan's `implements:` (the P2 and P5 plans claim them, so no `art-specification-primacy` finding); adding them to `implements:` (the plan header) is the retrospective's.

### Final review fix wave (2026-10-03)

- Findings 1, 8 (python image): the runtime lock installs `--only-binary :all:` (wheels only); an sdist would build under pip's build isolation, whose build requirements are installed from PyPI unhashed. Measured in the pinned base on 2026-10-03: a lock holding six 1.17.0's sdist hash builds and installs without the flag (exit 0) and installs nothing with it. Pinned in `test_release_python.sh` (the Dockerfile regex, `requirements-runtime.in`'s header, README's python deploy subsection, dfe-5 and the residual) and its opt-in docker case.
- Findings 2, 7 (the legacy waiver's timeline rule): every `base_ref_*` or `automatic_base_change*` event at or after the waiver's second refuses it; a base event with no time is `waiver-timeline-unknown`. `review-gate.md` (step 6 and the waiver row), the glossary and the threat model's residual name the events and the base rewritten with no timeline event as what stays (markers and bound waivers are refused there by the merge-base rule). R28's preview re-run after the change (3.3.0 at `refs/remotes/origin/main` = e73a942, `--since v0.0.1-demo`): 47 first-parent commits, 19 ok, 28 skipped (pre-transfer 28), 0 FAIL; #48's waiver still accepted.
- Findings 3, 6 (M0b): a merge precondition, in the PR body's checklist; D12 reworded (repo-scoped token, the measured range); D14.
- Finding 4 (README's Signing row): signing and notarization whenever the five Apple secrets exist, whatever `signing:` says (`release.yml`'s `signing-probe`, REQ-386); unsigned with tester instructions only for `signing: none` with the secrets absent. Task 1.5's settled Signing text above is superseded by this one; `test_onboarding_surface.sh` runs the probe step itself.
- Finding 5 (SEC-020's defang): `verifier.yml` turns each `\r` of the stacked base's classifier text into a space, prefixes it, and prints it between `::stop-commands::<random token>` and `::<token>::`; the comment and dfe-10 say this covers the text the classifier prints, not its code. `test_workflow_health.sh` injects `\r::error::` and `\r\n::warning::` and judges with a CR-aware split.

### Task 1.7 results (2026-10-03)

- Step 1: no kernel, spec, constitution, BACKLOG, security or releases file in `git diff e0a2022 HEAD`; every changed file is in Build 1's column or the Corrections list. (`origin/main` has since moved to e73a942, #63; Build 1 rebases on it at the PR, not here.)
- Step 2: scaffolded instances (python; tauri and flutter with `SPECFLOW_NO_SCAFFOLD=1`): the nine tests pass in all three, with visible SKIPs only (attestation 3, release_apps 8, release_python 16-17, threat_model_current 1, stack_packs 1); the python instance has `requirements-runtime.txt`. Its gates pass (exit 0) once the floor tools `pip-audit` and `bandit` are present (a scratch venv from the instance's own hash-pinned `requirements.txt`); without them the floor reports them missing, as designed (host hygiene: not installed into the factory-tools venv).
- Step 3: gates exit 0 on the build branch; wall time 4:32 while three instance runs and Build 2 ran concurrently (the 3:15 budget was measured idle, not re-measured); `check-test-first.sh --base refs/remotes/origin/main` PASS (7 commits); actionlint clean; `SPECFLOW_DOCKER=1 test_release_python.sh` passes (uid 10001 check included).
- Step 4: the whole-branch, verifier-dry-run and gate-code lenses ran at the build's final review (three opus agents; their findings are the "Final review fix wave" above), the fix waves had scoped re-reviews, and the headless verifier is the second review in solo mode (PR #65); PR body written to `$TMPDIR/p7-build1-pr-body.md`.

### Fix wave 1 (2026-10-03, PR #65)

Rebased on `refs/remotes/origin/main` @ e73a942 (#63: `test_first_run.sh` runs the instance's gates with `env -u SPECFLOW_QG_RUNNING -u SPECFLOW_FIRST_RUN -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH`, and `tests/governance/test_first_run_env.sh`) with no conflict: Build 1's commits did not touch that line, and `test_first_run_env.sh` passes on the rebased branch. Each item was fixed test-first (the pin seen red, then the change):

1. FIX 1 (R4, fail closed): the timeline rule compares only ISO-8601 UTC seconds — an empty, null or malformed time (the waiver's or a base event's) is `waiver-timeline-unknown`, never acceptance or a `TypeError`; a gh answer that is not JSON is an unreadable timeline (and, for any other gh read, a named exit-2 error, never a traceback); a base event in the waiver's own second refuses it. Fixtures 110–113; `test_attestation.sh` asserts the bound-waiver hint `check()` prints on `waiver-base-mismatch`, `waiver-unbound-retargeted` and `waiver-timeline-unknown` instead of grepping the source.
2. FIX 11: the commit-level bound waiver names the commit's first parent literally (`waiver_bases`, exact), not any base with the same merge base; fixture 114 and a real-git sibling-commit case. No existing fixture changed.
3. FIX 2, 4, 6 (the threat model): the two wrong BL citations (D18); the python image residual's severity "provisional, confirmed by no one yet"; dfe-10's SEC-020 update says the stacked base's text is still printed, labelled, beside the fixed line. `verifier.yml` now labels and defangs the bootstrap path's output (the PR head's own classifier) and its fixed line there names `--bootstrap`. The R9 pin covers REQ-350 and REQ-334 and requires each cited BL id to be listed in `docs/BACKLOG.md`.
4. FIX 3: `test_constitution_articles.sh` counts named files, never directories (R2(b)).
5. FIX 5: `init-project.sh`'s `templates/BACKLOG.md` guard is a precondition, before any effect.
6. FIX 7: the flutter checklist's Entitlements item says an embedded key the committed set lacks stops the signing.
7. FIX 8: `test_workflow_health.sh` 1b exempts only the fixed bootstrap line, matched whole.
8. FIX 9: `review-gate.md` step 4 and the glossary say to post the legacy `sha:<head>` form on a PR whose base's classifier predates P7 (this PR; an instance's first upgrade PR after v3.2.0).
9. FIX 10: the security floor leaves out a `requirements*.txt` that lists no package, with a NOTE line (osv-scanner 2.6.0 exits 128 on it alone, measured).

Results: gates exit 0 (Gate failures: none, Floor failures: none), wall-clock 3:15 (195 s) at load averages 2.97 / 3.25 / 5.02 at the start and 9.98 / 6.55 / 6.07 at the end (`uptime`; two instance test runs overlapped its last minute); `check-test-first.sh --base refs/remotes/origin/main --head HEAD` PASS (16 commits); `check-covers.sh` PASS; actionlint clean. The eight changed governance tests pass in a python and a tauri instance (`SPECFLOW_NO_SCAFFOLD=1` init), SKIPs printed (attestation 3, threat_model_current 1, backlog 16 — the init cases' SKIP line new in this wave — release_apps 8).

### Fix wave 2 (2026-10-03, PR #65 verifier run 1)

The headless verifier's run 1 on PR #65 (APPROVE at fe3078c, base 34b0bbb) folded. Each FIX was pinned first and seen red, then changed, then green:

1. FIX 1 (finding 1, medium): `review-gate.md`'s patch tier states the `/release` fallback-line follow-up once, as the exception inside "Does not qualify" — no bullet admits a release artifact beside one that refuses every release artifact. Pinned in `test_review_gate_claims.sh` (red: the separate bullet stood).
2. FIX 2 (finding 4, medium): Task 1.7 Step 4 and its result say what ran — the final review's three lenses (three opus agents), the fix waves' scoped re-reviews, the headless verifier as solo mode's second review.
3. FIX 3 (code mode, low): the python Dockerfile gives `/app` (its `WORKDIR`) to uid 10001 at build time, so an app that writes under its working directory runs. Pinned in `test_release_python.sh`'s opt-in `SPECFLOW_DOCKER=1` case (red with the old Dockerfile: `touch: cannot touch './.w': Permission denied`). The deploy contract names no directory, so README and `deploy.sh` are unchanged.
4. FIX 4 (finding 7, low): the glossary's legacy-waiver sentence names the waiver row's events (`base_ref_changed`, `automatic_base_change_succeeded` or `_failed`, `base_ref_force_pushed`, any `base_ref_*` or `automatic_base_change*` event), "at or after the second it was posted", and its fail-closed reasons. Pinned in `test_review_gate_claims.sh`, which compares the two lists (red: the glossary lacked `_failed`, `base_ref_*`, `automatic_base_change*`).
5. FIX 5 (finding 8, low): the threat model's dfe-2 row states R4's waiver rules (`base:<40-hex base>`, the timeline read, `waiver-base-mismatch` / `waiver-unbound-retargeted` / `waiver-timeline-unknown`, refused, never blocking) and cites fixtures 103–114. Pinned in `test_threat_model_current.sh`.
6. FIX 6 (Covers, low): `# Covers: REQ-351` beside `test_first_run.sh`'s opt-in uid check.
7. FIX 7 (code mode, low): `run-security-floor.sh` writes an omitted empty lockfile into the floor record's result for that scope (`clean; empty lockfile stacks/python/skeleton/requirements-runtime.txt omitted` in this tree's real run), not on stdout alone. The pin's render-and-`check-review` round trip also found fix wave 1's all-empty root recorded `not run — no tracked lockfile lists a package` beside exit `-`, which `floor.py check-review` refuses (only `not run — no tracked lockfile` is accepted there): the record now carries that accepted result, the printed line keeps the distinction. Pinned in `test_security_floor.sh` (red on both).
8. RECORD 8 (finding 2): Task 1.1 Step 0 names M0b as a merge precondition, with the exact probe, what to record and the two outcomes. RECORD 10: D19 (REQ-313/REQ-385 not in `implements:`); D14 keeps the time budget.

Results: gates exit 0 (Gate failures: none, Floor failures: none), wall-clock 3:14 (194 s) at load averages 2.45 / 2.34 / 2.64 at the start and 7.57 / 5.48 / 3.95 at the end (`uptime`); actionlint clean; the five changed governance tests pass in a scaffolded python instance, SKIPs printed (threat_model_current 1, release_python 16, first_run 1); `SPECFLOW_DOCKER=1 test_release_python.sh` passes in the template source (the `/app` check included). The plan header's "Neither build edits `scripts/init-project.sh` or any workflow" is false for this build because of the sanctioned corrections — SEC-020's `verifier.yml` (correction 2; SEC-021's is `run-verifier.sh`, correction 1) and `init-project.sh` (correction 9); D15, the header is the retrospective's to amend, and the human reviewer should read `verifier.yml`'s diff directly (dfe-10's claims: the classifier's exit code kept, its untrusted output wrapped in `::stop-commands::`, the fixed bootstrap line printed).

## Build 2: The habit-tracker example's home, the demo re-tag's follow-up path, REQ-392's record (REQ-391, REQ-392; REQ-306, REQ-324 slices)

Cut `build/factory-v3-2-p7-2` from `main` after the design PR merges, in parallel with Build 1 (R1).

### Task 2.1: `docs/examples/habit-tracker/` and its manifest subsection — kept by a tauri instance, removed by every other stack, inert to the gates, documents only; REQ-392's record (REQ-391, REQ-392, REQ-306; R10, R12)

**Files:** `docs/examples/habit-tracker/README.md` (new; it ships to every tauri instance with the example, so it holds no factory-maintainer instruction (design review, polish item 3; REQ-306, REQ-391 — the example's documents ship to tauri instances, the walk's checklist does not): what the example is; its provenance — the throwaway repository, `v3.2.0` or `fbd432a`, tauri, guided, solo, the second Mac and the tester instructions; the layout of Interfaces "The example"; an `## Evidence` section, empty until M6 fills it with what M1–M5 kept; the status line); `docs/examples/README.md` (new, factory-only: the index — `habit-tracker/` (REQ-391, tauri) and the demo greeting's location —, `## The habit-tracker walk (REQ-391)`: the walk's checklist M1–M6 and the evidence to copy back, verbatim from the section "Maintainer checklist", and `## External product (REQ-392)`: R12's definition of met, the fields to record (repository or description, Release URL, `release.yml` run id, the manifest's `signed`), and the line `Status: not met (v3.2.0's known-limitations records it open; docs/BACKLOG.md BL-019).`); `CLAUDE.md` (the `## Canonical Example` section, `:108`: the `### habit_tracker (stack: tauri)` subsection of Interfaces "The example", after `### demo_greeting (stack: python)` and its list (`:115-126`), before `## Critical Never-Do` (`:128`)); `scripts/factory-only.txt` (`docs/examples/README.md`: the factory's index, the walk's checklist and REQ-392's record are the factory's; a file under `docs/examples/habit-tracker/` could not be fenced, since init never fences a path the manifest lists or a file under one, `init-project.sh:633`, `:654`); `tests/governance/test_examples.sh`; this plan's `implements:` (REQ-391, REQ-392 join).

**Not edited:** `scripts/lib/specflow/examples.py` and `scripts/init-project.sh` — a directory token covers the example's tree, and init's loop already removes every example whose stack is not the instance's (`init-project.sh:616-628`), so REQ-306's "the REQ-391 example's artifacts when `stack != tauri`" holds once the subsection exists; the tests below prove it.

- [x] **Step 1: Write the failing tests.** In `test_examples.sh`, after the manifest-path checks (template-source section) and the per-stack init loop:
```bash
# REQ-391, REQ-306 (P7 R10): the second worked example — documents only, under docs/examples/habit-tracker/, listed in
# the manifest as habit_tracker (stack: tauri): a tauri instance keeps it, every other stack's init removes it and its
# subsection; it is inert to every gate (they glob top-level pipeline directories only); it holds .md and .txt files only;
# no secret hides under the gitleaks allowlist for docs/**/examples/; no transcript carries a home directory path.
# Covers: REQ-391
# Covers: REQ-306
ck "manifest lists habit_tracker (stack: tauri)" grep -qx 'habit_tracker tauri' <<<"$names"
ck "the example's paths are its README and its tree" \
  bash -c '[ "$(python3 "$1" --root "$2" list habit_tracker | sort | tr "\n" " ")" = "docs/examples/habit-tracker/ docs/examples/habit-tracker/README.md " ]' _ "$EXPY" "$ROOT"
ck "the example is documents only: .md and .txt files, nothing else" \
  bash -c '! find "$1/docs/examples/habit-tracker" -type f ! -name "*.md" ! -name "*.txt" | grep -q .' _ "$ROOT"
ck "the example's README states its status, provenance and layout, and has an Evidence section" \
  bash -c 'f="$1/docs/examples/habit-tracker/README.md"; grep -qE "^Status: (pending the maintainer'"'"'s walk \(REQ-391\)\.|walked on [0-9]{4}-[0-9]{2}-[0-9]{2} from (v3\.2\.0|fbd432a); Release: https://\S+\.)$" "$f" && grep -qx "## Evidence" "$f" && for w in "profile: guided" "solo: true" "tester instructions" "second Mac" "transcripts/"; do grep -qF -- "$w" "$f" || exit 1; done' _ "$ROOT"
ck "the example's README carries no factory-maintainer instruction (it ships to tauri instances): no M1–M6 checklist, no gitleaks recipe" \
  bash -c '! grep -qE "^- \*\*M[0-9]+ —|Maintainer checklist|gitleaks dir" "$1/docs/examples/habit-tracker/README.md"' _ "$ROOT"
ck "once walked, the copied docs/ tree and at least one /next transcript exist" \
  bash -c 'f="$1/docs/examples/habit-tracker"; grep -q "^Status: pending" "$f/README.md" || { test -d "$f/docs/specs" && ls "$f"/transcripts/[0-9][0-9]-*.txt >/dev/null 2>&1; }' _ "$ROOT"
ck "no transcript or copied document names a home directory" \
  bash -c '! grep -rqE "/(Users|home)/[A-Za-z0-9._-]+/" "$1/docs/examples/habit-tracker"' _ "$ROOT"
if command -v gitleaks >/dev/null 2>&1; then
  printf 'title = "no allowlist"\n[extend]\nuseDefault = true\n' > "$WORK/noallow.toml"
  ck "gitleaks with no allowlist finds nothing under docs/examples/ (the template's .gitleaks.toml skips it)" \
    gitleaks dir "$ROOT/docs/examples" --config "$WORK/noallow.toml" --no-banner --redact
fi
for s in python flutter; do
  D="$WORK/hx-$s"; copy_template "$D"
  ck "$s init drops the habit-tracker example and its subsection" \
    bash -c 'cd "$1" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Hx --stack "$2" </dev/null >/dev/null 2>&1 && ! test -e docs/examples/habit-tracker && ! grep -q "^### habit_tracker" CLAUDE.md' _ "$D" "$s"
done
D="$WORK/other-tauri"
ck "tauri instance keeps docs/examples/habit-tracker/ and its subsection, and loses the factory's docs/examples/README.md" \
  bash -c 'test -f "$1/docs/examples/habit-tracker/README.md" && grep -q "^### habit_tracker (stack: tauri)" "$1/CLAUDE.md" && ! test -e "$1/docs/examples/README.md"' _ "$D"
ck "the example is inert: a spec, a plan, two ADRs and a security review planted under the example tree — a [verifiable-model] REQ the plan claims with no proof, a missing ADR-009 the plan names, a duplicate ADR-001, a SEC id — leave the tauri instance's document gates green" \
  bash -c 'cd "$1" && E=docs/examples/habit-tracker/docs && mkdir -p $E/specs $E/security $E/adr $E/plans && printf -- "---\ntype: spec\n---\n- **REQ-001:** x [verifiable-model]\n" > $E/specs/2026-10-05-habit-tracker-design.md && printf -- "---\ntype: plan\nspec: 2026-10-05-habit-tracker\ndecisions: [ADR-009]\nimplements: [REQ-001]\n---\n" > $E/plans/2026-10-05-habit-tracker-plan.md && for n in 101 102; do printf -- "---\nid: ADR-001\n---\n# ADR-001\n" > $E/adr/$n-x.md; done && printf "SEC-001\n" > $E/security/0.1.0-review.md && bash scripts/check-traceability.sh >/dev/null && bash scripts/check-covers.sh >/dev/null && bash scripts/analyze-adr-plan-linkage.sh >/dev/null && bash scripts/check-architecture.sh >/dev/null' _ "$D"
# REQ-392 (P7 R12): the factory's record of the external product: what met looks like, the fields, the status.
# Covers: REQ-392
X="$ROOT/docs/examples/README.md"
factory_doc_ck "docs/examples/README.md records REQ-392: the definition of met, the fields, and a status line" "$X" \
  bash -c 'grep -q "^## External product (REQ-392)$" "$1" && for w in "release.yml" "run id" "Release URL" "signed" "BL-019"; do grep -qF -- "$w" "$1" || exit 1; done && grep -qE "^Status: (not met \(v3\.2\.0'"'"'s known-limitations records it open; docs/BACKLOG\.md BL-019\)\.|met on [0-9]{4}-[0-9]{2}-[0-9]{2}: .+)$" "$1"' _ "$X"
factory_doc_ck "the fence lists docs/examples/README.md" "$ROOT/scripts/factory-only.txt" grep -qx 'docs/examples/README.md' "$ROOT/scripts/factory-only.txt"
# REQ-391 (P7 R10; design review, polish item 3): the walk's checklist is the factory maintainer's — it lives in the fenced
# index, never in the README that ships to tauri instances.
factory_doc_ck "docs/examples/README.md carries the habit-tracker walk's checklist M1–M6 and its gitleaks step" "$X" \
  bash -c 's=$(awk "/^## The habit-tracker walk \\(REQ-391\\)\$/{f=1; next} /^## /{f=0} f" "$1"); for m in 1 2 3 4 5 6; do grep -qE "^- \*\*M$m — " <<<"$s" || exit 1; done; grep -qF "gitleaks" <<<"$s"' _ "$X"
```
(The tauri instance `$WORK/other-tauri` is the one the per-stack loop already scaffolds with `SPECFLOW_NO_SCAFFOLD=1`; the inert check writes into that throwaway copy only. The same files planted under the top-level `docs/` fail: measured 2026-10-03 in a copy of the template at this branch's head — `check-traceability.sh` "REQ-001 … is [verifiable*] and implemented but no proof carries 'Proves: REQ-001'" and "duplicate ADR id ADR-001", `analyze-adr-plan-linkage.sh` "REQ-001 not covered by any accepted ADR in decisions: ['ADR-009']" — and under `docs/examples/habit-tracker/docs/` all four gates exit 0.)
- [x] **Step 2: Run red.** `bash tests/governance/test_examples.sh` — the manifest, README, fence, walk-checklist and tauri-keeps checks FAIL; the python/flutter drop checks pass vacuously (nothing to drop), which is why the tauri check pins the subsection's presence.
- [x] **Step 3: Write**, as intent: the two READMEs (the factory's index carries `## The habit-tracker walk (REQ-391)` with the section "Maintainer checklist" M1–M6 verbatim and the evidence to copy back; the habit tracker's carries no maintainer instruction — what it is, provenance, layout, an empty `## Evidence`, the status line pending), the manifest subsection, the fence line; `implements:` gains REQ-391 and REQ-392.
- [x] **Step 4: Run green**, plus `bash tests/governance/test_reviews_use_slugs.sh`, `bash tests/governance/test_first_run.sh` (not opt-in: its default cases), `bash scripts/check-covers.sh` (REQ-391 and REQ-392 now claimed and cited).
- [x] **Step 5: Commit:** `examples: the habit tracker's home and manifest subsection — tauri keeps it, others drop it, inert and documents-only; REQ-392's record (REQ-391, REQ-392, REQ-306)`.

### Task 2.2: The demo re-tag's follow-up path — the released known-limitations may lose its stale fallback section once its tag is SSH-signed (REQ-324, REQ-391; R11)

**Files:** `tests/governance/test_verify_release.sh` (`:162-166`).

**Interfaces:** the `/release` follow-up exception (`release.md`: "the removal of a stale fallback line once a signed tag was created") applied to the inherited demo: the file may differ from its state at `v0.0.1-demo` only when that tag is SSH-signed by a key `.github/allowed_signers` lists and the signature verifies — `git verify-tag` with that file as committed at `HEAD`, `gpg.ssh.program` pinned to the `ssh-keygen` on PATH, `.github/revoked_signers` at `HEAD` as the revocation list, and the principal ssh-keygen reports equal to the tagger (amended by Build 2's final review, finding 3: the original text, a `-----BEGIN SSH SIGNATURE-----` substring in `git cat-file -p`, admitted an unsigned tag carrying the marker in its message and a signature by an unlisted key) — and the file is exactly the tagged one with its `## Unsigned tag (follow-up required)` section removed (that heading up to the next `## ` heading — on the real file, lines `:8-22`, leaving `## No other findings`); otherwise it must be unchanged. Any other edit — another section removed, a line added — is refused. `release_gate.LEGACY_FALLBACK_VERSIONS` and `verify-release.sh` are unchanged: the demo is never the previous release of a later version (R11's measurement).

- [x] **Step 1: Write the failing test.** `:162-166` become:
```bash
# P7 R11 (REQ-324, REQ-391): the inherited demo's released known-limitations is unchanged since its tag, except the
# /release follow-up's removal of its stale "## Unsigned tag (follow-up required)" section once v0.0.1-demo is re-tagged
# SSH-signed — exactly that section removed, nothing else changed (design review, polish item 3: a pure-removal rule
# would admit deleting any section).
# Covers: REQ-324
# Covers: REQ-391
demo_kl_ok() {  # demo_kl_ok REPO FILE — unchanged since v0.0.1-demo, or the tag is SSH-signed and FILE is the tagged one minus that section
  git -C "$1" diff --quiet v0.0.1-demo -- "$2" && return 0
  git -C "$1" cat-file -p refs/tags/v0.0.1-demo | grep -qF -- "-----BEGIN SSH SIGNATURE-----" || return 1
  git -C "$1" show "v0.0.1-demo:$2" | python3 -c '
import re, sys
old, new = sys.stdin.read(), open(sys.argv[1]).read()
m = re.search(r"(?ms)^## Unsigned tag \(follow-up required\)\n.*?(?=^## |\Z)", old)
sys.exit(0 if m and new == old[:m.start()] + old[m.end():] else 1)' "$1/$2"
}
if git -C "$ROOT" rev-parse -q --verify refs/tags/v0.0.1-demo >/dev/null 2>&1 \
   && git -C "$ROOT" cat-file -e v0.0.1-demo:docs/releases/0.0.1-demo-known-limitations.md 2>/dev/null; then
  ck "the released v0.0.1-demo known-limitations is unchanged since its tag, or lost only its stale fallback section by the /release follow-up (SSH-signed tag)" \
    demo_kl_ok "$ROOT" docs/releases/0.0.1-demo-known-limitations.md
fi
DK="$(mktemp -d)"
(cd "$DK" && git init -q -b main && printf '# KL\n\n## Unsigned tag (follow-up required)\nannotated fallback\n\n## No other findings\nnone\n' > kl.md \
  && git add kl.md && git commit -qm one && git tag -a -m demo v0.0.1-demo && sed -i.bak '3,5d' kl.md && rm -f kl.md.bak && git commit -qam removal)
ck "fixture: an annotated (unsigned) demo tag and the section's removal — refused" no demo_kl_ok "$DK" kl.md
ssh-keygen -q -t ed25519 -N "" -C demo -f "$DK.key"
(cd "$DK" && git tag -d v0.0.1-demo >/dev/null && git -c gpg.format=ssh -c user.signingkey="$DK.key" tag -s -m demo v0.0.1-demo HEAD~1)
ck "fixture: an SSH-signed demo tag and the stale fallback section removed — admitted" demo_kl_ok "$DK" kl.md
(cd "$DK" && git checkout -q v0.0.1-demo -- kl.md && sed -i.bak '6,7d' kl.md && rm -f kl.md.bak && git commit -qam other)
ck "fixture: an SSH-signed demo tag and another section removed (a pure removal, not the fallback section) — refused" no demo_kl_ok "$DK" kl.md
(cd "$DK" && git checkout -q HEAD~1 -- kl.md && echo "a line added after the tag" >> kl.md && git commit -qam addition)
ck "fixture: an SSH-signed demo tag, the section removed and a line added — refused" no demo_kl_ok "$DK" kl.md
rm_tree "$DK"; rm -f "$DK.key" "$DK.key.pub"
```
- [x] **Step 2: Run red.** The old pin's rule (`git -C <fixture> diff --quiet v0.0.1-demo -- kl.md`) run against the fixture's SSH-signed section removal exits 1: the follow-up M8 needs is refused today (record that run in the commit body). The new rule was measured in a scratch repository on 2026-10-03 (ssh-keygen ed25519, `gpg.format=ssh`, this fixture): unsigned tag and the section removed → 1; SSH-signed and the section removed → 0; SSH-signed and another section removed → 1; SSH-signed, the section removed and a line added → 1; unchanged → 0. On the real file, removing the section leaves exactly the frontmatter, the title and `## No other findings`.
- [x] **Step 3:** replace the old pin with `demo_kl_ok`'s real-tree check (no source change: the exception already exists in `release.md` and in `review-gate.md`'s RELEASE exit gate; Build 1 adds the patch-tier sentence, R11).
- [x] **Step 4: Run green**: `bash tests/governance/test_verify_release.sh`.
- [x] **Step 5: Commit:** `test(verify-release): the demo's released known-limitations may lose its stale fallback section once its tag is SSH-signed (REQ-324, REQ-391)`.

### Task 2.3: Build 2's whole-build verification

**Files:** this plan's `## Build 2` section and `implements:`.

- [x] **Step 1:** `git diff refs/remotes/origin/main --stat` — no kernel file, constitution, spec, `docs/security/`, `docs/releases/`, `init-project.sh` or `examples.py`; in the backlog only BL-028 … BL-031's **Absorbed:** lines (and `tests/governance/test_backlog.sh`'s pin of them), the recorded correction below; `--name-only` ⊆ Build 2's column plus those two files.
- [x] **Step 2: Inside scaffolded instances:** tauri, python and flutter (`SPECFLOW_NO_SCAFFOLD=1` for the app stacks): `test_examples.sh`, `test_verify_release.sh`, `test_reviews_use_slugs.sh`, `test_spec_lifecycle.sh` pass or SKIP visibly; the tauri instance keeps `docs/examples/habit-tracker/README.md`, the others do not; no instance has `docs/examples/README.md`.
- [x] **Step 3:** the gates (exit 0); `bash scripts/check-test-first.sh --base refs/remotes/origin/main`.
- [x] **Step 4:** the final review; the PR body lists **Gate code** (`CLAUDE.md`, `scripts/factory-only.txt`) and no architecture-artifact update.

#### Task 2.3's verification record (fix wave 1, 2026-10-03, at `0c25b34` on `e73a942`)

- **Step 1.** `git diff refs/remotes/origin/main --name-only`: `CLAUDE.md` (the `## Canonical Example` section only),
  `docs/BACKLOG.md` (BL-028 … BL-031's **Absorbed:** lines only), `docs/examples/README.md`,
  `docs/examples/habit-tracker/README.md`, this plan (this section and `implements:`), `scripts/factory-only.txt`,
  `tests/governance/test_backlog.sh`, `tests/governance/test_examples.sh`, `tests/governance/test_verify_release.sh`. No
  kernel file, constitution, spec, `docs/security/`, `docs/releases/`, `init-project.sh` or `examples.py`.
- **Step 2.** In a tauri and a flutter instance (`SPECFLOW_NO_SCAFFOLD=1`) and a python instance, initialised from a copy
  of this branch's tree: `test_examples.sh`, `test_verify_release.sh`, `test_reviews_use_slugs.sh` and
  `test_spec_lifecycle.sh` exit 0 in each, with SKIPs printed (`test_examples.sh`: "remaining cases run in the template
  source"; `test_verify_release.sh`: the CI-path and tauri-pack cases). The tauri instance keeps
  `docs/examples/habit-tracker/README.md` and nothing else under `docs/examples/`; the python and flutter instances have
  an empty `docs/examples/`; no instance has `docs/examples/README.md`.
- **Step 3.** `run-quality-gates.sh` (with `~/.venvs/factory-tools/bin` first on PATH): exit 0, "All quality gates
  passed", about 210 s at load 8–14. `check-test-first.sh --base refs/remotes/origin/main --head HEAD`: PASS, 5 commits.
  `check-covers.sh`: PASS, 57 claimed REQs.
- **Step 4.** The final review and the verifier dry run returned no critical or high finding; PR #64's body lists the gate
  code (`CLAUDE.md`'s Canonical Example section, `scripts/factory-only.txt`, the three governance tests).
- **Red runs Task 2.1 Step 2 and Task 2.2 Step 2 asked for** (fix wave 1, finding 9: commit `cb2ab8f`'s body lacks them, and
  history is not rewritten). Re-measured on 2026-10-03 in a scratch tree of `e73a942` with the build's tests laid over
  it: `test_examples.sh` as of `9069098` printed 8 FAIL lines (the manifest lists `habit_tracker`; the example's paths;
  the README's status, provenance and layout; the copied tree once walked, which fails without the README; the tauri
  instance keeps the example; REQ-392's record; the fence line; the walk's checklist M1–M6), and `test_backlog.sh` as of
  `1053fc4` printed 1 (BL-028 … BL-031's **Absorbed:** lines). The old pin's rule,
  `git diff --quiet v0.0.1-demo -- kl.md`, run against the fixture's SSH-signed tag (one `-----BEGIN SSH SIGNATURE-----`
  block) and the stale section removed, exited 1: the follow-up was refused.
- **Fix wave 1** (final review and verifier dry run on PR #64), each red before its change: finding 1 (the scratch
  instance's gates inherit `GITHUB_HEAD_REF`/`SPECFLOW_HEAD_BRANCH`; reproduced with `GITHUB_HEAD_REF=ship/3.2.0` exported:
  the inert check FAILed; fixed as `e73a942` did, `env -u` on the five gates and the trailing disposition call; new checks
  with either variable at `ship/9.9.9`: red, then green); finding 2 (with `ssh-keygen` off PATH the test aborted rc 127;
  now three SKIP lines, the pre-existing `--at-tag` signing section guarded too); finding 3 (that abort left the empty
  `$DK` behind; `$DK` now lives under the trap's `$W`; the duplicated cleanup line had already gone in `18df4e5`);
  finding 4 (the demo re-tag checks cite REQ-391 only); finding 5 (no line at all with `gitleaks` off PATH; now a SKIP);
  finding 6 (a new check refused "a tester on a second Mac opens the bundle" while pending; both texts now say "will
  open"); finding 7 (the copy rule; its check FAILed before `docs/examples/README.md` gained it); finding 8 (the new status
  regex FAILed on the old line, which assumed the v3.2.0 known-limitations on this tree; the commit body's wording of
  that red, "the old status regex FAILed on the new line", has it backwards — this line is the record); finding 10 (met
  by `18df4e5`: `demo_tag_signed` runs `git verify-tag`, no substring test).

### Recorded deviations (Build 2)

- **The BL-028 … BL-031 wording (`docs/BACKLOG.md`, `tests/governance/test_backlog.sh`), outside R1's Build 2 column.** Commit `1053fc4` (first written as `a72922b`, before the rebase onto `e73a942`) rewrites those four entries' **Absorbed:** lines from "the retrospective records `accepted (landed: …)`" to "the v3.2 retrospective is expected to record `accepted (landed: …)`", and `test_backlog.sh` pins the future tense and **Status:** open. Why: the old wording read as a decision already recorded, and only a retrospective writes decisions (R13; R17 itself says each entry stays open). The edit writes no decision line and changes no status, so R13's "the builds do not edit `docs/BACKLOG.md`" is kept in substance; the finding came to this build with its task, cited in that commit as "P7 design review run 2, finding 4" (no plan document records it; this note is its record). Task 2.3 Step 1 is amended to allow exactly these two files. Merge risk: Build 1's column does not include `test_backlog.sh` or `docs/BACKLOG.md`; the new check is appended after the BL-002 check, so a concurrent edit elsewhere in the file merges cleanly.
- **The walk's checklist is the plan's M1–M6, verbatim, plus one step added to M6** (final review, findings 2 and 7). `docs/examples/README.md` first carried a condensed M1–M6 that dropped the private-clone note, moved the `release` environment probe ahead of M2's `configure-repo.sh` (which creates the environment), and dropped the `allowed_signers` line format, the `unsigned-tag` choice and the second Mac's account. It now carries the six bullets exactly as the section "Maintainer checklist" has them, and `test_examples.sh` fails when any differs. The one addition, after the list: before M6's gates, run `bash tests/governance/test_reviews_use_slugs.sh` on the copied tree (finding 1). It is added there rather than to this plan's M6, which belongs to the section "Maintainer checklist", outside Build 2's section.
- **`v3.2.0` ships the pending stub to tauri instances** (final review, finding 8). This build's reading: yes. The walk can only start from `v3.2.0` (M1 clones it), so the example cannot be filled before `v3.2.0` is cut; REQ-306 removes it from every other stack; and the manifest's path tokens must exist (`test_examples.sh`). A tauri instance made from `v3.2.0` therefore receives `docs/examples/habit-tracker/README.md` with `Status: pending the maintainer's walk (REQ-391).`, and the copy-back reaches instances from the next factory release on. So that this stub never claims a walk that has not happened, the README and the `### habit_tracker (stack: tauri)` subsection state the walk as intent and point at the README's Status line; `test_examples.sh` fails a past-tense "tester opened" while the status is pending. If the maintainer prefers that `v3.2.0` ship no stub, the alternative is to land the subsection with the copy-back (M6) instead, in the ship lane's or the retrospective's call.
- **The inert check runs against a base ref, with a positive control** (final review, finding 5). As first written, its disposition sub-check SKIPped ("no base ref origin/main"), so it proved nothing. The tauri instance now gets `refs/remotes/origin/main` at init's commit. The plant is committed on a branch, and the same plant under the top-level `docs/` must fail all five document gates, the disposition gate included (exit 2, "run /security-review"). Under the example tree all five exit 0, and the disposition gate says the PR "touches no docs/security/".
- **The demo re-tag rule verifies the signature** (final review, finding 3; Task 2.2's Interfaces amended above). `demo_kl_ok` admits the section's removal only when `git verify-tag` (the pins above) succeeds and ssh-keygen's principal is the tagger. New fixtures refuse an unsigned tag whose message carries a fake signature block, a signature by an unlisted key, and a signature by a listed key that `.github/revoked_signers` lists. Red before the change: those three fixtures FAILed under the substring rule. `signers.verify` is not used because its anchor (the newest earlier SSH-signed release tag below the tag's commit, else trust on first use) does not exist below the demo's commit `792cecb`.

### Deferred corrections (for the retrospective or the owning PR)

- **R10 (plan header), Review Focus 5 and "Instance-visible readers of `docs/`" (plan header): "every gate globs top-level pipeline directories only" is too broad as R10 states it.** The pipeline gates (traceability, covers, the ADR linkage, the architecture check, the disposition gate, `verify-release.sh`) do read only the top-level pipeline directories. But `tests/governance/test_reviews_use_slugs.sh` runs in gates section 3 and reads every `docs/**/*.md`, `docs/examples/` included: it applies the Roman-numeral ban and amendment C's slug-existence check to the example tree. This was measured in a scratch tauri instance: an undefined slug and a numeral citation planted under `docs/examples/habit-tracker/docs/` fail it, naming the file. The header's readers paragraph names that walker; R10's sentence and Review Focus 5 do not. Build 2 narrowed its own column's sentences, the example README and `test_examples.sh`'s comment, and pinned the behaviour (`test_examples.sh`). It also added the check to the walk's M6 in `docs/examples/README.md`. Owner of the open question, whether `test_reviews_use_slugs.sh` should exclude `docs/examples/` (an example copied from an instance cites that instance's constitution, which a later retrospective may amend): amendment C's owner or the v3.2 retrospective. Build 2 does not edit that test (amendment C's file).
- **The section "Maintainer checklist", M6 (outside Build 2's section):** it should gain the article-citation step that `docs/examples/README.md` adds after its M1–M6 (above). Until then the fenced index is where that step lives. Owner: the retrospective, or the PR that next edits the checklist; `test_examples.sh` compares only M1–M6, so the plan's M6 gaining the sentence breaks nothing as long as the index's M6 gains it in the same PR. Done by amendment D's PR (2026-10-04; BL-041): the plan's M6 and the index's M6 gain the step in the same PR, and the index's separate "Added to M6" paragraph is folded into M6.
- **Task 2.1 Step 1's quoted test (this section, historical):** its comment "it is inert to every gate (they glob top-level pipeline directories only)" and its inert check without a base ref are superseded by the committed `test_examples.sh` (the deviation above). The step's text is kept as the plan that was reviewed, not rewritten after the fact.
- **The demo re-tag rule's residual:** `demo_tag_signed` reads `.github/allowed_signers` at the checkout's `HEAD`, which is a PR's head at PR time. A PR that adds a key could therefore admit a tag signed by that key. Two things bound this: such a PR is itself a reviewed change to the signer list, and the tag must already exist on the remote, which only a tag-pusher (the admin bypass of the `release tags` ruleset) can create. Reading the file at the base ref instead would fail closed in a checkout with no `origin/main`. Owner: the retrospective, alongside BL-020.
- **R1's table and Task 2.3 Step 1 (fix wave 1, finding 11).** The sanctioned BL-028 … BL-031 correction edits
  `docs/BACKLOG.md` and `tests/governance/test_backlog.sh`, neither in R1's Build 2 column; Task 2.3 Step 1 was amended
  to allow exactly those two files (the deviation above), R1's table was not. Owner: the retrospective.
- **Task 2.1 Step 1's drop checks (finding 11).** The plan's quoted test runs a fresh `copy_template` and init for python
  and flutter; the committed test reuses the instances the per-stack loop already initialised (`$WORK/py`,
  `$WORK/other-flutter`) and also checks that no file is left under `docs/examples/` — stronger, and cheaper, but not the
  text that was reviewed. Owner: the retrospective (no change needed unless the plan text is to match).
  Accepted as the plan's reading by the retrospective (`docs/retrospectives/2026-10-04-v3-2-closeout.md`, Proposed
  Changes, item 4): the committed test, the reused instances and the empty `docs/examples/` check, is what this step means.
- **The inert check's scope (finding 11).** The plan's inert check runs four document gates; the committed one runs five,
  `check-security-disposition.sh` included, against a base ref with a positive control (the deviation above), and since
  fix wave 1 with `GITHUB_HEAD_REF` and `SPECFLOW_HEAD_BRANCH` unset. Owner: the retrospective.
  Accepted as the plan's reading by the retrospective (`docs/retrospectives/2026-10-04-v3-2-closeout.md`, Proposed
  Changes, item 4): five gates against a base ref with a positive control, as committed, is the inert check's scope.
- **R10's account of what an instance carries (finding 11).** R10 does not name the documents a tauri instance inherits
  under `docs/` besides the example; measured on this branch they are `docs/BACKLOG.md`, `docs/GLOSSARY.md`, ADR-002,
  `docs/adr/README.md`, `docs/architecture/README.md`, `docs/releases/README.md`, `docs/releases/store-checklist.md`,
  `docs/releases/tester-instructions.md`, `docs/retrospectives/README.md`, `docs/security/README.md` and
  `docs/security/RUBRIC.md`, which is why M6's copy rule (`docs/examples/README.md`) excludes them and
  `test_examples.sh` measures the set. Owner: the retrospective, alongside the plan's own M6.
- **The gates' wall-clock (finding 12).** Under host load 7–13 from the concurrent Build 1 session the gates took
  261–306 s, over the 3-minute budget, at this build's base and head alike (no attributable cost from the changed tests);
  fix wave 1's run took about 210 s at load 8–14. Owner: the retrospective (the budget, or the runner).

## Maintainer checklist — REQ-391, REQ-392, the re-tag, R15 (not a build; the maintainer's, by hand)

Each item says what to run and what evidence to keep. Agents never run these. `export GH_TOKEN="$(gh auth token --user kpingali123)"` first in every shell that runs `gh` or tags.

- **M0 — before the walk.** `bash scripts/configure-repo.sh` on the factory (R15: sets `allow_rebase_merge: false`; confirms the ruleset and environment) and `gh api repos/Apps-Consultants/factory --jq .allow_rebase_merge` answers `false`. If Docker Desktop is available, run Task 1.4's opt-in case once: `SPECFLOW_DOCKER=1 bash tests/governance/test_release_python.sh` on `main` after Build 1 merges.
- **M0b — the timeline probe (R4; Build 1's Task 1.1 Step 0).** A merge precondition of Build 1's PR, measured on probe PR #67 (run 37169624336, 2026-10-04 UTC) after the classifier was written (D14; Task 1.1 Step 0): on a throwaway branch `probe/timeline-token` from `main`, add `.github/workflows/probe-timeline.yml` (`on: pull_request`, `permissions: contents: read, issues: read, pull-requests: read`, one step: `gh api --paginate "repos/$GITHUB_REPOSITORY/issues/48/timeline" --jq '[.[] | select(.event == "base_ref_changed") | .created_at]'` with the job's `GITHUB_TOKEN` exported as `GH_TOKEN`), open it as a draft PR, read the run, close it unmerged and delete the branch. Keep: the run id, the HTTP status, the answer (expected `["2026-09-30T11:25:56Z"]`). A failure triggers R4's fallback (the timeline rule dropped).
- **M1 — the throwaway instance (R10).** After `v3.2.0`'s Release is published: `git clone https://github.com/Apps-Consultants/factory.git habit-tracker && cd habit-tracker && git checkout --detach v3.2.0 && rm -rf .git && git init -b main`; create an empty private repository (a personal account reproduces the founder's free-plan path — about 200 macOS minutes a month, one tauri release costs about 100; the evidence records which account and plan), `git remote add origin <url>`. The factory is private: the HTTPS clone needs `gh auth setup-git` first (or clone over the SSH alias, `git@github.com-appsconsultants:Apps-Consultants/factory.git`). **Probe the `release` environment on the chosen plan** (fresh-eyes review, finding 17): `release.yml`'s `signing-probe` job declares `environment: release` unconditionally (`release.yml:460`, and the macOS job `:491`), and whether a job that names an environment runs on a GitHub Free personal private repository is unmeasured — after M2's `configure-repo.sh`, read `gh api repos/<owner>/<repo>/environments` and record the answer; if the environment cannot exist there, use an organisation repository or a public one for the walk and record which. Keep: the repository URL (or a description), the account and plan, the environment probe's answer, the commit `v3.2.0` names.
- **M2 — init.** First `bash scripts/init-project.sh --doctor --stack tauri` on the build Mac (Rust, Node, the Xcode command-line tools; fix every `MISSING` line it prints), then `bash scripts/init-project.sh` interactively: profile guided (Enter), name "Habit Tracker", "What are you building?" → the Mac desktop choice (tauri), solo (Enter); then `git push -u origin main` and `bash scripts/configure-repo.sh` (on a free private repository it reports the 403s; keep its output). Keep: the init transcript, `.specflow.yml`.
- **M3 — the walk.** In Claude Code inside the instance, run `/next` at every step and do what it prints or runs, from `IDEA.md` (a macOS habit tracker: add a habit, check it off today, a streak) through `design/<slug>` (brainstorm, spec, architecture, plan, tasks, analyze), every `build/<slug>-N`, to `ship/0.1.0`; run the verifier in a second terminal exactly as `/next` prints it; merge only when `/next` prints the merge. **Save every `/next` output** to `transcripts/NN-<where>.txt` as you go (NN two digits in run order, `<where>` the branch with `/` → `_`, or `main`). **Before `ship/0.1.0`** (fresh-eyes review, finding 17): the instance's `.github/allowed_signers` starts comment-only (`init-project.sh:684-694`), and `release-tag.sh` refuses an SSH-signed tag no anchor or first-use key covers (exit 6) — so add the maintainer's own key line (`<git email> namespaces="git" <the .pub contents>`, exactly as `git config user.email` spells it) by a reviewed `patch/allowed-signers` PR merged before the ship branch is cut (trust on first use: the key is trusted from the release after the first one tagged on a commit that lists it — the instance's first release `v0.1.0` then verifies as the first-use tag). If the maintainer instead takes the guided `unsigned-tag` path at M4, skip this and record the annotated fallback. Keep: every PR number and its verifier marker comment link.
- **M4 — the release.** After the ship PR merges: `/next` prints `/release --tag 0.1.0` (SSH signing configured per the instance's README; or the guided `unsigned-tag` confirmation and the annotated fallback); then `gh run watch` on the instance's `release.yml` run until it publishes. Keep: the Release URL, the run id, `manifest.json` (`signed: false`), the tester-instructions file.
- **M5 — the second Mac.** On another Mac (not the build machine), signed in to GitHub with an account that can read the private instance repository (a private repository's Release assets need it — or the walk used a public repository, M1), download the bundle from the Release page and follow `docs/releases/0.1.0-tester-instructions.md` exactly as written until the app opens and a habit can be checked off. Keep: the macOS version, each step that worked or did not, one screenshot reference (not committed), and a note of any instruction that was wrong — a wrong instruction is a finding for the retrospective, not a fix in the instance.
- **M6 — the copy-back (R10).** In the factory, on `patch/habit-tracker-example` from `main`: copy the instance's `docs/` tree at its Release commit to `docs/examples/habit-tracker/docs/`, the transcripts to `docs/examples/habit-tracker/transcripts/`, replace every home-directory path in the **whole copied tree** with `~` — transcripts and `docs/` alike, CI paths too, since `test_examples.sh` greps all of `docs/examples/habit-tracker/` for `/(Users|home)/<name>/` (`grep -rlE '/(Users|home)/[A-Za-z0-9._-]+/' docs/examples/habit-tracker | xargs sed -i '' -E "s#$HOME#~#g; s#/(Users|home)/[A-Za-z0-9._-]+/#~/#g"`, then the same `grep -rE` prints nothing), run `gitleaks dir docs/examples --config <a config with useDefault = true and no allowlist> --no-banner --redact` (nothing found), run `bash tests/governance/test_reviews_use_slugs.sh` on the copied tree before the gates (the docs-wide article-citation check reads every Markdown file under `docs/`, `docs/examples/` included: a copied document that cites an article by Roman numeral, or by an `art-` slug this factory's `constitution.md` does not define, fails the factory's gates, a slug in backticks included; rewrite each such citation in the copy as the factory's slug and note the change in the example README's Evidence section; added to M6 by amendment D's PR, 2026-10-04, BL-041), update `docs/examples/habit-tracker/README.md`'s status line to `Status: walked on YYYY-MM-DD from v3.2.0; Release: <URL>.` and add the evidence (M1–M5) to its `## Evidence` section (facts about the example, never the checklist, which stays in the fenced `docs/examples/README.md`); run the gates; open the PR; the verifier runs as for any PR; merge.
- **M7 — the demo re-tag (R11).** Only after `v3.2.0`'s Release is published and checked (its `release.yml` run succeeded; the Release is not a draft). In the factory on an up-to-date `main`, with SSH signing configured (`gpg.format ssh`, `user.signingkey ~/.ssh/id_ed25519_appsconsultants.pub`, `user.email ashwin.pingali@geninspired.com`):
  ```
  git fetch origin --tags
  c=$(git rev-parse 'v0.0.1-demo^{commit}')          # 792cecbca34316a574c37b7391696940d5d417d7
  git tag -d v0.0.1-demo
  git tag -s -m "SpecFlow v3.1 demo release (re-tagged SSH-signed in the v3.2 closeout, REQ-391)" v0.0.1-demo "$c"
  git -c gpg.ssh.allowedSignersFile=.github/allowed_signers tag -v v0.0.1-demo    # Good "git" signature for ashwin.pingali@geninspired.com
  git push --force origin refs/tags/v0.0.1-demo        # the release tags ruleset's update rule: the admin bypass
  gh run list --workflow release.yml --limit 3         # no new run: 792cecb has no release.yml
  ```
  Keep: the `tag -v` line, the push output. From now on `v3.2.0`'s `release.yml` cannot be re-run or dispatched (BL-020).
- **M8 — the demo follow-up.** On `patch/demo-retag-followup` from `main`: delete the section "## Unsigned tag (follow-up required)" (and nothing else) from `docs/releases/0.0.1-demo-known-limitations.md`; `bash tests/governance/test_verify_release.sh` passes (Task 2.2's rule: SSH-signed tag, exactly that section removed); the gates; the PR; the verifier; merge.
- **M9 — the external product (REQ-392, R12).** Instantiate a separate repository from `v3.2.0` for a product you intend to keep; walk it through the lanes path via `/next` to a published Release. If met by the retrospective, record it on `patch/req-392-record`: `docs/examples/README.md`'s REQ-392 section (repository or description, Release URL, run id, `signed`) and its status line `Status: met on YYYY-MM-DD: <Release URL>.`; if not, nothing changes, and BL-019's decision line at the retrospective says deferred with its trigger.
- **M10 — the retrospective** (next section).

## Retrospective — `phase/retro-YYYY-MM-DD` after `v3.2.0` (art-retrospective-cadence)

**When:** after the `ship/3.2.0` PR merges and `v3.2.0`'s Release is published; no later than 2026-10-11 (if `v3.2.0` slips past it, run it then as `triggered_by: adhoc`, and again after the release). Not a build: `/retrospective v3-2-closeout` on `phase/retro-YYYY-MM-DD` from `main`; one PR with `docs/retrospectives/YYYY-MM-DD-v3-2-closeout.md`, the decided entries of `docs/BACKLOG.md` (status and decision line, R13), and nothing else.

**Inputs:** P6 R5, R6, R8, R14, R27 (BL-003, BL-004, BL-005, BL-006, BL-008) and P7's rulings on them (R4, R5, R6, R15, R3); the factory's own release experience — the first SSH-signed tag on trust on first use (`v3.2.0`: the anchor was the first key-listing commit after the newest key-less one), `release.yml`'s first real run (its duration, every refusal and its fix, R28's preview against the real run, the `pre-transfer` listing), the source archive's three SHA-256 values (laptop, `release-build`, `build-source`: P6's Ship lane step 6), the tag ruleset's admin bypass; P6's three instance regressions — a governance test that copied a template-only file into an instance fixture, a `# Covers:` line outside `tests/governance/` citing a factory REQ (`tests/unit/test_render_dashboard.py`), the first-run manifest helper's schema drift — and the lesson "every final review runs the new tests and the gates inside a scaffolded instance" (now a Global Constraint here; BL-021 proposes a script); the usage-limit stall during P6; the parallel-build rebase cost (Builds 4 and 5: four plan/spec conflicts, R35's footnotes; P7 R1's narrower overlap as the experiment); the verifier's one-run approvals when fix waves were re-reviewed before the push (the headless-run count per P5 and P6 PR, read from each PR's marker comments, is the measurement); the habit-tracker walk's findings (M5's wrong instructions, if any) and REQ-392's state (BL-019); the residuals Task 1.6 re-accepted to 2026-12-15 (BL-007, BL-009, BL-010, BL-013 … BL-018, BL-023) and R18's consequence: `v3.2.0`'s released disposition still says `expiry: 2026-10-12` for SEC-006 … SEC-019 (SEC-010, SEC-012: 2026-11-15), so the next ship's disposition carries each forward with Task 1.6's date and BL id, or `status: fixed`; the two prior retrospectives' proposals (BL-024 … BL-033, R17), the absorbed ones expected to be recorded `accepted (landed: …)`.

**Outputs:** `## Decisions on Prior Proposals` holds exactly one line per open BL id (`test_backlog.sh` fails the PR otherwise), and the decided entries say so in `docs/BACKLOG.md`; `## Proposed Changes` carries the mandatory pinned-download bump (the python base digest, the tauri re-pin due 2026-11-15, the skeleton disposition expiry 2026-12-24); proposals, not edits, to the constitution and templates; any residual the retrospective shortens or closes is applied by a follow-up PR (`art-retrospective-cadence`).

## Review Focus

1. **Amendment C weakens no control (R2(g)).** Read each article's old and new text side by side: every rule stays; each "How to apply" names files that enforce it today (open them) or says convention; `art-release-readiness`'s new sentences are true of `release.yml` and `verify-release.sh` on `main` (P6 R30's replay of gates section 7 only, R26's CI comparison, R27's SSH-only rule); twelve articles; the docs-wide slug check finds nothing today and fails a planted slug that no article defines (an `art-` token, written in a scratch copy only — never in a committed document, which the check itself scans).
2. **The waiver's base binding only tightens (R4).** Every waiver the classifier accepted before is accepted after unless its PR was retargeted after it; a refused waiver never blocks; the timeline read fails closed; a commit-level waiver is unchanged in effect; R28's preview over the factory's real range, run before and after, shows no new refusal; the timeline read is measured under the workflows' token first (M0b), and a merged PR refused at the tag has a remedy (a bound waiver naming its merge's first parent).
3. **Entitlements (R7).** The signature never carries a key the project did not commit; an app that embeds more fails before any `codesign --force`; get-task-allow never signs in.
4. **The python image (R8).** The container's uid is not 0; nothing resolves from PyPI except hash-pinned files; the build context holds exactly the three files from the tagged tree.
5. **The example is inert and documents-only (R10).** A planted REQ, SEC or ADR id under `docs/examples/` changes no gate; no secret, no home path; a non-tauri instance has none of it. Corrected by amendment D's PR (2026-10-04; BL-041): "changes no gate" is read as no pipeline gate (traceability, covers, the ADR linkage, the architecture check, the disposition gate, `verify-release.sh`); `tests/governance/test_reviews_use_slugs.sh` reads `docs/examples/` and fails a Roman-numeral citation or an undefined `art-` slug planted there.
6. **Ownership of every hit and every residual.** The hits table; no `expires: 2026-10-12` left after Build 1; no build touches the ship lane's files, the spec or the constitution.

## Deferred by design

- **A configured `next_version` override** (R5; BL-003): deliberately absent, although the P7 hand-off (H2) asked for one. R5 keeps P6 R5's discrepancy as a documented one — `/next` on `main` proposes `ship/0.1.0` while the factory ships `3.2.0` — rather than fix it by configuration, because an override would be `.specflow.yml` deciding pipeline state (`art-branch-as-state`: configuration chooses names, never records progress) and an ADR-003 revision for a one-time mismatch that heals itself once `v3.2.0` is tagged (`/next` then proposes `ship/3.3.0`); a release of another version (`3.2.1`, BL-022) starts its `ship/<version>` branch by hand. BL-003 carries the decision to the retrospective.
- **A `profile:` for the template source** (R6; BL-004): the convention stays.
- **GPG-signed release tags** (R3; BL-008): `release.yml` refuses them; v3.3 decides.
- **A python example walk and the GHCR measurements** (R14; BL-009, BL-010): v3.3, or the first python instance's ship.
- **Open mediums under `medium_cap`** (BL-002): a REQ-322 kernel, Dafny and ADR-002 change — not amendment C, not P7.
- **A `permissions.ask` rule for `gh pr merge`** (BL-001), **`pull_request_target`** (BL-012), **the classifier from the previous release's tag in `release.yml`** (BL-013), **`refs/tags/origin/**` in the ruleset** (BL-007): the retrospective decides.
- **`v3.2.0`'s re-run after the demo re-tag** (R11; BL-020): accepted — no code change can reach a tagged release's own `signers.py`.
- **P7's own release** (BL-022): `3.2.1` by hand or the derived `3.3.0`, the retrospective's call; no ship lane is part of this plan.
- **Windows, Linux, iOS and Android bundles; store submission automation; runtime-contract extraction** — the spec's Won't Have, extraction now v3.3 in the constitution's words.
