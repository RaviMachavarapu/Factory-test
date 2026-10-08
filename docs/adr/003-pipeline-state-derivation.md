---
id: ADR-003
status: accepted
date: 2026-09-25
addresses: [REQ-341]
---

# ADR-003: Pipeline state is derived, never stored, by a total function over an enumerated state set

## Context
`art-branch-as-state` forbids an out-of-band state file; the objective review found there is no orchestrator. REQ-341 asks `/next` to derive `(lane, phase, next_step)` from the branch, the PRs, the tree and `.specflow.yml`, as a `[verifiable-model]` function. The spec review demanded an enumerated state set, merged PRs as an input, a definition of `N` in `build/<slug>-N`, and an answer for two open lanes. The ARCHITECTURE review of the first draft found that its `main` rows never advanced the pipeline and overlapped, that several rows needed inputs the signature did not carry, that a merged PR or a missing `## Build N` matched no row, and that the proof obligation ("total and deterministic") was vacuous. This revision fixes each.

## Decision

### Kernel
`scripts/lib/specflow/state.py` exposes one pure function:

```
derive(branch: Branch, branch_pr: PR | None, open_lane_prs: Sequence[PR],
       facts: Facts, path: Path, solo: bool) -> Result
```

- `Branch` is parsed by the wrapper (`parse_branch`, total, splitting `build/<slug>-N` on the last `-`): `Main | Design(slug) | Build(slug, n) | BuildSec(id) | Ship(version) | Patch(slug) | PhaseSpec(slug) | PhaseArch(slug) | PhasePlan(slug) | Impl(n, name) | ImplSec(id) | PhaseValidate | PhaseSecurity | PhaseRelease | Unknown`; `build/sec-<id>` is matched before the generic `build/<slug>-N` split.
- `PR(number, open, merged, closed, human_approved, attestation)`, where `branch_pr` is the newest PR whose head branch name equals the current branch; `human_approved` comes from `gh pr view --json reviewDecision == APPROVED`; `attestation ∈ {none, approve, request_changes, waiver}` is reduced by the shared classifier `scripts/lib/specflow/attestation.py` (rules of REQ-311/382: unedited comment, author association, `sha` equals head, `prompt_sha256` matches base, one marker per comment, newest wins; when several PRs share a head, the newest PR wins). The classifier is fixture-tested, not proved, and is the same module the CI check uses.
- `Facts` is a record of booleans and small values the wrapper computes; **the kernel decides order and precedence, never whether an artifact is complete**: `has_brainstorm`, `has_spec`, `spec_has_tagged_reqs`, `arch_complete` (ADR per tagged REQ, overview, threat model present), `has_plan`, `build_sections: set[int]`, `analyze_ok` (both analyze scripts exit 0), `has_source_diff` (vs base), `gates_pass`, `has_security_docs`, `has_release_docs`, `signing_key_present`, `pr_state_known` (false when `gh` failed or there is no remote); plus `unbuilt: list[(slug, n)]` (plan sections with no merged build PR), `untagged_ship: version | None` (a merged ship PR whose tag is absent), `next_version: version | None` (set iff at least one build PR merged since the last tag; the wrapper computes it from merged PRs and tags).
- `.specflow.yml` is configuration (`path`, `profile`, …), never state; nothing is written by `derive` or the wrapper.
- `Result(lane, phase, step, open_lanes)`; `step` is a `Step` datatype (`RunBrainstorm | RunSpecify | RunArchitecture | RunPlan | RunAnalyze | RunImplement(n) | RunGates | RunSecurityReview | RunRelease | CreatePr | RunVerifier(pr) | Merge(pr) | Checkout(pr) | CheckoutMain | NewBranch(name) | AddressFindings | TagRelease(version) | ExplainUnknown`). Rendering a `Step` to the literal command text (`render_step`, with slug, version, plan path and repo path filled in) is a wrapper function, fixture-tested, so strings stay out of the proof. `next_step` therefore contains everything the user must type, including for `RunVerifier` the full second-terminal instruction in the bootstrap form `git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>` (REQ-385 and REQ-313 as amended; `main`'s reviewed copy for every PR since the SEC-004 back-edge — before it the PR's own base, `refs/remotes/origin/<base>`, which on a stacked PR is unreviewed, and a stacked PR's instruction now names that base PR instead; the full ref since P6 build 3, as a tag named `origin/<base>` would shadow the short name; a governance test asserts `render_step(RunVerifier)` contains it, so a PR can never make `/next` run its own copy of the script).

### Precedence, in order
1. `branch_pr` is open → PR substate: `Blocked` if `request_changes`; `AwaitingVerifier` if `none`; otherwise (`approve` or `waiver`) `AwaitingMerge` when `solo` or `human_approved`, else `AwaitingHumanReview` (step `RequestReview`). In the guided profile `Merge` is emitted only after the pre-merge confirmation point (REQ-342 as amended).
2. `branch_pr` is merged → `(lane, Merged)`, step `CheckoutMain`; closed without merging → `(lane, Closed)`, step `ExplainUnknown` ("reopen the PR or delete the branch").
3. `Main`: open lane PRs **authored by the current user** → `(none, AwaitingMerge)`, step `Checkout(lowest-numbered own PR)`; other users' open PRs never block and are only listed in `open_lanes`; else `untagged_ship` → `(ship, Tag)`, step `TagRelease(version)`; else `unbuilt` non-empty → `(none, NextBuild)`, step `NewBranch(build/<slug>-N)` for the lowest `(slug, n)`; else every build of every live plan merged and `next_version` set → `(none, ReadyToShip)`, step `NewBranch(ship/<version>)`; else `Idle`, step `NewBranch(design/<slug>)` followed by `RunBrainstorm` (brainstorm first; `<slug>` is a placeholder the user fills).
4. Lane branch: the phase is the first missing artifact **after the last present one** in the lane's ordered list (so an existing spec with no brainstorm does not send the user back), **except** Architecture: when `spec_has_tagged_reqs` and not `arch_complete`, the phase is Architecture regardless of later artifacts (it is a gate, REQ-320, not an optional step).
5. `CreatePr` is never emitted when `pr_state_known` is false; the step is `ExplainUnknown` ("cannot see PRs: check `gh auth status` and the remote").

### State table, lanes path
| Branch | Condition | State | Step |
|---|---|---|---|
| `design/<slug>` | neither brainstorm nor spec | `(design, Brainstorm)` | `RunBrainstorm` |
| `design/<slug>` | no spec | `(design, Specify)` | `RunSpecify` |
| `design/<slug>` | `spec_has_tagged_reqs` and not `arch_complete` | `(design, Architecture)` | `RunArchitecture` |
| `design/<slug>` | no plan | `(design, Plan)` | `RunPlan` |
| `design/<slug>` | not `analyze_ok` | `(design, Analyze)` | `RunAnalyze` |
| `design/<slug>` | no PR | `(design, OpenPr)` | `CreatePr` |
| `build/<slug>-N` | `N ∉ build_sections` | `(build, UnknownBuild)` | `ExplainUnknown` ("add `## Build N` via a design PR, or check out an existing build") |
| `build/<slug>-N` | not `has_source_diff` | `(build, Implement)` | `RunImplement(N)` |
| `build/<slug>-N` | no PR | `(build, OpenPr)` | `CreatePr` |
| `build/sec-<id>` | not `has_source_diff` | `(build, Implement)` | `RunImplement(sec)` (security back-edge, `art-threat-driven-security`: fix with TDD, then re-run VALIDATE, then resume the ship lane) |
| `build/sec-<id>` | no PR | `(build, OpenPr)` | `CreatePr` |
| `patch/<slug>` | not `has_source_diff` | `(build, Implement)` | `RunImplement(0)` (patch tier: spec delta + implementation in one PR; the gates, not `derive`, enforce that no `[verifiable*]` REQ changed) |
| `patch/<slug>` | no PR | `(build, OpenPr)` | `CreatePr` |
| `ship/<version>` | no security docs | `(ship, Security)` | `RunSecurityReview` |
| `ship/<version>` | no release docs | `(ship, Release)` | `RunRelease` |
| `ship/<version>` | no PR | `(ship, OpenPr)` | `CreatePr` |
| any lane branch with an open PR | per precedence 1 | `AwaitingVerifier` / `AwaitingHumanReview` / `AwaitingMerge` / `Blocked` | `RunVerifier(pr)` / `RequestReview(pr)` / `Merge(pr)` / `AddressFindings` |
| any lane branch with a merged PR | precedence 2 | `(lane, Merged)` | `CheckoutMain` |
| any lane branch with a closed, unmerged PR | precedence 2 | `(lane, Closed)` | `ExplainUnknown` |
| `main` | precedence 3 | `AwaitingMerge` / `(ship, Tag)` / `NextBuild` / `ReadyToShip` / `Idle` | as listed |
| any other branch | — | `(none, UnknownBranch)` | `ExplainUnknown` |

`TagRelease` in the guided profile pauses at a confirmation point when `signing_key_present` is false (an annotated tag is a trust downgrade the founder must accept explicitly; REQ-342/383 as amended). There is no `Done` state: after the tag, `main` derives `Idle`, and `--explain` names the last released version and recommends `/retrospective` (a convention, not a state).

### State table, regulated path
Same construction, one branch per phase, slugs carried: `phase/spec-<slug>` → Brainstorm, Specify, OpenPr; `phase/arch-<slug>` → Architecture, OpenPr; `phase/plan-<slug>` → Plan, Analyze, OpenPr; `impl/plan-N-<name>` and `impl/sec-<id>` → Implement, OpenPr (the back-edge branch on the lanes path is `build/sec-<id>`); `phase/validate` → `(validate, Gates)` with `RunGates` until `gates_pass`, then OpenPr; `phase/security` and `phase/release` take their version from `next_version`. `main` precedence proposes the next `phase/*` branch instead of a lane. Legacy fixed-name branches (`phase/spec` without a slug) derive `UnknownBranch`.

**Mixed histories:** `derive` recognises both paths' prefixes regardless of `path`; the configured path only chooses which branch names precedence 3 proposes. The factory itself switches from regulated to lanes at P6 (REQ-381) and stays derivable because merged `phase/*`/`impl/*` PRs are visible through `open_lane_prs`/`unbuilt` like any other.

### Proof obligations
`verification/factory_v3_2/state.dfy` (`// Proves: REQ-341`) proves, over the enumerated datatypes: **MergeOnlyWhenApproved** (a `Merge(pr)` step is emitted only when `branch_pr` is open with attestation `approve` or `waiver`, `pr` is its number, and either `solo` or `human_approved` — REQ-385 and `art-review-gate`'s "verifier review and human approval"); **NoBlindCreatePr** (`CreatePr` is never emitted when `pr_state_known` is false); **PathClosure** (no regulated-only phase under `path: lanes` and vice versa for proposed branches); **PrPrecedence** (an open PR always yields a PR substate); **Progress** (setting the first missing fact moves the phase strictly forward in the lane's order). Totality and determinism follow from the datatypes and are stated, not laboured.

## Consequences
- The `Branch`/`PR`/`Facts` records above are the source of truth for the P5 plan; `Step` gains `RequestReview(pr)` and `RunImplement(sec)`.
- `/next` (REQ-342) and the guided profile (REQ-389) are thin: they render and print or run `step`; all judgement is in `derive`. `--json` emits `Result` including `open_lanes` for the dashboard (REQ-370).
- REQ-341/342/385 are amended in this PR: idle proposes a design branch and brainstorm first; inputs are `Facts`; `Done` is removed; `open_lanes` is part of the output; the second-terminal instruction is spelled out; pre-merge and unsigned-tag confirmation points exist; `patch/<slug>` and `build/sec-<id>` prefixes are named (REQ-340).
- `.claude/rules/review-gate.md` must document both paths before `--path lanes` can be chosen at init; P1 therefore ships the lane-to-phase mapping (REQ-343 moves its rule text to P1; the orchestrator stays P5), or init refuses `--path lanes` until it lands.
- Adding a lane or phase means a table row, a datatype constructor, a `Facts` field if needed, and fixtures.

## Alternatives Considered
- **A state file**: rejected; banned by `art-branch-as-state` and the failure that killed SpecFlow v1/v2.
- **GitHub labels as state**: rejected; mutable out-of-band state, unavailable offline.
- **Branch name alone**: rejected; cannot tell "spec written" from "not yet", nor PR substates.
- **Open PRs only as input**: rejected; a merged build lane is closed, so ship readiness was underivable.
- **Artifacts as bare paths (first draft)**: rejected; five rows needed contents, exit codes or tags. A `Facts` record makes the wrapper's responsibilities explicit and the kernel provable.
- **A persistent `done` state**: rejected; once any tag existed it could never return to idle.
- **Dafny compiled to Python**: rejected for v3.2 for the reasons in ADR-002.
