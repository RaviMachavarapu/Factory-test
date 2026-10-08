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
  W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
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
# REQ-305: the demo release hook and its examples are gone.
for p in scripts/release-python-wheel.sh scripts/release-python-wheel.sh.example scripts/release-node-tarball.sh.example; do
  ck "$p removed" no test -e "$p"
done
ck "release contract template kept" test -f scripts/release-stack.sh.template
# git grep: tracked files only — a plain grep -r walks gitignored .claude/worktrees/* (nested checkouts) and fails on their copy of this test.
ck "no reference to release-python-wheel" no git grep -q release-python-wheel -- README.md CLAUDE.md scripts .claude docs/releases

# BL-001 (REQ-371, REQ-385): a session asks before gh pr merge and a push to main; the deny list is unchanged.
# Covers: REQ-371
# Covers: REQ-385
ck "$S: deny list is exactly the three Read rules; ask names gh pr merge and pushes to main (BL-001)" python3 - "$S" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))["permissions"]
assert p["deny"] == ["Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)"], p["deny"]
ask = p["ask"]
assert "Bash(gh pr merge:*)" in ask, ask
for r in ("Bash(git push origin main:*)", "Bash(git push -u origin main:*)", "Bash(git push --force-with-lease origin main:*)"):
    assert r in ask, (r, ask)
assert not set(ask) & set(p["deny"]), ask
PY

# BL-001, final review findings 4 and 8 (REQ-371, REQ-385): the ask rules match only `git push origin main ...`-shaped
# prefixes, so a PreToolUse Bash hook (scripts/lib/specflow/push_guard.py, the hook form BL-001 allows) resolves the
# destination of every `git push` — a bare push on main, -f/--force, HEAD:main, <src>:main, +main, refs/heads/main,
# :main, --all/--mirror, any remote name, an env prefix, `cd`/`-C`, `bash -c` — and asks when it is main; it also asks
# on every `gh pr merge`, env-prefixed or chained. It asks, never blocks (P5 R14: guided /next runs the merge after the
# user's yes), and a missing script never blocks a session (the settings command exits 0 without it). The hook is run
# for real against scratch repositories, through the exact command settings.json registers.
# Covers: REQ-371
# Covers: REQ-385
ck "$S: a PreToolUse Bash hook runs push_guard.py, guarded so a checkout without it exits 0" python3 - "$S" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
pre = [e for e in s["hooks"]["PreToolUse"] if e.get("matcher") == "Bash"]
assert len(pre) == 1, pre
cmds = [h["command"] for h in pre[0]["hooks"] if h["type"] == "command"]
assert len(cmds) == 1 and "scripts/lib/specflow/push_guard.py" in cmds[0] and "[ -f " in cmds[0], cmds
PY
PG="$(mktemp -d)"
git init -q -b main "$PG/m" && git -C "$PG/m" commit -q --allow-empty -m m
git init -q -b main "$PG/f" && git -C "$PG/f" commit -q --allow-empty -m f && git -C "$PG/f" checkout -q -b feat
git init -q -b main "$PG/u" && git -C "$PG/u" commit -q --allow-empty -m u && git -C "$PG/u" checkout -q -b topic
git -C "$PG/u" config branch.topic.remote origin && git -C "$PG/u" config branch.topic.merge refs/heads/main
cp -R "$PG/u" "$PG/s" && git -C "$PG/u" config push.default upstream   # s: the same tracking branch, push.default simple
cp -R "$PG/f" "$PG/x" && git -C "$PG/x" config push.default matching
pg_cmd=$(python3 -c 'import json,sys; print([e for e in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"] if e.get("matcher") == "Bash"][0]["hooks"][0]["command"])' "$S" 2>/dev/null || true)
pg_run() { # <cwd> <command> [project dir]: the registered hook's stdout
  python3 -c 'import json,sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "cwd": sys.argv[2]}))' "$2" "$1" >"$PG/in.json"
  CLAUDE_PROJECT_DIR="${3:-$ROOT}" bash -c "$pg_cmd" <"$PG/in.json"
}
pg_asks() { local o; o=$(pg_run "$1" "$2") && python3 -c 'import json,sys; d=json.loads(sys.argv[1])["hookSpecificOutput"]; assert d["hookEventName"] == "PreToolUse" and d["permissionDecision"] == "ask" and d["permissionDecisionReason"], d' "$o"; }
pg_silent() { local o rc=0; o=$(pg_run "$1" "$2" "${3:-$ROOT}") || rc=$?; [[ $rc -eq 0 && -z "$o" ]]; }
while IFS='|' read -r dir cmd; do
  [[ -n "$cmd" ]] && ck "push_guard asks ($dir): $cmd" pg_asks "$PG/$dir" "$cmd" </dev/null
done <<'CASES'
f|git push origin main
f|git push -u origin main
f|git push --force-with-lease origin main
f|git push -f origin main
f|git push --force origin main
f|git push origin HEAD:main
f|git push origin feat:main
f|git push origin main:main
f|git push origin +main
f|git push origin refs/heads/main
f|git push origin feat:refs/heads/main
f|git push --set-upstream upstream main
f|git push origin :main
f|git push --delete origin main
f|git push --all origin
f|git push --mirror origin
f|git status && git push origin main
f|git push origin feat; git push origin main
f|bash -c 'git push origin main'
f|cd ../m && git push
f|git -C ../m push
f|GIT_TRACE=0 git push origin main
m|git push
m|git push -u origin HEAD
m|git push origin HEAD
m|git push origin
m|git push origin @
u|git push
x|git push
f|gh pr merge 5 --squash
f|GH_TOKEN="$(gh auth token --user kpingali123)" gh pr merge 5 --squash --match-head-commit abc
f|gh pr merge 5 --merge && gh pr edit 6 --base main
f|GH_TOKEN=$(gh auth token) gh pr merge 7
f|gh -R Apps-Consultants/factory pr merge 5 --squash
f|gh pr --repo Apps-Consultants/factory merge 5
f|gh --repo=Apps-Consultants/factory pr merge 5
CASES
while IFS='|' read -r dir cmd; do
  [[ -n "$cmd" ]] && ck "push_guard is silent ($dir): $cmd" pg_silent "$PG/$dir" "$cmd" </dev/null
done <<'CASES'
f|git push -u origin feat
f|git push origin patch/main-x
f|git push origin domain
f|git push origin main-feature
f|git push
f|git push origin HEAD
f|git push --force-with-lease
f|git status
f|git log main
f|git checkout main
f|echo "git push origin main"
f|gh pr view 5
f|gh pr create --base main
m|git push origin feat
s|git push
CASES
ck "push_guard with no script in the project dir: exit 0, silent (a checkout without it never blocks)" pg_silent "$PG/m" "git push" "$PG"
ck "push_guard on malformed hook input: exit 0, silent" bash -c 'o=$(printf "not json" | python3 "$1/scripts/lib/specflow/push_guard.py") && [ -z "$o" ]' _ "$ROOT"
rm_tree "$PG"

finish test_tooling_hygiene
