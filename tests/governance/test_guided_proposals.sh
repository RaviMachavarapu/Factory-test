#!/usr/bin/env bash
# REQ-389 (P5 R19): in the guided profile Claude proposes the stack, the [verifiable-model] tags, the kernel boundary,
# severity scores and dispositions, each recorded where it lands with a plain-English rationale and its consequence for
# the user; decisions (stack, scope, go/no-go) are asked, acknowledgements (tags, kernel, severity, disposition) are shown,
# once — a command /next runs asks nothing itself (REQ-342) — and the verifier's full mode, the part that reads the
# documents where they land, confirms the acknowledgements in guided solo mode, provisionally (P5 R19's reading of the
# REQ's "code mode"); code mode's headings are unchanged. REQ-310: the verifier's
# prompt names the base's profile and solo. A guided fixture instance records the stack decision's rationale and
# consequence in IDEA.md.
# Covers: REQ-389
# Covers: REQ-310
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
C=.claude/commands
guided() { awk '/^## Guided profile$/{f=1; next} /^## /{f=0} f' "$1" | tr '\n' ' '; }
for f in specify architecture security-review; do
  g=$(guided "$C/$f.md")
  ck "$f.md has a Guided profile section" test -n "$g"
  for w in 'Guided proposals' 'Rationale (plain English):' 'What this means for you:' 'acknowledgement'; do
    ck "$f.md's guided section says '$w'" grep -qF -- "$w" <<<"$g"
  done
done
for f in specify architecture security-review release; do
  ck "$f.md's guided section asks nothing when /next ran it (/next asked at its confirmation point, REQ-342)" \
    bash -c 'grep -qF "/next" <<<"$1" && grep -qiF "asks nothing" <<<"$1"' _ "$(guided "$C/$f.md")"
done
g=$(guided "$C/specify.md")
ck "specify.md: the tags are acknowledgements, the product scope a decision, confirmed_by: on the spec" \
  bash -c 'grep -qF "[verifiable-model]" <<<"$1" && grep -qi "scope" <<<"$1" && grep -qi "decision" <<<"$1" && grep -qF "confirmed_by:" <<<"$1"' _ "$g"
g=$(guided "$C/architecture.md")
ck "architecture.md: the kernel boundary is an acknowledgement recorded in the overview" \
  bash -c 'grep -qi "kernel" <<<"$1" && grep -qF "overview" <<<"$1" && grep -qF "confirmed_by:" <<<"$1"' _ "$g"
g=$(guided "$C/security-review.md")
ck "security-review.md: severity and disposition are acknowledgements in the review's prose, not a block key" \
  bash -c 'grep -qi "severity" <<<"$1" && grep -qi "disposition" <<<"$1" && grep -qi "not a block key" <<<"$1"' _ "$g"
g=$(guided "$C/release.md")
ck "release.md: go/no-go is a decision the human answers before the ship PR" \
  bash -c 'grep -qi "go/no-go" <<<"$1" && grep -qi "decision" <<<"$1"' _ "$g"
sk=$(awk '/^## Mode: full/{f=1; next} /^## /{f=0} f' .claude/skills/verifier/SKILL.md | tr '\n' ' ')
ck "full mode confirms guided acknowledgements in guided solo mode, provisionally (P5 R19: doc-only design and ship PRs get full mode alone)" \
  bash -c 'grep -qF "Guided acknowledgements" <<<"$1" && grep -qi "provisional" <<<"$1" && grep -qF "Profile: guided" <<<"$1" && grep -qF "Solo: true" <<<"$1" && grep -qF "Guided proposals" <<<"$1" && grep -qF "art-threat-driven-security" <<<"$1"' _ "$sk"
ck "code mode carries no guided pass" no grep -qF 'Guided acknowledgements' <<<"$(awk '/^## Mode: code$/{f=1; next} /^## /{f=0} f' .claude/skills/verifier/SKILL.md)"
ck "code mode's five headings are unchanged (REQ-310)" bash tests/governance/test_verifier_skill_modes.sh
ck "the headless prompt carries the Profile and Solo lines" \
  bash -c 'grep -qx "Profile: @PROFILE@" "$1" && grep -qx "Solo: @SOLO@" "$1"' _ .claude/skills/verifier/headless-prompt.md
ck "the spec template carries confirmed_by: and the Guided proposals note" \
  bash -c 'grep -qF "confirmed_by:" "$1" && grep -qF "Guided proposals" "$1"' _ schemas/spec-template.md
if ! instance; then
  for p in stacks/*/pack.yml; do
    ck "$p carries guided_consequence (what the stack choice means for the user)" grep -qE '^guided_consequence: .{20,}' "$p"
  done
  W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
  D="$W/g"; copy_template "$D"
  ck "guided init (scaffold-free) exits 0" bash -c "cd '$D' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Habit --profile guided --stack python </dev/null"
  st=$(awk '/^## Stack$/{f=1; next} /^## /{f=0} f' "$D/IDEA.md" | tr '\n' ' ')
  ck "the guided instance's IDEA.md records the stack with its rationale and what it means for the user" \
    bash -c 'grep -qF "Rationale (plain English):" <<<"$1" && grep -qF "What this means for you:" <<<"$1"' _ "$st"
fi
# PR #47 verifier low 6 (REQ-389; the citation discipline): the guided-acknowledgements finding cites each
# acknowledgement's own article — [verifiable-model] tags art-formal-verification, the kernel boundary art-kernel-boundary,
# severity and dispositions art-threat-driven-security — in SKILL.md step 8 and in the plan's R19; never one article for all.
# Covers: REQ-389
PL=docs/plans/2026-09-28-factory-v3-2-p5-plan.md
for f in .claude/skills/verifier/SKILL.md "$PL"; do
  [ -f "$f" ] || continue
  ck "$f: the guided-acknowledgements finding cites per acknowledgement, not art-threat-driven-security alone" \
    bash -c 'grep -qF "\`Guided acknowledgements (provisional): …\`" "$1" && ! grep -qF "Guided acknowledgements (provisional, art-threat-driven-security)" "$1" && grep -F "Guided acknowledgements (provisional)" "$1" | grep -qF "tags \`art-formal-verification\`, the kernel boundary \`art-kernel-boundary\`, severity and dispositions \`art-threat-driven-security\`"' _ "$f"
done

# PR #48 verifier run 2, F4 (REQ-389): the plan's H17 line names the verifier's full mode as REQ-389's control, as R19,
# REQ-389's body and SKILL.md step 8 do.
# Covers: REQ-389
if [ -f "$PL" ]; then
  ck "the plan's H17: the verifier's full-mode confirmation is REQ-389's control (never code mode)" \
    bash -c 'grep -F "A format check for \`confirmed_by:\`" "$1" | grep -qF "the verifier'"'"'s full-mode confirmation is REQ-389'"'"'s control (R19)" && ! grep -qF "code-mode confirmation is REQ-389" "$1"' _ "$PL"
fi

finish test_guided_proposals
