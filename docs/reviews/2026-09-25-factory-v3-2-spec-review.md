---
date: 2026-09-25
target: docs/specs/2026-09-25-factory-v3-2-design.md @ 2a86552 (branch phase/spec-factory-v3-2)
reviewers:
  - persona: verifier-full-mode
  - persona: customer-non-technical-founder
  - persona: senior-engineer-tauri-flutter
  - persona: implementation-planner
  - persona: security-and-release
verdict: REQUEST_CHANGES → revised in the same branch (see Disposition)
---

# Fresh-Eyes Synthesis — Factory v3.2 Spec (first draft)

Five parallel reviewers read the v3.2 design spec, its brainstorm, the review it implements, and the live repo. The engineer reviewer scaffolded real Tauri and Flutter skeletons and ran the named security tools; the planner ran the gates on the branch. Findings below are deduplicated; every one is dispositioned into the revised spec by REQ id.

## Convergent findings (≥2 reviewers)

| # | Finding | Flagged by | Disposition |
|---|---|---|---|
| 1 | **Spec-level gate triggers plus a six-plan umbrella guarantee a red `main` for months.** Once any plan references the spec, the new covers/proof/architecture gates flag every unimplemented REQ. | verifier, planner | **fixed:** new P0 (REQ-380): plans carry `implements: [REQ-…]`; linkage scopes per plan, traceability to the union across plans; the P3 checkers inherit the rule (REQ-394). P0 lands through its own plan on an impl branch (REQ-381 exempts it); REQ-327's two checker changes share one commit. |
| 2 | **Tag lifecycle contradicts itself.** `/release` Step 0 tags the PR head before merge; REQ-324/350 require the tag be an ancestor of main. | verifier, security, planner, engineer | **fixed:** REQ-383: ship PR carries no tag; `/release --tag` after merge on the merge commit; Step 0 removed; SSH `allowed_signers` verified by `release.yml`; `verify-release.sh` at PR time asserts the tag does *not yet* exist. |
| 3 | **Solo gate is described as a control but every link is author-controlled**; free-plan repos have no server-side anchor; no waiver path for a false REQUEST_CHANGES; anyone with comment access can post `APPROVE`. | verifier, security, engineer, founder | **fixed:** REQ-311/313/382: script (not model) writes a full-SHA marker with `prompt_sha256` and `model`; verifier script, skill and constitution taken from the base branch; comment author must be OWNER/MEMBER/COLLABORATOR and unedited; bounded maintainer waiver; REQ-314 words solo mode as a tamper-evident audit trail, not an enforced control. |
| 4 | **Verifier isolation misses the real attack surface**: a PR-controlled `.claude/settings.json` (hooks) and `CLAUDE.md` load inside a worktree of the PR head; `.env` is untracked so the real targets are `~/.config/gh`, `~/.claude`, `~/.ssh`. | security, engineer | **fixed:** REQ-313 rewritten from the engineer's empirical test: `--setting-sources user`, deny list passed on the command line, tools restricted to Read/Grep/Glob, gitleaks over the findings before posting, 64 KiB cap. |
| 5 | **REQ-322 proves the wrong property.** Expiry as a validity window turns every merged release red the day after; review/disposition set equality unmodelled; no schema; `owner` missing. | security, verifier | **fixed:** REQ-322 rewritten: inputs are both sets; equality precondition; carry-forward rule; date is an explicit input; only the version under release is evaluated; `schemas/security-disposition-template.md`; structured parser. |
| 6 | **Tauri skeleton cannot satisfy REQ-304 and REQ-330 at once.** `create-tauri-app` ships no tests; its fresh `Cargo.lock` has 7 RustSec advisories on day one; 80% coverage is unreachable without excluding bootstrap files. | engineer, verifier | **fixed:** REQ-304 pack overlay (vitest, one Rust test, `commands.rs`), pinned toolchains, pack-shipped `osv-scanner.toml` with reasoned ignores; REQ-325 per-toolchain floors with named tools and exact exclusion lists. |
| 7 | **REQ-331 thresholds are false for four of seven tools**; `osv-scanner` exits 128 on a lockfile-less tree; the template fails its own floor today; no `dart pub audit` exists. | engineer, security | **fixed:** REQ-330/331 rewritten per tool; exit 128 = PASS with note; absent tool = hard FAIL; P4's first task bumps `scripts/requirements.txt`; OQ1 closed. |
| 8 | **macOS minutes**: four app jobs per matrix run (~250–300 billed minutes) exceed a free private repo's ~200/month. | engineer, security, founder | **fixed:** REQ-360 split; app jobs run on `workflow_dispatch`, weekly schedule, and `stacks/<stack>/**` path changes only; `macos-15` pinned; caches; NFR states the cost. |
| 9 | **REQ-341 state set is not enumerated**; inputs cannot see merged lanes; `N` in `build/<slug>-N` undefined; two open lanes undefined; init leaves the repo off `main`. | verifier, engineer, planner | **fixed:** REQ-340/341 rewritten: `## Build N` sections; PRs open *and* merged as input; states enumerated incl. `awaiting-verifier`, `awaiting-merge`, `blocked`; init leaves on `main`; missing `gh` handled. |
| 10 | **`/next` cannot run the verifier** (must run outside a Claude session) and the spec never says so; guided "never a technical choice" is untestable. | founder, verifier, planner | **fixed:** REQ-385 `awaiting-verifier` state prints the out-of-session command; REQ-342/389 enumerate the confirmation points (REQ-344 was renumbered to REQ-389) and split decisions from acknowledgements. |
| 11 | **Stack chosen by a shell prompt before Claude exists**; Enter-default lands the founder in the engineer profile. | founder, verifier | **fixed:** REQ-300: profile asked first, default `guided`; in guided the prompt is "what are you building", mapped to a stack with a recorded rationale; `--doctor`. |
| 12 | **Unsigned macOS bundle cannot be handed to a tester**; Gatekeeper and the Apple Developer Program cost are never mentioned. | founder, security, engineer | **fixed:** REQ-386: tester instructions generated per release; checklist's first item is the developer-program cost; signing secrets named; `signed:` in the Release manifest. |
| 13 | **Test-first check roots are wrong for Tauri and Flutter** (`#[cfg(test)]` in-file, `lib/` and `test/`); shallow CI checkout breaks the commit walk; trigger keyed on branch names that P5 renames. | engineer, planner, verifier | **fixed:** REQ-310/321: triggers by diff content; pack `source_roots`/`test_globs`; `--no-merges` walk on `fetch-depth: 0`. |
| 14 | **Missing constitution amendments** (formal-verification "v3.2" promise, threat-driven-security back-edge names and solo severity, retrospective-cadence trigger, plus nine "How to apply" clauses). | verifier, planner | **fixed:** amendments consolidated into three PRs (with P2, with P5, and P7 closeout); REQ-326 moved to P7 with the planner's clause table as its acceptance list. |
| 15 | **Deletions in REQ-305/307 have live dependents** (`tests/unit/test_render_doc.py`, init's skill dir, README, demo release notes). | planner, verifier | **fixed:** REQ-307 lists every dependent. |
| 16 | **Review items silently dropped**: Dafny mandatory for every instance, clause-level test mapping and `tests/e2e/`, docs-wide slug check, patch tier under lanes, demo tag re-tag. | verifier, planner | **fixed / scoped:** `example.dfy` moves to `templates/` so proof-less instances need no Dafny (REQ-306); docs-wide slug check joins REQ-326; patch tier and minor exception kept and restated for lanes (REQ-340); clause-level mapping and `tests/e2e/` go to Won't Have; demo re-tag to REQ-391. |

## Single-reviewer findings kept

- **Founder:** "fully tested" must be explained in one sentence on the audience block, and a launch-and-exit smoke of the built bundle is added (REQ-390). The guided path must be proven on a desktop stack, not a Python CLI (REQ-391). A "you get / you do not get yet" table for founders (REQ-308).
- **Engineer:** `ci-setup.yml` cannot be included in Actions; packs ship a composite action instead, and `stacks/` is removed from an instance after init (REQ-303). Flutter's template targets macOS 10.15 and fails to build under current Xcode; packs pin and rewrite the deployment target (REQ-304). `flutter precache` and `xcode-select --install` join prerequisites.
- **Planner:** the factory must walk ARCHITECTURE for REQ-322/341 before the first plan (ADR linkage demands it); kernel = two pure Python decision functions under `scripts/lib/specflow/` (REQ-381). The Anthropic-free flat parser for `.specflow.yml` is stated. Deferral candidates named for the user's decision (below).
- **Security:** Dependabot PRs are exempt from the attestation check or the floor generates unmergeable PRs (REQ-334). Suppressions must cite a `SEC-NNN` and be listed in "Tools run" (REQ-388). `release.yml` needs job-level `contents: write, packages: write` and reads no repository secret unless signing secrets exist (REQ-351).

## Decisions left to the human partner

1. **Deferral candidates** the planner identified as safe to move to v3.3 without breaking the objective: Flutter stack (one third of REQ-304/325/331/352/360), the `deploy-<env>.sh` contract (keep the image push), and guided auto-run (REQ-342/344; keep `/next` printing). The revised spec keeps all of them Must Have per the brainstorm decision; the plan sequence puts them last so they can be cut.
2. **Repo visibility.** On a free private repo the solo gate is an audit trail. Making instances public gives free macOS minutes and real branch protection. The spec states the trade-off; it does not decide it.

## Disposition

All 16 convergent findings are dispositioned into the revised spec (same branch, next commit). Verifier verdict on the first draft: REQUEST_CHANGES (findings 1–3 high). The revised spec is to be re-verified by `scripts/run-verifier.sh` on the spec PR.

## Appendix — constitution clause table for REQ-326 (from the planner reviewer)

Article count stays twelve; `tests/governance/test_constitution_articles.sh` counts `^## [IVX]+ — ` headings.

| Article | Clause to amend | Amended to name | Motivating REQ |
|---|---|---|---|
| `art-specification-primacy` | "every PR that changes `src/` must reference at least one `REQ-NNN`" | `check-test-first.sh`; `src/` → the stack's source root | 321, 326 |
| `art-branch-as-state` | "Each phase has a named branch… There is no out-of-band state file"; "The 10 phase-branch names are listed in review-gate.md" | `.specflow.yml` classified as configuration; both paths' branch names | 301, 340, 341, 343 |
| `art-review-gate` | "with verifier review and human approval" | solo mode: verifier `APPROVE` is the recorded second review (audit trail, not control, on free private repos); waiver rule; names `verifier.yml` + `run-verifier.sh` | 311, 314, 382, 326 |
| `art-test-first` | "every PR that adds `src/` code must add a test in `tests/` in the same commit or earlier" | `check-test-first.sh` | 321, 314, 326 |
| `art-formal-verification` | "Runtime-contract extraction … is deferred to v3.2"; "(v3.2+)" | v3.3+; `check-traceability.sh` and the "proof owed once a plan implements the REQ" rule | 327, 326 |
| `art-kernel-boundary` | "ARCHITECTURE-phase verifier rejects an overview whose `kernel_modules.req_map:` does not cover…" | `check-architecture.sh` | 320, 326 |
| `art-threat-driven-security` | solo severity confirmation ("next available second reviewer"); How-to-apply; back-edge names `impl/sec-<id>` / `phase/security` | `check-security-disposition.sh`; lane equivalents; mandatory "Tools run" floor; guided-solo confirmation by verifier code mode | 322, 330, 332, 340, 389 |
| `art-release-readiness` | "a dist artifact described by `dist/manifest.json` … (`dist/` itself is gitignored)"; "RELEASE-phase verifier blocks merge if…" | Release job from the tag is the artifact of record; `verify-release.sh` (in gates) + `release.yml`; tag is an ancestor of `main`; signature verified | 324, 350, 351, 353, 383, 326 |
| `art-repository-singleton` | How-to-apply | "convention (no mechanism)" | 326 |
| `art-naming-tagging` | "the verifier rejects PRs that introduce duplicate IDs or that cite a non-existent slug" | `check-traceability.sh` (duplicates) + docs-wide slug check in `test_reviews_use_slugs.sh`; `TASK-NNN` retired or used | 326 |
| `art-secrets-hygiene` | "PR review rejects any commit containing `.env`" | `gitleaks` in the floor + `.claude/settings.json` deny list | 307, 330, 326 |
| `art-retrospective-cadence` | "after every RELEASE PR merges … `phase/retro-YYYY-MM-DD`" | "after every ship/RELEASE PR"; names `/retrospective` + `docs/BACKLOG.md` | 340, 371, 326 |
