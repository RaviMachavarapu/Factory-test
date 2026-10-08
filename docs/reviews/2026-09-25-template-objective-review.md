---
date: 2026-09-25
target: template repo @ main (aa35ef0), reviewed against the objective "any user inputs an idea and turns out a product that is fully tested and ready to go"
method: grounding read + three fresh-instance experiments + five parallel fresh-eyes reviewers
reviewers:
  - persona: non-technical-founder
  - persona: senior-engineer-node-adopter
  - persona: release-platform-engineer
  - persona: security-reviewer
  - persona: factory-maintainer
status: proposed
---

# Template Objective Review — 2026-09-25

**Question asked:** can a user with only an idea clone this template, run the pipeline, and get out a product that is fully tested and ready to ship?

**Answer today: no, for any user.** The pipeline's second documented step (`/speckit.specify`) does not exist in a fresh instance, every implementation PR is unmergeable under the documented branch protection, and the RELEASE command looks for a hook that `init-project.sh` never creates. Behind those three walls, "fully tested" and "ready to go" are both narrower than the docs say: CI runs the product's own tests only for Python, nothing checks coverage or test-first, no security tooling runs, and "shipped" ends at a gitignored tarball on a laptop.

The constitution and governance-test layer are genuinely careful. The gap is that the *tooling* stops well short of what the *documents* promise, and the template has only ever been run on itself.

## Evidence: what was actually run

All on a clean clone of `main` at `aa35ef0`, 2026-09-25.

| Experiment | Result |
|---|---|
| `bash scripts/run-quality-gates.sh` on the template itself | green: pytest 12 passed, Dafny 8 verified, 13/13 governance |
| Fresh instance, Python stack (`printf 'Acme\n1\n' \| bash scripts/init-project.sh`) then gates | green; but `release-python-wheel.sh` packages `demo-greeting-0.1.0.tar.gz` (the demo, not the product), and `/release` resolves `scripts/release-python.sh`, which does not exist |
| Fresh instance, Node stack, then gates | **FAIL** at the per-stack hook: `ESLint couldn't find an eslint.config.* file`; `scripts/release-node.sh` does not exist |
| Delete the demo as `README.md:15` advises, then gates | **FAIL**: `test_spec_lifecycle.sh` (empty `docs/specs/*.md` glob) and `test_traceability.sh:38` (hard-coded demo test path) |
| PR #18 (code-only chore) status checks | "Verifier findings posted": **FAILURE**, 0 verifier comments, merged anyway |
| `gh api .../branches/main/protection` | HTTP 403: private repo on free plan, branch protection unavailable |
| `ls ~/.claude/plugins`, `.specify/`, `.claude/commands/speckit.*` | SpecKit is not installed as a plugin and not scaffolded in this repo; a sibling project has `.specify/` + `speckit.*.md` written by `specify init` |

## Convergent findings (flagged by ≥2 reviewers, all reproduced)

| # | Finding | Severity vs objective | Flagged by | Evidence |
|---|---|---|---|---|
| 1 | `/speckit.specify`, `.clarify`, `.plan`, `.tasks`, `.analyze` are named in the pipeline table but do not exist in the repo; `init-project.sh` never runs `specify init`; README calls SpecKit a plugin | **blocks** (step 2 of Quick Start) | founder, engineer, maintainer | `CLAUDE.md:26-30`, `README.md:10,81`, `scripts/init-project.sh:128`; no `.specify/`, no `.claude/commands/speckit.*` |
| 2 | Code-only PRs can never pass "Verifier findings posted": `run-verifier.sh` diffs only `*.md`, exits 0 without posting when none changed; the CI check requires a comment; `configure-repo.sh` makes it required | **blocks** (every IMPLEMENT and VALIDATE PR) | engineer, release, maintainer | `scripts/run-verifier.sh:50-55`, `.github/workflows/verifier.yml:48-54`, `scripts/configure-repo.sh:26`; PR #18 |
| 3 | RELEASE step 5 resolves `scripts/release-$(cat .stack).sh`; init writes `.stack` as `python\|node\|go\|other` but generates only the quality-gate hook; the one shipped release hook is misnamed and demo-specific | **blocks** (last phase, every stack) | founder, engineer, maintainer | `.claude/commands/release.md:29`, `scripts/init-project.sh:69-86`, `scripts/release-python-wheel.sh:5` |
| 4 | CI installs Python + Dafny only; a Node or Go instance's tests never run in CI; the Node hook fails locally on a bare instance; "Other" stack (the Enter-key default) generates a hook that exits 1 by design | **blocks** for non-Python | founder, engineer, release | `.github/workflows/ci.yml:14-32`, `scripts/init-project.sh:20,41-45`; experiment B |
| 5 | Deleting the demo as README advises breaks two governance tests; `verification/example.dfy` keeps Dafny mandatory anyway | **blocks** (first PR of a fresh instance) | engineer, maintainer | `README.md:15`, `tests/governance/test_traceability.sh:38`, `tests/governance/test_spec_lifecycle.sh:17`; experiment C |
| 6 | Solo user cannot merge: one approving review required and GitHub ignores self-approval; on this free-plan private repo protection returns 403 so all gates are honor-system | **blocks** for solo, honor-system for teams | founder, release, maintainer | `scripts/configure-repo.sh:28-31`, `.claude/rules/review-gate.md:5`; 403 above |
| 7 | "Fully tested" has no machine check: no coverage floor, no test-first check, `# Covers:` verified only for the demo file, `tests/e2e/` unused, spec-template's "every contract clause maps to a named test" unparsed | **degrades** (core of the objective) | engineer, maintainer | `constitution.md:69`, `schemas/spec-template.md:46-50`, `scripts/check-traceability.sh:46-61` |
| 8 | Root `settings.json` is not read by Claude Code (project settings live in `.claude/settings.json`); its hook entries use a `pathPattern` field and `$CLAUDE_FILE_PATH` variable that do not exist. So the `.env` deny list and the spec-lint hook have never fired | **degrades** | engineer, release/security, maintainer, docs check | `settings.json:1-23`; `.claude/` contains no settings file |
| 9 | No security tooling at all (no dependency audit, SAST, secret scan, Dependabot); the "security tool floor" deferred to v3.2 lost its tracking home when the v3.1 spec was deleted in `02677f8` | **degrades** (blocks credibility of "0 findings" for any app with dependencies) | engineer, security, maintainer | `.github/` contents; `docs/reviews/2026-05-28-v3.1-demo-review.md:45`; `docs/retrospectives/` has only README |
| 10 | "Ready to go" ends at a gitignored `dist/` tarball: no publish, deploy, env config, migration execution, smoke test, rollback, or observability anywhere; no CI job verifies tag, manifest, or rebuilds the artifact | **degrades** (second half of the objective) | release, maintainer | `scripts/release-stack.sh.template:16-17`, `.gitignore:11`, `scripts/verify-release.sh:36-62` |
| 11 | `tdd.md` claims the verifier flags implementation commits without tests; the verifier skill has no such step, sees only markdown, and has no git access | **degrades** (false promise) | engineer, maintainer | `.claude/rules/tdd.md:21-22`, `.claude/skills/verifier/SKILL.md:26-33`, `scripts/run-verifier.sh:83` |
| 12 | Three constitution articles say "the verifier rejects/blocks" (kernel boundary, release readiness, slug existence); the verifier skill contains none of those instructions. Only 2 of 12 articles have real mechanical enforcement | **degrades** | maintainer (table below) | `constitution.md:106,155,192` vs `.claude/skills/verifier/SKILL.md` |
| 13 | No orchestrator: only 3 of 10 phases have an in-repo command; the user infers phase from branch names by reading two docs; the issue template promises "agents will pick up this issue" with no workflow behind it | **degrades** (the "any user" half) | founder, maintainer | `.claude/commands/`, `.github/ISSUE_TEMPLATE/idea-seed.yml:10-11` |
| 14 | Ceremony: minimum 7 branches, 7 PRs, 7 out-of-session `claude -p` runs, 7 approvals for v1 of anything; the patch tier can never apply to a v1 because v1 creates the kernel; VALIDATE is a PR with no diff | **degrades** | founder, engineer, maintainer | `.claude/rules/review-gate.md:19-27,74-86` |
| 15 | Dead tooling contradicts the no-API-key design: `render_doc.py` constructs an Anthropic client with a stale model id, `anthropic` is force-listed in requirements by a governance test and installed in every CI run, yet the only caller is the dead hook in finding 8 | **polish** | engineer, security, maintainer | `scripts/render_doc.py:11,17`, `tests/governance/test_workflow_health.sh:77`, `README.md:36` |

## Single-reviewer findings worth keeping

- **Founder:** the repo's own prior review declares non-technical founders out of scope and cites a "factory-lite" commitment that no longer exists anywhere in the tree; README has no audience statement (`docs/reviews/2026-05-28-v3.1-demo-review.md:35-37,63`). README step 1 says edit `IDEA.md`, which does not exist until init runs (`README.md:9,13`). No copy-paste install block for `gh`, SpecKit, Superpowers, Dafny. Spec filename convention `<date>-<slug>-design.md` is only inferable from the demo.
- **Engineer:** the Node hook works once `package.json` + `eslint.config.js` exist, so the fix is scaffolding, not hook design. `CLAUDE.md:16` "Testing: (configured at init time)" is never substituted. Prettier/vitest exit non-zero on empty globs.
- **Security:** `.gitignore:30` ignores every `*.lock`, defeating reproducible builds and SCA for instances. The verifier reads PR-author-controlled markdown with `Read,Grep,Glob` over the whole checkout and posts output verbatim under the maintainer's identity (prompt-injection to PR comment path; `scripts/run-verifier.sh:62-112`). Actions are tag-pinned, not SHA-pinned; `ci.yml` lacks a `permissions:` block. Secrets hygiene is gitignore plus "PR review rejects".
- **Release:** `verify-release.sh` passes on any 64-hex string in the notes, never compares against the manifest, and never checks the tag is an ancestor of `main`; the demo tag is still annotated with the promised re-tag follow-up never done.
- **Maintainer:** never-landed items with no tracking home after `02677f8`: tool floor, factory-lite/solo path, orchestration, TDD evidence, contract extraction, stacked-PR protocol, verdict waivers, `/release` calling `verify-release.sh`. The factory has only ever processed itself.

## Enforcement table (maintainer reviewer, verified)

| Article | Promised enforcement | Actual mechanism | Gap |
|---|---|---|---|
| `art-specification-primacy` | src PR must cite a REQ | PR template comment only | convention |
| `art-branch-as-state` | phase transitions are PRs | `configure-repo.sh` (opt-in, 403 on free plan) | no phase-name or ordering check |
| `art-review-gate` | verifier + human approval | grep for `specflow-verifier:` in any comment; 1 approval | spoofable; solo cannot self-approve |
| `art-test-first` | test in same/earlier commit; "verifier flags" | nothing | claim in `tdd.md` is false |
| `art-formal-verification` | `.dfy` per `[verifiable*]` REQ | `check-traceability.sh`, Dafny in gates and CI | strongest article; `[verifiable]` contracts unimplemented |
| `art-kernel-boundary` | "verifier rejects" uncovered `req_map` | nothing parses overview frontmatter | promise is false |
| `art-threat-driven-security` | crit/high fixed, medium cap, expiry | `verify-release.sh` checks SEC ids in known-limitations only | severity/cap/expiry unchecked; no tool floor |
| `art-release-readiness` | "verifier blocks" on six conditions | `verify-release.sh` covers them but is manual, not in CI or gates | exists, not wired |
| `art-repository-singleton` | no submodules | nothing | low stakes |
| `art-naming-tagging` | duplicate IDs, non-existent slugs rejected | duplicates yes; slug existence only for `review-gate.md` | partial; TASK-NNN never used |
| `art-secrets-hygiene` | gitignore + review | gitignore; deny list in dead `settings.json` | no scan |
| `art-retrospective-cadence` | retro per release, decisions recorded | command exists; retros deleted, 5 proposals undecided | loop broke on second use |

## What checked out

- Local gates are green on the template and on a fresh Python instance; Dafny is correctly recursive and SHA-pinned in CI.
- The demo document chain (brainstorm → spec → ADR → overview → threat model → plan → code → test → proof → empty review → release docs with manifest transcription) is intact at the document layer and is a good structural example.
- `check-traceability.sh`, `analyze-adr-plan-linkage.sh`, and the governance tests are substantive where they exist; empty-review validity and the medium cap are well-designed relief valves.
- The Node hook design is sound once a project skeleton exists.

## Recommended roadmap (dependency order)

1. **Make the first run work end to end** (S–M, one PR, all TDD-able via governance tests):
   in-repo `/specify`, `/plan`, `/tasks`, `/analyze` commands or `init-project.sh` runs `specify init --here --ai claude` with a path mapping; init generates `scripts/release-<stack>.sh` from the template; init scaffolds a minimal project skeleton per stack (package.json + eslint config, pyproject, go.mod) so the hook passes on a bare instance; default stack is a recommended one, not "Other"; demo-independent governance tests (nullglob, data-driven `# Covers:`); README step 0 = init, audience statement, copy-paste prerequisites. Delete `render_doc.py`, the doc-render skill, the `anthropic` requirement and its test line; move a correct `.claude/settings.json` with the documented hook schema.
2. **Attestation that works for code** (S–M): `run-verifier.sh` reviews `src/ tests/ verification/` on `impl/*` and posts on every PR; CI check matches `sha:<head>`; a code-review mode in the verifier skill; run the verifier in a clean worktree with `.env*` denied. Define solo mode (required checks + verdict parse, zero approvals) and say plainly that free-plan private repos get no server-side enforcement.
3. **Mechanize what the constitution already promises** (M): `check-architecture.sh` (req_map ⊇ verifiable REQs, threat-model minimums), `check-test-first.sh` (src change ⇒ tests change same/earlier commit, REQ cited), `check-security-disposition.sh` (crit/high fixed, cap, expiry), coverage floor in the generated hook, `verify-release.sh` called from the gates and from `/release`; per-stack CI setup (setup-node/npm ci, setup-go) emitted by init. Rewrite each article's "How to apply" to name its file.
4. **Security tool floor keyed on `.stack`** (M): gitleaks + osv-scanner/pip-audit/npm audit + semgrep in the gates and CI; Dependabot; un-ignore `*.lock`; SHA-pin actions; threat-model template with a domain checklist (auth, PII, payments, secrets, logging, deps).
5. **Collapse ceremony and add an orchestrator** (M): three lanes (design = spec+arch+plan, build = impl with CI as VALIDATE, ship = security+release) with identical mechanical gates; keep the 7-PR path as an opt-in regulated profile; a `/next` command that derives phase from branch, open PRs, and artifact presence and prints the exact next command.
6. **Define and deliver "ready to go"** (L): a tag-triggered CI job that rebuilds the artifact, verifies the manifest against the notes, checks the tag is an ancestor of main, and uploads a GitHub Release; a `deploy-<env>.sh` contract with migration step, smoke test, and rollback; then run one real external product through the pipeline and retro into a tracked backlog.

Items 1–2 are the difference between "cannot ship" and "can ship a Python or Node product with honest gates." Items 3–4 are the difference between "tests pass" and "fully tested." Items 5–6 are the difference between "an engineer can drive it" and "any user can."

## Disposition

All findings are proposals. This document changes no code. Per `art-review-gate` it should land via a PR; the roadmap's first item is a candidate for a single `impl/` branch with governance tests written first (`art-test-first`).
