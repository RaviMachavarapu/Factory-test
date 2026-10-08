---
name: specflow-tasks
description: TASKS phase — expand each Build lane of the plan into concrete tasks.
argument-hint: <slug>
---

You are entering the TASKS phase for `$ARGUMENTS`.

Read `docs/plans/<date>-$ARGUMENTS-plan.md` (the pattern is `docs/plans/<date>-<slug>-plan.md`). This command writes no new file:
it expands each `## Build N` section of that plan in place into numbered
tasks.

For every `## Build N`, add one or more `### Task N.M: <name>` subsections,
each with:
- **Files** — the files that task creates or modifies.
- **Interfaces** — the shape of what the task adds (function signatures,
  CLI flags, file formats) — intent, never implementation bodies
  (`art-test-first`).
- **Steps** — write the failing test first, run it and confirm the
  predicted failure, implement the minimum to pass, run it green, then any
  refactor, then commit.

Keep every task small enough to review and commit on its own. Do not
re-derive the plan's architecture or scope — only decompose it.

When finished, run `/analyze $ARGUMENTS` next, per `.claude/rules/review-gate.md`.
