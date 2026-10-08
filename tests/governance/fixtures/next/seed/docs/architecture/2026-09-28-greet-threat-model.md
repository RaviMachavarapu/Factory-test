---
spec: 2026-09-28-greet
assets:
  - name: greeting-output
    cia: {c: L, i: M, a: L}
trust_boundaries:
  - name: function-boundary
    between: [caller, greet]
dataflow_elements:
  - id: dfe-1
    name: name-input
    external: true
stride_per_element:
  dfe-1: [T]
---

# Greet — Threat Model

## Narrative
The only external input is the `name` parameter; the function performs no I/O.

## Domain checklist (REQ-333)

| Domain | Answer |
|---|---|
| Authentication | N/A because the function has no identity of its own |
| Authorization | N/A because there is no access-control decision |
| Session | N/A because there is no session, only an in-process call |
| PII and retention | dfe-1: the name only builds the returned string |
| Payments | N/A because nothing here handles money |
| Secrets at rest | N/A because the function holds no secret |
| Sensitive logging | dfe-1: greet performs no logging |
| Rate limiting | N/A because there is no exposed endpoint |
| Third-party integrations | N/A because the function calls nothing external |
| Update channel for apps | N/A because this is a library function, not an app |
