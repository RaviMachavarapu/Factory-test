#!/usr/bin/env bash
# REQ-310 (H12): in team mode a session-produced review may be posted with origin:in-session; in solo mode it may not,
# and solo is read from the base ref, never the PR head (dfe-6). --print-prompt gives a subagent the base-ref prompt
# and keeps the input files it names.
# Covers: REQ-310
# Covers: REQ-313
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
verifier_repo "$(mktemp -d)"; trap 'rm_tree "$VW"' EXIT
printf '### Findings\nNone.\n<!-- hidden -->\nAPPROVE\n' > "$VW/findings.md"
insess() { vreset; rc=0; out=$(cd "$VR" && CLAUDECODE=1 PATH="$VS/bin:$PATH" STUB_DIR="$VS" HOME="$VW/home" \
  bash -c 'git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- "$@"' _ "$@" </dev/null 2>&1) || rc=$?; }

vbranch flip 'printf "solo: false\n" > .specflow.yml; printf "# f\n" > docs/specs/zz-f.md'
insess 7 --from-file "$VW/findings.md" --model claude-opus-5-5
ck "solo at the base (the default) refuses --from-file even when the PR head says solo: false (exit 3)" [ "$rc" = 3 ]
ck "…naming the headless command, the base by its full ref (PR #54 verifier run 2, finding 3)" grep -qF 'git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7' <<<"$out"
ck "…posting nothing" no test -e "$VS/posted.md"

(cd "$VR" && git checkout -q main && printf 'solo: false\n' > .specflow.yml && git add .specflow.yml && git commit -qm team && git push -q origin main)
vbranch team 'printf "# t\n" > docs/specs/zz-t.md'
insess 7 --print-prompt
ck "--print-prompt works inside a session and prints the base-ref prompt" bash -c \
  '[ "$1" = 0 ] && grep -qF "docs/specs/zz-t.md" <<<"$2" && grep -q "Citation Discipline" <<<"$2" && grep -qF "=== specflow-verifier prompt 1/1: full ===" <<<"$2"' _ "$rc" "$out"
ck "--print-prompt runs no model and posts nothing" bash -c '[ ! -s "$1" ] && [ ! -e "$2" ]' _ "$VS/claude.argv" "$VS/posted.md"
insess 7 --from-file "$VW/findings.md" --model claude-opus-5-5
ck "team mode: --from-file posts inside a session (exit 0)" [ "$rc" = 0 ]
ck "…with origin:in-session and the given model" grep -qE '^<!-- specflow-verifier:full sha:[0-9a-f]{40} .* model:claude-opus-5-5 verdict:APPROVE digest:[0-9a-f]{64} origin:in-session -->$' "$VS/posted.md"
ck "…HTML comments stripped from the findings" [ "$(grep -c '<!--' "$VS/posted.md")" = 1 ]
ck "…scanned by gitleaks, no model run, check re-run" bash -c 'grep -qx dir "$1" && [ ! -s "$2" ] && grep -qx rerun "$3"' _ "$VS/gitleaks.argv" "$VS/claude.argv" "$VS/gh.argv"
insess 7
ck "a full run still refuses inside a session (exit 3)" [ "$rc" = 3 ]
insess 7 --from-file "$VW/findings.md"
ck "--from-file without --model is a usage error (exit 2)" [ "$rc" = 2 ]
printf 'no verdict here\n' > "$VW/nov.md"; insess 7 --from-file "$VW/nov.md" --model m
ck "--from-file without a verdict line: exit 9" [ "$rc" = 9 ]
vbranch team2 'printf "# u\n" > docs/specs/zz-u.md; printf "x\n" > tests/zz_u.txt'
insess 7 --from-file "$VW/findings.md" --model m
ck "documents + code need two findings files (exit 2)" [ "$rc" = 2 ]
insess 7 --from-file "$VW/findings.md" --from-file "$VW/findings.md" --model m
ck "…and post as full+code with two" bash -c '[ "$1" = 0 ] && grep -qE "^<!-- specflow-verifier:full\+code .* origin:in-session -->$" "$2"' _ "$rc" "$VS/posted.md"
# --print-prompt for documents + code: the code part's inputs still exist after the script exits (the subagent reads them later)
insess 7 --print-prompt
kept=$(sed -nE 's/^input kept at ([^:]+):.*/\1/p' <<<"$out")
ck "--print-prompt (documents + code): two prompts, the input dir named" bash -c \
  '[ "$1" = 0 ] && grep -qF "=== specflow-verifier prompt 2/2: code ===" <<<"$2" && [ -n "$3" ]' _ "$rc" "$out" "$kept"
ck "…whose diff.patch and commits.txt exist after exit" bash -c 'test -s "$1/diff.patch" && test -s "$1/commits.txt"' _ "$kept"
ck "…and the printed code prompt points at that same directory" grep -qF "$kept" <<<"$out"
ck "…with the PR's change in diff.patch" grep -qF 'tests/zz_u.txt' "$kept/diff.patch"
rm -rf "$kept"
finish test_verifier_insession
