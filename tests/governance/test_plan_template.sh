#!/usr/bin/env bash
# REQ-380: the plan template documents implements: and the Build-N shape,
# every plan that carries implements: lists only REQ-NNN ids (and not an
# empty list), and the plan-style rule is stated where plans are reviewed.
# Covers: REQ-380
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"
FAIL=0; pass() { echo "ok:   $1"; }; fail() { echo "FAIL: $1"; FAIL=1; }
# REQ-306: an instance with no plans left (every example removed, or
# docs/plans/ emptied outright) passes vacuously instead of iterating over
# the literal, non-matching glob pattern.
shopt -s nullglob

T=schemas/plan-template.md
if [[ -f $T ]]; then pass "$T exists"; else fail "$T missing"; fi
for key in 'spec:' 'decisions:' 'implements:' 'created:'; do
  if grep -q "^$key" "$T" 2>/dev/null; then pass "template has $key"; else fail "template lacks $key"; fi
done
if grep -q '^## Build 1: ' "$T" 2>/dev/null; then pass "template has '## Build 1:' section"; else fail "template lacks '## Build 1:'"; fi

for p in docs/plans/*.md; do
  line=$(awk '/^---$/{n++; next} n==1 && /^implements:/{print; exit}' "$p")
  [[ -z "$line" ]] && continue
  items=$(echo "$line" | sed 's/^implements:[[:space:]]*//' | tr -d '[]"'"'"' ' | tr ',' '\n' | sed '/^$/d')
  if [[ -z "$items" ]]; then
    fail "$p implements: is an empty list"
  elif echo "$items" | grep -vqE '^REQ-[0-9]{3}$'; then
    fail "$p implements: has a non-REQ-NNN entry: $line"
  else
    pass "$p implements: well-formed"
  fi
done

# implements: is mandatory from 2026-09-25 onward (REQ-380): a plan created
# on or after that date must carry an implements: key. Plans without
# created: frontmatter, or with an earlier created: date, are exempt (e.g.
# the demo plan, created: "2026-05-28").
for p in docs/plans/*.md; do
  created_line=$(awk '/^---$/{n++; next} n==1 && /^created:/{print; exit}' "$p")
  created=$(echo "$created_line" | sed 's/^created:[[:space:]]*//' | tr -d '"'"'"'' | xargs 2>/dev/null || true)
  [[ -z "$created" ]] && continue
  if [[ "$created" > "2026-09-24" ]]; then
    implements_line=$(awk '/^---$/{n++; next} n==1 && /^implements:/{print; exit}' "$p")
    if [[ -z "$implements_line" ]]; then
      fail "$p is missing mandatory implements: (created: $created, on or after 2026-09-25)"
    else
      pass "$p carries mandatory implements: (created: $created)"
    fi
  fi
done

for f in .claude/rules/review-gate.md .github/PULL_REQUEST_TEMPLATE.md docs/plans/2026-05-28-demo-greeting-plan.md; do
  # REQ-306: the demo plan is one place the rule is demonstrated, not the
  # only one — an instance that has removed the demo is not missing it.
  [[ -f "$f" ]] || continue
  if grep -q 'implementation as intent' "$f"; then pass "$f states the plan-style rule"; else fail "$f does not state the plan-style rule"; fi
done
if grep -q 'implements:' .claude/rules/review-gate.md; then pass "review-gate.md documents implements:"; else fail "review-gate.md does not mention implements:"; fi
if grep -q 'implements:' .github/PULL_REQUEST_TEMPLATE.md; then pass "PR template mentions implements:"; else fail "PR template does not mention implements:"; fi

# BL-027: the task skeleton carries the optional inventory step for files a
# stricter gate may fail (the template is an instance file, so this runs in
# an instance too).
# Covers: REQ-380
if grep -q 'Inventory: existing files the new gate may fail' "$T" 2>/dev/null \
   && awk '/^### Task 1\.1:/{t=1} t && /Inventory: existing files the new gate may fail/{f=1} END{exit !f}' "$T"; then
  pass "template task skeleton has the BL-027 inventory step"
else
  fail "template task skeleton lacks the 'Inventory: existing files the new gate may fail' step (BL-027)"
fi

[[ $FAIL -eq 0 ]] || { echo "test_plan_template: FAILED"; exit 1; }
echo "test_plan_template: all checks passed"
