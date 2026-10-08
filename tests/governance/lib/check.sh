# Sourced by governance tests (not run by the gates, which glob test_*.sh).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"; cd "$ROOT"
FAIL=0
pass() { echo "ok:   $1"; }
FINISHED=0
# A check after finish can never fail the script (finish exits only on failure), so it is refused outright:
# finish must be the last line of every governance test (PR #34 third-run high, "test the validator").
_after_finish() { if [[ ${FINISHED:-0} -eq 1 ]]; then echo "FAIL: $1 — check placed after finish; move it above finish (nothing may follow finish)"; exit 1; fi; }
fail() { _after_finish "$1"; echo "FAIL: $1"; FAIL=1; }
ck() { local d="$1"; shift; _after_finish "$d"; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
no() { ! "$@"; }
instance() { [[ -f .specflow.yml || -f .stack ]]; }
# factory_doc_ck DESC PATH CMD... — a pin on a factory document scripts/factory-only.txt fences out of every instance
# (REQ-306): run as ck DESC CMD... in the template source; in an instance, print a visible SKIP line naming PATH.
factory_doc_ck() { local d="$1" p="$2"; shift 2; _after_finish "$d"; if instance; then echo "SKIP (instance: $p is fenced): $d"; else ck "$d" "$@"; fi; }
finish() { FINISHED=1; if [[ $FAIL -eq 0 ]]; then echo "$1: all checks passed"; else echo "$1: FAILED"; exit 1; fi; }
copy_template() {  # copy_template DEST — the working tree as on disk, no .git
  mkdir -p "$1"
  (cd "$ROOT" && git ls-files -z --cached --others --exclude-standard \
     | while IFS= read -r -d '' f; do if [[ -e "$f" ]]; then printf '%s\0' "$f"; fi; done \
     | tar -cf - --null -T -) | (cd "$1" && tar -xf -)
}
export GIT_AUTHOR_NAME=specflow-test GIT_AUTHOR_EMAIL=specflow-test@example.invalid
export GIT_COMMITTER_NAME=specflow-test GIT_COMMITTER_EMAIL=specflow-test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

stub_pack() {  # stub_pack DIR STACK CHOICE LABEL — a toolchain-free stand-in for DIR/stacks/STACK
  local p="$1/stacks/$2"; rm -rf "$p"; mkdir -p "$p"
  cp "$1"/stacks/python/{gates.sh,security.sh,release.sh,action.yml} "$p/"
  printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in package) echo "$SPECFLOW_PKG" ;; preflight|scaffold) exit 0 ;; *) exit 2 ;; esac' > "$p/init.sh"
  chmod +x "$p/init.sh"; echo '# stub' > "$p/store-checklist.md"
  printf 'stack: %s\nguided_choice: %s\nguided_label: %s\nguided_rationale: stub rationale for %s\nguided_consequence: stub consequence for %s, what it means for the user\ntesting: stub testing line\nci_runs_on: ubuntu-latest\nsource_roots: [src]\ntest_globs: [src/**/*.test.ts]\ncoverage_exclude: []\nprereqs: []\n' "$2" "$3" "$4" "$2" "$2" > "$p/pack.yml"
}

run_within() {  # run_within SECS CMD... — CMD's status, or 124 once it outlives SECS (no coreutils timeout on macOS)
  local secs="$1"; shift
  "$@" & local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ $i -ge $secs ]]; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; fi
    sleep 1; i=$((i + 1))
  done
  wait "$pid"
}

stub_bin() {  # stub_bin DIR — fake gh, claude and gitleaks in DIR/bin (P2). Each appends its argv (one per line, then ---) to DIR/<tool>.argv.
  local d="$1"; mkdir -p "$d/bin"
  cat > "$d/bin/gh" <<'EOF'
#!/usr/bin/env bash
S="${STUB_DIR:?}"; { printf '%s\n' "$@"; echo ---; } >> "$S/gh.argv"
case "$1 ${2:-}" in
  "pr view")    cat "$S/pr.json" ;;
  "pr comment") while [ $# -gt 0 ]; do if [ "$1" = --body-file ]; then cp "$2" "$S/posted.md"; fi; shift; done ;;
  "run list")   if [ -f "$S/runs.json" ]; then cat "$S/runs.json"; else echo '[]'; fi ;;
  "run rerun")  exit "${STUB_RERUN_RC:-0}" ;;
  "repo view")  case " $* " in *" -q "*|*" --jq "*) echo o/r ;; *) echo '{"nameWithOwner": "o/r"}' ;; esac ;;
  api\ *)
    case "$*" in
      */issues/*/comments*) cat "$S/comments.json" ;;
      */issues/*/timeline*) if [ -f "$S/timeline.json" ]; then cat "$S/timeline.json"; else echo '[]'; fi ;;  # P7 R4
      */actions/runs*)  # default: one verifier run naming no PR (as for a fork PR), so the branch + SHA fallback applies
        if [ -n "${STUB_ACTIONS_RC:-}" ]; then echo 'gh: Server Error (HTTP 502)' >&2; exit "$STUB_ACTIONS_RC"; fi
        if [ -f "$S/actions_runs.json" ]; then cat "$S/actions_runs.json"
        else echo '{"total_count":1,"workflow_runs":[{"id":99,"path":".github/workflows/verifier.yml","pull_requests":[]}]}'; fi ;;
      */collaborators/*/permission*)  # R9: a MEMBER's repository role, from $S/permission.json, else HTTP 404
        if [ -f "$S/permission.json" ]; then cat "$S/permission.json"; else echo 'gh: Not Found (HTTP 404)' >&2; exit 1; fi ;;
      */pulls/*/commits*) f="${STUB_COMMITS:-$S/commits.json}"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
      */rulesets*)  # P6 Task 1.4: a POST/PUT body is saved and answered by STUB_RULESET_STATUS; a GET of the list prints
        # STUB_RULESETS; a GET of one ruleset (rulesets/<id>) prints STUB_RULESET, else HTTP 404
        case "$*" in
          *--method*)
            cat > "$S/ruleset.json"
            case "${STUB_RULESET_STATUS:-200}" in
              200) echo '{}' ;;
              403) echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
              *)   echo "gh: Not Found (HTTP ${STUB_RULESET_STATUS})" >&2; exit 1 ;;
            esac ;;
          */rulesets/[0-9]*) if [ -n "${STUB_RULESET:-}" ]; then echo "$STUB_RULESET"; else echo 'gh: Not Found (HTTP 404)' >&2; exit 1; fi ;;
          *) case "${STUB_RULESETS_STATUS:-200}" in   # the list (fix wave 2: STUB_RULESETS_STATUS answers it)
               200) echo "${STUB_RULESETS:-[]}" ;;
               403) echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
               *)   echo "gh: Server Error (HTTP ${STUB_RULESETS_STATUS})" >&2; exit 1 ;;
             esac ;;
        esac ;;
      */environments/release/deployment-branch-policies*)
        case "$*" in
          *--method*)
            cat > "$S/env-policy.json"
            case "${STUB_ENV_STATUS:-200}" in
              200) echo '{}' ;;
              403) echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
              *)   echo "gh: Not Found (HTTP ${STUB_ENV_STATUS})" >&2; exit 1 ;;
            esac ;;
          *) if [ -n "${STUB_ENV_POLICIES_STATUS:-}" ]; then echo "gh: Server Error (HTTP ${STUB_ENV_POLICIES_STATUS})" >&2; exit 1; fi
             if [ -n "${STUB_ENV_POLICIES:-}" ]; then echo "$STUB_ENV_POLICIES"; else echo '{"total_count": 0, "branch_policies": []}'; fi ;;
        esac ;;
      */environments/release*)
        case "$*" in
          *--method*)
            cat > "$S/environment.json"
            case "${STUB_ENV_STATUS:-200}" in
              200) echo '{}' ;;
              403) echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
              *)   echo "gh: Not Found (HTTP ${STUB_ENV_STATUS})" >&2; exit 1 ;;
            esac ;;
          *) if [ -n "${STUB_ENV:-}" ]; then echo "$STUB_ENV"; else echo 'gh: Not Found (HTTP 404)' >&2; exit 1; fi ;;
        esac ;;
      "api user")  # fix wave 2: the authenticated user (configure-repo.sh's team-mode environment reviewer)
        if [ -n "${STUB_USER_RC:-}" ]; then echo 'gh: Bad credentials (HTTP 401)' >&2; exit "$STUB_USER_RC"; fi
        echo '{"login": "maint", "id": 4242}' ;;
      *"--method PATCH repos/o/r --input"*)  # P6 R28 (Build 3 re-review): the repository's merge methods; the body is
        # saved and answered by STUB_REPO_STATUS
        cat > "$S/repo.json"
        case "${STUB_REPO_STATUS:-200}" in
          200) echo '{}' ;;
          403) echo 'gh: Must have admin rights to Repository. (HTTP 403)' >&2; exit 1 ;;
          *)   echo "gh: Not Found (HTTP ${STUB_REPO_STATUS})" >&2; exit 1 ;;
        esac ;;
      */branches/main/protection*)
        cat > "$S/protection.json"
        case "${STUB_PROTECTION_STATUS:-200}" in
          200) echo '{}' ;;
          403) echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
          *)   echo "gh: Not Found (HTTP ${STUB_PROTECTION_STATUS})" >&2; exit 1 ;;
        esac ;;
      *) echo "stub gh: unexpected api call: $*" >&2; exit 64 ;;
    esac ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 64 ;;
esac
EOF
  cat > "$d/bin/claude" <<'EOF'
#!/usr/bin/env bash
S="${STUB_DIR:?}"; { printf '%s\n' "$@"; echo ---; } >> "$S/claude.argv"
n=$(( $(cat "$S/claude.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/claude.n"
pwd -P > "$S/claude.cwd"; git rev-parse HEAD > "$S/claude.head" 2>/dev/null || true
cat > "$S/claude.stdin"
prev=""
for a in "$@"; do
  case "$prev" in
    --settings) cp "$a" "$S/claude.settings.json" ;;
    --mcp-config) cp "$a" "$S/claude.mcp.json" ;;
    --add-dir) ls "$a" > "$S/claude.adddir.ls" ;;
  esac
  prev="$a"
done
f="$S/claude.out.$n"; [ -f "$f" ] || f="$S/claude.out"; cat "$f"
exit "${STUB_CLAUDE_RC:-0}"
EOF
  cat > "$d/bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
# Mirrors gitleaks 8.30.1 `dir`: the path is the last argument; a hit exits with --exit-code (default 1); a missing
# --config file is fatal (exit 1). Only `dir` is accepted, so the pinned subcommand is asserted by every run.
S="${STUB_DIR:?}"; { printf '%s\n' "$@"; echo ---; } >> "$S/gitleaks.argv"
[ "${1:-}" = dir ] || { echo "stub gitleaks: expected the dir subcommand, got: $*" >&2; exit 64; }
code=1; cfg=""; prev=""; src=""
for a in "$@"; do
  case "$prev" in --exit-code) code="$a" ;; --config|-c) cfg="$a" ;; esac
  prev="$a"; src="$a"
done
if [ -n "$cfg" ] && [ ! -f "$cfg" ]; then echo 'FTL unable to load gitleaks config' >&2; exit 1; fi
if [ -n "$cfg" ]; then cp "$cfg" "$S/gitleaks.config"; fi
if [ -n "${STUB_GITLEAKS_RC:-}" ]; then exit "$STUB_GITLEAKS_RC"; fi
honour_allow=1; for a in "$@"; do [ "$a" = --ignore-gitleaks-allow ] && honour_allow=0; done
if grep -rqE 'AKIA[0-9A-Z]{16}' "$src"; then
  if [ "$honour_allow" = 1 ] && grep -rqi 'gitleaks:allow' "$src"; then exit 0; fi   # real gitleaks: an allow comment suppresses
  # Mirrors real gitleaks 8.30.1 --verbose --redact output on a hit: a
  # Finding/Secret block redacted, plus the RuleID a maintainer cites to waive
  # a genuine false positive (README.md's recovery text).
  { echo 'Finding:     REDACTED'; echo 'Secret:      REDACTED'; echo 'RuleID:      generic-api-key'; echo 'File:        (redacted)'; echo 'Line:        1'; echo 'leaks found: 1'; } >&2
  exit "$code"
fi
exit 0
EOF
  chmod +x "$d/bin/gh" "$d/bin/claude" "$d/bin/gitleaks"
}

# Verifier fixtures (P2): VW/repo holds this tree committed on main and pushed to VW/origin.git, as a template source
# (no .specflow.yml, no .specflow/, so solo defaults to true and the template code roots apply); VW/stub holds stub_bin.
verifier_repo() {  # verifier_repo DIR — sets VW, VR, VS
  VW="$1"; VR="$1/repo"; VS="$1/stub"; stub_bin "$VS"; mkdir -p "$1/home"
  copy_template "$VR"; rm -rf "$VR/.specflow.yml" "$VR/.stack" "$VR/.specflow"; git init -q --bare "$1/origin.git"
  (cd "$VR" && git init -q -b main && git add -A && git commit -qm base && git remote add origin "$1/origin.git" && git push -q origin main)
}
vbranch() {  # vbranch NAME SNIPPET [AUTHOR] — a PR head off main carrying SNIPPET's changes, pushed and checked out; the gh stub answers for it
  (cd "$VR" && git checkout -q main && git checkout -qb "$1" && mkdir -p docs/specs tests && eval "$2" && git add -A && git commit -qm "$1" && git push -q origin "$1")
  (cd "$VR" && python3 -c 'import json, subprocess, sys
rev = lambda r: subprocess.run(["git", "rev-parse", r], capture_output=True, text=True, check=True).stdout.strip()
print(json.dumps({"number": 7, "headRefName": sys.argv[1], "headRefOid": rev("origin/" + sys.argv[1]),
                  "baseRefName": "main", "baseRefOid": rev("origin/main"), "author": {"login": sys.argv[2]}}))' "$1" "${3:-alice}") > "$VS/pr.json"
  printf '[{"databaseId":99,"headSha":"%s"}]\n' "$(git -C "$VR" rev-parse HEAD)" > "$VS/runs.json"
}
vreset() { rm -f "$VS"/posted.md "$VS"/*.argv "$VS"/claude.n "$VS"/claude.stdin "$VS"/claude.cwd "$VS"/claude.head \
  "$VS"/claude.settings.json "$VS"/claude.mcp.json "$VS"/claude.adddir.ls "$VS"/gitleaks.config; }
vrun() {  # vrun ARGS… — the base-ref bootstrap, outside a Claude session, stubs first on PATH; sets rc and out
  vreset
  rc=0; out=$(cd "$VR" && unset CLAUDECODE && PATH="$VS/bin:$PATH" STUB_DIR="$VS" HOME="$VW/home" \
    bash -c 'git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- "$@"' _ "$@" </dev/null 2>&1) || rc=$?
}
vlocal() {  # vlocal ARGS… — the checkout's own copy of the script, outside a session; sets rc and out
  vreset
  rc=0; out=$(cd "$VR" && unset CLAUDECODE && PATH="$VS/bin:$PATH" STUB_DIR="$VS" HOME="$VW/home" bash scripts/run-verifier.sh "$@" </dev/null 2>&1) || rc=$?
}

floor_stubs() {  # floor_stubs DIR — fake floor tools (P4). gitleaks, osv-scanner, cargo, npm in DIR/bin; pip_audit and
  # bandit as python modules in DIR/py (python3 -m …, with PYTHONPATH=DIR/py). Each appends its argv (one per line,
  # then ---) to DIR/<tool>.argv and exits STUB_<TOOL>_RC (default 0); STUB_<TOOL>_MISSING=1 makes it behave as absent
  # (exit 127 / "No module named"); STUB_<TOOL>_MSG is printed to stderr before exiting (a network error, say);
  # --version prints the pinned version; gitleaks records GITLEAKS_CONFIG[_TOML] to DIR/gitleaks.env; npm prints
  # DIR/npm-audit.json (default: no vulnerabilities).
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

next_seed() {  # next_seed DIR — a small remote-less repository on main holding what next.sh reads (P5 Task 5): scripts/,
  # schemas/, the verifier skill, constitution.md and the glossary from this tree, then the synthetic greet set over it
  # (tests/governance/fixtures/next/seed/), so the tests run the same in the template source and in every instance.
  local d="$1" f
  mkdir -p "$d/.claude/skills" "$d/docs"
  cp -R "$ROOT/scripts" "$ROOT/schemas" "$d/"; cp -R "$ROOT/.claude/skills/verifier" "$d/.claude/skills/"
  cp "$ROOT/constitution.md" "$d/"; cp "$ROOT/docs/GLOSSARY.md" "$d/docs/"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} +
  cp -R "$ROOT/tests/governance/fixtures/next/seed/." "$d/"
  printf 'profile: engineer\npath: lanes\nsolo: true\n' > "$d/.specflow.yml"
  (cd "$d" && git init -q -b main && git add -A && git commit -qm seed)
}

next_sh() {  # next_sh ARGS — bash scripts/next.sh ARGS with CI's gate-script variables unset (PR #48: ci.yml's gates job
  # exports SPECFLOW_BASE_REF=refs/remotes/origin/<PR base> (the full ref since P6 Build 2) and SPECFLOW_HEAD_BRANCH, which a seed repository does not hold), so the
  # seed-based next tests run the same locally and in CI; test_next.sh sets them deliberately in its own scenario.
  env -u SPECFLOW_BASE_REF -u SPECFLOW_HEAD_BRANCH bash scripts/next.sh "$@"
}

# H10 (REQ-360): git's automatic gc and maintenance off for every git a test runs — a detached `git maintenance run
# --auto` still writing into a temp repository made an EXIT trap's rm -rf meet "Directory not empty" on macOS.
# Appended after any GIT_CONFIG_COUNT already exported.
_n="${GIT_CONFIG_COUNT:-0}"
export "GIT_CONFIG_KEY_${_n}=gc.auto" "GIT_CONFIG_VALUE_${_n}=0"
export "GIT_CONFIG_KEY_$((_n + 1))=maintenance.auto" "GIT_CONFIG_VALUE_$((_n + 1))=false"
export GIT_CONFIG_COUNT=$((_n + 2)); unset _n

rm_tree() {  # rm_tree DIR — rm -rf, retried up to ${RM_TREE_TRIES:-5} times a second apart; returns 0 whatever happens
  local d="$1" i=0 tries="${RM_TREE_TRIES:-5}"
  while [[ $i -lt $tries ]]; do
    rm -rf "$d" 2>/dev/null || true; if [[ ! -e "$d" ]]; then return 0; fi
    i=$((i + 1)); if [[ $i -lt $tries ]]; then sleep 1; fi
  done
  echo "note: rm_tree could not remove $d" >&2
  return 0
}
