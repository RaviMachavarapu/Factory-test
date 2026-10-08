#!/usr/bin/env bash
# REQ-300/301/303/308 (and REQ-312: the instance ci.yml keeps the gates job): init on throwaway copies — flags, Enter at every
# prompt, engineer prompts, rejected values, an existing clone. Template only.
# Covers: REQ-300, REQ-301, REQ-303, REQ-308, REQ-312, REQ-343
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — init runs in the template source"; exit 0; }
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT
val() { python3 "$ROOT/scripts/lib/specflow/config.py" --root "$1" get "$2" 2>/dev/null || true; }
has() { local d="$1"; shift; for kv in "$@"; do ck "$(basename "$d"): $kv" [ "$(val "$d" "${kv%%=*}")" = "${kv#*=}" ]; done; }
ph() { printf '%s%s%s%s%s' '{' '{' "$1" '}' '}'; }
init() { local d="$1"; shift; (cd "$d" && bash scripts/init-project.sh "$@" </dev/null 2>&1); }
ninit() { local d="$1"; shift; (cd "$d" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh "$@" </dev/null 2>&1); }
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
for p in PROJECT_NAME STACK TESTING PROFILE; do ck "$p substituted" no grep -qF "$(ph $p)" "$D/CLAUDE.md" "$D/README.md"; done
ck "Testing line from the pack" grep -q '^- Testing: pytest' "$D/CLAUDE.md"
ck "name in CLAUDE.md" grep -q 'Acme Tools' "$D/CLAUDE.md"; ck "name in README.md" grep -q 'Acme Tools' "$D/README.md"
ck ".git created" test -e "$D/.git"
ck "on main, no other branch" [ "$(git -C "$D" branch --list 2>/dev/null | tr -d ' \n')" = "*main" ]
ck "initialization committed" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ]
# PR #59 verifier run 1, finding 1 (REQ-322, REQ-306): RUBRIC.md ships to every instance, so init resets the factory's
# medium_cap override to the constitution's default of 5 and drops the factory's override record; every other line is
# the template's, in order.
# Covers: REQ-322, REQ-306
RBI="$D/docs/security/RUBRIC.md"
ck "instance RUBRIC.md: medium_cap 5 (the factory's override never ships)" grep -qE '^medium_cap: 5 +# max accepted' "$RBI"
ck "instance RUBRIC.md: no override record and no factory decision" \
  bash -c '! grep -qF "Override record" "$1" && ! grep -qF "maintainer decision for v3.2.0" "$1" && ! grep -qF "kpingali123" "$1"' _ "$RBI"
ck "instance RUBRIC.md: every other line is the template's — only the medium_cap line and the override record differ" \
  python3 - "$ROOT/docs/security/RUBRIC.md" "$RBI" <<'PYR'
import difflib, sys
t = open(sys.argv[1]).read().splitlines(); i = open(sys.argv[2]).read().splitlines()
lo = next(n for n, l in enumerate(t) if l.startswith("Override record"))
hi = next(n for n, l in enumerate(t) if l.startswith("## ") and n > lo)
for tag, a1, a2, b1, b2 in difflib.SequenceMatcher(None, t, i, autojunk=False).get_opcodes():
    if tag == "equal":
        continue
    for n in range(a1, a2):
        assert t[n].startswith("medium_cap:") or lo <= n < hi or (n == lo - 1 and not t[n]), ("removed", t[n])  # difflib may drop the blank line above the record instead
    for n in range(b1, b2):
        assert i[n].startswith("medium_cap: 5 "), ("added", i[n])
assert sum(l.startswith("medium_cap:") for l in i) == 1
PYR
ck "regulated next steps name phase/spec-<slug>" grep -qF 'phase/spec-<slug>' <<<"$out"
ck "regulated next steps start with /next (REQ-343)" grep -qF 'run /next at any time' <<<"$out"
# P5 lows patch (PR #48 verifier run 7, finding 4; REQ-340): the regulated IMPLEMENT branch is impl/plan-N-<plan slug>,
# N the plan's "## Build N" section, as review-gate.md, CLAUDE.md and README say.
# Covers: REQ-340
ck "regulated next steps name impl/plan-N-<plan slug> and the plan's ## Build N section, never impl/plan-N-<name>" \
  bash -c 'grep -qF "impl/plan-N-<plan slug>" <<<"$1" && grep -qF "## Build N" <<<"$1" && ! grep -qF "impl/plan-N-<name>" <<<"$1"' _ "$out"
ck "regulated next steps make phase/arch-<slug> conditional (F-7)" grep -qF 'phase/arch-<slug> (if' <<<"$out"
ck "regulated: no /architecture line before the first run-verifier.sh line (R-3)" python3 -c '
import sys
lines = sys.stdin.read().splitlines()
verifier_i = next((i for i, l in enumerate(lines) if "run-verifier.sh" in l), None)
arch_i = next((i for i, l in enumerate(lines) if "/architecture" in l), None)
sys.exit(0 if verifier_i is not None and arch_i is not None and arch_i > verifier_i else 1)
' <<<"$out"
ck "regulated: the arch step names phase/arch-<slug> and [verifiable] (R-3)" python3 -c '
import sys
lines = sys.stdin.read().splitlines()
sys.exit(0 if any("phase/arch-<slug>" in l and "[verifiable]" in l for l in lines) else 1)
' <<<"$out"
ck "next steps free of SpecKit" no grep -qi speckit <<<"$out"
# PR #54 verifier run 2, finding 3 (REQ-385, REQ-313): the bootstrap by the full ref — a tag named origin/main that
# git fetch auto-follows would otherwise choose the run-verifier.sh piped into bash.
# Covers: REQ-385
ck "regulated next steps print the verifier bootstrap by refs/remotes/origin/main, never the short name" \
  bash -c 'grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR-number>" <<<"$1" && ! grep -qF "git show origin/" <<<"$1"' _ "$out"
ck "regulated next steps carry no interim-window warning — the window closed with P6 Builds 4 and 5 (REQ-384)" \
  bash -c '! grep -qF -- "until P6" <<<"$1" && ! grep -qiF -- "interim" <<<"$1"' _ "$out"
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
ck "lanes next steps start with /next (REQ-343)" grep -qF 'run /next at any time' <<<"$out"
ck "lanes next steps: CI on the build PR is VALIDATE (F-7)" grep -qE 'CI on that PR is VALIDATE|VALIDATE is CI' <<<"$out"
ck "lanes next steps: ship lane lists SECURITY, RELEASE only (F-7)" grep -qF 'ship/<version> for SECURITY, RELEASE.' <<<"$out"
ck "lanes next steps print the verifier bootstrap by refs/remotes/origin/main, never the short name (REQ-385)" \
  bash -c 'grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR-number>" <<<"$1" && ! grep -qF "git show origin/" <<<"$1"' _ "$out"
# PR #54 verifier run 2, finding 2 (REQ-384, REQ-352; art-release-readiness): init's next steps ended with a one-line
# interim-window warning naming README's paragraph until the second of P6 Builds 4 and 5 merged (Build 5, 2026-10-03);
# R35's interim-window edit removed both and flipped these pins.
# Covers: REQ-384
ck "lanes next steps carry no interim-window warning (the window closed with P6 Builds 4 and 5)" \
  bash -c '! grep -qF -- "until P6" <<<"$1" && ! grep -qiF -- "Known interim limitation" <<<"$1"' _ "$out"
ck "…and the instance's README carries no interim paragraph" no grep -qF "Known interim limitation" "$D/README.md"

D="$WORK/eng"; copy_template "$D"; out=$(enter "$D" 'engineer\n\n\n\n\n\n\n')   # 3. engineer prompts
has "$D" profile=engineer stack=python path=lanes
ck "engineer asked for the stack" grep -q 'Stack (' <<<"$out"
ck "engineer not asked what they build" no grep -q 'What are you building?' <<<"$out"

D="$WORK/bad"; copy_template "$D"   # 4. rejected values: exit 2, nothing written
for a in "--stack go" "--stack other" "--profile boss" "--path waterfall" "--solo maybe" "--bogus"; do
  ck "rejects $a (exit 2)" [ "$(rc_of init "$D" --name X $a)" = 2 ]
done
ck "rejects an unsafe name (exit 2)" [ "$(rc_of init "$D" --name 'Bad"Name')" = 2 ]
for n in Calendar Email logging Types class Pytest Src Tests Conftest Unit; do
  ck "rejects stdlib/keyword/pytest/reserved-colliding name '$n' (exit 2)" [ "$(rc_of init "$D" --name "$n")" = 2 ]
done
ck "rejected-name refusal names the cause" grep -qi 'standard-library\|keyword\|pytest' <<<"$(init "$D" --name Calendar || true)"
ck "'Src' refusal names the reserved layout name (W-4)" grep -qi 'src' <<<"$(init "$D" --name Src || true)"
ck "'Tests' refusal names the reserved layout name (W-4)" grep -qi 'tests' <<<"$(init "$D" --name Tests || true)"
ck "'Conftest' refusal names the reserved layout name (W-4)" grep -qi 'conftest' <<<"$(init "$D" --name Conftest || true)"
ck "'Unit' refusal names the existing tests/unit clash (W-4)" grep -qF 'tests/unit' <<<"$(init "$D" --name Unit || true)"
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

D="$WORK/badprofile"; copy_template "$D"   # 7. mistyped interactive answers are validated, not silently coerced
out=$(enter "$D" 'Xyz\nBad\n\n\n\n\n\n')
ck "mistyped profile rejected (nothing written)" no test -e "$D/.specflow.yml"
ck "mistyped-profile refusal names the value" grep -qF 'Xyz' <<<"$out"

D="$WORK/badpath"; copy_template "$D"   # engineer profile, mistyped path prompt
out=$(enter "$D" 'engineer\n\npython\nWaterfall\n\n')
ck "mistyped path rejected (nothing written)" no test -e "$D/.specflow.yml"
ck "mistyped-path refusal names the value" grep -qF 'Waterfall' <<<"$out"

D="$WORK/casepath"; copy_template "$D"   # engineer profile, differently-cased but valid answers
out=$(enter "$D" 'Engineer\n\nPython\nRegulated\n\n')
has "$D" profile=engineer stack=python path=regulated

D="$WORK/badchoice"; copy_template "$D"   # guided, a choice number with no matching pack
out=$(enter "$D" '\n\n99\n\n')
ck "guided choice with no pack rejected (nothing written)" no test -e "$D/.specflow.yml"
ck "bad-guided-choice refusal names the value" grep -qF '99' <<<"$out"

D="$WORK/longname"; copy_template "$D"   # 8. a valid 64-char name is accepted, and its skeleton still gates green
LONG64="$(python3 -c 'print("A" * 64)')"
ck "64-char name accepted (exit 0)" [ "$(rc_of init "$D" --name "$LONG64" --profile engineer)" = 0 ]
OLD_PWD="$(pwd)"; cd "$D"
ck "long-name skeleton passes ruff" python3 -m ruff check src tests
ck "long-name skeleton passes black" python3 -m black --check -q src tests
ck "long-name skeleton test passes" python3 -m pytest -q tests
cd "$OLD_PWD"

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

# 10. Instances inherit no template-only CI (H5); the gates job runs on the pack's runner with its toolchain.
D="$WORK/ci-py"; copy_template "$D"; ck "python instance for CI checks" [ "$(rc_of init "$D" --name Ci --profile engineer)" = 0 ]
C="$D/.github/workflows/ci.yml"
ck "instance ci.yml keeps the gates job and its stable required-check name" grep -qE '^    name: gates$' "$C"
ck "instance ci.yml still runs the gates" grep -q 'run-quality-gates.sh' "$C"
ck "instance ci.yml drops the template-only jobs" no grep -qE 'specflow:template-only|test_first_run\.sh' "$C"
ck "instance has no app-stacks.yml" no test -e "$D/.github/workflows/app-stacks.yml"
# P6 Task 2.4 (REQ-303; P6 R18, R35; F36): init writes the pack's ci_runs_on and python_version into ci.yml's markers, so
# the gates job — where verify-release.sh builds the reproducible subset at PR time — runs on the pack's runner with the
# pack's Python, whatever values the pack holds (Build 4 pins python's). release-build.yml reads the pack's
# python_version itself (packinfo.py) and pins its own runner, ubuntu-24.04: it never reads ci_runs_on. Pack metadata
# reaching the instance's workflow is REQ-303's (fix wave 1: this block cited REQ-384).
# Covers: REQ-303
ck "python instance gates run on the pack's ci_runs_on" \
  bash -c 'r=$(python3 "$1/scripts/lib/specflow/config.py" --file "$1/.specflow/pack.yml" get ci_runs_on); grep -qE "^    runs-on: $r # specflow:runs-on$" "$2"' _ "$D" "$C"
ck "…and set up the pack's python_version at the specflow:python-version marker" \
  bash -c 'v=$(python3 "$1/scripts/lib/specflow/config.py" --file "$1/.specflow/pack.yml" get python_version); [ -n "$v" ] && grep -qF "python-version: \"$v\" # specflow:python-version" "$2"' _ "$D" "$C"
ck "the gates job uses the installed toolchain action" grep -qF 'uses: ./.github/actions/toolchain' "$C"
ck "test_workflow_health passes inside the instance" bash -c "cd '$D' && bash tests/governance/test_workflow_health.sh"
D="$WORK/ci-tauri"; copy_template "$D"
ck "tauri instance (no scaffold) for CI checks" [ "$(rc_of ninit "$D" --name Ci --stack tauri)" = 0 ]
ck "tauri instance gates run on macos-15" grep -qE '^    runs-on: macos-15' "$D/.github/workflows/ci.yml"

# 11. F-4: an old python3 (< 3.12) is a clean precondition failure, not a
# traceback, on the normal (non-doctor) path.
D="$WORK/oldpy"; copy_template "$D"
OLDPY_BIN="$WORK/oldpy-bin"; mkdir -p "$OLDPY_BIN"
for t in bash sh env git sed awk grep tr cut cat dirname basename uname mkdir rm cp mv ls head tail find sort wc jq xargs; do
  p=$(command -v "$t" 2>/dev/null || true); [[ "$p" == /* ]] && ln -sf "$p" "$OLDPY_BIN/$t"
done
printf '%s\n' '#!/bin/sh' 'if [ "$1" = "-c" ]; then echo "3.9.6"; exit 0; fi' 'exit 1' > "$OLDPY_BIN/python3"
chmod +x "$OLDPY_BIN/python3"
rc=0; out=$(cd "$D" && PATH="$OLDPY_BIN" bash scripts/init-project.sh --name OldPy --profile engineer </dev/null 2>&1) || rc=$?
ck "python3 3.9 exits 1 on the normal path (no traceback)" [ "$rc" = 1 ]
ck "old-python refusal names 3.12" grep -qF '3.12' <<<"$out"
ck "old-python refusal names an install command" grep -qE 'brew install python@3\.12|apt-get install -y python3\.12' <<<"$out"
ck "old-python refusal free of a python traceback" no grep -qi 'Traceback (most recent call last)' <<<"$out"
ck "old-python run wrote nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" ]

# 12. F-5/W-8: --help / -h print usage and exit 0; write nothing.
D="$WORK/help"; copy_template "$D"
for h in --help -h; do
  rc=0; out=$(cd "$D" && bash scripts/init-project.sh "$h" </dev/null 2>&1) || rc=$?
  ck "$h exits 0" [ "$rc" = 0 ]
  ck "$h mentions --doctor" grep -q -- '--doctor' <<<"$out"
  ck "$h mentions --stack" grep -q -- '--stack' <<<"$out"
  ck "$h free of 'Engineer profile only' (R-5)" no grep -qF 'Engineer profile only' <<<"$out"
done
ck "--help wrote nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" ]

# 13. F-3/W-3: init is atomic — preflight dry-runs the skeleton's destinations
# and the git identity before any write, and a mid-run failure prints a
# recovery hint. (Note: --name Unit, the review's own repro for the
# preflight case, is now caught earlier at the package step by item 3's
# tests/<pkg> check (exit 2, before preflight ever runs) — so this uses a
# different pre-existing-destination repro: a stray top-level file the
# skeleton would also write, e.g. requirements.txt.)
D="$WORK/preflight-dry-run"; copy_template "$D"
touch "$D/requirements.txt"
rc=0; out=$(init "$D" --name Widget --profile engineer) || rc=$?
ck "13a: a pre-existing skeleton destination exits 1 before any write" [ "$rc" = 1 ]
ck "13a: names the colliding destination" grep -qF 'requirements.txt' <<<"$out"
ck "13a: wrote nothing (no .specflow.yml, no .git)" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" ]

D="$WORK/noident"; copy_template "$D"; git_base "$D"
git -C "$D" config user.useConfigOnly true
rc=0; out=$(cd "$D" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL bash scripts/init-project.sh --name NoIdent --profile engineer </dev/null 2>&1) || rc=$?
ck "13b: an empty git identity exits 1 before any write" [ "$rc" = 1 ]
ck "13b: names git config --global user.email" grep -qF 'user.email' <<<"$out"
ck "13b: wrote nothing (.specflow.yml)" no test -e "$D/.specflow.yml"

# 13b-2 (R-2): user.useConfigOnly plus an explicit GIT_COMMITTER_NAME/EMAIL
# pair (no GIT_AUTHOR_*) resolves GIT_COMMITTER_IDENT but leaves
# GIT_AUTHOR_IDENT unresolved — checking committer identity alone would miss
# this. GIT_CONFIG_GLOBAL points at a scratch file so useConfigOnly doesn't
# need a real writable global config.
D="$WORK/noauthorident"; copy_template "$D"; git_base "$D"
GLOBAL_CFG_ONLY="$WORK/noauthorident-global.cfg"
printf '[user]\n\tuseConfigOnly = true\n' > "$GLOBAL_CFG_ONLY"
rc=0; out=$(cd "$D" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL GIT_CONFIG_GLOBAL="$GLOBAL_CFG_ONLY" GIT_CONFIG_NOSYSTEM=1 bash scripts/init-project.sh --name NoAuthorIdent --profile engineer </dev/null 2>&1) || rc=$?
ck "13b-2: committer-only identity (author unresolved) exits 1 before any write (R-2)" [ "$rc" = 1 ]
ck "13b-2: names git config --global user.name" grep -qF 'user.name' <<<"$out"
ck "13b-2: names git config --global user.email" grep -qF 'user.email' <<<"$out"
ck "13b-2: wrote nothing (.specflow.yml)" no test -e "$D/.specflow.yml"

# 13c (R-10): a mid-run failure after preflight but before the final commit
# must still leave a half-instance with a recovery hint. chmod 555 on a
# destination directory used to simulate this, but root ignores permission
# bits, so this stubs the python pack's own init.sh instead: package/
# preflight pass through to the real pack, scaffold exits 1 partway through
# section 5 (after .specflow.yml and the pack hooks are already written,
# before git init/commit) — root-safe.
D="$WORK/midrun"; copy_template "$D"
mv "$D/stacks/python/init.sh" "$D/stacks/python/init.sh.orig"
cat > "$D/stacks/python/init.sh" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == scaffold ]]; then
  echo "stub: scaffold failed" >&2
  exit 1
fi
exec bash "$HERE/init.sh.orig" "$@"
WRAP
chmod +x "$D/stacks/python/init.sh"
rc=0; out=$(init "$D" --name Midrun --profile engineer) || rc=$?
ck "13c: a mid-run failure (stubbed scaffold) exits non-zero" [ "$rc" != 0 ]
ck "13c: recovery hint printed" grep -qF 'nothing has been committed' <<<"$out"
ck "13c: recovery hint names git reset --hard and git clean" grep -qF 'git reset -q --hard' <<<"$out"
ck "13c: .specflow.yml was written (proves this is a real half-instance)" test -f "$D/.specflow.yml"
ck "13c: mid-run failure left no git commit (no .git yet)" no test -e "$D/.git"

# 13d (R-1): a SIGPIPE (or SIGKILL) can kill bash before the EXIT trap ever
# runs, leaving that same half-instance with no hint at the time. The next
# plain run must still find its way out: since .specflow.yml exists but was
# never committed (untracked, or no .git at all), the "already present"
# refusal appends the same recovery hint the trap would have printed. `head
# -5` mirrors the bug's own repro (unlike `head -1`, which on this host
# starves the writer before it reaches section 5 at all — confirmed
# empirically nothing gets written that early, so it can't reproduce the
# half-instance this precondition exists for).
D="$WORK/sigpipe"; copy_template "$D"
(cd "$D" && bash scripts/init-project.sh --name SigPipe --profile engineer 2>&1 | head -5) >/dev/null 2>&1 || true
ck "13d: the truncated run left .specflow.yml (half-instance, no commit)" test -f "$D/.specflow.yml"
ck "13d: the truncated run committed nothing" no test -e "$D/.git"
rc=0; out=$(init "$D" --name SigPipe2) || rc=$?
ck "13d: the re-run refuses (exit 1)" [ "$rc" = 1 ]
ck "13d: the re-run refusal names .specflow.yml" grep -qF '.specflow.yml' <<<"$out"
ck "13d: the re-run refusal carries the recovery hint (R-1)" grep -qF 'git reset -q --hard' <<<"$out"


# P6 Task 3.4 (REQ-303; P6 R35): init installs the pack's release action — stacks/<stack>/release/, its files included —
# as .github/actions/release/, beside the toolchain action, and copies every top-level stacks/<stack>/*.md into
# docs/releases/; a pack with no release/ installs none. Fixture packs only (the real ones gain release/ in Builds 4, 5).
# Covers: REQ-303
D="$WORK/rel-action"; copy_template "$D"; mkdir -p "$D/stacks/python/release"
printf 'name: fixture\nruns:\n  using: composite\n  steps: []\n' > "$D/stacks/python/release/action.yml"; echo e > "$D/stacks/python/release/extra.plist"
printf '# Extra\n' > "$D/stacks/python/extra-notes.md"
ck "python instance with a fixture release action" [ "$(rc_of ninit "$D" --name Rel --stack python)" = 0 ]
ck "init installs stacks/python/release/ as .github/actions/release/, its files included" \
  bash -c 'grep -qF "name: fixture" "$1/.github/actions/release/action.yml" && test -f "$1/.github/actions/release/extra.plist"' _ "$D"
ck "init copies every top-level stacks/<stack>/*.md into docs/releases/" test -f "$D/docs/releases/extra-notes.md"
D="$WORK/rel-none"; copy_template "$D"; rm -rf "$D/stacks/flutter/release"
ck "flutter instance (no scaffold) whose pack has no release/" [ "$(rc_of ninit "$D" --name Rel --stack flutter)" = 0 ]
ck "…installs no .github/actions/release/" no test -e "$D/.github/actions/release"
ck "…and still copies the store checklist" test -f "$D/docs/releases/store-checklist.md"

finish test_init
