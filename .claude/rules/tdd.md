# TDD Enforcement

**This rule loads at every session start.** Operational rule for `art-test-first`.

Before writing ANY implementation code:
1. A failing test for that code MUST already exist.
2. Run the test and confirm it FAILS (e.g., `pytest <test_file> -x`, or
   `bash tests/governance/<test>.sh` for governance behavior).
3. Only then write the minimum implementation to make it pass.
4. Refactor. Confirm it still passes.

If you find yourself writing implementation code without a corresponding
failing test, STOP. Write the test first. This is non-negotiable.

Scope notes for this factory:
- "Implementation code" includes shell scripts in `scripts/` and CI workflow
  logic — governance tests in `tests/governance/` are their test layer.
- `[verifiable-model]` requirements additionally need a Dafny proof in
  `verification/` (`art-formal-verification`); the proof complements, never
  replaces, the failing test.
- Test-first per commit is checked by `scripts/check-test-first.sh` (REQ-321)
  in `ci.yml`'s `gates` job, on every PR that changes a source file under the
  pack's `source_roots` (in the template source, `scripts/template-pack.yml`):
  a matching test file must gain a non-blank, non-comment line in the same or
  an earlier commit (a `#[cfg(test)]` hunk in the same `.rs` file counts for a
  Rust cfg-test rule), and a listed commit or the PR body must cite a
  `REQ-NNN`. The verifier's code mode reads the same commits as a second,
  judgement-based pass for what the script cannot prove — that the test
  actually exercises the changed code, not merely that one changed: a rule is
  satisfied for every later commit once any matching test gained a line; the
  per-change pairing is code mode's second pass. Residual: the walk is
  `rev-list --no-merges`, so conflict resolutions made in merge commits are
  not walked.
