#!/usr/bin/env bash
# Initialize a fresh SpecFlow v3.2 project from this template (REQ-300, REQ-301,
# REQ-303, REQ-308). Flags make every choice non-interactive; with none given,
# prompts ask the profile first, then apply guided/engineer questions. Leaves
# the repository on `main` — no branch is created or switched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/lib/specflow/config.py"

usage_err() {
  echo "init-project.sh: $1" >&2
  exit 2
}

precondition_err() {
  echo "init-project.sh: $1" >&2
  exit 1
}

# Shared verbatim between the section-5 EXIT trap (F-3/W-3) and the
# `.specflow.yml already present` precondition below (R-1): a SIGPIPE or
# SIGKILL kills bash before the EXIT trap can run, leaving a half-instance
# with no commit; the next run must still be able to find its way out.
RECOVERY_HINT="restore with: git reset -q --hard && git clean -qfd (existing clone) or delete this copy and re-extract it"

cfg_get() {  # cfg_get FILE KEY -> value or empty
  python3 "$CFG" --file "$1" get "$2" 2>/dev/null || true
}

escape_sed() { printf '%s' "$1" | sed 's/[&/\]/\\&/g'; }

# --- 1. Parse flags (stage a: flag syntax and allowed values) ---------------

NAME_FLAG=""
PROFILE_FLAG=""
STACK_FLAG=""
PATH_FLAG=""
SOLO_FLAG=""
DOCTOR=false
HAVE_FLAG=false

print_usage() {
  cat <<'USAGE'
Usage: init-project.sh [-h|--help] [--doctor] [--name NAME]
                        [--profile guided|engineer]
                        [--stack python|tauri|flutter]
                        [--path lanes|regulated] [--solo true|false]

  -h, --help          Show this help and exit 0.
  --doctor            Report-only prerequisite check for the configured (or
                       --stack-given) pack; writes nothing; exits 0 if
                       everything needed is present, 1 if anything is
                       missing.
  --name NAME         Project name (default: current directory name).
  --profile PROFILE   guided (default) or engineer.
  --stack STACK       python (default), tauri, or flutter.
  --path PATH         lanes (default) or regulated. Always honored; the
                       interactive guided prompts just skip this question
                       (guided always uses lanes when prompted).
  --solo true|false   Working alone, no second reviewer (default: true).

Passing any flag runs non-interactively, taking the default for anything not
given. With no flags at all, it prompts interactively in this order:
profile, then project name, then — guided profile — "What are you building?"
(a numbered menu that picks the stack; the path is always lanes); engineer
profile asks for the stack directly, then the path. Every profile is then
asked whether you are working alone (solo). Press Enter at any prompt to
accept its default.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      exit 0 ;;
    --name)
      [[ $# -ge 2 ]] || usage_err "--name needs a value"
      NAME_FLAG="$2"; HAVE_FLAG=true; shift 2 ;;
    --profile)
      [[ $# -ge 2 ]] || usage_err "--profile needs a value"
      case "$2" in
        guided|engineer) ;;
        *) usage_err "--profile: invalid value '$2' (must be guided or engineer)" ;;
      esac
      PROFILE_FLAG="$2"; HAVE_FLAG=true; shift 2 ;;
    --stack)
      [[ $# -ge 2 ]] || usage_err "--stack needs a value"
      case "$2" in
        python|tauri|flutter) ;;
        *) usage_err "--stack: invalid value '$2' (must be python, tauri, or flutter)" ;;
      esac
      STACK_FLAG="$2"; HAVE_FLAG=true; shift 2 ;;
    --path)
      [[ $# -ge 2 ]] || usage_err "--path needs a value"
      case "$2" in
        lanes|regulated) ;;
        *) usage_err "--path: invalid value '$2' (must be lanes or regulated)" ;;
      esac
      PATH_FLAG="$2"; HAVE_FLAG=true; shift 2 ;;
    --solo)
      [[ $# -ge 2 ]] || usage_err "--solo needs a value"
      case "$2" in
        true|false) ;;
        *) usage_err "--solo: invalid value '$2' (must be true or false)" ;;
      esac
      SOLO_FLAG="$2"; HAVE_FLAG=true; shift 2 ;;
    --doctor)
      DOCTOR=true; HAVE_FLAG=true; shift ;;
    *)
      usage_err "unknown flag: $1" ;;
  esac
done

# --- 1b. --doctor: report-only prerequisite check; writes nothing ----------
#
# Runs before any precondition check so it works both in the template source
# and inside an already-initialized instance. Exits 0 (all present), 1 (any
# missing) or 2 (bad flag, already handled above).

doctor_os() { uname -s 2>/dev/null || echo unknown; }

doctor_report() {  # doctor_report NAME "MAC_CMD" "LINUX_CMD" -> "MISSING NAME: <cmd for this OS>"
  local os="$1" mac="$2" linux="$3"
  case "$os" in
    Darwin) printf '%s' "$mac" ;;
    Linux) printf '%s' "$linux" ;;
    *) printf '%s; or: %s' "$mac" "$linux" ;;
  esac
}

run_doctor() {
  local os missing=0
  os="$(doctor_os)"

  check_present() {  # check_present NAME VERSION_CMD MAC_INSTALL LINUX_INSTALL
    local name="$1" vcmd="$2" mac="$3" linux="$4" ver
    if ver="$(eval "$vcmd" 2>/dev/null | head -1)" && [[ -n "$ver" ]]; then
      echo "ok   $name ($ver)"
    else
      echo "MISSING $name: $(doctor_report "$os" "$mac" "$linux")"
      missing=$((missing + 1))
    fi
  }

  check_present git "git --version" "xcode-select --install" "sudo apt-get install -y git"
  check_present gh "gh --version" "brew install gh" "sudo apt-get install -y gh"
  check_present jq "jq --version" "brew install jq" "sudo apt-get install -y jq"
  check_present gitleaks "gitleaks version" \
    'bash scripts/install-pinned-tool.sh gitleaks --dest "$HOME/.local/bin" (checksum-verified; put ~/.local/bin on PATH) — or: brew install gitleaks' \
    'bash scripts/install-pinned-tool.sh gitleaks --dest "$HOME/.local/bin" (checksum-verified; put ~/.local/bin on PATH)'
  check_present osv-scanner "osv-scanner --version" \
    'bash scripts/install-pinned-tool.sh osv-scanner --dest "$HOME/.local/bin" (checksum-verified; put ~/.local/bin on PATH) — or: brew install osv-scanner' \
    'bash scripts/install-pinned-tool.sh osv-scanner --dest "$HOME/.local/bin" (checksum-verified; put ~/.local/bin on PATH)'

  local pyver
  if pyver="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"; then
    local pymajor="${pyver%%.*}" pyminor
    pyminor="$(printf '%s' "$pyver" | cut -d. -f2)"
    if [[ "$pymajor" -gt 3 ]] || { [[ "$pymajor" -eq 3 ]] && [[ "$pyminor" -ge 12 ]]; }; then
      echo "ok   python3 ($pyver)"
    else
      echo "MISSING python3: need 3.12+, found $pyver — $(doctor_report "$os" "brew install python@3.12" "sudo apt-get install -y python3.12 python3.12-venv")"
      missing=$((missing + 1))
    fi
  else
    echo "MISSING python3: $(doctor_report "$os" "brew install python@3.12" "sudo apt-get install -y python3.12 python3.12-venv")"
    missing=$((missing + 1))
  fi

  check_present claude "claude --version" "npm install -g @anthropic-ai/claude-code" "npm install -g @anthropic-ai/claude-code"

  local doctor_stack="$STACK_FLAG"
  [[ -n "$doctor_stack" ]] || doctor_stack="$(python3 "$CFG" --root . get stack --default python 2>/dev/null || true)"
  [[ -n "$doctor_stack" ]] || doctor_stack="python"

  if [[ "$doctor_stack" == python ]]; then
    if python3 -m pytest --version >/dev/null 2>&1 \
      && python3 -m ruff --version >/dev/null 2>&1 \
      && python3 -m black --version >/dev/null 2>&1; then
      echo "ok   python3 -m pytest|ruff|black"
    else
      echo "MISSING python3 -m pytest|ruff|black: python3 -m venv .venv && . .venv/bin/activate && pip install -r scripts/requirements.txt"
      missing=$((missing + 1))
    fi
  else
    if python3 -m pytest --version >/dev/null 2>&1; then
      echo "ok   python3 -m pytest"
    else
      echo "MISSING python3 -m pytest: python3 -m venv .venv && . .venv/bin/activate && pip install -r scripts/requirements.txt"
      missing=$((missing + 1))
    fi
  fi

  if find verification -name '*.dfy' 2>/dev/null | grep -q .; then
    check_present dafny "dafny --version" "brew install dafny" \
      "wget -q https://github.com/dafny-lang/dafny/releases/download/v4.11.0/dafny-4.11.0-x64-ubuntu-22.04.zip && unzip -q dafny-4.11.0-*.zip -d /opt/dafny && export PATH=/opt/dafny/dafny:\$PATH (see verification/README.md)"
  fi

  # Pack prerequisites — an instance keeps its pack metadata at
  # .specflow/pack.yml, chosen once at init; the template source reads the
  # requested stack's pack directly (--stack, else config, else python).
  # Either the pack file is missing, or (in an instance) it belongs to a
  # different stack than the one doctor was asked about — both are MISSING.
  local pack_file="" pack_err=""
  if [[ -f .specflow/pack.yml ]]; then
    local inst_stack
    inst_stack="$(cfg_get .specflow/pack.yml stack)"
    if [[ "$inst_stack" == "$doctor_stack" ]]; then
      pack_file=".specflow/pack.yml"
    else
      pack_err="MISSING pack $doctor_stack: this instance was initialized with the $inst_stack pack (.specflow/pack.yml); a stack is chosen once, at init"
    fi
  else
    if [[ -f "stacks/$doctor_stack/pack.yml" ]]; then
      pack_file="stacks/$doctor_stack/pack.yml"
    else
      pack_err="MISSING pack $doctor_stack: stacks/$doctor_stack/ is not present in this checkout"
    fi
  fi

  if [[ -n "$pack_err" ]]; then
    echo "$pack_err"
    missing=$((missing + 1))
  fi

  if [[ -n "$pack_file" ]]; then
    local p
    for p in $(python3 "$CFG" --file "$pack_file" getlist prereqs 2>/dev/null || true); do
      local check mac linux
      check="$(cfg_get "$pack_file" "check_$p")"
      mac="$(cfg_get "$pack_file" "install_macos_$p")"
      linux="$(cfg_get "$pack_file" "install_linux_$p")"
      if [[ -n "$check" ]] && eval "$check" >/dev/null 2>&1; then
        echo "ok   $p"
      else
        echo "MISSING $p: $(doctor_report "$os" "$mac" "$linux")"
        missing=$((missing + 1))
      fi
    done
  fi

  echo "doctor: $missing missing"
  [[ "$missing" -eq 0 ]]
}

if $DOCTOR; then
  if run_doctor; then
    exit 0
  else
    exit 1
  fi
fi

# --- 1c. Interpreter guard (stage a, normal path only; REQ-300) -------------
#
# Everything past this point (cfg_get, every pack's `init.sh package`) needs
# python3 >= 3.12; macOS ships /usr/bin/python3 3.9, which crashes with a
# raw AttributeError on sys.stdlib_module_names the first time a pack's
# package check runs it. Fail cleanly, with the same install command the
# doctor prints, before any of that runs. --doctor has its own check above
# and is intentionally not routed through this one.
PYVER=""
if PYVER="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"; then
  PYMAJOR="${PYVER%%.*}"
  PYMINOR="$(printf '%s' "$PYVER" | cut -d. -f2)"
  if [[ "$PYMAJOR" -lt 3 ]] || { [[ "$PYMAJOR" -eq 3 ]] && [[ "$PYMINOR" -lt 12 ]]; }; then
    precondition_err "python3 $PYVER found, need 3.12+ — $(doctor_report "$(doctor_os)" "brew install python@3.12" "sudo apt-get install -y python3.12 python3.12-venv")"
  fi
else
  precondition_err "python3 not found, need 3.12+ — $(doctor_report "$(doctor_os)" "brew install python@3.12" "sudo apt-get install -y python3.12 python3.12-venv")"
fi

INTERACTIVE=true
$HAVE_FLAG && INTERACTIVE=false

# --- 2. Preconditions (stage b) ---------------------------------------------

if [[ -f .specflow.yml ]]; then
  # A SIGPIPE or SIGKILL mid-run (F-3/W-3) can leave .specflow.yml written
  # but never committed — the EXIT trap below never got to fire. Tell
  # those two cases apart the same way: tracked by git means a real,
  # committed instance; untracked (or no .git at all) means a half-instance
  # from an interrupted run, so give the same recovery hint the trap would
  # have printed (R-1).
  SPECFLOW_YML_TRACKED=false
  if [[ -d .git ]] && git ls-files --error-unmatch .specflow.yml >/dev/null 2>&1; then
    SPECFLOW_YML_TRACKED=true
  fi
  if $SPECFLOW_YML_TRACKED; then
    precondition_err "refusing to init — .specflow.yml already present (this looks like an initialized instance)"
  else
    precondition_err "refusing to init — .specflow.yml already present (this looks like an initialized instance) — if this is a half-finished init (interrupted mid-run), $RECOVERY_HINT"
  fi
fi

if [[ -d .git ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [[ "$BRANCH" != "main" ]]; then
    precondition_err "refusing to init — current branch is '$BRANCH', not 'main'"
  fi
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    precondition_err "refusing to init — working tree is dirty (commit or stash changes first)"
  fi
fi

# The backlog template (REQ-371): checked here, before any effect, so a missing one leaves nothing written — not even
# .specflow.yml, which would make the next run refuse as "already present".
if [[ ! -f templates/BACKLOG.md ]]; then
  precondition_err "refusing to init — templates/BACKLOG.md is missing: the new instance would keep the factory's own backlog (its BL ids); restore it from the template (git checkout -- templates/BACKLOG.md), then run init"
fi

# --- 3. Gather profile/name/stack/path/solo -------------------------------

DEFAULT_NAME="$(basename "$(pwd)")"

ask() {  # ask PROMPT VARNAME -- prompts to stderr, reads a line via read -r
  printf '%s' "$1" >&2
  local val=""
  IFS= read -r val || val=""
  printf -v "$2" '%s' "$val"
}

echo "=== SpecFlow v3.2 Project Setup ===" >&2
echo "" >&2

if $INTERACTIVE; then
  ask "Profile — guided or engineer? [guided]: " PROFILE_IN
  PROFILE_NORM="$(printf '%s' "$PROFILE_IN" | tr '[:upper:]' '[:lower:]')"
  PROFILE="${PROFILE_NORM:-guided}"
  case "$PROFILE" in
    guided|engineer) ;;
    *) usage_err "profile: invalid value '$PROFILE_IN' (must be guided or engineer)" ;;
  esac

  ask "Project name [$DEFAULT_NAME]: " NAME_IN
  NAME="${NAME_IN:-$DEFAULT_NAME}"

  if [[ "$PROFILE" == "guided" ]]; then
    printf 'What are you building?\n' >&2
    ORDER_TMP="$(mktemp)"
    for d in stacks/*/; do
      [[ -f "${d}pack.yml" ]] || continue
      gc="$(cfg_get "${d}pack.yml" guided_choice)"
      gl="$(cfg_get "${d}pack.yml" guided_label)"
      printf '%s\t%s\n' "$gc" "$gl" >> "$ORDER_TMP"
    done
    sort -n "$ORDER_TMP" | while IFS=$'\t' read -r gc gl; do
      printf '  (%s) %s\n' "$gc" "$gl" >&2
    done
    rm -f "$ORDER_TMP"
    [[ -d stacks/tauri ]]   || printf '  (a Mac desktop app option arrives with the tauri pack)\n' >&2
    [[ -d stacks/flutter ]] || printf '  (a multi-platform app option arrives with the flutter pack)\n' >&2

    DEFAULT_CHOICE="$(cfg_get stacks/python/pack.yml guided_choice)"
    [[ -n "$DEFAULT_CHOICE" ]] || DEFAULT_CHOICE="2"
    ask "Choice [$DEFAULT_CHOICE]: " CHOICE_IN
    CHOICE="${CHOICE_IN:-$DEFAULT_CHOICE}"

    STACK=""
    for d in stacks/*/; do
      [[ -f "${d}pack.yml" ]] || continue
      gc="$(cfg_get "${d}pack.yml" guided_choice)"
      if [[ "$gc" == "$CHOICE" ]]; then
        STACK="$(basename "$d")"
        break
      fi
    done
    if [[ -z "$STACK" ]]; then
      usage_err "guided choice: invalid value '$CHOICE' (no pack has guided_choice=$CHOICE)"
    fi
    PATH_VAL="lanes"
  else
    AVAIL_STACKS=""
    for d in stacks/*/; do
      s="$(basename "$d")"
      AVAIL_STACKS="${AVAIL_STACKS:+$AVAIL_STACKS, }$s"
    done
    ask "Stack ($AVAIL_STACKS) [python]: " STACK_IN
    STACK_NORM="$(printf '%s' "$STACK_IN" | tr '[:upper:]' '[:lower:]')"
    STACK="${STACK_NORM:-python}"
    case "$STACK" in
      python|tauri|flutter) ;;
      *) usage_err "stack: invalid value '$STACK_IN' (must be python, tauri, or flutter)" ;;
    esac
    ask "Path — lanes or regulated? [lanes]: " PATH_IN
    PATH_NORM="$(printf '%s' "$PATH_IN" | tr '[:upper:]' '[:lower:]')"
    PATH_VAL="${PATH_NORM:-lanes}"
    case "$PATH_VAL" in
      lanes|regulated) ;;
      *) usage_err "path: invalid value '$PATH_IN' (must be lanes or regulated)" ;;
    esac
  fi

  ask "Are you working alone (no second reviewer)? [Y/n]: " SOLO_IN
  case "$SOLO_IN" in
    [nN]*) SOLO="false" ;;
    *) SOLO="true" ;;
  esac
else
  PROFILE="${PROFILE_FLAG:-guided}"
  NAME="${NAME_FLAG:-$DEFAULT_NAME}"
  STACK="${STACK_FLAG:-python}"
  PATH_VAL="${PATH_FLAG:-lanes}"
  SOLO="${SOLO_FLAG:-true}"
fi

# --- 4. Stage c: name safety, pack presence, package rule, preflight -------

if ! [[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,63}$ ]]; then
  usage_err "--name: invalid value '$NAME' (must match ^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}\$)"
fi

STACK_DIR="stacks/$STACK"
if [[ ! -d "$STACK_DIR" ]]; then
  usage_err "no pack for stack '$STACK': $STACK_DIR/ is not present"
fi

# The stack-neutral candidate: lowercased, runs of non-[a-z0-9] -> '_',
# trimmed, 'app_' prefixed before a leading digit. Each pack's own
# `init.sh package` may refine or refuse this candidate (REQ-300, REQ-303).
PKG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')"
if [[ "$PKG" =~ ^[0-9] ]]; then
  PKG="app_$PKG"
fi

set +e
PKG_OUT="$(SPECFLOW_NAME="$NAME" SPECFLOW_PKG="$PKG" bash "$STACK_DIR/init.sh" package)"
package_rc=$?
set -e
[[ $package_rc -eq 0 ]] || exit "$package_rc"
PKG_OUT_LINES="$(wc -l <<<"$PKG_OUT" | tr -d ' ')"
if [[ -z "$PKG_OUT" ]] || [[ "$PKG_OUT_LINES" != 1 ]] || ! [[ "$PKG_OUT" =~ ^[a-z][a-z0-9_]*$ ]]; then
  usage_err "stacks/$STACK/init.sh package printed an invalid package '$PKG_OUT'"
fi
PKG="$PKG_OUT"

if [[ "${SPECFLOW_NO_SCAFFOLD:-}" != "1" ]]; then
  set +e
  SPECFLOW_NAME="$NAME" SPECFLOW_PKG="$PKG" bash "$STACK_DIR/init.sh" preflight
  preflight_rc=$?
  set -e
  if [[ $preflight_rc -ne 0 ]]; then
    echo "init: nothing was written — resolve the preflight problem above (for a missing tool: bash scripts/init-project.sh --doctor --stack $STACK) and re-run" >&2
    exit "$preflight_rc"
  fi
fi

echo "Initializing '$NAME' (package $PKG; $PROFILE profile, $STACK stack, $PATH_VAL path)..." >&2
echo "" >&2

# Git identity (stage c, F-3/W-3): section 5 always ends in `git commit`,
# whether .git already exists or init creates it here, so an unconfigured
# identity would otherwise fail only after everything else has been
# written. `git var GIT_COMMITTER_IDENT`/`GIT_AUTHOR_IDENT` resolve the same
# way commit does (global/system/local config, env vars, then an OS-level
# guess) and fail the same way commit would if none of those give an
# identity — checked separately (R-2) because `user.useConfigOnly` plus an
# explicit GIT_COMMITTER_* env pair (no GIT_AUTHOR_*) makes the committer
# half resolve while the author half still fails.
if ! git var GIT_COMMITTER_IDENT >/dev/null 2>&1 || ! git var GIT_AUTHOR_IDENT >/dev/null 2>&1; then
  precondition_err "no git identity configured — set it with git config --global user.name \"Your Name\" and git config --global user.email you@example.com (or without --global, in this repository only) and re-run"
fi

# --- 5. Effects: directories, config, pack install, scaffold, docs, git ----

# F-3/W-3: a failure partway through this section (a write that hits a
# permissions problem, a signal, anything set -e catches) otherwise leaves a
# half-instance that re-init refuses ("`.specflow.yml` already present")
# with no way out. Cleared right after the final commit succeeds below.
trap '
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "init failed — nothing has been committed; $RECOVERY_HINT" >&2
  fi
' EXIT
# A SIGPIPE (e.g. output piped into `head`) otherwise kills bash outright,
# skipping the EXIT trap above entirely (R-1) — ignore it here so a write
# that hits a closed pipe fails its command normally (EPIPE) instead, which
# `set -e` turns into a normal exit that the trap above does catch.
trap '' PIPE

# Every directory the 10-phase pipeline writes artifacts to. tests/e2e is not
# part of the template or an instance (spec Scope "Out").
mkdir -p docs/specs docs/plans docs/reviews docs/dashboard
mkdir -p docs/adr docs/architecture docs/security docs/releases docs/retrospectives
mkdir -p src src/contracts tests/unit tests/integration tests/data
mkdir -p tests/governance
mkdir -p verification
mkdir -p .github/workflows .github/ISSUE_TEMPLATE
mkdir -p .claude/rules
mkdir -p schemas templates scripts

# .specflow.yml is the one pipeline config (art-branch-as-state); scripts/
# run-quality-gates.sh and the RELEASE hook read it through config.py.
python3 "$CFG" --root . write profile="$PROFILE" path="$PATH_VAL" stack="$STACK" solo="$SOLO"
if ! python3 "$CFG" --root . validate; then
  precondition_err ".specflow.yml failed validation after write — this should not happen; please file a bug"
fi
echo "Wrote .specflow.yml" >&2

TESTING_VAL="$(cfg_get "$STACK_DIR/pack.yml" testing)"
RATIONALE_VAL="$(cfg_get "$STACK_DIR/pack.yml" guided_rationale)"
CONSEQUENCE_VAL="$(cfg_get "$STACK_DIR/pack.yml" guided_consequence)"

if [[ "$PROFILE" == "guided" ]]; then
  PROFILE_VAL="guided — Claude proposes technical decisions with a plain-English rationale; you confirm and merge"
else
  PROFILE_VAL="engineer — you make the technical calls; Claude implements and reviews"
fi

SAFE_NAME="$(escape_sed "$NAME")"
SAFE_STACK="$(escape_sed "$STACK")"
SAFE_TESTING="$(escape_sed "$TESTING_VAL")"
SAFE_PROFILE="$(escape_sed "$PROFILE_VAL")"

subst_pack_tokens() {  # subst_pack_tokens FILE
  sed -i.bak -e "s/__PKG__/$PKG/g" -e "s/__NAME__/$SAFE_NAME/g" "$1" && rm -f "$1.bak"
}

# Per-stack quality-gate / security / release hooks (REQ-303).
cp "$STACK_DIR/gates.sh" "scripts/quality-gates-${STACK}.sh"
chmod +x "scripts/quality-gates-${STACK}.sh"
cp "$STACK_DIR/security.sh" "scripts/security-${STACK}.sh"
chmod +x "scripts/security-${STACK}.sh"
cp "$STACK_DIR/release.sh" "scripts/release-${STACK}.sh"
chmod +x "scripts/release-${STACK}.sh"

# REQ-325: a pack's own lcov coverage-floor helper (currently flutter's), when it has one.
if [[ -f "$STACK_DIR/lcov-threshold.sh" ]]; then
  cp "$STACK_DIR/lcov-threshold.sh" scripts/lcov-threshold.sh
  chmod +x scripts/lcov-threshold.sh
fi

mkdir -p .github/actions/toolchain
cp "$STACK_DIR/action.yml" .github/actions/toolchain/action.yml

# P6 R35: the pack's release action (stacks/<stack>/release/, its files included) beside the toolchain action, for
# release.yml's stack jobs; a pack without one installs nothing there.
if [[ -d "$STACK_DIR/release" ]]; then
  mkdir -p .github/actions/release
  cp -R "$STACK_DIR/release/." .github/actions/release/
fi

mkdir -p .specflow
cp "$STACK_DIR/pack.yml" .specflow/pack.yml

# Instances inherit no template-only CI (H5): strip the first-run job (and any
# other block between the markers), drop app-stacks.yml (Task 8 creates it in
# the template only), and point the gates job at this pack's runner (REQ-360).
CI_YML=".github/workflows/ci.yml"
if [[ -f "$CI_YML" ]]; then
  awk '
    /# >>> specflow:template-only/ { skip = 1; next }
    /# <<< specflow:template-only/ { skip = 0; next }
    !skip { print }
  ' "$CI_YML" > "$CI_YML.tmp" && mv "$CI_YML.tmp" "$CI_YML"
  CI_RUNS_ON="$(cfg_get "$STACK_DIR/pack.yml" ci_runs_on)"
  CI_RUNS_ON="${CI_RUNS_ON:-ubuntu-latest}"
  SAFE_RUNS_ON="$(escape_sed "$CI_RUNS_ON")"
  sed -i.bak -e "s/^\(    runs-on: \).*\( # specflow:runs-on\)\$/\1${SAFE_RUNS_ON}\2/" "$CI_YML" && rm -f "$CI_YML.bak"
  # P6 R35: the pack's Python at the marker, when the pack declares one (a pack without the key leaves the line).
  CI_PYTHON="$(cfg_get "$STACK_DIR/pack.yml" python_version)"
  if [[ -n "$CI_PYTHON" ]]; then
    SAFE_PYTHON="$(escape_sed "$CI_PYTHON")"
    sed -i.bak -e "s/^\(          python-version: \).*\( # specflow:python-version\)\$/\1\"${SAFE_PYTHON}\"\2/" "$CI_YML" && rm -f "$CI_YML.bak"
  fi
fi
rm -f .github/workflows/app-stacks.yml
# REQ-321 (R15): the template source's own test-first pack is inert once a
# stack pack (.specflow/pack.yml, above) exists.
rm -f scripts/template-pack.yml scripts/release-template.sh

if [[ -f "$STACK_DIR/Dockerfile" ]]; then
  cp "$STACK_DIR/Dockerfile" Dockerfile
  subst_pack_tokens Dockerfile
fi

if [[ -f "$STACK_DIR/deploy.sh" ]]; then
  cp "$STACK_DIR/deploy.sh" scripts/deploy-local.sh
  subst_pack_tokens scripts/deploy-local.sh
  chmod +x scripts/deploy-local.sh
fi

# Every top-level Markdown file of the pack lands in docs/releases/ under its own name (the store checklist; P6 R35 adds
# the tester-instructions template).
for pack_md in "$STACK_DIR"/*.md; do
  if [[ -f "$pack_md" ]]; then
    cp "$pack_md" "docs/releases/$(basename "$pack_md")"
  fi
done

# Scaffold the pack's skeleton into the target (this directory). Skipped
# under SPECFLOW_NO_SCAFFOLD=1 (test-only: exercises everything else about an
# instance without a toolchain to compile Rust, run flutter, or fetch a
# generator).
if [[ "${SPECFLOW_NO_SCAFFOLD:-}" == "1" ]]; then
  echo "SKIP scaffold (SPECFLOW_NO_SCAFFOLD=1: test-only; this instance has no skeleton)" >&2
else
  SPECFLOW_NAME="$NAME" SPECFLOW_PKG="$PKG" bash "$STACK_DIR/init.sh" scaffold
  echo "Scaffolded $STACK skeleton" >&2
fi

# IDEA.md — guided profile records the chosen stack and its rationale.
if [ ! -f IDEA.md ]; then
  cp templates/IDEA.md IDEA.md
  echo "Created IDEA.md — fill it in before running /superpowers:brainstorming" >&2
fi
if [[ "$PROFILE" == "guided" ]]; then
  {
    echo ""
    echo "## Stack"
    echo ""
    echo "### Guided proposals"
    echo "Decision (asked at init): the stack, $STACK."
    echo "Rationale (plain English): $RATIONALE_VAL"
    echo "What this means for you: $CONSEQUENCE_VAL"
  } >> IDEA.md
fi

# REQ-306: drop every other stack's canonical example — its listed paths and
# its CLAUDE.md manifest subsection — before stacks/ (and examples.py with
# it) is removed below.
EXAMPLES_PY="scripts/lib/specflow/examples.py"
while read -r ex_name ex_stack; do
  [[ -z "$ex_name" ]] && continue
  [[ "$ex_stack" == "$STACK" ]] && continue
  while IFS= read -r ex_path; do
    [[ -z "$ex_path" ]] && continue
    rm -rf "$ex_path"
  done < <(python3 "$EXAMPLES_PY" list "$ex_name")
  python3 "$EXAMPLES_PY" strip "$ex_name"
done < <(python3 "$EXAMPLES_PY" names)

# REQ-306 (P5 R11): the factory's own design documents and proofs are not the
# instance's. scripts/factory-only.txt lists them as globs; match them against a
# walk of the new tree (no .git exists yet, so never git ls-files), skip every
# path the examples manifest still lists, remove each match, then the manifest.
FENCE_MANIFEST="scripts/factory-only.txt"
if [[ -f "$FENCE_MANIFEST" ]]; then
  KEEP_FILE="$(mktemp)"
  while read -r ex_name ex_stack; do
    [[ -z "$ex_name" ]] && continue
    python3 "$EXAMPLES_PY" list "$ex_name"
  done < <(python3 "$EXAMPLES_PY" names) > "$KEEP_FILE"
  python3 - "$FENCE_MANIFEST" "$KEEP_FILE" <<'PY'
import fnmatch, os, shutil, sys
man, keep_file = sys.argv[1:]
globs = [l.strip() for l in open(man) if l.strip() and not l.lstrip().startswith("#")]
keep = {l.strip().rstrip("/") for l in open(keep_file) if l.strip()}
def hit(g, f):
    return f.startswith(g) if g.endswith("/") else fnmatch.fnmatch(f, g)
files = []
for d, dirs, names in os.walk("."):
    dirs[:] = [x for x in dirs if x != ".git"]
    for n in names:
        files.append(os.path.relpath(os.path.join(d, n), "."))
for f in sorted(files):
    if f in keep or any(f.startswith(k + "/") for k in keep):
        continue
    if any(hit(g, f) for g in globs):
        os.remove(f)
for g in globs:   # a directory glob leaves nothing behind; pipeline directories (docs/specs, ...) stay
    if g.endswith("/") and os.path.isdir(g) and not any(True for _, _, n in os.walk(g) for _ in n):
        shutil.rmtree(g)
PY
  rm -f "$KEEP_FILE"
fi

# REQ-322, REQ-306 (PR #59 verifier run 1, finding 1): docs/security/RUBRIC.md ships to every instance, but the
# factory's medium_cap override is the factory's own decision. A new instance starts at the constitution's default of 5
# (art-threat-driven-security), with no override record; every other line of the file is kept as is.
RUBRIC_MD="docs/security/RUBRIC.md"
if [[ -f "$RUBRIC_MD" ]]; then
  python3 - "$RUBRIC_MD" <<'PY'
import re, sys
p = sys.argv[1]
lines = open(p).read().split("\n")
out, skip = [], False
for l in lines:
    if l.startswith("Override record"):
        skip = True
        continue
    if skip:
        if l.startswith("## "):
            skip = False
        else:
            continue
    out.append(re.sub(r"^medium_cap: \d+ *", lambda m: "medium_cap: 5".ljust(len(m.group(0))), l))  # the comment stays aligned
open(p, "w").write("\n".join(out))
PY
fi

# The backlog (REQ-371, art-retrospective-cadence): an instance's deferred proposals and BL-NNN ids are its own, so its
# docs/BACKLOG.md starts as the empty template, replacing the factory's (templates/BACKLOG.md is checked in the
# preconditions, before any effect).
mkdir -p docs
cp templates/BACKLOG.md docs/BACKLOG.md

# stacks/ is a template-source-only directory; instances never keep it.
rm -rf stacks

# Substitute the templated docs. CLAUDE.md carries {{PROJECT_NAME}}, {{STACK}},
# {{TESTING}} and {{PROFILE}}; README.md carries {{PROJECT_NAME}} only (the
# others are a no-op there). Per-file so a missing doc never blocks renaming
# the others.
for doc in CLAUDE.md README.md; do
  [ -f "$doc" ] || continue
  sed -i.bak "s/{{PROJECT_NAME}}/$SAFE_NAME/g; s/{{STACK}}/$SAFE_STACK/g; s/{{TESTING}}/$SAFE_TESTING/g; s/{{PROFILE}}/$SAFE_PROFILE/g" "$doc" && rm -f "$doc.bak"
done

# The signing anchor (REQ-383, REQ-306): an instance trusts none of the factory's keys. Comment-only signer files are
# written here, so the `chore: initialize` commit below is the newest key-less one and trust on first use starts after it
# whatever history the instance inherited.
mkdir -p .github
cat > .github/allowed_signers <<'SIGNERS'
# Release signers. A release tag v<version> is verified (git verify-tag) against this file as committed at the anchor -
# the newest earlier SSH-signed v<X.Y.Z> tag among the tag's strict ancestors, else trust on first use - never against
# the current tree; unsigned, lightweight and GPG-signed candidates are passed over, while an SSH-signed one off main's
# first-parent chain is refused (anchor-off-main), never passed over.
# Add your key: one line `<your git email> namespaces="git" <the contents of your .pub file>` in a PR, spelled exactly
# as your `git config user.email`; a key is trusted from the release after the first one tagged on a commit that lists
# it. Public keys only.
SIGNERS
cat > .github/revoked_signers <<'SIGNERS'
# Revoked release signers. One public key per line: <key type> <base64 public key>. A tag signed by a key listed here
# is refused (revoked); the file is read at the tag and, at tag time, on main's tip too (a union).
SIGNERS

# Initialize git — never creates or switches a branch; stays on main.
if [ ! -d .git ]; then
  git init -q -b main
fi
git add -A
git commit -q -m "chore: initialize $NAME from SpecFlow v3.2 template ($STACK, $PROFILE, $PATH_VAL)"
trap - EXIT
trap - PIPE

echo "" >&2
echo "=== Setup Complete ===" >&2
echo "" >&2
echo "You are on branch 'main'. No branch was created for you." >&2
echo "" >&2

if [[ "$PATH_VAL" == "regulated" ]]; then
  cat >&2 <<EON
Next steps (regulated path):
  0) In Claude Code, run /next at any time: it reads your branches, PRs and files and prints the next step (the guided profile runs it for you).
  1) Fill in IDEA.md with your product idea.
  2) git checkout -b phase/spec-<slug>
  3) Run /superpowers:brainstorming, then /specify to formalize the spec.
  4) Push and open a PR to main; from a terminal OUTSIDE any Claude Code
     session run:
       git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR-number>
     in team mode a human other than the author approves; in solo mode the
     verifier's APPROVE is the second review. Then merge.
  5) After the spec PR merges: git checkout -b phase/arch-<slug> (if a REQ is tagged [verifiable]/[verifiable-model]), run /architecture, then push and open its PR (same review-gate steps as step 4).
  6) Continue on phase/plan-<slug> for /specflow-plan, /specflow-tasks,
     /analyze, then impl/plan-N-<plan slug> for IMPLEMENT (N the plan's
     ## Build N section), phase/validate, phase/security, phase/release.
  7) After pushing to GitHub, run: bash scripts/configure-repo.sh
EON
else
  cat >&2 <<EON
Next steps (lanes path):
  0) In Claude Code, run /next at any time: it reads your branches, PRs and files and prints the next step (the guided profile runs it for you).
  1) Fill in IDEA.md with your product idea.
  2) git checkout -b design/<slug>
  3) Run /superpowers:brainstorming, then /specify (and /architecture if a
     requirement is tagged [verifiable]/[verifiable-model]), then
     /specflow-plan, /specflow-tasks, /analyze.
  4) Push and open a PR to main; from a terminal OUTSIDE any Claude Code
     session run:
       git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR-number>
     in team mode a human other than the author approves; in solo mode the
     verifier's APPROVE is the second review. Then merge.
  5) Continue on build/<slug>-1 for IMPLEMENT (CI on that PR is VALIDATE),
     then ship/<version> for SECURITY, RELEASE.
  6) After pushing to GitHub, run: bash scripts/configure-repo.sh
EON
fi
