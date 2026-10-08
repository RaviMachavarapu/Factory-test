---
name: architecture
description: ARCHITECTURE phase — produce ADRs, architecture overview, threat model from the spec.
argument-hint: <spec-slug>
---

You are entering the ARCHITECTURE phase for spec `$ARGUMENTS`.

Read `docs/specs/$ARGUMENTS-design.md` and `constitution.md` (articles `art-kernel-boundary` and `art-threat-driven-security`).

Produce in order:

1. One or more ADR files under `docs/adr/<NNN>-<topic>.md` with frontmatter `id`, `status: accepted`, `date`, `addresses: [REQ-NNN, ...]`. Body sections: Context, Decision, Consequences, Alternatives Considered.

2. `docs/architecture/$ARGUMENTS-overview.md` with frontmatter listing `kernel_modules` (each with `req_map` covering every `[verifiable]` REQ), `external_dependencies` (each with `justification`), `components`. Body: prose + Mermaid component diagram + Mermaid data-flow diagram.

3. `docs/architecture/$ARGUMENTS-threat-model.md`, from `schemas/threat-model-template.md`, answering every checklist row, with frontmatter listing `assets` (each with CIA rating), `trust_boundaries`, `dataflow_elements`, `stride_per_element` (every element with `external: true` has ≥1 STRIDE letter). Body: narrative + data-flow diagram with element IDs matching the frontmatter + the `## Domain checklist (REQ-333)` table.

When finished, run `/superpowers:brainstorming` only if alternatives are non-obvious — otherwise proceed to fresh-eyes review. Dispatch parallel reviewers including at least one customer persona (per project memory `feedback_customer-perspective-reviews.md`).

Before opening the PR, run `bash scripts/check-architecture.sh` (the ARCHITECTURE exit gate: every `[verifiable]`/`[verifiable-model]` REQ mapped, the threat model's shape, and the checklist answered) — it must pass. It checks a live spec once a plan names it or once its threat model or overview exists, so on the regulated path it already bites on the `phase/arch-<slug>` PR, before any plan. In the guided profile (`.specflow.yml` `profile: guided`, the default), each in-scope spec's overview, its threat model, and each ADR addressing one of its tagged REQs must also carry a non-empty `confirmed_by:` frontmatter value (REQ-389); the template's own inherited specs (the demo and the factory's v3.2 spec, a fixed list of slugs in `scripts/lib/specflow/frontmatter.py`) are grandfathered — never a spec by its own `created:` date — and in CI the profile is read at the base ref, so a PR cannot switch it off for itself.

Then push and open PR per `.claude/rules/review-gate.md`.

## Guided profile

Read only when `python3 scripts/lib/specflow/config.py get profile --default guided` prints `guided`. Ask or show only when the user ran `/architecture` directly. When `/next` ran this command it asks nothing here: `/next` shows the acknowledgements at its `design-pr` confirmation point (REQ-342 allows no other pause). `/next` writes `confirmed_by:` at `design-pr` into the spec and, where they exist, the overview, the threat model and the ADRs; on the regulated path `phase/spec-<slug>`'s point writes the spec's only, `phase/arch-<slug>`'s the architecture files', and `phase/plan-<slug>`'s writes none. It writes them just before the gates and `create-pr`; a gate run before that point under the guided profile reports `confirmed_by:` missing — that is expected, not a failure to fix by hand. At `design-pr` and `ship-pr`, after writing `confirmed_by:` (and, at `ship-pr`, the go/no-go answer) and running the gates green as `next.sh` renders them (`bash scripts/next.sh --gates`), `/next` runs `git add` on all of the lane's artifacts (new and edited) — exactly the path sets `next.md` names at that point, nothing else — and commits them — `git commit -m "docs(guided): confirmed_by: <handle> <date> — acknowledgements at design-pr (REQ-389)"`, or `…at ship-pr (REQ-389)` — and only then runs `create-pr`, so the pushed branch carries what the gates checked. Under a `### Guided proposals` heading, give each proposal a `Rationale (plain English):` line and a `What this means for you:` line, in words a non-engineer follows. The kernel boundary (which modules `kernel_modules.req_map` places behind `art-kernel-boundary`) is an **acknowledgement**: show it, do not ask. Record it in the overview under `### Guided proposals`, and add `confirmed_by: <handle> <YYYY-MM-DD>` to the frontmatter of the overview, the threat model and each ADR addressing a tagged REQ, which `check-architecture.sh` already requires (REQ-389).
