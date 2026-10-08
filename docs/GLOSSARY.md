# Glossary

Plain-English definitions of terms used across this template's docs,
`constitution.md`, and the pipeline tooling.

### /next

The command that derives where the pipeline is from branches, PRs and files,
and prints (engineer profile) or runs (guided profile) the next step. It
never runs the verifier or merges without a confirmation. In the template
source, which has no `.specflow.yml`, the defaults apply (guided); the
factory's own sessions run `bash scripts/next.sh --profile engineer --explain`.

### ADR

Architecture Decision Record. A short document in `docs/adr/` capturing one
architectural decision, its context, and its consequences. Produced in the
ARCHITECTURE phase.

### Attestation marker

The script-written first line of a verifier comment — never the model's own
text — carrying the head and base `sha` (SHAs), the base-ref prompt hash,
the model, the verdict, a findings digest, and the run's origin. The
`verifier` CI check parses this marker and judges it, staying red until the
PR's comments resolve to `approve` or a maintainer waiver for the current
head. The full rule set — author association (OWNER, MEMBER or
COLLABORATOR, a MEMBER or COLLABORATOR only with the admin, maintain or write
repository role: an unreadable role is never accepted and keeps blocking; a
known `read`, `triage` or `none` role neither accepts nor blocks; any other role name
is resolved through the legacy `permission` field, else treated as unreadable), head SHA, the recorded base (an `APPROVE` must give the head the same
merge base as the PR's current base; a `REQUEST_CHANGES` recorded against another base still blocks (`request-changes-base-mismatch`) until a newer accepted `APPROVE` or waiver supersedes it), base-ref prompt hash, findings digest,
verdict, mode, origin, edits, waivers, the Dependabot exemption and
precedence among comments — is `scripts/lib/specflow/attestation.py` and the claim table in
`.claude/rules/review-gate.md`; this entry does not restate it.

### Awaiting verifier

An open PR with no accepted verifier marker for its head. `/next` prints the
second-terminal command that runs the verifier; it never runs it itself
(`art-review-gate`).

### Back-edge

The protocol for looping back to IMPLEMENT when SECURITY finds a critical
or high finding that requires a code change, without restarting the whole
pipeline. See `.claude/rules/review-gate.md`.

### Build lane

The lanes-path branch `build/<slug>-N` that carries the IMPLEMENT work for
one "## Build N" section of a design-lane plan.

### Code mode

The verifier's review mode for anything that is not a document — scripts,
workflows, application code, tests, proofs. A code-only PR gets code mode,
a doc-only PR gets full mode, and a mixed PR gets both; every non-document
path is code mode's scope, including a stack pack's `verifier_deny:` roots,
`.gitignore` and `.gitattributes`. Markdown is a document, except that
`.md` files under `.claude/` and `.github/`, and model-instruction Markdown
that instances load as session instructions — any `CLAUDE.md` or
`CLAUDE.local.md` at any depth (Claude Code loads nested ones from every
subdirectory), Markdown under a stack's `overlay/` or `skeleton/` directory
(`stacks/<stack>/overlay/**`, `stacks/<stack>/skeleton/**`), and Markdown
under `templates/` — are both a document
and code, so both modes see them. Only `.editorconfig`, images and the
repository-root `LICENSE`/`NOTICE` files (`LICENSE`, `LICENSE.md`,
`LICENSE.txt`, and the same for `NOTICE`) are neither.

### Confirmation point

One of the seven moments the guided profile pauses and waits for the user:
brainstorm end, design PR, build PR, ship PR, awaiting verifier, merge, and
unsigned tag. `/next` prints `confirm: <id>` at each, in the guided profile only; the engineer
profile prints no `confirm:` line.

### Constitution article

One of the twelve non-negotiable rules in `constitution.md`, cited by its
`art-*` slug (never a Roman numeral).

### Coverage floor

The minimum test coverage percentage (`coverage_min` in `.specflow.yml`,
read at the base ref as well so a PR cannot lower the number) that
`run-quality-gates.sh` enforces per toolchain before a change is
considered fully tested: `pytest --cov=src` for python, `vitest`
thresholds and `cargo llvm-cov` for tauri, and `lcov-threshold.sh` for
flutter. For python the gate's own coverage config honours no
`# pragma: no cover` and its own pytest configuration ignores a PR's
`addopts` (a `conftest.py`, being code, is left to review); tauri's `vitest.config.ts` and in-source ignore
comments (`/* v8 ignore */`, Dart's `// coverage:ignore-line`) are read
from the PR and can narrow what is measured — review, not the gate,
catches those.

### Covers annotation

A `# Covers: REQ-NNN` (or `// Covers: REQ-NNN`) comment line — comma lists
allowed — at the top of a test file, linking it to the requirement it
verifies, checked by `check-covers.sh` so every claimed REQ has a test
that cites it — a governance `test_*.sh` with at least one check (`ck`),
the Covers line placed before the `finish` call that ends every governance
test (a line after it is never read), or a pack test file with a test
function (the Covers line in its header comments). The check proves the citation, not that the test
exercises the requirement; review judges that.

### Dafny proof

A formal verification proof, written in Dafny and stored under
`verification/`, that a `[verifiable]`/`[verifiable-model]` requirement's
model holds. Complements, never replaces, a failing test.

### Dependabot exemption

A PR opened by `dependabot[bot]` passes the `verifier` check without a
marker (in solo mode it merges with no second review) only when every
commit is authored by `dependabot[bot]`, is GitHub-**verified**, and is
committed by `dependabot[bot]` or **`web-flow`** (the committer for a commit
made through the GitHub API/UI; measured 2026-09-27 on real Dependabot PRs,
Dependabot's own commits are committed by `web-flow`, so it cannot be
dropped). The verified/`web-flow` check does not tie a commit to Dependabot:
GitHub gives every commit made through its API or UI committer `web-flow`
and `verified: true`, with an author the caller chooses, so anyone with
write access can create such a commit through the GitHub API and add it to a
Dependabot PR's branch. The check only rules out a plain `git push` of a
commit with a forged author. The real limit is the content rule: the diff
touches only known dependency manifests/lockfiles (`requirements.txt`,
`requirements.in`, `package.json`, `package-lock.json`, `Cargo.toml`,
`Cargo.lock`, `pubspec.yaml`, `pubspec.lock`) at any depth outside
**`.github/`** — any change under `.github/` always needs the verifier — and
only moves the versions of dependencies the base already lists: never a new
dependency in any manifest, a new lockfile, an npm lockfile that gains a
`node_modules/` entry or a name in any entry's dependency maps, an
index/VCS/git/path source or a non-dependency edit. Base and head are compared both ways: a line the head
removes is refused unless it is a version or hash line of a dependency whose
version moved — a removed pip option (`--index-url`, `--extra-index-url`,
`--find-links`, `--trusted-host`, any `-` line), a pubspec entry's `hosted:`,
`url:`, `path:`, `git:`, `ref:` or `sdk:` sub-key, a Cargo.toml
`registry`/`git`/`path` key, a package.json alias/file/git/URL spec, a
pubspec.lock `url:`/`source:`, a Cargo.lock `source`, or a package-lock
entry's `resolved` — and a `--hash=`, `sha256`, `checksum` or `integrity`
may change only for a dependency whose version changed in the same diff. A
package.json range must stay a registry range, never a dist-tag such as
`latest`. An npm lockfile must carry a `packages` map on both sides (a
lockfileVersion 1 file is refused outright, as base or head, and a v2 file's
legacy `dependencies` tree must mirror it), and each entry's `resolved` must
be the public registry's tarball of its own package and version. A forged
commit can therefore still move an existing dependency to another registry
version of the same package, on the same source, unreviewed (threat-model
dfe-13's residual). Any failure fails
closed: not exempt, the verifier must review it. `art-review-gate` states this
rule and its forgeable-author residual (amendment B, REQ-343).

Dependabot batches each ecosystem into one weekly PR (`.github/dependabot.yml`
groups). A workflow action bump touches `.github/`, which the classifier's
exemption refuses, so the verifier must attest it. A pip bump that moves only
`scripts/requirements.txt` passes the content rule and is exempt from the
verifier check; when it moves a gate tool's pin (ruff, black, pytest,
pytest-cov) the `gates` check stops it: `test_python_lockfiles.sh` pins each
to one version in `scripts/requirements.txt` and the pack lockfile
`stacks/python/skeleton/requirements.txt` (folding it into the pack lockfile
moves `stacks/python/pack.yml` too: `test_stack_packs.sh`,
`test_coverage_floor.sh`), and `enforce_admins: false` lets an admin merge past
a red `gates`. A bump of any other pin (build, setuptools, wheel, a transitive
dependency) passes both checks and can merge exempt (dfe-13's residual). So
the maintainer folds a week's batch into one attested `patch/<slug>` PR and
closes the Dependabot PRs as superseded (REQ-334).

### Derive

Computing the pipeline's state from branches, PRs and the tree, never
stored (`art-branch-as-state`). The rules live in
`scripts/lib/specflow/state.py`, proved in the template source. The Dafny
model stays in the template, so an instance's edit to `state.py` gets no proof
check (only its fixtures); the verifier's code mode names it as gate code.

### Design lane

The lanes-path branch `design/<slug>` that carries BRAINSTORM, SPECIFY,
ARCHITECTURE, PLAN, TASKS, and ANALYZE as a single PR. A follow-on design lane
for an existing spec uses its own slug (the factory's `design/factory-v3-2-p6`
for spec `2026-09-25-factory-v3-2`; for a spec slug `greet`, `greet-p2`):
`/next` derives `brainstorm` until the lane's plan
`docs/plans/<date>-<slug>-plan.md` exists (the newest, when several are
dated), then resolves the spec, its brainstorm and its architecture through
the plan's `spec:`. Any design lane may name any live spec there: `/next`
is advisory, and the verifier reads the documents the lane's PR carries.

### Disposition

The per-finding record in `docs/security/<version>-disposition.md` stating
whether a SECURITY finding is fixed, accepted, or deferred.

### Disposition gate

`scripts/check-security-disposition.sh`, the check over ADR-002's rules
(zero open critical/high, the accepted/deferred medium cap, no dropped
carry-forwards, no out-of-window expiries), backed by the proved kernel
`scripts/lib/specflow/disposition.py` and its Dafny model, which the
template keeps for itself (REQ-322). It runs at PR time
(gates section 7) on any PR that changes a security document and on every
`ship/<version>` PR, and blocks RELEASE by blocking that PR. A finding's
severity must equal the band of its required `cvss_vector` (CVSS v4.0);
relabelling `severity:` alone is a parser error.

### Engineer profile

The `.specflow.yml` `profile: engineer` setting: the human drives directly
and makes the calls, rather than reviewing Claude's plain-English proposals.

### Factory documents

The template carries the factory's own v3.2 design documents: its spec, the
pipeline-state decision record, the architecture overview and threat model,
the implementation plans, the reviews and the Dafny models. `scripts/init-project.sh`
removes them from a new project (the list is `scripts/factory-only.txt`, which
goes too), so your traceability, REQ numbers and proofs are your own; the python
demo stays as the worked example. You keep ADR-002, which defines the
disposition gate's rules 1-5 that your project runs. A `REQ-3xx` your documents
cite names one of the template's own requirements, kept as provenance. New REQ
numbers in your project continue after the highest `REQ-NNN` cited anywhere in it.
The Dafny model of `/next`'s rules (`state.dfy`) goes too, so an instance's edit to
`state.py` gets no proof check (only its fixtures); the verifier's code mode names
it as gate code.

### Facts

The small values `/next` reads from the tree for the derivation: which
artifacts exist, whether the gates passed, which builds merged.

### Fully tested

In this template, "fully tested" means automated code tests (pytest,
governance tests, and Dafny proofs where applicable) passing, plus the
security floor (no open critical/high SECURITY findings).

### Governance test

A test under `tests/governance/` that checks the pipeline's own scaffolding
— docs, scripts, rules — rather than product code. In the template source only,
`bash scripts/run-instance-tests.sh` runs a PR's governance tests committed since
`--base`, plus any named, inside a scaffolded instance and prints every instance
SKIP; in an instance it
refuses with a "template source only" message, since the instance's own gates
already run its tests.

### Guided profile

The `.specflow.yml` `profile: guided` setting: Claude proposes plain-English
summaries and the human confirms and merges, rather than driving directly.

### Kernel module

A module identified in the architecture as implementing a
`[verifiable]`/`[verifiable-model]` requirement, subject to
`art-kernel-boundary`.

### Lane

A stage of work on the lanes path (design, build, or ship), each its own
branch and PR, as opposed to the regulated path's phases.

### Lanes path

The `path: lanes` setting in `.specflow.yml`: three PRs (design, build,
ship) instead of the regulated path's seven phase branches.

### Manifest

`dist/manifest.json` (schema `specflow-manifest/2`), produced by the RELEASE
hook, listing release artifacts and their checksums; each `artifacts` entry
says whether it is reproducible (the source archive, the sdist, the wheel: the
same bytes from the same tree) or not (bundles). A python Release's manifest
also records the pushed image's digest, as a top-level `image` object
(`image.digest`), not as an `artifacts` entry. Only the reproducible subset is
transcribed into the notes. CI's manifest — `release-build.yml`'s on
the ship PR and `release.yml`'s attached to the
Release — is the record; a laptop build is a cross-check only.

### Pack minimum

The lowest macOS version a stack pack's bundle supports, set by the pack
(e.g. Flutter's is 12.0, because Xcode 27 rejects a lower
`MACOSX_DEPLOYMENT_TARGET`).

### Patch tier

The sanctioned light path (`patch/<slug>`, either path) for a small change
whose spec delta touches no `[verifiable*]` REQ, kernel-boundary module, or
trust boundary — one PR with spec delta + implementation + green gates.

### Phase

A stage of work on the regulated path (e.g. SPECIFY, ARCHITECTURE, PLAN),
each mapped to a branch prefix in `.claude/rules/review-gate.md`.

### Quality gates

`scripts/run-quality-gates.sh`: the mechanical CI gate running tests, lint,
Dafny, and governance tests for a given stack.

### Regulated path

The `path: regulated` setting in `.specflow.yml`: seven phase branches
(`phase/spec-*`, `phase/arch-*`, `phase/plan-*`, `impl/plan-N-*`,
`phase/validate`, `phase/security`, `phase/release`). `/next` reads a merged
`impl/plan-<token>-<name>` branch as `## Build <token>` of the plan whose slug
is `<name>`, and of no other plan (the token is the full token after `plan-`,
compared as a string, never reduced to digits: `1a`, `1b` and `1` are three
tokens); one whose `<name>` matches no plan slug counts for nothing, and
`--explain` names it.

### Release workflow

`.github/workflows/release.yml`, which runs on a pushed `v<version>` tag: it
re-checks the attestation marker, replays only the release checks at the tag
— gates section 7: the release documents, the disposition gate, the previous
tag, the REQ claims; never sections 1–6 or `check-test-first.sh`, so a ship
PR merged past a red `gates` check on those ships unless a human reads the
run — rebuilds the reproducible subset from a clean checkout and compares it
with the Artifacts rows the notes at the tag transcribed, then creates a
draft GitHub Release (the manifest, the artifacts, the image digest and, for
app stacks, the signed or unsigned bundle) that is published once every
asset is attached.

### REQ

A requirement identifier (e.g. `REQ-308`) used in specs, plans, and test
`# Covers:` annotations to trace a requirement from spec to code.

### Security floor

The tool floor `scripts/run-security-floor.sh` runs as section 5 of every
gates run: gitleaks over the full git history, osv-scanner over every
tracked lockfile, then the stack's own audits (pip-audit and bandit;
cargo-audit and npm audit; osv-scanner on `pubspec.lock`). A floor failure
is an advisory, a leak, a failed lookup or tool error (reported as such,
never as findings), or a missing floor tool, and the gates summary lists it
apart from gate failures. `SPECFLOW_FLOOR_OFFLINE=1` skips the advisory
lookups and its summary is not evidence. This is distinct from the SECURITY
exit bar — zero open critical or high findings, with accepted/deferred
mediums capped — which is the disposition gate, not the floor.

### Ship lane

The lanes-path branch `ship/<version>` that carries SECURITY and RELEASE
as a single PR. `/next` proposes `ship/<next_version>`, the minor version
after the newest `vX.Y.Z` tag (`0.1.0` when there is none); a release of
another version starts its `ship/<version>` branch by hand, and from then on
the branch's version is the truth.

### Smoke hook

`SPECFLOW_SMOKE=1`, which makes a stack's built skeleton start and exit 0;
`release.yml` runs it after each build through `scripts/release-smoke.sh` and
fails unless it exits 0 within 60 seconds (the image for python, the bundle's
executable for tauri and flutter, a self-check of the extracted source archive
for the template). `release.yml` runs the template's smoke itself now; the
image's and the bundle's run through the release actions Builds 4 and 5 add
(the stack's action, installed per stack where it exists). The app runs in a
process group of its own, killed whole on an overrun or an exit, and the
image as a named container that is stopped with `docker kill` and removed,
not only its CLI; an overrun prints a one-line reason. The honest limit: a
macOS helper launched through launchd or XPC is outside the process group,
so the smoke cannot kill it.

### Solo mode

The `.specflow.yml` `solo: true` setting for a single-person project:
`configure-repo.sh` requests zero required approving reviews, and the
verifier's own `APPROVE` under your identity stands in as the second
review — on any GitHub plan a self-attested audit trail, tamper-evident but
not an enforced control (the author can forge, re-roll or delete it,
`art-review-gate`), and not a substitute for the mechanical gates. On a free
private repository, in addition, GitHub enforces neither the checks nor the
review.

### Stack pack

A directory under `stacks/<stack>/` (e.g. `stacks/python/`) providing a
language's skeleton, quality-gate hook, release contract, and prerequisites,
copied into place by `init-project.sh`.

### Store checklist

`docs/releases/store-checklist.md`: an app stack's macOS distribution
checklist — signing, notarization, Gatekeeper, packaging, App Store versus
direct. `/release` appends it to each app release's notes; `release.yml`
refuses an app release without it. It is a checklist, not automation, and it
ends with the re-run sentence: re-run the tag after adding the secrets and
observe `signed: true`.

### Suppression

An ignore entry, allowlist string, fingerprint, `# nosec` marker, or
configuration key that hides a finding from a floor tool (gitleaks,
osv-scanner, pip-audit, bandit, cargo-audit, or npm audit). Every
suppression cites a `SEC-NNN` whose latest disposition entry is `accepted`
or `deferred` and names it in that entry's `suppresses:` list;
`check-suppressions.sh` enforces this. A configuration key or table is
named `<file>:<dotted key>[<digest>]`, the digest taken over its value, and
an array of tables (`[[PackageOverrides]]`, `[[rules]]`) is one suppression
per table, each citing its own `SEC-NNN` on its own header line — so a new
or changed entry needs a disposition change; the check prints the name to
list. An advisory suppression stops suppressing once its `ignoreUntil` date
passes, for every tool.

### Test-first check

`scripts/check-test-first.sh` (REQ-321), run by the `gates` job in
`.github/workflows/ci.yml` (a step of its own, not part of
`run-quality-gates.sh`) with the pack's policy read at the base ref, on every PR that changes a source file under
the pack's `source_roots`: a matching test file must gain a non-blank,
non-comment line in the same or an earlier commit as the source change
(a `#[cfg(test)]` hunk in the same `.rs` file counts for a Rust cfg-test
rule), and a commit or the PR body must cite a `REQ-NNN`. It proves only
that a matching test changed, not that it exercises the change — the
verifier's code mode is the second, judgement-based pass for that.

### Verifier

The adversarial review skill, bootstrapped from `main`'s reviewed copy for
every PR — a stacked PR's unreviewed base branch is never piped into bash
(SEC-004) — and run outside any Claude Code session
(`git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>`), in an
isolated worktree, on full mode (documents), code mode, or persona mode. It
always posts a marked comment, which the `verifier` check judges.
Never copy the bootstrap from a CI log; use the rendered line: on a stacked
PR the `verifier` job's log hint is printed by the unreviewed base's own
`attestation.py`, so it may be any pipe-to-bash line.

### Waiver

A maintainer's pass for the current head where the verifier cannot give
one: it overrides a `REQUEST_CHANGES` verdict, stands in for a bootstrap PR
with no acceptable marker (a base that predates the P2 verifier, whose
`--bootstrap` markers are never accepted), and clears a gitleaks false
positive that stops the findings from being posted (citing the redacted
rule id). It is a PR comment whose first line is
`<!-- specflow-verifier:waive sha:<40-hex head> base:<40-hex base> -->`
(`base:` optional: a waiver without it is a legacy waiver) followed by a
rationale of at least 20 characters, from an OWNER or MEMBER (GitHub's
`MEMBER` is any organisation member, including one with read-only access,
not a repository role, and on an organisation repository the maintainers
themselves are `MEMBER`, so a `MEMBER`'s waiver counts only when the commenter's
repository role is admin, maintain or write, read at check time: an unreadable
role is never accepted and keeps blocking; a known `read`, `triage` or `none`
role neither accepts nor blocks; any other role name is resolved through the
legacy `permission` field, else treated as unreadable; in team mode, someone who is neither the PR author nor an
author of any of its commits;
measured 2026-09-29 (PR #50): under the workflow's `GITHUB_TOKEN` a member whose organisation membership is private reads as `COLLABORATOR`, so rule 1b's role lookup, not `author_association`, is what admits that member's markers in CI, while a `COLLABORATOR`'s waiver is refused (`waiver-not-maintainer`): the maintainer's own waiver counts in CI only while their organisation membership is public — `gh api -X PUT orgs/<org>/public_members/<login>` makes it public),
linked in the PR body by convention — the link is not checked (REQ-382). Posting it does not re-run the `verifier` check: re-run the
`verifier` workflow afterwards (`gh run rerun <run-id>`, or edit the PR body,
which fires `edited`). A waiver does not override a blocking comment (an
edited, digest-mismatched, verdict-mismatched or multi-marker comment naming
the head), which must be deleted; and it wins only while it is the newest
accepted comment: a later `REQUEST_CHANGES` for the head supersedes it. A
bound waiver (with `base:`) is judged as an `APPROVE` marker is: a base that
gives the head another merge base than the PR's current base refuses it
(`waiver-base-mismatch`, refused, never blocking). A legacy waiver (no
`base:`) stands only while the PR's timeline has no base event at or after
the second it was posted — `base_ref_changed`, GitHub's automatic retarget
when the base branch is deleted (`automatic_base_change_succeeded` or
`_failed`), a `base_ref_force_pushed`, or any other `base_ref_*` or
`automatic_base_change*` event: a later retarget refuses it
(`waiver-unbound-retargeted`), and an unreadable timeline, or a base event with
no time, refuses it too (`waiver-timeline-unknown`, fail closed); post a bound
waiver naming the new base after retargeting. For a merged PR whose legacy waiver the
tag-time re-check refuses, the remedy is a bound waiver posted on that PR
naming its merge commit's first parent. On a PR whose base's classifier predates P7 (the factory's
own P7 Build 1 PR, judged by `main`'s; an instance's first upgrade PR after v3.2.0, judged by its v3.2.0 `main`'s),
post the legacy `sha:<head>` form: that classifier rejects the bound form as `malformed`; the bound form is accepted
once the base carries this classifier.
