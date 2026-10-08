# {{PROJECT_NAME}}

A verified spec-to-code pipeline using Superpowers + Dafny — the SpecFlow
Factory v3.2 workflow. Every phase or lane is a branch, every transition is
a PR, critical paths get formal verification, and security + release are
first-class phases with their own gates.

## Who this is for

This template supports two profiles, set in `.specflow.yml` (`profile:`):

- **guided** — you're not an engineer, or you'd rather not drive directly.
  Claude proposes plain-English summaries at each step and you confirm and
  merge; you're never asked to read a diff to make a decision.
- **engineer** — you drive directly: you write or review the spec, plan,
  and code yourself, and Claude works alongside you.

It also supports two paths (`path:`): **lanes** (three PRs: design, build,
ship) for solo or small teams who want less process, and **regulated**
(seven phase branches) for teams that need the full audit trail. See
`.claude/rules/review-gate.md` for both paths' branch names and the
lane-to-phase mapping.

| | You get | You do not get yet |
|---|---|---|
| **Hosting** | a repository, CI, and quality gates | managed hosting or deployment (bring your own) |
| **Auto-update** | manifest-verified releases | an auto-update channel |
| **Signing** | macOS signing and notarization whenever the five Apple secrets exist, whatever `signing:` says — environment secrets of the `release` environment, which a GitHub Free private repository cannot hold; with `signing: apple` and any secret missing the release fails and publishes nothing; with `signing: none` and the secrets absent, an unsigned bundle with tester instructions; SSH-signed release tags | Windows/Linux code-signing, mobile app-store signing, automated store submission |
| **Platforms** | Python (services, CLIs), Tauri (Mac desktop), or Flutter (the macOS build of a multi-platform app) | native Windows, Linux desktop, iOS, or Android builds |

In this template, "fully tested" means automated code tests plus the security floor (see `docs/GLOSSARY.md`, Security floor) — passing tests alone are not enough; SECURITY must also show zero open critical/high findings.

This repository **is** the template: there is no separate scaffold copy to
keep in sync. If you're reading this in your own project, someone already
ran `init-project.sh` (see Quick Start, step 0) — otherwise, that's the
first thing to do.

A note on free private repositories: a free-tier private GitHub repository
cannot enforce required-PR-review branch protection the way a paid plan or
a public repository can, so treat `art-review-gate` as convention, not an
unbypassable control, until you upgrade or make the repository public —
the public-repository trade-off being that branch protection then applies,
at the cost of visibility. Even then the gate is not fully mechanical: a
repository admin can merge past the required checks and review
(`enforce_admins` is false), and under `pull_request` the workflow file
itself (`verifier.yml`) comes from the PR, so a human still has to read
gate-code changes. Tauri and Flutter
instances run their gates on macOS runners: a free private repository has
about 200 macOS minutes a month (see `### Tauri` below). CI's
`pull_request` triggers include `edited`, so `gates` re-runs on every title or
body edit, which the waiver flow (linking a waiver in the PR body) makes
routine. For what still checks a PR when Actions cannot run at all, see the
enforcement section under Workflow below.

## Quick Start

New to the template? Open `docs/getting-started.html` in a browser before
step 0: it walks through the setup prompts and the two commands after them,
what the idea must contain (with an example), the three lanes, the seven
confirmation points, and the verifier run.

0. `bash scripts/init-project.sh` — one-time setup: run at every prompt or
   pass flags (see `--help`). It asks your profile, then your project name,
   then — guided profile — "What are you building?" (a numbered menu that
   picks your stack; the path is always lanes); engineer profile asks for
   your stack directly, then your path. Either way it installs that stack's
   pack, writes `.specflow.yml`, creates the pipeline directories, and
   generates your per-stack quality-gate hook. Non-interactive: pass flags,
   or press Enter at every prompt to accept defaults (guided profile, lanes
   path, python stack, solo mode). Stays on `main` — it commits directly,
   since there is nothing to review yet. Your project does not receive the
   template's own design documents and proofs (its v3.2 spec, its pipeline-state
   decision record, architecture, plans, reviews and Dafny models): the traceability, REQ
   numbers and proofs are yours (see the glossary's Factory documents).
1. Edit `IDEA.md` with what you're building.
2. Run `/superpowers:brainstorming` to explore the design, then `/specify`
   to formalize the spec (clarification is folded into `/specify`) — tag
   critical requirements `[verifiable-model]` (Dafny proof of a contract
   model + tests of the implementation). The full `[verifiable]` tag
   additionally requires runtime-contract extraction, which is deferred to v3.3
   — until then use the model tag (`art-formal-verification`).
3. Push your design branch (`design/<slug>` on the lanes path,
   `phase/spec-<slug>` on the regulated path) and open a PR to `main`.
   After review and merge, continue with the rest of the pipeline below.

The repo ships with a complete worked example — the demo greeting pipeline
(`docs/specs/2026-05-28-demo-greeting-*`) and its derived artifacts
demonstrate all 10 phases. Use it as a structural template; see `CLAUDE.md`
for the artifact map. Note: the demo's `.dfy` proofs make Dafny a hard
requirement for `scripts/run-quality-gates.sh` while they're present —
install Dafny, or delete `verification/demo_greeting/` along with the rest
of the demo if you don't need the example (see `docs/GLOSSARY.md` for terms
like "kernel module" and "Dafny proof").

## Workflow (10 phases, either path)

Regulated path:

```
main (integration branch)
├── phase/spec-<slug>    → BRAINSTORM + SPECIFY                → PR
├── phase/arch-<slug>    → ARCHITECTURE (ADRs, threat model)   → PR
├── phase/plan-<slug>    → PLAN + TASKS + ANALYZE              → PR
├── impl/plan-N-<plan slug> → IMPLEMENT of ## Build N (TDD + Dafny) → PR (one per ## Build N)
├── phase/validate       → VALIDATE (quality gates)            → PR
├── phase/security       → SECURITY (review + disposition)     → PR
└── phase/release        → RELEASE (notes, tag, manifest)      → PR

Out-of-cycle: phase/retro-YYYY-MM-DD (retrospectives),
              impl/sec-<id> (SECURITY back-edge)
```

Lanes path (fewer, larger PRs):

```
main (integration branch)
├── design/<slug>        → BRAINSTORM + SPECIFY + ARCHITECTURE + PLAN + TASKS + ANALYZE → PR
├── build/<slug>-N        → IMPLEMENT of "## Build N"          → PR (one per build; CI here is VALIDATE)
└── ship/<version>        → SECURITY + RELEASE                 → PR

Out-of-cycle: phase/retro-YYYY-MM-DD (retrospectives),
              build/sec-<id> (SECURITY back-edge)

Both paths: patch/<slug> (patch tier, for small changes — see
.claude/rules/review-gate.md)
```

In Claude Code, `/next` reads your branches, PRs and files and prints the next step on either path (the guided profile runs it for you). Squash merges are fine: the pipeline's state is derived from branches, PRs and files, never from a state file.

Each phase or lane uses specific tools (see `CLAUDE.md` for the exact
commands) and merges via PR with:

- **Mechanical gates in CI (`gates`)** — `scripts/run-quality-gates.sh`
  (tests + Dafny + governance tests) runs on every PR, to any base, plus
  Dafny verification and contract-alignment checks on `design/`, `build/`,
  `ship/`, `impl/`, `phase/plan-`, `phase/validate`, `phase/security` and
  `phase/release` heads (and any PR labelled `has-verification`; not
  `patch/`). Tests are checked against a per-toolchain coverage
  floor (`coverage_min`, read at the base ref so a PR cannot lower the
  number — in-source ignore comments in TypeScript and Dart, and a python
  `conftest.py` (arbitrary code), can still narrow what is measured, which
  review catches);
  `check-covers.sh` requires every claimed REQ to have a test that cites
  it (`# Covers:` — a citation, not proof the test exercises it); and a
  per-commit test-first step (`scripts/check-test-first.sh`, REQ-321, a
  separate `ci.yml` step rather than part of `run-quality-gates.sh`) fails
  a PR whose source change gained no matching test in the same or an
  earlier commit. The gates also
  run the security floor (gitleaks, osv-scanner, and the stack's own
  audits); the summary lists floor failures apart from gate failures (see
  `docs/GLOSSARY.md`, Security floor). Any PR that changes a security document,
  and every ship PR, is additionally blocked by
  `check-security-disposition.sh` (the disposition gate, ADR-002 rules 1–5);
  a ship PR also by `verify-release.sh` at PR time (the release gate: three
  docs, no tag yet, manifest content transcribed, known-limitations
  complete, every `[verifiable*]` REQ claimed and proved, the previous
  release's tag).
- **Verifier review, run locally on your Claude subscription (`verifier`)**
  — from a terminal *outside* any Claude Code session, bootstrapped from
  `main`'s reviewed copy for every PR, stacked or not:
  `git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR-number>`
  (a stacked PR's base branch is unreviewed, so its script is never piped
  into bash — SEC-004; the script reads the PR's base from `gh` and reviews
  against it; the full ref, since a tag named `origin/main` would shadow the
  short name;
  fork PRs are unsupported: the script fetches the head branch from `origin`
  and must run on it). It
  reviews documents in full mode and code in code mode (a doc-only PR gets
  full mode, a code-only PR gets code mode, a mixed PR gets both) via
  `claude -p` in an isolated worktree, and always posts a marked comment.
  Add `--persona` for persona-based review. The `verifier` check is green
  only on an `APPROVE` marker or a maintainer waiver for the current head.
  The check trusts a comment by its `author_association`, whose values
  GitHub documents at
  https://docs.github.com/en/graphql/reference/enums#commentauthorassociation:
  `MEMBER` means "a member of the organization that owns the repository".
  The docs do not say how a membership that is private, or not visible to
  the token's viewer, is reported; GitHub may then report that member as
  `CONTRIBUTOR` or `NONE`, which rejects their marker or waiver — make the
  membership public, or have an `OWNER` run the verifier or post the
  waiver.
  A `MEMBER`'s waiver, and a `MEMBER`'s or `COLLABORATOR`'s marker,
  additionally counts only when that person's repository role is admin,
  maintain or write (on an organisation repository the maintainers
  themselves are `MEMBER`); a role the check cannot read fails closed, so an
  `OWNER` can still post the waiver. A marker is also bound to the diff it
  reviewed: after a stacked PR is retargeted onto a base whose merge base
  with the head differs, its `APPROVE` is rejected as `base-mismatch` until
  the verifier is re-run, while a `REQUEST_CHANGES` recorded against another
  base still blocks (`request-changes-base-mismatch`) until a newer accepted
  `APPROVE` or waiver supersedes it.
  Model-instruction Markdown (any `CLAUDE.md` or `CLAUDE.local.md` at any
  depth, Markdown under `stacks/<stack>/overlay/` or `stacks/<stack>/skeleton/`,
  and `templates/**/*.md`) is reviewed as both document and code. The CI
  check runs the base's classifier, so once that rule is on `main` an open
  PR touching those paths changes review scope from `full` to `full+code`:
  its existing `APPROVE` is rejected as `mode-mismatch` until the verifier
  is re-run. Likewise, any change to `.claude/skills/verifier/SKILL.md` or
  `headless-prompt.md` moves `prompt_sha256` at `main`, so every open PR's
  existing `APPROVE` is rejected as `prompt-mismatch` until re-run.
  No API key is needed anywhere. If a planted secret or key stops the post
  (the findings scan exits non-zero, gitleaks not installed or a
  finding), the run tells you what to do: install gitleaks and re-run, use
  `--from-file` with edited findings in team mode, or have a maintainer
  waive a genuine false positive by citing the redacted rule id. Run
  `bash scripts/run-verifier.sh --canary` after any `claude` upgrade to
  check, on your machine, that the isolation flags (`--restricted`,
  `--safe-mode`, the deny list) still hold.
- **Human approval** — team mode (`solo: false`) needs one approval from
  someone other than the author before merge. Solo mode (`solo: true`)
  needs zero required approvals — the verifier's own `APPROVE` under your
  identity is the recorded second review: on any GitHub plan it is
  self-attested and **tamper-evident, not enforced** — you can forge, re-roll
  or delete it (`art-review-gate`). On a free private repository, in
  addition, GitHub enforces neither the checks nor the review.

Where GitHub Actions cannot start jobs (a billing block, exhausted minutes),
neither `gates` nor `verifier` runs. `/next` never prints a merge command
without an `APPROVE` (or a waiver) for the head, and the command it prints
carries `--match-head-commit <head>`, so it merges only that head, and
`bash scripts/run-quality-gates.sh` run locally checks the rest: those two are
then the only checks, and nothing stops a merge you type yourself.

Dependabot opens one weekly PR per ecosystem (`.github/dependabot.yml`). A
workflow action bump touches `.github/`, which the classifier's Dependabot
exemption refuses, so the verifier must attest it. A pip bump that moves only
`scripts/requirements.txt` is exempt from the verifier check; when it moves a
gate tool's pin (ruff, black, pytest, pytest-cov) the `gates` check stops it —
`test_python_lockfiles.sh` pins each to one version in both lockfiles (folding
it into the pack lockfile moves `stacks/python/pack.yml` too:
`test_stack_packs.sh`, `test_coverage_floor.sh`) — though `enforce_admins: false`
lets an admin merge past a red `gates`. A bump of any other pin (build,
setuptools, wheel, a transitive dependency) passes both checks and can merge
exempt. So fold a week's batch into one attested `patch/<slug>` PR and close the Dependabot PRs
as superseded.

## Key Files

| File | Purpose |
|------|---------|
| `IDEA.md` | Your product idea — the starting point |
| `CLAUDE.md` | The 10-phase pipeline table with exact tool invocations |
| `constitution.md` | The twelve non-negotiable articles — read first, cite by slug |
| `docs/GLOSSARY.md` | Plain-English definitions of pipeline terms |
| `.claude/rules/` | Session-loaded operational rules (review gate, TDD) |
| `.specflow.yml` | Your project's profile, path, stack, and coverage floor |
| `stacks/<stack>/` | The stack pack `init-project.sh` installs (skeleton, hook, prerequisites) |
| `schemas/spec-template.md` | Spec template with `[verifiable]`/`[verifiable-model]` tag support |
| `schemas/plan-template.md` | Plan template with `implements:` and the plan-style rule |
| `verification/README.md` | Dafny installation, proof patterns, contract extraction |
| `docs/specs/2026-05-28-demo-greeting-design.md` | Canonical worked example (all 10 phases) |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/init-project.sh` | One-time project setup (profile, path, stack pack, `.specflow.yml`) |
| `scripts/init-project.sh --doctor` | Report-only prerequisite check; writes nothing |
| `scripts/run-quality-gates.sh` | VALIDATE gate: tests + coverage floor + Dafny + governance tests + stack hook + security floor + document gates (traceability, ADR linkage, architecture, Covers) + the disposition gate (any PR that changes a security document, and ship PRs) + the release gate (ship PRs). Test-first (`scripts/check-test-first.sh`) is a separate `ci.yml` step, not part of this script |
| `scripts/run-instance-tests.sh [--base <ref>] [--stack ...] [--all] [TEST ...]` | Template source only: runs a PR's governance tests committed since `--base`, plus any named (an uncommitted test runs only when named), inside a scaffolded instance (python, plus each stack whose `stacks/<stack>/` files changed; `--stack` replaces that touched-stack default, so `--stack python` alone runs python only), prints each instance SKIP, and exits non-zero if any test fails there; in an instance it refuses (exit 2) |
| `SPECFLOW_FIRST_RUN=1 bash tests/governance/test_first_run.sh` | Builds and gates throwaway python instances; on a Mac, also the Tauri and Flutter instances whose prerequisites `--doctor` finds (compiles Rust and runs Flutter: several minutes; others print `SKIP`) |
| `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="tauri flutter" bash tests/governance/test_first_run.sh` | macOS only: builds, gates, releases and smoke-tests throwaway app instances; fails when a toolchain is missing |
| `SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh ...` | Test-only: init without the stack skeleton (no scaffold, no toolchain) |
| `scripts/run-verifier.sh` | Verifier review, bootstrapped from `main`'s reviewed copy for every PR: `git show refs/remotes/origin/main:scripts/run-verifier.sh \| bash -s -- <PR>` (run outside a Claude session); `--canary` checks isolation |
| `scripts/analyze-adr-plan-linkage.sh` | ANALYZE gate: ADR → plan traceability check |
| `scripts/configure-repo.sh` | GitHub branch protection: requests zero (solo) or one (team) required approving review and the stable checks `gates`/`verifier`; turns rebase-merge off (`allow_rebase_merge: false`; squash and merge commits stay on), so each merged PR is one first-parent commit the tag-time re-check can judge (REQ-350, P6 R28); exits 3 with a plain-English message on a free private repository's 403; re-run after updating to v3.2 (the check names changed, and the merge-methods setting is new) |
| `scripts/render-dashboard.sh` | Generate the pipeline dashboard |
| `scripts/verify-doc.sh` | Structural checks for spec/plan markdown |
| `scripts/cleanup-worktrees.sh` | Clean up stale worktrees |

## Formal Verification (Dafny)

Tag critical requirements `[verifiable-model]` in your spec (`[verifiable]`,
which adds runtime-contract extraction, is deferred to v3.3). During
IMPLEMENT, write Dafny proofs for those requirements in `verification/`.
Dafny is only required while the project actually has `.dfy` proofs — if you
remove the demo and haven't written your own, there is nothing to install.

```bash
# Verify all proofs (recursive — matches what CI and the gates run)
dafny verify $(find verification -name '*.dfy')

# See the verification guide
cat verification/README.md
```

## Prerequisites

Run `bash scripts/init-project.sh --doctor` any time to check all of the
below for your configured stack and print the exact install command for
whatever is missing, without writing anything.

- Git, GitHub CLI (`gh --version`), `jq --version`
- Claude Code (`claude --version`) with a subscription (the verifier runs
  on it — no API key needed) with Superpowers installed as a plugin
- Dafny (`dafny --version`) — only when the project has `.dfy` proofs
  under `verification/` (the shipped demo includes proofs; install Dafny
  or remove the demo)
- `gitleaks` ≥ 8.19 (the `dir` and `git` subcommands; checked against
  8.30.1) — the verifier's findings scan needs it before it will post a
  review, and the security floor's gitleaks scan needs it on every gates
  run
- `osv-scanner` ≥ 2.6.0 — the security floor's advisory scan over every
  tracked lockfile
- Both are installed with the checksum-verifying installer,
  `bash scripts/install-pinned-tool.sh gitleaks osv-scanner --dest "$HOME/.local/bin"`
  (put `~/.local/bin` on `PATH`); on macOS, Homebrew's version-only
  `brew install gitleaks` / `brew install osv-scanner` is an alternative
- The security floor queries advisory databases (osv.dev, and in an
  instance PyPI/RustSec/npm) on every default gates run — this needs the
  network. Set `SPECFLOW_FLOOR_OFFLINE=1` to skip those lookups for
  offline work; its result is not accepted as `/security-review` evidence
- pip-audit and bandit (the python floor tools) come from a python
  instance's own hash-pinned `requirements.txt` — in the template source
  that is `stacks/python/skeleton/requirements.txt`

#### macOS

```bash
xcode-select --install                              # git
git --version
brew install gh
gh --version
brew install jq
jq --version
npm install -g @anthropic-ai/claude-code             # Claude Code
claude --version
bash scripts/install-pinned-tool.sh gitleaks osv-scanner --dest "$HOME/.local/bin"
                                                      # checksum-verified; or: brew install gitleaks / brew install osv-scanner
gitleaks version                                     # checked against 8.30.1; needs >= 8.19
osv-scanner --version                                # needs >= 2.6.0 (security floor)
```

Then, inside Claude Code, install the Superpowers plugin:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Verify with `/plugin` — Superpowers should be listed as installed.

#### Ubuntu

```bash
sudo apt-get install -y git                          # git
git --version
sudo apt-get install -y gh                           # GitHub CLI
gh --version
sudo apt-get install -y jq
jq --version
npm install -g @anthropic-ai/claude-code             # Claude Code
claude --version

# gitleaks 8.30.1 and osv-scanner (verifier findings scan and security floor;
# checksum-verified against scripts/pinned-tools.yml, needs gitleaks >= 8.19)
bash scripts/install-pinned-tool.sh gitleaks osv-scanner --dest "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
gitleaks version
osv-scanner --version
```

Then, inside Claude Code, install the Superpowers plugin:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Verify with `/plugin` — Superpowers should be listed as installed.

### Tauri

macOS only: v3.2 builds, tests, and ships Tauri app stacks on Apple Silicon
Macs. On Linux or Windows, use a Mac, or the `macos-15` CI workflow.

```bash
xcode-select --install                               # Xcode command line tools
xcode-select -p

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
. "$HOME/.cargo/env"                                  # puts ~/.cargo/bin on PATH in this shell; new shells get it from your profile
rustup --version && cargo --version

rustup toolchain install 1.99.0 --profile minimal     # ~200 MB; rust-toolchain.toml pins this
rustup toolchain list

cargo install cargo-audit --locked --version 0.22.2   # security floor: Rust advisory scan
cargo audit --version

brew install node@24 && brew link --overwrite --force node@24
node --version

bash scripts/init-project.sh --doctor --stack tauri
```

The Python tooling below is needed too — the factory's own scripts and
tests run on every stack, including Tauri and Flutter instances.

Known limitation: the tauri pack ships a skeleton disposition
(`docs/security/0.0.0-skeleton-disposition.md`) that accepts SEC-001 and
SEC-002, the advisories still in the pinned Cargo/npm lockfiles, until
2027-03-24 (renewed on 2026-10-04 by the pinned-download bump, which also
fixed SEC-003: the re-pinned lockfiles no longer carry the `unic-*` crates).
Every instance inherits those entries, recorded as the pack's
(`owner: tauri-pack`, `inherited:`), and its first `/security-review` must
re-own and confirm them. The lapse is calendar-triggered by design (the P4
plan's Ruling on suppression expiry: the floor re-surfaces an accepted risk
on its date, while ADR-002's "no gate goes red on a calendar date" governs
only the disposition gate). After 2027-03-24 the template's own floor and
every tauri instance's floor fail, and a tauri instance scaffolded after
2027-03-24 fails its first gates run until it renews. Owner: the
maintainer, kpingali123, re-pins the tauri lockfiles (or renews SEC-001 and
SEC-002 with a new `ignoreUntil` and `expiry:`) by 2027-02-13. The triggers that
exist: `tests/governance/test_suppression_expiry.sh` warns in every gates
run from 2027-01-23 (60 days out) and fails the template's gates from
2027-02-23 (under 30 days out); the weekly schedule of
`.github/workflows/app-stacks.yml` (Mondays 06:00 UTC) runs the tauri first
run, whose gates run the floor, and goes red at its first run on or after
2027-03-24; `/retrospective` tracks the date too. A template re-pin never reaches an existing instance (it is a copy): an
instance scaffolded from v3.2.0 still carries SEC-001..003 until 2026-12-24.
Such an instance recovers on its own: in its next `/security-review`, bump
`ignoreUntil` in `osv-scanner.toml` AND in each `src-tauri/audit.toml`
entry's trailing comment (`# SEC-NNN reason: …; ignoreUntil: YYYY-MM-DD`),
and add disposition entries for SEC-001..003 under the instance's own
version (`docs/security/<version>-disposition.md`, with an `expiry:` no
earlier than the new `ignoreUntil`, and its own maintainer as `owner:`) —
or upgrade the dependencies so the advisories are gone.

A Tauri instance's required gates job runs on `macos-15` for every PR push,
about 3–5 macOS minutes per run. A free private repository has about 200
macOS minutes a month (macOS minutes count ten times Linux minutes), so
that is roughly 40–60 gate runs, and one release build costs far more;
public repositories run their gates free.

### Flutter

macOS only: v3.2 builds, tests, and ships the macOS build of a Flutter app
on Apple Silicon Macs. On Linux or Windows, use a Mac, or the `macos-15`
CI workflow.

```bash
xcode-select --install                                # Xcode command line tools

# Install Xcode from the App Store, then:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -version

brew install cocoapods
pod --version

git clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git "$HOME/development/flutter"
test "$(git -C "$HOME/development/flutter" rev-parse HEAD)" = 5fc346839b5d0eef006ed8404392afb4dfae428d
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zprofile && source ~/.zprofile
flutter --version

flutter precache --macos

bash scripts/init-project.sh --doctor --stack flutter
```

The Python tooling below is needed too — the factory's own scripts and
tests run on every stack, including Tauri and Flutter instances.

A Flutter instance's required gates job runs on `macos-15` for every PR
push, about 3–5 macOS minutes per run. A free private repository has about
200 macOS minutes a month (macOS minutes count ten times Linux minutes),
so that is roughly 40–60 gate runs, and one release build costs far more;
public repositories run their gates free.

### Dafny

The shipped demo's `.dfy` proofs (`verification/demo_greeting/`) make Dafny a
hard requirement for `scripts/run-quality-gates.sh` on the default (Enter at
every prompt) python path — install it, or delete
`verification/demo_greeting/` along with the rest of the demo if you don't
need the example.

**macOS:**

```bash
brew install dafny
dafny --version
```

**Ubuntu:**

```bash
wget -q -P /tmp https://github.com/dafny-lang/dafny/releases/download/v4.11.0/dafny-4.11.0-x64-ubuntu-22.04.zip
sudo unzip -q /tmp/dafny-4.11.0-*.zip -d /opt/dafny
export PATH="/opt/dafny/dafny:$PATH"
dafny --version
```

### Python

Template tooling is Python-independent of your product stack; your chosen
stack pack (see `stacks/<stack>/`) may add its own prerequisites, reported
by `--doctor`.

#### macOS

```bash
brew install python@3.12
python3.12 -m venv .venv && source .venv/bin/activate   # Homebrew's python is externally managed; re-run the activate line in each new shell
python3 --version   # 3.12+
pip install -r scripts/requirements.txt
```

#### Ubuntu

```bash
sudo apt-get install -y python3.12 python3.12-venv   # Ubuntu 24.04; on 22.04 run `sudo add-apt-repository ppa:deadsnakes/ppa` first
python3.12 -m venv .venv && source .venv/bin/activate   # system python is externally managed; re-run the activate line in each new shell
python3 --version   # 3.12+
pip install -r scripts/requirements.txt
```

`pip install -r scripts/requirements.txt` installs pytest, ruff, black, and
the build tooling `run-quality-gates.sh` and the python stack's release
hook depend on — into the `.venv` (gitignored), which must be active in any
shell that runs the gates.

#### Deploying a python instance

A python instance ships `scripts/deploy-local.sh`, which defines `migrate`,
`deploy <version>`, `smoke` and `rollback`. The image always runs by digest,
never by its mutable tag: `deploy` reads `image.digest` from the GitHub Release
`v<version>`'s `manifest.json` (or takes `DEPLOY_DIGEST`), then pulls and runs
`ghcr.io/<owner>/<repo>@<digest>` (the image name from `DEPLOY_IMAGE`, else the
origin remote) with docker, adding `DEPLOY_RUN_ARGS` (split on whitespace, such
as `-p 8080:8080`) to `docker run`; `smoke` runs the newest `vX.Y.Z` release's
image by digest with `SPECFLOW_SMOKE=1` (or `DEPLOY_VERSION`'s); and `rollback`
redeploys the release before the one running now — the running container's
`org.opencontainers.image.version` label names it, and the highest `vX.Y.Z` tag
below that version is deployed by its Release's digest (only `vX.Y.Z` tags
count: never a `-demo` or `-rc1` tag). `DEPLOY_DIGEST`, when set, is the digest
`deploy` and `smoke` run in place of the Release's (`rollback` never reads it).
`DRY_RUN=1` prints the docker, gh and migrate commands (never the git and
python3 calls that find the image, the tags and the digest) and runs none that
changes anything — the reads (the Release's `manifest.json`, the running
container's label) still run. Sourcing the script only defines the four
functions and leaves the caller's shell options alone.

A real environment is a copy, `scripts/deploy-<env>.sh`, whose credentials live
only in a GitHub Environment with required reviewers; `release.yml` never runs
a deploy script. The gates source every `scripts/deploy-*.sh` with `DRY_RUN=1`
under a `PATH` of stubs, so a copy keeps its work inside the four functions and
behind `run`, and names no command by absolute path.

The image runs as the non-root user 10001, on a base pinned by digest. It
installs your runtime dependencies from `requirements-runtime.txt` first
(`pip install --require-hashes --no-deps --only-binary :all:`, wheels only; the
skeleton's lock is empty), then
the release's wheel alone (`pip install --no-deps --no-index`), then `pip check`,
which fails the image build when the wheel declares a dependency the lock lacks.
List a runtime dependency in `requirements-runtime.in` and regenerate the lock:
`uv pip compile --generate-hashes --universal --python-version 3.12
requirements-runtime.in -o requirements-runtime.txt`. `release-image.sh build`
takes the lock from the tagged tree and fails when it is absent. A dependency
that ships no wheel for the image's platform fails the image build: pip would
build its sdist under build isolation, installing the build requirements from
PyPI with no hash check.
