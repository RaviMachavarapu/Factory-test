---
type: plan
phase: PLAN
spec: 2026-09-25-factory-v3-2
decisions: [ADR-002]
implements: [REQ-320, REQ-321, REQ-322, REQ-323, REQ-324, REQ-325, REQ-394, REQ-306, REQ-332, REQ-333, REQ-389]
created: "2026-09-27"
---

# Factory v3.2 — P3: Mechanized Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** the gates the constitution describes stop being conventions. A release is blocked by a pure, proved decision function (REQ-322) over findings whose severity is derived from a required CVSS v4.0 vector, so it cannot be relabelled; the release notes are checked at PR time (REQ-324); each commit's source change needs a test in the same or an earlier commit (REQ-321); every claimed REQ needs a test that cites it (REQ-323); coverage has a floor per toolchain that a PR cannot lower (REQ-325); and the ARCHITECTURE gate follows the claims (REQ-320, REQ-394), with `confirmed_by:` required on guided-profile architecture artifacts (REQ-389's check).

**Architecture:** ADR-002 is the design. The verified kernel is `scripts/lib/specflow/disposition.py` — `decide(review, disposition, prior, medium_cap, expiry_horizon_days, run_date) -> Verdict` over the frozen records in `scripts/lib/specflow/records.py` — whose Dafny model `verification/factory_v3_2/disposition.dfy` proves PASS iff rules 1–5, permutation invariance, and that lows with fresh ids do not affect rules 2–5. Everything else is unverified and fixture-tested: `cvss4.py` (the FIRST scoring algorithm over vendored lookup data), `blocks.py` (the one parser of review and disposition blocks, which `floor.py` now imports), `disposition_gate.py` behind `scripts/check-security-disposition.sh` (version resolution, tags, the ids-only-added walk, the base-ref rubric), `release_gate.py` behind `scripts/verify-release.sh`, `frontmatter.py` (the one frontmatter reader), `packinfo.py` (source roots, test globs and test-first rules), `scripts/check-test-first.sh`, `scripts/check-covers.sh` and `scripts/lib/specflow/coverage.sh`. `run-quality-gates.sh` gains section 6 (Document gates) and section 7 (Release gates); section 1 measures coverage.

**Plan style (REQ-380):** test code included (governance tests, fixture tables, stub tools); implementation as intent, never bodies. Documents are described by the content the tests pin.

**Tier:** regulated path (REQ-381: P0–P5 walk `phase/*`, `impl/*`). This plan is the PLAN-phase PR from `phase/plan-factory-v3-2-p3` to `main`. The Dafny proof follows it on the same branch (Ruling R1), so the PLAN PR carries the plan and the proof. `impl/plan-3-mechanized-gates` is cut from the plan branch and carries Tasks 1–15 as the IMPLEMENT-phase PR stacked on it (the P2 pattern): retarget it to `main` before the plan branch is deleted. `main @ f003112` carries the P2 attestation gate and the P4 floor, so both PRs get a real headless marker with no bootstrap: `git show origin/<base>:scripts/run-verifier.sh | bash -s -- <PR>`. Task 15 changes `.claude/skills/verifier/SKILL.md`, so `prompt_sha256` on `main` changes when the IMPLEMENT PR merges (open PRs then need a verifier re-run); the IMPLEMENT PR's own run reads the plan branch's copy. No constitution text changes in P3 (amendment B is P5's, C is P7's); R19 records the one conflict P3 creates with `art-release-readiness` (`constitution.md:187`, "tag missing") and hands it to amendment B.

**Spec:** `docs/specs/2026-09-25-factory-v3-2-design.md`, "Must Have — P3" (REQ-320, 321, 322, 323, 324, 325, 394, with REQ-322's Precondition, Postcondition, Invariant and Verification-scope lines and REQ-324's "as amended by the threat model" clause), plus the P3 slices of REQ-306 (`test_traceability.sh` delegates to `check-covers.sh`), REQ-332 (the block schema and the migration P4 handed over), REQ-333 (the checker scoped to `implements:`) and REQ-389 (`check-architecture.sh` requires `confirmed_by:` when `profile: guided`). `decisions: [ADR-002]`: REQ-322 is `[verifiable-model]` and ADR-002 governs it. **The proof `verification/factory_v3_2/disposition.dfy` (`// Proves: REQ-322`) is owed the moment this plan lists REQ-322** (REQ-327: `check-traceability.sh` fails without it), and it lands on this plan branch in the commit right after this plan (R1). No REQ body changes. Following the P4 precedent (the spec's `amended:` entry for PR #36), the IMPLEMENT PR adds one `amended:` entry to the spec's frontmatter (Task 15) recording the rulings that narrow, extend or read the literal REQ text: R4's inherited-artifact grandfathering, by slug at the base ref (REQ-389); R6's `carried_from:` schema field, R9's runtime band re-check, R10's reading of "lows never affect rules 2–5" (the proved property holds for a low with a fresh id and no due prior entry, since rule 4's own downgrade clause makes the unconditional form false), R12's walk over every changed security file with tagged priors read from the tag, and R20's informational 0.0 vector (REQ-322); R14's tag-after-merge and check (6)'s instance skip of the inherited specs by slug (REQ-324); R15's comment-only rule, non-source files and pin bumps (REQ-321). Each ruling is also recorded in the IMPLEMENT PR body.

**Partial claims:**
Context citations (PR #42 fourth verifier run, low 6): REQ-380, REQ-327, REQ-343, REQ-388, REQ-360 and REQ-310 are cited as context, not claims, in this plan and its commits — REQ-380 and REQ-327 are P0's, REQ-360 P1's, REQ-310 P2's, REQ-388 P4's, and REQ-343 is amendment B's (P5); each citing commit also cites the P3 REQ it changes.

- **REQ-320:** delivered — the `[verifiable*]` → `req_map` check scoped to the claims (R3), the threat-model checks unchanged, wired into `run-quality-gates.sh` section 6. Nothing stays open.
- **REQ-321:** delivered — the checker, per-pack `test_first_rules`, the template's own rules (R15), the `ci.yml` step with the PR body and base SHA. Residual (recorded in the threat model's residuals, Task 14): a force-push or squash before the first push rewrites the history the checker reads.
- **REQ-322:** delivered — kernel, model, records, parser, scorer, schema, wrapper, migration, wiring into the gates and `/security-review`. Open → P5: the `phase/security`/`phase/release` default version comes from `next.sh`'s `Facts.next_version`; P3 resolves those branches from the changed files (R11). Open → P6: `release.yml` replays the wrapper at the tag (REQ-350). Residual (dfe-3 and `RUBRIC.md`, Tasks 6 and 14): a current medium left `status: open` passes rules 2–5 with no owner, no expiry and no count against `medium_cap` — ADR-002 rule 3 and the constitution's SECURITY exit gate count accepted/deferred mediums only, so a stricter rule would contradict both — and carry-forward accepts it again at the next release, so a medium can stay open indefinitely; the verifier and the second reviewer look for long-open mediums.
- **REQ-323:** delivered, switched on in Task 13 once every claimed REQ has its test (R18).
- **REQ-324:** delivered at PR time — the three docs, "the tag does not yet exist", the notes' `## Artifacts` rows equal to `dist/manifest.json` row for row when it is present (otherwise every row has the file, sha256, size shape), known-limitations naming every accepted/deferred SEC id, the disposition gate, the ship-time proof assertion, the base-ref `medium_cap` (through the wrapper), and `/release` invoking it. Open → P6: REQ-384's CI-built manifest becomes the transcription source (P3 checks whatever `dist/manifest.json` is present), the tag-time re-check (REQ-350), and `/release --tag` (REQ-383). P3 moves `/release`'s tag step after the merge (R14), which is the part of REQ-383 that REQ-324's "the tag does not yet exist" forces now. In an instance, check (6) skips R4's inherited specs — by slug (`frontmatter.INHERITED_SPEC_SLUGS`), each present at the base ref, never by `created:` — with a note: the inherited factory spec's `[verifiable-model]` REQ-341 is claimed by no plan until P5, and without the skip every instance's ship PR would fail until then.
- **REQ-325:** delivered for all three stacks; the base-ref read P2 deferred; the skeleton figures are measured in Task 12's opt-in run.
- **REQ-394:** delivered.
- **REQ-306:** the P3 slice (delegation to `check-covers.sh`) closes REQ-306.
- **REQ-332:** the P3 slice (the block schema with required vectors; the four documents migrated; the parser accepts `suppresses:` and `inherited:`) closes REQ-332.
- **REQ-333:** the P3 slice (scoping) closes REQ-333.
- **REQ-389:** only the `check-architecture.sh` clause. Open → P5: the proposals with plain-English rationale and consequence, the decisions/acknowledgements split, the verifier code-mode confirmation in guided solo mode, and `/next`'s confirmation points.
- **Inherited factory artifacts in instances (F-10/W-7, inherited factory docs; owner P5, due by P5):** an instance keeps `docs/specs/2026-09-25-factory-v3-2-design.md`, its overview and threat model, ADR-002 and ADR-003, and the P0–P4 plans (`init-project.sh:585-600` removes only other stacks' examples and `stacks/`). P3's effects there, each stated in the IMPLEMENT PR's "what the user will see" and in the known-limitations of the next factory release: (1) R4's `confirmed_by:` rule and `verify-release.sh` check (6) grandfather the inherited specs by slug (`frontmatter.INHERITED_SPEC_SLUGS`: the demo and the v3.2 spec, with their overviews, threat models and REQ-addressing ADRs), each present at the base ref — never by a spec's `created:` date, which its author writes — so neither fires on those files; (2) `verification/factory_v3_2/disposition.dfy` ships to every instance (the inherited P3 plan claims REQ-322, so `check-traceability.sh` requires the proof), so tauri and flutter instances, which had no proof, now need Dafny for a local gates run (section 2 hard-fails without it) and `init-project.sh --doctor` reports it MISSING; their CI `gates` job already installs the pinned Dafny 4.9.1 (`ci.yml:45-52`).
- **Open → P7:** amendment C (REQ-326) names the files P3 ships as the mechanisms for `art-test-first`, `art-threat-driven-security` and `art-release-readiness`.

**ARCHITECTURE artifacts:** P3 walks the full phase path, so its IMPLEMENT branch may update the architecture documents the spec's ARCHITECTURE PR produced where P3 completes what they describe. Each edit is its own task with a governance test:
- **Task 14:** `docs/architecture/2026-09-25-factory-v3-2-overview.md` — `:41` (the frontmatter parsers "to be lifted … in P3" become lifted), `:131` ("P3 creates …" becomes what shipped, with the real module names), `:133` (`check-architecture.sh`'s hand-off is done); `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` — the narrative's shipped-plans sentence (`:103`), the dfe-3 row (`:111`) and the `:188` residual ("until P3 this is convention"). The demo threat model is untouched.

The IMPLEMENT PR body lists Task 14 under **Architecture-artifact updates**. No ADR is added or changed.

**Rulings** (decided here; the IMPLEMENT PR implements them):
- **R1 — the proof travels on the plan branch (H1).** `check-traceability.sh` (REQ-327) fails as soon as a plan lists REQ-322 in `implements:` and no `verification/**/*.dfy` carries `// Proves: REQ-322`, and `ci.yml`'s `gates` job runs on every PR, the PLAN PR included. So `verification/factory_v3_2/disposition.dfy` is written by the step right after this plan, on `phase/plan-factory-v3-2-p3`, to the shape under Interfaces "The Dafny model". The PLAN PR is then green; the IMPLEMENT PR adds the Python twin and the fixtures that mirror the model (the overview's three-layer rule). The IMPLEMENT branch may amend the proof only in a commit that keeps the twin (`disposition.py`), the fixtures and the model's names in step, and every agent that touches the proof verifies it under the CI-pinned Dafny 4.9.1 and the local 4.11.0 (H16). `verifier.yml`'s `verify-dafny` job runs only for `impl/`, `phase/validate` or the `has-verification` label (`verifier.yml:97-100`), so on the PLAN PR the proof is verified by `ci.yml`'s gates section 2 (`run-quality-gates.sh:43`, `dafny verify $(find verification -name '*.dfy')`), which runs on every PR (H14). The label does not exist in the repository and is not created. The proof's presence broke `test_examples.sh`'s "empty docs/specs and docs/plans" case (REQ-306): with every spec deleted, `// Proves: REQ-322` names a REQ no live spec defines, which `check-traceability.sh` rightly fails (REQ-327). A deleted spec takes its proofs with it, so that case now also deletes `verification/*/`; the PLAN PR carries this one test change beside the plan and the proof.
- **R2 — one frontmatter reader, two exceptions (H2).** `scripts/lib/specflow/frontmatter.py` holds `strip_quotes`, `strip_comment`, `parse_text`, `read`, `parse_list`, `TAG_RE`, `tagged_reqs`, `spec_slug`, `live_specs` and `claims`, lifted from `check-traceability.sh:22-69`, `analyze-adr-plan-linkage.sh:20-66` and `architecture.py:69-107`; those three and `check-covers.sh` import it. `config.py` and `attestation.py` keep their own copies: `verifier.yml:76-86` and `run-verifier.sh:511-513` materialise each of them alone from the base ref with `git show`, so an import of a sibling module would break the base-ref run. `architecture.py`'s rich YAML-subset parser (`:113-223`) stays where it is (architecture documents only).
- **R3 — what REQ-320's scoping checks.** A live spec is in scope when a plan names it in `spec:` or its overview or threat model exists (P4's rule, kept: the SPECIFY skip and the `phase/arch-<slug>` bite). The threat-model checks apply to every in-scope spec. The `req_map` check applies to: every tagged REQ of the spec when some plan without `implements:` names it (walked whole, as `check-traceability.sh` does); the tagged REQs in the union of `implements:` across all plans when plans name the spec only through `implements:`; and every tagged REQ when no plan names the spec yet (the ARCHITECTURE PR, `art-kernel-boundary`). After the ARCHITECTURE PR the obligation follows the claims — the same rule REQ-327 applies to proofs — so a spec amendment that tags a new REQ does not turn unrelated PRs red until a plan claims it.
- **R4 — the REQ-389 slice.** When `.specflow.yml` exists at the root and its `profile` is `guided` — read with `config.py`; a `.specflow.yml` with no `profile:` key counts as guided, `config.DEFAULTS`' value, as it does everywhere else — each in-scope spec's overview, its threat model, and each `docs/adr/*.md` whose `addresses:` names one of the spec's tagged REQs must carry a non-empty `confirmed_by:` frontmatter value. The template source has no `.specflow.yml`, so the rule is inert there. **Inherited-artifact cutoff** (the date-based rule first written here — a `created:` on or before 2026-09-27 — is superseded by the slug-based rule under **As implemented** below and is not the rule): every spec an instance inherits from the template today — the demo and the factory's own v3.2 spec, with its overview, threat model, ADR-002 and ADR-003, none carrying `confirmed_by:` — is grandfathered, with its overview, threat model and ADRs, and a guided instance keeps them (`init-project.sh:585-600` removes only other stacks' examples and `stacks/`). So a freshly initialised guided instance — the template's CI `first-run (guided)` job and the "every example removed" case included — passes section 6. A factory spec created after the cutoff that instances would inherit is F-10/W-7's to fence before it ships (P5). What `confirmed_by:` means (who acknowledges, the verifier's confirmation) is P5's. **As implemented** (PR #41 verifier finding 3): the grandfathering is keyed on the inherited specs' fixed slugs (`frontmatter.INHERITED_SPEC_SLUGS`: the demo and the v3.2 spec, with their overviews, threat models and REQ-addressing ADRs such as ADR-002/003), each present at the base ref — never on a spec's own `created:` date, which its author writes, so a backdated new spec is not grandfathered.
- **R5 — one block parser (H4).** `scripts/lib/specflow/blocks.py` is the only reader of `---`-fenced blocks in `docs/security/*-review.md` and `*-disposition.md`. `floor.py` imports it and deletes `parse_inline_list` (`:57-103`), `_version_key` (`:106-109`) and `_parse_disposition_blocks_at` (`:118-143`); `load_dispositions` and `_latest_disposition_entries` become thin wrappers over `blocks.latest_entries`, keeping their return shapes and error texts (`test_suppressions.sh` and `test_suppression_expiry.sh` grep them). The parser has two modes: **floor mode** (P4's behaviour — a schema header is optional, entries are checked for known keys, a status value and a date format) for the suppression scan and the expiry notice, and **gate mode** (header required, joined preconditions, rationale length) for the disposition gate. One latest-entry reduction serves both.
- **R6 — carried-forward findings are re-listed, not redefined.** ADR-002 rule 4 requires a latest prior entry of severity medium or above to appear in the current disposition, and rule 1 then requires it in the current review; `check-traceability.sh:161-170` fails a SEC id defined in two reviews. The re-listed review block therefore carries `carried_from: <prior version>`, and the SEC-uniqueness check counts a block as a definition only when it has no `carried_from:`. The wrapper checks that `carried_from` names an earlier version whose review defines or carries the id (a parser error otherwise). SEC ids are still never reused.
- **R7 — the demo's schema header is a schema migration, not a second addendum (H3).** `docs/security/README.md:32-46` allows one post-tag addendum. Adding the schema header block to `0.0.1-demo-review.md` and `0.0.1-demo-disposition.md` adds no SEC id, no finding and no text about the release; it restates the file in the schema the gates now read. README gains `## Schema migrations`: a released review or disposition may be rewritten into a new schema version's syntax (the header block, key renames) without adding, removing or re-scoring any finding and without a new SEC id; it is not an addendum; each migration is listed with its date and plan. The P3 entry lists the demo pair (header only) and the tauri skeleton pair (header, `vector:` → `cvss_vector:`, vectors for SEC-002 and SEC-003; the skeleton is a pack document, never tagged). A migrated demo file also keeps a python instance's untagged copy of the demo docs parseable.
- **R8 — CVSS v4.0 data provenance (H12).** FIRST's calculator is vendored once, at authoring time, from `https://github.com/FIRSTdotorg/cvss-v4-calculator` at commit `c5b0d409ae9f57c44264c6ce5f27d89298e1d32a` (2024-08-19, the default branch's head on 2026-09-27; licence BSD-2-Clause per the GitHub API): `cvss_lookup.js` (the 270-entry macro-vector → score table), `max_composed.js`, `max_severity.js`, `cvss_score.js` (`macroVector()`, `m()`, `cvss_score()`, rounding `Math.round(value * 10) / 10`), `metrics.js` and `LICENSE`. The data becomes a Python module (`cvss4_data.py`, dict literals, so importing it performs no file I/O); the module header and `cvss4_data.SOURCE` record the URL, the commit and each fetched file's sha256; the licence ships as `scripts/lib/specflow/cvss4_LICENSE`. Nothing is fetched at test time. The conformance vectors are produced by running FIRST's own JavaScript with node 24 (`tests/governance/fixtures/cvss4/generate.mjs`, command recorded in the JSON).
- **R9 — the kernel re-checks the vector.** ADR-002 derives severity in the parser; the overview (`:75`) lists "invalid vector" among `decide`'s preconditions. `decide` raises `ValueError` unless `cvss4.finding_severity(f.cvss_vector) == f.severity` for every finding (R20: band `none` reads as low): the runtime-contract layer of the three-layer pattern (`verification/README.md:9-12`) re-checks what the parser guarantees. `cvss4` is pure (no I/O), so the kernel stays pure. The Dafny model takes the severity as given (it is derived outside the model, as ADR-002 says). **As implemented** (PR #42 second verifier run, high): severity is the CVSS v4.0 *base* score, so `cvss4.finding_severity` takes base-only vectors (`cvss4.base_only`): a finding's `cvss_vector` carrying any Threat, Environmental or Supplemental metric is a parser error in `blocks.parse_review` and a `ValueError` in `decide` (kernel fixtures 35, 36); `cvss4.score` still scores full vectors for FIRST's conformance vectors.
- **R10 — "lows never affect rules 2–5".** ADR-002 rule 4 compares a carried-forward id's current severity with its prior severity, so a prior medium re-listed as low is exactly the downgrade the rule exists for. The invariant is therefore proved for a low finding whose id has no due prior entry (no latest prior entry with severity medium or above and status open, accepted or deferred): adding it and its entry leaves the rule 2–5 violations unchanged. Fixture 24 pins the boundary. ADR-002 is not changed: its rule 4 already defines the downgrade path.
- **R11 — the wrapper's version resolution.** `--version V` evaluates V. Else a branch named `ship/<version>` (`SPECFLOW_HEAD_BRANCH`, else `GITHUB_HEAD_REF`, else `git rev-parse --abbrev-ref HEAD`) evaluates that version. Else, when the base ref resolves, each version named by a changed file (`docs/security/<v>-review.md`/`-disposition.md`, `docs/releases/<v>-notes.md`/`-migration.md`/`-known-limitations.md`; committed, uncommitted, or untracked — `git ls-files --others --exclude-standard`) is evaluated, in semver order; a changed file naming no version (`RUBRIC.md`, `README.md`, `store-checklist.md`) is noted. Nothing named, or no base ref, prints a `SKIP`. A tagged version is printed as a `SKIP` and never evaluated as current; R12's removal walk still covers its files, and later versions read its entries from the tag. `phase/security`/`phase/release` use the changed files until P5's `next_version` exists.
- **R12 — ids are only ever added, in every security document.** Whenever the PR changes any `docs/security/*-review.md` or `*-disposition.md` — tagged or not, the version under evaluation or any other — the wrapper walks `git rev-list --reverse <base>..HEAD` over those files plus the working tree, reads every revision with `blocks.split_blocks` and `config.parse` (the one parser, R5, in lenient mode: ids only, so `id: "SEC-004"` is `SEC-004`, as it is to the gate), and reports each id present at the base or in an earlier revision and missing later as `FAIL security-disposition <v> <id> id_removed (commit <sha7> | working tree)`, exit 1 — an integrity violation, not malformed input (REQ-322: "errors if any commit in the PR's range removes a review id"; dfe-3's "deleted from both files"). Disposition ids count as well as review ids, so deleting only a prior entry is caught; a schema migration (R7) removes none. **Prior entries** of a tagged version are read from its tag (`git show v<ver>:docs/security/<ver>-review.md` and `-disposition.md`; at a tag the header is optional, and a pre-schema file with no blocks contributes nothing, as ADR-002 says), so a working-tree edit to a released version cannot change what later versions carry forward; an untagged prior version is read from the working tree. A prior version's review id with no entry in that version's disposition, or the reverse, is a parser error (exit 2): every prior version passed rule 1 when it shipped. Exit 2 stays for parser errors and unusable inputs.
- **R13 — the base ref.** Every P3 check that needs a base reads `SPECFLOW_BASE_REF` (CI sets it to `origin/` plus the PR's base branch, on `pull_request` only), defaulting to `origin/main`; `--base` overrides. When the ref does not resolve (a remote-less instance, the first-run cases), a diff-scoped check prints a `SKIP`, and a read that needs the base (the rubric, the plans for the proof assertion) falls back to the working tree with `note: no base ref <ref>: reading <file> from the working tree (not a control)`. A key absent from `RUBRIC.md` at the base takes ADR-002's default (`medium_cap` 5, `expiry_horizon_days` 180) with a note — the IMPLEMENT PR's own base, the plan branch, has no `expiry_horizon_days` yet. A `RUBRIC.md` absent at the base and in the working tree, with no `--rubric`, is exit 2 (`no docs/security/RUBRIC.md at <ref> or in the working tree; pass --rubric`): a missing file is never a default. The PR under review can raise neither value for itself.
- **R14 — `verify-release.sh` is a PR-time gate (H10).** Section 7 of the gates runs it; it evaluates each version whose `docs/releases/<v>-notes.md` differs from the base (committed, uncommitted, or untracked: a new notes file not yet added counts, so `/release` never sees a SKIP for its own version). For a tagged version whose notes changed it FAILS (REQ-324: the tag must not yet exist, and a released version's notes are not edited). Under `SPECFLOW_QG_RUNNING=1` it never runs the gates; run alone it runs them last, as today. Because the tag must not exist when the ship PR is open, `/release` loses Step 0 (preliminary tag) and step 7 (tag before the PR) now: the tag is created on the merge commit after the PR merges, as an interim instruction that P6's `/release --tag` (REQ-383) replaces. An annotated fallback is recorded in known-limitations before the PR opens. `/release` runs the stack hook and transcribes the manifest into the notes before it runs `verify-release.sh` (which runs the gates last), so no gates run ever sees notes without their `## Artifacts` table. Check (6) reads specs and proofs from the working tree and plans at the base ref; in an instance it skips the inherited factory specs (R4 as implemented: by slug, present at the base ref, never by `created:`), with a note, and whether the tree is an instance is judged at the base ref (PR #42 code mode). The constitution's "tag missing" conflicts with this until amendment B (R19).
- **R15 — REQ-321's roots and rules (H8).** `pack.yml` gains `test_first_rules:` — inline-list items `"<source glob> -> <test glob>[ | <test glob>]…"`, where the test side may be `cfg-test` (a `#[cfg(test)]` hunk in the same `.rs` file). A "matching test change" is a change to a file matching that rule's test side that adds at least one line that is neither blank nor a comment (after leading whitespace: `#`, `//`, `/*`, `*`), in the same or an earlier listed commit; a whitespace or comment-only edit satisfies nothing (a `cfg-test` hunk counts the same way). A file matching any `test_globs` entry is never a source file. A pack may declare `non_source:` globs: files under a source root that never need a test. python: `["src/** -> tests/**/test_*.py"]`; tauri: `["src/**/*.ts -> src/**/*.test.ts", "src-tauri/src/**/*.rs -> src-tauri/tests/** | cfg-test"]`; flutter: `["lib/** -> test/**/*_test.dart"]`. Without the key, each source root gets `<root>/** -> <every test glob>`. **The template source** (no `.specflow.yml`, no `.stack`, `stacks/` present) reads `scripts/template-pack.yml` (init removes it from instances): `source_roots: [scripts, stacks, .claude, .github, src]`, `test_globs: [tests/governance/test_*.sh, tests/governance/lib/**, tests/governance/fixtures/**, tests/**/test_*.py]` (so fixtures and the harness are never source), rules `src/** -> tests/**/test_*.py`, and `scripts/**`, `stacks/**`, `.claude/**`, `.github/**` each `-> tests/governance/test_*.sh | tests/**/test_*.py` — the rules' test side leaves out `tests/governance/fixtures/**` and `tests/governance/lib/**`, so a fixture or harness edit alone satisfies no source change — `tdd.md`'s scope: governance tests are the test layer for scripts, packs, `.claude/` and CI; `verification/` holds proofs, not source; `docs/`, `schemas/` and `templates/` are documents. Its `non_source:` lists the dependency manifests and lockfiles Dependabot and the packs edit (`scripts/requirements.in`, `scripts/requirements.txt`, `stacks/*/skeleton/requirements.in`, `stacks/*/skeleton/requirements.txt`, `**/*.lock`, `**/package.json`, `**/package-lock.json`, `**/pubspec.yaml`, `**/Cargo.toml`) and Markdown that is not model-instruction (`.github/**/*.md`); model-instruction Markdown (`.claude/**`, any `CLAUDE.md`, `stacks/*/overlay/**`, `stacks/*/skeleton/**`: gate code under REQ-310) stays source, and its test is the governance test that pins its wording. A commit whose only change to a workflow or composite action (`.github/workflows/*.yml`, `stacks/*/action.yml`) replaces `uses:` lines is a pin bump, not a source change (`test_action_pins.sh` is its standing test). So a Dependabot pip or github-actions PR prints the no-source SKIP, and P4's dfe-13 exemption path in the verifier is unchanged. The citation is satisfied by `REQ-\d{3}` in any listed commit message or the PR body. Every source root must match at least one tracked file (exit 2 otherwise), checked before the range. No PR range (no `--base`, no `SPECFLOW_BASE_REF`: a push to `main`) prints `SKIP test-first: no PR range …` and exits 0; a range that changes no source file prints `SKIP test-first: the PR touches no source file` and exits 0 — that is "runs whenever the diff touches a source root" (a non-source file or a pin bump under a root is not a source change). Residual (Task 14, and the Task 15 claim row): the checker proves only that a test file gained a real line in the same or an earlier commit, not that the test exercises the change; code mode's second pass remains the control for that. **As implemented** (PR #42 fourth verifier run, low 7): the policy (`source_roots`, `test_globs`, `test_first_rules`, `non_source`) is read from the pack at the base ref, not the working tree, so a PR cannot relax its own; whether the tree is an instance (`.specflow.yml` or `.stack`) or the template source is judged at the base ref too, so adding or deleting either file cannot swap the policy; the one exception is the bootstrap — the PR that first adds `scripts/template-pack.yml` (this one) is judged by its own copy, which is not a control. CI still runs the PR head's own `check-test-first.sh` and `packinfo.py`; code mode names an edit to them as gate code.
- **R16 — coverage per toolchain (H6, H9).**
  - Python, in the core gates' section 1 (not the pack hook, which stays lint and format): `python3 -m pytest tests/ -q --cov=src --cov-config=<temp file> --cov-report=term-missing:skip-covered --cov-fail-under=$MIN`, with `COVERAGE_FILE` in a temp directory, and `--cov-config` always passed (the temp file holds only `[run] omit` from `coverage_exclude`), so a repository `.coveragerc`, `setup.cfg`, `tox.ini` or `pyproject.toml` `[tool.coverage]` — an `omit` or `exclude_lines` a PR adds — is never read; whenever `src/` holds a `.py` file and the stack is `python` or `none` (the template source). **The template enforces it on its own demo** (`src/` measured 100% on 2026-09-27). pytest-cov is hash-pinned in `scripts/requirements.txt` (pip-tools, the file's existing generator) and in the python skeleton's lockfile (uv). A missing pytest-cov is a hard FAIL with the install line, as a missing Dafny is.
  - Tauri, in `stacks/tauri/gates.sh`: `npx --no vitest run --coverage --coverage.thresholds.lines=$MIN` (the include and exclude lists stay in `vitest.config.ts`) and, from `src-tauri`, `cargo llvm-cov --locked --fail-under-lines $MIN --ignore-filename-regex <regex built from pack.yml's .rs entries>`, which replaces `cargo test --locked` (llvm-cov runs the tests). cargo-llvm-cov 0.9.1 (crates.io, 2026-09-27) is a pack prerequisite installed with `cargo install cargo-llvm-cov --locked --version 0.9.1`; its `llvm-tools` component comes from the overlay's `rust-toolchain.toml` `components` and is a doctor prerequisite.
  - Flutter, in `stacks/flutter/gates.sh`: `flutter test --coverage`, then `bash scripts/lcov-threshold.sh coverage/lcov.info $MIN --exclude <each pack.yml coverage_exclude entry>` (`stacks/flutter/lcov-threshold.sh`, stdlib `python3`; init copies it into `scripts/`).
  - `coverage_min`: `$SPECFLOW_COVERAGE_MIN` when the gates export it; else `max(working tree, base ref)`, the base value read in `coverage.sh` with `git show <ref>:.specflow.yml` into a temp file and `config.py --file <tmp> get coverage_min --default 80` (validated 0–100 there; an invalid value exits 2 in the coverage step only). `attestation.py policy` is not touched: the verifier's classifier calls it on every PR (`attestation.py:1350`, `run-verifier.sh:522`), and a coverage key must never turn the `verifier` check red. A PR may raise its floor, never lower it.
  - Exclusions: `coverage_exclude` is read at the head and, when the base ref resolves and has `.specflow/pack.yml`, at the base; an entry the head adds is `FAIL coverage_exclude gains <entry> — a PR cannot widen its own exclusions (base <ref>)`, which fails section 1 (python) or the pack hook (tauri, flutter). Residual (Task 14): tauri's `vitest.config.ts` include and exclude lists are read from the PR head (the template test pins them equal to `pack.yml`'s only in the template source); code mode reviews an edit to them.
- **R17 — gate sections keep their numbers.** Section 5 stays the security floor (docs cite it by number). The new sections are appended after it: 6 "Document gates" (`check-traceability.sh`, `analyze-adr-plan-linkage.sh`, `check-architecture.sh`, and from Task 13 `check-covers.sh`) and 7 "Release gates" (`check-security-disposition.sh`, `verify-release.sh`). Their failures are gate failures (`gate_fail`), listed apart from floor failures.
- **R18 — `check-covers.sh` goes live last.** It can pass on this repository only once every REQ this plan claims has a test that cites it, and each task's test carries its own `# Covers:` line. So Task 13 — after every other code task — switches it on: the repository self-check, section 6, and `test_traceability.sh`'s delegation. The annotation grammar is a whole comment line, `^\s*(#|//)\s*Covers:\s*REQ-\d{3}(\s*,\s*REQ-\d{3})*\s*$` (P1's comma lists, `tests/demo_greeting/test_greeting.py:1`, count; a `Covers:` inside a string does not). Test files are those matching the pack's `test_globs`, plus `tests/governance/**` minus `tests/governance/fixtures/**`. A plan without `implements:` walks its spec whole (the demo plan: REQ-200–202, all cited). A Covers line outside `tests/governance/` that cites a REQ no live spec defines stays an error (the interim check moves into the script).
- **R19 — `art-release-readiness`'s "tag missing" and REQ-324's "does not yet exist".** `constitution.md:187` has the RELEASE-phase verifier block merge on "tag missing"; REQ-324 and R14 make `verify-release.sh` FAIL when `v<version>` exists at PR time, and `/release` tags after the merge. From P3 until the constitution text changes, every ship PR sits between the two. **Interim reading**, applied by the verifier and every reviewer: "tag missing" is judged after the merge — the ship PR must not carry the tag, and a merged release whose merge commit has no tag (signed, or annotated with the fallback recorded in known-limitations) is what the clause blocks; the next ship PR's reviewer checks the previous release's tag. Task 15 states this reading in `review-gate.md`'s RELEASE exit gate and in the verifier skill; the IMPLEMENT PR body states it. The constitution text is brought into line by amendment B (P5), which already carries the Dependabot-sentence correction (`review-gate.md`'s claim table); P3 changes no constitution text. **As implemented** (PR #42 verifier findings 1, 2 and 7): the verifier is not part of this reading's control — the headless verifier sees the changed documents and the code, never the PR body or the gates' output, so on a RELEASE-phase PR it records the reading as a standing informational finding and asks the maintainer to confirm the previous tag by hand. The control is the next ship PR's `verify-release.sh` check of the previous release's tag (a tag object; a signature that verifies, or the annotated-tag fallback recorded in that version's known-limitations; an ancestor of the base — each a FAIL) plus the PR template's RELEASE checkbox (convention); a missing tag is only a WARN, the one recorded gap. The spec's P3 `amended:` entry records R19 with amendment B's tracking id, REQ-343.
- **R20 — an informational finding scores 0.0.** A finding with no impact on any system (all six impact metrics `N`: FIRST scores 0.0, band `none`) — an unmaintained dependency with no known vulnerability, as SEC-002 and SEC-003 in the tauri skeleton are — is recorded as `severity: low`, and its body says it is informational. `cvss4.finding_severity(vector)` maps band `none` to `low` and is what the parser and `decide`'s R9 re-check compare against; a 0.0 vector with any other severity is a parser error. Inventing an impact to reach 0.1 would be a manufactured score (`art-threat-driven-security`); RUBRIC.md gains the 0.0 row (Task 6). **As implemented** (PR #42 verifier finding 3): the constitution's band table puts low at 0.1–3.9, so R20 is an interim reading beside R19, owned by the same amendment B (REQ-343) and recorded in `review-gate.md`, the spec's P3 `amended:` entry and RUBRIC.md's 0.0 row. **Deadline** (PR #42 third verifier run, finding 4), for R19 and R20 alike: amendment B (REQ-343) lands with P5's PLAN PR, no later than 2026-10-31; if amendment B has not merged by that date, the maintainer records an extension with a new date in review-gate.md by a reviewed PR (a lapse changes no code; nothing in the gates depends on the date), and the verifier reports a ship PR after a lapsed, unextended date as a finding of severity high.

**Verified against:** 2026-09-27 @ main `f003112` (worktree `.claude/worktrees/p3`, branch `phase/plan-factory-v3-2-p3`); every `file:line` anchor below was checked there.
- **Parsers.** `scripts/check-traceability.sh`: `strip_quotes` `:22-26`, `strip_comment` `:28-50`, `frontmatter` `:52-63`, `parse_list` `:65-69`, plan scoping `:94-119`, proof walk `:122-144` (tag regex `:140`), SEC uniqueness `:161-170`, `n_ver` `:178-179`. `scripts/analyze-adr-plan-linkage.sh`: parsers `:20-66`, tag regex `:76`, scoping `:115-126`. `scripts/lib/specflow/architecture.py`: `TAG_RE` `:53`, flat reader `:69-107`, rich reader `:113-223`, `check()` `:322-360` (plan slugs `:332-337`, SPECIFY skip `:346-347`, all tags `:348`). `scripts/check-architecture.sh:1-11` (`ARCH_BASE_DIR`).
- **Floor.** `scripts/lib/specflow/floor.py`: `import config` `:34-35`; `DISPOSITION_RE` `:45`; `parse_inline_list` `:57-103`; `_version_key` `:106-109`; `_parse_disposition_blocks_at` `:118-143`; `load_dispositions` `:146-156`; `_latest_disposition_entries` `:159-199` (a block through `config.parse` `:184-189`); `validate_citation` `:202-225`; `_expiry_dates` `:917-965`.
- **Config and policy.** `scripts/lib/specflow/config.py`: `KEYS` `:18`, `DEFAULTS` `:20-27` (`coverage_min: "80"`), `parse_list` `:89-94`, `coverage_min` validated 0–100 `:135-142`. `scripts/lib/specflow/attestation.py`: `policy` `:256-277` (solo/profile/path only), `_cmd_policy` `:1532-1540`, parser `:1613-1615`. `tests/governance/test_attestation.sh:78,81` pin the policy output exactly.
- **Gates and CI.** `scripts/run-quality-gates.sh`: sentinel `:13`; section 1 `:22-34`; section 2 `:36-57` (`:43`); section 3 `:59-73`; section 4 `:75-104`; section 5 `:106-118` (comment `# 5. Security floor` at `:106`); Summary `:120-141`. `.github/workflows/ci.yml`: checkout with `fetch-depth: 0` `:17-19`; pip `:42-43`; Dafny 4.9.1 `:45-52`; gates `:54-55`; template-only jobs `:57-116`; triggers include `edited` `:5` and push to `main` `:6-7`. `.github/workflows/verifier.yml`: base-ref materialisation `:69-87`; `verify-dafny` `:94-118`, condition `:97-100`.
- **Release.** `scripts/verify-release.sh:1-86`: asserts the tag exists `:21-33`, greps notes for any 64-hex `:35-40`, verifies `dist/` `:42-62`, greps the disposition with `-B5` `:64-73`, runs the gates `:75-80`. `.claude/commands/release.md`: Step 0 `:11-17`, `config.py` `:29`, step 7 (tag before PR) `:33`, Gate list `:37-44`. `docs/releases/0.0.1-demo-notes.md`: `## Artifacts` table `| Filename | SHA-256 | Size (bytes) |` with backticked cells. Tag `v0.0.1-demo` exists (local and origin).
- **Security documents.** `.claude/commands/security-review.md`: finding frontmatter `:15-23` (severity chosen by hand), disposition `:33-43`, `inherited:` `:44-46`, Gate `:52-55`. `docs/security/README.md:3` ("see spec § Artifact Schemas"), post-tag addendum `:32-46`. `docs/security/RUBRIC.md`: yaml `:6-8` (`medium_cap: 5` only), worked example `:26-47` (≈7.1 high; counter-example ≈4.x medium; no vector strings). `docs/security/0.0.1-demo-review.md` (no findings; addendum `:14-30`) and `0.0.1-demo-disposition.md:1-9` (prose). `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md`: the "pending (P3 schema)" sentence `:18-20`, findings `:58-104` (`vector:` `:62`, `:81`, `:95`; SEC-002/003 `pending`); `0.0.0-skeleton-disposition.md` blocks `:23-51` (`suppresses:`, `inherited:`, owner `tauri-pack`, expiry 2026-12-24).
- **Packs.** `stacks/*/pack.yml:8-10` (`source_roots`, `test_globs`, `coverage_exclude`); tauri `prereqs` `:26`, cargo-audit lines `:39-41`. `stacks/tauri/gates.sh:20-32` (`vitest run`, `cargo test --locked`); `stacks/flutter/gates.sh:20-25` (`flutter test`); `stacks/tauri/overlay/vitest.config.ts` (provider v8, include `src/**/*.ts`, exclude `src/main.ts` and the tests; "No coverage threshold yet (P3)"); `stacks/tauri/overlay/rust-toolchain.toml` (channel 1.93.1, minimal); `stacks/tauri/action.yml` inputs `:9-28`, rustup `:51-53`, cargo-audit cache/install `:58-67`; `.gitignore` gets `coverage/` from `stacks/tauri/init.sh:295` and `stacks/flutter/init.sh:289`. `scripts/init-project.sh:515-527` (pack copies), `:544` (drops `app-stacks.yml`).
- **Constitution, manifests, policy callers.** `constitution.md:187` (`art-release-readiness`: the RELEASE-phase verifier blocks merge on "tag missing"). Every release hook writes `{"version", "artifacts": [{"filename", "sha256", "size"}]}`: `scripts/release-stack.sh.template:41`, `stacks/python/release.sh:70`, `stacks/tauri/release.sh:56`, `stacks/flutter/release.sh:62`. `attestation.policy` is called by the classifier's verdict path (`attestation.py:1350`) and by `run-verifier.sh:522`. `config.DEFAULTS` gives `profile: guided` to a `.specflow.yml` without the key. `init-project.sh:585-600` removes other stacks' examples and `stacks/`, keeping the v3.2 spec, its architecture documents, ADR-002/003 and the P0–P4 plans in every instance.
- **Docs that name P3 as future (H7).** `.claude/skills/verifier/SKILL.md:48`; `.claude/rules/tdd.md:21-24`; `.claude/rules/review-gate.md:68` (claim row), `:133-134` (SECURITY and RELEASE exit gates; `test_spec_lifecycle.sh:53-54` requires the RELEASE line to keep "fallback" and "transcribed"); `docs/GLOSSARY.md:58-68`; `CLAUDE.md:74-85`; `README.md:123-130`, `:203`; `.github/PULL_REQUEST_TEMPLATE.md:22,24,26`; `.claude/commands/architecture.md:21`.
- **Tests that change.** `tests/governance/test_traceability.sh:37-76` (check 3, hand-rolled); `tests/governance/test_traceability_scoping.sh` (hand-rolled, no Covers line); `tests/governance/test_security_review.sh:185-190` (SEC uniqueness fixture, kept green); `tests/governance/test_python_lockfiles.sh` (tool loops); `tests/governance/test_stack_packs.sh:139,152,154,393` and `:356-371` (the skeleton review's `vector:` check, Task 6); `tests/governance/test_examples.sh` (on the PLAN PR, R1: the empty-specs case deletes `verification/*/`; Task 2: `check-architecture.sh` in guided instances); `tests/governance/test_verifier_skill_modes.sh:22` (code mode must keep naming `check-test-first.sh`); `tests/governance/test_config.sh:48` and `test_stack_packs.sh:383` (`/release` keeps `config.py`, `/security-review` keeps `inherited:`); `tests/governance/test_threat_model_current.sh` (its last check greps `check-architecture.sh.*REQ-320` in the overview).
- **Covers today** (whole-line grammar of R18, over the union of `implements:` of the six plans): 25 REQs, 23 cited; REQ-327 and REQ-380 are not (H5).

**Tool facts on this Mac (read-only runs, 2026-09-27):**
- dafny 4.11.0 local; CI and `scripts/pinned-tools.yml` pin 4.9.1 (`bash scripts/install-pinned-tool.sh dafny --dest "$TMPDIR/dafny491"` installs the arm64 macOS zip checksum-verified).
- python3 3.12.4 (host conda: never `pip install` into it; it has pytest 9.1.1 and pytest-cov 6.2.1). PyPI's newest pytest-cov is 7.1.0. uv 0.11.29 is installed; pip-tools is not (a throwaway venv under `$TMPDIR`).
- Coverage measured with the host's pytest-cov: the template's `src/` is 100% (5 statements); a scratch copy of the python skeleton is 90% (the `if __name__ == "__main__"` line is the miss).
- cargo 1.93.1; `cargo search cargo-llvm-cov` → 0.9.1; the `llvm-tools` component is available for 1.93.1 and not installed; cargo-llvm-cov is not installed.
- node 24.8.0 (the conformance generator). The FIRST calculator repository's root at `c5b0d409…`: `LICENSE`, `app.js` (Vue app; calls `macroVector()` and `cvss_score()`), `cvss_config.js`, `cvss_details.js`, `cvss_lookup.js` (4638 bytes), `cvss_score.js` (16097 bytes), `max_composed.js`, `max_severity.js`, `metrics.js`.
- gh 2.97.0 with `GH_TOKEN="$(gh auth token --user kpingali123)"`; the repository has no `has-verification` label.
- The default gates at `f003112` take about 2:30 in this worktree (the P4 floor's online advisory lookups); the budget is 3 minutes.

**Clause → task:**

| REQ | Clauses (task numbers) |
|---|---|
| 320 | runs when a plan implements a REQ of the spec 2; implemented `[verifiable*]` ∉ `req_map` fails 2; trust boundary, CIA, STRIDE, checklist (P4, kept) 2; live = not superseded 2; wired into the gates 2 |
| 321 | reads `source_roots`/`test_globs` 10; per-stack globs and the `#[cfg(test)]` rule 10; `rev-list --reverse --no-merges` on `fetch-depth: 0` 10; test in the same or an earlier commit 10; REQ cited in a commit message or the PR body 10; runs in CI when the diff touches a source root 10; errors on empty roots 10 |
| 322 | inputs and parser errors 3, 5, 7; rules 1–5 as an iff 4; `--version` and branch defaults 7; skip when no security/release doc changed 7; tagged never re-evaluated 7; id removal 7; base-ref rubric 6, 7; invariants 4 (and the model, R1); tests of the parser, reduction, base-ref reads and wiring 5, 7, 9 |
| 323 | fails on an uncovered claimed REQ 13; `#` and `//` forms under `test_globs` or `tests/governance/` 13; reports ids 13; `test_traceability.sh` delegates 13 |
| 394 | shared `parse_list()`/`frontmatter()` 1; `check-covers.sh` 13 and `check-architecture.sh` 2 scope to it |
| 324 | runs from the gates when notes differ, sentinel honoured, base default overridable 8; three docs, no tag yet, manifest rows, REQ-322 passes 8; `/release` invokes it 9; ship-time `[verifiable*]` claimed + `// Proves:` 8; base-ref `medium_cap` 7, 8 |
| 325 | default 80 and base-ref read 11; python 11; Rust and TypeScript 12; Flutter 12; skeletons clear the floor 11, 12; exclusion lists equal `coverage_exclude` 11, 12 |
| 306 (slice) | delegation 13 |
| 332 (slice) | schema 5; migration 6 |
| 333 (slice) | scoping 2 |
| 389 (slice) | `confirmed_by:` under `profile: guided` 2 |

**Findings handed to P3 (H1–H19) and raised while planning (P1–P6):**

| Finding | Owner |
|---|---|
| H1 | R1; the proof step after this plan; Task 4 keeps the twin in step |
| H2 | R2, R3, R4; Tasks 1, 2 |
| H3 | R6, R7; Task 6 |
| H4 | R5; Task 5 |
| H5 | R18; Task 13 (annotations on `test_traceability_scoping.sh`, `test_plan_template.sh`, `test_analyze_adr_plan_linkage.sh`) |
| H6 | R13, R16; Task 11 |
| H7 | Task 15 |
| H8 | R15; Task 10 |
| H9 | R16; Tasks 11, 12 |
| H10 | R14; Task 8 |
| H11 | Tasks 6 (RUBRIC, README), 9 (`/security-review`) |
| H12 | R8; Task 3 |
| H13 | Task 14 |
| H14 | R1 (the PLAN PR relies on gates section 2); Task 16 adds the label only if it exists |
| H15 | Global Constraints; every task |
| H16 | R1; Tasks 4, 16 |
| H17 | Task 9 |
| H18 | R15; Task 16 runs `check-test-first.sh` on the IMPLEMENT branch with base `phase/plan-factory-v3-2-p3` |
| H19 | ruled out — Deferred by design |
| P1 — SEC uniqueness vs re-listing (rule 4) | R6; Tasks 5, 6 |
| P2 — `/release` tags before the PR; REQ-324 needs no tag at PR time | R14; Task 9 |
| P3 — "lows never affect rules 2–5" vs rule 4's downgrade | R10; Task 4 fixture 24; the model's `LowsInertForRules2to5` precondition |
| P4 — `config.py`/`attestation.py` are materialised alone from the base ref | R2 |
| P5 — `check-covers.sh` cannot pass until every claimed REQ has its test | R18; Task 13 |
| P6 — `confirmed_by:` would fail a guided instance's demo and its inherited v3.2 artifacts | R4 (grandfathered by inherited slug at the base ref, never by `created:`); Task 2 (a guided copy of the v3.2 artifacts; `test_examples.sh` runs the check in guided instances) |
| Fresh-eyes review of this plan (2026-09-27): the guided cutoff, prior-version deletions, the constitution's "tag missing", `test_stack_packs.sh`'s skeleton check, the manifest key, one parser for the walk, `policy()` left alone, coverage config and exclusions, decorative test edits, instances' inherited spec and Dafny, open mediums, 0.0 vectors, the `amended:` entry, the RUBRIC vectors, `/release`'s order, working tree vs HEAD, the missing rubric, Dependabot PRs, messages grepped, the model's helper names and lapsed-without-expiry, boundary and fixture lemmas, the time budget | R4, R12–R16, R19, R20; Partial claims; Tasks 2–11, 14–16; the proof's boundary and `FixtureNN` lemmas |

## Global Constraints

From the spec:
- **Performance.** `run-quality-gates.sh` on a fresh instance completes in under 3 minutes on ubuntu (python), excluding toolchain download. The template's gates took about 2:30 at `f003112` and must stay under 3 minutes; the headroom is small (the 42 governance tests alone take about 161 s serially on this Mac, slowest `test_verifier_run` 31 s, `test_attestation` 22 s, `test_init` 21 s, `test_stack_packs` 18 s), and P3 adds about 12 tests plus sections 6 and 7 (estimate: 20–30 s). So Tasks 7, 8, 10 and 11 each time their new test and the gates in Step 4 and stop if the gates pass 2:50; tests that need synthetic repositories build one seed repository per test and `git clone` it per case (never a `cp -R scripts/` per case); Task 16 records the time after P3. App-stack gate runs on `macos-15` stay under 10 minutes with warm caches; P3 adds an instrumented Rust build (cargo llvm-cov) and a cached `cargo-llvm-cov` install.
- **Security.** No API key anywhere. All CI tool downloads pinned by version and checksum (P3 adds cargo-llvm-cov by `--locked --version`, pytest-cov by hash). Workflows stay read-only; no job elevates.
- **Scalability.** A stack stays one directory: it declares `test_first_rules:` and `coverage_exclude:` in `pack.yml` and runs its own coverage command in `gates.sh`.
- **Compliance.** No constitution change in P3; the conflict with `art-release-readiness` (`constitution.md:187`, "tag missing" vs REQ-324's "does not yet exist") is owned by amendment B (P5), with R19's interim reading until then.
- **Assumptions.** Pins live in the packs; a bumped pin may break the skeleton, which REQ-360 reports.

Plan-level (P1a/P1b/P2/P4, still in force):
- Python inside scripts is stdlib-only and always invoked as `python3`. `config.py` stays the one flat `key: value` reader of `.specflow.yml`, `pack.yml` and `pinned-tools.yml`; `tomllib` is stdlib.
- bash 3.2 (macOS): no associative arrays, `mapfile`, `${v,,}`, possibly-empty arrays under `set -u`, or coreutils `timeout` (use `run_within`); `grep -E` with POSIX classes (`[[:space:]]`), never `\s`; `sed -i.bak` then remove the backup.
- **Instance** means `.specflow.yml` or a legacy `.stack` is present; otherwise the tree is the **template source**. Tests pass in both. Loops over `stacks/*/…` sit inside `if ! instance; then …; fi`.
- **Opt-in rule.** Anything that downloads, compiles Rust, runs `flutter`, runs node, or queries a network service inside a *test* runs only under `SPECFLOW_FIRST_RUN=1` (with `FIRST_RUN_CASES`) or an explicit switch; each such step states its wall-clock. Default-gate tests use stub tools on `PATH` under `mktemp` and synthetic git repositories, and touch no network. Authoring-time fetches (Task 3's FIRST files, Task 11's lockfile compiles, Task 12's `cargo install`) happen once, by the implementer, never in a test.
- Gates stay green on the template source after every task (from the gates venv below), and `actionlint .github/workflows/*.yml` stays clean.
- `scripts/verify-doc.sh` must not flag any marker in plans or new files: no double braces anywhere (a GitHub expression is described in words, or built in a test with `"{" * 2`), and no placeholder words.
- New tests carry `# Covers: REQ-NNN`, source `tests/governance/lib/check.sh`, and keep every check **above** `finish` (the harness refuses a check after it). Hand-rolled tests (`test_traceability.sh`, `test_traceability_scoping.sh`, `test_plan_template.sh`, `test_run_quality_gates.sh`) keep their style.
- `gh` output is parsed with `python3`, never `--jq`; every `gh` call runs as `GH_TOKEN="$(gh auth token --user kpingali123)"`.
- One commit per task: check `git status`, stage the task's files, commit with the given message; every commit body ends with the `Co-Authored-By:` trailer given to the executing session.
- **Gates venv** (P4): the lint test needs the pinned ruff and black, and this Mac's conda black is older.

  ```bash
  python3 -m venv "$TMPDIR/p3-gates"
  "$TMPDIR/p3-gates/bin/pip" install --require-hashes -r scripts/requirements.txt
  PATH="$TMPDIR/p3-gates/bin:$PATH" bash scripts/run-quality-gates.sh
  ```

  After Task 11 re-run the `pip install` (the lockfile gains pytest-cov). Nothing is installed globally; `rm -rf "$TMPDIR/p3-gates"` undoes it. The floor needs the network (P4 R2); `SPECFLOW_FLOOR_OFFLINE=1` only when offline, never in CI.

Plan-level (new in P3):
- **Host hygiene.** Never `pip install` into the host interpreter (`/opt/miniconda3` or any global python), never `npm install -g`. pip-tools, uv caches and cargo tools go under `$TMPDIR` (`python3 -m venv "$TMPDIR/venv-p3"`, `UV_CACHE_DIR="$TMPDIR/uv-cache"`, `cargo install --root "$TMPDIR/cargo-tools"`). The one allowed host change is `rustup component add llvm-tools --toolchain 1.93.1`, reported in the PR body.
- **Dafny, both versions.** Any commit that touches `verification/` verifies under the local 4.11.0 (`dafny verify verification/factory_v3_2/disposition.dfy`) and under 4.9.1 (`bash scripts/install-pinned-tool.sh dafny --dest "$TMPDIR/dafny491"`, then the `dafny` binary under that directory).
- **The twin and the model stay in step.** `disposition.py`'s rule functions, `records.py`'s names and the fixture file names follow the model's predicates (Interfaces "The Dafny model"); a change to one is a change to all three in one commit.
- **Test-first on this branch (H18).** Every commit on `impl/plan-3-mechanized-gates` that changes a source file under `scripts/`, `stacks/`, `.claude/`, `.github/` or `src/` adds a non-blank, non-comment line to a `tests/governance/test_*.sh` (or a `tests/**/test_*.py`) in the same commit — a fixture or `lib/` change alone does not count (R15) — and every commit message cites a `REQ-NNN`. Task 16 runs the checker over the branch.
- **One parser per format.** Frontmatter: `frontmatter.py` (except R2's two). Security blocks: `blocks.py`. Pack metadata: `packinfo.py` over `config.py`.

## Interfaces shared by the tasks

**`scripts/lib/specflow/frontmatter.py`** (Task 1; stdlib; importable as `frontmatter` after `sys.path.insert(0, "<root>/scripts/lib/specflow")`):
- `strip_quotes(s) -> str`, `strip_comment(s) -> str` — exactly today's rules (`check-traceability.sh:22-50`): surrounding matching quotes removed; a `#` that starts the value or follows whitespace outside quotes starts a comment.
- `parse_text(text) -> dict[str, str]` — the flat reader: the first `---\n…\n---\n` block; each line with a `:` splits once; values through `strip_comment` then `strip_quotes`; no frontmatter → `{}`. `read(path) -> (dict, text)`.
- `parse_list(s) -> list[str]` — `[a, "b"]`, `[]`, `""` and a bare value; items quote-stripped, empties dropped.
- `TAG_RE` — today's tag regex, moved verbatim from `check-traceability.sh:140` (a bold `REQ-NNN` line carrying the tag outside backticks; a backticked tag is prose). `tagged_reqs(text) -> set[str]` of `"REQ-NNN"`.
- `spec_slug(path) -> str` (`<slug>-design.md` → `<slug>`, else the basename without `.md`).
- `live_specs(root) -> dict[slug, (fm, text)]` — `docs/specs/*.md` whose `type` is not `brainstorm` and `status` is not `superseded`.
- `claims(root) -> Claims(implemented: set[str], whole_specs: set[str], named_specs: set[str], plans: list[Plan])`, `Plan(path, spec, implements: list[str] | None, created: str)` — lenient: `implemented` holds only well-formed `REQ-NNN` items; validation errors stay with `check-traceability.sh` and `analyze-adr-plan-linkage.sh`, which read `plans`.
- Callers pass the repository root to the heredoc (`python3 - "$ROOT" <<'PY'`) and insert `<root>/scripts/lib/specflow` into `sys.path`, since `*_BASE_DIR` moves the cwd to fixture docs.

**`scripts/lib/specflow/packinfo.py`** (Task 10; Task 13 reuses it): `load(root) -> Pack(origin, source_roots, test_globs, rules, non_source, coverage_exclude)`; `origin` is `.specflow/pack.yml` in an instance, `scripts/template-pack.yml` in the template source, or python's defaults (`[src]`, `[tests/**/test_*.py]`, printed as a note) in an instance with no pack file; anything else raises `PackError` (exit 2 in callers). `Rule(source: str, tests: tuple[str, ...], cfg_test: bool)` parsed from `test_first_rules` items (`->` separates the sides, `|` the test globs; `cfg-test` sets `cfg_test`). `match(glob, path) -> bool`: `**/` matches zero or more directories, a trailing `/**` everything below, `*` and `?` stay within one segment; paths are POSIX and relative. `is_test(pack, path)` and `is_source(pack, path)` (under a source root, not a test, not `non_source`).

**Covers annotation** (R18): a whole line `^\s*(#|//)\s*Covers:\s*REQ-\d{3}(\s*,\s*REQ-\d{3})*\s*$`.

**The security schema** (`schemas/security-disposition-template.md`, Task 5). Every review and disposition in the schema opens with a header block at line 1, then prose and blocks. A block is a `---` line, flat `key: value` lines (`config.parse`), and a closing `---` line.

```
---
schema: specflow-security/1
kind: review                 # review | disposition (matches the file name)
version: 1.2.0               # the file name's version
---
```

A review finding block (in `<version>-review.md`), followed by its body (≤200 words, with the metric-by-metric reasoning table RUBRIC.md's worked example uses):

```
---
id: SEC-004
severity: medium             # must equal cvss4.finding_severity(cvss_vector): its band; 0.0 reads as low (R20)
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N
cite: [dfe-3, CWE-20]        # >= 1
affects: [src/app/x.py:12]
carried_from: 1.1.0          # only on a re-listed prior finding (R6)
---
```

A disposition entry block (in `<version>-disposition.md`):

```
---
id: SEC-004
status: accepted             # open | fixed | accepted | deferred
owner: alice                 # required for accepted/deferred medium or above
expiry: 2026-12-01           # YYYY-MM-DD; same rule
rationale: "…"               # >= 10 characters (gate mode)
reclassified_by: bob         # optional: the second reviewer of a downgrade (not the owner)
suppresses: [GHSA-…]         # optional (REQ-388); inline list, JSON-quoted items when they hold , " space or #
inherited: "…"               # optional (a pack's skeleton entry)
---
```

Keys outside these lists are errors. Several entries for one id may appear across versions (and, in floor mode, within one file: the later block wins); the gate requires unique ids within each current file.

**`scripts/lib/specflow/blocks.py`** (Task 5): `BlockError(ValueError)` with `.rel`, `.line`, `.message`; `split_blocks(text, rel) -> list[Block(line, body)]` (an unterminated fence raises `unterminated disposition block`, P4's text); `parse_review(text, rel, *, version) -> Review(header, findings: list[FindingBlock(id, severity, cvss_vector, cite, affects, carried_from, line)])`; `parse_disposition(text, rel, *, version, require_header) -> Disposition(header | None, entries: list[EntryBlock(id, status, owner, expiry, rationale, reclassified_by, suppresses, inherited, line)])`; `check_pair(review, disposition) -> list[BlockError]` (unique ids per file; accepted/deferred entries of severity medium or above have `owner` and `expiry`; rationale ≥ 10 characters); `parse_inline_list(s)` (moved from `floor.py`); `version_key(v)` (moved: a pre-release sorts before its release, `0.0.0-skeleton` < `0.0.1-demo` < `0.9.0` < `0.10.0`); `latest_entries(sec_dir, rel_dir, errors, *, before=None, require_header=False) -> dict[id, Latest(entry, version, path, line)]` — P4's reduction (higher version, then later block), limited to versions strictly before `before`; a file with blocks but no header is an error only when `require_header`. In gate mode a file must open with the header block, else `<file>:1: no schema header (schemas/security-disposition-template.md)` and nothing else in the file is read. The finding parser validates `cvss_vector` with `cvss4.parse` and raises `SEC-NNN: severity <s> but cvss_vector scores <x> (<band>)` when `severity` is not `cvss4.finding_severity(cvss_vector)` (a 0.0 vector is an informational `low`, R20). Values go through `config.parse` per block, so a quoted value (`id: "SEC-004"`) is the bare value; the same reading serves R12's walk (`split_blocks` plus `config.parse`, ids only). CLI: `python3 blocks.py check REVIEW DISPOSITION` (gate mode; exit 0, or 2 printing `<file>:<line>: <message>` per error) and `python3 blocks.py latest DIR [--before V]` (prints `<id> <version> <status>` per id, sorted by id). **As implemented** (PR #42 second verifier run, medium 3): with `--before V` (and optional `--base REF`), `latest` reads the prior versions through `disposition_gate.read_priors` (R12: a tagged version from its tag, else the working tree, else the base ref) and prints `<id> <version> <status> <severity>`, the severity joined from that version's review — `/security-review`'s carry-forward listing; a prior disposition with no review beside it is exit 2.

**`scripts/lib/specflow/cvss4.py`** (Task 3; pure): `CvssError(ValueError)`; `parse(vector) -> dict` (prefix `CVSS:4.0/`; the eleven base metrics mandatory, in the specification's order, then optional metrics in order; unknown metric, invalid value, duplicate, missing base metric, wrong order, empty segment or trailing `/` → `CvssError`); `macro_vector(metrics) -> str` (six digits, EQ1–EQ6 as FIRST's `macroVector()`); `score(vector) -> float` (FIRST's `cvss_score()`: the no-impact shortcut 0.0, the lookup, per-EQ distances from `MAX_COMPOSED` and `MAX_SEVERITY` with the metric level tables, the mean proportional distance, then JavaScript's `Math.round(value * 10) / 10`, reproduced as `math.floor(value * 10 + 0.5) / 10` — never Python's `round`); `severity(score) -> "none" | "low" | "medium" | "high" | "critical"` (0.0 none; 0.1–3.9 low; 4.0–6.9 medium; 7.0–8.9 high; 9.0–10.0 critical, RUBRIC.md); `band(vector) = severity(score(vector))`; `finding_severity(vector)` is `band(vector)` with `none` read as `low` (R20) — what the parser and the kernel compare a finding's severity with. `scripts/lib/specflow/cvss4_data.py`: `SOURCE` (`repository`, `commit`, `files: {name: sha256}`, `license: "BSD-2-Clause"`, `converted_by`), `LOOKUP` (270 entries, six-digit keys), `MAX_COMPOSED`, `MAX_SEVERITY`, `METRIC_ORDER`, `METRIC_VALUES`.

**Conformance vectors** (`tests/governance/fixtures/cvss4/vectors.json`, Task 3): `{"source": {"calculator": "https://github.com/FIRSTdotorg/cvss-v4-calculator", "commit": "c5b0d409ae9f57c44264c6ce5f27d89298e1d32a", "node": "v24.8.0", "command": "node tests/governance/fixtures/cvss4/generate.mjs \"$TMPDIR/first-cvss4\" > tests/governance/fixtures/cvss4/vectors.json"}, "vectors": [{"vector", "score", "severity"}, …], "malformed": ["…", …]}`. `generate.mjs` loads FIRST's `cvss_lookup.js`, `max_composed.js`, `max_severity.js` and `cvss_score.js` into one `vm` context (appending a line per file that exposes its `const` to `globalThis`), builds the calculator's `cvssSelected` (every metric `X` unless the vector sets it), and prints `macroVector()` → `cvss_score()` per vector. Its vector list is fixed in the file: the RUBRIC.md worked example and counter-example, the tauri skeleton's three vectors, at least five with `E:` (Threat), at least five with environmental metrics (`CR`/`IR`/`AR`/`M*`), at least three with supplemental metrics, the all-`N` impact vector (0.0), and a deterministic LCG sample (seed 322) to reach at least 60, covering every band. `malformed` is a hand-written list (at least 10) that `generate.mjs` does not score.

**`scripts/lib/specflow/records.py`** (Task 4; names shared with the Dafny model; the state records are P5's):

```
Severity(Enum) = critical | high | medium | low          Status(Enum) = open | fixed | accepted | deferred
Rule(Enum) = set_equality | severe_not_fixed | medium_cap | carry_forward | expiry_window
Finding(id: str, severity: Severity, cvss_vector: str)
Entry(id: str, status: Status, owner: str, expiry: date | None, rationale: str, reclassified_by: str | None)
PriorEntry(id: str, severity: Severity, status: Status, expiry: date | None, version: str)
Violation(id: str, rule: Rule)
Verdict(passed: bool, violations: tuple[Violation, ...])   # sorted by (id, rule.value)
```

All frozen dataclasses; `owner == ""` means none.

**`scripts/lib/specflow/disposition.py`** (Task 4; the kernel; imports only `records`, `cvss4`, `dataclasses`, `datetime`, `enum`, `typing`): `decide(review, disposition, prior, medium_cap, expiry_horizon_days, run_date) -> Verdict`, raising `ValueError` on a precondition (`pre`): duplicate ids in `review`, in `disposition` or in `prior`; a finding whose `cvss4.finding_severity(cvss_vector)` is not its severity (R9, R20); an accepted/deferred entry joined to a medium-or-above finding with `owner == ""` or `expiry is None`; `medium_cap < 0`; `expiry_horizon_days < 0`. One function per model predicate or function, named as the model's in snake_case: rules `rule1_set_equality`, `rule2_severe_fixed`, `rule3_medium_cap`, `rule4_carry_forward`, `rule5_expiry_window`, `all_rules_hold`, `pre`; helpers `sev_is(review, id, severity)`, `joined_severe(review, id)`, `joined_at_least_medium(review, id)`, `ranked_below(review, prior_entry)`, `due(prior_entry)`, `lapsed(prior_entry, run_date)` (an accepted/deferred prior entry whose expiry is `None` or on or before the run date — **`None` counts as lapsed**, fail closed, never a `TypeError`), `reclass_ok(entry)`, `entry_carries(review, entry, prior_entry, run_date)`, `carried_ok(review, disposition, prior_entry, run_date)`, `in_window(entry, run_date, horizon)`, `mediums_ad(review, disposition)`; violation sets `v1`…`v5`, `violations_2to5`, `violations` (their union). `decide(...).passed == all_rules_hold(...)` for every input satisfying `pre`.

**The Dafny model** (`verification/factory_v3_2/disposition.dfy`; written by the step right after this plan, on this branch, R1). Header, first lines:

```
// verification/factory_v3_2/disposition.dfy — ADR-002's security-disposition decision as a pure function.
// Proves: REQ-322
// Twin: scripts/lib/specflow/disposition.py (decide); fixtures: tests/governance/fixtures/disposition/.
```

Shape (names are binding — the twin and the Task 4 test grep them):
- `module SecurityDisposition` with `datatype Severity = Critical | High | Medium | Low`, `datatype Status = Open | Fixed | Accepted | Deferred`, `datatype Rule = SetEquality | SevereNotFixed | MediumCap | CarryForward | ExpiryWindow`, `datatype Option<T> = None | Some(value: T)`, `datatype Finding = Finding(id: string, severity: Severity)` (the vector stays outside the model: severity is derived by the parser, R9), `datatype Entry = Entry(id: string, status: Status, owner: string, expiry: Option<int>, rationale: string, reclassifiedBy: Option<string>)`, `datatype PriorEntry = PriorEntry(id: string, severity: Severity, status: Status, expiry: Option<int>)`, `datatype Violation = Violation(id: string, rule: Rule)`, `datatype Verdict = Pass | Fail(violations: set<Violation>)`. Dates are day ordinals (`int`), as `date.toordinal()` in the twin.
- Helpers (as committed; the twin's snake_case names above): `Rank` (Critical 3, High 2, Medium 1, Low 0), `AtLeastMedium`, `Severe` (rank ≥ 2), `AcceptedOrDeferred(status)`, `IdsR`, `IdsD`; the joins by id, existential over the review (under `Pre` at most one finding per id, so there is no `SevOf`): `SevIs(review, id, s)`, `JoinedSevere(review, id)`, `JoinedAtLeastMedium(review, id)`, `RankedBelow(review, p)`; `Due(p)` (status Open/Accepted/Deferred and at least Medium); `Lapsed(p, today)` (Accepted/Deferred and `expiry` is `None` or `≤ today`: **a prior acceptance with no expiry counts as lapsed**, fail closed); `ReclassOk(e)` (`reclassifiedBy` is `Some`, non-empty, not `owner`, and `|rationale| > 0`); `EntryCarries(review, e, p, today)` (`e.id == p.id`, and: a severe prior → Fixed; a `Lapsed` prior → Fixed, or Accepted/Deferred with `expiry > today`; `RankedBelow` → `ReclassOk`); `CarriedOk(review, disposition, p, today)` (some entry `EntryCarries`); `InWindow(e, today, horizon)` (`Some(x)` with `today < x <= today + horizon`); `MediumsAD(review, disposition)` (ids of Accepted/Deferred entries joined to a Medium).
- Predicates: `Rule1SetEquality`, `Rule2SevereFixed`, `Rule3MediumCap`, `Rule4CarryForward`, `Rule5ExpiryWindow` (every accepted/deferred entry joined to a medium-or-above finding is `InWindow`), `AllRulesHold`, and `Pre` (`UniqueFindingIds`, `UniqueEntryIds`, `UniquePriorIds`; owners and expiries per ADR-002's precondition; `cap` and `horizon` are `nat`).
- Functions: `V1`…`V5` (per-rule violation sets; V3 names every accepted/deferred medium id when their count exceeds the cap), `Violations` (their union), `Violations2to5`, `Decide` (`Pass` iff `Violations` is empty, else `Fail(Violations)`).
- Lemmas: `DecidePassIffAllRulesHold` (requires `Pre`; `Decide(...) == Pass <==> AllRulesHold(...)`), `DecidePermutationInvariant` (requires `Pre` on the first inputs and `multiset` equality of each pair of sequences; equal `Decide`), `LowsInertForRules2to5` (requires `Pre` before and after appending a `Low` finding `f` and its entry `e` with `e.id == f.id`, `f.id` in neither id set, and no `Due` prior entry with `f.id`; `Violations2to5` unchanged — R10), and the corollary `ZeroFindingsPass` (no `Due` prior entry → `Decide([], [], prior, …) == Pass`). `RuleIffNoViolations` (each rule holds iff its violation set is empty) carries theorem 1.
- Boundary lemmas — the theorems cannot see a wrong helper, since both sides share it, so each helper is pinned to its ADR-002 clause: `InWindowBoundaries` (false at `expiry == today`, true at `today + horizon`, false one day later and for `None`), `DueBoundaries`, `LapsedBoundaries` (an expiry equal to the run date and `None` lapse; one day later does not; open and fixed never lapse), `DowngradeByOwnerNotCarried`, `DowngradeWithoutRationaleNotCarried`, `SeverePriorLeftAcceptedNotCarried` (a severe prior re-listed with `ReclassOk` but left Accepted is not carried), `MediumsADCountsOnlyAcceptedDeferredMediums` (an accepted high and an open medium are not counted).
- Fixture lemmas — `Fixture13`, `Fixture19`, `Fixture20`, `Fixture24`, `Fixture25`, `Fixture33`, `Fixture34`, each `Decide(<fixture NN's inputs>) == <its verdict>` for every run date `today` (dates as `today + k`), so those Python fixtures are expectations the model itself has proved.
- The three layers (`verification/README.md:9-12`): the proof (this file), the runtime contract (`decide`'s precondition checks, including R9's band re-check), the tests (Task 4's fixtures mirror the model, one per rule, a permutation run, a lows-only fixture, the zero-findings case, the downgrade path, the expired-prior carry-forward).
- It verifies with `dafny verify` under 4.11.0 and 4.9.1, with no `{:axiom}` or `assume`: 34 verified, 0 errors under each (2026-09-27; 4.9.1 installed checksum-verified). Mutations checked when the boundary lemmas were added: `InWindow` as `today <= expiry`, `Lapsed` without the `None` case, `ReclassOk` without the owner clause, and a wrong `Fixture25` verdict each fail verification.

**Kernel fixtures** (`tests/governance/fixtures/disposition/NN-<name>.json`, Task 4): `{"about": "…", "review": [{"id", "severity", "cvss_vector"}], "disposition": [{"id", "status", "owner", "expiry", "rationale", "reclassified_by"}], "prior": [{"id", "severity", "status", "expiry", "version"}], "medium_cap": 5, "expiry_horizon_days": 180, "run_date": "2026-09-27", "expect": {"passed": bool, "violations": [["SEC-001", "carry_forward"], …]} | {"error": "ValueError"}}`. `cvss_vector` may be `"@critical"`, `"@high"`, `"@medium"` or `"@low"`: the runner substitutes the first vector of that band in `vectors.json`. Names: `01-pass-medium-accepted-in-window`, `02-set-equality-review-only`, `03-set-equality-disposition-only`, `04-severe-not-fixed-high-accepted`, `05-severe-not-fixed-critical-open`, `06-medium-cap-at-cap-passes`, `07-medium-cap-over-cap-names-each`, `08-carry-forward-prior-medium-missing`, `09-carry-forward-prior-high-not-fixed`, `10-carry-forward-expired-prior-refreshed-passes`, `11-carry-forward-expired-prior-stale`, `12-carry-forward-downgrade-without-reclassified-by`, `13-carry-forward-downgrade-reclassified-by-owner`, `14-carry-forward-downgrade-reclassified-passes`, `15-carry-forward-prior-fixed-not-due`, `16-carry-forward-prior-low-not-due`, `17-expiry-window-expired`, `18-expiry-window-beyond-horizon`, `19-expiry-window-at-horizon-passes`, `20-expiry-window-equal-run-date`, `21-lows-only-passes`, `22-zero-findings-passes`, `23-lows-inert` (fixture 07 plus an accepted low with a fresh id: the same violations), `24-medium-downgraded-to-low` (prior medium, current low, no `reclassified_by`: `carry_forward` — R10's boundary), `25-all-rules-violated` (sorted violations), `26-pre-duplicate-review-id`, `27-pre-duplicate-entry-id`, `28-pre-duplicate-prior-id`, `29-pre-medium-accepted-no-owner`, `30-pre-medium-deferred-no-expiry`, `31-pre-negative-cap`, `32-pre-band-mismatch`, `33-carry-forward-prior-accepted-no-expiry-refreshed-passes` (prior medium Accepted with expiry `null`, current Accepted with an expiry inside the window: pass — `lapsed` treats `None` as lapsed), `34-carry-forward-prior-accepted-no-expiry-open` (the same prior, current `open`: `carry_forward`). Fixtures 13, 19, 20, 24, 25, 33 and 34 carry exactly the inputs of the model's `FixtureNN` lemma of the same number — ids, severities, statuses, owners (`alice`), `reclassified_by`, `medium_cap`, `expiry_horizon_days`, and each date as `run_date` plus the lemma's `k` days (fixture 19's expiry is `run_date` + 180 = 2027-03-26) — and expect the lemma's verdict; each such fixture's `about` names its lemma.

**`scripts/check-security-disposition.sh`** (Task 7): `[--version V] [--root DIR] [--base REF] [--run-date YYYY-MM-DD] [--rubric FILE] [--no-git]`, a thin wrapper that `exec`s `python3 scripts/lib/specflow/disposition_gate.py` in `--root` (default: the repository root). Version resolution R11; base ref R13; rubric: `--rubric FILE`, else the first fenced `yaml` block of `docs/security/RUBRIC.md` at the base ref (`git show`), else the working tree with a note; `medium_cap` an integer ≥ 0 and `expiry_horizon_days` an integer ≥ 1, otherwise exit 2. First, when any `docs/security/*-review.md` or `*-disposition.md` differs from the base, the ids-only-added walk of R12 over every such file (`git rev-list --reverse <base>..HEAD -- docs/security/` plus the working tree; each revision read with `blocks.split_blocks` and `config.parse`, ids only — no second reader), whether or not any version is then evaluated. For each evaluated version: current files in gate mode (either missing → exit 2: "run /security-review"); prior entries from `blocks.latest_entries(…, before=V, require_header=True)`, where a tagged prior version's review and disposition are read from its tag (R12) and an untagged one from the working tree; each prior entry's severity taken from that version's review (review or finding missing → exit 2); a prior review id with no entry in that version's disposition, or the reverse, → exit 2 naming it; `carried_from` validated (R6); then `decide` with `run_date` (`--run-date`, else today UTC). `--no-git` skips the tag check, the tag reads and the walk, and reads the rubric from `--rubric`, else the working tree's `docs/security/RUBRIC.md`, else exit 2 (R13; pack roots such as `stacks/tauri/overlay` have no rubric, so their callers pass `--rubric`). Output lines:

```
SKIP security-disposition: <reason>
SKIP security-disposition <V>: tagged v<V> — a released version is never re-evaluated
PASS security-disposition <V>: <n> findings, <m> prior entries due, medium_cap <c> and expiry_horizon_days <h> from <ref>:docs/security/RUBRIC.md, run date <d>
FAIL security-disposition <V> <SEC-NNN> <rule>
ERROR security-disposition <file>:<line>: <message>
note: <text>
```

Exit 0 (every evaluated version passed, or nothing to evaluate), 1 (any FAIL), 2 (any ERROR; 2 wins).

**`scripts/verify-release.sh`** (Task 8): `[--version V | V] [--base REF]`, a wrapper over `python3 scripts/lib/specflow/release_gate.py` that, when `SPECFLOW_QG_RUNNING` is not `1`, then runs `run-quality-gates.sh` (R14; otherwise prints `note: under run-quality-gates.sh — not re-running the gates`). Versions: `--version`/positional, else each version whose `docs/releases/<v>-notes.md` differs from the base (committed, uncommitted, or untracked — `git diff --name-only <base>` plus `git ls-files --others --exclude-standard docs/releases/`), else `SKIP verify-release: no release notes differ from <base>` (or `… no base ref <ref>`). Per version, each failure its own `FAIL verify-release <V>: <what>` line: (1) `docs/releases/<V>-{notes,migration,known-limitations}.md` exist; (2) `v<V>` is not a tag; (3) the notes' `## Artifacts` table (backticks stripped from cells) has at least one row, each `<file> | <64-hex> | <integer>`, and when `dist/manifest.json` exists — `{"version", "artifacts": [{"filename", "sha256", "size"}]}`, the shape every release hook writes (`scripts/release-stack.sh.template:41`, `stacks/*/release.sh`) — its `(filename, sha256, size)` set equals the rows' set and every listed `dist/` file hashes to its sha256; an entry missing any of the three keys (a `file` or `name` key, say) is `FAIL verify-release <V>: dist/manifest.json entry <n> has no filename` (never an empty set compared); (4) known-limitations names every SEC id whose current disposition entry is accepted or deferred; (5) `check-security-disposition.sh --version <V>` exits 0 (its exit 2 → verify-release exit 2); (6) every tagged REQ of every live spec in the working tree is claimed by a plan at the base ref (the union of `implements:`, or a whole-walked spec; plans read with `git ls-tree`/`git show` at the base) — `REQ-NNN ([verifiable*], <spec>) is claimed by no merged plan's implements:` — and has `// Proves: REQ-NNN` in the first five lines of some `verification/**/*.dfy` in the working tree; in an instance each of R4's inherited specs (by slug, `frontmatter.INHERITED_SPEC_SLUGS`, present at the base ref — never by `created:`) is skipped with `note: <slug> is inherited from the template; not checked in an instance (F-10/W-7, P5)`. `PASS verify-release <V>: …` when all hold. Exit 0/1/2.

**`scripts/check-test-first.sh`** (Task 10): `[--base REV] [--head REV] [--pr-body-file FILE] [--pack FILE] [--root DIR]`; `--base` defaults to `$SPECFLOW_BASE_REF`; `--head` to `HEAD`. Order: load the pack (`--pack`, else `packinfo.load`; exit 2 on `PackError`); each source root must match a tracked file (`git ls-files -- <root>`; exit 2 naming it); no base → the R15 SKIP; `git rev-list --reverse --no-merges <base>..<head>`; per commit, `git diff-tree --no-commit-id -r --no-renames --name-status <c>` (status `A` or `M` counts; `D` never needs a test; a `non_source:` file and an R15 pin bump — `git diff -U0` shows only `uses:` lines changed in a workflow or composite action — are not source changes); a rule's test side is satisfied from the first listed commit that adds or modifies a matching file with at least one added line that is neither blank nor a comment (R15); for a `cfg-test` rule, a `.rs` file is also satisfied from a commit whose `git diff -U0 <c>^ <c> -- <file>` adds a line inside a `#[cfg(test)]` module of the post-image (`mod` block located by brace matching from the attribute). Lines:

```
FAIL test-first <sha7> <path>: no matching test change in this or an earlier commit (rule '<source> -> <tests>')
FAIL test-first: no REQ-NNN cited in any commit message or the PR body
PASS test-first: <n> commits, <m> source changes, each with a test in the same or an earlier commit; REQ cited
SKIP test-first: no PR range (no --base and no SPECFLOW_BASE_REF — a push to main has none)
SKIP test-first: the PR touches no source file
```

Exit 0/1/2. `ci.yml`'s `gates` job gains, before "Run quality gates", a step "Test-first per commit (REQ-321)" run only on `pull_request`, whose env maps `BASE_SHA`, `HEAD_SHA` and `PR_BODY` to the event's `pull_request.base.sha`, `pull_request.head.sha` and `pull_request.body` expressions and whose `run:` (the step's last key) writes `"$PR_BODY"` to `"$RUNNER_TEMP/pr-body.md"` and runs `bash scripts/check-test-first.sh --base "$BASE_SHA" --head "$HEAD_SHA" --pr-body-file "$RUNNER_TEMP/pr-body.md"`; and a sibling step on `push` that prints the SKIP line. The body never appears inside a `run:` script (script injection).

**`scripts/check-covers.sh`** (Task 13): `[--root DIR]` (or `COVERS_BASE_DIR`); bash with a `python3` heredoc (the `check-traceability.sh` shape) that imports `frontmatter` and `packinfo` — over `frontmatter.claims`, `frontmatter.live_specs` and `packinfo.load`. Walk: `git ls-files` when the root is a git work tree, else the filesystem skipping `.git`, `node_modules`, `target`, `.venv`, `build`, `dist`. Lines: `FAIL covers: REQ-NNN (claimed by <plan>) — no test cites it (# Covers: / // Covers: under the pack's test_globs or tests/governance/)`, `FAIL covers: <file>:<line> cites REQ-NNN, which no live spec defines`, `PASS: check-covers — <n> claimed REQs, each cited by a test`. Exit 0/1; 2 on `PackError` or an unreadable plan.

**`scripts/lib/specflow/coverage.sh`** (Tasks 11, 12; sourced by `run-quality-gates.sh` and the pack hooks; `CFG` is the `config.py` beside it):
- `coverage_min_resolve` — prints `<n> (<source>)`: `$SPECFLOW_COVERAGE_MIN` when set; else the working tree's `coverage_min` (default 80) and, when `SPECFLOW_BASE_REF` resolves, the base's (`git show <ref>:.specflow.yml` into a temp file, then `config.py --file <tmp> get coverage_min --default 80`; no `.specflow.yml` at the base → 80), taking the larger; an invalid value exits 2. It never calls `attestation.py` (R16).
- `pack_coverage_exclude` — `config.py --file .specflow/pack.yml getlist coverage_exclude` (nothing in the template source); when `SPECFLOW_BASE_REF` resolves and `.specflow/pack.yml` exists there, an entry absent at the base prints `FAIL coverage_exclude gains <entry> — a PR cannot widen its own exclusions (base <ref>)` and returns 1 (R16).
- `pytest_cov MIN` — in the cwd: the R16 python command with `COVERAGE_FILE` under `mktemp -d` and always a temporary `--cov-config` file holding only `[run]` and the `omit` list from `pack_coverage_exclude` (empty when there is none), so no repository coverage configuration is read; a missing `pytest_cov` module prints `FAIL pytest-cov missing — pip install --require-hashes -r scripts/requirements.txt` and returns 1.
- `run-quality-gates.sh` exports `SPECFLOW_COVERAGE_MIN` (resolved once, printed as `coverage_min <n> (<source>)`) before section 1 so the hooks read the same value; `ci.yml`'s "Run quality gates" step sets `SPECFLOW_BASE_REF` (`origin/` plus the `github.base_ref` expression, empty on push) and `SPECFLOW_HEAD_BRANCH` (the `github.head_ref` expression) in its env.

**`stacks/flutter/lcov-threshold.sh LCOV MIN [--exclude PATH]…`** (Task 12): stdlib `python3` in a bash wrapper; sums `DA:<line>,<hits>` records per `SF:` file (paths normalised relative to the cwd), skipping excluded files; prints `PASS coverage <x.y>% of <n> lines (min <MIN>%)` or `FAIL coverage <x.y>% of <n> lines, below min <MIN>%` with the excluded list; exit 0/1; 2 on an unreadable file, no `SF:` record, or a `MIN` outside 0–100.

---

### Task 1: One frontmatter reader — `frontmatter.py`, imported by `check-traceability.sh`, `analyze-adr-plan-linkage.sh` and `architecture.py` (REQ-394, REQ-380)

**Files:** create `scripts/lib/specflow/frontmatter.py`, `tests/governance/test_frontmatter.sh`; modify `scripts/check-traceability.sh` (`:19-69`, `:139-140`, `:178-179`), `scripts/analyze-adr-plan-linkage.sh` (`:17-76`), `scripts/lib/specflow/architecture.py` (`:51-53`, `:66-107`, `check()`).

**Interfaces:** `frontmatter.py` under "Interfaces shared by the tasks". Behaviour of the three callers is unchanged: every existing fixture test passes without edits.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_frontmatter.sh`:

```bash
#!/usr/bin/env bash
# REQ-394 / REQ-380: one frontmatter reader. scripts/lib/specflow/frontmatter.py holds parse_text()/read(), parse_list(),
# the strip-quotes / strip-comment rules REQ-380 established, the tag regex and the plan claims; check-traceability.sh,
# analyze-adr-plan-linkage.sh and architecture.py import it instead of carrying copies (check-covers.sh does too, Task 13).
# config.py and attestation.py keep their own reader: CI and run-verifier.sh materialise each alone from the base ref.
# Covers: REQ-394
# Covers: REQ-380
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; FM="$LIB/frontmatter.py"
ck "scripts/lib/specflow/frontmatter.py exists" test -f "$FM"
ck "frontmatter.parse_text/parse_list: the REQ-380 conventions" python3 - "$LIB" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import frontmatter as f
t = ('---\ntype: plan\nspec: "2026-01-01-x"  # a comment\nextended_by: ""\nimplements: [REQ-001, "REQ-002"]  # c\n'
     'bare:\nurl: a#b\nq: "x # y"\n---\n# body\n')
fm = f.parse_text(t)
assert fm["spec"] == "2026-01-01-x", fm
assert fm["extended_by"] == "" and fm["bare"] == "", fm      # REQ-327: an empty-quoted value is empty
assert fm["url"] == "a#b" and fm["q"] == "x # y", fm         # a glued or quoted '#' is not a comment
assert f.parse_list(fm["implements"]) == ["REQ-001", "REQ-002"]
assert f.parse_list("[]") == [] and f.parse_list("") == []
assert f.parse_text("# no frontmatter\n") == {}
assert f.tagged_reqs("- **REQ-901:** x. [verifiable-model]\n- **REQ-902:** names the `[verifiable]` tag.\n") == {"REQ-901"}
PY
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/docs/specs" "$W/docs/plans"
printf -- '---\ntype: spec\nstatus: accepted\n---\n- **REQ-901:** x. [verifiable-model]\n- **REQ-902:** y.\n' > "$W/docs/specs/2099-01-01-a-design.md"
printf -- '---\ntype: spec\nstatus: superseded\n---\n- **REQ-903:** z.\n' > "$W/docs/specs/2099-01-01-b-design.md"
printf -- '---\ntype: brainstorm\n---\nnotes\n' > "$W/docs/specs/2099-01-01-a-brainstorm.md"
printf -- '---\ntype: plan\nspec: 2099-01-01-a\nimplements: [REQ-902, not-a-req]  # one\n---\n' > "$W/docs/plans/p1.md"
printf -- '---\ntype: plan\nspec: 2099-01-01-a\n---\n' > "$W/docs/plans/p0.md"
ck "frontmatter.claims and live_specs: the union, whole-walked and named specs; live excludes superseded and brainstorm" \
  python3 - "$LIB" "$W" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import frontmatter as f
c = f.claims(sys.argv[2])
assert c.implemented == {"REQ-902"}, c.implemented          # lenient: a malformed item is not a claim
assert c.whole_specs == {"2099-01-01-a"} and c.named_specs == {"2099-01-01-a"}, c
assert sorted(p.implements is None for p in c.plans) == [False, True]
assert sorted(f.live_specs(sys.argv[2])) == ["2099-01-01-a"]
PY
for s in scripts/check-traceability.sh scripts/analyze-adr-plan-linkage.sh scripts/lib/specflow/architecture.py; do
  ck "$s imports frontmatter.py" grep -qE '^[[:space:]]*(import frontmatter|from frontmatter import)' "$ROOT/$s"
  ck "$s carries no copy of the parsers" \
    no grep -qE 'def (strip_comment|_strip_comment|strip_quotes|_strip_quotes|parse_list|frontmatter|parse_frontmatter|flat_frontmatter)\(' "$ROOT/$s"
  ck "$s carries no copy of the tag regex" no grep -qF 'verifiable(?:-model)?' "$ROOT/$s"
done
for s in config.py attestation.py; do
  ck "$s stays self-contained (materialised alone from the base ref)" no grep -qE '^[[:space:]]*(import frontmatter|from frontmatter)' "$LIB/$s"
done
finish test_frontmatter
```

- [ ] **Step 2: Run** `bash tests/governance/test_frontmatter.sh`. Expected: `FAIL: scripts/lib/specflow/frontmatter.py exists`, both python checks FAIL (`ModuleNotFoundError`), each "imports frontmatter.py", "no copy of the parsers" and "no copy of the tag regex" check FAILs; the two self-contained checks pass. Exit 1.
- [ ] **Step 3: Implement (intent).** Create `frontmatter.py` per Interfaces by moving today's functions (their behaviour, comments and REQ citations); `claims` walks `docs/plans/*.md` in sorted order. In the two shell scripts pass `"$ROOT"` to the heredoc and import the module; keep every error message and the PASS line byte-identical. In `architecture.py` import `frontmatter` for specs and plans (`TAG_RE`, `live_specs`, `claims`, `spec_slug`), leaving the rich reader. No behaviour change in this task (scoping is Task 2).
- [ ] **Step 4: Run** the test, `bash tests/governance/test_traceability_scoping.sh`, `bash tests/governance/test_analyze_adr_plan_linkage.sh`, `bash tests/governance/test_check_architecture.sh`, `bash tests/governance/test_traceability.sh`, `bash scripts/analyze-adr-plan-linkage.sh` — green; `bash scripts/check-traceability.sh` passes (the proof is already on the base branch, R1). Then the gates.
- [ ] **Step 5: Commit** — "refactor(specflow): one frontmatter reader — frontmatter.py shared by check-traceability, analyze-adr-plan-linkage and architecture.py (REQ-394, REQ-380)"

---

### Task 2: `check-architecture.sh` follows the claims; `confirmed_by:` in the guided profile; gate section 6 (REQ-320, REQ-394, REQ-389, REQ-333)

**Files:** modify `scripts/lib/specflow/architecture.py` (`check()`), `scripts/run-quality-gates.sh` (new section 6 after `:118`), `.claude/commands/architecture.md:21`, `tests/governance/test_check_architecture.sh` (new checks above `finish`), `tests/governance/test_examples.sh` (checks above `finish`: `check-architecture.sh` in guided instances); create `tests/governance/test_gate_sections.sh`.

**Interfaces:** R3 and R4. New error texts: `<ov>: REQ-NNN is [verifiable*] but appears in no kernel_modules[].req_map` (unchanged), `<file>: confirmed_by: missing or empty (profile: guided, REQ-389)`. The PASS line gains `, <k> claimed [verifiable*] REQs checked`. Section 6 of `run-quality-gates.sh`: `# 6. Document gates (REQ-320, REQ-327, REQ-380)` / `SECTION "Document gates"`, running each of `scripts/check-traceability.sh`, `scripts/analyze-adr-plan-linkage.sh`, `scripts/check-architecture.sh` that exists (`bash` it; `PASS <script>` or `FAIL <script>` plus `gate_fail`). `/architecture` says that in the guided profile each overview, threat model and ADR for a `[verifiable*]` REQ carries `confirmed_by:` (and keeps its sentence containing "threat model or overview exists").

- [ ] **Step 1: Write the failing tests.** Append to `tests/governance/test_check_architecture.sh`, above `finish`:

```bash
# P3 (REQ-320, REQ-394): the req_map check follows the claims — the union of implements: across plans, read through
# frontmatter.py; a plan without implements: walks its spec whole; before any plan (the ARCHITECTURE PR) every tagged REQ
# must map (R3). REQ-389's check (R4): a guided instance's v3.2-era architecture artifacts carry confirmed_by:.
# Covers: REQ-320
# Covers: REQ-394
# Covers: REQ-389
PL="$A/docs/plans/2099-01-01-x-plan.md"
mk; edit "$PL" "implements: [REQ-900]" "implements: [REQ-901]"; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "a tagged REQ no plan claims need not map once plans name the spec (REQ-320)" [ "$rc" = 0 ]
mk; edit "$PL" $'implements: [REQ-900]\n' ""; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "a plan without implements: walks its spec whole: the unmapped tagged REQ fails" \
  bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
mk; rm "$PL"; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "no plan yet (the ARCHITECTURE PR): every tagged REQ must map" bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
mk; edit "$PL" "implements: [REQ-900]" "implements: [REQ-900]  # the kernel REQ"; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "implements: is read through frontmatter.py (a trailing comment keeps the claim)" [ "$rc" = 1 ]
ADR="$A/docs/adr/001-x.md"
guided() { mkdir -p "$A/docs/adr"; printf 'profile: %s\n' "$1" > "$A/.specflow.yml"
  printf -- '---\nid: ADR-001\nstatus: accepted\naddresses: [REQ-900]\n---\n# A\n' > "$ADR"; }
mk; guided guided; ca
ck "guided: the overview, threat model and ADR for the tagged REQ without confirmed_by: fail, each named" \
  bash -c '[ "$1" = 1 ] && grep -q "overview.md: confirmed_by" <<<"$2" && grep -q "threat-model.md: confirmed_by" <<<"$2" && grep -q "001-x.md: confirmed_by" <<<"$2"' _ "$rc" "$out"
mk; guided guided; for f in "$OV" "$TM" "$ADR"; do edit "$f" $'---\n' $'---\nconfirmed_by: "founder (acknowledged 2099-01-02)"\n'; done; ca
ck "guided: confirmed_by: on each passes" [ "$rc" = 0 ]
mk; guided guided; for f in "$OV" "$TM" "$ADR"; do edit "$f" $'---\n' $'---\nconfirmed_by: ""\n'; done; ca
ck "guided: an empty confirmed_by: fails" [ "$rc" = 1 ]
mk; guided engineer; ca
ck "engineer profile: confirmed_by: is not required" [ "$rc" = 0 ]
mk; guided guided; edit "$A/docs/specs/2099-01-01-x-design.md" "status: accepted" $'status: accepted\ncreated: "2026-05-28"'; ca
ck "guided: a new spec backdated before the cutoff (created: is the author's) is not grandfathered" [ "$rc" = 1 ]
mk; guided guided; edit "$A/docs/specs/2099-01-01-x-design.md" "status: accepted" $'status: accepted\ncreated: "2026-09-28"'; ca
ck "guided: a spec whose slug is not in the inherited list is not grandfathered" [ "$rc" = 1 ]
ck "grandfathering is a fixed list of the template's inherited spec slugs (the demo and the v3.2 spec)" \
  bash -c 'grep -qF "\"2026-05-28-demo-greeting\"" "$1" && grep -qF "\"2026-09-25-factory-v3-2\"" "$1"' _ "$ROOT/scripts/lib/specflow/frontmatter.py"
mk; guided guided; printf 'stack: python\n' > "$A/.specflow.yml"; ca
ck "a .specflow.yml with no profile: key is guided (config.DEFAULTS): confirmed_by: is required" [ "$rc" = 1 ]
V32=docs/specs/2026-09-25-factory-v3-2-design.md
if [ -f "$ROOT/$V32" ]; then   # the factory's own v3.2 artifacts, as a guided instance inherits them
  G="$W/inherited"; mkdir -p "$G/docs/specs" "$G/docs/architecture" "$G/docs/adr" "$G/docs/plans"
  cp "$ROOT/$V32" "$G/docs/specs/"; cp "$ROOT"/docs/architecture/2026-09-25-factory-v3-2-*.md "$G/docs/architecture/"
  cp "$ROOT"/docs/adr/002-*.md "$ROOT"/docs/adr/003-*.md "$G/docs/adr/"; cp "$ROOT"/docs/plans/*factory-v3-2*.md "$G/docs/plans/"
  printf 'profile: guided\nstack: python\n' > "$G/.specflow.yml"
  rc=0; out=$(ARCH_BASE_DIR="$G" bash "$CA" 2>&1) || rc=$?
  ck "guided: the inherited v3.2 spec, overview, threat model, ADR-002 and ADR-003 without confirmed_by: pass (R4: grandfathered by inherited slug)" [ "$rc" = 0 ]
fi
ck "/architecture says guided artifacts carry confirmed_by:" grep -qF 'confirmed_by:' "$AC"
```

Append to `tests/governance/test_examples.sh`, above `finish` (the tauri and flutter instances there are initialised with `SPECFLOW_NO_SCAFFOLD=1` in the default guided profile, and the python one is guided too):

```bash
# REQ-389 (R4): a freshly initialised guided instance passes check-architecture.sh — the demo and the inherited factory
# v3.2 artifacts are grandfathered by their slugs (frontmatter.INHERITED_SPEC_SLUGS) (gates section 6, the CI first-run (guided) job).
# Covers: REQ-389
for s in tauri flutter; do
  D="$WORK/other-$s"
  if [ -f "$D/.specflow.yml" ]; then
    ck "$s guided instance: check-architecture.sh passes (inherited artifacts grandfathered)" bash -c "cd '$D' && bash scripts/check-architecture.sh"
  fi
done
ck "python guided instance: check-architecture.sh passes (demo and v3.2 grandfathered)" bash -c "cd '$WORK/py' && bash scripts/check-architecture.sh"
```

Create `tests/governance/test_gate_sections.sh`:

```bash
#!/usr/bin/env bash
# REQ-320 (and the P3 gate wiring): run-quality-gates.sh runs the document checkers as section 6 — check-traceability.sh,
# analyze-adr-plan-linkage.sh, check-architecture.sh (check-covers.sh joins in Task 13) — each failure a gate failure,
# listed apart from the floor. Sections 1–5 keep their numbers (docs cite "section 5" for the floor); 6 and 7 follow it.
# Covers: REQ-320
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
G="$ROOT/scripts/run-quality-gates.sh"
sec() { awk -v h="$1" 'index($0, "SECTION \"" h "\"") {f=1; next} /SECTION "/ {f=0} f' "$G"; }
d=$(sec "Document gates")
ck "run-quality-gates.sh has section 6, Document gates" bash -c 'grep -qE "^# 6\. Document gates" "$1" && grep -qF "SECTION \"Document gates\"" "$1"' _ "$G"
for s in check-traceability.sh analyze-adr-plan-linkage.sh check-architecture.sh; do
  ck "Document gates runs scripts/$s" grep -qF "scripts/$s" <<<"$d"
done
ck "a document-gate failure is recorded with gate_fail (a gate failure, not a floor failure)" grep -q 'gate_fail' <<<"$d"
ck "the floor keeps section 5" grep -qE '^# 5\. Security floor' "$G"
ck "Document gates follow the floor and precede the Summary" python3 - "$G" <<'PY'
import sys; t = open(sys.argv[1]).read()
assert t.index('SECTION "Security floor"') < t.index('SECTION "Document gates"') < t.index('SECTION "Summary"')
PY
finish test_gate_sections
```

- [ ] **Step 2: Run** `bash tests/governance/test_check_architecture.sh; bash tests/governance/test_gate_sections.sh`. Expected: "need not map once plans name the spec" FAILs (today every tag must map), the guided cases that expect a failure FAIL (no `confirmed_by:` rule: the missing, empty, backdated, new-slug and no-`profile:` cases, and the inherited-slug list), the `/architecture` check FAILs; the other new cases pass already (P4 behaviour), among them the grandfathering cases, the inherited v3.2 copy and the `test_examples.sh` checks, which guard the change rather than drive it. `test_gate_sections.sh` FAILs on every section check except "the floor keeps section 5". Both exit 1.
- [ ] **Step 3: Implement (intent).** In `check()`: build the per-spec `req_map` obligation from `frontmatter.claims` per R3; add R4 (read `.specflow.yml` with `config.load` only when it exists; grandfathering by `frontmatter.INHERITED_SPEC_SLUGS`, each slug's spec present at the base ref, never by `created:`; ADRs from `docs/adr/*.md` via `frontmatter.read`, `addresses:` via `parse_list`). Add section 6 to the gates per Interfaces. Edit `/architecture` step 21 per Interfaces.
- [ ] **Step 4: Run** both tests, `bash tests/governance/test_examples.sh`, `bash scripts/check-architecture.sh` (this repository passes: REQ-322 and REQ-341 are both mapped), and the gates — green.
- [ ] **Step 5: Commit** — "feat(architecture): check-architecture.sh follows the implements: claims, requires confirmed_by: in the guided profile, runs as gate section 6 (REQ-320, REQ-394, REQ-389, REQ-333)"

---

### Task 3: CVSS v4.0 scoring — `cvss4.py` over FIRST's vendored data, with conformance vectors from FIRST's own JavaScript (REQ-322)

**Network at implement time:** about 10 seconds (six files from `raw.githubusercontent.com` at the pinned commit), plus node for the generator (under 5 seconds). The test is offline.

**Files:** create `scripts/lib/specflow/cvss4.py`, `scripts/lib/specflow/cvss4_data.py`, `scripts/lib/specflow/cvss4_LICENSE`, `tests/governance/fixtures/cvss4/generate.mjs`, `tests/governance/fixtures/cvss4/vectors.json`, `tests/governance/test_cvss4.sh`; modify `docs/security/RUBRIC.md` (worked example `:26-47`: each example gains its full vector string and FIRST's exact score).

**Interfaces:** `cvss4.py`, `cvss4_data.py` and the conformance vectors under "Interfaces shared by the tasks"; R8.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_cvss4.sh`:

```bash
#!/usr/bin/env bash
# REQ-322 (ADR-002: severity is derived from a required CVSS v4.0 vector): cvss4.py scores a vector with FIRST's algorithm
# over the macro-vector lookup table, max-composed vectors and max-severity distances vendored once from a pinned commit of
# github.com/FIRSTdotorg/cvss-v4-calculator (BSD-2-Clause; URL, commit and each file's sha256 recorded), and agrees with
# FIRST's own JavaScript on every conformance vector (generated with node at authoring time; never fetched in a test).
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; V="$ROOT/tests/governance/fixtures/cvss4/vectors.json"
for f in "$LIB/cvss4.py" "$LIB/cvss4_data.py" "$LIB/cvss4_LICENSE" "$V" "$ROOT/tests/governance/fixtures/cvss4/generate.mjs"; do
  ck "$(basename "$f") exists" test -f "$f"
done
ck "provenance: the FIRST repository, a 40-hex commit, a sha256 per fetched file, BSD-2-Clause, 270 lookup entries" \
  python3 - "$LIB" <<'PY'
import re, sys; sys.path.insert(0, sys.argv[1]); import cvss4_data as d
s = d.SOURCE
assert s["repository"] == "https://github.com/FIRSTdotorg/cvss-v4-calculator", s
assert re.fullmatch(r"[0-9a-f]{40}", s["commit"]) and s["license"] == "BSD-2-Clause", s
for f in ("cvss_lookup.js", "max_composed.js", "max_severity.js", "cvss_score.js", "LICENSE"):
    assert re.fullmatch(r"[0-9a-f]{64}", s["files"][f]), f
assert len(d.LOOKUP) == 270 and all(re.fullmatch(r"[0-9]{6}", k) for k in d.LOOKUP), len(d.LOOKUP)
PY
ck "cvss4.py's header names the source URL and the commit" \
  bash -c 'head -30 "$1" | grep -qF "FIRSTdotorg/cvss-v4-calculator" && head -30 "$1" | grep -qE "[0-9a-f]{40}"' _ "$LIB/cvss4.py"
ck "the BSD-2-Clause notice ships beside the data" grep -qF 'Redistribution and use in source and binary forms' "$LIB/cvss4_LICENSE"
ck "no network or file I/O in the scorer (pure: the kernel imports it)" \
  no grep -qE '^[[:space:]]*(import|from) (urllib|http|socket|subprocess)|open\(' "$LIB/cvss4.py" "$LIB/cvss4_data.py"
report=$(python3 - "$LIB" "$V" <<'PY'
import json, sys; sys.path.insert(0, sys.argv[1]); import cvss4
v = json.load(open(sys.argv[2])); bad = []
if "node" not in v["source"]["command"] or v["source"]["commit"] != __import__("cvss4_data").SOURCE["commit"]:
    bad.append("vectors.json: provenance does not match cvss4_data.SOURCE")
vs = v["vectors"]
if len(vs) < 60: bad.append(f"only {len(vs)} vectors (want >= 60)")
bands = {c["severity"] for c in vs}
if not {"none", "low", "medium", "high", "critical"} <= bands: bad.append(f"bands covered: {sorted(bands)}")
if sum("/E:" in c["vector"] for c in vs) < 5: bad.append("fewer than 5 Threat (E:) vectors")
if sum(any(f"/{m}:" in c["vector"] for m in ("CR", "IR", "AR", "MAV", "MVC", "MSI")) for c in vs) < 5:
    bad.append("fewer than 5 Environmental vectors")
for c in vs:
    try:
        got = cvss4.score(c["vector"]); sev = cvss4.severity(got)
    except Exception as e:
        bad.append(f'{c["vector"]}: raised {e!r}'); continue
    if got != c["score"] or sev != c["severity"] or cvss4.band(c["vector"]) != sev:
        bad.append(f'{c["vector"]}: {got} {sev} != FIRST {c["score"]} {c["severity"]}')
if len(v["malformed"]) < 10: bad.append("fewer than 10 malformed vectors")
for m in v["malformed"]:
    try:
        cvss4.parse(m); bad.append(f"malformed accepted: {m!r}")
    except cvss4.CvssError:
        pass
print("\n".join(bad))
PY
)
ck "cvss4 agrees with FIRST's calculator on every conformance vector and rejects every malformed one${report:+: $report}" [ -z "$report" ]
ck "RUBRIC.md's worked example (high) and counter-example (medium) carry vectors that FIRST scores in those bands" \
  python3 - "$LIB" "$ROOT/docs/security/RUBRIC.md" "$V" <<'PY'
import json, re, sys; sys.path.insert(0, sys.argv[1]); import cvss4
vec = re.findall(r"CVSS:4\.0/[A-Z]+:[A-Za-z]+(?:/[A-Z]+:[A-Za-z]+)*", open(sys.argv[2]).read())
assert len(vec) == 2, vec
assert [cvss4.band(x) for x in vec] == ["high", "medium"], [(x, cvss4.score(x)) for x in vec]
known = {c["vector"] for c in json.load(open(sys.argv[3]))["vectors"]}
assert set(vec) <= known, "the rubric vectors are conformance vectors"
PY
ck "finding_severity: a 0.0 vector (no impact) is an informational low (R20); every other band is itself" python3 - "$LIB" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import cvss4
z = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N"
assert cvss4.score(z) == 0.0 and cvss4.band(z) == "none" and cvss4.finding_severity(z) == "low"
h = "CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:H/VI:H/VA:N/SC:N/SI:N/SA:N"
assert cvss4.finding_severity(h) == cvss4.band(h) == "high"
PY
finish test_cvss4
```

- [ ] **Step 2: Run** `bash tests/governance/test_cvss4.sh`. Expected: the five existence checks FAIL, provenance and the header FAIL, the conformance check FAILs (`ModuleNotFoundError`), the rubric and `finding_severity` checks FAIL; the I/O check passes vacuously. Exit 1.
- [ ] **Step 3: Implement (intent).**
  1. Fetch once: `mkdir -p "$TMPDIR/first-cvss4"`; for each of `cvss_lookup.js max_composed.js max_severity.js cvss_score.js metrics.js LICENSE`, `curl --proto '=https' --tlsv1.2 -fsSL -o "$TMPDIR/first-cvss4/<f>" "https://raw.githubusercontent.com/FIRSTdotorg/cvss-v4-calculator/c5b0d409ae9f57c44264c6ce5f27d89298e1d32a/<f>"`; record `shasum -a 256` of each. Record the wall-clock.
  2. Convert the data with a one-off node snippet (the same `vm` loading as the generator, printing the three objects as JSON), and write `cvss4_data.py` (dict literals, `SOURCE` per Interfaces, the snippet's command in `SOURCE["converted_by"]`). Copy `LICENSE` to `cvss4_LICENSE`.
  3. Write `cvss4.py` (with `finding_severity`, R20), porting `macroVector()`, `m()`, `getEQMaxes()`, `extractValueMetric()` and `cvss_score()` from `cvss_score.js` line by line (the level tables, the EQ3/EQ6 joint handling, the NaN-ignored distances), the rounding per Interfaces; the header names the source, the commit, the licence and that nothing is fetched at run time. `METRIC_ORDER`/`METRIC_VALUES` follow the CVSS v4.0 specification's vector string order (FIRST's `metrics.js` as the cross-check).
  4. Write `generate.mjs` per Interfaces and run `node tests/governance/fixtures/cvss4/generate.mjs "$TMPDIR/first-cvss4" > tests/governance/fixtures/cvss4/vectors.json`.
  5. RUBRIC.md: the worked example's metric table gains the vector `CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:H/VI:H/VA:N/SC:N/SI:N/SA:N` and FIRST's score, 7.6 (high), in place of "≈ 7.1"; the counter-example gains the vector `CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N` — the vulnerable system's confidentiality lowered to None per its "no secrets in scope" reasoning, integrity still High because the renderer writes the HTML the attacker controls — and FIRST's score, 6.0 (medium), in place of "≈ 4.x", with a Why row saying so. (Measured by the fresh-eyes review with FIRST's JavaScript at the pinned commit under node 24: lowering integrity too, to `VI:L` or `VI:N`, scores 2.3, low — so the counter-example lowers confidentiality only.) Both vectors are in the generator's fixed list. If FIRST's calculator, run here, scores the example outside high or the counter-example outside medium, stop and report: the reasoning, not the band, is what the rubric asserts.
- [ ] **Step 4: Run** the test and the gates — green.
- [ ] **Step 5: Commit** — "feat(security): cvss4.py — CVSS v4.0 scoring over FIRST's vendored macro-vector data, conformance vectors from FIRST's calculator (REQ-322)"

---

### Task 4: The disposition kernel — `records.py` and `decide()`, the twin of the Dafny model, with fixtures that mirror it (REQ-322)

**Files:** create `scripts/lib/specflow/records.py`, `scripts/lib/specflow/disposition.py`, `tests/governance/fixtures/disposition/01-…json` to `34-…json` (Interfaces "Kernel fixtures"), `tests/governance/test_disposition_kernel.sh`.

**Interfaces:** `records.py`, `disposition.py`, "The Dafny model", "Kernel fixtures"; R9, R10.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_disposition_kernel.sh`:

```bash
#!/usr/bin/env bash
# REQ-322 (ADR-002): decide() is a pure function over the review findings, the disposition entries and the latest prior
# entry per id: PASS iff rules 1–5 hold; order-independent; lows with fresh ids never affect rules 2–5; zero findings with
# no due carry-forward pass; a precondition violation raises ValueError (exit 2 in the wrapper), never FAIL. It is the
# twin of verification/factory_v3_2/disposition.dfy: the rule functions carry the model's predicate names, and the
# fixtures mirror the model — one per rule and sub-clause, the downgrade path, the expired-prior carry-forward, a
# lows-only case, the zero-findings case — each also run under five shuffles of every input.
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; K="$LIB/disposition.py"; FX="$ROOT/tests/governance/fixtures/disposition"
DFY="$ROOT/verification/factory_v3_2/disposition.dfy"
ck "records.py and disposition.py exist" test -f "$LIB/records.py" -a -f "$K"
ck "the model carries its Proves header in the first five lines" bash -c 'head -5 "$1" | grep -qx "// Proves: REQ-322"' _ "$DFY"
for p in Rule1SetEquality Rule2SevereFixed Rule3MediumCap Rule4CarryForward Rule5ExpiryWindow AllRulesHold Pre Decide \
         SevIs JoinedSevere JoinedAtLeastMedium RankedBelow Due Lapsed ReclassOk EntryCarries CarriedOk InWindow MediumsAD \
         V1 V2 V3 V4 V5 Violations2to5 Violations; do
  ck "the model defines $p" grep -qE "(predicate|function) $p[(<]" "$DFY"
done
for l in DecidePassIffAllRulesHold DecidePermutationInvariant LowsInertForRules2to5 ZeroFindingsPass \
         InWindowBoundaries DueBoundaries LapsedBoundaries DowngradeByOwnerNotCarried SeverePriorLeftAcceptedNotCarried \
         MediumsADCountsOnlyAcceptedDeferredMediums Fixture13 Fixture19 Fixture20 Fixture24 Fixture25 Fixture33 Fixture34; do
  ck "the model proves $l" grep -qE "lemma $l[(<]" "$DFY"
done
ck "each FixtureNN lemma of the model has its fixture NN-*.json" bash -c \
  'for n in $(grep -oE "lemma Fixture[0-9]+" "$1" | grep -oE "[0-9]+"); do ls "$2/$n-"*.json >/dev/null 2>&1 || exit 1; done' _ "$DFY" "$FX"
ck "the model assumes nothing (no {:axiom}, no assume statement)" no grep -qE '\{:axiom\}|^[[:space:]]*assume[[:space:]]' "$DFY"
for f in rule1_set_equality rule2_severe_fixed rule3_medium_cap rule4_carry_forward rule5_expiry_window all_rules_hold pre decide \
         sev_is joined_severe joined_at_least_medium ranked_below due lapsed reclass_ok entry_carries carried_ok in_window mediums_ad \
         v1 v2 v3 v4 v5 violations_2to5 violations; do
  ck "the twin defines $f (the model's name, snake_case)" grep -qE "^def $f\(" "$K"
done
ck "the kernel is pure: no I/O imports, no open/print/input" python3 - "$K" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
allowed = {"__future__", "dataclasses", "datetime", "enum", "typing", "records", "cvss4"}
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        assert {a.name.split(".")[0] for a in n.names} <= allowed, [a.name for a in n.names]
    if isinstance(n, ast.ImportFrom):
        assert (n.module or "").split(".")[0] in allowed, n.module
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
        assert n.func.id not in ("open", "print", "input", "exec", "eval"), n.func.id
PY
n=$(find "$FX" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
ck "at least 34 kernel fixtures ($n)" [ "${n:-0}" -ge 34 ]
for r in set_equality severe_not_fixed medium_cap carry_forward expiry_window; do
  ck "some fixture expects a $r violation" bash -c 'grep -l "\"$1\"" "$2"/*.json 2>/dev/null | grep -q .' _ "$r" "$FX"
done
report=$(python3 - "$LIB" "$FX" "$ROOT/tests/governance/fixtures/cvss4/vectors.json" <<'PY'
import datetime, glob, json, os, random, sys
sys.path.insert(0, sys.argv[1]); import records as R, disposition as D
vec = {}
for c in json.load(open(sys.argv[3]))["vectors"]:
    vec.setdefault(c["severity"], c["vector"])
day = lambda s: datetime.date.fromisoformat(s) if s else None
def load(fx):
    v = lambda s: vec[s[1:]] if s.startswith("@") else s
    rv = [R.Finding(f["id"], R.Severity(f["severity"]), v(f["cvss_vector"])) for f in fx["review"]]
    dp = [R.Entry(e["id"], R.Status(e["status"]), e.get("owner", ""), day(e.get("expiry")), e.get("rationale", ""),
                  e.get("reclassified_by")) for e in fx["disposition"]]
    pr = [R.PriorEntry(p["id"], R.Severity(p["severity"]), R.Status(p["status"]), day(p.get("expiry")), p["version"])
          for p in fx["prior"]]
    return rv, dp, pr, fx["medium_cap"], fx["expiry_horizon_days"], day(fx["run_date"])
def run(args):
    try:
        v = D.decide(*args)
        return {"passed": v.passed, "violations": [[x.id, x.rule.value] for x in v.violations]}
    except ValueError:
        return {"error": "ValueError"}
bad = []
for p in sorted(glob.glob(os.path.join(sys.argv[2], "*.json"))):
    name = os.path.basename(p); fx = json.load(open(p)); args = load(fx); got = run(args)
    if got != fx["expect"]:
        bad.append(f"{name}: got {got}, want {fx['expect']}"); continue
    if "passed" in got and got["passed"] != D.all_rules_hold(*args):
        bad.append(f"{name}: decide().passed != all_rules_hold() (theorem 1's twin)")
    for seed in range(5):
        rng = random.Random(seed); sh = [list(a) for a in args[:3]]
        for s in sh: rng.shuffle(s)
        if run((sh[0], sh[1], sh[2]) + args[3:]) != got:
            bad.append(f"{name}: verdict changes under shuffle seed {seed}")
print("\n".join(bad))
PY
)
ck "every fixture's verdict matches, equals all_rules_hold, and survives five shuffles${report:+: $report}" [ -z "$report" ]
finish test_disposition_kernel
```

- [ ] **Step 2: Run** `bash tests/governance/test_disposition_kernel.sh`. Expected: the model checks pass (the proof, with its helpers, boundary lemmas and `FixtureNN` lemmas, is on the base branch); the FixtureNN-to-fixture pairing, the twin checks, the purity check, the fixture count, the per-rule greps and the fixture run FAIL (no module, no fixtures). Exit 1.
- [ ] **Step 3: Implement (intent).** `records.py` per Interfaces (frozen dataclasses, string-valued enums). `disposition.py`: one function per model predicate and violation set, `decide` checking `pre` first (R9's re-check through `cvss4.finding_severity`), then returning `Verdict(passed=not v, violations=tuple(sorted(v, key=lambda x: (x.id, x.rule.value))))`. Write the 34 fixtures (the expected verdicts derived by hand from ADR-002's rules, each file's `about` naming the model predicate it mirrors; fixtures 13, 19, 20, 24, 25, 33 and 34 transcribe their `FixtureNN` lemma's inputs and verdict, which the model has proved). `lapsed` treats a `None` expiry as lapsed, as the model does (fixtures 33, 34). Run the Dafny model under both versions unchanged (no edit to `verification/` in this task).
- [ ] **Step 4: Run** the test and the gates — green.
- [ ] **Step 5: Commit** — "feat(security): the disposition kernel — records.py and decide(), the Python twin of disposition.dfy, with 34 fixtures that mirror the model (REQ-322)"

---

### Task 5: The block schema and `blocks.py`, the one parser — `floor.py` imports it (REQ-322, REQ-332)

**Files:** create `schemas/security-disposition-template.md`, `scripts/lib/specflow/blocks.py`, `tests/governance/test_security_blocks.sh`; modify `scripts/lib/specflow/floor.py` (`:45-199`, imports).

**Interfaces:** "The security schema", `blocks.py`; R5, R6. The template shows the header, one finding block with its body and reasoning table, one disposition entry, and the rules (bands from RUBRIC.md, carried findings, the downgrade path, lows, floor and gate modes).

- [ ] **Step 1: Write the failing test** — `tests/governance/test_security_blocks.sh`:

```bash
#!/usr/bin/env bash
# REQ-322 / REQ-332: blocks.py is the one parser of review and disposition blocks (schemas/security-disposition-template.md):
# a header block (schema, kind, version), finding blocks (id, severity, cvss_vector, cite, affects, carried_from) and
# entries (id, status, owner, expiry, rationale, reclassified_by, suppresses, inherited). Duplicate ids, unknown keys, an
# invalid vector, a severity that is not the vector's band, an unterminated block, a missing header (gate mode) and, once
# joined, an accepted/deferred medium-or-above entry without owner or expiry are parser errors (exit 2). The latest-entry
# reduction (versions by semver) is one function; floor.py imports it and keeps no reader of its own (P4 H4).
# Covers: REQ-322
# Covers: REQ-332
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; B="$LIB/blocks.py"; FP="$LIB/floor.py"; TPL="$ROOT/schemas/security-disposition-template.md"
ck "blocks.py exists" test -f "$B"
for k in 'schema: specflow-security/1' 'kind: review' 'kind: disposition' 'cvss_vector:' 'carried_from:' 'reclassified_by:' 'suppresses:' 'inherited:'; do
  ck "the schema template shows '$k'" grep -qF "$k" "$TPL"
done
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
read -r VH VM VL < <(python3 - "$ROOT/tests/governance/fixtures/cvss4/vectors.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))["vectors"]
print(*(next(c["vector"] for c in v if c["severity"] == s) for s in ("high", "medium", "low")))
PY
)
hdr() { printf -- '---\nschema: specflow-security/1\nkind: %s\nversion: %s\n---\n\n# %s\n\n' "$1" "$2" "$1"; }
finding() { printf -- '---\nid: %s\nseverity: %s\ncvss_vector: %s\ncite: [CWE-20]\naffects: [src/a.py:1]\n---\n\nbody\n\n' "$1" "$2" "$3"; }
entry() { printf -- '---\nid: %s\nstatus: %s\nowner: %s\n' "$1" "$2" "${4-alice}"
  [ -z "${3:-}" ] || printf 'expiry: %s\n' "$3"; printf 'rationale: "fixture rationale text"\n---\n\n'; }
edit() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
t = open(p).read(); assert old in t, old; open(p, "w").write(t.replace(old, new, 1))
PY
}
D="$W/docs/security"; mkdir -p "$D"; RV="$D/1.0.0-review.md"; DS="$D/1.0.0-disposition.md"
ok() { { hdr review 1.0.0; finding SEC-001 medium "$VM"; finding SEC-002 low "$VL"; } > "$RV"
       { hdr disposition 1.0.0; entry SEC-001 accepted 2026-12-01; entry SEC-002 accepted; } > "$DS"; }
bc() { rc=0; out=$(python3 "$B" check "$RV" "$DS" 2>&1) || rc=$?; }
ok; bc; ck "a well-formed pair parses (an accepted low needs no expiry)" [ "$rc" = 0 ]
ok; finding SEC-001 low "$VL" >> "$RV"; bc
ck "a duplicate review id is a parser error (exit 2) naming it" bash -c '[ "$1" = 2 ] && grep -q "SEC-001" <<<"$2"' _ "$rc" "$out"
ok; entry SEC-002 fixed >> "$DS"; bc
ck "a duplicate disposition id is a parser error naming it" bash -c '[ "$1" = 2 ] && grep -q "SEC-002" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" "severity: medium" "severity: high"; bc
ck "a severity that is not the vector's band is a parser error naming both" \
  bash -c '[ "$1" = 2 ] && grep -q "high" <<<"$2" && grep -q "medium" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" "cvss_vector: CVSS:4.0/AV:" "cvss_vector: CVSS:4.0/AV:Q/X:"; bc
ck "an invalid vector is a parser error naming cvss_vector" bash -c '[ "$1" = 2 ] && grep -q "cvss_vector" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" "expiry: 2026-12-01" "expirey: 2026-12-01"; bc
ck "an unknown key is a parser error naming it (a typo never drops a field)" bash -c '[ "$1" = 2 ] && grep -q "expirey" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" "owner: alice" "owner: "; bc
ck "an accepted medium without owner is a parser error" bash -c '[ "$1" = 2 ] && grep -q "owner" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" $'expiry: 2026-12-01\n' ""; bc
ck "an accepted medium without expiry is a parser error" bash -c '[ "$1" = 2 ] && grep -q "expiry" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" "status: accepted" "status: waived"; bc
ck "an unknown status is a parser error naming it" bash -c '[ "$1" = 2 ] && grep -q "waived" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" $'schema: specflow-security/1\n' ""; bc
ck "gate mode: a disposition without the schema header is a parser error" bash -c '[ "$1" = 2 ] && grep -q "schema" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" "version: 1.0.0" "version: 1.0.1"; bc
ck "a header version that is not the file name's is a parser error naming it" bash -c '[ "$1" = 2 ] && grep -q "1.0.1" <<<"$2"' _ "$rc" "$out"
ok; printf -- '---\nid: SEC-003\nstatus: fixed\n' >> "$DS"; bc
ck "an unterminated block is a parser error (fail closed)" bash -c '[ "$1" = 2 ] && grep -qi "unterminated" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" $'affects: [src/a.py:1]\n---' $'affects: [src/a.py:1]\ncarried_from: 2.0.0\n---'; bc
ck "carried_from must name an earlier version" bash -c '[ "$1" = 2 ] && grep -q "carried_from" <<<"$2"' _ "$rc" "$out"
Z="CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N"
ok; finding SEC-003 low "$Z" >> "$RV"; entry SEC-003 accepted >> "$DS"; bc
ck "an informational finding (0.0: every impact N) is severity low (R20)" [ "$rc" = 0 ]
ok; finding SEC-003 medium "$Z" >> "$RV"; entry SEC-003 fixed >> "$DS"; bc
ck "…and a 0.0 vector at any other severity is a parser error naming the id" bash -c '[ "$1" = 2 ] && grep -q "SEC-003" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" $'id: SEC-002\n' $'id: "SEC-002"\n'; bc
ck "a quoted id is the bare id (values through config.parse, one reading for the gate and R12's walk)" [ "$rc" = 0 ]
L="$W/l"; mkdir -p "$L"
{ hdr disposition 0.9.0; entry SEC-001 accepted 2026-12-01; } > "$L/0.9.0-disposition.md"
{ hdr disposition 0.10.0; entry SEC-001 fixed; } > "$L/0.10.0-disposition.md"
{ hdr disposition 0.0.0-skeleton; entry SEC-002 accepted 2026-12-01; } > "$L/0.0.0-skeleton-disposition.md"
ck "latest entry per id orders versions by semver (0.10.0 after 0.9.0; a pre-release before its release)" \
  bash -c 'o=$(python3 "$1" latest "$2"); grep -qx "SEC-001 0.10.0 fixed" <<<"$o" && grep -qx "SEC-002 0.0.0-skeleton accepted" <<<"$o"' _ "$B" "$L"
ck "…and --before 0.10.0 leaves that version out (the wrapper's prior entries)" \
  bash -c 'python3 "$1" latest "$2" --before 0.10.0 | grep -qx "SEC-001 0.9.0 accepted"' _ "$B" "$L"
ck "floor.py imports blocks.py" grep -qE '^(import blocks|from blocks import)' "$FP"
for f in _parse_disposition_blocks_at parse_inline_list _version_key; do
  ck "floor.py no longer defines $f (one reader)" no grep -qE "^def $f\(" "$FP"
done
finish test_security_blocks
```

- [ ] **Step 2: Run** `bash tests/governance/test_security_blocks.sh`. Expected: `blocks.py exists` and every template check FAIL; every parse case FAILs — python cannot open `blocks.py` (exit 2, so a check on the exit code alone would pass for the wrong reason), which is why each error case also greps its message (the id, the key, the version, `carried_from`), and the cases that expect exit 0 fail on the exit code; the latest checks FAIL; `floor.py imports blocks.py` FAILs and the three "no longer defines" checks FAIL. Exit 1.
- [ ] **Step 3: Implement (intent).** Write the template and `blocks.py` per Interfaces (values through `config.parse` per block; `cvss4.parse`/`cvss4.band` for vectors). In `floor.py`, import `blocks` and replace its reader per R5, keeping `load_dispositions`' and `_latest_disposition_entries`' return shapes and P4's error texts; floor mode stays header-optional.
- [ ] **Step 4: Run** the test, `bash tests/governance/test_suppressions.sh`, `bash tests/governance/test_suppression_expiry.sh`, `bash tests/governance/test_security_review.sh`, `bash scripts/check-suppressions.sh`, and the gates — green, with no edit to the P4 tests.
- [ ] **Step 5: Commit** — "feat(security): the block schema and blocks.py, the one review/disposition parser; floor.py reads through it (REQ-322, REQ-332)"

---

### Task 6: The shipped security documents in the schema — demo and tauri skeleton; RUBRIC's horizon; README's schema migrations; carried findings in the SEC-uniqueness check (REQ-332, REQ-322)

**Files:** modify `docs/security/0.0.1-demo-review.md`, `docs/security/0.0.1-demo-disposition.md` (header block at line 1 only), `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md` (header; `vector:` → `cvss_vector:`; vectors for SEC-002 and SEC-003; a reasoning table per finding; the "pending (P3 schema)" sentence `:18-20` rewritten), `stacks/tauri/overlay/docs/security/0.0.0-skeleton-disposition.md` (header only), `docs/security/RUBRIC.md:6-8` (`expiry_horizon_days: 180` with a comment citing ADR-002 rule 5) and its bands and rules (a `0.0` row: no impact, an informational finding recorded as `low`, R20; a rule stating the open-medium residual), `docs/security/README.md` (`:3` points at the template; new `## Schema migrations`), `scripts/check-traceability.sh:161-170`, `tests/governance/test_stack_packs.sh:356-371` (the skeleton review check, below); create `tests/governance/test_security_schema_docs.sh`.

**Interfaces:** R6, R7, R20. SEC-002 and SEC-003 are unmaintained crates with no known vulnerability, so they get informational vectors: base exploitability metrics from their advisories' facts (reachable only through Linux-only build dependencies — for example `AV:L`, `AT:P`) and every impact metric `N` (FIRST score 0.0), `severity: low`, and a body sentence "Informational: no known vulnerability, so no impact is scored (R20); low is the floor a finding takes." Nothing invents an impact. Each vector is added to `generate.mjs`'s fixed list and `vectors.json` regenerated (node, offline, under 5 seconds). The `## Tools run` sections and their evidence lines are not touched. The rewritten sentence at `:18-20` keeps "provisional", "second reviewer" and `art-threat-driven-security` ahead of `## Tools run` (the `test_stack_packs.sh` check asserts them). RUBRIC.md's open-medium rule: "A medium left `status: open` is not counted toward `medium_cap` and needs no owner or expiry (ADR-002 rule 3 counts accepted/deferred mediums only), and carry-forward re-lists it at every release; reviewers look for long-open mediums."

- [ ] **Step 1: Write the failing test** — `tests/governance/test_security_schema_docs.sh`:

```bash
#!/usr/bin/env bash
# REQ-332 / REQ-322: the shipped security documents are in the block schema. The demo review and disposition gain the
# schema header only (a schema migration, not an addendum — docs/security/README.md); the tauri skeleton review's findings
# carry a cvss_vector whose band is the recorded severity, with the metric reasoning in the body, and its disposition keeps
# suppresses: and inherited:. RUBRIC.md carries expiry_horizon_days (ADR-002 rule 5). A carried-forward finding
# (carried_from:) re-lists an id without redefining it (check-traceability.sh's SEC uniqueness).
# Covers: REQ-332
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
B="$ROOT/scripts/lib/specflow/blocks.py"
pair() { python3 "$B" check "$1-review.md" "$1-disposition.md"; }
if [[ -f "$ROOT/docs/security/0.0.1-demo-review.md" ]]; then
  ck "the demo review and disposition parse in the schema (zero findings)" pair "$ROOT/docs/security/0.0.1-demo"
  ck "the demo review still carries exactly one addendum" [ "$(grep -c '^### Addendum' "$ROOT/docs/security/0.0.1-demo-review.md")" = 1 ]
fi
if ! instance; then
  S="$ROOT/stacks/tauri/overlay/docs/security/0.0.0-skeleton"
  ck "the tauri skeleton review and disposition parse in the schema (each severity is its vector's finding_severity)" pair "$S"
  ck "SEC-002 and SEC-003 say they are informational (0.0 vectors, R20)" [ "$(grep -ci 'informational' "$S-review.md")" -ge 2 ]
  ck "no skeleton finding is 'pending'" no grep -qF 'pending (P3 schema)' "$S-review.md"
  ck "no skeleton finding uses the old vector: key" no grep -qE '^vector:' "$S-review.md"
  ck "each skeleton finding carries a metric-reasoning table" [ "$(grep -c '^| Attack Vector |' "$S-review.md")" -ge 3 ]
  ck "the skeleton disposition keeps suppresses: and inherited: on all three entries" \
    bash -c '[ "$(grep -c "^suppresses:" "$1")" = 3 ] && [ "$(grep -c "^inherited:" "$1")" = 3 ]' _ "$S-disposition.md"
fi
RB="$ROOT/docs/security/RUBRIC.md"; RM="$ROOT/docs/security/README.md"
ck "RUBRIC.md: medium_cap 5 and expiry_horizon_days 180" bash -c 'grep -qE "^medium_cap: 5" "$1" && grep -qE "^expiry_horizon_days: 180" "$1"' _ "$RB"
ck "RUBRIC.md: a 0.0 vector is an informational low (R20), and an open medium is not capped (the residual reviewers look for)" \
  bash -c 'grep -qF "0.0" "$1" && grep -qiF "informational" "$1" && grep -qiF "long-open mediums" "$1"' _ "$RB"
ck "README: per-finding frontmatter points at the schema template, not 'spec § Artifact Schemas'" \
  bash -c 'grep -qF "schemas/security-disposition-template.md" "$1" && ! grep -qF "Artifact Schemas" "$1"' _ "$RM"
sm=$(awk '/^## Schema migrations$/{f=1; next} /^## /{f=0} f' "$RM")
for w in 'specflow-security/1' '0.0.1-demo-review.md' '0.0.1-demo-disposition.md' 'no SEC' 'not an addendum' '0.0.0-skeleton'; do
  ck "README Schema migrations states '$w'" grep -qF -- "$w" <<<"$sm"
done
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
T="$W/t"; mkdir -p "$T/docs/security" "$T/docs/specs" "$T/docs/plans"
printf -- '---\nid: SEC-001\nseverity: medium\n---\n' > "$T/docs/security/0.0.0-skeleton-review.md"
printf -- '---\nid: SEC-001\nseverity: medium\ncarried_from: 0.0.0-skeleton\n---\n' > "$T/docs/security/0.1.0-review.md"
ck "a carried-forward finding (carried_from:) is a reference, not a second definition" env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
printf -- '---\nid: SEC-001\nseverity: medium\n---\n' > "$T/docs/security/0.1.0-review.md"
ck "…without carried_from: it is a duplicate definition" no env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
finish test_security_schema_docs
```

In `tests/governance/test_stack_packs.sh`, the skeleton review check (`:356-371`) changes with the key, in the same commit; its comment drops "(or says it is pending P3's schema)", and its per-block assertions become:

```python
for sec, b in blocks.items():
    assert re.search(r"^cvss_vector: CVSS:4\.0/\S+$", b, re.M) and not re.search(r"^vector:", b, re.M), (sec, b)
assert "pending (P3 schema)" not in text
assert "cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N" in blocks["SEC-001"]
```

The CWE-758 assertions and the summary assertions ("provisional", "second reviewer", "art-threat-driven-security" before `## Tools run`) stay as they are.

- [ ] **Step 2: Run** `bash tests/governance/test_security_schema_docs.sh; bash tests/governance/test_stack_packs.sh`. Expected: both `pair` checks FAIL (no header; `vector:` is an unknown key; `pending`), the "pending", "vector:", informational, reasoning-table, RUBRIC, README and Schema-migrations checks FAIL, the carried-forward check FAILs (duplicate definition today); the addendum-count, `suppresses:`/`inherited:` and duplicate checks pass. `test_stack_packs.sh`'s skeleton check FAILs (`vector:` and `pending`); its other checks pass. Both exit 1.
- [ ] **Step 3: Implement (intent).** Per Files and Interfaces. `check-traceability.sh`'s SEC uniqueness reads the review blocks through `blocks.split_blocks` (lenient: it counts an `id: SEC-NNN` block as a definition unless the block has `carried_from:`; no vector validation there, so `test_security_review.sh:185-190` keeps passing). README's `## Schema migrations` per R7, with the P3 entry dated 2026-09-27.
- [ ] **Step 4: Run** the test, `bash tests/governance/test_stack_packs.sh`, `bash tests/governance/test_security_review.sh` (the `## Tools run` digests and the `--pack` provenance path), `test_suppressions.sh`, `test_suppression_expiry.sh`, `bash scripts/check-suppressions.sh`, `python3 scripts/lib/specflow/floor.py check-review docs/security/0.0.1-demo-review.md --root .`, `bash tests/governance/test_cvss4.sh`, and the gates — green.
- [ ] **Step 5: Commit** — "docs(security): the demo and tauri skeleton security docs in the block schema (CVSS v4.0 vectors, schema-migration rule), RUBRIC expiry_horizon_days, carried findings re-listed (REQ-332, REQ-322)"

---

### Task 7: The wrapper — `check-security-disposition.sh`, gate section 7 (REQ-322)

**Files:** create `scripts/check-security-disposition.sh`, `scripts/lib/specflow/disposition_gate.py`, `tests/governance/test_security_disposition_gate.sh`; modify `scripts/run-quality-gates.sh` (section 7 after section 6), `tests/governance/test_gate_sections.sh` (checks above `finish`).

**Interfaces:** `check-security-disposition.sh`; R11, R12, R13. Section 7: `# 7. Release gates (REQ-322, REQ-324)` / `SECTION "Release gates"`, running `bash scripts/check-security-disposition.sh` (PASS/SKIP lines printed; exit ≠ 0 → `FAIL scripts/check-security-disposition.sh` and `gate_fail`).

- [ ] **Step 1: Write the failing tests** — `tests/governance/test_security_disposition_gate.sh`:

```bash
#!/usr/bin/env bash
# REQ-322 (ADR-002's wrapper): scripts/check-security-disposition.sh resolves the version (--version; ship/<version>; else
# each untagged version a changed docs/security/ or docs/releases/ file names; else a SKIP), never re-evaluates a tagged
# version, reads medium_cap and expiry_horizon_days from RUBRIC.md at the base ref, fails any commit that removes an id
# from any review or disposition, tagged or not (id_removed, read with the one parser), reads a tagged prior version
# from its tag, reduces prior dispositions to the latest entry per id, and maps decide(): 0 PASS, 1 FAIL naming id and
# rule, 2 parser error. Synthetic repositories cloned from one seed under mktemp; a fixed --run-date; no network.
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CSD="$ROOT/scripts/check-security-disposition.sh"
ck "scripts/check-security-disposition.sh exists and is executable" test -x "$CSD"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
read -r VH VM VL < <(python3 - "$ROOT/tests/governance/fixtures/cvss4/vectors.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))["vectors"]
print(*(next(c["vector"] for c in v if c["severity"] == s) for s in ("high", "medium", "low")))
PY
)
hdr() { printf -- '---\nschema: specflow-security/1\nkind: %s\nversion: %s\n---\n\n# %s\n\n' "$1" "$2" "$1"; }
docs() {  # docs VERSION "id|severity|vector|status|expiry|carried_from"… — writes the version's review and disposition
  local v="$1" s i sv vec st ex cf; shift
  { hdr review "$v"; for s in "$@"; do IFS='|' read -r i sv vec st ex cf <<<"$s"
      printf -- '---\nid: %s\nseverity: %s\ncvss_vector: %s\ncite: [CWE-20]\naffects: [src/a.py:1]\n' "$i" "$sv" "$vec"
      [ -z "$cf" ] || printf 'carried_from: %s\n' "$cf"; printf -- '---\n\nbody\n\n'; done; } > "$R/docs/security/$v-review.md"
  { hdr disposition "$v"; for s in "$@"; do IFS='|' read -r i sv vec st ex cf <<<"$s"
      printf -- '---\nid: %s\nstatus: %s\nowner: alice\n' "$i" "$st"; [ -z "$ex" ] || printf 'expiry: %s\n' "$ex"
      printf 'rationale: "fixture rationale text"\n---\n\n'; done; } > "$R/docs/security/$v-disposition.md"
}
SEED="$W/seed"; mkdir -p "$SEED/docs/security"; cp -R "$ROOT/scripts" "$SEED/scripts"   # one copy of scripts/ per test
bt=$(printf '\140\140\140')   # a fence, spelled so this plan's own fence survives
printf '# Rubric\n\n%syaml\nmedium_cap: 1\nexpiry_horizon_days: 90\n%s\n' "$bt" "$bt" > "$SEED/docs/security/RUBRIC.md"
(cd "$SEED" && git init -q -b main && git add -A && git commit -qm base)
n=0
mkrepo() {  # a clone of the seed (main: scripts/ and a rubric with cap 1, horizon 90) with its own bare origin; HEAD on ship/1.0.0
  n=$((n + 1)); R="$W/r$n"; git clone -q --bare "$SEED" "$R.git"; git clone -q "$R.git" "$R"
  (cd "$R" && git checkout -qb ship/1.0.0)
}
mkprior() {  # main also carries 0.9.0 (SEC-001: an accepted medium whose expiry has passed), tagged v0.9.0; HEAD on ship/1.1.0
  mkrepo; (cd "$R" && git checkout -q main); docs 0.9.0 "SEC-001|medium|$VM|accepted|2026-09-01|"; commit 0.9.0
  (cd "$R" && git tag v0.9.0 && git push -q origin main && git checkout -qb ship/1.1.0)
}
commit() { (cd "$R" && git add -A && git commit -qm "$1"); }
csd() { rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_BASE_REF=origin/main \
  bash scripts/check-security-disposition.sh --run-date 2026-09-27 "$@" 2>&1) || rc=$?; }
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-15|" "SEC-002|low|$VL|accepted||"; commit s; csd
ck "ship/1.0.0: an accepted medium inside the window and an accepted low pass" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS security-disposition 1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|high|$VH|accepted|2026-10-15|"; commit s; csd
ck "an accepted high fails, naming the id and severe_not_fixed" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 severe_not_fixed" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-15|" "SEC-002|medium|$VM|deferred|2026-10-20|"; commit s; csd
ck "two accepted/deferred mediums over the base's cap of 1 fail medium_cap" bash -c '[ "$1" = 1 ] && grep -q "medium_cap" <<<"$2"' _ "$rc" "$out"
(cd "$R" && sed -i.bak 's/^medium_cap: 1/medium_cap: 9/' docs/security/RUBRIC.md && rm docs/security/RUBRIC.md.bak); commit raise; csd
ck "…and still fail when the PR raises its own cap (the rubric is read at the base ref)" bash -c '[ "$1" = 1 ] && grep -q "medium_cap" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2027-06-01|"; commit s; csd
ck "an expiry beyond the base rubric's 90-day horizon fails expiry_window" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 expiry_window" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|high|$VM|fixed||"; commit s; csd
ck "a severity that is not the vector's band is a parser error (exit 2)" [ "$rc" = 2 ]
mkrepo; docs 1.0.0 "SEC-001|low|$VL|accepted||" "SEC-002|low|$VL|accepted||"; commit two; docs 1.0.0 "SEC-001|low|$VL|accepted||"; commit drop; csd
ck "a commit that removes a review id fails id_removed, naming it" bash -c '[ "$1" = 1 ] && grep -q "SEC-002 id_removed" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb feature/x); echo x > "$R/a.txt"; commit x; csd
ck "a branch whose diff names no versioned security or release doc prints a SKIP" bash -c '[ "$1" = 0 ] && grep -q "^SKIP security-disposition" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb feature/y); docs 1.0.0 "SEC-001|high|$VH|open||"; commit s; csd
ck "on another branch a changed docs/security/1.0.0-* file names the version evaluated" \
  bash -c '[ "$1" = 1 ] && grep -q "1.0.0 SEC-001 severe_not_fixed" <<<"$2"' _ "$rc" "$out"
(cd "$R" && git tag v1.0.0); csd
ck "a tagged version is never re-evaluated (a SKIP naming the tag)" bash -c '[ "$1" = 0 ] && grep -q "tagged v1.0.0" <<<"$2"' _ "$rc" "$out"
mkprior; docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit 1.1.0; csd
ck "a prior medium (0.9.0, expired) missing from 1.1.0 fails carry_forward" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
docs 1.1.0 "SEC-001|medium|$VM|fixed||0.9.0" "SEC-002|low|$VL|accepted||"; commit carry; csd
ck "…re-listed with carried_from: 0.9.0 and fixed, it passes" [ "$rc" = 0 ]
docs 1.1.0 "SEC-001|low|$VL|accepted|2026-10-15|0.9.0" "SEC-002|low|$VL|accepted||"; commit down; csd
ck "…re-listed at low without reclassified_by, it fails carry_forward (the downgrade path)" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
mkprior; docs 0.9.0; docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit "drop SEC-001 from the released 0.9.0"; csd
ck "deleting a finding from a tagged prior version's review and disposition fails id_removed, and the tag still carries it forward" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-001 id_removed" <<<"$2" && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
mkprior; hdr disposition 0.9.0 > "$R/docs/security/0.9.0-disposition.md"; docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit "drop the entry only"; csd
ck "deleting only the prior disposition entry fails id_removed" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 id_removed" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|low|$VL|accepted||" "SEC-002|low|$VL|accepted||"
(cd "$R/docs/security" && sed -i.bak 's/^id: SEC-002$/id: "SEC-002"/' 1.0.0-review.md 1.0.0-disposition.md && rm -f ./*.bak); commit quoted
docs 1.0.0 "SEC-001|low|$VL|accepted||"; commit drop; csd
ck "a quoted id (id: \"SEC-002\") removed later fails id_removed (the walk reads ids with the one parser)" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-002 id_removed" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -q main); docs 0.9.0 "SEC-001|medium|$VM|fixed||"; hdr disposition 0.9.0 > "$R/docs/security/0.9.0-disposition.md"
commit 0.9.0; (cd "$R" && git push -q origin main && git checkout -qb ship/1.1.0); docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit 1.1.0; csd
ck "a prior version's review id with no entry in its disposition is a parser error (exit 2) naming it" \
  bash -c '[ "$1" = 2 ] && grep -q "SEC-001" <<<"$2"' _ "$rc" "$out"
if ! instance; then
  ck "the tauri pack's migrated skeleton passes (--root, --no-git, the template's rubric, run date 2026-09-27)" \
    bash "$CSD" --root "$ROOT/stacks/tauri/overlay" --version 0.0.0-skeleton --no-git --rubric "$ROOT/docs/security/RUBRIC.md" --run-date 2026-09-27
  rc=0; out=$(bash "$CSD" --root "$ROOT/stacks/tauri/overlay" --version 0.0.0-skeleton --no-git --run-date 2026-09-27 2>&1) || rc=$?
  ck "no RUBRIC.md anywhere and no --rubric is exit 2 (a missing rubric is never a default, R13)" \
    bash -c '[ "$1" = 2 ] && grep -q "RUBRIC.md" <<<"$2"' _ "$rc" "$out"
fi
ck "the wrapper calls the kernel and the parser" bash -c 'grep -q "disposition" "$1" && grep -qE "^(import|from) (blocks|disposition)" "$2"' _ "$CSD" "$ROOT/scripts/lib/specflow/disposition_gate.py"
finish test_security_disposition_gate
```

Append to `tests/governance/test_gate_sections.sh`, above `finish`:

```bash
# REQ-322: section 7, Release gates, runs the disposition wrapper as a gate.
# Covers: REQ-322
r=$(sec "Release gates")
ck "run-quality-gates.sh has section 7, Release gates" bash -c 'grep -qE "^# 7\. Release gates" "$1"' _ "$G"
ck "Release gates runs scripts/check-security-disposition.sh with gate_fail" bash -c 'grep -qF "scripts/check-security-disposition.sh" <<<"$1" && grep -q gate_fail <<<"$1"' _ "$r"
```

- [ ] **Step 2: Run** both tests. Expected: every wrapper case FAILs (the script does not exist: `rc` 127); the section-7 checks FAIL. Exit 1.
- [ ] **Step 3: Implement (intent).** `disposition_gate.py` per Interfaces: resolution, base ref, rubric, parse, priors, carried_from, walk, then `disposition.decide`; one output grammar. The shell wrapper resolves `--root`, then `exec python3`. Add section 7.
- [ ] **Step 4: Run** both tests (`time bash tests/governance/test_security_disposition_gate.sh`: record it; a seed clone per case keeps it near 10 s), then `bash scripts/check-security-disposition.sh` on this branch (expect `SKIP security-disposition 0.0.1-demo: tagged v0.0.1-demo …` once Task 6's files differ from `origin/main`, and no `id_removed`: Task 6's migration removes no id), and `time` the gates — green, under 2:50, else stop and report.
- [ ] **Step 5: Commit** — "feat(security): check-security-disposition.sh — version resolution, tagged versions skipped, base-ref rubric, ids only added, latest prior entry per id; gate section 7 (REQ-322)"

---

### Task 8: `verify-release.sh` becomes the PR-time release gate (REQ-324)

**Files:** rewrite `scripts/verify-release.sh`; create `scripts/lib/specflow/release_gate.py`, `tests/governance/test_verify_release.sh`; modify `scripts/run-quality-gates.sh` (section 7 also runs `bash scripts/verify-release.sh`), `tests/governance/test_gate_sections.sh` (a check above `finish`).

**Interfaces:** `verify-release.sh`; R13, R14.

- [ ] **Step 1: Write the failing tests** — `tests/governance/test_verify_release.sh`:

```bash
#!/usr/bin/env bash
# REQ-324: scripts/verify-release.sh is a PR-time gate that run-quality-gates.sh runs (section 7) for each version whose
# docs/releases/<v>-notes.md differs from the base (SPECFLOW_BASE_REF, default origin/main): the three release docs exist,
# v<version> is not yet tagged, the notes' ## Artifacts rows equal dist/manifest.json row for row when it is present (else
# every row has the file | sha256 | size shape), known-limitations names every accepted or deferred SEC id,
# check-security-disposition.sh passes, and every [verifiable*] REQ of every live spec is claimed by a plan on the base ref
# and carries a // Proves: header. Under SPECFLOW_QG_RUNNING it never re-runs the gates. The tagged demo is not evaluated.
# Covers: REQ-324
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
SHA=$(printf x | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
VL=$(python3 -c 'import json, sys; print(next(c["vector"] for c in json.load(open(sys.argv[1]))["vectors"] if c["severity"] == "low"))' \
  "$ROOT/tests/governance/fixtures/cvss4/vectors.json")
hdr() { printf -- '---\nschema: specflow-security/1\nkind: %s\nversion: 1.0.0\n---\n\n# %s\n\n' "$1" "$1"; }
SEED="$W/seed"; mkdir -p "$SEED/docs/specs" "$SEED/docs/plans" "$SEED/docs/security" "$SEED/verification/x"
cp -R "$ROOT/scripts" "$SEED/scripts"   # one copy of scripts/ per test
printf -- '---\ntype: spec\nstatus: accepted\n---\n- **REQ-900:** k. [verifiable-model]\n' > "$SEED/docs/specs/2099-01-01-x-design.md"
printf -- '---\ntype: plan\nspec: 2099-01-01-x\nimplements: [REQ-900]\n---\n' > "$SEED/docs/plans/2099-01-01-x-plan.md"
printf -- '// Proves: REQ-900\nlemma L() ensures true {}\n' > "$SEED/verification/x/k.dfy"
bt=$(printf '\140\140\140')
printf '%syaml\nmedium_cap: 5\nexpiry_horizon_days: 180\n%s\n' "$bt" "$bt" > "$SEED/docs/security/RUBRIC.md"
(cd "$SEED" && git init -q -b main && git add -A && git commit -qm base)
n=0
mkrepo() {  # a clone of the seed (main: scripts/, a spec with one [verifiable-model] REQ, a plan claiming it, its proof, a
  # rubric) with its own bare origin; HEAD on ship/1.0.0 with complete 1.0.0 security and release docs, committed
  n=$((n + 1)); R="$W/r$n"; git clone -q --bare "$SEED" "$R.git"; git clone -q "$R.git" "$R"
  (cd "$R" && git checkout -qb ship/1.0.0); mkdir -p "$R/docs/releases"
  hdr review > "$R/docs/security/1.0.0-review.md"; hdr disposition > "$R/docs/security/1.0.0-disposition.md"
  printf '# Notes\n\n## Artifacts\n\n| Filename | SHA-256 | Size (bytes) |\n|---|---|---|\n| `x-1.0.0.tar.gz` | `%s` | 1 |\n' "$SHA" \
    > "$R/docs/releases/1.0.0-notes.md"
  echo '# Migration' > "$R/docs/releases/1.0.0-migration.md"; echo '# Known limitations' > "$R/docs/releases/1.0.0-known-limitations.md"
  (cd "$R" && git add -A && git commit -qm "release docs (REQ-324)")
}
vr() { rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_QG_RUNNING=1 SPECFLOW_BASE_REF=origin/main \
  bash scripts/verify-release.sh "$@" 2>&1) || rc=$?; }
mkrepo; vr
ck "complete 1.0.0 release docs pass" bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
ck "under SPECFLOW_QG_RUNNING it does not re-run the gates" grep -qF 'not re-running the gates' <<<"$out"
mkrepo; rm "$R/docs/releases/1.0.0-migration.md"; vr
ck "a missing migration doc fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "1.0.0-migration.md" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git reset -q HEAD~1); vr
ck "untracked release docs (not yet added) differ from the base: evaluated, not skipped" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git tag v1.0.0); vr
ck "notes changed for an already tagged v1.0.0 fail (the tag must not exist yet)" bash -c '[ "$1" = 1 ] && grep -q "v1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; printf '# Notes\n' > "$R/docs/releases/1.0.0-notes.md"; vr
ck "notes without an Artifacts table fail, saying so" bash -c '[ "$1" = 1 ] && grep -q "Artifacts" <<<"$2"' _ "$rc" "$out"
mkrepo; mkdir -p "$R/dist"; printf x > "$R/dist/x-1.0.0.tar.gz"
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$R/dist/manifest.json"; vr
ck "with dist/manifest.json present, rows equal to the manifest pass" [ "$rc" = 0 ]
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}, {"filename": "y.whl", "sha256": "%s", "size": 2}]}\n' \
  "$SHA" "$SHA" > "$R/dist/manifest.json"; vr
ck "…a manifest row the notes do not transcribe fails" bash -c '[ "$1" = 1 ] && grep -q "y.whl" <<<"$2"' _ "$rc" "$out"
printf '{"version": "1.0.0", "artifacts": [{"file": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$R/dist/manifest.json"; vr
ck "…an entry without filename (the key every release hook writes) fails, naming the key" \
  bash -c '[ "$1" = 1 ] && grep -q "filename" <<<"$2"' _ "$rc" "$out"
if [ -f "$ROOT/scripts/release-stack.sh.template" ]; then   # the hook contract every stack's release.sh follows
mkrepo; rm -f "$R/docs/releases/1.0.0-notes.md"; (cd "$R" && VERSION=1.0.0 DIST_DIR="$R/dist" bash scripts/release-stack.sh.template >/dev/null)
python3 - "$R" <<'PY'   # transcribe the hook's real manifest into the notes, as /release does before verify-release
import json, sys
r = sys.argv[1]; m = json.load(open(f"{r}/dist/manifest.json"))
rows = "".join(f"| `{a['filename']}` | `{a['sha256']}` | {a['size']} |\n" for a in m["artifacts"])
open(f"{r}/docs/releases/1.0.0-notes.md", "w").write("# Notes\n\n## Artifacts\n\n| Filename | SHA-256 | Size (bytes) |\n|---|---|---|\n" + rows)
PY
vr; ck "a manifest written by the release-hook template ({filename, sha256, size}), transcribed, passes" [ "$rc" = 0 ]
fi
mkrepo
printf -- '---\nid: SEC-001\nseverity: low\ncvss_vector: %s\ncite: [CWE-20]\naffects: [a:1]\n---\n\nbody\n' "$VL" >> "$R/docs/security/1.0.0-review.md"
printf -- '---\nid: SEC-001\nstatus: accepted\nowner: alice\nrationale: "fixture rationale text"\n---\n' >> "$R/docs/security/1.0.0-disposition.md"; vr
ck "known-limitations missing an accepted SEC id fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "SEC-001" <<<"$2"' _ "$rc" "$out"
echo '- SEC-001: accepted low' >> "$R/docs/releases/1.0.0-known-limitations.md"; vr
ck "…naming it passes" [ "$rc" = 0 ]
sed -i.bak 's/^status: accepted/status: open/' "$R/docs/security/1.0.0-disposition.md"; rm "$R/docs/security/1.0.0-disposition.md.bak"
printf -- '---\nid: SEC-002\nseverity: low\ncvss_vector: %s\ncite: [CWE-20]\naffects: [a:1]\n---\n' "$VL" >> "$R/docs/security/1.0.0-review.md"; vr
ck "a disposition that fails check-security-disposition.sh fails verify-release, naming it" \
  bash -c '[ "$1" != 0 ] && grep -q "security-disposition" <<<"$2"' _ "$rc" "$out"
mkrepo; printf -- '- **REQ-901:** k2. [verifiable-model]\n' >> "$R/docs/specs/2099-01-01-x-design.md"; vr
ck "a [verifiable*] REQ no merged plan claims fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "REQ-901" <<<"$2"' _ "$rc" "$out"
mkrepo; rm "$R/verification/x/k.dfy"; vr
ck "a claimed [verifiable*] REQ without a // Proves: header fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb feature/z main); echo z > "$R/z.txt"; (cd "$R" && git add -A && git commit -qm z); vr
ck "no release notes differ from the base: a SKIP" bash -c '[ "$1" = 0 ] && grep -q "^SKIP verify-release" <<<"$2"' _ "$rc" "$out"
ck "the gates' Release gates section runs verify-release.sh" \
  bash -c 'awk "/SECTION \"Release gates\"/{f=1} /SECTION \"Summary\"/{f=0} f" "$1" | grep -qF "scripts/verify-release.sh"' _ "$ROOT/scripts/run-quality-gates.sh"
finish test_verify_release
```

- [ ] **Step 2: Run** `bash tests/governance/test_verify_release.sh`. Expected: the first case FAILs (today's script asserts the tag exists and runs the gates), and so do the untracked-docs, manifest-row, `filename`, hook-template, known-limitations, claim and proof cases, the SKIP case (today it requires a version argument) and the section check. The missing-migration, no-Artifacts and disposition cases grep their FAIL text, so today's exit 1 on a missing argument does not pass them. Exit 1.
- [ ] **Step 3: Implement (intent).** `release_gate.py` per Interfaces (plans at the base through `git ls-tree` and `git show` into `frontmatter.parse_text`; specs and proofs from the working tree; the manifest's `filename` key; the disposition through `blocks`); `verify-release.sh` keeps a positional version for compatibility, then the gates run per R14. Add it to section 7 after the disposition wrapper.
- [ ] **Step 4: Run** the test (`time` it: record), `bash tests/governance/test_gate_sections.sh`, then `SPECFLOW_QG_RUNNING=1 bash scripts/verify-release.sh` in this worktree (expect the SKIP: no notes differ from `origin/main`), and `time` the gates — green, under 2:50, else stop and report.
- [ ] **Step 5: Commit** — "feat(release): verify-release.sh is the PR-time release gate — three docs, no tag yet, manifest rows, known-limitations, the disposition gate, claimed and proved [verifiable*] REQs (REQ-324)"

---

### Task 9: `/security-review` and `/release` call the gates; the PR template names them (REQ-324, REQ-322)

**Files:** modify `.claude/commands/security-review.md` (`:15-23`, `:33-46`, `:48-55`), `.claude/commands/release.md` (remove Step 0 `:11-17`; step 7 `:33` becomes "run verify-release"; new "After the PR merges" section; Gate list `:37-44` replaced by a pointer), `.github/PULL_REQUEST_TEMPLATE.md:24,26`; create `tests/governance/test_release_commands.sh`.

**Interfaces (content the test pins):**
- `/security-review`: step 1's finding block is the schema's (with `cvss_vector:` required, `severity:` "the vector's band — RUBRIC.md", `carried_from:` for a re-listed prior finding); step 2's entry block adds `reclassified_by:`; both point at `schemas/security-disposition-template.md`; a new step before "Before opening the PR": re-list every latest prior entry of medium or above that is open, accepted or deferred (ADR-002 rule 4); "Before opening the PR" adds `bash scripts/check-security-disposition.sh --version $ARGUMENTS`; the Gate section says the gate is that script (ADR-002 rules 1–5, with the cap and horizon read from RUBRIC.md at the base). Keeps `inherited:`, `suppresses:`, "never reuse", the floor steps.
- `/release`: no Step 0; steps 1–3 as today (the three docs); step 4 is today's step 5 (the stack hook through `config.py`, and the `dist/manifest.json` check); step 5 is today's step 6 (transcribe the manifest into the notes' `## Artifacts`); today's step 4 (run the gates) is gone, because step 6 runs them: `bash scripts/verify-release.sh --version $ARGUMENTS` — the PR-time gate (REQ-324), which runs `run-quality-gates.sh` last — so no gates run sees the notes before their `## Artifacts` table exists (R14); if no signing key is configured, record the annotated fallback in known-limitations before step 6; step 7: push and open the PR; "After the PR merges": check out `main`, pull, `git tag -s v$ARGUMENTS -m "Release v$ARGUMENTS"` on the merge commit (or `git tag -a` with the recorded fallback), `git tag -v`, push the tag — an interim step that P6's `/release --tag` (REQ-383) replaces. The old "Gate (per …)" list is replaced by one line naming `verify-release.sh`.
- PR template: **SECURITY** — "`bash scripts/check-security-disposition.sh --version <version>` passes (ADR-002: no open critical/high, mediums within `medium_cap` with owner and expiry, carry-forwards re-listed)"; **RELEASE** — "`bash scripts/verify-release.sh --version <version>` passes (three docs, the tag does not exist yet, manifest rows, known-limitations, the disposition gate); the signed tag is created after the merge".

- [ ] **Step 1: Write the failing test** — `tests/governance/test_release_commands.sh`:

```bash
#!/usr/bin/env bash
# REQ-324 / REQ-322: /release invokes verify-release.sh instead of restating the gate and tags only after the ship PR
# merges (the PR-time gate requires that v<version> does not yet exist); /security-review writes the block schema
# (cvss_vector, carried_from, reclassified_by) and runs check-security-disposition.sh before the PR; the PR template's
# SECURITY and RELEASE lines name both gates.
# Covers: REQ-324
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
RL="$ROOT/.claude/commands/release.md"; SR="$ROOT/.claude/commands/security-review.md"; PT="$ROOT/.github/PULL_REQUEST_TEMPLATE.md"
ck "/release runs verify-release.sh for the version" grep -qF 'bash scripts/verify-release.sh --version $ARGUMENTS' "$RL"
ck "/release creates no preliminary tag (Step 0 is gone)" no grep -qiE 'preliminary|sequential-PR-chain' "$RL"
ck "/release tags only after the PR merges" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read()
i = t.index("After the PR merges"); assert "git tag -s" not in t[:i] and "git tag -s" in t[i:]
PY
ck "/release no longer restates the gate" no grep -qF 'Gate (per `art-release-readiness`)' "$RL"
ck "/release runs the hook and transcribes the manifest before verify-release.sh, and runs no gates before them" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read()
hook, art, vr = t.index("config.py"), t.index("## Artifacts"), t.index("bash scripts/verify-release.sh --version")
assert hook < art < vr, (hook, art, vr)
assert "run-quality-gates.sh" not in t[:vr], "a gates run before the transcription fails verify-release's Artifacts check"
PY
ck "/release still resolves the stack through config.py" grep -qF 'lib/specflow/config.py' "$RL"
for w in 'schemas/security-disposition-template.md' 'cvss_vector:' 'carried_from:' 'reclassified_by:' \
         'bash scripts/check-security-disposition.sh --version $ARGUMENTS' 'inherited:' 'suppresses:'; do
  ck "/security-review states '$w'" grep -qF -- "$w" "$SR"
done
ck "/security-review no longer lets severity be chosen apart from the vector" no grep -qF 'severity: critical | high | medium | low   # by CVSS v4.0 base' "$SR"
ck "the PR template's SECURITY line names check-security-disposition.sh" bash -c 'grep "^\*\*SECURITY\*\*" "$1" | grep -qF "check-security-disposition.sh"' _ "$PT"
ck "the PR template's RELEASE line names verify-release.sh's PR-time contract" \
  bash -c 'l=$(grep "^\*\*RELEASE\*\*" "$1"); grep -qF "verify-release.sh" <<<"$l" && grep -qi "does not exist yet" <<<"$l"' _ "$PT"
finish test_release_commands
```

- [ ] **Step 2: Run** `bash tests/governance/test_release_commands.sh`. Expected: every check FAILs except "still resolves the stack through config.py", `inherited:` and `suppresses:` (the ordering check FAILs: no `verify-release.sh --version` step, and step 4 runs the gates). Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. `test_config.sh:48`, `test_stack_packs.sh:383` and `test_security_review.sh:178-183` stay green.
- [ ] **Step 4: Run** the test, those three tests, `bash tests/governance/test_plan_template.sh` (the PR template keeps "implementation as intent" and `implements:`), and the gates — green.
- [ ] **Step 5: Commit** — "docs(commands): /security-review writes the block schema and runs check-security-disposition.sh; /release runs verify-release.sh and tags after the merge; PR template (REQ-324, REQ-322)"

---

### Task 10: Test-first per commit — `check-test-first.sh`, `packinfo.py`, the template's own rules, the `ci.yml` step (REQ-321)

**Files:** create `scripts/check-test-first.sh`, `scripts/lib/specflow/packinfo.py`, `scripts/template-pack.yml`, `tests/governance/test_check_test_first.sh`; modify `stacks/{python,tauri,flutter}/pack.yml` (`test_first_rules:` after `test_globs:`), `.github/workflows/ci.yml` (two steps before "Run quality gates"), `scripts/init-project.sh` (next to `:544`: `rm -f scripts/template-pack.yml`).

**Interfaces:** `packinfo.py`, `check-test-first.sh`; R15.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_check_test_first.sh`:

```bash
#!/usr/bin/env bash
# REQ-321: scripts/check-test-first.sh walks git rev-list --reverse --no-merges <base>..<head> and fails when a commit
# adds or changes a source file (under the pack's source_roots, not matching its test_globs) with no matching test change
# (the pack's test_first_rules) in that commit or an earlier listed one — for Rust a #[cfg(test)] hunk in the same .rs
# file also counts — or when neither a listed commit message nor the PR body cites a REQ-NNN. It errors (exit 2), never
# passes, when a source root matches no tracked file; with no PR range (a push to main) it prints a loud SKIP. A test
# change counts only when it adds a line that is neither blank nor a comment. The template source checks its own PRs
# with scripts/template-pack.yml (fixtures and lib/ are never the test side; lockfiles, non-instruction Markdown and
# uses: pin bumps are not source). Synthetic repositories under mktemp; no network.
# Covers: REQ-321
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
TF="$ROOT/scripts/check-test-first.sh"
ck "scripts/check-test-first.sh exists and is executable" test -x "$TF"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
n=0
repo() {  # repo python|tauri|template — a repository with that pack and one base commit
  n=$((n + 1)); R="$W/$1$n"; mkdir -p "$R/.specflow"; : > "$R/.specflow.yml"
  if [ "$1" = template ]; then   # the template source: no .specflow.yml, stacks/ present, scripts/template-pack.yml
    rm -rf "$R/.specflow" "$R/.specflow.yml"; mkdir -p "$R/scripts" "$R/stacks/x" "$R/.claude/commands" "$R/.github/workflows" "$R/src" \
      "$R/tests/governance/fixtures" "$R/tests/governance/lib"
    cp "$ROOT/scripts/template-pack.yml" "$R/scripts/"; echo 'echo a' > "$R/scripts/a.sh"; echo 'pip==1.0' > "$R/scripts/requirements.txt"
    echo 'x: 1' > "$R/stacks/x/pack.yml"; echo '# c' > "$R/.claude/commands/c.md"; : > "$R/src/__init__.py"
    printf 'jobs:\n  g:\n    steps:\n      - uses: actions/checkout@%s # v4.0.0\n      - run: echo hi\n' "$(printf 'a%.0s' $(seq 40))" > "$R/.github/workflows/ci.yml"
    echo '# PR template' > "$R/.github/PULL_REQUEST_TEMPLATE.md"
    printf '#!/usr/bin/env bash\necho ok\n' > "$R/tests/governance/test_a.sh"; echo '{}' > "$R/tests/governance/fixtures/f.json"
    echo 'ck() { :; }' > "$R/tests/governance/lib/check.sh"
  elif [ "$1" = python ]; then
    printf 'stack: python\nsource_roots: [src]\ntest_globs: [tests/**/test_*.py]\ntest_first_rules: ["src/** -> tests/**/test_*.py"]\n' > "$R/.specflow/pack.yml"
    mkdir -p "$R/src/app" "$R/tests"; : > "$R/src/app/__init__.py"; echo 'X = 1' > "$R/src/app/m.py"; echo 'def test_x(): pass' > "$R/tests/test_m.py"
  else
    printf '%s\n' 'stack: tauri' 'source_roots: [src, src-tauri/src]' 'test_globs: [src/**/*.test.ts, src-tauri/tests/**]' \
      'test_first_rules: ["src/**/*.ts -> src/**/*.test.ts", "src-tauri/src/**/*.rs -> src-tauri/tests/** | cfg-test"]' > "$R/.specflow/pack.yml"
    mkdir -p "$R/src/lib" "$R/src-tauri/src"; echo 'export const a = 1;' > "$R/src/lib/a.ts"
    printf 'pub fn g() -> u8 { 1 }\n\n#[cfg(test)]\nmod tests {\n    use super::*;\n    #[test]\n    fn t() { assert_eq!(g(), 1); }\n}\n' > "$R/src-tauri/src/c.rs"
  fi
  (cd "$R" && git init -q -b main && git add -A && git commit -qm "base (REQ-100)"); BASE=$(git -C "$R" rev-parse HEAD)
}
c() { (cd "$R" && eval "$1" && git add -A && git commit -qm "$2"); }   # c SNIPPET MESSAGE
tf() { rc=0; out=$(cd "$R" && env -u SPECFLOW_BASE_REF bash "$TF" --base "$BASE" "$@" 2>&1) || rc=$?; }
repo python; c 'echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "a source change with no test in this or an earlier commit fails, naming the commit and the file" \
  bash -c '[ "$1" = 1 ] && grep -q "$(git -C "$3" rev-parse --short HEAD)" <<<"$2" && grep -q "src/app/m.py" <<<"$2"' _ "$rc" "$out" "$R"
repo python; c 'echo "def test_y(): pass" >> tests/test_m.py' "test: y (REQ-101)"; c 'echo "Y = 2" >> src/app/m.py' "feat: y"; tf
ck "a test in an earlier listed commit passes" [ "$rc" = 0 ]
repo python; c 'echo "def test_y(): pass" >> tests/test_m.py; echo "Y = 2" >> src/app/m.py' "feat: y with its test (REQ-101)"; tf
ck "a test in the same commit passes" [ "$rc" = 0 ]
repo python; c 'echo "def test_y(): pass" >> tests/test_m.py; echo "Y = 2" >> src/app/m.py' "feat: y"; tf
ck "no REQ-NNN in any commit message and no PR body fails" bash -c '[ "$1" = 1 ] && grep -q "REQ-NNN" <<<"$2"' _ "$rc" "$out"
printf 'Implements REQ-101.\n' > "$W/body.md"; tf --pr-body-file "$W/body.md"
ck "…a REQ-NNN in the PR body passes" [ "$rc" = 0 ]
repo python; c 'git rm -q src/app/m.py' "chore: remove m (REQ-101)"; tf
ck "deleting a source file needs no test (the root still matches __init__.py)" [ "$rc" = 0 ]
repo python; c 'echo notes > README.md' "docs (REQ-101)"; tf
ck "a PR touching no source file prints a SKIP and passes" bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first: the PR touches no source file" <<<"$2"' _ "$rc" "$out"
repo python; c 'echo "# a note" >> tests/test_m.py' "test: comment (REQ-101)"; c 'echo "Y = 2" >> src/app/m.py' "feat: y"; tf
ck "a comment-only test edit does not satisfy a later source change (R15)" bash -c '[ "$1" = 1 ] && grep -q "src/app/m.py" <<<"$2"' _ "$rc" "$out"
repo python; c 'printf "\n\n" >> tests/test_m.py; echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "a whitespace-only test edit in the same commit does not satisfy it either" [ "$rc" = 1 ]
repo template; c 'echo "pip==1.1" > scripts/requirements.txt' "Bump pip from 1.0 to 1.1"; tf
ck "template: a Dependabot-style lockfile bump (no test, no REQ) is not a source change: SKIP" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first: the PR touches no source file" <<<"$2"' _ "$rc" "$out"
repo template; c "sed -i.bak 's/checkout@a*/checkout@$(printf 'b%.0s' $(seq 40))/; s/v4.0.0/v4.1.0/' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak" "Bump actions/checkout"; tf
ck "template: a uses: pin bump is not a source change: SKIP" bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first" <<<"$2"' _ "$rc" "$out"
repo template; c "sed -i.bak 's/echo hi/echo bye/' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak" "ci: bye (REQ-101)"; tf
ck "template: any other workflow change needs a governance test" bash -c '[ "$1" = 1 ] && grep -q ".github/workflows/ci.yml" <<<"$2"' _ "$rc" "$out"
repo template; c 'echo "# PR template, reworded" > .github/PULL_REQUEST_TEMPLATE.md' "docs: PR template"; tf
ck "template: non-instruction Markdown under .github/ is not source: SKIP" [ "$rc" = 0 ]
repo template; c 'echo "# reworded" > .claude/commands/c.md' "docs: command (REQ-101)"; tf
ck "template: model-instruction Markdown (.claude/) is source and needs a governance test" [ "$rc" = 1 ]
repo template; c 'echo "{\"a\": 1}" > tests/governance/fixtures/f.json; echo "echo b" >> scripts/a.sh' "feat: b (REQ-101)"; tf
ck "template: a fixture change alone is not a test change for scripts/" [ "$rc" = 1 ]
repo template; c 'echo "echo checked" >> tests/governance/test_a.sh; echo "echo b" >> scripts/a.sh' "feat: b (REQ-101)"; tf
ck "template: a governance test line in the same commit passes" [ "$rc" = 0 ]
repo tauri; c 'echo "export const b = 2;" >> src/lib/a.ts' "feat b (REQ-101)"; tf
ck "tauri: a .ts change with no .test.ts fails" [ "$rc" = 1 ]
repo tauri; c 'mkdir -p src-tauri/tests && echo "#[test] fn i() {}" > src-tauri/tests/i.rs' "test (REQ-101)"; c 'echo "export const b = 2;" >> src/lib/a.ts' "feat b"; tf
ck "tauri: a Rust test does not match a TypeScript change (rules are per source glob)" [ "$rc" = 1 ]
repo tauri; c 'python3 - <<"PY"
p = "src-tauri/src/c.rs"; t = open(p).read()
t = t.replace("pub fn g() -> u8 { 1 }", "pub fn g() -> u8 { 1 }\npub fn h() -> u8 { 2 }")
t = t.replace("fn t() { assert_eq!(g(), 1); }", "fn t() { assert_eq!(g(), 1); }\n    #[test]\n    fn u() { assert_eq!(h(), 2); }")
open(p, "w").write(t)
PY' "feat h (REQ-101)"; tf
ck "tauri: a .rs change with a #[cfg(test)] hunk in the same file passes" [ "$rc" = 0 ]
repo tauri; c 'printf "\npub fn h() -> u8 { 2 }\n" >> src-tauri/src/c.rs' "feat h (REQ-101)"; tf
ck "tauri: a .rs change outside any #[cfg(test)] module, with no test, fails" [ "$rc" = 1 ]
repo python; c 'git rm -rq src' "drop src (REQ-101)"; tf
ck "a source root that matches no tracked file is an error (exit 2) naming it" bash -c '[ "$1" = 2 ] && grep -q "src" <<<"$2"' _ "$rc" "$out"
repo python; rc=0; out=$(cd "$R" && env -u SPECFLOW_BASE_REF bash "$TF" 2>&1) || rc=$?
ck "no --base and no SPECFLOW_BASE_REF (a push to main): a loud SKIP, exit 0" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first: no PR range" <<<"$2"' _ "$rc" "$out"
ck "the template's pack file names its roots, globs and rules" \
  bash -c 'for k in source_roots test_globs test_first_rules; do grep -q "^$k:" "$1" || exit 1; done; grep -qF "scripts/** ->" "$1"' _ "$ROOT/scripts/template-pack.yml"
ck "this repository's source roots all match tracked files (the template checks itself)" \
  bash -c 'cd "$1" && bash scripts/check-test-first.sh --base HEAD --head HEAD' _ "$ROOT"
if ! instance; then
  for s in python tauri flutter; do ck "stacks/$s/pack.yml declares test_first_rules" grep -q '^test_first_rules: \[' "$ROOT/stacks/$s/pack.yml"; done
  ck "init removes scripts/template-pack.yml from an instance" grep -qF 'rm -f scripts/template-pack.yml' "$ROOT/scripts/init-project.sh"
fi
CI="$ROOT/.github/workflows/ci.yml"
ck "ci.yml runs check-test-first.sh on pull_request with the PR's base and head SHAs and body file" \
  grep -qF 'bash scripts/check-test-first.sh --base "$BASE_SHA" --head "$HEAD_SHA" --pr-body-file "$RUNNER_TEMP/pr-body.md"' "$CI"
ck "ci.yml passes the PR body and SHAs through env, never inside a run: script" python3 - "$CI" <<'PY'
import sys; t = open(sys.argv[1]).read(); o = "{" * 2
for k, e in (("PR_BODY", "body"), ("BASE_SHA", "base.sha"), ("HEAD_SHA", "head.sha")):
    assert f"{k}: ${o} github.event.pull_request.{e} }}}}" in t, k
for block in t.split("\n      - ")[1:]:
    if "run:" in block:
        assert "github.event.pull_request" not in block.split("run:", 1)[1], block[:80]
PY
finish test_check_test_first
```

- [ ] **Step 2: Run** `bash tests/governance/test_check_test_first.sh`. Expected: the existence check FAILs and every case FAILs with `rc` 127 (the template cases also because `scripts/template-pack.yml` does not exist yet: `cp` fails the helper); the pack, init and `ci.yml` checks FAIL. Exit 1.
- [ ] **Step 3: Implement (intent).** `packinfo.py` and `check-test-first.sh` (a thin wrapper over a `python3` heredoc or a `testfirst` function in `packinfo.py`'s sibling — keep the rules in one place) per Interfaces; the three packs' `test_first_rules` and `scripts/template-pack.yml` (with `non_source:`) per R15; the comment-only rule and the pin-bump rule per R15; the two `ci.yml` steps per Interfaces (the push step's `if:` is `github.event_name != 'pull_request'`). `actionlint .github/workflows/*.yml` clean.
- [ ] **Step 4: Run** the test (`time` it: record), `bash tests/governance/test_stack_packs.sh`, `actionlint .github/workflows/*.yml`, `bash scripts/check-test-first.sh --base phase/plan-factory-v3-2-p3` on this branch (expect PASS over Tasks 1–10), and `time` the gates — green, under 2:50, else stop and report.
- [ ] **Step 5: Commit** — "feat(gates): check-test-first.sh — per-commit test-first over the PR's commits with per-pack rules and the template's own, run by ci.yml on pull_request (REQ-321)"

---

### Task 11: Coverage floor, python — `coverage.sh`, section 1 with `--cov`, pytest-cov hash-pinned, `coverage_min` and `coverage_exclude` from the base ref (REQ-325)

**Network at implement time:** about 2 minutes (pip-tools 7.6.1 into a throwaway venv and `pip-compile`; `uv pip compile`; pip-audit on both lockfiles). The test is offline.

**Files:** create `scripts/lib/specflow/coverage.sh`, `tests/governance/test_coverage_floor.sh`; modify `scripts/run-quality-gates.sh` (resolve and export `SPECFLOW_COVERAGE_MIN` before section 1; section 1 through `pytest_cov` when R16's python condition holds), `.github/workflows/ci.yml` ("Run quality gates" env), `scripts/requirements.in`, `scripts/requirements.txt`, `stacks/python/skeleton/requirements.in`, `stacks/python/skeleton/requirements.txt`, `stacks/python/pack.yml` (`pytest_cov_version`), `tests/governance/test_python_lockfiles.sh` and `tests/governance/test_stack_packs.sh:30-33` (the tool loops gain pytest-cov).

**Interfaces:** `coverage.sh`; R13, R16. `attestation.py` and `test_attestation.sh` are not touched (R16: the base `coverage_min` is read by `coverage.sh` through `git show` and `config.py`). `scripts/requirements.in` gains `pytest-cov>=7.1,<8` with a comment naming REQ-325; regenerate from inside `scripts/` with `python3 -m venv "$TMPDIR/venv-p3" && "$TMPDIR/venv-p3/bin/pip" install pip-tools==7.6.1`, then `"$TMPDIR/venv-p3/bin/pip-compile" --allow-unsafe --generate-hashes --strip-extras --output-file=requirements.txt requirements.in` (existing pins are kept). The skeleton's `requirements.in` gains the same range; regenerate with `UV_CACHE_DIR="$TMPDIR/uv-cache" uv pip compile --generate-hashes --universal --python-version 3.12 requirements.in -o requirements.txt`. `pack.yml` `pytest_cov_version` equals the resolved pin (7.1.0 on 2026-09-27).

- [ ] **Step 1: Write the failing tests** — `tests/governance/test_coverage_floor.sh`:

```bash
#!/usr/bin/env bash
# REQ-325: coverage_min (default 80) is a per-toolchain line threshold. Python: the core gates run pytest with --cov=src
# --cov-fail-under=$MIN and always its own --cov-config (scripts/lib/specflow/coverage.sh), pytest-cov hash-pinned in
# both lockfiles; CI also reads coverage_min at the base ref (git show + config.py, never attestation.py's policy) and
# applies the higher value, and refuses a coverage_exclude entry the base does not have, so a PR can neither lower its
# own floor (P2's deferral) nor widen its exclusions; a repository coverage config (omit, exclude_lines) is never read.
# Covers: REQ-325
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CV="$ROOT/scripts/lib/specflow/coverage.sh"; CFG="$ROOT/scripts/lib/specflow/config.py"
ck "scripts/lib/specflow/coverage.sh exists" test -f "$CV"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
py() {  # py DIR full|part — a src/ package with two functions; the test calls both, or one
  mkdir -p "$1/src/m" "$1/tests"; : > "$1/src/__init__.py"; : > "$1/src/m/__init__.py"
  printf 'def a():\n    return 1\n\n\ndef b():\n    x = 2\n    y = x + 1\n    return y\n' > "$1/src/m/core.py"
  if [ "$2" = full ]; then printf 'from src.m.core import a, b\n\n\ndef test_ab():\n    assert a() == 1 and b() == 3\n' > "$1/tests/test_core.py"
  else printf 'from src.m.core import a\n\n\ndef test_a():\n    assert a() == 1\n' > "$1/tests/test_core.py"; fi
}
py "$W/full" full; py "$W/part" part
run_cov() { rc=0; out=$(cd "$1" && bash -c 'source "$1"; pytest_cov "$2"' _ "$CV" "$2" 2>&1) || rc=$?; }
run_cov "$W/full" 80; ck "a fully covered src/ passes coverage_min 80" [ "$rc" = 0 ]
run_cov "$W/part" 80; ck "src/ at 50% fails coverage_min 80, saying so" bash -c '[ "$1" != 0 ] && grep -q "80" <<<"$2"' _ "$rc" "$out"
run_cov "$W/part" 40; ck "…and passes coverage_min 40" [ "$rc" = 0 ]
ck "a coverage run leaves no .coverage file in the tree" [ ! -e "$W/full/.coverage" -a ! -e "$W/part/.coverage" ]
printf '[run]\nomit = src/m/core.py\n[report]\nexclude_lines =\n    .*\n' > "$W/part/.coveragerc"
printf '[tool.coverage.report]\nexclude_lines = [".*"]\n' > "$W/part/pyproject.toml"; cp "$W/part/.coveragerc" "$W/part/setup.cfg"
run_cov "$W/part" 80
ck "a repository .coveragerc, setup.cfg or pyproject.toml omit/exclude_lines is ignored (own --cov-config): still fails 80" [ "$rc" != 0 ]
rm -f "$W/part/.coveragerc" "$W/part/setup.cfg" "$W/part/pyproject.toml"
G="$W/g"; mkdir -p "$G"
(cd "$G" && git init -q -b main && printf 'coverage_min: 90\n' > .specflow.yml && git add -A && git commit -qm base \
   && git checkout -qb pr && printf 'coverage_min: 50\n' > .specflow.yml && git commit -qam lower)
res() { (cd "$G" && env -u SPECFLOW_COVERAGE_MIN SPECFLOW_BASE_REF="$1" bash -c 'source "$1"; coverage_min_resolve' _ "$CV" 2>&1); }
ck "CI: when the PR lowers coverage_min, the base's value governs (90, not 50)" grep -q '^90 ' <<<"$(res main)"
(cd "$G" && printf 'coverage_min: 95\n' > .specflow.yml && git commit -qam raise)
ck "a PR may raise its own floor (95)" grep -q '^95 ' <<<"$(res main)"
ck "locally (no SPECFLOW_BASE_REF) the working tree's value applies" grep -q '^95 ' <<<"$(res '')"
ck "coverage.sh reads the base value itself (git show + config.py), never through attestation.py's policy" \
  bash -c 'grep -qF "git show" "$1" && ! grep -qF "attestation.py" "$1"' _ "$CV"
ck "attestation.py policy is unchanged: solo, profile and path only (the verifier's classifier calls it)" \
  no grep -qF 'coverage_min' "$ROOT/scripts/lib/specflow/attestation.py"
mkdir -p "$G/.specflow"; (cd "$G" && git checkout -q main && printf 'coverage_exclude: []\n' > .specflow/pack.yml && git add -A \
   && git commit -qm pack && git checkout -q pr && git merge -q main -m m && printf 'coverage_exclude: [src/m/core.py]\n' > .specflow/pack.yml \
   && git commit -qam widen)
rc=0; out=$(cd "$G" && SPECFLOW_BASE_REF=main bash -c 'source "$1"; pack_coverage_exclude' _ "$CV" 2>&1) || rc=$?
ck "a coverage_exclude entry the base does not have fails, naming it" bash -c '[ "$1" != 0 ] && grep -q "coverage_exclude gains src/m/core.py" <<<"$2"' _ "$rc" "$out"
Q="$ROOT/scripts/run-quality-gates.sh"
ck "the gates source coverage.sh, export SPECFLOW_COVERAGE_MIN and run pytest through pytest_cov" \
  bash -c 'grep -q "lib/specflow/coverage.sh" "$1" && grep -q "export SPECFLOW_COVERAGE_MIN" "$1" && grep -q "pytest_cov" "$1"' _ "$Q"
ck "ci.yml passes the base ref to the gates" grep -qF 'SPECFLOW_BASE_REF' "$ROOT/.github/workflows/ci.yml"
ck "coverage.sh reads coverage_exclude from the pack (never a literal list)" grep -qF 'getlist coverage_exclude' "$CV"
if ! instance; then
  ck "the python pack's coverage_exclude is []" [ -z "$(python3 "$CFG" --file "$ROOT/stacks/python/pack.yml" getlist coverage_exclude)" ]
  for f in scripts/requirements.in stacks/python/skeleton/requirements.in; do ck "$f lists pytest-cov as a range" grep -qE '^pytest-cov[<>=!~ ]' "$ROOT/$f"; done
  for f in scripts/requirements.txt stacks/python/skeleton/requirements.txt; do
    ck "$f pins pytest-cov with a hash" python3 - "$ROOT/$f" <<'PY'
import re, sys
t = open(sys.argv[1]).read().replace("\\\n", " ")
assert re.search(r"^pytest-cov==[\w.]+ .*--hash=sha256:[0-9a-f]{64}", t, re.M)
PY
  done
  ck "pack.yml pytest_cov_version equals the skeleton lockfile's pin" \
    bash -c 'v=$(python3 "$1" --file "$2" get pytest_cov_version); grep -q "^pytest-cov==$v " "$3"' _ "$CFG" "$ROOT/stacks/python/pack.yml" "$ROOT/stacks/python/skeleton/requirements.txt"
fi
finish test_coverage_floor
```

- [ ] **Step 2: Run** `bash tests/governance/test_coverage_floor.sh`. Expected: `coverage.sh exists` and every functional case FAIL (the file cannot be sourced), including the repository-config and widened-exclusion cases, the `git show` check, the gates, ci.yml, lockfile and pin checks FAIL; the python `coverage_exclude` check and the "`attestation.py policy` is unchanged" check pass (they guard). Exit 1.
- [ ] **Step 3: Implement (intent).** Per Files and Interfaces; compile both lockfiles per Interfaces; then (network, about 5 seconds) `pip-audit -r scripts/requirements.txt --strict --disable-pip` and the same for the skeleton's lockfile — both exit 0; record the times. Re-run the gates venv's `pip install`. Measure the python first-run case's coverage figure in Task 16.
- [ ] **Step 4: Run** the test (`time` it: record), `bash tests/governance/test_attestation.sh` (unchanged, green), `bash tests/governance/test_python_lockfiles.sh`, `bash tests/governance/test_stack_packs.sh`, `actionlint .github/workflows/*.yml`, and `time` the gates from the venv — green, under 2:50, else stop and report; section 1 prints `coverage_min 80 (…)` and pytest-cov's total for `src/` (100%).
- [ ] **Step 5: Commit** — "feat(gates): coverage_min for python — pytest --cov=src --cov-fail-under with its own --cov-config in the core gates, pytest-cov hash-pinned, coverage_min and coverage_exclude read from the base ref as well (REQ-325)"

---

### Task 12: Coverage floor, app stacks — vitest thresholds, cargo llvm-cov, flutter lcov (REQ-325)

**Opt-in at implement time (macOS):** `rustup component add llvm-tools --toolchain 1.93.1` (the one host change; report it), `cargo install --locked --version 0.9.1 --root "$TMPDIR/cargo-tools" cargo-llvm-cov` (about 3–5 minutes cold), then `PATH="$TMPDIR/cargo-tools/bin:$PATH" SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="tauri flutter" bash tests/governance/test_first_run.sh` (about 20 minutes for tauri with the instrumented build and 10 for flutter). The test itself uses stub toolchains.

**Files:** create `stacks/flutter/lcov-threshold.sh`; modify `stacks/tauri/gates.sh:20-32`, `stacks/flutter/gates.sh:20-25`, `stacks/tauri/overlay/vitest.config.ts` (drop the "No coverage threshold yet (P3)" comment; lists unchanged), `stacks/tauri/overlay/rust-toolchain.toml` (`components = ["llvm-tools"]`), `stacks/tauri/pack.yml` (`cargo_llvm_cov_version: 0.9.1`; `prereqs` gains `cargo_llvm_cov` and `llvm_tools` with `check_`/`install_macos_`/`install_linux_` lines like `:39-41`), `stacks/tauri/action.yml` (input `cargo_llvm_cov_version`, a cache step and a cache-miss install like `:58-67`, and `--component llvm-tools` on the toolchain install), `scripts/init-project.sh` (copy the pack's `lcov-threshold.sh` to `scripts/lcov-threshold.sh`, executable, when present), `tests/governance/test_coverage_floor.sh` (checks above `finish`), `tests/governance/test_stack_packs.sh:154` (the tauri gates word list: `cargo llvm-cov` for `cargo test --locked`).

**Interfaces:** R16; `lcov-threshold.sh`. `MIN` in each hook is `${SPECFLOW_COVERAGE_MIN:-$(source scripts/lib/specflow/coverage.sh; coverage_min_resolve | cut -d' ' -f1)}`; exclusions come from `pack_coverage_exclude`. The cargo regex joins `re.escape` of each `.rs` entry as `(^|/)<entry>$` with `|`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/governance/test_coverage_floor.sh`, above `finish`:

```bash
# REQ-325, app stacks: tauri runs vitest with --coverage.thresholds.lines=$MIN and cargo llvm-cov --fail-under-lines $MIN;
# flutter runs flutter test --coverage then the pack's lcov-threshold.sh; every exclusion list equals pack.yml's
# coverage_exclude. Stub toolchains record argv (no Rust, Node or Flutter needed).
if ! instance; then
  T="$ROOT/stacks/tauri"; F="$ROOT/stacks/flutter"
  ck "tauri pins cargo-llvm-cov and lists it and llvm-tools as prerequisites" \
    bash -c 'grep -q "^cargo_llvm_cov_version: " "$1" && grep -qE "^prereqs: .*cargo_llvm_cov" "$1" && grep -qE "^prereqs: .*llvm_tools" "$1" \
      && grep -q "^install_macos_cargo_llvm_cov: cargo install cargo-llvm-cov --locked --version" "$1"' _ "$T/pack.yml"
  ck "the tauri action installs cargo-llvm-cov at the pack's version, and llvm-tools" \
    bash -c 'v=$(sed -n "s/^cargo_llvm_cov_version: //p" "$2"); grep -qF "default: \"$v\"" "$1" && grep -qF "cargo install cargo-llvm-cov --locked" "$1" && grep -qF "llvm-tools" "$1"' _ "$T/action.yml" "$T/pack.yml"
  ck "the tauri overlay's rust-toolchain.toml asks for llvm-tools" grep -qF 'llvm-tools' "$T/overlay/rust-toolchain.toml"
  ck "vitest.config.ts excludes exactly pack.yml's TypeScript coverage_exclude entries (plus the tests)" \
    python3 - "$T/overlay/vitest.config.ts" "$T/pack.yml" "$CFG" <<'PY'
import re, subprocess, sys
cfg = open(sys.argv[1]).read()
got = {x.strip().strip('"') for x in re.search(r"exclude:\s*\[([^\]]*)\]", cfg).group(1).split(",") if x.strip()}
pack = subprocess.run([sys.executable, sys.argv[3], "--file", sys.argv[2], "getlist", "coverage_exclude"],
                      capture_output=True, text=True, check=True).stdout.split()
assert got == {p for p in pack if p.endswith(".ts")} | {"src/**/*.test.ts"}, got
PY
  stub() {  # stub DIR TOOL [SNIPPET] — records argv to DIR/TOOL.argv, runs SNIPPET, exits 0
    cat > "$1/bin/$2" <<EOF
#!/usr/bin/env bash
{ printf '%s\n' "\$@"; echo ---; } >> "$1/$2.argv"
${3:-:}
exit 0
EOF
    chmod +x "$1/bin/$2"; }
  inst() {  # inst DIR PACK — an instance-shaped directory with the pack's pack.yml and the coverage helpers
    mkdir -p "$1/bin" "$1/inst/.specflow" "$1/inst/scripts/lib/specflow" "$1/inst/src-tauri"
    cp "$2" "$1/inst/.specflow/pack.yml"; cp "$CFG" "$CV" "$1/inst/scripts/lib/specflow/"; }
  S="$W/tauri"; inst "$S" "$T/pack.yml"; for t in npm npx cargo; do stub "$S" "$t"; done
  rc=0; (cd "$S/inst" && PATH="$S/bin:$PATH" SPECFLOW_COVERAGE_MIN=80 bash "$T/gates.sh") >/dev/null 2>&1 || rc=$?
  ck "tauri gates.sh passes against stub toolchains" [ "$rc" = 0 ]
  ck "tauri: vitest runs with --coverage and --coverage.thresholds.lines=80" \
    bash -c 'tr "\n" " " < "$1" | grep -qF "vitest run --coverage --coverage.thresholds.lines=80"' _ "$S/npx.argv"
  ck "tauri: cargo llvm-cov --locked --fail-under-lines 80 replaces cargo test" \
    bash -c 'tr "\n" " " < "$1" | grep -qF "llvm-cov --locked --fail-under-lines 80" && ! grep -qx test "$1"' _ "$S/cargo.argv"
  ck "tauri: the llvm-cov ignore regex comes from pack.yml (main.rs and lib.rs out, commands.rs in)" python3 - "$S/cargo.argv" <<'PY'
import re, sys
a = open(sys.argv[1]).read().split("\n"); rx = re.compile(a[a.index("--ignore-filename-regex") + 1])
assert rx.search("/x/src-tauri/src/main.rs") and rx.search("/x/src-tauri/src/lib.rs"), rx.pattern
assert not rx.search("/x/src-tauri/src/commands.rs"), rx.pattern
PY
  LC="$F/lcov-threshold.sh"
  lc() { rc=0; out=$(bash "$LC" "$@" 2>&1) || rc=$?; }
  printf 'SF:lib/app.dart\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,0\nend_of_record\nSF:lib/main.dart\nDA:1,0\nDA:2,0\nend_of_record\n' > "$W/lcov.info"
  lc "$W/lcov.info" 80; ck "lcov-threshold.sh: 3 of 6 lines is below 80" [ "$rc" = 1 ]
  lc "$W/lcov.info" 70 --exclude lib/main.dart; ck "…excluding lib/main.dart, 3 of 4 lines (75%) clears 70" [ "$rc" = 0 ]
  lc "$W/lcov.info" 80 --exclude lib/main.dart; ck "…and misses 80, printing 75" bash -c '[ "$1" = 1 ] && grep -q "75" <<<"$2"' _ "$rc" "$out"
  lc "$W/none.info" 80; ck "a missing lcov file is an error (exit 2), never a pass" [ "$rc" = 2 ]
  : > "$W/empty.info"; lc "$W/empty.info" 80; ck "an lcov file with no records is an error (exit 2)" [ "$rc" = 2 ]
  S2="$W/flutter"; inst "$S2" "$F/pack.yml"; cp "$LC" "$S2/inst/scripts/lcov-threshold.sh"; stub "$S2" dart
  stub "$S2" flutter 'if [ "$*" = "test --coverage" ]; then mkdir -p coverage; printf "SF:lib/app.dart\nDA:1,1\nend_of_record\nSF:lib/main.dart\nDA:1,0\nend_of_record\n" > coverage/lcov.info; fi'
  rc=0; (cd "$S2/inst" && PATH="$S2/bin:$PATH" SPECFLOW_COVERAGE_MIN=80 bash "$F/gates.sh") >/dev/null 2>&1 || rc=$?
  ck "flutter gates.sh runs flutter test --coverage and excludes pack.yml's lib/main.dart (1 of 1 line: passes 80)" \
    bash -c '[ "$1" = 0 ] && grep -qx -e --coverage "$2"' _ "$rc" "$S2/flutter.argv"
  ck "init copies the flutter pack's lcov-threshold.sh into scripts/" grep -qF 'lcov-threshold.sh' "$ROOT/scripts/init-project.sh"
fi
```

- [ ] **Step 2: Run** `bash tests/governance/test_coverage_floor.sh`. Expected: the new pack, action, toolchain and `vitest.config.ts` checks FAIL except the `vitest.config.ts` equality (the lists already match); the tauri stub run fails its argv checks (`vitest run` without `--coverage`; `cargo test --locked`); the lcov checks FAIL (no script); the flutter run and init checks FAIL. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Files and Interfaces. Then the opt-in run (above): record, per stack, the TypeScript, Rust and Dart line coverage the gates print, the tauri and flutter wall-clocks, and the cold `cargo install` time. A figure under 80 means the skeleton does not clear the floor: add the missing skeleton test (test-first) in this task rather than lowering anything.
- [ ] **Step 4: Run** the test, `bash tests/governance/test_stack_packs.sh`, `bash tests/governance/test_action_pins.sh`, `actionlint .github/workflows/*.yml`, and the gates — green.
- [ ] **Step 5: Commit** — "feat(packs): coverage_min for tauri (vitest thresholds, cargo llvm-cov) and flutter (lcov-threshold.sh); exclusions from pack.yml coverage_exclude (REQ-325)"

---

### Task 13: `check-covers.sh` goes live — the repository self-check, section 6, `test_traceability.sh` delegates; REQ-327 and REQ-380 cited where they are exercised (REQ-323, REQ-306, REQ-394)

**Files:** create `scripts/check-covers.sh`, `tests/governance/test_check_covers.sh`; modify `scripts/run-quality-gates.sh` (section 6 also runs `scripts/check-covers.sh`), `tests/governance/test_traceability.sh:37-76` (check 3 becomes `bash scripts/check-covers.sh`), `tests/governance/test_gate_sections.sh` (a check above `finish`), and add Covers lines: `tests/governance/test_traceability_scoping.sh` (`# Covers: REQ-327` and `# Covers: REQ-380` after its header comment; style otherwise unchanged), `tests/governance/test_plan_template.sh` and `tests/governance/test_analyze_adr_plan_linkage.sh` (`# Covers: REQ-380`) — each exercises the REQ it now cites (H5).

**Interfaces:** `check-covers.sh`, the Covers grammar; R18.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_check_covers.sh`:

```bash
#!/usr/bin/env bash
# REQ-323 / REQ-306 / REQ-394: scripts/check-covers.sh fails when a REQ some plan claims (implements:, read through
# frontmatter.py; a plan without implements: walks its spec whole) has no test citing it on a whole '# Covers:' or
# '// Covers:' line under the pack's test_globs or tests/governance/ (fixtures excluded), reporting each uncovered id; a
# Covers line outside tests/governance/ citing a REQ no live spec defines also fails (the interim check test_traceability.sh
# carried until P3, which now delegates here). This repository passes it on its own plans.
# Covers: REQ-323
# Covers: REQ-306
# Covers: REQ-394
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CC="$ROOT/scripts/check-covers.sh"
ck "scripts/check-covers.sh exists and is executable" test -x "$CC"
ck "this repository passes check-covers.sh (every claimed REQ has a test)" bash "$CC"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mk() {  # an instance-shaped fixture: a python pack, one spec, one plan claiming REQ-901 and REQ-902, both cited
  A="$W/a"; rm -rf "$A"; mkdir -p "$A/docs/specs" "$A/docs/plans" "$A/.specflow" "$A/tests/unit" "$A/tests/governance/fixtures"
  : > "$A/.specflow.yml"; printf 'stack: python\nsource_roots: [src]\ntest_globs: [tests/**/test_*.py]\n' > "$A/.specflow/pack.yml"
  printf -- '---\ntype: spec\nstatus: accepted\n---\n- **REQ-901:** a.\n- **REQ-902:** b.\n- **REQ-903:** c.\n' > "$A/docs/specs/2099-01-01-x-design.md"
  printf -- '---\ntype: plan\nspec: 2099-01-01-x\nimplements: [REQ-901, REQ-902]  # two\n---\n' > "$A/docs/plans/2099-01-01-x-plan.md"
  printf '# Covers: REQ-901\ndef test_a(): pass\n' > "$A/tests/unit/test_a.py"
  printf '#!/usr/bin/env bash\n# Covers: REQ-902\n' > "$A/tests/governance/test_b.sh"
}
cc() { rc=0; out=$(COVERS_BASE_DIR="$A" bash "$CC" 2>&1) || rc=$?; }
mk; cc; ck "fixture: every claimed REQ cited (a pack test glob, a governance test) passes" [ "$rc" = 0 ]
mk; rm "$A/tests/governance/test_b.sh"; cc
ck "an uncovered claimed REQ fails, naming only it" bash -c '[ "$1" = 1 ] && grep -q "REQ-902" <<<"$2" && ! grep -q "REQ-901" <<<"$2"' _ "$rc" "$out"
mk; printf '# Covers: REQ-901, REQ-902\n' > "$A/tests/unit/test_a.py"; rm "$A/tests/governance/test_b.sh"; cc
ck "a comma list on one Covers line cites every id" [ "$rc" = 0 ]
mk; rm "$A/tests/governance/test_b.sh"; printf 'x = "# Covers: REQ-902 in a string"\n' > "$A/tests/unit/test_c.py"; cc
ck "a Covers mention inside code (not a whole comment line) cites nothing" [ "$rc" = 1 ]
mk; rm "$A/tests/governance/test_b.sh"; printf '# Covers: REQ-902\n' > "$A/tests/governance/fixtures/f.sh"; cc
ck "a Covers line in tests/governance/fixtures/ cites nothing" [ "$rc" = 1 ]
mk; rm "$A/tests/governance/test_b.sh"; printf '# Covers: REQ-902\n' > "$A/tests/unit/helper.py"; cc
ck "a Covers line outside the pack's test_globs cites nothing" [ "$rc" = 1 ]
mk; printf 'stack: tauri\nsource_roots: [src]\ntest_globs: [src/**/*.test.ts]\n' > "$A/.specflow/pack.yml"; rm "$A/tests/unit/test_a.py"
mkdir -p "$A/src/lib"; printf '// Covers: REQ-901\n' > "$A/src/lib/g.test.ts"; cc
ck "a // Covers: line under a TypeScript test glob cites" [ "$rc" = 0 ]
mk; printf -- '---\ntype: plan\nspec: 2099-01-01-x\n---\n' > "$A/docs/plans/2099-01-01-x-plan.md"; cc
ck "a plan without implements: walks its spec whole (REQ-903 uncovered)" bash -c '[ "$1" = 1 ] && grep -q "REQ-903" <<<"$2"' _ "$rc" "$out"
mk; printf '# Covers: REQ-999\n' >> "$A/tests/unit/test_a.py"; cc
ck "a Covers line outside tests/governance/ citing a REQ no live spec defines fails" bash -c '[ "$1" = 1 ] && grep -q "REQ-999" <<<"$2"' _ "$rc" "$out"
mk; printf '# Covers: REQ-999\n' >> "$A/tests/governance/test_b.sh"; cc
ck "…but not under tests/governance/ (an instance may delete the factory spec)" [ "$rc" = 0 ]
mk; rm -rf "$A/docs/specs" "$A/docs/plans"; cc
ck "no plans and no specs (every example removed, REQ-306) passes" [ "$rc" = 0 ]
ck "check-covers.sh reads plans through frontmatter.py" grep -qE '(import frontmatter|from frontmatter import)' "$CC"
ck "test_traceability.sh delegates its Covers check to check-covers.sh" grep -qF 'scripts/check-covers.sh' "$ROOT/tests/governance/test_traceability.sh"
ck "test_traceability.sh no longer carries the interim glob" no grep -qF 'Interim REQ-323 check' "$ROOT/tests/governance/test_traceability.sh"
for t in test_traceability_scoping.sh:REQ-327 test_traceability_scoping.sh:REQ-380 test_plan_template.sh:REQ-380 test_analyze_adr_plan_linkage.sh:REQ-380; do
  ck "${t%%:*} cites ${t##*:}, which it exercises" grep -qE "^# Covers: (.*, )?${t##*:}(,|$)" "$ROOT/tests/governance/${t%%:*}"
done
ck "run-quality-gates.sh's Document gates run check-covers.sh" \
  bash -c 'awk "/SECTION \"Document gates\"/{f=1} /SECTION \"Release gates\"/{f=0} f" "$1" | grep -qF "scripts/check-covers.sh"' _ "$ROOT/scripts/run-quality-gates.sh"
finish test_check_covers
```

Append to `tests/governance/test_gate_sections.sh`, above `finish`: `ck "Document gates runs scripts/check-covers.sh" grep -qF "scripts/check-covers.sh" <<<"$d"`.

- [ ] **Step 2: Run** `bash tests/governance/test_check_covers.sh`. Expected: the existence and self-check FAIL, every fixture case FAILs (`rc` 127), the delegation, the four Covers checks and the section check FAIL. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces and R18; `test_traceability.sh` check 3 calls `bash scripts/check-covers.sh` in its own hand-rolled pass/fail style. The four Covers lines per Files.
- [ ] **Step 4: Run** the test, `bash tests/governance/test_traceability.sh`, `bash tests/governance/test_gate_sections.sh`, `bash scripts/check-covers.sh` (PASS over the 36 REQs the seven plans claim), and the gates — green.
- [ ] **Step 5: Commit** — "feat(gates): check-covers.sh goes live — every claimed REQ cited by a test, gate section 6, test_traceability.sh delegates; REQ-327 and REQ-380 cited where exercised (REQ-323, REQ-306, REQ-394)"

---

### Task 14: Architecture artifacts match what shipped — the overview's P3 notes, dfe-3, the narrative, the `implements:` residual (H13; REQ-322, REQ-324, REQ-394) — architecture-artifact update

**Files:** `docs/architecture/2026-09-25-factory-v3-2-overview.md` (`:41`, `:131`, `:133`), `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` (`:103`, `:111`, `:188`, and residual bullets for REQ-321's rewritten history and what the checker proves, the open-medium loophole, and the head-read `vitest.config.ts`), `tests/governance/test_threat_model_current.sh` (checks above `finish`).

**Interfaces (content the test pins):**
- Overview `:41`: the frontmatter and list parsers were lifted in P3 into `scripts/lib/specflow/frontmatter.py`, which `check-traceability.sh`, `analyze-adr-plan-linkage.sh`, `architecture.py` and `check-covers.sh` import; `config.py` and `attestation.py` keep their own reader (R2).
- Overview `:131`: "P3 created `records.py`, `blocks.py`, `cvss4.py` (with `cvss4_data.py`, vendored from FIRST's calculator), `disposition.py`, `disposition_gate.py` and `check-security-disposition.sh`, the Dafny model `verification/factory_v3_2/disposition.dfy`, and `schemas/security-disposition-template.md`, and migrated the demo disposition and review and the tauri pack's `0.0.0-skeleton` review and disposition (P4) to it."
- Overview `:133`: P4 created `check-architecture.sh`; P3 scoped its `req_map` check to the `implements:` claims (REQ-320, REQ-394) and added `confirmed_by:` for the guided profile (REQ-389's check) — on one line with `check-architecture.sh` and `REQ-320` (the existing test greps that).
- Threat model `:103`: "P2 (…), P3 (dfe-3) and P4 (…) have shipped".
- dfe-3 row `:111`: the mitigations as shipped — severity from a required CVSS v4.0 vector (`cvss4.py`, FIRST's data; a mismatch is a parser error; a 0.0 vector is an informational low), ids only added over the PR's commits in every review and disposition, tagged or not (`id_removed`), a tagged prior version read from its tag, carried findings re-listed with `carried_from`, latest prior entry per id by semver, `medium_cap` and `expiry_horizon_days` from `RUBRIC.md` at the base ref (`SPECFLOW_BASE_REF`), tagged versions never re-evaluated as current, `check-security-disposition.sh`; and the residual: a medium left `open` is outside rules 3 and 5 (no cap, owner or expiry) and can be carried open indefinitely (ADR-002 rule 3; `RUBRIC.md` tells reviewers to look for it). Boundary and Threats cells unchanged.
- Residual `:188`: "`verify-release.sh` asserts it at ship time from the plans on the base ref (REQ-324 as amended); a tagged REQ nobody claims still owes no proof before a ship PR."
- New residual bullets: `check-test-first.sh` reads the commits as pushed; a squash or force-push before review rewrites what it sees; and it proves only that a test file gained a real (non-blank, non-comment) line in the same or an earlier commit, not that the test exercises the change — code mode's second pass is the control for that (REQ-321). A current medium left `status: open` passes rules 2–5 without owner, expiry or a place under `medium_cap`, and carry-forward accepts it open again (REQ-322, ADR-002 rule 3). Tauri's `vitest.config.ts` include and exclude lists are read from the PR head, so a PR can narrow what TypeScript coverage measures; code mode reviews an edit to it (REQ-325).

- [ ] **Step 1: Write the failing test.** Append to `tests/governance/test_threat_model_current.sh`, above `finish`:

```bash
# P3 (REQ-322, REQ-324, REQ-394, REQ-321): the architecture artifacts say what P3 shipped.
# Covers: REQ-322
# Covers: REQ-324
# Covers: REQ-394
r3=$(row dfe-3)
for w in 'check-security-disposition.sh' 'SPECFLOW_BASE_REF' 'carried_from' 'id_removed' 'cvss4.py'; do ck "dfe-3 states '$w'" grep -qF "$w" <<<"$r3"; done
ck "the narrative lists P3 among the shipped plans" grep -qF 'P3 (dfe-3)' "$TM"
ck "the implements: residual names verify-release.sh's ship-time check, not 'until P3'" \
  bash -c '! grep -qF "until P3 this is convention" "$1" && grep -qF "verify-release.sh" "$1"' _ "$TM"
ck "a residual records that check-test-first.sh reads the commits as pushed (REQ-321)" \
  bash -c 'awk "/^## Residual risks/{f=1} f" "$1" | grep -qF "check-test-first.sh"' _ "$TM"
for w in 'not that the test exercises' 'left `status: open`' 'vitest.config.ts'; do
  ck "a residual states '$w'" bash -c 'awk "/^## Residual risks/{f=1} f" "$1" | grep -qF -- "$2"' _ "$TM" "$w"
done
ck "dfe-3 states the open-medium residual and the tag read" bash -c 'grep -qF "open" <<<"$1" && grep -qF "from its tag" <<<"$1"' _ "$r3"
ck "overview: the frontmatter parsers are lifted, not 'to be lifted'" \
  bash -c 'grep -qF "scripts/lib/specflow/frontmatter.py" "$1" && ! grep -qF "to be lifted" "$1"' _ "$OV"
ck "overview: P3 created the disposition modules and the model, as shipped" \
  bash -c 'grep -qE "P3 created .*records.py.*blocks.py.*cvss4.py.*disposition.py" "$1" && ! grep -qF "P3 creates" "$1"' _ "$OV"
ck "overview: check-architecture.sh's scoping is done (P3 scoped it, REQ-320)" \
  bash -c 'grep -qE "P3 scoped .*REQ-320" "$1" && ! grep -qF "P3 scopes it" "$1"' _ "$OV"
```

- [ ] **Step 2: Run** `bash tests/governance/test_threat_model_current.sh`. Expected: every new check FAILs. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces; element ids, frontmatter and the Domain checklist unchanged; `check-architecture.sh` stays green.
- [ ] **Step 4: Run** the test, `bash scripts/check-architecture.sh`, and the gates — green.
- [ ] **Step 5: Commit** — "docs(architecture): the overview's P3 notes, dfe-3, the narrative and the residuals match what P3 shipped (architecture-artifact update; REQ-322, REQ-324, REQ-394)"

---

### Task 15: The docs say what P3 shipped — `tdd.md`, the claim table and gate rules, the verifier skill, the glossary, `CLAUDE.md`, README (H7; REQ-321, REQ-323, REQ-325, REQ-322, REQ-324)

**Files:** `.claude/rules/tdd.md:21-24`; `.claude/rules/review-gate.md:68` (the claim row), new claim rows for the disposition gate and the release gate, `:133-134` (SECURITY and RELEASE exit gates); `.claude/skills/verifier/SKILL.md:48`; `docs/GLOSSARY.md` (`:58-68`; new `### Disposition gate` after `### Disposition`; new `### Test-first check` after `### Suppression`); `CLAUDE.md:74-85`; `README.md:123-130`, `:203`; `docs/specs/2026-09-25-factory-v3-2-design.md` (frontmatter `amended:` gains one entry; no REQ body changes); `tests/governance/test_onboarding_surface.sh` (checks above `finish`).

**Interfaces (content the tests pin):**
- `tdd.md`: test-first per commit is checked by `scripts/check-test-first.sh` (REQ-321) in `ci.yml`'s `gates` job on every PR that changes a source root (the pack's `source_roots`; in the template source, `scripts/template-pack.yml`); the verifier's code mode reads the same commits as a second, judgement-based pass.
- Claim row "Test-first per commit": Mechanism — `check-test-first.sh` in the `gates` job (per commit over `base..head`, per-pack rules, `#[cfg(test)]`, REQ citation from commits or the PR body); it proves only that a matching test file gained a non-blank, non-comment line in the same or an earlier commit, not that the test exercises the change — code mode's second pass remains the control for that; residuals: history rewritten before push, and that gap; Files — `scripts/check-test-first.sh`, `.github/workflows/ci.yml`, `tests/governance/test_check_test_first.sh`. New rows: "A release cannot proceed with an open critical/high, over-cap mediums, dropped carry-forwards or out-of-window expiries" → `check-security-disposition.sh` (the proved kernel), Files `scripts/check-security-disposition.sh`, `scripts/lib/specflow/disposition.py`, `verification/factory_v3_2/disposition.dfy`; "Release docs are complete before the tag" → `verify-release.sh` at PR time, Files `scripts/verify-release.sh`, `scripts/lib/specflow/release_gate.py`. Every file exists (`test_review_gate_claims.sh`).
- SECURITY exit gate: `bash scripts/check-security-disposition.sh` (ADR-002 rules 1–5). RELEASE exit gate: at PR time `verify-release.sh` (three docs, no tag yet, manifest content transcribed, known-limitations, the disposition gate); after the merge the tag is created and signed — annotated permitted only with the fallback recorded in known-limitations (the words "fallback" and "transcribed" stay, `test_spec_lifecycle.sh:53-54`); and R19's interim reading: `art-release-readiness`'s "tag missing" is judged after the merge (the ship PR must not carry the tag; a merged release without its tag is what it blocks) until amendment B (P5) aligns the constitution text.
- `SKILL.md:48`: `scripts/check-test-first.sh` (REQ-321) is the gate, run by CI; code mode reads `commits.txt` as a second pass for what the script cannot judge (a test that changed but does not exercise the changed code). Full mode, on a RELEASE-phase PR, applies R19's interim reading: "tag missing" is judged after the merge, so a ship PR without `v<version>` is correct and one carrying it fails `verify-release.sh`. Headings unchanged (`test_verifier_skill_modes.sh`).
- The spec's `amended:` gains one entry, in the P4 entry's form: "P3 IMPLEMENT PR (2026-09-27 plan): rulings of the P3 plan (docs/plans/2026-09-27-factory-v3-2-p3-plan.md) that narrow, extend or read literal REQ text, REQ bodies unchanged — " followed by R4, R6, R9, R10, R12, R14 (with check (6)'s instance skip of the inherited specs by slug), R15 and R20, each in one clause (the list in this plan's **Spec** paragraph).
- Glossary: **Coverage floor** — `coverage_min`, per toolchain (`pytest --cov=src`, `vitest` thresholds, `cargo llvm-cov`, `lcov-threshold.sh`), read at the base ref as well so a PR cannot lower it; **Covers annotation** — whole-line `# Covers:` / `// Covers:` (comma lists), checked by `check-covers.sh`; **Disposition gate** — `check-security-disposition.sh` over ADR-002's rules, severity from the CVSS v4.0 vector; **Test-first check** — `check-test-first.sh`.
- `CLAUDE.md` Project Map: `check-test-first.sh`, `check-covers.sh`, `check-security-disposition.sh`, `verify-release.sh` (the PR-time release gate), `scripts/template-pack.yml`, `scripts/lib/specflow/{frontmatter,blocks,cvss4,records,disposition}.py`, and `schemas/security-disposition-template.md`.
- README gates bullet: tests with the coverage floor, Dafny, the document gates, the release gates, and the test-first step on every PR; the `:203` row names the same sections.

- [ ] **Step 1: Write the failing tests.** Append to `tests/governance/test_onboarding_surface.sh`, above `finish`:

```bash
# P3 (REQ-321, REQ-323, REQ-325, REQ-322, REQ-324): the mechanized gates, where a user or a session reads them.
# Covers: REQ-321
# Covers: REQ-323
# Covers: REQ-325
g=docs/GLOSSARY.md
cf=$(awk '/^### Coverage floor$/{f=1; next} /^### /{f=0} f' "$g")
for w in 'pytest --cov=src' 'cargo llvm-cov' 'vitest' 'lcov-threshold.sh' 'base ref'; do ck "glossary Coverage floor: '$w'" grep -qF "$w" <<<"$cf"; done
ca=$(awk '/^### Covers annotation$/{f=1; next} /^### /{f=0} f' "$g")
ck "glossary Covers annotation: // Covers: and check-covers.sh" bash -c 'grep -qF "// Covers:" <<<"$1" && grep -qF "check-covers.sh" <<<"$1"' _ "$ca"
for h in 'Disposition gate' 'Test-first check'; do ck "glossary defines $h" grep -qx "### $h" "$g"; done
ck "tdd.md: check-test-first.sh is live, not 'a later plan'" \
  bash -c 'grep -qF "check-test-first.sh" "$1" && ! grep -qF "until then it is not" "$1" && ! grep -qF "(P3) adds" "$1"' _ .claude/rules/tdd.md
ck "verifier SKILL.md: code mode no longer 'stands in … until P3'" no grep -qF 'until P3 builds it' .claude/skills/verifier/SKILL.md
row=$(grep -F '| Test-first per commit |' .claude/rules/review-gate.md || true)
ck "review-gate.md claim row: test-first is check-test-first.sh in ci.yml, not a convention" \
  bash -c 'grep -qF "scripts/check-test-first.sh" <<<"$1" && grep -qF ".github/workflows/ci.yml" <<<"$1" && ! grep -qF "Convention until" <<<"$1"' _ "$row"
for w in 'scripts/check-security-disposition.sh' 'scripts/verify-release.sh' 'verification/factory_v3_2/disposition.dfy'; do
  ck "review-gate.md's claim table names $w" grep -qF "$w" .claude/rules/review-gate.md
done
ck "review-gate.md RELEASE exit gate: verify-release.sh at PR time, the tag after the merge" \
  bash -c 'l=$(grep -F "RELEASE exit gate" "$1"); grep -qF "verify-release.sh" <<<"$l" && grep -qi "after the merge" <<<"$l"' _ .claude/rules/review-gate.md
ck "CLAUDE.md's project map names the P3 scripts and schema" \
  bash -c 'for s in check-test-first.sh check-covers.sh check-security-disposition.sh verify-release.sh template-pack.yml security-disposition-template.md; do grep -qF "$s" CLAUDE.md || exit 1; done'
gb=$(awk '/Mechanical gates in CI/{f=1} /Verifier review, run locally/{exit} f' README.md)
for w in 'coverage' 'test-first' 'check-security-disposition.sh' 'verify-release.sh'; do ck "README gates bullet: '$w'" grep -qiF "$w" <<<"$gb"; done
ck "review-gate.md RELEASE exit gate: 'tag missing' is judged after the merge until amendment B (R19)" \
  bash -c 'l=$(grep -F "RELEASE exit gate" "$1"); grep -qF "tag missing" <<<"$l" && grep -qF "amendment B" <<<"$l"' _ .claude/rules/review-gate.md
ck "verifier SKILL.md: the interim reading of 'tag missing' for RELEASE-phase PRs" \
  bash -c 'grep -qF "tag missing" "$1" && grep -qF "judged after the merge" "$1"' _ .claude/skills/verifier/SKILL.md
ck "review-gate.md claim row: the checker proves a test changed, not that it exercises the change" grep -qF 'not that the test exercises' <<<"$row"
if [ -f docs/specs/2026-09-25-factory-v3-2-design.md ]; then   # an instance may delete the factory spec
  ck "the v3.2 spec's amended: records the P3 rulings (P4's precedent)" \
    bash -c 'awk "/^amended:/{f=1; next} /^[a-z_]+:/{f=0} f" "$1" | grep -F "P3 IMPLEMENT" | grep -qF "REQ-322"' _ docs/specs/2026-09-25-factory-v3-2-design.md
fi
```

- [ ] **Step 2: Run** `bash tests/governance/test_onboarding_surface.sh`. Expected: every new check FAILs. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. `test_review_gate_claims.sh`, `test_spec_lifecycle.sh`, `test_verifier_skill_modes.sh`, `test_verifier_skill_citations.sh` and `test_reviews_use_slugs.sh` stay green.
- [ ] **Step 4: Run** the test, those five, and the gates — green.
- [ ] **Step 5: Commit** — "docs: the mechanized gates as shipped — tdd.md, the claim table and gate rules (R19's interim reading), the verifier skill, glossary, CLAUDE.md, README, the spec's amended: entry (REQ-321, REQ-323, REQ-325, REQ-322, REQ-324)"

---

### Task 16: Whole-branch verification and the IMPLEMENT PR body

- [ ] **Step 1:**
  - `time PATH="$TMPDIR/p3-gates/bin:$PATH" bash scripts/run-quality-gates.sh` — green, under 3 minutes (about 2:30 before P3); record it and the new sections' own times.
  - `actionlint .github/workflows/*.yml` — clean.
  - `dafny verify verification/factory_v3_2/disposition.dfy` with 4.11.0 and with the pinned 4.9.1 — both verified (34 verified, 0 errors at the PLAN PR); record the counts.
  - `git grep -nE '(^|[ (])python[ ]+-m' -- scripts tests stacks` and `git grep -nF -e --jq -- scripts` — empty.
- [ ] **Step 2:** `bash scripts/verify-doc.sh docs/plans/2026-09-27-factory-v3-2-p3-plan.md` (silent), `bash scripts/analyze-adr-plan-linkage.sh`, `bash scripts/check-traceability.sh`, `bash scripts/check-architecture.sh`, `bash scripts/check-covers.sh`, `bash scripts/check-suppressions.sh`, `bash tests/governance/test_plan_template.sh` — all pass.
- [ ] **Step 3 (H18):** `bash scripts/check-test-first.sh --base phase/plan-factory-v3-2-p3 --head HEAD` — PASS over every commit of this branch; paste its output in the PR body.
- [ ] **Step 4: Opt-in runs on this Mac (record each wall-clock):**
  - `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="guided engineer profiles" bash tests/governance/test_first_run.sh` (about 4 minutes) — the python instances clear `coverage_min` 80 (record the figure; 90% measured on a scratch copy).
  - Task 12's `tauri flutter` run, if not already recorded.
  - A `SKIP: <stack> — missing …` line is recorded as "not run, why", never as green.
- [ ] **Step 5:** No real tool in the tests: `git grep -nE '^(cargo llvm-cov|flutter test|npx|node) ' -- tests/governance` shows only the opt-in paths. `git diff phase/plan-factory-v3-2-p3 --stat` touches only the files named in Tasks 1–15. `git status --porcelain` is empty. The `has-verification` label is added to the PR only if it exists (`GH_TOKEN="$(gh auth token --user kpingali123)" gh label list`); it is not created.
- [ ] **Step 6: IMPLEMENT PR body** (`--body-file "$(mktemp)"`; base `phase/plan-factory-v3-2-p3`, retargeted to `main` before that branch is deleted). It states:
  - the Partial claims and which plan relists each open clause;
  - the rulings R1–R20, including R14's move of `/release`'s tag step, R10's reading of "lows never affect rules 2–5", and the spec's new `amended:` entry (Task 15);
  - **R19's interim reading**, verbatim: `art-release-readiness`'s "tag missing" (`constitution.md:187`) is judged after the merge until amendment B (REQ-343, P5) changes the text — its control is the next ship PR's `verify-release.sh` previous-tag check plus the PR template's checkbox, and the verifier records it as a standing informational finding (R19 as implemented);
  - the inherited-artifact effects in instances (Partial claims): R4's and check (6)'s grandfathering of the inherited specs by slug, Dafny now needed locally in tauri and flutter instances, and the dangling proof below;
  - **Architecture-artifact updates:** Task 14, named as such;
  - the H1–H19 and P1–P6 disposition;
  - the CVSS provenance (commit, files, sha256s), the pinned pytest-cov and cargo-llvm-cov versions, and the host change (`rustup component add llvm-tools --toolchain 1.93.1`);
  - the measured figures: the gates before and after, each opt-in case, the coverage per stack, and the CI minutes of the first run (the `gates` job, and `app-stacks.yml` if the pack paths triggered it, cold and warm cargo-llvm-cov);
  - **what the user will see:**
    - *Every PR is now checked commit by commit* — a source change needs a test in the same or an earlier commit and some REQ cited; the check prints SKIP on a push to `main` and on a PR that changes no source file (a lockfile bump or an action pin bump included); a test change counts only when it adds a real line.
    - *The gates measure coverage* (`coverage_min`, 80 by default); a local run needs pytest-cov (`pip install --require-hashes -r scripts/requirements.txt`); a PR that lowers `coverage_min` still meets the base's value.
    - *A ship PR is blocked* until its security disposition passes ADR-002's rules and its release docs are complete; the signed tag is created after the merge ("tag missing" in the constitution is read after the merge until amendment B). A finding removed from any review or disposition, including a released one, fails the gates.
    - *Tauri and flutter instances need Dafny locally* — the inherited factory proof `verification/factory_v3_2/disposition.dfy` ships to every instance (CI already installs Dafny); P5 (F-10/W-7) removes or fences the inherited factory docs.
    - *A Dependabot lockfile or action-pin PR prints SKIP for test-first*; a comment-only test edit no longer satisfies it.
    - *Every claimed REQ needs a test* that cites it (`# Covers:`).
    - *An instance that deletes the inherited factory spec must delete its proof too* — `docs/specs/2026-09-25-factory-v3-2-design.md` removed while `verification/factory_v3_2/disposition.dfy` stays leaves a dangling `// Proves: REQ-322` that `check-traceability.sh` fails (REQ-327); delete `verification/factory_v3_2/` with the spec until P5's F-10/W-7 fence (PR #41 verifier finding 4). The next release's known-limitations should carry the same note (its `/release` author adds it).
    - *The next ship PR checks the previous release's tag*: a lightweight tag, an unsigned one without the fallback recorded in its known-limitations, or one off `main` fails; a missing one is a WARN. A BAD signature fails. In CI the runner has no signer's public key, so a signed previous tag whose signature cannot be checked there (no public key, no gpg) is a WARN, not a FAIL, until P6's tag-time check verifies it with the key (REQ-350, REQ-383).
    - *`prompt_sha256` changes on merge* (Task 15 edits the verifier skill): PRs open at that moment need their verifier run again.

---

## Review Focus

1. **Relabelling a finding** on a `ship/1.2.0` PR. Editing `severity: high` to `medium` alone is a parser error (the vector's band is high; exit 2). Editing the vector too passes the parser, so the verifier must read the metric reasoning in the finding's body. Deleting SEC-004 from both files in a later commit fails `id_removed` naming the commit (R12) — and so does deleting it, on any branch, from a released `1.0.0` review or disposition, while `ship/1.1.0` still reads 1.0.0's entries from tag `v1.0.0`. Leaving a medium `open` is the recorded residual (R12's neighbour in dfe-3): the reviewer reads it. Raising `medium_cap` in `RUBRIC.md` in the same PR changes nothing (the base's value is read) (Tasks 5, 7).
2. **A tauri instance's first release, 0.1.0,** run on 2026-12-30. The skeleton's SEC-001 (medium, accepted, expiry 2026-12-24) is omitted: `carry_forward`. It is re-listed with `carried_from: 0.0.0-skeleton` and re-accepted until 2027-03-01 by the instance's maintainer: PASS, with `check-traceability.sh` still green (R6). It is re-listed as low without `reclassified_by`: `carry_forward` (R10). SEC-002 and SEC-003 (lows) are not due. The tag `v0.0.1-demo` never makes the demo evaluated (Tasks 6, 7).
3. **`check-test-first.sh` on four PRs** (R15). A PR whose first commit changes `scripts/check-covers.sh` and whose second adds its test fails, naming commit 1. A tauri `.rs` change whose `#[cfg(test)]` module gains a test in the same commit passes, and a `.rs` change with only a `.test.ts` change fails. A PR citing no REQ in any commit passes once its body cites one. A comment-only edit to a test does not count, and a Dependabot lockfile or pin bump prints SKIP. A `push` to `main` prints SKIP (Task 10).
4. **The PLAN PR itself** (`phase/plan-factory-v3-2-p3` → `main`). Its gates are green because the proof travels with the plan (R1); `verify-dafny` does not run on a `phase/plan-*` head, and section 2 verifies the proof under Dafny 4.9.1 in CI. On the IMPLEMENT PR, the model's names, the twin's functions and the 34 fixtures line up (Task 4's greps), the boundary fixtures 13, 19, 20, 24, 25, 33 and 34 are the model's own proved `FixtureNN` verdicts, and `LowsInertForRules2to5` states R10's precondition (H1, H14).
5. **A PR that lowers `coverage_min` to 50** while tests cover 60%: the gates still fail at the base's 80, and printing `coverage_min 80 (base origin/main: 80; working tree: 50)` shows why. Adding `src/app/x.py` to `coverage_exclude`, or `exclude_lines = .*` to `pyproject.toml`, changes nothing: the base's exclusions govern and the repository's coverage config is never read. In a tauri instance, `src-tauri/src/lib.rs` is excluded because `pack.yml` says so, not because `gates.sh` does (Tasks 11, 12).
6. **`check-architecture.sh` after P3** (R3, R4). The v3.2 spec passes: REQ-322 is claimed and mapped, and REQ-341 is mapped although unclaimed. A spec amendment that tags a new REQ does not turn gates red until a plan claims it. A guided instance's new spec whose overview lacks `confirmed_by:` fails, while its demo and the inherited v3.2 artifacts (by slug, present at the base ref — a backdated `created:` grandfathers nothing) are grandfathered — a fresh guided instance passes section 6 (Task 2).

## Deferred by design

- **Open clauses of claimed REQs** are under **Partial claims**, each with the plan that relists the REQ:
  - P5 — REQ-322's `phase/security`/`phase/release` default version from `next_version`; the rest of REQ-389.
  - P6 — REQ-324's CI-built manifest (REQ-384) and tag-time re-check (REQ-350); `/release --tag` (REQ-383); `release.yml` replaying the disposition wrapper at the tag.
- **Not P3's (H19):**
  - The open mediums from P4's APPROVE run → `patch/p4-mediums` or P5: the npm lockfile rule accepting new `node_modules` entries and edited per-entry dependency maps, the bandit and npm severity thresholds, and `check-review` passing a table-less review in the template source.
  - The tauri lockfile re-pin due 2026-11-15 → the maintainer.
  - REQ-341 and `next.sh`, the second kernel with the same three-layer shape → P5.
  - The constitution → amendment B (P5) and C (P7); P3 changes no constitution text. Amendment B also aligns `art-release-readiness`'s "tag missing" with REQ-324 (R19).
- **Kernel compiled from Dafny:** rejected by ADR-002 for v3.2; the twin plus fixtures keep the two aligned.
- **A per-file test mapping for REQ-321** (a source file matched by a test of the same name): the REQ asks for "a matching test change" per rule, and a name heuristic would be both stricter than the REQ and wrong for integration tests; code mode reads the diff for it.
- **Coverage per file or per branch:** REQ-325 sets a line threshold per toolchain; branch coverage is not measured.
- **`pull_request_target`** (P2's residual: a PR edits its own workflow, including the new test-first step) is unchanged; a PR that edits `ci.yml` is gate code, which code mode flags. P6's tag-time checks run from `main`.
- **Open mediums** (PR #42 verifier finding 5, a named residual in the threat model): a medium left `status: open` is outside `medium_cap` and needs no owner or expiry, so any number can ship indefinitely. REQ-322's preconditions and ADR-002 rule 3 name accepted/deferred mediums only, so P3 changes no code. Follow-up proposal for the retrospective / P5 backlog: count open mediums toward `medium_cap`, or require an `owner:` on an open medium.
- **A deleted inherited spec's proof** (PR #41 verifier finding 4): an instance that deletes `docs/specs/2026-09-25-factory-v3-2-design.md` must also delete `verification/factory_v3_2/`, or `check-traceability.sh` fails on the dangling `// Proves: REQ-322` (REQ-327). Documented in the IMPLEMENT PR body and "What the user will see"; no code — P5's F-10/W-7 fence removes or fences the inherited factory docs.
- **An instance's later edits to inherited specs** (R4 as implemented, PR #42 fix wave 2): grandfathering is by slug at the base ref (`frontmatter.INHERITED_SPEC_SLUGS`), so an instance that edits its inherited demo or v3.2 spec, overview, threat model or ADR-002/003 after init keeps the grandfathering — `check-architecture.sh`'s `confirmed_by:` rule and `verify-release.sh` check (6) still skip those files, edited or not. The alternative (grandfather only the unedited inherited content) needs a content fingerprint the template does not ship. Recorded as an input to P5's F-10/W-7 fence, which removes or fences the inherited factory docs and can retire the slug list with them; that fence must also cover NEW content an instance adds to an inherited spec — a new `[verifiable*]` REQ, or a new ADR addressing one of its REQs — not only the unchanged inherited content, since today both escape `confirmed_by:` and `verify-release.sh` check (6) by slug (PR #42 third verifier run, finding 6).
- **A signed previous tag in CI** (R19 as implemented): `git tag -v` needs the signer's public key, which the CI runner does not hold, so on the first ship PR after a signed release the previous tag's signature is WARNed as unverifiable here, not FAILed, until P6's tag-time check verifies it with the maintainer's key (REQ-350, REQ-383) — whoever's key made the signature, so until then a signature nobody checked in CI passes the gate with a WARN.
- **An id added and removed within one PR** (PR #41 verifier finding 6): R12 compares each commit with its first parent, so an id an earlier commit of the PR added by mistake, which the base never had, still fails `id_removed` when a later commit drops it. Exempting ids absent at the base would let a ship PR delete a finding it wrote without any trace the gate sees, so the behaviour stays; `/security-review` and dfe-3 give the recovery — keep the id as `status: fixed` with a rationale saying it was raised in error, or open a new PR from a branch rebuilt on the base, linking the closed one.
- **A carried-forward downgrade re-accepted as low** (PR #41 verifier finding 7): rule 4 needs only an expiry after the run date and rule 5 covers mediums only, so its expiry has no upper bound. REQ-322 and ADR-002 set no horizon for lows; RUBRIC.md and dfe-3 say the reviewer checks that expiry.
- **History rewritten before push:** `check-test-first.sh` and the ids-only-added walk read the commits as pushed; a squash or force-push before review is recorded as a residual (Task 14), not prevented.
