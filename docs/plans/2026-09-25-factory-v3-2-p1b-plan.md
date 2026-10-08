---
type: plan
phase: PLAN
spec: 2026-09-25-factory-v3-2
decisions: []
implements: [REQ-303, REQ-304, REQ-306, REQ-360, REQ-300, REQ-305, REQ-308]
created: "2026-09-25"
---

# Factory v3.2 — P1b: App Stack Packs (Tauri + Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** `bash scripts/init-project.sh --stack tauri` (or guided choice 1) and `--stack flutter` (or guided choice 3) produce an instance on `main` whose skeleton passes `run-quality-gates.sh` on this Mac with no hand edits, whose `scripts/release-<stack>.sh` builds a macOS bundle (Tauri `.dmg`, Flutter zipped `.app`) and writes `dist/manifest.json`, whose app starts and exits 0 under `SPECFLOW_SMOKE=1`, and whose CI runs on the right runner. The template's default gates and its ubuntu CI stay toolchain-free and under 3 minutes.

**Architecture:** two more packs beside `stacks/python/`, same contract (`init.sh`, `gates.sh`, `security.sh`, `release.sh`, `action.yml`, `pack.yml`, plus `store-checklist.md`), each with an `overlay/` applied on top of the pinned generator's output. Lockfiles are generated once at pin time and shipped in the overlay, so the advisory lists describe exactly what an instance gets. Package-name rules move from `init-project.sh` into each pack (`init.sh package`), and each pack checks its scaffold prerequisites (`init.sh preflight`) before init writes anything. The generators are verified by content hash before they run: `create-tauri-app` against the npm `dist.integrity` recorded in `pack.yml`, the Flutter SDK against its pinned `frameworkRevision`. A test-only `SPECFLOW_NO_SCAFFOLD=1` lets the ubuntu jobs and default gates exercise app-stack init without node, Rust or Flutter. Everything that compiles Rust, runs `flutter`, or fetches a generator is opt-in (`SPECFLOW_FIRST_RUN=1` on Darwin, or an explicit `FIRST_RUN_CASES` entry) and runs weekly and on pack changes in a new `macos-15` workflow.

**Plan style (REQ-380):** test code included; implementation as intent, never bodies. Skeleton test files (`greet.test.ts`, the Rust `#[cfg(test)]` module, `widget_test.dart`) are tests and are given in full; the code they test is intent.

**Tier:** regulated path (REQ-381: P0–P5 walk `phase/*`, `impl/*`); tasks, not `## Build N`. This plan merges alone on the PLAN-phase PR from `phase/plan-factory-v3-2-p1b`. After it merges, `impl/plan-1b-app-packs` is cut from the updated `main` and carries Tasks 1–10 as the IMPLEMENT-phase PR. No task starts before the PLAN PR merges.

**Spec:** `docs/specs/2026-09-25-factory-v3-2-design.md`, "Must Have — P1". Nothing here is `[verifiable*]`: `decisions: []`, no proof owed.

**Partial claims:** `docs/plans/2026-09-25-factory-v3-2-p1a-plan.md` ("Partial claims") handed P1b these clauses, which this plan claims by listing the REQ again: REQ-300 `--stack tauri|flutter` and guided options (1)/(3); REQ-303 the tauri and flutter packs; REQ-304 the tauri and flutter skeletons; REQ-305 the tauri and flutter `release.sh`; REQ-308 the tauri and flutter prerequisites; REQ-360 the `macos-15` gate runs and the ubuntu profile diff for app stacks. REQ-306 is listed for its app-stack test surface (Task 3, Task 5). After P1b these clauses stay open, each claimed again by the named plan: REQ-303 — floor tools in every pack's `action.yml` and their CI wiring → P4 (REQ-330). REQ-306 — `test_traceability.sh` delegating to `check-covers.sh` → P3 (REQ-323); removing the REQ-391 example when `stack != tauri` → P7. REQ-308 — `/next` linking a glossary term on first use → P5. REQ-360 — the floor half of "floor failures reported separately" becomes a CI signal only when P4 installs `cargo-audit`/`osv-scanner` in the pack actions (P1b's first-run runs them when they are on `PATH`, Tasks 4 and 6). REQ-300, REQ-304 and REQ-305 have no clause left open. Room left without implementing: REQ-321 (`source_roots`, `test_globs` in each `pack.yml`), REQ-325 (`coverage_exclude`; thresholds and Flutter's `lcov-threshold.sh` are P3), REQ-331 (`security.sh` stays the P4 stub; `src-tauri/audit.toml` is written in `cargo-audit`'s own schema), REQ-388 (the `SEC-NNN` citation on each suppression is P4's), REQ-352/386/390 (`store-checklist.md` fixes the secret names and the release job appends it, signs and smoke-tests in P6; P1b's first-run already launches the built app under `SPECFLOW_SMOKE=1`). REQ-334's first clause (`*.lock` out of `.gitignore`) lands early in Task 4 because the skeletons need it; P4 still claims REQ-334.

**Verified against:** 2026-09-25 @ main `d17106e`; every `file:line` anchor was checked there. Toolchain facts were measured on this Mac the same day (macOS 27.0, Xcode 27.0 `27A266a`, node 24.8.0, rustc 1.93.1, Flutter 3.35.5, CocoaPods 1.16.2) in a scratch directory: `create-tauri-app@4.7.4 --template vanilla-ts` scaffolds in under 1 s; `npm install` 4 s; `cargo test` in `src-tauri` 19 s cold (warm `~/.cargo` registry), 2 s warm; `npm run tauri -- build --bundles dmg` 102 s, producing one `<name>_0.1.0_aarch64.dmg`; `flutter create --platforms=macos --no-pub` under 1 s, `flutter pub get` 1 s, `dart analyze --fatal-infos` 2 s, `flutter test` 4 s; `flutter build macos --release` **fails** on Xcode 27 as generated (`MACOSX_DEPLOYMENT_TARGET 10.15`; supported range 12.0–27.0), then fails again at `release_unpack_macos` because Xcode 27's `lipo` accepts one arch per `-verify_arch` and Flutter 3.35.5 passes `arm64 x86_64`; with the target at 12.0 and `ARCHS = arm64` in `macos/Runner/Configs/Release.xcconfig` it builds in 17 s. `flutter create` writes no `macos/Podfile` for a plugin-free app; with the Podfile added and no plugins, `flutter build macos --release --no-pub` runs no `pod install` and leaves a committed tree clean (measured). `flutter create --no-pub` writes no `macos/Flutter/GeneratedPluginRegistrant.swift` although `project.pbxproj` refers to it; the first `flutter pub get` writes it (for a plugin-free app: the `FlutterMacOS` and `Foundation` imports and an empty `RegisterGeneratedPlugins`). `flutter --version --machine` reports `frameworkRevision` `ac4e799d237041cf905519190471f657b657155a` for 3.35.5, and `packages/flutter_tools/lib/src/commands/create_base.dart:641-713` holds the `_keywords` set (69 names) and `_packageDependencies` (`collection`, `flutter`, `flutter_test`, `meta`) that `flutter create` refuses. `npm view <pkg>@4.7.4 dist.integrity` gives `sha512-7ZXpBxtl+eA3/ZFHWRbp+PpVxU78bpEqOJYa36Jw3mbgXq6GfsGAqDGtK5fEPHGtYwAjkFEDti4VHCauwEC4xg==` for `create-tauri-app` and `sha512-/9EhGCcfTYI4go/dFGa8rBZulwqYhz6kqlRtFZOcZaECiChry8xMRuEuFe1C3XLFIPBb0BE2uthZVF86binYyA==` for `create-tauri-app-darwin-arm64` (its native binary); `npm pack --ignore-scripts` of both, extracted into `node_modules/<name>` and run with `node node_modules/create-tauri-app/create-tauri-app.js …`, scaffolds the same tree as `npx`. `rustup toolchain list` shows only `stable` (1.93.1), so the first `cargo` run under the overlay's `rust-toolchain.toml` (`channel = "1.93.1"`) makes rustup 1.28.2 install a separate `1.93.1-aarch64-apple-darwin` toolchain (about 200 MB, tens of seconds); the 19 s above came from a directory without that file. The template's default gates take 21 s here; a python first-run case takes 5 s.

**Clause → task:** 300 `--stack tauri|flutter` 3+5 (package rule 1), guided (1)/(3) 1+3+5, Enter default unchanged 1, `--doctor` pack prereqs and missing pack 2 · 303 tauri pack 3, flutter pack 5, copy and delete exercised 1+4+6, `action.yml` wired into instance CI 7 · 304 tauri skeleton 3+4, flutter skeleton 5+6, lockfiles and `.gitignore` 4+6, advisory lists 4+6, `SPECFLOW_SMOKE` 3+5 (run 4+6) · 305 tauri `release.sh` 3+4, flutter 5+6 · 306 app-stack instances drop the demo 3+5 · 308 README/CLAUDE.md/GLOSSARY 9, doctor 2, pack prereqs 3+5 · 360 macOS gate runs 4+6+8, ubuntu profile diff 8, floor versus gate 4+6, no inherited no-op jobs 7.

**P1a fresh-eyes findings handed to P1b:** H1 (`*.lock` drops the skeleton lockfiles) → Task 4. H2 (`--doctor --stack X` with no pack says `0 missing`) → Task 2. H3 (python-only name rules and the ruff/black doctor check applied to every stack) → Task 1 (names) and Task 2 (doctor). H4 (CLAUDE.md is identical across profiles) → decided: init renders a `- Profile:` line into `CLAUDE.md` (Task 1), and the ubuntu job asserts the two profiles differ in exactly `.specflow.yml` (`profile:`), `CLAUDE.md` (`- Profile:`) and `IDEA.md` (`## Stack`) and are otherwise byte-identical (Task 8). H5 (instances inherit `First run` jobs that install Dafny, then skip) → Task 7: template-only jobs sit between markers that init deletes, `app-stacks.yml` is deleted, so instances inherit neither the old nor the new no-op jobs. H6 (lines pending on `chore/p1a-review-fixes`) → Global Constraints; Task 2 wraps `init-project.sh:129-136` without editing them, Task 9 inserts README text before `### Python` (`README.md:225`), Tasks 7–8 edit `test_workflow_health.sh` away from the chore's check 9 insertion point; `run-quality-gates.sh` is not edited at all. README references to the demo (F-13) stay: the demo is the python instance's worked example and init already removes it, with its manifest entry, from app instances; `README.md:65-72` says so in general terms.

## Core gates in an app instance

`run-quality-gates.sh` needs no change (and `:21` is H6-frozen). In a tauri or flutter instance: §1 (`:18-29`) finds `tests/unit/test_render_dashboard.py` — the factory's own test, which ships to every instance — so pytest runs, and `python3` + `pytest` are prerequisites on every stack (the factory's scripts are Python; `--doctor` reports them, Task 2). Until `chore/p1a-review-fixes` merges, §1 calls bare `python -m pytest` (`:21`, H6-frozen), so an app instance also needs a `python` on `PATH` that has pytest (an activated `.venv`, as README's Python section says); after the chore it is `python3`. §2 (`:31-50`) prints `SKIP dafny`: init removes `verification/demo_greeting/` with the python example (`init-project.sh:430-442`) and `templates/example.dfy` is outside `verification/`. §3 (`:52-65`) runs the governance tests; template-only ones skip on `.specflow.yml`. §4 (`:67-88`) runs `scripts/quality-gates-<stack>.sh`, the pack's toolchain gate. So an app instance passes the core gates with no hand edits, and Tasks 4 and 6 prove it.

## Pins (2026-09-25)

`create-tauri-app` 4.7.4 (and `create-tauri-app-darwin-arm64` 4.7.4), each with its npm `dist.integrity` above · `@tauri-apps/cli` 2.11.5 · Rust 1.93.1 (`rust-toolchain.toml`) · Node 24.8.0 · Flutter 3.35.5 at `frameworkRevision` `ac4e799d237041cf905519190471f657b657155a` · macOS host 27.0 (Xcode 27, `xcode-select` at `/Applications/Xcode.app/Contents/Developer`, CocoaPods installed, Flutter darwin engine artifacts cached) · `vitest` and `@vitest/coverage-v8`: the exact version `npm view vitest version` returns at pin time (5.0.2 on 2026-09-25) · Flutter pack minimum macOS 12.0 · both packs build `arm64` only. CI runs on `macos-15` (never `macos-latest`).

## Global Constraints

From the spec: **Performance** — `run-quality-gates.sh` on a fresh instance under 3 minutes on ubuntu (python) excluding downloads; app-stack gate runs on `macos-15` under 10 minutes with warm caches; a free private repository has about 200 macOS minutes a month and one Tauri release costs about 100, so app first-run tests are scheduled and path-filtered, never per-PR. An app *instance* is different: its required gates job runs on `macos-15` for every PR push (Task 7), about 3–5 of those minutes per run, so a free private instance repository gets roughly 40–60 gate runs a month (public repositories run free); README states this (Task 9). The warm-cache target is measurable only because `app-stacks.yml` caches a fixed `CARGO_TARGET_DIR` and the cargo registry (Task 8); cold and warm timings go in the PR body. **Security** — no API key anywhere; workflows read-only by default (the new workflow declares `permissions: contents: read`). The spec requires every CI tool download pinned by version and checksum. P1b pins what it adds by content hash: `create-tauri-app` and `create-tauri-app-darwin-arm64` by the npm `dist.integrity` (sha512) recorded in `pack.yml`, verified by `init.sh` before anything from them runs, on the founder's Mac and in `app-stacks.yml`; the Flutter SDK by `frameworkRevision` (a git commit id), verified after the clone in the pack action and doctor hint and before every scaffold; skeleton dependencies by the shipped lockfiles' integrity fields (`package-lock.json` sha512, `Cargo.lock` checksums, `pubspec.lock` sha256), enforced by `npm ci`, `cargo --locked`/`--frozen` and `pub get --enforce-lockfile`. **Exception, time-boxed to P4 (REQ-330, REQ-334; threat model dfe-4, substituted binary):** until P4 merges, these stay pinned by version only and P1b does not claim compliance for them — Node via `actions/setup-node`; the Rust toolchain via `rustup` (rustup checks its channel manifest's hashes, not a template-held one); the Dart SDK and engine artifacts the pinned Flutter SDK downloads on first run (keyed by that revision's `engine.version`); Homebrew formulas and the rustup installer in doctor hints; every GitHub Action by tag. The PR body lists them (Task 10) and "Deferred by design" hands them to P4. **Scalability** — a stack is one directory plus its governance-test entry. **Compliance** — `constitution.md` is not touched. **Scope** — only macOS desktop bundles are built; code signing, notarization and store submission are a documented checklist with hook points and secret names, not automation; Node is Tauri's frontend toolchain, not a stack. **Assumption** — the pins above; the skeleton is expected to break when a pin is bumped, and REQ-360 separates floor failures from gate failures. **REQ-380** — gates apply to implemented REQs only.

Plan-level (P1a's, still in force):
- Python inside scripts is stdlib-only and is always invoked as `python3`; `config.py` and `examples.py` stay flat parsers. `tomllib` (3.11+) is stdlib.
- bash 3.2 (macOS): no associative arrays, `mapfile`, `${v,,}`, or possibly-empty arrays under `set -u`; no coreutils `timeout` (absent on macOS — use `run_within`, Task 4); prompts via `printf` to stderr and `read -r`.
- **Instance** = `.specflow.yml` or legacy `.stack` present, else **template source**; template-only tests skip in instances.
- Gates stay green on the template source after every task; `analyze-adr-plan-linkage.sh` and `check-traceability.sh` are untouched; `review-gate.md` is untouched.
- No `verify-doc.sh`-flagged markers in plans; tests spell double-brace placeholders via `ph` or `printf`.
- New tests carry `# Covers: REQ-NNN` and source `tests/governance/lib/check.sh` (`$ROOT`, `pass`, `fail`, `ck`, `no`, `instance`, `finish`, `copy_template`, fixed git identity).
- One commit per task: check `git status`, stage the task's files, commit with the given message; every commit body ends with the `Co-Authored-By:` trailer line given to the executing session.

Plan-level (new in P1b):
- **Opt-in toolchain rule.** Anything that compiles Rust, runs `flutter`, or fetches `create-tauri-app` runs only under `SPECFLOW_FIRST_RUN=1` on Darwin **when `--doctor` reports none of that pack's `prereqs:` missing** (otherwise the case prints `SKIP: <stack> — missing <prereqs>` and is not run), or when `FIRST_RUN_CASES` names the case explicitly. Default gates and ubuntu CI stay toolchain-free: the new default-gate checks are static or use fake `npm`/`node`/`flutter`/`ditto` on `PATH`, and they exercise the scaffold and release contracts behaviourally, not only by grep.
- **H6 freeze.** Do not edit `run-quality-gates.sh:21`, `test_python_lint_format.sh`, `init-project.sh:119,123,134`, `README.md:225-249`; new code calls `python3`; `test_workflow_health.sh` gains nothing after check 8 (the chore appends check 9 there).
- **Pack `init.sh` contract.** Three subcommands, cwd = target, env `SPECFLOW_NAME`, `SPECFLOW_PKG`; any other subcommand exits 2. `package` prints the final package (or refuses, exit 2; no writes, no network). `preflight` checks everything `scaffold` needs (tools, versions, platform, generator download and integrity) and writes nothing in cwd; it prints one stderr line `preflight: missing <item>: <hint>` per gap plus a last line naming `bash scripts/init-project.sh --doctor --stack <stack>`, and exits 1 on any gap; init calls it before any write. `scaffold` checks every destination before copying and, on any clash, exits 1 naming the path and writes nothing; generators never run `git init`; the generated root `README.md` and `.gitignore` are skipped; the `# >>> specflow <stack> pack` block is appended to `./.gitignore` only when absent; `__PKG__`/`__NAME__` are substituted only in overlay files (all text) — generated files are copied byte for byte except the pack's named rewrites. Packs read their own pins from `pack.yml` through `$HERE/../../scripts/lib/specflow/config.py`, never hard-coded.
- **Release hooks make no network calls** (`scripts/release-stack.sh.template:17`): cargo runs `--frozen`, `flutter build` runs `--no-pub`; the gates (`npm ci`, `cargo test --locked`, `pub get --enforce-lockfile`) fetch beforehand.

## Review Focus

1. `--stack tauri --name Calendar` with `SPECFLOW_NO_SCAFFOLD=1` → exit 0, package `calendar`; `--stack python --name Calendar` → exit 2 naming the standard library (Task 1; Task 3).
2. `--doctor --stack flutter` in a copy with no `stacks/flutter/` → `MISSING pack flutter: …`, exit 1; the same in a python instance → exit 1 naming python (Task 2).
3. On this Mac, `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=tauri`: Enter, Enter, `1`, Enter → guided tauri instance with committed `package-lock.json` and `src-tauri/Cargo.lock`, gates green, manifest with exactly one `.dmg`, the release binary exits 0 within 60 s under `SPECFLOW_SMOKE=1`, tree still clean (Task 4).
4. Flutter instance: every `MACOSX_DEPLOYMENT_TARGET` is 12.0, `macos/Podfile` says `platform :osx, '12.0'`, `Release.xcconfig` has `ARCHS = arm64` → `flutter build macos --release` succeeds on Xcode 27, which it measurably does not without them (Task 5; Task 6).
5. A fresh python instance's `ci.yml` has no `First run` or profile job, there is no `app-stacks.yml`, the gates job keeps its required-check name, and `test_workflow_health.sh` passes inside the instance (Task 7).
6. Guided choice 1 on a Mac without node → init exits 1 with `preflight: missing node` and the `--doctor` line, and the copy has no `.specflow.yml` and no `.git` (Task 1; Task 3). A `create-tauri-app` tarball whose sha512 differs from `pack.yml` is refused before it runs (Task 3).

---

### Task 1: Package rules move into the packs; scaffold preflight before any write; `SPECFLOW_NO_SCAFFOLD`; the profile line

**Files:** modify `scripts/init-project.sh` (`:298-347` stage c; `:349` progress line; `:413-415` scaffold; `:447-453` doc loop and its comment), `stacks/python/init.sh` (new `package` and `preflight` subcommands; header `:1-8`), `CLAUDE.md:14-20` (a `- Profile:` line carrying the PROFILE placeholder in PROJECT_NAME's double-brace form), `tests/governance/lib/check.sh` (`stub_pack`), `tests/governance/test_init.sh` (`:29`; new case 9), `tests/governance/test_template_instantiation.sh` (after `:60-64`), `tests/governance/test_stack_packs.sh` (append), `tests/governance/test_examples.sh:37-40` (case 4's hand-built stub becomes `stub_pack`).

**Interfaces:**
- `stacks/<stack>/init.sh package` — env `SPECFLOW_NAME` (already matched by init's name regex) and `SPECFLOW_PKG` (init's candidate: lowercased, runs of non-`[a-z0-9]` → `_`, trimmed, `app_` before a leading digit, as `:304-307` today); cwd = target. Prints the final package on stdout and exits 0, or prints one stderr line naming the cause and exits 2. Pure bash + `python3` stdlib; no toolchain, no network, no writes.
- Python's rule is today's `:309-342` moved verbatim in behaviour: 40-character cap and trailing-`_` trim, refusal when `src/<pkg>` exists, refusal of a Python keyword, a standard-library module name, or `pytest`, with the same wording ("a Python keyword", "a Python standard-library module name", "the pytest package name").
- Init stage c order, all before any write: name regex (`:300-302`, core, stack-neutral — it guards the `sed` substitutions) → pack presence (`:344-347`, moved up; exit 2 naming `stacks/<stack>/`) → candidate → `bash "$STACK_DIR/init.sh" package` (its exit 2 and stderr line propagate) → init validates the printed package: empty output, more than one line, or anything not matching `^[a-z][a-z0-9_]*$` is refused with exit 2 (`init: stacks/<stack>/init.sh package printed an invalid package '<out>'`) → unless `SPECFLOW_NO_SCAFFOLD=1`, `bash "$STACK_DIR/init.sh" preflight` (on failure its stderr lines pass through, init adds `init: nothing was written — install what is missing (bash scripts/init-project.sh --doctor --stack <stack>) and re-run` and exits 1). The progress line becomes `Initializing '<name>' (package <pkg>; <profile> profile, <stack> stack, <path> path)...`. (P1a's non-atomic init, review F-3, stays with the patch tier; the preflight removes the likely app-stack causes.)
- Python's `init.sh preflight` exits 0 (its scaffold needs only bash and `sed`); its header comment documents all three subcommands.
- `SPECFLOW_NO_SCAFFOLD=1` (test-only; documented in init's header comment and README's Scripts table in Task 9): init does everything except `init.sh preflight` and `init.sh scaffold` and prints `SKIP scaffold (SPECFLOW_NO_SCAFFOLD=1: test-only; this instance has no skeleton)` to stderr. The pack hooks, action, `pack.yml`, checklist, examples step and commit still happen.
- `CLAUDE.md` `## Stack` gains `- Profile: <placeholder>` after the Language line; init's `for doc in` sed gains a fourth `s/…/…/g` for the PROFILE placeholder with `guided — Claude proposes technical decisions with a plain-English rationale; you confirm and merge` or `engineer — you make the technical calls; Claude implements and reviews` (escaped with `escape_sed`). Keep the loop and the `s/` form that `test_template_instantiation.sh:29-58` parses.
- `check.sh` `stub_pack DIR STACK CHOICE LABEL` — replaces `DIR/stacks/STACK` with a toolchain-free stand-in (python's hooks, an `init.sh` whose `package` echoes the candidate and whose `preflight` and `scaffold` exit 0, a stub checklist, a complete `pack.yml` including `ci_runs_on`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/governance/lib/check.sh`:

```bash
stub_pack() {  # stub_pack DIR STACK CHOICE LABEL — a toolchain-free stand-in for DIR/stacks/STACK
  local p="$1/stacks/$2"; rm -rf "$p"; mkdir -p "$p"
  cp "$1"/stacks/python/{gates.sh,security.sh,release.sh,action.yml} "$p/"
  printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in package) echo "$SPECFLOW_PKG" ;; preflight|scaffold) exit 0 ;; *) exit 2 ;; esac' > "$p/init.sh"
  chmod +x "$p/init.sh"; echo '# stub' > "$p/store-checklist.md"
  printf 'stack: %s\nguided_choice: %s\nguided_label: %s\nguided_rationale: stub rationale for %s\ntesting: stub testing line\nci_runs_on: ubuntu-latest\nsource_roots: [src]\ntest_globs: [src/**/*.test.ts]\ncoverage_exclude: []\nprereqs: []\n' "$2" "$3" "$4" "$2" > "$p/pack.yml"
}
```

In `tests/governance/test_init.sh`, line 29 becomes `for p in PROJECT_NAME STACK TESTING PROFILE; do …` (same body). Add a helper after `:15` and case 9 before `finish`:

```bash
ninit() { local d="$1"; shift; (cd "$d" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh "$@" </dev/null 2>&1); }
```

```bash
# 9. Package rules are pack-owned (H3); SPECFLOW_NO_SCAFFOLD skips only the skeleton; the profile is rendered (H4).
D="$WORK/pkgrule"; copy_template "$D"; stub_pack "$D" tauri 1 'a Mac desktop app'
rc=0; out=$(ninit "$D" --name Calendar --stack tauri) || rc=$?
ck "a non-python pack may take the name Calendar (exit 0)" [ "$rc" = 0 ]
ck "the package comes from the pack's rule" grep -q 'package calendar' <<<"$out"
D="$WORK/pkgrefuse"; copy_template "$D"; stub_pack "$D" flutter 3 'a multi-platform app'
printf '%s\n' '#!/usr/bin/env bash' '[ "${1:-}" = package ] && { echo "package name reserved by the stub pack" >&2; exit 2; }' 'exit 0' > "$D/stacks/flutter/init.sh"
rc=0; out=$(init "$D" --name Anything --stack flutter) || rc=$?
ck "a pack's package refusal exits 2" [ "$rc" = 2 ]
ck "the refusal carries the pack's reason" grep -q 'reserved by the stub pack' <<<"$out"
ck "the refused run wrote nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" ]
D="$WORK/emptypkg"; copy_template "$D"; stub_pack "$D" tauri 1 'a Mac desktop app'
printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in package) echo "${STUB_PKG_OUT-}" ;; *) exit 0 ;; esac' > "$D/stacks/tauri/init.sh"
for bad in '' 'Bad-Name' '1abc'; do
  rc=0; (cd "$D" && STUB_PKG_OUT="$bad" SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Anything --stack tauri </dev/null >/dev/null 2>&1) || rc=$?
  ck "init refuses the pack's package output '$bad' (exit 2)" [ "$rc" = 2 ]
done
ck "a refused package output wrote nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" ]
D="$WORK/preflight"; copy_template "$D"; stub_pack "$D" tauri 1 'a Mac desktop app'
printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in package) echo "$SPECFLOW_PKG" ;; preflight) echo "preflight: missing node: stub hint" >&2; exit 1 ;; *) exit 0 ;; esac' > "$D/stacks/tauri/init.sh"
rc=0; out=$(init "$D" --name Anything --stack tauri) || rc=$?
ck "a failed scaffold preflight exits 1" [ "$rc" = 1 ]
ck "the preflight's reason is shown" grep -q 'preflight: missing node: stub hint' <<<"$out"
ck "init points at --doctor after a failed preflight" grep -qF -- '--doctor --stack tauri' <<<"$out"
ck "the failed preflight wrote nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" ]
ck "SPECFLOW_NO_SCAFFOLD=1 skips the preflight (exit 0)" [ "$(rc_of ninit "$D" --name Anything --stack tauri)" = 0 ]
D="$WORK/noscaffold"; copy_template "$D"; out=$(ninit "$D" --name Bare --profile engineer) || true
ck "SPECFLOW_NO_SCAFFOLD=1: config written" test -f "$D/.specflow.yml"
ck "SPECFLOW_NO_SCAFFOLD=1: pack hooks installed" test -x "$D/scripts/quality-gates-python.sh"
ck "SPECFLOW_NO_SCAFFOLD=1: no skeleton" no test -e "$D/pyproject.toml"
ck "SPECFLOW_NO_SCAFFOLD=1: says so" grep -q 'SKIP scaffold' <<<"$out"
ck "engineer profile rendered into CLAUDE.md" grep -q '^- Profile: engineer' "$D/CLAUDE.md"
ck "guided profile rendered into CLAUDE.md" grep -q '^- Profile: guided' "$WORK/enter/CLAUDE.md"
D="$WORK/menu"; copy_template "$D"; stub_pack "$D" tauri 1 'a Mac desktop app'; stub_pack "$D" flutter 3 'a multi-platform app'
out=$(cd "$D" && printf '\n\n1\n\n' | SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh 2>&1) || true
ck "guided menu lists (1) (2) (3) in order" python3 -c '
import re, sys
got = re.findall(r"^  \((\d)\) (.+)$", sys.stdin.read(), re.M)
sys.exit(got != [("1", "a Mac desktop app"), ("2", "a web service or command-line tool"), ("3", "a multi-platform app")])' <<<"$out"
has "$D" profile=guided stack=tauri
ck "guided IDEA.md carries the chosen pack's rationale" grep -q 'stub rationale for tauri' "$D/IDEA.md"
```

In `tests/governance/test_template_instantiation.sh`, template branch, after `:60-64`:

```bash
  if grep -qF "$(printf '%s%s%s%s%s' '{' '{' PROFILE '}' '}')" CLAUDE.md && grep -qE 's/\{\{PROFILE\}\}/' scripts/init-project.sh; then
    pass "CLAUDE.md carries the PROFILE placeholder and init substitutes it"
  else
    fail "CLAUDE.md has no rendered profile line (H4)"
  fi
```

Append to `tests/governance/test_stack_packs.sh` before `finish` (the cwd there is `$W`):

```bash
# --- package rules are pack-owned (H3): init.sh package prints the package or refuses with exit 2 ---
rc_of() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
mkdir -p "$W/pk"
pkg() { (cd "$W/pk" && env SPECFLOW_NAME="$2" SPECFLOW_PKG="$3" bash "$1/init.sh" package 2>/dev/null); }
ck "python: package keeps a valid candidate" [ "$(pkg "$P" 'Acme Tools' acme_tools)" = acme_tools ]
ck "python: package caps the length at 40" [ "$(pkg "$P" Long "$(printf 'a%.0s' $(seq 1 50))" | wc -c | tr -d ' ')" = 41 ]
for n in calendar email class pytest; do ck "python: package '$n' refused (exit 2)" [ "$(rc_of pkg "$P" X "$n")" = 2 ]; done
mkdir -p "$W/pk/src/acme_tools"
ck "python: a package clashing with src/<pkg> is refused (exit 2)" [ "$(rc_of pkg "$P" X acme_tools)" = 2 ]
rm -rf "$W/pk/src"
ck "python: preflight needs nothing (exit 0)" bash -c "cd '$W/pk' && SPECFLOW_NAME=X SPECFLOW_PKG=x bash '$P/init.sh' preflight"
ck "python: an unknown subcommand exits 2" [ "$(rc_of bash -c "cd '$W/pk' && bash '$P/init.sh' frobnicate")" = 2 ]
```

In `tests/governance/test_examples.sh`, case 4's hand-built stub (`:37-40`: `rm -rf`, `mkdir`, `cp`, the `exit 0` `init.sh`, the `pack.yml` `printf`) becomes one line, so the stub answers `package` with a real package (the checks at `:41-43` stay):

```bash
D="$WORK/other"; copy_template "$D"; stub_pack "$D" tauri 1 'a Mac desktop app'
```

- [ ] **Step 2: Run them — expect** in `test_init.sh`: Calendar with the stub tauri pack exits 2 (today's core stdlib rule), so both case-9 name checks FAIL; the stub flutter pack's refusal is never consulted (init calls only `scaffold`, which exits 0), so the three refusal checks FAIL; the invalid package outputs are never read (the first run exits 0, the next two are refused as re-inits with exit 1), so all four `emptypkg` checks FAIL; the stub preflight is never called, so the first `preflight` run exits 0 and all five `preflight` checks FAIL (the `SPECFLOW_NO_SCAFFOLD` re-run is refused as a re-init); `SPECFLOW_NO_SCAFFOLD` is ignored, so `no skeleton` and `says so` FAIL while `config written` and `pack hooks installed` pass; both profile-line checks FAIL; the menu checks and the IDEA.md rationale pass already (P1a builds the menu from `pack.yml`; they pin the order for the real packs); line 29's PROFILE check passes vacuously. `test_template_instantiation.sh`: the PROFILE check FAILs. `test_stack_packs.sh`: `init.sh package` exits 2 today, so the four refusals, the clash and the unknown-subcommand check pass vacuously, and `keeps a valid candidate`, `caps the length` and `preflight needs nothing` FAIL. Exit 1 for all three (the `test_init.sh` and `test_stack_packs.sh` outcomes before this revision's added checks were confirmed on a scratch copy at `d17106e`). `test_examples.sh` stays green with `stub_pack` (today's init never calls `package`).

- [ ] **Step 3: Implement (intent)** — per Interfaces: python's `init.sh` gains `package` (the moved rules) and `preflight` (exit 0), `scaffold` unchanged; init's stage c calls `package`, validates its output, then `preflight`, all after the pack-presence check and before any write; preflight and scaffold are skipped under `SPECFLOW_NO_SCAFFOLD=1`; `CLAUDE.md` gains the Profile line and init substitutes it; the header comment names the new variable.

- [ ] **Step 4: Run** `for t in init template_instantiation stack_packs examples init_doctor first_run; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect all green (`test_init.sh:60-63` still refuses Calendar for python).

- [ ] **Step 5: Commit** — "feat(init): package rules are pack-owned and validated; scaffold preflight before any write; SPECFLOW_NO_SCAFFOLD test switch; profile rendered into CLAUDE.md (REQ-300, REQ-303, REQ-360)"

---

### Task 2: `--doctor` — a missing pack is MISSING (H2); ruff/black only for python (H3)

**Files:** modify `scripts/init-project.sh` (`:94-174` `run_doctor`: the stack/pack resolution at `:143-154` moves above `:129`; `:129-136` wrapped, not edited), `tests/governance/test_init_doctor.sh` (append before `finish`).

**Interfaces:**
- Doctor stack = `--stack`, else `.specflow.yml` via `config.py`, else `python` (as today). Pack file: in an instance, `.specflow/pack.yml` only when its `stack:` equals the doctor stack, else `MISSING pack <stack>: this instance was initialized with the <instance stack> pack (.specflow/pack.yml); a stack is chosen once, at init`; in the template source, `stacks/<stack>/pack.yml`, else `MISSING pack <stack>: stacks/<stack>/ is not present in this checkout`. Either counts as missing (exit 1).
- `:129-136` stay byte-identical inside a new `if [[ "$doctor_stack" == python ]]; then … else … fi`: python keeps the combined `pytest|ruff|black` check; every other stack gets `ok   python3 -m pytest` or `MISSING python3 -m pytest: python3 -m venv .venv && . .venv/bin/activate && pip install -r scripts/requirements.txt` (the core §1 runs the factory's own tests on every stack; the venv wording matches the chore branch).

- [ ] **Step 1: Write the failing test** — append before `finish test_init_doctor`:

```bash
# H2: a stack whose pack is absent is MISSING, never "0 missing".
D="$WORK/nopack"; copy_template "$D"; rm -rf "$D/stacks/tauri"
rc=0; out=$(cd "$D" && bash scripts/init-project.sh --doctor --stack tauri </dev/null 2>&1) || rc=$?
ck "doctor --stack tauri without its pack exits 1" [ "$rc" = 1 ]
ck "doctor names the missing pack" grep -qE '^MISSING pack tauri: .*stacks/tauri/' <<<"$out"
rc=0; out=$(cd "$WORK/inst" && bash scripts/init-project.sh --doctor --stack flutter </dev/null 2>&1) || rc=$?
ck "doctor in a python instance refuses another stack (exit 1)" [ "$rc" = 1 ]
ck "that refusal names the instance's stack" grep -qE '^MISSING pack flutter: .*python' <<<"$out"
# H3: ruff and black are the python pack's gate tools, not every stack's.
D="$WORK/stubdoc"; copy_template "$D"; stub_pack "$D" tauri 1 'a Mac desktop app'
out=$(cd "$D" && bash scripts/init-project.sh --doctor --stack tauri </dev/null 2>&1 || true)
ck "app-stack doctor checks pytest (the factory's own tests)" grep -qE '^(ok +|MISSING )python3 -m pytest' <<<"$out"
ck "app-stack doctor does not demand ruff or black" no grep -qE 'ruff|black' <<<"$out"
out=$(cd "$D" && bash scripts/init-project.sh --doctor --stack python </dev/null 2>&1 || true)
ck "python doctor still checks ruff and black" grep -qF 'pytest|ruff|black' <<<"$out"
```

- [ ] **Step 2: Run it — expect** the no-pack doctor to print `doctor: 0 missing` or only the tool gaps of this machine and never a `MISSING pack` line, so the exit-code (when everything else is installed) and pack-name checks FAIL; the python instance ignores `--stack flutter` and reads its own pack, so both instance checks FAIL; the stub tauri doctor prints `ok   python3 -m pytest|ruff|black`, so the pytest check passes and `does not demand ruff or black` FAILs; the python check passes. Exit 1.

- [ ] **Step 3: Implement (intent)** — per Interfaces; the only lines added around `:129-136` are the `if`, the `else` branch and the `fi`.

- [ ] **Step 4: Run** `bash tests/governance/test_init_doctor.sh && bash tests/governance/test_init.sh && bash scripts/run-quality-gates.sh` — expect green; `git diff main -- scripts/init-project.sh | grep -E '^-.*(119|123|134)'` shows nothing (confirm by eye that `:119`, `:123`, `:134` are untouched).

- [ ] **Step 5: Commit** — "fix(doctor): a missing pack is MISSING and exits 1; ruff/black checked only for the python pack (REQ-300, REQ-308)"

---

### Task 3: The tauri pack — files, pins, package rule, overlay, static contract

**Files:** create `stacks/tauri/` — `init.sh`, `gates.sh`, `security.sh`, `release.sh` (executable), `action.yml`, `pack.yml`, `store-checklist.md`, and `overlay/` with `package.json`, `vitest.config.ts`, `rust-toolchain.toml`, `osv-scanner.toml`, `src/lib/greet.ts`, `src/lib/greet.test.ts`, `src-tauri/src/commands.rs`, `src-tauri/src/lib.rs`, `src-tauri/audit.toml`. Modify `tests/governance/test_stack_packs.sh` (append), `tests/governance/test_examples.sh:37-44` (case 4 for tauri).

**Interfaces:**
- `pack.yml` — `stack: tauri`, `guided_choice: 1`, `guided_label: a Mac desktop app`, `guided_rationale: Tauri builds a small native Mac app from a TypeScript web UI and a Rust core; v3.2 builds, tests and ships the macOS bundle only.`, `testing: vitest (src/**/*.test.ts), cargo test (src-tauri), governance tests (tests/governance/)`, `ci_runs_on: macos-15`, `source_roots: [src, src-tauri/src]`, `test_globs: [src/**/*.test.ts, src-tauri/tests/**]` (REQ-321's same-file `#[cfg(test)]` rule is checker logic, P3), `coverage_exclude: [src-tauri/src/main.rs, src-tauri/src/lib.rs, src/main.ts]` (REQ-325), `lockfile: package-lock.json`, `lockfiles: [package-lock.json, src-tauri/Cargo.lock]`, `create_tauri_app_version: 4.7.4`, `create_tauri_app_integrity` and `create_tauri_app_darwin_arm64_integrity` (the two `sha512-…` values under **Verified against**, re-read with `npm view <pkg>@<version> dist.integrity` at pin time), `tauri_cli_version: 2.11.5`, `rust_version: 1.93.1`, `node_version: 24.8.0`, `vitest_version` and `vitest_coverage_version` (exact, at pin time), `macos_min: "10.13"` (Tauri 2's default `LSMinimumSystemVersion`, left as generated), `macos_archs: arm64`, `macos_host: "27.0 (Xcode 27, CocoaPods installed)"`, `prereqs: [xcode_clt, rustup, rust_toolchain, node]` with `check_xcode_clt: xcode-select -p` / `install_macos_xcode_clt: xcode-select --install`; `check_rustup: rustup --version && cargo --version` / `install_macos_rustup: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`; `check_rust_toolchain: rustup toolchain list | grep -q '^1\.93\.1-'` / `install_macos_rust_toolchain: rustup toolchain install 1.93.1 --profile minimal` (the overlay's `rust-toolchain.toml` would otherwise make the first `cargo` run install it silently, about 200 MB); `check_node: node --version | grep -q '^v24\.' && npm --version` / `install_macos_node: brew install node@24 && brew link --overwrite --force node@24`; every `install_linux_*`: `not supported: v3.2 builds app stacks on macOS only — use a Mac, or the macos-15 CI workflow`. Before committing, confirm each macOS formula with `brew info rustup node@24` (reads only).
- `init.sh package` — the candidate is kept unless it is a Rust keyword (strict and reserved, e.g. `match`, `fn`, `self`, `async`), a Cargo-reserved name (`std`, `core`, `alloc`, `test`, `proc_macro`), a Windows-reserved name (`con`, `prn`, `aux`, `nul`, `com1`–`com9`, `lpt1`–`lpt9`), or a skeleton dependency (`tauri`, `tauri_build`, `tauri_plugin_opener`, `serde`, `serde_json`); refusal exit 2 naming which.
- Generator fetch (shared by `preflight` and `scaffold`) — into `${XDG_CACHE_HOME:-$HOME/.cache}/specflow/create-tauri-app-<version>/`, when not already there: `npm pack --ignore-scripts --pack-destination <that dir> create-tauri-app@<version> create-tauri-app-darwin-arm64@<version>`; then each `.tgz` is checked with `python3` (`hashlib.sha512`, base64, `sha512-` prefix) against `create_tauri_app_integrity` / `create_tauri_app_darwin_arm64_integrity`. A mismatch exits 1 naming the file, both hashes and "delete it to refetch"; nothing from an unverified tarball is extracted or run. No `npx`, so nothing is fetched or executed on registry metadata alone.
- `init.sh preflight` — reports every gap, then exits 1 if any: `uname -s` Darwin and `uname -m` arm64 (the verified binary package is arm64 only); `node` on `PATH` reporting `v24.`; `npm` on `PATH`; the generator fetch and verification (this is also the network check). Writes nothing in cwd.
- `init.sh scaffold` (about 1 s once the tarballs are cached) — needs `node` and `npm` (else exit 1 naming them and `--doctor`); runs the generator fetch; extracts the two verified tarballs into `<fresh mktemp -d>/gen/node_modules/<name>/` (`tar -xzf … --strip-components 1`); in a second fresh `mktemp -d`, `node <gen>/node_modules/create-tauri-app/create-tauri-app.js <pkg> --template vanilla-ts --manager npm --identifier com.example.<pkg with _ as -> --tauri-version 2 --yes` (the tool runs no `git init`; `.app` is avoided as the identifier's last segment); copies `overlay/` over the generated tree (overwrite allowed there), substituting `__PKG__`/`__NAME__` only in the overlay files (generated files, including `src-tauri/icons/*.png|icns|ico`, are copied byte for byte); after Task 4, re-sorts the `[[package]]` blocks of `src-tauri/Cargo.lock` by (name, numeric version) so the substituted root sits where cargo would write it (python3 stdlib); lists every destination in cwd first, skipping the generated root `README.md` and `.gitignore`, and exits 1 naming the first clash with nothing written; then copies; then appends the `# >>> specflow tauri pack` … `# <<< specflow tauri pack` block to `./.gitignore` only when the start marker is absent (`node_modules/`, `coverage/`; `src-tauri/.gitignore` from the generator already covers `target/` and `gen/schemas`). No `npm install`, no cargo, no network beyond the generator fetch.
- Overlay — `package.json`: the generator's, with `devDependencies` `@tauri-apps/cli` = `tauri_cli_version`, `vitest` = `vitest_version`, `@vitest/coverage-v8` = `vitest_coverage_version` (exact, no range) and `"test": "vitest run"`; `vitest.config.ts`: `vitest/config`, tests `src/**/*.test.ts`, v8 coverage over `src/**/*.ts` excluding `src/main.ts` and the tests (no threshold: P3); `rust-toolchain.toml`: `channel = "<rust_version>"`, profile minimal, at the instance root (rustup finds it from `src-tauri/`); `src/lib/greet.ts`: `greeting(name: string): string` → `Hello, <trimmed name>!`, or `Hello, friend!` when blank; `src-tauri/src/commands.rs`: the `greet` Tauri command moved out of the generated `lib.rs`, plus its test module; `src-tauri/src/lib.rs`: the generated builder with `mod commands;`, `commands::greet` in `invoke_handler`, and a `setup` hook that exits the process with status 0 when `SPECFLOW_SMOKE` is `1` (REQ-390); `src-tauri/audit.toml` (cargo-audit schema: `[advisories]`, `ignore = []`) and `osv-scanner.toml`, each with a header comment only until Task 4 enumerates them.
- `gates.sh` (cwd = instance root) — `npm ci`; `npx --no tsc` (type check; vitest strips types without checking them); `npx --no vitest run`; `cargo test --locked` in `src-tauri`; `PASS`/`FAIL` per step as python's `gates.sh`; exit 1 on any failure.
- `security.sh` — python's P4 stub verbatim (`security floor lands in P4`).
- `release.sh` (cwd = instance root; the `release-stack.sh.template` contract) — needs `VERSION`, `DIST_DIR`; refuses (exit 1, before building) unless `VERSION` equals `src-tauri/tauri.conf.json` `version`; refuses when `node_modules/` is absent ("run npm ci — scripts/quality-gates-tauri.sh does"); the bundle directory is `${CARGO_TARGET_DIR:-src-tauri/target}/release/bundle/dmg` (Task 8's CI sets `CARGO_TARGET_DIR`); clears it; runs `CI=true npm run tauri -- build --bundles dmg -- --frozen` through `npm` on `PATH` — `CI=true` makes tauri's `bundle_dmg.sh` skip the Finder/AppleScript layout step, which otherwise needs a macOS Automation grant for the terminal and can block on a dialog, so local and CI runs behave the same; `--frozen` (locked and offline) keeps the release hook off the network, the gates having fetched every crate (`cargo test --locked`); requires exactly one `*.dmg` in that directory (exit 1 listing them otherwise); copies it into `DIST_DIR`; writes `manifest.json` `{version, artifacts: [{filename, sha256, size}]}` listing only that file.
- `action.yml` — composite: `actions/setup-python@v5` 3.12 and `pip install -r scripts/requirements.txt` (core gates); `actions/setup-node@v4` with input `node_version` defaulting to `node_version`; `rustup toolchain install <rust_version input, default rust_version> --profile minimal`; `Swatinem/rust-cache@v2` whose `workspaces` comes from the input `cargo_workspaces` (default `src-tauri -> target`), only `if: inputs.rust_cache == 'true'` (input, default `'true'`; `app-stacks.yml` turns it off and caches its own target directory, Task 8). Floor tools: P4.
- `store-checklist.md` — the macOS distribution checklist P6 appends to release notes (REQ-352): (1) Apple Developer Program, US$99 a year, enrollment from a day to a few weeks for organizations (D-U-N-S); (2) replace `com.example.<pkg>` in `src-tauri/tauri.conf.json` `identifier`; (3) signing secrets with the fixed names `APPLE_CERTIFICATE_P12` (base64 `.p12` of a Developer ID Application certificate), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (read by the release workflow from P6, REQ-386); (4) notarization (`xcrun notarytool submit --wait`, `xcrun stapler staple`); (5) Gatekeeper (`spctl --assess --type execute -vv`; opening an unsigned app via System Settings → Privacy & Security → Open Anyway); (6) packaging: the `.dmg` from `release-tauri.sh`; (7) Mac App Store versus direct Developer ID distribution (App Store needs sandbox entitlements, an App Store Connect record, an Apple Distribution certificate; not automated in v3.2); (8) arm64 only: Intel Macs need `--target universal-apple-darwin`. It does not yet say "re-run the tag and observe `signed: true`" — P6 adds that line when it becomes true.

Skeleton tests (given in full):

```ts
// stacks/tauri/overlay/src/lib/greet.test.ts
import { describe, expect, it } from "vitest";
import { greeting } from "./greet";

describe("greeting", () => {
  it("greets by name", () => {
    expect(greeting("Ada")).toBe("Hello, Ada!");
  });
  it("falls back when the name is blank", () => {
    expect(greeting("   ")).toBe("Hello, friend!");
  });
});
```

```rust
// stacks/tauri/overlay/src-tauri/src/commands.rs — test module (the command above it is intent)
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greet_names_the_caller() {
        assert_eq!(greet("Ada"), "Hello, Ada! You've been greeted from Rust!");
    }
}
```

- [ ] **Step 1: Write the failing tests** — append to `tests/governance/test_stack_packs.sh` before `finish` (after Task 1's block, whose `rc_of` and `pkg` it reuses):

```bash
# --- tauri pack (REQ-303/304/305): static contract; no toolchain, no network ---
T="$ROOT/stacks/tauri"; TO="$T/overlay"; tv() { val "$T/pack.yml" get "$1"; }
ck "stacks/tauri present" test -d "$T"
for k in create_tauri_app_version tauri_cli_version rust_version node_version vitest_version vitest_coverage_version macos_host macos_min macos_archs lockfile; do
  ck "tauri: pack.yml pins $k" [ -n "$(tv $k)" ]
done
for k in create_tauri_app_integrity create_tauri_app_darwin_arm64_integrity; do
  ck "tauri: pack.yml pins $k by sha512 (dfe-4)" grep -qE '^sha512-[A-Za-z0-9+/]{86}==$' <<<"$(tv $k)"
done
ck "tauri: guided choice 1, a Mac desktop app" [ "$(tv guided_choice):$(tv guided_label)" = "1:a Mac desktop app" ]
ck "tauri: CI runner is macos-15" [ "$(tv ci_runs_on)" = macos-15 ]
ck "tauri: coverage_exclude per REQ-325" [ "$(val "$T/pack.yml" getlist coverage_exclude | tr '\n' ' ')" = "src-tauri/src/main.rs src-tauri/src/lib.rs src/main.ts " ]
ck "tauri: rust-toolchain.toml pins rust_version" grep -qE "^channel *= *\"$(tv rust_version)\"" "$TO/rust-toolchain.toml"
ck "tauri: package.json pins the CLI, vitest and coverage exactly" python3 - "$TO/package.json" "$(tv tauri_cli_version)" "$(tv vitest_version)" "$(tv vitest_coverage_version)" <<'PY'
import json, sys
dev = json.load(open(sys.argv[1]))["devDependencies"]
want = {"@tauri-apps/cli": sys.argv[2], "vitest": sys.argv[3], "@vitest/coverage-v8": sys.argv[4]}
assert all(dev.get(k) == v for k, v in want.items()), (dev, want)
PY
for f in vitest.config.ts src/lib/greet.ts src/lib/greet.test.ts src-tauri/src/commands.rs src-tauri/src/lib.rs src-tauri/audit.toml osv-scanner.toml; do
  ck "tauri overlay has $f" test -f "$TO/$f"
done
ck "tauri: commands.rs carries a #[cfg(test)] test" grep -q '#\[cfg(test)\]' "$TO/src-tauri/src/commands.rs"
ck "tauri: lib.rs wires commands and honours SPECFLOW_SMOKE" bash -c "grep -q 'mod commands' '$TO/src-tauri/src/lib.rs' && grep -q SPECFLOW_SMOKE '$TO/src-tauri/src/lib.rs'"
ck "tauri: vitest coverage excludes src/main.ts" grep -q 'src/main.ts' "$TO/vitest.config.ts"
ck "tauri: init.sh reads the generator pins from pack.yml and never runs npx" bash -c "grep -q create_tauri_app_version '$T/init.sh' && grep -q create_tauri_app_integrity '$T/init.sh' && grep -q -- '--template vanilla-ts' '$T/init.sh' && ! grep -qE 'create-tauri-app@[0-9]' '$T/init.sh' && ! grep -q npx '$T/init.sh'"
for w in 'npm ci' 'vitest run' 'cargo test --locked' src-tauri; do ck "tauri: gates.sh runs $w" grep -qF -- "$w" "$T/gates.sh"; done
for w in --frozen CI=true CARGO_TARGET_DIR; do ck "tauri: release.sh uses $w" grep -qF -- "$w" "$T/release.sh"; done
ck "tauri: release.sh never uses --locked alone (cargo could fetch)" no grep -qE -- '--locked' "$T/release.sh"
ck "tauri: action's rust-cache is switchable with configurable workspaces" bash -c "grep -q 'rust_cache' '$T/action.yml' && grep -q 'cargo_workspaces' '$T/action.yml'"
ck "tauri: action installs the pinned node and rust" bash -c "grep -q actions/setup-node '$T/action.yml' && grep -qF '$(tv node_version)' '$T/action.yml' && grep -q 'rustup toolchain install' '$T/action.yml' && grep -qF '$(tv rust_version)' '$T/action.yml'"
for w in 'Apple Developer Program' APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD notarytool stapler Gatekeeper 'App Store' 'Developer ID' .dmg; do
  ck "tauri: store-checklist names $w" grep -qF -- "$w" "$T/store-checklist.md"
done
for k in $(val "$T/pack.yml" getlist prereqs); do ck "tauri: install_linux_$k is honest (macOS only)" grep -qi macos <<<"$(tv "install_linux_$k")"; done
ck "tauri: Calendar is a valid package" [ "$(pkg "$T" Calendar calendar)" = calendar ]
for n in match tauri std serde_json; do ck "tauri: package '$n' refused (exit 2)" [ "$(rc_of pkg "$T" X "$n")" = 2 ]; done
# release.sh contract without a toolchain: a fake npm stands in for `npm run tauri -- build`.
R="$W/rel-tauri"; mkdir -p "$R/bin" "$R/app/node_modules" "$R/app/src-tauri/target/release/bundle/dmg"
printf '{"version": "0.1.0"}\n' > "$R/app/src-tauri/tauri.conf.json"
echo stale > "$R/app/src-tauri/target/release/bundle/dmg/old_0.0.9_aarch64.dmg"
cat > "$R/bin/npm" <<'FAKE'
#!/usr/bin/env bash
touch "$FAKE_MARK"; printf '%s\n' "$@" > "$FAKE_ARGV"; echo "${CI:-unset}" > "$FAKE_CI"
d="${CARGO_TARGET_DIR:-src-tauri/target}/release/bundle/dmg"; mkdir -p "$d"
for n in $FAKE_DMGS; do head -c 2048 /dev/urandom > "$d/$n"; done
FAKE
chmod +x "$R/bin/npm"
trel() { (cd "$R/app" && env -u CI -u CARGO_TARGET_DIR PATH="$R/bin:$PATH" FAKE_MARK="$R/mark" FAKE_ARGV="$R/argv" FAKE_CI="$R/ci" "$@" bash "$T/release.sh"); }
ck "tauri release: a VERSION unlike tauri.conf.json is refused" [ "$(rc_of trel VERSION=9.9.9 DIST_DIR="$R/d0" FAKE_DMGS=x.dmg)" != 0 ]
ck "tauri release: the refusal comes before building" no test -e "$R/mark"
ck "tauri release: one dmg built" trel VERSION=0.1.0 DIST_DIR="$R/d1" FAKE_DMGS=fix_0.1.0_aarch64.dmg
ck "tauri release: manifest lists exactly the new dmg, verified" python3 - "$R/d1" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
assert m["version"] == "0.1.0" and [e["filename"] for e in m["artifacts"]] == ["fix_0.1.0_aarch64.dmg"], m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
ck "tauri release: a stale dmg is cleared before building" no test -e "$R/app/src-tauri/target/release/bundle/dmg/old_0.0.9_aarch64.dmg"
ck "tauri release: the build runs with CI=true (no Finder layout step, no Automation prompt)" [ "$(cat "$R/ci" 2>/dev/null)" = true ]
ck "tauri release: cargo runs --frozen (no network in a release hook)" grep -qx -- --frozen "$R/argv"
ck "tauri release: dmg bundles only" grep -qx dmg "$R/argv"
ck "tauri release: two dmgs are refused" [ "$(rc_of trel VERSION=0.1.0 DIST_DIR="$R/d2" FAKE_DMGS='a.dmg b.dmg')" != 0 ]
ck "tauri release: honours CARGO_TARGET_DIR" trel VERSION=0.1.0 DIST_DIR="$R/d4" CARGO_TARGET_DIR="$R/tgt" FAKE_DMGS=ct_0.1.0_aarch64.dmg
ck "tauri release: the CARGO_TARGET_DIR dmg is the one shipped" test -f "$R/d4/ct_0.1.0_aarch64.dmg"
rm -rf "$R/app/node_modules"
ck "tauri release: missing node_modules is refused" [ "$(rc_of trel VERSION=0.1.0 DIST_DIR="$R/d3" FAKE_DMGS=fix.dmg)" != 0 ]
# init.sh preflight/scaffold without a toolchain: fake npm and node stand in for the registry and the generator.
# (Guarded: under set -e the harness setup would abort the whole test before the pack exists.)
if [[ ! -f "$T/init.sh" ]]; then fail "tauri: init.sh missing — scaffold harness not run"; else
S="$W/scaf-tauri"; mkdir -p "$S/bin" "$S/tgz" "$S/root/scripts/lib/specflow" "$S/root/stacks"
cp "$ROOT/scripts/lib/specflow/config.py" "$S/root/scripts/lib/specflow/"; cp -R "$T" "$S/root/stacks/tauri"; ST="$S/root/stacks/tauri"
CV=$(tv create_tauri_app_version)
for n in create-tauri-app create-tauri-app-darwin-arm64; do
  mkdir -p "$S/src/$n/package"; printf '{"name": "%s", "version": "%s"}\n' "$n" "$CV" > "$S/src/$n/package/package.json"
  tar -czf "$S/tgz/$n-$CV.tgz" -C "$S/src/$n" package
done
sri() { python3 -c 'import base64, hashlib, sys; print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1], "rb").read()).digest()).decode())' "$1"; }
setpin() { python3 - "$ST/pack.yml" "$1" "$2" <<'PY'
import re, sys
p, k, v = sys.argv[1:4]; t = open(p).read()
t, n = re.subn(rf"(?m)^{k}:.*$", f"{k}: {v}", t); assert n == 1, k
open(p, "w").write(t)
PY
}
cat > "$S/bin/npm" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == pack ]] || exit 0
dest=""; while [[ $# -gt 0 ]]; do [[ "$1" == --pack-destination ]] && dest="$2"; shift; done
cp "$FAKE_TGZ"/*.tgz "$dest/"
FAKE
cat > "$S/bin/node" <<'FAKE'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && { echo v24.8.0; exit 0; }
shift; printf '%s\n' "$@" > "$FAKE_ARGS"; p="$1"
mkdir -p "$p/src" "$p/src-tauri/src" "$p/src-tauri/icons"
printf '{"name": "%s", "version": "0.1.0"}\n' "$p" > "$p/package.json"
echo 'generated main' > "$p/src/main.ts"; echo 'generated lib' > "$p/src-tauri/src/lib.rs"
printf '{"version": "0.1.0", "identifier": "com.example.%s"}\n' "$p" > "$p/src-tauri/tauri.conf.json"
printf '\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80' > "$p/src-tauri/icons/icon.png"
echo 'generator readme' > "$p/README.md"; echo 'node_modules' > "$p/.gitignore"
FAKE
chmod +x "$S/bin/npm" "$S/bin/node"
tscaf() { (cd "$1" && env PATH="$S/bin:$PATH" XDG_CACHE_HOME="$S/cache" FAKE_TGZ="$S/tgz" FAKE_ARGS="$S/args" SPECFLOW_NAME='Habit Tracker' SPECFLOW_PKG=habit_tracker bash "$ST/init.sh" "$2"); }
setpin create_tauri_app_integrity "sha512-$(printf 'A%.0s' $(seq 1 86))=="
setpin create_tauri_app_darwin_arm64_integrity "$(sri "$S/tgz/create-tauri-app-darwin-arm64-$CV.tgz")"
mkdir -p "$S/bad"; echo keep > "$S/bad/README.md"
ck "tauri scaffold: a tarball unlike its pinned sha512 is refused (exit 1)" [ "$(rc_of tscaf "$S/bad" scaffold)" = 1 ]
ck "tauri scaffold: the generator never ran from an unverified tarball" no test -e "$S/args"
ck "tauri scaffold: that refusal wrote nothing" [ "$(ls -A "$S/bad")" = README.md ]
ck "tauri preflight: a tarball unlike its pin fails the preflight (exit 1)" bash -c "out=\$( (cd '$S/bad' && env PATH='$S/bin:$PATH' XDG_CACHE_HOME='$S/cache' FAKE_TGZ='$S/tgz' SPECFLOW_NAME=X SPECFLOW_PKG=x bash '$ST/init.sh' preflight) 2>&1); [ \$? = 1 ] && grep -q '^preflight: .*integrity' <<<\"\$out\""
setpin create_tauri_app_integrity "$(sri "$S/tgz/create-tauri-app-$CV.tgz")"
A="$S/app"; mkdir -p "$A"; echo 'my readme' > "$A/README.md"; printf 'mine/\n' > "$A/.gitignore"
ck "tauri scaffold: verified tarballs scaffold (exit 0)" tscaf "$A" scaffold
ck "tauri scaffold: the generator got the pinned template and identifier" bash -c "grep -qx vanilla-ts '$S/args' && grep -qx com.example.habit-tracker '$S/args'"
ck "tauri scaffold: an existing README.md is kept" [ "$(cat "$A/README.md")" = 'my readme' ]
ck "tauri scaffold: .gitignore keeps its lines, skips the generator's, gains the block once" bash -c "grep -qx 'mine/' '$A/.gitignore' && ! grep -qx node_modules '$A/.gitignore' && [ \$(grep -c '^# >>> specflow tauri pack' '$A/.gitignore') = 1 ]"
ck "tauri scaffold: the overlay wins and its tokens are substituted" python3 - "$A" <<'PY'
import json, pathlib, sys
a = pathlib.Path(sys.argv[1])
assert json.load(open(a / "package.json"))["name"] == "habit_tracker"
assert "mod commands" in (a / "src-tauri/src/lib.rs").read_text()
for p in a.rglob("*"):
    if p.is_file() and p.suffix != ".png":
        assert b"__PKG__" not in p.read_bytes() and b"__NAME__" not in p.read_bytes(), p
PY
ck "tauri scaffold: generated binaries are copied byte for byte" python3 -c 'import sys; sys.exit(open(sys.argv[1], "rb").read() != b"\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80")' "$A/src-tauri/icons/icon.png"
ck "tauri scaffold: generated files the overlay does not replace are kept" test -f "$A/src/main.ts"
cp "$A/.gitignore" "$S/gi.before"
rc=0; out=$(tscaf "$A" scaffold 2>&1) || rc=$?
ck "tauri scaffold: a second run refuses (exit 1)" [ "$rc" = 1 ]
ck "tauri scaffold: the refusal names the clashing file" grep -qE 'package\.json|src/|src-tauri/' <<<"$out"
ck "tauri scaffold: the refused run changed nothing" cmp -s "$A/.gitignore" "$S/gi.before"
B="$S/again"; mkdir -p "$B"; printf '# >>> specflow tauri pack\nnode_modules/\ncoverage/\n# <<< specflow tauri pack\n' > "$B/.gitignore"
tscaf "$B" scaffold >/dev/null 2>&1 || true
ck "tauri scaffold: an existing block is not appended again" [ "$(grep -c '^# >>> specflow tauri pack' "$B/.gitignore")" = 1 ]
ck "tauri init.sh: an unknown subcommand exits 2" [ "$(rc_of tscaf "$A" frobnicate)" = 2 ]
if [ -x /usr/bin/node ] || [ -x /bin/node ]; then echo "SKIP: node in /usr/bin or /bin — missing-node preflight case not run"; else
  mkdir -p "$S/nonode"; ln -s "$(command -v python3)" "$S/nonode/python3"; cp "$S/bin/npm" "$S/nonode/npm"
  rc=0; out=$(cd "$A" && env PATH="$S/nonode:/usr/bin:/bin" XDG_CACHE_HOME="$S/cache" FAKE_TGZ="$S/tgz" SPECFLOW_NAME=X SPECFLOW_PKG=x bash "$ST/init.sh" preflight 2>&1) || rc=$?
  ck "tauri preflight: missing node exits 1" [ "$rc" = 1 ]
  ck "tauri preflight: names node and the doctor" bash -c "grep -q '^preflight: missing node' <<<\"\$1\" && grep -qF -- '--doctor --stack tauri' <<<\"\$1\"" _ "$out"
fi
fi   # scaffold harness
```

In `tests/governance/test_examples.sh`, replace case 4 (the `stub_pack` line Task 1 wrote and the three checks after it) with the real pack (the python checks after it stay):

```bash
# 4. Other stacks' examples are dropped — real packs, scaffold skipped (no toolchain in the default gates).
for s in tauri; do
  [[ -d "$ROOT/stacks/$s" ]] || { fail "stacks/$s missing"; continue; }
  D="$WORK/other-$s"; copy_template "$D"
  ck "init --stack $s (SPECFLOW_NO_SCAFFOLD=1) exits 0" bash -c "cd '$D' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Habit --stack $s </dev/null"
  while IFS= read -r p; do ck "$s instance drops $p" no test -e "$D/$p"; done < <(python3 "$EXPY" --root "$ROOT" list demo_greeting)
  ck "$s CLAUDE.md drops demo_greeting" no grep -q '^### demo_greeting' "$D/CLAUDE.md"
  ck "$s instance has the store checklist" test -f "$D/docs/releases/store-checklist.md"
done
```

- [ ] **Step 2: Run them — expect** `FAIL: stacks/tauri present` and every tauri check FAIL (no files), including `FAIL: tauri: init.sh missing — scaffold harness not run`, except the four release refusals (VERSION, before building, two dmgs, missing `node_modules/`), which pass vacuously because a missing `release.sh` exits non-zero without running `npm`; the per-pack loop has no tauri entry yet; `test_examples.sh` prints `FAIL: stacks/tauri missing`. Exit 1. Implement `init.sh package` first (against the package checks); with `preflight` and `scaffold` still unknown subcommands (exit 2), re-run: the harness now runs and every scaffold and preflight check in it FAILs except the unknown-subcommand one — the failing behavioural test the `preflight` and `scaffold` bodies are written against (`art-test-first`).

- [ ] **Step 3: Implement (intent)** — the pack per Interfaces. Resolve `vitest_version`/`vitest_coverage_version` with `npm view vitest version` and `npm view @vitest/coverage-v8 version` (network, no compile) and record them in `pack.yml` and `overlay/package.json`; record both `dist.integrity` values from `npm view`. Start `overlay/package.json` and `overlay/src-tauri/src/lib.rs` from the generator's output — run the pack's own verified fetch in a scratch directory (`SPECFLOW_NAME=Pin SPECFLOW_PKG=pin_app bash stacks/tauri/init.sh scaffold` once `scaffold` exists; before that, the manual `npm pack` + sha512 comparison + `node …/create-tauri-app.js pin_app --template vanilla-ts --manager npm --identifier com.example.pin-app --tauri-version 2 --yes` from **Verified against**, under 1 s) — replacing `pin_app` with `__PKG__`. Lockfiles and advisory entries come in Task 4.

- [ ] **Step 4: Run** `for t in stack_packs examples init init_doctor; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green on this Mac and with `PATH` reduced as in Task 10 Step 1 (no node, cargo or flutter; the harness uses only its fakes); the default gates grow by about 3 s.

- [ ] **Step 5: Commit** — "feat(stacks): tauri pack — pins with sha512-verified generator, preflight, pack-owned package rule, overlay, gates and offline release contract, store checklist (REQ-303, REQ-304, REQ-305, REQ-306)"

---

### Task 4: The tauri skeleton on this Mac — lockfiles, advisories, `.gitignore` (H1), first run

**Opt-in; expected wall-clock on this Mac:** the tauri first-run case about 3 minutes (init with a cached `npx` under 5 s, core gates about 5 s, `npm ci` 4 s, `tsc` + vitest about 3 s, `cargo test --locked` 20 s cold, `tauri build --bundles dmg` 102 s cold, smoke under 5 s); add 1–2 minutes when `~/.cargo/registry` is cold, and once per machine the `rustup toolchain install 1.93.1 --profile minimal` that the overlay's `rust-toolchain.toml` requires (tens of seconds, about 200 MB in `~/.rustup`; Step 3 does it explicitly). The static checks run in the default gates (under 1 s).

**Files:** modify `.gitignore:30` (remove `*.lock`); create `stacks/tauri/overlay/package-lock.json`, `stacks/tauri/overlay/src-tauri/Cargo.lock`; fill `stacks/tauri/overlay/src-tauri/audit.toml` and `stacks/tauri/overlay/osv-scanner.toml`; modify `stacks/tauri/init.sh` (the `Cargo.lock` re-sort), `tests/governance/lib/check.sh` (`run_within`), `tests/governance/test_stack_packs.sh` (append), `tests/governance/test_first_run.sh` (`:21`, helpers after `:20`, tauri case before `:44`).

**Interfaces:**
- `run_within SECS CMD…` (check.sh) — CMD's exit status, or 124 after killing it when it outlives SECS (macOS has no `timeout`).
- Overlay lockfiles carry `__PKG__` for the root package (`package-lock.json` top-level `name` and `packages[""].name`; `Cargo.lock` `name = "__PKG__"`); `init.sh scaffold` substitutes it like any overlay file, then re-sorts `Cargo.lock`'s `[[package]]` blocks by (name, numeric version) — cargo serialises them in that order, and a root left where `pin_app` sorted would make any lock-writing cargo run (`npm run tauri dev`, plain `cargo build`, rust-analyzer) rewrite the file in a fresh instance. `--locked`/`--frozen` compare the resolve, not the text, so the gates pass either way.
- `src-tauri/audit.toml` — `[advisories]` `ignore = [ "RUSTSEC-…",  # reason: <why>; ignoreUntil: YYYY-MM-DD ]`, one line per advisory (cargo-audit has no expiry field, so reason and expiry live in the trailing comment); header `# Enumerated with cargo-audit X.Y.Z on YYYY-MM-DD against src-tauri/Cargo.lock sha256 <hex of the overlay file>`. `osv-scanner.toml` — `[[IgnoredVulns]]` `id`, `ignoreUntil` (TOML date), `reason`; header naming `osv-scanner X.Y.Z on YYYY-MM-DD`, `package-lock.json sha256 <hex>` and `src-tauri/Cargo.lock sha256 <hex>`. `ignoreUntil` = pin date + 90 days. Empty lists are acceptable only when the tools ran and found nothing, which the header then records.
- `test_first_run.sh` — default cases `guided engineer`; on Darwin, `tauri` and `flutter` join only when `bash scripts/init-project.sh --doctor --stack <s>` (run in the template) reports none of that pack's `prereqs:` as `MISSING` and the pack exists (core tools such as `gh`, `claude` or `dafny` do not gate it); otherwise it prints `SKIP: <s> — missing <prereqs> (…--doctor --stack <s>; name it in FIRST_RUN_CASES to run it anyway)`. Explicit `FIRST_RUN_CASES` runs what it names on any OS and fails loudly when a toolchain is missing. The tauri smoke binary is `${CARGO_TARGET_DIR:-<instance>/src-tauri/target}/release/<pkg>`. `floor LABEL CMD…` reports a floor tool's findings under `floor failures:` with a `FAIL: <label>: floor (new advisories, not a gate failure)` line, apart from `gates()`'s gate failures (REQ-360). `manifest DIST VERSION SUFFIX` asserts exactly one artifact with SUFFIX whose sha256 and size verify.

- [ ] **Step 1: Write the failing tests**

Append to `tests/governance/lib/check.sh`:

```bash
run_within() {  # run_within SECS CMD... — CMD's status, or 124 once it outlives SECS (no coreutils timeout on macOS)
  local secs="$1"; shift
  "$@" & local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ $i -ge $secs ]]; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; fi
    sleep 1; i=$((i + 1))
  done
  wait "$pid"
}
```

Append to `tests/governance/test_stack_packs.sh` before `finish`:

```bash
# --- lockfiles are committed (H1) and the advisory lists were enumerated against them (REQ-304) ---
ck ".gitignore no longer ignores *.lock (H1; REQ-334's first clause)" no grep -qxF '*.lock' "$ROOT/.gitignore"
for f in Cargo.lock src-tauri/Cargo.lock pubspec.lock uv.lock package-lock.json; do ck "git would track $f" no git -C "$ROOT" check-ignore -q --no-index "$f"; done
for f in package-lock.json src-tauri/Cargo.lock; do ck "tauri overlay ships $f with the __PKG__ token" grep -q __PKG__ "$TO/$f"; done
# The Task 3 scaffold harness ($A, package habit_tracker) now receives the overlay Cargo.lock.
ck "tauri: the instance Cargo.lock keeps cargo's (name, version) order after substitution" python3 - "${A:-/nonexistent}/src-tauri/Cargo.lock" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
assert "__PKG__" not in text and 'name = "habit_tracker"' in text
ids = [(n, [int(x) for x in re.findall(r"\d+", v)]) for n, v in re.findall(r'\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"', text)]
assert ids and ids == sorted(ids), "[[package]] blocks out of cargo's order"
PY
ck "tauri: audit.toml was enumerated against the shipped Cargo.lock" python3 - "$TO" <<'PY'
import hashlib, pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1]); text = (o / "src-tauri/audit.toml").read_text()
lock = hashlib.sha256((o / "src-tauri/Cargo.lock").read_bytes()).hexdigest()
assert re.search(r"cargo-audit \d+\.\d+\.\d+ on \d{4}-\d{2}-\d{2}", text), "header must name the cargo-audit version and date"
assert f"src-tauri/Cargo.lock sha256 {lock}" in text, f"header must record src-tauri/Cargo.lock sha256 {lock}"
for i in tomllib.loads(text)["advisories"]["ignore"]:
    line = next(l for l in text.splitlines() if f'"{i}"' in l)
    assert re.search(r"# reason: .+; ignoreUntil: \d{4}-\d{2}-\d{2}\s*$", line), line
PY
ck "tauri: osv-scanner.toml was enumerated against the shipped lockfiles" python3 - "$TO" <<'PY'
import datetime, hashlib, pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1]); text = (o / "osv-scanner.toml").read_text()
assert re.search(r"osv-scanner \d+\.\d+\.\d+ on \d{4}-\d{2}-\d{2}", text), "header must name the osv-scanner version and date"
for lock in ("package-lock.json", "src-tauri/Cargo.lock"):
    h = hashlib.sha256((o / lock).read_bytes()).hexdigest()
    assert f"{lock} sha256 {h}" in text, f"header must record {lock} sha256 {h}"
for v in tomllib.loads(text).get("IgnoredVulns", []):
    assert v.get("id") and v.get("reason") and isinstance(v.get("ignoreUntil"), datetime.date), v
PY
```

In `tests/governance/test_first_run.sh`: insert after `gates()` (`:13-20`):

```bash
floor() {  # floor LABEL CMD... — a floor tool's findings are reported apart from gate failures (REQ-360)
  local label="$1"; shift; local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then pass "$label: floor clean"; return 0; fi
  fail "$label: floor (new advisories, not a gate failure), exit $rc"
  echo "  floor failures:"; tail -30 <<<"$out" | sed 's/^/    /'
}
manifest() {  # manifest DIST VERSION SUFFIX — exactly one artifact ending in SUFFIX; sha256 and size verify
  python3 - "$@" <<'PY'
import hashlib, json, os, sys
d, version, suffix = sys.argv[1:4]
m = json.load(open(os.path.join(d, "manifest.json")))
arts = m["artifacts"]
assert m["version"] == version and len(arts) == 1 and arts[0]["filename"].endswith(suffix), m
p = os.path.join(d, arts[0]["filename"])
assert hashlib.sha256(open(p, "rb").read()).hexdigest() == arts[0]["sha256"] and os.path.getsize(p) == arts[0]["size"], arts
PY
}
app_missing() {  # app_missing STACK — the pack prerequisites --doctor reports MISSING (empty: ready)
  local s="$1" out p m=""
  [[ -f "$ROOT/stacks/$s/pack.yml" ]] || { echo "pack stacks/$s/"; return 0; }
  out=$(cd "$ROOT" && bash scripts/init-project.sh --doctor --stack "$s" </dev/null 2>&1 || true)
  for p in $(python3 "$ROOT/scripts/lib/specflow/config.py" --file "$ROOT/stacks/$s/pack.yml" getlist prereqs 2>/dev/null); do
    if grep -q "^MISSING $p:" <<<"$out"; then m="$m $p"; fi
  done
  echo "${m# }"
}
DEFAULT_CASES="guided engineer"
if [[ -z "${FIRST_RUN_CASES:-}" && "$(uname -s)" == Darwin ]]; then
  for s in tauri flutter; do
    m=$(app_missing "$s")
    if [[ -z "$m" ]]; then DEFAULT_CASES="$DEFAULT_CASES $s"
    else echo "SKIP: $s — missing $m (bash scripts/init-project.sh --doctor --stack $s; name it in FIRST_RUN_CASES to run it anyway)"; fi
  done
fi
```

Line 21 becomes `for c in ${FIRST_RUN_CASES:-$DEFAULT_CASES}; do`. Before the `*)` arm (`:44`), add (the flutter arm comes in Task 6; between Tasks 5 and 6 a Darwin default run whose doctor finds Flutter reports `unknown FIRST_RUN_CASES entry 'flutter'`, so run with `FIRST_RUN_CASES=tauri`):

```bash
    tauri)   # macOS (REQ-360): guided Enter-through with choice 1 — the Mac-desktop pack end to end
      D="$WORK/habit-tracker"; copy_template "$D"   # the default name derives the package habit_tracker
      ck "tauri: guided init, choice 1" bash -c "cd '$D' && printf '\n\n1\n\n' | bash scripts/init-project.sh"
      ck "tauri: stack recorded" [ "$(python3 "$D/scripts/lib/specflow/config.py" --root "$D" get stack 2>/dev/null)" = tauri ]
      ck "tauri: lockfiles and ignore lists committed (H1)" git -C "$D" ls-files --error-unmatch package-lock.json src-tauri/Cargo.lock rust-toolchain.toml src-tauri/audit.toml osv-scanner.toml
      ck "tauri: init left a clean tree" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ]
      gates "$D" "tauri/guided/lanes/solo"
      if command -v cargo-audit >/dev/null 2>&1; then
        ign=$(python3 -c 'import sys, tomllib; print(" ".join("--ignore " + i for i in tomllib.load(open(sys.argv[1], "rb"))["advisories"]["ignore"]))' "$D/src-tauri/audit.toml")
        floor "tauri: cargo audit" bash -c "cd '$D/src-tauri' && cargo audit --deny warnings $ign"
      else echo "SKIP: cargo-audit not installed — tauri floor not run (P4 installs it in CI)"; fi
      if command -v osv-scanner >/dev/null 2>&1; then
        floor "tauri: osv-scanner" osv-scanner scan source --config "$D/osv-scanner.toml" -L "$D/package-lock.json" -L "$D/src-tauri/Cargo.lock"
      else echo "SKIP: osv-scanner not installed — tauri floor not run (P4 installs it in CI)"; fi
      ck "tauri: release-tauri.sh builds the dmg" bash -c "cd '$D' && VERSION=0.1.0 DIST_DIR='$WORK/dist-tauri' bash scripts/release-tauri.sh"
      ck "tauri: manifest lists exactly one .dmg that verifies" manifest "$WORK/dist-tauri" 0.1.0 .dmg
      ck "tauri: SPECFLOW_SMOKE=1 start-up exits 0 within 60 s" run_within 60 env SPECFLOW_SMOKE=1 "${CARGO_TARGET_DIR:-$D/src-tauri/target}/release/habit_tracker"
      ck "tauri: gates and release leave the tree clean" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ] ;;
```

- [ ] **Step 2: Run them — expect** in `test_stack_packs.sh`: the `*.lock` check and `git would track` for `Cargo.lock`, `src-tauri/Cargo.lock`, `pubspec.lock`, `uv.lock` FAIL (`package-lock.json` passes — `*.lock` never matched it), both lockfile-token checks, both enumeration checks and the Cargo.lock order check (no lock in the harness instance) FAIL. `SPECFLOW_FIRST_RUN=1 bash tests/governance/test_first_run.sh` with no case list on this Mac prints `SKIP: flutter — missing pack stacks/flutter/` (and `SKIP: tauri — missing rust_toolchain` until Step 3's install). `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=tauri bash tests/governance/test_first_run.sh` on this Mac: init and stack pass; `lockfiles … committed` FAILs; the gates FAIL at `npm ci` (no `package-lock.json`) and `cargo test --locked` (no `Cargo.lock`); the release FAILs (`node_modules/` absent); smoke FAILs (no binary). Exit 1.

- [ ] **Step 3: Implement (intent)**
  - `.gitignore`: drop `*.lock` (a comment says lockfiles are committed, `art-repository-singleton`).
  - Rust toolchain: `rustup toolchain install 1.93.1 --profile minimal` (the overlay's `rust-toolchain.toml` needs it; about 200 MB in `~/.rustup`, reversible with `rustup toolchain uninstall 1.93.1`). This install is outside the brew allowance for this execution, so surface it to the user before running it, and record it in the PR body; `--doctor --stack tauri` reports it as `rust_toolchain`.
  - Pin-time lockfiles, in an empty scratch directory: `SPECFLOW_NAME=Pin SPECFLOW_PKG=pin_app bash <template>/stacks/tauri/init.sh scaffold`; `npm install`; `(cd src-tauri && cargo generate-lockfile)`; `bash <template>/stacks/tauri/gates.sh` passes there; copy both lockfiles into the overlay with `pin_app` → `__PKG__` in exactly the root-package fields (`grep -c pin_app` on the copies is 0 afterwards).
  - Scaffold: after substitution, re-sort `src-tauri/Cargo.lock`'s `[[package]]` blocks (python3 stdlib: split on the `[[package]]` header, sort by name then the numeric parts of the version, rejoin after the file's preamble of comments and `version = …`).
  - Advisories: `brew install cargo-audit osv-scanner` (user-level, reversible with `brew uninstall`; record the install and versions in the PR body). In the scratch instance run `(cd src-tauri && cargo audit --json)` and `osv-scanner scan source -L package-lock.json -L src-tauri/Cargo.lock --format json`; list **every** reported id — vulnerabilities and cargo-audit warnings (unmaintained, unsound, yanked), since P4 runs `--deny warnings` — with a one-line reason (e.g. "gtk-rs GTK3 bindings unmaintained; Linux-only dependency of tauri, not compiled for macOS") and `ignoreUntil`; write the headers with tool versions, date and the overlay lockfiles' sha256. Re-run both tools against the scratch instance with the lists applied: clean.

- [ ] **Step 4: Run** `bash tests/governance/test_stack_packs.sh && bash scripts/run-quality-gates.sh && time SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=tauri bash tests/governance/test_first_run.sh` — expect green, including `floor clean` twice; record the wall-clock (target about 3 minutes).

- [ ] **Step 5: Commit** — "feat(stacks): tauri skeleton ships pinned, cargo-ordered lockfiles and enumerated advisory lists; *.lock no longer ignored; doctor-gated macOS first run (REQ-304, REQ-305, REQ-360)"

---

### Task 5: The flutter pack — files, pins, package rule, overlay, static contract

**Files:** create `stacks/flutter/` — `init.sh`, `gates.sh`, `security.sh`, `release.sh` (executable), `action.yml`, `pack.yml`, `store-checklist.md`, and `overlay/` with `lib/main.dart`, `lib/app.dart`, `test/widget_test.dart`, `osv-scanner.toml` (header only until Task 6). Modify `tests/governance/test_stack_packs.sh` (append), `tests/governance/test_examples.sh` (case 4's loop becomes `for s in tauri flutter; do`).

**Interfaces:**
- `pack.yml` — `stack: flutter`, `guided_choice: 3`, `guided_label: a multi-platform app`, `guided_rationale: Flutter keeps one Dart codebase that can later target iOS, Android, Windows and Linux; v3.2 builds, tests and ships the macOS app only.`, `testing: flutter test (test/), dart analyze --fatal-infos, governance tests (tests/governance/)`, `ci_runs_on: macos-15`, `source_roots: [lib]`, `test_globs: [test/**/*_test.dart]`, `coverage_exclude: [lib/main.dart]` (the entry point with the smoke hook; the app lives in `lib/app.dart`), `lockfile: pubspec.lock`, `lockfiles: [pubspec.lock]`, `flutter_version: 3.35.5`, `flutter_revision: ac4e799d237041cf905519190471f657b657155a` (the SDK is pinned by this commit id, not by the movable tag), `macos_min: "12.0"`, `macos_archs: arm64`, `macos_host: "27.0 (Xcode 27, CocoaPods installed, Flutter darwin engine artifacts cached)"`, `prereqs: [xcode, cocoapods, flutter, flutter_macos]` with `check_xcode: xcodebuild -version` / `install_macos_xcode: install Xcode from the App Store (open 'macappstore://apps.apple.com/app/id497799835'), then: xcode-select --install; sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch`; `check_cocoapods: pod --version` / `install_macos_cocoapods: brew install cocoapods`; `check_flutter: flutter --version --machine | grep -q '"frameworkRevision": "ac4e799d237041cf905519190471f657b657155a"'` / `install_macos_flutter: git clone --depth 1 --branch 3.35.5 https://github.com/flutter/flutter.git "$HOME/development/flutter" && test "$(git -C "$HOME/development/flutter" rev-parse HEAD)" = ac4e799d237041cf905519190471f657b657155a && echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zprofile` (`PATH` is extended only when the tag resolves to the pinned revision); `check_flutter_macos` true when `<flutterRoot>/bin/cache/artifacts/engine/darwin-x64` exists (flutterRoot from `flutter --version --machine`; the check never downloads) / `install_macos_flutter_macos: flutter precache --macos`; every `install_linux_*` as in Task 3.
- `init.sh package` — the candidate is refused (exit 2, naming which set) when it is in any of: (a) the full `_keywords` set of the pinned SDK's `packages/flutter_tools/lib/src/commands/create_base.dart` (69 names, copied into `init.sh` at pin time with a comment naming the file and `flutter_revision`; besides the reserved words it includes `abstract as async await covariant deferred dynamic export extension external factory function get hide implements import inout interface late library mixin native of on operator out part patch required set show source static sync typedef yield`); (b) that file's `_packageDependencies` (`collection`, `flutter`, `flutter_test`, `meta`); (c) the generated app's other direct dependencies (`cupertino_icons`, `flutter_lints`) and `test`; (d) every package key under `packages:` in `overlay/pubspec.lock`, read at run time so it follows the pin (`clock`, `fake_async`, `boolean_selector`, `stack_trace`, `leak_tracker…`; empty until Task 6 ships the lock) — a root package named like a locked dependency fails at `pub get`. Checked before any write, so `--name Library` or a guided run in a folder named `library` is refused by init instead of by `flutter create` after init has written files.
- `init.sh preflight` — reports every gap, then exits 1 if any: Darwin; `flutter` on `PATH`; `flutter --version --machine` `frameworkRevision` equal to `flutter_revision` (a mismatch names both revisions and both versions); the SDK's `packages/flutter_tools/templates/cocoapods/Podfile-macos` present under its `flutterRoot`. No network, writes nothing.
- `init.sh scaffold` (runs `flutter`; about 1 s) — needs `flutter` at `flutter_revision` (else exit 1 naming both revisions and `--doctor`); in a fresh `mktemp -d`, `flutter create --platforms=macos --org com.example --project-name <pkg> --no-pub <tmp>/<pkg>`; overlay copied over, with `__PKG__`/`__NAME__` substituted only in the overlay files (generated files, including `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`, are copied byte for byte); every `MACOSX_DEPLOYMENT_TARGET = …;` in `macos/Runner.xcodeproj/project.pbxproj` set to `macos_min`; `macos/Podfile` written from the SDK's `packages/flutter_tools/templates/cocoapods/Podfile-macos` with `platform :osx, '<macos_min>'` (the generator writes none for a plugin-free app; shipping it keeps the minimum once plugins arrive); `ARCHS = arm64` appended, with a one-line comment naming Xcode 27's `lipo`, to `macos/Runner/Configs/Release.xcconfig`; `pubspec.yaml` `version:` set to `0.1.0+1`; every destination in cwd listed first (skipping the generated `README.md` and root `.gitignore`), exit 1 naming the first clash with nothing written; then copied; the `# >>> specflow flutter pack` block appended to `./.gitignore` only when absent (`.dart_tool/`, `.flutter-plugins-dependencies`, `**/Flutter/ephemeral/`, `**/Pods/`, `*.iml`, `.idea/` — `flutter create` writes `.idea/` and `<pkg>.iml` — and `coverage/`; the template already ignores `build/`). No `pub get`.
- Overlay — `lib/app.dart`: `GreetingApp`, a `MaterialApp` whose home shows `Hello from __NAME__`; `lib/main.dart`: `WidgetsFlutterBinding.ensureInitialized()`, then `exit(0)` from `dart:io` when `Platform.environment['SPECFLOW_SMOKE'] == '1'` (REQ-390), else `runApp(const GreetingApp())`.
- `gates.sh` — `flutter pub get --enforce-lockfile`; `dart analyze --fatal-infos`; `flutter test`; `PASS`/`FAIL` per step; exit 1 on any failure.
- `security.sh` — the P4 stub verbatim.
- `release.sh` — needs `VERSION`, `DIST_DIR`; refuses (before building) unless `VERSION` equals `pubspec.yaml` `version` without its `+build` suffix; clears `build/macos/Build/Products/Release`; `flutter build macos --release --no-pub` (no implicit `pub get`, so no network in the release hook; the gates ran `pub get --enforce-lockfile`; measured to build); requires exactly one `*.app` there (exit 1 listing them otherwise); `ditto -c -k --sequesterRsrc --keepParent <app> <fresh mktemp dir>/<pubspec name>-<VERSION>-macos-arm64.zip` (keeps signatures and extended attributes); copies it into `DIST_DIR`; `manifest.json` listing only it.
- `action.yml` — composite: setup-python 3.12 and `pip install -r scripts/requirements.txt`; inputs `flutter_version` and `flutter_revision` defaulting to the pack's pins; `actions/cache@v4` on the runner tool-cache directory `flutter-<revision>` keyed on the revision; on a miss, `git clone --depth 1 --branch <flutter_version> https://github.com/flutter/flutter.git <dir>` and then `test "$(git -C <dir> rev-parse HEAD)" = <flutter_revision>` (a tag that moved fails the job); `<dir>/bin` appended to `GITHUB_PATH`; `flutter precache --macos`; `flutter --version --machine` re-checked against the revision. No `subosito/flutter-action` (it pins by version only). The Dart SDK and engine artifacts the SDK then downloads are the P4 exception in Global Constraints. Floor tools: P4.
- `store-checklist.md` — Task 3's items with Flutter specifics: bundle identifier in `macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`); packaging is the `.zip` from `release-flutter.sh` made with `ditto` (a `.dmg` via `hdiutil create` is optional); arm64 only because Flutter 3.35.5's universal build fails on Xcode 27 (`lipo -verify_arch`, measured 2026-09-25), revisit on the next Flutter pin; minimum macOS 12.0.

Skeleton test (given in full):

```dart
// stacks/flutter/overlay/test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:__PKG__/app.dart';

void main() {
  testWidgets('shows the greeting', (tester) async {
    await tester.pumpWidget(const GreetingApp());
    expect(find.text('Hello from __NAME__'), findsOneWidget);
  });
}
```

- [ ] **Step 1: Write the failing tests** — append to `tests/governance/test_stack_packs.sh` before `finish`:

```bash
# --- flutter pack (REQ-303/304/305): static contract; no toolchain, no network ---
F="$ROOT/stacks/flutter"; FO="$F/overlay"; fv() { val "$F/pack.yml" get "$1"; }
ck "stacks/flutter present" test -d "$F"
for k in flutter_version macos_host lockfile; do ck "flutter: pack.yml pins $k" [ -n "$(fv $k)" ]; done
ck "flutter: guided choice 3, a multi-platform app" [ "$(fv guided_choice):$(fv guided_label)" = "3:a multi-platform app" ]
ck "flutter: CI runner is macos-15" [ "$(fv ci_runs_on)" = macos-15 ]
ck "flutter: pack minimum macOS 12.0 (Xcode 27 rejects 10.15)" [ "$(fv macos_min)" = 12.0 ]
ck "flutter: arm64 only (Xcode 27 lipo)" [ "$(fv macos_archs)" = arm64 ]
ck "flutter: coverage_exclude" [ "$(val "$F/pack.yml" getlist coverage_exclude | tr '\n' ' ')" = "lib/main.dart " ]
for f in lib/main.dart lib/app.dart test/widget_test.dart osv-scanner.toml; do ck "flutter overlay has $f" test -f "$FO/$f"; done
ck "flutter: main.dart honours SPECFLOW_SMOKE" grep -q SPECFLOW_SMOKE "$FO/lib/main.dart"
ck "flutter: the widget test imports the package by token" grep -qF 'package:__PKG__/app.dart' "$FO/test/widget_test.dart"
ck "flutter: init.sh creates macOS only and rewrites the minimum" bash -c "grep -q macos_min '$F/init.sh' && grep -q flutter_version '$F/init.sh' && grep -q -- '--platforms=macos' '$F/init.sh' && grep -q MACOSX_DEPLOYMENT_TARGET '$F/init.sh' && grep -q 'platform :osx' '$F/init.sh' && grep -q 'ARCHS' '$F/init.sh'"
for w in 'flutter pub get --enforce-lockfile' 'dart analyze --fatal-infos' 'flutter test'; do ck "flutter: gates.sh runs $w" grep -qF -- "$w" "$F/gates.sh"; done
ck "flutter: pack.yml pins the SDK by a 40-hex frameworkRevision (dfe-4)" grep -qE '^[0-9a-f]{40}$' <<<"$(fv flutter_revision)"
ck "flutter: action verifies the SDK revision and precaches macOS" bash -c "grep -qF '$(fv flutter_revision)' '$F/action.yml' && grep -q 'rev-parse HEAD' '$F/action.yml' && grep -qF 'flutter precache --macos' '$F/action.yml' && ! grep -q subosito '$F/action.yml'"
ck "flutter: the doctor check and install hint both verify the revision" bash -c "[ \$(grep -E '^(check|install_macos)_flutter:' '$F/pack.yml' | grep -cF '$(fv flutter_revision)') = 2 ]"
ck "flutter: init.sh checks the SDK revision, not the tag" grep -q flutter_revision "$F/init.sh"
ck "flutter: release.sh builds with --no-pub (no network in a release hook)" grep -qF -- '--no-pub' "$F/release.sh"
for w in 'Apple Developer Program' APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD notarytool stapler Gatekeeper 'App Store' 'Developer ID' ditto .zip; do
  ck "flutter: store-checklist names $w" grep -qF -- "$w" "$F/store-checklist.md"
done
for k in $(val "$F/pack.yml" getlist prereqs); do ck "flutter: install_linux_$k is honest (macOS only)" grep -qi macos <<<"$(fv "install_linux_$k")"; done
ck "flutter: Calendar is a valid package" [ "$(pkg "$F" Calendar calendar)" = calendar ]
for n in flutter flutter_test test class library import late required async source collection meta cupertino_icons flutter_lints; do
  ck "flutter: package '$n' refused (exit 2)" [ "$(rc_of pkg "$F" X "$n")" = 2 ]
done
# release.sh contract without a toolchain: fake flutter and ditto stand in for the build and the zip.
R="$W/rel-flutter"; mkdir -p "$R/bin" "$R/app/build/macos/Build/Products/Release/old.app"
printf 'name: fix\nversion: 0.1.0+1\n' > "$R/app/pubspec.yaml"
cat > "$R/bin/flutter" <<'FAKE'
#!/usr/bin/env bash
touch "$FAKE_MARK"; printf '%s\n' "$@" > "$FAKE_ARGV"; d=build/macos/Build/Products/Release
for n in $FAKE_APPS; do mkdir -p "$d/$n.app/Contents/MacOS"; head -c 2048 /dev/urandom > "$d/$n.app/Contents/MacOS/$n"; done
FAKE
cat > "$R/bin/ditto" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do src="${dest:-}"; dest="$a"; done
python3 -c 'import os, shutil, sys; shutil.make_archive(sys.argv[2][:-4], "zip", os.path.dirname(sys.argv[1]), os.path.basename(sys.argv[1]))' "$src" "$dest"
FAKE
chmod +x "$R/bin/flutter" "$R/bin/ditto"
frel() { (cd "$R/app" && env PATH="$R/bin:$PATH" FAKE_MARK="$R/mark" FAKE_ARGV="$R/argv" "$@" bash "$F/release.sh"); }
ck "flutter release: a VERSION unlike pubspec.yaml is refused" [ "$(rc_of frel VERSION=0.2.0 DIST_DIR="$R/d0" FAKE_APPS=fix)" != 0 ]
ck "flutter release: the refusal comes before building" no test -e "$R/mark"
ck "flutter release: one zipped app built" frel VERSION=0.1.0 DIST_DIR="$R/d1" FAKE_APPS=fix
ck "flutter release: manifest lists exactly one .zip, verified" python3 - "$R/d1" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
names = [e["filename"] for e in m["artifacts"]]
assert m["version"] == "0.1.0" and len(names) == 1 and names[0].endswith(".zip"), m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
ck "flutter release: a stale .app is cleared before building" no test -e "$R/app/build/macos/Build/Products/Release/old.app"
ck "flutter release: the build runs --release --no-pub (no network)" bash -c "grep -qx -- --release '$R/argv' && grep -qx -- --no-pub '$R/argv'"
ck "flutter release: two apps are refused" [ "$(rc_of frel VERSION=0.1.0 DIST_DIR="$R/d2" FAKE_APPS='a b')" != 0 ]
# init.sh preflight/scaffold without a toolchain: a fake flutter stands in for the SDK and its generator.
if [[ ! -f "$F/init.sh" ]]; then fail "flutter: init.sh missing — scaffold harness not run"; else
S="$W/scaf-flutter"; SR="$S/sdk"; mkdir -p "$S/bin" "$SR/packages/flutter_tools/templates/cocoapods" "$S/root/scripts/lib/specflow" "$S/root/stacks"
cp "$ROOT/scripts/lib/specflow/config.py" "$S/root/scripts/lib/specflow/"; cp -R "$F" "$S/root/stacks/flutter"; SF="$S/root/stacks/flutter"
printf "platform :osx, '10.15'\n\nflutter_macos_podfile_setup\n" > "$SR/packages/flutter_tools/templates/cocoapods/Podfile-macos"
cat > "$S/bin/flutter" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '{\n  "frameworkVersion": "%s",\n  "frameworkRevision": "%s",\n  "flutterRoot": "%s"\n}\n' "$FAKE_VER" "$FAKE_REV" "$FAKE_ROOT"; exit 0; fi
[[ "${1:-}" == create ]] || exit 0
for a in "$@"; do d="$a"; done; p=""; while [[ $# -gt 0 ]]; do [[ "$1" == --project-name ]] && p="$2"; shift; done
mkdir -p "$d/lib" "$d/test" "$d/macos/Runner.xcodeproj" "$d/macos/Runner/Configs" "$d/macos/Runner/Assets.xcassets/AppIcon.appiconset"
printf 'name: %s\nversion: 1.0.0+1\n' "$p" > "$d/pubspec.yaml"
echo 'generated main' > "$d/lib/main.dart"; echo 'generated test' > "$d/test/widget_test.dart"
for i in 1 2 3; do echo '    MACOSX_DEPLOYMENT_TARGET = 10.15;'; done > "$d/macos/Runner.xcodeproj/project.pbxproj"
echo '#include "../../Flutter/Flutter-Release.xcconfig"' > "$d/macos/Runner/Configs/Release.xcconfig"
printf '\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80' > "$d/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png"
echo 'generator readme' > "$d/README.md"; echo '.dart_tool/' > "$d/.gitignore"
FAKE
chmod +x "$S/bin/flutter"
fscaf() { (cd "$1" && env PATH="$S/bin:$PATH" FAKE_ROOT="$SR" FAKE_VER="$(fv flutter_version)" FAKE_REV="${FAKE_REV_OVERRIDE:-$(fv flutter_revision)}" SPECFLOW_NAME='Acme Notes' SPECFLOW_PKG=acme_notes bash "$SF/init.sh" "$2"); }
mkdir -p "$S/old"
ck "flutter scaffold: another SDK revision is refused (exit 1)" [ "$(FAKE_REV_OVERRIDE=0000000000000000000000000000000000000000 rc_of fscaf "$S/old" scaffold)" = 1 ]
ck "flutter scaffold: that refusal wrote nothing" [ -z "$(ls -A "$S/old")" ]
ck "flutter preflight: another SDK revision fails the preflight (exit 1)" [ "$(FAKE_REV_OVERRIDE=0000000000000000000000000000000000000000 rc_of fscaf "$S/old" preflight)" = 1 ]
A="$S/app"; mkdir -p "$A"; echo 'my readme' > "$A/README.md"; printf 'mine/\n' > "$A/.gitignore"
ck "flutter scaffold: the pinned SDK scaffolds (exit 0)" fscaf "$A" scaffold
ck "flutter scaffold: every MACOSX_DEPLOYMENT_TARGET is the pack minimum" python3 - "$A/macos/Runner.xcodeproj/project.pbxproj" "$(fv macos_min)" <<'PY'
import re, sys
vals = re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);", open(sys.argv[1]).read())
assert len(vals) == 3 and set(vals) == {sys.argv[2]}, vals
PY
ck "flutter scaffold: Podfile from the SDK template at the pack minimum" [ "$(head -1 "$A/macos/Podfile" 2>/dev/null)" = "platform :osx, '$(fv macos_min)'" ]
ck "flutter scaffold: Release.xcconfig gains ARCHS = arm64 once" [ "$(grep -c '^ARCHS = arm64$' "$A/macos/Runner/Configs/Release.xcconfig" 2>/dev/null)" = 1 ]
ck "flutter scaffold: version 0.1.0+1" grep -qx 'version: 0.1.0+1' "$A/pubspec.yaml"
ck "flutter scaffold: the overlay replaces the generated main.dart" grep -q SPECFLOW_SMOKE "$A/lib/main.dart"
ck "flutter scaffold: overlay tokens substituted" bash -c "grep -qF 'package:acme_notes/app.dart' '$A/test/widget_test.dart' && grep -qF 'Hello from Acme Notes' '$A/lib/app.dart'"
ck "flutter scaffold: generated binaries are copied byte for byte" python3 -c 'import sys; sys.exit(open(sys.argv[1], "rb").read() != b"\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80")' "$A/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png"
ck "flutter scaffold: an existing README.md is kept" [ "$(cat "$A/README.md")" = 'my readme' ]
ck "flutter scaffold: .gitignore keeps its lines, skips the generator's, gains the block once" bash -c "grep -qx 'mine/' '$A/.gitignore' && grep -qx '.idea/' '$A/.gitignore' && [ \$(grep -c '^# >>> specflow flutter pack' '$A/.gitignore') = 1 ]"
cp "$A/.gitignore" "$S/gi.before"; cp "$A/pubspec.yaml" "$S/pub.before"
rc=0; out=$(fscaf "$A" scaffold 2>&1) || rc=$?
ck "flutter scaffold: a second run refuses (exit 1)" [ "$rc" = 1 ]
ck "flutter scaffold: the refusal names the clashing file" grep -qE 'pubspec\.yaml|lib/|test/|macos/' <<<"$out"
ck "flutter scaffold: the refused run changed nothing" bash -c "cmp -s '$A/.gitignore' '$S/gi.before' && cmp -s '$A/pubspec.yaml' '$S/pub.before'"
B="$S/again"; mkdir -p "$B"; printf '# >>> specflow flutter pack\n.dart_tool/\n# <<< specflow flutter pack\n' > "$B/.gitignore"
fscaf "$B" scaffold >/dev/null 2>&1 || true
ck "flutter scaffold: an existing block is not appended again" [ "$(grep -c '^# >>> specflow flutter pack' "$B/.gitignore")" = 1 ]
ck "flutter init.sh: an unknown subcommand exits 2" [ "$(rc_of fscaf "$A" frobnicate)" = 2 ]
if [ -x /usr/bin/flutter ] || [ -x /bin/flutter ]; then echo "SKIP: flutter in /usr/bin or /bin — missing-flutter preflight case not run"; else
  mkdir -p "$S/noflutter"; ln -s "$(command -v python3)" "$S/noflutter/python3"
  rc=0; out=$(cd "$A" && env PATH="$S/noflutter:/usr/bin:/bin" SPECFLOW_NAME=X SPECFLOW_PKG=x bash "$SF/init.sh" preflight 2>&1) || rc=$?
  ck "flutter preflight: missing flutter exits 1" [ "$rc" = 1 ]
  ck "flutter preflight: names flutter and the doctor" bash -c "grep -q '^preflight: missing flutter' <<<\"\$1\" && grep -qF -- '--doctor --stack flutter' <<<\"\$1\"" _ "$out"
fi
fi   # scaffold harness
```

In `tests/governance/test_examples.sh`, case 4's loop header becomes `for s in tauri flutter; do`.

- [ ] **Step 2: Run them — expect** `FAIL: stacks/flutter present` and every flutter check FAIL, including `FAIL: flutter: init.sh missing — scaffold harness not run`, except the three release refusals (VERSION, before building, two apps), vacuous as in Task 3; `test_examples.sh` prints `FAIL: stacks/flutter missing`. Exit 1. As in Task 3, implement `init.sh package` first; with `preflight` and `scaffold` still unknown subcommands, the harness runs and every scaffold and preflight check in it FAILs except the unknown-subcommand one.

- [ ] **Step 3: Implement (intent)** — the pack per Interfaces; copy `_keywords` and `_packageDependencies` from the pinned SDK's `create_base.dart` into `init.sh` (Task 6's first run checks the copy against the SDK); `pubspec.lock` and the osv entries come in Task 6. Once `stacks/flutter/` exists, init's absent-pack notes (`init-project.sh:242-243`) no longer print in the template; keep them (they still guard a checkout with a pack removed).

- [ ] **Step 4: Run** `for t in stack_packs examples init init_doctor; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green; a guided Enter-through in a copy now shows (1) (2) (3) and still picks python.

- [ ] **Step 5: Commit** — "feat(stacks): flutter pack — SDK pinned by revision, preflight, pack minimum macOS 12.0, arm64 offline release, flutter create's full package rule, overlay, store checklist (REQ-303, REQ-304, REQ-305, REQ-306)"

---

### Task 6: The flutter skeleton on this Mac — `pubspec.lock`, advisories, first run

**Opt-in; expected wall-clock on this Mac:** the flutter first-run case about 1.5 minutes (init about 2 s, core gates about 5 s, `pub get` 1 s, `dart analyze` 2 s, `flutter test` 4 s, `flutter build macos --release` 17 s, zip under 1 s, smoke under 5 s). It stays inside the default Darwin case list: the release run is far under the ~10-minute bound, so no second opt-in variable is added.

**Files:** create `stacks/flutter/overlay/pubspec.lock`, `stacks/flutter/overlay/macos/Flutter/GeneratedPluginRegistrant.swift`; fill `stacks/flutter/overlay/osv-scanner.toml`; modify `tests/governance/test_stack_packs.sh` (append), `tests/governance/test_first_run.sh` (flutter case before `*)`).

**Interfaces:** `pubspec.lock` carries no root-package name (checked); once it ships, `init.sh package` refuses every package key in it (Task 5, rule d). `macos/Flutter/GeneratedPluginRegistrant.swift` — what `flutter pub get` writes for a plugin-free app (the `FlutterMacOS` and `Foundation` imports, an empty `RegisterGeneratedPlugins`), captured at pin time; `flutter create --no-pub` omits it although `project.pbxproj` refers to it, so without it the gates' `pub get` would leave it untracked and the clean-tree check would fail. `osv-scanner.toml` as in Task 4 with the header naming `pubspec.lock sha256 <hex>`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/governance/test_stack_packs.sh` before `finish`:

```bash
ck "flutter overlay ships pubspec.lock" test -s "$FO/pubspec.lock"
ck "flutter overlay ships the plugin registrant pub get would write" bash -c "grep -q 'import FlutterMacOS' '$FO/macos/Flutter/GeneratedPluginRegistrant.swift' && grep -q 'func RegisterGeneratedPlugins' '$FO/macos/Flutter/GeneratedPluginRegistrant.swift'"
for n in clock fake_async stack_trace; do ck "flutter: package '$n' (a locked dependency) refused (exit 2)" [ "$(rc_of pkg "$F" X "$n")" = 2 ]; done
ck "flutter: osv-scanner.toml was enumerated against the shipped pubspec.lock" python3 - "$FO" <<'PY'
import datetime, hashlib, pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1]); text = (o / "osv-scanner.toml").read_text()
h = hashlib.sha256((o / "pubspec.lock").read_bytes()).hexdigest()
assert re.search(r"osv-scanner \d+\.\d+\.\d+ on \d{4}-\d{2}-\d{2}", text), "header must name the osv-scanner version and date"
assert f"pubspec.lock sha256 {h}" in text, f"header must record pubspec.lock sha256 {h}"
for v in tomllib.loads(text).get("IgnoredVulns", []):
    assert v.get("id") and v.get("reason") and isinstance(v.get("ignoreUntil"), datetime.date), v
PY
```

In `tests/governance/test_first_run.sh`, before the `*)` arm:

```bash
    flutter)   # macOS (REQ-360): engineer flags — the multi-platform pack's macOS build end to end
      D="$WORK/acme-notes"; copy_template "$D"
      ck "flutter: init with flags" bash -c "cd '$D' && bash scripts/init-project.sh --name 'Acme Notes' --stack flutter --profile engineer --path regulated --solo false </dev/null"
      ck "flutter: pubspec.lock, osv list, Podfile and plugin registrant committed" git -C "$D" ls-files --error-unmatch pubspec.lock osv-scanner.toml macos/Podfile macos/Flutter/GeneratedPluginRegistrant.swift
      FROOT=$(flutter --version --machine 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["flutterRoot"])' 2>/dev/null || true)
      ck "flutter: the package rule refuses every _keywords and _packageDependencies name of the pinned SDK" python3 - "$FROOT/packages/flutter_tools/lib/src/commands/create_base.dart" "$ROOT/stacks/flutter/init.sh" <<'PY'
import os, re, subprocess, sys
src = open(sys.argv[1]).read()
names = []
for var in ("_keywords", "_packageDependencies"):
    names += re.findall(r"'([a-z_]+)'", re.search("const " + var + r" = <String>\{(.*?)\};", src, re.S).group(1))
assert len(names) > 60, names
env = dict(os.environ, SPECFLOW_NAME="X")
bad = [n for n in names if subprocess.run(["bash", sys.argv[2], "package"], env=dict(env, SPECFLOW_PKG=n), capture_output=True).returncode != 2]
assert not bad, f"not refused: {bad}"
PY
      MIN=$(python3 "$D/scripts/lib/specflow/config.py" --file "$D/.specflow/pack.yml" get macos_min 2>/dev/null || true)
      ck "flutter: every MACOSX_DEPLOYMENT_TARGET is the pack minimum ($MIN)" python3 - "$D/macos/Runner.xcodeproj/project.pbxproj" "$MIN" <<'PY'
import re, sys
vals = set(re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);", open(sys.argv[1]).read()))
assert vals == {sys.argv[2]}, vals
PY
      ck "flutter: Podfile platform is the pack minimum" grep -qE "^platform :osx, '$MIN'" "$D/macos/Podfile"
      ck "flutter: release builds arm64 only (Xcode 27 lipo)" grep -qE '^ARCHS = arm64' "$D/macos/Runner/Configs/Release.xcconfig"
      ck "flutter: init left a clean tree" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ]
      gates "$D" "flutter/engineer/regulated/team"
      if command -v osv-scanner >/dev/null 2>&1; then
        floor "flutter: osv-scanner" osv-scanner scan source --config "$D/osv-scanner.toml" -L "$D/pubspec.lock"
      else echo "SKIP: osv-scanner not installed — flutter floor not run (P4 installs it in CI)"; fi
      ck "flutter: release-flutter.sh zips the app" bash -c "cd '$D' && VERSION=0.1.0 DIST_DIR='$WORK/dist-flutter' bash scripts/release-flutter.sh"
      ck "flutter: manifest lists exactly one .zip that verifies" manifest "$WORK/dist-flutter" 0.1.0 .zip
      ck "flutter: SPECFLOW_SMOKE=1 start-up exits 0 within 60 s" run_within 60 env SPECFLOW_SMOKE=1 "$D/build/macos/Build/Products/Release/acme_notes.app/Contents/MacOS/acme_notes"
      ck "flutter: gates and release leave the tree clean" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ] ;;
```

- [ ] **Step 2: Run them — expect** in `test_stack_packs.sh` the lock, registrant, three locked-dependency refusals and enumeration checks FAIL (no `pubspec.lock`, no registrant). `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=flutter bash tests/governance/test_first_run.sh`: the committed-files check FAILs on `pubspec.lock` and the registrant; the `_keywords` check passes (Task 5 copied the set); the gates FAIL at `flutter pub get --enforce-lockfile` (nothing to enforce); the final clean-tree check FAILs on the untracked `macos/Flutter/GeneratedPluginRegistrant.swift` that `pub get` wrote. Exit 1.

- [ ] **Step 3: Implement (intent)** — in an empty scratch directory: `SPECFLOW_NAME=Pin SPECFLOW_PKG=pin_app bash <template>/stacks/flutter/init.sh scaffold`; `flutter pub get`; `bash <template>/stacks/flutter/gates.sh` passes; copy `pubspec.lock` into the overlay (confirm `grep -c pin_app pubspec.lock` is 0) and `macos/Flutter/GeneratedPluginRegistrant.swift` into `overlay/macos/Flutter/` (confirm it names no package; re-running `flutter pub get` in a committed copy leaves `git status` empty). Run `osv-scanner scan source -L pubspec.lock --format json` (installed in Task 4), list every id with reason and `ignoreUntil`, write the header, re-run with the list: clean.

- [ ] **Step 4: Run** `bash tests/governance/test_stack_packs.sh && bash scripts/run-quality-gates.sh && time SPECFLOW_FIRST_RUN=1 bash tests/governance/test_first_run.sh` — on this Mac, with both packs' prerequisites reported present by `--doctor`, the default list is `guided engineer tauri flutter` (a `SKIP: <stack> — missing …` line otherwise; then name the stacks in `FIRST_RUN_CASES`); expect green; record the flutter and total wall-clock.

- [ ] **Step 5: Commit** — "feat(stacks): flutter skeleton ships a pinned pubspec.lock, the plugin registrant and an enumerated osv list; macOS first run with release and smoke (REQ-304, REQ-305, REQ-360)"

---

### Task 7: Instances inherit no template-only CI (H5); the gates job uses the pack's runner and toolchain

**Files:** modify `.github/workflows/ci.yml` (`:10-32` gates job; `:34-63` first-run job inside markers), `scripts/init-project.sh` (after the pack install `:384-411`), `stacks/python/pack.yml` (`ci_runs_on: ubuntu-latest`), `tests/governance/test_stack_packs.sh` (`:18` required keys gain `ci_runs_on`), `tests/governance/test_init.sh` (case 10), `tests/governance/test_workflow_health.sh` (`:12-14`, `:16`, new check 7b before `# 8.` at `:85`, `:86` and `:88`).

**Interfaces:**
- `ci.yml`: the first-run job sits between the comment lines `  # >>> specflow:template-only — init-project.sh deletes from here to the end marker` and `  # <<< specflow:template-only` (column 2, inside `jobs:`). The gates job keeps its name `Quality gates (pytest + Dafny + governance)` (a required check in `configure-repo.sh:26`); its `runs-on: ubuntu-latest` line gains the trailing comment `# specflow:runs-on`; after checkout it gains a step `Stack toolchain (installed by init from the pack)` with `if: hashFiles('.github/actions/toolchain/action.yml') != ''` and `uses: ./.github/actions/toolchain`; its Dafny step gains `if: runner.os == 'Linux'` (an app instance has no proofs at init; a macOS Dafny install pinned by checksum comes with P4's action wiring, REQ-330).
- Init, after installing the pack: deletes the marked block from `.github/workflows/ci.yml` (inclusive, `awk`), deletes `.github/workflows/app-stacks.yml` if present (Task 8 creates it), and sets the value on the `# specflow:runs-on` line to the pack's `ci_runs_on` (default `ubuntu-latest` when absent). Every pack declares `ci_runs_on`.
- `test_workflow_health.sh`: `TEMPLATE=true`, false when `.specflow.yml` or `.stack` exists (after `:14`); `WORKFLOWS` gains `app-stacks.yml` only when the file exists; check 7b — template: `ci.yml` carries both markers and `test_first_run.sh` appears only between them; instance: no marker, no `test_first_run.sh`, no `app-stacks.yml`. Check 8 is satisfied by `TEMPLATE=false` (`:86` opens `if [[ $TEMPLATE == false ]] || { grep …`, `:88` closes `…ci.yml; }; then`); `:87`, `:89-92` and everything after stay as they are, so the chore branch's check 9, appended after `:92`, merges cleanly.

- [ ] **Step 1: Write the failing tests**

Add check 7b to `tests/governance/test_workflow_health.sh` immediately before `# 8.` (`:85`), and the `TEMPLATE` line after `:14`:

```bash
TEMPLATE=true; if [[ -f .specflow.yml || -f .stack ]]; then TEMPLATE=false; fi
```

```bash
# 7b. Instances inherit no template-only CI (H5): init deletes the marked jobs and app-stacks.yml.
if [[ $TEMPLATE == true ]]; then
  if grep -q '# >>> specflow:template-only' .github/workflows/ci.yml && grep -q '# <<< specflow:template-only' .github/workflows/ci.yml \
     && [ -z "$(awk '/# >>> specflow:template-only/{f=1} /# <<< specflow:template-only/{f=0} !f && /test_first_run\.sh/' .github/workflows/ci.yml)" ]; then
    pass "ci.yml keeps its template-only jobs between the markers"
  else
    fail "ci.yml template-only jobs are not marked for init to strip (H5)"
  fi
elif grep -qE 'specflow:template-only|test_first_run\.sh' .github/workflows/ci.yml || [[ -e .github/workflows/app-stacks.yml ]]; then
  fail "this instance inherited template-only CI jobs (H5)"
else
  pass "this instance's CI carries no template-only jobs"
fi
```

Append case 10 to `tests/governance/test_init.sh` before `finish`:

```bash
# 10. Instances inherit no template-only CI (H5); the gates job runs on the pack's runner with its toolchain.
D="$WORK/ci-py"; copy_template "$D"; ck "python instance for CI checks" [ "$(rc_of init "$D" --name Ci --profile engineer)" = 0 ]
C="$D/.github/workflows/ci.yml"
ck "instance ci.yml keeps the gates job and its required-check name" grep -qF 'name: Quality gates (pytest + Dafny + governance)' "$C"
ck "instance ci.yml still runs the gates" grep -q 'run-quality-gates.sh' "$C"
ck "instance ci.yml drops the template-only jobs" no grep -qE 'specflow:template-only|test_first_run\.sh' "$C"
ck "instance has no app-stacks.yml" no test -e "$D/.github/workflows/app-stacks.yml"
ck "python instance gates run on ubuntu-latest" grep -qE '^    runs-on: ubuntu-latest' "$C"
ck "the gates job uses the installed toolchain action" grep -qF 'uses: ./.github/actions/toolchain' "$C"
ck "test_workflow_health passes inside the instance" bash -c "cd '$D' && bash tests/governance/test_workflow_health.sh"
D="$WORK/ci-tauri"; copy_template "$D"
ck "tauri instance (no scaffold) for CI checks" [ "$(rc_of ninit "$D" --name Ci --stack tauri)" = 0 ]
ck "tauri instance gates run on macos-15" grep -qE '^    runs-on: macos-15' "$D/.github/workflows/ci.yml"
```

- [ ] **Step 2: Run them — expect** `test_workflow_health.sh` check 7b to FAIL (no markers). `test_init.sh` case 10: the instance keeps the first-run job, so `drops the template-only jobs` and `uses the installed toolchain action` FAIL, the tauri instance still says `ubuntu-latest` so its check FAILs, and `test_workflow_health passes inside the instance` FAILs on 7b; the other case-10 checks pass (`app-stacks.yml` does not exist yet). `test_stack_packs.sh`: `python: pack.yml declares ci_runs_on` FAILs. Exit 1.

- [ ] **Step 3: Implement (intent)** — per Interfaces: markers and the gates-job changes in `ci.yml`; the strip, delete and runner steps in init; `ci_runs_on` in python's `pack.yml`; the required-key list; the `TEMPLATE` flag, `WORKFLOWS` and the two check-8 lines.

- [ ] **Step 4: Run** `for t in init workflow_health template_instantiation stack_packs; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh && SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="guided engineer" bash tests/governance/test_first_run.sh` — expect green.

- [ ] **Step 5: Commit** — "fix(ci): instances drop template-only jobs; the gates job runs on the pack's runner with its toolchain action (REQ-303, REQ-360)"

---

### Task 8: App-stack CI — `app-stacks.yml` on `macos-15`; the ubuntu profile diff

**Opt-in:** the new workflow runs only on `workflow_dispatch`, weekly, and on PRs touching the packs. Estimates on the 3-vCPU `macos-15` runner, restated after review: tauri cold about 10–15 minutes (the generator's `Cargo.toml` sets `[profile.release] lto = true, codegen-units = 1`, so the 102 s release build here will take several times longer, plus a cold debug `cargo test`), warm about 4–6 minutes once the cargo registry and a fixed `CARGO_TARGET_DIR` are restored; flutter cold about 4–6 minutes (SDK clone and precache), warm 2–3. Dispatch twice after pushing — the first run is cold, the second warm — and record both in the PR body; if the warm tauri run exceeds the spec's 10 minutes, say so there as a known gap for the reviewer rather than claiming the target. The ubuntu job initializes four instances with `SPECFLOW_NO_SCAFFOLD=1` and never touches node, Rust or Flutter (under 30 s).

**Files:** create `.github/workflows/app-stacks.yml`; modify `.github/workflows/ci.yml` (an `app-profiles` job inside the template-only markers), `tests/governance/test_first_run.sh` (`profiles` case; `profiles` joins `DEFAULT_CASES`), `tests/governance/test_workflow_health.sh` (checks 7c and 7d, after 7b, still before `# 8.`).

**Interfaces:**
- `app-stacks.yml`: `name: App stacks (macOS)`; `on:` `workflow_dispatch:`, `schedule:` one weekly `cron`, `pull_request:` with `paths:` `stacks/tauri/**`, `stacks/flutter/**`, `.github/workflows/app-stacks.yml` (either pack's change runs both stacks, about 2 extra minutes; one file keeps the wiring in one place); top-level `permissions: contents: read`; job `first-run`, `runs-on: macos-15`, `timeout-minutes: 30`, matrix `stack: [tauri, flutter]`, `fail-fast: false`, named from the matrix value as `First run (<stack>, macos-15)`; job env `CARGO_TARGET_DIR` set to `first-run-target` under the runner's temp directory (outside the checkout, so `copy_template` never copies it and the instance tree stays clean); steps: checkout; `uses: ./stacks/tauri` with `if: matrix.stack == 'tauri'` and `with: rust_cache: "false"` (rust-cache cannot see the instance, which `test_first_run.sh` creates later under `mktemp -d`; in the template checkout there is no `src-tauri/`); for tauri, `actions/cache@v4` on `~/.cargo/registry/index`, `~/.cargo/registry/cache`, `~/.cargo/git/db`, `~/.npm` and the `CARGO_TARGET_DIR` path, keyed on the runner OS, the pack's `rust_version` and the hash of `stacks/tauri/overlay/src-tauri/Cargo.lock` and `stacks/tauri/overlay/package-lock.json`; `uses: ./stacks/flutter` with `if: matrix.stack == 'flutter'` (its action caches the SDK by revision); for flutter, `actions/cache@v4` on `~/.pub-cache` keyed on `stacks/flutter/overlay/pubspec.lock`; `bash tests/governance/test_first_run.sh` with env `SPECFLOW_FIRST_RUN: "1"` and `FIRST_RUN_CASES` set to the matrix value. `release.sh` and the tauri smoke path already honour `CARGO_TARGET_DIR` (Tasks 3, 4). Not a required check.
- `ci.yml` job `app-profiles`, named `App-stack profiles (tauri, flutter)`, `runs-on: ubuntu-latest`, inside the markers (so instances never inherit it): checkout, then `bash tests/governance/test_first_run.sh` with `SPECFLOW_FIRST_RUN: "1"` and `FIRST_RUN_CASES: profiles`. No setup-node, flutter-action, rustup or cargo step.
- H4 decision, asserted by `profiles`: for each app stack, the guided and engineer instances (same name, stack, lanes, solo) differ in exactly `.specflow.yml` (the `profile:` line), `CLAUDE.md` (the `- Profile:` line) and `IDEA.md` (guided's `## Stack` rationale), and are otherwise byte-identical. `init.sh scaffold` receives only `SPECFLOW_NAME`/`SPECFLOW_PKG`, so skipping it removes nothing profile-dependent: the scaffold-free diff is the whole profile dimension.

- [ ] **Step 1: Write the failing tests**

In `tests/governance/test_first_run.sh`, the `DEFAULT_CASES` line becomes `DEFAULT_CASES="guided engineer profiles"; if …` (same Darwin clause), and before `*)`:

```bash
    profiles)   # REQ-360 on ubuntu: the profile dimension for app stacks, no toolchain (SPECFLOW_NO_SCAFFOLD)
      for s in tauri flutter; do
        for p in guided engineer; do
          E="$WORK/prof-$s-$p/acme"; mkdir -p "$(dirname "$E")"; copy_template "$E"
          ck "$s/$p: scaffold-free init" bash -c "cd '$E' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Acme --stack $s --profile $p --path lanes --solo true </dev/null"
        done
        G="$WORK/prof-$s-guided/acme"; N="$WORK/prof-$s-engineer/acme"
        ck "$s: the profiles differ in exactly .specflow.yml, CLAUDE.md and IDEA.md" [ "$(diff -rq -x .git -x __pycache__ "$G" "$N" | sed -E 's#^Files .*/acme/([^ ]+) and .*#\1#' | LC_ALL=C sort | tr '\n' ' ')" = ".specflow.yml CLAUDE.md IDEA.md " ]
        ck "$s: .specflow.yml differs only in profile" [ "$(diff "$G/.specflow.yml" "$N/.specflow.yml" | grep -E '^[<>]' | tr '\n' '|')" = "< profile: guided|> profile: engineer|" ]
        ck "$s: CLAUDE.md differs only in the rendered Profile line (H4)" [ "$(diff "$G/CLAUDE.md" "$N/CLAUDE.md" | grep -E '^[<>]' | cut -c1-13 | tr '\n' '|')" = "< - Profile: |> - Profile: |" ]
        ck "$s: guided IDEA.md records the stack rationale" grep -q '^## Stack' "$G/IDEA.md"
        ck "$s: engineer IDEA.md has no stack rationale" no grep -q '^## Stack' "$N/IDEA.md"
        ck "$s: CLAUDE.md names the stack" grep -q "^- Language: $s" "$G/CLAUDE.md"
        ck "$s: instance CI runs on macos-15" grep -qE '^    runs-on: macos-15' "$G/.github/workflows/ci.yml"
      done ;;
```

Add after check 7b in `tests/governance/test_workflow_health.sh`:

```bash
# 7c. App stacks gate on macos-15 by dispatch, schedule and their pack paths — never on every PR (REQ-360).
A=.github/workflows/app-stacks.yml
if [[ $TEMPLATE == false ]]; then
  pass "instance: app-stacks.yml is a template-only workflow"
elif [[ -f $A ]] && grep -qE '^[[:space:]]*workflow_dispatch:' "$A" && grep -qE '^[[:space:]]*-?[[:space:]]*cron:' "$A" \
     && grep -qF 'stacks/tauri/**' "$A" && grep -qF 'stacks/flutter/**' "$A" && grep -qE 'runs-on:[[:space:]]*macos-15' "$A" \
     && ! grep -q macos-latest "$A" && grep -qF 'uses: ./stacks/tauri' "$A" && grep -qF 'uses: ./stacks/flutter' "$A" \
     && grep -qE 'SPECFLOW_FIRST_RUN:[[:space:]]*"?1"?' "$A" && grep -qE '^permissions:' "$A" \
     && grep -q 'CARGO_TARGET_DIR:' "$A" && grep -q 'actions/cache@' "$A" && grep -qE 'rust_cache:[[:space:]]*"?false"?' "$A"; then
  pass "app-stacks.yml runs the tauri and flutter first runs on macos-15 with warm-cacheable build dirs"
else
  fail "app-stacks.yml missing or incomplete (REQ-360: dispatch, weekly schedule, pack paths, macos-15, pack actions, cached CARGO_TARGET_DIR)"
fi
# 7d. The ubuntu job asserts the app-stack profile dimension without any app toolchain (REQ-360, H4).
job=$(awk '/^  app-profiles:/{f=1; print; next} f && /^  [A-Za-z#]/{exit} f' .github/workflows/ci.yml)
if [[ $TEMPLATE == false ]]; then
  pass "instance: the profile-diff job is template-only"
elif grep -q 'FIRST_RUN_CASES: profiles' <<<"$job" && grep -q 'ubuntu-latest' <<<"$job" && ! grep -qE 'setup-node|flutter-action|rustup|cargo' <<<"$job"; then
  pass "ci.yml app-profiles job diffs the profiles on ubuntu with no app toolchain"
else
  fail "ci.yml lacks the toolchain-free app-profiles job (REQ-360)"
fi
```

- [ ] **Step 2: Run them — expect** checks 7c and 7d FAIL (no workflow, no job; 7c would also FAIL on a workflow without the cached `CARGO_TARGET_DIR`). `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=profiles bash tests/governance/test_first_run.sh` prints `FAIL: unknown FIRST_RUN_CASES entry 'profiles'`. Exit 1.

- [ ] **Step 3: Implement (intent)** — the workflow and the job per Interfaces (no step installs node, Rust or Flutter in `app-profiles`); the `profiles` case is already written.

- [ ] **Step 4: Run** `for t in workflow_health template_instantiation init; do bash tests/governance/test_$t.sh; done && SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=profiles bash tests/governance/test_first_run.sh && bash scripts/run-quality-gates.sh` — expect green. Then prove the CI layout locally: `CARGO_TARGET_DIR="$(mktemp -d)/first-run-target" SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES=tauri bash tests/governance/test_first_run.sh` — green (the dmg and the smoke binary are found under that directory, and the instance tree stays clean).

- [ ] **Step 5: Commit** — "ci: app-stacks workflow on macos-15 (dispatch, weekly, pack paths); toolchain-free ubuntu profile diff for tauri and flutter (REQ-360)"

---

### Task 9: README, CLAUDE.md and glossary for the app stacks

**Files:** modify `README.md` (`:29` Platforms row; `:38-43` the free-private-repository note gains one sentence on macOS minutes; `:137-150` Scripts table, including the `:144` first-run row; new `### Tauri` and `### Flutter` inserted between `:223` and `:225`, so `### Python` and the chore-owned `:225-249` are untouched), `CLAUDE.md` (`:55-75` Project Map), `docs/GLOSSARY.md` (three entries), `tests/governance/test_onboarding_surface.sh` (append before `finish`).

**Interfaces:**
- `### Tauri` — one line: macOS only; v3.2 builds, tests and ships app stacks on Apple Silicon Macs; on Linux or Windows use a Mac or the `macos-15` CI workflow. A copy-paste block with a verification command after each install: `xcode-select --install` / `xcode-select -p`; the rustup one-liner / `rustup --version && cargo --version`; `rustup toolchain install 1.93.1 --profile minimal` / `rustup toolchain list` (the project's `rust-toolchain.toml` selects 1.93.1; about 200 MB); `brew install node@24 && brew link --overwrite --force node@24` / `node --version`; then `bash scripts/init-project.sh --doctor --stack tauri`. A sentence: the Python tooling below is needed too (the factory's own scripts and tests run on every stack). A CI-cost sentence: an instance's required gates job runs on `macos-15` for every PR push, about 3–5 macOS minutes per run; a free private repository has about 200 macOS minutes a month (macOS minutes count ten times Linux minutes), roughly 40–60 gate runs, and one release build costs far more; public repositories run free.
- `### Flutter` — the same one-line note; block: `xcode-select --install`; Xcode from the App Store, `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, `sudo xcodebuild -runFirstLaunch` / `xcodebuild -version`; `brew install cocoapods` / `pod --version`; the pinned `git clone --depth 1 --branch 3.35.5`, the `git -C … rev-parse HEAD` comparison with `ac4e799d237041cf905519190471f657b657155a` (from `pack.yml`'s `install_macos_flutter`) and the `PATH` line / `flutter --version`; `flutter precache --macos`; then `--doctor --stack flutter`; the same Python sentence and the same CI-cost sentence.
- Free-private-repository note (`:38-43`): one added sentence — Tauri and Flutter instances run their gates on macOS runners, whose minutes a free private repository has about 200 of a month (see `### Tauri`).
- Platforms row: Python (services, CLIs), Tauri (Mac desktop) and Flutter (the macOS build of a multi-platform app); not yet: Windows, Linux desktop, iOS, Android builds, signing automation.
- Scripts table: the `:144` row becomes "Builds and gates throwaway python instances; on a Mac, also the Tauri and Flutter instances whose prerequisites `--doctor` finds (compiles Rust and runs Flutter: several minutes; others print `SKIP`)"; new rows for `SPECFLOW_FIRST_RUN=1 FIRST_RUN_CASES="tauri flutter" bash tests/governance/test_first_run.sh` (macOS: builds, gates, releases and smoke-tests throwaway app instances; fails when a toolchain is missing) and `SPECFLOW_NO_SCAFFOLD=1` (test-only: init without the stack skeleton).
- `CLAUDE.md` map: `stacks/<stack>/` in the template, `.specflow/pack.yml` in an instance; `docs/releases/store-checklist.md` — app stacks: the macOS distribution checklist, appended to release notes from P6 (REQ-352).
- Glossary: `### Pack minimum` (the lowest macOS a pack's bundle supports, set by the pack — Flutter 12.0 because Xcode 27 rejects lower), `### Smoke hook` (`SPECFLOW_SMOKE=1` makes a skeleton start and exit 0; the release job runs it from P6), `### Store checklist` (`docs/releases/store-checklist.md`: signing, notarization, Gatekeeper, packaging, App Store versus direct; a checklist, not automation).
- Init's printed next steps stay as they are: they are stack-neutral. (The lanes text's "`ship/<version>` for VALIDATE" predates P1b and belongs to P5's next-steps rewrite, REQ-343.)

- [ ] **Step 1: Write the failing test** — append before `finish test_onboarding_surface`:

```bash
# P1b (REQ-308): app-stack prerequisites, honest about macOS-only, and the new terms.
appsec() { awk -v h="$1" '$0 ~ "^### " h {f=1; next} f && /^##/{exit} f' README.md; }
for s in Tauri Flutter; do
  blk=$(appsec "$s")
  ck "prerequisites: ### $s" grep -q . <<<"$blk"
  ck "$s: copy-paste installs with --version checks" grep -q -- '--version' <<<"$blk"
  ck "$s: xcode-select --install" grep -qF 'xcode-select --install' <<<"$blk"
  ck "$s: --doctor for the stack" grep -qiF -- "--doctor --stack $(tr '[:upper:]' '[:lower:]' <<<"$s")" <<<"$blk"
  ck "$s: honest one-line Linux note" grep -qiE 'macos only|only on macos' <<<"$blk"
  ck "$s: states the per-PR macOS CI cost and the monthly budget" bash -c "grep -qi 'macOS minutes' <<<\"\$1\" && grep -q '200' <<<\"\$1\"" _ "$blk"
done
ck "Tauri: installs the pinned Rust toolchain" grep -qF 'rustup toolchain install 1.93.1' <<<"$(appsec Tauri)"
ck "Flutter: verifies the SDK revision after cloning" grep -qF 'rev-parse HEAD' <<<"$(appsec Flutter)"
ck "the free-private-repository note mentions macOS minutes" awk '/free-tier private GitHub repository|free private repositor/{f=1} f && /macOS minutes/{hit=1} /^## Quick Start/{exit} END{exit !hit}' README.md
ck "the first-run row says app stacks run only when --doctor finds them" bash -c "grep -E 'test_first_run\.sh' README.md | grep -q -- '--doctor'"
ck "Flutter: flutter precache --macos" grep -qF 'flutter precache --macos' <<<"$(appsec Flutter)"
ck "app sections sit before ### Python" awk '/^### Tauri/{t=NR} /^### Flutter/{f=NR} /^### Python/{p=NR} END{exit !(t && f && p && t < p && f < p)}' README.md
ck "audience names the app stacks" grep -qE 'Tauri' <<<"$aud"
for t in 'Pack minimum' 'Smoke hook' 'Store checklist'; do ck "glossary defines $t" grep -qx "### $t" docs/GLOSSARY.md; done
ck "CLAUDE.md maps the store checklist" grep -qF 'docs/releases/store-checklist.md' CLAUDE.md
ck "README documents SPECFLOW_NO_SCAFFOLD as test-only" grep -q 'SPECFLOW_NO_SCAFFOLD' README.md
```

- [ ] **Step 2: Run it — expect** every new check to FAIL (no sections, no terms, no rows); exit 1. The pre-existing checks stay `ok:` (the glossary count only grows).

- [ ] **Step 3: Rewrite (intent)** — per Interfaces; keep `README.md:225-249` byte-identical. The CI-cost figures come from the spec's Performance line (about 200 macOS minutes a month on a free private repository) and the gate-run times measured in Tasks 4, 6 and 8; if Task 8's dispatches measured otherwise, use the measured figures.

- [ ] **Step 4: Run** `for t in onboarding_surface template_instantiation reviews_use_slugs tooling_hygiene; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green; `git diff main -- README.md` shows no line inside `### Python`.

- [ ] **Step 5: Commit** — "docs(onboarding): Tauri and Flutter prerequisites (macOS only) and their macOS CI cost, app-stack terms, store checklist in the map (REQ-308)"

---

### Task 10: Whole-branch verification and PR

- [ ] **Step 1:** `time bash scripts/run-quality-gates.sh` — green, under 3 minutes (21 s before P1b); no toolchain is invoked (run it once with node, cargo and flutter removed from `PATH` to prove it: `PATH=/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v python3)") bash scripts/run-quality-gates.sh`, with `dafny` added if proofs exist).
- [ ] **Step 2:** `time SPECFLOW_FIRST_RUN=1 bash tests/governance/test_first_run.sh` on this Mac — cases `guided engineer profiles tauri flutter` green (if a `SKIP: <stack> — missing …` line appears, install what it names or re-run with `FIRST_RUN_CASES="guided engineer profiles tauri flutter"`), `floor clean` for each tool on `PATH`; record the per-case wall-clock.
- [ ] **Step 3:** `bash scripts/verify-doc.sh docs/plans/2026-09-25-factory-v3-2-p1b-plan.md` (silent), `bash scripts/analyze-adr-plan-linkage.sh`, `bash scripts/check-traceability.sh`, `bash tests/governance/test_plan_template.sh` — pass.
- [ ] **Step 4:** `git diff main -- scripts/run-quality-gates.sh tests/governance/test_python_lint_format.sh` — empty; `git diff main -- scripts/init-project.sh` touches none of `:119`, `:123`, `:134`; no bare `python` in what P1b touched: `git diff --name-only main -- stacks scripts tests/governance | xargs grep -nE '(^|[ (])python[ ]+-m' 2>/dev/null` — empty (a whole-tree grep still shows the five H6-frozen hits, `scripts/run-quality-gates.sh:21` and `tests/governance/test_python_lint_format.sh:28,30,37,39`, until `chore/p1a-review-fixes` merges; P1b must not add a sixth); `git status --porcelain` — empty.
- [ ] **Step 5:** PR body via `--body-file "$(mktemp)"`: the partial claims and the plans that relist them; the H1–H6 disposition; the `brew install cargo-audit osv-scanner` note with versions, and the `rustup toolchain install 1.93.1 --profile minimal` note (reversible with `rustup toolchain uninstall 1.93.1`); the version-only downloads that remain the P4 exception (Global Constraints, Security; dfe-4); the measured wall-clocks; the cold and warm `app-stacks.yml` dispatch results (trigger each after pushing with `gh workflow run app-stacks.yml --ref impl/plan-1b-app-packs`, the second after the first finishes), with the warm tauri time set against the spec's 10-minute target; gates ticked only if run; attribution footer. Then, in a second terminal outside Claude Code: `scripts/run-verifier.sh <PR#>`.

---

## Deferred by design

- **Open clauses of claimed REQs** — under **Partial claims**, each with the plan that lists the REQ again.
- **Checksum pins for the remaining version-only downloads** (REQ-330, REQ-334, P4; threat model dfe-4) — `actions/setup-node`'s Node, the rustup toolchain, the Dart SDK and engine artifacts the pinned Flutter SDK fetches, Homebrew and rustup-installer doctor hints, and every GitHub Action by tag. P1b pins its generators by content hash and states this exception in Global Constraints; P4 closes it before v3.2 releases.
- **Floor tools in CI** (REQ-330, P4): P1b's first-run runs `cargo-audit`/`osv-scanner` only when they are on `PATH`; the pack actions install them in P4, which also decides how skeleton suppressions cite a `SEC-NNN` (REQ-388).
- **Dafny on `macos-15`** — an app instance has no proofs at init; the gates job's Dafny step is Linux-only until P4's action wiring installs a checksum-pinned macOS Dafny.
- **Universal (arm64 + x86_64) bundles** — Tauri needs `--target universal-apple-darwin`; Flutter 3.35.5 cannot on Xcode 27 (measured). Both packs ship arm64; the store checklists say so; revisit on the next pin.
- **Coverage thresholds** (REQ-325, P3) — `coverage_exclude` and the vitest coverage scope are in place; thresholds and Flutter's `lcov-threshold.sh` are P3's.
