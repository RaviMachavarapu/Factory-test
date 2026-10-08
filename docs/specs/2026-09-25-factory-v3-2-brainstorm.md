---
type: brainstorm
phase: BRAINSTORM
spec: 2026-09-25-factory-v3-2
status: accepted
created: "2026-09-25"
---

# Brainstorm — Factory v3.2: idea in, tested ship-ready product out

## Goal
Make the template deliver its stated objective: any user inputs an idea and turns out a product that is fully tested and ready to go. Input is the 2026-09-25 template objective review (`docs/reviews/2026-09-25-template-objective-review.md`, PR #19), which found the objective unachievable today for any user and proposed a six-item roadmap.

## Decisions taken in this brainstorm (with the human partner)

| Question | Decision | Alternatives rejected |
|---|---|---|
| Scope of the first plan | Whole roadmap (items 1–6) as one umbrella spec, one plan per item | items 1+2 only; items 1–4 |
| Who is "any user" | Two profiles selected at init: **guided** (non-technical founder; Claude makes technical decisions, human confirms plain-English summaries and merges) and **engineer** | founder only; developer only |
| Solo review gate | The verifier's verdict is the second reviewer: CI parses APPROVE / REQUEST_CHANGES and the comment SHA; solo mode requires zero human approvals, teams keep one | always require a second human; documented honor system |
| Pipeline shape | Three lanes by default (design, build, ship); the 7-PR path stays as an opt-in **regulated** profile with identical mechanical gates | lanes only; keep 7 PRs and add `/next` |
| First-class stacks | Python, Tauri (Vite + TypeScript + Vitest frontend, Rust backend), Flutter | Node/Go as first-class |
| "Ready to go" for Python | Container image + GitHub Release + deploy hook contract (migrate, smoke, rollback) | Release only; full deploy to one named cloud |
| "Ready to go" for Tauri/Flutter | Built macOS bundles on a GitHub Release + store-readiness checklist; signing/notarization stay a checklist | signed + store submission automated; unsigned local build only |
| CI platforms | macOS desktop only in v3.2 | Windows/Linux desktop; Android; iOS |
| Tauri frontend | Opinionated: Vite + TypeScript + Vitest | user picks; Rust-only gates |
| Architecture | **Approach 1:** config-driven factory with stack packs, in-repo `/next` and spec commands, constitution amended for lanes and solo mode | Approach 2: ship the factory as a Claude Code plugin (strains `art-repository-singleton`, new packaging subsystem). Approach 3: adopt SpecKit wholesale (its `specs/NNN-feature/` layout and own constitution conflict with `docs/specs/` and the 12 articles; moving external dependency at the core) |

## Assumptions carried into the spec
- Dafny stays as-is: model proofs are stack-agnostic; Rust and Dart code are covered by tests, not extracted contracts.
- SpecKit is replaced by thin in-repo commands rather than run via `specify init`.
- The v3.2 success criterion is executable: a fresh instance of each stack, in each profile, goes idea → GitHub Release with green gates using only the commands `/next` printed, and a governance test performs that walk.

## Hand-off
SPECIFY turns this into `docs/specs/2026-09-25-factory-v3-2-design.md` with REQ-300..REQ-395. The six roadmap items became eight plans (P0 plan-scoped gates and P7 closeout were added by the fresh-eyes review). Two requirements are tagged `[verifiable-model]`: the lane/phase state derivation (a state machine) and the security-disposition gate decision (a data-integrity rule).
