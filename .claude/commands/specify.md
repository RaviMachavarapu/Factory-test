---
name: specify
description: SPECIFY phase — write a spec from the constitution, IDEA.md, and any brainstorm notes.
argument-hint: <slug>
---

You are entering the SPECIFY phase for `$ARGUMENTS`.

Read `constitution.md` (cite articles by slug, never Roman numeral) and, if
present, `IDEA.md` and any brainstorm notes for `$ARGUMENTS` under
`docs/specs/`.

Read `.specflow.yml`'s `profile` key (via `python3 scripts/lib/specflow/config.py get profile --default guided`) and phrase your confirmations and clarifying questions plainly when `profile` is `guided` — no jargon, no unexplained acronyms.

Produce `docs/specs/<date>-$ARGUMENTS-design.md` (the pattern is `docs/specs/<date>-<slug>-design.md`) from `schemas/spec-template.md`, continuing the global REQ sequence (check existing specs under `docs/specs/` for the highest `REQ-NNN` used anywhere in the repo — IDs are globally unique, never reused or restarted, per `art-naming-tagging`). For every requirement, decide once whether it needs a `[verifiable]` or `[verifiable-model]` tag (per the template's Verification Identification section) and give a one-line rationale for the tag (or its absence) next to the requirement.

Ask at most five clarifying questions, batched, before you write the spec — never more.

When the spec is written, run `bash scripts/verify-doc.sh docs/specs/<date>-$ARGUMENTS-design.md` and fix anything it flags before proceeding.

Name the next command (`/architecture $ARGUMENTS`) and the branch this phase's work belongs on, per `.claude/rules/review-gate.md`.

## Guided profile

Read only when `python3 scripts/lib/specflow/config.py get profile --default guided` prints `guided`. Ask or show only when the user ran `/specify` directly. When `/next` ran this command it asks nothing here: `/next` asked the scope at `brainstorm-end` and shows the acknowledgements at `design-pr` (REQ-342 allows no other pause). `/next` writes `confirmed_by:` at `design-pr` into the spec and, where they exist, the overview, the threat model and the ADRs; on the regulated path `phase/spec-<slug>`'s point writes the spec's only, `phase/arch-<slug>`'s the architecture files', and `phase/plan-<slug>`'s writes none. It writes them just before the gates and `create-pr`; a gate run before that point under the guided profile reports `confirmed_by:` missing — that is expected, not a failure to fix by hand. At `design-pr` and `ship-pr`, after writing `confirmed_by:` (and, at `ship-pr`, the go/no-go answer) and running the gates green as `next.sh` renders them (`bash scripts/next.sh --gates`), `/next` runs `git add` on all of the lane's artifacts (new and edited) — exactly the path sets `next.md` names at that point, nothing else — and commits them — `git commit -m "docs(guided): confirmed_by: <handle> <date> — acknowledgements at design-pr (REQ-389)"`, or `…at ship-pr (REQ-389)` — and only then runs `create-pr`, so the pushed branch carries what the gates checked. Under a `### Guided proposals` heading, give each proposal a `Rationale (plain English):` line and a `What this means for you:` line, in words a non-engineer follows. Two kinds of proposal. The product scope is a **decision**: ask it, once, before writing the spec, and record the answer. The `[verifiable]` and `[verifiable-model]` tags are **acknowledgements**: show them with their one-line rationales and do not ask; the user acknowledges by confirming. Record both in the spec under `### Guided proposals`, and add `confirmed_by: <handle> <YYYY-MM-DD>` to the spec's frontmatter (REQ-389). The verifier's full mode confirms the acknowledgements provisionally in guided solo mode.
