<!-- Phase PR checklist — delete sections that don't apply. -->

## What

<!-- One paragraph. Which phase / plan / fix is this? Reference REQ-NNN / ADR-NNN / SEC-NNN ids. -->

## Gate checklist

- [ ] `bash scripts/run-quality-gates.sh` exits 0 locally
- [ ] Verifier run from a terminal **outside** any Claude Code session, bootstrapped from `main`'s reviewed copy, stacked PR or not (SEC-004): `git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR#>` — the `verifier` check is green only on an `APPROVE` marker or a waiver for the current head
- [ ] If waived: link to the waiver comment and its rationale (REQ-382)
- [ ] Constitution citations use `art-*` slugs, never Roman numerals

### Lane checklists (keep the one that applies)

#### Design lane — design/<slug>; regulated: phase/spec-<slug>, phase/arch-<slug>, phase/plan-<slug>

**SPEC** — spec has lifecycle frontmatter (`status: draft`), Scope subsection, globally-unique REQ ids; `[verifiable*]` tags carry a Verification scope line.

**ARCHITECTURE** — every `[verifiable]`/`[verifiable-model]` REQ appears in a `kernel_modules.req_map`; threat model has ≥1 trust boundary, ≥1 asset with CIA, STRIDE per external element.

**PLAN/ANALYZE** — plan frontmatter has `spec:` + `decisions:` + `implements:`; `bash scripts/analyze-adr-plan-linkage.sh` passes; the plan may carry test code and implementation as intent, no implementation bodies.

#### Build lane — build/<slug>-N, build/sec-<id>, patch/<slug>; regulated: impl/plan-N-<plan slug> (N the plan's ## Build N section), impl/sec-<id>, phase/validate

**IMPLEMENT** — failing test existed before each implementation change (`art-test-first`); `[verifiable*]` REQs have `.dfy` proofs with `// Proves:` headers; tests carry `# Covers:`.

**VALIDATE** — on the lanes path CI on this PR is VALIDATE; on `phase/validate`, `bash scripts/run-quality-gates.sh` is green.

#### Ship lane — ship/<version>; regulated: phase/security, phase/release

**SECURITY** — `bash scripts/check-security-disposition.sh --version <version>` passes (ADR-002: no open critical/high, mediums within `medium_cap` with owner and expiry, carry-forwards re-listed). A downgrade needs both `reclassified_by:` (the second reviewer's handle, never the `owner:`) and a `rationale:` that names that reviewer.

- [ ] (SECURITY) If this PR edits a released version's review or disposition: schema-migration edits to a released review/disposition confirmed by the maintainer (docs/security/README.md) — header or syntax only, no SEC id added, removed or re-scored; the confirmation is stated in the merge or approval comment

**RELEASE** — `bash scripts/verify-release.sh --version <version>` passes (three docs, the tag does not exist yet, manifest rows, known-limitations, the disposition gate, every `[verifiable*]` REQ claimed and proved, the previous release's tag checked); the signed tag is created after the merge.

- [ ] (RELEASE) The maintainer confirmed by hand that the previous release's tag exists, is signed (or annotated with the fallback recorded in that version's known-limitations) and is on that release's merge commit, and the previous ship PR's `gates` and test-first checks were green at its merge — `release.yml` replays gates section 7 at the tag, never sections 1–6 or `check-test-first.sh`, so a published Release alone proves neither (a missing tag is only a WARN in `verify-release.sh`) — as `art-release-readiness` requires ("tag missing" is judged after the merge)

## Tier

- [ ] Full phase PR
- [ ] Patch tier (spec-delta + impl + validate in one PR — see review-gate.md)
- [ ] Minor exception (doc-only; see bounds in review-gate.md)
