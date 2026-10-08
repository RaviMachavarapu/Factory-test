---
type: plan
phase: PLAN
spec: 2026-09-25-factory-v3-2
decisions: [ADR-003]
implements: [REQ-330, REQ-331, REQ-332, REQ-333, REQ-334, REQ-388, REQ-303, REQ-360, REQ-311]
created: "2026-09-26"
---

# Factory v3.2 — P4: Security Tool Floor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** "fully tested" gains its second half. Every gates run — on a laptop, in CI, and inside a fresh instance — runs a security floor: gitleaks over the full git history with a narrow allowlist, osv-scanner over every tracked lockfile, then the stack's own audits (pip-audit and bandit; cargo-audit and npm audit; osv-scanner on `pubspec.lock`). A missing floor tool is a hard failure with an exact install line, as a missing Dafny already is. CI installs gitleaks and osv-scanner from release assets whose sha256 the repository pins; Rust tools come from `cargo install --locked --version`, Python tools from hash-pinned requirements, and every GitHub Action is pinned to a commit SHA. Floor failures are reported apart from gate failures. Every suppression cites a `SEC-NNN` its disposition accepts, and `/security-review` pastes a rendered `## Tools run` section instead of writing "manual review". Threat models answer a ten-domain checklist, and `check-architecture.sh` fails when an item is left unanswered. The Dependabot exemption now also needs verified commits from GitHub's signing identity and a diff that touches only dependency files.

**Architecture:** one new stdlib module, `scripts/lib/specflow/floor.py`, holds the floor's rules: the suppression inventory and its `SEC-NNN` check, the summary record, the `## Tools run` renderer and the review checker. A sourced bash helper, `scripts/lib/specflow/floor.sh`, gives every floor tool the same contract (presence check, version, offline switch, one grammar line, one summary record). `scripts/run-security-floor.sh` is the floor. `run-quality-gates.sh` calls it as section 5 and lists its failures apart from the gate failures. `scripts/install-pinned-tool.sh` downloads and verifies the pinned release assets for CI and for anyone without Homebrew. A second new stdlib module, `scripts/lib/specflow/architecture.py`, parses the architecture documents for `check-architecture.sh`. `attestation.py` gains the diff and committer/signature rules, with fixtures.

**Plan style (REQ-380):** test code included (governance tests, stub tools, fixture tables); implementation as intent, never bodies. Documents are described by the content the tests pin.

**Tier:** regulated path (REQ-381: P0–P5 walk `phase/*`, `impl/*`). This plan is the PLAN-phase PR from `phase/plan-factory-v3-2-p4` to `main`. `impl/plan-4-security-floor` carries Tasks 1–15 as the IMPLEMENT-phase PR. The user chooses whether to cut it from the plan branch and stack it (the P2 pattern: retarget it to `main` before the plan branch is deleted) or to cut it from `main` after the PLAN PR merges. `main @ 1905b5b` carries the P2 attestation gate, so both PRs get a real headless marker with no bootstrap: `git show origin/<base>:scripts/run-verifier.sh | bash -s -- <PR>`. P4 changes neither `SKILL.md` nor `headless-prompt.md`, so `prompt_sha256` stays stable across the two PRs. P4 touches no constitution text (REQ-343: amendment B owns the corrections).

**Spec:** `docs/specs/2026-09-25-factory-v3-2-design.md`, "Must Have — P4" (REQ-330, 331, 332, 333, 334, 388, each with its "as amended by the threat model" clause), plus the P4 slices of REQ-303 (the pack `action.yml` "installs the pinned toolchain and floor tools"), REQ-360 ("floor failures (new advisories) are reported separately from gate failures") and REQ-311 (the Dependabot committer/signature check and dependency-only diff that the patch/p2-mediums sync handed to P4). `decisions: [ADR-003]`: the Dependabot rule extends `attestation.py`'s classifier, whose `PR.attestation` reduction ADR-003 governs; the classifier stays fixture-tested, not proved. **Nothing in `implements:` is `[verifiable*]`, so no Dafny proof is owed and `check-traceability.sh` asks for none.** No REQ body changes and no `amended:` entry are needed. Every ruling below implements a REQ's intent with the real tool flags and records the difference under Interfaces. REQ-311's body already names the committer/signature check and the diff restriction as P4's (REQ-334, dfe-13).

**Partial claims:**
- **REQ-330:** delivered — the floor section, the pinned gitleaks and osv-scanner invocations, the hard FAIL with an install hint for a missing tool, CI installs from checksum-verified release assets (cached), Rust tools via `cargo install --locked --version`, Python tools from hash-pinned requirements, and the first task's bump (black to 26.x, which clears PYSEC-2026-2120 and PYSEC-2026-2121). Nothing stays open.
- **REQ-331:** delivered, with the rulings under Interfaces (cargo-audit ignores passed as `--ignore`; pip-audit `--disable-pip`; npm filtered through `osv-scanner.toml`; `dart analyze` stays in the gates hook).
- **REQ-332:** delivered — the mandatory section, the renderer, the review checker, the command text, the demo review and the tauri skeleton review. "Filled from the floor's output" is checked, not trusted: `render` prints an evidence line (a sha256 over the summary's commit and the rendered rows), and `check-review` recomputes it and requires that commit in the repository's history (for a shipped review's provenance commit, not since PR #74, 2026-10-04: see the Interfaces note below). The digest catches a paraphrased or hand-edited table; it does not stop someone who recomputes it on purpose, which the reviewer and the verifier still read for. Open → P3 (ADR-002): the block schema with required CVSS v4.0 vectors (`schemas/security-disposition-template.md`, `blocks.py`), which will migrate the demo review and disposition and the tauri pack's `0.0.0-skeleton` review and disposition. P3's parser must accept the new `suppresses:` key.
- **REQ-333:** delivered — the template, the checker for the checklist and for the ARCHITECTURE exit-gate shape that `.claude/rules/review-gate.md` states, both threat models, and the command. P4's checker checks every live spec that some plan names. P3 claims REQ-320 and narrows this to `implements:` (REQ-394) and adds `confirmed_by:` for the guided profile (REQ-389). P2 set the precedent: it created `attestation.py` for P5 to extend.
- **REQ-334:** delivered — `requirements.in` and a hash-pinned `requirements.txt` installed with `--require-hashes`, SHA-pinned actions, a read-only top-level `permissions:` in every workflow, `.github/dependabot.yml`, and `/retrospective`'s bump step. `*.lock` already left `.gitignore` in P1b Task 4 (`.gitignore:30-31`), and this plan's test only asserts it. Also delivered: dfe-13's diff restriction (paths and per-file content), and the committer/signature check. Open → P6: job-level elevation in `release.yml` (REQ-351), and the tag-time re-check applying the same Dependabot rule (REQ-350).
- **REQ-388:** delivered — every suppression cites an active `SEC-NNN` whose `suppresses:` names that entry, for every kind (ignore entries, allowlist strings, fingerprints, `# nosec`, and any non-whitelisted key or table in a suppression file, including `.bandit` and `[tool.bandit]`); "baseline entry" is ruled out by R16 (the floor passes no baseline); the allowlist is limited to the three paths; the growth check; the verifier's findings scan pinned to the base ref's config; and the tauri skeleton's suppressions cite `SEC-001`–`SEC-003` from a pack-shipped disposition.
- **REQ-303:** the pack actions install the floor tools, `pack.yml` gains `floor_tools`, `lockfiles` and `cargo_audit_version`, and REQ-303 is then closed.
- **REQ-360:** the floor/gate split becomes a real signal (H2); the app-stack floors run in the opt-in and scheduled macOS cases. Nothing stays open for P4.
- **REQ-311:** the Dependabot restriction is delivered. Open → P5 (`next.sh` shares `attestation.py`) and → P6 (the tag-time replay).
- **Checksum-pinned macOS Dafny** (P1b Deferred): delivered here (Task 6).
- **Open → P7 closeout** (Deferred by design): the version-only downloads recorded in v3.2's known-limitations, and Dependabot ecosystems for instance lockfiles.

**ARCHITECTURE artifacts:** P4 walks the full phase path, so its IMPLEMENT branch may update the architecture documents the spec's ARCHITECTURE PR produced, where P4 changes or completes what they describe. Each such edit is its own task with a governance test:
- **Task 12:** the REQ-333 checklist answers — the demo threat model gains the checklist, and the v3.2 threat model's "Update channel for apps" row is rewritten as `N/A because …`.
- **Task 13:** the v3.2 threat model's dfe-2 row (the P2 classifier as shipped), dfe-4, dfe-11 and dfe-13 rows (the P4 rules as shipped) and its narrative's "none of the mitigations exist" sentence; the overview's stale "P5 creates `attestation.py`" note, plus a line recording `check-architecture.sh`'s hand-off to P3.

The IMPLEMENT PR body lists Tasks 12 and 13 under **Architecture-artifact updates** so the reviewer reads them as such. No ADR is added or changed.

**Rulings** (decided here; the IMPLEMENT PR implements them):
- **R1 — floor tools locally.** The gates never download a tool. Locally, each floor tool must already be installed, and a missing one is `FAIL floor <tool> … (missing)` with the exact install line, even offline. `--doctor` lists them as prerequisites for every stack (H6). The install line is `bash scripts/install-pinned-tool.sh <tool> --dest "$HOME/.local/bin"` (checksum-verified, Linux and macOS), with `brew install <tool>` offered on macOS as Homebrew's version-only alternative. CI installs gitleaks and osv-scanner once per job with the same script, from a cache of the verified assets (the checksum is checked on every run, cached or not). It installs cargo-audit with `cargo install --locked --version` (the binary cached by version) and pip-audit and bandit from the instance's hash-pinned lockfile.
- **R2 — "network-free"** (recorded as a Ruling under Global Constraints). The default gates download nothing and compile nothing. The floor's advisory lookups are metadata queries: osv-scanner to api.osv.dev, pip-audit to PyPI, cargo-audit's RustSec git fetch, and npm's registry. An advisory scan cannot run without them. They run by default (measured on 2026-09-26: +~8 s on the template's gates). `SPECFLOW_FLOOR_OFFLINE=1` makes a gates run fully network-free: each tool is still checked for presence and gitleaks and bandit still run, while each advisory lookup prints a `SKIP floor … offline` line. The summary then records `mode: offline`, `floor.py render` refuses it as evidence, and no workflow may set the variable. Governance tests never touch the network; they use stub tools. A failed lookup is never reported as findings: a network error (or an exit that is not the tool's findings exit) prints `lookup failed` or `error, not findings` with the rerun hint (Interfaces "Floor lines").
- **R3 — osv-scanner scope.** The floor lists tracked lockfiles with `git ls-files` and passes each with `-L`, instead of `-r .`. Measured: `scan source -r .` inside this worktree, which is nested under the main checkout's ignored `.claude/worktrees/`, visits one directory and exits 128, "no package sources" — a false clean. With zero tracked lockfiles, the floor itself prints the REQ's "PASS with a note" and does not call osv-scanner. With tracked lockfiles, an exit of 128 or 127 is a FAIL. There is exactly one `--config`: the repository's `osv-scanner.toml`, or a generated empty file. This means per-directory `osv-scanner.toml` files never apply, which matters because the tauri overlay's root config was measured not applying to `src-tauri/Cargo.lock` without `--config`. In the template source, the root scan leaves `stacks/` out, and each `stacks/<s>/{overlay,skeleton}` directory is scanned separately with its own config. The suppression check follows the same rule (Interfaces "Suppression scan"): in the template source its root run leaves `stacks/` out, and each pack root is checked separately against its own shipped `docs/security/` (Task 8).
- **R4 — cargo-audit ignores.** cargo-audit 0.22.2 reads `.cargo/audit.toml` (cwd) and `$CARGO_HOME/audit.toml`, never `src-tauri/audit.toml`. Measured: with the P1b file at the crate root, "7 denied warnings found!" and exit 1; copied to `.cargo/audit.toml`, exit 0. So `security-tauri.sh` parses `src-tauri/audit.toml` with `tomllib` and passes each entry as `--ignore <id>`, and the file stays where REQ-304 and REQ-331 put it.
- **R5 — pip-audit.** `python3 -m pip_audit -r <lockfile> --strict --disable-pip --progress-spinner off`, with each `[[IgnoredVulns]]` id in `osv-scanner.toml` passed as `--ignore-vuln`. `--disable-pip` audits a hash-pinned lockfile without creating a venv or running pip, so no package code executes. The lockfile is the instance's `requirements.txt`, which the python pack ships hash-pinned. That corrects H16, whose premise ("no lockfile beyond scripts/requirements.txt") is false: `stacks/python/skeleton/requirements.txt` is uv-generated with hashes. Only when an instance has no root `requirements.txt` (a `SPECFLOW_NO_SCAFFOLD` instance) does the audit fall back to `scripts/requirements.txt`, with a printed note.
- **R6 — npm audit.** npm has no ignore file. `npm audit --audit-level=high --json` is filtered in `python3`: a high or critical advisory whose GHSA id is not an `[[IgnoredVulns]]` id in `osv-scanner.toml` fails, and so does npm's own `error` object (fail closed). One ignore file then serves osv-scanner, pip-audit and npm.
- **R7 — `dart analyze --fatal-infos`.** It stays in `quality-gates-flutter.sh`, which already runs it (`stacks/flutter/gates.sh:13`), and is not run twice. REQ-331 itself calls it "static hygiene, not a vulnerability check". `security-flutter.sh` runs the osv-scanner half.
- **R8 — `gitleaks:allow`.** The floor passes `--ignore-gitleaks-allow`, so an inline allow comment suppresses nothing. Under REQ-388 there are then no inline gitleaks suppressions to cite. The suppression kinds are the `.gitleaks.toml` allowlist, `.gitleaksignore` fingerprints, `[[IgnoredVulns]]`, cargo `ignore` entries, bandit `# nosec`, bandit configuration (`.bandit` files, which bandit discovers under its targets, and `[tool.bandit]`), and any key or table outside each suppression file's whitelist (`[[PackageOverrides]]`, `[extend] disabledRules`, `[[rules]]`, `[target]`, `[output]`, …).
- **R9 — suppression growth (REQ-388's "grows without a SEC-NNN").** The SEC id is required inline, with no committed baseline of counts. Every suppression entry carries `SEC-NNN` on its own line (TOML comment, `reason` prefix, or the comment line before a `.gitleaksignore` fingerprint). That id's latest disposition entry must be `accepted` or `deferred`, and its `suppresses:` list must name the entry, for every kind: the advisory id, the allowlist string, the fingerprint, the config key (`<file>:<key>`), or for a `# nosec` the name `<file>:<test id>:<12-hex digest of the suppressed code>` (the digest survives line moves and changes when the suppressed code does; `file:line` would break on every edit above the line). A new entry therefore needs a disposition edit — a security artifact reviewed on the full path — and cannot ride on an old SEC id (fixtures "unlisted", "glreuse", "nosecreuse"). A count baseline would add a second file to keep in step and would still let one entry be swapped for another.
- **R10 — "the current disposition".** ADR-002's reduction: the latest entry per id across `docs/security/*-disposition.md`, versions ordered by semver, with a pre-release suffix before its release (`0.0.0-skeleton` < `0.0.1-demo` < `0.9.0` < `0.10.0`). The suppression check never compares an expiry with today (ADR-002: no disposition goes red on a calendar date). It requires every advisory ignore — `[[IgnoredVulns]]` and `audit.toml` entries alike — to carry an `ignoreUntil` no later than the entry's `expiry`. The floor itself does apply that date, the same way for every tool (the Ruling on expiry under Global Constraints).
- **R11 — the Dependabot diff set.** A path is a dependency file when its basename is one of `requirements.txt`, `requirements.in`, `package.json`, `package-lock.json`, `Cargo.toml`, `Cargo.lock`, `pubspec.yaml`, `pubspec.lock`, at any depth, and it is not under `.github/`. That covers `scripts/requirements.{in,txt}` and every pack's files: the python instance root, tauri root `package*.json` and `src-tauri/Cargo.*`, and flutter `pubspec.*`. Both sides of a rename count (`git diff --no-renames`).
  - `.github/dependabot.yml` is **excluded**, against the task's suggestion. Dependabot never edits its own configuration, and an exempt change there would silently change what the next exempt PR may touch.
  - `pyproject.toml` is excluded because it carries gate configuration (the pytest `pythonpath`).
  - Any change under `.github/`, including a workflow `uses:` bump, needs attestation.
  - **Content, not just paths.** Dependabot only moves versions, so an exempt diff may only move versions: each dependency file passes a per-basename content rule (Interfaces "Dependabot rule", step 6). An index URL, a URL, VCS or direct-reference requirement, a `package.json` edit outside the four dependency maps (`scripts`, `overrides`, …), a Cargo `[patch]`/`[replace]` table or git/path source, a lockfile `resolved`/`source` off the public registry, or a pubspec `dependency_overrides`/git/path source makes the PR non-exempt.
- **R12 — the skeleton's `SEC-NNN` source (H4).** The advisories are still present at pin time. Measured on 2026-09-26: osv-scanner 2.6.0 reports all eight overlay ids, and cargo-audit 0.22.2 denies the seven RUSTSEC ids when they are not ignored, so they cannot simply be deleted. The tauri pack therefore ships `overlay/docs/security/0.0.0-skeleton-review.md` and `…-disposition.md`, which init's scaffold copies into every tauri instance. They define SEC-001 (glib RUSTSEC-2024-0429 and its alias GHSA-wrw7-89jp-8q8g, medium, CVSS 6.9, Linux-only), SEC-002 (proc-macro-error RUSTSEC-2024-0370, low) and SEC-003 (the five unic-* RUSTSEC-2025-0075/0080/0081/0098/0100, low), all accepted until 2026-12-24 (the P1b `ignoreUntil`). The instance's first `/security-review` carries them forward (ADR-002 rule 4) and numbers its own findings from SEC-004.
- **R13 — REQ-332's "a lockfile under the pack's source roots".** This reads as "a lockfile the pack declares" (`pack.yml` `lockfiles:`, present on disk), because python's lockfile is at the instance root, outside `source_roots: [src]`, and the literal reading would never trigger. `scripts/requirements.txt` is never a pack lockfile.
- **R14 — the floor summary.** It is written to `.specflow/floor-summary.json` (gitignored) in the format under Interfaces. `/security-review` renders it with `floor.py render`, which refuses a summary that is offline, stale (commit ≠ HEAD) or dirty, that holds a tool that did not produce evidence (`missing`, `skipped-offline`, `error`, `lookup-failed`), or whose `suppression_errors` is non-empty (it lists them and exits 1).
- **R15 — pinned but still version-only (H3).** REQ-330's text limits P4 to the floor tools, the Rust tools and the Python tools. P4 pins by content: gitleaks and osv-scanner (the release checksum files), the macOS arm64 Dafny zip (Dafny publishes no checksum file, so the sha256 was computed from the asset, stated in `pinned-tools.yml`), cargo-audit (`--locked --version`), the pip tools (hashes), and every action (SHA). These stay version-only, with the honest note P7 copies into v3.2's known-limitations:
  - Node via `actions/setup-node`;
  - Python via `actions/setup-python`;
  - the Rust toolchain via `rustup` (rustup verifies its channel manifest, not a repository-held hash);
  - the Dart SDK and engine artifacts the revision-pinned Flutter SDK fetches;
  - Homebrew formulas and the `sh.rustup.rs` installer in the doctor hints;
  - npm itself.
- **R16 — REQ-388's "baseline entry".** The floor passes no baseline to any tool: never gitleaks `--baseline-path`/`-b`, never bandit `-b`/`--baseline`, `-s`/`--skip`, `-c`/`--configfile` or `--ini`; osv-scanner, pip-audit, cargo-audit and npm audit take none. A baseline file in the tree therefore suppresses nothing and needs no `SEC-NNN`. Task 5's test pins the gitleaks argv and Task 7's the bandit argv.

**Verified against:** 2026-09-26 @ main `1905b5b`; every `file:line` anchor below was checked there.
- **Gates and floor sections.** `scripts/run-quality-gates.sh`: §1 pytest `:18-29`, §2 Dafny `:31-50` (the missing-Dafny FAIL at `:45`), §3 governance `:52-65`, §4 per-stack hook `:67-93`, Summary `:95-101`. The pack stubs are `stacks/python/security.sh:1-6` and `stacks/{tauri,flutter}/security.sh:1-5`, each printing `security floor lands in P4` and exiting 0 (H2).
- **Pack actions.**
  - `stacks/python/action.yml`: `:14` `actions/setup-python@v5`; `:20` `pip install -r scripts/requirements.txt`; `:22` root `requirements.txt` with `--require-hashes`; `:24-28` Dafny placeholder.
  - `stacks/tauri/action.yml`: `:26` `setup-python@v5`, `:31` pip, `:32` `setup-node@v4`, `:35-37` rustup, `:38` `Swatinem/rust-cache@v2`, `:42-46` Dafny placeholder.
  - `stacks/flutter/action.yml`: `:20` `setup-python@v5`, `:25` pip, `:28` `actions/cache@v4`, `:57-61` placeholder.
- **Pack metadata.** `stacks/*/pack.yml`: python `:11` `lockfile: requirements.txt` and `:13-18` tool pins; tauri `:12` and flutter `:12` `lockfiles:`; nothing reads `lockfile`/`lockfiles` today.
- **Workflows.**
  - `.github/workflows/ci.yml`: no top-level `permissions:`; `:14` checkout with no `fetch-depth`; `:16-18` toolchain action; `:20` setup-python; `:24-25` `pip install -r scripts/requirements.txt`; `:27-34` Linux Dafny with sha256 `697ee703…`; `:39-82` template-only jobs (first-run `:40-69`, app-profiles `:71-81`).
  - `.github/workflows/app-stacks.yml`: `:13-14` `permissions: contents: read`; `:26` checkout; `:31-35` `./stacks/tauri`; `:37-47` and `:53-58` `actions/cache@v4`; `:49-51` `./stacks/flutter`.
  - `.github/workflows/verifier.yml`: `:13-16` read permissions; checkouts `:23`, `:47`, `:99`, `:125`.
  - Tag pins: `actions/checkout@v4` ×8, `actions/setup-python@v5` ×5, `actions/cache@v4` ×3, `actions/setup-node@v4` ×1, `Swatinem/rust-cache@v2` ×1.
- **Attestation.** `scripts/lib/specflow/attestation.py`: `:361` `DEPENDABOT`; `:364-372` `dependabot_exempt(pr_author, commit_authors)`; `:375-385` `commit_author`; `:495-500` `classify` checks the exemption first; `:605-619` `check` reads commits via `gh api --paginate …/pulls/<pr>/commits` or `--commits FILE` and decides the exemption before the policy read; `:727-755` `fixture` reads `context.commit_authors`; `:903-910` `check`'s arguments.
  - `tests/governance/fixtures/attestation/21-*.json` (no commit authors → not exempt), `33-*.json` (all commits by dependabot → exempt), `34-*.json` (a foreign commit → not exempt), `35-*.json` (team self-waiver by a commit author).
  - `tests/governance/test_attestation.sh:160-161` (the fixture loop, `≥ 35`), `:162-167` (rule names), `:219-244` (the Dependabot check path).
- **Verifier findings scan.** `scripts/run-verifier.sh`: `:93-99` `require_gitleaks` (exit 6); `:270-296` `scan_findings` — `gitleaks dir … --ignore-gitleaks-allow --gitleaks-ignore-path "$SCRATCH/cfg" --exit-code 7`, `--config` only when given, with `GITLEAKS_CONFIG`/`_TOML` unset; `:563-566` the config is `git show "$src_ref:.gitleaks.toml"` (`src_ref` = `origin/<base>`, or `HEAD` only under `--bootstrap`) (H15: confirmed, pinned by Task 4). `tests/governance/test_verifier_isolation.sh:47-49` asserts no `--config` because the template has no `.gitleaks.toml` — Task 4 must change it. `:96-104` covers an instance-like base with its own `.gitleaks.toml`. `tests/governance/lib/check.sh:91-114` holds the stub gitleaks (`dir` only; a missing `--config` file is fatal at `:102`).
- **Doctor and init.** `scripts/init-project.sh`: `:133-239` `run_doctor` (core `check_present` `:147-149`, `:166`; python tools `:172-186`; Dafny `:190-193`; pack prereqs `:224-236`); `:512-521` init copies `security.sh`, `action.yml` and `pack.yml` into the instance; `:607-610` init commits.
- **Tests that change.**
  - `tests/governance/test_stack_packs.sh`: `:26-27` asserts the stub sentinel; `:30-33` pin loop; `:35` uv check; `:244` the tauri scaffold harness `$A`; `:277-310` lockfile and advisory checks.
  - `tests/governance/test_first_run.sh`: `:12` the `FLOOR` regex; `:13-20` `gates()`; `:21-27` `floor()`; `:48` `DEFAULT_CASES`; `:86-92` and `:123-125` the conditional tauri and flutter floor runs.
  - `tests/governance/test_python_lint_format.sh:27-44` checks ruff and black but reads no range (H9). P1b's H6 freeze has lapsed: `:28` and `run-quality-gates.sh:21` call `python3`.
  - `tests/governance/test_init_doctor.sh:15-18`.
  - `scripts/check-traceability.sh:161-168` counts every `SEC-NNN` occurrence in a review as a definition.
- **Security documents.**
  - `docs/security/0.0.1-demo-review.md:9-12`: `## Tools run` lists manual review, a threat-model walkthrough and Dafny (H13).
  - `docs/security/0.0.1-demo-disposition.md` is prose, with no findings.
  - `.claude/commands/security-review.md:11-33`: finding and disposition frontmatter, with no tools section.
- **Architecture documents and commands.**
  - `.claude/commands/architecture.md:17` states the threat-model shape inline (H8).
  - `.claude/commands/retrospective.md:16-18`.
  - `docs/architecture/2026-05-28-demo-greeting-threat-model.md` has no checklist (H8).
  - `docs/architecture/2026-09-25-factory-v3-2-threat-model.md`: `:103` "None of the mitigations below exist today", `:110` dfe-2 ("accepts only unedited comments", H7), `:112` dfe-4, `:119` dfe-11, `:121` dfe-13, `:170-183` checklist; `:183` "Update channel for apps | N/A for the factory itself; …" does not match the grammar.
  - `docs/architecture/2026-09-25-factory-v3-2-overview.md:131-132` ("P5 creates `attestation.py`", H7).
- **User-facing docs.**
  - `docs/GLOSSARY.md:76-84` (Dependabot exemption: "are P4's") and `:171-174` (Security floor = the disposition bar).
  - `.claude/rules/review-gate.md:64` (the Dependabot claim row).
  - `README.md`: `:31` "fully tested"; `:123-126` gates bullet; `:228-243` Prerequisites; `:245-257` macOS; `:262-285` Ubuntu, with the gitleaks lines at `:279-284`.
  - `.gitignore:30-31` already says lockfiles are committed (H10).
  - `scripts/requirements.txt:1-14` is a range file.

**Tool facts on this Mac (read-only runs):**
- **gitleaks 8.30.1.**
  - CLI: `gitleaks git [flags] [repo]` with `--no-banner`, `--redact[=uint]`, `-c/--config`, `--exit-code` (default 1), `--ignore-gitleaks-allow`, `-i/--gitleaks-ignore-path` (default `.`), `--log-level`, and `-f/--report-format` with `-r/--report-path`.
  - Config precedence: `--config`, then `GITLEAKS_CONFIG`, then `GITLEAKS_CONFIG_TOML`, then `<target>/.gitleaks.toml`, then the default rules.
  - This repository's full history: 187 commits in 0.25 s, no leaks with the default rules.
  - In a scratch repository with the three-path allowlist below, an `AKIA…` key under `tests/governance/fixtures/` was suppressed, the same key under `src/` was reported with exit 1, and `--log-level warn` printed only `leaks found: 1`.
- **osv-scanner 2.6.0.**
  - CLI: `scan source [options] [dirs]` with repeatable `-L`, `-r`, `--config` (both `--config x` and `--config=x` accepted, measured), `--allow-no-lockfiles`, `--offline`, `--offline-vulnerabilities`, `--no-ignore` and `--experimental-exclude`.
  - Exit codes: 0 clean; 1 findings; 127 a missing config or lockfile (measured); 128 no package sources.
  - `-r --no-ignore .` found five lockfiles in 2.6 s and 11 advisories:
    - pygments 2.9.0 (PYSEC-2023-117, PYSEC-2026-2987), which osv-scanner resolved from the range file `scripts/requirements.txt`;
    - black 25.12.0 (PYSEC-2026-2120, CVSS 9.8, fixed in 26.3.0; PYSEC-2026-2121, 8.7, fixed in 26.3.1) in `stacks/python/skeleton/requirements.txt`;
    - the eight tauri overlay ids, reported as "unused ignores" without `--config`.
  - With `--config stacks/tauri/overlay/osv-scanner.toml` the tauri overlay is clean; flutter's `pubspec.lock` is clean.
  - A hash-pinned trial of `scripts/requirements.txt` was clean, and so was a trial skeleton lockfile with pip-audit and bandit (45 packages).
- **cargo-audit 0.22.2.** CLI: `cargo audit [-D warnings] [-f FILE] [--ignore ID]… [-n] [--stale] [--json]`. R4's measurement took 0.45 s with the cached advisory DB.
- **pip-audit 2.9.0** (2.10.1 on PyPI). Flags: `-r`, `-S/--strict`, `--disable-pip` (hashed files or `--no-deps` only), `--ignore-vuln`, `--progress-spinner`. On the skeleton lockfile it found black PYSEC-2026-2120 and 2121 in 1.4 s; on the trial pins it was clean in 0.5 s.
- **bandit 1.8.5** (1.9.4 on PyPI). Flags: `-r`, `--severity-level`, `--confidence-level`, `-q`, `--ignore-nosec`. `bandit -r src stacks/python/skeleton/src --severity-level high --confidence-level medium -q` exits 0 in 0.16 s.
- **npm 11.6.0.** `npm audit --audit-level=high` on the overlay's `package.json` and `package-lock.json`: "found 0 vulnerabilities" in 0.6 s.
- **pip-tools 7.6.1** in a throwaway venv under the scratch directory. `pip-compile --generate-hashes --allow-unsafe --strip-extras` took 38 s and resolved black 26.5.1, ruff 0.15.22, pytest 9.1.1, build 1.6.1, setuptools 84.0.0 and wheel 0.48.0. Black 26.5.1 leaves `src/` and `tests/` unchanged (8 files), and ruff is clean. The skeleton trial with pip-audit (2.10.1) and bandit (1.9.4) took 60 s.
- **uv 0.11.29** (`~/.local/bin/uv`). python3 3.12.4 (conda; black 25.1.0, ruff 0.15.22). actionlint 1.7.12. dafny 4.11.0. gh 2.97.0 as `kpingali123`.
- **Release checksum files** (`gh release download`, read-only):
  - gitleaks 8.30.1: `darwin_arm64` `b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5`, `linux_x64` `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb`.
  - osv-scanner 2.6.0: `darwin_arm64` `98c460dcd37de25819babd757d04542045b6243113e209edcd4d89fedb0256b4`, `linux_amd64` `ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108`.
  - Dafny 4.9.1 `arm64-macos-11.zip`, computed: `3209da6998c98c10e15970b85f6aa27925682c3273cd41539348ab8f7941553e`.
- **Action SHAs** (`gh api repos/<o>/<r>/git/ref/tags/<tag>`, a second hop for annotated tags, then the exact tag from `…/tags`):

| Action | Pin |
|---|---|
| `actions/checkout` | `11d5960a326750d5838078e36cf38b85af677262` (v4.4.0) |
| `actions/setup-python` | `a26af69be951a213d495a4c3e4e4022e16d87065` (v5.6.0) |
| `actions/cache` | `0057852bfaa89a56745cba8c7296529d2fc39830` (v4.3.0) |
| `actions/setup-node` | `49933ea5288caeca8642d1e84afbd3f7d6820020` (v4.4.0) |
| `Swatinem/rust-cache` | `6323deb102c322ba6fcbdcafc7e3dddab59af2b6` (v2.9.2; annotated tag, dereferenced) |

- **Gates timing.** The default gates take 1:42 at `1905b5b`.

**Clause → task:**

| REQ | Clauses (task numbers) |
|---|---|
| 330 | floor section 5; gitleaks full history + `.gitleaks.toml` 4+5; osv-scanner + config + the 128 note 5; then `security-<stack>.sh` 5+7; missing tool = hard FAIL + hint 5+9; CI release assets + checksum 2+6; Rust `--locked --version` 6; Python hash-pinned 1+6; first task bumps requirements 1 |
| 331 | python 7; tauri 7+8; flutter 7; ignore files 7+8; thresholds 7 |
| 388 | SEC-NNN per suppression 4+8; allowlist of three 4; growth 4; verifier base config 4 |
| 332 | section + tools + suppressions 11; filled from the floor 5+11; governance test 11; demo review 11 |
| 333 | template 12; checker 12; demo model 12 |
| 334 | `*.lock` (P1b) 1; `requirements.in` + pip-compile + `--require-hashes` 1+6; lint test range 1; SHA pins 3; read-only permissions 3; `dependabot.yml` 3; `/retrospective` 3; dfe-13 diff + committer/signature 10 |
| 303 | action installs floor tools 6; `pack.yml` keys 6+7 |
| 360 | separate reporting 5+7 |
| 311 | Dependabot slice 10 |

**Findings handed to P4 (H1–H17):**

| Finding | Owner |
|---|---|
| H1 | Task 6 (floor tools in `ci.yml`, the first-run job, `app-stacks.yml` via the pack actions, and each pack action; checksum-verified installs) |
| H2 | Tasks 5, 7 (real `security.sh`; `test_stack_packs.sh:26-27` changes; the split is testable with stubs) |
| H3 | R15; Tasks 2, 3, 6 (pinned by content); the rest ruled version-only → P7 known-limitations |
| H4 | R12; Task 8 |
| H5 | Task 10 (diff restriction, committer/signature check, fixtures, `--files`); Task 13 (the dfe-13 row); Task 14 (claim table, glossary) |
| H6 | Task 9 |
| H7 | Task 13 |
| H8 | Task 12 |
| H9 | Task 1 (pip-tools in a throwaway venv, 38 s measured; `requirements.in`; `--require-hashes`; the lint test reads `requirements.in`; `pip-audit --strict` clean on the result) |
| H10 | done in P1b; asserted by Task 1's test; Partial claims |
| H11 | Interfaces "Pinned tool invocations" (REQ bodies unchanged) |
| H12 | R1, R2; Tasks 5, 6, 9; CI minutes measured in Task 15 |
| H13 | R13, R14; Task 11 |
| H14 | Task 3 |
| H15 | Task 4 (confirmed at `run-verifier.sh:563-566`; pinned by a test; the template's config must extend the default rules) |
| H16 | R5, corrected premise; Task 7 |
| H17 | frontmatter and **Spec** above |

## Global Constraints

From the spec:
- **Performance.** `run-quality-gates.sh` on a fresh instance completes in under 3 minutes on ubuntu (python), excluding toolchain download. The template's gates took 1:42 before P4 and must stay under 3 minutes; Task 15 records the time after P4. App-stack gate runs on `macos-15` stay under 10 minutes with warm caches; P4 adds a cached cargo-audit (a cold compile once per version) and the floor.
- **Security.** No API key anywhere. All CI tool downloads are pinned by version and checksum — this plan closes the floor, Rust and Python part; the rest is R15. Workflows are read-only by default: Task 3 adds `ci.yml`'s missing block, and no job elevates.
- **Scalability.** A stack stays one directory. It declares `floor_tools:` and `lockfiles:` in `pack.yml` and ships its `security.sh`.
- **Compliance.** No constitution change (REQ-343: amendment B owns the `art-review-gate` Dependabot sentence).
- **Assumptions.** Pins live in the packs. The skeleton breaks when a pin is bumped, and REQ-360 separates floor failures from gate failures.

Plan-level (P1a/P1b/P2, still in force):
- Python inside scripts is stdlib-only and always invoked as `python3`. `config.py` stays the one flat `key: value` reader (`floor.py`, `architecture.py` and `install-pinned-tool.sh` read `pack.yml`, `.specflow.yml` and `scripts/pinned-tools.yml` through it). `tomllib` is stdlib.
- bash 3.2 (macOS): no associative arrays, `mapfile`, `${v,,}`, possibly-empty arrays under `set -u`, or coreutils `timeout` (use `run_within`).
- **Instance** means `.specflow.yml` or a legacy `.stack` is present; otherwise the tree is the **template source**. Tests pass in both. Loops over `stacks/*/…` sit inside `if ! instance; then shopt -s nullglob; …; fi`.
- **Opt-in rule.** Anything that downloads, compiles Rust, runs `flutter` or queries an advisory database inside a *test* runs only under `SPECFLOW_FIRST_RUN=1` (with `FIRST_RUN_CASES`) or an explicit switch (`PINNED_TOOLS_LIVE=1`). Each such step states its expected wall-clock. Default-gate tests use stub tools on `PATH` under `mktemp` and need no network.
- Gates stay green on the template source after every task, and `actionlint .github/workflows/*.yml` stays clean.
- `analyze-adr-plan-linkage.sh` is untouched. `check-traceability.sh` changes only at `:161-168` (Task 11, with a test).
- `scripts/verify-doc.sh` must not flag any marker in plans or new files. Tests never spell a double brace.
- New tests carry `# Covers: REQ-NNN` and source `tests/governance/lib/check.sh`.
- **`finish` is the last line of every test.** `check.sh` refuses any check after it, so add checks above it.
- `gh` output is parsed with `python3`, never `--jq`, and every `gh` call runs as `GH_TOKEN="$(gh auth token --user kpingali123)"`.
- One commit per task: check `git status`, stage the task's files, and commit with the given message. Every commit body ends with the `Co-Authored-By:` trailer given to the executing session.

Plan-level (new in P4):
- **Gates venv.** From Task 1 on, the lint test requires the pinned ruff and black, and this Mac's conda black is 25.1.0. Run the gates from a throwaway venv:

  ```bash
  python3 -m venv "$TMPDIR/p4-gates"
  "$TMPDIR/p4-gates/bin/pip" install --require-hashes -r scripts/requirements.txt
  PATH="$TMPDIR/p4-gates/bin:$PATH" bash scripts/run-quality-gates.sh
  ```

  For the python first-run cases (which run pip-audit and bandit inside the instance), also install `stacks/python/skeleton/requirements.txt` into the same venv. Nothing is installed globally. `rm -rf "$TMPDIR/p4-gates"` undoes it.
- **The floor needs the network** (R2), and gitleaks and osv-scanner must be on `PATH` for the gates. Both are installed here (Homebrew). Use `SPECFLOW_FLOOR_OFFLINE=1` only when offline, never in CI.
- **Ruling — "network-free" (fresh-eyes finding 5).** The workflow's "default gates stay network-free" is kept in this sense: the gates *download* nothing (no tool, no compile, no package install), and governance tests touch no network at all. The floor's advisory lookups are not downloads, and they run on every default gates run (osv.dev always; PyPI, RustSec and npm in instances). An offline laptop run therefore goes red with `lookup failed` lines until it is rerun online or with `SPECFLOW_FLOOR_OFFLINE=1`, whose summary is not evidence. This redefinition is deliberate: an advisory scan that skips its lookup silently is a false clean.
- **Ruling — suppression expiry (fresh-eyes finding 6).** ADR-002's "no gate goes red on a calendar date" governs the disposition gate (`verify-release.sh`, REQ-322): a merged release's verdict never changes with the date. It does not govern the floor, whose result already changes whenever an advisory database does. The floor deliberately fails when a suppression's `ignoreUntil` passes, so an accepted risk resurfaces for re-acceptance, and it does so identically for every tool: osv-scanner applies `ignoreUntil` itself, and `floor.py ignores` (Task 7) hands cargo-audit, pip-audit and the npm filter only the ids whose `ignoreUntil` is today or later (UTC), printing `note: <id> (SEC-NNN) expires <date>` within 30 days and `note: <id> (SEC-NNN) expired <date> — no longer ignored` after. The suppression check stays calendar-free (R10).
- **Stub tools.** `floor_stubs DIR` (Task 5) puts fake `gitleaks`, `osv-scanner`, `cargo` and `npm` in `DIR/bin`, and `pip_audit` and `bandit` as Python modules in `DIR/py`, run as `python3 -m …` with `PYTHONPATH=DIR/py`. A test that must prove a tool is *absent* uses a minimal `PATH` of symlinked system tools (as `test_init_doctor.sh:11-13` does), because the real gitleaks and osv-scanner are installed on this Mac.
- **One floor grammar.** Only `floor.sh`'s `floor_tool` prints floor lines, and only `floor.py` writes the summary, renders `## Tools run` and judges reviews.

## Interfaces shared by the tasks

**Pinned tool invocations** (H11; the REQ text is on the left, the command P4 runs is on the right; every difference is a ruling above, and no REQ body is edited):

| Tool | REQ text | Pinned invocation (cwd = repository root) | Exit | Ignore source |
|---|---|---|---|---|
| gitleaks | `gitleaks git --no-banner --redact .` | `env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML gitleaks git --no-banner --redact --log-level warn --ignore-gitleaks-allow --exit-code 1 [--config .gitleaks.toml] .` (the `--config` only when the file exists; `.gitleaksignore` at the root is read by default; never `--baseline-path`, R16) | 0 clean; 1 leak (FAIL); other: FAIL | `.gitleaks.toml` allowlist, `.gitleaksignore` (R8) |
| osv-scanner | `osv-scanner scan source -r . --config osv-scanner.toml` | `osv-scanner scan source --config <osv-scanner.toml or an empty temp file> -L <tracked lockfile>…` (R3) | 0; 1 findings; 127/128 with tracked lockfiles → FAIL (lookup failed when the output is a network error, otherwise error, not findings); no tracked lockfile → not run, PASS with note | `osv-scanner.toml` `[[IgnoredVulns]]` (osv-scanner applies `ignoreUntil`) |
| pip-audit | `pip-audit -r <lockfile> --strict` | `python3 -m pip_audit -r <lockfile> --strict --disable-pip --progress-spinner off [--ignore-vuln <id>]…` (R5) | 0; 1 findings; other, or a network error: FAIL (error / lookup failed) | `osv-scanner.toml` ids still in date (`floor.py ignores`) |
| bandit | `bandit -r src --severity-level high --confidence-level medium` | `python3 -m bandit -r <source_root> --severity-level high --confidence-level medium -q`, per `source_roots` entry that exists; never `-b`, `-s`, `-c` or `--ini` (R16) | 0; 1 FAIL | `# nosec B… SEC-NNN`; `.bandit` / `[tool.bandit]` keys citing a SEC |
| cargo-audit | `cargo audit --deny warnings` (ignores in `src-tauri/audit.toml`) | `cargo audit --deny warnings --file src-tauri/Cargo.lock [--ignore <id>]…` (R4) | 0; 1 findings; other, or a network error: FAIL (error / lookup failed) | `src-tauri/audit.toml` `[advisories] ignore` entries still in date (`floor.py ignores`) |
| npm audit | `npm audit --audit-level=high` | `npm audit --audit-level=high --json`, filtered by `python3` (R6) | decided by the filter | `osv-scanner.toml` ids |
| osv-scanner (flutter) | `osv-scanner scan source -L pubspec.lock` | `osv-scanner scan source --config <osv-scanner.toml or empty> -L pubspec.lock` | as osv-scanner | `osv-scanner.toml` |
| dart analyze | `dart analyze --fatal-infos` | unchanged in `quality-gates-flutter.sh` (R7) | — | — |

Tool names are canonical and appear in the floor lines, the summary, `pack.yml` `floor_tools:` and review rows: `gitleaks`, `osv-scanner`, `pip-audit`, `bandit`, `cargo-audit`, `npm-audit`. Lockfile basenames the floor scans: `requirements.txt`, `uv.lock`, `poetry.lock`, `Pipfile.lock`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `pubspec.lock`, `Gemfile.lock`, `composer.lock`, `go.mod`.

**Floor lines** (the only output grammar the gates parse):

```
PASS floor <tool> [<scope>] (<version>, exit 0): clean
FAIL floor <tool> [<scope>] (<version>, exit <n>): findings — see the tool output above[; <detail>]
FAIL floor <tool> [<scope>] (<version>, exit <n>): lookup failed — <first error line>; rerun online, or set SPECFLOW_FLOOR_OFFLINE=1 to skip lookups (not evidence)
FAIL floor <tool> [<scope>] (<version>, exit <n>): error, not findings — <first error line>
FAIL floor <tool> [<scope>] (missing): not installed — <install line>; see bash scripts/init-project.sh --doctor
SKIP floor <tool> [<scope>] (<version>, offline): SPECFLOW_FLOOR_OFFLINE=1 — advisory lookup not run; not valid evidence for /security-review
PASS floor osv-scanner [<scope>] (<version>, not run): not run — no tracked lockfile
```

The outcome of a run with a non-zero exit is decided in this order:
1. the tool is `--online` and its output matches the network-error pattern (case-insensitive: `connection (refused|reset|error|aborted)`, `could not resolve`, `no such host`, `name or service not known`, `temporary failure in name resolution`, `timed out`, `network is unreachable`, `failed to fetch`, `HTTPSConnectionPool`, `ENOTFOUND`, `ECONNREFUSED`, `ECONNRESET`, `EAI_AGAIN`, `ETIMEDOUT`) → `lookup failed`, status `lookup-failed`;
2. the exit is not the tool's findings exit (1 for every floor tool; the npm filter decides for itself) → `error, not findings`, status `error`;
3. otherwise → `findings`, status `fail`, with extra detail where the script has it (npm's unignored GHSA ids).

`<first error line>` is the first output line matching the pattern, or else the last non-empty output line, cut to 160 characters.

**`scripts/lib/specflow/floor.sh`** (sourced; cwd = repository root): `floor_tool [--online] TOOL SCOPE VERSION_CMD INSTALL_HINT -- CMD ARGS…`. It runs `VERSION_CMD` through `eval`; a non-zero exit or empty output means *missing*, which returns 1 even offline. The version is the first `\d+(\.\d+)+` in that output. With `--online` and `SPECFLOW_FLOOR_OFFLINE=1`, it prints the SKIP line and returns 0 without running `CMD`. Otherwise it runs `CMD`, streams its output (also kept in a temp file for the classification under "Floor lines"), prints the PASS/FAIL line, and returns 0 or 1. When `SPECFLOW_FLOOR_RECORD` is set, every outcome is appended there via `floor.py record`. It also defines `floor_offline` (true when `SPECFLOW_FLOOR_OFFLINE=1`) and `floor_emit STATUS TOOL SCOPE VERSION EXIT RESULT` for results a script computes itself (the npm filter).

**`scripts/lib/specflow/floor.py`** subcommands (cwd = the repository unless `--root`):

| Subcommand | Does | Exit |
|---|---|---|
| `record --file F --tool T --scope S --version V --exit N\|- --status pass\|fail\|error\|lookup-failed\|missing\|skipped-offline\|not-applicable --result R --command C` | appends one JSON object per line to F | 0 |
| `summarize --records F --out PATH --mode online\|offline --root DIR` | writes the summary (below), embedding `suppressions` and `suppression_errors` from the suppression scan of `--root` | 0; 2 on unreadable records |
| `suppressions --root DIR [--json]` | the REQ-388 scan (below); prints one `<file>:<line>: <problem>` per violation, or with `--json` `{"suppressions": [...], "errors": [...]}` | 0 clean; 1 violations |
| `ignores --root DIR --source osv\|cargo` (Task 7) | prints, one per line, the ids of `DIR/osv-scanner.toml` `[[IgnoredVulns]]` (`osv`) or `DIR/src-tauri/audit.toml` `[advisories] ignore` (`cargo`) whose `ignoreUntil` is today or later (UTC); the expiry notes (Global Constraints) go to stderr | 0; 2 on an unreadable file |
| `render --summary F --root DIR` (Task 11) | prints the `## Tools run` section | 0; 1 (listing why on stderr) when `mode` is offline, any status is `missing`, `skipped-offline`, `error` or `lookup-failed`, `commit` ≠ `git -C DIR rev-parse HEAD`, `dirty` is true, or `suppression_errors` is non-empty (each error listed) |
| `check-review FILE --root DIR [--pack PACK_YML]` (Task 11) | the REQ-332 check (below), reporting every violation; `--pack` defaults to `DIR/.specflow/pack.yml` | 0; 1 violations |

**Floor summary** (`.specflow/floor-summary.json`; `.gitignore` gains `.specflow/floor-summary.json`):

```json
{"schema": 1, "generated_at": "2026-09-26T20:00:00Z", "commit": "<40-hex HEAD or null>", "dirty": false,
 "mode": "online", "stack": "python|tauri|flutter|none",
 "tools": [{"tool": "gitleaks", "scope": ".", "version": "8.30.1", "exit": 0, "status": "pass",
            "result": "clean", "command": "gitleaks git --no-banner ..."}],
 "suppressions": [{"file": "src-tauri/audit.toml", "line": 11, "kind": "cargo-audit",
                   "id": "RUSTSEC-2024-0370", "name": "RUSTSEC-2024-0370", "sec": "SEC-002"}],
 "suppression_errors": []}
```

`dirty` is `git status --porcelain --untracked-files=no` being non-empty. `exit` is an integer, or `null` when the tool was not run. A `not-applicable` record's `result` is exactly `not run — no tracked lockfile`.

**`## Tools run` format** (what `render` prints and `check-review` accepts):

```
## Tools run

Floor summary: `.specflow/floor-summary.json` at <40-hex commit>, generated <UTC>, mode online.
Floor evidence: rows sha256 <64-hex>.

| Tool | Scope | Version | Exit | Result |
|---|---|---|---|---|
| gitleaks | . | 8.30.1 | 0 | clean |
| osv-scanner | . | 2.6.0 | - | not run — no tracked lockfile |

### Active suppressions

| File | Line | Id | SEC |
|---|---|---|---|
| src-tauri/audit.toml | 11 | RUSTSEC-2024-0370 | SEC-002 |
```

When there are no suppressions, the suppressions table is replaced by the line `None.` The Exit cell of a tool that was not run is `-`. Other review activities (manual review, a threat-model walkthrough) may follow the subsection as a list. A review produced outside the repository it lives in (the demo review, the tauri pack's skeleton review) carries one provenance line before the table: `Floor run <date> on a scratch instance of template commit <40-hex> (working tree)…`.

**The evidence digest.** `rows sha256` is the sha256 of the UTF-8 text formed by the summary's commit followed by every data row of the tools table and then of the suppressions table (the lines starting `| ` that are neither a header nor a `|---` separator), exactly as printed, joined with `\n`.

`check-review` rules (it reports every violation, not only the first):
- the section exists;
- **when the section contains a tools table** (the `| Tool | Scope | Version | Exit | Result |` header):
  - the `Floor evidence:` line is present, and its digest equals the one recomputed from the section's rows (otherwise: "the Tools run rows differ from what floor.py render printed");
  - `--root` is in a git work tree, and the commit — the `Floor summary:` commit, or the provenance line's template commit when there is one — is HEAD or an ancestor of it (`git merge-base --is-ancestor`). For the provenance form only, a commit absent from the repository is accepted (a tauri instance's copy of the skeleton review names a template commit that the instance's history lacks) — since PR #74 (2026-10-04) any commit outside HEAD's history is accepted there, present in the object store or not: a shipped review's provenance commit is not verified, its digest is the evidence (`docs/security/README.md`);
  - the `### Active suppressions` subsection exists, with rows whose SEC matches `^SEC-\d{3}$`, or `None.`;
  - every tools row has a version matching `^\d+(\.\d+)+$`, and an integer exit — or `-` exactly when its Result is `not run — no tracked lockfile`;
- when the pack's `lockfiles:` exist under `--root` (R13), the tools table is required and its rows must include `gitleaks`, `osv-scanner` and every `floor_tools:` entry. Without such a lockfile the table is optional, and a manual-only section (no tools table, so no subsection) passes.

**Suppression scan** (R8–R10, R16; `floor.py suppressions --root DIR` and `scripts/check-suppressions.sh [--root DIR] [--json]`, a wrapper).

*Which files.* When `DIR` is inside a git work tree, the list is `git -C DIR ls-files --cached --others --exclude-standard` (tracked plus untracked-not-ignored), so ignored copies such as the main checkout's `.claude/worktrees/*` never enter — the failure `test_tooling_hygiene.sh:47` records for a plain walk. Outside a git work tree (test fixtures), it is a filesystem walk skipping `.git`, `node_modules`, `target`, `.venv`, `build` and `dist`. **In the template source** (`DIR` has neither `.specflow.yml` nor `.stack`, and `DIR/stacks/` exists), paths under `stacks/` are left out, as R3 does for osv-scanner; each pack root (`stacks/<s>/overlay`, `stacks/<s>/skeleton`) is checked as its own `--root`, against its own shipped `docs/security/` (Task 8's loop). So the template's root run never reads the tauri overlay's entries, and the pack-root run reads them against `stacks/tauri/overlay/docs/security/`.

*Whitelists.* Each suppression file has a whitelist of keys. An entry is a list item under a whitelisted key; **any other key or table is itself an entry, of kind `config`**, named `<file basename>:<dotted key>` (for example `.gitleaks.toml:extend.disabledRules`, `.gitleaks.toml:rules`, `osv-scanner.toml:PackageOverrides`, `audit.toml:target`), which must cite a SEC with `# SEC-NNN` on its key line or table-header line.

| Kind | Where | Whitelisted keys | An entry, and the name `suppresses:` must list | Must carry |
|---|---|---|---|---|
| `gitleaks-path` / `gitleaks-regex` / `gitleaks-commit` / `gitleaks-stopword` | `DIR/.gitleaks.toml` `[allowlist]` and each `[[allowlists]]` | top level `title`; `[extend]` `useDefault`; allowlist tables `description`, `paths`, `regexes`, `commits`, `stopwords` | each string beyond the three permitted `paths` (`(^\|/)\.env\.example$`, `^docs/(.*/)?examples/`, `^tests/(.*/)?fixtures/`); the string | `# SEC-NNN` on the entry's line |
| — | `DIR/.gitleaks.toml` | — | `[extend] useDefault = true` missing | always an error (a config without it scans with no rules) |
| `config` | `DIR/.gitleaks.toml` | — | any other key or table: `[extend] disabledRules`, `path` or `url`; any `[[rules]]` (it can override a default rule id or carry its own allowlist); allowlist `regexTarget`, `condition`, `targetRules`; `<file>:<key>` | `# SEC-NNN` on the key or header line |
| `gitleaks-fingerprint` | `DIR/.gitleaksignore` | — | each non-comment line; the fingerprint | an immediately preceding `# SEC-NNN …` line |
| `osv` | every `osv-scanner.toml` | `[[IgnoredVulns]]` with `id`, `ignoreUntil`, `reason` | each `[[IgnoredVulns]]`; its id | `reason` starting `SEC-NNN:`; an `ignoreUntil` no later than the entry's `expiry` |
| `config` | every `osv-scanner.toml` | — | any other key or table: `[[PackageOverrides]]` (which can ignore a whole package, or its vulnerabilities with `vulnerability.ignore`), `GoVersionOverride`, an `[[IgnoredVulns]]` key beyond the three; `<file>:<key>` | `# SEC-NNN` on the key or header line |
| `cargo-audit` | every `audit.toml` and `.cargo/audit.toml` | `[advisories]` `ignore` | each id; the id | `# SEC-NNN` and `ignoreUntil: YYYY-MM-DD` (no later than the entry's `expiry`) on the entry's line |
| `config` | every `audit.toml` and `.cargo/audit.toml` | — | any other table or key: `[target]`, `[output]`, `[database]`, `[yanked]`, any other `[advisories]` key; `<file>:<key>` | `# SEC-NNN` on the key or header line |
| `bandit-config` | every `.bandit` file (bandit discovers one under its `-r` targets) and `[tool.bandit]` in every `pyproject.toml` | none | each key (`skips`, `exclude`, `tests`, …); `<path>:<key>` | a `# SEC-NNN` line immediately before the key (`.bandit`, INI) or `# SEC-NNN` on the key line (TOML) |
| `nosec` | `*.py` under `source_roots` (`DIR/.specflow/pack.yml`, default `[src]`) | — | each `# nosec` comment (matched case-insensitively), which must name bandit test ids — a bare `# nosec` is an error; per id, `<file>:<test id>:<12 hex>`, the hex being the first 12 of the sha256 of the code before the comment, stripped (the error message prints the expected name) | `SEC-NNN` on the line |

For each cited `SEC-NNN`, the id's **latest** entry across `DIR/docs/security/*-disposition.md` (R10) must exist and be `accepted` or `deferred`, and its `suppresses:` must list the entry's name — for every kind.

**Disposition entry** (the `/security-review` block format plus P4's key; each block is a `---`-fenced YAML block, separated from the next by a blank line):

```
---
id: SEC-001
status: accepted
owner: apingali
expiry: 2026-12-24
rationale: "…"
suppresses: [RUSTSEC-2024-0429, GHSA-wrw7-89jp-8q8g]
---
```

`suppresses:` is an inline list. An item that holds a comma, a quote, a space or a `#` (an allowlist regex, a fingerprint) is written as a double-quoted JSON string; unquoted items are split on commas and stripped.

**`scripts/pinned-tools.yml`** (flat, read by `config.py --file`):
- `gitleaks_version: 8.30.1`, `gitleaks_sha256_darwin_arm64`, `gitleaks_sha256_linux_x64`;
- `osv_scanner_version: 2.6.0`, `osv_scanner_sha256_darwin_arm64`, `osv_scanner_sha256_linux_amd64`;
- `dafny_version: 4.9.1`, `dafny_sha256_arm64_macos` (computed; a comment says so), `dafny_sha256_x64_ubuntu` (the value `ci.yml:32` already verifies).

**`scripts/install-pinned-tool.sh TOOL… --dest DIR [--pins FILE] [--cache DIR]`** (options anywhere). `TOOL` is one of `gitleaks`, `osv-scanner`, `dafny`. `--pins` defaults to `scripts/pinned-tools.yml`. `--cache` defaults to `${XDG_CACHE_HOME:-$HOME/.cache}/specflow-tools`. The platform comes from `uname -s`/`uname -m`, overridable with `SPECFLOW_TOOL_OS`/`SPECFLOW_TOOL_ARCH`:
- Darwin/arm64 maps to gitleaks `darwin_arm64`, osv-scanner `darwin_arm64` and Dafny `arm64-macos-11`.
- Linux/x86_64 (or amd64) maps to `linux_x64`, `linux_amd64` and `x64-ubuntu-20.04`.
- Anything else exits 3.

URLs:
- `https://github.com/gitleaks/gitleaks/releases/download/v<v>/gitleaks_<v>_<os>_<arch>.tar.gz`
- `https://github.com/google/osv-scanner/releases/download/v<v>/osv-scanner_<os>_<arch>`
- `https://github.com/dafny-lang/dafny/releases/download/v<v>/dafny-<v>-<platform>.zip`

Each asset is fetched with `curl --proto '=https' --tlsv1.2 -fsSL -o <cache>/<asset> <url>`, unless the cached copy's sha256 matches the pin; a mismatched cached copy is deleted and fetched again. The sha256 is computed with `python3` `hashlib`. A mismatch installs nothing. Installation: gitleaks is `tar -xzf` into `DEST` (the `gitleaks` member only); osv-scanner is copied to `DEST/osv-scanner`; Dafny is `unzip -q` into `DEST` (giving `DEST/dafny/dafny`). Each tool is made executable, and the script prints `installed <tool> <version> -> <path>`. Exit codes: 0; 1 download, checksum or extract failure; 2 usage (unknown tool, no `--dest`); 3 no pinned asset for this platform (it prints `brew install <tool>` as the version-only fallback).

**Dependabot rule** (R11; `attestation.py`):
- `DEPENDENCY_FILES` is the set of basenames in R11.
- `DEPENDABOT_COMMITTERS = {"dependabot[bot]", "web-flow"}`.
- `dependabot_exemption(pr_author, commits, files, contents) -> (bool, reason)` checks in this order, and the first failure is the reason:
  1. `pr_author != "dependabot[bot]"` → `not-dependabot` (identity by opener);
  2. `commits` is `None` or empty → `no-commits`;
  3. for each commit in order: `commit_author(c) != "dependabot[bot]"` → `commit-author:<sha7>`; committer login not in `DEPENDABOT_COMMITTERS` (a null `committer` counts as unknown) → `committer:<sha7>`; `c["commit"]["verification"]["verified"] is not True` (missing counts as false) → `unverified:<sha7>`;
  4. `files` is `None` or empty → `files-unknown`;
  5. for each path in sorted order: it starts with `.github/` → `workflow-path:<p>`; its basename is not in `DEPENDENCY_FILES` → `not-a-dependency-file:<p>`;
  6. `contents` is `None` → `content-unknown`; then for each path in sorted order, the content rule for its basename, applied to `contents[p] = {"base": text or None, "head": text or None}` (a path missing from `contents` → `content-unknown`; `head` None, a deletion → `content:<p>:deleted`; an unparsable file → `content:<p>:unparsable`). "Added lines" are the head's lines absent from the base's:
     - `requirements.txt` / `requirements.in`: every added line is blank, a `#` comment, a `--hash=sha256:<64 hex>` continuation, or a requirement `name[extras]==version` (`.txt`) or `name[extras]<specifier>` (`.in`) with an optional `; marker` and trailing `\` — any option line (`-i`, `--index-url`, `--extra-index-url`, `-f`, `--find-links`, `--trusted-host`, `-e`, `-r`, `-c`), URL (`://`), direct reference (` @ `) or VCS (`git+`) → `content:<p>:requirement-line`;
     - `package.json` (parsed with `json`): with `dependencies`, `devDependencies`, `optionalDependencies` and `peerDependencies` removed, head equals base → else `content:<p>:non-dependency-key` (`scripts`, `overrides`, `bin`, …); every value in those four maps at head is a registry version range (digits, `.`, `x`, `*`, `^`, `~`, `<`, `>`, `=`, `|`, `-`, spaces and pre-release letters; never `:` or `/`) → else `content:<p>:non-registry-spec` (git, `github:`, `file:`, `link:`, `npm:` aliases, URLs);
     - `package-lock.json` (`json`): every `packages.*.resolved` at head starts with `https://registry.npmjs.org/` → else `content:<p>:resolved`;
     - `Cargo.toml` (`tomllib`): with every dependency entry (`dependencies`, `dev-dependencies`, `build-dependencies` and their `target.*` forms) reduced to its keys other than `version` (a string entry reduces to `{}`), head equals base → else `content:<p>:non-version-change` (a `[patch]` or `[replace]` table, a git/path/registry source, a new dependency, features);
     - `Cargo.lock` (`tomllib`): every `[[package]]` `source` at head is absent, `registry+https://github.com/rust-lang/crates.io-index` or `sparse+https://index.crates.io/` → else `content:<p>:source`;
     - `pubspec.yaml`: every added line is a dependency version line (`^\s+[a-z0-9_]+:\s*["']?[\^~<>=]*\d[\w.+-]*["']?\s*$`) → else `content:<p>:non-version-line` (`dependency_overrides`, `git:`, `path:`, `hosted:`);
     - `pubspec.lock`: no added line is `source: git` or `source: path`, and every added `url:` is `"https://pub.dev"` → else `content:<p>:source`;
  7. otherwise `(True, "exempt-dependabot")`.
- `dependabot_exempt(...)` returns the bool.
- `classify(..., *, commit_authors=None, commits=None, files=None, contents=None)` uses it. The exemption is decided from `commits`, `files` and `contents` only: `commit_authors` alone never exempts (with `commits` absent the reason is `no-commits`). `commit_authors` defaults to `{commit_author(c) for c in commits}` when only `commits` is given, and still feeds the team self-waiver rule.
- `check` gains `--files FILE` (one path per line, or a JSON list) and `--contents FILE` (a JSON object in the `contents` shape). Without `--files`, the files are `git diff --name-only --no-renames <base-ref>...<head>`; without `--contents`, each file's texts are `git show <merge-base>:<p>` and `git show <head>:<p>` (a path absent on one side is `None`). A git failure means `None` (fail closed). For a `dependabot[bot]` PR that is not exempt, `check` prints `attestation: dependabot[bot] PR not exempt (<reason>) — the verifier must review it` before the normal result.
- Fixtures gain the context keys `commits` (GitHub `pulls/<n>/commits` objects: `sha`, `author.login`, `committer.login`, `commit.verification.verified`), `files` and `contents`.

**Threat-model checklist** (REQ-333; `schemas/threat-model-template.md`, `check-architecture.sh`): the section `## Domain checklist (REQ-333)` has a `| Domain | Answer |` table with exactly these rows: `Authentication`, `Authorization`, `Session`, `PII and retention`, `Payments`, `Secrets at rest`, `Sensitive logging`, `Rate limiting`, `Third-party integrations`, `Update channel for apps`. An answer is one of:
- one or more ids that exist in the frontmatter `dataflow_elements` (matching `^dfe-\d+(, dfe-\d+)*` and followed by `:`, `;`, `,` or the end of the cell);
- `N/A because ` followed by at least 10 characters.

**`scripts/check-architecture.sh`** (wrapper over `scripts/lib/specflow/architecture.py check`; `ARCH_BASE_DIR` points it at fixture docs, as `TRACE_BASE_DIR` does for `check-traceability.sh`). It checks every spec under `docs/specs/*.md` that is live (`status` ≠ `superseded`; `type: brainstorm` excluded) and named by some plan's `spec:`, with the frontmatter conventions of `check-traceability.sh`. For each such spec:
- (a) every `[verifiable]` or `[verifiable-model]` REQ appears in some `docs/architecture/<slug>-overview.md` `kernel_modules[].req_map`;
- (b) `docs/architecture/<slug>-threat-model.md` exists, with at least one trust boundary, at least one asset whose `cia` has `c`, `i` and `a` each in `{L, M, H}`, and at least one STRIDE letter in `stride_per_element` for every `dataflow_elements` entry with `external: true`;
- (c) every checklist row is present and answered.

Check (a) finds tags with the same regex as `scripts/check-traceability.sh:139-140`: a tag in backticks is prose about the tag, not a tag (`docs/specs/2026-09-25-factory-v3-2-design.md:133`, REQ-389, mentions `` `[verifiable-model]` `` and must not be flagged).

The frontmatter parser handles exactly the subset the template documents: scalars, block lists of maps (`- key: value` items with indented keys), nested block maps whose values are scalars or inline lists (`stride_per_element:` followed by indented `dfe-1: [T, I, E]` lines), inline `{…}` maps, inline `[…]` lists, `key: []`, blank lines and full-line `#` comments. Any other syntax is an error naming the line (fail closed). Output is one line per violation, `<file>: <problem>`. Exit codes: 0; 1 violations; 2 an unreadable document.

---

### Task 1: The template's Python lockfiles clear the floor — `requirements.in`, a hash-pinned `requirements.txt`, black ≥ 26.3.1, pip-audit and bandit in the python pack (REQ-334, REQ-330's first task)

**Network at implement time:** about 2 minutes (pip-compile 40 s, `uv pip compile` 60 s, pip-audit 2 s). The test is static.

**Files:**
- Create `scripts/requirements.in` and `tests/governance/test_python_lockfiles.sh`.
- Regenerate `scripts/requirements.txt` and `stacks/python/skeleton/requirements.txt`.
- Modify `stacks/python/skeleton/requirements.in`; `stacks/python/pack.yml:13-18`; `tests/governance/test_python_lint_format.sh` (header, and new checks above `:46`); `tests/governance/test_stack_packs.sh:30-33`; `.github/workflows/ci.yml:25,55`; `stacks/{python,tauri,flutter}/action.yml` (the `pip install -r scripts/requirements.txt` lines at `:20`, `:31`, `:25`).

**Interfaces:**
- `scripts/requirements.in`: the ranges of today's `scripts/requirements.txt`, except `black>=26.3.1,<27` (PYSEC-2026-2120, PYSEC-2026-2121), with the file's comments carried over.
- `scripts/requirements.txt` is regenerated, from inside `scripts/`, by `pip-compile --generate-hashes --allow-unsafe --strip-extras -o requirements.txt requirements.in` (pip-tools 7.6.1, from a throwaway venv: `python3 -m venv "$TMPDIR/p4-piptools" && "$TMPDIR/p4-piptools/bin/pip" install pip-tools==7.6.1`). `--allow-unsafe` keeps `setuptools` pinned and hashed; `--require-hashes` would refuse it otherwise.
- The skeleton's `requirements.in` gains `pip-audit>=2.9,<3` and `bandit>=1.8,<2`, and black moves to `>=26.3.1,<27`. Its lockfile is regenerated with `uv pip compile --generate-hashes --universal --python-version 3.12 requirements.in -o requirements.txt`, keeping P1a's uv convention that `test_stack_packs.sh:35` pins.
- `pack.yml` `*_version` values equal the new pins (on 2026-09-26: black 26.5.1, pip-audit 2.10.1, bandit 1.9.4), and the pin loop covers `pip-audit`→`pip_audit_version` and `bandit`→`bandit_version`. `pip install` lines gain `--require-hashes`.

- [ ] **Step 1: Write the failing tests.** `tests/governance/test_python_lockfiles.sh`:

```bash
#!/usr/bin/env bash
# REQ-334: ranges live in scripts/requirements.in; scripts/requirements.txt is pip-compile --generate-hashes output
# installed with --require-hashes. REQ-330's first task: the pins clear the floor (black >= 26.3.1 fixes
# PYSEC-2026-2120/2121, reported by osv-scanner and pip-audit on 2026-09-26). The python pack's lockfile carries the
# stack's floor tools (pip-audit, bandit) and the same gate-tool pins as the template's.
# Covers: REQ-334
# Covers: REQ-330
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
IN=scripts/requirements.in; TXT=scripts/requirements.txt; SK=stacks/python/skeleton
ck "$IN exists" test -f "$IN"
for t in pytest ruff black build setuptools wheel; do
  ck "$IN: $t as a range, never '=='" bash -c 'grep -qiE "^$2([<>=!~ ]|$)" "$1" && ! grep -qiE "^$2==" "$1"' _ "$IN" "$t"
done
ck "$TXT is pip-compile --generate-hashes output" bash -c 'grep -q "pip-compile" "$1" && grep -q -- "--generate-hashes" "$1"' _ "$TXT"
pins() { python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read().replace("\\\n", " ")
for line in text.splitlines():
    m = re.match(r"^([A-Za-z0-9_.-]+)==([^ ;\\]+)(.*)$", line)
    if m:
        print(m.group(1).lower(), m.group(2), "hashed" if "--hash=sha256:" in m.group(3) else "unhashed")
PY
}
tp=$(pins "$TXT")
for t in pytest ruff black build setuptools wheel; do ck "$TXT pins $t" grep -q "^$t " <<<"$tp"; done
ck "$TXT: every pin carries a sha256 hash" no grep -q ' unhashed$' <<<"$tp"
ck "$TXT: no requirement line without '=='" python3 - "$TXT" <<'PY'
import re, sys
text = open(sys.argv[1]).read().replace("\\\n", " ")
bad = [l for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#") and not re.match(r"^[A-Za-z0-9_.-]+==", l)]
assert not bad, bad
PY
vge() { python3 -c 'import sys; a, b = ([int(x) for x in v.split(".")[:3]] for v in sys.argv[1:3]); sys.exit(0 if a >= b else 1)' "$1" "$2"; }
for f in "$TXT" $( [ -d "$SK" ] && echo "$SK/requirements.txt" ); do
  b=$(pins "$f" | awk '$1 == "black" {print $2}')
  ck "$f: black ${b:-none} >= 26.3.1 (PYSEC-2026-2120, PYSEC-2026-2121)" vge "${b:-0}" 26.3.1
done
if [ -d "$SK" ]; then
  sp=$(pins "$SK/requirements.txt")
  for t in pip-audit bandit; do
    ck "$SK/requirements.in lists $t (a python instance's floor tools come from its own lockfile)" grep -qiE "^$t([<>=!~ ]|$)" "$SK/requirements.in"
    ck "$SK/requirements.txt pins $t with a hash" grep -q "^$t [^ ]* hashed$" <<<"$sp"
  done
  for t in ruff black pytest; do
    ck "gate tool $t: one pin in both lockfiles (the template's lint equals an instance's)" \
      [ "$(awk -v t="$t" '$1 == t {print $2}' <<<"$tp")" = "$(awk -v t="$t" '$1 == t {print $2}' <<<"$sp")" ]
  done
  ck "the python pack action installs scripts/requirements.txt with --require-hashes" grep -qF 'pip install --require-hashes -r scripts/requirements.txt' stacks/python/action.yml
fi
ck "ci.yml installs the gate tools with --require-hashes" grep -qF 'pip install --require-hashes -r scripts/requirements.txt' .github/workflows/ci.yml
ck "*.lock is not ignored (REQ-334's first clause, landed in P1b)" no git check-ignore -q --no-index x.lock
finish test_python_lockfiles
```

In `tests/governance/test_python_lint_format.sh`, add `# Covers: REQ-334` under the header comment, and insert above `if [[ $FAIL -ne 0 ]]` (`:46`):

```bash
# REQ-334: the installed ruff and black satisfy the ranges in scripts/requirements.in (this test's range source).
range_report=$(python3 - <<'PY'
import re, subprocess, sys
def ver(t):
    p = subprocess.run([sys.executable, "-m", t, "--version"], capture_output=True, text=True)
    m = re.search(r"(\d+\.\d+(?:\.\d+)?)", p.stdout + p.stderr)
    return tuple(int(x) for x in m.group(1).split(".")) if m else None
def ok(v, spec):
    for part in spec.split(","):
        m = re.match(r"\s*(>=|<=|==|<|>)\s*([\d.]+)\s*$", part)
        if not m:
            return False
        w = tuple(int(x) for x in m.group(2).split("."))
        n = max(len(v), len(w)); a = v + (0,) * (n - len(v)); b = w + (0,) * (n - len(w))
        if not {">=": a >= b, "<=": a <= b, "==": a == b, "<": a < b, ">": a > b}[m.group(1)]:
            return False
    return True
out, seen = [], set()
for line in open("scripts/requirements.in"):
    m = re.match(r"^(ruff|black)\s*([<>=!~].*)$", line.strip())
    if m:
        seen.add(m.group(1)); v = ver(m.group(1))
        if v is None or not ok(v, m.group(2)):
            out.append(f"{m.group(1)} {'.'.join(map(str, v)) if v else 'missing'} does not satisfy {m.group(2)}")
if seen != {"ruff", "black"}:
    out.append("scripts/requirements.in lacks a ruff or black range")
print("; ".join(out))
PY
)
if [[ -z "$range_report" ]]; then pass "ruff and black satisfy scripts/requirements.in"
else fail "$range_report — run: pip install --require-hashes -r scripts/requirements.txt"; fi
```

Replace the pin loop at `tests/governance/test_stack_packs.sh:30-33` with:

```bash
for tk in ruff:ruff black:black pytest:pytest build:build setuptools:setuptools wheel:wheel pip-audit:pip_audit bandit:bandit; do
  t=${tk%%:*}; k=${tk##*:}
  pin=$(grep -iE "^$t==" "$P/skeleton/requirements.txt" 2>/dev/null | head -1 | sed -E 's/^[^=]+==([^ ;\\]+).*/\1/' || true)
  ck "$t pin '$pin' equals pack.yml ${k}_version" [ -n "$pin" -a "$(val "$P/pack.yml" get "${k}_version")" = "$pin" ]
done
```

- [ ] **Step 2: Run** `bash tests/governance/test_python_lockfiles.sh; bash tests/governance/test_python_lint_format.sh; bash tests/governance/test_stack_packs.sh`. Expected:
  - `FAIL: scripts/requirements.in exists`, `FAIL: … is pip-compile --generate-hashes output`, the `pins` FAILs, both `black … >= 26.3.1` FAILs, the pip-audit/bandit FAILs and the two `--require-hashes` FAILs;
  - the lint test FAILs on `scripts/requirements.in`, which is missing;
  - `FAIL: pip-audit pin '' equals pack.yml pip_audit_version`.

  All three exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. Create the pip-tools venv, write `requirements.in`, and compile both lockfiles. Update the pack pins and the four `pip install` lines. Create the gates venv (Global Constraints) and run `python3 -m black --check src tests` from it. If black 26 reformats anything, commit that reformat in this task; on 2026-09-26 it reformatted nothing. Then run, recording the times and results for the PR body (network, about 5 s):

  ```bash
  pip-audit -r scripts/requirements.txt --strict --disable-pip
  pip-audit -r stacks/python/skeleton/requirements.txt --strict --disable-pip
  osv-scanner scan source -L scripts/requirements.txt -L stacks/python/skeleton/requirements.txt
  ```

  Each must exit 0.
- [ ] **Step 4: Run** the three tests, then `PATH="$TMPDIR/p4-gates/bin:$PATH" bash scripts/run-quality-gates.sh` — green.
- [ ] **Step 5: Commit** — "build(deps): requirements.in and hash-pinned requirements.txt, black 26 (PYSEC-2026-2120/2121), pip-audit and bandit in the python pack lockfile (REQ-334, REQ-330)"

---

### Task 2: Pinned tool assets and a checksum-verifying installer (REQ-330)

**Files:** create `scripts/pinned-tools.yml`, `scripts/install-pinned-tool.sh`, `tests/governance/test_pinned_tools.sh`.

**Interfaces:** `scripts/pinned-tools.yml` and `install-pinned-tool.sh`, both under "Interfaces shared by the tasks". The pin values are those under **Verified against**. `pinned-tools.yml` opens with a comment:
- it names each value's source: the release's `*_checksums.txt` or `*_SHA256SUMS`, or, for Dafny, "computed with shasum -a 256 from the release asset; Dafny publishes no checksum file";
- it says that `/retrospective` bumps them (Task 3).

- [ ] **Step 1: Write the failing test** — `tests/governance/test_pinned_tools.sh`:

```bash
#!/usr/bin/env bash
# REQ-330 (H3): gitleaks, osv-scanner and Dafny come from release assets whose sha256 the repository pins
# (scripts/pinned-tools.yml, copied from each release's checksum file; Dafny publishes none, so its hash was computed
# from the asset). The installer verifies on every run, cached or not, and installs nothing on a mismatch.
# Covers: REQ-330
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
PIN="$ROOT/scripts/pinned-tools.yml"; INST="$ROOT/scripts/install-pinned-tool.sh"; CFG="$ROOT/scripts/lib/specflow/config.py"
[[ -f "$INST" ]] || { fail "scripts/install-pinned-tool.sh missing"; finish test_pinned_tools; }
get() { python3 "$CFG" --file "$1" get "$2" 2>/dev/null || true; }
ck "gitleaks pinned at 8.30.1 (the version the verifier's findings scan was checked against)" [ "$(get "$PIN" gitleaks_version)" = 8.30.1 ]
ck "osv-scanner pinned at 2.6.0" [ "$(get "$PIN" osv_scanner_version)" = 2.6.0 ]
ck "Dafny pinned at 4.9.1 (ci.yml's version)" [ "$(get "$PIN" dafny_version)" = 4.9.1 ]
for k in gitleaks_sha256_darwin_arm64 gitleaks_sha256_linux_x64 osv_scanner_sha256_darwin_arm64 osv_scanner_sha256_linux_amd64 \
         dafny_sha256_arm64_macos dafny_sha256_x64_ubuntu; do
  ck "pinned-tools.yml: $k is a sha256" bash -c '[[ "$1" =~ ^[0-9a-f]{64}$ ]]' _ "$(get "$PIN" "$k")"
done
ck "Dafny's ubuntu pin is the one ci.yml already verifies" grep -qF "$(get "$PIN" dafny_sha256_x64_ubuntu)" "$ROOT/.github/workflows/ci.yml"
ck "downloads use curl --proto =https --tlsv1.2 -fsSL" grep -qE "curl --proto '?=https'? --tlsv1\.2 -fsSL" "$INST"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
B="$W/bin"; A="$W/assets"; mkdir -p "$B" "$A/pkg"
cat > "$B/curl" <<'EOF'
#!/usr/bin/env bash
# Stub curl: -o FILE URL copies $STUB_ASSETS/<basename of URL> to FILE, or exits 22 (HTTP 404) as curl -f does.
out=""; url=""; prev=""
for a in "$@"; do case "$prev" in -o) out="$a" ;; esac; case "$a" in https://*) url="$a" ;; esac; prev="$a"; done
echo "$url" >> "$STUB_ASSETS/curl.urls"
f="$STUB_ASSETS/$(basename "$url")"; [ -f "$f" ] || exit 22
cp "$f" "$out"
EOF
chmod +x "$B/curl"
printf '#!/bin/sh\necho 8.30.1\n' > "$A/pkg/gitleaks"; chmod +x "$A/pkg/gitleaks"
tar -czf "$A/gitleaks_8.30.1_linux_x64.tar.gz" -C "$A/pkg" gitleaks
printf '#!/bin/sh\necho "osv-scanner version: 2.6.0"\n' > "$A/osv-scanner_linux_amd64"
python3 - "$A/dafny-4.9.1-x64-ubuntu-20.04.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    i = zipfile.ZipInfo("dafny/dafny"); i.external_attr = 0o755 << 16
    z.writestr(i, "#!/bin/sh\necho 4.9.1\n")
PY
sha() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
printf 'gitleaks_version: 8.30.1\ngitleaks_sha256_linux_x64: %s\nosv_scanner_version: 2.6.0\nosv_scanner_sha256_linux_amd64: %s\ndafny_version: 4.9.1\ndafny_sha256_x64_ubuntu: %s\n' \
  "$(sha "$A/gitleaks_8.30.1_linux_x64.tar.gz")" "$(sha "$A/osv-scanner_linux_amd64")" "$(sha "$A/dafny-4.9.1-x64-ubuntu-20.04.zip")" > "$W/pins.yml"
inst() { rc=0; out=$(PATH="$B:$PATH" STUB_ASSETS="$A" SPECFLOW_TOOL_OS="${OS:-Linux}" SPECFLOW_TOOL_ARCH="${ARCH:-x86_64}" \
  bash "$INST" --pins "$W/pins.yml" --cache "$W/cache" --dest "$W/dest" "$@" 2>&1) || rc=$?; }
inst gitleaks osv-scanner dafny
ck "installs all three: exit 0" [ "$rc" = 0 ]
ck "gitleaks from its release URL for linux x64" grep -qxF 'https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz' "$A/curl.urls"
ck "osv-scanner from its release URL for linux amd64" grep -qxF 'https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_linux_amd64' "$A/curl.urls"
ck "Dafny from its release URL for ubuntu x64" grep -qxF 'https://github.com/dafny-lang/dafny/releases/download/v4.9.1/dafny-4.9.1-x64-ubuntu-20.04.zip' "$A/curl.urls"
ck "installed binaries are executable and report the pinned versions" \
  bash -c '[ "$("$1/gitleaks")" = 8.30.1 ] && "$1/osv-scanner" | grep -q 2.6.0 && [ "$("$1/dafny/dafny")" = 4.9.1 ]' _ "$W/dest"
rm -f "$A/curl.urls"; inst gitleaks
ck "a cached, verified asset is reused (no download)" bash -c '[ "$1" = 0 ] && [ ! -e "$2" ]' _ "$rc" "$A/curl.urls"
printf 'tampered\n' >> "$W/cache/gitleaks_8.30.1_linux_x64.tar.gz"; rm -rf "$W/dest"; inst gitleaks
ck "a tampered cached asset is discarded and fetched again (verified on every run)" bash -c '[ "$1" = 0 ] && [ -s "$2" ] && [ -x "$3/gitleaks" ]' _ "$rc" "$A/curl.urls" "$W/dest"
printf 'x\n' >> "$A/osv-scanner_linux_amd64"; rm -rf "$W/cache" "$W/dest"; inst osv-scanner
ck "a download whose sha256 differs from the pin: exit 1, 'checksum mismatch', nothing installed" \
  bash -c '[ "$1" = 1 ] && grep -qi "checksum mismatch" <<<"$2" && [ ! -e "$3/osv-scanner" ]' _ "$rc" "$out" "$W/dest"
rm "$A/gitleaks_8.30.1_linux_x64.tar.gz"; rm -rf "$W/cache"; inst gitleaks
ck "a failed download (HTTP 404): exit 1" [ "$rc" = 1 ]
inst trivy
ck "an unknown tool: usage error (exit 2)" [ "$rc" = 2 ]
OS=Darwin ARCH=x86_64 inst gitleaks
ck "no pinned asset for this platform (Intel macOS): exit 3, naming brew as the version-only fallback" bash -c '[ "$1" = 3 ] && grep -qF "brew install gitleaks" <<<"$2"' _ "$rc" "$out"
if [[ "${PINNED_TOOLS_LIVE:-0}" == 1 ]]; then   # opt-in, network, about 5 s: the pins equal the published checksum files
  gl=$(curl --proto '=https' --tlsv1.2 -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt)
  os=$(curl --proto '=https' --tlsv1.2 -fsSL https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_SHA256SUMS)
  ck "live: gitleaks linux x64 pin = release checksum" grep -qF "$(get "$PIN" gitleaks_sha256_linux_x64)  gitleaks_8.30.1_linux_x64.tar.gz" <<<"$gl"
  ck "live: gitleaks darwin arm64 pin = release checksum" grep -qF "$(get "$PIN" gitleaks_sha256_darwin_arm64)  gitleaks_8.30.1_darwin_arm64.tar.gz" <<<"$gl"
  ck "live: osv-scanner linux amd64 pin = release checksum" grep -qF "$(get "$PIN" osv_scanner_sha256_linux_amd64)  osv-scanner_linux_amd64" <<<"$os"
  ck "live: osv-scanner darwin arm64 pin = release checksum" grep -qF "$(get "$PIN" osv_scanner_sha256_darwin_arm64)  osv-scanner_darwin_arm64" <<<"$os"
else
  echo "SKIP: live checksum comparison (PINNED_TOOLS_LIVE=1 compares the pins with each release's checksum file)"
fi
finish test_pinned_tools
```

- [ ] **Step 2: Run** `bash tests/governance/test_pinned_tools.sh`. Expected: `FAIL: scripts/install-pinned-tool.sh missing`, exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. The script's header names the sources and the `/retrospective` bump.
- [ ] **Step 4: Run** the test, then `PINNED_TOOLS_LIVE=1 bash tests/governance/test_pinned_tools.sh` (network, about 5 s). Then run a real install on this Mac: `bash scripts/install-pinned-tool.sh gitleaks osv-scanner --dest "$TMPDIR/p4-tools"`, then `"$TMPDIR/p4-tools/gitleaks" version` and `"$TMPDIR/p4-tools/osv-scanner" --version` (network, about 10 s). Record all of it, then `rm -rf "$TMPDIR/p4-tools"`. Run the gates.
- [ ] **Step 5: Commit** — "build(floor): pinned gitleaks, osv-scanner and Dafny assets with a checksum-verifying installer (REQ-330)"

---

### Task 3: Every action SHA-pinned, read-only workflows, Dependabot for pip and actions, `/retrospective` bumps the pins (REQ-334)

**Files:**
- Modify every `uses:` line in `.github/workflows/{ci,verifier,app-stacks}.yml` and `stacks/{python,tauri,flutter}/action.yml`, and add a top-level `permissions:` to `ci.yml` (after `on:`, before `jobs:`).
- Create `.github/dependabot.yml` and `tests/governance/test_action_pins.sh`.
- Modify `.claude/commands/retrospective.md`.

**Interfaces:**
- Every remote `uses:` becomes `owner/repo@<40-hex> # v<X.Y.Z>`, with the SHAs and tags listed under **Verified against**. Local `./…` actions are unchanged.
- `ci.yml` gains `permissions:` / `  contents: read`. No job-level `permissions:` anywhere; `release.yml` (P6) is the only file the test lets elevate.
- `.github/dependabot.yml`: `version: 2`; `updates:` with `package-ecosystem: pip`, `directory: "/scripts"`, `schedule: interval: weekly`, and `package-ecosystem: github-actions`, `directory: "/"`, `schedule: interval: weekly`. Dependabot handles pip-compile output (it regenerates `requirements.txt` with hashes) and SHA-pinned `uses:` with their version comments. The pack composites' `uses:` lines are not in `.github/workflows/`, so `/retrospective` bumps them.
- `/retrospective`'s produce step gains a sentence. It says to propose, as one of `## Proposed Changes`, the bump of every pinned download:
  - `scripts/pinned-tools.yml` (new sha256 values from the new release's checksum file; Dafny's computed);
  - the pack pins (`stacks/*/pack.yml`, including `cargo_audit_version`), with the lockfiles regenerated by pip-compile or uv;
  - the SHA-pinned actions in `stacks/*/action.yml` (`.github/actions/toolchain/action.yml` in an instance), which Dependabot does not watch;
  - the re-enumeration of `osv-scanner.toml` and `audit.toml` suppressions against their disposition.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_action_pins.sh`:

```bash
#!/usr/bin/env bash
# REQ-334 (dfe-4): every GitHub Action is pinned to a full commit SHA with a version comment; every workflow has a
# top-level read-only permissions: block, and no job elevates (only release.yml may, for REQ-351, in P6); Dependabot
# watches pip (scripts/) and github-actions; /retrospective bumps the pinned tool downloads and the pack actions' pins.
# Covers: REQ-334
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
shopt -s nullglob
files=(.github/workflows/*.yml .github/actions/*/action.yml)
if ! instance; then files+=(stacks/*/action.yml); fi
shopt -u nullglob
ck "there are workflow and action files to check (${#files[@]})" [ "${#files[@]}" -gt 2 ]
for f in "${files[@]}"; do
  bad=$(grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:' "$f" | grep -vE 'uses:[[:space:]]+\./' \
        | grep -vE 'uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*[[:space:]]*$' || true)
  ck "$f: every uses: is a 40-hex SHA with a '# vX.Y.Z' comment (or a local ./ action)" [ -z "$bad" ]
  if [ -n "$bad" ]; then printf '    %s\n' "$bad"; fi
done
for wf in .github/workflows/*.yml; do
  ck "$wf: a top-level permissions: block" grep -qE '^permissions:' "$wf"
  top=$(awk '/^permissions:/{f=1; next} f && /^[^ ]/{exit} f' "$wf")
  ck "$wf: top-level permissions are read-only" bash -c 'grep -qE "^permissions:[[:space:]]*(read-all|\{\})?[[:space:]]*$" "$2" && ! grep -qE ":[[:space:]]*write" <<<"$1"' _ "$top" "$wf"
  if [[ "$(basename "$wf")" != release.yml ]]; then
    ck "$wf: no job elevates to write (only release.yml may, REQ-351)" no grep -qE '^[[:space:]]+[a-z-]+:[[:space:]]*write' "$wf"
  fi
done
D=.github/dependabot.yml
ck "$D exists" test -f "$D"
ck "$D: version 2" grep -qE '^version:[[:space:]]*2[[:space:]]*$' "$D"
ck "$D: pip for /scripts and github-actions for /" python3 - "$D" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
eco = {}
for b in re.split(r"\n\s*-\s+package-ecosystem:", "\n" + t)[1:]:
    name = b.split("\n", 1)[0].strip().strip('"')
    d = re.search(r'^\s*directory:\s*"?([^"\n]+)"?\s*$', b, re.M)
    eco[name] = d.group(1).strip() if d else None
assert eco.get("pip") == "/scripts" and eco.get("github-actions") == "/", eco
PY
ck "$D: every ecosystem has a schedule" [ "$(grep -cE '^[[:space:]]+interval:' "$D")" -ge 2 ]
R=.claude/commands/retrospective.md
ck "/retrospective bumps scripts/pinned-tools.yml" bash -c 'grep -qF "scripts/pinned-tools.yml" "$1" && grep -qi "bump" "$1"' _ "$R"
ck "/retrospective bumps the pack actions' SHA pins (Dependabot watches only .github/workflows)" grep -qF 'stacks/*/action.yml' "$R"
finish test_action_pins
```

- [ ] **Step 2: Run** `bash tests/governance/test_action_pins.sh`. Expected: one `every uses: is a 40-hex SHA` FAIL per file, `FAIL: .github/workflows/ci.yml: a top-level permissions: block`, the `dependabot.yml` FAILs and the `/retrospective` FAILs. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. Before editing, re-resolve each SHA read-only (a tag may have moved since 2026-09-26): `GH_TOKEN="$(gh auth token --user kpingali123)" gh api repos/<owner>/<repo>/git/ref/tags/<tag>`, then `gh api repos/<o>/<r>/git/tags/<sha>` when the object type is `tag`, then `gh api "repos/<o>/<r>/tags?per_page=100"` for the exact version. Parse the output with `python3`. If a SHA differs from the table above, use the new one and say so in the PR body.
- [ ] **Step 4: Run** the test, `actionlint .github/workflows/*.yml` and the gates — green.
- [ ] **Step 5: Commit** — "ci: pin every action by commit SHA, read-only permissions everywhere, Dependabot for pip and actions, /retrospective bumps the pins (REQ-334)"

---

### Task 4: `.gitleaks.toml`, the suppression rules, and the verifier's base-ref config pinned (REQ-388; dfe-11; H15)

**Files:**
- Create `.gitleaks.toml`, `scripts/lib/specflow/floor.py` (the disposition reader and `suppressions`), `scripts/check-suppressions.sh` and `tests/governance/test_suppressions.sh`.
- Modify `tests/governance/lib/check.sh` (`:102`: the stub gitleaks keeps a copy of its `--config`; `:133`: `vreset` also removes that copy) and `tests/governance/test_verifier_isolation.sh` (`:47-49`, plus two cases before the canary block at `:106`).

**Interfaces:** "Suppression scan", "Disposition entry" and `floor.py suppressions` under shared Interfaces. `.gitleaks.toml`:

```toml
title = "specflow"

[extend]
useDefault = true

[allowlist]
description = "The only paths REQ-388 permits without a SEC-NNN (threat model dfe-11); any further entry cites one."
paths = [
  '''(^|/)\.env\.example$''',
  '''^docs/(.*/)?examples/''',
  '''^tests/(.*/)?fixtures/''',
]
```

`run-verifier.sh` needs no change (H15, confirmed at `:563-566`): the tests pin that the findings scan receives the base ref's file, never the head's.

- [ ] **Step 1: Write the failing tests.** `tests/governance/test_suppressions.sh`:

```bash
#!/usr/bin/env bash
# REQ-388 as amended (dfe-11): every suppression — an osv-scanner.toml or audit.toml ignore entry, a .gitleaks.toml
# allowlist entry beyond the three permitted paths, a .gitleaksignore fingerprint, a bandit "# nosec", a .bandit or
# [tool.bandit] key, and any key or table outside a suppression file's whitelist — cites a SEC-NNN whose latest
# disposition entry is accepted or deferred and names the entry in suppresses: (so an allowlist or ignore set cannot
# grow, or ride on an old SEC id, without a disposition change). In the template source the root run leaves stacks/
# to the per-pack-root runs; git-ignored copies are never scanned.
# Covers: REQ-388
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CS="$ROOT/scripts/check-suppressions.sh"
[[ -f "$CS" ]] || { fail "scripts/check-suppressions.sh missing"; finish test_suppressions; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
ck ".gitleaks.toml present" test -f "$ROOT/.gitleaks.toml"
ck ".gitleaks.toml extends gitleaks' default rules (a config without them scans with no rules)" python3 - "$ROOT/.gitleaks.toml" <<'PY'
import sys, tomllib
assert tomllib.load(open(sys.argv[1], "rb")).get("extend", {}).get("useDefault") is True
PY
if ! instance; then
  ck "the template's allowlist is exactly .env.example, docs/**/examples/**, tests/**/fixtures/**" python3 - "$ROOT/.gitleaks.toml" <<'PY'
import sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb")); al = c.get("allowlist", {})
assert set(al) <= {"description", "paths"}, al
assert al["paths"] == [r"(^|/)\.env\.example$", r"^docs/(.*/)?examples/", r"^tests/(.*/)?fixtures/"], al["paths"]
assert "allowlists" not in c and "rules" not in c
PY
fi
ck "this repository passes its own suppression check" bash "$CS" --root "$ROOT"

case_root() {  # case_root NAME [ENTRY…] — a fresh root with one disposition: SEC-001 accepted (suppresses two ids plus
  # each ENTRY name, JSON-quoted), SEC-002 fixed
  C="$W/$1"; shift; rm -rf "$C"; mkdir -p "$C/docs/security"
  local sup; sup=$(python3 -c 'import json, sys; print(", ".join(["RUSTSEC-2099-0001", "GHSA-aaaa-bbbb-cccc"] + [json.dumps(x) for x in sys.argv[1:]]))' ${1+"$@"})
  cat > "$C/docs/security/0.1.0-disposition.md" <<EOF
# Security Disposition — v0.1.0

---
id: SEC-001
status: accepted
owner: alice
expiry: 2099-06-30
rationale: "fixture: unmaintained crate, no known vulnerability"
suppresses: [$sup]
---

---
id: SEC-002
status: fixed
owner: alice
rationale: "fixture: upgraded"
suppresses: [RUSTSEC-2099-0002]
---
EOF
}
chk() { rc=0; out=$(bash "$CS" --root "$C" 2>&1) || rc=$?; }
audit() { mkdir -p "$C/src-tauri"; printf '[advisories]\nignore = [\n  %s\n]\n' "$1" > "$C/src-tauri/audit.toml"; }
osv() { mkdir -p "$(dirname "$C/${4:-osv-scanner.toml}")"; printf '[[IgnoredVulns]]\nid = "%s"\nignoreUntil = %s\nreason = "%s"\n' "$1" "$2" "$3" > "$C/${4:-osv-scanner.toml}"; }
gl() {  # gl EXTRA_LINE — the permitted allowlist plus EXTRA_LINE (may be empty)
  { printf '[extend]\nuseDefault = true\n\n[allowlist]\npaths = [\n'
    printf "  '''%s''',\n" '(^|/)\.env\.example$' '^docs/(.*/)?examples/' '^tests/(.*/)?fixtures/'
    if [ -n "$1" ]; then printf '%s\n' "$1"; fi
    printf ']\n'; } > "$C/.gitleaks.toml"
}
case_root ok; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01'; chk
ck "an audit.toml entry citing an accepted SEC that lists it: pass" [ "$rc" = 0 ]
js=$(bash "$CS" --root "$C" --json)
ck "--json lists it with its kind, id and SEC" python3 -c 'import json, sys
s = json.loads(sys.argv[1])["suppressions"]
assert [(x["kind"], x["id"], x["sec"]) for x in s] == [("cargo-audit", "RUSTSEC-2099-0001", "SEC-001")], s' "$js"
case_root nosec; audit '"RUSTSEC-2099-0001",  # reason: no citation'; chk
ck "an ignore entry without a SEC-NNN fails, naming file and line" bash -c '[ "$1" = 1 ] && grep -q "src-tauri/audit.toml:3" <<<"$2"' _ "$rc" "$out"
case_root unknown; audit '"RUSTSEC-2099-0001",  # SEC-009 reason: x'; chk
ck "citing a SEC-NNN no disposition defines fails" bash -c '[ "$1" = 1 ] && grep -q "SEC-009" <<<"$2"' _ "$rc" "$out"
case_root fixed; audit '"RUSTSEC-2099-0002",  # SEC-002 reason: x'; chk
ck "citing a SEC-NNN whose latest entry is fixed fails (the suppression outlived its finding)" bash -c '[ "$1" = 1 ] && grep -q "SEC-002" <<<"$2"' _ "$rc" "$out"
case_root unlisted; audit '"RUSTSEC-2099-0003",  # SEC-001 reason: reused id'; chk
ck "an active SEC-NNN reused for an id its suppresses: omits fails (the ignore set grew)" bash -c '[ "$1" = 1 ] && grep -q "RUSTSEC-2099-0003" <<<"$2"' _ "$rc" "$out"
case_root osvok; osv GHSA-aaaa-bbbb-cccc 2099-01-01 'SEC-001: fixture'; chk
ck "an IgnoredVulns reason starting with an active SEC-NNN that lists the id: pass" [ "$rc" = 0 ]
case_root osvbad; osv GHSA-aaaa-bbbb-cccc 2099-01-01 'fixture without a citation'; chk
ck "an IgnoredVulns reason without a leading SEC-NNN fails" [ "$rc" = 1 ]
case_root osvlate; osv GHSA-aaaa-bbbb-cccc 2100-01-01 'SEC-001: fixture'; chk
ck "an ignoreUntil after the disposition entry's expiry fails" bash -c '[ "$1" = 1 ] && grep -qi "expiry" <<<"$2"' _ "$rc" "$out"
case_root nested; osv GHSA-zzzz-zzzz-zzzz 2099-01-01 'no citation' sub/osv-scanner.toml; chk
ck "an osv-scanner.toml in a subdirectory is checked too" bash -c '[ "$1" = 1 ] && grep -q "sub/osv-scanner.toml" <<<"$2"' _ "$rc" "$out"
case_root glbase; gl ''; chk
ck "a .gitleaks.toml with only the three permitted paths: pass" [ "$rc" = 0 ]
case_root glgrow; gl "  '''^src/'''"; chk
ck "an allowlist path beyond the three without a SEC-NNN fails (the allowlist grew)" bash -c '[ "$1" = 1 ] && grep -q "gitleaks.toml" <<<"$2"' _ "$rc" "$out"
case_root glcited '^src/generated/'; gl "  '''^src/generated/''',  # SEC-001 generated test keys"; chk
ck "…and passes when the new entry cites an active SEC-NNN whose suppresses: names it" [ "$rc" = 0 ]
case_root glreuse; gl "  '''^src/generated/''',  # SEC-001 generated test keys"; chk
ck "an allowlist path citing an active SEC-NNN whose suppresses: omits it fails (no riding on an old id)" bash -c '[ "$1" = 1 ] && grep -qF "^src/generated/" <<<"$2"' _ "$rc" "$out"
case_root glnodefault; printf '[allowlist]\npaths = []\n' > "$C/.gitleaks.toml"; chk
ck "a .gitleaks.toml that drops the default rules fails" bash -c '[ "$1" = 1 ] && grep -q useDefault <<<"$2"' _ "$rc" "$out"
case_root glregex; printf "[extend]\nuseDefault = true\n[allowlist]\nregexes = [\n  '''AKIA.*''',\n]\n" > "$C/.gitleaks.toml"; chk
ck "an allowlist regex without a SEC-NNN fails" [ "$rc" = 1 ]
case_root glignore; printf 'abc123:src/a.py:generic-api-key:4\n' > "$C/.gitleaksignore"; chk
ck "a .gitleaksignore fingerprint without a preceding '# SEC-NNN' line fails" [ "$rc" = 1 ]
case_root glignoreok 'abc123:src/a.py:generic-api-key:4'; printf '# SEC-001 fixture key\nabc123:src/a.py:generic-api-key:4\n' > "$C/.gitleaksignore"; chk
ck "…and passes with one" [ "$rc" = 0 ]
case_root nosec2; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec B602\n' > "$C/src/app/x.py"; chk
ck "a '# nosec' under a source root without a SEC-NNN fails, naming file and line" bash -c '[ "$1" = 1 ] && grep -q "src/app/x.py:2" <<<"$2"' _ "$rc" "$out"
d=$(python3 -c 'import hashlib; print(hashlib.sha256(b"subprocess.run(\"ls\", shell=True)").hexdigest()[:12])')
case_root nosec3 "src/app/x.py:B602:$d"; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec B602 SEC-001\n' > "$C/src/app/x.py"; chk
ck "…and passes when it cites an active SEC-NNN listing <file>:<test id>:<digest of the code>" [ "$rc" = 0 ]
case_root nosecreuse; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec B602 SEC-001\n' > "$C/src/app/x.py"; chk
ck "a '# nosec' citing an active SEC-NNN that does not list it fails, printing the name to list" bash -c '[ "$1" = 1 ] && grep -qF "src/app/x.py:B602:$3" <<<"$2"' _ "$rc" "$out" "$d"
case_root nosecbare "src/app/x.py:B602:$d"; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec SEC-001\n' > "$C/src/app/x.py"; chk
ck "a bare '# nosec' (no bandit test id) fails" bash -c '[ "$1" = 1 ] && grep -qi "test id" <<<"$2"' _ "$rc" "$out"
case_root latest; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: x'
printf -- '---\nid: SEC-001\nstatus: fixed\nowner: alice\nrationale: "fixture: upgraded in 0.10.0"\n---\n' > "$C/docs/security/0.10.0-disposition.md"
printf -- '---\nid: SEC-001\nstatus: accepted\nowner: alice\nexpiry: 2099-06-30\nrationale: "fixture: older entry"\nsuppresses: [RUSTSEC-2099-0001]\n---\n' > "$C/docs/security/0.9.0-disposition.md"; chk
ck "the latest entry per id wins by version (0.10.0 after 0.9.0 and 0.1.0): fixed, so the suppression fails" [ "$rc" = 1 ]
# Advisory ignores carry an ignoreUntil (the floor applies it to every tool; the check compares it with expiry only).
case_root osvnountil; printf '[[IgnoredVulns]]\nid = "GHSA-aaaa-bbbb-cccc"\nreason = "SEC-001: fixture"\n' > "$C/osv-scanner.toml"; chk
ck "an IgnoredVulns without ignoreUntil fails" bash -c '[ "$1" = 1 ] && grep -q ignoreUntil <<<"$2"' _ "$rc" "$out"
case_root auditnountil; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture'; chk
ck "an audit.toml entry without 'ignoreUntil: YYYY-MM-DD' fails" bash -c '[ "$1" = 1 ] && grep -q ignoreUntil <<<"$2"' _ "$rc" "$out"
# Config-level routes: every key or table outside a suppression file's whitelist is an entry that cites a SEC-NNN.
case_root osvpkg; printf '[[PackageOverrides]]\nname = "lodash"\necosystem = "npm"\nignore = true\n' > "$C/osv-scanner.toml"; chk
ck "an osv-scanner.toml [[PackageOverrides]] (a whole-package ignore) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q PackageOverrides <<<"$2"' _ "$rc" "$out"
case_root osvpkgok 'osv-scanner.toml:PackageOverrides'; printf '[[PackageOverrides]]  # SEC-001 fixture\nname = "lodash"\necosystem = "npm"\nignore = true\n' > "$C/osv-scanner.toml"; chk
ck "…and passes when its header cites an active SEC-NNN that lists osv-scanner.toml:PackageOverrides" [ "$rc" = 0 ]
case_root gldisabled; printf '[extend]\nuseDefault = true\ndisabledRules = ["generic-api-key"]\n' > "$C/.gitleaks.toml"; chk
ck "a .gitleaks.toml [extend] disabledRules without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q disabledRules <<<"$2"' _ "$rc" "$out"
case_root glrules; printf 'stack: python\n' > "$C/.specflow.yml"; printf "[extend]\nuseDefault = true\n\n[[rules]]\nid = \"generic-api-key\"\nregex = '''x^'''\n" > "$C/.gitleaks.toml"; chk
ck "an instance's .gitleaks.toml [[rules]] (overriding a default rule) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q rules <<<"$2"' _ "$rc" "$out"
case_root audittarget; printf '[advisories]\nignore = []\n\n[target]\nos = "linux"\n' > "$C/audit.toml"; chk
ck "an audit.toml table beyond [advisories] ignore ([target]) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q target <<<"$2"' _ "$rc" "$out"
case_root banditini; mkdir -p "$C/src"; printf '[bandit]\nskips = B602\n' > "$C/src/.bandit"; chk
ck "a .bandit file under a source root (bandit reads it unasked) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -qF "src/.bandit" <<<"$2"' _ "$rc" "$out"
case_root banditpy; printf '[tool.bandit]\nskips = ["B602"]\n' > "$C/pyproject.toml"; chk
ck "a [tool.bandit] key in pyproject.toml without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q "tool.bandit" <<<"$2"' _ "$rc" "$out"
# Which files: the template source leaves stacks/ to the per-pack-root runs; git-ignored copies never enter.
case_root tmpl; mkdir -p "$C/stacks/x/overlay"; printf '[advisories]\nignore = [\n  "RUSTSEC-2099-0009",\n]\n' > "$C/stacks/x/overlay/audit.toml"; chk
ck "template-shaped root: an uncited stacks/x/overlay/audit.toml is left to the pack-root run (root check passes)" [ "$rc" = 0 ]
rc=0; out=$(bash "$CS" --root "$C/stacks/x/overlay" 2>&1) || rc=$?
ck "…and the pack-root run fails on it" bash -c '[ "$1" = 1 ] && grep -q "RUSTSEC-2099-0009" <<<"$2"' _ "$rc" "$out"
printf 'stack: python\n' > "$C/.specflow.yml"; chk
ck "…while in an instance nothing under stacks/ is skipped" [ "$rc" = 1 ]
case_root ignored; mkdir -p "$C/wt/copy"; printf '[advisories]\nignore = [\n  "RUSTSEC-2099-0009",\n]\n' > "$C/wt/copy/audit.toml"
printf 'wt/\n' > "$C/.gitignore"; (cd "$C" && git init -q -b main && git add -A && git commit -qm ignored); chk
ck "in a git work tree, an ignored copy (as .claude/worktrees/* is) is never scanned" [ "$rc" = 0 ]
finish test_suppressions
```

In `tests/governance/lib/check.sh`, the stub gitleaks gains, right after the missing-config line (`:102`): `if [ -n "$cfg" ]; then cp "$cfg" "$S/gitleaks.config"; fi`; and `vreset` (`:133`) adds `"$VS"/gitleaks.config` to the files it removes, so every run starts without a copy and a stale file from an earlier run can never satisfy a `cmp`. In `tests/governance/test_verifier_isolation.sh`, replace `:48-49` with:

```bash
ck "gitleaks dir scanned the findings with the base's .gitleaks.toml (the template ships one)" \
  bash -c '[ "$(head -1 <<<"$1")" = dir ] && grep -qx -- --config <<<"$1"' _ "$gl"
ck "…whose content is the base's" cmp -s "$VS/gitleaks.config" <(git -C "$VR" show origin/main:.gitleaks.toml)
```

Then insert, before the canary block (`# The canary:` at `:106`):

```bash
# H15 (REQ-388 as amended, dfe-11): a PR that widens .gitleaks.toml does not widen the findings scan.
vbranch widen "printf '[extend]\nuseDefault = true\n[allowlist]\nregexes = [\"\"\"AKIA.*\"\"\"]\n' > .gitleaks.toml; printf 'x\n' > src/zz3.txt"
vrun 7
ck "the widening PR's findings scan still passes --config" grep -qx -- --config "$VS/gitleaks.argv"
ck "the findings scan uses the base's .gitleaks.toml, never the PR head's" cmp -s "$VS/gitleaks.config" <(git -C "$VR" show origin/main:.gitleaks.toml)
ck "…so the head's widened allowlist never reaches gitleaks" bash -c 'test -f "$1" && ! grep -q AKIA "$1"' _ "$VS/gitleaks.config"
# A base without .gitleaks.toml: gitleaks' built-in rules (no --config at all).
(cd "$VR" && git checkout -q main && git rm -q .gitleaks.toml && git commit -qm "no gitleaks config" && git push -q origin main)
vbranch builtin 'printf "x\n" > src/zz4.txt'
vrun 7
ck "a base without .gitleaks.toml: the findings scan runs the built-in rules" no grep -qx -- --config "$VS/gitleaks.argv"
```

- [ ] **Step 2: Run** `bash tests/governance/test_suppressions.sh; bash tests/governance/test_verifier_isolation.sh`. Expected: `FAIL: scripts/check-suppressions.sh missing` (exit 1). The isolation test FAILs at `…with the base's .gitleaks.toml` and at the widening-PR checks, and only because the template has no `.gitleaks.toml` yet (so the base passes no `--config`). `run-verifier.sh` does not change in this task: these checks pin its current base-ref behaviour (H15), and the red comes from the missing file, not from a missing feature. The `builtin` check passes before and after.
- [ ] **Step 3: Implement (intent).** Per Interfaces: `.gitleaks.toml`, and `floor.py` with its disposition reader (the `---` blocks, flat keys, inline lists, versions from the file name `<X.Y.Z[-pre]>-disposition.md`) and `suppressions` subcommand. The module docstring says it is the one home of the floor's rules (REQ-330/331/332/388). `check-suppressions.sh` runs `python3 "$ROOT/scripts/lib/specflow/floor.py" suppressions --root "${root:-$ROOT}" "$@"`. Then verify for real, once (local, about 1 s): `gitleaks git --no-banner --redact --log-level warn --ignore-gitleaks-allow --config .gitleaks.toml .` → exit 0. Record the output line.
- [ ] **Step 4: Run** both tests and the gates — green. `this repository passes its own suppression check` is green because the root run leaves `stacks/` out in the template source: the tauri overlay's still-uncited entries (`stacks/tauri/overlay/osv-scanner.toml:9-47`, `src-tauri/audit.toml:10-18`) are first checked by Task 8's per-pack-root loop, which goes red there before Task 8 cites them.
- [ ] **Step 5: Commit** — "feat(floor): .gitleaks.toml limited to three paths, every suppression cites an active SEC-NNN, the verifier's scan keeps the base's config (REQ-388)"

---

### Task 5: The security floor — `run-security-floor.sh`, section 5 of the gates, the summary, floor failures reported apart (REQ-330, REQ-360)

**Files:**
- Create `scripts/run-security-floor.sh`, `scripts/lib/specflow/floor.sh` and `tests/governance/test_security_floor.sh`.
- Modify:
  - `scripts/lib/specflow/floor.py` (`record`, `summarize`);
  - `scripts/run-quality-gates.sh` (a new §5 after `:93`, and the Summary at `:95-101`);
  - `tests/governance/lib/check.sh` (append `floor_stubs`);
  - `tests/governance/test_first_run.sh:12-20` (`gates()`);
  - `.gitignore` (append `.specflow/floor-summary.json`).

**Interfaces:** "Pinned tool invocations" (gitleaks, osv-scanner), "Floor lines", `floor.sh`, `floor.py record`/`summarize` and the summary, all under shared Interfaces. `run-security-floor.sh [--summary PATH]` runs with cwd = repository root, in this order:
1. **Not a git work tree:** a `FAIL floor gitleaks` line, exit 1.
2. **gitleaks.**
3. **osv-scanner (R3).** The root scan leaves out `stacks/` in the template source (no `.specflow.yml`/`.stack`, and `stacks/` tracked). Each `stacks/<s>/overlay` and `stacks/<s>/skeleton` with tracked lockfiles is scanned with `<dir>/osv-scanner.toml`, or the empty config, at scope `<dir>`.
4. **The stack script.** In an instance, `scripts/security-<stack>.sh` runs with `SPECFLOW_FLOOR_RECORD` exported. A configured stack whose script is absent or not executable is `FAIL floor security-<stack>.sh [.] (missing): …`.
5. **The summary:** `floor.py summarize`.

Exit 0 iff no `FAIL floor` line was printed.

Install lines:
- gitleaks: `bash scripts/install-pinned-tool.sh gitleaks --dest "$HOME/.local/bin"` (checksum-verified), and on Darwin also `or brew install gitleaks (Homebrew's version)`;
- osv-scanner: the same, with `osv-scanner`.

`run-quality-gates.sh`:
- §5 `SECTION "Security floor"` runs `bash scripts/run-security-floor.sh`, printing its output through and keeping the `FAIL floor` lines.
- The Summary prints `Gate failures: none` or `Gate failures (<n>):`, followed by the indented FAIL lines of §1–§4.
- Then `Floor failures: none` or `Floor failures (<n>) — advisories, a leak, a failed lookup or tool error, or a missing floor tool (see === Security floor ===):`, followed by the indented `FAIL floor …` lines. A `lookup failed` line is thereby never counted as an advisory.
- Then the existing last line: `All quality gates passed` (exit 0) or `One or more gates failed` (exit 1).

`floor_stubs DIR` in `check.sh`:

```bash
floor_stubs() {  # floor_stubs DIR — fake floor tools (P4). gitleaks, osv-scanner, cargo, npm in DIR/bin; pip_audit and bandit as
  # python modules in DIR/py (python3 -m …, with PYTHONPATH=DIR/py). Each appends its argv (one per line, then ---) to
  # DIR/<tool>.argv and exits STUB_<TOOL>_RC (default 0); STUB_<TOOL>_MISSING=1 makes it behave as absent (exit 127 /
  # "No module named"); STUB_<TOOL>_MSG is printed to stderr before exiting (a network error, say); --version prints the
  # pinned version; gitleaks records GITLEAKS_CONFIG[_TOML] to DIR/gitleaks.env; npm prints DIR/npm-audit.json (default:
  # no vulnerabilities).
  local d="$1" t; mkdir -p "$d/bin" "$d/py/pip_audit" "$d/py/bandit"
  for t in gitleaks osv-scanner cargo npm; do
    cat > "$d/bin/$t" <<'EOF'
#!/usr/bin/env bash
S="${STUB_DIR:?}"; me=$(basename "$0"); U=$(printf '%s' "$me" | tr 'a-z-' 'A-Z_')
m="STUB_${U}_MISSING"; [ -z "${!m:-}" ] || exit 127
case "$me $*" in
  "gitleaks version") echo 8.30.1; exit 0 ;;
  "osv-scanner --version") echo "osv-scanner version: 2.6.0"; exit 0 ;;
  "cargo audit --version") echo "cargo-audit-audit 0.22.2"; exit 0 ;;
  "npm --version") echo 11.6.0; exit 0 ;;
esac
{ printf '%s\n' "$@"; echo ---; } >> "$S/$me.argv"
[ "$me" != gitleaks ] || echo "${GITLEAKS_CONFIG-unset} ${GITLEAKS_CONFIG_TOML-unset}" > "$S/gitleaks.env"
[ "$me" != npm ] || cat "$S/npm-audit.json" 2>/dev/null || echo '{"vulnerabilities": {}}'
g="STUB_${U}_MSG"; [ -z "${!g:-}" ] || echo "${!g}" >&2
r="STUB_${U}_RC"; exit "${!r:-0}"
EOF
    chmod +x "$d/bin/$t"
  done
  for t in pip_audit bandit; do
    : > "$d/py/$t/__init__.py"
    cat > "$d/py/$t/__main__.py" <<'EOF'
import os, sys
me = os.path.basename(os.path.dirname(os.path.abspath(__file__)))
if os.environ.get("STUB_" + me.upper() + "_MISSING"):
    sys.exit(f"{sys.executable}: No module named {me}")
if sys.argv[1:] == ["--version"]:
    print({"pip_audit": "pip-audit 2.10.1", "bandit": "bandit 1.9.4"}[me]); sys.exit(0)
with open(os.path.join(os.environ["STUB_DIR"], me + ".argv"), "a") as f:
    f.write("\n".join(sys.argv[1:]) + "\n---\n")
if os.environ.get("STUB_" + me.upper() + "_MSG"):
    print(os.environ["STUB_" + me.upper() + "_MSG"], file=sys.stderr)
sys.exit(int(os.environ.get("STUB_" + me.upper() + "_RC", "0")))
EOF
  done
}
```

- [ ] **Step 1: Write the failing test** — `tests/governance/test_security_floor.sh`:

```bash
#!/usr/bin/env bash
# REQ-330: the security floor — gitleaks over the full history with the repository's .gitleaks.toml, osv-scanner over
# every tracked lockfile with one config, then the instance's security-<stack>.sh; a missing floor tool is a hard FAIL
# with an install hint (as for Dafny); a machine-readable summary for /security-review; SPECFLOW_FLOOR_OFFLINE=1 skips
# the advisory lookups loudly. REQ-360: run-quality-gates.sh reports floor failures apart from gate failures.
# Covers: REQ-330
# Covers: REQ-360
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
[[ -f "$ROOT/scripts/run-security-floor.sh" ]] || { fail "scripts/run-security-floor.sh missing"; finish test_security_floor; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
S="$W/stub"; floor_stubs "$S"
MIN="$W/min"; mkdir -p "$MIN"   # system tools only: the host's real gitleaks and osv-scanner cannot leak in
for t in bash sh env python3 git sed awk grep tr cat dirname basename uname mkdir rm cp mv ls head tail find sort wc date mktemp tee cut xargs; do
  p=$(command -v "$t" 2>/dev/null || true); if [[ "$p" == /* ]]; then ln -sf "$p" "$MIN/$t"; fi
done
R="$W/repo"; mkdir -p "$R/scripts/lib/specflow"
cp "$ROOT/scripts/run-security-floor.sh" "$ROOT/scripts/run-quality-gates.sh" "$R/scripts/"
cp "$ROOT"/scripts/lib/specflow/{config.py,floor.py,floor.sh} "$R/scripts/lib/specflow/"
cp "$ROOT/.gitleaks.toml" "$R/"; printf '.specflow/floor-summary.json\n' > "$R/.gitignore"
(cd "$R" && git init -q -b main && git add -A && git commit -qm base)
SUM="$R/.specflow/floor-summary.json"
fl() {  # fl [VAR=VALUE…] — the floor in $R with stub tools only; sets rc and out
  rm -f "$S"/*.argv; rc=0
  out=$(cd "$R" && PATH="$S/bin:$MIN" PYTHONPATH="$S/py" STUB_DIR="$S" env "$@" bash scripts/run-security-floor.sh 2>&1) || rc=$?
}
first() { awk '/^---$/{exit} {print}' "$S/$1.argv" 2>/dev/null || true; }
pair() { awk -v a="$1" -v b="$2" 'p == a && $0 == b {f = 1} {p = $0} END {exit !f}'; }

# 1. No tracked lockfile: gitleaks over the full history with the repository's config; osv-scanner a noted PASS.
fl
ck "clean repository, no lockfile: exit 0" [ "$rc" = 0 ]
g=$(first gitleaks)
ck "gitleaks git (full history), not dir" [ "$(head -1 <<<"$g")" = git ]
for f in --no-banner --redact --ignore-gitleaks-allow; do ck "gitleaks $f" grep -qx -- "$f" <<<"$g"; done
ck "gitleaks --config .gitleaks.toml (the repository's allowlist)" pair --config .gitleaks.toml <<<"$g"
ck "gitleaks scans the repository root (last argument .)" [ "$(tail -1 <<<"$g")" = . ]
for f in --baseline-path -b; do ck "gitleaks: no $f (the floor passes no baseline, R16)" no grep -qx -- "$f" <<<"$g"; done
ck "osv-scanner not run without a tracked lockfile, and the floor says so" \
  bash -c '[ ! -s "$1" ] && grep -q "^PASS floor osv-scanner \[\.\] .*no tracked lockfile" <<<"$2"' _ "$S/osv-scanner.argv" "$out"
ck "the summary is written" test -s "$SUM"
ck "summary: schema 1, online, HEAD, clean, gitleaks pass 8.30.1, osv-scanner not-applicable" python3 - "$SUM" "$(git -C "$R" rev-parse HEAD)" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert s["schema"] == 1 and s["mode"] == "online" and s["commit"] == sys.argv[2] and s["dirty"] is False, s
t = {r["tool"]: r for r in s["tools"]}
assert t["gitleaks"]["status"] == "pass" and t["gitleaks"]["version"] == "8.30.1" and t["gitleaks"]["exit"] == 0, t
assert t["osv-scanner"]["status"] == "not-applicable" and t["osv-scanner"]["exit"] is None, t
assert t["osv-scanner"]["result"] == "not run — no tracked lockfile", t
assert s["suppressions"] == [] and s["suppression_errors"] == [], s
PY
fl GITLEAKS_CONFIG=/nonexistent.toml GITLEAKS_CONFIG_TOML='title = "x"'
ck "gitleaks never sees GITLEAKS_CONFIG or GITLEAKS_CONFIG_TOML from the environment" [ "$(cat "$S/gitleaks.env")" = "unset unset" ]

# 2. Tracked lockfiles, one config for all; an untracked lockfile is not the product's.
(cd "$R" && mkdir -p sub loose && : > requirements.txt && : > sub/Cargo.lock && git add -A && git commit -qm locks && : > loose/package-lock.json)
fl
o=$(first osv-scanner)
ck "osv-scanner scan source, never -r" bash -c '[ "$(sed -n 1,2p <<<"$1" | tr "\n" " ")" = "scan source " ] && ! grep -qx -- -r <<<"$1"' _ "$o"
ck "…-L for exactly the tracked lockfiles" [ "$(awk 'p == "-L" {print} {p = $0}' <<<"$o" | LC_ALL=C sort | tr '\n' ' ')" = "requirements.txt sub/Cargo.lock " ]
ck "…one --config even without an osv-scanner.toml (per-directory configs never apply)" \
  bash -c 'c=$(awk "p == \"--config\" {print} {p = \$0}" <<<"$1"); [ -n "$c" ] && [ "$c" != osv-scanner.toml ]' _ "$o"
(cd "$R" && printf '# no ignores\n' > osv-scanner.toml && git add -A && git commit -qm cfg)
fl
ck "…--config osv-scanner.toml when the repository has one" pair --config osv-scanner.toml <<<"$(first osv-scanner)"
fl STUB_OSV_SCANNER_RC=1
ck "an advisory: exit 1, FAIL floor osv-scanner" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner" <<<"$2"' _ "$rc" "$out"
ck "…a findings line, never 'lookup failed'" bash -c 'grep -q "^FAIL floor osv-scanner.*findings" <<<"$1" && ! grep -q "lookup failed" <<<"$1"' _ "$out"
fl STUB_OSV_SCANNER_RC=128
ck "exit 128 with tracked lockfiles is a FAIL, never the 'no package sources' PASS" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner" <<<"$2"' _ "$rc" "$out"
ck "…reported as an error, not as findings" grep -q '^FAIL floor osv-scanner .*error, not findings' <<<"$out"
fl STUB_OSV_SCANNER_RC=127 STUB_OSV_SCANNER_MSG='failed to fetch: Post "https://api.osv.dev/v1/querybatch": dial tcp: lookup api.osv.dev: no such host'
ck "a network failure (exit 127, no such host): FAIL floor osv-scanner … lookup failed, with the rerun hint" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner .*lookup failed" <<<"$2" && grep -qF SPECFLOW_FLOOR_OFFLINE=1 <<<"$2" && ! grep -q "^FAIL floor osv-scanner.*findings" <<<"$2"' _ "$rc" "$out"
ck "…recorded as lookup-failed in the summary" python3 -c 'import json, sys
t = {r["tool"]: r for r in json.load(open(sys.argv[1]))["tools"]}; assert t["osv-scanner"]["status"] == "lookup-failed", t' "$SUM"
fl STUB_GITLEAKS_RC=1
ck "a leak: exit 1, FAIL floor gitleaks" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor gitleaks" <<<"$2"' _ "$rc" "$out"
ck "…recorded as fail, exit 1, in the summary" python3 -c 'import json, sys
t = {r["tool"]: r for r in json.load(open(sys.argv[1]))["tools"]}; assert t["gitleaks"]["status"] == "fail" and t["gitleaks"]["exit"] == 1, t' "$SUM"

# 3. A missing floor tool is a hard FAIL with an install hint, even offline (REQ-330: as for Dafny).
fl STUB_GITLEAKS_MISSING=1
ck "gitleaks missing: exit 1, FAIL floor gitleaks (missing), naming the checksum-verified installer and --doctor" bash -c \
  '[ "$1" = 1 ] && grep -q "^FAIL floor gitleaks \[\.\] (missing)" <<<"$2" && grep -qF "install-pinned-tool.sh gitleaks" <<<"$2" && grep -qF -- "--doctor" <<<"$2"' _ "$rc" "$out"
fl STUB_OSV_SCANNER_MISSING=1 SPECFLOW_FLOOR_OFFLINE=1
ck "osv-scanner missing is a FAIL even offline" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner.*(missing)" <<<"$2"' _ "$rc" "$out"

# 4. Offline (R2): every tool present; gitleaks (local) runs; advisory lookups skipped loudly and marked.
fl SPECFLOW_FLOOR_OFFLINE=1
ck "offline: exit 0, gitleaks ran, osv-scanner not invoked" bash -c '[ "$1" = 0 ] && [ -s "$2" ] && [ ! -s "$3" ]' _ "$rc" "$S/gitleaks.argv" "$S/osv-scanner.argv"
ck "offline: the SKIP line says it is not evidence" grep -q '^SKIP floor osv-scanner.*not valid evidence' <<<"$out"
ck "offline: summary mode offline, osv-scanner skipped-offline" python3 -c 'import json, sys
s = json.load(open(sys.argv[1])); t = {r["tool"]: r for r in s["tools"]}
assert s["mode"] == "offline" and t["osv-scanner"]["status"] == "skipped-offline", s' "$SUM"

# 5. Template source: the root scan leaves stacks/ out; each pack root is scanned with its own config.
(cd "$R" && mkdir -p stacks/tauri/overlay stacks/python/skeleton && : > stacks/tauri/overlay/package-lock.json \
  && printf '# pack config\n' > stacks/tauri/overlay/osv-scanner.toml && : > stacks/python/skeleton/requirements.txt && git add -A && git commit -qm packs)
fl
ck "template: three osv-scanner runs (root, python skeleton, tauri overlay)" [ "$(grep -cx -- --- "$S/osv-scanner.argv")" = 3 ]
ck "template: the root run names no stacks/ path" no grep -q '^stacks/' <<<"$(first osv-scanner)"
ck "template: the tauri overlay run uses the overlay's own osv-scanner.toml" grep -qx stacks/tauri/overlay/osv-scanner.toml "$S/osv-scanner.argv"
ck "template: a pack root's result carries its scope" grep -q '^PASS floor osv-scanner \[stacks/tauri/overlay\]' <<<"$out"

# 6. Instance: the stack's security script runs after the core floor and is recorded; a missing one is a FAIL.
(cd "$R" && git rm -rq stacks && printf 'stack: python\n' > .specflow.yml && git add -A && git commit -qm instance)
cat > "$R/scripts/security-python.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source scripts/lib/specflow/floor.sh
floor_tool --online pip-audit requirements.txt 'echo pip-audit 2.10.1' 'pip install --require-hashes -r requirements.txt' -- bash -c 'exit "${FAKE_RC:-0}"'
EOF
chmod +x "$R/scripts/security-python.sh"
fl
ck "instance: the stack script's tool is in the summary" python3 -c 'import json, sys
assert "pip-audit" in [r["tool"] for r in json.load(open(sys.argv[1]))["tools"]]' "$SUM"
fl FAKE_RC=1
ck "instance: the stack script's failure fails the floor" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit" <<<"$2"' _ "$rc" "$out"
chmod -x "$R/scripts/security-python.sh"; fl
ck "instance: a configured stack without an executable security script is a FAIL" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor security-python.sh" <<<"$2"' _ "$rc" "$out"
chmod +x "$R/scripts/security-python.sh"

# 7. REQ-360: the gates run the floor as its own section and list floor failures apart from gate failures.
qg() { rc=0; out=$(cd "$R" && PATH="$S/bin:$MIN" PYTHONPATH="$S/py" STUB_DIR="$S" env -u SPECFLOW_QG_RUNNING "$@" bash scripts/run-quality-gates.sh 2>&1) || rc=$?; }
qg STUB_OSV_SCANNER_RC=1
ck "gates: a '=== Security floor ===' section" grep -qx '=== Security floor ===' <<<"$out"
ck "gates: exit 1" [ "$rc" = 1 ]
sm=$(sed -n '/^=== Summary ===/,$p' <<<"$out")
ck "summary: the missing hook is listed under Gate failures" bash -c 'sed -n "/^Gate failures/,/^Floor failures/p" <<<"$1" | grep -q "FAIL scripts/quality-gates-python.sh"' _ "$sm"
ck "summary: the advisory is under Floor failures, and no floor line is under Gate failures" bash -c \
  'sed -n "/^Floor failures/,\$p" <<<"$1" | grep -q "FAIL floor osv-scanner" && ! sed -n "/^Gate failures/,/^Floor failures/p" <<<"$1" | grep -q "FAIL floor"' _ "$sm"
printf '#!/usr/bin/env bash\necho PASS lint\n' > "$R/scripts/quality-gates-python.sh"; chmod +x "$R/scripts/quality-gates-python.sh"
qg
ck "gates all green: 'Gate failures: none', 'Floor failures: none', 'All quality gates passed'" bash -c \
  '[ "$1" = 0 ] && grep -qx "Gate failures: none" <<<"$2" && grep -qx "Floor failures: none" <<<"$2" && grep -qx "All quality gates passed" <<<"$2"' _ "$rc" "$out"
ck "this repository's gates run the floor" grep -q 'run-security-floor.sh' "$ROOT/scripts/run-quality-gates.sh"
ck ".specflow/floor-summary.json is gitignored (a run leaves the tree clean)" git -C "$ROOT" check-ignore -q --no-index .specflow/floor-summary.json
ck "no workflow sets SPECFLOW_FLOOR_OFFLINE (CI evidence is always online)" no grep -rq SPECFLOW_FLOOR_OFFLINE "$ROOT/.github"
finish test_security_floor
```

Replace `tests/governance/test_first_run.sh:12-20` with:

```bash
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT; GATES_OUT=""
gates() {  # gates DIR LABEL — the instance's gates; on failure the summary keeps floor failures apart (REQ-360)
  local rc=0; GATES_OUT=$(cd "$1" && env -u SPECFLOW_QG_RUNNING -u SPECFLOW_FIRST_RUN bash scripts/run-quality-gates.sh 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then pass "$2: gates exit 0"; return 0; fi
  fail "$2: gates exit $rc"
  sed -n '/^=== Summary ===/,$p' <<<"$GATES_OUT" | sed 's/^/    /'
  tail -40 <<<"$GATES_OUT" | sed 's/^/    | /'
}
```

- [ ] **Step 2: Run** `bash tests/governance/test_security_floor.sh`. Expected: `FAIL: scripts/run-security-floor.sh missing`, exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces: `floor.sh`, `floor.py record`/`summarize`, `run-security-floor.sh`, §5 and the Summary, `floor_stubs`, the `gates()` change, and `.gitignore`.
- [ ] **Step 4: Run** the test, then the gates from the gates venv. The summary's `suppression_errors` is empty on the template, because the root scan leaves `stacks/` out (Task 4). The real floor now runs on the template: gitleaks (under 1 s) and osv-scanner over `scripts/requirements.txt` and the three pack roots (about 5 s, network). Expect `PASS floor` lines only, `Floor failures: none`, and a total well under 3 minutes; record it. Run `SPECFLOW_FLOOR_OFFLINE=1 bash scripts/run-quality-gates.sh` once too: green, with SKIP lines. Run `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=guided bash tests/governance/test_first_run.sh` (about 1 minute; the stack script is still the P4 stub): green, with the floor's gitleaks and osv-scanner lines in the instance's gates.
- [ ] **Step 5: Commit** — "feat(floor): run-security-floor.sh — gitleaks full history, osv-scanner on tracked lockfiles, stack script, summary — as gates section 5, floor failures listed apart (REQ-330, REQ-360)"

---

### Task 6: CI installs the floor — `ci.yml`, the first-run job, and every pack action; macOS Dafny pinned (REQ-330, REQ-303; H1, H12)

**Files:**
- Modify `.github/workflows/ci.yml` (gates `:14-37`, first-run `:48-63`) and `stacks/{python,tauri,flutter}/action.yml`; add `cargo_audit_version: 0.22.2` to `stacks/tauri/pack.yml`.
- Create `tests/governance/test_ci_floor.sh`.

**Interfaces** (describe steps by intent; every `uses:` is SHA-pinned per Task 3):
- **`ci.yml` gates:**
  - checkout with `fetch-depth: 0`;
  - an `actions/cache` step for `~/.cache/specflow-tools`, keyed on `runner.os` and `hashFiles('scripts/pinned-tools.yml')`;
  - a "Floor tools" step running `bash scripts/install-pinned-tool.sh gitleaks osv-scanner --dest "$HOME/.local/specflow-bin"` and appending that directory to `$GITHUB_PATH`.

  Both new steps carry `if: hashFiles('.github/actions/toolchain/action.yml') == ''`: in an instance, the toolchain action installs the tools instead.
- **`ci.yml` first-run** (template-only): the same cache and install steps; `pip install --require-hashes -r scripts/requirements.txt`, then `pip install --require-hashes -r stacks/python/skeleton/requirements.txt` (a python instance's floor tools).
- **Every pack action:**
  - the same cache and install steps (gitleaks and osv-scanner);
  - python: `pip install --require-hashes -r scripts/requirements.txt` and the existing root `requirements.txt` with `--require-hashes`;
  - tauri: an input `cargo_audit_version` defaulting to `0.22.2` (the pack pin); a cache of `~/.cargo/bin/cargo-audit` keyed on that version; `cargo install cargo-audit --locked --version <input>` on a cache miss;
  - tauri and flutter: the Dafny placeholder (`:42-46`, `:57-61`) becomes `bash scripts/install-pinned-tool.sh dafny --dest "$RUNNER_TEMP/dafny-dist"`, adding `$RUNNER_TEMP/dafny-dist/dafny` to `$GITHUB_PATH`, under the same `hashFiles('verification/**/*.dfy') != ''` condition;
  - python: the placeholder is removed, because `ci.yml`'s Linux step installs Dafny.
- **`app-stacks.yml`:** unchanged beyond Task 3. Its jobs use the pack actions, which now carry the floor tools.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_ci_floor.sh`:

```bash
#!/usr/bin/env bash
# REQ-330 (H1, H12): CI installs gitleaks and osv-scanner from the checksum-verified assets (cached) and runs the floor on
# the full history; every pack action installs its pinned toolchain and the floor tools (REQ-303), cargo-audit with
# cargo install --locked --version, Python tools from hash-pinned lockfiles; app stacks get a checksum-pinned macOS
# Dafny. REQ-360: the first-run jobs can run an instance's floor.
# Covers: REQ-330
# Covers: REQ-303
# Covers: REQ-360
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CI=.github/workflows/ci.yml
job() { awk -v j="  $1:" '$0 == j {f = 1; print; next} f && /^  [A-Za-z#]/ {exit} f' "$CI"; }
gates=$(job gates)
ck "ci.yml gates: checkout with fetch-depth: 0 (gitleaks scans the full history)" grep -qE 'fetch-depth:[[:space:]]*0' <<<"$gates"
ck "ci.yml gates: installs gitleaks and osv-scanner with install-pinned-tool.sh" grep -qE 'install-pinned-tool\.sh.*gitleaks.*osv-scanner' <<<"$gates"
ck "ci.yml gates: …only when no pack toolchain action provides them" grep -qF "hashFiles('.github/actions/toolchain/action.yml') == ''" <<<"$gates"
ck "ci.yml gates: the asset cache is keyed on scripts/pinned-tools.yml" grep -qF 'pinned-tools.yml' <<<"$gates"
if ! instance; then
  fr=$(job first-run)
  ck "first-run job: installs the floor tools" grep -qF 'install-pinned-tool.sh' <<<"$fr"
  ck "first-run job: installs the python instance lockfile (pip-audit, bandit) with --require-hashes" grep -qF 'pip install --require-hashes -r stacks/python/skeleton/requirements.txt' <<<"$fr"
  acts="stacks/python/action.yml stacks/tauri/action.yml stacks/flutter/action.yml"
else
  acts=".github/actions/toolchain/action.yml"
fi
for a in $acts; do
  [[ -f "$a" ]] || continue
  ck "$a: installs gitleaks and osv-scanner from the pinned, checksum-verified assets" grep -qE 'install-pinned-tool\.sh.*gitleaks.*osv-scanner' "$a"
  ck "$a: no 'in P4' placeholder left" no grep -q 'in P4' "$a"
  ck "$a: never turns the floor offline" no grep -q SPECFLOW_FLOOR_OFFLINE "$a"
done
if ! instance; then
  pin=$(python3 scripts/lib/specflow/config.py --file stacks/tauri/pack.yml get cargo_audit_version 2>/dev/null || true)
  ck "tauri pack.yml pins cargo_audit_version ($pin)" [ -n "$pin" ]
  ck "tauri action: cargo install cargo-audit --locked --version, defaulting to the pack pin" \
    bash -c 'grep -qF "cargo install cargo-audit --locked --version" "$1" && grep -qF "$2" "$1"' _ stacks/tauri/action.yml "${pin:-none}"
  ck "tauri action: the cargo-audit binary is cached" bash -c 'grep -q "\.cargo/bin/cargo-audit" "$1" && grep -q "actions/cache@" "$1"' _ stacks/tauri/action.yml
  ck "python action: both lockfiles installed with --require-hashes" \
    bash -c 'grep -qF "pip install --require-hashes -r scripts/requirements.txt" "$1" && grep -qF "pip install --require-hashes -r requirements.txt" "$1"' _ stacks/python/action.yml
  for s in tauri flutter; do
    ck "$s action: Dafny from the checksum-pinned macOS asset when proofs exist" \
      bash -c 'grep -qF "install-pinned-tool.sh dafny" "$1" && grep -qF "hashFiles('"'"'verification/**/*.dfy'"'"')" "$1"' _ "stacks/$s/action.yml"
  done
  ck "python action: no Dafny step (ci.yml's Linux step installs it)" no grep -qi dafny stacks/python/action.yml
  ck "app-stacks.yml: its jobs use the pack actions (which carry the floor tools)" \
    bash -c 'grep -qF "uses: ./stacks/tauri" "$1" && grep -qF "uses: ./stacks/flutter" "$1"' _ .github/workflows/app-stacks.yml
fi
finish test_ci_floor
```

- [ ] **Step 2: Run** `bash tests/governance/test_ci_floor.sh`. Expected: the ci.yml gates FAILs (fetch-depth, install, condition, cache), the first-run FAILs, one pair of FAILs per pack action (install, `in P4` placeholder), and the tauri, python and Dafny FAILs. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. For `ci.yml`, the first-run job keeps `SPECFLOW_FIRST_RUN`/`FIRST_RUN_CASES` as they are.
- [ ] **Step 4: Run** the test, `actionlint .github/workflows/*.yml` (which also checks `run:` scripts with shellcheck) and `bash tests/governance/test_workflow_health.sh` (its `actionlint` step includes `app-stacks.yml`) — green. Run the gates. CI minutes are measured on the IMPLEMENT PR (Task 15).
- [ ] **Step 5: Commit** — "ci: install the floor tools from pinned assets in ci.yml and every pack action, cargo-audit locked, checksum-pinned macOS Dafny (REQ-330, REQ-303)"

---

### Task 7: Real `security.sh` per stack (REQ-331; REQ-303 `pack.yml` keys; H2, H16)

**Files:**
- Rewrite `stacks/{python,tauri,flutter}/security.sh`.
- Modify `scripts/lib/specflow/floor.py` (`ignores`, per the Ruling on expiry), `stacks/{python,tauri,flutter}/pack.yml` (`floor_tools:`, and python's `lockfiles: [requirements.txt]`), `tests/governance/test_stack_packs.sh:26-27`, and `tests/governance/test_first_run.sh` (remove `floor()` at `:21-27`; `:86-92`, `:123-125`; the python cases).
- Create `tests/governance/test_stack_security.sh`.

**Interfaces:** "Pinned tool invocations" (pip-audit, bandit, cargo-audit, npm audit, osv-scanner flutter) under shared Interfaces. Each script has cwd = instance root; it sources `scripts/lib/specflow/floor.sh` and reads its pack through `python3 scripts/lib/specflow/config.py --file .specflow/pack.yml`. It exits 0 iff every one of its floor lines is PASS or SKIP. `pack.yml`: python `floor_tools: [pip-audit, bandit]`, tauri `[cargo-audit, npm-audit]`, flutter `[osv-scanner]`. Every ignore list a script passes to a tool comes from `python3 scripts/lib/specflow/floor.py ignores --root . --source osv|cargo` (only the ids still in date; Global Constraints, the Ruling on expiry), never from reading the files itself.

`security-python.sh`:
- The lockfile is `requirements.txt` when present. Otherwise it is `scripts/requirements.txt`, after printing `note: no product lockfile (requirements.txt); auditing the factory tooling lockfile scripts/requirements.txt` (R5).
- bandit runs once per existing `source_roots` entry.
- The install hint is `pip install --require-hashes -r requirements.txt`.

`security-tauri.sh`:
- Ignores come from `src-tauri/audit.toml` via `floor.py ignores --source cargo` (R4).
- The npm filter (R6) takes its ids from `floor.py ignores --source osv` and prints the unignored GHSA ids in the FAIL line. npm's own `error` object fails closed: `lookup failed` when its code or summary matches the network-error pattern (`ENOTFOUND`, `EAI_AGAIN`, …), otherwise `error, not findings`.
- cargo-audit's install hint is `cargo install cargo-audit --locked --version <pack.yml cargo_audit_version>`.

`security-flutter.sh`: osv-scanner only (R7).

- [ ] **Step 1: Write the failing tests.** `tests/governance/test_stack_security.sh`:

```bash
#!/usr/bin/env bash
# REQ-331: each pack's security.sh runs the pinned real CLIs and fails on any finding its ignore file does not list;
# thresholds only where the tool has them (bandit, npm). REQ-303: packs declare floor_tools and lockfiles.
# Template source only (init removes stacks/); stub tools, no toolchain, no network.
# Covers: REQ-331
# Covers: REQ-303
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — init removed stacks/"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
S="$W/stub"; floor_stubs "$S"; CFG="$ROOT/scripts/lib/specflow/config.py"
for s in python tauri flutter; do
  ck "$s: security.sh is no longer the P4 stub" no grep -q 'security floor lands in P4' "$ROOT/stacks/$s/security.sh"
  ck "$s: security.sh sources the floor helper" grep -q 'scripts/lib/specflow/floor.sh' "$ROOT/stacks/$s/security.sh"
  ck "$s: pack.yml declares floor_tools" python3 "$CFG" --file "$ROOT/stacks/$s/pack.yml" getlist floor_tools
  ck "$s: pack.yml declares lockfiles" python3 "$CFG" --file "$ROOT/stacks/$s/pack.yml" getlist lockfiles
done
mkinst() {  # mkinst STACK — a stub instance: the floor helpers, the pack's pack.yml and security script; sets I
  I="$W/$1"; rm -rf "$I"; mkdir -p "$I/scripts/lib/specflow" "$I/.specflow"
  cp "$ROOT"/scripts/lib/specflow/{config.py,floor.py,floor.sh} "$I/scripts/lib/specflow/"
  cp "$ROOT/stacks/$1/pack.yml" "$I/.specflow/pack.yml"; cp "$ROOT/stacks/$1/security.sh" "$I/scripts/security-$1.sh"
  printf 'stack: %s\n' "$1" > "$I/.specflow.yml"
}
sec() {  # sec STACK [VAR=VALUE…] — the installed security script, stubs first; sets rc and out
  local s="$1"; shift; rm -f "$S"/*.argv; rc=0
  out=$(cd "$W/$s" && PATH="$S/bin:$PATH" PYTHONPATH="$S/py" STUB_DIR="$S" env "$@" bash "scripts/security-$s.sh" 2>&1) || rc=$?
}
argv() { awk '/^---$/{exit} {print}' "$S/$1.argv" 2>/dev/null || true; }
pair() { awk -v a="$1" -v b="$2" 'p == a && $0 == b {f = 1} {p = $0} END {exit !f}'; }
h64() { printf "$1%.0s" $(seq 64); }

# --- python: pip-audit on the product lockfile (ignores from osv-scanner.toml), bandit per source root ---
mkinst python; mkdir -p "$I/src/app"; printf 'x = 1\n' > "$I/src/app/__init__.py"
printf 'pytest==9.1.1 \\\n    --hash=sha256:%s\n' "$(h64 a)" > "$I/requirements.txt"
printf '[[IgnoredVulns]]\nid = "PYSEC-2099-1"\nignoreUntil = 2099-01-01\nreason = "SEC-001: fixture"\n\n[[IgnoredVulns]]\nid = "PYSEC-2000-1"\nignoreUntil = 2000-01-01\nreason = "SEC-001: fixture, expired"\n' > "$I/osv-scanner.toml"
sec python
ck "python: clean, exit 0" [ "$rc" = 0 ]
pa=$(argv pip_audit)
ck "python: pip-audit -r requirements.txt" pair -r requirements.txt <<<"$pa"
for f in --strict --disable-pip; do ck "python: pip-audit $f" grep -qx -- "$f" <<<"$pa"; done
ck "python: pip-audit --ignore-vuln from osv-scanner.toml" pair --ignore-vuln PYSEC-2099-1 <<<"$pa"
ck "python: an IgnoredVulns whose ignoreUntil has passed is not ignored (every tool expires it as osv-scanner does)" no grep -qx PYSEC-2000-1 <<<"$pa"
ck "…and the floor says so" grep -q 'PYSEC-2000-1.*expired' <<<"$out"
ba=$(argv bandit)
ck "python: bandit -r src" pair -r src <<<"$ba"
ck "python: bandit --severity-level high --confidence-level medium" bash -c 'awk "p == \"--severity-level\" && \$0 == \"high\" {a = 1} p == \"--confidence-level\" && \$0 == \"medium\" {b = 1} {p = \$0} END {exit !(a && b)}" <<<"$1"' _ "$ba"
for f in -b --baseline -s --skip -c --configfile --ini; do ck "python: bandit gets no $f (no baseline, no skips, no config; R16)" no grep -qx -- "$f" <<<"$ba"; done
ck "python: a floor line per tool, with scope and version" \
  bash -c 'grep -q "^PASS floor pip-audit \[requirements.txt\] (2.10.1, exit 0)" <<<"$1" && grep -q "^PASS floor bandit \[src\] (1.9.4, exit 0)" <<<"$1"' _ "$out"
sec python STUB_PIP_AUDIT_RC=1
ck "python: a pip-audit finding fails (exit 1, FAIL floor pip-audit)" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit" <<<"$2"' _ "$rc" "$out"
sec python STUB_BANDIT_RC=1
ck "python: a bandit finding fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor bandit" <<<"$2"' _ "$rc" "$out"
sec python STUB_PIP_AUDIT_RC=1 STUB_PIP_AUDIT_MSG="requests.exceptions.ConnectionError: HTTPSConnectionPool(host='pypi.org', port=443): Max retries exceeded"
ck "python: a pip-audit connection error is 'lookup failed', never findings" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit .*lookup failed" <<<"$2" && ! grep -q "^FAIL floor pip-audit.*findings" <<<"$2"' _ "$rc" "$out"
sec python STUB_PIP_AUDIT_MISSING=1
ck "python: pip-audit missing is a hard FAIL naming the hash-pinned install" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit.*(missing)" <<<"$2" && grep -qF "pip install --require-hashes -r requirements.txt" <<<"$2"' _ "$rc" "$out"
sec python SPECFLOW_FLOOR_OFFLINE=1
ck "python offline: pip-audit skipped loudly, bandit (local) still runs" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP floor pip-audit" <<<"$2" && grep -q "^PASS floor bandit" <<<"$2"' _ "$rc" "$out"
ck "python offline: pip-audit never invoked" [ ! -s "$S/pip_audit.argv" ]
rm "$I/requirements.txt"; mkdir -p "$I/scripts"; printf 'pytest==9.1.1 \\\n    --hash=sha256:%s\n' "$(h64 b)" > "$I/scripts/requirements.txt"
sec python
ck "python: no product lockfile, so scripts/requirements.txt is audited with a printed note (H16)" \
  bash -c '[ "$1" = 0 ] && grep -q "no product lockfile" <<<"$2"' _ "$rc" "$out"
ck "…pip-audit -r scripts/requirements.txt" pair -r scripts/requirements.txt <<<"$(argv pip_audit)"

# --- tauri: cargo audit with audit.toml's ignores as --ignore; npm audit filtered by osv-scanner.toml ---
mkinst tauri; mkdir -p "$I/src-tauri"; : > "$I/src-tauri/Cargo.lock"; echo '{}' > "$I/package-lock.json"
printf '[advisories]\nignore = [\n  "RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01\n  "RUSTSEC-2000-0001",  # SEC-001 reason: fixture, expired; ignoreUntil: 2000-01-01\n]\n' > "$I/src-tauri/audit.toml"
printf '[[IgnoredVulns]]\nid = "GHSA-aaaa-bbbb-cccc"\nignoreUntil = 2099-01-01\nreason = "SEC-002: fixture"\n' > "$I/osv-scanner.toml"
sec tauri
ck "tauri: clean, exit 0" [ "$rc" = 0 ]
ca=$(argv cargo)
ck "tauri: cargo audit" [ "$(head -1 <<<"$ca")" = audit ]
ck "tauri: --deny warnings" pair --deny warnings <<<"$ca"
ck "tauri: --file src-tauri/Cargo.lock" pair --file src-tauri/Cargo.lock <<<"$ca"
ck "tauri: audit.toml's entry passed as --ignore (cargo-audit never reads src-tauri/audit.toml itself, R4)" pair --ignore RUSTSEC-2099-0001 <<<"$ca"
ck "tauri: an entry whose ignoreUntil has passed is not passed (the same expiry as osv-scanner's)" no grep -qx RUSTSEC-2000-0001 <<<"$ca"
na=$(argv npm)
ck "tauri: npm audit --audit-level=high --json" bash -c 'grep -qx audit <<<"$1" && grep -qx -- --audit-level=high <<<"$1" && grep -qx -- --json <<<"$1"' _ "$na"
npmv() { python3 -c 'import json, sys
print(json.dumps({"vulnerabilities": {"pkg": {"severity": sys.argv[1], "via": [{"source": 1, "severity": sys.argv[1], "url": "https://github.com/advisories/" + sys.argv[2]}]}}}))' "$1" "$2" > "$S/npm-audit.json"; }
npmv high GHSA-xxxx-yyyy-zzzz; sec tauri STUB_NPM_RC=1
ck "tauri: a high npm advisory not in osv-scanner.toml fails, naming it" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor npm-audit" <<<"$2" && grep -q GHSA-xxxx-yyyy-zzzz <<<"$2"' _ "$rc" "$out"
npmv high GHSA-aaaa-bbbb-cccc; sec tauri STUB_NPM_RC=1
ck "tauri: a high npm advisory listed in osv-scanner.toml passes" bash -c '[ "$1" = 0 ] && grep -q "^PASS floor npm-audit" <<<"$2"' _ "$rc" "$out"
npmv moderate GHSA-xxxx-yyyy-zzzz; sec tauri
ck "tauri: a moderate npm advisory is below the threshold" [ "$rc" = 0 ]
echo '{"error": {"code": "ENOTFOUND", "summary": "registry unreachable"}}' > "$S/npm-audit.json"; sec tauri STUB_NPM_RC=1
ck "tauri: npm audit's own network error fails closed as 'lookup failed', not findings" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor npm-audit .*lookup failed" <<<"$2"' _ "$rc" "$out"
rm -f "$S/npm-audit.json"; sec tauri STUB_CARGO_RC=1
ck "tauri: a cargo-audit finding fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor cargo-audit" <<<"$2"' _ "$rc" "$out"
sec tauri STUB_CARGO_MISSING=1
ck "tauri: cargo-audit missing is a hard FAIL naming the pinned, locked install" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor cargo-audit.*(missing)" <<<"$2" && grep -qF "cargo install cargo-audit --locked --version" <<<"$2"' _ "$rc" "$out"
sec tauri SPECFLOW_FLOOR_OFFLINE=1
ck "tauri offline: both advisory lookups skipped loudly, exit 0" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP floor cargo-audit" <<<"$2" && grep -q "^SKIP floor npm-audit" <<<"$2"' _ "$rc" "$out"

# --- flutter: osv-scanner on pubspec.lock with the instance's osv-scanner.toml; dart analyze stays in the gates hook ---
mkinst flutter; : > "$I/pubspec.lock"; printf '# no ignores\n' > "$I/osv-scanner.toml"
sec flutter
ck "flutter: clean, exit 0" [ "$rc" = 0 ]
oa=$(argv osv-scanner)
ck "flutter: osv-scanner scan source --config osv-scanner.toml -L pubspec.lock" \
  bash -c '[ "$(sed -n 1,2p <<<"$1" | tr "\n" " ")" = "scan source " ] && grep -qx -- --config <<<"$1" && grep -qx osv-scanner.toml <<<"$1" && grep -qx pubspec.lock <<<"$1"' _ "$oa"
sec flutter STUB_OSV_SCANNER_RC=1
ck "flutter: an advisory fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner" <<<"$2"' _ "$rc" "$out"
ck "flutter: dart analyze --fatal-infos stays in the gates hook (R7)" grep -q 'dart analyze --fatal-infos' "$ROOT/stacks/flutter/gates.sh"
ck "flutter: security.sh does not run dart analyze a second time" no grep -q 'dart analyze' "$ROOT/stacks/flutter/security.sh"
finish test_stack_security
```

In `tests/governance/test_stack_packs.sh`, delete `:26-27` (the stub sentinel; `test_stack_security.sh` owns `security.sh` now). In `tests/governance/test_first_run.sh`:
- delete `floor()` (`:21-27`);
- after each python `gates` call in the guided and engineer cases, add `ck "<label>: the floor ran pip-audit and bandit" bash -c 'grep -q "^PASS floor pip-audit" <<<"$1" && grep -q "^PASS floor bandit" <<<"$1"' _ "$GATES_OUT"`;
- replace `:86-92` with `ck "tauri: the floor ran cargo-audit and npm audit inside the gates" bash -c 'grep -q "^PASS floor cargo-audit" <<<"$1" && grep -q "^PASS floor npm-audit" <<<"$1"' _ "$GATES_OUT"`;
- replace `:123-125` with `ck "flutter: the floor ran osv-scanner on pubspec.lock inside the gates" grep -q '^PASS floor osv-scanner \[pubspec.lock\]' <<<"$GATES_OUT"`.

- [ ] **Step 2: Run** `bash tests/governance/test_stack_security.sh`. Expected: the `no longer the P4 stub`, `sources the floor helper` and `floor_tools`/`lockfiles` FAILs (python has no `lockfiles` yet), then the stubs' output checks FAIL (the stub prints `security floor lands in P4`). Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces, including `floor.py ignores`.
- [ ] **Step 4: Run** the test and the gates, then `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="guided engineer" bash tests/governance/test_first_run.sh` from the gates venv with the skeleton lockfile installed (network; about 2 minutes). Both are green with `PASS floor pip-audit [requirements.txt]` and `PASS floor bandit [src]`.
- [ ] **Step 5: Commit** — "feat(floor): real security.sh per stack — pip-audit and bandit, cargo-audit and npm audit, osv-scanner on pubspec.lock (REQ-331, REQ-303)"

---

### Task 8: The tauri skeleton's suppressions cite `SEC-001`–`SEC-003` from a pack-shipped disposition (REQ-388, REQ-331; H4, R12)

**Opt-in verification:** `FIRST_RUN_CASES=packfloor`, about 15 s of network. The full tauri first-run takes about 15 minutes, as P1b measured.

**Files:**
- Modify `stacks/tauri/overlay/src-tauri/audit.toml` and `stacks/tauri/overlay/osv-scanner.toml`.
- Create `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md` and `…/0.0.0-skeleton-disposition.md`.
- Modify `tests/governance/test_stack_packs.sh` (`:289-310`, and new checks after `:288`), `tests/governance/test_suppressions.sh` (pack roots, above `finish`) and `tests/governance/test_first_run.sh` (a `packfloor` case, `:48` defaults, and a tauri summary check).

**Interfaces:**
- `audit.toml` entries become `"RUSTSEC-…",  # SEC-00N reason: …; ignoreUntil: 2026-12-24`.
- Every `[[IgnoredVulns]]` `reason` starts with `SEC-00N: `.
- Both headers keep the enumeration line, with its tool version, date and lockfile sha256. They add: "Each entry cites a SEC-NNN in docs/security/0.0.0-skeleton-disposition.md, which init copies into every tauri instance (REQ-388); the instance's first /security-review carries them forward."
- The disposition has three entries, as in R12: owner `apingali`, expiry `2026-12-24`, a rationale of at least 10 characters, and `suppresses:` listing exactly the eight ids between them.
- The review has `## Summary` and `## Findings` with three blocks (`id`, `severity`, `cite` with the advisory ids and a CWE, `affects: [src-tauri/Cargo.lock:<line>]`) in the current `/security-review` format. P3 migrates them to the CVSS block schema. It has **no `## Tools run` section yet**: `floor.py render` does not exist until Task 11, whose Step 3 renders the section from a real floor run and whose `test_security_review.sh` is the first test to check the pack-shipped review (fresh-eyes findings 3 and 12, option b).

- [ ] **Step 1: Write the failing tests.** In `tests/governance/test_stack_packs.sh`:
  - in the audit.toml check (`:295-297`), replace the line regex with `r"# SEC-\d{3} reason: .+; ignoreUntil: \d{4}-\d{2}-\d{2}\s*$"`;
  - in both osv-scanner checks (`:306-307`, `:435-436`), add `assert re.match(r"SEC-\d{3}: ", v["reason"]), v`;
  - after `:288`, add:

```bash
SD="$TO/docs/security"
ck "tauri: the pack ships the skeleton's review and disposition (the SEC-NNN its suppressions cite, REQ-388)" test -f "$SD/0.0.0-skeleton-review.md" -a -f "$SD/0.0.0-skeleton-disposition.md"
ck "tauri: every suppressed advisory is listed by exactly one skeleton disposition entry" python3 - "$TO" <<'PY'
import pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1])
ids = set(tomllib.loads((o / "src-tauri/audit.toml").read_text())["advisories"]["ignore"])
ids |= {v["id"] for v in tomllib.loads((o / "osv-scanner.toml").read_text()).get("IgnoredVulns", [])}
listed = []
for block in re.findall(r"^---\n(.*?)\n---$", (o / "docs/security/0.0.0-skeleton-disposition.md").read_text(), re.M | re.S):
    m = re.search(r"^suppresses:\s*\[(.*)\]\s*$", block, re.M)
    if m:
        listed += [x.strip() for x in m.group(1).split(",") if x.strip()]
assert sorted(listed) == sorted(ids), (sorted(listed), sorted(ids))
PY
ck "tauri: the scaffolded instance receives the skeleton disposition" test -f "${A:-/nonexistent}/docs/security/0.0.0-skeleton-disposition.md"
```

In `tests/governance/test_suppressions.sh`, above `finish`:

```bash
# H4 (REQ-388): each pack root's suppressions cite a SEC-NNN its own shipped disposition defines (template source only).
if ! instance; then
  shopt -s nullglob
  for r in "$ROOT"/stacks/*/overlay "$ROOT"/stacks/*/skeleton; do ck "${r#$ROOT/}: suppressions cite the pack's own active SEC-NNN" bash "$CS" --root "$r"; done
  shopt -u nullglob
fi
```

In `tests/governance/test_first_run.sh`:
- add a case before `*)`:

```bash
    packfloor)   # opt-in, network (about 15 s): the real floor tools on every pack's shipped lockfiles and ignore files
      miss=""; for t in cargo-audit osv-scanner npm pip-audit; do command -v "$t" >/dev/null 2>&1 || miss="$miss $t"; done
      if [[ -n "$miss" ]]; then fail "packfloor: missing$miss (bash scripts/init-project.sh --doctor --stack tauri)"; else
        TO="$ROOT/stacks/tauri/overlay"; P="$WORK/packfloor"; mkdir -p "$P"; cp -R "$TO/src-tauri" "$TO/package.json" "$TO/package-lock.json" "$P/"
        ign=$(python3 -c 'import sys, tomllib; print(" ".join("--ignore " + i for i in tomllib.load(open(sys.argv[1], "rb"))["advisories"]["ignore"]))' "$TO/src-tauri/audit.toml")
        ck "packfloor: cargo audit --deny warnings on the tauri Cargo.lock with its SEC-cited ignores" bash -c "cd '$P' && cargo audit --deny warnings --file src-tauri/Cargo.lock $ign"
        ck "packfloor: without them cargo audit still finds the advisories (the ignores are live, not stale)" no bash -c "cd '$P' && cargo audit --deny warnings --file src-tauri/Cargo.lock"
        ck "packfloor: osv-scanner on the tauri lockfiles with the overlay config" osv-scanner scan source --config "$TO/osv-scanner.toml" -L "$TO/package-lock.json" -L "$TO/src-tauri/Cargo.lock"
        ck "packfloor: npm audit --audit-level=high on the tauri lockfile" bash -c "cd '$P' && npm audit --audit-level=high"
        ck "packfloor: osv-scanner on the flutter pubspec.lock" osv-scanner scan source --config "$ROOT/stacks/flutter/overlay/osv-scanner.toml" -L "$ROOT/stacks/flutter/overlay/pubspec.lock"
        ck "packfloor: pip-audit --strict on the python skeleton lockfile" pip-audit -r "$ROOT/stacks/python/skeleton/requirements.txt" --strict --disable-pip --progress-spinner off
      fi ;;
```

- after `:48`, add: `if [[ -z "${FIRST_RUN_CASES:-}" ]] && command -v cargo-audit >/dev/null 2>&1 && command -v osv-scanner >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v pip-audit >/dev/null 2>&1; then DEFAULT_CASES="$DEFAULT_CASES packfloor"; fi`;
- in the tauri case, after `gates`, add `ck "tauri: the floor summary lists the skeleton's suppressions with SEC-001..003" python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); assert sorted({x["sec"] for x in s["suppressions"]}) == ["SEC-001", "SEC-002", "SEC-003"] and not s["suppression_errors"], s' "$D/.specflow/floor-summary.json"`.
- [ ] **Step 2: Run** `bash tests/governance/test_stack_packs.sh; bash tests/governance/test_suppressions.sh`. Expected: the `# SEC-\d{3} reason` and `SEC-\d{3}: ` assertion FAILs, the skeleton review/disposition FAILs, and `FAIL: stacks/tauri/overlay: suppressions cite the pack's own active SEC-NNN`. Both exit 1.
- [ ] **Step 3: Implement (intent).** Edit the two ignore files, write the disposition, and write the review's `## Summary` and three findings (no `## Tools run`; Task 11 adds it). Then run `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=packfloor bash tests/governance/test_first_run.sh` (network, about 15 s) — green.
- [ ] **Step 4: Run** both tests and the gates — green. If the `tauri` case is ready (`--doctor` is clean), run it too: `FIRST_RUN_CASES=tauri` (about 15 minutes). Record the time.
- [ ] **Step 5: Commit** — "feat(tauri): skeleton suppressions cite SEC-001..003 from a pack-shipped skeleton review and disposition (REQ-388, REQ-331)"

---

### Task 9: `--doctor` lists the floor tools; README Prerequisites (REQ-330, REQ-303; H6, R1)

**Files:** modify `scripts/init-project.sh:147-149` (and the python block `:172-186`); `stacks/python/pack.yml` and `stacks/tauri/pack.yml` (`prereqs:`, plus `check_*`/`install_*` keys); `README.md` (`:228-243`, the macOS block `:245-257`, the Ubuntu block `:262-285`, `### Tauri` at `:296`); `tests/governance/test_init_doctor.sh`; `tests/governance/test_onboarding_surface.sh`.

**Interfaces:**
- **Core checks** (every stack): `check_present gitleaks "gitleaks version" …` and `check_present osv-scanner "osv-scanner --version" …`, with install lines from R1. On macOS the line is `bash scripts/install-pinned-tool.sh gitleaks --dest "$HOME/.local/bin" (checksum-verified; put ~/.local/bin on PATH) — or: brew install gitleaks`. Linux drops the brew part.
- **python pack:**
  - `prereqs: [build, pip_audit, bandit]`;
  - `check_pip_audit: python3 -m pip_audit --version`;
  - `check_bandit: python3 -m bandit --version`;
  - install lines for both OSes: `pip install --require-hashes -r requirements.txt` — stack-neutral, because an instance prints it and `test_init_doctor.sh:25-27` asserts that instance doctor output names no `stacks/` path (with pip-audit or bandit missing — CI's `gates` job and the gates venv install only `scripts/requirements.txt` — a `stacks/…` hint would break that check). The template-source variant (`stacks/python/skeleton/requirements.txt`) lives only in the README's Prerequisites prose, which no instance prints. No `install_*` value in any pack names a `stacks/` path.
- **tauri pack:**
  - `prereqs` gains `cargo_audit`;
  - `check_cargo_audit: cargo audit --version`;
  - `install_macos_cargo_audit: cargo install cargo-audit --locked --version 0.22.2`;
  - `install_linux_cargo_audit` is the pack's existing "not supported" sentence.
- **README Prerequisites:**
  - a bullet for osv-scanner (≥ 2.6.0, the floor's advisory scan), next to gitleaks, which is now a prerequisite for the floor as well as the verifier;
  - the installer line, with Homebrew's version-only alternative on macOS;
  - one sentence that the floor queries advisory databases on every gates run and that `SPECFLOW_FLOOR_OFFLINE=1` skips those lookups for offline work (not accepted as evidence);
  - one sentence that pip-audit and bandit come from a python instance's `requirements.txt`, which in the template source is `stacks/python/skeleton/requirements.txt`;
  - the Ubuntu block uses the installer instead of `wget`, keeping the `8.30.1` and `8.19` mentions that P2's test pins;
  - `### Tauri` gains `cargo install cargo-audit --locked --version 0.22.2`.

- [ ] **Step 1: Write the failing tests.** In `tests/governance/test_init_doctor.sh`, after the `for t in gh claude` line (`:18`):

```bash
for t in gitleaks osv-scanner; do ck "MISSING $t: the checksum-verified installer (a floor tool on every stack, REQ-330)" grep -qE "^MISSING $t: .*install-pinned-tool\.sh $t" <<<"$out"; done
ck "python doctor checks the python floor tools (pip-audit, bandit)" bash -c 'grep -qE "^(ok +|MISSING )pip_audit" <<<"$1" && grep -qE "^(ok +|MISSING )bandit" <<<"$1"' _ "$out"
```

and, above `finish`:

```bash
# REQ-330 (H6): the tauri floor needs cargo-audit, installed locked at the pack's version.
DT="$WORK/tauridoc"; copy_template "$DT"
out=$(cd "$DT" && PATH="$BIN" bash scripts/init-project.sh --doctor --stack tauri </dev/null 2>&1 || true)
ck "tauri doctor reports cargo-audit" grep -qE '^MISSING cargo_audit: .+' <<<"$out"
if [[ "$(uname -s)" == Darwin ]]; then ck "…with the pinned, locked install" grep -qE '^MISSING cargo_audit: cargo install cargo-audit --locked --version [0-9.]+' <<<"$out"; fi
# An instance's doctor names no stacks/ path even when the python floor tools are missing (the :27 check, exercised where
# it can fail: minimal PATH, and pip_audit/bandit made absent with the floor_stubs modules — the host python3 has both).
PS="$WORK/pystub"; floor_stubs "$PS"
out=$(cd "$WORK/inst" && PATH="$BIN" PYTHONPATH="$PS/py" STUB_PIP_AUDIT_MISSING=1 STUB_BANDIT_MISSING=1 bash scripts/init-project.sh --doctor </dev/null 2>&1 || true)
ck "instance doctor, pip-audit missing: the hash-pinned install of the instance lockfile" grep -qE '^MISSING pip_audit: pip install --require-hashes -r requirements\.txt' <<<"$out"
ck "…and the output still names no stacks/ path" no grep -q 'stacks/' <<<"$out"
ck "stacks/{python,tauri}/pack.yml: no install_* value names a stacks/ path (an instance prints them)" no grep -qE '^install_[a-z_]+:.*stacks/' stacks/python/pack.yml stacks/tauri/pack.yml
```

In `tests/governance/test_onboarding_surface.sh`, above `finish`:

```bash
# P4 (REQ-330, H6, H12): the floor tools are prerequisites, installed from checksum-verified assets; the floor is online.
# Covers: REQ-330
pre=$(awk '/^## Prerequisites/{f=1; next} /^## /{if (f) exit} f' README.md)
ck "README prerequisites name osv-scanner (the floor's advisory scan)" grep -q 'osv-scanner' <<<"$pre"
ck "README prerequisites give the checksum-verified installer" grep -qF 'install-pinned-tool.sh' <<<"$pre"
ck "README says what SPECFLOW_FLOOR_OFFLINE=1 does" grep -qF 'SPECFLOW_FLOOR_OFFLINE' <<<"$pre"
ck "README Tauri prerequisites install cargo-audit locked at a version" grep -qE 'cargo install cargo-audit --locked --version [0-9.]+' <<<"$pre"
```

- [ ] **Step 2: Run** `bash tests/governance/test_init_doctor.sh; bash tests/governance/test_onboarding_surface.sh`. Expected: `FAIL: MISSING gitleaks: …` and `…osv-scanner`, the pip_audit/bandit FAIL, the cargo_audit FAILs, `FAIL: instance doctor, pip-audit missing: …` (no pip_audit prereq yet), and the four README FAILs. The two no-`stacks/` checks pass before and after: they pin that the new install lines never break `:27`. Both tests exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. `test_stack_packs.sh`'s per-prereq loop (`:22-24`) already requires the `check_`/`install_macos_`/`install_linux_` triple for each new prereq.
- [ ] **Step 4: Run** both tests, `bash tests/governance/test_stack_packs.sh`, `bash scripts/init-project.sh --doctor --stack tauri` (record its output) and the gates — green.
- [ ] **Step 5: Commit** — "feat(doctor): gitleaks, osv-scanner and each stack's floor tools are prerequisites with checksum-verified install lines (REQ-330, REQ-303)"

---

### Task 10: The Dependabot exemption — verified commits from GitHub's signing identity, dependency files only (REQ-334 as amended, dfe-13; REQ-311; H5)

**Files:**
- Modify `scripts/lib/specflow/attestation.py` (`:361-372`, `:495-500`, `:605-619`, `:727-755`, `:903-910`) and `tests/governance/fixtures/attestation/33-dependabot-all-commits.json`.
- Create `tests/governance/fixtures/attestation/36-…json` through `52-…json`.
- Modify `tests/governance/test_attestation.sh` (`:161`, `:164-166`, `:219-244`).

**Interfaces:** "Dependabot rule" under shared Interfaces.

**Fixtures.** Each has `head`/`prompt_sha256`/`solo: true`/`pr_author: "dependabot[bot]"`/`required_mode: "code"` and `"comments": []`, and — so that P2's rule would exempt it and the fixture goes red before this task (fresh-eyes finding 8) — `commit_authors: ["dependabot[bot]"]`. Commits use the shape `{"sha": "<40 hex>", "author": {"login": …}, "committer": {"login": …}, "commit": {"author": {"name": …, "email": …}, "verification": {"verified": …, "reason": …}}}`. `contents` maps each listed path to `{"base": …, "head": …}` texts. The `rule` field is one sentence. The expected result is `{"state": "approve", "reason": "exempt-dependabot", "comment_id": null}` where marked "exempt", and `{"state": "none", "reason": "no-marker", "comment_id": null}` otherwise:

| File | Commits | `files` | `contents` | Expect |
|---|---|---|---|---|
| 33-dependabot-all-commits (rewritten) | author dependabot[bot], committer web-flow, verified | `["scripts/requirements.txt"]` | a pin bump with its `--hash` lines | exempt |
| 36-dependabot-unverified | as 33, `verified: false` | as 33 | as 33 | none |
| 37-dependabot-foreign-committer | committer `mallory`, verified | as 33 | as 33 | none |
| 38-dependabot-bot-committer | committer `dependabot[bot]`, verified | as 33 | as 33 | exempt |
| 39-dependabot-source-file | as 33 | `["scripts/requirements.txt", "src/app.py"]` | as 33, plus `src/app.py` | none |
| 40-dependabot-workflow-uses | as 33 | `[".github/workflows/ci.yml"]` | a `uses:` SHA bump | none |
| 41-dependabot-files-unknown | as 33 | key absent | key absent | none |
| 42-dependabot-nested-lockfiles | as 33 | `["package.json", "package-lock.json", "src-tauri/Cargo.toml", "src-tauri/Cargo.lock", "scripts/requirements.in", "pubspec.lock"]` | a version-only edit of each (registry `resolved`/`source` values) | exempt |
| 43-dependabot-config-file | as 33 | `[".github/dependabot.yml"]` | an interval change | none |
| 44-dependabot-verification-missing | as 33 with no `verification` key | as 33 | as 33 | none |
| 45-dependabot-pyproject | as 33 | `["pyproject.toml"]` | a version edit | none |
| 46-dependabot-foreign-opener | as 33 (every commit perfect) | as 33 | as 33; `pr_author: "mallory"` | none (identity by opener) |
| 47-dependabot-null-committer | as 33 with `"committer": null` | as 33 | as 33 | none (`committer:<sha7>`) |
| 48-dependabot-index-url | as 33 | as 33 | the head adds `--extra-index-url https://pypi.example.invalid/simple` | none |
| 49-dependabot-package-scripts | as 33 | `["package.json"]` | a dependency bump plus a changed `scripts.postinstall` | none |
| 50-dependabot-cargo-patch | as 33 | `["src-tauri/Cargo.toml"]` | a version bump plus a `[patch.crates-io]` git source | none |
| 51-dependabot-pubspec-overrides | as 33 | `["pubspec.yaml"]` | a version bump plus a `dependency_overrides:` block | none |
| 52-dependabot-contents-unknown | as 33 | as 33 | key absent | none (`content-unknown`) |

Fixtures 21 and 34 keep `commit_authors` and stay not exempt (fail closed: no commits, so no verification). Fixture 35 is unchanged.

- [ ] **Step 1: Write the failing tests.** Write the eleven fixture files per the table. In `tests/governance/test_attestation.sh`:
  - change `:161` to `ck "52 or more fixtures ($n)" [ "$n" -ge 52 ]`;
  - append to the rule list at `:164-166`: `dependabot-unverified dependabot-foreign-committer dependabot-bot-committer dependabot-source-file dependabot-workflow-uses dependabot-files-unknown dependabot-nested-lockfiles dependabot-config-file dependabot-verification-missing dependabot-pyproject dependabot-foreign-opener dependabot-null-committer dependabot-index-url dependabot-package-scripts dependabot-cargo-patch dependabot-pubspec-overrides dependabot-contents-unknown`;
  - replace the Dependabot block `:219-244` (from its comment to `rm -f "$S/commits.json"; cp …`) with:

```bash
# Dependabot (REQ-311; REQ-334 as amended, dfe-13; P4): exempt only when the opener and every commit author map to
# dependabot[bot], every commit is verified with committer dependabot[bot] or web-flow, every changed path is a
# dependency manifest or lockfile outside .github/, and each file's change passes its content rule (versions only).
# Commits come from gh api pulls/<pr>/commits (or --commits FILE), paths from git diff --no-renames <base>...<head>
# (or --files FILE), texts from git show at the merge base and the head (or --contents FILE).
cmt() { python3 -c 'import json, sys
out = []
for spec in sys.argv[1:]:
    p = spec.split(":"); a = p[0]; c = p[1] if len(p) > 1 else "web-flow"; v = p[2] if len(p) > 2 else "true"
    out.append({"sha": "0" * 40, "author": None if a == "-" else {"login": a},
                "committer": None if c == "-" else {"login": c},
                "commit": {"author": {"name": "dependabot[bot]" if a == "-" else a, "email": "x@example.invalid"},
                           "verification": {"verified": v == "true", "reason": "valid" if v == "true" else "unsigned"}}})
print(json.dumps(out))' "$@"; }
(cd "$G" && git checkout -q -b deps "$GB" && mkdir -p scripts \
  && printf 'pytest==9.1.1 \\\n    --hash=sha256:%s\n' "$(printf 'a%.0s' $(seq 64))" > scripts/requirements.txt \
  && printf 'pytest>=9,<10\n' > scripts/requirements.in && git add -A && git commit -qm deps \
  && git checkout -q -b idx "$GB" && mkdir -p scripts \
  && printf -- '--extra-index-url https://pypi.example.invalid/simple\npytest==9.1.1\n' > scripts/requirements.txt \
  && git add -A && git commit -qm idx && git checkout -q pr)
DH=$(git -C "$G" rev-parse deps); IH=$(git -C "$G" rev-parse idx)
chkc() {  # chkc HEAD PR_AUTHOR [ARGS…] — the check against HEAD, stubs first; sets rc and out
  local h="$1"; shift; rm -f "$S/gh.argv"; rc=0
  out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$h" \
    --base-ref "$GB" --base-name main --pr-author "$@" 2>&1) || rc=$?
}
cp "$S/comments.json" "$W/rc-comments.json"; echo '[]' > "$S/comments.json"
printf 'scripts/requirements.txt\nscripts/requirements.in\n' > "$W/deps.txt"
cmt 'dependabot[bot]' 'dependabot[bot]' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "Dependabot PR: verified web-flow commits by dependabot[bot], a version-only change to dependency files: exempt" bash -c '[ "$1" = 0 ] && grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
ck "…having read the commits through gh api --paginate pulls/7/commits" bash -c 'grep -qx "repos/o/r/pulls/7/commits" "$1" && grep -qx -- --paginate "$1"' _ "$S/gh.argv"
chkc "$DH" 'dependabot[bot]'
ck "…the same without --files: paths from git diff <base>...<head>, texts from git show — exempt" bash -c '[ "$1" = 0 ] && grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
chkc "$DH" mallory
ck "…the same commits and diff in a PR opened by someone else: not exempt (identity by opener)" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
chkc "$IH" 'dependabot[bot]'
ck "…an added --extra-index-url in requirements.txt: not exempt (content rule)" bash -c '[ "$1" = 1 ] && grep -q "not exempt (content:scripts/requirements.txt" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]' mallory > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…one commit by someone else: not exempt, fails with no marker" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2" && grep -q "no accepted verifier comment" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]' - > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…a commit whose GitHub author is null: not exempt (fail closed)" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
echo '[]' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…no commits listed: not exempt (fail closed)" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:web-flow:false' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…an unverified commit (an author email anyone with push access can set): not exempt, and says why" bash -c '[ "$1" = 1 ] && grep -q "not exempt (unverified" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:mallory' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…a verified commit whose committer is neither dependabot[bot] nor web-flow: not exempt" bash -c '[ "$1" = 1 ] && grep -q "not exempt (committer" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:-' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…a null committer: not exempt (committer:<sha7>)" bash -c '[ "$1" = 1 ] && grep -q "not exempt (committer:0000000" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:dependabot[bot]' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…committer dependabot[bot] is accepted" [ "$rc" = 0 ]
cmt 'dependabot[bot]' > "$S/commits.json"; printf '.github/workflows/ci.yml\n' > "$W/wf.txt"; chkc "$GH" 'dependabot[bot]' --files "$W/wf.txt"
ck "…a uses: bump under .github/workflows/ needs attestation" bash -c '[ "$1" = 1 ] && grep -q "not exempt (workflow-path" <<<"$2"' _ "$rc" "$out"
printf 'scripts/requirements.txt\nsrc/app.py\n' > "$W/src.txt"; chkc "$GH" 'dependabot[bot]' --files "$W/src.txt"
ck "…a source file beside the lockfile needs attestation" bash -c '[ "$1" = 1 ] && grep -q "not exempt (not-a-dependency-file" <<<"$2"' _ "$rc" "$out"
chkc "$GH" 'dependabot[bot]'
ck "…without --files the paths come from git diff <base>...<head> (here docs/a.md): not exempt" bash -c '[ "$1" = 1 ] && grep -q "docs/a.md" <<<"$2"' _ "$rc" "$out"
printf 'scripts/requirements.txt\n' > "$W/one.txt"
python3 -c 'import json; print(json.dumps({"scripts/requirements.txt": {"base": "pytest==9.1.0\n", "head": "pytest==9.1.1\n"}}))' > "$W/contents.json"
chkc "$GH" 'dependabot[bot]' --files "$W/one.txt" --contents "$W/contents.json"
ck "check --contents FILE supplies the texts instead of git show (here for a head that lacks the file): exempt" [ "$rc" = 0 ]
cmt 'dependabot[bot]' > "$W/dcommits.json"; cmt mallory > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --commits "$W/dcommits.json" --files "$W/deps.txt"
ck "check --commits FILE reads the commits from FILE instead of gh" bash -c '[ "$1" = 0 ] && ! grep -q "pulls/7/commits" "$2"' _ "$rc" "$S/gh.argv"
cmt mallory > "$W/mcommits.json"; chkc "$DH" 'dependabot[bot]' --commits "$W/mcommits.json" --files "$W/deps.txt"
ck "check --commits FILE with a foreign commit: not exempt" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
rm -f "$S/commits.json"; cp "$W/rc-comments.json" "$S/comments.json"
```

- [ ] **Step 2: Run** `bash tests/governance/test_attestation.sh`. Expected: every negative fixture except 46 FAILs — 36, 37, 39–41, 43–45 and 47–52 carry `commit_authors: ["dependabot[bot]"]`, so today's `fixture()` (which reads only `context.commit_authors`, `attestation.py:740-741`) exempts them and returns `approve`/`exempt-dependabot` instead of `none`/`no-marker`. Fixture 46 (a foreign opener) passes before and after: P2's rule already checks the opener, and 46 pins that. Fixtures 33, 38 and 42 pass today on `commit_authors` alone and stay green. The rule-name and count checks FAIL, and every `--files`/`--contents` check FAILs with `unrecognized arguments`. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. `dependabot_exempt`'s docstring and the module docstring name REQ-334 (dfe-13), the committer set, why the author email alone is not enough, and why paths alone are not enough (the content rules). The fixture runner passes `commits`, `files` and `contents` when present.
- [ ] **Step 4: Run** the test and the gates — green. `bash tests/governance/test_verifier_run.sh` stays green: `run-verifier.sh` does not call the exemption.
- [ ] **Step 5: Commit** — "feat(attestation): the Dependabot exemption needs verified commits from GitHub's signing identity and a dependency-only diff (REQ-334, dfe-13; REQ-311)"

---

### Task 11: `## Tools run` — rendered from the floor, checked in every review; SEC ids unique by definition (REQ-332; H13, R13, R14)

**Files:**
- Modify `scripts/lib/specflow/floor.py` (`render`, `check-review`), `.claude/commands/security-review.md` (`:11-33`, plus a new step 0), `docs/security/0.0.1-demo-review.md:9-12`, `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md` (its `## Tools run`, which Task 8 left out) and `scripts/check-traceability.sh:161-168`.
- Create `tests/governance/test_security_review.sh`.

**Interfaces:** "`## Tools run` format" (with the evidence digest and the provenance line), `render` and `check-review` under shared Interfaces.
- **`check-traceability.sh`:** a SEC id is *defined* by a line `id: SEC-NNN` in a review. Only definitions must be unique across reviews; citations elsewhere (a later review's suppressions table) are references.
- **`/security-review`:**
  - Step 0: run `bash scripts/run-security-floor.sh` online. A failure becomes a finding, never a suppression without a SEC; a `lookup failed` line means rerun online, never paste.
  - Paste the output of `python3 scripts/lib/specflow/floor.py render --summary .specflow/floor-summary.json --root .` verbatim as `## Tools run`; editing a row breaks the evidence digest.
  - The review's findings keep the existing frontmatter.
  - New ids continue after the highest `id: SEC-NNN` under `docs/security/`; ids are never reused.
  - A suppression added for a finding gets a disposition entry whose `suppresses:` names the entry (Interfaces "Suppression scan"), and the suppression cites the SEC id (REQ-388).
  - Before the PR: `python3 scripts/lib/specflow/floor.py check-review docs/security/$ARGUMENTS-review.md --root .` and `bash scripts/check-suppressions.sh` pass.
- **Demo review:** its `## Tools run` is rendered from a scratch python instance (Step 3), with the provenance line before the table: "Floor run 2026-09-26 (P4) on a scratch instance of template commit <40-hex> (working tree); the floor did not exist at this release's 2026-05-28 review." The manual-review, threat-model and Dafny lines follow the suppressions subsection as a list.
- **Tauri skeleton review** (Task 8 shipped it without the section): its `## Tools run` is rendered from a scratch tauri instance (Step 3), with the provenance line "Floor run 2026-09-26 (P4) on a scratch instance of template commit <40-hex> (working tree): the tauri overlay with the floor scripts." This task's test is the first to check the pack-shipped review.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_security_review.sh`:

```bash
#!/usr/bin/env bash
# REQ-332: docs/security/<version>-review.md carries a mandatory "## Tools run" section — each floor tool with version,
# exit status and a one-line result, and every active suppression with its SEC-NNN — rendered by floor.py from the
# floor's summary and checked against it (an evidence digest over the rows; a commit in the repository's history — a
# shipped review's provenance commit excepted since PR #74, the Interfaces note); a
# review listing only manual review fails when the product has a lockfile (the pack's lockfiles; scripts/requirements.txt
# alone does not count). render refuses a summary that is not evidence. SEC ids are unique by definition, not by mention.
# Covers: REQ-332
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
FP="$ROOT/scripts/lib/specflow/floor.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
G="$W/g"; mkdir -p "$G"; (cd "$G" && git init -q -b main && echo x > a && git add a && git commit -qm a)
HS=$(git -C "$G" rev-parse HEAD)
summary() {  # summary MODE COMMIT ERRORS TOOL… — TOOL is name|scope|exit|status|result ("-": not run); one suppression
  python3 - "$@" > "$W/sum.json" <<'PY'
import json, sys
mode, commit, errors = sys.argv[1:4]
ver = {"gitleaks": "8.30.1", "osv-scanner": "2.6.0", "pip-audit": "2.10.1", "bandit": "1.9.4"}
tools = []
for spec in sys.argv[4:]:
    name, scope, ex, status, result = spec.split("|")
    tools.append({"tool": name, "scope": scope, "version": ver[name], "exit": None if ex == "-" else int(ex),
                  "status": status, "result": result, "command": name})
print(json.dumps({"schema": 1, "generated_at": "2026-09-26T20:00:00Z", "commit": commit, "dirty": False, "mode": mode,
  "stack": "python", "tools": tools,
  "suppressions": [{"file": "src-tauri/audit.toml", "line": 11, "kind": "cargo-audit", "id": "RUSTSEC-2024-0370",
                    "name": "RUSTSEC-2024-0370", "sec": "SEC-002"}],
  "suppression_errors": [e for e in errors.split(";") if e]}))
PY
}
GL='gitleaks|.|0|pass|clean'; OS='osv-scanner|.|0|pass|clean'; ONA='osv-scanner|.|-|not-applicable|not run — no tracked lockfile'
PA='pip-audit|requirements.txt|0|pass|clean'; BA='bandit|src|0|pass|clean'
render() { rc=0; md=$(cd "${RD:-$G}" && python3 "$FP" render --summary "$W/sum.json" --root . 2>"$W/render.err") || rc=$?; }
sub() { python3 -c 'import sys; p, a, b = sys.argv[1:4]; t = open(p).read(); assert a in t, a; open(p, "w").write(t.replace(a, b, 1))' "$@"; }
nosub() { python3 -c 'import sys; print(sys.stdin.read().split("\n### Active suppressions")[0])'; }

summary online "$HS" '' "$GL" "$OS"; render
ck "render: exit 0 for an online summary of HEAD" [ "$rc" = 0 ]
ck "render: '## Tools run' heading" grep -qx '## Tools run' <<<"$md"
ck "render: the tools table header" grep -qxF '| Tool | Scope | Version | Exit | Result |' <<<"$md"
ck "render: one row per tool with version and exit" bash -c 'grep -qxF "| gitleaks | . | 8.30.1 | 0 | clean |" <<<"$1" && grep -qxF "| osv-scanner | . | 2.6.0 | 0 | clean |" <<<"$1"' _ "$md"
ck "render: '### Active suppressions' with each SEC-NNN" bash -c 'grep -qx "### Active suppressions" <<<"$1" && grep -qxF "| src-tauri/audit.toml | 11 | RUSTSEC-2024-0370 | SEC-002 |" <<<"$1"' _ "$md"
ck "render: names the summary's commit" grep -qF "$HS" <<<"$md"
ck "render: the evidence line (a sha256 over the commit and the rows)" grep -qE '^Floor evidence: rows sha256 [0-9a-f]{64}\.$' <<<"$md"
summary online "$HS" '' "$GL" "$ONA"; render
ck "render: a tool that was not run prints '-' in the Exit cell" grep -qxF '| osv-scanner | . | 2.6.0 | - | not run — no tracked lockfile |' <<<"$md"
mkdir -p "$G/docs/security"; RG="$G/docs/security/0.1.0-review.md"; NA="$md"
rg() { printf '# Security Review — v0.1.0\n\n## Summary\n0 findings.\n\n%s\n' "$1" > "$RG"; }
crg() { rc=0; out=$(python3 "$FP" check-review "$RG" --root "$G" 2>&1) || rc=$?; }
rg "$NA"; crg
ck "round trip: a rendered section, with a tool not run, passes check-review" [ "$rc" = 0 ]
sub "$RG" '| gitleaks | . | 8.30.1 | 0 | clean |' '| gitleaks | . | 8.30.1 | 0 | clean (manual check) |'; crg
ck "a hand-edited row fails: the evidence digest no longer matches" bash -c '[ "$1" = 1 ] && grep -qi digest <<<"$2"' _ "$rc" "$out"
rg "$NA"; sub "$RG" '| - | not run — no tracked lockfile |' '| - | clean |'; crg
ck "a '-' exit is accepted only with the result 'not run — no tracked lockfile'" bash -c '[ "$1" = 1 ] && grep -qi exit <<<"$2"' _ "$rc" "$out"
summary offline "$HS" '' "$GL" 'osv-scanner|.|-|skipped-offline|SPECFLOW_FLOOR_OFFLINE=1'; render
ck "render refuses an offline summary (not evidence)" [ "$rc" = 1 ]
summary online "$(printf '0%.0s' $(seq 40))" '' "$GL" "$OS"; render
ck "render refuses a summary of another commit (stale)" [ "$rc" = 1 ]
summary online "$HS" '' "$GL" 'osv-scanner|.|127|lookup-failed|lookup failed — no such host'; render
ck "render refuses a summary with a failed lookup (no evidence)" [ "$rc" = 1 ]
summary online "$HS" 'src-tauri/audit.toml:3: RUSTSEC-2099-0003 is not in the suppresses: of SEC-001' "$GL" "$OS"; render
ck "render refuses a summary with suppression errors, listing them" bash -c '[ "$1" = 1 ] && grep -q RUSTSEC-2099-0003 "$2"' _ "$rc" "$W/render.err"

R="$W/r"; mkdir -p "$R/docs/security" "$R/.specflow" "$R/scripts"; : > "$R/scripts/requirements.txt"
(cd "$R" && git init -q -b main && git add -A && git commit -qm r); HR=$(git -C "$R" rev-parse HEAD)
RV="$R/docs/security/0.1.0-review.md"
rev() { printf '# Security Review — v0.1.0\n\n## Summary\n0 findings.\n\n%s\n' "$1" > "$RV"; }
cr() { rc=0; out=$(python3 "$FP" check-review "$RV" --root "$R" 2>&1) || rc=$?; }
rev $'## Findings\nNone.'; cr
ck "a review with no '## Tools run' section fails" bash -c '[ "$1" = 1 ] && grep -q "Tools run" <<<"$2"' _ "$rc" "$out"
rev $'## Tools run\n- Manual review by reviewer: @alice'; cr
ck "manual-only with no product lockfile passes (scripts/requirements.txt alone does not count)" [ "$rc" = 0 ]
summary online "$HR" '' "$GL" "$OS"; RD="$R" render; rev "$(nosub <<<"$md")"; cr
ck "a tools table without '### Active suppressions' fails even with no product lockfile" bash -c '[ "$1" = 1 ] && grep -q "Active suppressions" <<<"$2"' _ "$rc" "$out"
printf 'stack: python\nlockfiles: [requirements.txt]\nfloor_tools: [pip-audit, bandit]\n' > "$R/.specflow/pack.yml"; : > "$R/requirements.txt"
rev $'## Tools run\n- Manual review by reviewer: @alice'; cr
ck "manual-only when the pack's lockfile exists fails" bash -c '[ "$1" = 1 ] && grep -qi "manual" <<<"$2"' _ "$rc" "$out"
summary online "$HR" '' "$GL" "$OS" "$PA" "$BA"; RD="$R" render; FULL="$md"; rev "$FULL"; cr
ck "a rendered table with gitleaks, osv-scanner and the pack's floor_tools passes" [ "$rc" = 0 ]
summary online "$HR" '' "$GL" "$OS" "$PA"; RD="$R" render; rev "$md"; cr
ck "a missing pack floor tool row fails, naming it" bash -c '[ "$1" = 1 ] && grep -q bandit <<<"$2"' _ "$rc" "$out"
rev "$FULL"; sub "$RV" '| requirements.txt | 2.10.1 | 0 |' '| requirements.txt |  | 0 |'; cr
ck "a row without a version fails" bash -c '[ "$1" = 1 ] && grep -qi version <<<"$2"' _ "$rc" "$out"
rev "$FULL"; sub "$RV" '| requirements.txt | 2.10.1 | 0 |' '| requirements.txt | 2.10.1 | ok |'; cr
ck "a row without a numeric exit status fails" bash -c '[ "$1" = 1 ] && grep -qi exit <<<"$2"' _ "$rc" "$out"
rev "$(nosub <<<"$FULL")"; cr
ck "a missing '### Active suppressions' subsection fails" bash -c '[ "$1" = 1 ] && grep -q "Active suppressions" <<<"$2"' _ "$rc" "$out"
rev "$FULL"; sub "$RV" '| SEC-002 |' '| 002 |'; cr
ck "a suppression row without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q "SEC" <<<"$2"' _ "$rc" "$out"
summary online "$HS" '' "$GL" "$OS" "$PA" "$BA"; render; rev "$md"; cr
ck "a section rendered at a commit outside this repository's history fails" bash -c '[ "$1" = 1 ] && grep -qi ancestor <<<"$2"' _ "$rc" "$out"

shopt -s nullglob
for f in "$ROOT"/docs/security/*-review.md; do ck "${f#$ROOT/} has a valid '## Tools run'" python3 "$FP" check-review "$f" --root "$ROOT"; done
if ! instance; then
  for f in "$ROOT"/stacks/*/overlay/docs/security/*-review.md; do
    r="${f%/docs/security/*}"; ck "${f#$ROOT/} (pack-shipped) has a valid '## Tools run'" python3 "$FP" check-review "$f" --root "$r" --pack "${r%/overlay}/pack.yml"
  done
fi
shopt -u nullglob
SR="$ROOT/.claude/commands/security-review.md"
ck "/security-review runs the floor first" grep -qF 'bash scripts/run-security-floor.sh' "$SR"
ck "/security-review pastes floor.py render's output (never a paraphrase)" grep -qF 'floor.py render' "$SR"
ck "/security-review checks the review with floor.py check-review and check-suppressions.sh" bash -c 'grep -qF "floor.py check-review" "$1" && grep -qF "check-suppressions.sh" "$1"' _ "$SR"
ck "/security-review: SEC ids continue after the highest defined and are never reused" grep -qi 'never reuse' "$SR"
ck "/security-review: a suppression's disposition entry lists the ids in suppresses:" grep -qF 'suppresses:' "$SR"

T="$W/trace"; mkdir -p "$T/docs/security" "$T/docs/specs" "$T/docs/plans"
printf -- '# R1\n\n---\nid: SEC-001\nseverity: low\n---\n' > "$T/docs/security/0.0.0-skeleton-review.md"
printf -- '# R2\n\n## Tools run\n\n| File | Line | Id | SEC |\n|---|---|---|---|\n| a | 1 | X | SEC-001 |\n' > "$T/docs/security/0.1.0-review.md"
ck "citing an earlier SEC id in a later review is a reference, not a duplicate" env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
printf -- '\n---\nid: SEC-001\nseverity: low\n---\n' >> "$T/docs/security/0.1.0-review.md"
ck "defining the same SEC id in two reviews still fails" no env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
finish test_security_review
```

- [ ] **Step 2: Run** `bash tests/governance/test_security_review.sh`. Expected: every `render` and `check-review` check FAILs (`invalid choice`), including the demo review's and the pack-shipped skeleton review's. The `/security-review` checks and `citing an earlier SEC id…` FAIL (today every mention counts). Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. Then render the two reviews produced outside their repository (network; about 30 s for the demo, about 1 minute for the tauri skeleton). Both scratch instances are built from the **working tree** — `render` and `check-review` are uncommitted at this point, so a `git clone` (which also checks out this branch, and `init-project.sh:292-296` refuses a non-`main` branch) would lack them:
  1. **Demo.** `bash -c 'source tests/governance/lib/check.sh; copy_template "$1"' _ "$TMPDIR/p4-demo"` (the working tree, no `.git`). There, `bash scripts/init-project.sh --name Demo --profile guided </dev/null`, which runs `git init -b main` and commits. Then `bash scripts/run-security-floor.sh` from the gates venv with the skeleton lockfile installed, and `python3 scripts/lib/specflow/floor.py render --summary .specflow/floor-summary.json --root .`. Paste the output into `0.0.1-demo-review.md` after the provenance line, naming `git rev-parse HEAD` of this worktree followed by `(working tree)`. `rm -rf "$TMPDIR/p4-demo"`.
  2. **Tauri skeleton.** Make `$TMPDIR/p4-tauri` by `cp -R` from the working tree: `stacks/tauri/overlay/.` (which carries Task 8's `docs/security/`), `scripts/run-security-floor.sh`, `scripts/lib/specflow/{config.py,floor.py,floor.sh}`, `stacks/tauri/security.sh` as `scripts/security-tauri.sh`, `stacks/tauri/pack.yml` as `.specflow/pack.yml`, `.gitleaks.toml`, `.gitignore`, and a `.specflow.yml` with `stack: tauri`. `git init -b main` and commit. Run `bash scripts/run-security-floor.sh` with cargo-audit, osv-scanner and npm on `PATH` (`bash scripts/init-project.sh --doctor --stack tauri` names them); it must pass, and `render` refuses it if any suppression error remains. Paste the rendered section into `stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md` after its provenance line. `rm -rf "$TMPDIR/p4-tauri"`.
- [ ] **Step 4: Run** the test, `bash tests/governance/test_traceability.sh`, `bash scripts/check-traceability.sh` and the gates — green.
- [ ] **Step 5: Commit** — "feat(security-review): a mandatory Tools run section rendered from the floor summary and checked in every review; SEC ids unique by definition (REQ-332)"

---

### Task 12: The threat-model template's domain checklist and `check-architecture.sh` (REQ-333; H8) — includes architecture-artifact updates

**Files:**
- Create `schemas/threat-model-template.md`, `scripts/lib/specflow/architecture.py`, `scripts/check-architecture.sh` and `tests/governance/test_check_architecture.sh`.
- Modify `.claude/commands/architecture.md:17`.
- **Architecture artifacts:** `docs/architecture/2026-05-28-demo-greeting-threat-model.md` (append the checklist) and `docs/architecture/2026-09-25-factory-v3-2-threat-model.md:183` (answer grammar).

**Interfaces:** "Threat-model checklist" and `check-architecture.sh` under shared Interfaces.
- **`schemas/threat-model-template.md`:**
  - frontmatter showing every key with one example entry (`spec`, `assets` with `cia: {c: , i: , a: }`, `trust_boundaries` with `between`, `dataflow_elements` with `external`, `stride_per_element`), plus a comment line naming the supported YAML subset;
  - body sections `## Narrative`, `## Elements` (the `| id | Element | Boundary | Threats | Mitigations (REQ) |` table), `## Data-flow diagram`, `## Domain checklist (REQ-333)` (the ten rows, with the answer grammar stated above the table), and `## Residual risks`.
- **`/architecture` step 3:** "from `schemas/threat-model-template.md`, answering every checklist row", and before the PR: `bash scripts/check-architecture.sh`.
- **Demo answers:**
  - PII and retention: `dfe-1: the name is used only to build the returned string; nothing stores or logs it`;
  - Sensitive logging: `dfe-1: greet performs no logging`;
  - every other row: `N/A because …` (the pure function has no identity, sessions, money, secrets, endpoints, dependencies or update channel).
- **v3.2 `:183`:** `N/A because the factory ships no app of its own; for products it is a store-checklist item (REQ-386) and a threat-model item the product's own model must answer`.

- [ ] **Step 1: Write the failing test** — `tests/governance/test_check_architecture.sh`:

```bash
#!/usr/bin/env bash
# REQ-333: the threat-model template carries the ten-domain checklist; check-architecture.sh fails on an unanswered item
# and on the ARCHITECTURE exit-gate shape .claude/rules/review-gate.md states (every [verifiable*] REQ in some overview
# req_map; >= 1 trust boundary; >= 1 asset with CIA; >= 1 STRIDE letter per external element), for each live spec a plan
# names. The demo and v3.2 threat models answer the checklist.
# Covers: REQ-333
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CA="$ROOT/scripts/check-architecture.sh"; TPL="$ROOT/schemas/threat-model-template.md"
[[ -f "$CA" ]] || { fail "scripts/check-architecture.sh missing"; finish test_check_architecture; }
DOMAINS=("Authentication" "Authorization" "Session" "PII and retention" "Payments" "Secrets at rest" "Sensitive logging" "Rate limiting" "Third-party integrations" "Update channel for apps")
ck "schemas/threat-model-template.md exists" test -f "$TPL"
for d in "${DOMAINS[@]}"; do ck "template checklist row: $d" grep -qE "^\| $d \|" "$TPL"; done
for k in assets trust_boundaries dataflow_elements stride_per_element; do ck "template frontmatter key $k" grep -qE "^$k:" "$TPL"; done
ck "template states the answer grammar (dfe-N or 'N/A because …')" grep -qF 'N/A because' "$TPL"
ck "this repository passes check-architecture.sh" bash "$CA"
AC="$ROOT/.claude/commands/architecture.md"
ck "/architecture points at the template" grep -qF 'schemas/threat-model-template.md' "$AC"
ck "/architecture runs check-architecture.sh before the PR" grep -qF 'scripts/check-architecture.sh' "$AC"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mk() {  # mk — a spec with one [verifiable-model] REQ (and one REQ that only mentions the tag in backticks, as REQ-389 does),
  # a plan naming it, an overview mapping it, a complete threat model whose frontmatter has a full-line # comment and the
  # nested block map stride_per_element (the subset the template documents)
  A="$W/a"; rm -rf "$A"; mkdir -p "$A/docs/specs" "$A/docs/plans" "$A/docs/architecture"
  printf -- '---\ntype: spec\nstatus: accepted\n---\n\n# X\n\n- **REQ-900:** a pure rule. [verifiable-model]\n- **REQ-901:** a doc.\n- **REQ-902:** prose naming the `[verifiable-model]` tag, which is not a tag.\n' > "$A/docs/specs/2099-01-01-x-design.md"
  printf -- '---\ntype: plan\nspec: 2099-01-01-x\nimplements: [REQ-900]\n---\n\n# P\n' > "$A/docs/plans/2099-01-01-x-plan.md"
  OV="$A/docs/architecture/2099-01-01-x-overview.md"; TM="$A/docs/architecture/2099-01-01-x-threat-model.md"
  printf -- '---\nspec: 2099-01-01-x\nkernel_modules:\n  - path: src/x.py\n    req_map: [REQ-900]\n---\n\n# O\n' > "$OV"
  { printf -- '---\nspec: 2099-01-01-x\n# the supported YAML subset: see schemas/threat-model-template.md\nassets:\n  - name: data\n    cia: {c: H, i: M, a: L}\ntrust_boundaries:\n  - name: user-to-app\n    between: [user, app]\n'
    printf 'dataflow_elements:\n  - id: dfe-1\n    name: input\n    external: true\n  - id: dfe-2\n    name: inner\n    external: false\n'
    printf 'stride_per_element:\n  dfe-1: [T, I]\n  dfe-2: []\n---\n\n# T\n\n## Domain checklist (REQ-333)\n\n| Domain | Answer |\n|---|---|\n'
    for d in "${DOMAINS[@]}"; do printf '| %s | N/A because the fixture has no %s surface |\n' "$d" "$d"; done
    printf '\n## Residual risks\n- none\n'; } > "$TM"
}
ca() { rc=0; out=$(ARCH_BASE_DIR="$A" bash "$CA" 2>&1) || rc=$?; }
edit() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
t = open(p).read(); assert old in t, old; open(p, "w").write(t.replace(old, new, 1))
PY
}
S1="| Session | N/A because the fixture has no Session surface |"
mk; ca; ck "fixture: a complete architecture passes (a backticked tag is prose; a # comment and a nested block map parse)" [ "$rc" = 0 ]
mk; edit "$TM" "| Payments | N/A because the fixture has no Payments surface |"$'\n' ""; ca
ck "a missing checklist row fails, naming the domain" bash -c '[ "$1" = 1 ] && grep -q "Payments" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" "$S1" "| Session | later |"; ca
ck "an answer that is neither dfe-N nor 'N/A because …' fails, naming the domain" bash -c '[ "$1" = 1 ] && grep -q "Session" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" "$S1" "| Session | N/A |"; ca
ck "a bare 'N/A' (no reason) fails" [ "$rc" = 1 ]
mk; edit "$TM" "$S1" "| Session | dfe-1: the input carries the session cookie |"; ca
ck "an answer citing an existing dfe-N passes" [ "$rc" = 0 ]
mk; edit "$TM" "$S1" "| Session | dfe-7: no such element |"; ca
ck "an answer citing an unknown dfe-N fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "dfe-7" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" "  dfe-1: [T, I]" "  dfe-1: []"; ca
ck "an external element with no STRIDE letter fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "dfe-1" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" $'trust_boundaries:\n  - name: user-to-app\n    between: [user, app]\n' $'trust_boundaries: []\n'; ca
ck "no trust boundary fails" [ "$rc" = 1 ]
mk; edit "$TM" "    cia: {c: H, i: M, a: L}" "    cia: {c: H, i: M}"; ca
ck "no asset with a full CIA rating fails" [ "$rc" = 1 ]
mk; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "a [verifiable-model] REQ in no req_map fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
mk; rm "$TM"; ca
ck "a spec a plan names, with no threat model, fails" [ "$rc" = 1 ]
mk; rm "$A/docs/plans/2099-01-01-x-plan.md" "$TM"; ca
ck "a spec no plan names yet is not checked (ARCHITECTURE may be in progress)" [ "$rc" = 0 ]
mk; edit "$A/docs/specs/2099-01-01-x-design.md" "status: accepted" "status: superseded"; rm "$TM"; ca
ck "a superseded spec is not checked" [ "$rc" = 0 ]
mk; edit "$TM" "  dfe-2: []" "  dfe-2: !!set {}"; ca
ck "YAML outside the documented subset is an error naming the line (fail closed)" [ "$rc" = 2 ]
mk; rm -rf "$A/docs/specs" "$A/docs/plans" "$A/docs/architecture"; ca
ck "no docs at all (an instance with every example removed) passes" [ "$rc" = 0 ]
finish test_check_architecture
```

- [ ] **Step 2: Run** `bash tests/governance/test_check_architecture.sh`. Expected: `FAIL: scripts/check-architecture.sh missing`, exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces: the template, `architecture.py` (parser, `check`; the parser covers the documented subset, including nested block maps and full-line comments, and check (a) reuses `check-traceability.sh:139-140`'s tag regex), the wrapper, the command, and the two threat-model edits. With the checker in place, before the v3.2 edit, `bash scripts/check-architecture.sh` must name exactly `Update channel for apps` for the v3.2 model, plus the demo model's missing section. Record that output for the PR body.
- [ ] **Step 4: Run** the test and the gates — green.
- [ ] **Step 5: Commit** — "feat(architecture): threat-model template with the ten-domain checklist, check-architecture.sh, both threat models answer it (REQ-333)"

---

### Task 13: Architecture artifacts match what shipped — dfe-2, dfe-4, dfe-11, dfe-13, the narrative, the overview's plan note (H7; REQ-311, REQ-334, REQ-388)

**Files:** architecture artifacts `docs/architecture/2026-09-25-factory-v3-2-threat-model.md` (`:103`, `:110`, `:112`, `:119`, `:121`) and `docs/architecture/2026-09-25-factory-v3-2-overview.md` (`:131-132`, plus one bullet); create `tests/governance/test_threat_model_current.sh`.

**Interfaces (the content the test pins):**
- **dfe-2's mitigation** describes the P2 classifier as shipped. It judges each marker-bearing comment in order:
  - an author association other than `OWNER`/`MEMBER`/`COLLABORATOR` is ignored and never blocks;
  - an edited or multi-marker comment is blocking when it names the head, and rejected otherwise;
  - `sha` must equal the head, and `prompt_sha256` must match the base's;
  - `digest-mismatch` and `verdict-mismatch` are blocking;
  - `mode-mismatch` and `in-session-in-solo` are rejected;
  - blocking comments take precedence, and otherwise the newest accepted comment decides (REQ-311, REQ-382 as amended; fixtures 01–35).

  The tamper-evident sentence stays.
- **dfe-4:** the mitigations as delivered — release-asset checksums (`scripts/pinned-tools.yml`), `cargo install --locked --version`, hash-pinned requirements, SHA-pinned actions, read-only `permissions:`. The Dependabot clause now points to dfe-13 (dependency files only; any `uses:` bump under `.github/workflows/**` needs attestation). The version-only residuals of R15 are named: `setup-node`, `setup-python`, `rustup`, the Dart/engine artifacts, Homebrew, and the rustup installer. Delivered: "P4 (release.yml elevation: P6)".
- **dfe-11:** the floor passes `--ignore-gitleaks-allow`; each entry cites a `SEC-NNN` whose latest disposition entry is accepted or deferred and lists the id in `suppresses:` (`check-suppressions.sh`); the allowlist is the three paths; the verifier uses the base ref's `.gitleaks.toml`.
- **dfe-13:** the rule under shared Interfaces and R11, stated in full with "fail closed" and the per-file content rules (no index, URL or VCS requirement; no `package.json` change outside the dependency maps; no Cargo `[patch]`, `[replace]` or git/path source; no pubspec `dependency_overrides`; lockfile sources on the public registries), the residual (whether GitHub signs an API-created commit whose author is set to Dependabot's address with committer `web-flow` is unmeasured; the diff restriction bounds such a commit to dependency files, which the floor still scans on the PR), and "the tag-time re-check applying the same rule is P6's (REQ-350)". Delivered: "P4 (tag-time re-check: P6)".
- **The narrative's `:103` sentence** becomes: "The "Delivered in" column names the plan that ships each mitigation. P2 (dfe-1, dfe-2, dfe-6, dfe-8, dfe-9) and P4 (dfe-4 except `release.yml`, dfe-11, dfe-13 except the tag-time re-check) have shipped; every other row is open until its plan merges."
- **Overview:**
  - the `:132` bullet becomes "P2 created `attestation.py` (the CI check runs the base's copy); P5 extends it for `next.sh` and creates `state.py`, its Dafny model, `next.sh`, and `/next`";
  - the P3 bullet (`:131`) gains "and the tauri pack's `0.0.0-skeleton` review and disposition (P4)";
  - a new bullet: "P4 created `scripts/check-architecture.sh` (REQ-333 checklist and the ARCHITECTURE exit-gate shape); P3 scopes it to `implements:` (REQ-320, REQ-394) and adds `confirmed_by:` (REQ-389)."

- [ ] **Step 1: Write the failing test** — `tests/governance/test_threat_model_current.sh`:

```bash
#!/usr/bin/env bash
# Architecture artifacts kept true to what shipped (P4 walks the full phase path, so its IMPLEMENT branch may update
# them): dfe-2 describes the P2 classifier as shipped; dfe-4, dfe-11 and dfe-13 the P4 rules; the narrative no longer
# says nothing exists; the overview no longer says P5 creates attestation.py.
# Covers: REQ-311
# Covers: REQ-334
# Covers: REQ-388
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
TM="$ROOT/docs/architecture/2026-09-25-factory-v3-2-threat-model.md"; OV="$ROOT/docs/architecture/2026-09-25-factory-v3-2-overview.md"
[[ -f "$TM" && -f "$OV" ]] || { echo "SKIP: the v3.2 architecture documents are not in this tree"; exit 0; }
row() { grep -E "^\| $1 \|" "$TM" || true; }
r2=$(row dfe-2)
ck "dfe-2 no longer claims only unedited comments are considered" no grep -qF 'accepts only unedited comments' <<<"$r2"
for w in 'names the head' 'mode-mismatch' 'verdict-mismatch' 'digest-mismatch' 'in-session-in-solo' 'blocking'; do ck "dfe-2 states '$w'" grep -qF "$w" <<<"$r2"; done
r13=$(row dfe-13)
for w in 'verification.verified' 'web-flow' '.github/' 'requirements.txt' 'Cargo.lock' 'pubspec.lock' 'fail closed' 'REQ-350' '[patch]' 'dependency_overrides'; do ck "dfe-13 states '$w'" grep -qF "$w" <<<"$r13"; done
ck "dfe-13 no longer exempts uses: lines" no grep -qF 'and `uses:` lines' <<<"$r13"
r4=$(row dfe-4)
ck "dfe-4 no longer exempts uses: lines for Dependabot" no grep -qF 'and `uses:` lines' <<<"$r4"
ck "dfe-4 names the version-only residuals" bash -c 'grep -q "setup-node" <<<"$1" && grep -q "rustup" <<<"$1" && grep -qi "homebrew" <<<"$1"' _ "$r4"
r11=$(row dfe-11)
for w in 'ignore-gitleaks-allow' 'suppresses:' 'check-suppressions.sh'; do ck "dfe-11 states '$w'" grep -qF -- "$w" <<<"$r11"; done
ck "the narrative no longer says no mitigation exists" no grep -qF 'None of the mitigations below exist today' "$TM"
ck "the overview no longer says P5 creates attestation.py" no grep -qF 'P5 creates `attestation.py`' "$OV"
ck "the overview says P2 created attestation.py and P5 extends it" grep -qE 'P2 created `attestation.py`.*P5 extends' "$OV"
ck "the overview records check-architecture.sh's hand-off to P3 (REQ-320)" grep -qE 'check-architecture.sh.*REQ-320' "$OV"
finish test_threat_model_current
```

- [ ] **Step 2: Run** `bash tests/governance/test_threat_model_current.sh`. Expected: every content check FAILs except the no-`uses:` checks for dfe-4 and dfe-13, which also FAIL today. Exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. Keep each row's `Boundary` and `Threats` cells, and keep the element ids and the frontmatter unchanged. `check-architecture.sh` stays green.
- [ ] **Step 4: Run** the test, `bash scripts/check-architecture.sh` and the gates — green.
- [ ] **Step 5: Commit** — "docs(architecture): threat-model dfe-2, dfe-4, dfe-11, dfe-13 and the overview's plan notes match what P2 and P4 shipped (architecture-artifact update)"

---

### Task 14: The docs say what P4 shipped — glossary, README, the claim table, `CLAUDE.md`, `docs/security/README.md` (REQ-330, REQ-334, REQ-388)

**Files:** `docs/GLOSSARY.md` (`:76-84`, `:171-174`, and a new `### Suppression` in alphabetical order after `### Store checklist`); `README.md` (`:31`, `:123-126`); `.claude/rules/review-gate.md:64`; `CLAUDE.md` (Project Map lines for `scripts/`, `schemas/` and `.specflow/`); `docs/security/README.md`; `tests/governance/test_onboarding_surface.sh`.

**Interfaces (content the tests pin):**
- **Security floor** (glossary): the tool floor `scripts/run-security-floor.sh` runs as section 5 of every gates run — gitleaks over the full history, osv-scanner over every tracked lockfile, then the stack's own audits. A floor failure is an advisory, a leak, a failed lookup or tool error (reported as such, never as findings), or a missing floor tool, and the summary lists it apart from gate failures. `SPECFLOW_FLOOR_OFFLINE=1` skips the advisory lookups and is not evidence. The SECURITY exit bar (zero open critical or high, capped mediums) is the disposition gate, not the floor.
- **Suppression** (glossary): an ignore entry, allowlist string, fingerprint, `# nosec` or configuration key that hides a finding from a floor tool. Each one cites a `SEC-NNN` whose latest disposition entry is accepted or deferred and names it in `suppresses:`, and `check-suppressions.sh` enforces this. An advisory suppression stops working on its `ignoreUntil` date, for every tool.
- **Dependabot exemption** (glossary): the rule as shipped — verified commits, committer `dependabot[bot]` or `web-flow`, dependency files only and version-only changes to them, `.github/` always reviewed, fail closed. The "are P4's" sentence and the P4 tracking sentence go; the constitution sentence stays tracked for amendment B (P5).
- **The `review-gate.md:64` row:** the same rule, its files (`scripts/lib/specflow/attestation.py`, `tests/governance/fixtures/attestation`), and the residual.
- **README:**
  - `:31` stays and gains "(see `docs/GLOSSARY.md`, Security floor)";
  - the gates bullet (`:123-126`) says the gates also run the security floor and that the summary lists floor failures apart from gate failures.
- **`CLAUDE.md`:** the Project Map names `run-security-floor.sh`, `check-suppressions.sh`, `check-architecture.sh`, `install-pinned-tool.sh`, `schemas/threat-model-template.md`, and `.specflow/floor-summary.json` (generated, gitignored). The Canonical Example manifest is untouched.
- **`docs/security/README.md`:** the `## Tools run` section and where it comes from; suppressions and `suppresses:`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/governance/test_onboarding_surface.sh`, above `finish`:

```bash
# P4 (REQ-330, REQ-334, REQ-388): the floor, suppressions and the Dependabot rule, where a user reads them.
# Covers: REQ-334
# Covers: REQ-388
g=docs/GLOSSARY.md
sf=$(awk '/^### Security floor$/{f=1; next} /^### /{f=0} f' "$g")
ck "glossary: Security floor is the tool floor (gitleaks, osv-scanner, run-security-floor.sh)" \
  bash -c 'grep -q gitleaks <<<"$1" && grep -q osv-scanner <<<"$1" && grep -q run-security-floor.sh <<<"$1"' _ "$sf"
ck "glossary: floor failures are listed apart from gate failures" grep -qi 'apart from gate failures' <<<"$sf"
ck "glossary defines Suppression" grep -qx '### Suppression' "$g"
sp=$(awk '/^### Suppression$/{f=1; next} /^### /{f=0} f' "$g")
ck "glossary: a suppression cites a SEC-NNN listed in suppresses:" bash -c 'grep -q "SEC-NNN" <<<"$1" && grep -q "suppresses:" <<<"$1"' _ "$sp"
db=$(awk '/^### Dependabot exemption$/{f=1; next} /^### /{f=0} f' "$g")
for w in verified web-flow '.github/' lockfile; do ck "glossary: Dependabot exemption states '$w'" grep -qF "$w" <<<"$db"; done
ck "glossary: the Dependabot entry no longer defers the rule to P4" no grep -qF "are P4's" <<<"$db"
cl=$(grep -F 'dependabot[bot]' .claude/rules/review-gate.md | head -1)
for w in verified web-flow '.github/'; do ck "review-gate.md claim row: Dependabot states '$w'" grep -qF "$w" <<<"$cl"; done
gb=$(awk '/Mechanical gates in CI/{f=1} /Verifier review, run locally/{exit} f' README.md)
ck "README gates bullet names the security floor and its separate report" bash -c 'grep -qi "security floor" <<<"$1" && grep -qi "floor failures" <<<"$1"' _ "$gb"
ck "CLAUDE.md project map names the floor scripts" bash -c 'grep -q run-security-floor.sh CLAUDE.md && grep -q check-suppressions.sh CLAUDE.md && grep -q install-pinned-tool.sh CLAUDE.md'
ck "docs/security/README.md explains Tools run and suppresses:" bash -c 'grep -q "Tools run" docs/security/README.md && grep -q "suppresses:" docs/security/README.md'
```

- [ ] **Step 2: Run** `bash tests/governance/test_onboarding_surface.sh`. Expected: the new checks FAIL (the glossary's Security floor has no tool names, there is no Suppression entry, the Dependabot entry says "are P4's", …), exit 1.
- [ ] **Step 3: Implement (intent).** Per Interfaces. `bash tests/governance/test_review_gate_claims.sh` must stay green (every file named in the claim table exists).
- [ ] **Step 4: Run** the test, `bash tests/governance/test_review_gate_claims.sh` and the gates — green.
- [ ] **Step 5: Commit** — "docs: the security floor, suppressions and the Dependabot rule as shipped — glossary, README, claim table, CLAUDE.md (REQ-330, REQ-334, REQ-388)"

---

### Task 15: Whole-branch verification and the IMPLEMENT PR body

- [ ] **Step 1:**
  - `time PATH="$TMPDIR/p4-gates/bin:$PATH" bash scripts/run-quality-gates.sh` — green, under 3 minutes (1:42 before P4); record it.
  - `SPECFLOW_FLOOR_OFFLINE=1` run once — green, with SKIP lines.
  - `actionlint .github/workflows/*.yml` — clean.
  - `git grep -nE '(^|[ (])python[ ]+-m' -- scripts tests stacks` — empty.
  - `git grep -nF -e --jq -- scripts` — empty.
- [ ] **Step 2:** `bash scripts/verify-doc.sh docs/plans/2026-09-26-factory-v3-2-p4-plan.md` (silent), `bash scripts/analyze-adr-plan-linkage.sh`, `bash scripts/check-traceability.sh`, `bash tests/governance/test_plan_template.sh`, `bash scripts/check-architecture.sh`, `bash scripts/check-suppressions.sh` — all pass.
- [ ] **Step 3: Opt-in runs on this Mac (network; record each wall-clock):**
  - `PINNED_TOOLS_LIVE=1 bash tests/governance/test_pinned_tools.sh` (about 5 s).
  - `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="guided engineer profiles packfloor" bash tests/governance/test_first_run.sh` (about 3 minutes).
  - With `--doctor` clean for the app stacks, `FIRST_RUN_CASES="tauri flutter"` (about 15 and 10 minutes, per P1b).

  A `SKIP: <stack> — missing …` line is recorded as "not run, why", never as green.
- [ ] **Step 4:** No real tool in the tests: `git grep -nE '^(gitleaks|osv-scanner|cargo audit|npm audit|pip-audit) ' -- tests/governance` shows only the opt-in `packfloor` case. `git diff main --stat` touches only the files named in Tasks 1–14. `git status --porcelain` is empty.
- [ ] **Step 5: IMPLEMENT PR body** (`--body-file "$(mktemp)"`; base `main`, or the plan branch when stacked). It states:
  - the Partial claims, and which plan relists each open clause;
  - the rulings R1–R15, including the flag differences from the REQ text (Interfaces "Pinned tool invocations");
  - **Architecture-artifact updates:** Task 12 (the demo threat model's checklist, v3.2 `:183`) and Task 13 (dfe-2, dfe-4, dfe-11, dfe-13, the narrative, the overview's P3/P4/P5 notes), named as such;
  - the H1–H17 disposition, including H16's corrected premise;
  - the SHAs pinned (Task 3's table), noting any tag that moved;
  - the measured times: default gates (before and after), each opt-in case, and the CI minutes from this PR's first CI run — the ubuntu `gates` job before and after (the floor-tool install from cold and from cache, and the floor run), the two first-run jobs, and, if `app-stacks.yml` ran on the pack paths, the tauri job with a cold `cargo install cargo-audit` and its warm re-run (`gh workflow run app-stacks.yml --ref <branch>` a second time);
  - **what the user will see:**
    - *Every gates run now needs gitleaks and osv-scanner* (`bash scripts/init-project.sh --doctor` names them) and the network. Offline, the floor prints `lookup failed` (never "findings"); `SPECFLOW_FLOOR_OFFLINE=1` works offline, but its summary cannot feed `/security-review`.
    - *The template's own floor goes red on 2026-12-24*, when the tauri skeleton's `ignoreUntil` passes — by design (the Ruling on expiry), and for osv-scanner, cargo-audit and npm alike; the floor warns from 30 days before. `/retrospective` (or the next tauri pin bump) re-enumerates: prune the advisories that are gone, and re-accept the rest in a new skeleton disposition entry.
    - *Dependabot opens PRs weekly.* Those touching only `scripts/requirements.*` with verified GitHub-signed commits pass `verifier` without a marker. Every `github-actions` PR edits `.github/workflows/**`, so it needs a verifier run. When the first Dependabot PR arrives, record its commits' `committer.login` and `verification.verified` (`gh api repos/kpingali123/factory/pulls/<n>/commits`, parsed with `python3`) in the PR thread; this measures the dfe-13 assumption.
    - *Nothing changes for `prompt_sha256`*: open PRs keep their markers.

---

## Review Focus

1. **The Dependabot rule on four PRs.**
   - Verified `web-flow` commits touching `src-tauri/Cargo.lock` and `package-lock.json`: exempt (fixture 42).
   - The same PR plus a `uses:` bump in `.github/workflows/ci.yml`: needs attestation (`workflow-path`, fixture 40).
   - A human's commit authored as `dependabot[bot]` from the command line (unverified): not exempt (`unverified`, fixture 36).
   - A PR touching `.github/dependabot.yml`: not exempt (fixture 43; R11's exclusion).
   - Verified `web-flow` commits that add `--extra-index-url` to `scripts/requirements.txt`, or a `[patch]` git source to `src-tauri/Cargo.toml`: not exempt (content rules, fixtures 48 and 50) (dfe-13; Task 10).
2. **A PR that adds `"RUSTSEC-2099-0003",  # SEC-001` to `src-tauri/audit.toml`** while SEC-001's `suppresses:` lists only `RUSTSEC-2099-0001`: `check-suppressions.sh` fails ("the ignore set grew"). So does a `[[PackageOverrides]] ignore = true` in `osv-scanner.toml`, a `src/.bandit` with `skips`, or a second `# nosec` riding on an accepted SEC. A PR that widens `.gitleaks.toml` fails the same check, and its verifier findings scan still receives the base's config (REQ-388, dfe-11; Tasks 4, 8).
3. **The floor inside `.claude/worktrees/p4`** (nested under the main checkout's ignored path): `osv-scanner scan source -r .` would visit one directory and exit 128, a false clean. The floor's `git ls-files` list scans `scripts/requirements.txt` and every pack lockfile, and a 128 with tracked lockfiles is a FAIL (R3; Task 5).
4. **A fresh python instance on ubuntu CI, and the same instance with `black==25.12.0` planted in `requirements.txt`.** The clean instance shows `PASS floor` lines for gitleaks, osv-scanner, pip-audit (`requirements.txt`) and bandit (`src`). With the planted pin, the summary lists `FAIL floor osv-scanner` and `FAIL floor pip-audit` under "Floor failures", with "Gate failures: none" (REQ-360; Tasks 5, 7).
5. **cargo-audit and the P1b `src-tauri/audit.toml`.** Without P4's `--ignore` flags, the file is dead config: 7 denied warnings, exit 1 (R4, measured). `packfloor` proves the ignores are both effective and still needed (Tasks 7, 8).
6. **The v3.2 threat model's "Update channel for apps | N/A for the factory itself …" row:** `check-architecture.sh` fails on it before Task 12's edit, and on any `| Session | later |`. A spec that no plan names yet is not checked, so a design lane mid-ARCHITECTURE is never red (REQ-333; Task 12).

## Deferred by design

- **Open clauses of claimed REQs** are listed under **Partial claims**, each with the plan that lists the REQ again:
  - P3: the CVSS block schema and the migration of the demo and skeleton security docs; REQ-320's `implements:` scoping; `confirmed_by:`.
  - P5: `next.sh` shares `attestation.py`.
  - P6: `release.yml`'s job-level elevation, and the tag-time replay of the Dependabot rule (REQ-350).
- **Version-only downloads** (R15): Node via `setup-node`, Python via `setup-python`, the `rustup` toolchain, the Dart SDK and engine artifacts, Homebrew formulas, the `sh.rustup.rs` installer, and npm itself. REQ-330 limits P4 to the floor, Rust and Python tools. P7 closeout records them in v3.2's known-limitations.
- **Dependabot for instance lockfiles** (pip at `/` for python, npm and cargo for tauri, pub for flutter) and for the composite actions' `uses:` lines. The template's `dependabot.yml` covers what REQ-334 names; `/retrospective` bumps the pack actions meanwhile. This goes to the P7 backlog, because an app instance's Dependabot PRs would each cost macOS minutes.
- **Offline advisory databases** (`osv-scanner --offline-vulnerabilities` with a cached DB, cargo-audit `--no-fetch --stale`) are not adopted. An offline floor is a loud SKIP, not a stale answer.
- **The dfe-13 spoofing question** (whether GitHub signs an API-created commit with Dependabot's author address and committer `web-flow`) is measured only by observing real Dependabot PRs (Task 15's note). P6's tag-time re-check replays the rule.
- **`art-review-gate`'s Dependabot sentence** goes to constitution amendment B (P5, REQ-343). P4 changes no constitution text.
- **`pull_request_target`** (P2's residual: a PR edits its own workflow) is unchanged. A PR that edits `ci.yml` to skip the floor is gate code, which code mode flags. P6's tag-time checks run from `main`.
