---
date: 2026-09-25
target: merged range b7f959b..d17106e (PR #26 PLAN, PR #25 IMPLEMENT — Factory v3.2 P1a, first-run path: core + python pack), which merged without the headless verifier
method: two fresh-eyes reviewers on scratch copies of main @ d17106e — verifier full mode, and an implementer walking --doctor and fresh python instances (engineer, guided, Enter-at-every-prompt) through the gates
reviewers:
  - persona: verifier-full-mode
  - persona: implementer-walk
status: proposed
---

# P1a Fresh-Eyes Review — 2026-09-25

**Verdict from both reviewers: REQUEST_CHANGES**, on one shared high: the copy-paste
Python prerequisites in README (REQ-308) and the `--doctor` install hints did not
produce a working toolchain on a fresh macOS or Ubuntu machine (externally-managed
interpreter, no venv, `python3.12` absent from Ubuntu 22.04's apt), and the core gate
called a bare `python` that neither OS ships (`art-specification-primacy`). Everything
else on the main path worked: template gates green; non-interactive and
Enter-at-every-prompt inits for both profiles produce green instances; the first-run
test passes in about 12 s and its recursion guard holds; the python release hook
builds a wheel + sdist with a verifying manifest; precondition errors are clean.

## Fixed in this PR

| Id | Finding | Fix |
|---|---|---|
| F-1 / W-1 | README Python blocks `pip install` into an externally-managed interpreter; Ubuntu package name wrong for 22.04; doctor prints the same commands | Both OS blocks create and activate `.venv` first (deadsnakes note for 22.04); `--doctor` prints the venv command; `test_onboarding_surface.sh` asserts it |
| F-2 / W-1 | `run-quality-gates.sh:21` and `test_python_lint_format.sh` call bare `python`; doctor checks `python3` only | `python3 -m …` everywhere; `test_workflow_health.sh` rejects bare `python` invocations in shipped scripts and tests |

## Residual findings (medium), with owner

| Id | Finding | Owner |
|---|---|---|
| F-3 / W-3 | Init is not atomic: `.specflow.yml` is written before scaffold and commit; `--name Unit` (scaffold hits `tests/unit/__init__.py`), an empty git identity, or a SIGPIPE leave a half-instance that re-init refuses with no recovery hint | patch tier (next) |
| W-4 | `--name Src` / `--name Conftest` accepted but the skeleton fails pytest with no hand edits (REQ-304) | patch tier (next), with F-3 |
| W-5 | Gates SKIP (and pass) when the configured stack's `scripts/quality-gates-<stack>.sh` is missing or not executable | patch tier (next) |
| F-4 | Only `--doctor` checks the interpreter; on `/usr/bin/python3` 3.9 init dies with a raw `AttributeError` (`sys.stdlib_module_names`) | patch tier (next) |
| F-5 / W-8 | `--help`/`-h` exit 2 "unknown flag"; README Quick Start describes the wrong prompt order | patch tier (next) |
| F-7 | Init's printed lanes next-steps put VALIDATE in the ship lane; regulated steps make `/architecture` conditional then unconditional | patch tier (next) |
| F-8 | `/analyze` claims ADR-consequence and REQ-to-task checks the two scripts do not perform | patch tier (next) |
| F-6 | Python instances keep the demo's `.dfy` proofs, so the default Enter path needs Dafny; README has no Dafny install block | patch tier (next) |
| F-9 | `.gitignore` `*.lock` ignores `Cargo.lock`, `pubspec.lock`, `uv.lock`; `copy_template` and init's `git add -A` would drop the P1b skeleton lockfiles | **P1b** (REQ-304 lockfiles) |
| W-2 | `--doctor --stack tauri|flutter` reports "0 missing" when no pack exists | **P1b** (packs arrive; doctor must fail on a missing pack) |
| F-14 | Python name/package rules and ruff/black doctor checks apply to every stack | **P1b** (pack-scoped validation and prereqs) |
| W-6 | `CLAUDE.md` is byte-identical across profiles, so REQ-360's profile diff for app stacks is vacuous unless something profile-specific is rendered | **P1b** (REQ-360 ubuntu profile-diff job) |
| F-19 / W-12 | Instances inherit the "First run (python, …)" CI jobs, which no-op after installing Dafny | **P1b** (per-stack job wiring) |
| F-10 / W-7 | Instances inherit the factory's own v3.2 spec, ADRs, plans, reviews; instance traceability counts 58 factory REQs and `/specify` would start at REQ-396 | P5 (`/next`) at the latest; decide owner now |
| F-11 / W-9 | Installed `action.yml` is used by no workflow; CI and README install range pins, not the pack pins | P4 (REQ-330) |
| F-18 / W-15 | `security.sh` stub exits 0 so the floor/gate split in `test_first_run.sh` is untestable | P4 (REQ-331) |
| F-21 | Constitution `art-branch-as-state` text ("No work on main") predates init's commit on main and the lanes default | P5 amendment PR B (REQ-343) |

Lows (F-12, F-13, F-15, F-16, F-17, F-20, F-22, F-23, F-24, F-25, W-10, W-11, W-13, W-14, W-16) are recorded in the two reviewer reports attached to the PR and are not repeated here; W-10 (`include = ["__PKG__*"]` prefix glob bundles sibling packages into the wheel) is the one worth taking with F-3.

## Test-first audit

No `art-test-first` violators in the range: every `scripts/`, `stacks/` and `src/` change has a test in the same or an earlier commit. `bdb6bf5` added assertions that only pass after `41e6d2b`, so `main` carries one red intermediate commit — a note for the retrospective, not a fix.
