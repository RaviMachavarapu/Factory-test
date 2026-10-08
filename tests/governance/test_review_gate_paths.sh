#!/usr/bin/env bash
# REQ-308 with ADR-003's consequence (REQ-343's rule text moved to P1):
# review-gate.md documents both paths' branches and the lane-to-phase mapping.
# Covers: REQ-308
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
R=.claude/rules/review-gate.md
for b in 'design/<slug>' 'build/<slug>-N' 'build/sec-<id>' 'ship/<version>' 'patch/<slug>' 'phase/spec-<slug>' 'phase/arch-<slug>' \
         'phase/plan-<slug>' 'impl/plan-N-<plan slug>' 'impl/sec-<id>' 'phase/validate' 'phase/security' 'phase/release' 'phase/retro-YYYY-MM-DD'; do
  ck "names $b" grep -qF "$b" "$R"
done
map=$(awk '/^## Lane-to-phase mapping/{f=1; next} /^## /{f=0} f' "$R")
for ph in BRAINSTORM SPECIFY ARCHITECTURE PLAN TASKS ANALYZE IMPLEMENT VALIDATE SECURITY RELEASE; do ck "mapping places $ph" grep -q "$ph" <<<"$map"; done
ck "no fixed-name phase/spec|arch|plan (ADR-003)" no grep -qE '(^|[^-/a-z])phase/(spec|arch|plan)([^-]|$)' "$R"
ck "mapping precedes the back-edge protocol" awk '/^## Lane-to-phase mapping/{m=NR} /^## Back-edge protocol/{b=NR} END{exit !(m && b && m < b)}' "$R"
ck "patch tier names patch/<slug>" grep -qF 'patch/<slug>' <<<"$(awk '/^## Patch tier/,/^## Minor exception/' "$R")"
ck "path named as .specflow.yml configuration" grep -q specflow.yml "$R"
# P5 (REQ-340, R12; REQ-343): the proof and contract jobs run on every branch of either path where a proof, a contract or
# its twin travels (not patch/); the patch tier and the minor exception stay stated for both paths; CLAUDE.md, README
# and /security-review name both paths and /next.
# Covers: REQ-340
V=.github/workflows/verifier.yml
cond() { awk -v j="  $1:" '$0==j{f=1; next} f && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{exit} f' "$V" \
  | awk '/^    if: \|/{f=1; next} f && /^    [a-z-]+:/{exit} f' | tr -d ' \n'; }
for job in verify-dafny contract-alignment; do
  c=$(cond "$job")
  for pre in impl/ phase/validate phase/plan- design/ build/ ship/ phase/security phase/release; do  # F8: the regulated ship pair too
    ck "$job runs on $pre heads" grep -qF "startsWith(github.head_ref,'$pre')" <<<"$c"
  done
  ck "$job keeps the has-verification label" grep -qF "'has-verification'" <<<"$c"
  ck "$job leaves patch/ out (a patch never touches a [verifiable*] REQ)" no grep -qF "'patch/'" <<<"$c"
done
ck "both proof jobs share one condition" [ "$(cond verify-dafny)" = "$(cond contract-alignment)" ]
ck "actionlint accepts the workflows (when installed)" bash -c 'command -v actionlint >/dev/null 2>&1 || exit 0; actionlint .github/workflows/*.yml'
ck "the patch tier is one PR from patch/<slug> on either path" grep -qF 'on either path' <<<"$(awk '/^## Patch tier/,/^## Minor exception/' "$R")"
ck "the minor exception bounds doc-only fixes, whatever the path" bash -c 'awk "/^## Minor exception/,0" "$1" | grep -qi "doc-only"' _ "$R"
ck "/security-review's back-edge names impl/sec- and build/sec-" \
  bash -c 'grep -qF "impl/sec-<finding-id>" "$1" && grep -qF "build/sec-<finding-id>" "$1"' _ .claude/commands/security-review.md
for w in '/next' 'scripts/next.sh' 'scripts/lib/specflow/state.py' 'scripts/lib/specflow/pipeline.py' '.claude/commands/next.md'; do
  ck "CLAUDE.md names $w" grep -qF -- "$w" CLAUDE.md
done
ck "README's workflow section names /next and squash merges" \
  bash -c 'w=$(awk "/^## Workflow/{f=1; next} /^## Key Files/{f=0} f" README.md); grep -qF "/next" <<<"$w" && grep -qi "squash" <<<"$w"'
# PR #48 verifier low 8 (REQ-340, REQ-341): CLAUDE.md is model-instruction Markdown loaded every session — one copy of the
# /next sentence, after both pipeline tables (after the lanes table, before the back-edge).
# Covers: REQ-340, REQ-341
ck "CLAUDE.md carries the /next derives… sentence exactly once" \
  bash -c '[ "$(grep -cF "\`/next\` derives the phase or lane on either path" CLAUDE.md)" = 1 ]'
ck "…after both tables: below the lanes table's Ship row, above the back-edge" \
  bash -c 'n=$(grep -nF "\`/next\` derives the phase or lane on either path" CLAUDE.md | cut -d: -f1); s=$(grep -nF "| Ship | \`ship/<version>\`" CLAUDE.md | cut -d: -f1); b=$(grep -n "^Back-edge:" CLAUDE.md | cut -d: -f1); [ "$n" -gt "$s" ] && [ "$n" -lt "$b" ]'

# Round 3b re-review D4 (REQ-340): /next reads impl/plan-N-<name>'s N as the plan's "## Build N" token and <name> as
# the plan's slug; CLAUDE.md, README and review-gate.md say so, never "one per plan" or a plan number.
# Covers: REQ-340
ck "CLAUDE.md: impl/plan-N-<plan slug> — N is the plan's ## Build N section" \
  grep -qF '`impl/plan-N-<plan slug>` — N is the plan'"'"'s `## Build N` section' CLAUDE.md
ck "README: impl/plan-N-<plan slug>, one PR per ## Build N, never one per plan" \
  bash -c 'grep -qF "impl/plan-N-<plan slug>" README.md && ! grep -qF "PR (one per plan)" README.md && grep -F "impl/plan-N-<plan slug>" README.md | grep -qF "## Build N"'
ck "review-gate.md: impl/plan-N-<plan slug>, one branch per ## Build N, never one per impl plan" \
  bash -c 'grep -qF "impl/plan-N-<plan slug>" "$1" && ! grep -qF "one branch per impl plan" "$1"' _ "$R"
ck "GLOSSARY's Regulated path: N as the ## Build token, <name> as the plan's slug" \
  bash -c 'awk "/^### Regulated path$/{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | grep -qF "as \`## Build <token>\` of the plan whose slug is \`<name>\`"'

finish test_review_gate_paths
