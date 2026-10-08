---
id: ADR-991
status: accepted
date: 2026-09-28
addresses: [REQ-991]
---

# ADR-991: The greeting is a pure function

## Context
REQ-991 needs a greeting with a provable prefix.

## Decision
Keep `greet` pure and inside the verified kernel.

## Consequences
- The prefix is provable.

## Alternatives Considered
- A template library: rejected, no benefit.
