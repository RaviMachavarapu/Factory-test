#!/usr/bin/env bash
# Smoke test for scripts/run-quality-gates.sh: exits 0 on a clean repo, and (REQ-303, W-5) a configured stack whose
# quality-gates hook is missing or not executable is a gate FAILURE naming the hook, never a silent SKIP.
# Covers: REQ-303
set -euo pipefail

# Recursion guard: when this test is invoked by the orchestrator itself, the
# orchestrator sets SPECFLOW_QG_RUNNING=1 so the smoke test's own re-invocation
# of the orchestrator would otherwise recurse. We short-circuit here.
if [[ "${SPECFLOW_QG_RUNNING:-0}" == "1" ]]; then
  echo "SKIP: smoke test no-op inside orchestrator (recursion guard)"
  exit 0
fi

OUTPUT=$(bash scripts/run-quality-gates.sh 2>&1) || {
  echo "FAIL: script exited non-zero on clean repo"
  echo "$OUTPUT"
  exit 1
}

if ! grep -q 'All quality gates passed' <<<"$OUTPUT"; then  # a here-string: under pipefail, echo | grep -q can die of SIGPIPE
  echo "FAIL: script did not report success"
  echo "$OUTPUT"
  exit 1
fi

echo "PASS: run-quality-gates.sh exits 0 with success message on clean repo"

# W-5/REQ-303: a configured stack whose quality-gates hook is missing or not
# executable is a gate FAILURE, never a silent SKIP. One cheap python
# instance (SPECFLOW_NO_SCAFFOLD=1 keeps it fast — the demo example alone is
# enough for pytest/dafny to have something to do).
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
HOOKD="$(mktemp -d)"; trap 'rm_tree "$HOOKD"' EXIT
copy_template "$HOOKD"
(cd "$HOOKD" && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Hookless --profile engineer </dev/null >/dev/null 2>&1)
chmod -x "$HOOKD/scripts/quality-gates-python.sh"
HOOK_RC=0
HOOK_OUTPUT=$(cd "$HOOKD" && env -u SPECFLOW_QG_RUNNING bash scripts/run-quality-gates.sh 2>&1) || HOOK_RC=$?

if [[ "$HOOK_RC" -ne 1 ]]; then
  echo "FAIL: gates exited $HOOK_RC (want 1) when the configured stack's hook is not executable"
  echo "$HOOK_OUTPUT"
  exit 1
fi
if ! grep -q '^FAIL ' <<<"$HOOK_OUTPUT"; then
  echo "FAIL: missing-hook output does not contain a FAIL line"
  echo "$HOOK_OUTPUT"
  exit 1
fi
if ! grep -qF 'scripts/quality-gates-python.sh' <<<"$HOOK_OUTPUT"; then
  echo "FAIL: missing-hook output does not name the hook path"
  echo "$HOOK_OUTPUT"
  exit 1
fi

echo "PASS: run-quality-gates.sh fails (not SKIP) when the configured stack's hook is missing or not executable"
