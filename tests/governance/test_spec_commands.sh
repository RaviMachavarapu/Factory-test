#!/usr/bin/env bash
# REQ-302: in-repo /specify, /specflow-plan, /specflow-tasks, /analyze write from the repo's
# templates; no onboarding document mentions SpecKit (docs/ is exempt).
# Covers: REQ-302
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=.claude/commands
for c in specify specflow-plan specflow-tasks analyze; do
  ck "/$c: frontmatter opens" [ "$(sed -n 1p "$C/$c.md" 2>/dev/null)" = "---" ]
  for k in "name: $c" 'description: ' 'argument-hint: '; do ck "/$c: $k" grep -q "^$k" "$C/$c.md"; done
done
for pair in 'specify|schemas/spec-template.md' 'specify|docs/specs/<date>-<slug>-design.md' 'specify|verify-doc.sh' \
            'specflow-plan|schemas/plan-template.md' 'specflow-plan|docs/plans/<date>-<slug>-plan.md' 'specflow-plan|implements:' \
            'specflow-plan|superpowers:writing-plans' 'specflow-tasks|docs/plans/<date>-<slug>-plan.md' 'specflow-tasks|## Build' 'analyze|analyze-adr-plan-linkage.sh' 'analyze|check-traceability.sh'; do
  ck "/${pair%%|*} mentions ${pair#*|}" grep -qF -- "${pair#*|}" "$C/${pair%%|*}.md"
done
hits=$(grep -rniE 'speckit|spec-kit' --exclude-dir=worktrees README.md CLAUDE.md .claude scripts templates schemas stacks 2>/dev/null | grep -v '^\.claude/settings\.local\.json' || true)
if [[ -z "$hits" ]]; then pass "no onboarding document references SpecKit"; else fail "SpecKit references remain:"; sed 's/^/    /' <<<"$hits"; fi

# F-8: /analyze names what the two checkers actually check, not an
# ADR-consequence or REQ-to-task claim they don't implement.
ck "analyze.md no longer claims 'ADR consequence' coverage" no grep -qF 'ADR consequence' "$C/analyze.md"
ck "analyze.md no longer claims 'has at least one task' coverage" no grep -qF 'has at least one task' "$C/analyze.md"
ck "analyze.md names analyze-adr-plan-linkage.sh's real check" grep -qF "accepted ADR in the plan's decisions:" "$C/analyze.md"
# PR #54 verifier run 2, finding 3 (REQ-385, REQ-313): by the full ref refs/remotes/origin/<base> — a tag named
# origin/<base> would shadow the short name.
# SEC-004 (high; dfe-9): main's reviewed copy for every PR — a stacked PR's base branch is unreviewed and never piped.
# Covers: REQ-313
ck "analyze.md bootstraps the verifier from refs/remotes/origin/main for every PR, never the short name or a base branch's copy (SEC-004)" \
  bash -c 'grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh" "$1" && ! grep -qF "origin/<base>:scripts/run-verifier.sh" "$1" && ! grep -qF "git show origin/" "$1" && grep -qi "base branch" "$1" && grep -qF "SEC-004" "$1"' _ "$C/analyze.md"
ck "analyze.md names check-traceability.sh's real check" grep -qF 'REQ IDs defined at most once' "$C/analyze.md"

# R-8: bullet 1 must say the linkage check covers every tagged REQ the plan
# implements (implements:, or the whole spec when absent) across every plan,
# per analyze-adr-plan-linkage.sh's own header (REQ-380 scoping) — not just
# "this plan"'s whole spec.
bullet1=$(awk '/^1\. `bash scripts\/analyze-adr-plan-linkage\.sh`/{f=1} f{print} /^2\. `bash scripts\/check-traceability\.sh`/{exit}' "$C/analyze.md")
ck "analyze.md bullet 1 mentions implements: (R-8)" grep -qF 'implements:' <<<"$bullet1"
ck "analyze.md bullet 1 says the check runs across every plan (R-8)" grep -qF 'every plan' <<<"$bullet1"

finish test_spec_commands
