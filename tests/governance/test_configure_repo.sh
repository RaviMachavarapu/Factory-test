#!/usr/bin/env bash
# REQ-312 (H7): configure-repo.sh reads solo through config.py, asks for zero approvals in solo mode and one in team
# mode, requires the stable checks gates and verifier, and says in plain English when GitHub refuses (HTTP 403).
# Covers: REQ-312
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
S="$W/stub"; stub_bin "$S"; D="$W/t"; copy_template "$D"; rm -f "$D/.specflow.yml" "$D/.stack"
cfg() { rm -f "$S/repo.json" "$S/protection.json" "$S/ruleset.json" "$S/environment.json" "$S/env-policy.json" "$S/gh.argv"; rc=0; out=$(cd "$D" && PATH="$S/bin:$PATH" STUB_DIR="$S" bash scripts/configure-repo.sh "$@" </dev/null 2>&1) || rc=$?; }
pj() { python3 -c 'import json, sys; p = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$S/protection.json" "$1"; }
cfg
ck "solo (the default): exit 0" [ "$rc" = 0 ]
ck "solo: zero required approvals" [ "$(pj 'p["required_pull_request_reviews"]["required_approving_review_count"]')" = 0 ]
ck "required checks are exactly gates and verifier" [ "$(pj 'p["required_status_checks"]["contexts"]')" = "['gates', 'verifier']" ]
ck "status checks are strict" [ "$(pj 'p["required_status_checks"]["strict"]')" = True ]
ck "stale approvals are dismissed" [ "$(pj 'p["required_pull_request_reviews"]["dismiss_stale_reviews"]')" = True ]
ck "solo: the last pusher's approval is not required (require_last_push_approval false or absent)" \
  [ "$(pj 'p["required_pull_request_reviews"].get("require_last_push_approval", False)')" = False ]
printf 'solo: false\n' > "$D/.specflow.yml"; cfg
ck "team: one required approval" [ "$(pj 'p["required_pull_request_reviews"]["required_approving_review_count"]')" = 1 ]
ck "team: the approval must come from someone other than the last pusher (require_last_push_approval, #33 third bootstrap)" \
  [ "$(pj 'p["required_pull_request_reviews"].get("require_last_push_approval")')" = True ]
export STUB_PROTECTION_STATUS=403; cfg; unset STUB_PROTECTION_STATUS
ck "HTTP 403: exit 3" [ "$rc" = 3 ]
ck "HTTP 403: says GitHub will not block merges" grep -qi 'will not block merges' <<<"$out"
ck "HTTP 403: says /next is the only gate" grep -qF '/next is the only gate' <<<"$out"
ck "HTTP 403: /next is here — no merge command without an APPROVE; the local gates; no 'later plan' (REQ-312)" \
  bash -c 'grep -qF "never prints a merge command" <<<"$1" && grep -qF "run-quality-gates.sh" <<<"$1" && ! grep -qiE "later plan|P5" <<<"$1"' _ "$out"
ck "the PUT body went to gh api on stdin (--input -)" bash -c 'grep -qx -- --input "$1" && grep -qx -- - "$1"' _ "$S/gh.argv"
export STUB_PROTECTION_STATUS=404; cfg; unset STUB_PROTECTION_STATUS
ck "another failure: exit 1 with manual steps naming gates and verifier" bash -c '[ "$1" = 1 ] && grep -q gates <<<"$2" && grep -q verifier <<<"$2"' _ "$rc" "$out"
cfg --dry-run
ck "--dry-run prints the request and calls no API" bash -c '[ "$1" = 0 ] && grep -q "\"gates\"" <<<"$2" && ! grep -qx api "$3"' _ "$rc" "$out" "$S/gh.argv"
ck "no legacy check names remain" no grep -qE 'Quality gates \(pytest|Verifier findings posted' scripts/configure-repo.sh
ck "solo is read through config.py (REQ-301)" grep -qF 'scripts/lib/specflow/config.py' scripts/configure-repo.sh
ck "the literal contexts stay in the source (test_template_instantiation.sh check 2 greps them)" grep -qF '"contexts": ["gates", "verifier"]' scripts/configure-repo.sh
ck "the summary says admins can still merge past the checks (enforce_admins: false)" bash -c 'cd "$1" && PATH="$2/bin:$PATH" STUB_DIR="$2" bash scripts/configure-repo.sh </dev/null 2>&1 | grep -qi admin' _ "$D" "$S"
export STUB_PROTECTION_STATUS=403; cfg; unset STUB_PROTECTION_STATUS
ck "HTTP 403: the merge command /next prints is bound to the attested head (--match-head-commit), and says what that does not stop" \
  bash -c 'grep -qF -- "--match-head-commit" <<<"$1" && grep -qi "nothing stops a merge you type yourself" <<<"$1"' _ "$out"
# P6 Task 1.4 (REQ-383 as amended; dfe-12): configure-repo.sh also requests a tag ruleset restricting v* tags to admins,
# updates an existing one in place, says in plain English when GitHub refuses it, and --check-ruleset reports it.
# Covers: REQ-383
cfg
ck "a tag ruleset is requested: tag target, active, refs/tags/v*, creation/update/deletion/non-fast-forward, admins bypass" python3 - "$S/ruleset.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
assert p["name"] == "release tags" and p["target"] == "tag" and p["enforcement"] == "active", p
assert p["conditions"]["ref_name"]["include"] == ["refs/tags/v*"], p
assert {r["type"] for r in p["rules"]} == {"creation", "update", "deletion", "non_fast_forward"}, p
assert p["bypass_actors"] == [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}], p
PY
ck "…sent with POST to repos/o/r/rulesets when none of that name exists" bash -c 'grep -qx POST "$1" && grep -qx "repos/o/r/rulesets" "$1"' _ "$S/gh.argv"
export STUB_RULESETS='[{"id": 42, "name": "release tags"}]'; cfg; unset STUB_RULESETS
ck "an existing 'release tags' ruleset is updated in place (PUT repos/o/r/rulesets/42), never duplicated" \
  bash -c 'grep -qx PUT "$1" && grep -qx "repos/o/r/rulesets/42" "$1" && ! grep -x -A1 POST "$1" | grep -qx "repos/o/r/rulesets"' _ "$S/gh.argv"
export STUB_RULESET_STATUS=403; cfg; unset STUB_RULESET_STATUS
ck "ruleset HTTP 403: exit 3; anyone with write access can push a v* tag; release.yml binds only tags on reviewed commits — the ruleset is the control (P6 R31)" \
  bash -c '[ "$1" = 3 ] && grep -qF "GitHub refused the tag ruleset" <<<"$2" && grep -qF "bind only a tag on a reviewed commit" <<<"$2" && grep -qF "the ruleset is the control" <<<"$2" && ! grep -qF "still refuses" <<<"$2"' _ "$rc" "$out"
cfg --check-ruleset
ck "--check-ruleset with none: 'ruleset: absent', exit 1, nothing written" \
  bash -c '[ "$1" = 1 ] && grep -qx "ruleset: absent" <<<"$2" && [ ! -e "$3" ]' _ "$rc" "$out" "$S/ruleset.json"
RS_OK='{"id": 42, "name": "release tags", "target": "tag", "enforcement": "active", "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}}, "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}, {"type": "non_fast_forward"}], "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]}'
export STUB_RULESETS='[{"id": 42, "name": "release tags"}]' STUB_RULESET="$RS_OK"; cfg --check-ruleset
ck "--check-ruleset with one as requested (read by id): 'ruleset: present (id 42)', exit 0" bash -c '[ "$1" = 0 ] && grep -qx "ruleset: present (id 42)" <<<"$2"' _ "$rc" "$out"
# Build 1 final review (REQ-383; P6 R14, R31): the reader fails closed — a ruleset named 'release tags' that does not
# enforce the requested body is 'present but ineffective', exit 3, which /release records like an absent one.
rs() { python3 -c 'import json, sys; b = json.loads(sys.argv[1]); exec(sys.argv[2]); print(json.dumps(b))' "$RS_OK" "$1"; }
for c in 'b["enforcement"] = "disabled"|enforcement' 'b["enforcement"] = "evaluate"; b["target"] = "branch"|enforcement'   'b["conditions"]["ref_name"]["include"] = ["refs/tags/*"]|include' 'b["rules"] = b["rules"][:2]|rules'   'b["bypass_actors"].append({"actor_id": 2, "actor_type": "RepositoryRole", "bypass_mode": "always"})|bypass'; do
  STUB_RULESET=$(rs "${c%|*}"); export STUB_RULESET; cfg --check-ruleset
  ck "--check-ruleset: a 'release tags' ruleset whose ${c##*|} differs from the request is present but ineffective, exit 3" \
    bash -c '[ "$1" = 3 ] && grep -q "^ruleset: present but ineffective (id 42: .*$3" <<<"$2"' _ "$rc" "$out" "${c##*|}"
done
unset STUB_RULESET; cfg --check-ruleset
ck "--check-ruleset: the ruleset is listed but cannot be read by id: unreadable, exit 2" bash -c '[ "$1" = 2 ] && grep -q "^ruleset: unreadable" <<<"$2"' _ "$rc" "$out"
unset STUB_RULESETS
cfg --dry-run
ck "--dry-run prints the ruleset and environment bodies as well, and calls no API" \
  bash -c 'grep -qF "refs/tags/v*" <<<"$1" && grep -qF "custom_branch_policies" <<<"$1" && ! grep -qx api "$2"' _ "$out" "$S/gh.argv"
# P6 Task 1.4 (REQ-386; P6 R32, R35; art-secrets-hygiene): the Apple secrets' environment — release, admitting only v*
# tags — requested beside the ruleset, refused in plain English, and --check-environment reports it.
# Covers: REQ-386
cfg
ck "the release environment is requested with custom deployment policies, and its one policy admits tags v*" \
  bash -c 'python3 -c "import json, sys; e = json.load(open(sys.argv[1])); assert e[\"deployment_branch_policy\"] == {\"protected_branches\": False, \"custom_branch_policies\": True}, e" "$1" && python3 -c "import json, sys; p = json.load(open(sys.argv[1])); assert p == {\"name\": \"v*\", \"type\": \"tag\"}, p" "$2"' _ "$S/environment.json" "$S/env-policy.json"
export STUB_ENV_STATUS=403; cfg; unset STUB_ENV_STATUS
ck "environment HTTP 403 (a free private repository): exit 3, saying environment secrets are unavailable and bundles ship unsigned" \
  bash -c '[ "$1" = 3 ] && grep -qF "GitHub refused the release environment" <<<"$2" && grep -qF "ship unsigned" <<<"$2"' _ "$rc" "$out"
cfg --check-environment
ck "--check-environment with none: 'environment release: absent', exit 1, nothing written" \
  bash -c '[ "$1" = 1 ] && grep -qx "environment release: absent" <<<"$2" && [ ! -e "$3" ]' _ "$rc" "$out" "$S/environment.json"
ENV_OK='{"name": "release", "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}'
POL_OK='{"total_count": 1, "branch_policies": [{"name": "v*", "type": "tag"}]}'
export STUB_ENV="$ENV_OK" STUB_ENV_POLICIES="$POL_OK"; cfg --check-environment
ck "--check-environment with it: 'environment release: present (tag policy v*)', exit 0" \
  bash -c '[ "$1" = 0 ] && grep -qxF "environment release: present (tag policy v*)" <<<"$2"' _ "$rc" "$out"
# Build 1 final review (REQ-386; P6 R32): the reader fails closed — another policy beside v* (a '*' branch policy admits
# every branch to the Apple secrets), protected-branches deployment, or no custom policies is present but ineffective.
export STUB_ENV_POLICIES='{"total_count": 2, "branch_policies": [{"name": "v*", "type": "tag"}, {"name": "*", "type": "branch"}]}'; cfg --check-environment
ck "--check-environment: a '*' branch policy beside v*: present but ineffective, exit 3" \
  bash -c '[ "$1" = 3 ] && grep -q "^environment release: present but ineffective (.*\*" <<<"$2"' _ "$rc" "$out"
export STUB_ENV_POLICIES="$POL_OK" STUB_ENV='{"name": "release", "deployment_branch_policy": {"protected_branches": true, "custom_branch_policies": false}}'; cfg --check-environment
ck "--check-environment: protected-branches deployment (no custom policies): present but ineffective, exit 3" \
  bash -c '[ "$1" = 3 ] && grep -q "^environment release: present but ineffective" <<<"$2"' _ "$rc" "$out"
export STUB_ENV='{"name": "release", "deployment_branch_policy": null}'; cfg --check-environment
ck "--check-environment: no deployment policy at all (every branch may deploy): present but ineffective, exit 3" \
  bash -c '[ "$1" = 3 ] && grep -q "^environment release: present but ineffective" <<<"$2"' _ "$rc" "$out"
export STUB_ENV="$ENV_OK" STUB_ENV_POLICIES='{"total_count": 0, "branch_policies": []}'; cfg --check-environment
ck "--check-environment: no v* tag policy: present but ineffective, exit 3" \
  bash -c '[ "$1" = 3 ] && grep -q "^environment release: present but ineffective" <<<"$2"' _ "$rc" "$out"
unset STUB_ENV STUB_ENV_POLICIES
# Build 1 final review (REQ-386): only HTTP 403 is the plan limitation; a 404 (a token that is not an admin's) or a 422
# (a rejected body) on the environment is an error — exit 1 with the API's message, never "secrets are unavailable".
for code in 404 422; do
  export STUB_ENV_STATUS=$code; cfg; unset STUB_ENV_STATUS
  ck "environment HTTP $code: exit 1, an error naming the API's answer, not the plan limitation" \
    bash -c '[ "$1" = 1 ] && grep -qF "ERROR: Failed to set the release environment" <<<"$2" && grep -qF "HTTP $3" <<<"$2" && ! grep -qF "environment secrets are unavailable" <<<"$2"' _ "$rc" "$out" "$code"
done
# Fix wave 2 (REQ-383, REQ-386; C7): gh output is parsed with python3, never --jq; a non-403 failure of the ruleset or
# environment request exits 1 even beside a 403 elsewhere (never masked to 3); an existing v* policy is not POSTed again;
# team mode names the authenticated user (gh api user) as the release environment's reviewer, and fails closed when it
# cannot be read.
ck "configure-repo.sh parses gh output with python3: no --jq and no -q filter" \
  no grep -qE -- '--jq|[[:space:]]-q[[:space:]]+\.' scripts/configure-repo.sh
export STUB_RULESET_STATUS=404 STUB_ENV_STATUS=403; cfg; unset STUB_RULESET_STATUS STUB_ENV_STATUS
ck "a ruleset error (404) beside an environment 403: exit 1 — the error is never masked to 3" \
  bash -c '[ "$1" = 1 ] && grep -qF "ERROR: Failed to set the tag ruleset" <<<"$2"' _ "$rc" "$out"
export STUB_PROTECTION_STATUS=403 STUB_ENV_STATUS=422; cfg; unset STUB_PROTECTION_STATUS STUB_ENV_STATUS
ck "branch protection 403 beside an environment error (422): exit 1" bash -c '[ "$1" = 1 ] && grep -qF "ERROR: Failed to set the release environment" <<<"$2"' _ "$rc" "$out"
export STUB_PROTECTION_STATUS=403 STUB_RULESET_STATUS=404 STUB_ENV_STATUS=403; cfg; unset STUB_PROTECTION_STATUS STUB_RULESET_STATUS STUB_ENV_STATUS
ck "branch protection 403, a ruleset error, an environment 403: exit 1" [ "$rc" = 1 ]
export STUB_RULESETS_STATUS=502; cfg; unset STUB_RULESETS_STATUS
ck "the ruleset list cannot be read (HTTP 502): exit 1, an error, and no ruleset is POSTed blind (no duplicate)" \
  bash -c '[ "$1" = 1 ] && grep -qF "ERROR" <<<"$2" && [ ! -e "$3" ]' _ "$rc" "$out" "$S/ruleset.json"
export STUB_RULESETS_STATUS=403; cfg; unset STUB_RULESETS_STATUS
ck "the ruleset list refused (HTTP 403): the plan-limit text, exit 3, nothing POSTed" \
  bash -c '[ "$1" = 3 ] && grep -qF "GitHub refused the tag ruleset" <<<"$2" && [ ! -e "$3" ]' _ "$rc" "$out" "$S/ruleset.json"
export STUB_ENV_POLICIES='{"total_count": 1, "branch_policies": [{"name": "v*", "type": "tag"}]}'; cfg; unset STUB_ENV_POLICIES
ck "the v* tag policy already exists: exit 0 and no POST to deployment-branch-policies" \
  bash -c '[ "$1" = 0 ] && [ ! -e "$2" ] && ! grep -x -A1 POST "$3" | grep -qx "repos/o/r/environments/release/deployment-branch-policies"' _ "$rc" "$S/env-policy.json" "$S/gh.argv"
export STUB_ENV_POLICIES_STATUS=502; cfg; unset STUB_ENV_POLICIES_STATUS
ck "the environment's policies cannot be read (HTTP 502): exit 1, an error, and no policy is POSTed blind" \
  bash -c '[ "$1" = 1 ] && grep -qF "ERROR" <<<"$2" && [ ! -e "$3" ]' _ "$rc" "$out" "$S/env-policy.json"
printf 'solo: false\n' > "$D/.specflow.yml"; cfg
ck "team mode: the release environment's reviewer is the authenticated user (gh api user, parsed with python3)" python3 - "$S/environment.json" <<'PY2'
import json, sys
e = json.load(open(sys.argv[1]))
assert e.get("reviewers") == [{"type": "User", "id": 4242}], e
PY2
export STUB_USER_RC=1; cfg; unset STUB_USER_RC
ck "team mode, the authenticated user cannot be read: exit 1, an error — never an environment without its reviewer" \
  bash -c '[ "$1" = 1 ] && grep -qF "ERROR" <<<"$2" && [ ! -e "$3" ]' _ "$rc" "$out" "$S/environment.json"
rm -f "$D/.specflow.yml"
# Build 3 re-review (REQ-350, REQ-312; P6 R28): the tag-time re-check judges a rebase merge's earlier commits as direct
# pushes, so the factory merges by squash or merge commit — configure-repo.sh disables rebase-merge on the repository
# (PATCH repos/<owner>/<repo>, squash and merge commits left on), reports it, and handles 403/non-403 as its other requests.
# Covers: REQ-350, REQ-312
cfg
ck "rebase-merge is disabled: PATCH repos/o/r with allow_rebase_merge false, squash and merge commits left true" \
  bash -c 'python3 -c "import json, sys; b = json.load(open(sys.argv[1])); assert b == {\"allow_rebase_merge\": False, \"allow_squash_merge\": True, \"allow_merge_commit\": True}, b" "$1" && grep -qx PATCH "$2" && grep -qx "repos/o/r" "$2"' _ "$S/repo.json" "$S/gh.argv"
ck "…exit 0, and the summary says rebase-merge is disabled (squash or merge commit only)" \
  bash -c '[ "$1" = 0 ] && grep -qF "Merge methods: rebase-merge disabled (squash or merge commit only)" <<<"$2"' _ "$rc" "$out"
export STUB_REPO_STATUS=403; cfg; unset STUB_REPO_STATUS
ck "merge methods HTTP 403: exit 3, the plan's convention residual — a rebase-merged code commit needs a commit-level waiver at the tag" \
  bash -c '[ "$1" = 3 ] && grep -qF "GitHub refused to disable rebase-merge" <<<"$2" && grep -qF "convention" <<<"$2" && grep -qF "commit-level waiver" <<<"$2" && ! grep -qF "Merge methods: rebase-merge disabled" <<<"$2"' _ "$rc" "$out"
export STUB_REPO_STATUS=404; cfg; unset STUB_REPO_STATUS
ck "merge methods HTTP 404: exit 1, an error naming the API's answer" \
  bash -c '[ "$1" = 1 ] && grep -qF "ERROR: Failed to disable rebase-merge" <<<"$2" && grep -qF "HTTP 404" <<<"$2"' _ "$rc" "$out"
export STUB_REPO_STATUS=404 STUB_ENV_STATUS=403; cfg; unset STUB_REPO_STATUS STUB_ENV_STATUS
ck "a merge-methods error beside an environment 403: exit 1 — never masked to 3" [ "$rc" = 1 ]
cfg --dry-run
ck "--dry-run prints the merge-methods body and calls no API" bash -c 'grep -qF "\"allow_rebase_merge\": false" <<<"$1" && ! grep -qx api "$2"' _ "$out" "$S/gh.argv"
finish test_configure_repo
