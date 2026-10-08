#!/usr/bin/env bash
# BL-021: scripts/run-instance-tests.sh runs the new or changed governance tests inside a
# scaffolded instance, prints every instance SKIP, and fails when any test fails there.
# Fixture: a scratch template repository gains one test that SKIPs in an instance and one
# that fails; the script runs against it (SPECFLOW_NO_SCAFFOLD=1 keeps the init fast).
# Covers: REQ-360, REQ-306
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
# Final review finding 2: the script ships to every instance (init removes only the template's own pack files), so
# there it must refuse plainly instead of failing inside init-project.sh. Run here in an instance, and in the
# template source against a scratch instance scaffolded by init-project.sh; the glossary keeps the script out of
# its instance-facing "Factory documents" paragraph and the README marks it template-source only.
refuses_in() { # <dir>: the script refuses, exit 2, naming "template source only"
  local rc=0 out; out=$(cd "$1" && bash scripts/run-instance-tests.sh 2>&1) || rc=$?
  [[ $rc -eq 2 ]] && grep -qF 'template source only' <<<"$out" && ! grep -qF 'init-project.sh' <<<"$out"
}
ck "GLOSSARY: the Factory documents paragraph does not advertise run-instance-tests.sh" \
  bash -c '! awk "/^### Factory documents/{p=1;next} /^### /{p=0} p" docs/GLOSSARY.md | grep -qF run-instance-tests'
ck "GLOSSARY: the Governance test entry names run-instance-tests.sh as template source only" \
  bash -c 'awk "/^### Governance test/{p=1;next} /^### /{p=0} p" docs/GLOSSARY.md | tr "\n" " " | grep -F run-instance-tests | grep -qiF "template source only"'
ck "README: the run-instance-tests.sh row says template source only" \
  bash -c 'grep -F "scripts/run-instance-tests.sh" README.md | grep -qiF "template source only"'
if instance; then
  ck "in this instance, run-instance-tests.sh refuses: exit 2, 'template source only', init never run" refuses_in "$ROOT"
  finish test_run_instance_tests; exit 0
fi
ck "the script exists" test -f scripts/run-instance-tests.sh
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT
I="$WORK/inst"; copy_template "$I"
(cd "$I" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Acme --stack python --profile engineer --path lanes --solo true </dev/null >/dev/null 2>&1)
ck "in a scaffolded instance, run-instance-tests.sh refuses: exit 2, 'template source only', init never run" refuses_in "$I"
S="$WORK/tpl"; copy_template "$S"
git -C "$S" init -q -b main && git -C "$S" add -A && git -C "$S" commit -q -m base
BASE=$(git -C "$S" rev-parse HEAD)
cat > "$S/tests/governance/test_zz_fixture_skip.sh" <<'T'
#!/usr/bin/env bash
if [[ -f .specflow.yml ]]; then echo "SKIP fixture-skip: not applicable in an instance"; fi
echo "fixture-skip ran in $(basename "$PWD")"; exit 0
T
cat > "$S/tests/governance/test_zz_fixture_fail.sh" <<'T'
#!/usr/bin/env bash
if [[ -f .specflow.yml ]]; then echo "fixture-fail: failing inside the instance"; exit 1; fi
exit 0
T
git -C "$S" add -A && git -C "$S" commit -q -m fixtures
run() { (cd "$S" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/run-instance-tests.sh "$@" 2>&1); }
rc=0; OUT=$(run --base "$BASE") || rc=$?
printf '%s\n' "$OUT" > "$WORK/out1"
ck "a failing test in the instance exits 1 (not a usage error, not a crash)" [ "$rc" -eq 1 ]
ck "lists only the changed tests (both fixtures, no others)" bash -c "grep -q test_zz_fixture_skip.sh '$WORK/out1' && grep -q test_zz_fixture_fail.sh '$WORK/out1' && ! grep -q 'RUN test_attestation' '$WORK/out1'"
ck "prints the instance SKIP line" grep -q '^SKIP fixture-skip: not applicable in an instance' "$WORK/out1"
ck "names the failing test" grep -q '^FAIL.*test_zz_fixture_fail.sh' "$WORK/out1"
ck "prints a per-stack summary" grep -q '^python: 2 test(s), 1 failed, 1 SKIP' "$WORK/out1"
ck "no stack pack changed: only python is scaffolded" bash -c "! grep -q '^tauri:' '$WORK/out1' && ! grep -q '^flutter:' '$WORK/out1'"
# BL-021's decision reads "init per touched stack": a change under stacks/<stack>/ adds that stack to the default.
mkdir -p "$S/stacks/tauri" && echo touched > "$S/stacks/tauri/touched.txt" && git -C "$S" add -A && git -C "$S" commit -q -m "touch tauri"
rc=0; OUT=$(run --base "$BASE" tests/governance/test_zz_fixture_skip.sh) || rc=$?
printf '%s\n' "$OUT" > "$WORK/out3"
ck "a change under stacks/tauri/ adds tauri to the default stacks (python still first)" bash -c "grep -q '^python: 2 test(s), 1 failed, 1 SKIP' '$WORK/out3' && grep -q '^tauri: 2 test(s), 1 failed, 1 SKIP' '$WORK/out3' && ! grep -q '^flutter:' '$WORK/out3'"
ck "--stack given: the touched stack is not added on top of it" bash -c "cd '$S' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/run-instance-tests.sh --base '$BASE' --stack python tests/governance/test_zz_fixture_skip.sh 2>&1 | { ! grep -q '^tauri:'; }"
rc=0; OUT=$(cd "$S" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/run-instance-tests.sh --base HEAD --stack tauri 2>&1) || rc=$?
ck "no changed tests exits 0" [ "$rc" -eq 0 ]
rc=0; OUT=$(cd "$S" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/run-instance-tests.sh --base HEAD --stack tauri tests/governance/test_zz_fixture_skip.sh 2>&1) || rc=$?
printf '%s\n' "$OUT" > "$WORK/out2"
ck "an explicitly named passing test on another stack exits 0" [ "$rc" -eq 0 ]
ck "the tauri summary is printed" grep -q '^tauri: 1 test(s), 0 failed, 1 SKIP' "$WORK/out2"
rc=0; OUT=$(cd "$S" && bash scripts/run-instance-tests.sh --stack rust 2>&1) || rc=$?
ck "an unknown stack is refused" [ "$rc" -eq 2 ]
# P6's lesson (a), the retrospective: GITHUB_HEAD_REF and SPECFLOW_HEAD_BRANCH leak a PR's branch name into a
# scaffolded instance's gates, so the runner unsets them (as test_first_run.sh does) for every test it runs.
cat > "$S/tests/governance/test_zz_fixture_env.sh" <<'T'
#!/usr/bin/env bash
if [[ -n "${GITHUB_HEAD_REF:-}${SPECFLOW_HEAD_BRANCH:-}${SPECFLOW_QG_RUNNING:-}" ]]; then echo "fixture-env: a CI or orchestrator variable leaked into the instance"; exit 1; fi
exit 0
T
git -C "$S" add -A && git -C "$S" commit -q -m env-fixture
rc=0; OUT=$(cd "$S" && GITHUB_HEAD_REF=refs/heads/x SPECFLOW_HEAD_BRANCH=x SPECFLOW_QG_RUNNING=1 SPECFLOW_NO_SCAFFOLD=1 bash scripts/run-instance-tests.sh --base HEAD tests/governance/test_zz_fixture_env.sh 2>&1) || rc=$?
ck "GITHUB_HEAD_REF, SPECFLOW_HEAD_BRANCH and SPECFLOW_QG_RUNNING are unset inside the instance" bash -c '[ "$1" -eq 0 ] && grep -q "^python: 1 test(s), 0 failed, 0 SKIP" <<<"$2"' _ "$rc" "$OUT"
finish test_run_instance_tests
