#!/usr/bin/env bash
# Configure GitHub branch protection for the SpecFlow v3.2 workflow, the 'release tags' ruleset, the 'release'
# environment (P6 R14, R31, R32) and the merge methods — rebase-merge disabled (P6 R28).
# Requires: gh CLI authenticated with admin scope. gh output is parsed with python3, never with a jq filter.
# Replaces any previously required contexts (the migration from the pre-v3.2 check names).
# Exit: 0 all configured; 3 GitHub refused one or more requests with HTTP 403 (the plan limit, said in plain English);
# 1 any other failure — it outranks 3, so an error is never masked by a 403 elsewhere. --check-ruleset and
# --check-environment have their own codes (below). Team mode names the authenticated gh user (gh api user) as the
# release environment's reviewer; other maintainers are added by hand in Settings -> Environments.
set -euo pipefail

DRY_RUN=0
CHECK=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --check-ruleset) CHECK=ruleset ;;
    --check-environment) CHECK=environment ;;
  esac
done

manual_steps() {
  echo ""
  echo "Manual setup instructions:"
  echo "  Go to Settings -> Branches -> Add rule for 'main':"
  echo "    - Require pull request reviews"
  echo "    - Require status checks to pass: \"gates\" and \"verifier\""
  echo "    - Restrict direct pushes to repo admins only"
}

REPO=$(gh repo view --json nameWithOwner 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["nameWithOwner"])
except (ValueError, KeyError, TypeError):
    pass
' || true)
if [ -z "$REPO" ]; then
  echo "ERROR: Not in a GitHub repository or gh CLI not authenticated."
  manual_steps
  exit 1
fi

SOLO=$(python3 scripts/lib/specflow/config.py get solo --default true)
if [ "$SOLO" = "true" ]; then
  APPROVALS=0
else
  APPROVALS=1
fi

# Tag ruleset (P6 R14, R31): only admins (role 5) create, move or delete v* tags.
RULESET_BODY=$(python3 -c '
import json
print(json.dumps({
    "name": "release tags",
    "target": "tag",
    "enforcement": "active",
    "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
    "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}, {"type": "non_fast_forward"}],
    "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
}))
')

# Release environment (P6 R32, R35): the Apple secrets live here, reachable only from v* tags.
# env_body [REVIEWER_ID] — team mode adds the reviewer when one is known.
env_body() {
  python3 -c '
import json, sys
b = {"deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}}
if len(sys.argv) > 1 and sys.argv[1]:
    b["reviewers"] = [{"type": "User", "id": int(sys.argv[1])}]
print(json.dumps(b))
' "$@"
}
POLICY_BODY='{"name": "v*", "type": "tag"}'
# Merge methods (P6 R28): the tag-time re-check judges a rebase merge's earlier commits as direct pushes, so the factory
# merges by squash or merge commit — rebase-merge is disabled on the repository, the other two left on.
MERGE_BODY='{"allow_rebase_merge": false, "allow_squash_merge": true, "allow_merge_commit": true}'

# ruleset_id — prints the id of the 'release tags' ruleset ("" when none); returns 1 when the list is unreadable.
ruleset_id() {
  local out
  out=$(gh api "repos/$REPO/rulesets" 2>&1) || { printf '%s' "$out"; return 1; }
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    rs = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
for r in rs if isinstance(rs, list) else []:
    if r.get("name") == "release tags":
        print(r.get("id", ""))
        break
'
}

# env_policy_state — prints present | absent for the v* tag policy (the write path: POST it when absent); prints gh's
# answer and returns 1 when the policies cannot be read, so the caller never POSTs blind.
env_policy_state() {
  local out
  out=$(gh api "repos/$REPO/environments/release/deployment-branch-policies" 2>&1) || { printf '%s' "$out"; return 1; }
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    print("the deployment policies are not JSON"); sys.exit(1)
print("present" if any(p.get("name") == "v*" and p.get("type") == "tag" for p in d.get("branch_policies") or []) else "absent")
'
}

# limited — record a plan limitation (HTTP 403): exit 3, unless an error (exit 1) is already recorded.
limited() { if [ "$FINAL_RC" != 1 ]; then FINAL_RC=3; fi; }

# The readers fail closed (Build 1 final review): "present" only when GitHub holds exactly what this script requests.
# --check-ruleset:     ruleset: present (id N) | present but ineffective (id N: <why>) | absent | unreadable (<why>);
#                      exit 0 | 3 | 1 | 2.
# --check-environment: environment release: present (tag policy v*) | present but ineffective (<why>) | absent |
#                      unreadable (<why>); exit 0 | 3 | 1 | 2. Neither changes anything.
if [ "$CHECK" = ruleset ]; then
  if ! id=$(ruleset_id); then
    echo "ruleset: unreadable ($(printf '%s' "$id" | head -n 1))"
    exit 2
  fi
  if [ -z "$id" ]; then echo "ruleset: absent"; exit 1; fi
  if ! rout=$(gh api "repos/$REPO/rulesets/$id" 2>&1); then
    echo "ruleset: unreadable (id $id: $(printf '%s' "$rout" | head -n 1))"
    exit 2
  fi
  why=$(printf '%s' "$rout" | python3 -c '
import json, sys
want = json.loads(sys.argv[1])
try:
    r = json.load(sys.stdin)
except ValueError:
    print("unreadable: the ruleset is not JSON"); sys.exit(0)
bad = []
if r.get("enforcement") != "active":
    bad.append("enforcement is %s, not active" % r.get("enforcement"))
if r.get("target") != "tag":
    bad.append("target is %s, not tag" % r.get("target"))
ref = (r.get("conditions") or {}).get("ref_name") or {}
if ref.get("include") != ["refs/tags/v*"] or (ref.get("exclude") or []) != []:
    bad.append("include is %s and exclude %s, not exactly refs/tags/v*" % (ref.get("include"), ref.get("exclude")))
have = {x.get("type") for x in r.get("rules") or []}
need = {x["type"] for x in want["rules"]}
if not need <= have:
    bad.append("rules lack " + ", ".join(sorted(need - have)))
actors = sorted((a.get("actor_id"), a.get("actor_type")) for a in r.get("bypass_actors") or [])
if actors != [(5, "RepositoryRole")]:
    bad.append("bypass actors are %s, not admins (RepositoryRole 5) alone" % actors)
print("; ".join(bad))
' "$RULESET_BODY")
  case "$why" in
    "") echo "ruleset: present (id $id)"; exit 0 ;;
    unreadable:*) echo "ruleset: unreadable (id $id: ${why#unreadable: })"; exit 2 ;;
    *) echo "ruleset: present but ineffective (id $id: $why)"; exit 3 ;;
  esac
fi

if [ "$CHECK" = environment ]; then
  if ! eout=$(gh api "repos/$REPO/environments/release" 2>&1); then
    if grep -qi 'HTTP 404' <<<"$eout"; then echo "environment release: absent"; exit 1; fi
    echo "environment release: unreadable ($(printf '%s' "$eout" | head -n 1))"
    exit 2
  fi
  if ! pout=$(gh api "repos/$REPO/environments/release/deployment-branch-policies" 2>&1); then
    echo "environment release: unreadable (its deployment policies: $(printf '%s' "$pout" | head -n 1))"
    exit 2
  fi
  why=$(python3 -c '
import json, sys
try:
    e, p = json.loads(sys.argv[1]), json.loads(sys.argv[2])
except ValueError:
    print("unreadable: not JSON"); sys.exit(0)
bad = []
dbp = e.get("deployment_branch_policy")
if dbp != {"protected_branches": False, "custom_branch_policies": True}:
    bad.append("deployment_branch_policy is %s, not custom policies only" % json.dumps(dbp))
pol = sorted((x.get("name"), x.get("type")) for x in p.get("branch_policies") or [])
if pol != [("v*", "tag")]:
    bad.append("its policies are %s, not exactly the v* tag policy" % (", ".join("%s (%s)" % x for x in pol) or "none"))
print("; ".join(bad))
' "$eout" "$pout")
  case "$why" in
    "") echo "environment release: present (tag policy v*)"; exit 0 ;;
    unreadable:*) echo "environment release: unreadable (${why#unreadable: })"; exit 2 ;;
    *) echo "environment release: present but ineffective ($why)"; exit 3 ;;
  esac
fi

BODY=$(python3 -c '
import json, sys
approvals = int(sys.argv[1])
print(json.dumps({
    "required_status_checks": {
        "strict": True,
        "contexts": ["gates", "verifier"],
    },
    "enforce_admins": False,
    "required_pull_request_reviews": {
        "required_approving_review_count": approvals,
        "dismiss_stale_reviews": True,
        # Team mode: the approval must come from someone other than the last
        # pusher, so pushing onto the PR of another person cannot self-approve it.
        "require_last_push_approval": approvals > 0,
    },
    "restrictions": None,
}))
' "$APPROVALS")

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run: would PUT this to repos/$REPO/branches/main/protection:"
  echo "$BODY"
  echo "Dry run: would POST (or PUT by id) this to repos/$REPO/rulesets:"
  echo "$RULESET_BODY"
  echo "Dry run: would PUT this to repos/$REPO/environments/release (team mode adds the authenticated maintainer as reviewer):"
  env_body
  echo "Dry run: would POST this to repos/$REPO/environments/release/deployment-branch-policies when absent:"
  echo "$POLICY_BODY"
  echo "Dry run: would PATCH this to repos/$REPO (merge methods):"
  echo "$MERGE_BODY"
  exit 0
fi

echo "Configuring branch protection for $REPO (solo=$SOLO, approvals=$APPROVALS)..."

FINAL_RC=0
API_OUT=$(printf '%s' "$BODY" | gh api --method PUT "repos/$REPO/branches/main/protection" --input - 2>&1) && API_RC=0 || API_RC=$?

PROTECTED=1
if [ "$API_RC" != 0 ]; then
  if grep -qi 'HTTP 403' <<<"$API_OUT"; then
    echo "GitHub refused branch protection for $REPO (HTTP 403: a private repository on the free plan cannot use it)."
    echo "GitHub will not block merges: nothing server-side stops a merge without a verifier APPROVE or a review."
    echo "/next is the only gate: it never prints a merge command until an APPROVE marker (or a maintainer waiver) for the current head exists."
    echo "The merge command it prints carries --match-head-commit <head>, so gh refuses it once the head has moved past the attested one."
    echo "Run bash scripts/run-quality-gates.sh locally before every merge; nothing stops a merge you type yourself."
    echo "For server-side enforcement make the repository public or upgrade the plan, then re-run this script."
    limited
    PROTECTED=0
  else
    echo "ERROR: Failed to set branch protection. You may lack admin permissions."
    echo "$API_OUT"
    manual_steps
    exit 1
  fi
fi

# Tag ruleset: POST, or PUT by id when a ruleset named 'release tags' exists. The list is read first; when it cannot be
# read nothing is POSTed blind (a duplicate ruleset), and the failure is reported like the write's.
RULESET_OK=1
if rid=$(ruleset_id); then
  if [ -n "$rid" ]; then
    R_OUT=$(printf '%s' "$RULESET_BODY" | gh api --method PUT "repos/$REPO/rulesets/$rid" --input - 2>&1) && R_RC=0 || R_RC=$?
  else
    R_OUT=$(printf '%s' "$RULESET_BODY" | gh api --method POST "repos/$REPO/rulesets" --input - 2>&1) && R_RC=0 || R_RC=$?
  fi
else
  R_OUT="${rid:-the rulesets list is not JSON}"; R_RC=1
fi
if [ "$R_RC" != 0 ]; then
  RULESET_OK=0
  if grep -qi 'HTTP 403' <<<"$R_OUT"; then
    echo "GitHub refused the tag ruleset for $REPO (HTTP 403: $(printf '%s' "$R_OUT" | head -n 1)); anyone with write access can push a v* tag."
    echo "release.yml's refusals bind only a tag on a reviewed commit (one that carries main's release.yml): a tag on any other commit runs that commit's own release.yml, which can skip every check — the ruleset is the control (P6 R31)."
    limited
  else
    echo "ERROR: Failed to set the tag ruleset."
    echo "$R_OUT"
    FINAL_RC=1  # an error outranks a plan limitation (3)
  fi
fi

# Release environment: PUT, then the v* tag policy when absent. Team mode adds the caller (the authenticated gh
# user who runs this script, a maintainer — `gh api user`, parsed with python3) as the required reviewer; other
# maintainers are added by hand. An unreadable user fails closed: no environment without its reviewer.
ENV_OK=1
REVIEWER=""
E_RC=0; E_OUT=""
if [ "$APPROVALS" != 0 ]; then
  U_OUT=$(gh api user 2>&1) && U_RC=0 || U_RC=$?
  REVIEWER=$(printf '%s' "$U_OUT" | python3 -c '
import json, sys
try:
    i = json.load(sys.stdin).get("id")
except (ValueError, AttributeError):
    i = None
print(i if isinstance(i, int) and not isinstance(i, bool) else "")
' 2>/dev/null || true)
  if [ "$U_RC" != 0 ] || [ -z "$REVIEWER" ]; then
    E_RC=1; E_OUT="the authenticated user (gh api user) cannot be read, so team mode has no reviewer for the release environment — nothing was changed: $(printf '%s' "$U_OUT" | head -n 1)"
  fi
fi
if [ "$E_RC" = 0 ]; then
  E_OUT=$(env_body "$REVIEWER" | gh api --method PUT "repos/$REPO/environments/release" --input - 2>&1) && E_RC=0 || E_RC=$?
fi
if [ "$E_RC" = 0 ]; then
  if pstate=$(env_policy_state); then
    if [ "$pstate" != present ]; then
      E_OUT=$(printf '%s' "$POLICY_BODY" | gh api --method POST "repos/$REPO/environments/release/deployment-branch-policies" --input - 2>&1) && E_RC=0 || E_RC=$?
    fi
  else
    E_RC=1; E_OUT="the release environment's deployment policies cannot be read, so no policy was added: $pstate"
  fi
fi
if [ "$E_RC" != 0 ]; then
  ENV_OK=0
  if grep -qi 'HTTP 403' <<<"$E_OUT"; then
    echo "GitHub refused the release environment for $REPO (HTTP 403: $(printf '%s' "$E_OUT" | head -n 1)); environment secrets are unavailable — the Apple secrets cannot be stored safely and bundles ship unsigned (P6 R32)."
    limited
  else
    # A 404 (a token that cannot administer the repository) or a 422 (a rejected body) is an error, not the plan limit.
    echo "ERROR: Failed to set the release environment."
    echo "$E_OUT"
    FINAL_RC=1  # an error outranks a plan limitation (3)
  fi
fi

# Merge methods: PATCH the repository (P6 R28). A 403 is recorded like the other plan limitations; any other failure is
# an error that outranks it.
MERGE_OK=1
M_OUT=$(printf '%s' "$MERGE_BODY" | gh api --method PATCH "repos/$REPO" --input - 2>&1) && M_RC=0 || M_RC=$?
if [ "$M_RC" != 0 ]; then
  MERGE_OK=0
  if grep -qi 'HTTP 403' <<<"$M_OUT"; then
    echo "GitHub refused to disable rebase-merge for $REPO (HTTP 403: $(printf '%s' "$M_OUT" | head -n 1)); merging by squash or merge commit stays a convention (P6 R28): the tag-time re-check judges a rebase merge's earlier commits as direct pushes, so a rebase-merged code commit needs a commit-level waiver before the tag."
    limited
  else
    echo "ERROR: Failed to disable rebase-merge."
    echo "$M_OUT"
    FINAL_RC=1  # an error outranks a plan limitation (3)
  fi
fi

if [ "$PROTECTED" = 1 ]; then
  echo "Branch protection configured for main:"
  if [ "$APPROVALS" = 0 ]; then
    echo "  - Require 0 PR review approvals (solo mode)"
  else
    echo "  - Require $APPROVALS PR review approval(s) (team mode)"
  fi
  echo "  - Require gates and verifier status checks"
  echo "  - A PR is still required to merge"
  echo "  - Repository admins (a solo owner is one) can still merge past red checks because enforce_admins is false"
fi
if [ "$RULESET_OK" = 1 ]; then
  echo "Tag ruleset 'release tags': only admins create, move or delete v* tags"
fi
if [ "$ENV_OK" = 1 ]; then
  echo "Environment 'release': the Apple signing secrets live here, reachable only from v* tags"
fi
if [ "$MERGE_OK" = 1 ]; then
  echo "Merge methods: rebase-merge disabled (squash or merge commit only)"
fi
exit "$FINAL_RC"
