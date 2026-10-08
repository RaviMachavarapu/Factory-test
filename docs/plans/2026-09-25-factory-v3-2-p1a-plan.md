---
type: plan
phase: PLAN
spec: 2026-09-25-factory-v3-2
decisions: []
implements: [REQ-300, REQ-301, REQ-302, REQ-303, REQ-304, REQ-305, REQ-306, REQ-307, REQ-308, REQ-360]
created: "2026-09-25"
---

# Factory v3.2 — P1a: First-Run Path (Core + Python Pack) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** clone, run `bash scripts/init-project.sh` (flags, or Enter at every prompt), and get a python instance on `main` with green gates, a release hook writing a verifiable `dist/manifest.json`, honest onboarding docs for both profiles and paths, and in-repo spec commands.

**Architecture:** one flat `.specflow.yml`, read only via `scripts/lib/specflow/config.py` (`.stack` as fallback). Stacks are packs in `stacks/<stack>/`, copied by init to fixed paths. Examples are listed once, in `CLAUDE.md` "Canonical Example", read by `scripts/lib/specflow/examples.py`. Tests share `tests/governance/lib/check.sh`; a first-run test gates a fresh instance.

**Plan style (REQ-380):** test code included; implementation as intent, never bodies. **Tier:** regulated path (REQ-381), tasks not `## Build N`. REQ-381 exempts only P0's plan from the PLAN phase, so this plan does not travel with its code. It merges first on a PLAN-phase PR from `phase/plan-factory-v3-2-p1a`, cut from `main`, carrying this plan, the REQ-302 spec amendment (Task 11) and `3d3b4ec` (without which `verify-doc.sh` misreads this plan). After that PR merges, `impl/plan-1a-first-run` is cut again from the updated `main` and carries Tasks 1–13 as the IMPLEMENT-phase PR. No task starts before the PLAN PR merges.

**Spec:** `docs/specs/2026-09-25-factory-v3-2-design.md`, "Must Have — P1". Claimed: REQ-300–308 and 360, several in part (below). REQ-343's `review-gate.md` part (ADR-003: before `--path lanes` is selectable) is delivered here and claimed by P5. Nothing is `[verifiable*]`: `decisions: []`, no proof owed.

**Partial claims:** a REQ is listed in `implements:` when this plan delivers its python slice. Each clause below stays open, and the named plan lists the REQ again in its own `implements:`. REQ-300 — `--stack tauri|flutter` and guided options (1) and (3) → P1b. REQ-301 — `signing` values other than `none` → P6 (REQ-354). REQ-303 — tauri and flutter packs → P1b; floor tools in `action.yml` and their `ci.yml` wiring → P4 (REQ-330). REQ-304 — tauri and flutter skeletons → P1b. REQ-305 — tauri and flutter `release.sh` → P1b. REQ-306 — `test_traceability.sh` delegating to `check-covers.sh` → P3 (REQ-323); removing the REQ-391 example when `stack != tauri` → P7. REQ-308 — tauri and flutter prerequisites → P1b; `/next` linking a glossary term → P5. REQ-360 — `macos-15` gate runs and the ubuntu profile diff for app stacks → P1b.

**Verified against:** 2026-09-25 @ main `b7f959b`; every `file:line` anchor was checked there. The branch's first commit, `3d3b4ec`, fixes a false "missing YAML frontmatter" from `scripts/verify-doc.sh` on documents over the pipe buffer (this plan is one), test-first in `tests/unit/test_verify_doc.sh`; it touches no file this plan anchors. Revised after a fresh-eyes review on the same base; Claude Code's built-in command names were checked on 2.1.283 (Task 11).

**Clause → task:** 300 flags 6, `--doctor` 7, prompts/defaults/`main` 6, Enter → green gates 6+12 · 301 writer 1+6, parser and fallback 1 · 302 commands 11, SpecKit gone from init 6 and from README/CLAUDE.md 10, full scan 11 · 303 pack 3, copy and delete 6 · 304 python skeleton 3, green in an instance 12 · 305 contract 3+12, demo hook 4 · 306 tests and `example.dfy` 8, examples removed → green 12, other stacks' examples 9 · 307 2 · 308 rule 5, init 6, docs 10 · 360 12.

## Global Constraints

From the spec: **Performance** — gates on a fresh python instance under 3 minutes on ubuntu, excluding downloads. **Security** — no API key anywhere; CI downloads pinned by version and checksum. **Scalability** — a stack is one directory plus its test entry. **Compliance** — `constitution.md` changes only in amendment PRs A/B/C (not here). **Scope** — no Node or Go; `tests/e2e/` leaves the template and init. **Assumption** — Claude Code reads settings only from `.claude/settings.json`, hook input as stdin JSON. **REQ-380** — gates apply to implemented REQs only.

Plan-level:
- Stdlib-only python in scripts; `config.py` and `examples.py` are flat parsers.
- bash 3.2 (macOS): no associative arrays, `mapfile`, `${v,,}`, or possibly-empty arrays under `set -u`; prompts via `printf` to stderr and `read -r` (bash hides `read -p` prompts off a terminal).
- **Instance** = `.specflow.yml` or legacy `.stack` present, else **template source**; template-only tests skip in instances; `test_python_lint_format.sh` and `test_template_instantiation.sh` keep their guards on the new file.
- Gates stay green on the template source after every task.
- `analyze-adr-plan-linkage.sh` and `check-traceability.sh` are untouched (the `example.dfy` exemption at `check-traceability.sh:124` goes dead after Task 8, harmlessly).
- `review-gate.md` keeps six numbered lines between `## Back-edge protocol` and `## Minor exception` (`test_spec_lifecycle.sh:53-59`) and its RELEASE wording (`:44-51`); init keeps the `for doc in CLAUDE.md README.md; do` loop and `s/` sed that `test_template_instantiation.sh:29-58` parses.
- No `verify-doc.sh`-flagged markers in plans; tests spell double-brace placeholders via `ph`.
- New tests carry `# Covers: REQ-NNN` and source `tests/governance/lib/check.sh` (repo-root cwd, `$ROOT`, `pass`, `fail`, `ck DESC CMD…` passing iff CMD succeeds, `no CMD…`, `instance`, `finish NAME`; from Task 6 `copy_template DEST` and a fixed git identity with `GIT_CONFIG_GLOBAL=/dev/null`).
- One commit per task: stage the task's files after checking `git status`, then commit with the given message. Every commit body ends with the required `Co-Authored-By:` trailer line given to the executing session (as on `bbb3ea1`).

## Review Focus

1. **Enter at every prompt** → guided/python/lanes/solo, profile first, green gates (Task 6 case 2; Task 12).
2. **Only a legacy `.stack`** → `config.py` falls back to it; `.specflow.yml` wins when both exist (Task 1).
3. **`--stack tauri` with no pack** → exit 2 naming `stacks/tauri/`, nothing written, menu hides it (Task 6).
4. **Examples removed, docs emptied** → example-dependent tests and instance gates stay green (Task 8 case 3; Task 12).
5. **Hook stdin JSON** for `docs/specs/x.md` vs `n.md` → `verify-doc.sh` runs for the first only (Task 2).

---

### Task 1: `config.py` — the one reader of `.specflow.yml`

**Files:** create `scripts/lib/__init__.py`, `scripts/lib/specflow/__init__.py` (empty), `scripts/lib/specflow/config.py`, `tests/governance/lib/check.sh`, `tests/governance/test_config.sh`. Delete `scripts/quality-gates-stack.sh.template` (`:3` keys on `.stack`; nothing references it and packs replace it in Task 3), so the `.stack` scan is green when this task ends. Modify the `.stack` readers and writer `scripts/run-quality-gates.sh:67-79`, `.claude/commands/release.md:29`, `scripts/init-project.sh:63-66`; `tests/governance/test_onboarding_surface.sh:59-73`; guards in `test_python_lint_format.sh:7-10,20-24`, `test_template_instantiation.sh:19-25`.

**Interfaces:**
- `config.py`: `KEYS = (profile, path, stack, solo, coverage_min, signing)`, `DEFAULTS` (guided, lanes, python, true, 80, none), `ALLOWED` (guided|engineer, lanes|regulated, python|tauri|flutter, true|false, int 0–100, non-empty), `ConfigError(ValueError)`; `parse(text)` (flat; `#` lines, trailing ` #` comments and quotes stripped as in P0's parsers; indented or colon-less lines raise), `parse_list`, `load(root)` (`.stack` supplies `stack` only when file or key is absent), `validate(cfg) -> list[str]` (one line per bad key), `dump(cfg)` (header "configuration, not pipeline state (art-branch-as-state)", `KEYS` order).
- CLI `[--root DIR | --file PATH] get KEY [--default V]` (exit 1 if absent) · `getlist KEY` · `write K=V…` (defaults ← file ← args, unvalidated) · `validate` (exit 2); exit 2 on parse or usage errors; `--file` never reads `.stack`.
- Gates pick `scripts/quality-gates-<stack>.sh` via `config.py get stack --default none`; an unreadable config is a FAIL.

- [ ] **Step 1: Write the helper and the failing test**

```bash
mkdir -p tests/governance/lib
cat > tests/governance/lib/check.sh <<'EOS'
# Sourced by governance tests (not run by the gates, which glob test_*.sh).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"; cd "$ROOT"
FAIL=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
ck() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
no() { ! "$@"; }
instance() { [[ -f .specflow.yml || -f .stack ]]; }
finish() { if [[ $FAIL -eq 0 ]]; then echo "$1: all checks passed"; else echo "$1: FAILED"; exit 1; fi; }
EOS
cat > tests/governance/test_config.sh <<'EOS'
#!/usr/bin/env bash
# REQ-301: config.py is the one flat reader of .specflow.yml (no PyYAML); a
# legacy .stack is a fallback; no shipped script reads .stack on its own.
# Covers: REQ-301
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CFG="$ROOT/scripts/lib/specflow/config.py"
[[ -f "$CFG" ]] || { fail "scripts/lib/specflow/config.py missing"; finish test_config; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
get() { python3 "$CFG" --root "$1" get "${@:2}" 2>/dev/null || true; }
is() { [ "$(get "$1" "$2" "${@:4}")" = "$3" ]; }   # is DIR KEY WANT [--default V]
mkdir -p "$W/a" "$W/b" "$W/c" "$W/d" "$W/e" "$W/f"
cat > "$W/a/.specflow.yml" <<'EOF'
# SpecFlow configuration (not pipeline state)
profile: "engineer"   # who drives
stack: python

solo: 'false'
coverage_min: 85
EOF
ck "double quotes and trailing comment stripped" is "$W/a" profile engineer
ck "single quotes stripped" is "$W/a" solo false
ck "plain value" is "$W/a" coverage_min 85
echo flutter > "$W/b/.stack"; ck ".stack used when .specflow.yml is absent" is "$W/b" stack flutter
printf 'profile: guided\n' > "$W/c/.specflow.yml"; echo tauri > "$W/c/.stack"
ck ".stack fills a missing stack key" is "$W/c" stack tauri
echo flutter > "$W/a/.stack"; ck ".specflow.yml wins over .stack" is "$W/a" stack python
ck "missing key exits non-zero" no python3 "$CFG" --root "$W/d" get stack
ck "--default applies" is "$W/d" stack none --default none
printf 'stack:\n  name: python\n' > "$W/e/.specflow.yml"
rc=0; python3 "$CFG" --root "$W/e" get stack >/dev/null 2>&1 || rc=$?; ck "nested YAML exits 2" [ "$rc" = 2 ]
python3 "$CFG" --root "$W/f" write stack=python profile=engineer
ck "write emits the six keys in order" [ "$(grep -oE '^[a-z_]+:' "$W/f/.specflow.yml" | tr -d ':' | tr '\n' ' ')" = "profile path stack solo coverage_min signing " ]
ck "write keeps arguments" is "$W/f" profile engineer
ck "write fills defaults" is "$W/f" path lanes
ck "file says configuration, not state" grep -q art-branch-as-state "$W/f/.specflow.yml"
ck "written file validates" python3 "$CFG" --root "$W/f" validate
printf 'profile: boss\nstack: go\n' > "$W/f/.specflow.yml"
rc=0; out=$(python3 "$CFG" --root "$W/f" validate 2>&1) || rc=$?
ck "validate exits 2" [ "$rc" = 2 ]; ck "validate names profile" grep -q profile <<<"$out"; ck "validate names stack" grep -q stack <<<"$out"
printf 'source_roots: [src, "lib"]\n' > "$W/p.yml"
ck "getlist splits a flow list" [ "$(python3 "$CFG" --file "$W/p.yml" getlist source_roots | tr '\n' ' ')" = "src lib " ]
while IFS= read -r f; do
  [[ "$f" == tests/governance/test_config.sh ]] || ck "$f reads .stack only as a fallback" grep -qE '\.specflow\.yml|specflow/config\.py' "$f"
done < <(grep -rlE --exclude-dir=__pycache__ '\.stack([^a-zA-Z_/-]|$)' scripts stacks .github .claude/commands tests/governance 2>/dev/null || true)
ck "quality-gates-stack.sh.template removed (packs replace it)" no test -e scripts/quality-gates-stack.sh.template
ck "run-quality-gates.sh reads the stack via config.py" grep -q lib/specflow/config.py scripts/run-quality-gates.sh
ck "/release reads the stack via config.py" grep -q lib/specflow/config.py .claude/commands/release.md
finish test_config
EOS
chmod +x tests/governance/test_config.sh
```

- [ ] **Step 2: Run it — expect** `FAIL: scripts/lib/specflow/config.py missing`, `test_config: FAILED`, exit 1.

- [ ] **Step 3: Implement (intent)** — `config.py` per Interfaces; delete `scripts/quality-gates-stack.sh.template`; gates §4, `release.md:29` and `init-project.sh:63-66` go through it (an unreadable config prints `FAIL config`); the onboarding check asserts `.specflow.yml`; both guards test `.specflow.yml || .stack`.

- [ ] **Step 4: Run** `bash tests/governance/test_config.sh && bash scripts/run-quality-gates.sh` — expect all `ok:`, `SKIP per-stack hook (scripts/quality-gates-none.sh …)`, `All quality gates passed`.

- [ ] **Step 5: Commit** — "feat(config): .specflow.yml read through lib/specflow/config.py; .stack is a fallback (REQ-301)"

---

### Task 2: Remove dead tooling; settings at `.claude/settings.json`

**Files:** create `tests/governance/test_tooling_hygiene.sh`, `.claude/settings.json`. Delete the seven paths the test lists (`render_template.html` is read only by `render_doc.py:15`). Modify `scripts/requirements.txt:1-6` (`anthropic`; `markdown`, `jinja2` imported only by `render_doc.py`), `tests/conftest.py:1,11`, `test_workflow_health.sh:76-83`, `init-project.sh:60`, `README.md:62`.

**Interfaces:** `.claude/settings.json` — `permissions.deny` `Read(./.env)`, `Read(./.env.*)`, `Read(./secrets/**)`; `hooks.PostToolUse` `[{matcher: "Write|Edit|MultiEdit", hooks: [{type: "command", command}]}]`, the command taking the path from `jq -r .tool_input.file_path` and, for `*/docs/specs/*.md` or `*/docs/plans/*.md` only, running `bash "$CLAUDE_PROJECT_DIR"/scripts/verify-doc.sh "<path>"` with its stdout captured. Claude Code shows a PostToolUse hook's exit-0 stdout only in the transcript and passes stderr to Claude only on exit 2, so when `verify-doc.sh` prints anything the command writes it to stderr and exits 2; otherwise it exits 0 and prints nothing. `jq` joins the prerequisites.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/governance/test_tooling_hygiene.sh <<'EOS'
#!/usr/bin/env bash
# REQ-307: the dead doc renderer is gone with every dependent (no API key
# anywhere); settings are .claude/settings.json in the documented schema.
# Covers: REQ-307
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
for p in scripts/render_doc.py scripts/render-doc.sh scripts/render_template.html .claude/skills/doc-render tests/unit/test_render_doc.py tests/integration/test_render_doc_shell.py settings.json; do
  ck "$p removed" no test -e "$p"
done
ck "no anthropic requirement" no grep -qiE '^anthropic' scripts/requirements.txt
ck "conftest sets no API key" no grep -q ANTHROPIC_API_KEY tests/conftest.py
ck "test_workflow_health no longer forces anthropic" no grep -qE 'for dep in .*anthropic' tests/governance/test_workflow_health.sh
ck "init creates no doc-render skill" no grep -q doc-render scripts/init-project.sh
ck "README and CLAUDE.md drop the renderer" no grep -qE 'render-doc|render_doc' README.md CLAUDE.md
S=.claude/settings.json
ck "$S: documented hooks schema and deny list" python3 - "$S" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
deny = s["permissions"]["deny"]
assert any(".env" in d for d in deny) and any("secrets/" in d for d in deny), deny
cmds = []
for entry in s["hooks"]["PostToolUse"]:
    assert "matcher" in entry and "pathPattern" not in entry, entry
    cmds += [h["command"] for h in entry["hooks"] if h["type"] == "command"]
joined = "\n".join(cmds)
assert "jq -r .tool_input.file_path" in joined and "scripts/verify-doc.sh" in joined, joined
assert "CLAUDE_FILE_PATH" not in joined, joined
PY
if command -v jq >/dev/null 2>&1 && [[ -f $S ]]; then
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  mkdir -p "$W/docs/specs"; echo '# no frontmatter' > "$W/docs/specs/x.md"; echo '# notes' > "$W/n.md"
  cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["PostToolUse"][0]["hooks"][0]["command"])' "$S")
  hook() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_PROJECT_DIR="$ROOT" bash -c "$cmd" >"$W/out" 2>"$W/err"; }
  rc=0; hook "$W/docs/specs/x.md" || rc=$?
  ck "hook exits 2 on a flagged spec (Claude reads stderr only on exit 2)" [ "$rc" = 2 ]
  ck "hook sends verify-doc.sh warnings to stderr" grep -q 'missing YAML frontmatter' "$W/err"
  rc=0; hook "$W/n.md" || rc=$?
  ck "hook ignores other files (exit 0, silent)" [ "$rc" = 0 -a ! -s "$W/out" -a ! -s "$W/err" ]
else
  echo "SKIP: jq or $S absent — functional hook check skipped (--doctor lists jq)"
fi
finish test_tooling_hygiene
EOS
chmod +x tests/governance/test_tooling_hygiene.sh
```

- [ ] **Step 2: Run it — expect** every check to FAIL except the skipped functional hook checks. Exit 1.

- [ ] **Step 3: Implement (intent)** — delete the seven paths; drop `anthropic` (and `markdown`/`jinja2` if nothing else imports them); `conftest.py` loses the key; `test_workflow_health.sh:77` checks `pytest` only; init drops doc-render; `README.md:62` becomes the `verify-doc.sh` row; add the settings file.

- [ ] **Step 4: Run** `bash tests/governance/test_tooling_hygiene.sh && python3 -m pytest tests/ -q && bash scripts/run-quality-gates.sh` — expect all green.

- [ ] **Step 5: Commit** — "chore(tooling): remove the dead doc renderer and the anthropic dependency; .claude/settings.json with documented hooks (REQ-307)"

---

### Task 3: The python stack pack

**Files:** create `stacks/python/` (`init.sh`, `gates.sh`, `security.sh`, `release.sh`, `deploy.sh` executable; `action.yml`, `pack.yml`, `Dockerfile`; `skeleton/` with `pyproject.toml`, `requirements.in`, `requirements.txt`, `src/__PKG__/{__init__,__main__}.py`, `tests/__PKG__/test___PKG___smoke.py`) and `tests/governance/test_stack_packs.sh`. Add `build>=1.2,<2`, `setuptools>=69`, `wheel>=0.43` to `scripts/requirements.txt`.

**Interfaces:**
- `init.sh scaffold` — cwd = target, env `SPECFLOW_NAME`, `SPECFLOW_PKG`; copies `skeleton/`, substituting `__PKG__` (paths, contents) and `__NAME__`; never overwrites (exit 1); other subcommands exit 2.
- `gates.sh` — `python3 -m ruff check src tests`, `python3 -m black --check src tests` (pytest stays in gates §1). `security.sh` — prints `security floor lands in P4`, exits 0.
- `release.sh` — the `release-stack.sh.template` contract on cwd: needs `VERSION`, `DIST_DIR`; fails unless `VERSION` = `[project].version` (`tomllib`); `python3 -m build --no-isolation --sdist --wheel --outdir "$DIST_DIR"` (offline); writes `manifest.json` `{version, artifacts: [{filename, sha256, size}]}` as `verify-release.sh` reads it.
- `deploy.sh` — REQ-351 stub: `migrate`, `deploy`, `smoke`, `rollback` print `deploy contract lands in P6 (REQ-351)` to stderr, return 3 (`DRY_RUN=1` only prints). It dispatches only when executed (`${BASH_SOURCE[0]}` = `$0`) with a function name as `$1`; sourced, with or without arguments, it only defines the four functions and returns 0 (this test and REQ-351's `test_deploy_contract.sh` source it). `Dockerfile` — `FROM python:3.12-slim`, installs the `dist/` wheel, runs `python -m __PKG__` (built in P6).
- Pack tokens — `__PKG__` and `__NAME__` appear in `skeleton/`, `Dockerfile` and `deploy.sh` (the image name); `init.sh scaffold` substitutes them in `skeleton/`, and init substitutes them in the `Dockerfile` and `deploy.sh` it installs (Task 6). `gates.sh`, `security.sh`, `release.sh` and `action.yml` carry none.
- `action.yml` — composite: setup-python `python_version`; `pip install -r scripts/requirements.txt`; `--require-hashes -r requirements.txt` if present; `ci.yml:23-29`'s Dafny step if `hashFiles('verification/**/*.dfy') != ''`. Floor tools and `ci.yml` wiring: P4 (REQ-330).
- `pack.yml` — `stack: python`, `guided_choice: 2`, `guided_label: a web service or command-line tool`, `guided_rationale`, `testing: pytest (tests/), ruff + black (lint and format), governance tests (tests/governance/)`, `source_roots: [src]`, `test_globs: [tests/**/test_*.py]`, `coverage_exclude: []`, `lockfile: requirements.txt`, `python_version: "3.12"`, `<tool>_version` = lockfile pins, `prereqs: [build]` with `check_`, `install_macos_`, `install_linux_build`.
- Skeleton — `pyproject.toml` (name `__PKG__`, `0.1.0`, `>=3.12`, no runtime deps, `setuptools>=69` backend, packages from `src` including `__PKG__*`, pytest `pythonpath = ["."]`); `requirements.in` (the six tools within `scripts/requirements.txt`'s ranges) and its lock, generated in `stacks/python/skeleton/` by `uv pip compile --generate-hashes --universal --python-version 3.12 requirements.in -o requirements.txt` (pip-compile-format output, REQ-304; `--universal` resolves markers for macOS and ubuntu alike; uv emits `setuptools`, which plain `pip-compile` drops without `--allow-unsafe`; `uv` is a maintainer tool, not an instance prerequisite); `__main__.py` `main() -> int`, 0 at once under `SPECFLOW_SMOKE=1` (REQ-390), else a greeting; the smoke test imports `from src.__PKG__.__main__ import main` (the demo's convention) and covers both branches.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/governance/test_stack_packs.sh <<'EOS'
#!/usr/bin/env bash
# REQ-303: every pack has every required file. REQ-304 (python in P1a): the
# skeleton passes lint, format, tests with no hand edits. REQ-305: release.sh
# honours VERSION/DIST_DIR and writes manifest.json. Template source only.
# Covers: REQ-303, REQ-304, REQ-305
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — init removed stacks/"; exit 0; }
CFG="$ROOT/scripts/lib/specflow/config.py"
val() { python3 "$CFG" --file "$1" "${@:2}" 2>/dev/null || true; }
shopt -s nullglob
ck "stacks/python present" test -d stacks/python
for d in stacks/*/; do
  s=$(basename "$d"); req="init.sh gates.sh security.sh release.sh action.yml pack.yml"
  if [[ $s == python ]]; then req="$req Dockerfile deploy.sh"; else req="$req store-checklist.md"; fi
  for f in $req; do ck "$s: $f present" test -f "$d$f"; done
  for f in "$d"*.sh; do ck "$f executable" test -x "$f"; ck "$f parses" bash -n "$f"; done
  for k in stack source_roots test_globs coverage_exclude guided_choice guided_label guided_rationale testing prereqs; do
    ck "$s: pack.yml declares $k" python3 "$CFG" --file "${d}pack.yml" get "$k"
  done
  ck "$s: pack.yml stack matches the directory" [ "$(val "${d}pack.yml" get stack)" = "$s" ]
  for t in $(val "${d}pack.yml" getlist prereqs); do
    for k in check install_macos install_linux; do ck "$s: ${k}_$t" python3 "$CFG" --file "${d}pack.yml" get "${k}_$t"; done
  done
  ck "$s: composite action" grep -qE '^[[:space:]]*using:[[:space:]]*"?composite"?' "${d}action.yml"
  ck "$s: security.sh exits 0" bash "${d}security.sh"
  ck "$s: security.sh is the P4 stub" grep -q 'security floor lands in P4' <<<"$(bash "${d}security.sh" 2>&1 || true)"
done
P="$ROOT/stacks/python"
for t in ruff black pytest build setuptools wheel; do
  pin=$(grep -iE "^$t==" "$P/skeleton/requirements.txt" 2>/dev/null | head -1 | sed -E 's/^[^=]+==([^ ;\\]+).*/\1/' || true)
  ck "$t pin '$pin' equals pack.yml" [ -n "$pin" -a "$(val "$P/pack.yml" get "${t}_version")" = "$pin" ]
done
ck "lockfile is hash-pinned" grep -q -- '--hash=sha256:' "$P/skeleton/requirements.txt"
ck "lockfile made by uv pip compile --universal" grep -qE 'uv pip compile .*--universal' "$P/skeleton/requirements.txt"
ck "sourcing deploy.sh with no arguments returns 0" env DRY_RUN=1 bash -c "source '$P/deploy.sh'"
fns=$(DRY_RUN=1 bash -c "source '$P/deploy.sh' && declare -F" 2>/dev/null || true)
for fn in migrate deploy smoke rollback; do ck "deploy.sh defines $fn" grep -q " $fn\$" <<<"$fns"; done
ck "Dockerfile FROM python:" grep -q '^FROM python:' "$P/Dockerfile"
ck "Dockerfile has the __PKG__ token" grep -q __PKG__ "$P/Dockerfile"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; cd "$W"
ck "scaffold runs" env SPECFLOW_NAME="Acme Tools" SPECFLOW_PKG=acme_tools bash "$P/init.sh" scaffold
for f in pyproject.toml requirements.in requirements.txt src/acme_tools/__main__.py tests/acme_tools/test_acme_tools_smoke.py; do ck "skeleton has $f" test -f "$f"; done
ck "tokens substituted" no grep -rqE '__PKG__|__NAME__' .
ck "skeleton passes ruff" python3 -m ruff check src tests
ck "skeleton passes black" python3 -m black --check -q src tests
ck "skeleton test passes" python3 -m pytest -q tests
ck "SPECFLOW_SMOKE=1 start-up exits 0" env SPECFLOW_SMOKE=1 python3 -m src.acme_tools
ck "release.sh runs (build tools: pip install -r scripts/requirements.txt)" env VERSION=0.1.0 DIST_DIR="$W/dist" bash "$P/release.sh"
ck "manifest verifies: sdist + wheel, sha256, size" python3 - "$W/dist" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
names = [e["filename"] for e in m["artifacts"]]
assert m["version"] == "0.1.0" and any(n.endswith(".whl") for n in names) and any(n.endswith(".tar.gz") for n in names), m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
ck "release.sh refuses a VERSION unlike pyproject.toml" no env VERSION=9.9.9 DIST_DIR="$W/d2" bash "$P/release.sh"
finish test_stack_packs
EOS
chmod +x tests/governance/test_stack_packs.sh
```

- [ ] **Step 2: Run it — expect** `FAIL: stacks/python present`, no per-pack lines, every python check FAIL except the vacuous `tokens substituted` and `refuses a VERSION`. Exit 1.

- [ ] **Step 3: Implement (intent)** — pack and skeleton per Interfaces; hashed lockfile from the Interfaces' `uv pip compile` command (uv 0.11 here), inside `scripts/requirements.txt`'s ranges (ruff `>=0.15,<0.16`, black `>=25,<26`), pins copied into `pack.yml`; the three ranges added to `scripts/requirements.txt` with a comment naming the release hook.

- [ ] **Step 4: Run** `pip install -r scripts/requirements.txt && bash tests/governance/test_stack_packs.sh && bash scripts/run-quality-gates.sh` — expect all green (template pytest does not collect `stacks/`).

- [ ] **Step 5: Commit** — "feat(stacks): python stack pack with skeleton, gates, release contract and P4/P6 stubs (REQ-303, REQ-304, REQ-305)"

---

### Task 4: Retire the demo release hook and its examples

**Files:** delete `scripts/release-python-wheel.sh` (demo tarball), its `.example`, `scripts/release-node-tarball.sh.example` (`scripts/quality-gates-stack.sh.template` went in Task 1); keep `scripts/release-stack.sh.template`, rewording `:2-4` (packs implement it). Modify `docs/releases/0.0.1-demo-notes.md:36-41` and `test_tooling_hygiene.sh` (append; `# Covers: REQ-307, REQ-305`).

- [ ] **Step 1: Append the failing checks** before `finish`:

```bash
# REQ-305: the demo release hook and its examples are gone.
for p in scripts/release-python-wheel.sh scripts/release-python-wheel.sh.example scripts/release-node-tarball.sh.example; do
  ck "$p removed" no test -e "$p"
done
ck "release contract template kept" test -f scripts/release-stack.sh.template
ck "no reference to release-python-wheel" no grep -rq release-python-wheel README.md CLAUDE.md scripts .claude docs/releases
```

- [ ] **Step 2: Run it — expect** three `removed` FAILs and the reference FAIL (`0.0.1-demo-notes.md:39`). Exit 1.

- [ ] **Step 3: Implement (intent)** — delete the three; reword the contract header; the notes' verify block says the producing hook was retired in v3.2 (REQ-305) and is reproduced from tag `v0.0.1-demo` (script unnamed); table and `jq` comparison stay.

- [ ] **Step 4: Run** `bash tests/governance/test_tooling_hygiene.sh && bash scripts/run-quality-gates.sh` — expect green.

- [ ] **Step 5: Commit** — "chore(release): retire the demo-specific release hook and its examples (REQ-305)"

---

### Task 5: `review-gate.md` — both paths and the lane-to-phase mapping

**Files:** create `tests/governance/test_review_gate_paths.sh`. Modify `.claude/rules/review-gate.md:5-45` (steps speak of the phase or lane PR; `## Phase sequence` and "Out-of-cycle" become `## Paths and branch names` and `## Lane-to-phase mapping`), `:60-71` (back-edge names both forms, six steps), `:73-86` (patch tier on `patch/<slug>`, both paths).

**Interfaces:** `## Paths and branch names` — the path is `.specflow.yml` `path:` (configuration, `art-branch-as-state`); lanes `design/<slug>`, `build/<slug>-N` (one per `## Build N`), `ship/<version>`, back-edge `build/sec-<id>`; regulated `phase/spec-<slug>`, `phase/arch-<slug>`, `phase/plan-<slug>`, `impl/plan-N-<name>`, `phase/validate`, `phase/security`, `phase/release`, back-edge `impl/sec-<id>`; both `patch/<slug>`, `phase/retro-YYYY-MM-DD`; `/next` (P5) derives state from them. `## Lane-to-phase mapping` (lanes | regulated): BRAINSTORM, SPECIFY → design | `phase/spec-`; ARCHITECTURE → design | `phase/arch-`; PLAN, TASKS, ANALYZE → design | `phase/plan-`; IMPLEMENT → build | `impl/plan-N-`; VALIDATE → CI on the build PR | `phase/validate`; SECURITY, RELEASE → ship | `phase/security`, `phase/release`; plus back-edge, patch and retro rows.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/governance/test_review_gate_paths.sh <<'EOS'
#!/usr/bin/env bash
# REQ-308 with ADR-003's consequence (REQ-343's rule text moved to P1):
# review-gate.md documents both paths' branches and the lane-to-phase mapping.
# Covers: REQ-308
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
R=.claude/rules/review-gate.md
for b in 'design/<slug>' 'build/<slug>-N' 'build/sec-<id>' 'ship/<version>' 'patch/<slug>' 'phase/spec-<slug>' 'phase/arch-<slug>' \
         'phase/plan-<slug>' 'impl/plan-N-<name>' 'impl/sec-<id>' 'phase/validate' 'phase/security' 'phase/release' 'phase/retro-YYYY-MM-DD'; do
  ck "names $b" grep -qF "$b" "$R"
done
map=$(awk '/^## Lane-to-phase mapping/{f=1; next} /^## /{f=0} f' "$R")
for ph in BRAINSTORM SPECIFY ARCHITECTURE PLAN TASKS ANALYZE IMPLEMENT VALIDATE SECURITY RELEASE; do ck "mapping places $ph" grep -q "$ph" <<<"$map"; done
ck "no fixed-name phase/spec|arch|plan (ADR-003)" no grep -qE '(^|[^-/a-z])phase/(spec|arch|plan)([^-]|$)' "$R"
ck "mapping precedes the back-edge protocol" awk '/^## Lane-to-phase mapping/{m=NR} /^## Back-edge protocol/{b=NR} END{exit !(m && b && m < b)}' "$R"
ck "patch tier names patch/<slug>" grep -qF 'patch/<slug>' <<<"$(awk '/^## Patch tier/,/^## Minor exception/' "$R")"
ck "path named as .specflow.yml configuration" grep -q specflow.yml "$R"
finish test_review_gate_paths
EOS
chmod +x tests/governance/test_review_gate_paths.sh
```

- [ ] **Step 2: Run it — expect** `ok:` only for `impl/plan-N-<name>`, `phase/validate`, `phase/security`, `phase/release`, `phase/retro-YYYY-MM-DD`; FAIL for the other nine names, all ten phases, the fixed-name check (`:27-29`), ordering, patch tier, `.specflow.yml`. Exit 1.

- [ ] **Step 3: Rewrite (intent)** — lines 5-20 say "phase or lane PR" (keep the verifier, approval, `run-verifier.sh` and slug text); lines 24-45 become the two sections; back-edge steps 1 and 5 name both branch forms (still six numbered lines, none in the patch tier); gate bullets verbatim.

- [ ] **Step 4: Run** `for t in review_gate_paths review_gate_citations spec_lifecycle plan_template verifier_process; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green (`back-edge has 6 steps`).

- [ ] **Step 5: Commit** — "docs(review-gate): both paths' branch names and the lane-to-phase mapping (REQ-308; ADR-003)"

---

### Task 6: `init-project.sh` — flags, profile-first prompts, pack install, stays on `main`

**Files:** rewrite `scripts/init-project.sh` (node/go/other prompts `:8-47`, `tests/e2e` in `:56`, hook generation `:68-86`, branch `:114-115`, SpecKit next steps `:117-139`). `git rm tests/e2e/.keep` (the template stops shipping `tests/e2e/`; spec Scope "Out"). Create `tests/governance/test_init.sh`. Modify `lib/check.sh`, `CLAUDE.md:16` (a `TESTING` placeholder, PROJECT_NAME's form), `test_template_instantiation.sh` (after `:53-58`), `test_onboarding_surface.sh:74-78` (v3.2).

**Interfaces:**
- `init-project.sh [--name N] [--profile guided|engineer] [--stack python|tauri|flutter] [--path lanes|regulated] [--solo true|false] [--doctor]`; any value flag → non-interactive (defaults; name = directory basename; stdin unread).
- Exit 0; 1 precondition (`.specflow.yml` present, or `.git` off `main` or dirty); 2 usage or invalid value — name outside `^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$`, package clashing with a `src/` dir, absent pack (names `stacks/<stack>/`; tauri/flutter arrive in P1b). Order, all before any write: (a) flag syntax and allowed values (2); (b) preconditions (1); (c) pack presence and package clash (2). A second init, which meets both an existing `.specflow.yml` and a deleted `stacks/`, therefore exits 1. Every refusal prints one stderr line naming its cause: the rejected flag and value; `.specflow.yml` for an existing instance; the current branch and `main` when off `main`; `stacks/<stack>/` for an absent pack.
- Prompts (stderr, ending `]: `): `Profile — guided or engineer? [guided]: `; `Project name [<dir>]: `; guided `What are you building?` with `  (<guided_choice>) <guided_label>` per present pack (a note when Mac desktop / multi-platform packs are absent) and `Choice [<python's>]: `; engineer `Stack (<packs>) [python]: `, `Path — lanes or regulated? [lanes]: `; both `Are you working alone (no second reviewer)? [Y/n]: `. Guided prompts skip the path question and take `lanes`; an explicit `--path` flag is honoured under either profile (`--profile guided --path regulated` is valid); empty or EOF → default.
- Package: lowercased, non-`[a-z0-9]` runs → `_`, trimmed, `app_` before a leading digit.
- Effects: artifact dirs (minus `tests/e2e`, doc-render); `config.py write`; `gates.sh`/`security.sh`/`release.sh` → `scripts/{quality-gates,security,release}-<stack>.sh` (`+x`), `action.yml` → `.github/actions/toolchain/action.yml`, `pack.yml` → `.specflow/pack.yml`, if present `Dockerfile` → `./Dockerfile` and `deploy.sh` → `scripts/deploy-local.sh` (REQ-351's env), both with `__PKG__`/`__NAME__` substituted as `init.sh scaffold` does; `init.sh scaffold`; `IDEA.md` (guided appends `## Stack` + `guided_rationale`); PROJECT_NAME, STACK, TESTING (pack `testing:`) in the `for doc in` loop; delete `stacks/`; `git init -b main` if needed; commit `chore: initialize <name> from SpecFlow v3.2 template (<stack>, <profile>, <path>)`. No branch is created or switched.
- Next steps: lanes — fill `IDEA.md`, `git checkout -b design/<slug>`, `/superpowers:brainstorming`, `/specify`, `/architecture` (if tagged), `/specflow-plan`, `/specflow-tasks`, `/analyze`, PR, `scripts/run-verifier.sh <PR>` in a second terminal, then `build/<slug>-1`, `ship/<version>`; regulated — `phase/spec-<slug>` … `phase/release`. Both name `configure-repo.sh`; `/next` arrives later.
- `check.sh` gains `copy_template DEST` (tracked plus untracked-unignored files on disk, no `.git`) and the git environment.

- [ ] **Step 1: Extend the helper; write the failing tests**

```bash
cat >> tests/governance/lib/check.sh <<'EOS'
copy_template() {  # copy_template DEST — the working tree as on disk, no .git
  mkdir -p "$1"
  (cd "$ROOT" && git ls-files -z --cached --others --exclude-standard \
     | while IFS= read -r -d '' f; do if [[ -e "$f" ]]; then printf '%s\0' "$f"; fi; done \
     | tar -cf - --null -T -) | (cd "$1" && tar -xf -)
}
export GIT_AUTHOR_NAME=specflow-test GIT_AUTHOR_EMAIL=specflow-test@example.invalid
export GIT_COMMITTER_NAME=specflow-test GIT_COMMITTER_EMAIL=specflow-test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
EOS
cat > tests/governance/test_init.sh <<'EOS'
#!/usr/bin/env bash
# REQ-300/301/303/308: init on throwaway copies — flags, Enter at every
# prompt, engineer prompts, rejected values, an existing clone. Template only.
# Covers: REQ-300, REQ-301, REQ-303, REQ-308
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — init runs in the template source"; exit 0; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
val() { python3 "$ROOT/scripts/lib/specflow/config.py" --root "$1" get "$2" 2>/dev/null || true; }
has() { local d="$1"; shift; for kv in "$@"; do ck "$(basename "$d"): $kv" [ "$(val "$d" "${kv%%=*}")" = "${kv#*=}" ]; done; }
ph() { printf '%s%s%s%s%s' '{' '{' "$1" '}' '}'; }
init() { local d="$1"; shift; (cd "$d" && bash scripts/init-project.sh "$@" </dev/null 2>&1); }
rc_of() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
enter() { (cd "$1" && printf "$2" | bash scripts/init-project.sh 2>&1) || true; }
git_base() { git -C "$1" init -q -b main && git -C "$1" add -A && git -C "$1" commit -qm base; }

D="$WORK/flags"; copy_template "$D"   # 1. flags: engineer / regulated / team
rc=0; out=$(init "$D" --name "Acme Tools" --profile engineer --stack python --path regulated --solo false) || rc=$?
ck "flags: exit 0" [ "$rc" = 0 ]
has "$D" profile=engineer path=regulated stack=python solo=false coverage_min=80 signing=none
for f in quality-gates-python security-python release-python deploy-local; do ck "scripts/$f.sh executable" test -x "$D/scripts/$f.sh"; done
for f in .github/actions/toolchain/action.yml .specflow/pack.yml Dockerfile pyproject.toml requirements.txt src/acme_tools/__main__.py tests/acme_tools/test_acme_tools_smoke.py; do
  ck "$f present" test -f "$D/$f"
done
ck "Dockerfile names the package" grep -q acme_tools "$D/Dockerfile"
for p in stacks .stack tests/e2e .claude/skills/doc-render; do ck "$p absent" no test -e "$D/$p"; done
ck "template ships no tests/e2e" no test -e "$ROOT/tests/e2e"
ck "installed pack files carry no tokens" no grep -qE '__PKG__|__NAME__' "$D/Dockerfile" "$D/scripts/deploy-local.sh"
for p in PROJECT_NAME STACK TESTING; do ck "$p substituted" no grep -qF "$(ph $p)" "$D/CLAUDE.md" "$D/README.md"; done
ck "Testing line from the pack" grep -q '^- Testing: pytest' "$D/CLAUDE.md"
ck "name in CLAUDE.md" grep -q 'Acme Tools' "$D/CLAUDE.md"; ck "name in README.md" grep -q 'Acme Tools' "$D/README.md"
ck ".git created" test -e "$D/.git"
ck "on main, no other branch" [ "$(git -C "$D" branch --list 2>/dev/null | tr -d ' \n')" = "*main" ]
ck "initialization committed" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ]
ck "regulated next steps name phase/spec-<slug>" grep -qF 'phase/spec-<slug>' <<<"$out"
ck "next steps free of SpecKit" no grep -qi speckit <<<"$out"
ck "init-project.sh free of SpecKit (REQ-302)" no grep -qiE 'speckit|spec-kit' "$ROOT/scripts/init-project.sh"
ck "second init refused (exit 1)" [ "$(rc_of init "$D" --name Again)" = 1 ]
ck "second init refusal names .specflow.yml" grep -qF .specflow.yml <<<"$(init "$D" --name Again || true)"

D="$WORK/enter"; copy_template "$D"; out=$(enter "$D" '\n\n\n\n\n\n\n\n')   # 2. Enter everywhere
has "$D" profile=guided path=lanes stack=python solo=true
ck "profile asked first" python3 -c 'import sys; s = sys.stdin.read(); p = s.find("Profile"); sys.exit(not 0 <= p < s.find("Project name"))' <<<"$out"
ck "guided asks what you are building" grep -q 'What are you building?' <<<"$out"
[[ -d stacks/tauri ]] || ck "no Mac desktop option without its pack" no grep -qE '\([0-9]\) a Mac desktop app' <<<"$out"
[[ -d stacks/flutter ]] || ck "no multi-platform option without its pack" no grep -qE '\([0-9]\) a multi-platform app' <<<"$out"
ck "IDEA.md records the stack and rationale" grep -q '^## Stack' "$D/IDEA.md"
ck "lanes next steps name design/<slug>" grep -qF 'design/<slug>' <<<"$out"

D="$WORK/eng"; copy_template "$D"; out=$(enter "$D" 'engineer\n\n\n\n\n\n\n')   # 3. engineer prompts
has "$D" profile=engineer stack=python path=lanes
ck "engineer asked for the stack" grep -q 'Stack (' <<<"$out"
ck "engineer not asked what they build" no grep -q 'What are you building?' <<<"$out"

D="$WORK/bad"; copy_template "$D"   # 4. rejected values: exit 2, nothing written
for a in "--stack go" "--stack other" "--profile boss" "--path waterfall" "--solo maybe" "--bogus"; do
  ck "rejects $a (exit 2)" [ "$(rc_of init "$D" --name X $a)" = 2 ]
done
ck "rejects an unsafe name (exit 2)" [ "$(rc_of init "$D" --name 'Bad"Name')" = 2 ]
ck "refusal names the rejected value" grep -q boss <<<"$(init "$D" --name X --profile boss || true)"
for s in tauri flutter; do
  [[ -d "$D/stacks/$s" ]] && continue
  ck "--stack $s refused (exit 2)" [ "$(rc_of init "$D" --name X --stack $s)" = 2 ]
  ck "--stack $s refusal names stacks/$s" grep -qF "stacks/$s" <<<"$(init "$D" --name X --stack $s || true)"
done
ck "rejected runs wrote nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" ]

D="$WORK/clone"; copy_template "$D"; git_base "$D"   # 5. existing clone
ck "clone: init exits 0" [ "$(rc_of init "$D" --name Clone --profile engineer)" = 0 ]
ck "clone: one commit on main" [ "$(git -C "$D" branch --show-current):$(git -C "$D" rev-list --count HEAD)" = main:2 ]
D="$WORK/off"; copy_template "$D"; git_base "$D"; git -C "$D" checkout -qb feature
ck "refuses off main (exit 1)" [ "$(rc_of init "$D" --name F)" = 1 ]
out=$(init "$D" --name F || true)
ck "off-main refusal names the branch" grep -q feature <<<"$out"
ck "off-main refusal names main" grep -q main <<<"$out"
ck "off-main run wrote nothing" no test -e "$D/.specflow.yml"

D="$WORK/gr"; copy_template "$D"   # 6. guided with an explicit regulated path
ck "--profile guided --path regulated accepted" [ "$(rc_of init "$D" --name GR --profile guided --path regulated)" = 0 ]
has "$D" profile=guided path=regulated
finish test_init
EOS
chmod +x tests/governance/test_init.sh
```

In `tests/governance/test_template_instantiation.sh`, template-source branch, after `:53-58`:

```bash
  if grep -qF "$(printf '%s%s%s%s%s' '{' '{' TESTING '}' '}')" CLAUDE.md && grep -qE 's/\{\{TESTING\}\}/' scripts/init-project.sh; then
    pass "CLAUDE.md carries the TESTING placeholder and init substitutes it"
  else
    fail "CLAUDE.md Testing line is not substituted by init (REQ-308)"
  fi
```

- [ ] **Step 2: Run them — expect** the old init to exit 1 at its first `read -rp` on every `</dev/null` run (EOF under `set -e`), writing nothing (confirmed on a scratch copy at `b7f959b`). So case 1 fails from `flags: exit 0` on, except `second init refused (exit 1)`, which passes for the wrong reason while its `.specflow.yml` check fails; case 4's exit-2 and refusal-text checks fail (exit 1) and `rejected runs wrote nothing` passes vacuously; in case 5 `clone: init exits 0` and both refusal-text checks fail, while `refuses off main (exit 1)` and `off-main run wrote nothing` pass vacuously; case 6 fails. The piped cases 2 and 3 run the old flow (name from the first line, `other` in `.stack`, `phase/spec` checked out, `/speckit.specify` printed): no `Profile` prompt, and their `has` checks fail. The template `tests/e2e`, init-source SpecKit and TESTING checks fail. Exit 1.

- [ ] **Step 3: Implement (intent)** — rewrite init per Interfaces (parse, early `--doctor` branch for Task 7, validate, apply); banner v3.2; add the `CLAUDE.md:16` placeholder; `test_onboarding_surface.sh:74-78` asserts `v3\.2`.

- [ ] **Step 4: Run** `for t in init template_instantiation onboarding_surface config; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green, `PASS tests/governance/test_init.sh`.

- [ ] **Step 5: Commit** — "feat(init): non-interactive flags, profile-first prompts, pack install, stays on main (REQ-300, REQ-301, REQ-303, REQ-308)"

---

### Task 7: `init-project.sh --doctor`

**Files:** modify `scripts/init-project.sh`; create `tests/governance/test_init_doctor.sh`.

**Interfaces:** `--doctor [--stack S]` writes nothing; exit 0 all present, 1 any missing, 2 bad flag. Stack: flag, else config, else python; pack metadata from `stacks/` or `.specflow/pack.yml`. Checks: `git`, `gh`, `jq`, `python3` 3.12+, `claude`, `python3 -m pytest|ruff|black` (install `pip install -r scripts/requirements.txt`), `dafny` only if a `.dfy` exists, then pack `prereqs`. Lines `ok <tool> (<version>)` or `MISSING <tool>: <install command>` (Darwin brew, Linux apt, else both), then `doctor: N missing`. macOS / Ubuntu: git `xcode-select --install` / `apt-get install -y git`; gh, jq `brew install X` / `apt-get install -y X`; python3 `brew install python@3.12` / `apt-get install -y python3.12`; claude `npm install -g @anthropic-ai/claude-code`; dafny `brew install dafny` / `verification/README.md`'s zip steps (apt lines prefixed `sudo`).

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/governance/test_init_doctor.sh <<'EOS'
#!/usr/bin/env bash
# REQ-300 (--doctor) / REQ-308: --doctor names each missing prerequisite with
# its install command, changes nothing, exits 1 if any is missing; Dafny only
# while proofs exist.
# Covers: REQ-300, REQ-308
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — doctor fixtures run in the template source"; exit 0; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
D="$WORK/t"; copy_template "$D"; BIN="$WORK/bin"; mkdir -p "$BIN"   # no gh, claude, dafny
for t in bash sh env python3 git sed awk grep tr cat dirname basename uname mkdir rm cp mv ls head tail find sort wc jq xargs; do
  p=$(command -v "$t" 2>/dev/null || true); if [[ "$p" == /* ]]; then ln -sf "$p" "$BIN/$t"; fi
done
doctor() { (cd "$1" && PATH="$BIN" bash scripts/init-project.sh --doctor --stack python </dev/null 2>&1); }
rc=0; out=$(doctor "$D") || rc=$?
ck "doctor exits 1 when prerequisites are missing" [ "$rc" = 1 ]
for t in gh claude; do ck "MISSING $t: <install command>" grep -qE "^MISSING $t: .+" <<<"$out"; done
ck "git reported present" grep -qE '^ok +git' <<<"$out"
if find "$D/verification" -name '*.dfy' | grep -q .; then ck "dafny required while proofs exist" grep -qE '^MISSING dafny: .+' <<<"$out"; fi
find "$D/verification" -name '*.dfy' -delete
ck "dafny not demanded without proofs" no grep -q dafny <<<"$(doctor "$D" || true)"
ck "doctor changed nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" -a -d "$D/stacks" ]
D="$WORK/inst"; copy_template "$D"
ck "instance init" bash -c "cd '$D' && bash scripts/init-project.sh --name Inst --profile engineer </dev/null"
out=$(cd "$D" && bash scripts/init-project.sh --doctor </dev/null 2>&1 || true)
ck "doctor in an instance reports git" grep -qE '^ok +git' <<<"$out"
ck "doctor in an instance needs no stacks/" no grep -q 'stacks/' <<<"$out"
finish test_init_doctor
EOS
chmod +x tests/governance/test_init_doctor.sh
```

- [ ] **Step 2: Run it — expect** Task 6's init rejects `--doctor` (exit 2): exit-code, `MISSING`, `ok git` and instance-doctor checks FAIL; dafny-absent and changed-nothing pass vacuously. Exit 1.

- [ ] **Step 3: Implement (intent)** — the `--doctor` branch per Interfaces, before any write; checks capture output and never install.

- [ ] **Step 4: Run** `bash tests/governance/test_init_doctor.sh && bash tests/governance/test_init.sh && bash scripts/run-quality-gates.sh` — expect green.

- [ ] **Step 5: Commit** — "feat(init): --doctor prints the install command for each missing prerequisite (REQ-300, REQ-308)"

---

### Task 8: Example-independent tests; one example manifest

**Files:** create `scripts/lib/specflow/examples.py`, `tests/governance/test_examples.sh`; `git mv verification/example.dfy templates/example.dfy`. Modify `verification/README.md:35,49`, `src/contracts/README.md:17`, `CLAUDE.md:59-70`, and the demo-dependent `test_traceability.sh:37-42`, `test_spec_lifecycle.sh:16-35`, `test_plan_template.sh:7,16,33,47-49`.

**Interfaces:**
- Manifest: `### <name> (stack: <stack>)` subsections under `## Canonical Example`; backticked tokens with `/` are paths, one per token, no brace expansion. `### demo_greeting (stack: python)` spells out every item of `CLAUDE.md:63-70`; one sentence says init and `test_examples.sh` read this list (REQ-306). P7 adds REQ-391's.
- `examples.py`: `parse(text) -> {name: (stack, [paths])}`, `strip(text, name) -> str`; CLI `[--root DIR] names` (`<name> <stack>` lines), `list NAME`, `strip NAME` (rewrites `DIR/CLAUDE.md`); unknown name exits 2.
- `test_traceability.sh` check 3 → interim REQ-323 check (replaced by P3's `check-covers.sh`): each line under `tests/`, excluding `tests/governance/`, that starts `#` or `//` then `Covers:` cites only REQ ids some `docs/specs/*.md` defines; none at all passes. Governance tests are excluded because they are the factory's own and cite the factory spec, which an instance may delete (the emptied-docs case of `test_examples.sh` does exactly that); P3's `check-covers.sh` covers them in the REQ-323 direction.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/governance/test_examples.sh <<'EOS'
#!/usr/bin/env bash
# REQ-306: governance tests are example-independent; examples are listed in
# CLAUDE.md "Canonical Example" (examples.py, shared with init); the
# placeholder proof lives in templates/.
# Covers: REQ-306
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
EXPY="$ROOT/scripts/lib/specflow/examples.py"
ck "example.dfy left verification/" no test -e verification/example.dfy
ck "example.dfy lives in templates/" test -f templates/example.dfy
ck "docs point at templates/example.dfy" no grep -q verification/example.dfy verification/README.md src/contracts/README.md
instance && { echo "SKIP: remaining cases run in the template source"; finish test_examples; exit 0; }
names=$(python3 "$EXPY" --root "$ROOT" names 2>/dev/null || true)
ck "manifest lists demo_greeting (stack: python)" grep -qx 'demo_greeting python' <<<"$names"
count=0
while read -r n s; do
  [[ -z "$n" ]] && continue
  while IFS= read -r p; do count=$((count + 1)); ck "manifest path exists: $p" test -e "$p"; done < <(python3 "$EXPY" --root "$ROOT" list "$n")
done <<<"$names"
ck "manifest lists paths" [ "$count" -gt 0 ]
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
D="$WORK/stripped"; copy_template "$D"
while read -r n s; do
  [[ -z "$n" ]] && continue
  (cd "$D" && python3 scripts/lib/specflow/examples.py list "$n" | while IFS= read -r p; do rm -rf "$p"; done \
     && python3 scripts/lib/specflow/examples.py strip "$n")
done <<<"$names"
ck "demo removed" no test -e "$D/src/demo_greeting"
ck "demo manifest entry stripped" no grep -q '^### demo_greeting' "$D/CLAUDE.md"
for t in spec_lifecycle plan_template traceability analyze_adr_plan_linkage; do
  ck "test_$t passes with every example removed" bash -c "cd '$D' && bash tests/governance/test_$t.sh"
done
rm -f "$D"/docs/specs/*.md "$D"/docs/plans/*.md
for t in spec_lifecycle plan_template traceability; do
  ck "test_$t passes with empty docs/specs and docs/plans" bash -c "cd '$D' && bash tests/governance/test_$t.sh"
done
finish test_examples
EOS
chmod +x tests/governance/test_examples.sh
```

- [ ] **Step 2: Run it — expect** the `example.dfy`, manifest and `demo removed` checks to FAIL, and with the docs emptied `test_spec_lifecycle` and `test_plan_template` to FAIL on unmatched globs. Exit 1. (`test_traceability.sh:37-42` fails once strip works: confirmed by a dry run at `b7f959b`.)

- [ ] **Step 3: Implement (intent)** — `examples.py` and manifest per Interfaces; update both READMEs; `test_traceability.sh:37-42` becomes the interim check; `test_spec_lifecycle.sh` and `test_plan_template.sh` use `shopt -s nullglob`, pass an empty `docs/specs/` and a missing demo plan as valid (REQ-306), and never expand an empty array.

- [ ] **Step 4: Run** `for t in examples traceability spec_lifecycle plan_template; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green, `PASS dafny` (demo proof remains).

- [ ] **Step 5: Commit** — "test(examples): governance tests example-independent; example manifest in CLAUDE.md; example.dfy to templates/ (REQ-306)"

---

### Task 9: Instances drop other stacks' examples

**Files:** modify `scripts/init-project.sh` (examples step after scaffold, before `stacks/` deletion and commit), `tests/governance/test_examples.sh` (case 4).

**Interfaces:** for each `<name> <stack>` from `examples.py names` whose stack differs from the chosen one, init removes every listed path and strips the subsection. Python keeps the demo; tauri drops it (and from P7 keeps the habit tracker).

- [ ] **Step 1: Append the failing case** before `finish`:

```bash
# 4. Other stacks' examples are dropped; a stub tauri pack (no-op scaffold) stands in for P1b's.
D="$WORK/other"; copy_template "$D"; rm -rf "$D/stacks/tauri"; mkdir -p "$D/stacks/tauri"
cp "$D"/stacks/python/{gates.sh,security.sh,release.sh,action.yml} "$D/stacks/tauri/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D/stacks/tauri/init.sh"; chmod +x "$D/stacks/tauri/init.sh"; echo '# stub' > "$D/stacks/tauri/store-checklist.md"
printf 'stack: tauri\nguided_choice: 1\nguided_label: a Mac desktop app\nguided_rationale: stub\ntesting: stub\nsource_roots: [src]\ntest_globs: [src/**/*.test.ts]\ncoverage_exclude: []\nprereqs: []\n' > "$D/stacks/tauri/pack.yml"
ck "init --stack tauri (stub pack) exits 0" bash -c "cd '$D' && bash scripts/init-project.sh --name Habit --stack tauri </dev/null"
while IFS= read -r p; do ck "tauri instance drops $p" no test -e "$D/$p"; done < <(python3 "$EXPY" --root "$ROOT" list demo_greeting)
ck "tauri CLAUDE.md drops demo_greeting" no grep -q '^### demo_greeting' "$D/CLAUDE.md"
D="$WORK/py"; copy_template "$D"
ck "python init exits 0" bash -c "cd '$D' && bash scripts/init-project.sh --name Py </dev/null"
ck "python instance keeps its example" test -d "$D/src/demo_greeting"
ck "python CLAUDE.md keeps demo_greeting" grep -q '^### demo_greeting' "$D/CLAUDE.md"
```

- [ ] **Step 2: Run it — expect** cases 1–3 `ok:`; case 4 init exits 0 but every `drops` check FAILs; the python checks pass. Exit 1.

- [ ] **Step 3: Implement (intent)** — the examples step per Interfaces via `python3 scripts/lib/specflow/examples.py`.

- [ ] **Step 4: Run** `bash tests/governance/test_examples.sh && bash tests/governance/test_init.sh && bash scripts/run-quality-gates.sh` — expect green.

- [ ] **Step 5: Commit** — "feat(init): instances drop other stacks' examples (REQ-306)"

---

### Task 10: README, CLAUDE.md and glossary for both profiles and both paths

**Files:** rewrite `README.md` (`:5-83`, SpecKit at `:82`) and `test_onboarding_surface.sh`; modify `CLAUDE.md:3,21-38,40-57` (v3.1, `/speckit.*`, map); create `docs/GLOSSARY.md`.

**Interfaces:** README sections `## Who this is for`, `## Quick Start`, `## Prerequisites` (`### Python`), and a workflow section; the title keeps PROJECT_NAME. Glossary: 20+ `### <Term>` entries.

- [ ] **Step 1: Rewrite the test**

```bash
cat > tests/governance/test_onboarding_surface.sh <<'EOS'
#!/usr/bin/env bash
# The onboarding surface (README, CLAUDE.md, glossary, init, rules) describes
# the current pipeline for both profiles and both paths; no stale copies
# (2026-06-09 review Theme 3; REQ-308); README and CLAUDE.md drop SpecKit (REQ-302).
# Covers: REQ-308, REQ-302
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
section() { awk -v h="$2" '$0 ~ "^## " h {f=1; next} /^## /{f=0} f' "$1"; }
for ph in BRAINSTORM SPECIFY ARCHITECTURE PLAN TASKS ANALYZE IMPLEMENT VALIDATE SECURITY RELEASE; do ck "README names $ph" grep -q "$ph" README.md; done
for s in init-project.sh run-quality-gates.sh run-verifier.sh analyze-adr-plan-linkage.sh; do ck "README mentions $s" grep -q "$s" README.md; done
ck "no stale superpowers:brainstorm" no grep -rqE 'superpowers:brainstorm([^i]|$)' README.md CLAUDE.md scripts/init-project.sh templates .claude/commands
ck "no specflow-scaffold copies" [ ! -e specflow-scaffold -a ! -e specflow-scaffold.zip ]
ck "no root rule duplicates" [ ! -e review-gate.md -a ! -e tdd.md ]
ck "tdd.md cites art-test-first" grep -q art-test-first .claude/rules/tdd.md
for d in docs/adr docs/architecture docs/security docs/releases docs/retrospectives tests/governance; do ck "init creates $d" grep -q "$d" scripts/init-project.sh; done
ck "init writes .specflow.yml" grep -q '\.specflow\.yml' scripts/init-project.sh
ck "init is v3.2" grep -q 'v3\.2' scripts/init-project.sh
ck "init no longer v2 or v3.1" no grep -qE 'SpecFlow v2|v3\.1' scripts/init-project.sh
aud=$(section README.md 'Who this is for')
for w in guided engineer 'You get' 'You do not get yet' hosting auto-update signing Windows Linux mobile; do ck "audience names '$w'" grep -qi -- "$w" <<<"$aud"; done
ck "fully tested defined with the security floor" grep -qi 'security floor' <<<"$(grep -i 'fully tested' <<<"$aud" || true)"
ck "Quick Start step 0 runs init" grep -qE '^0\. .*init-project\.sh' <<<"$(section README.md 'Quick Start')"
pre=$(section README.md 'Prerequisites')
ck "prerequisites: ### Python" grep -q '^### Python' <<<"$pre"
for os in macOS Ubuntu; do ck "prerequisites cover $os" grep -q "$os" <<<"$pre"; done
ck "prerequisites give --version checks" grep -q -- '--version' <<<"$pre"
ck "prerequisites give --doctor" grep -q 'init-project.sh --doctor' <<<"$pre"
ck "Dafny only when the project has proofs" grep -qiE 'only (when|if)' <<<"$(grep -i dafny <<<"$pre" || true)"
ck "README links docs/GLOSSARY.md" grep -q docs/GLOSSARY.md README.md
n=$(grep -c '^### ' docs/GLOSSARY.md 2>/dev/null || true); ck "glossary has 20+ terms (${n:-0})" [ "${n:-0}" -ge 20 ]
for f in README.md CLAUDE.md; do
  for b in 'design/<slug>' 'build/<slug>-N' 'build/sec-<id>' 'ship/<version>' 'patch/<slug>' 'phase/spec-<slug>' 'phase/arch-<slug>' 'phase/plan-<slug>' 'impl/plan-N-<name>' 'impl/sec-<id>'; do
    ck "$f names $b" grep -qF "$b" "$f"
  done
done
for c in specify specflow-plan specflow-tasks analyze; do ck "CLAUDE.md names /$c" grep -qE "\`/$c[ \`]" CLAUDE.md; done
ck "README and CLAUDE.md drop SpecKit (REQ-302)" no grep -qiE 'speckit|spec-kit' README.md CLAUDE.md
ck "README states the public-repository trade-off" grep -qi 'public repositor' README.md
finish test_onboarding_surface
EOS
```

- [ ] **Step 2: Run it — expect** phase, script, stale-copy and init checks pass (Tasks 1, 6); audience, Quick Start, prerequisites, glossary, lanes branches, commands, SpecKit (`README.md:3,10,82`, `CLAUDE.md:3,26-30`) and public-repository checks FAIL. Exit 1.

- [ ] **Step 3: Rewrite (intent)**
- `README.md`: `## Who this is for` (founder/guided: Claude proposes, the human confirms plain-English summaries and merges; engineer/engineer: makes the calls), a "You get" / "You do not get yet" table (hosting, auto-update, signing, Windows, Linux, mobile; what later v3.2 plans add), and "In this template, fully tested means automated code tests plus the security floor."; `## Quick Start` from `0. bash scripts/init-project.sh`; `## Prerequisites` → `### Python` → `#### macOS` / `#### Ubuntu` installs (git, gh, jq, Python 3.12, Claude Code, `pip install -r scripts/requirements.txt`, Superpowers) with `--version` checks and `init-project.sh --doctor`; Dafny "only when the project has proofs"; both workflow blocks; the public-repository trade-off (a free private repository cannot block merges); no SpecKit, no renderer; glossary link.
- `CLAUDE.md`: line 3 v3.2 without SpecKit; tables "Lanes path (default)" and "Regulated path" with `/specify` (clarification included), `/specflow-plan` + `/superpowers:writing-plans`, `/specflow-tasks`, `/analyze`; both back-edge forms; the map adds `.specflow.yml`, `.specflow/pack.yml`, `stacks/`, `docs/GLOSSARY.md` and drops `tests/e2e`.
- `docs/GLOSSARY.md`: plain `### ` entries — ADR, Attestation marker, Back-edge, Build lane, Constitution article, Coverage floor, Covers annotation, Dafny proof, Design lane, Disposition, Engineer profile, Fully tested, Governance test, Guided profile, Kernel module, Lane, Lanes path, Manifest, Patch tier, Phase, Quality gates, Regulated path, REQ, Security floor, Ship lane, Solo mode, Stack pack, Verifier.

- [ ] **Step 4: Run** `for t in onboarding_surface template_instantiation tooling_hygiene reviews_use_slugs; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green.

- [ ] **Step 5: Commit** — "docs(onboarding): README audience, prerequisites, both paths; CLAUDE.md tables; glossary (REQ-308)"

---

### Task 11: `/specify`, `/specflow-plan`, `/specflow-tasks`, `/analyze`

**Files:** create `.claude/commands/{specify,specflow-plan,specflow-tasks,analyze}.md`, `tests/governance/test_spec_commands.sh`. Names per REQ-302 as amended on the PLAN PR: Claude Code ships built-in `/plan` and `/tasks`, so those two carry the `specflow-` prefix.

**Interfaces:** frontmatter `name`, `description`, `argument-hint: <slug>` (as `architecture.md:1-5`); each reads `.specflow.yml` `profile` to phrase confirmations plainly for guided users; none mentions SpecKit.
- `/specify <slug>`: reads `constitution.md`, `IDEA.md`, any brainstorm; writes `docs/specs/<date>-<slug>-design.md` from `schemas/spec-template.md`; continues the global REQ sequence; one-line rationale per tag; at most five clarifying questions; runs `bash scripts/verify-doc.sh`; names the next command and branch.
- `/specflow-plan <slug>`: reads spec, ADRs, overview; uses `/superpowers:writing-plans`; writes `docs/plans/<date>-<slug>-plan.md` from `schemas/plan-template.md` (`spec`, `decisions`, `implements:`, `created`; lanes plans use `## Build N:`).
- `/specflow-tasks <slug>`: expands each `## Build N` of `docs/plans/<date>-<slug>-plan.md` into tasks (Files, Interfaces, Steps; failing test first); no new file.
- `/analyze <slug>`: runs `analyze-adr-plan-linkage.sh`, `check-traceability.sh`, `verify-doc.sh`; checks every `implements:` REQ has a task and every spec REQ is claimed or deferred; fixes the plan; prints a PR summary.

- [ ] **Step 0: Names still free?** Settled at plan time: Claude Code 2.1.283's built-in command table (read with `strings` from the installed binary) holds `plan` ("Enable plan mode or view the current session plan") and `tasks` (alias `bashes`), hence the amendment; `specify` and `analyze` were free. Re-check on the executor's build: `strings "$(python3 -c 'import os, shutil; print(os.path.realpath(shutil.which("claude")))')" | grep -oE 'name:"(help|specify|specflow-plan|specflow-tasks|analyze)"' | sort -u` — expect exactly `name:"help"`, the sanity hit showing the table was read. No `name:"help"` (not a native build): record "built-in names unchecked" in the PR body and go on. Any other hit: stop and request a further REQ-302 amendment; never rename silently.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/governance/test_spec_commands.sh <<'EOS'
#!/usr/bin/env bash
# REQ-302: in-repo /specify, /specflow-plan, /specflow-tasks, /analyze write from the repo's
# templates; no onboarding document mentions SpecKit (docs/ is exempt).
# Covers: REQ-302
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=.claude/commands
for c in specify specflow-plan specflow-tasks analyze; do
  ck "/$c: frontmatter opens" [ "$(sed -n 1p "$C/$c.md" 2>/dev/null)" = "---" ]
  for k in "name: $c" 'description: ' 'argument-hint: '; do ck "/$c: $k" grep -q "^$k" "$C/$c.md"; done
done
for pair in 'specify|schemas/spec-template.md' 'specify|docs/specs/<date>-<slug>-design.md' 'specify|verify-doc.sh' \
            'specflow-plan|schemas/plan-template.md' 'specflow-plan|docs/plans/<date>-<slug>-plan.md' 'specflow-plan|implements:' \
            'specflow-plan|superpowers:writing-plans' 'specflow-tasks|docs/plans/<date>-<slug>-plan.md' 'specflow-tasks|## Build' 'analyze|analyze-adr-plan-linkage.sh' 'analyze|check-traceability.sh'; do
  ck "/${pair%%|*} mentions ${pair#*|}" grep -qF -- "${pair#*|}" "$C/${pair%%|*}.md"
done
hits=$(grep -rniE 'speckit|spec-kit' --exclude-dir=worktrees README.md CLAUDE.md .claude scripts templates schemas stacks 2>/dev/null | grep -v '^\.claude/settings\.local\.json' || true)
if [[ -z "$hits" ]]; then pass "no onboarding document references SpecKit"; else fail "SpecKit references remain:"; sed 's/^/    /' <<<"$hits"; fi
finish test_spec_commands
EOS
chmod +x tests/governance/test_spec_commands.sh
```

- [ ] **Step 2: Run it — expect** sixteen frontmatter FAILs, eleven `mentions` FAILs, and `ok: no onboarding document references SpecKit` (its red states were Task 6's init-source check and Task 10's README/CLAUDE.md check). Exit 1.

- [ ] **Step 3: Write the commands (intent)** per Interfaces; each ends by naming the next command and, at a PR boundary, `.claude/rules/review-gate.md`.

- [ ] **Step 4: Run** `bash tests/governance/test_spec_commands.sh && bash tests/governance/test_onboarding_surface.sh && bash scripts/run-quality-gates.sh` — expect green.

- [ ] **Step 5: Commit** — "feat(commands): /specify, /specflow-plan, /specflow-tasks, /analyze write specs and plans from the templates (REQ-302)"

---

### Task 12: The first-run test and its CI job

**Files:** create `tests/governance/test_first_run.sh`; modify `.github/workflows/ci.yml` (a job after `:9-32`), `test_workflow_health.sh` (check 8 after `:76-83`), `README.md` (one line).

**Interfaces:**
- `test_first_run.sh` skips under `SPECFLOW_QG_RUNNING=1`, without `SPECFLOW_FIRST_RUN=1`, and in instances; `FIRST_RUN_CASES` picks cases; gate failures print `FAIL` lines split into floor (P4's tools) and gates.
- CI job `first-run` (`First run (python, <profile>)`, ubuntu, matrix `profile: [guided, engineer]`, `fail-fast: false`): checkout, Python 3.12, `pip install -r scripts/requirements.txt`, `ci.yml:23-29`'s Dafny step, then the test with `SPECFLOW_FIRST_RUN: "1"` and `FIRST_RUN_CASES` from the matrix. Not a required check.

- [ ] **Step 1: Write the tests**

```bash
cat > tests/governance/test_first_run.sh <<'EOS'
#!/usr/bin/env bash
# REQ-360: instantiate the template in a temp dir and run run-quality-gates.sh
# there (exit 0). REQ-305: the installed release hook honours its contract.
# REQ-306: with every example removed the gates stay green. Opt-in with
# SPECFLOW_FIRST_RUN=1; CI runs one case per profile (FIRST_RUN_CASES).
# Covers: REQ-360, REQ-306, REQ-305
set -euo pipefail
[[ "${SPECFLOW_QG_RUNNING:-0}" == 1 ]] && { echo "SKIP: first-run no-op inside the orchestrator (recursion guard)"; exit 0; }
[[ "${SPECFLOW_FIRST_RUN:-0}" == 1 ]] || { echo "SKIP: set SPECFLOW_FIRST_RUN=1 to instantiate and gate a throwaway copy"; exit 0; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — first-run tests the template source"; exit 0; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT; FLOOR='(security|gitleaks|osv|audit)'
gates() {  # gates DIR LABEL
  local rc=0 out; out=$(cd "$1" && env -u SPECFLOW_QG_RUNNING -u SPECFLOW_FIRST_RUN bash scripts/run-quality-gates.sh 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then pass "$2: gates exit 0"; return 0; fi
  fail "$2: gates exit $rc"
  echo "  floor failures:"; grep -E '^FAIL ' <<<"$out" | grep -iE "$FLOOR" | sed 's/^/    /' || true
  echo "  gate failures:"; grep -E '^FAIL ' <<<"$out" | grep -viE "$FLOOR" | sed 's/^/    /' || true
  tail -40 <<<"$out" | sed 's/^/    | /'
}
for c in ${FIRST_RUN_CASES:-guided engineer}; do
  D="$WORK/$c"; copy_template "$D"
  case "$c" in
    guided)
      ck "guided: init with Enter at every prompt" bash -c "cd '$D' && printf '\n\n\n\n\n\n\n\n' | bash scripts/init-project.sh"
      ck "guided: profile recorded" [ "$(python3 "$D/scripts/lib/specflow/config.py" --root "$D" get profile 2>/dev/null)" = guided ]
      gates "$D" "guided/python/lanes/solo"
      ck "guided: release-python.sh runs" bash -c "cd '$D' && VERSION=0.1.0 DIST_DIR='$WORK/dist' bash scripts/release-python.sh"
      ck "guided: dist/manifest.json verifies" python3 - "$WORK/dist" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
assert m["version"] == "0.1.0" and m["artifacts"], m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
      (cd "$D" && python3 scripts/lib/specflow/examples.py names | while read -r n s; do
         python3 scripts/lib/specflow/examples.py list "$n" | while IFS= read -r p; do rm -rf "$p"; done
         python3 scripts/lib/specflow/examples.py strip "$n"; done)
      gates "$D" "guided with every shipped example removed" ;;
    engineer)
      ck "engineer: init with flags" bash -c "cd '$D' && bash scripts/init-project.sh --name Acme --profile engineer --path regulated --solo false </dev/null"
      gates "$D" "engineer/python/regulated/team" ;;
    *) fail "unknown FIRST_RUN_CASES entry '$c'" ;;
  esac
done
finish test_first_run
EOS
chmod +x tests/governance/test_first_run.sh
```

In `tests/governance/test_workflow_health.sh` after check 7:

```bash
# 8. The first-run test runs on every PR for python x both profiles (REQ-360).
if grep -q 'tests/governance/test_first_run.sh' .github/workflows/ci.yml \
   && grep -qE 'SPECFLOW_FIRST_RUN:[[:space:]]*"?1"?' .github/workflows/ci.yml \
   && grep -qE 'profile:[[:space:]]*\[[[:space:]]*guided,[[:space:]]*engineer[[:space:]]*\]' .github/workflows/ci.yml; then
  pass "ci.yml runs test_first_run.sh for guided and engineer"
else
  fail "ci.yml does not run the first-run test for both profiles (REQ-360)"
fi
```

- [ ] **Step 2: Run — expect** check 8 of `test_workflow_health.sh` to fail. `SPECFLOW_FIRST_RUN=1 bash tests/governance/test_first_run.sh` integrates Tasks 1–11 and should pass; if not, extend the owning task's test, fix there, return. Without the variable it skips.

- [ ] **Step 3: Implement (intent)** — the `first-run` job per Interfaces; README line: `SPECFLOW_FIRST_RUN=1 bash tests/governance/test_first_run.sh` builds and gates a throwaway instance locally.

- [ ] **Step 4: Run** `for t in workflow_health template_instantiation onboarding_surface; do bash tests/governance/test_$t.sh; done && bash scripts/run-quality-gates.sh` — expect green and the recursion-guard skip.

- [ ] **Step 5: Commit** — "test(first-run): instantiate and gate python x both profiles; CI job per profile (REQ-360, REQ-306)"

---

### Task 13: Whole-branch verification and PR

- [ ] **Step 1:** `bash scripts/run-quality-gates.sh && SPECFLOW_FIRST_RUN=1 bash tests/governance/test_first_run.sh` — green; note the instance gate time (NFR: 3 minutes).
- [ ] **Step 2:** `verify-doc.sh` on this plan (silent), `analyze-adr-plan-linkage.sh`, `check-traceability.sh`, `test_plan_template.sh` — pass.
- [ ] **Step 3:** `grep -rnE '\.stack([^a-zA-Z_/-]|$)' scripts stacks .github .claude/commands | grep -v specflow`, `grep -rni speckit --exclude-dir=worktrees README.md CLAUDE.md .claude scripts templates schemas`, `git status --porcelain` — no output.
- [ ] **Step 4:** PR body via `--body-file "$(mktemp)"`: what (the partial claims and the plans that relist them), the tier decision (PLAN PR merged first), the Task 11 Step 0 result, gates ticked only if run, attribution footer.
- [ ] **Step 5:** second terminal, outside Claude Code: `scripts/run-verifier.sh <PR#>`.

---

## Deferred by design

- **Open clauses of claimed REQs** — under **Partial claims**, each with the plan that lists the REQ again; init refuses tauri/flutter by name until P1b.
- **Floor-versus-gate reporting** (REQ-360) prints both headings from Task 12 but has nothing to classify until P4. **Dockerfile and deploy behaviour** — P6 (REQ-351, REQ-390).
- **Known consequence, no P1 REQ covers it:** instances inherit the factory's own v3.2 docs (REQ-300–395) and, once P3/P5 add proofs, need Dafny even without the demo; a later plan or P7 should decide whether init removes them.
