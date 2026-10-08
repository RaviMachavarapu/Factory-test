#!/usr/bin/env bash
# Governance test: a fresh instance created from this template must actually
# instantiate correctly — it must rename to the new project, and the branch
# protection it configures must reference checks that really exist. Guards two
# defects where the template "works" mechanically but mis-instantiates:
#   - init-project.sh substitutes placeholders that are no longer present
#     (the rename silently no-ops; the instance keeps the template's identity)
#   - configure-repo.sh requires status-check contexts that match no workflow
#     job name (branch protection would block every merge forever)
# Covers: REQ-312
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }
pass() { echo "ok:   $1"; }

# 1. The placeholder checks describe the TEMPLATE SOURCE. A fresh instance has
#    already run init-project.sh — which writes .specflow.yml and substitutes
#    the placeholders away — so these checks would false-fail there. Skip them
#    when .specflow.yml or a legacy .stack is present (the unambiguous "init
#    has run" marker; the template source ships without either).
if [[ -f .specflow.yml || -f .stack ]]; then
  pass "instantiated instance (.specflow.yml or .stack present) — skipping template-source placeholder checks"
else
  # init-project.sh renames the templated docs by looping over them and sed-ing
  # {{PROJECT_NAME}}. The loop's doc list, with any trailing `;`/comment stripped:
  loop_docs=$(grep -E '^[[:space:]]*for doc in ' scripts/init-project.sh \
              | sed -E 's/.*for doc in//; s/;.*//; s/#.*//')

  if grep -qE 's/\{\{PROJECT_NAME\}\}/' scripts/init-project.sh; then
    pass "init-project.sh performs the {{PROJECT_NAME}} substitution"
  else
    fail "init-project.sh has no {{PROJECT_NAME}} substitution — instances are never renamed"
  fi

  # Every doc must (a) be a whitespace-delimited token in that loop list and
  # (b) still carry the {{PROJECT_NAME}} placeholder — together they prove the
  # rename actually reaches the file (not just a stray mention elsewhere).
  for f in CLAUDE.md README.md; do
    case " $loop_docs " in
      *" $f "*) : ;;
      *) fail "$f is not in init-project.sh's substitution loop — rename never reaches it"; continue ;;
    esac
    if grep -qF '{{PROJECT_NAME}}' "$f"; then
      pass "$f is renamed by init and carries {{PROJECT_NAME}}"
    else
      fail "$f missing {{PROJECT_NAME}} — init rename is a dead no-op; instance keeps the template's identity"
    fi
  done

  # CLAUDE.md additionally documents the stack via {{STACK}}.
  if grep -qF '{{STACK}}' CLAUDE.md; then
    pass "CLAUDE.md carries {{STACK}}"
  else
    fail "CLAUDE.md missing {{STACK}} — init stack substitution is dead"
  fi

  if grep -qF "$(printf '%s%s%s%s%s' '{' '{' TESTING '}' '}')" CLAUDE.md && grep -qE 's/\{\{TESTING\}\}/' scripts/init-project.sh; then
    pass "CLAUDE.md carries the TESTING placeholder and init substitutes it"
  else
    fail "CLAUDE.md Testing line is not substituted by init (REQ-308)"
  fi

  if grep -qF "$(printf '%s%s%s%s%s' '{' '{' PROFILE '}' '}')" CLAUDE.md && grep -qE 's/\{\{PROFILE\}\}/' scripts/init-project.sh; then
    pass "CLAUDE.md carries the PROFILE placeholder and init substitutes it"
  else
    fail "CLAUDE.md has no rendered profile line (H4)"
  fi
fi

# 2. Every required status-check context in configure-repo.sh must match an
#    actual workflow job name, otherwise branch protection requires checks that
#    never report and no PR can ever merge.
# `|| true`: with pipefail an empty match would abort the assignment before the
# guard below can report it; keep going so the explicit diagnostic fires.
contexts=$(grep -oE '"contexts": *\[[^]]*\]' scripts/configure-repo.sh \
           | grep -oE '"[^"]+"' | grep -vx '"contexts"' | tr -d '"' || true)
# Job-level `name:` lines are indented (workflow-level name: is at column 0;
# step names start with `- ` so they do not match this pattern).
jobnames=$(grep -hE '^[[:space:]]+name:' .github/workflows/*.yml \
           | sed -E 's/^[[:space:]]+name:[[:space:]]*//')

if [[ -z "$contexts" ]]; then
  fail "could not parse required contexts from scripts/configure-repo.sh"
fi
while IFS= read -r ctx; do
  [[ -z "$ctx" ]] && continue
  if grep -qxF "$ctx" <<<"$jobnames"; then
    pass "required check '$ctx' matches a workflow job name"
  else
    fail "required check '$ctx' matches no workflow job name — branch protection would block all merges"
  fi
done <<<"$contexts"

if [[ "$(tr '\n' ' ' <<<"$contexts")" == "gates verifier " ]]; then
  pass "required checks are exactly the stable ids gates and verifier (REQ-312)"
else
  fail "required checks are not exactly 'gates verifier': $(tr '\n' ' ' <<<"$contexts")"
fi

if [[ $FAIL -ne 0 ]]; then
  echo "test_template_instantiation: FAILED"
  exit 1
fi
echo "test_template_instantiation: all checks passed"
