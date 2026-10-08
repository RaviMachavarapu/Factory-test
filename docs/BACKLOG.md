# Backlog

Every proposal this project deferred — from a plan's rulings, an accepted residual or a retrospective — with an id.
Ids are `BL-NNN` (three-digit zero-padded, globally unique, never reused; `art-naming-tagging`). Each entry carries a
**Source:**, a **Listed:** date, a **Proposal:**, optional **Absorbed:** (what already delivers it, in whole or in part),
**Planned:** and **Landed:** (the PR that implemented a decided entry's target, a record of fact, not a decision) lines,
and a **Status:** (open or decided).
Every retrospective records one decision line per open id in its `## Decisions on Prior Proposals`
(`/retrospective`): `- BL-NNN: accepted (landed: <PR/commit>) | accepted (target: <PR/owner>) | rejected (<why>) | deferred (<trigger>)`;
in the same PR it marks each decided entry **Status:** decided with a **Decision:** line naming that retrospective
(`<decision> — docs/retrospectives/<file>.md`), and lists each proposal it defers as a new id. Only a retrospective
writes decisions here.

### BL-001 — A permission rule or hook for `gh pr merge` and pushes to `main`
- **Source:** the P5 plan (`docs/plans/2026-09-28-factory-v3-2-p5-plan.md`), H5 and R14
- **Listed:** 2026-10-03
- **Proposal:** a `permissions.ask` rule (or a hook) in `.claude/settings.json`, so a session asks before it runs `gh pr merge` or pushes to `main`; merges stay the maintainer's.
- **Status:** decided
- **Landed:** the `permissions.ask` rules, the PreToolUse hook `scripts/lib/specflow/push_guard.py` and the `next.md` sentence, PR #74 (2026-10-04), the target met.
- **Decision:** accepted (target: a patch PR adding a permissions.ask rule for gh pr merge and pushes to main; owner kpingali123; before v3.3) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-002 — Open mediums count toward `medium_cap` and need an owner
- **Source:** the P5 plan, H9 and R16; the threat model's open-medium residual (`docs/architecture/2026-09-25-factory-v3-2-threat-model.md`); not adopted by amendment C: a REQ-322 kernel and ADR-002 change (ADR-002 rule 3 and the Dafny model's `MediumsAD` revised), which the P7 plan's Hits table leaves to v3.3
- **Listed:** 2026-10-03
- **Proposal:** a current medium with `status: open` counts toward `medium_cap` and needs `owner:`, and `check-security-disposition.sh` fails an ownerless open medium — a REQ-322 kernel change (ADR-002 rule 3 revised, the Dafny model's `MediumsAD` gains open mediums), proposed for v3.3.
- **Status:** decided
- **Decision:** accepted (target: the v3.3 design lane — a REQ-322 kernel change: ADR-002 rule 3, disposition.py, the Dafny model; owner kpingali123) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-003 — A configured `next_version` override
- **Source:** P6 R5; P7 R5
- **Listed:** 2026-10-03
- **Proposal:** let configuration override the `next_version` that `/next` derives for a ship branch. P7 R5 proposes rejection: the mismatch heals once `v3.2.0` is tagged, and an override would be configuration recording progress (`art-branch-as-state`) and an ADR-003 revision.
- **Status:** decided
- **Decision:** rejected (P7 R5: v3.2.0 is tagged, so /next derives the next version; configuration would record pipeline state, art-branch-as-state) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-004 — A `profile:` for the template source
- **Source:** P6 R6; P7 R6
- **Listed:** 2026-10-03
- **Proposal:** record a profile for the template source so `/next` there runs as engineer without `--profile engineer`. P7 R6 proposes keeping the convention (`docs/GLOSSARY.md`): a committed `.specflow.yml` would make the template an instance, and a key in `scripts/template-pack.yml` would put configuration into pack metadata.
- **Status:** decided
- **Decision:** rejected (P7 R6: a committed .specflow.yml would make the template an instance; the engineer-profile convention stays, docs/GLOSSARY.md) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-005 — Waiver base binding
- **Source:** P6 R8; the waiver residual in `.claude/rules/review-gate.md` and in the threat model (dfe-2)
- **Listed:** 2026-10-03
- **Proposal:** a waiver may name the PR's base (`base:<40-hex>`) and is then judged by the marker's base rule; a waiver without one stands only while the PR's timeline shows no retarget after it (P7 R4).
- **Planned:** P7 Build 1, Tasks 1.1–1.2
- **Status:** decided
- **Decision:** accepted (landed: on main by PR #65, unreleased — reaches instances with the next template release, BL-022; the bound waiver grammar and the timeline rule; M0b measured on probe PR #67, run 37169624336) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-006 — Merge methods and the `release tags` ruleset
- **Source:** P6 R14; P7 R15
- **Listed:** 2026-10-03
- **Proposal:** the factory still has `allow_rebase_merge: true` until the maintainer re-runs `bash scripts/configure-repo.sh` (M0); the `release tags` ruleset and the `release` environment exist (measured 2026-10-03). Decide whether `configure-repo.sh` should also verify these settings on every run.
- **Status:** decided
- **Decision:** rejected (verifying on every run: configure-repo.sh writes these settings each time it runs, so drift arises between runs, which PR #53's read-only --check-ruleset and --check-environment flags are the maintainer's explicit check for; rebase-merge was disabled by the maintainer's run on 2026-10-03, read back with gh api) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-007 — The ruleset also restricting `refs/tags/origin/**`
- **Source:** P7 R15; the threat model's short-name base residual (dfe-6, dfe-14)
- **Listed:** 2026-10-03
- **Proposal:** restrict `refs/tags/origin/**` in the `release tags` ruleset (or a second ruleset), so no pushed tag can shadow `origin/<base>` in the local tools' short-name reads.
- **Status:** decided
- **Decision:** deferred (the v3.3 design lane; SEC-016 is low and the full ref is used everywhere that matters) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-008 — GPG-signed release tags
- **Source:** P6 R27; P7 R3
- **Listed:** 2026-10-03
- **Proposal:** accept GPG-signed release tags in `release.yml` and `signers.py` (a GPG keyring for the Release job, keys at the anchor); today a GPG-signed tag is refused at the tag and `art-release-readiness` reads "signed" as SSH-signed. Proposed for v3.3.
- **Status:** decided
- **Decision:** deferred (the v3.3 spec: GPG keyring at the anchor; release.yml refuses GPG tags until then, P7 R3) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-009 — The python GHCR path proved by an example instance
- **Source:** P6 R20; P7 R14
- **Listed:** 2026-10-03
- **Proposal:** take a python instance through a release, so `release.yml` pushes its image to GHCR for real; until then the GHCR path is proved by stubs only. Proposed trigger: v3.3.
- **Status:** decided
- **Decision:** deferred (the first python instance's ship known to the maintainer — REQ-392's product if it is python, or an instance whose owner reports its first ship to kpingali123) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-010 — The first-release registry measurement
- **Source:** P7 R14; the threat model's GHCR residual
- **Listed:** 2026-10-03
- **Proposal:** on a python instance's first release, measure the job token's answer for a never-pushed package, its right to delete a version, and the read-back of the pushed digest, and record them in the threat model.
- **Status:** decided
- **Decision:** deferred (the same first python ship known to the maintainer, with BL-009: the three registry measurements) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-011 — The Dockerfile freeze
- **Source:** P6 R20; the threat model's Dockerfile residual
- **Listed:** 2026-10-03
- **Proposal:** lift P6's freeze on `stacks/python/Dockerfile`: install a hash-pinned runtime lock with `--require-hashes --no-deps`, then the release's wheel alone, and run as a non-root user (P7 R8).
- **Planned:** P7 Build 1, Task 1.4
- **Status:** decided
- **Decision:** accepted (landed: on main by PR #65 Task 1.4, unreleased — reaches instances with the next template release, BL-022; USER 10001, requirements-runtime.txt with --require-hashes --no-deps, the three-file context) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-012 — `pull_request_target` for `verifier.yml`
- **Source:** `.claude/rules/review-gate.md`'s first claim row
- **Listed:** 2026-10-03
- **Proposal:** run the `verifier` check under `pull_request_target`, so the workflow file comes from the base rather than the PR, closing the residual that a PR can edit `verifier.yml` to pass its own check.
- **Status:** decided
- **Decision:** deferred (the v3.3 design lane: pull_request_target needs its own threat analysis of the base-run model) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-013 — `release.yml` running the classifier from the previous published release's tag
- **Source:** P6 Build 3 final review, finding 6; the threat model's residual on what `release.yml` binds (dfe-12)
- **Listed:** 2026-10-03
- **Proposal:** at the tag, run `attestation.py` from the previous published release's tag rather than the tagged tree, so a reviewed ship PR cannot change the classifier that re-judges it.
- **Status:** decided
- **Decision:** deferred (the v3.3 design lane, with BL-012) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-014 — Whether the Dependabot exemption is still worth its residual
- **Source:** dfe-13's accepted residual (the threat model)
- **Listed:** 2026-10-03
- **Proposal:** decide whether to keep REQ-334's Dependabot exemption — a forged commit can still move an existing dependency to another registry version of the same package, unreviewed — or to have the verifier review every Dependabot PR.
- **Status:** decided
- **Decision:** deferred (the next retrospective, run after the next ship PR merges — 3.2.1, planned by 2026-11-15, BL-022 — with the count of Dependabot PRs exempted since 2026-10-03 as the input) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-015 — `deploy-local.sh`'s cut-over and `rollback` with an explicit version
- **Source:** PR #57 verifier run 1, finding 5
- **Listed:** 2026-10-03
- **Proposal:** revisit `deploy-local.sh`'s stop-then-start cut-over, and give `rollback` an explicit version instead of the previous release.
- **Status:** decided
- **Decision:** deferred (the first python instance's ship known to the maintainer, with BL-009) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-016 — The Apple secrets on argv and the `release` environment
- **Source:** P6 R32's residual
- **Listed:** 2026-10-03
- **Proposal:** keep the Apple signing and notarization secrets off process argv (pass them by file or stdin), and scope them to the `release` environment only.
- **Status:** decided
- **Decision:** deferred (the first signed instance release known to the maintainer — REQ-392's product if it signs, or an instance whose owner reports its first signed release to kpingali123) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-017 — Registry caches in the app bundle
- **Source:** P6 R15's residual
- **Listed:** 2026-10-03
- **Proposal:** keep the app stacks' package-registry caches out of the bundled app, or prove that they never enter it.
- **Status:** decided
- **Decision:** deferred (the first signed instance release known to the maintainer, with BL-016) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-018 — The signed path exercised only by stubs
- **Source:** P6 R33
- **Listed:** 2026-10-03
- **Proposal:** exercise the macOS signing and notarization path for real on an instance's first signed release; until then only stub tools exercise it.
- **Status:** decided
- **Decision:** deferred (the first signed instance release known to the maintainer, with BL-016) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-019 — REQ-392's external product
- **Source:** Success Metric 3 (the v3.2 spec); P7 R12
- **Listed:** 2026-10-03
- **Proposal:** a product other than the factory and the habit tracker, taken through the lanes path via `/next` to a published GitHub Release (REQ-392); the retrospective records it met (with `docs/examples/README.md`'s record) or deferred with a trigger.
- **Status:** decided
- **Decision:** deferred (the external product's first published Release, recorded by a patch PR to docs/examples/README.md's External product section; owner kpingali123; reviewed at the next retrospective; the habit tracker does not count, R12's default, since no decision keeps it) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-020 — `v3.2.0`'s re-run path after the demo re-tag
- **Source:** P7 R11
- **Listed:** 2026-10-03
- **Proposal:** once `v0.0.1-demo` is re-tagged SSH-signed, `v3.2.0`'s `release.yml` can no longer be re-run or dispatched (the re-signed demo tag reads `no-anchor`); decide whether a later release restores a recovery path.
- **Status:** decided
- **Decision:** rejected (no code can reach a tagged release's own signers.py; a later release supersedes v3.2.0 rather than re-running it) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-021 — A script that runs the new tests inside a scaffolded instance
- **Source:** P6's lesson (the first instance regression)
- **Listed:** 2026-10-03
- **Proposal:** one script every final review runs: copy the template, run `init-project.sh` for each touched stack, run each new or changed governance test there, and print every instance SKIP.
- **Status:** decided
- **Landed:** `scripts/run-instance-tests.sh` with its governance test, PR #74 (2026-10-04), the target met.
- **Decision:** accepted (target: a patch PR adding scripts/run-instance-tests.sh — copy_template, init per touched stack, run each new or changed governance test, print every SKIP; owner kpingali123; before the next build lane) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-022 — The factory's next release after P7
- **Source:** P7 R5
- **Listed:** 2026-10-03
- **Proposal:** ship P7's fixes as `3.2.1` (a `ship/3.2.1` branch started by hand) or wait for the derived `3.3.0`.
- **Planned:** the cap re-decided to 8 for the 3.2.1 ship alone by PR #76 (`patch/ship-3-2-1-prereqs`, 2026-10-04; back to 5 by a reduction PR after the 3.2.1 Release, 2026-12-15 at the latest), the ship/3.2.1 PR (#77) follows; the next retrospective records the outcome. 2026-10-04: the ship/3.2.1 PR (#77) is open, carrying `docs/security/3.2.1-*.md` and `docs/releases/3.2.1-*.md` (19 findings, none open; every accepted entry to 2027-01-31, so `v3.2.1` is tagged by 2027-01-30); it does not carry BL-034's fix. 2026-10-05: v3.2.1 released 2026-10-05 (tag on `609abbc`, run 37302823217); the cap returned to 5 by `patch/post-3-2-1-records` (on this PR's merge).
- **Status:** decided
- **Decision:** deferred (ship 3.2.1 by 2026-11-15, the tauri re-pin deadline, carrying the P7 builds, the Build 1 run-2 fold and the re-pins, with the seven carried accepted or deferred mediums brought within medium_cap 5 by fixes or the cap re-decided by its own reviewed PR; or 3.3.0 if a design lane opens first — the maintainer decides at that ship) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-023 — dfe-12's forged-anchor residual
- **Source:** dfe-12 (the threat model); P7 R9
- **Listed:** 2026-10-03
- **Proposal:** a merger's key is trusted from the release after the one whose tagged tree lists it in `.github/allowed_signers`; decide whether a newly listed key needs a second signer or an out-of-band fingerprint check.
- **Status:** decided
- **Decision:** deferred (the v3.3 design lane; re-accepted to 2026-12-15 in the threat model by PR #65 Task 1.6) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-024 — PLAN-phase no-code reminders in `/architecture` and the writing-plans skill
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-05-28-v3-1-cutover.md`, proposal #5 (deferred there: external-skill coordination, "revisit at the v3.2 retro"; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** `/architecture` reminds the next PLAN PR that a plan carries no implementation code, and the external `superpowers:writing-plans` skill refuses code bodies in PLAN-phase task descriptions.
- **Absorbed:** in part by REQ-380 — plans carry test code and intent, never bodies (`/specflow-plan`, `schemas/plan-template.md`, `test_plan_template.sh`); the external skill's change remains.
- **Status:** decided
- **Decision:** rejected (the /architecture reminder would repeat a rule REQ-380 already states in /specflow-plan and schemas/plan-template.md, pinned by test_plan_template.sh — absorbed in part by PR #22, 4348b08 — and the writing-plans skill is outside the factory's tree) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-025 — TDD evidence (the red run) in implementer reports
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-05-28-v3-1-cutover.md`, proposal #6 (deferred there: external skill, "revisit at the v3.2 retro"; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** the external `superpowers:subagent-driven-development` implementer prompt requires the pasted failing run before the passing one when a dispatch adds both tests and source.
- **Absorbed:** in part by REQ-321 — `scripts/check-test-first.sh` fails a commit whose source change no earlier or same-commit test line precedes; the external prompt's change remains.
- **Status:** decided
- **Decision:** rejected (the implementer prompt is an external skill outside the factory's tree; absorbed in part by REQ-321 — PR #42, 1ee84c8 — whose check-test-first.sh checks per commit that a test line precedes the source change, which the pasted red run was meant to show) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-026 — A sequential-chain verifier mode
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-05-28-v3-1-cutover.md`, proposal #8 (deferred there: "needs design; candidate for v3.2 spec"; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** when several PRs are stacked, verifier full mode diffs each branch against the projected baseline after the PRs below it merge, so a citation of a rule that exists only on an unmerged PR is caught at review time.
- **Absorbed:** in part by REQ-395 — `ci.yml` and `verifier.yml` check stacked PRs to any base, and a marker is judged against the base it recorded (`base-mismatch` after a retarget, `.claude/rules/review-gate.md` step 6); diffing against the projected baseline remains.
- **Status:** decided
- **Decision:** rejected (a projected-baseline diff needs a model of merges that have not happened; absorbed in part by REQ-395 — PR #33, f14709a, and PR #48, e337b41 — which refuses a marker after a retarget that changes the merge base, base-mismatch, so a stacked PR whose base is squash-merged is reviewed again against main, where a citation of an unmerged rule surfaces) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-027 — Inventory legacy files when a plan introduces a stricter gate
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-05-28-v3-1-cutover.md`, proposal #10 (deferred there: external skill, "revisit at the v3.2 retro"; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** a plan that tightens a gate lists the existing files the new gate may fail and budgets a cleanup task (the external `superpowers:writing-plans` skill, or `schemas/plan-template.md`).
- **Status:** decided
- **Landed:** the plan template's optional inventory step, pinned, PR #74 (2026-10-04), the target met.
- **Decision:** accepted (target: a patch PR to schemas/plan-template.md adding an 'existing files the new gate may fail' inventory step; owner kpingali123; before v3.3) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-028 — A wrong-branch guard in `run-verifier.sh`
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-06-09-enforcement-remediation.md`, proposal #1 (no decision recorded; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** `run-verifier.sh <PR>` refuses to review a checkout that is not the PR's head.
- **Absorbed:** by REQ-310 — `scripts/run-verifier.sh` resolves the PR's head and base with `gh` and reviews exactly that head; the v3.2 retrospective is expected to record `accepted (landed: …)`.
- **Status:** open

### BL-029 — A stacked-PR merge protocol
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-06-09-enforcement-remediation.md`, proposal #2 (no decision recorded; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** merge the bottom PR without deleting its branch, retarget the next PR, then delete the branch; never `--delete-branch` while a stacked PR still bases on it.
- **Absorbed:** by `.claude/rules/review-gate.md` step 6 (a stacked PR is retargeted before its base branch is deleted) with REQ-395 (stacked PRs are checked to any base); the v3.2 retrospective is expected to record `accepted (landed: …)`.
- **Status:** open

### BL-030 — Record verdict waivers
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-06-09-enforcement-remediation.md`, proposal #3 (no decision recorded; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** a merge past a `REQUEST_CHANGES` without a verifier re-run records who waived the re-run and why, so `art-review-gate`'s audit trail stays intact.
- **Absorbed:** by REQ-382 — the maintainer waiver comment (`<!-- specflow-verifier:waive sha:<head> -->`, a 20-character rationale, a maintainer) — and REQ-311 (the check parses the verdict: an unaddressed `REQUEST_CHANGES` blocks); the v3.2 retrospective is expected to record `accepted (landed: …)`.
- **Status:** open

### BL-031 — `/release` delegates its mechanical gate to `verify-release.sh`
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-06-09-enforcement-remediation.md`, proposal #4 (no decision recorded; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** replace `/release`'s hand-spelled gate checks with one `bash scripts/verify-release.sh <version>` so the command and the gate cannot drift.
- **Absorbed:** by REQ-324 — `/release` invokes `scripts/verify-release.sh` instead of restating the gate (`.claude/commands/release.md` step 6); the v3.2 retrospective is expected to record `accepted (landed: …)`.
- **Status:** open

### BL-032 — `extends` / `extended_by` symmetry in `test_spec_lifecycle.sh`
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-06-09-enforcement-remediation.md`, proposal #5 (no decision recorded; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** `tests/governance/test_spec_lifecycle.sh` checks that a spec's `extends:` and the extended spec's `extended_by:` name each other, as it checks `superseded_by` (measured 2026-10-03: no governance test checks it).
- **Status:** decided
- **Landed:** the `extends`/`extended_by` symmetry check, PR #74 (2026-10-04), the target met.
- **Decision:** accepted (target: a patch PR adding the extends/extended_by symmetry check to tests/governance/test_spec_lifecycle.sh; owner kpingali123; before v3.3) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-033 — The `v0.0.1-demo` re-tag, signed
- **Source:** retrospective `02677f8^:docs/retrospectives/2026-06-09-enforcement-remediation.md`, the carried open item (the 2026-05-28 retrospective's decision on its proposal #3: the annotated fallback is temporary and every retrospective tracks the re-tag until done; P7 R17)
- **Listed:** 2026-10-03
- **Proposal:** re-create `v0.0.1-demo` signed on its commit `792cecb` and remove the stale fallback section from its released known-limitations by the `/release` follow-up.
- **Planned:** P7's maintainer checklist M7 (the SSH-signed re-tag, after `v3.2.0`'s Release) and M8 (the follow-up PR Build 2's Task 2.2 admits); P7 R11, BL-020.
- **Status:** decided
- **Decision:** accepted (target: the maintainer's M7 re-tag and M8 follow-up PR, unblocked since v3.2.0's Release; owner kpingali123; before 3.2.1) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-034 — The inherited demo release blocks a python or v3.1 instance's first tag
- **Source:** `docs/releases/3.2.0-known-limitations.md` and `docs/releases/3.2.0-migration.md` §7 (PR #62 verifier run 1, finding 7): `signers.py`'s previous-release check takes the inherited `0.0.1-demo` notes as the previous release, finds no tag in the instance and returns `previous-untagged`, so `release-tag.sh` exits 11 and `release.yml` refuses the first tag
- **Listed:** 2026-10-03
- **Proposal:** before any python or v3.1 instance's first ship, a design lane (`design/<slug>`, with a spec delta to REQ-383's previous-release rule) or a `build/sec-<id>` back-edge under a SEC id raised by the next security review — never `patch/`, because `signers.previous` is dfe-12's trust boundary and the patch tier admits no change to one (`review-gate.md`): `signers.previous` treats the inherited demo release (notes without a tag, listed by the examples manifest) as no previous release, or `init-project.sh` strips the demo's release records from an instance. Owner: kpingali123.
- **Planned:** none yet — the P7 retrospective decides; a python instance's first ship (or REQ-392's external product, if it is a python instance) is the deadline.
- **Status:** decided
- **Decision:** accepted (target: a build/sec-<id> back-edge under a SEC id the 3.2.1 ship's review raises, or the v3.3 design lane — which one, and so whether 3.2.1 by 2026-11-15 carries it, is decided at the 3.2.1 ship; v3.3 has no date; owner kpingali123; before any python or v3.1 instance's first ship) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-035 — A strict parse, or a pin, of spec frontmatter
- **Source:** `docs/security/3.2.0-review.md` Notes (PR #62 verifier run 1, finding 8): the spec's `amended:` list carried an inner double quote in a double-quoted item and an item at column 0, both invalid YAML, and no gate noticed because `frontmatter.py` splits each line on its first `:`
- **Listed:** 2026-10-03
- **Proposal:** a strict YAML parse of spec frontmatter in `scripts/lib/specflow/frontmatter.py`, or a `tests/governance/test_spec_lifecycle.sh` pin of the two defect shapes (unescaped quotes inside a double-quoted `amended:` item; an `amended:` item at column 0). Owner: kpingali123.
- **Status:** decided
- **Landed:** the two defect-shape pins, PR #74 (2026-10-04), the patch target met (the strict parse stays v3.3's).
- **Decision:** accepted (target: a patch PR pinning the two defect shapes in test_spec_lifecycle.sh; owner kpingali123; the strict parse at v3.3) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-036 — An upgrade lane for instances that take a new template version
- **Source:** `docs/releases/3.2.0-migration.md` §1 (PR #62 verifier run 2, finding 4): a template upgrade carries constitution amendments, security and release artifacts and `.github/` workflows, which is outside the patch tier, yet no lane covers it; `/next` and the verifier's code mode key on the `patch/` prefix and would apply the patch tier's weaker REQ-citation fallback
- **Listed:** 2026-10-03
- **Proposal:** a named lane or prefix (the migration recommends `upgrade/<version>` meanwhile) with its own `/next` steps and verifier treatment for template upgrades. Owner: kpingali123.
- **Planned:** none — the retrospective decides.
- **Status:** decided
- **Decision:** deferred (the v3.3 spec, undated; until then the next template release, 3.2.1, is taken on an upgrade/<version> branch per docs/releases/3.2.0-migration.md §1, which /next reports as unknown) — docs/retrospectives/2026-10-04-v3-2-closeout.md

### BL-037 — dfe-10's CI-log bootstrap hint residual (SEC-020)
- **Source:** retrospective `docs/retrospectives/2026-10-04-v3-2-closeout.md` (P7 plan Build 1, Deferred corrections D18); the threat model's dfe-10 row; `docs/security/3.2.0-disposition.md`'s SEC-020 (medium, open)
- **Listed:** 2026-10-04
- **Proposal:** what remains after the retrospective's decision (its Proposed Changes, item 2): SEC-020 is not accepted under the medium cap, which returns to 5, and stays an open medium; dfe-10's residual is re-affirmed at medium 5.2 by the same vector, owner kpingali123, expiry 2026-12-15 — provisional (solo mode) until the next available second reviewer confirms or downgrades it; the retrospective PR's merge records the decision. PR #65's `verifier.yml` narrowed it (the fixed `main`-only bootstrap line is printed beside the base's labelled, defanged text), but the base's text is still printed. Left over: take that text out of CI's log, or close the residual. Trigger: the next ship's security review (3.2.1, planned by 2026-11-15, BL-022) records SEC-020 fixed if the base's text no longer reaches the log, else re-scores it and disposes of it within the cap. The threat model's dfe-10 row is re-pointed at this id by the retrospective's re-dating patch PR (Proposed Changes, item 7), before 2026-12-15. Owner: kpingali123.
- **Planned:** the next ship's security review (3.2.1, planned by 2026-11-15, BL-022) and the retrospective's re-dating patch PR (its Proposed Changes, item 7, before 2026-12-15); owner kpingali123; the cap for the 3.2.1 ship is 8 by PR #76 (`docs/security/RUBRIC.md`'s v3.2.1 record), its eighth place reserved for SEC-020 should that review accept or defer it. 2026-10-05: the re-dating patch is PR #78 (`patch/post-3-2-1-records`), item 7's patch: the residual dates re-aligned to 2027-01-31, dfe-10's severity 5.2 and sign-off recorded with SEC-020's confirmation trigger, dfe-12's Boundary half closed, SEC-021's `headless-prompt.md` half recorded on dfe-9 — item 7 complete on this PR's merge; the next retrospective records it.
- **Status:** open

### BL-038 — dfe-12's `attestation_since` pre-transfer boundary residual
- **Source:** retrospective `docs/retrospectives/2026-10-04-v3-2-closeout.md` (P7 plan Build 1, Deferred corrections D18); the threat model's dfe-12 row; SEC-008
- **Listed:** 2026-10-04
- **Proposal:** the retrospective closes the residual (its Proposed Changes, item 2; P7 R9, R15): `v3.2.0` is published and its tagged tree carries `attestation_since: e88e8361ef913ca7ac7475e506610003be7574bb`, so the never-moves rule fixes the boundary. Left over: recording the closure. The retrospective's re-dating patch PR (Proposed Changes, item 7, before 2026-12-15) writes it into the threat model's dfe-12 row; the next ship's disposition (3.2.1, planned by 2026-11-15, BL-022) records SEC-008's Boundary half closed and carries its Tagged-tree half under BL-013, since the released 3.2.0 disposition is never edited (P7 R18). Owner: kpingali123.
- **Planned:** the retrospective's re-dating patch PR (its Proposed Changes, item 7, before 2026-12-15) and the next ship's disposition (3.2.1, planned by 2026-11-15, BL-022); owner kpingali123. 2026-10-05: the re-dating patch is PR #78 (`patch/post-3-2-1-records`), item 7's patch: the residual dates re-aligned to 2027-01-31, dfe-10's severity 5.2 and sign-off recorded with SEC-020's confirmation trigger, dfe-12's Boundary half closed, SEC-021's `headless-prompt.md` half recorded on dfe-9 — item 7 complete on this PR's merge; the next retrospective records it.
- **Status:** open

### BL-039 — A concurrency group in `ci.yml`
- **Source:** retrospective `docs/retrospectives/2026-10-04-v3-2-closeout.md`: `ci.yml` ran twice per head on PR #62 and PR #65 when a push and a PR-body edit landed seconds apart
- **Listed:** 2026-10-04
- **Proposal:** give `.github/workflows/ci.yml` a `concurrency` group keyed on the PR number (as `verifier.yml`'s and `release-build.yml`'s already are) that cancels a superseded run of the same PR, and `app-stacks.yml` the same if its triggers ever include `edited`. A patch PR; the workflow edit is gate code, which code mode names. Owner: kpingali123.
- **Planned:** implemented in PR #74 (2026-10-04), the `ci.yml` concurrency group, ahead of a decision; the next retrospective decides.
- **Status:** open

### BL-040 — `floor.py check-review`'s untested refusals
- **Source:** retrospective `docs/retrospectives/2026-10-04-v3-2-closeout.md`; PR #66 verifier run 2 (the untested refusal reasons)
- **Listed:** 2026-10-04
- **Proposal:** pin the three refusal reasons PR #66 added with no test ("the file is absent at v<ver>", "the file is outside --root", "the file name carries no version") in `tests/governance/test_security_review.sh`. The comment in `scripts/lib/specflow/floor.py` that cites the squash-merge permission to REQ-340 is correct (REQ-340's body states it), and may also cite `art-branch-as-state`, which states it too. A patch PR. Owner: kpingali123.
- **Planned:** implemented in PR #74 (2026-10-04), ahead of a decision — the three refusal pins, the REQ-340 citation kept beside `art-branch-as-state`, and a change the proposal did not ask for: `check-review` no longer checks a shipped review's provenance commit against history — an ancestor of `HEAD` and any other value both pass, and whether the object is held locally no longer matters (the rebase onto #73 surfaced the old existence test; `docs/security/README.md`, the threat model's dfe-3 residual); the next retrospective decides, the rule change included.
- **Status:** open

### BL-041 — The plan-header and constitution wording the P7 builds deferred
- **Source:** retrospective `docs/retrospectives/2026-10-04-v3-2-closeout.md`; P7 plan Build 1 Deferred corrections D1, D3, D4, D5, D7, D13, D14, D15, D19, and Build 2's Deferred corrections (R10's scope, the M6 citation step, R1's table)
- **Listed:** 2026-10-04
- **Proposal:** a constitution amendment D for the constitution items (D1 and D5 in `art-naming-tagging`, D4 in `art-secrets-hygiene`, D7 in `art-threat-driven-security`, `art-review-gate` and `art-formal-verification`; the sentences are in the retrospective's Proposed Changes, item 3), proposed there and applied by its own amendment PR; and a doc patch to `docs/plans/2026-10-03-factory-v3-2-p7-plan.md` for the header items (item 4). Owner: kpingali123.
- **Planned:** carried by design/amendment-d (PR #75, 2026-10-04; open as this line is written): the constitution items (item 3), the review-gate patch-tier bullet (item 2) and the plan-header items (item 4); the next retrospective records it once merged.
- **Status:** open

### BL-042 — The spec readings to record in the v3.2 spec's P7 `amended:` entry
- **Source:** retrospective `docs/retrospectives/2026-10-04-v3-2-closeout.md`; P7 plan Build 1 Deferred corrections D2, D9, D10; the 3.2.0 review's SEC-021; Build 2's M6 copy rule
- **Listed:** 2026-10-04
- **Proposal:** a doc patch to `docs/specs/2026-09-25-factory-v3-2-design.md`'s P7 `amended:` entry recording D9 (REQ-385's `base_pr == 0` wording), D10 (REQ-313's base-read inputs, `.gitleaks.toml` now `main`'s), the ship review's SEC-021 base-read inputs, Build 2's M6 copy rule narrowing REQ-391's "docs/ artifacts", and D2 as moot (M0b measured readable, probe PR #67). REQ bodies unchanged. Owner: kpingali123.
- **Planned:** the documentation patch to the v3.2 spec before the 3.2.1 ship (the retrospective's Proposed Changes, item 5); owner kpingali123.
- **Status:** open

### BL-043 — The `build-source` checksum comment on the merged ship PR
- **Source:** retrospective `docs/retrospectives/2026-10-04-v3-2-closeout.md`: the P6 plan's Ship lane step 6 asks for `build-source`'s checksum in a comment on the merged ship PR; none was posted on PR #62
- **Listed:** 2026-10-04
- **Proposal:** `/release --tag` (`.claude/commands/release.md`) posts the comment after the Release job succeeds, or the convention is dropped because `release.yml`'s `build-source` job, which compares the rebuilt archive with the notes' row, is the record. Owner: kpingali123.
- **Planned:** none — decided at the 3.2.1 ship (its `/release --tag` posts the comment, or the convention is dropped); owner kpingali123. 2026-10-04: decided at the 3.2.1 ship: proposed dropped, the ship/3.2.1 PR #77 (`docs/releases/3.2.1-known-limitations.md`: `release.yml`'s `build-source` job, which compares the rebuilt archive with the notes' row before publishing, is the record); the maintainer confirms by merging; the next retrospective records the decision. 2026-10-05: the maintainer confirmed the drop by merging PR #77 (v3.2.1 released 2026-10-05); the next retrospective records the decision.
- **Status:** open

### BL-044 — REQs for the push hook and the instance-test runner
- **Source:** PR #74 verifier run 3 (code mode, `art-specification-primacy`): `scripts/lib/specflow/push_guard.py` traces to REQ-371 and REQ-385, and `scripts/run-instance-tests.sh` to REQ-306 and REQ-360, none of which describes those scripts; their contracts come from BL-001 and BL-021, not from a REQ
- **Listed:** 2026-10-04
- **Proposal:** the next spec amendment (the v3.2 spec's `amended:` entry for 3.2.1, or v3.3's spec) defines two REQs — the hook's contract (asks before a push to `main` or a `gh pr merge`, never denies; the registered command in `.claude/settings.json` exits 0 when the script is absent; a convenience, not a control) and the runner's (tests committed since `--base` plus any named, python plus each touched stack, every SKIP printed, exit 1 on a failure, 2 in an instance) — and the tests' `# Covers:` lines and the scripts' comments cite them. Owner: kpingali123.
- **Planned:** none — the next retrospective decides.
- **Status:** open

### BL-045 — The verifier skill checks the patch-tier `medium_cap` exception
- **Source:** PR #75 verifier run 1, finding 2: `.claude/rules/review-gate.md`'s patch tier (amendment D) says a rubric-only reduction of `medium_cap` to 5 from above qualifies and "a reviewer reads the diff", but `.claude/skills/verifier/SKILL.md` asks neither mode to check that a `patch/` PR touching `docs/security/RUBRIC.md` only reduces the cap, so in solo mode the check is the model's general judgement
- **Listed:** 2026-10-04
- **Proposal:** `.claude/skills/verifier/SKILL.md` (gate code; its own reviewed PR) gains one instruction for a `patch/` PR whose diff touches `docs/security/RUBRIC.md`: `REQUEST_CHANGES` unless the only change is `medium_cap` reduced to 5 from above with the kernel and the spec untouched; a governance pin in `tests/governance/test_review_gate_claims.sh` or `test_verifier_skill.sh` names the instruction. Owner: kpingali123.
- **Planned:** none — the next retrospective decides.
- **Status:** open

### BL-046 — The next ship's eight carried mediums under `medium_cap` 5
- **Source:** PR #78 verifier run 1, finding 2: `docs/security/3.2.1-disposition.md` accepts eight mediums (SEC-007, SEC-008, SEC-009, SEC-010, SEC-012, SEC-013, SEC-014, SEC-020) to 2027-01-31; ADR-002 rule 4 re-lists every one in the next disposition, and rule 3 caps accepted or deferred mediums at `medium_cap`, now 5 again (`docs/security/RUBRIC.md`'s 2026-10-05 record), so the next ship fails the disposition gate unless at least three are fixed or downgraded, or the cap is re-decided by its own reviewed PR before it
- **Listed:** 2026-10-05
- **Proposal:** before the next ship (3.2.2 or 3.3.0), fix or downgrade at least three of the eight — the candidates with a deferred fix are SEC-013 (BL-016), SEC-014 (BL-017), SEC-007 (BL-023), SEC-008 and SEC-009 (BL-013), SEC-020 (BL-037); SEC-010 and SEC-012 have no BL id yet — or re-decide the cap by its own `patch/<slug>` PR under `.claude/rules/review-gate.md`'s third exception. Owner: kpingali123. Two more facts for that ship: all eight expire on 2027-01-31, so a ship after that date must also fix or re-accept them (ADR-002 rules 4 and 5); and SEC-021 (low 2.0, provisional) would be a ninth accepted medium if the next second reviewer re-scores it medium.
- **Planned:** none — the next retrospective decides.
- **Status:** open

