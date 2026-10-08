---
type: plan
phase: PLAN
spec: 2026-09-25-factory-v3-2
decisions: [ADR-003]
implements: [REQ-340, REQ-341, REQ-342, REQ-343, REQ-385, REQ-389, REQ-306, REQ-308, REQ-310, REQ-311, REQ-312, REQ-334, REQ-382, REQ-395, REQ-393, REQ-345]
created: "2026-09-28"
---

# Factory v3.2 — P5: Lanes, Orchestrator, Profiles and Amendment B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** a user types `/next` and is told — or, in the guided profile, walked through — the one next step of the pipeline, derived from branches, PRs and the tree and never from a state file (`art-branch-as-state`). The derivation is a pure, proved function (REQ-341): it never prints a merge command unless the branch's PR is open with an `APPROVE` or a waiver for its head and, in team mode, a human approval (REQ-385, `art-review-gate`); it tells a copy-paste user exactly what to type in a second terminal to get the verifier's review; it knows both paths' branch names (REQ-340) and the factory's own mixed history. The guided profile pauses only at enumerated confirmation points (REQ-342) and records its proposals in plain English where they land, split into decisions and acknowledgements (REQ-389). The constitution stops carrying P3's interim readings: amendment B (REQ-343) lands with this PLAN PR.

**Architecture:** ADR-003 is the design. The verified kernel is `scripts/lib/specflow/state.py` — `derive(branch, branch_pr, open_lane_prs, facts, path, solo) -> Result` over the frozen records added to `scripts/lib/specflow/records.py` — whose Dafny model `verification/factory_v3_2/state.dfy` proves MergeOnlyWhenApproved, NoBlindCreatePr, PathClosure, PrPrecedence and Progress. Everything else is unverified and fixture-tested: `scripts/lib/specflow/pipeline.py` (the wrapper: `parse_branch`, fact collection from the tree, PR state from `gh` reduced by the shared classifier `scripts/lib/specflow/attestation.py`, `render_step`, the guided confirmation points, `--explain`, `--json`) behind `scripts/next.sh`, and `.claude/commands/next.md`. `attestation.py` gains the one entry point both the CI check and `next.sh` call (`pr_attestation`), the repository-role check REQ-382 deferred to P5, and the npm lockfile's new-entry rule.

**Plan style (REQ-380):** test code included (governance tests, fixture tables, stub tools); implementation as intent, never bodies. Documents are described by the content the tests pin. Rulings of this plan are `R1`–`R22`; outside this document they are cited as "P5 R<n>", and the P3 plan's rulings as "P3 R<n>" (the R12 collision H8 records is why).

**Tier:** regulated path (REQ-381: P0–P5 walk `phase/*`, `impl/*`). This plan is the PLAN-phase PR from `phase/plan-factory-v3-2-p5` to `main`. On this branch, after this plan: the Dafny proof and its shape test (R1), then constitution **amendment PR B** (R2, section "Amendment B" below) — so the PLAN PR carries the plan, the proof and amendment B, and it is the constitution amendment PR the spec's Compliance line names for P5. `impl/plan-5-orchestrator` is cut from the plan branch after amendment B and carries Tasks 1–16 as the IMPLEMENT-phase PR stacked on it (the P2/P3 pattern): the PLAN PR merges with a merge commit, never a squash, while the IMPLEMENT PR is stacked on it (a squash would leave the plan commits in the stacked PR's `main..head`, walked again by `check-test-first.sh` and `commits.txt`; R22), and the IMPLEMENT PR is retargeted to `main` and updated before the plan branch is deleted (strict protection). `main @ b3db479` carries P0–P4 and patches #43, #44 and #46, so both PRs get a real headless marker with no bootstrap: `git show origin/<base>:scripts/run-verifier.sh | bash -s -- <PR>`. Amendment B edits `.claude/skills/verifier/SKILL.md` (step 7) and Task 10 edits `SKILL.md` and `headless-prompt.md`, so `prompt_sha256` on `main` moves when each PR merges: PRs open at that moment need their verifier run again.

**Spec:** `docs/specs/2026-09-25-factory-v3-2-design.md`, "Must Have — P5" (REQ-340, 341, 342, 343, 345, 385, 389, 393, with REQ-341's Precondition, Postcondition, Invariant and Verification-scope lines and every "As amended by ADR-003" clause), plus the P5 slices of REQ-306, 308, 310, 311, 312, 334, 382 and 395 (below). `decisions: [ADR-003]`: REQ-341 is `[verifiable-model]` and ADR-003 governs it. **The proof `verification/factory_v3_2/state.dfy` (`// Proves: REQ-341`) is owed the moment this plan lists REQ-341** (REQ-327: `check-traceability.sh` fails without it); it lands on this plan branch in the commit right after this plan, to the shape under Interfaces "The Dafny model" (R1). No REQ body changes, except REQ-389's (PR #48 verifier finding 1: 'code mode' → 'full mode', and the per-article citation), recorded in the spec's P5 IMPLEMENT `amended:` entry. The PLAN PR adds one `amended:` entry to the spec (amendment B, R4's idle step, R5's record refinements; section "Amendment B"); the IMPLEMENT PR adds one more for the wrapper rulings as shipped (Task 16), the P3/P4 precedent.

**Partial claims:**
Context citations: REQ-380, REQ-327, REQ-381, REQ-314, REQ-321, REQ-322, REQ-324, REQ-331, REQ-332, REQ-350, REQ-383 and REQ-384 are cited as context, not claims; each citing commit also cites the P5 REQ it changes, except Task 11's security-document commit, which cites REQ-332 alone (a P3/P4 hand-off; the plan lists REQ-332 as context), and the three test-only maintenance commits of earlier plans' REQs — fbbfcad (REQ-324 alone), 2b2d34d (REQ-303, an earlier plan's claim, neither a P5 claim nor listed here) and 9f5c2f9 (REQ-360, beside P5's REQ-306) (test-only maintenance of earlier plans' REQs).

- **Staged claims (R3):** REQ-342, REQ-345 and REQ-393 are delivered by this plan but are not in `implements:` at the PLAN PR — `check-covers.sh` (live since P3) fails a claimed REQ that no test cites, and their first citing tests land on the IMPLEMENT branch. Each joins `implements:` in the commit that adds its first citing test: REQ-342 in Task 7, REQ-393 in Task 8, REQ-345 in Task 12. At the IMPLEMENT PR's head the list is the full P5 set.
- **REQ-340:** delivered — both paths' grammar in `parse_branch` (both prefixes recognised whatever the configured path; `build/sec-<id>` before the build split; `patch/<slug>`), `## Build N` numbered from 1 with no gap (R6: a gap is reported and a missing number is an unknown build, Task 5), `verifier.yml`'s proof jobs on both paths' branches (R12), squash merges and both paths in `art-branch-as-state` and `review-gate.md` (amendment B), one PR-template checklist per lane (amendment B), init's next steps, README's workflow block and `CLAUDE.md`'s tables naming `/next` (Task 9). The patch tier and the minor exception are already stated for both paths (`review-gate.md:173-200`); Task 9 pins them. Open → P6: the factory's own switch to lanes (REQ-381).
- **REQ-341:** delivered — kernel, model (this branch), records, wrapper, fact collection, fixtures that mirror the model, the generated truth table.
- **REQ-342:** delivered — `/next` in both profiles, the seven confirmation points, the dfe-10 warning, `--explain`. Open → P6: `TagRelease` renders `/release`'s post-merge steps until `/release --tag` exists (REQ-383).
- **REQ-343:** delivered — amendment B on this PR; `CLAUDE.md`, README and init's next steps name `/next` for both paths (Tasks 9, 14). `constitution.md` on this branch is an amendment-B follow-up (two corrections), signed off in #48's merge comment.
- **REQ-345, REQ-385, REQ-393:** delivered.
- **REQ-389:** the remainder after P3's `check-architecture.sh` clause — proposals with plain-English rationale and user-facing consequence where each lands, the decisions/acknowledgements split, the verifier's confirmation in guided solo mode recorded as provisional (in full mode, the part that reads the documents where acknowledgements land — R19's reading of the REQ's "code mode", recorded in Task 16's `amended:` entry), `confirmed_by:`'s meaning (R19). Nothing stays open; P7's habit-tracker walk (REQ-391) exercises it.
- **Slices:** REQ-306 (instances do not receive the factory's own design documents and proofs, R11); REQ-308 (`/next` links a glossary term on first use; the glossary gains its terms); REQ-310 (the verifier's prompt names the base's `profile` and `solo`, R19); REQ-311 (`next.sh` shares the classifier through `pr_attestation`); REQ-312 (the HTTP 403 message names `/next` as present); REQ-334 (npm lockfile entries, R10; Dependabot batching, R15); REQ-382 (the repository-role check for `MEMBER` waivers, R9; `--explain` reports an unlinked waiver, R20); REQ-395 (README's enforcement paragraph names `/next` as present).
- **Not claimed, with the reason:** REQ-322 — `next.sh` does not change the disposition wrapper; P3 R11's changed-files resolution for `phase/security`/`phase/release` stays, and `next_version` only shapes what `/next` proposes (R13). REQ-313 — the verifier's isolation is unchanged. REQ-314 — amendment A's; amendment B records the maintainer's sign-off on its zero-approval rule, which is REQ-343's clause. REQ-381 — exempt (ARCHITECTURE-phase deliverable). REQ-331, REQ-332 — R17's rulings change no behaviour. REQ-370 (Should Have) — `--json` emits the `Result`; `render_dashboard.py` reading it → P7.
- **Open → P6:** `release.yml` and the tag-time replay of the gates and the Dependabot rule (REQ-350), `/release --tag` (REQ-383), the CI-built manifest (REQ-384), the factory's own switch to lanes (REQ-381); art-release-readiness's sentence 'until release.yml replays these checks at the tag (REQ-350), that checkbox is the only check…' expires when REQ-350 ships — P6 (or amendment C) owes the article update. **Open → P7:** amendment C (REQ-326) naming `scripts/next.sh`, `scripts/lib/specflow/state.py` and `scripts/lib/specflow/pipeline.py` as mechanisms; amendment C also carries art-branch-as-state's `impl/plan-N-<name>` → `impl/plan-N-<plan slug>` (N the plan's `## Build N` section), as review-gate.md, CLAUDE.md and README already say (PR #48 verifier run 4, finding 4; the PR template's Build-lane heading and init's next steps say `impl/plan-N-<plan slug>` from the P5 lows patch (`patch/p5-mediums`) on, so the article is the last rule text that says `impl/plan-N-<name>` (ADR-003:64 and `state.dfy`'s comments still carry it, for the P7 ADR touch alongside amendment C)); the habit-tracker example (REQ-391); the retrospective, which receives R14's hook proposal and R16's open-medium proposal (REQ-371's backlog).

**ARCHITECTURE artifacts:** P5 walks the full phase path, so its IMPLEMENT branch may update the architecture documents the spec's ARCHITECTURE PR produced where P5 completes what they describe, each edit its own task with a governance test (the P3 Task 14 pattern): **Task 15** — `docs/architecture/2026-09-25-factory-v3-2-overview.md` (`:36` the kernel row, `:42` the classifier bullet, `:76` the interfaces bullet, `:132` "P5 extends … creates …" as shipped) and `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` (`:103` the shipped-plans sentence, the dfe-2, dfe-7, dfe-10 and dfe-13 rows, the `:192` open-medium residual with R16's proposal, and new residuals for the wrapper). Amendment B changes one threat-model phrase on this branch (`:195`, "until amendment B"), because it names the amendment that this PR lands. The IMPLEMENT PR body lists Task 15 under **Architecture-artifact updates**. No ADR is added or changed; R5 and R6 refine ADR-003's records inside its own "a `Facts` field if needed" consequence and are recorded in the spec's `amended:`.

**Rulings** (decided here; the PLAN and IMPLEMENT PRs implement them):
- **R1 — the proof, and its shape test, travel on the plan branch (H1).** `check-traceability.sh` (REQ-327) fails as soon as this plan lists REQ-341 and no `verification/**/*.dfy` carries `// Proves: REQ-341` in its first five lines; `ci.yml`'s `gates` job runs on every PR. So `verification/factory_v3_2/state.dfy` is written by the step right after this plan, on `phase/plan-factory-v3-2-p5`, to the shape under Interfaces "The Dafny model", together with `tests/governance/test_state_model.sh` (full code below), which cites REQ-341, REQ-385 and REQ-340 — the model is their first layer. The model step's first commit (`42d0bea`) carried `state.dfy` alone, which left the PLAN PR's gates red (`check-covers.sh`, `test_check_covers.sh`, `test_traceability.sh` and `test_examples.sh`: no test cited REQ-341 or REQ-385); the fresh-eyes revision commits the test with the revised proof, and the IMPLEMENT branch is cut only after it. It verifies under the local Dafny 4.11.0 and the CI-pinned 4.9.1 (`bash scripts/install-pinned-tool.sh dafny --dest "$TMPDIR/dafny491"`); gates section 2 verifies it in CI on the PLAN PR (`verify-dafny` does not run on a `phase/plan-*` head until R12 lands). The IMPLEMENT branch adds the Python twin and the fixtures that mirror the model; it may amend the proof only in a commit that keeps the twin, the fixtures and the model's names in step, verified under both versions.
- **R2 — amendment B lands on the plan branch, before the IMPLEMENT branch is cut (H2).** The spec's P3 `amended:` entry and `RUBRIC.md` set its deadline (no later than 2026-10-31) and name P5's PLAN PR as its carrier. The section "Amendment B" below is executed on this branch after R1's commit: the governance tests that pin the interim text are rewritten first, then the constitution and the eight documents it edits besides it (review-gate.md, RUBRIC.md, SKILL.md, the PR template, the schema template, GLOSSARY.md, the threat model, the spec). It changes no gate script; SKILL.md step 7 and the PR template are verifier-instruction and `.github/` surfaces a human reads as gate code (the step 7 edit removes the lapsed-deadline high-finding rule, correct once amendment B merges). Every control it describes is the one already running; it removes the interim-reading override text, never a mechanical check.
- **R3 — claims go live with their citing test.** P3 R18 switched `check-covers.sh` on; since then a PLAN PR that claims a REQ no test cites fails section 6. The PLAN PR claims the REQs whose first citing test is on the plan branch or already exists (REQ-341, 385 and 340 via `test_state_model.sh`; REQ-343 and 340 via amendment B's tests; REQ-389 via P3's; the slices via existing tests). REQ-342, REQ-393 and REQ-345 join `implements:` in the IMPLEMENT commit that adds their first citing test (Tasks 7, 8, 12). No test is written to satisfy the checker ahead of the behaviour it tests, and `check-covers.sh` is not changed.
- **R4 — REQ-393's idle step is ADR-003's rendering (H3).** REQ-393's literal `(none, idle, "run /specify <slug>")` predates ADR-003's amendment of REQ-341 (idle creates `design/<slug>` and runs brainstorming first). `test_first_run.sh` asserts what the accepted architecture derives: on `main` in the remote-less instance, `state: none idle`, step `NewBranch(ProposeDesign)` rendered as `git checkout -b design/<slug>` followed by `/superpowers:brainstorming` (lanes, the guided case); `NewBranch(ProposeSpec)` rendered as `git checkout -b phase/spec-<slug>` followed by `/superpowers:brainstorming` (regulated, the engineer case); in both, `pr_state_known` false, never `awaiting-verifier` and never `CreatePr`. The model proves the derivation (`RemoteLessMainIsIdle`); the spec's P5 PLAN `amended:` entry records the reading.
- **R5 — the kernel's records refine ADR-003 without changing its rules.** (a) `PR` gains `mine` (author login equals `gh api user`'s): precedence 3 names "open lane PRs authored by the current user", which the record must carry. (b) `Impl(plan, name)`: `plan` is the token after `plan-` (`[0-9]+[a-z]?`), a string, because the factory's own history has `impl/plan-1a-first-run` and `impl/plan-1b-app-packs`. (c) `Step`'s arguments are datatypes, so strings stay out of the proof: `NewBranch(Proposal)`, `RunImplement(ImplTarget)`, `ExplainUnknown(Why)`, `AddressFindings(pr)`; `render_step` makes names and text. (d) An `Unknown` branch derives `(none, unknown-branch, ExplainUnknown(BranchUnknown))` before precedence 1, so no PR on an unknown branch yields a merge (dfe-7). (e) On `Main`, `branch_pr` must be `None` (a PR whose head is `main`, as the factory's closed #1, is never the branch's PR). (f) `UnknownBuild` is checked after precedence 1 and 2: an open PR on `build/<slug>-N` still reports its substate. (g) `open_lanes` is every open lane PR's number, sorted, on every derivation. (h) `pr_state_known` false requires `branch_pr` `None` and no open lane PRs.
- **R6 — the regulated path's `main` precedence.** ADR-003 says `main` "proposes the next `phase/*` branch instead of a lane" but carries no fact that tells validate, security and release apart. `Facts` gains `ship_phases_merged ⊆ {validate, security, release}` (merged `phase/validate`, `phase/security`, `phase/release` PRs whose merge commit is not an ancestor of the latest release tag). Regulated precedence 3: own open lane PRs → `Checkout`; `untagged_ship` → `(release, tag)`; `unbuilt` → `NewBranch(ProposeImpl(slug, n))` (`impl/plan-<n>-<slug>`); `next_version` set → `ReadyToShip` with `ProposeValidate`, else `ProposeSecurity`, else `ProposeRelease`, the first not in `ship_phases_merged`; else `Idle` with `ProposeSpec`. `unbuilt` is computed from `## Build N` sections on both paths (the plan template's shape); a plan with no such section (the factory's P0–P5 plans, the demo's) contributes nothing, and `--explain` says `/next` does not track it. REQ-340's "N from 1, contiguous": a plan whose section numbers are not exactly `1..max` (say `## Build 1` and `## Build 3`) gets a `note:` naming the plan and its numbers ("builds are numbered from 1 with no gap, REQ-340"); `unbuilt` lists only sections that exist, so the gap is never proposed, and `build/<slug>-2` derives `unknown-build` (the kernel's `n ∉ build_sections`). The kernel is unchanged; `test_next.sh` pins the note.
- **R7 — the wrapper's facts.** `pipeline.py` computes only the facts the branch's lane reads (a fact the lane does not read cannot change the result; `--json` reports it as `null`): artifact presence by slug (`docs/specs/<date>-<slug>-{brainstorm,design}.md`, a plan named `<date>-<slug>-plan.md` or whose `spec:` is the slug's spec), `spec_has_tagged_reqs` through `frontmatter.tagged_reqs`, `arch_complete` (every tagged REQ addressed by some `docs/adr/*.md` `addresses:`, the overview and the threat model present, and `check-architecture.sh` exit 0), `analyze_ok` (a plan exists and `analyze-adr-plan-linkage.sh` and `check-traceability.sh` exit 0), `build_sections` (`^## Build ([1-9][0-9]*):` in the slug's plans), `has_source_diff` (a path `packinfo.is_source` or `packinfo.is_test` in `git diff --name-only <base>...HEAD`, committed or not), `gates_pass` only under `--gates` (which runs `run-quality-gates.sh`; otherwise false and explained), the ship lane's docs by version, `signing_key_present` (`git config --get user.signingkey` non-empty). The base is `--base`, else `SPECFLOW_BASE_REF`, else the PR's base (`origin/<baseRefName>`), else `origin/main`, else `main`. With a branch PR, `solo` is the base's (`pr_attestation`'s policy read at `origin/<baseRefName>`, as the CI check reads it, dfe-6); without one, the working tree's configuration. `next.sh` writes nothing: not the tree, the index, a ref or a file under `.git` (no `git fetch`); a test compares `git status --porcelain --ignored` and `git for-each-ref` before and after. Because it never fetches, `--explain` prints the base it judged against — `why: base origin/<b> at <sha7>, committed <date> (this checkout's view; next.sh never fetches)` — so a stale `origin/<base>` is visible. `next.sh` runs the checkout's own `pipeline.py`, `state.py`, `records.py` and `attestation.py`, never the base's copies (it is a local advisory tool, and `pipeline.py` is itself the checkout's): a PR that edits them can make `/next` print a merge command the CI check (which runs the base's classifier) refuses, and a stale base can judge `prompt_sha256` differently from CI — Task 15 records both as residuals; the server-side `verifier` check, where protection works, is unaffected.
- **R8 — the template source, retrospectives, and a path override.** The template source has no `.specflow.yml`, so `config.DEFAULTS` apply (profile guided, path lanes); `next.sh` prints `note: template source (no .specflow.yml): profile guided, path lanes are the defaults; the factory walks the regulated path until P6 (REQ-381) — run with --path regulated to see its own state`. `--path lanes|regulated` overrides the configured path for that run (printed as `path regulated (--path)`); configuration is still never state. `phase/retro-YYYY-MM-DD` is `Unknown` in the kernel (ADR-003 lists no retro constructor); `render_step` explains it as a retrospective branch (`/retrospective`, then a PR; `art-retrospective-cadence` is a convention).
- **R9 — a `MEMBER`'s or `COLLABORATOR`'s marker or waiver needs a writing repository role (H6; rule 1b as shipped).** REQ-382 as amended defers "a check of the commenter's repository role" to P5; `MEMBER` is any organisation member, read-only ones included, and a `COLLABORATOR` may hold only the read or triage role. **Rule 1b, as shipped** (the P5 final review widened it from waivers to every marker-bearing comment, and PR #48 verifier runs 2–3 settled both directions): a `MEMBER`'s or `COLLABORATOR`'s marker or waiver counts only with a writing role — `admin`, `maintain` or `write` (`gh api repos/<repo>/collaborators/<login>/permission`: its `role_name`; a custom or empty `role_name` is resolved through the legacy `permission` field, and a role neither field names is unreadable); `OWNER` needs no lookup. Both directions: an unreadable role is never accepted and keeps blocking — the comment is never an approval or a waiver (`marker-permission-unknown`, `waiver-permission-unknown`), but its blocking rules run as for a writer, a blocking result suffixed `-permission-unknown`, and its `REQUEST_CHANGES` for the head still counts (`request-changes-permission-unknown`); a known `read`, `triage` or `none` role neither accepts nor blocks (`marker-not-writer`, `waiver-not-writer`) — a principal who cannot approve cannot block either; this narrows the pre-P5 rule, under which such a comment blocked whatever its role, and the maintainer waives the verifier's high on it at #48's merge. **The base binding:** a marker's recorded base must be 40 hex characters and be the PR's current base tip or give the head the same merge base; otherwise `base-mismatch` refuses only an `APPROVE`'s acceptance, and a `REQUEST_CHANGES` for the head still counts (`request-changes-base-mismatch`), so a retarget never revives an older approval. `classify` takes `permissions: dict[login, role] | None`; `check()` and `next.sh` (`pr_attestation`) fetch the role for each `MEMBER` or `COLLABORATOR` whose comment bears a marker occurrence; `check --permissions FILE` is a test-only input `verifier.yml` never passes. A CI token that cannot read roles therefore rejects every `MEMBER` and `COLLABORATOR` approval and waiver and leaves `OWNER`'s working; in solo mode markers stay self-attested (REQ-314), which the claim table says. **On an organisation repository the maintainers themselves are `MEMBER`**: a read-only check (2026-09-28) shows `kpingali123`'s comments on `Apps-Consultants/factory` carry `author_association: MEMBER` (PR #46), so every maintainer waiver on this repository will need the lookup, made with `verifier.yml`'s `GITHUB_TOKEN` (`contents`, `issues` and `pull-requests: read`). The token's access is unproven, and the IMPLEMENT PR's own `verifier` run cannot prove it: `verifier.yml` materialises `attestation.py` from `origin/<base>` (the plan branch, later `main`), which has no lookup until the IMPLEMENT PR merges. So Task 4 probes it first with a throwaway draft PR (the CI-diagnostics pattern); if the token is refused, the orchestrator stops before Task 4's R9 part lands and asks the maintainer (the one decision this plan does not pre-set: fail-closed would remove the maintainer's own waiver route). The claim row and the PR body say that organisation maintainers are `MEMBER`.
- **R10 — an npm lockfile may not grow (H11).** `_package_lock_rule` refuses a `node_modules/<name>` key the base's `packages` map lacks (`content:<path>:new-entry`) and a name added to any entry's `dependencies`, `optionalDependencies`, `peerDependencies` or `devDependencies` map (`content:<path>:dependency-added`); ranges may move, entries may disappear. Most real npm bumps then need attestation, which costs nothing today: no `dependabot.yml` watches npm (P4's Deferred). dfe-13's residual and `review-gate.md`'s Dependabot row say so.
- **R11 — instances do not receive the factory's own design documents and proofs (H7, REQ-306).** `scripts/factory-only.txt` lists, one glob per line, the factory's v3.2 spec and brainstorm, ADR-003, the v3.2 overview and threat model, every `docs/plans/*-factory-v3-2-*-plan.md`, the factory's reviews (every review the examples manifest does not list), `verification/factory_v3_2/`, and itself. Init removes every match before it removes `stacks/`, then the manifest, matching the globs against a filesystem walk of the new tree (relative paths, `.git` skipped): at that point `copy_template` trees have no `.git` yet (`git init` runs at `init-project.sh:662`), so `git ls-files` would exit 128. So an instance's traceability counts only its own specs (and the python demo's), no inherited proof dangles when a spec is deleted, tauri and flutter instances no longer need Dafny, and every REQ, ADR or proof added later to those documents is fenced with them. **ADR-002 stays in instances:** it defines the disposition gate's rules 1–5 that every instance runs, and the documents an instance's sessions read cite it (`CLAUDE.md`, README, `/security-review`, `review-gate.md`'s SECURITY exit gate, the glossary, `RUBRIC.md`, the PR template); its one mention of the template's proof path is history in its Consequences. ADR-003 is fenced, and the documents an instance's sessions read never cite it (Task 13 checks the id, not only the path). A `REQ-3xx` an instance's documents cite names the template's own requirement, kept as provenance; the glossary's Factory documents entry says so. A governance test fails when a factory document is not matched by the manifest (any path naming `factory-v3-2` or `factory_v3_2`, any ADR addressing a REQ of the factory spec other than ADR-002, any review the examples manifest does not list). `frontmatter.INHERITED_SPEC_SLUGS` keeps both slugs (instances created before P5 still hold the factory spec). New REQ numbers in an instance continue after the highest `REQ-NNN` cited anywhere in its tree, as `/specify` says: the template's governance tests cite REQ-1xx–3xx, and a fresh REQ-300 would be "covered" by `test_init.sh`'s citation.
- **R12 — the proof jobs run on both paths (H4).** `verifier.yml`'s `verify-dafny` and `contract-alignment` jobs run on the `has-verification` label or a head branch starting `impl/`, `phase/validate`, `phase/plan-`, `design/`, `build/`, `ship/`, `phase/security` or `phase/release` (the regulated path's ship pair, PR #48 verifier run 2) — every branch where a proof, a contract or its twin travels on either path. `verify-dafny` adds nothing `ci.yml`'s gates section 2 does not already do on every PR (the same pinned 4.9.1 over `verification/**`); it stays as the verifier workflow's second, independent run, not a required check, and running it on every PR would spend minutes on doc-only PRs for no new signal. `patch/` is left out (a patch never touches a `[verifiable*]` REQ).
- **R13 — the security branches' version (H16).** P3 R11 stays: `check-security-disposition.sh` on `phase/security`/`phase/release` evaluates the versions the changed files name. `next.sh` passes no `--version` to any gate; `Facts.next_version` shapes only what `/next` proposes (`ship/<version>`, `/security-review <version>`, `/release <version>`), so REQ-322's behaviour is unchanged and not claimed.
- **R14 — no PreToolUse merge-blocking hook (H5).** Ruled out: REQ-342 as amended has guided `/next` run `gh pr merge` after the pre-merge confirmation point, which a blocking hook would break; project hooks are per-checkout and editable by any PR (dfe-10), so a hook is not a control; `main` is protected server-side on this repository and the admin bypass is the recorded residual; no REQ asks for it. Proposed for the P7 retrospective: a `permissions.ask` rule for `Bash(gh pr merge:*)`, which prompts rather than blocks.
- **R15 — Dependabot batching (H14).** Adopted: `.github/dependabot.yml` groups each ecosystem's updates into one weekly PR (`groups:` with `patterns: ["*"]`). Recorded where a maintainer reads it (the file's comment, the glossary's Dependabot entry, README): a pip bump of ruff, black, pytest or pytest-cov that moves only `scripts/requirements.txt` is exempt from the `verifier` check but stopped by the `gates` check (`test_python_lockfiles.sh` pins each to one version in both lockfiles; folding it into the pack lockfile also moves `pack.yml`, which `test_stack_packs.sh` and `test_coverage_floor.sh` check), a workflow action bump touches `.github/`, which the classifier's exemption refuses (attestation needed), and the maintainer consolidates a batch into one attested `patch/<slug>` PR (the #43 precedent) and closes the Dependabot PRs as superseded.
- **R16 — open mediums (H9).** No kernel change in P5 (ADR-002 rule 3 and the constitution's SECURITY gate count accepted/deferred mediums only). Proposed for amendment C / P7, as REQ text for the spec amendment that adopts it (it assigns the id): "A current finding of severity medium with `status: open` counts toward `medium_cap` and needs `owner:` (not `expiry:`); `check-security-disposition.sh` fails an ownerless open medium (ADR-002 rule 3 revised; the Dafny model's `MediumsAD` gains open mediums)." Task 15 writes it into the threat-model residual.
- **R17 — floor thresholds and the template's own reviews (H12, H13).** H12: REQ-331 sets the thresholds (`bandit --severity-level high`, `npm audit --audit-level=high`, "severity thresholds apply only where the tool supports them"); lowering them would contradict the REQ's literal commands. The floor's pass is not the review: `/security-review` runs each thresholded tool once more at the next level down (`bandit … --severity-level medium`, `npm audit --audit-level=moderate`) and records what it finds as findings; a finding below the floor's threshold needs no `SEC-NNN` suppression, because the floor never fails on it. H13: REQ-332 requires the tools table "when the product has a dependency manifest (a lockfile under the pack's source roots; `scripts/requirements.txt` alone does not count)"; the template source's product is the demo, which has none, so a table-less review is conformant there. Both rulings are pinned by tests (Task 11).
- **R18 — the tauri skeleton review (H8).** Under the schema-migration rule (`docs/security/README.md`), as a header and prose edit only — no SEC id added, removed or re-scored, vectors unchanged: `R12` becomes `P4 R12` and `R20` becomes `art-threat-driven-security`'s informational row (amendment B), and SEC-002's and SEC-003's exploitability tables are labelled "recorded for the vector's shape only: with every impact metric `N` the vector scores 0.0 whatever these rows say". The maintainer confirms the exception in the IMPLEMENT PR's merge comment (the README's rule); the PR template's SECURITY checkbox asks for it.
- **R19 — REQ-389's guided surfaces.** **Decisions** (the human answers): the stack (init), the product scope (end of brainstorm, before `/specify`), release go/no-go (before the ship PR). **Acknowledgements** (the human is shown): the `[verifiable-model]` tags (spec), the kernel boundary (overview), severity scores and dispositions (security review). Each proposal is written where it lands under a `Guided proposals` heading with a `Rationale (plain English):` line and a `What this means for you:` line; `/specify`, `/architecture` and `/security-review` write them in the guided profile only. `confirmed_by:` means the GitHub handle and date of the human who made the decision or was shown the acknowledgements (`confirmed_by: alice 2026-09-28`); `check-architecture.sh`'s presence rule stays the only mechanical check (a format check would prove nothing about who confirmed). **Where the verifier confirms them:** acknowledgements land in `docs/specs/*.md`, the overview, the threat model and `docs/security/*-review.md`, which REQ-310's review scope classes as documents, so a lanes design PR and a ship PR are doc-only and get full mode alone; a code-mode pass would never run on the PRs that carry them. So in guided solo mode the verifier's **full mode** reads each changed document's `### Guided proposals`, confirms or not each acknowledgement against the document's own content, and lists the result as one provisional finding (`Guided acknowledgements (provisional): …`, severity low, citing each acknowledgement's own article — `[verifiable-model]` tags `art-formal-verification`, the kernel boundary `art-kernel-boundary`, severity and dispositions `art-threat-driven-security`; an acknowledgement it cannot confirm is a medium finding). Code mode is unchanged (its five headings, REQ-310); a mixed PR gets both parts, and the full-mode part covers the documents. This reads REQ-389's "the verifier's code mode confirms" as the part of the verifier that reads those artifacts, and REQ-389's body now reads so (PR #48 verifier finding 1: its 'code mode' became 'full mode', with the per-article citation), a REQ body change the spec's P5 IMPLEMENT `amended:` entry records. `run-verifier.sh` adds `Profile:` and `Solo:` lines, read with `attestation.py policy` at the base ref, to the prompt. **Asked once, where `/next` shows it:** a command's `## Guided profile` section asks a decision or shows acknowledgements only when the user ran the command directly; when `/next` ran it, the command asks nothing, because `/next` asked at its confirmation point (scope at `brainstorm-end`, the acknowledgements at `design-pr`, go/no-go at `ship-pr`, after the release documents exist), and the `confirmed_by:` line is written at that `/next` point. REQ-342 allows no other pause.
- **R20 — an unlinked waiver (H15).** The PR body is author-editable and not a re-trigger, so no check: when the branch PR's attestation is `waiver`, `next.sh --explain` prints `why: waiver accepted (<url>), not linked from the PR body — REQ-382's convention, the PR template's checkbox` unless the body contains the waiver comment's URL.
- **R21 — PR state's edge cases (the wrapper; Fail safe).** (a) **A reused branch name.** `phase/validate`, `phase/security` and `phase/release` are fixed names every release cycle reuses, and a `patch/<slug>` can be reused: an open PR whose head is the branch always counts, but a merged or closed one counts as the branch's PR only when its `headRefOid` equals the local `HEAD`; otherwise the branch has no PR (`why: PR #<n> (merged) is an earlier use of this branch name — its head <sha7> is not HEAD`), so a new `phase/validate` after a release derives `validate gates`, never the previous cycle's `merged` and a loop back to `git checkout -b phase/validate`. (b) **A base missing locally.** When `origin/<baseRefName>` is not in the checkout (a stacked PR's base never fetched), the attestation is `none` with `why: base origin/<b> not in this checkout (git fetch origin <b>)`, and `solo` fails safe to team mode (`false`), never the working tree's configuration (PR #48 verifier run 2; likewise a PR head missing locally or an unreadable attestation). (c) **A merge commit missing locally.** A merged PR whose merge commit is not in the checkout (not pulled yet) counts as not an ancestor of the latest release tag — its build is unreleased — and `--explain` names it (`why: the merge commit <sha7> of PR #<n> is not in this checkout: counted as not released (git pull)`). (d) **An empty `reviewDecision`.** GitHub fills `reviewDecision` only where protection requires reviews; when it is empty (and not in solo mode), `human_approved` comes from `gh pr view <n> --json reviews`: a reviewer's latest review at the head decides (`commit.oid` equal to `headRefOid`), and the PR is approved when at least one such latest review is `APPROVED` by a reviewer who counts — an `OWNER`, or a `MEMBER` or `COLLABORATOR` whose repository role is `admin`, `maintain` or `write` (rule 1b's lookup, R9; unreadable fails closed), who is neither the PR author nor an author or committer of any of its commits — and an undismissed `CHANGES_REQUESTED` at any commit means no approval (a reviewer's latest review at any commit being a change request, until that reviewer approves or it is dismissed; PR #48 verifier run 2 and the P5 final review).
- **R22 — rendering on stacked PRs.** (a) `Merge(pr)` renders `gh pr merge <pr> --squash`, except when an open PR's base is this branch: then `gh pr merge <pr> --merge`, followed by the stacked PR's retarget (`gh pr edit <m> --base <this PR's base>`, `main` or the branch this PR is itself stacked on, before this branch is deleted) — a squash would leave the merged commits in the stacked PR's `main..head`. As shipped (PR #48 verifier run 4, finding 6): the stacked line is only shell commands, the merge first — `gh pr merge <pr> --merge --match-head-commit <head> && gh pr edit <m> --base <this PR's base>` (main, or the branch this PR is itself stacked on), no `--delete-branch`, so the branch survives and the stacked PR keeps the merge base its marker recorded (a retarget first would make that marker `base-mismatch`) — and the explanation (including updating the stacked PR where `main`'s protection requires up-to-date branches) is a `notes` line. (b) `RunVerifier(pr)` renders REQ-385's instruction with the PR's own base (`origin/<base>`, the base-ref form of REQ-313 that `review-gate.md` step 3 uses) and the sentence "In a second terminal, not inside Claude — open a new terminal window …" (REQ-385's literal prefix joined to its amended text); when the base is not `main`, it adds `Warning: origin/<base> is not main — the script comes from a branch no review has approved yet (a PR author chooses a stacked PR's base); read it first with git show origin/<base>:scripts/run-verifier.sh`. Task 15 records the stacked-base residual; Task 16's `amended:` entry records both readings of REQ-385's quoted text.

**Verified against:** 2026-09-28 @ main `b3db479` (worktree `.claude/worktrees/p5`, branch `phase/plan-factory-v3-2-p5`); every `file:line` anchor below was checked there; the rulings' later anchors re-verified at the IMPLEMENT branch head.
- **Constitution.** `constitution.md`: `art-branch-as-state` `:25-37` ("No work on `main`" `:34`); `art-review-gate` `:41-85` (Dependabot sentence `:71-75`, admin wording `:77-80`); `art-threat-driven-security` `:142-171` (band table `:153-158`, back-edge `:171`); `art-release-readiness` `:175-187` ("tag missing" `:187`); `art-retrospective-cadence` `:244-256`. Amendment A (`0b546c0`) changed the text in place with a REQ-citing subject and no dated note.
- **Rules and interim text.** `.claude/rules/review-gate.md`: claim rows `:58-72` (waiver `:62` "deferred to P5", Dependabot `:64` "tracked for constitution amendment PR B (P5)", disposition gate `:70` naming `verification/factory_v3_2/disposition.dfy`, release gate `:71` "R19's one gap"); "Paths and branch names" `:74-106`; mapping `:108-120`; RELEASE exit gate `:137` (R19's and R20's interim readings and the deadline sentence); back-edge `:139-150`; patch tier `:152-167`; minor exception `:169-181`. `docs/security/RUBRIC.md:13-19` (the 0.0 row), `:28-33`, `:35-38` (interim paragraph and deadline). `.claude/skills/verifier/SKILL.md:34` (step 7), `:44-66` (code mode; headings `:56-62`). `.claude/skills/verifier/headless-prompt.md:1-19` (placeholders `@MODE@`, `@BASE@`, `@HEAD_BRANCH@`, `@DOCS@`, `@CODE@`, `@INPUT_DIR@`). `.github/PULL_REQUEST_TEMPLATE.md:14-30` (phase sections; RELEASE checkbox `:30`). `schemas/security-disposition-template.md:41`, `:62`, `:98-99`, `:108`. `docs/GLOSSARY.md:89-127` (Dependabot; `:127`), `:145`, `:178` (Lane), `:305-321` (Waiver; `:316`). `docs/architecture/2026-09-25-factory-v3-2-threat-model.md:103`, `:110`, `:115` (dfe-7), `:118` (dfe-10), `:121` (dfe-13), `:192`, `:195`. Overview `:36`, `:42`, `:76`, `:132`.
- **Tests that pin interim text.** `tests/governance/test_onboarding_surface.sh:222-225`, `:232-267`; `test_review_gate_claims.sh:163-172` (`DEPCON`), `:245-256` (`AMB_DL`); `test_security_schema_docs.sh:84-85`; `test_spec_lifecycle.sh:106` (the "no later than" exemption), `:156`; `test_threat_model_current.sh:62-70`; `test_verify_release.sh:12` (a comment). Tests that pin "later plan": `test_onboarding_surface.sh:121-131`, `test_configure_repo.sh:27`; "deferred to P5": `test_review_gate_claims.sh:114-115`.
- **Classifier.** `scripts/lib/specflow/attestation.py`: header `:9` ("P5's next.sh imports"), `_TRUSTED` `:382`, `_package_lock_rule` `:608-660`, `_WAIVER_TRUSTED` `:1022`, `_judge_comment` waiver branch `:1078-1089`, `classify` `:1132-1167`, `explain` `:1170-1180`, `check` `:1314-1440`, CLI `:1585-1655`. `tests/governance/test_attestation.sh:159-171` (fixture loop, "71 or more"); `tests/governance/fixtures/attestation/01-…json` to `71-…json` (18 is a `MEMBER` waiver).
- **Scripts and workflows.** `scripts/init-project.sh:597-607` (examples removal), `:609` (`rm -rf stacks`), `:625` (init's commit on `main`), `:637-651` and `:654-668` (next steps). `scripts/configure-repo.sh:69-73` (403 text). `.github/workflows/verifier.yml:94-100`, `:120-126` (proof-job conditions). `.github/dependabot.yml:1-16`. `.github/ISSUE_TEMPLATE/idea-seed.yml` (referenced only by `docs/reviews/2026-09-25-template-objective-review.md:52` and the spec). `scripts/run-verifier.sh:515-530` (policy read), `:760` (`Findings posted to PR #$pr.`). `scripts/lib/specflow/disposition_gate.py:170-190` (`ship/<version>`; `VERSION_RE` `:295`). `scripts/lib/specflow/release_gate.py:173` ("(F-10/W-7, P5)"). `scripts/lib/specflow/records.py:1-6` ("state records … are P5's"). `scripts/lib/specflow/frontmatter.py:107` (`INHERITED_SPEC_SLUGS`). `scripts/lib/specflow/config.py:18-27` (`KEYS`, `DEFAULTS`: guided, lanes). `.claude/commands/security-review.md:60` (names the P4 plan), `:92` (back-edge names only `impl/sec-`). `tests/governance/lib/check.sh` (`copy_template`, `stub_bin`, `verifier_repo`, `GIT_CONFIG_GLOBAL=/dev/null`). Every trap `rm -rf` in `tests/governance/test_*.sh` (27 files; `test_examples.sh:21`).
- **The factory's PRs** (`gh pr list --state all`, read-only, 2026-09-28): heads `phase/spec` (#2, #3), `phase/spec-v3.1` (#4), `impl/plan-1-foundation` … `impl/plan-3-demo` (#5–#7), `impl/fix-p0-ci-enforcement` (#9), `impl/p1-adoption-path` (#10), `chore/*`, `phase/spec-factory-v3-2` (#20), `impl/plan-0-plan-scoping` (#21 closed, #22 merged), `phase/arch-factory-v3-2`, `phase/arch-factory-v3-2-fixes`, `impl/plan-1a-first-run`, `impl/plan-1b-app-packs`, `phase/plan-factory-v3-2-p1a` … `-p3`, `impl/plan-2-verifier-attestation`, `impl/plan-3-mechanized-gates`, `impl/plan-4-security-floor`, `patch/p1a-mediums`, `patch/p2-mediums`, `patch/action-bumps`, `patch/p3-mediums`, `patch/first-run-argmax`, `diag/first-run-floor`, `dependabot/…` (#37–#40 closed), and #1 whose head is `main` (closed). Tags: `v0.0.1-demo` only (a pre-release).

**Tool facts on this Mac (2026-09-28):** dafny 4.11.0 (Homebrew), CI pins 4.9.1 (`scripts/pinned-tools.yml`); git 2.54.0 (`GIT_CONFIG_COUNT` since 2.31); python3 3.12.4 host conda (never `pip install` into it); the gate venv `~/.venvs/factory-tools` (ruff 0.16.9, black 26.5.1, pytest 9.1.1, pytest-cov 7.1.0) first on `PATH` for every gates or governance-test run; gh 2.97.0 with two accounts (always `GH_TOKEN="$(gh auth token --user kpingali123)"`); actionlint 1.7.12; node v24.8.0; the default gates ~1:30 here, ~3:00 in CI; `test_examples.sh`'s EXIT-trap flake seen three times on macOS (H10).

**Clause → task:**

| REQ | Clauses (task numbers; AB = the amendment B section on this branch; M = the model step, R1) |
|---|---|
| 340 | lanes and regulated branch grammar 3; both prefixes whatever the path 2, 3, M; `build/sec-<id>` before the build split 3; N from 1, contiguous sections (a gap is noted, R6), unknown-build 2, 5; ship offered when every build merged 2, 6; squash merges AB; patch tier and minor exception for both paths 9; gates identical on both paths 9 (R12) |
| 341 | inputs (Branch, PR, Facts, path, solo) 2, 5, 6; `attestation.py` reduction 4, 6; no remote or `gh` failure → empty lists, explained 5, 6; exactly one Result in the enumerated set 2; PR substates first 2; merged/closed 2; `main` order 2, 6; first missing after last present, architecture as a gate 2, 5; no `CreatePr` without PR state 2, M; `build/sec-<id>` implement 2; `render_step` incl. the second-terminal text 3; pure, no state file, deterministic, every state has a step 2, 5; merge only when approved incl. human approval 2, M; proof obligations M; tests of `parse_branch`, `render_step`, the classifier, facts with fixture repositories incl. remote-less, the truth table 2, 3, 4, 5, 6 |
| 342 | engineer prints 7; guided runs exactly the engineer commands 7; confirmation points (brainstorm end, design PR with REQ-389 acknowledgements, each build PR, ship PR, awaiting-verifier, before merge, unsigned tag) 3, 7; `--explain` 5, 6, 7; the other-author checkout warning 6, 7 |
| 343 | constitution text AB; `review-gate.md` both paths and mapping (P1, pinned) 9; PR template one checklist per lane AB; `CLAUDE.md` tables, README workflow block, init's next steps 9, 14; Dependabot sentence, admin bypass, solo sign-off AB; R19 and R20 settled AB |
| 345 | the issue template removed, nothing references it 12 |
| 385 | awaiting-verifier renders the base-ref second-terminal instruction verbatim, warning when the base is not `main` (R22) 3, 6; `/next` never runs it 7; blocked prints the findings and no merge command 6; regardless of plan 2, M |
| 389 | proposals with rationale and consequence where each lands 10; decisions vs acknowledgements 10; the verifier confirms in guided solo, provisional (full mode, R19) 10; asked once, at the `/next` point (R19) 7, 10; `confirmed_by:` 10 (P3's check kept) |
| 393 | `/next` on `main` in the remote-less instance derives idle (R4), both profiles 8, M |
| 306 (slice) | the fence 13 |
| 308 (slice) | glossary terms linked on first use 3, 14 |
| 310 (slice) | the prompt's profile and solo lines 10 |
| 311 (slice) | `pr_attestation` shared by the check and `next.sh` 4, 6 |
| 312 (slice) | the 403 message 14 |
| 334 (slice) | npm lockfile entries 4; Dependabot batching 12 |
| 382 (slice) | `MEMBER` role check 4; unlinked waiver explained 6 |
| 395 (slice) | README's enforcement paragraph 14 |

**Findings handed to P5 (H1–H23):**

| Finding | Owner |
|---|---|
| H1 | R1; the model step after this plan; Task 2 keeps the twin in step |
| H2 | R2; section "Amendment B" |
| H3 | R4; Task 8; the spec's P5 PLAN `amended:` entry |
| H4 | R12; Task 9 |
| H5 | R14 — ruled out; proposed for the P7 retrospective |
| H6 | R9; Task 4 |
| H7 | R11; Task 13 |
| H8 | R18; Task 11 |
| H9 | R16; Task 15 (threat-model residual); Deferred by design |
| H10 | Task 1 |
| H11 | R10; Task 4 |
| H12 | R17; Task 11 |
| H13 | R17; Task 11 |
| H14 | R15; Task 12 |
| H15 | R20; Task 6 |
| H16 | R13 |
| H17 | R19; Task 10 |
| H18 | R5, R6, R8; Tasks 2, 3, 6 (the factory's own history as fixtures) |
| H19 | Task 14 |
| H20 | Tasks 3 (glossary terms), 15 (overview, threat model) |
| H21 | section "Amendment B" (`art-branch-as-state`) |
| H22 | section "Amendment B" (`art-review-gate`, `art-release-readiness`, `art-threat-driven-security`) |
| H23 | Task 12 |

## Global Constraints

From the spec:
- **Performance.** `run-quality-gates.sh` on a fresh instance completes in under 3 minutes on ubuntu (python), excluding toolchain download. The template's gates take about 1:30 here and about 3:00 in CI; P5 adds about eight test files. Budget: P5's new and changed tests add at most 45 s of serial time here; each task times its test in Step 4 and stops if the whole gates run passes 2:30 here. Tests that need repositories build one seed per test and `git clone` it per case; the seeds copy only what the case reads (never `copy_template` per case).
- **Security.** No API key anywhere. No new download in CI. Workflows stay read-only; no job elevates. `next.sh` never runs `run-verifier.sh`, never runs `gh pr merge`, never writes.
- **Scalability.** A lane or phase is a table row, a constructor, a fact if needed, and fixtures (ADR-003's consequence).
- **Compliance.** Constitution changes only in the "Amendment B" section, on this branch (amendment PR B); nothing on the IMPLEMENT branch edits `constitution.md`, except the two corrections PR #47's verifier raised against amendment B's own text (findings 3 and 7: the admin-bypass convention in `art-branch-as-state`; the informational-low-is-not-a-placeholder clause in `art-threat-driven-security`), folded into the stacked IMPLEMENT PR, recorded in the spec's P5 IMPLEMENT `amended:` entry and signed off by the maintainer in #48's merge comment.
- **Assumptions.** Claude Code runs `.claude/commands/next.md` as the `/next` command; `gh pr list --json` offers `number, headRefName, baseRefName, state, author, mergedAt, mergeCommit, reviewDecision, isDraft, headRefOid, url, body` (gh 2.97.0).

Plan-level (P1a/P1b/P2/P3/P4, still in force):
- Python inside scripts is stdlib-only and always invoked as `python3`. `config.py` stays the one flat `key: value` reader; `frontmatter.py` the one frontmatter reader (`config.py` and `attestation.py` keep their own, materialised alone from the base ref); `blocks.py` the one security-block parser; `packinfo.py` the pack reader.
- bash 3.2 (macOS): no associative arrays, `mapfile`, `${v,,}`, possibly-empty arrays under `set -u`, or coreutils `timeout` (use `run_within`); `grep -E` with POSIX classes, never `\s`; `sed -i.bak` then remove the backup.
- **Instance** means `.specflow.yml` or a legacy `.stack` is present; otherwise the tree is the **template source**. Tests pass in both; a test that reads a fenced factory document (R11) skips that read when the file is absent.
- **Opt-in rule.** Anything that downloads, compiles Rust, runs `flutter` or node, or queries a network service inside a test runs only under `SPECFLOW_FIRST_RUN=1` (with `FIRST_RUN_CASES`) or an explicit switch, with its wall-clock stated. Default-gate tests use stub tools on `PATH` under `mktemp` and synthetic git repositories and touch no network; they never spawn the real `claude` or the real `gh`.
- Gates stay green on the template source after every task (from the gate venv), and plain `actionlint .github/workflows/*.yml` stays clean.
- `scripts/verify-doc.sh` must not flag any marker in plans or new files: no double braces anywhere (a GitHub expression is described in words) and no placeholder words.
- New or changed tests carry `# Covers: REQ-NNN`, source `tests/governance/lib/check.sh`, and keep every check **above** `finish` (the harness refuses a check after it). Checks assert behaviour through fixtures or synthetic repositories; grep alone only for text no code runs (command files, rule documents).
- Never pass captured multi-KB output as one argv (Linux caps an argument at 128 KiB): write it to a file and grep the file.
- `gh` output is parsed with `python3`, never `--jq`; every `gh` call runs as `GH_TOKEN="$(gh auth token --user kpingali123)"`.
- One commit per task (two where a step says so): check `git status`, stage the task's files, commit with the given message; every commit subject cites a `REQ-NNN`; every commit body ends with the `Co-Authored-By:` trailer given to the executing session. Never `git stash`.
- **Host hygiene.** Never `pip install` into the host interpreter or `npm install -g`; anything needed goes into a venv under `$TMPDIR`. The gates run as `PATH="$HOME/.venvs/factory-tools/bin:$PATH" bash scripts/run-quality-gates.sh` (the host conda's ruff 0.15.22 fails the lint range check).
- **Dafny, both versions.** Any commit that touches `verification/` verifies under 4.11.0 and 4.9.1.
- **The twin and the model stay in step.** `state.py`'s function names, `records.py`'s names and the fixture file names follow the model (Interfaces); a change to one is a change to all three in one commit.
- **Test-first on this branch.** Every IMPLEMENT commit that changes a file under `scripts/`, `stacks/`, `.claude/`, `.github/` or `src/` adds a non-blank, non-comment line to a `tests/governance/test_*.sh` in the same or an earlier commit (P3 R15); Task 16 runs `check-test-first.sh` over the branch.

Plan-level (new in P5):
- **One classifier.** `next.sh` reduces a PR's comments only through `attestation.pr_attestation` → `attestation.classify`; no second reading of markers or waivers exists anywhere (REQ-311). Pinned both ways: `test_attestation.sh` checks that `check()` goes through `pr_attestation`, and `test_next_prs.sh` checks that `pipeline.py` never contains `specflow-verifier` and never calls `parse_marker`, `_judge_comment` or `classify`, its only route to an attestation being `attestation.pr_attestation`.
- **Fail safe.** Whenever `next.sh` cannot establish an input (no remote, a `gh` failure, a PR head or base not present locally, an unreadable comment), it chooses the value that can never produce `Merge` or `CreatePr` (`pr_state_known` false, or attestation `none`) and says so under `--explain` (R21).
- **Instance-independent seeds.** The next tests' seed repository is built from `scripts/`, `schemas/`, `.claude/skills/verifier/`, `constitution.md` and `docs/GLOSSARY.md` (present in the template source and in every instance) plus a small synthetic document set checked in under `tests/governance/fixtures/next/seed/`, never from the python demo or `scripts/template-pack.yml`: instances run every `tests/governance/test_*.sh` (`run-quality-gates.sh:107-119`), and tauri, flutter and example-stripped instances have neither.
- **Strings stay out of the kernel.** `state.py` returns `Result` records only; every user-facing string comes from `pipeline.render_step`, `pipeline.confirmation_point` and the explain lines.
- **The proof is the template's.** `verification/factory_v3_2/` is fenced out of instances (R11); `test_state_model.sh` and the model checks in `test_state_kernel.sh` skip when the model is absent.

## Interfaces shared by the tasks

**Records** (`scripts/lib/specflow/records.py`, Task 2; frozen dataclasses and string-valued enums, stdlib only; the JSON spelling of every kind is the model's constructor name, and of lanes and phases the kebab value):

```
Path(Enum)        = lanes | regulated
Attestation(Enum) = none | approve | request_changes | waiver               # model: NoMarker | Approve | RequestChanges | Waiver
BranchKind(Enum)  = Main | Design | Build | BuildSec | Ship | Patch | PhaseSpec | PhaseArch | PhasePlan
                  | Impl | ImplSec | PhaseValidate | PhaseSecurity | PhaseRelease | Unknown
Branch(kind: BranchKind, slug: str = "", n: int = 0, id: str = "", version: str = "", plan: str = "", name: str = "")
PR(number: int, open: bool, merged: bool, closed: bool, human_approved: bool, attestation: Attestation, mine: bool)
RegShip(Enum)     = validate | security | release
Facts(has_brainstorm, has_spec, spec_has_tagged_reqs, arch_complete, has_plan: bool, build_sections: frozenset[int],
      analyze_ok, has_source_diff, gates_pass, has_security_docs, has_release_docs, signing_key_present,
      pr_state_known: bool, unbuilt: tuple[tuple[str, int], ...], untagged_ship: str | None,
      next_version: str | None, ship_phases_merged: frozenset[RegShip])
Lane(Enum)        = none | design | build | ship | spec | arch | plan | impl | validate | security | release
Phase(Enum)       = brainstorm | specify | architecture | plan | analyze | implement | gates | security | release
                  | open-pr | unknown-build | awaiting-verifier | awaiting-human-review | awaiting-merge | blocked
                  | merged | closed | tag | next-build | ready-to-ship | idle | unknown-branch
ProposalKind(Enum)= ProposeDesign | ProposeBuild | ProposeShip | ProposeSpec | ProposeImpl | ProposeValidate
                  | ProposeSecurity | ProposeRelease
Proposal(kind: ProposalKind, slug: str = "", n: int = 0, version: str = "")
TargetKind(Enum)  = Section | SecFix | PatchTier | PlanTarget
ImplTarget(kind: TargetKind, n: int = 0, id: str = "", plan: str = "", name: str = "")
Why(Enum)         = PrStateUnknown | BranchUnknown | BuildUnknown | PrClosed
StepKind(Enum)    = RunBrainstorm | RunSpecify | RunArchitecture | RunPlan | RunAnalyze | RunImplement | RunGates
                  | RunSecurityReview | RunRelease | CreatePr | RunVerifier | RequestReview | Merge | Checkout
                  | CheckoutMain | NewBranch | AddressFindings | TagRelease | ExplainUnknown
Step(kind: StepKind, pr: int = 0, proposal: Proposal | None = None, target: ImplTarget | None = None,
     version: str = "", why: Why | None = None)
Result(lane: Lane, phase: Phase, step: Step, open_lanes: tuple[int, ...])     # open_lanes sorted ascending
```

JSON helpers (pure): `branch_from_json`/`branch_to_json` (`{"kind": "Build", "slug": "habit-tracker", "n": 1}`; unused fields omitted), `pr_from_json`, `facts_from_json` (every missing key defaults to false, empty or `null`), `step_to_json`/`step_from_json` (`{"kind": "NewBranch", "proposal": {"kind": "ProposeBuild", "slug": "a", "n": 2}}`, `{"kind": "RunImplement", "target": {"kind": "Section", "n": 1}}`, `{"kind": "ExplainUnknown", "why": "PrStateUnknown"}`, `{"kind": "Merge", "pr": 12}`, `{"kind": "TagRelease", "version": "0.2.0"}`), `result_to_json` (`{"lane", "phase", "step", "open_lanes"}`). The P3 records keep their names; the module docstring stops calling state records "what a running instance persists" (nothing persists).

**The kernel** (`scripts/lib/specflow/state.py`, Task 2; imports only `records` and the stdlib's `dataclasses`, `enum`, `typing`, `__future__`; no I/O). `derive(branch, branch_pr, open_lane_prs, facts, path, solo) -> Result`, raising `ValueError` only when `pre(...)` is false. One function per model function, named as the model's in snake_case: `pre`, `numbers_of`, `own_numbers`, `min_of`, `lane_of`, `lane_list`, `first_missing_after_last_present`, `lane_phase`, `phase_step`, `impl_target_of`, `pr_substate`, `main_result`, `regulated_ship_proposal`, `phase_order`, `set_fact`, `lanes_proposal`, `regulated_proposal`, `derive`. `pre` (R5): every PR well-formed (exactly one of open/merged/closed; number ≥ 1); every open lane PR open, numbers distinct; `Main` ⇒ `branch_pr is None`; `pr_state_known` false ⇒ `branch_pr is None` and no open lane PRs; `Build` has `n ≥ 1`, and every `build_sections` and `unbuilt` number is ≥ 1; `unbuilt` sorted ascending by `(slug, n)` (the model takes its head); `spec_has_tagged_reqs` ⇒ `has_spec`; `untagged_ship` and `next_version`, when set, non-empty. `derive`, in order (ADR-003's precedence with R5 and R6):
1. `Unknown` → `(none, unknown-branch, ExplainUnknown(BranchUnknown))`.
2. `Main` → `main_result`: own open lane PRs (`mine`) → `(none, awaiting-merge, Checkout(min_of(own_numbers(open_lane_prs))))` — the lowest-numbered open lane PR of the current user, never another user's (`MainChecksOutLowestOwn`); else `untagged_ship` → `(ship | release by path, tag, TagRelease(version))`; else `unbuilt` → `(none, next-build, NewBranch(ProposeBuild(slug, n) | ProposeImpl(slug, n)))` for `unbuilt[0]`; else `next_version` → `(none, ready-to-ship, NewBranch(ProposeShip(version) | regulated_ship_proposal(ship_phases_merged)))`; else `(none, idle, NewBranch(ProposeDesign | ProposeSpec))`.
3. `branch_pr` open → `pr_substate`: `request_changes` → `blocked`, `AddressFindings(pr)`; `none` → `awaiting-verifier`, `RunVerifier(pr)`; `approve`/`waiver` → `awaiting-merge`, `Merge(pr)` when `solo` or `human_approved`, else `awaiting-human-review`, `RequestReview(pr)`.
4. `branch_pr` merged → `(lane, merged, CheckoutMain)`; closed → `(lane, closed, ExplainUnknown(PrClosed))`.
5. `Build(slug, n)` with `n ∉ build_sections` → `(build, unknown-build, ExplainUnknown(BuildUnknown))`.
6. `lane_phase`: on `Design`, `spec_has_tagged_reqs and not arch_complete` → `architecture`; else `first_missing_after_last_present(lane_list(branch, facts))` — the entry after the last present one, or `open-pr` when none follows. `lane_list`: Design `[(brainstorm, has_brainstorm), (specify, has_spec)] + ([(architecture, arch_complete)] if spec_has_tagged_reqs) + [(plan, has_plan), (analyze, analyze_ok)]`; PhaseSpec `[(brainstorm, …), (specify, …)]`; PhaseArch `[(architecture, arch_complete)]`; PhasePlan `[(plan, …), (analyze, …)]`; Build, BuildSec, Patch, Impl, ImplSec `[(implement, has_source_diff)]`; PhaseValidate `[(gates, gates_pass)]`; Ship `[(security, has_security_docs), (release, has_release_docs)]`; PhaseSecurity `[(security, …)]`; PhaseRelease `[(release, …)]`.
7. The phase's step (`phase_step`): brainstorm → `RunBrainstorm`, specify → `RunSpecify`, architecture → `RunArchitecture`, plan → `RunPlan`, analyze → `RunAnalyze`, implement → `RunImplement(impl_target_of(branch))` (`Section(n)`, `SecFix(id)` for BuildSec and ImplSec, `PatchTier`, `PlanTarget(plan, name)`), gates → `RunGates`, security → `RunSecurityReview`, release → `RunRelease`; open-pr → `CreatePr` when `pr_state_known`, else `ExplainUnknown(PrStateUnknown)`.
`lane_of`: Design → design; Build, BuildSec, Patch → build; Ship → ship; PhaseSpec → spec; PhaseArch → arch; PhasePlan → plan; Impl, ImplSec → impl; PhaseValidate → validate; PhaseSecurity → security; PhaseRelease → release; Main, Unknown → none. `phase_order`: brainstorm 0, specify 1, architecture 2, plan 3, analyze 4, implement 5, gates 6, security 7, release 8, open-pr 9, every other phase 10. `set_fact(facts, phase)` sets the fact that phase stands for (brainstorm → `has_brainstorm`, specify → `has_spec`, architecture → `arch_complete`, plan → `has_plan`, analyze → `analyze_ok`, implement → `has_source_diff`, gates → `gates_pass`, security → `has_security_docs`, release → `has_release_docs`). `lanes_proposal(p)`: ProposeDesign, ProposeBuild, ProposeShip; `regulated_proposal(p)`: ProposeSpec, ProposeImpl, ProposeValidate, ProposeSecurity, ProposeRelease.

**The Dafny model** (`verification/factory_v3_2/state.dfy`; written by the step right after this plan, on this branch, R1). Header, first lines:

```
// verification/factory_v3_2/state.dfy — ADR-003's pipeline-state derivation as a pure, total function.
// Proves: REQ-341
// Twin: scripts/lib/specflow/state.py (derive); fixtures: tests/governance/fixtures/state/.
```

followed by a prose restatement of ADR-003's precedence 1–5, both state tables, R5 and R6, and the modelling choices (strings are opaque slugs, ids and versions; `open_lanes` is a `set<nat>` in the model and a sorted tuple in the twin; `unbuilt` is taken at its head, the wrapper sorts it). Shape (names are binding — `test_state_model.sh`, the twin and Task 2's test grep them):
- `module PipelineState`, with `datatype Option<T> = None | Some(value: T)`, `datatype Path = Lanes | Regulated`, `datatype Attestation = NoMarker | Approve | RequestChanges | Waiver`, `datatype Branch = Main | Design(slug: string) | Build(slug: string, n: nat) | BuildSec(id: string) | Ship(version: string) | Patch(slug: string) | PhaseSpec(slug: string) | PhaseArch(slug: string) | PhasePlan(slug: string) | Impl(plan: string, name: string) | ImplSec(id: string) | PhaseValidate | PhaseSecurity | PhaseRelease | Unknown`, `datatype PR = PR(number: nat, open: bool, merged: bool, closed: bool, humanApproved: bool, attestation: Attestation, mine: bool)`, `datatype RegShip = RValidate | RSecurity | RRelease`, `datatype Unbuilt = Unbuilt(slug: string, n: nat)`, `datatype Facts = Facts(hasBrainstorm: bool, hasSpec: bool, specHasTaggedReqs: bool, archComplete: bool, hasPlan: bool, buildSections: set<nat>, analyzeOk: bool, hasSourceDiff: bool, gatesPass: bool, hasSecurityDocs: bool, hasReleaseDocs: bool, signingKeyPresent: bool, prStateKnown: bool, unbuilt: seq<Unbuilt>, untaggedShip: Option<string>, nextVersion: Option<string>, shipPhasesMerged: set<RegShip>)`, `datatype Lane = NoLane | DesignLane | BuildLane | ShipLane | SpecLane | ArchLane | PlanLane | ImplLane | ValidateLane | SecurityLane | ReleaseLane`, `datatype Phase = Brainstorm | Specify | Architecture | PlanPhase | Analyze | Implement | Gates | Security | Release | OpenPr | UnknownBuild | AwaitingVerifier | AwaitingHumanReview | AwaitingMerge | Blocked | Merged | Closed | Tag | NextBuild | ReadyToShip | Idle | UnknownBranch`, `datatype Proposal = ProposeDesign | ProposeBuild(slug: string, n: nat) | ProposeShip(version: string) | ProposeSpec | ProposeImpl(slug: string, n: nat) | ProposeValidate | ProposeSecurity | ProposeRelease`, `datatype ImplTarget = Section(n: nat) | SecFix(id: string) | PatchTier | PlanTarget(plan: string, name: string)`, `datatype Why = PrStateUnknown | BranchUnknown | BuildUnknown | PrClosed`, `datatype Step = RunBrainstorm | RunSpecify | RunArchitecture | RunPlan | RunAnalyze | RunImplement(target: ImplTarget) | RunGates | RunSecurityReview | RunRelease | CreatePr | RunVerifier(pr: nat) | RequestReview(pr: nat) | Merge(pr: nat) | Checkout(pr: nat) | CheckoutMain | NewBranch(p: Proposal) | AddressFindings(pr: nat) | TagRelease(version: string) | ExplainUnknown(why: Why)`, `datatype Result = Result(lane: Lane, phase: Phase, step: Step, openLanes: set<nat>)`.
- Functions and predicates (twin names in snake_case): `WellFormedPr`, `IsLaneBranch` (not Main, not Unknown), `Pre`, `NumbersOf`, `OwnNumbers` (the numbers of the current user's PRs, in order), `MinOf`, `LaneOf`, `LaneList`, `FirstMissingAfterLastPresent`, `LanePhase`, `PhaseStep`, `ImplTargetOf`, `PrSubstate`, `MainResult`, `RegulatedShipProposal`, `Derive`, `PhaseOrder` (the order the Progress theorem needs), `ArtifactPhase` (the nine artifact phases), `SetFact`, `LanesProposal`, `RegulatedProposal`.
- The five theorems (ADR-003's proof obligations), each requiring `Pre`:
  - `MergeOnlyWhenApproved` — `Derive(…).step.Merge?` implies `branchPr.Some?`, `branchPr.value.open`, attestation `Approve` or `Waiver`, `step.pr == branchPr.value.number`, `solo || branchPr.value.humanApproved`, and `IsLaneBranch(branch)` (REQ-385, `art-review-gate`).
  - `NoBlindCreatePr` — `!facts.prStateKnown` implies `Derive(…).step != CreatePr`.
  - `PathClosure` — a `NewBranch(p)` step has `LanesProposal(p)` under `Lanes` and `RegulatedProposal(p)` under `Regulated`.
  - `PrPrecedence` — for a lane branch whose `branchPr` is open, the phase is one of the four PR substates, `Blocked` iff `RequestChanges`, `AwaitingVerifier` iff `NoMarker`, and the lane is `LaneOf(branch)`.
  - `Progress` — for a lane branch with no PR (and, for `Build`, `n ∈ buildSections`) whose derived phase `p` is an `ArtifactPhase`, `Pre` still holds of `SetFact(facts, p)`, `PhaseOrder` of the phase `q` derived from `SetFact(facts, p)` is strictly greater than `PhaseOrder(p)`, and `q` stays in the lane's order: `q.lane == LaneOf(branch) && (ArtifactPhase(q.phase) || q.phase == OpenPr)` (ADR-003: "in the lane's order"; `PhaseOrder` maps every non-lane phase to 10, so without this conjunct a jump out of the lane would count as progress).
- Further lemmas: `UnknownBranchNeverMerges` (an `Unknown` branch derives exactly `Result(NoLane, UnknownBranch, ExplainUnknown(BranchUnknown), NumbersOf(openLanePrs))`, dfe-7), `UnknownPrStateNeverAwaitsVerifier` (`!prStateKnown` ⇒ the phase is none of AwaitingVerifier, AwaitingHumanReview, AwaitingMerge, Blocked, Merged, Closed), `RemoteLessMainIsIdle` (REQ-393, R4: `Main`, no PRs, `!prStateKnown`, empty `unbuilt`, no `untaggedShip` or `nextVersion` ⇒ `Result(NoLane, Idle, NewBranch(ProposeDesign or ProposeSpec by path), {})`), `OtherUsersPrsNeverBlock` (on `Main`, when no open lane PR is `mine`, the phase is not `AwaitingMerge` and the step is not `Checkout`), `MainChecksOutLowestOwn` (on `Main`, a `Checkout(n)` step names some open lane PR with `mine`, and `n` is at most every own PR's number: ADR-003 precedence 3's "lowest-numbered open lane PR of the current user", dfe-10 — mixed own and foreign PRs included), with its helpers `OwnNumbersSpec` (`x in OwnNumbers(prs) <==>` some `prs[i].mine` has number `x`) and `MinOfSpec` (`MinOf(xs) in xs` and `≤` every element); the fixture helpers `ScanBackAllMissing` and `ScanBackAfterPresent`. Totality and determinism follow from the datatypes and are stated in the header, not laboured.
- Fixture lemmas `Fixture01`, `Fixture02`, `Fixture04`, `Fixture09`, `Fixture20`, `Fixture22`, `Fixture24`, `Fixture30`, `Fixture41`, `Fixture42`, `Fixture62`: each `Derive(<fixture NN's inputs>) == <its expected Result>`, so those Python fixtures are expectations the model itself has proved, and every theorem's hypothesis has a witness the model proves — `Fixture01` → `Fixture02` is a `Progress` pair (`Fixture02` also states that its facts are `SetFact(<Fixture01's facts>, Brainstorm)`), 22 `MergeOnlyWhenApproved`, 09 `NoBlindCreatePr`, 30 and 41 `PathClosure` on lanes and 42 on regulated (REQ-393), 20 `PrPrecedence`, 62 `UnknownBranchNeverMerges`.
- Layout the test relies on: each `datatype` declaration is followed by a blank line or another declaration, and each lemma's body opens with `{` on a line of its own. It verifies with `dafny verify` under 4.11.0 and 4.9.1 with no `{:axiom}`, no `assume`, no `{:verify false}` and no `requires false` (after the fresh-eyes revision: 62 verified, 0 errors, under both). Mutation checks before committing, each on a scratch copy, never committed: `MergeOnlyWhenApproved` fails to verify when `PrSubstate` emits `Merge` without the `solo || humanApproved` conjunct (m1); `NoBlindCreatePr` fails when the open-pr step ignores `prStateKnown` (m2); `Progress` fails when `Derive` sends `design/<slug>` with `analyzeOk && gatesPass` to `(DesignLane, UnknownBuild, ExplainUnknown(BuildUnknown))` and the proof body's intermediate `assert` is deleted (the lane conjunct, not an incidental proof step, is the guard); `MainChecksOutLowestOwn` fails when `MainResult` emits `Checkout(MinOf(own) + 1)` (m8).

**`tests/governance/test_state_model.sh`** (written with the model, R1, and committed with the revised model after the fresh-eyes review; full code):

```bash
#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R1, R5, R6): the Dafny model of derive() — verification/factory_v3_2/state.dfy — carries its
# Proves header, every Branch constructor ADR-003 lists, the PR, Facts, Step and Result records, the phase order the
# Progress theorem needs, and the five theorems by name, with nothing assumed. Progress keeps the derived phase in the
# branch's lane (ADR-003: "in the lane's order"), and main's Checkout names the lowest open lane PR of the current user
# (dfe-10). REQ-385: MergeOnlyWhenApproved carries the human-approval conjunct. REQ-340: one Branch datatype holds both
# paths' constructors, and PathClosure ties proposals to the configured path. Gates section 2 verifies the file; this
# test pins its shape.
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
DFY="$ROOT/verification/factory_v3_2/state.dfy"
[[ -f "$DFY" ]] || { echo "SKIP: the factory's state model ships only in the template source (P5 R11 fences it out of instances)"; exit 0; }
block() {  # the datatype's declaration, up to a blank line or the next declaration
  awk -v n="$1" 'f && (/^[[:space:]]*$/ || /^[[:space:]]*(datatype|function|predicate|lemma) /) {exit}
                 $0 ~ ("^[[:space:]]*datatype " n "[ <=]") {f=1} f' "$DFY" | tr '\n' ' '
}
head_of() {  # a lemma's signature and contract, up to the line that opens its body
  awk -v n="$1" '$0 ~ ("lemma " n "[(<]") {f=1} f && /^[[:space:]]*\{/ {exit} f' "$DFY" | tr '\n' ' '
}
ck "the Proves header is in the first five lines" bash -c 'head -5 "$1" | grep -qx "// Proves: REQ-341"' _ "$DFY"
ck "module PipelineState" grep -qE '^module PipelineState' "$DFY"
for d in Option Path Attestation Branch PR RegShip Unbuilt Facts Lane Phase Proposal ImplTarget Why Step Result; do
  ck "datatype $d" grep -qE "^[[:space:]]*datatype $d( |<)" "$DFY"
done
br=$(block Branch)
for c in Main Design Build BuildSec Ship Patch PhaseSpec PhaseArch PhasePlan Impl ImplSec PhaseValidate PhaseSecurity PhaseRelease Unknown; do
  ck "Branch has $c (ADR-003)" grep -qE "(=|\|)[[:space:]]*$c([[:space:]]|[(]|$)" <<<"$br"
done
st=$(block Step)
for c in RunBrainstorm RunSpecify RunArchitecture RunPlan RunAnalyze RunImplement RunGates RunSecurityReview RunRelease \
         CreatePr RunVerifier RequestReview Merge Checkout CheckoutMain NewBranch AddressFindings TagRelease ExplainUnknown; do
  ck "Step has $c" grep -qE "(=|\|)[[:space:]]*$c([[:space:]]|[(]|$)" <<<"$st"
done
fa=$(block Facts)
for f in hasBrainstorm hasSpec specHasTaggedReqs archComplete hasPlan buildSections analyzeOk hasSourceDiff gatesPass \
         hasSecurityDocs hasReleaseDocs signingKeyPresent prStateKnown unbuilt untaggedShip nextVersion shipPhasesMerged; do
  ck "Facts has $f" grep -qE "$f:" <<<"$fa"
done
pr=$(block PR)
for f in number open merged closed humanApproved attestation mine; do ck "PR has $f" grep -qE "$f:" <<<"$pr"; done
for fn in WellFormedPr IsLaneBranch Pre NumbersOf OwnNumbers MinOf LaneOf LaneList FirstMissingAfterLastPresent LanePhase \
          PhaseStep ImplTargetOf PrSubstate MainResult RegulatedShipProposal Derive PhaseOrder ArtifactPhase SetFact \
          LanesProposal RegulatedProposal; do
  ck "the model defines $fn" grep -qE "(function|predicate) $fn[(<]" "$DFY"
done
for l in MergeOnlyWhenApproved NoBlindCreatePr PathClosure PrPrecedence Progress UnknownBranchNeverMerges \
         UnknownPrStateNeverAwaitsVerifier RemoteLessMainIsIdle OtherUsersPrsNeverBlock OwnNumbersSpec MinOfSpec \
         MainChecksOutLowestOwn; do
  ck "the model proves $l" grep -qE "lemma $l[(<]" "$DFY"
done
mo=$(head_of MergeOnlyWhenApproved)
ck "MergeOnlyWhenApproved's conclusion carries the human-approval conjunct (solo || humanApproved)" \
  bash -c 'grep -qF "humanApproved" <<<"$1" && grep -qF "solo" <<<"$1" && grep -qF "Waiver" <<<"$1"' _ "$mo"
pc=$(head_of PathClosure)
ck "PathClosure speaks of both paths" bash -c 'grep -qF "Lanes" <<<"$1" && grep -qF "Regulated" <<<"$1"' _ "$pc"
pg=$(head_of Progress)
ck "Progress keeps the new phase in the branch's lane, an artifact phase or OpenPr (ADR-003: 'in the lane's order')" \
  bash -c 'grep -qF "LaneOf(branch)" <<<"$1" && grep -qF "ArtifactPhase(q.phase) || q.phase == OpenPr" <<<"$1"' _ "$pg"
mc=$(head_of MainChecksOutLowestOwn)
ck "MainChecksOutLowestOwn: main's Checkout names an open lane PR of the current user, the lowest such (dfe-10)" \
  bash -c 'grep -qF "Checkout?" <<<"$1" && grep -qF ".mine" <<<"$1" && grep -qF "<=" <<<"$1"' _ "$mc"
ck "at least ten FixtureNN lemmas" [ "$(grep -cE 'lemma Fixture[0-9]+' "$DFY")" -ge 10 ]
f2=$(head_of Fixture02)
ck "a Progress witness: Fixture02's facts are SetFact of Fixture01's, and its phase follows" \
  bash -c 'grep -qF "SetFact(" <<<"$1" && grep -qF "Brainstorm" <<<"$1" && grep -qF "Specify" <<<"$1"' _ "$f2"
ck "a regulated PathClosure witness: Fixture42 is the regulated remote-less idle (REQ-393)" \
  bash -c 'grep -qF "Regulated" <<<"$1" && grep -qF "ProposeSpec" <<<"$1"' _ "$(head_of Fixture42)"
ck "the model assumes nothing (no {:axiom}, no assume statement, no {:verify false})" \
  no grep -qE '\{:axiom\}|\{:verify false\}|^[[:space:]]*assume[[:space:]]' "$DFY"
finish test_state_model
```

**Kernel fixtures** (`tests/governance/fixtures/state/NN-<name>.json`, Task 2): `{"about": "…", "lemma": "FixtureNN" (optional), "branch": <Branch JSON>, "branch_name": "<the string it parses from>" (optional), "branch_pr": <PR JSON> | null, "open_lane_prs": [<PR JSON>], "facts": {…}, "path": "lanes" | "regulated", "solo": bool, "expect": <Result JSON> | {"error": "ValueError"}}`. Names (76; one per rule, per theorem and per row of both state tables, overview `:46`; each `about` names its row, rule or theorem): `01-design-nothing-brainstorm`, `02-design-brainstorm-specify` (01 → 02 is the Progress pair), `03-design-spec-without-brainstorm-plan`, `04-design-tagged-arch-incomplete-architecture` (plan present too), `05-design-untagged-skips-architecture`, `06-design-tagged-arch-complete-plan`, `07-design-analyze`, `08-design-create-pr`, `09-design-no-pr-state-explain`, `10-build-unknown-build`, `11-build-implement`, `12-build-create-pr`, `13-build-sec-implement`, `14-build-sec-create-pr`, `15-patch-implement`, `16-patch-create-pr`, `17-ship-security`, `18-ship-release`, `19-ship-create-pr`, `20-pr-open-none-awaiting-verifier`, `21-pr-open-request-changes-blocked`, `22-pr-approve-solo-merge`, `23-pr-waiver-solo-merge`, `24-pr-approve-team-no-human-awaiting-review`, `25-pr-approve-team-human-merge`, `26-pr-waiver-team-no-human-awaiting-review`, `27-pr-merged-checkout-main`, `28-pr-closed-explain`, `29-main-own-open-prs-checkout-lowest` (own #15 and #12, another user's #9: `Checkout(12)`, `open_lanes` [9, 12, 15]), `30-main-others-prs-never-block` (idle), `31-main-untagged-ship-tag-lanes`, `32-main-untagged-ship-tag-regulated`, `33-main-next-build-lowest-lanes`, `34-main-next-build-regulated-impl`, `35-main-ready-to-ship-lanes`, `36-main-ready-to-ship-regulated-validate`, `37-main-ready-to-ship-regulated-security`, `38-main-ready-to-ship-regulated-release`, `39-main-idle-lanes`, `40-main-idle-regulated`, `41-main-remote-less-idle-lanes` (REQ-393), `42-main-remote-less-idle-regulated` (REQ-393), `43-phase-spec-brainstorm`, `44-phase-spec-specify`, `45-phase-spec-create-pr`, `46-phase-arch-architecture`, `47-phase-arch-create-pr`, `48-phase-plan-plan`, `49-phase-plan-analyze`, `50-phase-plan-create-pr`, `51-impl-implement`, `52-impl-sec-implement`, `53-impl-sec-create-pr`, `54-phase-validate-gates`, `55-phase-validate-create-pr`, `56-phase-validate-reused-name-gates` (R21(a): the wrapper dropped the previous cycle's merged PR, so `branch_pr` is `null` and the branch derives `validate gates`, never `merged`; its `about` says so), `57-phase-security-security`, `58-phase-security-create-pr`, `59-phase-release-release`, `60-phase-release-create-pr`, `61-unknown-branch`, `62-unknown-branch-approved-pr-never-merges`, `63-build-open-pr-precedes-unknown-build`, `64-factory-phase-plan-p5-awaiting-verifier` (`branch_name` `phase/plan-factory-v3-2-p5`), `65-factory-impl-plan-5-orchestrator-create-pr`, `66-factory-patch-first-run-argmax-merged`, `67-factory-impl-plan-1a-first-run-implement` (`Impl("1a", "first-run")`), `68-factory-legacy-phase-spec-unknown` (`branch_name` `phase/spec`), `69-pre-main-with-branch-pr`, `70-pre-pr-open-and-merged`, `71-pre-no-pr-state-with-open-lanes`, `72-pre-tagged-without-spec`, `73-pre-open-lane-pr-not-open`, `74-pre-unbuilt-unsorted`, `75-pre-duplicate-open-lane-numbers`, `76-pre-build-zero`. Fixtures 01, 02, 04, 09, 20, 22, 24, 30, 41, 42 and 62 carry exactly the inputs of the model's `FixtureNN` lemma of the same number and name it in `lemma`; the fresh-eyes revision added 44, 50, 53, 56, 58 and 60 and renumbered the rest (the model's `Fixture56` became `Fixture62`).

**The wrapper** (`scripts/lib/specflow/pipeline.py`, Tasks 3, 5, 6; stdlib; imports `records`, `state`, `config`, `frontmatter`, `packinfo`, `attestation`):
- `parse_branch(name: str) -> Branch` — total, never raises: `main` → Main; `design/<slug>`, `patch/<slug>` → Design, Patch; `build/sec-<id>` → BuildSec (checked first); `build/<slug>-<N>` split on the last `-`, `N` matching `[1-9][0-9]*` → Build; `ship/<version>` with `disposition_gate.VERSION_RE`'s grammar → Ship; `phase/spec-<slug>`, `phase/arch-<slug>`, `phase/plan-<slug>` → PhaseSpec, PhaseArch, PhasePlan; `phase/validate`, `phase/security`, `phase/release` exactly → PhaseValidate, PhaseSecurity, PhaseRelease; `impl/sec-<id>` → ImplSec (first); `impl/plan-<plan>-<name>` with `plan` matching `[0-9]+[a-z]?` → Impl; a slug, id or name matches `[A-Za-z0-9][A-Za-z0-9._-]*`; anything else (a legacy `phase/spec`, `phase/retro-…`, `impl/fix-…`, `chore/…`, `dependabot/…`, detached `HEAD`, an empty slug, `build/x-0`) → Unknown. The pattern for VERSION_RE is copied, not imported (`pipeline.py` must not depend on the gate module).
- `RenderCtx(repo: str, branch: str, base: str, slug: str, version: str, plan_path: str, spec_slug: str, n: int = 0, stacked: tuple[int, ...] = ())` (`repo` is `git rev-parse --show-toplevel` — on macOS `mktemp` paths under `/var` resolve to `/private/var`, so neither `$PWD` nor a caller's path is used; `n` is a build branch's section number; `stacked` the numbers of open PRs whose base is this branch, R22); `render_step(step: Step, ctx: RenderCtx) -> str` — one line, exactly (repo paths through `shlex.quote`):
  - `RunVerifier(pr)`: `In a second terminal, not inside Claude — open a new terminal window (Terminal.app or your shell) and run: cd <repo> && git show origin/<base>:scripts/run-verifier.sh | bash -s -- <pr>; when it prints "Findings posted to PR #<pr>", return here and run /next.` (REQ-385 as amended; the base-ref form of REQ-313; R22(b)). When `base` is not `main`, the same line continues: ` Warning: origin/<base> is not main — the script comes from a branch no review has approved yet (a PR author chooses a stacked PR's base); read it first with git show origin/<base>:scripts/run-verifier.sh`.
  - `Merge(pr)`: `gh pr merge <pr> --squash` (REQ-340: squash merges are permitted); `--match-head-commit <head>` binds either form to the judged head; when `stacked` is non-empty, `gh pr merge <pr> --merge --match-head-commit <head> && gh pr edit <m> --base <this PR's base>` (R22: the merge first, then one `gh pr edit` per stacked PR, shell commands only; the explanation is a `notes` line). `AddressFindings(pr)`: `address the findings on PR #<pr> (listed above), push, then run /next — there is no merge until an APPROVE marker for the new head exists`. `RequestReview(pr)`: `ask a teammate who is not the author to approve PR #<pr> (gh pr view <pr> --web)`. `Checkout(pr)`: `gh pr checkout <pr>`. `CheckoutMain`: `git checkout main && git pull --ff-only`. `CreatePr`: `git push -u origin <branch> && gh pr create --base <base> --fill`.
  - `NewBranch(ProposeDesign)`: `git checkout -b design/<slug> (choose a short name for the idea), then run /superpowers:brainstorming`; `ProposeSpec`: the same with `phase/spec-<slug>`; `ProposeBuild(s, n)`: `git checkout -b build/<s>-<n>`; `ProposeImpl(s, n)`: `git checkout -b impl/plan-<n>-<s>`; `ProposeShip(v)`: `git checkout -b ship/<v>`; `ProposeValidate`, `ProposeSecurity`, `ProposeRelease`: `git checkout -b phase/validate` (…`security`, …`release`). The literal `<slug>` in the design and spec proposals is the one placeholder a user fills.
  - `RunBrainstorm`: `run /superpowers:brainstorming and save the notes as docs/specs/<today>-<slug>-brainstorm.md`; `RunSpecify`: `/specify <slug>`; `RunArchitecture`: `/architecture <spec_slug>`; `RunPlan`: `/specflow-plan <slug>`; `RunAnalyze`: `/analyze <slug>`; `RunImplement(Section(n))`: `/superpowers:subagent-driven-development for "## Build <n>" of <plan_path> (test first, art-test-first)`; `SecFix(id)`: the same for the fix of `<id>` (the back-edge, `art-threat-driven-security`), `PatchTier`: the spec delta and its implementation, test first, in this one PR; `PlanTarget`: the plan's tasks; `RunGates`: `bash scripts/next.sh --gates`; `RunSecurityReview`: `/security-review <version>`; `RunRelease`: `/release <version>`; `TagRelease(v)`: `tag v<v> on the ship PR's merge commit — follow "After the PR merges" in .claude/commands/release.md (signed; annotated only with the fallback recorded)`.
  - `ExplainUnknown(PrStateUnknown)`: `cannot see PRs: check gh auth status and the remote (git remote -v), then run /next`; `(BranchUnknown)`: `this branch is not a pipeline branch (.claude/rules/review-gate.md lists both paths' names): check out main, or a branch /next knows`, or, for a `phase/retro-` branch, `a retrospective branch: run /retrospective, then open its PR (art-retrospective-cadence)`; `(BuildUnknown)`: `the plan has no "## Build <n>": add it through a design PR, or check out an existing build`; `(PrClosed)`: `the PR was closed without merging: reopen it or delete the branch`.
- `confirmation_point(result, facts, profile) -> str | None` — `None` in the engineer profile; in the guided profile, keyed on the Result's lane and phase, never on its step (so `design-pr`, `build-pr` and `ship-pr` apply at phase `open-pr` whether the step is `CreatePr` or `ExplainUnknown(PrStateUnknown)` — the summary is shown before the user pushes, remote or not): `brainstorm-end` (phase specify: confirm the product scope before `/specify`), `design-pr` (design lane, or `phase/spec-`, `phase/arch-`, `phase/plan-`, at open-pr: the spec summary and the REQ-389 acknowledgements), `build-pr` (build, impl or validate lane at open-pr: what was built, in user terms), `ship-pr` (ship, security or release lane at open-pr: the security dispositions and release notes; go/no-go is a decision), `awaiting-verifier` (print the command, never run it), `merge` (any `Merge` step), `unsigned-tag` (`TagRelease` with `signing_key_present` false). Printed as `confirm: <id> — <what to show or ask>`.
- `GLOSSARY_TERMS` — `(term, anchor)` for the terms `/next` prints: Lane, Design lane, Build lane, Ship lane, Patch tier, Back-edge, Waiver, Attestation marker, /next, Derive, Facts, Confirmation point, Awaiting verifier; `terms_for(result) -> list[(term, anchor)]`, each term once per output (REQ-308: linked on first use), printed as `terms: <term> (docs/GLOSSARY.md#<anchor>), …`.
- CLI: `python3 pipeline.py derive [--root DIR] [--explain] [--json] [--gates] [--profile guided|engineer] [--path lanes|regulated] [--base REF]` and `python3 pipeline.py parse-branch NAME` (prints Branch JSON). `scripts/next.sh` is `exec python3 "<its dir>/lib/specflow/pipeline.py" derive "$@"` (the `check-security-disposition.sh` shape).

**`next.sh` output** (text; exit 0 for any derived state, 2 for a usage, configuration or git error, or a precondition `ValueError`, printed as `ERROR next: …`):

```
state: <lane> <phase>
next: <render_step>
confirm: <id> — <text>                    (guided profile only, when a point applies)
open lanes: #<n> (yours, <head>), #<m> (<author>, <head> — not yours: checking it out runs its code on your machine; let CI run the gates first, dfe-10)
findings:                                 (blocked only: the REQUEST_CHANGES comment's URL, then its findings)
terms: <term> (docs/GLOSSARY.md#<anchor>), …
note: <text>                              (template source, PR state unknown, --path override)
why: <text>                               (--explain only: each fact, where it came from, what was assumed)
```

`--json`: `{"state": {"lane", "phase"}, "step": <Step JSON>, "next_step": "<render_step>", "open_lanes": [<n>…], "open_lane_prs": [{"number", "author", "head", "mine"}], "confirm": "<id>" | null, "pr_state_known": bool, "path": "lanes" | "regulated", "profile": "guided" | "engineer", "facts": {<each fact or null when the lane does not read it>}, "findings": "<text>" | null, "explain": ["…"], "notes": ["…"]}`.

**PR state** (Task 6): with an `origin` remote and a working `gh`: `gh repo view --json nameWithOwner`; `gh api user` (the current login); `gh pr list --state all --limit 1000 --json number,headRefName,baseRefName,state,author,mergedAt,mergeCommit,reviewDecision,isDraft,headRefOid,url,body`. `branch_pr` is the highest-numbered PR whose `headRefName` equals the branch and that is open, or merged or closed with `headRefOid` equal to the local `HEAD` (R21(a): a fixed name reused by a later cycle; never on `main`, R5); a merged or closed PR dropped by that rule gets a `why:` line. Open lane PRs: open PRs whose head parses to neither Main nor Unknown. `human_approved` is `reviewDecision == "APPROVED"`; when `reviewDecision` is empty (and not in solo mode), it is read from the branch PR's reviews (`gh pr view <n> --json reviews`, R21(d)): a reviewer's latest review at the head decides, at least one `APPROVED` from an `OWNER`, or a `MEMBER` or `COLLABORATOR` whose repository role is `admin`, `maintain` or `write` (`attestation.repo_role`, unreadable fails closed), who is neither the PR author nor an author or committer of any of its commits (`gh api repos/<repo>/pulls/<n>/commits`); an undismissed `CHANGES_REQUESTED` at any commit means no approval. `RenderCtx.stacked` is every open PR whose `baseRefName` is the branch (R22). The branch PR's attestation is `attestation.pr_attestation(...)` when its `headRefOid` is present locally (`git cat-file -e`), else `none` with `why: the PR head <sha7> is not in this checkout (pull or push first)`; likewise when `origin/<baseRefName>` is not in the checkout (`git rev-parse --verify -q`): `none`, `why: base origin/<b> not in this checkout (git fetch origin <b>)`, and `solo` false — team mode, fail safe (R21(b)). With a branch PR, `--explain` prints `why: base origin/<b> at <sha7>, committed <date> (this checkout's view; next.sh never fetches)` (R7). `pr_attestation`'s `comment` entry supplies the blocked `findings:` block (its `html_url` and `body`) and R20's waiver URL — the comments are fetched once, inside `pr_attestation`; open lane PRs other than the branch's carry `none` (the kernel reads only `number`, `open` and `mine` for them). `unbuilt`, `untagged_ship`, `next_version`, `ship_phases_merged` come from merged PRs and tags: a plan's `## Build N` is done when a merged `build/<slug>-N` PR names it, or when a merged `impl/plan-<token>-<name>` PR names it: `<name>` is the plan's slug and the token — the full token after `plan-` (`1a`, `1b`, `5`), compared as a string, never reduced to digits — equals `N`; a merged impl PR whose `<name>` matches no plan slug counts for nothing and `--explain` names it (an earlier cycle's `impl/plan-1-foundation` never marks another plan's Build 1 done; PR #48 scoped re-review N1); a build PR is a merged PR whose head parses to Build, BuildSec, Patch, Impl or ImplSec; the latest release tag is the highest `v<major>.<minor>.<patch>` tag with no pre-release suffix (`v0.0.1-demo` is ignored); `next_version` is set iff a build PR's merge commit is not an ancestor of that tag (or no tag exists), valued minor + 1 (`0.1.0` with no tag) — a merge commit not in the checkout counts as not an ancestor, and `--explain` names it (R21(c)); `untagged_ship` is the lowest version of a merged `ship/<v>` PR, or of a merged `phase/release` PR (the `docs/releases/<v>-notes.md` it added, `gh pr view <n> --json files`), with no tag `v<v>`; a `<v>` that fails the `ship/<version>` rule (`VERSION_RE`) is never passed to `git tag --list` and, while its PR is unreleased and no later merged `phase/release` PR names a valid version, derives ExplainUnknown on `main` naming the file (PR #48 scoped re-review N5; round 3b D1). That guard and the bad-slug guard (`build unknown-build`) are wrapper-side fail-safes outside `state.dfy`, mirroring the kernel's lane naming (the tag row's `ship` on the lanes path, `release` on the regulated path). No remote, or any `gh` failure: `pr_state_known` false, every list empty, `note: cannot see PRs (<reason>) — /next will not propose creating a PR`.

**Classifier additions** (`scripts/lib/specflow/attestation.py`, Task 4, as shipped after the final review and PR #48's verifier runs): `classify(..., permissions=None, bases=None)`; `WRITER_ROLES = ("admin", "maintain", "write")`, `_NON_WRITER_ROLES = ("read", "triage", "none")` and `resolve_role` (a custom or empty `role_name` is resolved through the legacy `permission` field; a role neither field names is unreadable). It applies rule 1b for markers and waivers, judged before any blocking rule: a `MEMBER`'s or `COLLABORATOR`'s comment counts, for acceptance and for blocking, only with a writing role — a known `read`, `triage` or `none` role neither accepts nor blocks (`marker-not-writer`, `waiver-not-writer`); an unreadable role is never accepted and keeps blocking (`marker-permission-unknown`, `waiver-permission-unknown`; a blocking reason suffixed `-permission-unknown`; `request-changes-permission-unknown`); an `OWNER` needs no lookup. The base binding: a marker's `base:` must be 40 hex, and a recorded base that does not give the head the PR's current merge base is `base-mismatch` for an `APPROVE` (refused) and `request-changes-base-mismatch` for a `REQUEST_CHANGES` (still blocking until a newer accepted comment supersedes it). `pr_attestation(*, repo, pr, head, base_ref, pr_author, gh_json=_gh_json_list, commits=None, files=None, contents=None, comments=None, permissions=None) -> dict` returning `classify`'s dict plus `"judged"` (the `explain` list), `"required_mode"`, `"prompt_sha256"`, `"solo"`, `"comment"` — `{"id", "html_url", "body"}` of the decisive comment (the accepted marker or waiver, or the `REQUEST_CHANGES` comment), or `null` when none decides — and `"role_unknown"`, so `next.sh`'s `findings:` block and R20 never fetch the comments a second time — the one function that gathers a PR's inputs (commits, files and contents at `base_ref..head`, policy and prompt hash at the base, review scope, comments, each `MEMBER` or `COLLABORATOR` commenter's role, and each marker's recorded base against the current merge base) and classifies them; `check()` classifies only through it and prints its messages. `check --permissions FILE` (test-only JSON `{login: role}` or `{login: {role_name, permission}}`; no workflow passes it). `_package_lock_rule` per R10, plus `base-lockfile-v1` (a base `package-lock.json` without a `packages` map fails closed) and the v2 legacy tree mirroring `packages`. It adds fixtures 72–102: `72-waiver-member-write` … `81-dependabot-npm-lockfile-entry-removed` (waiver roles and npm entries, as planned), then 82–88 and 92–102 (marker roles, custom roles, unreadable roles that keep blocking, the base binding and a base that is not a SHA) and 89–91 (npm: base v1, the legacy tree, the v2 mirror); the fixture context gains `"permissions": {login: role}`, and every existing fixture whose accepted waiver or marker comes from a `MEMBER` or `COLLABORATOR` gains its commenter's `"write"` role (listed in the PR body); fixtures before 72 keep their numbers.

**The fence manifest** (`scripts/factory-only.txt`, Task 13): one repository-relative glob per line (`fnmatch` over the relative paths of a filesystem walk of the new tree, `.git` skipped — init runs before `git init`, R11; a trailing `/` a directory), `#` comments; init reads it with `python3`, removes each match, then the manifest. Content: `docs/specs/2026-09-25-factory-v3-2-*.md`, `docs/adr/003-pipeline-state-derivation.md`, `docs/architecture/2026-09-25-factory-v3-2-*.md`, `docs/plans/*-factory-v3-2-*-plan.md`, `docs/reviews/*.md`, `verification/factory_v3_2/`, `scripts/factory-only.txt`. A path the examples manifest lists (`CLAUDE.md` "Canonical Example", `examples.py list`) is never fenced, so the python demo keeps `docs/reviews/2026-05-28-v3.1-demo-review.md`; the factory's later reviews (P5's, P6's) are fenced by the same glob. ADR-002 is not listed: it governs every instance's disposition gate (R11).

---

## The model step (R1) — on this branch, right after this plan

Not a numbered task: the step after this plan writes `verification/factory_v3_2/state.dfy` to the shape under Interfaces "The Dafny model" and `tests/governance/test_state_model.sh` (full code above), verifies the model under 4.11.0 and 4.9.1, runs `test_state_model.sh` and `check-traceability.sh` (now passing for REQ-341), and commits both: "proof(p5): verification/factory_v3_2/state.dfy — ADR-003's derive as a pure function, the five proof obligations, and its shape test (REQ-341, REQ-385, REQ-340)". Expected state after it: `check-traceability.sh` passes, and `check-covers.sh` passes for REQ-341, REQ-385 and REQ-340 (`test_state_model.sh` cites them); it still fails on REQ-343 alone until the amendment-B commit below. The gates are red between this plan's commit and the amendment-B commit (the plan claims before its tests exist on the branch); only the PLAN PR's head is judged. **As executed:** the first model commit (`42d0bea`) carried `state.dfy` without the test, so the PLAN PR's head was red (`check-covers.sh`: no test cited REQ-341 or REQ-385; with it `test_check_covers.sh`, `test_traceability.sh` and `test_examples.sh`). The fresh-eyes revision commits `test_state_model.sh` with the revised model ("proof(p5): revise after proof review (REQ-341)", its body citing REQ-385 and REQ-340), re-runs `check-covers.sh`, `test_traceability.sh`, `test_examples.sh` and the gates from the venv, and the IMPLEMENT branch is cut only after that commit.

## Amendment B (REQ-343) — on this branch, after the model step, before the IMPLEMENT branch is cut

Constitution amendment PR B (spec, Non-Functional Requirements, Compliance): the text changes in place, as amendment A (`0b546c0`) did, with a REQ-citing commit subject and no dated note in the articles; the record is the commit, the spec's P5 PLAN `amended:` entry and the PLAN PR body. It turns P3 R19 and P3 R20 from interim readings into article text, makes the corrections `patch/p2-mediums` and P4 routed to it, and removes every interim-reading and deadline sentence from where a session reads the rules. **It weakens no mechanism (the article's text is narrowed in two places: the manifest-absent condition and the GPG-or-SSH fallback):** no script, workflow or gate changes; each rewritten sentence describes a mechanism that already runs (`verify-release.sh`'s previous-tag check, the PR template's checkbox, P4's Dependabot rule, `enforce_admins: false`), and the constitution's "tag missing" still blocks — now at the moment it can be judged.

**Files:** `constitution.md` (`art-branch-as-state` `:34-37`, `art-review-gate` `:71-80`, `art-threat-driven-security` `:153-158` and `:171`, `art-release-readiness` `:184-187`, `art-retrospective-cadence` `:253-256`); `.claude/rules/review-gate.md` (`:64`'s last sentence, `:71`'s "R19's one gap", a squash sentence in "Paths and branch names", `:137`); `docs/security/RUBRIC.md:35-38`; `.claude/skills/verifier/SKILL.md:34`; `.github/PULL_REQUEST_TEMPLATE.md:14-30`; `schemas/security-disposition-template.md:98-99`; `docs/GLOSSARY.md:127`; `docs/architecture/2026-09-25-factory-v3-2-threat-model.md:195` (one phrase); `docs/specs/2026-09-25-factory-v3-2-design.md` (frontmatter `amended:` gains one entry; no REQ body changes); tests: create `tests/governance/test_constitution_amendment_b.sh`; rewrite `tests/governance/test_onboarding_surface.sh:222-225`, `:232-233`, `:242-243`, `:258-264`, `tests/governance/test_review_gate_claims.sh:163-172`, `:245-256`, `tests/governance/test_security_schema_docs.sh:84-85`; add to `tests/governance/test_threat_model_current.sh` and `tests/governance/test_spec_lifecycle.sh`; reword the comment `tests/governance/test_verify_release.sh:12`.

**Interfaces (the settled text, as intent; the tests pin the quoted phrases):**
- **`art-branch-as-state`** (F-21, H21). "No work on `main`" goes. The article says: work reaches `main` only through a PR, except init's first commit (the new instance's starting tree, with nothing yet to review) and the doc-only minor exception bounded in `.claude/rules/review-gate.md`. Each phase has a named branch on either path — lanes: `design/<slug>`, `build/<slug>-N`, `ship/<version>`, and `build/sec-<id>` for the security back-edge; regulated: `phase/spec-<slug>`, `phase/arch-<slug>`, `phase/plan-<slug>`, `impl/plan-N-<name>`, `phase/validate`, `phase/security`, `phase/release`, and `impl/sec-<id>`; both: `patch/<slug>` (the patch tier) and `phase/retro-YYYY-MM-DD`. State of work is the set of branches and their PRs — open, merged or closed — and the tree; it is derived from them and there is no out-of-band state file. "Squash merges are permitted": state is read from PRs, not branch ancestry. `.specflow.yml` is configuration, not state: its `path` chooses which branch names are proposed, and nothing records progress in it. How to apply: every phase transition is a PR that reaches `main`, directly or stacked on an open phase PR (REQ-395); both paths' branch names and the lane-to-phase mapping are in `.claude/rules/review-gate.md`.
- **`art-review-gate`** (H22). The Dependabot sentence becomes P4's rule and its residual: a PR opened by `dependabot[bot]` passes the verifier check without a marker only when every commit is authored by `dependabot[bot]`, verified by GitHub, and committed by `dependabot[bot]` or `web-flow`, and its diff touches only dependency manifests and lockfiles — "never `.github/`" — and "only moves the versions" of dependencies the base already lists; anything else "fails closed" and the verifier must review it (REQ-334); in solo mode such a PR merges with no second review. The identity checks do not tie a commit to Dependabot: "anyone with write access" can create through GitHub's API a commit GitHub marks verified and committed by `web-flow` under a chosen author, so the content rule is the real limit, and a forged commit can still move an existing dependency to another registry version of the same package unreviewed (threat-model "dfe-13"'s residual). The admin sentence: even where branch protection works, a repository admin (a solo owner always is one) can merge past red `gates` or `verifier` checks and "without the required approving review"; on a free-plan private repository "nothing server-side" enforces the checks or the review (the free-plan qualifier stays on this server-side sentence alone). The solo-marker sentence drops its free-plan qualifier: the solo `APPROVE` is the recorded second review and, "in solo mode, on any GitHub plan, it is a tamper-evident audit trail" … "not an enforced control" (the threat model's first residual says the same; the factory itself is on the Team plan with protection on). New: "**Solo sign-off:**" "zero required approvals" in solo mode ("REQ-314") is the maintainer's explicit decision — the verifier, not a person, is the second review — signed off by merging this amendment (amendment PR B, REQ-343). Every phrase `test_review_gate_claims.sh:8-12` and `:52-58` requires stays.
- **`art-threat-driven-security`** (H22). The band table gains the row `| low (informational) | 0.0 |` after `| low | 0.1–3.9 |`, and a sentence: a finding with no impact on any system (every impact metric `N`) scores 0.0 and is recorded as `severity: low`, its body saying it is informational; inventing an impact to reach 0.1 is a manufactured score. The back-edge: spawn `impl/sec-<finding-id>` (regulated path) or `build/sec-<finding-id>` (lanes path) from main, fix with TDD, merge, re-run VALIDATE (on the lanes path, CI on that build PR), then resume `phase/security` or `ship/<version>` with `status: fixed`.
- **`art-release-readiness`** (P3 R19, H22). The tag `v<version>` is created on the release PR's merge commit "after the merge" (signed preferred; annotated permitted only when neither GPG nor SSH signing is verifiably available, with the "fallback" recorded in `<version>-known-limitations.md` plus a follow-up to re-tag signed); the manifest paragraph, "transcribed" included, is unchanged. How to apply: at PR time the RELEASE-phase gate (`scripts/verify-release.sh`) blocks merge if any of: gates non-zero; manifest checksums wrong or manifest content not transcribed into release notes ("checked only where `dist/manifest.json` exists" — locally, where `/release` produces it; in CI, where `dist/` is gitignored, only the Artifacts table's shape is checked, until the CI-built manifest, "REQ-384"; a missing manifest blocks nothing at PR time, as `release_gate.check_artifacts` and `review-gate.md`'s RELEASE exit gate say); known-limitations missing a SEC-NNN that is accepted or deferred; the tag `v<version>` "already exists" (the release PR never carries its own tag). "Tag missing" is judged after the merge: a merged release whose merge commit has no tag, or an annotated tag without the fallback recorded, is incomplete; the next release PR's `verify-release.sh` fails a previous release tag that is lightweight, unsigned without the recorded fallback, badly signed or not an ancestor of its base, and warns when it is missing, which the "PR template"'s RELEASE checkbox asks the maintainer to confirm by hand; until `release.yml` replays these checks at the tag ("REQ-350"), that checkbox is the only check between a merge and the next release PR.
- **`art-retrospective-cadence`.** Run `/retrospective` after every release PR merges — `ship/<version>` on the lanes path, `phase/release` on the regulated path ("recommended; not automatic"); How to apply names both.
- **`.claude/rules/review-gate.md`.** `:64`'s last sentence ("The constitution's sentence … overclaims; its correction is tracked for constitution amendment PR B (P5) alongside REQ-334 (P4).") becomes "`art-review-gate` states this rule and its forgeable-author residual (amendment B, REQ-343)." `:71`'s "(R19's one gap)" becomes "(the one gap `art-release-readiness` records)". "Paths and branch names" gains, after its first paragraph: "Squash merges are permitted on both paths: state is derived from PRs (open, merged or closed) and the tree, never from branch ancestry (REQ-340)." `:137`: "**R19's interim reading** (until constitution amendment B, REQ-343, P5, aligns the text): `art-release-readiness`'s "tag missing" is judged after the merge — … what the clause blocks. This reading overrides the article's literal text until then. Its control is" becomes "`art-release-readiness` judges "tag missing" after the merge: the ship PR must not carry `v<version>`, and a merged release without its tag is what the clause blocks. Its control is" (the control description, through "standing informational finding.", is unchanged); "**R20's interim reading** … Deadline for both readings: … a finding of severity high." (to the end of the bullet) becomes "A finding with no impact on any system scores 0.0 and is recorded as an informational `severity: low` (`art-threat-driven-security`'s band table, `docs/security/RUBRIC.md`)."
- **`docs/security/RUBRIC.md:35-38`** becomes one sentence: "The 0.0 row is `art-threat-driven-security`'s own (constitution amendment B, REQ-343)." (`:31`'s "(R20)" stays: it names the ruling that introduced the mapping.)
- **`.claude/skills/verifier/SKILL.md:34` (step 7):** On a RELEASE-phase PR (head branch `phase/release` or `ship/<version>`, as the prompt names it, or a changed `docs/releases/<version>-notes.md`), record a "standing informational finding" (severity low), every time, with no condition on anything outside the changed documents and the code: `art-release-readiness`'s "tag missing" is "judged after the merge" — a ship PR that does not yet carry `v<version>` is correct, and one that does carry the tag fails `verify-release.sh`. In that finding, ask the maintainer to confirm by hand that the previous release's tag exists, is signed (or annotated with the fallback recorded in that version's known-limitations) and tags that release's merge commit: `verify-release.sh` FAILs a wrong previous tag in CI but only WARNs on a missing one. A `severity: low` finding with a 0.0 vector is an informational low (`art-threat-driven-security`'s band table), not a band violation. (The override sentence, the deadline and the lapse rule go.)
- **`.github/PULL_REQUEST_TEMPLATE.md`** — one checklist per lane (REQ-343): `### Phase-specific (keep the one that applies)` becomes `### Lane checklists (keep the one that applies)` with `#### Design lane — design/<slug>; regulated: phase/spec-<slug>, phase/arch-<slug>, phase/plan-<slug>` (the **SPEC**, **ARCHITECTURE** and **PLAN/ANALYZE** lines, unchanged), `#### Build lane — build/<slug>-N, build/sec-<id>, patch/<slug>; regulated: impl/plan-N-<name>, impl/sec-<id>, phase/validate` (the **IMPLEMENT** line, and a **VALIDATE** line: CI on this PR is VALIDATE on the lanes path; on `phase/validate`, `bash scripts/run-quality-gates.sh` green), `#### Ship lane — ship/<version>; regulated: phase/security, phase/release` (the **SECURITY** and **RELEASE** lines and their checkboxes, the lines still starting `**SECURITY**` and `**RELEASE**`, `test_release_commands.sh:35-59`). The RELEASE checkbox ends "— as `art-release-readiness` requires ("tag missing" is judged after the merge); `verify-release.sh` only WARNs when it is missing" instead of naming R19.
- **`schemas/security-disposition-template.md:98-99`:** "`none` 0.0 (an informational finding recorded as `severity: low` — R20's interim reading pending constitution amendment B, REQ-343)" becomes "`none` 0.0 (an informational finding recorded as `severity: low` — `art-threat-driven-security`'s informational row)". `:41` and `:62` keep "(R20)" (provenance).
- **`docs/GLOSSARY.md:127`:** the overclaim sentence becomes "`art-review-gate` states this rule and its forgeable-author residual (amendment B, REQ-343)."
- **Threat model `:195`:** "(R19's one gap until amendment B, REQ-343)" becomes "(the one gap `art-release-readiness` records)"; nothing else in the architecture documents changes on this branch.
- **The spec's `amended:`** gains, after the P3 IMPLEMENT entry: "P5 PLAN PR (2026-09-28): constitution amendment B (REQ-343) lands with this PR, REQ bodies unchanged — art-branch-as-state lists both paths' branch names, permits init's first commit on main and the doc-only minor exception while every phase transition stays a PR, permits squash merges, and classifies .specflow.yml as configuration; art-review-gate states the Dependabot rule P4 shipped with its forgeable-author residual (dfe-13), says enforce_admins: false lets an admin skip the required approving review as well as red checks, and records the maintainer's sign-off on solo mode's zero required approvals (REQ-314); art-threat-driven-security names the lanes back-edge build/sec-<id> and gains the informational 0.0 row (P3 R20); art-release-readiness judges 'tag missing' after the merge (P3 R19); art-retrospective-cadence triggers on the ship/<version> or phase/release PR; the interim-reading and deadline text leaves review-gate.md, RUBRIC.md, the verifier skill, the PR template and the schema template (the P3 IMPLEMENT entry above stays as history). REQ-393's step is read as ADR-003's rendering of idle (P5 R4): NewBranch(ProposeDesign), rendered git checkout -b design/<slug> then RunBrainstorm, on the lanes path, and NewBranch(ProposeSpec), rendered git checkout -b phase/spec-<slug> then RunBrainstorm, on the regulated path, not the literal run /specify <slug>. REQ-341 as refined by the P5 plan's R5 and R6, ADR-003 unchanged: PR carries mine; Impl carries the plan token as a string (impl/plan-1a-first-run); Step's arguments are datatypes (NewBranch(Proposal), RunImplement(ImplTarget), ExplainUnknown(Why), AddressFindings(pr)); an unknown branch derives unknown-branch before any PR substate; main has no branch PR; Facts gains ship_phases_merged, which orders the regulated path's phase/validate, phase/security and phase/release proposals." The entry holds no double quote (the frontmatter readers are flat) and no date after today (`test_spec_lifecycle.sh:103-109`).

**The measurement** (`git grep -n` of `interim`, `amendment B`, `R19`, `R20`, `2026-10-31`, `later plan`, `P5` over the tree, excluding the spec's `amended:` history, `docs/plans/`, `docs/reviews/` and released `docs/security/*-review.md`), each hit with its disposition:

| Hit | Disposition |
|---|---|
| `.claude/rules/review-gate.md:62` "a check of the commenter's repository permission is deferred to P5" | rewritten — Task 4 (R9 delivers it) |
| `.claude/rules/review-gate.md:64` "tracked for constitution amendment PR B (P5) alongside REQ-334 (P4)" | rewritten — here |
| `.claude/rules/review-gate.md:71` "(R19's one gap)" | rewritten — here |
| `.claude/rules/review-gate.md:137` R19's and R20's interim readings, the override sentence, the deadline and lapse rule | removed and rewritten — here |
| `.claude/skills/verifier/SKILL.md:34` step 7's interim reading, override sentence and deadline | rewritten — here |
| `.github/PULL_REQUEST_TEMPLATE.md:30` "under R19's interim reading … until amendment B, REQ-343" | rewritten — here |
| `docs/security/RUBRIC.md:35-38` interim paragraph and deadline | removed and rewritten — here |
| `docs/security/RUBRIC.md:31` "(R20)" | kept — provenance of the `none` → `low` mapping, not interim text |
| `schemas/security-disposition-template.md:98-99` "R20's interim reading pending constitution amendment B, REQ-343" | rewritten — here |
| `schemas/security-disposition-template.md:41`, `:62` "(R20)" | kept — provenance |
| `docs/GLOSSARY.md:127` "tracked for constitution amendment PR B (P5)" | rewritten — here |
| `docs/GLOSSARY.md:316` "a permission check is deferred to P5" | rewritten — Task 4 |
| threat model `:195` "(R19's one gap until amendment B, REQ-343)" | rewritten — here |
| threat model `:115` dfe-7, `:118` dfe-10 "P5"; `:192` "retrospective / P5 backlog" | rewritten — Task 15 (what P5 shipped; R16's proposal) |
| overview `:130` heading "Consequences recorded for later plans" | kept — a heading, still true |
| overview `:132` "P5 extends it … and creates …" | rewritten — Task 15 |
| `docs/security/README.md:32` "(both informational, R20)" | kept — a dated schema-migration record |
| `docs/adr/003-pipeline-state-derivation.md:72`, `:75` "P5 plan" | kept — ADR-003 is not changed; history |
| `.claude/commands/release.md:39` "an interim step; P6's `/release --tag`" | kept — P6's interim step (REQ-383), not amendment B's |
| `.claude/commands/analyze.md:35` "which later plan claims the rest" | kept — generic, true |
| `scripts/check-covers.sh:15` "its former interim check" | kept — history of REQ-323's delegation |
| `scripts/configure-repo.sh:71` "Until v3.2's /next arrives (a later plan, P5)" | rewritten — Task 14 (once `/next` exists) |
| `README.md:192-196` "A later plan (P5) adds `/next`" | rewritten — Task 14 |
| `scripts/lib/specflow/cvss4.py:1`, `:346` "R20" | kept — ruling provenance in code |
| `scripts/lib/specflow/release_gate.py:17`, `:390`, `:407` "R19" | kept — the ruling that defines the WARN; the printed text names the ruling, not an override |
| `scripts/lib/specflow/release_gate.py:173` "(F-10/W-7, P5)" | rewritten — Task 13 (the fence) |
| `scripts/lib/specflow/attestation.py:9` "P5's `next.sh` imports this module" | rewritten — Task 4 |
| `scripts/lib/specflow/records.py:5` "The state records … are P5's" | rewritten — Task 2 |
| `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md:13` "R12", `:26`, `:108`, `:135` "R20" | rewritten — Task 11 (R18) |
| `tests/governance/test_onboarding_surface.sh:222-225`, `:232-233`, `:242-243`, `:258-264` | rewritten first — here |
| `tests/governance/test_onboarding_surface.sh:121-131` "/next … a later plan" | rewritten — Task 14 |
| `tests/governance/test_onboarding_surface.sh:207` ("tdd.md … not 'a later plan'") | kept — it forbids stale text |
| `tests/governance/test_review_gate_claims.sh:114-115` "P5" | rewritten — Task 4 |
| `tests/governance/test_review_gate_claims.sh:163-172` `DEPCON`; `:245-256` `AMB_DL` | rewritten first — here |
| `tests/governance/test_review_gate_claims.sh:154` | kept — it forbids stale text |
| `tests/governance/test_security_schema_docs.sh:84-85` | rewritten first — here |
| `tests/governance/test_security_schema_docs.sh:21`, `:34`, `:55` "R20" | kept — provenance labels; their assertions hold after the amendment |
| `tests/governance/test_spec_lifecycle.sh:85`, `:106` | kept — the P3 entry keeps "no later than 2026-10-31" as history, so the exemption stays |
| `tests/governance/test_spec_lifecycle.sh:156`, `:159-169` | kept — REQ bodies unchanged |
| `tests/governance/test_threat_model_current.sh:4`, `:29-30` | rewritten — Task 15 |
| `tests/governance/test_threat_model_current.sh:62-70` | kept, and a check added here |
| `tests/governance/test_verify_release.sh:12` "(R19: …)" | reworded — here (a comment) |
| `tests/governance/test_configure_repo.sh:27` | rewritten — Task 14 |
| `tests/governance/test_attestation.sh:4`, `:159` "P5's next.sh must pass these files unchanged" | rewritten — Task 4 |
| `tests/governance/test_cvss4.sh:66`, `test_security_blocks.sh:77` "R20"; `test_check_covers.sh:5`, `:71` "interim" | kept — provenance and history |

- [x] **Step AB-1: Write the failing tests.** Create `tests/governance/test_constitution_amendment_b.sh`:

```bash
#!/usr/bin/env bash
# REQ-343 (constitution amendment B, with P5's PLAN PR): art-branch-as-state lists both paths' branch names, permits init's
# first commit on main and the doc-only minor exception while every phase transition stays a PR, permits squash merges and
# calls .specflow.yml configuration; art-review-gate states the Dependabot rule P4 shipped and its forgeable-author
# residual, the admin bypass of the required review as well as red checks, and the maintainer's sign-off on solo mode's
# zero required approvals (REQ-314); art-threat-driven-security names the lanes back-edge and the informational 0.0 row;
# art-release-readiness judges "tag missing" after the merge; art-retrospective-cadence triggers on the release PR of
# either path. No interim reading or deadline survives where a session reads the rules. The PR template has one checklist
# per lane (REQ-343), and review-gate.md permits squash merges on both paths (REQ-340).
# Covers: REQ-343
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=constitution.md
art() { awk -v s="slug: $1" '$0 == s {f=1} f && /^---$/ {exit} f' "$C" | tr '\n' ' ' | tr -s ' '; }
bas=$(art art-branch-as-state); rev=$(art art-review-gate); tds=$(art art-threat-driven-security)
rel=$(art art-release-readiness); ret=$(art art-retrospective-cadence)
ck "constitution keeps twelve well-formed articles" bash tests/governance/test_constitution_articles.sh
for b in 'design/<slug>' 'build/<slug>-N' 'ship/<version>' 'build/sec-<id>' 'phase/spec-<slug>' 'phase/arch-<slug>' \
         'phase/plan-<slug>' 'impl/plan-N-<name>' 'impl/sec-<id>' 'phase/validate' 'phase/security' 'phase/release' \
         'patch/<slug>' 'phase/retro-YYYY-MM-DD'; do
  ck "art-branch-as-state names $b" grep -qF -- "$b" <<<"$bas"
done
ck "art-branch-as-state no longer says 'No work on main' (init commits on main; F-21)" no grep -qF 'No work on `main`' <<<"$bas"
ck "art-branch-as-state permits init's first commit and the doc-only minor exception" \
  bash -c 'grep -qF "first commit" <<<"$1" && grep -qi "init" <<<"$1" && grep -qi "minor exception" <<<"$1"' _ "$bas"
ck "art-branch-as-state: every phase transition is still a PR that reaches main, directly or stacked" \
  bash -c 'grep -qF "reaches \`main\`" <<<"$1" && grep -qi "stacked" <<<"$1"' _ "$bas"
ck "art-branch-as-state: squash merges permitted; .specflow.yml is configuration, not state; no state file" \
  bash -c 'grep -qF "Squash merges are permitted" <<<"$1" && grep -qF ".specflow.yml" <<<"$1" && grep -qi "configuration, not state" <<<"$1" && grep -qF "no out-of-band state file" <<<"$1"' _ "$bas"
for w in 'verified' 'web-flow' 'never `.github/`' 'only moves the versions' 'fails closed' 'anyone with write access' 'dfe-13' \
         'without the required approving review' 'nothing server-side' 'Solo sign-off:' 'zero required approvals' 'REQ-314'; do
  ck "art-review-gate says '$w'" grep -qF -- "$w" <<<"$rev"
done
ck "art-review-gate drops the overclaim and the P4 deferral" \
  bash -c '! grep -qF "a commit by anyone else removes the exemption" <<<"$1" && ! grep -qF "deferred to P4" <<<"$1"' _ "$rev"
ck "art-review-gate: the solo marker is an audit trail, not an enforced control, on any GitHub plan (threat model's first residual)" \
  bash -c 'grep -qF "in solo mode, on any GitHub plan, it is a tamper-evident audit trail" <<<"$1" && ! grep -qF "on a free-plan private repository it is a tamper-evident" <<<"$1"' _ "$rev"
ck "art-threat-driven-security: the informational 0.0 row follows the 0.1–3.9 low row" \
  python3 - "$C" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
a = t[t.index("slug: art-threat-driven-security"):]
a = a[: a.index("\n---\n")]
rows = [l.strip() for l in a.splitlines() if l.startswith("| ")]
i = rows.index("| low | 0.1–3.9 |")
assert rows[i + 1] == "| low (informational) | 0.0 |", rows
PY
ck "art-threat-driven-security: an informational finding is recorded as severity low, never a manufactured score" \
  bash -c 'grep -qi "informational" <<<"$1" && grep -qF "severity: low" <<<"$1" && grep -qi "manufactured" <<<"$1"' _ "$tds"
ck "art-threat-driven-security: the back-edge names impl/sec- (regulated) and build/sec- (lanes), resuming phase/security or ship/<version>" \
  bash -c 'grep -qF "impl/sec-<finding-id>" <<<"$1" && grep -qF "build/sec-<finding-id>" <<<"$1" && grep -qF "ship/<version>" <<<"$1"' _ "$tds"
for w in 'after the merge' 'already exists' 'verify-release.sh' 'PR template' 'REQ-350' 'transcribed' 'fallback' 'tag missing'; do
  ck "art-release-readiness says '$w'" grep -qiF -- "$w" <<<"$rel"
done
ck "art-release-readiness: the manifest is compared only where dist/manifest.json exists; a missing manifest blocks nothing at PR time" \
  bash -c 'grep -qF "checked only where \`dist/manifest.json\` exists" <<<"$1" && grep -qF "REQ-384" <<<"$1" && ! grep -qF "manifest absent" <<<"$1"' _ "$rel"
ck "art-retrospective-cadence triggers on ship/<version> and phase/release, recommended not automatic" \
  bash -c 'grep -qF "ship/<version>" <<<"$1" && grep -qF "phase/release" <<<"$1" && grep -qF "recommended; not automatic" <<<"$1"' _ "$ret"
for f in "$C" .claude/rules/review-gate.md docs/security/RUBRIC.md .claude/skills/verifier/SKILL.md \
         .github/PULL_REQUEST_TEMPLATE.md schemas/security-disposition-template.md docs/GLOSSARY.md; do
  ck "$f: no interim reading, no override of an article, no amendment-B deadline" \
    bash -c 't=$(tr "\n" " " < "$1"); ! grep -qiF "interim reading" <<<"$t" && ! grep -qF "2026-10-31" <<<"$t" && ! grep -qF "until amendment B" <<<"$t" && ! grep -qF "overrides the article" <<<"$t"' _ "$f"
done
rg=.claude/rules/review-gate.md
ck "review-gate.md: squash merges are permitted on both paths (REQ-340)" \
  grep -qF 'Squash merges are permitted on both paths' <<<"$(awk '/^## Paths and branch names/{f=1; next} /^## /{f=0} f' "$rg" | tr '\n' ' ')"
rel_gate=$(grep -F "RELEASE exit gate" "$rg")
ck "review-gate.md RELEASE exit gate: art-release-readiness judges 'tag missing' after the merge; the control is unchanged" \
  bash -c 'grep -qF "judges \"tag missing\" after the merge" <<<"$1" && grep -qF "PR template" <<<"$1" && grep -qF "git tag -v" <<<"$1"' _ "$rel_gate"
PT=.github/PULL_REQUEST_TEMPLATE.md
for lane in 'Design lane' 'Build lane' 'Ship lane'; do ck "the PR template has a $lane checklist" grep -qE "^#### $lane — " "$PT"; done
for b in 'design/<slug>' 'phase/spec-<slug>' 'phase/plan-<slug>' 'build/<slug>-N' 'impl/plan-N-<name>' 'phase/validate' \
         'ship/<version>' 'phase/security' 'phase/release'; do
  ck "the PR template's lane headings name $b" bash -c 'grep -E "^#### " "$1" | grep -qF -- "$2"' _ "$PT" "$b"
done
ck "the PR template keeps its SECURITY and RELEASE lines and its plan-style rule" \
  bash -c 'grep -q "^\*\*SECURITY\*\*" "$1" && grep -q "^\*\*RELEASE\*\*" "$1" && grep -qF "implementation as intent" "$1" && grep -qF "implements:" "$1"' _ "$PT"
finish test_constitution_amendment_b
```

In `tests/governance/test_onboarding_surface.sh`, replace `:222-225` with:

```bash
ck "review-gate.md RELEASE exit gate: 'tag missing' is judged after the merge (art-release-readiness), not an interim reading" \
  bash -c 'l=$(grep -F "RELEASE exit gate" "$1"); grep -qF "tag missing" <<<"$l" && grep -qF "after the merge" <<<"$l" && ! grep -qiF "interim" <<<"$l"' _ .claude/rules/review-gate.md
ck "verifier SKILL.md: 'tag missing' is judged after the merge, per art-release-readiness" \
  bash -c 'grep -qF "tag missing" "$1" && grep -qF "judged after the merge" "$1" && grep -qF "art-release-readiness" "$1"' _ .claude/skills/verifier/SKILL.md
```

replace the comment at `:232-233` with the block's first two comment lines below and the check at `:242-243` with its `# Covers: REQ-343` line and check (the `# Covers: REQ-324`/`REQ-322` lines `:234-235` stay):

```bash
# PR #42 findings 1, 2, 3, 7 and code mode (REQ-324, REQ-322), settled by amendment B (REQ-343): the previous-tag control
# is the CI check plus the PR template's checkbox, never the verifier; the 0.0 row is the constitution's own.
# Covers: REQ-343
ck "RELEASE exit gate: no interim reading, no override of the article, no deadline; the 0.0 row cites art-threat-driven-security" \
  bash -c '! grep -qiF "interim reading" <<<"$1" && ! grep -qF "overrides the article" <<<"$1" && ! grep -qF "2026-10-31" <<<"$1" && grep -qF "art-threat-driven-security" <<<"$1"' _ "$rel"
```

and replace `:258-264` with:

```bash
s7=$(grep -E "^7\. " "$sk" || true)
ck "verifier SKILL.md step 7 depends on nothing the headless verifier cannot see, and states no deadline" \
  bash -c '! grep -qiF "PR body" <<<"$1" && ! grep -qF "WARN verify-release" <<<"$1" && grep -qF "standing informational finding" <<<"$1" && grep -qF "art-release-readiness" <<<"$1" && ! grep -qF "2026-10-31" <<<"$1" && ! grep -qiF "interim" <<<"$1"' _ "$s7"
ck "the PR template's RELEASE checkbox: the maintainer confirms the previous tag, as art-release-readiness requires" \
  bash -c 'grep -qE "^- \[ \] .*previous release.*tag.*art-release-readiness" "$1" && ! grep -qF "R19" "$1"' _ .github/PULL_REQUEST_TEMPLATE.md
ck "RUBRIC.md: the 0.0 row is art-threat-driven-security's own; no interim paragraph, no deadline" \
  bash -c 'grep -qF "art-threat-driven-security" "$1" && ! grep -qiF "interim reading" "$1" && ! grep -qF "2026-10-31" "$1"' _ docs/security/RUBRIC.md
```

In `tests/governance/test_review_gate_claims.sh`, replace `:163-172` with:

```bash
# P4 (REQ-334, dfe-13) and amendment B (REQ-343): the wording states the shipped verified-commit rule, fails closed on any
# mismatch, and says art-review-gate states the same rule — no overclaim is left to track.
# Covers: REQ-343
DEPFAIL='fails? closed'
DEPCON='`art-review-gate` states this rule and its forgeable-author residual (amendment B, REQ-343)'
for pair in "GLOSSARY:$gdb" "table row:$dep"; do
  where=${pair%%:*}; txt=${pair#*:}; txt=$(tr '\n' ' ' <<<"$txt" | tr -s ' ')
  ck "$where Dependabot: any failure — unverified, a foreign committer, .github/, or a non-version edit — fails closed" grep -qiE "$DEPFAIL" <<<"$txt"
  ck "$where Dependabot: art-review-gate states the same rule (amendment B), no tracked overclaim" \
    bash -c 'grep -qF "$1" <<<"$2" && ! grep -qF "overclaims" <<<"$2"' _ "$DEPCON" "$txt"
done
ck "GLOSSARY Dependabot: no longer says flatly 'A commit by anyone else'" no grep -qF 'A commit by anyone else,' <<<"$gdb"
```

and `:245-256` with:

```bash
# PR #42 third and fourth verifier runs (REQ-324, REQ-322): P3 R19/R20's interim readings carried a deadline; amendment B
# (REQ-343) landed with P5's PLAN PR, so the deadline and its lapse rule leave every document a session reads and stay
# only in the history (the spec's P3 amended: entry and the P3 plan, both fenced out of instances by P5 R11).
AMB_DL='amendment B (REQ-343) lands with P5'"'"'s PLAN PR, no later than 2026-10-31'
for f in "$R" docs/security/RUBRIC.md .claude/skills/verifier/SKILL.md .github/PULL_REQUEST_TEMPLATE.md \
         schemas/security-disposition-template.md docs/GLOSSARY.md; do
  ft=$(tr '\n' ' ' < "$f" | tr -s ' ')
  ck "$f no longer carries amendment B's deadline or its lapse rule" \
    bash -c '! grep -qF "$1" <<<"$2" && ! grep -qF "2026-10-31" <<<"$2" && ! grep -qF "lapsed, unextended date" <<<"$2"' _ "$AMB_DL" "$ft"
done
for f in docs/specs/2026-09-25-factory-v3-2-design.md docs/plans/2026-09-27-factory-v3-2-p3-plan.md; do
  [ -f "$f" ] || continue
  ck "$f keeps amendment B's deadline as history" grep -qF "no later than 2026-10-31" "$f"
done
```

In `tests/governance/test_security_schema_docs.sh`, replace `:84-85` with:

```bash
# Amendment B (REQ-343): the 0.0 row is the constitution's own, no longer an interim reading.
# Covers: REQ-343
ck "the schema template's band table matches RUBRIC.md: none 0.0 is informational (art-threat-driven-security's row), low is 0.1–3.9, never 'none/low 0.0–3.9', no interim reading" \
  bash -c 'grep -qF "0.1–3.9" "$1" && grep -qF "art-threat-driven-security" "$1" && grep -qiF "informational" "$1" && ! grep -qF "0.0–3.9" "$1" && ! grep -qiF "interim reading" "$1"' _ "$ROOT/schemas/security-disposition-template.md"
```

Append to `tests/governance/test_threat_model_current.sh`, above `finish`:

```bash
# Amendment B (REQ-343): the release-gates residual names the gap art-release-readiness records, not "until amendment B".
# Covers: REQ-343
ck "the release-gates residual no longer waits for amendment B" no grep -qF 'until amendment B' <<<"$rr"
ck "the release-gates residual names the gap art-release-readiness records" grep -qF 'the one gap `art-release-readiness` records' <<<"$rr"
```

In `tests/governance/test_spec_lifecycle.sh`, add `# Covers: REQ-343` to the header's Covers lines and, inside the `if [[ -f $V32 ]]` block before its closing `fi` (`:170`):

```bash
  # P5 PLAN PR (REQ-343; P5 R4, R5): amendment B, the idle-step reading and the record refinements, below the P3 entry.
  a5=$(grep -F 'P5 PLAN PR' <<<"$fm" || true); miss=""
  for t in '2026-09-28' 'amendment B' 'REQ-343' 'art-branch-as-state' 'art-review-gate' 'art-threat-driven-security' \
           'art-release-readiness' 'art-retrospective-cadence' 'REQ-393' 'NewBranch(ProposeDesign)' 'RunBrainstorm' \
           'REQ-341' 'ADR-003 unchanged' 'ship_phases_merged' 'REQ bodies unchanged'; do
    grep -qF -- "$t" <<<"$a5" || miss="$miss [$t]"
  done
  if [[ -z $miss ]]; then pass "the P5 PLAN PR amended: entry records amendment B, R4's idle step and R5/R6"
  else fail "the P5 PLAN PR amended: entry is missing or omits:$miss"; fi
  if [[ -n $a5 ]] && [[ $(grep -nF 'P3 IMPLEMENT PR' <<<"$fm" | cut -d: -f1) -lt $(grep -nF 'P5 PLAN PR' <<<"$fm" | cut -d: -f1) ]]; then
    pass "the P5 PLAN entry follows the P3 IMPLEMENT entry (history is appended)"
  else fail "the P5 PLAN amended: entry is not below the P3 IMPLEMENT entry"; fi
```

Reword the comment at `tests/governance/test_verify_release.sh:12`: "(R19: the tag is created after that merge)" → "(art-release-readiness: the tag is created after that merge)".

- [x] **Step AB-2: Run** `PATH="$HOME/.venvs/factory-tools/bin:$PATH"` with each of `bash tests/governance/test_constitution_amendment_b.sh`, `test_onboarding_surface.sh`, `test_review_gate_claims.sh`, `test_security_schema_docs.sh`, `test_threat_model_current.sh`, `test_spec_lifecycle.sh`. Expected: the new checks FAIL (the articles, the interim text, the PR template's lanes, the P5 entry); the checks this section leaves alone pass. Exit 1 for each.
- [x] **Step AB-3: Implement (intent).** Edit the constitution per Interfaces, keeping every phrase `test_review_gate_claims.sh:8-12` and `:52-58` and `test_spec_lifecycle.sh`'s constitution checks require; then `review-gate.md`, `RUBRIC.md`, `SKILL.md` step 7, the PR template, the schema template, the glossary, the threat-model phrase and the spec's `amended:` entry. No script, workflow or skill mode other than step 7 changes. `test_reviews_use_slugs.sh` and `test_verifier_skill_citations.sh` stay green (every cited slug exists).
- [x] **Step AB-4: Run** the six tests, `test_constitution_articles.sh`, `test_reviews_use_slugs.sh`, `test_verifier_skill_modes.sh`, `test_verifier_skill_citations.sh`, `test_release_commands.sh`, `test_plan_template.sh`, then `bash scripts/check-covers.sh` (now PASS: REQ-343 is cited) and the gates — green, in under 3 minutes.
- [x] **Step AB-5: Commit** — "constitution: amendment B — both paths and squash merges in art-branch-as-state, art-review-gate's Dependabot rule, admin bypass and solo sign-off, the lanes back-edge and the informational 0.0 row, 'tag missing' after the merge, retrospectives on either release PR; the interim readings retired (REQ-343, REQ-340)"
- [x] **Step AB-6: The PLAN PR.** Push `phase/plan-factory-v3-2-p5` and open the PR to `main` (`--body-file "$(mktemp)"`). The body states: this is **constitution amendment PR B** (REQ-343) as well as P5's PLAN PR; the plan, the model and its test (R1), amendment B (R2), each with its commit; R3's staged claims (REQ-342, 345 and 393 join `implements:` on the IMPLEMENT branch); the measurement table's disposition in one line per group; "amendment B weakens no control" with the reason; a checkbox **"Solo sign-off (REQ-314, REQ-343): I accept solo mode's zero required approvals — the verifier's APPROVE, not a person, is the second review in solo mode"** for the maintainer to tick before merging; that `prompt_sha256` on `main` moves when this PR merges (step 7 of `SKILL.md`), so open PRs then need their verifier run again; the verify-dafny note (R1, R12); the attribution footer. `impl/plan-5-orchestrator` is then cut from this branch's head.

---

## IMPLEMENT tasks (on `impl/plan-5-orchestrator`, cut from this branch after amendment B)

### Task 1: The governance harness stops the EXIT-trap flake — git's automatic maintenance off, `rm_tree` in every trap (H10; REQ-306, REQ-360)

**Files:** `tests/governance/lib/check.sh` (exports and `rm_tree`), `tests/governance/test_check_harness.sh` (checks above `finish`), and every `tests/governance/test_*.sh` whose EXIT trap runs `rm -rf` (27 files today; `grep -lE "trap +'rm -rf" tests/governance/test_*.sh`).

**Interfaces:** `check.sh` exports `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` setting `gc.auto=0` and `maintenance.auto=false` (appending after any count already exported), so no git a test runs starts a detached `git maintenance run --auto` that writes into the temp repository after the last check. `rm_tree DIR` runs `rm -rf DIR` up to `${RM_TREE_TRIES:-5}` times, one second apart, and returns 0 whatever happens (on the last failure it prints `note: rm_tree could not remove DIR` to stderr). Every `trap 'rm -rf "$X"' EXIT` becomes `trap 'rm_tree "$X"' EXIT`. Test-only: no file under `scripts/`, `stacks/`, `.claude/`, `.github/` changes.

- [x] **Step 1: Write the failing test.** Append to `tests/governance/test_check_harness.sh`, above `finish`, and change its own trap to `rm_tree`:

```bash
# H10 (REQ-360, REQ-306): an EXIT trap never fails a test after "all checks passed". git's automatic gc and maintenance
# are off for every git a governance test runs (a detached `git maintenance run --auto` still writing into a temp
# repository made rm -rf meet "Directory not empty" on macOS), and rm_tree retries, then never fails.
# Covers: REQ-360
ck "check.sh turns git's automatic gc and maintenance off for every test (GIT_CONFIG_COUNT)" bash -c \
  'source "$1" >/dev/null; [ "$(git config --get gc.auto)" = 0 ] && [ "$(git config --get maintenance.auto)" = false ]' _ "$H"
ST="$W/stuck"; mkdir -p "$ST/locked"; : > "$ST/locked/f"; chmod 500 "$ST/locked"
mk trap_stuck 'set -e; trap "rm_tree \"$STUCK\"" EXIT; ck "a" true; finish stuck'
out=$(STUCK="$ST" RM_TREE_TRIES=2 bash "$W/trap_stuck" 2>&1); rc=$?
chmod 700 "$ST/locked"
ck "a passing test whose EXIT trap cannot remove its temp tree still exits 0 (rm_tree never fails, even under set -e)" \
  bash -c '[ "$1" = 0 ] && grep -q "all checks passed" <<<"$2"' _ "$rc" "$out"
ck "every governance test's EXIT trap removes its temp tree with rm_tree, never a bare rm -rf" python3 - "$ROOT/tests/governance" <<'PY'
import glob, os, re, sys
bad = [f"{os.path.basename(p)}:{i}" for p in sorted(glob.glob(os.path.join(sys.argv[1], "test_*.sh")))
       for i, line in enumerate(open(p), 1) if re.search(r"trap\s+'rm -rf", line)]
assert not bad, bad
PY
```

- [x] **Step 2: Run** `PATH="$HOME/.venvs/factory-tools/bin:$PATH" bash tests/governance/test_check_harness.sh`. Expected: the three new checks FAIL (no exports, no `rm_tree`: the stuck trap's `rm -rf` exits 1 under `set -e`, and 27 traps use `rm -rf`). Exit 1.
- [x] **Step 3: Implement (intent).** The exports and `rm_tree` in `check.sh`; each trap rewritten (a test that defines its trap before sourcing `check.sh` sources it first). No check changes meaning.
- [x] **Step 4: Run** the test, then `test_examples.sh` five times in a row and the gates twice — green each time (record the gates' time; about 1:30).
- [x] **Step 5: Commit** — "test(governance): git maintenance off and rm_tree in every EXIT trap — test_examples.sh's macOS flake (REQ-360, REQ-306)"

---

### Task 2: The state kernel — `records.py`'s state records and `state.py`'s `derive`, the twin of the Dafny model, with fixtures that mirror it (REQ-341, REQ-385, REQ-340)

**Files:** modify `scripts/lib/specflow/records.py` (the state records and JSON helpers; its docstring's "what a running instance persists" sentence); create `scripts/lib/specflow/state.py`, `tests/governance/fixtures/state/01-…json` to `76-…json` (Interfaces "Kernel fixtures"), `tests/governance/test_state_kernel.sh`.

**Interfaces:** "Records", "The kernel", "The Dafny model", "Kernel fixtures"; R5, R6.

- [x] **Step 1: Write the failing test** — `tests/governance/test_state_kernel.sh`:

```bash
#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R5, R6): derive() is a pure, total function over the parsed branch, the branch's newest PR, the
# open lane PRs, the Facts record, the path and solo — exactly one Result for every input satisfying pre(), ValueError
# outside it. It is the twin of verification/factory_v3_2/state.dfy (one function per model function, the model's names
# in snake_case), and the fixtures mirror the model: one per state-table row, precedence rule and theorem, the factory's
# own mixed history, and the model's FixtureNN lemmas. A generated truth table over every Branch constructor x PR state
# x attestation x path x solo x human approval x three open-lane-PR sets x eight fact sets (main's tag, next-build,
# ready-to-ship and each regulated ship proposal reached) checks the theorems' twins. REQ-385: no Merge step
# without an open PR's APPROVE or waiver and, in team mode, a human approval. REQ-340: both paths' constructors, path
# closure of every proposal.
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; K="$LIB/state.py"; FX="$ROOT/tests/governance/fixtures/state"
DFY="$ROOT/verification/factory_v3_2/state.dfy"
ck "records.py and state.py exist" test -f "$LIB/records.py" -a -f "$K"
for f in pre numbers_of own_numbers min_of lane_of lane_list first_missing_after_last_present lane_phase phase_step \
         impl_target_of pr_substate main_result regulated_ship_proposal phase_order set_fact lanes_proposal \
         regulated_proposal derive; do
  ck "the twin defines $f (the model's name, snake_case)" grep -qE "^def $f\(" "$K"
done
if [[ -f "$DFY" ]]; then   # the model ships only in the template source (P5 R11)
  ck "each FixtureNN lemma of the model has its fixture NN-*.json, which names the lemma" bash -c \
    'for n in $(grep -oE "lemma Fixture[0-9]+" "$1" | grep -oE "[0-9]+"); do f=$(ls "$2/$n-"*.json 2>/dev/null | head -1); [ -n "$f" ] && grep -qF "\"Fixture$n\"" "$f" || exit 1; done' _ "$DFY" "$FX"
fi
ck "the kernel is pure: it imports only records and typing/dataclasses/enum, and calls no I/O" python3 - "$K" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
allowed = {"__future__", "dataclasses", "enum", "typing", "records"}
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        assert {a.name.split(".")[0] for a in n.names} <= allowed, [a.name for a in n.names]
    if isinstance(n, ast.ImportFrom):
        assert (n.module or "").split(".")[0] in allowed, n.module
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
        assert n.func.id not in ("open", "print", "input", "exec", "eval", "__import__"), n.func.id
PY
n=$(find "$FX" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
ck "at least 76 kernel fixtures ($n)" [ "${n:-0}" -ge 76 ]
for k in Main Design Build BuildSec Ship Patch PhaseSpec PhaseArch PhasePlan Impl ImplSec PhaseValidate PhaseSecurity PhaseRelease Unknown; do
  ck "some fixture's branch is $k" bash -c 'grep -lE "\"kind\": \"$1\"" "$2"/*.json 2>/dev/null | grep -q .' _ "$k" "$FX"
done
REPORT="$(mktemp)"
python3 - "$LIB" "$FX" > "$REPORT" <<'PY'
import glob, itertools, json, os, sys
sys.path.insert(0, sys.argv[1])
import records as R, state as S
bad = []
def run(fx):
    try:
        r = S.derive(R.branch_from_json(fx["branch"]), R.pr_from_json(fx["branch_pr"]) if fx["branch_pr"] else None,
                     tuple(R.pr_from_json(p) for p in fx["open_lane_prs"]), R.facts_from_json(fx["facts"]),
                     R.Path(fx["path"]), fx["solo"])
        return R.result_to_json(r)
    except ValueError:
        return {"error": "ValueError"}
for p in sorted(glob.glob(os.path.join(sys.argv[2], "*.json"))):
    fx = json.load(open(p)); got = run(fx)
    if got != fx["expect"]:
        bad.append(f"{os.path.basename(p)}: got {got}, want {fx['expect']}")
    if run(fx) != got:
        bad.append(f"{os.path.basename(p)}: not deterministic")
K = R.BranchKind
B = [R.Branch(K.Main), R.Branch(K.Design, slug="a"), R.Branch(K.Build, slug="a", n=1), R.Branch(K.Build, slug="a", n=3),
     R.Branch(K.BuildSec, id="SEC-004"), R.Branch(K.Ship, version="0.2.0"), R.Branch(K.Patch, slug="a"),
     R.Branch(K.PhaseSpec, slug="a"), R.Branch(K.PhaseArch, slug="a"), R.Branch(K.PhasePlan, slug="a"),
     R.Branch(K.Impl, plan="1a", name="a"), R.Branch(K.ImplSec, id="SEC-004"), R.Branch(K.PhaseValidate),
     R.Branch(K.PhaseSecurity), R.Branch(K.PhaseRelease), R.Branch(K.Unknown)]
def facts(**kw):
    base = dict(has_brainstorm=False, has_spec=False, spec_has_tagged_reqs=False, arch_complete=False, has_plan=False,
                build_sections=frozenset({1}), analyze_ok=False, has_source_diff=False, gates_pass=False,
                has_security_docs=False, has_release_docs=False, signing_key_present=False, pr_state_known=True,
                unbuilt=(), untagged_ship=None, next_version=None, ship_phases_merged=frozenset())
    base.update(kw)
    return R.Facts(**base)
RS = R.RegShip
F = [facts(), facts(pr_state_known=False),
     facts(has_brainstorm=True, has_spec=True, spec_has_tagged_reqs=True, has_plan=True),
     facts(has_brainstorm=True, has_spec=True, has_plan=True, analyze_ok=True, has_source_diff=True, gates_pass=True,
           has_security_docs=True, has_release_docs=True, unbuilt=(("a", 2),), next_version="0.2.0"),
     facts(untagged_ship="0.1.0", next_version="0.2.0"),                          # main: tag
     facts(next_version="0.2.0"),                                                 # main: ready-to-ship, validate
     facts(next_version="0.2.0", ship_phases_merged=frozenset({RS.validate})),    # … security
     facts(next_version="0.2.0", ship_phases_merged=frozenset({RS.validate, RS.security}))]  # … release
SUB = {"request_changes": "blocked", "none": "awaiting-verifier"}
OWN12 = R.PR(12, True, False, False, False, R.Attestation.none, True)
OWN15 = R.PR(15, True, False, False, False, R.Attestation.none, True)
OTHER9 = R.PR(9, True, False, False, False, R.Attestation.none, False)
OLP = [(), (OTHER9,), (OWN15, OTHER9, OWN12)]   # none; another user's only; two own PRs and a lower foreign one
rows = 0
seen = set()
for b, f, path, solo, human, att, st, olp in itertools.product(B, F, list(R.Path), (True, False), (True, False),
                                                              list(R.Attestation), ("none", "open", "merged", "closed"), OLP):
    pr = None if st == "none" else R.PR(7, st == "open", st == "merged", st == "closed", human, att, True)
    args = (b, pr, olp, f, path, solo)
    if not S.pre(*args):
        try:
            S.derive(*args); bad.append(f"no ValueError outside pre: {args}")
        except ValueError:
            pass
        continue
    r = S.derive(*args); rows += 1; k = r.step.kind.value
    seen.add((b.kind.value, r.phase.value, k, r.step.proposal.kind.value if r.step.proposal else ""))
    lane_branch = b.kind not in (K.Main, K.Unknown)
    if k == "Merge" and not (pr and pr.open and pr.attestation in (R.Attestation.approve, R.Attestation.waiver)
                             and r.step.pr == pr.number and (solo or pr.human_approved) and lane_branch):
        bad.append(f"MergeOnlyWhenApproved: {args} -> {r}")
    if not f.pr_state_known and k == "CreatePr":
        bad.append(f"NoBlindCreatePr: {args} -> {r}")
    if k == "NewBranch" and not (S.lanes_proposal(r.step.proposal) if path is R.Path.lanes else S.regulated_proposal(r.step.proposal)):
        bad.append(f"PathClosure: {args} -> {r}")
    if b.kind is K.Unknown and (r.phase.value, k) != ("unknown-branch", "ExplainUnknown"):
        bad.append(f"UnknownBranchNeverMerges: {args} -> {r}")
    if pr and pr.open and lane_branch:
        want = SUB.get(att.value) or ("awaiting-merge" if solo or human else "awaiting-human-review")
        if r.phase.value != want or r.lane is not S.lane_of(b):
            bad.append(f"PrPrecedence: {args} -> {r}")
    if pr is None and lane_branch and S.phase_order(r.phase) < 9:
        g = S.set_fact(f, r.phase)
        new = S.derive(b, None, olp, g, path, solo) if S.pre(b, None, olp, g, path, solo) else None
        if new is None or not (S.phase_order(r.phase) < S.phase_order(new.phase) <= 9) or new.lane is not S.lane_of(b):
            bad.append(f"Progress (forward, in the lane's order): {args} -> {r} -> {new}")
    own = [p.number for p in olp if p.mine]
    if b.kind is K.Main and k == "Checkout" and (not own or r.step.pr != min(own)):
        bad.append(f"MainChecksOutLowestOwn: main checks out the lowest own PR, never another user's: {args} -> {r}")
    if b.kind is K.Main and not own and (k == "Checkout" or r.phase.value == "awaiting-merge"):
        bad.append(f"OtherUsersPrsNeverBlock: {args} -> {r}")
    if b.kind is K.Main and k == "TagRelease" and r.lane is not (R.Lane.ship if path is R.Path.lanes else R.Lane.release):
        bad.append(f"main's tag step is in the path's ship lane: {args} -> {r}")
    if r.open_lanes != tuple(sorted(p.number for p in olp)):
        bad.append(f"open_lanes: {r}")
if rows < 40000:
    bad.append(f"only {rows} truth-table rows satisfied pre")
for want in (("Main", "tag", "TagRelease", ""), ("Main", "next-build", "NewBranch", "ProposeBuild"),
             ("Main", "next-build", "NewBranch", "ProposeImpl"), ("Main", "ready-to-ship", "NewBranch", "ProposeShip"),
             ("Main", "ready-to-ship", "NewBranch", "ProposeValidate"), ("Main", "ready-to-ship", "NewBranch", "ProposeSecurity"),
             ("Main", "ready-to-ship", "NewBranch", "ProposeRelease"), ("Main", "awaiting-merge", "Checkout", ""),
             ("Main", "idle", "NewBranch", "ProposeDesign"), ("Main", "idle", "NewBranch", "ProposeSpec")):
    if want not in seen:
        bad.append(f"the truth table never reaches {want}: the PathClosure and main twins are not exercised there")
print("\n".join(bad))
PY
ck "every fixture's Result matches and repeats; the truth table satisfies the five theorems' twins" [ ! -s "$REPORT" ]
if [ -s "$REPORT" ]; then head -20 "$REPORT"; fi
rm -f "$REPORT"
finish test_state_kernel
```

- [x] **Step 2: Run** `bash tests/governance/test_state_kernel.sh`. Expected: `records.py` exists, the twin, purity, count, per-constructor and fixture checks FAIL (no `state.py`, no fixtures); the `FixtureNN` pairing FAILs (the model is on the base branch, its fixtures are not). Exit 1.
- [x] **Step 3: Implement (intent).** The records and JSON helpers per Interfaces (frozen dataclasses, string-valued enums; the P3 records unchanged). `state.py`: one function per model function; `derive` checks `pre` first and raises `ValueError` naming the violated clause, then follows the seven steps of Interfaces "The kernel" in order. Write the 76 fixtures, each expected Result derived by hand from ADR-003's tables with R5 and R6 and its `about` naming the table row, precedence rule or theorem it mirrors; fixtures 01, 02, 04, 09, 20, 22, 24, 30, 41, 42 and 62 transcribe their `FixtureNN` lemma's inputs and Result. Fixtures 64–68 use the factory's own branch names (`branch_name`), with the kinds `parse_branch` will give them in Task 3. No edit to `verification/` (if the model and the twin disagree, stop: the fix is one commit changing the model, the twin and the fixtures together, verified under both Dafny versions).
- [x] **Step 4: Run** the test (about 5 s: the truth table has about 41 500 rows that satisfy `pre`; if it passes 10 s, stop and report rather than thin the table), `test_state_model.sh`, and the gates — green.
- [x] **Step 5: Commit** — "feat(next): the state kernel — records.py's state records and state.py's derive, the Python twin of state.dfy, with 76 fixtures and a generated truth table (REQ-341, REQ-385, REQ-340)"

---

### Task 3: The wrapper's pure layer — `parse_branch`, `render_step`, the confirmation points and glossary links (REQ-341, REQ-385, REQ-340, REQ-308)

**Files:** create `scripts/lib/specflow/pipeline.py` (the pure functions and the `parse-branch` subcommand; `derive`'s CLI arrives in Task 5), `tests/governance/test_next_render.sh`; modify `docs/GLOSSARY.md` (new `### /next`, `### Awaiting verifier`, `### Confirmation point`, `### Derive`, `### Facts`, in alphabetical place).

**Interfaces:** "The wrapper" (`parse_branch`, `RenderCtx`, `render_step`, `confirmation_point`, `GLOSSARY_TERMS`, `terms_for`); R5, R8. Glossary entries: **/next** — the command that derives where the pipeline is from branches, PRs and files and prints (engineer) or runs (guided) the next step; it never runs the verifier or merges without a confirmation. **Awaiting verifier** — an open PR with no accepted verifier marker for its head; `/next` prints the second-terminal command. **Confirmation point** — one of the seven moments the guided profile pauses (brainstorm end, design PR, build PR, ship PR, awaiting verifier, merge, unsigned tag). **Derive** — computing the pipeline's state from branches, PRs and the tree, never stored (`art-branch-as-state`; `scripts/lib/specflow/state.py`, proved in the template source). **Facts** — the small values `/next` reads from the tree for the derivation (which artifacts exist, whether the gates passed, which builds merged).

- [x] **Step 1: Write the failing test** — `tests/governance/test_next_render.sh`:

```bash
#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R5, R8): parse_branch is total over both paths' names — build/sec-<id> before the build split,
# build/<slug>-N on the last '-', impl/plan-<token>-<name> with the factory's 1a/1b tokens, legacy phase/spec, retro and
# foreign prefixes Unknown — and every kernel fixture's branch_name parses to its branch. REQ-385: the awaiting-verifier
# step renders the complete second-terminal instruction in the base-ref form, verbatim, and warns when the base is not
# main (P5 R22); blocked never renders a merge, and a merge with a PR stacked on the branch keeps a merge commit.
# REQ-340: both paths' proposals render to branch names that parse back. REQ-342's confirmation points are pure
# functions of the Result's lane and phase (never its step), the facts and the profile. REQ-308: every glossary term /next prints links to a real heading.
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-340
# Covers: REQ-308
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; P="$LIB/pipeline.py"; FX="$ROOT/tests/governance/fixtures/state"
ck "pipeline.py exists" test -f "$P"
ck "parse-branch prints Branch JSON" bash -c 'python3 "$1" parse-branch build/sec-SEC-004 | grep -qF "\"BuildSec\""' _ "$P"
REPORT="$(mktemp)"
python3 - "$LIB" "$FX" "$ROOT/docs/GLOSSARY.md" > "$REPORT" <<'PY'
import dataclasses, glob, json, os, re, sys
sys.path.insert(0, sys.argv[1])
import records as R, pipeline as P
bad = []
TABLE = """main|{"kind": "Main"}
design/habit-tracker|{"kind": "Design", "slug": "habit-tracker"}
build/habit-tracker-2|{"kind": "Build", "slug": "habit-tracker", "n": 2}
build/a-b-10|{"kind": "Build", "slug": "a-b", "n": 10}
build/sec-SEC-004|{"kind": "BuildSec", "id": "SEC-004"}
build/sec-4|{"kind": "BuildSec", "id": "4"}
build/habit-tracker|{"kind": "Unknown"}
build/habit-tracker-0|{"kind": "Unknown"}
ship/0.2.0|{"kind": "Ship", "version": "0.2.0"}
ship/1.0.0-rc.1|{"kind": "Ship", "version": "1.0.0-rc.1"}
ship/v1.0.0|{"kind": "Unknown"}
patch/first-run-argmax|{"kind": "Patch", "slug": "first-run-argmax"}
phase/spec-factory-v3-2|{"kind": "PhaseSpec", "slug": "factory-v3-2"}
phase/spec-v3.1|{"kind": "PhaseSpec", "slug": "v3.1"}
phase/arch-factory-v3-2-fixes|{"kind": "PhaseArch", "slug": "factory-v3-2-fixes"}
phase/plan-factory-v3-2-p5|{"kind": "PhasePlan", "slug": "factory-v3-2-p5"}
impl/plan-5-orchestrator|{"kind": "Impl", "plan": "5", "name": "orchestrator"}
impl/plan-1a-first-run|{"kind": "Impl", "plan": "1a", "name": "first-run"}
impl/plan-0-plan-scoping|{"kind": "Impl", "plan": "0", "name": "plan-scoping"}
impl/sec-SEC-004|{"kind": "ImplSec", "id": "SEC-004"}
phase/validate|{"kind": "PhaseValidate"}
phase/security|{"kind": "PhaseSecurity"}
phase/release|{"kind": "PhaseRelease"}
phase/spec|{"kind": "Unknown"}
phase/retro-2026-06-09|{"kind": "Unknown"}
impl/fix-p0-ci-enforcement|{"kind": "Unknown"}
impl/p1-adoption-path|{"kind": "Unknown"}
chore/template-cleanup|{"kind": "Unknown"}
diag/first-run-floor|{"kind": "Unknown"}
dependabot/pip/scripts/ruff-0.16.8|{"kind": "Unknown"}
design/|{"kind": "Unknown"}
design/a/b|{"kind": "Unknown"}
HEAD|{"kind": "Unknown"}"""
for row in TABLE.splitlines():
    name, want = row.split("|", 1)
    got = R.branch_to_json(P.parse_branch(name))
    if got != json.loads(want):
        bad.append(f"parse_branch({name!r}) = {got}, want {want}")
for p in sorted(glob.glob(os.path.join(sys.argv[2], "*.json"))):
    fx = json.load(open(p))
    if "branch_name" in fx and R.branch_to_json(P.parse_branch(fx["branch_name"])) != fx["branch"]:
        bad.append(f"{os.path.basename(p)}: branch_name {fx['branch_name']!r} does not parse to its branch")
ctx = P.RenderCtx(repo="/work/my repo", branch="design/habit", base="main", slug="habit", version="0.2.0",
                  plan_path="docs/plans/2026-09-28-habit-plan.md", spec_slug="2026-09-28-habit")
St, SK = R.Step, R.StepKind
want = ("In a second terminal, not inside Claude — open a new terminal window (Terminal.app or your shell) and run: "
        "cd '/work/my repo' && git show origin/main:scripts/run-verifier.sh | bash -s -- 7; "
        "when it prints \"Findings posted to PR #7\", return here and run /next.")
if P.render_step(St(SK.RunVerifier, pr=7), ctx) != want:
    bad.append("RunVerifier does not render REQ-385's instruction verbatim: " + P.render_step(St(SK.RunVerifier, pr=7), ctx))
stacked = dataclasses.replace(ctx, repo="/w", base="phase/plan-factory-v3-2-p5")
sv = P.render_step(St(SK.RunVerifier, pr=47), stacked)
if "git show origin/phase/plan-factory-v3-2-p5:scripts/run-verifier.sh | bash -s -- 47" not in sv:
    bad.append("RunVerifier does not use the PR's own base (a stacked PR)")
if "Warning: origin/phase/plan-factory-v3-2-p5 is not main" not in sv or "\n" in sv:
    bad.append("RunVerifier on a stacked PR does not warn, on the same line, that the script comes from an unreviewed branch (P5 R22)")
if P.render_step(St(SK.Merge, pr=12), ctx) != "gh pr merge 12 --squash":
    bad.append("Merge does not render 'gh pr merge 12 --squash'")
sm = P.render_step(St(SK.Merge, pr=12), dataclasses.replace(ctx, stacked=(47,)))
if not sm.startswith("gh pr merge 12 --merge") or "gh pr edit 47 --base main" not in sm or "--squash" in sm:
    bad.append(f"Merge with PR #47 stacked on the branch renders {sm!r}, not a merge commit and the retarget (P5 R22)")
if "gh pr merge" in P.render_step(St(SK.AddressFindings, pr=12), ctx):
    bad.append("AddressFindings renders a merge command")
PK, Pr = R.ProposalKind, R.Proposal
props = {PK.ProposeDesign: ("git checkout -b design/<slug>", "Design"), PK.ProposeSpec: ("git checkout -b phase/spec-<slug>", "PhaseSpec"),
         PK.ProposeValidate: ("git checkout -b phase/validate", "PhaseValidate"),
         PK.ProposeSecurity: ("git checkout -b phase/security", "PhaseSecurity"),
         PK.ProposeRelease: ("git checkout -b phase/release", "PhaseRelease")}
for kind, (text, parsed) in props.items():
    out = P.render_step(St(SK.NewBranch, proposal=Pr(kind)), ctx)
    if text not in out:
        bad.append(f"{kind.value} renders {out!r}, lacking {text!r}")
    name = out.split("git checkout -b ", 1)[1].split()[0].replace("<slug>", "x")
    if R.branch_to_json(P.parse_branch(name))["kind"] != parsed:
        bad.append(f"{kind.value}'s branch {name} does not parse to {parsed}")
for kind in (PK.ProposeDesign, PK.ProposeSpec):
    if "/superpowers:brainstorming" not in P.render_step(St(SK.NewBranch, proposal=Pr(kind)), ctx):
        bad.append(f"{kind.value} does not follow the branch with brainstorming (ADR-003; P5 R4)")
for pr, text, parsed in ((Pr(PK.ProposeBuild, slug="habit", n=2), "git checkout -b build/habit-2", "Build"),
                         (Pr(PK.ProposeImpl, slug="habit", n=2), "git checkout -b impl/plan-2-habit", "Impl"),
                         (Pr(PK.ProposeShip, version="0.2.0"), "git checkout -b ship/0.2.0", "Ship")):
    out = P.render_step(St(SK.NewBranch, proposal=pr), ctx)
    if text not in out or R.branch_to_json(P.parse_branch(text.split()[-1]))["kind"] != parsed:
        bad.append(f"{pr} renders {out!r}")
for k in SK:
    step = St(k, pr=7, proposal=Pr(PK.ProposeDesign), target=R.ImplTarget(R.TargetKind.Section, n=1), version="0.2.0",
              why=R.Why.BranchUnknown)
    if not P.render_step(step, ctx).strip():
        bad.append(f"{k.value} renders nothing")
retro = dataclasses.replace(ctx, branch="phase/retro-2026-06-09")
if "/retrospective" not in P.render_step(St(SK.ExplainUnknown, why=R.Why.BranchUnknown), retro):
    bad.append("a retrospective branch is not explained as one (P5 R8)")
if "gh auth status" not in P.render_step(St(SK.ExplainUnknown, why=R.Why.PrStateUnknown), ctx):
    bad.append("PrStateUnknown does not say how to restore PR state")
L, Ph = R.Lane, R.Phase
def res(lane, phase, step):
    return R.Result(L(lane), Ph(phase), step, ())
F0 = R.facts_from_json({})
FS = R.facts_from_json({"signing_key_present": True})
cases = [(res("design", "specify", St(SK.RunSpecify)), F0, "brainstorm-end"),
         (res("design", "open-pr", St(SK.CreatePr)), F0, "design-pr"),
         (res("design", "open-pr", St(SK.ExplainUnknown, why=R.Why.PrStateUnknown)), F0, "design-pr"),
         (res("build", "open-pr", St(SK.ExplainUnknown, why=R.Why.PrStateUnknown)), F0, "build-pr"),
         (res("ship", "open-pr", St(SK.ExplainUnknown, why=R.Why.PrStateUnknown)), F0, "ship-pr"),
         (res("spec", "open-pr", St(SK.CreatePr)), F0, "design-pr"),
         (res("plan", "open-pr", St(SK.CreatePr)), F0, "design-pr"),
         (res("build", "open-pr", St(SK.CreatePr)), F0, "build-pr"),
         (res("impl", "open-pr", St(SK.CreatePr)), F0, "build-pr"),
         (res("validate", "open-pr", St(SK.CreatePr)), F0, "build-pr"),
         (res("ship", "open-pr", St(SK.CreatePr)), F0, "ship-pr"),
         (res("release", "open-pr", St(SK.CreatePr)), F0, "ship-pr"),
         (res("build", "awaiting-verifier", St(SK.RunVerifier, pr=7)), F0, "awaiting-verifier"),
         (res("build", "awaiting-merge", St(SK.Merge, pr=7)), F0, "merge"),
         (res("ship", "tag", St(SK.TagRelease, version="0.2.0")), F0, "unsigned-tag"),
         (res("ship", "tag", St(SK.TagRelease, version="0.2.0")), FS, None),
         (res("build", "implement", St(SK.RunImplement, target=R.ImplTarget(R.TargetKind.Section, n=1))), F0, None)]
for result, facts, want in cases:
    if P.confirmation_point(result, facts, "guided") != want:
        bad.append(f"guided confirmation_point({result.lane.value}, {result.phase.value}) = "
                   f"{P.confirmation_point(result, facts, 'guided')}, want {want}")
    if P.confirmation_point(result, facts, "engineer") is not None:
        bad.append(f"engineer profile pauses at {result.phase.value}")
anchors = set()
for line in open(sys.argv[3]):
    if line.startswith("### "):
        anchors.add(re.sub(r"[^a-z0-9 -]", "", line[4:].strip().lower()).replace(" ", "-"))
for term, anchor in P.GLOSSARY_TERMS:
    if anchor not in anchors:
        bad.append(f"glossary term {term!r} links #{anchor}, which docs/GLOSSARY.md has no heading for")
for need in ("/next", "Awaiting verifier", "Confirmation point", "Derive", "Facts"):
    if need not in dict(P.GLOSSARY_TERMS):
        bad.append(f"GLOSSARY_TERMS lacks {need}")
t = P.terms_for(res("design", "awaiting-verifier", St(SK.RunVerifier, pr=7)))
if len(t) != len(set(t)):
    bad.append("terms_for repeats a term (REQ-308: linked on first use, once)")
print("\n".join(bad))
PY
ck "parse_branch, render_step, confirmation_point and the glossary links behave as Interfaces 'The wrapper' says" [ ! -s "$REPORT" ]
if [ -s "$REPORT" ]; then head -20 "$REPORT"; fi
rm -f "$REPORT"
finish test_next_render
```

- [x] **Step 2: Run** `bash tests/governance/test_next_render.sh`. Expected: every check FAILs (no `pipeline.py`). Exit 1.
- [x] **Step 3: Implement (intent).** `pipeline.py`'s pure functions per Interfaces, with the version grammar copied from `disposition_gate.VERSION_RE` (no import of the gate module); the `parse-branch` subcommand; the five glossary entries. No I/O in these functions.
- [x] **Step 4: Run** the test (about 1 s), `test_state_kernel.sh`, `test_onboarding_surface.sh` (the glossary's term count), and the gates — green.
- [x] **Step 5: Commit** — "feat(next): pipeline.py's pure layer — parse_branch over both paths and the factory's history, render_step with the second-terminal verifier instruction, the guided confirmation points, glossary links (REQ-341, REQ-385, REQ-340, REQ-308)"

---

### Task 4: `attestation.py` shared with `next.sh` — `pr_attestation`, the repository role for a `MEMBER`'s waiver, npm lockfiles that may not grow (R9, R10; REQ-311, REQ-382, REQ-334)

**Files:** `scripts/lib/specflow/attestation.py` (header `:9`, `_package_lock_rule` `:608-660`, `_WAIVER_TRUSTED` `:1022` and the waiver branch `:1078-1089`, `classify` `:1132`, `check` `:1314-1440`, CLI); `tests/governance/fixtures/attestation/72-…json` to `81-…json`, and the existing fixtures whose accepted waiver comes from a `MEMBER` (18, and any other `grep -l '"MEMBER"'` shows with `"state": "waiver"`); `tests/governance/lib/check.sh` (`stub_bin`'s `gh` answers `repos/<repo>/collaborators/<login>/permission` from `$STUB_DIR/permission.json`, else HTTP 404); `tests/governance/test_attestation.sh` (`:4`, `:159`, the fixture list and count, checks above `finish`); `.claude/rules/review-gate.md:62` (waiver row) and `:64` (Dependabot row: the npm growth rule); `docs/GLOSSARY.md:316` (Waiver) and the Dependabot entry; `README.md`'s `MEMBER` paragraph; `tests/governance/test_review_gate_claims.sh:114-115`.

**Interfaces:** "Classifier additions"; R9, R10. The claim row says: a `MEMBER`'s waiver counts only when the commenter's repository role is admin, maintain or write (on an organisation repository the maintainers themselves are `MEMBER` — this repository's included — so their waivers take the lookup too) (read at check time with `gh api repos/<repo>/collaborators/<login>/permission`; an unreadable role fails closed, so a token that cannot read it rejects `MEMBER` waivers and leaves `OWNER` waivers working); a `MEMBER`'s or `COLLABORATOR`'s marker (`APPROVE` or `REQUEST_CHANGES`) needs the same writing role (rule 1b, R9 as shipped): an unreadable role is never accepted and keeps blocking, a known `read`, `triage` or `none` role neither accepts nor blocks — in team mode the human approval is the control, in solo mode a marker is self-attested (REQ-314). The Dependabot row gains: an npm lockfile gains no `node_modules/` entry and no name in any entry's dependency maps.

- [x] **Step 1: Write the failing test.** In `tests/governance/test_attestation.sh`, change `:4` and `:159`'s "P5's next.sh must pass these files unchanged" to "next.sh classifies through the same pr_attestation()", raise `:171`'s count to 81, and append above `finish`:

```bash
# P5 (REQ-382 as amended, R9; REQ-334, R10; REQ-311): a MEMBER's waiver counts only with a writing repository role, an
# npm lockfile may not grow, and pr_attestation() is the one entry point the CI check and next.sh share.
# Covers: REQ-382
# Covers: REQ-334
# Covers: REQ-311
for r in waiver-member-write waiver-member-maintain waiver-member-read-rejected waiver-member-triage-rejected \
         waiver-member-permission-unknown waiver-owner-no-lookup dependabot-npm-lockfile-new-entry \
         dependabot-npm-lockfile-dependency-added dependabot-npm-lockfile-range-moves dependabot-npm-lockfile-entry-removed; do
  ck "fixture for $r" bash -c 'ls "$1"/*-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
ck "every fixture whose accepted waiver comes from a MEMBER names that member's role in its context" python3 - "$FX" <<'PY'
import glob, json, os, sys
for p in glob.glob(os.path.join(sys.argv[1], "*.json")):
    d = json.load(open(p))
    if d["expect"].get("state") != "waiver":
        continue
    c = next(c for c in d["comments"] if c["id"] == d["expect"]["comment_id"])
    if c["author_association"] == "MEMBER":
        assert c["user"]["login"] in (d["context"].get("permissions") or {}), os.path.basename(p)
PY
ck "check() classifies only through pr_attestation(), which calls classify()" python3 - "$A" <<'PY'
import ast, sys
t = ast.parse(open(sys.argv[1]).read())
fn = {n.name: n for n in t.body if isinstance(n, ast.FunctionDef)}
calls = lambda f: {c.func.id for c in ast.walk(fn[f]) if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)}
assert "pr_attestation" in fn and "pr_attestation" in calls("check") and "classify" in calls("pr_attestation")
assert "classify" not in calls("check")
PY
ck "verifier.yml never passes the test-only --permissions input" no grep -qF -- '--permissions' .github/workflows/verifier.yml
waiver() {  # waiver LOGIN ASSOCIATION — one waiver comment for the head, as the check reads it
  python3 -c 'import json, sys
print(json.dumps([{"id": 5, "user": {"login": sys.argv[1]}, "author_association": sys.argv[2],
  "created_at": "2026-09-28T10:00:00Z", "updated_at": "2026-09-28T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-5",
  "body": "<!-- specflow-verifier:waive sha:" + sys.argv[3] + " -->\nReviewed by hand: a maintainer-decided waiver."}]))' "$1" "$2" "$GH" > "$S/comments.json"
}
waiver bob MEMBER; echo '{"permission": "write", "role_name": "write"}' > "$S/permission.json"; chk
ck "a MEMBER with the write role: the waiver passes, after a lookup of that member's repository role" \
  bash -c '[ "$1" = 0 ] && grep -q "repos/o/r/collaborators/bob/permission" "$2"' _ "$rc" "$S/gh.argv"
echo '{"permission": "read", "role_name": "read"}' > "$S/permission.json"; chk
ck "a read-only MEMBER's waiver fails as waiver-not-writer" bash -c '[ "$1" = 1 ] && grep -q "waiver-not-writer" <<<"$2"' _ "$rc" "$out"
rm -f "$S/permission.json"; chk
ck "a MEMBER whose role cannot be read: the waiver fails closed (waiver-permission-unknown)" \
  bash -c '[ "$1" = 1 ] && grep -q "waiver-permission-unknown" <<<"$2"' _ "$rc" "$out"
echo '{"bob": "maintain"}' > "$W/perms.json"
rm -f "$S/gh.argv"; rc=0; out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$GH" \
  --base-ref "$GB" --base-name main --pr-author alice --permissions "$W/perms.json" 2>&1) || rc=$?
ck "check --permissions FILE (test-only) supplies the roles instead of gh" bash -c '[ "$1" = 0 ] && ! grep -q collaborators "$2"' _ "$rc" "$S/gh.argv"
waiver alice OWNER; chk
ck "an OWNER's waiver needs no role lookup" bash -c '[ "$1" = 0 ] && ! grep -q collaborators "$2"' _ "$rc" "$S/gh.argv"
rg=.claude/rules/review-gate.md
wrow=$(grep -F '| Waivers need a maintainer' "$rg" || true)
ck "review-gate.md's waiver row: a MEMBER needs the admin, maintain or write role; unreadable fails closed; no 'deferred to P5'" \
  bash -c 'grep -qF "admin, maintain or write" <<<"$1" && grep -qi "fails closed" <<<"$1" && ! grep -qF "deferred to P5" <<<"$1"' _ "$wrow"
ck "the glossary's Waiver entry says the same" \
  bash -c 'w=$(awk "/^### Waiver$/{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " "); grep -qF "admin, maintain or write" <<<"$w" && ! grep -qF "deferred to P5" <<<"$w"'
ck "review-gate.md's Dependabot row: an npm lockfile gains no entry and no dependency name" \
  bash -c 'grep -F "dependabot[bot]" "$1" | grep -qF "no \`node_modules/\` entry"' _ "$rg"
```

and replace `tests/governance/test_review_gate_claims.sh:114-115` with:

```bash
ck "table: the waiver row says MEMBER is any organisation member, the maintainers included, and needs the admin, maintain or write role (R9)" \
  bash -c 'grep -qF "any organisation member" <<<"$1" && grep -qi "read-only" <<<"$1" && grep -qF "admin, maintain or write" <<<"$1" && grep -qF "the maintainers themselves are \`MEMBER\`" <<<"$1"' _ "$wrow"
```

- [x] **Step 2: Run** `bash tests/governance/test_attestation.sh` and `test_review_gate_claims.sh`. Expected: the ten fixture-name checks, the count, the `MEMBER`-role, the AST, the role-lookup and `--permissions` checks, and the three document checks FAIL; the existing fixtures still pass. Exit 1.
- [x] **Step 3: Implement (intent).** `classify(..., permissions=None)` and the waiver branch per R9 (the reasons `waiver-not-writer`, `waiver-permission-unknown`); `pr_attestation(...)` gathers what `check()` gathers today, plus each `MEMBER` waiver author's role (`gh api repos/<repo>/collaborators/<login>/permission`, `role_name`, else `permission`; any failure → no entry), and returns `classify`'s dict with `judged`, `required_mode`, `prompt_sha256` and `solo`; `check()` prints exactly today's messages from `pr_attestation`'s result, and gains `--permissions FILE`. `fixture()` passes the context's `permissions`. `_package_lock_rule` per R10 (`new-entry`, `dependency-added`). Write fixtures 72–81; add the `write` role to each existing accepted-`MEMBER`-waiver fixture (list them in the commit body). The stub `gh` case. The documents per Interfaces. The header's `:9` sentence says `next.sh` imports the module through `pr_attestation`. Before committing, one read-only live call confirms the endpoint's shape with the maintainer's token (`GH_TOKEN="$(gh auth token --user kpingali123)" gh api repos/Apps-Consultants/factory/collaborators/kpingali123/permission` — at plan time it answered `{"permission": "admin", "role_name": "admin", …}`). **The CI token's access (R9):** the IMPLEMENT PR's own `verifier` run does not exercise the lookup (`verifier.yml:69-92` materialises `attestation.py` from `origin/<base>`, which has no lookup until this PR merges), and a maintainer's waiver on this organisation repository is a `MEMBER`'s. So before the IMPLEMENT PR opens, the orchestrator — not an implementer, who never pushes — runs a draft-PR probe (the CI-diagnostics pattern): a throwaway branch `diag/member-permission` from `main` whose one added workflow, triggered by `pull_request` on that branch alone and carrying `verifier.yml`'s exact `permissions:` block, calls the endpoint for the PR author with `GITHUB_TOKEN` and prints only the HTTP status and `role_name`; the draft PR is then closed and the branch deleted, nothing merged. The IMPLEMENT PR body records the result. If the token is refused, the orchestrator stops before this task's R9 part lands and asks the maintainer (R9: fail-closed would remove the maintainer's own waiver route).
- [x] **Step 4: Run** the two tests, `test_workflow_health.sh`, `test_verifier_run.sh` (the stub `gh` change), and the gates — green.
- [x] **Step 5: Commit** — "feat(attestation): pr_attestation() shared by the check and next.sh; a MEMBER's waiver needs a writing repository role; an npm lockfile may not grow (REQ-382, REQ-334, REQ-311)"

---

### Task 5: `next.sh` — facts from the tree, the derivation, the output; remote-less (REQ-341, REQ-340)

**Files:** create `scripts/next.sh`, `tests/governance/test_next.sh`; modify `scripts/lib/specflow/pipeline.py` (the `derive` subcommand: configuration, branch, facts, output; PR state is "unknown" in this task whenever there is no remote, and Task 6 adds `gh`), `tests/governance/lib/check.sh` (`next_seed DIR`: a small repository holding what `next.sh` reads — `scripts/`, `schemas/`, `.claude/skills/verifier/`, `constitution.md` and `docs/GLOSSARY.md` from the tree, then the synthetic set `tests/governance/fixtures/next/seed/` copied over it — with `.specflow.yml` `profile: engineer`, `path: lanes`, `solo: true`, committed on `main`, no remote; Global Constraints "Instance-independent seeds"); create `tests/governance/fixtures/next/seed/` — `docs/specs/2026-09-28-greet-brainstorm.md`, `docs/specs/2026-09-28-greet-design.md` (one `[verifiable-model]` REQ, `REQ-991`), `docs/adr/991-greet-kernel.md` (accepted, `addresses: [REQ-991]`; renumbered from `REQ-001`/ADR-001 by the P5 lows patch, so no seed id is one a live document defines — the demo owns ADR-001), `docs/architecture/2026-09-28-greet-overview.md` (its `kernel_modules.req_map` names the REQ), `docs/architecture/2026-09-28-greet-threat-model.md` (the ten-domain checklist, `schemas/threat-model-template.md`'s shape), `docs/plans/2026-09-28-greet-plan.md` (`spec:`, `decisions: [ADR-991]`, `implements: [REQ-991]`, and no `## Build N` section), `verification/greet/greet.dfy` (a stub with `// Proves: REQ-991` in its first five lines; nothing in these tests runs Dafny), `src/greet/__init__.py`, `tests/greet/test_greet.py`, and `.specflow/pack.yml` (the python-shaped fields `packinfo.py` reads: `source_roots`, `test_globs`, `test_first_rules`, `non_source`). The set lives under `tests/governance/fixtures/`, which `check-traceability.sh`, `check-covers.sh`, `check-architecture.sh` and gates section 2 do not scan in the template or an instance — confirm that before committing, and stop and report if any does.

**Interfaces:** "The wrapper" (CLI), "`next.sh` output"; R6 (the build-number gap note), R7, R8. The branch is `git symbolic-ref --short -q HEAD` (a detached head is `Unknown`, rendered as such). Configuration: `config.py`'s `path`, `profile`, `solo` (a value outside the allowed set is exit 2); `--path` and `--profile` override for the run and say so in a `note:`. Facts per R7, lane-scoped. Output per Interfaces; `--json` as specified.

- [x] **Step 1: Write the failing test** — `tests/governance/test_next.sh`:

```bash
#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R7, R8): scripts/next.sh collects the Facts from the tree — the design lane's artifacts by slug,
# tagged REQs and the architecture gate, the plan's "## Build N" sections, the source diff against the base, the ship
# lane's documents by version, the gates only when asked — calls derive, and prints state, next step, notes and --explain
# reasons, or --json. It writes nothing. Without a remote it never calls gh and never proposes creating a PR
# (pr_state_known false). REQ-340: both paths' branches; --path overrides the configured path for one run; a plan's
# "## Build N" sections are numbered from 1 with no gap, and a gap is noted (P5 R6). The seed is synthetic
# (tests/governance/fixtures/next/seed/), so the test runs the same in the template source and in every instance.
# Covers: REQ-341
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
mkdir -p "$W/bin"; printf '#!/usr/bin/env bash\necho "$*" >> "%s/gh.called"; exit 1\n' "$W" > "$W/bin/gh"; chmod +x "$W/bin/gh"
SEED="$W/seed"; next_seed "$SEED"
repo() {  # repo NAME BRANCH [PATH] — a remote-less clone of the seed on BRANCH (path lanes unless given); sets D
  D="$W/$1"; git clone -q "$SEED" "$D"; git -C "$D" remote remove origin
  if [ "${3:-lanes}" != lanes ]; then
    printf 'profile: engineer\npath: %s\nsolo: true\n' "$3" > "$D/.specflow.yml"; git -C "$D" commit -qam "path $3"
  fi
  if [ "$2" != main ]; then git -C "$D" checkout -q -b "$2"; fi
}
nx() { rc=0; (cd "$D" && PATH="$W/bin:$PATH" bash scripts/next.sh "$@") > "$W/out" 2>&1 || rc=$?; }
has() { grep -qF -- "$1" "$W/out"; }
line() { grep -E "^$1: " "$W/out" || true; }
commit() { git -C "$D" add -A && git -C "$D" commit -qm "$1"; }
DS=docs/specs/2026-09-28-greet; DP=docs/plans/2026-09-28-greet-plan.md
repo main-lanes main; nx
ck "main, no remote, lanes: state none idle" has 'state: none idle'
ck "…next: design/<slug>, then brainstorming (P5 R4)" bash -c 'grep -qF "git checkout -b design/<slug>" <<<"$1" && grep -qF "/superpowers:brainstorming" <<<"$1"' _ "$(line next)"
ck "…says it cannot see PRs, proposes no PR, and never called gh" \
  bash -c 'grep -q "^note: cannot see PRs" "$1" && ! grep -qF "gh pr create" "$1" && [ ! -e "$2" ]' _ "$W/out" "$W/gh.called"
repo main-reg main regulated; nx
ck "main, no remote, regulated: idle proposes phase/spec-<slug>, then brainstorming" \
  bash -c 'grep -q "^state: none idle" "$1" && grep -F "next: " "$1" | grep -qF "git checkout -b phase/spec-<slug>"' _ "$W/out"
repo design-full design/greet; nx
ck "design lane with every artifact, no remote: open-pr, explained, never gh pr create (NoBlindCreatePr)" \
  bash -c 'grep -q "^state: design open-pr" "$1" && grep -F "next: " "$1" | grep -qF "cannot see PRs" && ! grep -qF "gh pr create" "$1"' _ "$W/out"
before=$(cd "$D" && git status --porcelain --ignored && git for-each-ref)
nx --explain
ck "next.sh writes nothing: no file, index or ref changes (--explain included)" \
  [ "$before" = "$(cd "$D" && git status --porcelain --ignored && git for-each-ref)" ]
ck "--explain gives each fact the design lane read and where it came from" \
  bash -c 'grep -q "^why: .*spec" "$1" && grep -q "^why: .*check-architecture.sh" "$1" && grep -q "^why: .*analyze" "$1"' _ "$W/out"
repo design-noplan design/greet; git -C "$D" rm -q "$DP"; commit "no plan"; nx
ck "…without the plan: design plan, /specflow-plan greet" bash -c 'grep -q "^state: design plan" "$1" && grep -qF "/specflow-plan greet" "$1"' _ "$W/out"
repo design-noov design/greet; git -C "$D" rm -q docs/architecture/2026-09-28-greet-overview.md; commit "no overview"; nx
ck "…a tagged REQ, no overview, the plan present: design architecture (a gate, REQ-320)" \
  bash -c 'grep -q "^state: design architecture" "$1" && grep -qF "/architecture 2026-09-28-greet" "$1"' _ "$W/out"
repo design-bs design/greet; git -C "$D" rm -q "$DS-design.md" "$DP"; commit "brainstorm only"; nx
ck "…the brainstorm alone: design specify" has 'state: design specify'
repo design-none design/greet; git -C "$D" rm -q "$DS-design.md" "$DS-brainstorm.md" "$DP"; commit "nothing"; nx
ck "…nothing: design brainstorm" has 'state: design brainstorm'
repo design-specfirst design/greet; git -C "$D" rm -q "$DS-brainstorm.md" "$DP"; commit "spec, no brainstorm"; nx
ck "…a spec without a brainstorm never sends the user back: design plan (after the last present)" has 'state: design plan'
repo build build/greet-1; nx
ck "build/<slug>-1 and no '## Build 1' in the plan: build unknown-build, explained" \
  bash -c 'grep -q "^state: build unknown-build" "$1" && grep -qF "## Build 1" "$1"' _ "$W/out"
printf '\n## Build 1: greet\n' >> "$D/$DP"; commit "build 1"; nx
ck "…with the section, no source change: build implement" has 'state: build implement'
echo 'X = 1' > "$D/src/greet/extra.py"; commit "source"; nx
ck "…with a source change against main: build open-pr" has 'state: build open-pr'
repo gap build/greet-2; printf '\n## Build 1: a\n\n## Build 3: c\n' >> "$D/$DP"; commit "a gap"; nx
ck "a plan with Build 1 and Build 3: build/<slug>-2 is unknown-build, and a note names the gap (REQ-340: from 1, no gap)" \
  bash -c 'grep -q "^state: build unknown-build" "$1" && grep "^note: " "$1" | grep -qF "numbered from 1 with no gap"' _ "$W/out"
repo ship ship/0.1.0; nx
ck "ship/0.1.0 without security docs: ship security, /security-review 0.1.0" \
  bash -c 'grep -q "^state: ship security" "$1" && grep -qF "/security-review 0.1.0" "$1"' _ "$W/out"
mkdir -p "$D/docs/security"; : > "$D/docs/security/0.1.0-review.md"; : > "$D/docs/security/0.1.0-disposition.md"; commit sec; nx
ck "…with them: ship release, /release 0.1.0" bash -c 'grep -q "^state: ship release" "$1" && grep -qF "/release 0.1.0" "$1"' _ "$W/out"
mkdir -p "$D/docs/releases"; for k in notes migration known-limitations; do : > "$D/docs/releases/0.1.0-$k.md"; done; commit rel; nx
ck "…with the three release docs: ship open-pr" has 'state: ship open-pr'
repo validate phase/validate regulated
printf '#!/usr/bin/env bash\nexit "${STUB_GATES_RC:-0}"\n' > "$D/scripts/run-quality-gates.sh"; commit "stub gates"; nx
ck "phase/validate without --gates: validate gates; next is next.sh --gates" \
  bash -c 'grep -q "^state: validate gates" "$1" && grep -qF "bash scripts/next.sh --gates" "$1"' _ "$W/out"
nx --gates
ck "…--gates runs the gates; green: validate open-pr" has 'state: validate open-pr'
STUB_GATES_RC=1 nx --gates
ck "…red: validate gates" has 'state: validate gates'
repo chore chore/x; nx
ck "chore/x: none unknown-branch" has 'state: none unknown-branch'
repo retro phase/retro-2026-09-28; nx
ck "a retrospective branch: unknown to the kernel, explained as /retrospective (P5 R8)" \
  bash -c 'grep -q "^state: none unknown-branch" "$1" && grep -qF "/retrospective" "$1"' _ "$W/out"
repo js build/greet-1; nx --json
ck "--json: the documented keys; pr_state_known false; null for facts the lane does not read" python3 - "$W/out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
need = {"state", "step", "next_step", "open_lanes", "open_lane_prs", "confirm", "pr_state_known", "path", "profile",
        "facts", "findings", "explain", "notes"}
assert need <= set(d), sorted(need - set(d))
assert d["state"] == {"lane": "build", "phase": "unknown-build"} and d["pr_state_known"] is False and d["open_lanes"] == []
assert d["step"] == {"kind": "ExplainUnknown", "why": "BuildUnknown"} and d["facts"]["has_security_docs"] is None
PY
repo tsrc main; git -C "$D" rm -q .specflow.yml; mkdir -p "$D/stacks/python"; echo 'stack: python' > "$D/stacks/python/pack.yml"; commit "template source"; nx
ck "the template source: the defaults apply, and a note says the factory walks regulated until P6 (P5 R8)" \
  bash -c 'grep -q "^note: template source" "$1" && grep -qF -- "--path regulated" "$1" && grep -q "^state: none idle" "$1"' _ "$W/out"
nx --path regulated
ck "--path regulated overrides the configured path for one run, and says so" \
  bash -c 'grep -qF "git checkout -b phase/spec-<slug>" "$1" && grep -qF "path regulated (--path)" "$1"' _ "$W/out"
repo badcfg main; printf 'path: sideways\n' > "$D/.specflow.yml"; nx
ck "a path that is neither lanes nor regulated: exit 2, ERROR next" bash -c '[ "$1" = 2 ] && grep -q "^ERROR next" "$2"' _ "$rc" "$W/out"
D="$W/notgit"; mkdir -p "$D/scripts"; cp -R "$ROOT/scripts/next.sh" "$ROOT/scripts/lib" "$D/scripts/"; nx
ck "outside a git repository: exit 2, ERROR next" bash -c '[ "$1" = 2 ] && grep -q "^ERROR next" "$2"' _ "$rc" "$W/out"
finish test_next
```

- [x] **Step 2: Run** `bash tests/governance/test_next.sh`. Expected: `next_seed` is undefined, then (once the helper is written) every check FAILs: no `scripts/next.sh`. Exit 1.
- [x] **Step 3: Implement (intent).** `next_seed` in `check.sh`. `scripts/next.sh` per Interfaces. `pipeline.py derive`: read the configuration; resolve the branch and the base (R7); with no `origin` remote, PR state is unknown (`pr_state_known` false, lists empty, the note) and `gh` is never called; collect the lane's facts (R7: the slug's documents; `frontmatter.tagged_reqs`; `arch_complete` only on a design or `phase/arch-` branch, running `check-architecture.sh` from the repository with its output kept for `--explain`; `analyze_ok` only when a plan exists; `packinfo` for the source diff; `--gates` runs `scripts/run-quality-gates.sh` and records its exit status); call `state.derive`; render; print per Interfaces. `ValueError` from `derive` is exit 2 (`ERROR next: derive precondition: …`: a wrapper bug, never a user state).
- [x] **Step 4: Run** the test (time it: about 15 s here; the design cases run `check-architecture.sh` and the analyze scripts), `test_next_render.sh`, `test_state_kernel.sh`, and the gates — green, under 2:30 here.
- [x] **Step 5: Commit** — "feat(next): scripts/next.sh — facts from the tree, the derivation and its output, remote-less; nothing is written (REQ-341, REQ-340)"

---

### Task 6: `next.sh` — PR state from `gh` through the shared classifier; blocked findings; the unlinked waiver; the factory's own history (REQ-341, REQ-385, REQ-382, REQ-311)

**Files:** modify `scripts/lib/specflow/pipeline.py` (PR state, merged-PR facts, findings, open lanes, R20); create `tests/governance/test_next_prs.sh`, `tests/governance/fixtures/next/factory-prs.json` (captured once, read-only: `GH_TOKEN="$(gh auth token --user kpingali123)" gh pr list --repo Apps-Consultants/factory --state all --limit 1000 --json number,headRefName,baseRefName,state,author,mergedAt,mergeCommit,reviewDecision,isDraft,headRefOid,url` filtered to PRs #1–#46, `body` set to `""`, saved as `{"source": {"command": "<that command>", "captured": "<date>", "note": "PRs #1–#46 only; bodies emptied"}, "prs": [...]}`).

**Interfaces:** "PR state"; R5–R7, R13, R20, R21, R22. With a PR, `solo` is the base's (`pr_attestation`'s policy read, as the CI check reads it, dfe-6); without one, the working tree's configuration. The blocked output's `findings:` block is the `REQUEST_CHANGES` comment's URL and its body without the marker line, at most 60 lines. `open lanes:` lists every open lane PR with its author and head, marking each that is not the current user's with the dfe-10 warning.

- [x] **Step 1: Write the failing test** — `tests/governance/test_next_prs.sh`:

```bash
#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R5–R7, R20): with a remote, next.sh reads the PRs through gh — the branch's newest PR, the open lane
# PRs and whose they are, merged PRs and tags for unbuilt builds, the untagged ship and the next version — and reduces the
# branch PR's comments with attestation.pr_attestation (REQ-311: one classifier). REQ-385: an open PR with no marker
# renders the second-terminal instruction; a REQUEST_CHANGES prints the findings and no merge command; a merge is printed
# only on an APPROVE (and, in team mode, a human approval — reviewDecision, or the reviews at the head when GitHub
# leaves it empty). REQ-382: an accepted waiver the PR body does not link is reported under --explain. P5 R21: a merged
# PR of an earlier use of a fixed branch name is not the branch's PR; a base or merge commit missing locally fails safe
# and is explained. P5 R22: a PR stacked on the branch turns the merge into a merge commit plus the retarget, and a
# stacked PR's verifier instruction warns about its unreviewed base. The factory's own PRs derive on main for both
# paths. A gh failure fails safe. pipeline.py never reads a marker or waiver itself (REQ-311).
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-382
# Covers: REQ-311
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
A="$ROOT/scripts/lib/specflow/attestation.py"; S="$W/stub"; mkdir -p "$S/bin"
cat > "$S/bin/gh" <<'EOF'
#!/usr/bin/env bash
S="${STUB_DIR:?}"; { printf '%s\n' "$@"; echo ---; } >> "$S/gh.argv"
[ -z "${STUB_GH_FAIL:-}" ] || { echo 'gh: HTTP 502' >&2; exit 1; }
case "$1 ${2:-}" in
  "repo view") echo '{"nameWithOwner": "o/r"}' ;;
  "pr list")   python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(json.dumps(d["prs"] if isinstance(d, dict) else d))' "$S/prs.json" ;;
  "pr view")   if printf '%s\n' "$@" | grep -qx reviews; then f="$S/reviews-$3.json"; d='{"reviews": []}'; else f="$S/files-$3.json"; d='{"files": []}'; fi
               if [ -f "$f" ]; then cat "$f"; else echo "$d"; fi ;;
  "api user")  echo "{\"login\": \"${STUB_LOGIN:-alice}\"}" ;;
  api\ *)
    case "$*" in
      */issues/*/comments*) n=$(sed -E 's#.*/issues/([0-9]+)/comments.*#\1#' <<<"$*"); f="$S/comments-$n.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
      */pulls/*/commits*) echo '[]' ;;
      */collaborators/*/permission*) echo '{"permission": "write", "role_name": "write"}' ;;
      *) echo "stub gh: unexpected api call: $*" >&2; exit 64 ;;
    esac ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 64 ;;
esac
EOF
chmod +x "$S/bin/gh"
SEED="$W/seed"; next_seed "$SEED"
git init -q --bare -b main "$W/origin.git"   # check.sh sets GIT_CONFIG_GLOBAL=/dev/null: without -b, HEAD is master and clones check out nothing
git -C "$SEED" remote add origin "$W/origin.git"; git -C "$SEED" push -q origin main
repo() {  # repo NAME BRANCH — a clone with origin; a non-main BRANCH gets one commit and is pushed; sets D and HEAD_SHA
  D="$W/$1"; git clone -q "$W/origin.git" "$D"
  if [ "$2" != main ]; then
    git -C "$D" checkout -q -b "$2"; echo "$1" > "$D/note-$1.txt"; git -C "$D" add -A; git -C "$D" commit -qm "$1"; git -C "$D" push -q origin "$2"
  fi
  HEAD_SHA=$(git -C "$D" rev-parse HEAD)
}
prs() {  # prs "NUMBER HEAD BASE STATE AUTHOR [HEAD_OID [REVIEW_DECISION [BODY_URL]]]" … — gh pr list's answer
  python3 - "$@" > "$S/prs.json" <<'PY'
import json, sys
out = []
for row in sys.argv[1:]:
    n, head, base, state, author, *rest = row.split()
    out.append({"number": int(n), "headRefName": head, "baseRefName": base, "state": state, "author": {"login": author},
                "mergedAt": "2026-09-28T10:00:00Z" if state == "MERGED" else None,
                "mergeCommit": {"oid": "0" * 40} if state == "MERGED" else None,
                "reviewDecision": rest[1] if len(rest) > 1 and rest[1] != "-" else "", "isDraft": False,
                "headRefOid": rest[0] if rest else "1" * 40, "url": f"https://github.com/o/r/pull/{n}",
                "body": ("waiver: " + rest[2]) if len(rest) > 2 else ""})
print(json.dumps(out))
PY
}
comment() {  # comment VERDICT|waive — $S/comments-7.json: one valid comment (OWNER alice) for HEAD_SHA against origin/main
  python3 - "$A" "$D" "$HEAD_SHA" "$1" > "$S/comments-7.json" <<'PY'
import json, subprocess, sys
a, d, head, verdict = sys.argv[1:]
def at(*args, inp=None):
    return subprocess.run(["python3", a, *args], cwd=d, input=inp, capture_output=True, text=True, check=True).stdout.strip()
if verdict == "waive":
    body = f"<!-- specflow-verifier:waive sha:{head} -->\nReviewed by hand: the maintainer decided this one."
else:
    tail = "## SpecFlow verifier\n\n- [art-test-first] high: an example finding\n" + verdict
    base = subprocess.run(["git", "rev-parse", "origin/main"], cwd=d, capture_output=True, text=True, check=True).stdout.strip()
    mode = json.loads(at("review-scope", "--base", "origin/main", "--head", head))["mode"]
    body = at("marker", "--mode", mode, "--sha", head, "--base", base, "--prompt-sha256", at("prompt-hash", "--ref", "origin/main"),
              "--model", "opus", "--verdict", verdict, "--digest", at("digest", inp=tail + "\n"), "--origin", "headless") + "\n" + tail
print(json.dumps([{"id": 1, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-09-28T10:00:00Z",
                   "updated_at": "2026-09-28T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-1", "body": body}]))
PY
}
nx() { rc=0; rm -f "$S/gh.argv"; (cd "$D" && PATH="$S/bin:$PATH" STUB_DIR="$S" bash scripts/next.sh "$@") > "$W/out" 2>&1 || rc=$?; }
has() { grep -qF -- "$1" "$W/out"; }
repo av design/x; prs "7 design/x main OPEN alice $HEAD_SHA"; rm -f "$S"/comments-*.json; nx
ck "an open PR with no marker: design awaiting-verifier" has 'state: design awaiting-verifier'
ck "…the next line is REQ-385's second-terminal instruction, verbatim, in the base-ref form (repo = git's toplevel: /var is /private/var on macOS)" \
  bash -c 'want="next: In a second terminal, not inside Claude — open a new terminal window (Terminal.app or your shell) and run: cd $(printf %q "$(git -C "$2" rev-parse --show-toplevel)") && git show origin/main:scripts/run-verifier.sh | bash -s -- 7; when it prints \"Findings posted to PR #7\", return here and run /next."; grep -qxF -- "$want" "$1"' _ "$W/out" "$D"
ck "…no merge command; the comments were read through gh" bash -c '! grep -qF "gh pr merge" "$1" && grep -q "issues/7/comments" "$2"' _ "$W/out" "$S/gh.argv"
nx --explain
ck "…--explain names the base it judged against and its date (next.sh never fetches, P5 R7)" \
  bash -c 'grep -qE "^why: base origin/main at [0-9a-f]{7}, committed " "$1"' _ "$W/out"
comment APPROVE; nx --profile guided
ck "an APPROVE for the head, solo: awaiting-merge, gh pr merge 7 --squash, and the guided merge confirmation" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qF "next: gh pr merge 7 --squash" "$1" && grep -q "^confirm: merge" "$1"' _ "$W/out"
prs "7 design/x main OPEN alice $HEAD_SHA" "8 build/x-1 design/x OPEN alice"; nx
ck "…with PR #8 stacked on design/x: a merge commit, then #8 retargeted (P5 R22)" \
  bash -c 'grep -qF "next: gh pr merge 7 --merge" "$1" && grep -qF "gh pr edit 8 --base main" "$1" && ! grep -qF -- "--squash" "$1"' _ "$W/out"
prs "7 design/x main OPEN alice $HEAD_SHA"
comment REQUEST_CHANGES; nx
ck "a REQUEST_CHANGES: blocked, the findings printed with their URL, no merge command (REQ-385)" \
  bash -c 'grep -q "^state: design blocked" "$1" && grep -q "^findings:" "$1" && grep -qF "an example finding" "$1" && grep -qF "issuecomment-1" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
comment waive; nx --explain
ck "a waiver the PR body does not link: accepted, and --explain says it is not linked (P5 R20)" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qF "not linked from the PR body" "$1"' _ "$W/out"
prs "7 design/x main OPEN alice $HEAD_SHA - https://github.com/o/r/pull/7#issuecomment-1"; nx --explain
ck "…linked: no such line" no has 'not linked from the PR body'
repo team design/y
(cd "$W" && git clone -q origin.git teambase && cd teambase && printf 'profile: engineer\npath: lanes\nsolo: false\n' > .specflow.yml && git commit -qam team && git push -q origin main)
git -C "$D" fetch -q origin && git -C "$D" rebase -q origin/main && git -C "$D" push -q -f origin design/y; HEAD_SHA=$(git -C "$D" rev-parse HEAD)
prs "7 design/y main OPEN alice $HEAD_SHA -"; comment APPROVE; nx
ck "team mode (solo read at the base): an APPROVE without a human approval is awaiting-human-review, no merge" \
  bash -c 'grep -q "^state: design awaiting-human-review" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
prs "7 design/y main OPEN alice $HEAD_SHA APPROVED"; nx
ck "…with reviewDecision APPROVED: awaiting-merge" has 'state: design awaiting-merge'
prs "7 design/y main OPEN alice $HEAD_SHA -"
printf '{"reviews": [{"author": {"login": "%s"}, "state": "APPROVED", "commit": {"oid": "%s"}}]}\n' alice "$HEAD_SHA" > "$S/reviews-7.json"; nx
ck "…reviewDecision empty, only the author's own approval: still awaiting-human-review (P5 R21(d))" has 'state: design awaiting-human-review'
printf '{"reviews": [{"author": {"login": "%s"}, "state": "APPROVED", "commit": {"oid": "%s"}}]}\n' bob "$HEAD_SHA" > "$S/reviews-7.json"; nx
ck "…reviewDecision empty (no required review), another user's APPROVED review at the head: awaiting-merge, read with gh pr view --json reviews (P5 R21(d))" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qx reviews "$2"' _ "$W/out" "$S/gh.argv"
rm -f "$S/reviews-7.json"
repo gone design/z; prs "6 design/z main CLOSED alice $HEAD_SHA" "7 design/z main MERGED alice $HEAD_SHA"; nx
ck "the branch's newest PR decides (#7 merged over #6 closed): design merged, check out main" \
  bash -c 'grep -q "^state: design merged" "$1" && grep -qF "git checkout main && git pull --ff-only" "$1"' _ "$W/out"
prs "7 design/z main CLOSED alice $HEAD_SHA"; nx
ck "a closed, unmerged PR: design closed" has 'state: design closed'
prs "7 design/z main OPEN alice $(printf '2%.0s' $(seq 40))"; rm -f "$S"/comments-*.json; nx --explain
ck "a PR head not in this checkout: attestation none (fail safe), explained" \
  bash -c 'grep -q "^state: design awaiting-verifier" "$1" && grep -qF "not in this checkout" "$1"' _ "$W/out"
prs "7 design/z phase/plan-x OPEN alice $HEAD_SHA"; nx --explain
ck "a stacked PR whose base was never fetched: awaiting-verifier, the instruction from the PR's own base, with the unreviewed-base warning (P5 R21(b), R22)" \
  bash -c 'grep -q "^state: design awaiting-verifier" "$1" && grep -qF "git show origin/phase/plan-x:scripts/run-verifier.sh | bash -s -- 7" "$1" && grep -qF "Warning: origin/phase/plan-x is not main" "$1"' _ "$W/out"
ck "…--explain: the base is not in this checkout, so no marker is read (fail safe)" has 'base origin/phase/plan-x not in this checkout'
repo reuse phase/validate; prs "5 phase/validate main MERGED alice $(printf '3%.0s' $(seq 40))"; nx --explain
ck "a fixed name reused after a release: the old merged PR #5 (another head) is not this branch's PR — validate gates, never merged (P5 R21(a))" \
  bash -c 'grep -q "^state: validate gates" "$1" && grep -qF "earlier use of this branch name" "$1"' _ "$W/out"
prs "5 phase/validate main MERGED alice $HEAD_SHA"; nx
ck "…the same merged PR at this HEAD is the branch's PR: validate merged" has 'state: validate merged'
repo mainown main; prs "12 build/a-1 main OPEN alice" "15 build/b-1 main OPEN alice" "9 build/c-1 main OPEN bob"; nx
ck "main with the user's open lane PRs: awaiting-merge, check out the lowest own (#12)" \
  bash -c 'grep -q "^state: none awaiting-merge" "$1" && grep -qF "next: gh pr checkout 12" "$1"' _ "$W/out"
ck "…another user's PR is listed with the dfe-10 warning, never proposed" \
  bash -c 'grep "^open lanes:" "$1" | grep -qF "#9 (bob" && grep "^open lanes:" "$1" | grep -qF "dfe-10"' _ "$W/out"
prs "9 build/c-1 main OPEN bob"; nx
ck "main with only another user's open PR: not blocked by it" bash -c '! grep -q "^state: none awaiting-merge" "$1" && grep -q "^open lanes:" "$1"' _ "$W/out"
prs "19 build/a-1 main MERGED alice" "20 ship/0.2.0 main MERGED alice"; nx
ck "a merged ship PR with no tag: ship tag, pointing at /release's post-merge steps" \
  bash -c 'grep -q "^state: ship tag" "$1" && grep -qF "v0.2.0" "$1" && grep -qF "After the PR merges" "$1"' _ "$W/out"
git -C "$D" tag -a v0.2.0 -m v0.2.0; nx --explain
ck "…once v0.2.0 exists: ready-to-ship ship/0.3.0 (the build PR's merge commit is not in the tag)" \
  bash -c 'grep -q "^state: none ready-to-ship" "$1" && grep -qF "git checkout -b ship/0.3.0" "$1"' _ "$W/out"
ck "…a merge commit missing from the checkout counts as not released, and --explain says so (P5 R21(c))" \
  has 'is not in this checkout: counted as not released'
git -C "$D" tag -d v0.2.0 >/dev/null
printf -- '---\ntype: plan\nspec: 2026-09-28-habit\n---\n\n## Build 1: a\n\n## Build 2: b\n' > "$D/docs/plans/2026-09-28-habit-plan.md"
git -C "$D" add -A; git -C "$D" commit -qm habit
prs "30 build/habit-1 main MERGED alice"; nx
ck "a plan whose Build 1 merged and Build 2 did not: next-build build/habit-2" \
  bash -c 'grep -q "^state: none next-build" "$1" && grep -qF "git checkout -b build/habit-2" "$1"' _ "$W/out"
repo factory main; git -C "$D" rm -q .specflow.yml; mkdir -p "$D/stacks/python"; echo 'stack: python' > "$D/stacks/python/pack.yml"
git -C "$D" add -A; git -C "$D" commit -qm "template source"
cp "$ROOT/tests/governance/fixtures/next/factory-prs.json" "$S/prs.json"; STUB_LOGIN=kpingali123 nx
ck "the factory's own history on main, template source (lanes by default): ready-to-ship ship/0.1.0, with the note" \
  bash -c 'grep -q "^state: none ready-to-ship" "$1" && grep -qF "git checkout -b ship/0.1.0" "$1" && grep -q "^note: template source" "$1"' _ "$W/out"
STUB_LOGIN=kpingali123 nx --path regulated
ck "…with --path regulated: ready-to-ship, phase/validate (P5 R6)" has 'git checkout -b phase/validate'
repo ghfail design/w; prs "7 design/w main OPEN alice $HEAD_SHA"; STUB_GH_FAIL=1 nx --explain
ck "gh failing with a remote: PR state unknown, no PR proposed, explained (fail safe)" \
  bash -c 'grep -q "^note: cannot see PRs" "$1" && ! grep -qF "gh pr create" "$1" && ! grep -qE "^state: .*awaiting" "$1"' _ "$W/out"
ck "pipeline.py reads no marker or waiver itself: its only route to an attestation is attestation.pr_attestation (REQ-311)" \
  python3 - "$ROOT/scripts/lib/specflow/pipeline.py" <<'PY'
import ast, sys
src = open(sys.argv[1]).read()
assert "specflow-verifier" not in src, "pipeline.py spells the marker prefix"
calls = set()
for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.Call):
        calls.add(n.func.attr if isinstance(n.func, ast.Attribute) else getattr(n.func, "id", ""))
    if isinstance(n, ast.ImportFrom) and (n.module or "").split(".")[-1] == "attestation":
        assert {a.name for a in n.names} <= {"pr_attestation"}, [a.name for a in n.names]
assert not calls & {"parse_marker", "_judge_comment", "classify"}, sorted(calls & {"parse_marker", "_judge_comment", "classify"})
assert "pr_attestation" in calls, "pipeline.py never calls attestation.pr_attestation"
PY
finish test_next_prs
```

- [x] **Step 2: Run** `bash tests/governance/test_next_prs.sh`. Expected: every PR-state check FAILs (Task 5 treats every repository as having no PR state); the fixture file is missing. Exit 1.
- [x] **Step 3: Implement (intent).** In `pipeline.py`, per Interfaces "PR state": the `gh` calls (parsed with `python3`, every failure → unknown PR state), the branch PR (R21(a)), the open lane PRs with `mine`, `human_approved` (R21(d)), `RenderCtx.stacked` (R22), the branch PR's attestation through `attestation.pr_attestation` (when the head is local; the base `origin/<baseRefName>`; the base's `solo`), the merged-PR facts and tags, the `findings:` block and the `open lanes:` line; R20's explain line. Capture the fixture file once (read-only `gh`; PRs #1–#46; bodies emptied).
- [x] **Step 4: Run** the test (about 20 s), `test_next.sh`, `test_attestation.sh`, and the gates — green, under 2:30.
- [x] **Step 5: Commit** — "feat(next): PR state from gh through attestation.pr_attestation — the branch PR's substate, blocked findings, open lanes and whose they are, merged builds, the untagged ship and the next version; the factory's own history as a fixture (REQ-341, REQ-385, REQ-382, REQ-311)"

---

### Task 7: The `/next` command — engineer and guided profiles, the seven confirmation points (REQ-342)

**Files:** create `.claude/commands/next.md`, `tests/governance/test_next_command.sh`; modify `docs/plans/2026-09-28-factory-v3-2-p5-plan.md`'s frontmatter (`implements:` gains `REQ-342`, R3).

**Interfaces:** `next.md` — frontmatter `name: next`, `description:` (derive where the pipeline is and print or run the next step), `argument-hint: [--explain]`. Sections, in order: `## What it runs` — `bash scripts/next.sh --json $ARGUMENTS`; read `"profile"`, `"state"`, `"next_step"`, `"confirm"`, `"open_lane_prs"`, `"findings"`, `"explain"`, `"notes"`; print the terms line. `## Engineer profile` — print the state and the next step verbatim (with any findings and notes); run nothing. `## Guided profile` — run exactly the command `next.sh` printed (the one the engineer profile would print), in plain English first ("what this does, what you will see"), then run `next.sh` again and continue; stop at every confirmation point, show what that point names, and continue only on the user's yes; at a decision (scope, go/no-go) ask, at an acknowledgement (tags, kernel, severity, disposition, REQ-389) show and record `confirmed_by:` — written at this `/next` point, in the artifact the point names; a command `/next` runs asks nothing itself (its `## Guided profile` section asks only when the user runs it directly, R19), so REQ-342's seven points are the only pauses. The `design-pr`, `build-pr` and `ship-pr` points apply at phase `open-pr` whatever the step, remote or not (Interfaces `confirmation_point`). `## Confirmation points` — exactly seven bullets `- \`brainstorm-end\``, `- \`design-pr\``, `- \`build-pr\``, `- \`ship-pr\``, `- \`awaiting-verifier\``, `- \`merge\``, `- \`unsigned-tag\``, each with what is shown or asked. `## Never` — never runs `scripts/run-verifier.sh` (REQ-385: it prints the second-terminal instruction and waits); never runs `gh pr merge` without the `merge` confirmation, and never unless `next.sh` printed it; never creates an annotated tag without the `unsigned-tag` confirmation; never runs `gh pr checkout` on a PR whose author is not the current user without first warning that checking it out runs its code on this machine and that CI should run the gates first (dfe-10); never writes or reads a state file (`art-branch-as-state`); never edits `.specflow.yml` to change the path or profile. `## --explain` — pass it through and print every `why:` line.

- [x] **Step 1: Write the failing test** — `tests/governance/test_next_command.sh`:

```bash
#!/usr/bin/env bash
# REQ-342 (ADR-003 as amended; P5 R19): /next prints the derived state and command in the engineer profile; in the guided
# profile it runs exactly the engineer-profile command and pauses only at the seven confirmation points; it never runs
# the verifier, never merges without the merge confirmation, never tags unsigned without the unsigned-tag confirmation,
# and warns before checking out a PR whose author is not the current user (dfe-10). next.sh prints the confirm: line only
# in the guided profile.
# Covers: REQ-342
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
N=.claude/commands/next.md
ck "the /next command exists" test -f "$N"
fm=$(awk '/^---$/{n++; next} n==1' "$N" 2>/dev/null || true)
for k in 'name: next' 'description:' 'argument-hint:'; do ck "next.md frontmatter has $k" grep -qF "$k" <<<"$fm"; done
for h in '## What it runs' '## Engineer profile' '## Guided profile' '## Confirmation points' '## Never' '## --explain'; do
  ck "next.md has '$h'" grep -qxF "$h" "$N"
done
sec() { awk -v h="## $1" '$0==h{f=1; next} /^## /{f=0} f' "$N" | tr '\n' ' '; }
ck "next.md runs bash scripts/next.sh --json and reads its profile" bash -c 'grep -qF "bash scripts/next.sh --json" <<<"$1" && grep -qF "\"profile\"" <<<"$1"' _ "$(sec 'What it runs')"
cp=$(awk '/^## Confirmation points$/{f=1; next} /^## /{f=0} f' "$N")
for id in brainstorm-end design-pr build-pr ship-pr awaiting-verifier merge unsigned-tag; do
  ck "next.md lists the confirmation point '$id'" grep -qE "^- \`$id\`" <<<"$cp"
done
ck "next.md: exactly seven confirmation points" [ "$(grep -cE '^- `[a-z-]+`' <<<"$cp")" = 7 ]
nv=$(sec Never)
ck "never runs scripts/run-verifier.sh (REQ-385)" grep -qF 'scripts/run-verifier.sh' <<<"$nv"
ck "never runs gh pr merge without the merge confirmation" bash -c 'grep -qF "gh pr merge" <<<"$1" && grep -qF "\`merge\`" <<<"$1"' _ "$nv"
ck "never tags unsigned without the unsigned-tag confirmation" grep -qF '`unsigned-tag`' <<<"$nv"
ck "never checks out another author's PR without the dfe-10 warning" bash -c 'grep -qF "gh pr checkout" <<<"$1" && grep -qF "dfe-10" <<<"$1"' _ "$nv"
ck "never a state file (art-branch-as-state)" grep -qF 'art-branch-as-state' <<<"$nv"
ck "guided: runs exactly the command next.sh printed" grep -qiF 'exactly the command' <<<"$(sec 'Guided profile')"
ck "engineer: prints, runs nothing" grep -qiF 'runs nothing' <<<"$(sec 'Engineer profile')"
ck "guided: a command /next runs asks nothing itself; confirmed_by: is written at the /next point (REQ-342: no other pause)" \
  bash -c 'grep -qiF "asks nothing" <<<"$1" && grep -qF "confirmed_by:" <<<"$1"' _ "$(sec 'Guided profile')"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
next_seed "$W/seed"; git clone -q "$W/seed" "$W/d"; git -C "$W/d" remote remove origin; git -C "$W/d" checkout -q -b design/greet
(cd "$W/d" && bash scripts/next.sh --profile guided) > "$W/g" 2>&1
(cd "$W/d" && bash scripts/next.sh --profile engineer) > "$W/e" 2>&1
ck "guided: a complete design lane with no remote (step ExplainUnknown at open-pr) still pauses at design-pr" grep -q '^confirm: design-pr' "$W/g"
ck "engineer: the same state prints no confirm line" bash -c 'grep -q "^state: design open-pr" "$1" && ! grep -q "^confirm:" "$1"' _ "$W/e"
ck "both profiles derive the same state and the same next step" [ "$(grep -E '^(state|next): ' "$W/g")" = "$(grep -E '^(state|next): ' "$W/e")" ]
finish test_next_command
```

- [x] **Step 2: Run** `bash tests/governance/test_next_command.sh`. Expected: the command-file checks FAIL (no file); the `next.sh` checks pass (Tasks 3, 5). Exit 1.
- [x] **Step 3: Implement (intent).** Write `next.md` per Interfaces, in plain English for the guided sections. Add `REQ-342` to this plan's `implements:` (R3).
- [x] **Step 4: Run** the test, `bash scripts/check-covers.sh` (REQ-342 now claimed and cited), `test_plan_template.sh`, and the gates — green.
- [x] **Step 5: Commit** — "feat(next): the /next command — engineer prints, guided runs the same command and pauses only at the seven confirmation points; never the verifier, never an unconfirmed merge or unsigned tag, the dfe-10 warning (REQ-342)"

---

### Task 8: The first run — `/next` on `main` in a fresh, remote-less instance derives idle on both paths (REQ-393, R4)

**Files:** `tests/governance/test_first_run.sh` (the header's Covers line gains REQ-393; the `guided` and `engineer` cases gain checks); this plan's `implements:` gains `REQ-393` (R3).

**Interfaces:** R4. Opt-in (the whole test is): `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="guided engineer" bash tests/governance/test_first_run.sh`, about 4 minutes here; CI's first-run jobs run both cases on every PR.

- [x] **Step 1: Write the failing test.** Change the header to `# Covers: REQ-360, REQ-306, REQ-305, REQ-393`. In the `guided)` case, after `gates "$D" "guided/python/lanes/solo"` and its floor check:

```bash
      ck "guided: next.sh on main in the remote-less instance runs (REQ-393)" bash -c "cd '$D' && bash scripts/next.sh --json > '$WORK/next-guided.json'"
      ck "guided: idle, NewBranch(ProposeDesign) rendered design/<slug> then brainstorming, PR state unknown (P5 R4)" python3 - "$WORK/next-guided.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["state"] == {"lane": "none", "phase": "idle"}, d["state"]
assert d["step"] == {"kind": "NewBranch", "proposal": {"kind": "ProposeDesign"}}, d["step"]
assert "git checkout -b design/<slug>" in d["next_step"] and "/superpowers:brainstorming" in d["next_step"], d["next_step"]
assert d["pr_state_known"] is False and d["profile"] == "guided" and d["path"] == "lanes", d
PY
      ck "guided: never awaiting-verifier, never a PR command, in the remote-less instance" \
        bash -c '! grep -qE "awaiting-verifier|gh pr (create|merge)" "$1"' _ "$WORK/next-guided.json"
```

and in the `engineer)` case, after its floor check:

```bash
      ck "engineer: next.sh on main in the remote-less instance runs (REQ-393)" bash -c "cd '$D' && bash scripts/next.sh --json > '$WORK/next-engineer.json'"
      ck "engineer (regulated): idle, NewBranch(ProposeSpec) rendered phase/spec-<slug> then brainstorming (P5 R4)" python3 - "$WORK/next-engineer.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["state"] == {"lane": "none", "phase": "idle"}, d["state"]
assert d["step"] == {"kind": "NewBranch", "proposal": {"kind": "ProposeSpec"}}, d["step"]
assert "git checkout -b phase/spec-<slug>" in d["next_step"] and "/superpowers:brainstorming" in d["next_step"], d["next_step"]
assert d["pr_state_known"] is False and d["profile"] == "engineer" and d["path"] == "regulated", d
PY
      ck "engineer: never awaiting-verifier, never a PR command" bash -c '! grep -qE "awaiting-verifier|gh pr (create|merge)" "$1"' _ "$WORK/next-engineer.json"
```

- [x] **Step 2: Run** the opt-in command above (about 4 minutes). Expected: before this task's implementation step nothing is missing — Tasks 3–6 already derive idle — so the new checks pass on first run; confirm they FAIL against a deliberately broken copy (point the checks at `idle-x` in a scratch copy of the test, never committed) and record that in the commit body. The test change is the deliverable; REQ-393 is a test REQ.
- [x] **Step 3: Implement (intent).** Add `REQ-393` to this plan's `implements:` (R3). Nothing else.
- [x] **Step 4: Run** the opt-in cases again (both green), `bash scripts/check-covers.sh`, `test_plan_template.sh`, and the gates — green.
- [x] **Step 5: Commit** — "test(first-run): /next on main in the remote-less instance derives idle — design/<slug> or phase/spec-<slug>, then brainstorming — never awaiting-verifier (REQ-393)"

---

### Task 9: Both paths everywhere else — the proof jobs (R12), init's next steps, `CLAUDE.md`, README's workflow block, `/security-review`'s back-edge (REQ-340, REQ-343)

**Files:** `.github/workflows/verifier.yml:97-100` and `:123-126`; `scripts/init-project.sh:637-668` (both next-steps blocks); `CLAUDE.md` ("Start Every Session Here", both pipeline tables, the Project Map); `README.md` (the "Workflow (10 phases, either path)" section); `.claude/commands/security-review.md:92`; tests `tests/governance/test_review_gate_paths.sh` (checks above `finish`), `tests/governance/test_init.sh` (after `:37` and `:64`).

**Interfaces:** R12's condition, identical in both jobs: the label, or `github.head_ref` starting with `impl/`, `phase/validate`, `phase/plan-`, `design/`, `build/`, `ship/`, `phase/security` or `phase/release` (R12 as shipped; in YAML, one `startsWith(github.head_ref, '<prefix>')` per prefix, joined by `||`). Init's next steps gain, in both blocks, a first line: `0) In Claude Code, run /next at any time: it reads your branches, PRs and files and prints the next step (the guided profile runs it for you).` — the existing lines stay (`test_init.sh:36-64` pin them). `CLAUDE.md`: "Start Every Session Here" gains "Run `/next` to see where the pipeline stands and what to do next (`scripts/next.sh`; state is derived from branches, PRs and files, `art-branch-as-state`)"; under both pipeline tables, "`/next` derives the phase or lane on either path (both paths' branch names are recognised whatever `.specflow.yml`'s `path` says) and prints the step; squash merges are permitted"; the Project Map names `scripts/next.sh`, `scripts/lib/specflow/state.py` (the proved kernel), `scripts/lib/specflow/pipeline.py` and `.claude/commands/next.md`. README's workflow section says the same in two sentences. `/security-review`'s back-edge: `impl/sec-<finding-id>` (regulated) or `build/sec-<finding-id>` (lanes).

- [x] **Step 1: Write the failing tests.** Append to `tests/governance/test_review_gate_paths.sh`, above `finish` (its header gains `# Covers: REQ-340`):

```bash
# P5 (REQ-340, R12; REQ-343): the proof and contract jobs run on every branch of either path where a proof, a contract or
# its twin travels (not patch/); the patch tier and the minor exception stay stated for both paths; CLAUDE.md, README
# and /security-review name both paths and /next.
# Covers: REQ-340
V=.github/workflows/verifier.yml
cond() { awk -v j="  $1:" '$0==j{f=1; next} f && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{exit} f' "$V" \
  | awk '/^    if: \|/{f=1; next} f && /^    [a-z-]+:/{exit} f' | tr -d ' \n'; }
for job in verify-dafny contract-alignment; do
  c=$(cond "$job")
  for pre in impl/ phase/validate phase/plan- design/ build/ ship/; do
    ck "$job runs on $pre heads" grep -qF "startsWith(github.head_ref,'$pre')" <<<"$c"
  done
  ck "$job keeps the has-verification label" grep -qF "'has-verification'" <<<"$c"
  ck "$job leaves patch/ out (a patch never touches a [verifiable*] REQ)" no grep -qF "'patch/'" <<<"$c"
done
ck "both proof jobs share one condition" [ "$(cond verify-dafny)" = "$(cond contract-alignment)" ]
ck "actionlint accepts the workflows (when installed)" bash -c 'command -v actionlint >/dev/null 2>&1 || exit 0; actionlint .github/workflows/*.yml'
ck "the patch tier is one PR from patch/<slug> on either path" grep -qF 'on either path' <<<"$(awk '/^## Patch tier/,/^## Minor exception/' "$R")"
ck "the minor exception bounds doc-only fixes, whatever the path" bash -c 'awk "/^## Minor exception/,0" "$1" | grep -qi "doc-only"' _ "$R"
ck "/security-review's back-edge names impl/sec- and build/sec-" \
  bash -c 'grep -qF "impl/sec-<finding-id>" "$1" && grep -qF "build/sec-<finding-id>" "$1"' _ .claude/commands/security-review.md
for w in '/next' 'scripts/next.sh' 'scripts/lib/specflow/state.py' 'scripts/lib/specflow/pipeline.py' '.claude/commands/next.md'; do
  ck "CLAUDE.md names $w" grep -qF -- "$w" CLAUDE.md
done
ck "README's workflow section names /next and squash merges" \
  bash -c 'w=$(awk "/^## Workflow/{f=1; next} /^## Key Files/{f=0} f" README.md); grep -qF "/next" <<<"$w" && grep -qi "squash" <<<"$w"'
```

and in `tests/governance/test_init.sh`, after `:37` and after `:64`:

```bash
ck "regulated next steps start with /next (REQ-343)" grep -qF 'run /next at any time' <<<"$out"
```

```bash
ck "lanes next steps start with /next (REQ-343)" grep -qF 'run /next at any time' <<<"$out"
```

- [x] **Step 2: Run** both tests. Expected: the six prefix checks per job (`phase/plan-`, `design/`, `build/`, `ship/` missing), the CLAUDE.md, README, back-edge and init checks FAIL. Exit 1.
- [x] **Step 3: Implement (intent).** Per Interfaces; `actionlint .github/workflows/*.yml` clean.
- [x] **Step 4: Run** the two tests, `test_workflow_health.sh`, `test_onboarding_surface.sh`, `test_examples.sh` (the examples manifest in `CLAUDE.md` is untouched), and the gates — green.
- [x] **Step 5: Commit** — "feat(lanes): both paths everywhere — verify-dafny and contract-alignment on design/, build/, ship/ and phase/plan- heads; /next in init's next steps, CLAUDE.md and README; the lanes back-edge in /security-review (REQ-340, REQ-343)"

---

### Task 10: Guided proposals — decisions and acknowledgements where each lands; the verifier confirms the acknowledgements in guided solo mode (REQ-389, REQ-310)

**Files:** `.claude/commands/specify.md`, `.claude/commands/architecture.md`, `.claude/commands/security-review.md`, `.claude/commands/release.md` (a `## Guided profile` section in each); `templates/IDEA.md` (the `## Stack` shape); `stacks/python/pack.yml`, `stacks/tauri/pack.yml`, `stacks/flutter/pack.yml` (`guided_consequence:`); `scripts/init-project.sh:498` and `:582-590` (read `guided_consequence`; the guided `## Stack` block writes the rationale and the consequence lines); `tests/governance/lib/check.sh` (`stub_pack` writes a `guided_consequence:` too); `schemas/spec-template.md` (a commented `confirmed_by:` frontmatter key and a `## Guided proposals` note); `.claude/skills/verifier/SKILL.md` (full mode: a step 8, `Guided acknowledgements`; code mode unchanged); `.claude/skills/verifier/headless-prompt.md` (`Profile: @PROFILE@`, `Solo: @SOLO@`); `scripts/run-verifier.sh` (a new policy read in the headless path — see Step 3 — and `render_prompt` substitutes both placeholders); create `tests/governance/test_guided_proposals.sh`; modify `tests/governance/test_verifier_run.sh` (a check above `finish`).

**Interfaces:** R19. Each command's `## Guided profile` section (read only when `config.py get profile` is `guided`) asks or shows only when the user ran the command directly — when `/next` ran it, it asks nothing, because `/next` asked at its confirmation point and writes `confirmed_by:` there (R19; REQ-342 allows no other pause) — and says: what Claude proposes, where it is written under a `### Guided proposals` heading with, per proposal, a `Rationale (plain English):` line and a `What this means for you:` line, and whether it is a **decision** (asked: the product scope in `/specify`, go/no-go in `/release`) or an **acknowledgement** (shown: the `[verifiable-model]` tags in `/specify`, the kernel boundary in `/architecture`, severity and disposition in `/security-review`), and the `confirmed_by: <handle> <YYYY-MM-DD>` frontmatter it adds (the spec in `/specify`; the overview, threat model and ADRs in `/architecture`, which `check-architecture.sh` already requires). `/security-review` records its guided proposals in the review's prose, "not a block key" (the schema's keys are fixed, `schemas/security-disposition-template.md`). Init's guided `## Stack` block: `Rationale (plain English): <guided_rationale>` and `What this means for you: <guided_consequence>`. The verifier's **full mode** (R19: the part that reads the documents where acknowledgements land; a design or ship PR is doc-only), step 8, when the prompt says exactly `Profile: guided` and `Solo: true`: read each changed document's `### Guided proposals` and confirm (or not) each acknowledgement against the document's own content — tags against each REQ's Verification scope, the kernel boundary against `kernel_modules.req_map`, severity against the vector, disposition against ADR-002's rules — and record one finding `Guided acknowledgements (provisional): …` (severity low), citing each acknowledgement's own article — `[verifiable-model]` tags `art-formal-verification`, the kernel boundary `art-kernel-boundary`, severity and dispositions `art-threat-driven-security`; an acknowledgement it cannot confirm is a medium finding. Code mode is unchanged: its five REQ-310 headings, no guided pass (a mixed PR gets both parts, and full mode covers its documents).

- [x] **Step 1: Write the failing tests** — `tests/governance/test_guided_proposals.sh` (the verifier checks read the full-mode section; code mode's headings are pinned unchanged):

```bash
#!/usr/bin/env bash
# REQ-389 (P5 R19): in the guided profile Claude proposes the stack, the [verifiable-model] tags, the kernel boundary,
# severity scores and dispositions, each recorded where it lands with a plain-English rationale and its consequence for
# the user; decisions (stack, scope, go/no-go) are asked, acknowledgements (tags, kernel, severity, disposition) are shown,
# once — a command /next runs asks nothing itself (REQ-342) — and the verifier's full mode, the part that reads the
# documents where they land, confirms the acknowledgements in guided solo mode, provisionally (P5 R19's reading of the
# REQ's "code mode"); code mode's headings are unchanged. REQ-310: the verifier's
# prompt names the base's profile and solo. A guided fixture instance records the stack decision's rationale and
# consequence in IDEA.md.
# Covers: REQ-389
# Covers: REQ-310
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=.claude/commands
guided() { awk '/^## Guided profile$/{f=1; next} /^## /{f=0} f' "$1" | tr '\n' ' '; }
for f in specify architecture security-review; do
  g=$(guided "$C/$f.md")
  ck "$f.md has a Guided profile section" test -n "$g"
  for w in 'Guided proposals' 'Rationale (plain English):' 'What this means for you:' 'acknowledgement'; do
    ck "$f.md's guided section says '$w'" grep -qF -- "$w" <<<"$g"
  done
done
for f in specify architecture security-review release; do
  ck "$f.md's guided section asks nothing when /next ran it (/next asked at its confirmation point, REQ-342)" \
    bash -c 'grep -qF "/next" <<<"$1" && grep -qiF "asks nothing" <<<"$1"' _ "$(guided "$C/$f.md")"
done
g=$(guided "$C/specify.md")
ck "specify.md: the tags are acknowledgements, the product scope a decision, confirmed_by: on the spec" \
  bash -c 'grep -qF "[verifiable-model]" <<<"$1" && grep -qi "scope" <<<"$1" && grep -qi "decision" <<<"$1" && grep -qF "confirmed_by:" <<<"$1"' _ "$g"
g=$(guided "$C/architecture.md")
ck "architecture.md: the kernel boundary is an acknowledgement recorded in the overview" \
  bash -c 'grep -qi "kernel" <<<"$1" && grep -qF "overview" <<<"$1" && grep -qF "confirmed_by:" <<<"$1"' _ "$g"
g=$(guided "$C/security-review.md")
ck "security-review.md: severity and disposition are acknowledgements in the review's prose, not a block key" \
  bash -c 'grep -qi "severity" <<<"$1" && grep -qi "disposition" <<<"$1" && grep -qi "not a block key" <<<"$1"' _ "$g"
g=$(guided "$C/release.md")
ck "release.md: go/no-go is a decision the human answers before the ship PR" \
  bash -c 'grep -qi "go/no-go" <<<"$1" && grep -qi "decision" <<<"$1"' _ "$g"
sk=$(awk '/^## Mode: full/{f=1; next} /^## /{f=0} f' .claude/skills/verifier/SKILL.md | tr '\n' ' ')
ck "full mode confirms guided acknowledgements in guided solo mode, provisionally (P5 R19: doc-only design and ship PRs get full mode alone)" \
  bash -c 'grep -qF "Guided acknowledgements" <<<"$1" && grep -qi "provisional" <<<"$1" && grep -qF "Profile: guided" <<<"$1" && grep -qF "Solo: true" <<<"$1" && grep -qF "Guided proposals" <<<"$1" && grep -qF "art-threat-driven-security" <<<"$1"' _ "$sk"
ck "code mode carries no guided pass" no grep -qF 'Guided acknowledgements' <<<"$(awk '/^## Mode: code$/{f=1; next} /^## /{f=0} f' .claude/skills/verifier/SKILL.md)"
ck "code mode's five headings are unchanged (REQ-310)" bash tests/governance/test_verifier_skill_modes.sh
ck "the headless prompt carries the Profile and Solo lines" \
  bash -c 'grep -qx "Profile: @PROFILE@" "$1" && grep -qx "Solo: @SOLO@" "$1"' _ .claude/skills/verifier/headless-prompt.md
ck "the spec template carries confirmed_by: and the Guided proposals note" \
  bash -c 'grep -qF "confirmed_by:" "$1" && grep -qF "Guided proposals" "$1"' _ schemas/spec-template.md
if ! instance; then
  for p in stacks/*/pack.yml; do
    ck "$p carries guided_consequence (what the stack choice means for the user)" grep -qE '^guided_consequence: .{20,}' "$p"
  done
  W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
  D="$W/g"; copy_template "$D"
  ck "guided init (scaffold-free) exits 0" bash -c "cd '$D' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Habit --profile guided --stack python </dev/null"
  st=$(awk '/^## Stack$/{f=1; next} /^## /{f=0} f' "$D/IDEA.md" | tr '\n' ' ')
  ck "the guided instance's IDEA.md records the stack with its rationale and what it means for the user" \
    bash -c 'grep -qF "Rationale (plain English):" <<<"$1" && grep -qF "What this means for you:" <<<"$1"' _ "$st"
fi
finish test_guided_proposals
```

and append to `tests/governance/test_verifier_run.sh`, above `finish`, after a case whose `vrun` ran the stub `claude` (the base is the template source: no `.specflow.yml`, so the defaults):

```bash
# REQ-310 / REQ-389 (P5 R19): the prompt names the base's profile and solo, read with attestation.py policy at the base.
# Covers: REQ-389
vbranch prof 'echo x > docs/prof.md' alice; vrun 7
ck "the prompt names the base's profile and solo (the defaults: guided, true)" \
  bash -c 'grep -qx "Profile: guided" "$1" && grep -qx "Solo: true" "$1"' _ "$VS/claude.stdin"
(cd "$VR" && git checkout -q main && printf 'solo: maybe\n' > .specflow.yml && git add .specflow.yml && git commit -qm 'bad policy' && git push -q origin main)
vbranch badpol 'echo y > docs/badpol.md' alice; vrun 7
ck "an unreadable policy at the base stops the headless run before the model is called (exit 1, no prompt sent)" \
  bash -c '[ "$1" = 1 ] && grep -qF "could not read policy" <<<"$2" && [ ! -e "$3" ]' _ "$rc" "$out" "$VS/claude.stdin"
(cd "$VR" && git checkout -q main && git rm -q .specflow.yml && git commit -qm 'policy restored' && git push -q origin main)
```

- [x] **Step 2: Run** both tests. Expected: every command, skill, prompt, template, pack and IDEA check FAILs, and the prompt check FAILs. Exit 1.
- [x] **Step 3: Implement (intent).** Per Interfaces, in plain English; the `guided_consequence:` values say, for each pack, what the choice means for the founder (python: a web service or command-line tool, shipped as a container image; tauri: a Mac app you can hand to a tester; flutter: the macOS build of an app that can later target phones). `config.py`'s pack reading needs no change (flat keys). `run-verifier.sh`: the headless path reads no policy today — the `policy --ref origin/<base>` call at `:519` runs only inside the `--from-file` branch, and the prompt is rendered at `:180-192` — so add one read before rendering, `python3 "$attestation" policy --ref "$src_ref"` (the base ref, or the PR head under `--bootstrap`, the same `$src_ref` the skill and constitution come from), and pass `profile` and `solo` to `render_prompt` for `@PROFILE@` and `@SOLO@`. When the read fails, the run stops with `ERROR: could not read policy at <ref>.` and exit 1 before the model is called, as the `--from-file` path does: a prompt that misstated the policy would switch the guided pass on or off wrongly. The template file is unchanged except for its two placeholder lines, so `prompt_sha256` moves once, when this task merges.
- [x] **Step 4: Run** the two tests, `test_verifier_skill_modes.sh`, `test_verifier_skill_citations.sh`, `test_verifier_isolation.sh`, `test_init.sh`, `test_stack_packs.sh`, `test_check_architecture.sh`, and the gates — green.
- [x] **Step 5: Commit** — "feat(guided): proposals with a plain-English rationale and consequence where each lands, decisions asked and acknowledgements shown; the verifier confirms acknowledgements in guided solo mode, provisionally; the prompt names the base's profile and solo (REQ-389, REQ-310)"

---

### Task 11: Security-document hand-offs — the tauri skeleton review (R18), the floor's thresholds (R17), the template's own reviews (R17) (H8, H12, H13; REQ-332, REQ-331 as context)

**Files:** `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md` (header and prose only); `docs/security/README.md` (the schema-migrations list gains P5's entry for the skeleton review; a paragraph on thresholds); `.claude/commands/security-review.md` (a step after step 0: the lower-threshold runs); tests `tests/governance/test_security_schema_docs.sh`, `tests/governance/test_security_review.sh` (checks above `finish`).

**Interfaces:** R17, R18. The skeleton review: `R12` → `P4 R12`; each `R20` → `art-threat-driven-security`'s informational row; above SEC-002's and SEC-003's metric tables, "Recorded for the vector's shape only: with every impact metric `N` the vector scores 0.0 whatever these rows say." No `id:`, `severity:` or `cvss_vector:` line changes. `/security-review`, after step 0: run `bandit -r src --severity-level medium --confidence-level medium` (python) and `npm audit --audit-level=moderate` (tauri) once, outside the floor, and record each result as a finding with its own vector (or "none found"); a finding below the floor's threshold needs no `SEC-NNN` suppression. `docs/security/README.md` says the same and that a table-less `## Tools run` is conformant where the product has no pack lockfile (REQ-332's own exception; the template source's demo).

- [x] **Step 1: Write the failing tests.** Append to `tests/governance/test_security_schema_docs.sh`, above its `W=` line's following checks (above `finish`):

```bash
# P5 R18 (H8; REQ-332): the tauri skeleton review names its rulings by plan and labels the informational findings'
# exploitability rows as shape only — a header and prose edit under the schema-migration rule: no SEC id added, removed
# or re-scored.
# Covers: REQ-332
SKR="$ROOT/stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md"
if [ -f "$SKR" ]; then
  ck "the skeleton review cites P4 R12, never a bare R12" \
    bash -c 'grep -qF "P4 R12" "$1" && ! sed "s/P4 R12//g" "$1" | grep -qE "(^|[^0-9A-Za-z])R12([^0-9]|$)"' _ "$SKR"
  ck "the skeleton review cites no bare R20; the informational row is art-threat-driven-security's" \
    bash -c '! grep -qE "(^|[^0-9A-Za-z])R20([^0-9]|$)" "$1" && grep -qF "art-threat-driven-security" "$1"' _ "$SKR"
  ck "SEC-002's and SEC-003's metric tables are labelled as recorded for the vector's shape only" \
    [ "$(grep -c "Recorded for the vector's shape only" "$SKR")" -ge 2 ]
  ck "no id, severity or vector changed since P4's review shipped (b3db479)" bash -c \
    'diff <(git -C "$2" show b3db479:stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md | grep -E "^(id|severity|cvss_vector):") <(grep -E "^(id|severity|cvss_vector):" "$1")' _ "$SKR" "$ROOT"
fi
ck "docs/security/README.md lists P5's skeleton-review migration (header and prose only)" \
  bash -c 'awk "/^## Schema migrations$/{f=1; next} /^## /{f=0} f" "$1" | grep -qF "P5"' _ "$RM"
```

and to `tests/governance/test_security_review.sh`, above `finish`:

```bash
# P5 R17 (H12, H13; REQ-332, REQ-331 as context): the floor's thresholds stay REQ-331's; /security-review runs each
# thresholded tool once more a level lower and records what it finds as findings; a table-less Tools run is conformant
# where the product has no pack lockfile (the template source's demo) and fails where it has one.
# Covers: REQ-332
if [ -d "$ROOT/stacks/python" ]; then
  ck "python's security hook keeps bandit --severity-level high" grep -qF -- '--severity-level high' "$ROOT/stacks/python/security.sh"
  ck "tauri's security hook keeps npm audit --audit-level=high" grep -qF -- '--audit-level=high' "$ROOT/stacks/tauri/security.sh"
fi
SRC=$(tr '\n' ' ' < "$ROOT/.claude/commands/security-review.md")
ck "/security-review runs bandit at medium and npm audit at moderate, recording the results as findings" \
  bash -c 'grep -qF -- "--severity-level medium" <<<"$1" && grep -qF -- "--audit-level=moderate" <<<"$1" && grep -qi "record each result as a finding" <<<"$1"' _ "$SRC"
ck "docs/security/README.md: below the floor's threshold needs no SEC-NNN suppression" \
  grep -qi 'below the floor.s threshold needs no' "$ROOT/docs/security/README.md"
T13="$W/h13"; mkdir -p "$T13/docs/security"
printf '## Tools run\n\nManual review only.\n\n## Findings\n\nNone.\n' > "$T13/docs/security/9.9.9-review.md"
ck "a table-less Tools run passes check-review where the product has no pack lockfile (the template source's case)" \
  python3 "$FP" check-review "$T13/docs/security/9.9.9-review.md" --root "$T13"
mkdir -p "$T13/.specflow"; printf 'lockfiles: [uv.lock]\n' > "$T13/.specflow/pack.yml"; : > "$T13/uv.lock"
ck "…and fails once the pack's lockfile exists" no python3 "$FP" check-review "$T13/docs/security/9.9.9-review.md" --root "$T13"
```

- [x] **Step 2: Run** both tests. Expected: the skeleton-review, README, `/security-review` checks FAIL; the thresholds and the two `check-review` checks pass already (they pin today's behaviour, R17). Exit 1.
- [x] **Step 3: Implement (intent).** Per Interfaces. The skeleton review stays parseable by `blocks.py` in floor mode; its disposition is untouched.
- [x] **Step 4: Run** the two tests, `test_stack_packs.sh`, `test_suppressions.sh`, `test_stack_security.sh`, and the gates — green. The IMPLEMENT PR body asks the maintainer to confirm R18's schema-migration exception in the merge comment.
- [x] **Step 5: Commit** — "docs(security): the tauri skeleton review cites P4 R12 and labels informational metric rows as shape only; /security-review looks below the floor's thresholds; table-less reviews where no lockfile exists (REQ-332)"

---

### Task 12: The `.github` surface — the idea-seed template removed; Dependabot batches (REQ-345, REQ-334; R15)

**Files:** delete `.github/ISSUE_TEMPLATE/idea-seed.yml` (and the directory); `.github/dependabot.yml`; `docs/GLOSSARY.md` (Dependabot exemption); `README.md` (one paragraph in the enforcement section); create `tests/governance/test_github_surface.sh`; this plan's `implements:` gains `REQ-345` (R3).

**Interfaces:** R15. `dependabot.yml`: each of the two `updates` gains `groups:` with one group whose `patterns: ["*"]`; the header comment keeps its current content and adds: a pip bump of ruff, black, pytest or pytest-cov that moves only `scripts/requirements.txt` is exempt from the `verifier` check but stopped by the `gates` check (`test_python_lockfiles.sh`; `stacks/python/skeleton/requirements.txt` and `stacks/python/pack.yml` must move with `scripts/requirements.txt`), workflow action bumps are never exempt (`.github/` is always attested), so the maintainer folds a week's batch into one attested `patch/<slug>` PR and closes the Dependabot PRs as superseded (the #43 precedent).

- [x] **Step 1: Write the failing test** — `tests/governance/test_github_surface.sh`:

```bash
#!/usr/bin/env bash
# REQ-345: the idea-seed issue template (no workflow consumed it) is gone and nothing outside the history points at it;
# IDEA.md is the single entry point. REQ-334 (P5 R15): Dependabot batches each ecosystem into one weekly PR, and the file,
# the glossary and README say how a batch merges — gate-tool pip bumps and workflow action bumps are never exempt, so the
# maintainer folds the batch into one attested patch/<slug> PR and closes the Dependabot PRs as superseded.
# Covers: REQ-345
# Covers: REQ-334
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
ck "the idea-seed issue template is removed" no test -e .github/ISSUE_TEMPLATE/idea-seed.yml
ck "no issue template is left" bash -c '! ls .github/ISSUE_TEMPLATE/* >/dev/null 2>&1'
ck "nothing outside the history references idea-seed" \
  bash -c '! git grep -qF "idea-seed" -- . ":!docs/reviews" ":!docs/specs" ":!docs/plans" ":!tests/governance/test_github_surface.sh"'
ck "IDEA.md stays the entry point (init copies templates/IDEA.md)" bash -c 'test -f templates/IDEA.md && grep -qF "templates/IDEA.md" scripts/init-project.sh'
DB=.github/dependabot.yml
ck "dependabot.yml: pip at /scripts and github-actions at /, weekly, each one group of every update" python3 - "$DB" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
blocks = re.split(r"\n  - package-ecosystem: ", "\n" + t.split("\nupdates:", 1)[1])[1:]
eco = {b.split("\n", 1)[0].strip(): b for b in blocks}
assert set(eco) == {"pip", "github-actions"}, sorted(eco)
assert 'directory: "/scripts"' in eco["pip"] and 'directory: "/"' in eco["github-actions"]
for name, b in eco.items():
    assert "interval: weekly" in b, name
    assert "groups:" in b and re.search(r'patterns:\s*\[\s*"\*"\s*\]', b), name
PY
cm=$(grep -E '^#' "$DB" | tr '\n' ' ')
for w in 'patch/<slug>' 'superseded' 'stacks/python/skeleton/requirements.txt' '.github/'; do
  ck "dependabot.yml's comment says '$w'" grep -qF -- "$w" <<<"$cm"
done
gd=$(awk '/^### Dependabot exemption$/{f=1; next} /^### /{f=0} f' docs/GLOSSARY.md | tr '\n' ' ')
ck "the glossary's Dependabot entry: a batch is folded into one attested patch/<slug> PR, the rest superseded" \
  bash -c 'grep -qF "patch/<slug>" <<<"$1" && grep -qi "superseded" <<<"$1"' _ "$gd"
ck "README says how a Dependabot batch merges" \
  bash -c 'grep -i "dependabot" README.md | grep -qF "patch/<slug>"'
finish test_github_surface
```

- [x] **Step 2: Run** it. Expected: the removal, grouping, comment, glossary and README checks FAIL. Exit 1.
- [x] **Step 3: Implement (intent).** Delete the template; edit `dependabot.yml`, the glossary entry and README (the README sentence names `patch/<slug>` on the line that names Dependabot); add `REQ-345` to `implements:` (R3). `actionlint` is unaffected (not a workflow).
- [x] **Step 4: Run** the test, `test_action_pins.sh`, `test_attestation.sh`, `bash scripts/check-covers.sh`, and the gates — green.
- [x] **Step 5: Commit** — "chore(github): remove the unused idea-seed issue template; Dependabot groups each ecosystem weekly and the docs say a batch merges as one attested patch PR (REQ-345, REQ-334)"

---

### Task 13: The inherited-documents fence — instances do not receive the factory's own design documents and proofs (R11; H7; REQ-306)

**Files:** create `scripts/factory-only.txt`; modify `scripts/init-project.sh` (before `:609`: read the manifest, remove each match, remove the manifest); `scripts/lib/specflow/release_gate.py:173` (the note drops "(F-10/W-7, P5)"); `.claude/rules/review-gate.md:70` (the Files cell names `scripts/check-security-disposition.sh`, `scripts/lib/specflow/disposition.py` and `tests/governance/fixtures/disposition`; the Mechanism says the kernel is proved by the template's own Dafny model, which instances do not receive); `.claude/commands/security-review.md:60` (points at `docs/security/README.md`'s suppression rules, not the P4 plan); `schemas/security-disposition-template.md:108` and `docs/GLOSSARY.md:145` (name the model without its path); `docs/GLOSSARY.md` (new `### Factory documents`: what the template keeps for itself and an instance does not receive); `README.md` (Quick Start step 0 gains one sentence); every `tests/governance/test_*.sh` that reads a fenced path without a presence guard (found by `git grep -lE 'factory[-_]v3[-_]2|docs/adr/00[23]-' -- tests/governance/test_*.sh`; each read guarded as `test_threat_model_current.sh:11` does); `tests/governance/test_examples.sh` (checks above `finish`).

**Interfaces:** "The fence manifest"; R11. Init removes the matches after the examples removal (`:597-607`) and before `rm -rf stacks` (`:609`), with `python3` (`fnmatch` over the relative paths of an `os.walk` of the new tree, `.git` skipped — the tree has no `.git` until `:621`, so never `git ls-files`; a trailing `/` a directory prefix), skipping every path the examples manifest lists, then `scripts/factory-only.txt`. ADR-002 is not in the manifest: it defines the disposition gate every instance runs, and instance documents cite its rules 1–5. The glossary entry: the template carries the factory's own v3.2 spec, ADR-003, architecture, plans, reviews and proofs; an instance does not receive them (so its traceability, REQ numbering and proofs are its own; the python demo stays as the worked example); it keeps ADR-002, the disposition gate's rules; a `REQ-3xx` its documents cite names one of the template's own requirements, kept as provenance; new REQ numbers continue after the highest REQ cited anywhere in the instance.

- [x] **Step 1: Write the failing test.** Append to `tests/governance/test_examples.sh`, above `finish` (after its instances exist):

```bash
# P5 R11 (H7; REQ-306): instances do not receive the factory's own design documents and proofs. scripts/factory-only.txt
# lists them; init removes every match and the manifest, walking the new tree (no .git exists yet); every factory
# document the template ships is matched — any path naming factory-v3-2, any ADR addressing a REQ of the factory spec
# except ADR-002 (it governs every instance's disposition gate), any review the examples manifest does not list, any
# proof of a factory REQ — so a REQ, ADR or proof added to them later is fenced with them; no document an instance's
# sessions read cites a fenced ADR by id.
# Covers: REQ-306
M="$ROOT/scripts/factory-only.txt"
ck "the fence manifest exists in the template source" test -f "$M"
ck "every manifest line matches a tracked path, and every factory document is matched" python3 - "$ROOT" "$M" <<'PY'
import fnmatch, os, re, subprocess, sys
root, man = sys.argv[1:]
globs = [l.strip() for l in open(man) if l.strip() and not l.lstrip().startswith("#")]
files = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, check=True).stdout.split()
hit = lambda g, f: f.startswith(g) if g.endswith("/") else fnmatch.fnmatch(f, g)
for g in globs:
    assert any(hit(g, f) for f in files), f"{g} matches nothing"
spec = open(os.path.join(root, "docs/specs/2026-09-25-factory-v3-2-design.md")).read()
reqs = set(re.findall(r"-\s+\*\*(REQ-\d{3}):?\*\*", spec))
ex = subprocess.run(["python3", os.path.join(root, "scripts/lib/specflow/examples.py"), "--root", root, "list", "demo_greeting"],
                    capture_output=True, text=True, check=True).stdout.split()
need = [f for f in files if re.search(r"factory[-_]v3[-_]2", f) and f.startswith(("docs/", "verification/"))]
for f in files:
    p = os.path.join(root, f)
    if f.startswith("docs/adr/0") and f.endswith(".md") and f != "docs/adr/002-security-disposition-decision.md":
        m = re.search(r"^addresses:\s*\[(.*?)\]", open(p).read(), re.M)
        if m and set(re.findall(r"REQ-\d{3}", m.group(1))) & reqs:
            need.append(f)
    if f.startswith("docs/reviews/") and f not in ex and not f.endswith("README.md"):
        need.append(f)
    if f.startswith("verification/") and f.endswith(".dfy"):
        if set(re.findall(r"Proves:\s*(REQ-\d{3})", "".join(open(p).readlines()[:5]))) & reqs:
            need.append(f)
missing = sorted({f for f in need if not any(hit(g, f) for g in globs)})
assert not missing, missing
PY
FENCED='docs/(specs|architecture|plans|reviews)/[^ )`]*(factory-v3-2|p1a-fresh-eyes|template-objective)|verification/factory_v3_2|docs/adr/003-|ADR-003'
for s in tauri flutter; do
  D="$WORK/other-$s"
  [ -f "$D/.specflow.yml" ] || continue
  ck "$s instance: no fenced document, no factory proof, no manifest" \
    bash -c 'cd "$1" && ! git ls-files | grep -qE "$2" && [ ! -e scripts/factory-only.txt ]' _ "$D" "$FENCED"
  ck "$s instance: ADR-002 stays — it defines the disposition gate the instance runs (P5 R11)" \
    test -f "$D/docs/adr/002-security-disposition-decision.md"
  ck "$s instance: traceability, covers and the ADR linkage pass with the factory documents gone" \
    bash -c "cd '$D' && bash scripts/check-traceability.sh >/dev/null && bash scripts/check-covers.sh >/dev/null && bash scripts/analyze-adr-plan-linkage.sh >/dev/null"
  ck "$s instance: no .dfy file is left, so Dafny is not needed" bash -c '! find "$1/verification" -name "*.dfy" 2>/dev/null | grep -q .' _ "$D"
  ck "$s instance: the documents a user or a session reads name no removed path and cite no fenced ADR by id" bash -c \
    'cd "$1" && ! git grep -qE "$2" -- README.md CLAUDE.md docs/GLOSSARY.md docs/security .claude .github schemas templates verification/README.md' _ "$D" "$FENCED"
done
D="$WORK/py"
ck "python instance: the demo's proof and review stay, and no factory proof or review arrives" \
  bash -c 'test -f "$1/verification/demo_greeting/greeting.dfy" && test -f "$1/docs/reviews/2026-05-28-v3.1-demo-review.md" && ! test -e "$1/verification/factory_v3_2" && [ "$(ls "$1/docs/reviews" | wc -l | tr -d " ")" = 1 ]' _ "$D"
ck "python instance: the tests that read factory documents skip them cleanly" \
  bash -c "cd '$D' && for t in state_model disposition_kernel threat_model_current; do bash tests/governance/test_\$t.sh >/dev/null 2>&1 || { echo \$t; exit 1; }; done"
```

- [x] **Step 2: Run** `bash tests/governance/test_examples.sh`. Expected: the manifest checks FAIL (no manifest), each instance still holds the factory documents (ADR-002's check passes already), the review-gate row's proof path and the security-review pointer name removed paths, and `test_disposition_kernel.sh` fails in the python instance once the proof is gone (after Step 3's init change, before the guard). Exit 1.
- [x] **Step 3: Implement (intent).** The manifest and init's removal; the document edits per Files; a presence guard for every test read of a fenced file (`test_disposition_kernel.sh`'s model checks sit inside `if [[ -f "$DFY" ]]`, as `test_state_kernel.sh`'s do). Then run the opt-in first run.
- [x] **Step 4: Run** the test, `test_review_gate_claims.sh` (the claim table's files exist), `test_security_review.sh`, `test_verify_release.sh`, and the gates — green; then `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="guided engineer profiles" bash tests/governance/test_first_run.sh` (opt-in, about 5 minutes): every instance's full gates pass with the factory documents gone — CI's first-run jobs repeat this on every PR.
- [x] **Step 5: Commit** — "feat(init): instances do not receive the factory's own spec, ADRs, architecture, plans, reviews and proofs — scripts/factory-only.txt, removed at init; tests read them only where they exist (REQ-306)"

---

### Task 14: `/next` is here — the 403 message, README's enforcement paragraph (H19; REQ-312, REQ-395, REQ-308)

**Files:** `scripts/configure-repo.sh:71-72`; `README.md:192-196`; `tests/governance/test_configure_repo.sh:27`; `tests/governance/test_onboarding_surface.sh:121-131`.

**Interfaces:** The 403 message: GitHub will not block merges (kept); "/next is the only gate" (kept); new: "it never prints a merge command until an APPROVE marker (or a maintainer waiver) for the current head exists — run bash scripts/run-quality-gates.sh locally before every merge; nothing stops a merge you type yourself." README: "Where GitHub Actions cannot start jobs … `/next` never prints a merge command without an `APPROVE` (or a waiver) for the head, and `bash scripts/run-quality-gates.sh` run locally checks the rest: those two are then the only checks, and nothing stops a merge you type yourself." No "later plan" and no "P5" in either.

- [x] **Step 1: Write the failing tests.** Replace `tests/governance/test_configure_repo.sh:27` with:

```bash
ck "HTTP 403: /next is here — no merge command without an APPROVE; the local gates; no 'later plan' (REQ-312)" \
  bash -c 'grep -qF "never prints a merge command" <<<"$1" && grep -qF "run-quality-gates.sh" <<<"$1" && ! grep -qiE "later plan|P5" <<<"$1"' _ "$out"
```

and `tests/governance/test_onboarding_surface.sh:121-131` (the comment and the loop) with:

```bash
# REQ-395: where Actions cannot start jobs, the README says what still checks a PR — in the enforcement section the spec
# names and in the free-private-repositories note — and /next, which exists, never prints a merge command without an
# APPROVE for the head.
fpr=$(awk '/^A note on free private repositories/{f=1} /^## Quick Start/{exit} f' README.md)
enf=$(awk '/merges via PR with:/{f=1} /^## Key Files/{exit} f' README.md)
ck "README states the Actions-cannot-start-jobs paragraph once (#33 third bootstrap F8)" [ "$(tr '\n' ' ' < README.md | grep -o 'cannot start jobs' | wc -l | tr -d ' ')" = 1 ]
ck "README's free-private-repositories note points at the enforcement section instead of repeating it" grep -qi 'enforcement' <<<"$fpr"
ck "README (enf): when Actions cannot start jobs, /next and the local gates are the only checks (REQ-395)" \
  bash -c 'grep -qi "cannot start" <<<"$1" && grep -qF "/next" <<<"$1" && grep -qF "run-quality-gates.sh" <<<"$1"' _ "$enf"
ck "README (enf): /next is present — it never prints a merge command without an APPROVE; no 'later plan'" \
  bash -c 'grep -qF "never prints a merge command" <<<"$1" && ! grep -qiE "later plan|\(P5\)" <<<"$1"' _ "$enf"
```

- [x] **Step 2: Run** both tests. Expected: the new checks FAIL. Exit 1.
- [x] **Step 3: Implement (intent).** Per Interfaces.
- [x] **Step 4: Run** both tests and the gates — green.
- [x] **Step 5: Commit** — "docs: /next is here — the 403 message and README's enforcement paragraph say it never prints a merge command without an APPROVE (REQ-312, REQ-395, REQ-308)"

---

### Task 15: Architecture artifacts match what shipped — the overview's kernel row and P5 notes; dfe-2, dfe-7, dfe-10, dfe-13; the open-medium proposal (H20, H9; REQ-341, REQ-340, REQ-382, REQ-334) — architecture-artifact update

**Files:** `docs/architecture/2026-09-25-factory-v3-2-overview.md` (`:36`, `:42`, `:76`, `:132`); `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` (`:103`, the dfe-2, dfe-7, dfe-10 and dfe-13 rows, the `:192` residual, four new residuals); `tests/governance/test_threat_model_current.sh` (`:4`, `:29-30`, checks above `finish`).

**Interfaces (content the test pins):**
- Overview `:36`: the kernel row keeps `derive(branch, branch_pr, open_lane_prs, facts, path, solo) -> Result` and adds "(records in `records.py`; `PR.mine`, `Facts.ship_phases_merged`, P5 R5–R6)". `:42`: the classifier is the single module both the CI check and `next.sh` use, through `pr_attestation`. `:76`: "`pipeline.parse_branch(name) -> Branch` is total … `pipeline.render_step(step, ctx) -> str` …" (the functions live in the wrapper, `scripts/lib/specflow/pipeline.py`, not in the kernel file). `:132`: "P2 created `attestation.py` (the CI check runs the base's copy); P5 extended it (`pr_attestation`, a `MEMBER` waiver's repository role, npm lockfile growth) and created `state.py`, its Dafny model `verification/factory_v3_2/state.dfy`, `pipeline.py`, `next.sh` and `/next`."
- Threat model `:103`: "P2 (…), P3 (dfe-3), P4 (…) and P5 (dfe-7, dfe-10) have shipped". dfe-7: `derive` is total and proved: an unknown branch derives `unknown-branch` with no merge step (`UnknownBranchNeverMerges`), both paths' prefixes are recognised whatever the path, a merge step needs an approved open PR (`MergeOnlyWhenApproved`), and the proof jobs run on both paths' branches (R12); Delivered in P5. dfe-10: `/next` lists other users' open PRs with the warning and never proposes checking one out; `next.md` warns before `gh pr checkout` of another author's PR; Delivered in P5. dfe-2: a `MEMBER`'s waiver needs the admin, maintain or write repository role (read at check time; unreadable fails closed). dfe-13: an npm lockfile gains no entry and no dependency name.
- Residual `:192`: keeps the open-medium residual and replaces "the follow-up proposal for the retrospective / P5 backlog is …" with R16's proposed REQ text, "Proposed for amendment C / P7".
- New residuals: "**`/next`'s facts come from the unverified wrapper** (REQ-341): the kernel decides order and precedence, never whether an artifact is complete; a wrong fact yields a wrong proposal, never a merge without an approved PR (the kernel's theorem, whatever the facts)." "**`/next` reads PR state through `gh`**: a PR head or base not in the checkout, or any `gh` failure, reads as no marker or no PR state (fail safe); a merge the user types is not `/next`'s." "**`/next` runs the checkout's own code against the checkout's view of the base** (P5 R7): `pipeline.py`, `state.py`, `records.py` and `attestation.py` are the checkout's copies, not the base's as `verifier.yml` materialises them, so a PR that edits them can make `/next` print a merge command the CI check would refuse; and `next.sh` never fetches, so a stale `origin/<base>` can judge `prompt_sha256` differently from CI — `--explain` prints the base's commit and date. Where branch protection works the `verifier` check still decides; where it does not (REQ-385's case), `/next` is advisory to the degree the checkout is trusted." "**A stacked PR's verifier instruction runs a script from an unreviewed branch** (P5 R22): `/next` renders `git show origin/<base>:scripts/run-verifier.sh` with the PR's own base, which on a stacked PR is a phase branch no review has approved and which the PR's author chose; the instruction says so and asks the maintainer to read the script first."

- [x] **Step 1: Write the failing test.** In `tests/governance/test_threat_model_current.sh`, change `:4`'s last clause to "the overview says what P5 extended and created", replace `:29-30` with:

```bash
ck "the overview no longer says P5 creates attestation.py or extends it in the future tense" \
  bash -c '! grep -qF "P5 creates \`attestation.py\`" "$1" && ! grep -qF "P5 extends it for" "$1"' _ "$OV"
ck "the overview says P2 created attestation.py and P5 extended it and created state.py, pipeline.py and next.sh" \
  grep -qE 'P2 created `attestation.py`.*P5 extended it.*`state.py`.*`pipeline.py`.*`next.sh`' "$OV"
```

and append above `finish`:

```bash
# P5 (REQ-341, REQ-340, REQ-382, REQ-334; H20, H9): the architecture artifacts say what P5 shipped.
# Covers: REQ-341
r7=$(row dfe-7); r10=$(row dfe-10); r2b=$(row dfe-2); r13b=$(row dfe-13)
for w in 'UnknownBranchNeverMerges' 'MergeOnlyWhenApproved' 'both paths'; do ck "dfe-7 states '$w'" grep -qF "$w" <<<"$r7"; done
ck "dfe-7 and dfe-10 are delivered in P5" bash -c 'grep -qE "\| P5 \|$" <<<"$1" && grep -qE "\| P5 \|$" <<<"$2"' _ "$r7" "$r10"
ck "dfe-10: /next lists other users' PRs with the warning and never proposes checking one out" \
  bash -c 'grep -qF "never proposes" <<<"$1" && grep -qF "next.md" <<<"$1"' _ "$r10"
ck "dfe-2: a MEMBER's waiver needs the admin, maintain or write role" grep -qF 'admin, maintain or write' <<<"$r2b"
ck "dfe-13: an npm lockfile gains no entry" grep -qF 'no `node_modules/` entry' <<<"$r13b"
ck "the narrative lists P5 among the shipped plans" grep -qF 'P5 (dfe-7, dfe-10)' "$TM"
ck "the open-medium residual carries the proposal for amendment C / P7, not 'P5 backlog'" \
  bash -c 'grep -qF "Proposed for amendment C / P7" <<<"$1" && ! grep -qF "P5 backlog" <<<"$1"' _ "$rr"
for w in "come from the unverified wrapper" "reads PR state through" "runs the checkout's own code" "from an unreviewed branch"; do ck "a residual states '$w'" grep -qF "$w" <<<"$(awk '/^## Residual risks/{f=1} f' "$TM")"; done
ck "overview: render_step and parse_branch live in pipeline.py" grep -qF 'pipeline.render_step' "$OV"
```

- [x] **Step 2: Run** `bash tests/governance/test_threat_model_current.sh`. Expected: the new checks FAIL. Exit 1.
- [x] **Step 3: Implement (intent).** Per Interfaces; element ids, frontmatter and the Domain checklist unchanged; `check-architecture.sh` stays green.
- [x] **Step 4: Run** the test, `bash scripts/check-architecture.sh`, and the gates — green.
- [x] **Step 5: Commit** — "docs(architecture): the overview's kernel row and P5 notes, dfe-2, dfe-7, dfe-10, dfe-13 and the residuals match what P5 shipped; the open-medium proposal for amendment C (architecture-artifact update; REQ-341, REQ-340, REQ-382, REQ-334)"

---

### Task 16: The spec's IMPLEMENT entry, whole-branch verification and the PR bodies

**Files:** `docs/specs/2026-09-25-factory-v3-2-design.md` (frontmatter `amended:` gains one entry after the P5 PLAN entry; REQ body changes: REQ-389's (R19) and the sync of REQ-311's, REQ-340's, REQ-382's, REQ-385's and REQ-393's to what shipped (PR #48 verifier runs 4 and 5)); `tests/governance/test_spec_lifecycle.sh` (one check inside the `V32` block).

**Interfaces:** the entry, as shipped, is the spec's P5 IMPLEMENT `amended:` entry — the spec holds its text, which this plan does not copy (an earlier copy here went stale, PR #48 verifier run 4, finding 5). It opens "rulings of the P5 plan … that narrow, extend or read literal REQ text, REQ bodies unchanged except REQ-389's and, synced to what shipped, REQ-311's, REQ-340's, REQ-382's, REQ-385's and REQ-393's" and records, in order: the plan's rulings — REQ-341 (R7, R8, R21), REQ-382 (R9, R20), REQ-334 (R10, R15), REQ-306 (R11), REQ-340 (R12: the proof jobs run on impl/, phase/validate, phase/plan-, design/, build/ and ship/ heads, and on phase/security and phase/release, the regulated path's ship pair, not patch/), REQ-322 (R13), REQ-389 (R19), REQ-310, REQ-385 (R22: origin/<base>, the stacked merge); the final-review rulings — rule 1b for markers and waivers (a `MEMBER`'s or `COLLABORATOR`'s comment counts only with a writing role; a known non-writing role neither accepts nor blocks; an unreadable role is never accepted and keeps blocking; fixtures 72–102), the base binding (`base-mismatch`, `request-changes-base-mismatch`), `--match-head-commit`, the fork-PR exclusion and the team-mode approval rule (REQ-385), `next_version` on phase/security and phase/release (REQ-341), the `sec-` reservation (REQ-340), `base-lockfile-v1` (REQ-334); REQ-389's body change (full mode, the per-article citation); PR #47's findings on amendment B (the two art-release-readiness narrowings, the two constitution corrections signed off in #48's merge comment); the read of REQ-385's 'APPROVE marker' as including an accepted waiver and rule 1b's narrowing of the pre-P5 rule; and the sync of REQ-311, REQ-340, REQ-382, REQ-385 and REQ-393's bodies (PR #48 verifier run 4, each an appended 'As amended by P5 (PR #48):' sentence).

- [x] **Step 1: Write the failing check** in `tests/governance/test_spec_lifecycle.sh`, inside the `V32` block after the P5 PLAN checks:

```bash
  a5i=$(grep -F 'P5 IMPLEMENT PR' <<<"$fm" || true); miss=""
  for t in 'REQ-341' 'REQ-382' 'REQ-334' 'REQ-306' 'REQ-340' 'REQ-389' 'REQ-310' 'REQ-385' 'R9' 'R11' 'R12' 'R19' 'R21' 'R22' \
           'full mode' 'origin/<base>' 'REQ bodies unchanged'; do
    grep -qF -- "$t" <<<"$a5i" || miss="$miss [$t]"
  done
  if [[ -z $miss ]] && [[ $(grep -nF 'P5 PLAN PR' <<<"$fm" | cut -d: -f1) -lt $(grep -nF 'P5 IMPLEMENT PR' <<<"$fm" | cut -d: -f1) ]]; then
    pass "the P5 IMPLEMENT amended: entry records the wrapper rulings, below the P5 PLAN entry"
  else fail "the P5 IMPLEMENT amended: entry is missing, out of order, or omits:$miss"; fi
```

- [x] **Step 2: Run** `bash tests/governance/test_spec_lifecycle.sh` — the new check FAILs. **Step 3:** add the entry. **Step 4:** the test passes. **Step 5: Commit** — "docs(spec): the P5 IMPLEMENT amended: entry — the wrapper, fence, waiver-role, npm, proof-job and guided rulings (REQ-341, REQ-382, REQ-334, REQ-306, REQ-340, REQ-389, REQ-310)".
- [x] **Step 6: Whole-branch verification** (record each result in the PR body):
  - `time PATH="$HOME/.venvs/factory-tools/bin:$PATH" bash scripts/run-quality-gates.sh` — green, under 3 minutes (about 1:30 before P5; record the new tests' own times).
  - `actionlint .github/workflows/*.yml` — clean.
  - `dafny verify verification/factory_v3_2/state.dfy` and `…/disposition.dfy` under 4.11.0 and 4.9.1 — verified, record the counts.
  - `bash scripts/verify-doc.sh docs/plans/2026-09-28-factory-v3-2-p5-plan.md` (silent), `bash scripts/analyze-adr-plan-linkage.sh`, `bash scripts/check-traceability.sh`, `bash scripts/check-architecture.sh`, `bash scripts/check-covers.sh` (the full P5 set claimed and cited), `bash tests/governance/test_plan_template.sh` — pass.
  - `bash scripts/check-test-first.sh --base phase/plan-factory-v3-2-p5 --head HEAD` — PASS over every commit; paste its output.
  - `git grep -nE '(^|[ (])python[ ]+-m' -- scripts tests stacks` and `git grep -nF -e --jq -- scripts` — empty; no test calls the real `gh` or `claude` (`git grep -nE '^[^#]*\bgh (pr|api) ' -- tests/governance/test_*.sh` shows only stubbed calls).
  - Opt-in (about 5 minutes): `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="guided engineer profiles" bash tests/governance/test_first_run.sh` — green, REQ-393's checks included.
  - `git diff phase/plan-factory-v3-2-p5 --stat` touches only the files named in Tasks 1–16; `git status --porcelain` empty.
- [x] **Step 7: The IMPLEMENT PR** (`--body-file "$(mktemp)"`; base `phase/plan-factory-v3-2-p5`; retarget it to `main` and update it before the plan branch is deleted — strict protection). The body states: the Partial claims and R3's staged claims (REQ-342, REQ-393, REQ-345 joined `implements:` in Tasks 7, 8, 12); the rulings R1–R22; **Architecture-artifact updates:** Task 15, named as such; the H1–H23 disposition; the fixture edits of Task 4 (which `MEMBER` fixtures gained a role); R18's schema-migration exception, for the maintainer to confirm in the merge comment; the live `gh api …/collaborators/…/permission` shape check with the maintainer's token and the draft-PR probe's result with `verifier.yml`'s `GITHUB_TOKEN` (Task 4 Step 3; R9) — this PR's own `verifier` run does not exercise the lookup (the check runs the base's `attestation.py`), so the first real use is a `MEMBER` waiver on a PR opened after this one merges, and on this organisation repository the maintainers are `MEMBER`; the measured figures (gates before and after, each new test's time, Dafny counts, the opt-in run); **what the user will see:**
  - *`/next`* tells you where the pipeline stands and the one next step, on either path; in the guided profile it runs the step and pauses at seven named points; it never runs the verifier (it prints the second-terminal command) and never prints a merge command without an `APPROVE` or a waiver for the head and, in team mode, a human approval.
  - *A fresh instance* no longer contains the factory's own spec, ADR-003, architecture, plans, reviews and proofs (it keeps ADR-002, which defines the disposition gate every instance runs — R11, `scripts/factory-only.txt`, the glossary's "Factory documents"); tauri and flutter instances no longer need Dafny; the python demo stays.
  - *A `MEMBER`'s waiver* now needs the admin, maintain or write repository role; an `OWNER`'s is unchanged.
  - *An npm lockfile change that adds a package* is no longer Dependabot-exempt.
  - *`prompt_sha256` changes on merge* (Task 10 edits the verifier skill and prompt): PRs open at that moment need their verifier run again.

---

## Review Focus

1. **This PLAN PR and its IMPLEMENT PR through `/next`.** On `phase/plan-factory-v3-2-p5` with PR #N open and no marker, `next.sh` prints `state: plan awaiting-verifier` and the second-terminal instruction verbatim with `origin/main`; on `impl/plan-5-orchestrator`, stacked, the instruction uses `origin/phase/plan-factory-v3-2-p5` and warns that the base is not `main` (R22). After a solo `APPROVE` on the PLAN PR, with the IMPLEMENT PR stacked on it, it prints `gh pr merge <N> --merge` and the retarget (`gh pr edit <M> --base main`), never `--squash` (R22), and the guided profile pauses at `merge`; after a `REQUEST_CHANGES` it prints the findings and no merge command; a PR head not pulled locally reads as no marker. `MergeOnlyWhenApproved` is the theorem behind each (R5, Tasks 2, 3, 6).
2. **A fresh guided python instance on `main`, no remote** — `state: none idle`, `git checkout -b design/<slug>` then brainstorming; the engineer (regulated) instance proposes `phase/spec-<slug>`; `gh` is never called and neither instance can reach `awaiting-verifier` or `CreatePr` (`NoBlindCreatePr`, `UnknownPrStateNeverAwaitsVerifier`, `RemoteLessMainIsIdle`; R4, Task 8).
3. **A read-only organisation member's waiver on a team repository** is rejected as `waiver-not-writer`; one whose role the CI token cannot read is rejected as `waiver-permission-unknown`; an `OWNER`'s needs no lookup; the check's messages are otherwise unchanged, and `next.sh` gets the same answer because both go through `pr_attestation` (R9, Task 4).
4. **Amendment B against REQ-343, `review-gate.md`, `RUBRIC.md` and the verifier skill.** Every clause of REQ-343 and every correction routed to it (the Dependabot sentence as P4 shipped it, the admin bypass of the review, the solo sign-off, P3 R19, P3 R20) is in the article text; no interim reading, override sentence or deadline remains where a session reads the rules; the previous-tag control (`verify-release.sh` plus the PR template's checkbox) is unchanged; nothing mechanical changes (R2, section "Amendment B").
5. **A tauri guided instance after the fence** has no factory document, no `.dfy` and no manifest; its traceability, covers and ADR-linkage checks pass; the demo's absence and the factory documents' absence leave `check-architecture.sh` and `verify-release.sh` check (6) with nothing inherited to grandfather; a python instance keeps the demo and its proof (R11, Task 13).
6. **The factory's own history on `main`** (fixture of PRs #1–#46): in the template source (lanes by default) `/next` proposes `ship/0.1.0` with the template-source note; with `--path regulated`, `phase/validate`; `impl/plan-1a-first-run` parses as an `Impl`, `phase/spec` and `impl/fix-p0-ci-enforcement` as `Unknown`; the closed #21 and merged #22 on `impl/plan-0-plan-scoping` read as merged (R5, R6, R8, Task 6).

## Deferred by design

- **Open clauses of claimed REQs** are under **Partial claims**, each with the plan that relists the REQ: P6 — `/release --tag` behind `TagRelease` (REQ-383), the tag-time replay of the gates and of the Dependabot rule (REQ-350), the CI-built manifest (REQ-384), the factory's switch to lanes (REQ-381). P7 — amendment C naming `next.sh`, `state.py` and `pipeline.py` (REQ-326); the habit-tracker walk (REQ-391); `render_dashboard.py` reading `--json` (REQ-370).
- **A PreToolUse hook that blocks `gh pr merge` or pushes to `main`** (H5): ruled out (R14); proposed for the P7 retrospective as a `permissions.ask` rule.
- **Open mediums counted toward `medium_cap`** (H9): R16's proposed REQ text for amendment C / P7; no kernel change without an ADR-002 revision.
- **A mechanical check that the PR body links a waiver** (H15): not a check (the body is author-editable and not a re-trigger); `--explain` reports it (R20).
- **A format check for `confirmed_by:`** (H17): not adopted — a handle and a date prove nothing about who confirmed; the verifier's full-mode confirmation is REQ-389's control (R19).
- **Repository-role checks for attestation markers** (R9): no longer deferred — the final review adopted them (the spec's P5 IMPLEMENT `amended:` entry): a `MEMBER`'s or `COLLABORATOR`'s marker needs the admin, maintain or write role like a waiver, since a solo marker is self-attested by the author (REQ-314), never by a read-only third party.
- **`verify-dafny` on every PR** (R12): it adds nothing gates section 2 does not already run on every PR; running it on doc-only PRs would spend CI minutes for no signal.
- **Retrospective branches in the kernel** (R8): ADR-003 lists no retro constructor; adding one is an ADR change for P7's retrospective to propose if `/next` should track retros.
- **Plans without `## Build N` sections** (R6): the factory's own P0–P5 plans and the demo's are not tracked by `/next`'s `unbuilt`; `--explain` says so.
- **`next.sh` fetching from the remote** (R7): never — a stale local view is explained (`--explain` prints the base's commit and date), never refreshed behind the user's back; from the P5 lows patch on, a base tip gh reports (`baseRefOid`) that differs from `origin/<base>` prints a note and a why line naming both tips and `git fetch origin <base>` (PR #48 verifier run 7, code finding 3; the derivation is unchanged).
- **Signing-key detection beyond `user.signingkey`** (PR #48 verifier run 7, code finding 3): `signing_key_present` reads only `git config user.signingkey`, so a GPG setup that signs with gpg's default key gets an unneeded `unsigned-tag` confirmation. The residual errs toward asking; detecting gpg's default secret key would make the fact depend on the host's keyring, so it is not adopted.
- **`next.sh` running the base's copies of its modules** (R7): not adopted — `pipeline.py` is itself the checkout's, so materialising `state.py` and `attestation.py` from `origin/<base>` would not make `/next` a control; Task 15 records the residual, and the server-side `verifier` check stays the control where protection works.
