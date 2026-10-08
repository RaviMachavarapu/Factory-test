---
type: plan
phase: PLAN
spec: <date>-<slug>
decisions: [ADR-NNN]
implements: [REQ-NNN]  # the REQs this plan delivers; gates scope to this list (REQ-380)
created: ""
---

# [Plan Title] — Implementation Plan

Implements REQ-NNN (per ADR-NNN).

Plans may carry the failing test code (the tests are the behavioural spec and
are written first) and describe implementation as intent, never bodies
(`art-test-first`).

## Files

**Created:**
- [`path/to/file`] — [what it does / which REQ it serves]

## Build 1: <name>

[One build lane implements this plan's scope end to end. Further units of
work are `## Build 2:`, `## Build 3:`, and so on, numbered contiguously
starting from 1.]

### Task 1.1: [Task name]

[What this task does, and which REQ(s) it covers. Describe intent — the
runnable implementation lives in IMPLEMENT, never in this document.]

**Inventory: existing files the new gate may fail** (optional step — include
it when the task tightens a gate): list the tracked files that would fail the
new rule, measured on the base (a grep, or the new test run against the
tree), and budget their cleanup in this same task.
