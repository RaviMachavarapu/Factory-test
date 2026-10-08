---
name: analyze
description: ANALYZE phase — verify ADR-to-plan linkage, traceability, and doc structure before IMPLEMENT.
argument-hint: <slug>
---

You are entering the ANALYZE phase for `$ARGUMENTS`.

Run, in order:

1. `bash scripts/analyze-adr-plan-linkage.sh` — across every plan, checks
   that every `[verifiable]`/`[verifiable-model]` REQ the plan implements
   (its `implements:` frontmatter list, or the whole source spec when that
   field is absent) has an accepted ADR in the plan's decisions: field whose
   addresses: includes it.
2. `bash scripts/check-traceability.sh` — checks REQ IDs defined at most once
   across live (non-superseded) specs (plus ADR/SEC id uniqueness), that
   every `[verifiable]`/`[verifiable-model]` REQ a plan implements has a
   Dafny proof carrying a matching `// Proves:` header, and that no proof
   cites a REQ no live spec defines.
3. `bash scripts/verify-doc.sh docs/plans/<date>-$ARGUMENTS-plan.md` — must be
   silent.

Cross-check `docs/specs/<date>-$ARGUMENTS-design.md`: every spec REQ must
either appear in some plan's `implements:` list or be named under a
"Deferred by design" (or equivalent) section with the plan that will claim it
later. A REQ that is neither claimed nor deferred is a gap — fix the plan
before proceeding, not the checker.

If any check fails, fix the plan (never the scripts, unless the scripts
themselves are wrong — in that case say so explicitly and stop) and re-run
until all three are green.

Print a short PR summary: which REQs this plan claims in full, which in
part (and which later plan claims the rest), and the result of each of the
three checks above. Then proceed per `.claude/rules/review-gate.md`
(commit, push, open the PR, run
`git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR-number>` from a
separate terminal outside this session). It is `main`'s reviewed copy for
every PR: a PR stacked on another phase branch is still reviewed against its
base branch, whose script is never piped into bash (SEC-004).
