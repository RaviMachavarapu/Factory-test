---
date: 2026-09-25
target: ARCHITECTURE artifacts for 2026-09-25-factory-v3-2 @ c47471f (draft 1)
reviewers:
  - persona: skeptical-architect
  - persona: security-reviewer
  - persona: dafny-modeler-implementer
  - persona: customer-engineer-and-founder
verdict: REQUEST_CHANGES on draft 1 → revised in the same branch (see Disposition)
---

# Fresh-Eyes Synthesis — Factory v3.2 ARCHITECTURE

Four parallel reviewers read ADR-002, ADR-003, the overview and the threat model. The modeler wrote both Dafny models in scratch and verified them (5 and 7 obligations, 0 errors), which made the structural defects in the first draft concrete rather than argued.

## Convergent findings (≥2 reviewers)

| # | Finding | Flagged by | Disposition |
|---|---|---|---|
| 1 | **ADR-002 carry-forward never ends**: every prior accepted/deferred entry stays due forever after a later version fixed it; two prior entries for one id have no winner. | architect, modeler | **fixed:** latest prior entry per id (semver order), any status; open, critical and high prior entries carry forward too. |
| 2 | **Set equality was a rule in the ADR and a precondition in the spec**; duplicates undetectable; "lows never affect the result" false under rule 1. | architect, modeler | **fixed:** rule 1, duplicates are parser errors, invariant reads "lows never affect rules 2–5", postcondition is an iff (REQ-322 amended). |
| 3 | **An open critical can be relabelled to low, deleted from both files, or parked in an untagged version** and still pass. | security, architect | **fixed:** severity derived from a required CVSS vector; review ids may only be added between base and head; prior open entries carry forward; exactly one untagged version with docs or error; cap from the base ref; expiry horizon (ADR-002, REQ-322/324 amended). |
| 4 | **ADR-003's `main` rows never advance the pipeline and overlap** (`idle`, `(ship, tag)`, `done` all match); `done` is permanent. | architect, modeler, customer | **fixed:** explicit `main` precedence (awaiting-merge → ship tag → next-build → ready-to-ship → idle); `done` removed; idle proposes the design branch and brainstorm first. |
| 5 | **Rows need inputs the signature does not carry** (file contents, script exit codes, diffs, tags). | architect, modeler | **fixed:** `Facts` record computed by the wrapper; kernel decides order and precedence only. |
| 6 | **Inputs with no row**: merged/closed PR, `build/<slug>-N` with no `## Build N`, regulated branches without a version, other-path branches, legacy fixed names. | architect, modeler, customer | **fixed:** `(lane, merged)`, `unknown-build`, `next_version` fact, both prefixes recognised, legacy names → `unknown-branch`. |
| 7 | **"Total and deterministic" is a vacuous proof obligation**; the REQ-385 merge-safety property was not stated. | modeler, architect | **fixed:** named lemmas merge-only-when-approved, path closure, PR precedence, progress (REQ-341 amended). |
| 8 | **Attestation classification credited to `derive`** but it receives a reduced enum; CI and `next.sh` would duplicate the rules. | modeler, architect, security | **fixed:** shared fixture-tested `attestation.py`; threat model and overview corrected; REQ-311 amended. |
| 9 | **Guided `/next` would auto-merge and auto-downgrade to an unsigned tag without a confirmation point.** | architect, customer | **fixed:** confirmation points before merge and before an annotated tag (REQ-342/383 amended). |
| 10 | **Idle skipped BRAINSTORM**, sending users backward and, in guided mode, past the founder's first confirmation. | customer, modeler | **fixed:** idle step creates the design branch and runs brainstorming; "first missing artifact after the last present one". |
| 11 | **The second-terminal step is unexplained** for the copy-paste user. | customer, founder persona | **fixed:** full rendered instruction (REQ-385 amended). |
| 12 | **Mermaid syntax and threat-model list inconsistencies** (`[/…]` shape, `<stack>`, missing boundary). | architect, security | **fixed:** labels quoted, `verifier-to-github` boundary added. |

## Single-reviewer findings kept

- **Security:** maintainer workstation and user-scope MCP servers as an exfiltration channel (new dfe-9; REQ-313 amended: empty MCP config, `mcp__*` disallowed, reads outside the worktree denied, symlink refusal, bootstrap from base ref); PR-head code executed locally (dfe-10, warning in `/next`); suppression configs (dfe-11, allowlist narrowed, growth needs `SEC-NNN`); the signing anchor is inside the tree it protects (dfe-12, verify against `allowed_signers` as of the previous signed tag, tag ruleset requested); Dependabot exemption identification (dfe-13); `.specflow.yml` policy keys read from the base ref (dfe-6); missing STRIDE letters added; assets for policy/gate code and `allowed_signers`; honest "self-attested, forgeable in solo mode on any plan" wording; a "Delivered in" column so no mitigation reads as live; `implements:` self-declaration closed at ship time (REQ-324 amended).
- **Modeler:** `Step` datatype with rendering outside the proof; Python interface and fixture discipline recorded in the overview; effort S (disposition) and M (state); `[verifiable-model]` is the honest tag for both.
- **Customer:** mid-build discovery of a needed `## Build 2` is now derivable (`next-build` on `main` after the plan gains the section via a design PR); cross-lane visibility via `open_lanes`; review-gate.md must document both paths before `--path lanes` is selectable (REQ-343 amended: rule text moves to P1).
- **Architect:** "Dafny compiled to Python" alternative recorded and rejected with a reason; `check-test-first.sh` must error on empty globs (REQ-321 amended).

## Decisions left to the human partner
- **Spec amendments landed in this ARCHITECTURE PR** rather than a separate spec PR, because every one of them is a defect the architecture review exposed in REQ-322/341 and their neighbours; the PR body lists each amended REQ. If you prefer a separate spec PR, say so and I split it.
- **Repository visibility** (Open Question 5) remains the only lever that turns the solo gate from audit trail into control.

## Disposition
All 12 convergent findings and the kept single-reviewer findings are dispositioned into draft 2 (same branch, next commit). The ARCHITECTURE exit gate is met mechanically: both `[verifiable-model]` REQs map to kernel modules; the threat model has 8 trust boundaries, 8 assets with CIA, STRIDE letters on all 12 external elements, and an answered domain checklist.
