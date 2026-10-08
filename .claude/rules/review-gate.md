# Human Review Gate

**This rule loads at every session start.**

Before proceeding from one phase or lane to the next:
1. Ensure all work is committed to the phase or lane branch.
2. Push the branch and open a PR to `main`, or stacked on an open phase PR
   (its base is that PR's branch) when the next phase cannot wait for the merge.
   `configure-repo.sh` protects only `main`: a PR stacked on a phase branch
   merges into it with no required checks, and the final PR to `main` covers
   the combined diff.
3. Run the verifier from a separate terminal, OUTSIDE any Claude Code session
   (a Claude session cannot spawn another), bootstrapped from `main`'s
   reviewed copy of the script for every PR, stacked or not:
   `git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>`.
   A stacked PR's base is a branch no review has approved, which its author
   chose, so its script is never piped into bash (SEC-004): the script reads
   the PR's base from `gh` and reviews the PR against it, the policy, prompt,
   skill and constitution read at `refs/remotes/origin/<base>` as data, while
   the code it runs (`attestation.py`, `config.py`) is `main`'s. `/next`
   names a stacked PR's unreviewed base PR, to be merged first, then the
   stacked PR retargeted: after a squash merge the retarget makes the marker
   `base-mismatch` and the stacked PR is reviewed again against `main`;
   after the merge commit `/next` prints, the merge base is unchanged and
   the marker survives (step 6), the base's prompt, skill and constitution
   that steered it having been reviewed by the base PR before its merge.
   Never copy the bootstrap from a CI log; use the rendered line: on a
   stacked PR the `verifier` job runs the base's own `attestation.py`, so
   the bootstrap hint printed in its log is the unreviewed base's text and
   may be any pipe-to-bash line (SEC-004 re-review, dfe-10's residual).
   It reviews documents in full mode and code in code mode (a doc-only PR
   gets full mode, a code-only PR gets code mode, a mixed PR gets both) via
   `claude -p` on your Claude Code subscription, in an isolated worktree, and
   always posts a marked comment. Add `--persona` for persona mode. The
   `verifier` check passes only on an `APPROVE` marker or a maintainer waiver
   for the current head SHA. Team-mode alternative, for a fresh-context
   verifier subagent inside a session: `--print-prompt` to get the base-ref
   prompt, then post its findings with
   `git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR> --from-file <findings> --model <id>`
   — refused (`solo: false` required) when the base's `.specflow.yml` has
   `solo: true`, since a solo repository's second review must be a headless
   run outside the author's own session.
4. If `REQUEST_CHANGES` is posted, the `verifier` check fails: address the
   findings and re-run the command above, or a maintainer waives it by
   posting a comment whose first line is
   `<!-- specflow-verifier:waive sha:<40-hex head> base:<40-hex base> -->`
   (the `base:` part may be left out for a legacy waiver, which a later
   retarget refuses, step 6) followed by a
   rationale of at least 20 characters (in team mode, from someone who is
   neither the PR author nor an author of any of its commits), and linking
   that comment in the PR body (for a merged PR whose legacy waiver the
   tag-time re-check refuses as `waiver-unbound-retargeted`, the remedy is a
   bound waiver posted on that PR naming its merge commit's first parent,
   R4; convention: the PR template's checkbox;
   nothing checks the link). Posting the waiver does not re-run the check
   (the workflow has no `issue_comment` trigger): after posting it, re-run
   the `verifier` workflow (`gh run rerun <run-id>`, or edit the PR body,
   which fires `edited`). On a PR whose base's classifier predates P7 (the
   factory's own P7 Build 1 PR, judged by `main`'s; an instance's first upgrade
   PR after v3.2.0, judged by its v3.2.0 `main`'s), post the legacy
   `sha:<head>` form: that classifier rejects the bound form as `malformed`;
   the bound form is accepted once the base carries this classifier. A
   waiver does not override a blocking comment (an edited, digest-mismatched, verdict-mismatched or multi-marker comment
   that names the head): that comment must be deleted. A waiver wins only
   while it is the newest accepted comment: a later `REQUEST_CHANGES` for the
   same head supersedes it.
5. Team mode (`solo: false`) additionally needs one human approval from
   someone other than the author before merge. Solo mode (`solo: true`)
   needs zero approvals (`configure-repo.sh`) — the verifier's `APPROVE` is
   itself the recorded second review.
6. After merge, create the next phase branch from updated `main`. A stacked PR
   must be retargeted to the merged PR's base (`main`, or the branch it was
   itself stacked on) before that base branch is deleted. Retargeting
   fires `edited`, so both checks re-run against the new base, and the marker
   is judged against it: an `APPROVE` whose recorded base gives the head
   another merge base than the new base does reviewed another diff and is
   refused (`base-mismatch`), so run the verifier again, while
   a `REQUEST_CHANGES` recorded against another base still blocks
   (`request-changes-base-mismatch`) until a newer accepted `APPROVE` or
   waiver supersedes it. A waiver is judged the same way since P7 (R4): a
   bound waiver whose base gives the head another merge base than the new
   base is refused (`waiver-base-mismatch`), and a legacy waiver (no `base:`)
   posted before the retarget is refused once the PR's timeline records it —
   `base_ref_changed`, GitHub's automatic retarget when the base branch is
   deleted (`automatic_base_change_succeeded` or `_failed`), a
   `base_ref_force_pushed` or any other base event at or after the waiver's
   second (`waiver-unbound-retargeted`) — so post a bound waiver
   naming the new base after retargeting. When the base branch was
   merged into `main` with a merge commit (the command `/next` prints for a
   PR with a stacked PR on it), the merge base is unchanged and the marker
   survives the retarget; an update-branch required by strict protection
   (`gh pr update-branch <m>`, where the new base requires branches to be up
   to date) creates a new head, which needs a fresh verifier run or a waiver.

This is the operational rule for `art-branch-as-state` and `art-review-gate`.

## What enforces each claim

| Claim | Mechanism | Files |
|---|---|---|
| A verifier comment exists for the head and its verdict is enforced | The `verifier` job is a required check where branch protection works — a repository admin (a solo owner always is one) can merge past it because `enforce_admins` is false, and on a free private repository nothing server-side enforces it. The job runs the base's own `attestation.py` and `config.py` (materialised with `git show refs/remotes/origin/<base>:…` — the full ref since P6 Build 2's fix wave 2: the checkout brings tags, and a tag named `origin/<base>`, which anyone with write access can push, would shadow the short name and choose the classifier; the bootstrap a maintainer types — `git show refs/remotes/origin/main:scripts/run-verifier.sh`, `main`'s reviewed copy for every PR since the SEC-004 back-edge (before it, a stacked PR's own base) — and `run-verifier.sh`'s own base reads use the full ref too since P6 Build 3 (PR #54 verifier run 2, finding 3: before it, such a tag chose the script the bootstrap piped into bash); `next.sh`'s own git reads keep the short name, a convention residual of that developer's own advisory view (owner: kpingali123; the P6 plan's Deferred)), not the PR's (for a PR to `main`; on a stacked PR the base is itself unreviewed); the fallback is taken only when `git cat-file -e` finds no module at the base, and any other read failure fails the job. Only when the base predates the module (a v3.2-upgrade PR) does the head's copy run: in that bootstrap path the PR head's own classifier runs and is not a control (the PR can rewrite it), and a maintainer waiver is the route for an honest PR. Residual: under `pull_request` the workflow file itself comes from the PR, so a bypass needs an edit to `verifier.yml`, which code mode flags as gate code for a human (in solo mode, nobody else reads it); `pull_request_target` is proposed in `docs/BACKLOG.md` (BL-012) | `.github/workflows/verifier.yml`, `scripts/lib/specflow/attestation.py` |
| The marker is written by the script, not the model | `run-verifier.sh` writes the marker line itself after the model runs; the model cannot forge it into the posted comment | `scripts/run-verifier.sh`, `tests/governance/test_verifier_run.sh` |
| Verifier isolation — it cannot read outside the worktree or the denied secrets, run disallowed tools, load the PR's `CLAUDE.md` or rules, or be steered by the PR's own copy of its skill | `--restricted`, `--safe-mode`, the deny list; `bash scripts/run-verifier.sh --canary` checks the flags against the real `claude`. The script's comparison of itself with `main`'s copy is a guard against running the checkout's copy by mistake, not a control: `bash -s` bypasses it. Its `attestation.py` and `config.py` are `main`'s since the SEC-004 back-edge, so a stacked PR's unreviewed base supplies data only, never code: the base-read inputs that remain are the policy keys (`.specflow.yml`), the prompt template (`headless-prompt.md`), the skill (`SKILL.md`), the constitution and the pack's deny-list additions (`verifier_deny`), while the findings scan's `.gitleaks.toml` is `main`'s (SEC-021), since a base's could allowlist every string, and a stacked base without the entry point `main` carries is refused, never offered `--bootstrap`. Under `--bootstrap` the model is given the PR head's own skill and constitution and the head's classifier reads the policy; bootstrap markers are never accepted (`base-predates-attestation`) | `scripts/run-verifier.sh`, `tests/governance/test_verifier_isolation.sh` |
| Policy keys (`solo`, `profile`, `path`) come from the base ref, never the PR head | `attestation.py policy --ref` reads `.specflow.yml` at the base (for a PR to `main`; on a stacked PR the base is itself unreviewed); in the bootstrap path the PR head's own classifier performs that read | `scripts/lib/specflow/attestation.py` |
| Waivers need a maintainer (`OWNER`/`MEMBER`), a 20-character rationale, and (in team mode) someone who is neither the PR author nor an author of any of its commits | The classifier's waiver rules (commit authors from `gh api pulls/<PR>/commits`); team-mode approvals: `configure-repo.sh` sets `require_last_push_approval`, so the last pusher cannot approve their own push; PR-body link: convention (PR template checkbox), not checked. `MEMBER` is GitHub's `author_association` for any organisation member, including one with read-only access to this repository, not a repository role, and on an organisation repository the maintainers themselves are `MEMBER` (this repository's included), so a `MEMBER`'s waiver counts only when the commenter's repository role is admin, maintain or write, read at check time with `gh api repos/<repo>/collaborators/<login>/permission`; an unreadable role fails closed (`waiver-permission-unknown`), so a token that cannot read it rejects `MEMBER` waivers and leaves `OWNER` waivers working (R9). A marker (`APPROVE` or `REQUEST_CHANGES`) from a `MEMBER` or a `COLLABORATOR` (who may hold only the read or triage role) needs the same writing role. Rule 1b fails closed in both directions: an unreadable role is never accepted and keeps blocking; a known `read`, `triage` or `none` role neither accepts nor blocks; any other role name is resolved through the legacy `permission` field, else treated as unreadable. A known `read`, `triage` or `none` role is judged before any blocking rule (`marker-not-writer`, `waiver-not-writer`), so a read-only principal can neither supply the second review nor block it. This narrows the pre-P5 rule, under which a `MEMBER`'s comment blocked regardless of repository role: a `MEMBER` or `COLLABORATOR` whose role is known to be `read`, `triage` or `none` can no longer block, because a principal who cannot approve cannot block either — otherwise a read-only organisation member could hold any PR with a hand-posted `REQUEST_CHANGES` (REQ-382 as amended, plan R9). An unreadable role (`gh api` failed) is never accepted as an approval or a waiver (`marker-permission-unknown`, `waiver-permission-unknown`), but the blocking rules still run: an edited, multi-marker, digest- or verdict-mismatched comment naming the head still blocks (`edited-permission-unknown` and so on), and a `REQUEST_CHANGES` for the head still counts as one (`request-changes-permission-unknown`, superseded by a newer accepted `APPROVE` or waiver exactly as a writer's is); the check's output and `/next --explain` name each login whose role could not be read, and why; `run-verifier.sh` posts under the identity of the writer who runs it. Since P7 (R4) a waiver may bind the base — `<!-- specflow-verifier:waive sha:<40-hex head> base:<40-hex base> -->` — and is then judged as a marker is: a base that gives the head another merge base than the PR's current base refuses it as `waiver-base-mismatch` (refused, never blocking). A legacy waiver (no `base:`) is accepted only while the PR's timeline has no base event at or after the second it was posted — `base_ref_changed`, `automatic_base_change_succeeded`/`_failed` (GitHub's retarget when the base branch is deleted, unmeasured whether it also records `base_ref_changed`), `base_ref_force_pushed`, any `base_ref_*` or `automatic_base_change*` event (`waiver-unbound-retargeted`; an unreadable timeline, or a base event with no time, refuses it, `waiver-timeline-unknown`, fail closed); a commit-level waiver on a direct push has no timeline, and a bound one names the commit's first parent. Residual: the timeline read is GitHub's record of a retarget, a property of the platform with no expiry; a base rewritten with no timeline event (the merge base moves, nothing recorded) leaves a legacy waiver standing, where a marker or a bound waiver is refused by the merge-base rule — post bound waivers; and the read under the workflows' read-only `GITHUB_TOKEN` was measured by the draft-PR probe (P7 M0b, PR #67, run 37169624336, 2026-10-04 UTC: HTTP 200, the paginated `base_ref_changed` query answered), the precondition of Build 1's merge; it was measured under `pull_request`, and the tag-time read (`release.yml`'s verify job, the same read permissions) is unmeasured: owner kpingali123; recovery (R4): a bound waiver naming the merge commit's first parent clears a refused legacy waiver at the tag; pre-ship check: before the 3.2.1 tag the maintainer runs `scripts/release-tag.sh 3.2.1 --dry-run`, which runs `release-check` with the maintainer's token and so does not measure the workflow token; the tag-push read is measured by the first `release.yml` run itself, fail-closed: a refusal is `waiver-timeline-unknown`, recoverable by the bound waiver (PR #71 verifier run 1, finding 4). The solo marker is self-attested by the author (REQ-314), never by a third party. The draft-PR probe of `verifier.yml`'s read-only `GITHUB_TOKEN` against that endpoint was run on 2026-09-29 (PR #49, closed unmerged; run 36582019062, `permissions: contents/issues/pull-requests: read`): HTTP 200 with the role for a collaborator (`admin` for the maintainer), `permission: none` for a non-collaborator such as `github-actions[bot]`, HTTP 404 for a login that is not a user — so the fail-closed reasons `marker-permission-unknown`/`waiver-permission-unknown` arise only when `gh api` itself fails, not from the token's scope; if GitHub ever withdraws that read, every `MEMBER` or `COLLABORATOR` marker and waiver fails closed and the maintainer decides. `--permissions` is a test-only injection of roles; `verifier.yml` never passes it and any workflow that does is gate code (`tests/governance/test_attestation.sh` asserts no workflow passes it). Also measured 2026-09-29 (PR #50): under the workflow's `GITHUB_TOKEN` a member whose organisation membership is private reads as `COLLABORATOR`, so rule 1b's role lookup, not `author_association`, is what admits that member's markers in CI, while a `COLLABORATOR`'s waiver is refused (`waiver-not-maintainer`): the maintainer's own waiver counts in CI only while their organisation membership is public (`gh api -X PUT orgs/<org>/public_members/<login>` makes it public). On a personal (non-org) repository everyone but the owner is `COLLABORATOR`, so a team-mode waiver of the owner's PR needs an organisation or a second OWNER | `scripts/lib/specflow/attestation.py`, `scripts/configure-repo.sh`, `tests/governance/fixtures/attestation` |
| Solo waiver | Convention: self-posted by the author, possibly from a Claude Code session, and accepted; tamper-evident only | `constitution.md` |
| PRs opened by `dependabot[bot]` pass the `verifier` check without a marker only when every commit is authored by `dependabot[bot]`, is GitHub-verified, and is committed by `dependabot[bot]` or `web-flow`, and the diff touches only known dependency manifests/lockfiles (never `.github/`) whose content only moves the versions of dependencies the base already lists | The classifier's exemption (REQ-334 as amended, dfe-13), from the PR's commits (`gh api pulls/<PR>/commits`) and diff (`git diff --no-renames`). An author-email match alone proves nothing, since anyone with push access can set it; the verified/`web-flow` check does not tie a commit to Dependabot either, because GitHub gives every API/UI commit committer `web-flow` and `verified: true` with a caller-chosen author, so anyone with write access can create such a commit through the GitHub API (it only rules out a plain `git push` with a forged author; real Dependabot commits are committed by `web-flow`, measured 2026-09-27). The real limit is the content rule: a dependency-only diff that adds no dependency in any manifest and no new lockfile, and only moves versions; base and head are compared both ways, so a line the head removes is refused unless it is a version or hash line of a dependency whose version moved (a removed pip option such as `--index-url`, a pubspec `hosted:`/`url:`/`path:`/`git:`/`ref:`/`sdk:` sub-key, a Cargo.toml `registry`/`git`/`path` key, a package.json alias/file/git/URL spec, a pubspec.lock `url:`/`source:`, a Cargo.lock `source`, a package-lock `resolved`), and a `--hash=`/`sha256`/`checksum`/`integrity` changes only for a dependency whose version changed; a package.json range never becomes a dist-tag; an npm lockfile must carry a `packages` map (a lockfileVersion 1 file is refused outright) and each entry's `resolved` must be the public registry's tarball of its own package and version; an npm lockfile gains no `node_modules/` entry and no name in any entry's dependency maps (ranges may move, entries may disappear; R10); a forged commit can still move an existing dependency to another registry version of the same package, on the same source, unreviewed (dfe-13's residual). Any failure — an unverified commit, a non-dependabot/web-flow committer, a `.github/` touch, or a non-version-moving edit — fails closed: not exempt, the verifier must review it. In solo mode exempt PRs merge with no second review. `art-review-gate` states this rule and its forgeable-author residual (amendment B, REQ-343). | `scripts/lib/specflow/attestation.py`, `tests/governance/fixtures/attestation` |
| The mechanical gates run on every PR, to any base | `pull_request` triggers with no `branches:` filter | `.github/workflows/ci.yml`, `scripts/run-quality-gates.sh` |
| Solo or team approval counts and the required check names | `configure-repo.sh` requests zero (solo) or one (team) approving review and the stable checks `gates`/`verifier` | `scripts/configure-repo.sh` |
| Human approval in team mode | Branch protection's required-review count, where GitHub returns 403 (free private repos) this is convention, not server-enforced. Where protection works, `configure-repo.sh` sets `enforce_admins: false`, so a repository admin can merge without the required approving review as well as past red checks: on a team where the author is an admin, the approval is optional too | `scripts/configure-repo.sh` |
| Test-first per commit | `scripts/check-test-first.sh`, a step of the `gates` job in `.github/workflows/ci.yml` (not a `run-quality-gates.sh` section): per commit over `base..head`, per-pack rules, `#[cfg(test)]`, REQ citation from commits or the PR body. The policy (`source_roots`, `test_globs`, `test_first_rules`, `non_source`) is read from the pack at the base ref (in CI the base is the event's base SHA, never a name a tag could shadow), so a PR cannot relax its own; whether the tree is an instance (`.specflow.yml` or `.stack`) or the template source is judged at the base ref too, so adding or deleting either file cannot swap the policy; the PR that first adds `scripts/template-pack.yml` is judged by its own copy (bootstrap, not a control). It proves only that a matching test file gained a non-blank, non-comment line in the same or an earlier commit, not that the test exercises the change: a rule is satisfied for every later commit once any matching test gained a line; the per-change pairing is code mode's second pass (R15's approved semantics; in the template pack the four non-`src` rules share `tests/governance/test_*.sh`, so one added test line satisfies all four). Residuals: history rewritten before push; that gap; the walk is `rev-list --no-merges`, so source changes in conflict resolutions made in merge commits are not walked; CI runs the PR head's own `check-test-first.sh` and `packinfo.py` (the policy is read at the base, the code that reads it is not), so a PR can relax the check by editing them — code mode names that edit as gate code; and an admin can merge past a red `gates` job (`enforce_admins: false`) | `scripts/check-test-first.sh`, `.github/workflows/ci.yml`, `tests/governance/test_check_test_first.sh` |
| The coverage floor measures the PR's code at the base's `coverage_min` (REQ-325) | For python, `pytest_cov` runs `pytest --cov=src --cov-fail-under=<min>` with the gate's own `--cov-config` (no repository coverage config, no `# pragma: no cover`) and its own pytest configuration: `-c <temp ini>` carrying only `pyproject.toml`'s `pythonpath` (a fixed allowlist, never `addopts`), `--rootdir` the working tree, `-p no:cacheprovider`, `PYTEST_ADDOPTS` unset — so no `pytest.ini`, `tox.ini`, `setup.cfg` or `pyproject.toml` switches measurement off; `coverage_min` and `coverage_exclude` are read at the base ref (the higher floor governs, a new exclusion FAILs) — `SPECFLOW_BASE_REF`, which `ci.yml` passes as the full `refs/remotes/origin/<base>` since P6 Build 2's fix wave 2, as a tag named `origin/<base>` would shadow the short name; a local run's short `origin/main` (`next.sh`, a developer's own gates run) is that developer's own view, a convention residual. Residuals: a `conftest.py` is arbitrary code and can still monkeypatch pytest-cov or coverage internals; code mode reads pytest configuration and `conftest.py` edits as gate code; tauri's `vitest.config.ts` and in-source ignore comments in TypeScript and Dart narrow what is measured, and the stack hooks (`gates.sh`, flutter's `lcov-threshold.sh`) run from the PR head — code mode names those edits too | `scripts/lib/specflow/coverage.sh`, `scripts/run-quality-gates.sh`, `tests/governance/test_coverage_floor.sh` |
| At PR time, a PR that changes a security document (and every `ship/<version>` PR) fails the `gates` check on an open critical/high, over-cap mediums, a dropped carry-forward, an out-of-window expiry, a removed id, or a malformed pair (unique ids, owner/expiry, rationale ≥ 10 characters) | `scripts/check-security-disposition.sh` (the proved kernel), gates section 7 (the kernel is proved by the template's own Dafny model, which instances do not receive). Residuals: the `gates` check is required only where branch protection works, and `enforce_admins: false` lets an admin merge past it; the tag is created by hand after the merge, and `release.yml` replays it at the tag (`--at-tag`) before anything is published (REQ-350, P6 R30); a tag nobody pushes is never replayed — the next ship PR's WARN; a review squashed before push leaves no trace for the id walk; a current medium left `status: open` passes rules 2–5 (dfe-3); a pushed `v<version>` tag makes `disposition_gate` skip that version's current review/disposition as released, so anyone who can push tags can take a non-ship PR's edits to that version out of evaluation (the id-removal walk still runs, and that version's ship PR then fails `verify-release.sh` because the tag exists) — an admin/tag-push exposure beside `enforce_admins: false` | `scripts/check-security-disposition.sh`, `scripts/lib/specflow/disposition.py`, `tests/governance/fixtures/disposition` |
| At PR time, a ship PR's release docs exist and are consistent: three docs, no tag yet, the Artifacts table, known-limitations complete, the disposition gate, every `[verifiable*]` REQ claimed and proved | `scripts/verify-release.sh`, gates section 7. Residuals: an admin can merge past a red `gates` job (`enforce_admins: false`); the release stays untagged until the maintainer tags it after the merge, and `release.yml` replays it at the tag (`--at-tag`) before anything is published (REQ-350, P6 R30); a tag nobody pushes is never replayed — the next ship PR's WARN; the PR template's RELEASE checkbox is where the maintainer confirms by hand that the previous release's tag exists, is signed (or annotated with the fallback recorded in that version's known-limitations) and is on that release's merge commit, and the previous ship PR's `gates` and test-first checks were green at its merge — `release.yml` replays gates section 7 at the tag, never sections 1–6 or `check-test-first.sh`, so a published Release alone proves neither (convention); the next ship PR checks the previous release's tag — a tag object, a signature that verifies or the annotated-tag fallback recorded in that version's known-limitations (read at the tag, or on the base as it stood when the tag was created — a line added after the tag records nothing), an ancestor of the base — but a missing tag is only a WARN (the one gap `art-release-readiness` records); in CI the runner holds no signer's public key of its own, so an SSH signature is checked against `.github/allowed_signers` as of the newest earlier SSH-signed release tag, itself verified back to trust on first use (`signers.py`, P6 R3) — the anchor is found among the `v<X.Y.Z>` tags, never the notes, and an SSH-signed previous tag must sit on a first-parent commit of the base (`anchor-off-main`, the tag-time rule): `signers.verify` runs `git verify-tag` with the anchor's copy of the file passed as `-c gpg.ssh.allowedSignersFile=<tmp>` and `gpg.ssh.program` pinned to the `ssh-keygen` on PATH, never the local configuration, takes the tagger as git parses the tag header, and reads `.github/revoked_signers` at that tag's tree (unreadable or malformed: refused); a GPG signature, or an SSH one with no anchor key, that this machine cannot check is a WARN (`git verify-tag` reports no public key or no gpg, which is never a FAIL, whoever's key made the signature); it FAILs a lightweight tag, an unsigned annotated tag without the recorded fallback, and a signature `signers.verify` refuses — `bad` (a BAD signature, or no tagger), `unlisted`, `tagger-mismatch`, `revoked`, `revocation-unreadable`, `revocation-malformed`, `anchor-off-main`, `anchor-unverified`, `shallow` or `git-error` — and a tag whose commit is not an ancestor of the base; the anchor's own residuals are P6 R3's TOFU caveat; CI runs the PR head's own `signers.py` (as it runs the head's `release_gate.py`), so a PR can change every verdict by editing it — code mode names that edit as gate code; in CI (`SPECFLOW_HEAD_SHA` set, or `GITHUB_ACTIONS`) the gate never reads `dist/` — a forced `dist/` or one PR-head code wrote into the checkout could otherwise choose the manifest — and ignores `SPECFLOW_RELEASE_BUILD=0`, a local-only switch to the shape check (ignored in CI since P6 Build 2's fix wave 2: PR-head code in an earlier gates step could write it into `$GITHUB_ENV`) — so `verify-release.sh` builds the reproducible subset itself and compares it row for row (P6 R26) with the notes' Artifacts table, from the PR head's tree (`SPECFLOW_HEAD_SHA`), in the required `gates` check, while `release-build` is the record, not a required check; a tracked `dist/` FAILs wherever the gate runs; outside CI (`/release`, locally) `dist/manifest.json`, CI's downloaded artifact, is compared instead and its checksums checked. Residual: to build the subset CI runs the PR head's own stack hook — `scripts/release-<stack>.sh` (`scripts/release-template.sh` in the template source, from `scripts/release-stack.sh.template` in an instance) — and `release_manifest.py`, so a ship PR can edit the hook to build whatever rows its notes carry; the stack itself is read at the base ref (`packinfo.py --ref`, instance-ness and the pack as committed there), so adding or deleting `.specflow.yml` or `.stack` cannot swap the hook (in CI the base is the full `refs/remotes/origin/<base>` since P6 Build 2's fix wave 2, as a tag named `origin/<base>` would shadow the short name; a local run's short `origin/main` (`next.sh`, a developer's own gates run, and `release-tag.sh`'s HEAD check, choice of `M`, docs comparison, recorded-fallback read and advisory `next:` line — its `signers.py` and `release-check` calls take the full `refs/remotes/<remote>/main`) is that developer's own view, a convention residual, and `release-tag.sh` fails closed, as it requires `HEAD` to equal `<remote>/main`) — code mode names those edits as gate code | `scripts/verify-release.sh`, `scripts/lib/specflow/release_gate.py`, `scripts/lib/specflow/release_manifest.py`, `scripts/lib/specflow/signers.py` |
| At the tag, every first-parent commit of `main` since the previous published Release is re-judged by the CI check's own classifier before anything is published (REQ-350) | `attestation.py release-check` (through `pr_attestation`, the one classifier; no rule weakened), run by `release.yml`'s `verify` job on the pushed tag and by `release-tag.sh` before it signs (exit 7): a commit is judged by a PR only through the exact association (the PR's `merge_commit_sha` is the commit, never containment) and only when it carries exactly that PR's reviewed head merged onto its parent; a commit with no exact PR is a direct push, accepted unwaived only inside the minor exception (no code, no phase artifact, not `constitution.md`), else only under a maintainer's marker or waiver posted on the commit; rebase-merge is disabled by `configure-repo.sh` (`allow_rebase_merge: false`), so the factory merges by squash or merge commit; a rebase-merged code commit needs a commit-level waiver (a rebase merge's earlier commits carry partial trees and read as direct pushes; where GitHub refuses the setting with HTTP 403 it is convention); both callers also run the same previous-release check (`signers.py previous`), so `release-tag.sh` never pushes a tag `release.yml` would refuse. Residuals: the pre-transfer boundary `attestation_since` is read at the tag's tree (`scripts/template-pack.yml`), so at the one release that introduces it any accepted PR could have set it (dfe-12); doc-only direct pushes are accepted unwaived (the minor exception); an admin can bypass the `release tags` ruleset and push a tag on a commit whose own workflow drops the check (R31); the classifier runs from the tagged tree, so a reviewed ship PR that edits `release.yml`, `attestation.py` or `scripts/template-pack.yml` is bound only by that PR's own review (code mode names the edit as gate code; in solo mode that review is the model's alone); and the workflow's `GITHUB_TOKEN` reads a maintainer whose organisation membership is private as `COLLABORATOR`, so their waivers are refused at the tag (`waiver-not-maintainer`) — keep the maintainer's membership public | `scripts/lib/specflow/attestation.py`, `.github/workflows/release.yml`, `scripts/lib/specflow/signers.py`, `tests/governance/test_release_check.sh` |
| The solo second review is self-attested, not a control | Convention: tamper-evident, not enforced | `constitution.md` |
| `/next` never runs the verifier: in `awaiting-verifier` it renders the second-terminal instruction (REQ-385) | `render_step` renders `RunVerifier` as the second-terminal instruction (`_verifier_line`; the `refs/remotes/origin/main:scripts/run-verifier.sh` argument — the full ref since P6 Build 3, a tag named `origin/<base>` would shadow the short name; `main`'s reviewed copy for every PR since the SEC-004 back-edge — and, for a stacked PR, one sentence naming its unreviewed base PR, the base name shell-quoted, since it may carry `;`, `$()` or backticks); `.claude/commands/next.md` forbids running `scripts/run-verifier.sh`, and the guided `awaiting-verifier` point only prints and waits. Residual: `/next` runs the checkout's own copies of `scripts/next.sh`, `pipeline.py`, `state.py` and `next.md` (no fetch, no base-ref copy), so a PR that edits them changes what its author's `/next` prints — code mode names those edits as gate code; the `next.md` rule is an instruction to the session, not a mechanism | `scripts/lib/specflow/pipeline.py`, `.claude/commands/next.md`, `tests/governance/test_next_render.sh`, `tests/governance/test_next_command.sh` |
| `/next` prints a merge command only for an approved head, and the command merges only that head (REQ-385) | The kernel's `derive` (`state.py`, the twin of the template's own Dafny model `state.dfy`, which instances do not receive: `MergeOnlyWhenApproved`, `UnknownBranchNeverMerges`; so an instance's edit to `state.py` gets no proof check, only its fixtures, and code mode names it as gate code) returns `Merge` only for an open PR whose attestation is `approve` or `waiver` and, in team mode, that has a human approval; a `REQUEST_CHANGES` is `blocked` with its findings printed, and an unknown branch never merges. The attestation comes from `attestation.pr_attestation`, the CI check's own classifier, so its rule 1b holds here too: an unreadable role is never accepted and keeps blocking; a known `read`, `triage` or `none` role neither accepts nor blocks; any other role name is resolved through the legacy `permission` field, else treated as unreadable (a `REQUEST_CHANGES` from a commenter whose role lookup failed is `blocked`, never `awaiting-merge`). The rendered command carries `--match-head-commit <headRefOid>` of the head that was judged, so gh refuses it once the head has moved (a push after the `APPROVE`). The branch's PR is chosen among this repository's PRs only: a fork PR sharing the branch name is never it. In team mode with an empty `reviewDecision` (no required review) the approval is read from the reviews at the head — from an `OWNER`, or a `MEMBER` or `COLLABORATOR` with a writing role (unreadable fails closed), never from the PR author or an author or committer of any of its commits — and `--explain` says nothing server-side enforces it. Residuals: the checkout's own copies run (row above) and PR state is this checkout's view (`next.sh` never fetches); where branch protection is absent `/next` is advisory: nothing stops a merge typed by hand; the last-pusher exclusion is approximated by the commits' authors and committers (a push of someone else's commits is not attributable) | `scripts/lib/specflow/state.py`, `scripts/lib/specflow/pipeline.py`, `tests/governance/test_state_kernel.sh`, `tests/governance/test_state_model.sh`, `tests/governance/test_next_prs.sh`, `tests/governance/test_next_render.sh` |
| Other users' PRs never block `/next`, and checking one out carries the dfe-10 warning | On `main` the kernel checks out only the current user's own open lane PRs (`OtherUsersPrsNeverBlock` in the template's Dafny model); others, and every fork PR, are listed with the warning that checking one out runs its code on this machine (`open_lanes_line`), and `.claude/commands/next.md` forbids that checkout without the warning. Residual: the checkout's own copies run (first `/next` row) | `scripts/lib/specflow/state.py`, `scripts/lib/specflow/pipeline.py`, `.claude/commands/next.md`, `tests/governance/test_next_prs.sh` |
| The review procedure itself — steps 1–6 above, the paths and branch names, the lane-to-phase mapping, the patch tier and the minor exception's bounds — to which `art-branch-as-state` and `art-review-gate` point (amendment C, REQ-326) | Convention: this file loads at every session start and the verifier reads it; the rows above name what enforces each part, and a part no row names is convention (no mechanism) | `.claude/rules/review-gate.md`, `constitution.md` |

## Paths and branch names

The path is `.specflow.yml`'s `path:` key (configuration, not pipeline
state — `art-branch-as-state`): `lanes` or `regulated`. `/next` derives
state from the branch name, its PRs (open, merged or closed) and the tree;
both paths' prefixes are recognised regardless of the configured path. A
slug may not start with `sec-`: `build/sec-<id>` is the back-edge's name, so
the builds of a design slug `sec-x` would be `build/sec-x-N`, which parses as
the back-edge. `/next` treats a `design/`, `patch/` or `phase/{spec,arch,plan}-`
branch with such a slug as unknown, and does not track a plan whose slug
starts with `sec-`.

Squash merges are permitted on both paths: state is derived from PRs (open,
merged or closed) and the tree, never from branch ancestry (REQ-340).

Lanes path:

```
design/<slug>        (BRAINSTORM + SPECIFY + ARCHITECTURE + PLAN + TASKS + ANALYZE, one PR)
build/<slug>-N        (IMPLEMENT of "## Build N", one branch per build; CI on this PR is VALIDATE)
ship/<version>        (SECURITY + RELEASE, one PR)
```

Out-of-cycle (lanes): `build/sec-<id>` (SECURITY back-edge).

Regulated path:

```
phase/spec-<slug>    (BRAINSTORM + SPECIFY)
phase/arch-<slug>    (ARCHITECTURE)
phase/plan-<slug>    (PLAN + TASKS + ANALYZE)
impl/plan-N-<plan slug>   (IMPLEMENT, one branch per "## Build N" section of the plan)
phase/validate       (VALIDATE)
phase/security       (SECURITY)
phase/release        (RELEASE)
```

Out-of-cycle (regulated): `impl/sec-<id>` (SECURITY back-edge).

Both paths: `patch/<slug>` (patch tier), `phase/retro-YYYY-MM-DD`
(Retrospective, per `art-retrospective-cadence`).

## Lane-to-phase mapping

| Phase(s) | Lanes-path branch | Regulated-path branch |
|---|---|---|
| BRAINSTORM, SPECIFY | `design/<slug>` | `phase/spec-<slug>` |
| ARCHITECTURE | `design/<slug>` | `phase/arch-<slug>` |
| PLAN, TASKS, ANALYZE | `design/<slug>` | `phase/plan-<slug>` |
| IMPLEMENT | `build/<slug>-N` | `impl/plan-N-<plan slug>` |
| VALIDATE | CI on the build PR | `phase/validate` |
| SECURITY, RELEASE | `ship/<version>` | `phase/security`, `phase/release` |
| SECURITY back-edge | `build/sec-<id>` | `impl/sec-<id>` |
| Patch tier | `patch/<slug>` | `patch/<slug>` |
| Retrospective | `phase/retro-YYYY-MM-DD` | `phase/retro-YYYY-MM-DD` |

## Tool sequence per phase

See `CLAUDE.md` pipeline table.

## Phase-specific gate rules

- ARCHITECTURE exit gate: every `[verifiable]` or `[verifiable-model]` REQ maps to a kernel module (`art-kernel-boundary`); threat model has ≥1 trust boundary, ≥1 asset with CIA, ≥1 STRIDE category per external-facing data-flow element.
- PLAN exit gate: plan frontmatter carries `spec:`, `decisions:`, and
  `implements:` (mandatory for plans created from v3.2 on; the demo plan is
  grandfathered and walked whole); `scripts/analyze-adr-plan-linkage.sh`
  scopes per plan and `scripts/check-traceability.sh` to the union across
  plans (REQ-380); an explicit empty `implements:` list is an error. Plans
  may carry test code and describe implementation as intent, never bodies
  (`art-test-first`).
- SECURITY exit gate: zero `severity: critical, status: open`; zero `severity: high, status: open`; accepted/deferred mediums cap respected (`art-threat-driven-security`); `bash scripts/check-security-disposition.sh` (ADR-002 rules 1–5, the proved kernel).
- RELEASE exit gate, at PR time (`art-release-readiness`): gates green, and `scripts/verify-release.sh` checks that the three docs (notes, migration, known-limitations) exist, that no tag `v<version>` exists yet, that known-limitations references every SEC-NNN with accepted/deferred status, and that the disposition gate passes; where `dist/manifest.json` exists (locally, under `/release`) it also checks that each `dist/` file hashes to its manifest entry and that the manifest content is transcribed into the release notes row for row — in CI the gate never reads `dist/` (a forced or PR-written one could choose the manifest): `verify-release.sh` builds the reproducible subset itself and compares it row for row (P6 R26) with the notes' Artifacts table, and a tracked `dist/` FAILs wherever the gate runs. After the merge, the tag `v<version>` is created and signed on the merge commit, with SSH — annotated permitted only when no signer at all (SSH, GPG or X.509) is configured or held, the fallback recorded in known-limitations; a GPG-signed tag is refused at the tag (`release.yml` holds no GPG keyring; P6 R27). `scripts/release-tag.sh` never falls back by itself: with no signer it refuses (exit 3) unless the engineer passes `--annotated` explicitly, and `--annotated` tags only once the fallback line is already on `main` (exit 4 otherwise); in the guided profile `/next`'s `unsigned-tag` confirmation point comes first, a convention the script cannot check. A released review, disposition, notes, migration or known-limitations file is never edited after its tag, except the schema-migration exception for security docs (`docs/security/README.md`) and the `/release` follow-up that records the annotated-tag fallback when it was created (or removes a stale one once a signed tag was created). `art-release-readiness` judges "tag missing" after the merge: the ship PR must not carry `v<version>`, and a merged release without its tag is what the clause blocks. Its control is the next ship PR's `verify-release.sh` check of the previous release's tag — it FAILs a lightweight tag, an unsigned annotated tag unless that version's known-limitations records the annotated-tag fallback (at the tag, or on the base before the tag was created; the inherited `0.0.1-demo` release alone is read by its legacy prose), a BAD signature (`git tag -v` for a GPG one), a signature `signers.verify` refuses (`unlisted`, `tagger-mismatch`, `revoked`, `revocation-unreadable`, `revocation-malformed`, `anchor-off-main` — an SSH-signed tag off the base's first-parent history —, `anchor-unverified`, `shallow`, `git-error`), and a tag whose commit is not an ancestor of the base; an SSH signature is checked against `.github/allowed_signers` as of the newest earlier SSH-signed release tag, itself verified back to trust on first use (`signers.py`, P6 R3) — `git verify-tag` with the anchor's copy of the file and the `ssh-keygen` on PATH, never the local configuration; a GPG signature, or an SSH one with no anchor key, that this machine cannot check (`git tag -v` reports no public key or no gpg) is a WARN, never a FAIL; and it only WARNs when the tag is missing (the one gap: nothing checks a release left untagged before the next ship PR, and then only as a WARN) — plus the PR template's RELEASE checkbox, where the maintainer confirms by hand that the previous release's tag exists, is signed (or annotated with the fallback recorded in that version's known-limitations) and is on that release's merge commit, and the previous ship PR's `gates` and test-first checks were green at its merge — `release.yml` replays gates section 7 at the tag, never sections 1–6 or `check-test-first.sh`, so a published Release alone proves neither (convention). The verifier is not part of this control: it sees the changed documents and the code, never the PR body or the gates' output, so on a ship PR it records this reading as a standing informational finding. A finding with no impact on any system scores 0.0 and is recorded as an informational `severity: low` (`art-threat-driven-security`'s band table, `docs/security/RUBRIC.md`).

## Back-edge protocol

If SECURITY surfaces a finding with `severity: critical` or `severity: high` that requires code change:

1. Spawn `impl/sec-<id>` (regulated) or `build/sec-<id>` (lanes) from `main`, using the finding id, while the `phase/security` or `ship/<version>` PR remains open.
2. Fix using TDD (`art-test-first`).
3. PR to `main`, merge.
4. Re-run VALIDATE locally; fix any regressions on the same branch.
5. Resume `phase/security` (regulated) or `ship/<version>` (lanes), rebase on `main`, append the fix record to the review and update the disposition to `status: fixed`.
6. SECURITY completes only when every critical and high finding is `fixed`.

Mediums never trigger the back-edge; they go straight to disposition.

## Patch tier (sanctioned light path)

For small changes that don't warrant the full 7-PR pipeline (added 2026-06-09;
the unsanctioned alternative is bypassing the state machine entirely, which is
how SpecFlow v1 died): branch `patch/<slug>`, on either path.

- **Qualifies:** a change whose spec delta touches no `[verifiable*]` REQ, no
  kernel-boundary module, and no trust boundary in the threat model.
- **A rubric-only `medium_cap` reduction to the default (amendment D, REQ-396):**
  a reduction of `medium_cap` in `docs/security/RUBRIC.md` to the constitution's
  default (5, `art-threat-driven-security`) from above it, with the kernel
  (`scripts/lib/specflow/disposition.py`) and the spec untouched, takes the patch
  tier — the first of the three security-artifact exceptions "Does not qualify"
  names below; qualifying is convention (no mechanism): a reviewer reads the
  diff; the verifier skill does not check it (BL-045). Any other change of
  `medium_cap` — one that does not reduce it to 5 from above — takes its own
  reviewed PR on a `patch/<slug>` branch that carries no other security
  artifact, under this tier's Process bullet (TDD, green gates, the verifier's
  review), merged before the ship PR it governs (ADR-002: the gate reads the cap
  from the base ref, so a PR cannot raise its own; `docs/security/RUBRIC.md`'s
  override note; PR #59's route for v3.2.0, written down), with the decision
  recorded there and the maintainer's merge (in solo mode the verifier's
  APPROVE remains the recorded second review) — the third exception below. The reduction-only reading is a narrowing of the
  retrospective's item 2, which admitted a change "toward" the default, and the
  raise route is amendment D's addition beyond it.
- **Process:** ONE PR from `patch/<slug>` containing the spec delta +
  implementation (TDD) + green `run-quality-gates.sh`. The verifier still runs
  (`git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- <PR>`); in team
  mode a human other than the author approves; in solo mode the verifier's
  APPROVE is the second review.
- **Does not qualify:** anything touching `[verifiable*]` REQs, ADRs, the
  constitution, security artifacts, or release artifacts — those take the
  full phase path — except the known-limitations fallback-line follow-up:
  the `/release` follow-up that records or removes a release's annotated-tag fallback line
  in `<version>-known-limitations.md` (`.claude/commands/release.md`) rides a
  `patch/<slug>` PR, a documents-only edit the release rules permit; the
  rubric-only `medium_cap` reduction to the default (the bullet above); and a
  `medium_cap` change other than a reduction to the default, on its own
  `patch/<slug>` PR that carries no other security artifact (the same bullet) —
  three exceptions, each under the Process bullet.

## Minor exception (bounded)

Doc-only fixes (typos, formatting, broken links) may merge directly to `main`
without a PR (`art-review-gate`) — bounded to changes that touch **no** files
under `src/`, `verification/`, `scripts/`, `.github/`, `.claude/`, no
model-instruction Markdown — any `CLAUDE.md` or `CLAUDE.local.md` at any depth,
Markdown under `stacks/<stack>/overlay/**` and `stacks/<stack>/skeleton/**`, and
`templates/**/*.md` (gate code under REQ-310: sessions load it as instructions,
nested `CLAUDE.md` files included) — and no phase
artifacts (specs, ADRs, plans, security, releases). If a "minor" change needs
any of those, it is patch tier at minimum.
