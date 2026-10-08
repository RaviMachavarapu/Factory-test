# {{PROJECT_NAME}}

Short description: Built with the SpecFlow Factory v3.2 pipeline — verified spec-to-code using Superpowers + Dafny formal verification, plus architecture / security / release gates, on either the lanes path or the regulated path (`.specflow.yml` `path:`; see `docs/GLOSSARY.md`).

## Start Every Session Here

Read `constitution.md` first. It defines the twelve non-negotiable articles. Cite article slugs (e.g., `art-kernel-boundary`) — never Roman numerals.

Run `/next` to see where the pipeline stands and what to do next (`scripts/next.sh`; state is derived from branches, PRs and files, `art-branch-as-state`).

## Repo Rule

All code, specs, plans, proofs, ADRs, threat models, and release artifacts live in this repository (Article `art-repository-singleton`).

## Stack

- Language: {{STACK}} (configured at init time)
- Profile: {{PROFILE}}
- Testing: {{TESTING}}
- Verification: Dafny (for `[verifiable]`/`[verifiable-model]` requirements, Article `art-formal-verification`)
- CI: GitHub Actions
- AI: Claude Code (Opus for specs/reviews, Sonnet for implementation)

## Pipeline (10 phases, either path)

Regulated path — one branch per phase:

| Phase | Branch | Primary tool(s) | Output |
|---|---|---|---|
| BRAINSTORM | `phase/spec-<slug>` | `/superpowers:brainstorming` | brainstorm notes |
| SPECIFY | `phase/spec-<slug>` | `/specify` (clarification included) | `docs/specs/<spec>.md` |
| ARCHITECTURE | `phase/arch-<slug>` | `/architecture` | ADR(s), `docs/architecture/<spec-slug>-overview.md`, `docs/architecture/<spec-slug>-threat-model.md` |
| PLAN | `phase/plan-<slug>` | `/specflow-plan` + `/superpowers:writing-plans` | `docs/plans/<plan>.md` (PLAN consumes ADRs; does not re-derive architecture) |
| TASKS | `phase/plan-<slug>` | `/specflow-tasks` | task list inside the plan |
| ANALYZE | `phase/plan-<slug>` | `/analyze` + verifier skill | analysis report + ADR→PLAN linkage check |
| IMPLEMENT | `impl/plan-N-<plan slug>` — N is the plan's `## Build N` section | `/superpowers:subagent-driven-development`, TDD, Dafny | code + tests + proofs |
| VALIDATE | `phase/validate` | `scripts/run-quality-gates.sh` + verifier | green gate pass |
| SECURITY | `phase/security` | `/security-review` | `docs/security/<version>-review.md`, `docs/security/<version>-disposition.md` |
| RELEASE | `phase/release` | `/release` | `docs/releases/<version>-{notes,migration,known-limitations}.md`, signed tag, `dist/manifest.json` |

Lanes path — the same 10 phases, folded into three branches:

| Lane | Branch | Phases | Primary tool(s) |
|---|---|---|---|
| Design | `design/<slug>` | BRAINSTORM, SPECIFY, ARCHITECTURE, PLAN, TASKS, ANALYZE | `/superpowers:brainstorming`, `/specify`, `/architecture`, `/specflow-plan` + `/superpowers:writing-plans`, `/specflow-tasks`, `/analyze` |
| Build | `build/<slug>-N` | IMPLEMENT (of "## Build N"), VALIDATE (CI on this PR) | `/superpowers:subagent-driven-development`, TDD, Dafny, `scripts/run-quality-gates.sh` |
| Ship | `ship/<version>` | SECURITY, RELEASE | `/security-review`, `/release` |

`/next` derives the phase or lane on either path (both paths' branch names are recognised whatever `.specflow.yml`'s `path` says) and prints the step; squash merges are permitted.

Back-edge: if SECURITY surfaces critical/high requiring code change, spawn
`impl/sec-<id>` (regulated) or `build/sec-<id>` (lanes), fix, merge,
re-VALIDATE, resume SECURITY (Article `art-threat-driven-security`).

Out-of-cycle: `/retrospective` runs on `phase/retro-YYYY-MM-DD` (Article `art-retrospective-cadence`); the patch tier runs on `patch/<slug>` on either path.

See `.claude/rules/review-gate.md` for the full path/branch table and the
lane-to-phase mapping, and `docs/GLOSSARY.md` for term definitions.

## Project Map

- `constitution.md` — twelve articles, read first
- `docs/GLOSSARY.md` — plain-English definitions of pipeline terms
- `.specflow.yml` — profile, path, stack, solo, coverage floor, signing (read only via `scripts/lib/specflow/config.py`)
- `.specflow/pack.yml` — the installed stack pack's metadata (skeleton, hook, prerequisites); in the template source the packs live under `stacks/<stack>/`
- `docs/specs/` — design specs and brainstorm output
- `docs/adr/` — architecture decision records (one per decision)
- `docs/architecture/` — overview + threat model per spec
- `docs/plans/` — implementation plans
- `docs/security/` — security review + disposition per release
- `docs/releases/` — release notes + migration + known-limitations per release
- `docs/releases/store-checklist.md` — app stacks: the macOS distribution checklist (signing, notarization, packaging), appended to each release's notes by `/release` under `## macOS distribution checklist`; `verify-release.sh` and `release.yml` refuse an app-stack release whose notes lack that heading (REQ-352)
- `docs/retrospectives/` — periodic retros
- `docs/reviews/` — review syntheses
- `docs/dashboard/` — generated HTML dashboard (gitignored)
- `src/` — application code (incl. `src/contracts/` for extracted runtime contracts)
- `verification/` — Dafny proofs (`.dfy`)
- `tests/` — unit / integration / governance tests
- `scripts/` — automation (incl. `next.sh` (the `/next` wrapper, `.claude/commands/next.md`), `scripts/lib/specflow/state.py` (its kernel, proved in the template source by the Dafny model `state.dfy` (an instance keeps only the fixtures)), `scripts/lib/specflow/pipeline.py` (branch parsing and step rendering), `run-quality-gates.sh`, `run-verifier.sh`,
  `run-security-floor.sh` (the security floor, gates section 5),
  `check-suppressions.sh` (every suppression cites a live `SEC-NNN`),
  `check-architecture.sh` (the threat-model domain checklist),
  `install-pinned-tool.sh` (checksum-verified floor-tool installer),
  `check-test-first.sh` (REQ-321, per-commit test-first — a `ci.yml` gates-job step, not a run-quality-gates.sh section),
  `check-covers.sh` (REQ-323, every claimed REQ cited by a test, gates
  section 6), `check-security-disposition.sh` (REQ-322, the disposition
  gate, ADR-002 rules 1–5), `verify-release.sh` (the PR-time release gate,
  REQ-324), `scripts/template-pack.yml` (the template source's own pack
  metadata, read where an instance has none);
  `scripts/lib/specflow/attestation.py` holds the attestation rules,
  `scripts/lib/specflow/floor.py` the floor's rules and `## Tools run`
  renderer, `scripts/lib/specflow/{frontmatter,blocks,cvss4,records,
  disposition,packinfo,release_gate}.py` the frontmatter reader, the
  security-block parser, CVSS v4.0 scoring, the disposition kernel's
  records and pure decision function, pack metadata, and the release gate;
  `scripts/lib/specflow/disposition_gate.py` the PR-time disposition gate
  behind `check-security-disposition.sh` (which versions to evaluate, the
  removed-id walk, prior entries from tags), and
  `scripts/lib/specflow/coverage.sh` the coverage floor (REQ-325), sourced
  by gates section 1 and the pack hooks; `scripts/lib/specflow/push_guard.py`
  the PreToolUse hook that asks before a push to `main` or a `gh pr merge`
  (BL-001; a local convenience, not a control: it misses git aliases, scripts
  that push, `remote.<name>.push` mappings, `gh api` merges, shell variables
  and command substitutions, commands run through `xargs` or `find -exec`,
  a wrapper's flag values such as `sudo -u root`, and, for a push with no
  explicit ref, a `--git-dir` repository's branch, since the branch is read
  from the working directory; `main` is hard-coded);
  `scripts/run-instance-tests.sh` runs a PR's new or changed governance tests
  inside a scaffolded instance, template source only (BL-021))
- `schemas/` — spec and plan templates (incl. `schemas/threat-model-template.md`,
  the ten-domain checklist, and `schemas/security-disposition-template.md`,
  the review/disposition block schema)
- `templates/` — starter templates
- `.specflow/floor-summary.json` — the floor's last-run summary (generated,
  gitignored)

## Canonical Example

This section is a manifest: one `### <name> (stack: <stack>)` subsection per
example, read by `scripts/lib/specflow/examples.py` and shared by init and
`tests/governance/test_examples.sh` (REQ-306) — every backticked path token
below is checked to exist, and stripping an example removes its subsection.

### demo_greeting (stack: python)

`docs/specs/2026-05-28-demo-greeting-design.md` and its derived artifacts demonstrate the full 10-phase pipeline. Use the demo as a structural template for new specs. The derived artifacts:

- BRAINSTORM: `docs/specs/2026-05-28-demo-greeting-brainstorm.md`
- SPECIFY: `docs/specs/2026-05-28-demo-greeting-design.md`
- ARCHITECTURE: `docs/adr/001-greeting-invariant.md`, `docs/architecture/2026-05-28-demo-greeting-overview.md`, `docs/architecture/2026-05-28-demo-greeting-threat-model.md`
- PLAN/TASKS: `docs/plans/2026-05-28-demo-greeting-plan.md`
- IMPLEMENT: `src/demo_greeting/`, `tests/demo_greeting/`, `verification/demo_greeting/`
- Fresh-eyes review: `docs/reviews/2026-05-28-v3.1-demo-review.md`
- SECURITY: `docs/security/0.0.1-demo-review.md`, `docs/security/0.0.1-demo-disposition.md`
- RELEASE: `docs/releases/0.0.1-demo-notes.md`, `docs/releases/0.0.1-demo-migration.md`, `docs/releases/0.0.1-demo-known-limitations.md`, tag `v0.0.1-demo`

### habit_tracker (stack: tauri)

The second worked example (REQ-391): a macOS habit tracker to be taken through the lanes path in `profile: guided`,
`solo: true`, in a throwaway instance repository, to a GitHub Release whose unsigned bundle a tester will open on a second
Mac. Documents only — once walked, the instance's docs artifacts and the transcript of every next-step run; no second
stack skeleton ships. Whether it has been walked yet: the Status line of `docs/examples/habit-tracker/README.md` (until then the
directory holds only that README); the tree: `docs/examples/habit-tracker/`.

## Critical Never-Do

- Never write code before a failing test exists (`art-test-first`).
- Never push directly to main (`art-branch-as-state`, `art-review-gate`).
- Never create a separate repository (`art-repository-singleton`).
- Never commit `.env` (`art-secrets-hygiene`).
- Never cite an article by Roman numeral (`art-naming-tagging`).
