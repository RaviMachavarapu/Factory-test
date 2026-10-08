---
name: specflow-plan
description: PLAN phase — write an implementation plan from the spec, ADRs, and architecture overview.
argument-hint: <slug>
---

You are entering the PLAN phase for `$ARGUMENTS`.

Read `docs/specs/<date>-$ARGUMENTS-design.md`, its ADR(s) under `docs/adr/`,
and `docs/architecture/<date>-$ARGUMENTS-overview.md`. This command consumes
the ADRs; it does not re-derive architecture (`art-specification-primacy`).

Use `/superpowers:writing-plans` to structure the plan.

Read `.specflow.yml`'s `path` key (via `python3 scripts/lib/specflow/config.py get path --default lanes`): on the `lanes` path, organize work into `## Build 1:`, `## Build 2:`, ... lanes; on the `regulated` path, use numbered tasks instead.

Write `docs/plans/<date>-$ARGUMENTS-plan.md` (the pattern is `docs/plans/<date>-<slug>-plan.md`) from `schemas/plan-template.md`, with frontmatter `spec:` (this spec's slug), `decisions:` (the ADR IDs it consumes), `implements:` (the REQ-NNN list this plan delivers — never empty), and `created:`. Plans may carry failing test code but describe implementation as intent, never bodies (`art-test-first`).

When finished, name the next command (`/specflow-tasks $ARGUMENTS` if the plan used `## Build` lanes and needs task expansion, otherwise `/analyze $ARGUMENTS`) and the branch this phase's work belongs on, per `.claude/rules/review-gate.md`.
