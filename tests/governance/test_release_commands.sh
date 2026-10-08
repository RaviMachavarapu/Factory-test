#!/usr/bin/env bash
# REQ-324 / REQ-322: /release invokes verify-release.sh instead of restating the gate and tags only after the ship PR
# merges (the PR-time gate requires that v<version> does not yet exist); /security-review writes the block schema
# (cvss_vector, carried_from, reclassified_by) and runs check-security-disposition.sh before the PR; the PR template's
# SECURITY and RELEASE lines name both gates. /release records the tag kind at tag time (PR #42 finding 6); a downgrade
# needs reclassified_by: and a rationale naming that reviewer, in one sentence across the command, schema, RUBRIC and
# PR template (finding 4).
# Covers: REQ-324
# Covers: REQ-322
# Covers: REQ-332
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
RL="$ROOT/.claude/commands/release.md"; SR="$ROOT/.claude/commands/security-review.md"; PT="$ROOT/.github/PULL_REQUEST_TEMPLATE.md"
ck "/release runs verify-release.sh for the version" grep -qF 'bash scripts/verify-release.sh --version $ARGUMENTS' "$RL"
ck "/release creates no preliminary tag (Step 0 is gone)" no grep -qiE 'preliminary|sequential-PR-chain' "$RL"
ck "/release no longer restates the gate" no grep -qF 'Gate (per `art-release-readiness`)' "$RL"
for w in 'schemas/security-disposition-template.md' 'cvss_vector:' 'carried_from:' 'reclassified_by:' \
         'bash scripts/check-security-disposition.sh --version $ARGUMENTS' 'inherited:' 'suppresses:'; do
  ck "/security-review states '$w'" grep -qF -- "$w" "$SR"
done
ck "/security-review tells the author how to recover from an id added by mistake in an earlier commit of the PR (id_removed, R12)" \
  bash -c 'for w in "id_removed" "raised in error" "rebuilt on the base" "force-push"; do grep -qF -- "$w" "$1" || exit 1; done' _ "$SR"
ck "/security-review no longer lets severity be chosen apart from the vector" no grep -qF 'severity: critical | high | medium | low   # by CVSS v4.0 base' "$SR"
ck "the PR template's SECURITY line names check-security-disposition.sh" bash -c 'grep "^\*\*SECURITY\*\*" "$1" | grep -qF "check-security-disposition.sh"' _ "$PT"
ck "the PR template's RELEASE line names verify-release.sh's PR-time contract" \
  bash -c 'l=$(grep "^\*\*RELEASE\*\*" "$1"); grep -qF "verify-release.sh" <<<"$l" && grep -qi "does not exist yet" <<<"$l"' _ "$PT"
# PR #42 findings 4, 6 and 9 (REQ-324, REQ-322): the tag kind is decided and recorded at tag time; the Gate lines name
# check (6) and the previous release's tag; a downgrade needs a second reviewer, in the same sentence everywhere.
ck "/release: the fallback line it records starts '- Annotated-tag fallback:' (the exact prefix verify-release reads)" \
  grep -qE '^ *- Annotated-tag fallback: .*annotated' "$RL"
for f in "$RL" "$PT"; do
  ck "$(basename "$f"): the RELEASE gate line names check (6) and the previous release's tag" \
    bash -c 'l=$(grep -E "^(Gate:|\*\*RELEASE\*\*)" "$1" | grep -F "verify-release.sh"); grep -qF "every \`[verifiable*]\` REQ claimed and proved" <<<"$l" && grep -qF "previous release" <<<"$l"' _ "$f"
done
RS='A downgrade needs both `reclassified_by:` (the second reviewer'"'"'s handle, never the `owner:`) and a `rationale:` that names that reviewer.'
for f in "$SR" "$ROOT/schemas/security-disposition-template.md" "$ROOT/docs/security/RUBRIC.md" "$PT"; do
  ck "$(basename "$f") states the downgrade rule in the one sentence" grep -qF -- "$RS" "$f"
done
# PR #42 second verifier run, medium 4 (REQ-332): a schema-migration edit to a released review/disposition is confirmed
# by the maintainer on the record (docs/security/README.md's standing exception), never left implicit.
ck "the PR template carries a SECURITY checkbox recording the maintainer's confirmation of schema-migration edits (docs/security/README.md)" \
  bash -c 'grep -E "^- \[ \] \(SECURITY\)" "$1" | grep -qF "schema-migration edits to a released review/disposition confirmed by the maintainer (docs/security/README.md)"' _ "$PT"
ck "/security-review no longer calls reclassified_by: optional" no grep -qF 'reclassified_by: <github-handle>   # optional' "$SR"
# PR #47 verifier medium 1 (REQ-343, REQ-324), narrowed by amendment C (P7 fresh-eyes review, finding 21; REQ-353, P6
# R27): the annotated-tag fallback is permitted only when no signer at all — SSH, GPG or X.509 — is configured or held,
# and a GPG-signed tag is refused at the tag; review-gate.md's RELEASE exit gate, /release and release-tag.sh's header
# say so, and none keeps the pre-amendment "neither GPG nor SSH" condition, under which a GPG-only signer was told to sign.
# Covers: REQ-343, REQ-324, REQ-353
rgx=$(grep -F -- '- RELEASE exit gate, at PR time' .claude/rules/review-gate.md || true)
ck "review-gate.md's RELEASE exit gate: SSH-signed; annotated only when no signer at all is configured or held; GPG refused at the tag" \
  bash -c 'grep -qF "is created and signed on the merge commit, with SSH — annotated permitted only when no signer at all (SSH, GPG or X.509) is configured or held, the fallback recorded in known-limitations; a GPG-signed tag is refused at the tag" <<<"$1" && ! grep -qF "neither GPG nor SSH" <<<"$1" && ! grep -qF "only with the GPG fallback" <<<"$1"' _ "$rgx"
RL=.claude/commands/release.md
ck "/release: the fallback's condition is no signer at all (SSH, GPG or X.509), never 'neither a GPG nor an SSH signing key', never GPG alone" \
  bash -c 'grep -qF "if no signer at all — SSH, GPG or X.509 — is configured or held in this environment" "$1" && grep -qF "(no signer — SSH, GPG or X.509 — at tag time" "$1" && ! grep -qF "neither a GPG nor an SSH signing key" "$1" && ! grep -qF "(no GPG key at tag time)" "$1"' _ "$RL"
ck "release-tag.sh's header cites art-release-readiness by its amended condition" \
  bash -c 'grep -qF "(art-release-readiness: no signer at all — SSH, GPG or X.509 — configured or held)" "$1" && ! grep -qF "neither GPG nor SSH signing verifiably available" "$1"' _ scripts/release-tag.sh

# P7 design review, polish item 2 (REQ-353, REQ-383; P6 R17, R27): what Builds 1–3 shipped — release-tag.sh never falls
# back by itself (no signer: exit 3), the annotated path is the engineer's explicit --annotated with the fallback already
# on main (exit 4 otherwise), and the guided confirmation point is /next's; the rule file every session loads, /release
# and the script's header say so.
# Covers: REQ-353
ck "review-gate.md's RELEASE exit gate: release-tag.sh refuses with no signer; --annotated only explicitly and with the fallback on main; /next's unsigned-tag point" \
  bash -c 'for w in "\`scripts/release-tag.sh\` never falls back by itself: with no signer it refuses (exit 3) unless the engineer passes \`--annotated\` explicitly" "\`--annotated\` tags only once the fallback line is already on \`main\` (exit 4 otherwise)" "\`/next\`'"'"'s \`unsigned-tag\` confirmation point"; do grep -qF -- "$w" <<<"$1" || { echo "missing $w"; exit 1; }; done' _ "$rgx"
ck "/release: the tag step never falls back by itself; --annotated is explicit, after /next's unsigned-tag point, and needs the line on main" \
  bash -c 'for w in "the tag step never falls back by itself: with no signer it refuses, exit 3, until you pass \`--annotated\` explicitly" "only after \`/next\`'"'"'s \`unsigned-tag\` confirmation point" "tags annotated only once this line is on \`main\`, exit 4" "(no signer — SSH, GPG or X.509 — at tag time, so the tag step'"'"'s \`--annotated\` creates it by the engineer'"'"'s explicit choice)"; do grep -qF -- "$w" "$1" || { echo "missing $w"; exit 1; }; done' _ "$RL"
ck "release-tag.sh's header: it refuses rather than falling back; annotated only on an explicit --annotated with the fallback on main" \
  bash -c 'grep -qF "the script refuses (exit 3) rather than falling back" "$1" && grep -qF "only when the engineer passes --annotated explicitly and the fallback is already recorded on main (exit 4 otherwise)" "$1" && ! grep -qF "or annotated only when signing-kind is none" "$1"' _ scripts/release-tag.sh
# PR #48 verifier run 2, F3 (REQ-389): when /next runs /release or /security-review, the ship-pr point shows the severity
# scores and dispositions, writes confirmed_by: into the security review and the disposition, asks go or no-go and records
# the answer under ### Guided proposals in the release notes — both commands say what /next writes.
# Covers: REQ-389
for f in "$RL" "$SR"; do
  ck "$(basename "$f"): says /next records go/no-go under ### Guided proposals in the release notes and writes confirmed_by: into the security review and the disposition" \
    bash -c 't=$(tr "\n" " " < "$1" | tr -s " "); grep -qF "records the answer under \`### Guided proposals\` in the release notes" <<<"$t" && grep -qF "writes \`confirmed_by:\` into the frontmatter of the security review and the disposition" <<<"$t"' _ "$f"
done
# Scoped re-review N1 (REQ-389): on the regulated path phase/security's point writes only the security docs'
# confirmed_by: and phase/release's asks go or no-go — the release notes do not exist on phase/security.
# Covers: REQ-389
rc='on the regulated path `phase/security`'"'"'s point writes the security review'"'"'s and disposition'"'"'s `confirmed_by:` only, and `phase/release`'"'"'s asks go or no-go and records it under `### Guided proposals` in the release notes'
for f in "$RL" "$SR"; do
  ck "$(basename "$f"): names the regulated path's split of the ship-pr point (phase/security, phase/release)" \
    bash -c 'tr "\n" " " < "$1" | tr -s " " | grep -qF "$2"' _ "$f" "$rc"
done

# PR #48 verifier run 3, finding 3 (REQ-389): /release and /security-review carry the shared sentence — /next commits the
# confirmed_by: edits (and the go/no-go answer) after the gates and before create-pr pushes the ship PR.
# Covers: REQ-389
SH='At `design-pr` and `ship-pr`, after writing `confirmed_by:` (and, at `ship-pr`, the go/no-go answer) and running the gates green as `next.sh` renders them (`bash scripts/next.sh --gates`), `/next` runs `git add` on all of the lane'\''s artifacts (new and edited) — exactly the path sets `next.md` names at that point, nothing else — and commits them — `git commit -m "docs(guided): confirmed_by: <handle> <date> — acknowledgements at design-pr (REQ-389)"`, or `…at ship-pr (REQ-389)` — and only then runs `create-pr`, so the pushed branch carries what the gates checked.'
for f in "$RL" "$SR"; do
  ck "$(basename "$f"): carries the shared commit-before-create-pr sentence" \
    bash -c 'tr "\n" " " < "$1" | tr -s " " | grep -qF "$2"' _ "$f" "$SH"
done

# P6 Task 1.3 (REQ-383; P6 R17): /release <version> writes the ship PR's documents; /release --tag <version> runs only
# "Tag the release" — bash scripts/release-tag.sh — after the merge; the session never runs git tag itself.
# Covers: REQ-383
ck "release.md: argument-hint names both forms" grep -qF 'argument-hint: <version> | --tag <version>' "$RL"
ck "release.md: --tag reads the version after it from \$ARGUMENTS and runs only 'Tag the release'" \
  bash -c 'grep -qF "When \`\$ARGUMENTS\` begins with \`--tag \`" "$1" && grep -qx "## Tag the release" "$1"' _ "$RL"
ck "release.md: the tag is release-tag.sh's, after the merge; the session never runs git tag; every exit is explained" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read(); i = t.index("\n## Tag the release")
assert "bash scripts/release-tag.sh" in t[i:] and "release-tag.sh" not in t[:i], "the script appears only in the tag section"
assert "git tag -s" not in t and "git tag -a" not in t, "the session never tags by hand"
for w in ("exit 2", "exit 3", "exit 4", "exit 5", "exit 6", "--annotated", "unsigned-tag", "follow-up docs PR", "**stop**",
          "is never edited after its tag"):
    assert w in t[i:], w
PY
# Build 1 final review (REQ-383): the closing sentence lists every refusal of the next ship PR's previous-tag check, and
# exit 6 names the kinds a signed tag is refused with.
ck "release.md: the next ship PR's FAIL kinds in full; exit 6 names its kinds (revoked, no-anchor, shallow, git-error)" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read(); i = t.index("\n## Tag the release"); s = t[i:]
line = next(l for l in s.splitlines() if l.startswith("The next ship PR's `verify-release.sh` FAILs"))
for w in ("lightweight", "unsigned", "BAD", "unlisted", "tagger-mismatch", "revoked", "anchor-off-main", "anchor-unverified",
          "revocation-unreadable", "revocation-malformed", "shallow", "git-error", "off `main`"):
    assert w in line, w
x6 = next(l for l in s.splitlines() if l.strip().startswith("- exit 6:"))
for w in ("unlisted", "tagger-mismatch", "revoked", "anchor-off-main", "anchor-unverified", "no-anchor", "shallow", "git-error"):
    assert w in x6, w
assert "anchor-downgrade" not in t, "anchor-downgrade is gone (P6 R3(i), fix wave 2)"
PY
# Fix wave 2 (REQ-383; P6 R17, C4, C9), as Build 3 delivered it (fix wave 1, E): exits 8, 9 and 11; exit 7 is the
# tag-time re-check, present; the guided pause is /next's convention; the local-binaries residual.
ck "release.md: exits 8, 9 and 11; exit 7 is attestation.py release-check (present, no Build 3 qualifier); the guided pause is /next's (a convention); the local-binaries residual" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read(); s = t[t.index("\n## Tag the release"):]
for w in ("exit 8", "exit 9", "exit 11", "attestation.py release-check", "signers.py previous", "convention", "ssh-keygen", "local git and ssh-keygen binaries"):
    assert w in s, w
x7 = next(l for l in s.splitlines() if l.strip().startswith("- exit 7:"))
assert "Build 3" not in x7 and "release-check" in x7 and "waiver" in x7, x7
PY
# Fix wave 1, E and I (REQ-383, REQ-350; P6 R17): release.yml exists, so the tag section names it in the present tense —
# no "from Build 3 on", no "arrives with Build 3", no "until then" — and its preflight note says release.yml reads GitHub
# as the workflow's GITHUB_TOKEN, under which a private-membership maintainer reads as COLLABORATOR (keep it public).
# Covers: REQ-383
ck "release.md's tag section: no 'from Build 3' / 'arrives with Build 3' / 'until then'; step 3: release.yml re-verifies the pushed tag in a clean runner" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read(); s = t[t.index("\n## Tag the release"):]
bad = [l[:120] for l in s.splitlines() if "from Build 3" in l or "arrives with Build 3" in l or "until then" in l or "Build 1's script" in l]
assert not bad, bad
x3 = next(l for l in s.splitlines() if l.startswith("3. Run `bash scripts/release-tag.sh"))
assert "`release.yml` re-verifies the pushed tag in a clean runner" in x3, x3[-300:]
assert "GITHUB_TOKEN" in x3 and "COLLABORATOR" in x3 and "public" in x3, x3[-400:]
PY
ck "release.md: no interim step, no 'until P6' or P6's forward reference (a 'P6 R<n>' citation is not one)" \
  bash -c '! grep -qiF "interim step" "$1" && ! grep -qE "until P6|P6.s " "$1"' _ "$RL"
ck "release.md: the tag section exports the gh account (release-tag.sh uses the ambient gh auth)" \
  bash -c 'sed -n "/^## Tag the release/,\$p" "$1" | grep -qF "GH_TOKEN=\"\$(gh auth token --user"' _ "$RL"

# PR #53 verifier run 1, finding 6 (REQ-383; P6 R17): release.md ships to instances, so "Tag the release" names no
# factory account — step 2 exports the account that can push to this repository's main (gh auth status); the factory's
# own account is recorded in the plan's R17 only.
# Covers: REQ-383
ck "release.md names no factory account; step 2 exports the account that can push to main (gh auth status)" \
  bash -c '! grep -qF "kpingali123" "$1" && grep -E "^2\. " <(sed -n "/^## Tag the release/,\$p" "$1") | grep -qF "the account that can push to this repository'"'"'s \`main\` (\`gh auth status\`)"' _ "$RL"
# P6 Task 2.5 (REQ-384, REQ-383; P6 R14, R18, R26): /release transcribes CI's manifest — release-build.yml's artifact,
# never a laptop build — resolves the stack through packinfo.py, and records an absent tag ruleset in known-limitations.
# Covers: REQ-384
ck "/release: push the branch, run release-build.yml, download its artifact, transcribe, then verify-release.sh — no gates before" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read()
order = ["git push -u origin HEAD", "gh workflow run release-build.yml", "gh run download", "## Artifacts", "bash scripts/verify-release.sh --version"]
idx = [t.index(w) for w in order]; assert idx == sorted(idx), list(zip(order, idx))
assert "run-quality-gates.sh" not in t[:idx[-1]], "a gates run before the transcription"
assert "CI's manifest is the record" in t and "release_manifest.py rows" in t
PY
# PR #54 fix wave 2 (REQ-384): by the full ref refs/remotes/origin/main, as CI passes the base — a tag named origin/main
# would shadow the short name.
ck "/release resolves the hook through packinfo.py at the base, refs/remotes/origin/main (P6 R2; Build 2 final review; fix wave 2)" grep -qF 'scripts/release-$(python3 scripts/lib/specflow/packinfo.py --root . --ref refs/remotes/origin/main stack).sh' "$RL"
ck "/release records an absent or unreadable tag ruleset as a '- Tag ruleset:' line (configure-repo.sh --check-ruleset)" \
  bash -c 'grep -qF "configure-repo.sh --check-ruleset" "$1" && grep -qF -- "- Tag ruleset:" "$1"' _ "$RL"
ck "/release's '- Tag ruleset:' line binds release.yml's refusals to a reviewed commit and never says it 'still refuses' (P6 R31)" \
  bash -c 'l=$(grep -F -- "- Tag ruleset:" "$1"); grep -qF "reviewed commit" <<<"$l" && grep -qF "verify-tag" <<<"$l" && ! grep -qF "still refuses" "$1"' _ "$RL"
ck "/release (python) records the reproducibility residual as a '- Reproducible builds:' line (P6 R18)" grep -qF -- '- Reproducible builds:' "$RL"
ck "/release writes the notes' Release link line and transcribes only after the ship branch is up to date with main (F7, F11)" \
  bash -c 'grep -qF "Release: https://github.com/<owner>/<repo>/releases/tag/v<version>" "$1" && grep -qF "gh pr update-branch" "$1"' _ "$RL"
# Build 2 final review (REQ-384, REQ-340): release.md ships to every instance and RELEASE runs on ship/<v> (lanes) or
# phase/release (regulated), so step 4 pushes the current branch and dispatches release-build.yml on it — never a
# hard-coded ship/ name, which fails on phase/release (or, adapted by a session, creates a lanes branch /next misreads).
# REQ-340 is the two paths' branch grammar this exercises (PR #54 verifier run 1, code-mode medium: it cited REQ-381,
# which no plan claims; commit c986712's citation stands in history).
# Covers: REQ-384
# Covers: REQ-340
ck "release.md step 4 pushes the current branch and dispatches on it; it names both paths' branches and hard-codes no ship/ ref" \
  bash -c 's4=$(grep -E "^4\. " "$1"); grep -qF "git push -u origin HEAD" <<<"$s4" && grep -qF -- "--ref \"\$(git branch --show-current)\"" <<<"$s4" && grep -qF "ship/<version>" <<<"$s4" && grep -qF "phase/release" <<<"$s4" && ! grep -qF "origin ship/" "$1" && ! grep -qF -- "--ref ship/" "$1"' _ "$RL"
# Fix wave 1 (REQ-384; P6 R15, R18): release.md ships to every instance, and release.yml arrives with Build 3 — so in
# steps 1-7 every line naming release.yml says "from Build 3 (REQ-350) on" (Build 3's Task 3.5 removes the qualifier
# and flips this pin); and the branch is brought up to date with main BEFORE the push and the dispatch, so the artifact
# transcribed is built from the tree that is pushed (gh pr update-branch only once the PR exists, on a later push).
# Covers: REQ-384
ck "release.md steps 1-7: release.yml exists, so no line names it with the 'from Build 3 (REQ-350) on' qualifier (P6 Task 3.5)" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read(); s = t[:t.index("\n## Guided profile")]
bad = [l[:100] for l in s.splitlines() if "from Build 3 (REQ-350) on" in l]
assert not bad, bad
PY
# PR #54 verifier run 2, finding 5 (REQ-384; art-review-gate): step 4 rebases onto the full ref too — a planted tag named
# origin/main would otherwise choose the commit the ship branch is rebased onto.
# Covers: REQ-384
ck "release.md: no short-name rebase or read — every origin/main is the full ref refs/remotes/origin/main or names the tag" \
  bash -c '! grep -qF "git rebase origin/main" "$1" && ! grep -qE "(^|[^/\`])origin/main[^\`]" "$1"' _ "$RL"
ck "release.md step 4: rebase on main, then push, then dispatch release-build; gh pr update-branch only once the PR exists" python3 - "$RL" <<'PY'
import sys; t = open(sys.argv[1]).read()
s4 = next(l for l in t.splitlines() if l.startswith("4. "))
order = ["git rebase refs/remotes/origin/main", "git push -u origin HEAD", "gh workflow run release-build.yml", "gh run download"]
idx = [s4.find(w) for w in order]; assert -1 not in idx and idx == sorted(idx), list(zip(order, idx))
assert "gh pr update-branch" in t and "once the PR exists" in t
s5 = next(l for l in t.splitlines() if l.startswith("5. "))
assert "release-build" in s5 and "again" in s5, s5[:200]
PY
# PR #54 verifier run 1, finding 3 (REQ-384, REQ-352; art-release-readiness): step 4 carried the interim-window
# sentence until the second of P6 Builds 4 and 5 merged (Build 5, 2026-10-03): every pack's hook now honours
# RELEASE_PARTS, RELEASE_COMMIT and SOURCE_DATE_EPOCH, so R35's interim-window edit removed it and flipped this pin.
# Covers: REQ-384
ck "release.md step 4: no known interim limitation — the window closed with P6 Builds 4 and 5; step 4 still resolves the hook" \
  bash -c 's4=$(grep -E "^4\. " "$1"); grep -qF "packinfo.py" <<<"$s4" || { echo "no hook resolution"; exit 1; }; for w in "Known interim limitation" "interim" "Builds 4 and 5"; do grep -qiF -- "$w" <<<"$s4" && { echo "still has $w"; exit 1; }; done; exit 0' _ "$RL"
# P6 Task 3.2 (REQ-352, REQ-386, REQ-354; P6 R22, R23, R32, R35): /release's app-stack steps — the checklist appended to
# the notes, the release environment's secret list and its check, signing: written with config.py, the unsigned-bundle
# line and the tester instructions, the re-run sentence — keyed on the governing pack's stack.
# Covers: REQ-352
# Covers: REQ-354
ck "/release (app stacks) appends docs/releases/store-checklist.md under ## macOS distribution checklist" \
  bash -c 'grep -qF "docs/releases/store-checklist.md" "$1" && grep -qF "## macOS distribution checklist" "$1"' _ "$RL"
ck "/release (app stacks): the release environment's secret list, its check, signing: written with config.py, the '- Unsigned bundle:' line, the tester instructions" \
  bash -c 'for w in "gh secret list --env release --json name" "configure-repo.sh --check-environment" "- Release environment:" "config.py --root . write signing=" "- Unsigned bundle:" "tester-instructions.md"; do grep -qF -- "$w" "$1" || exit 1; done; ! grep -qF "gh secret list --json name" "$1"' _ "$RL"
ck "/release (app stacks) says the store checklist's re-run sentence (REQ-386)" \
  grep -qF 'Re-run the tag after adding the secrets and observe `signed: true`.' "$RL"
# Build 2's fix wave replaced the plan's short ref with the full one (a tag named origin/main would shadow it): the stack is
# read with --ref refs/remotes/origin/main, in step 4 and again by the app-stack bullet.
ck "/release reads the app-stack steps by the pack's stack (python and the template skip them)" \
  bash -c 'grep -F "for the app stacks only" "$1" | grep -qF "packinfo.py --root . --ref refs/remotes/origin/main stack" && grep -F "for the app stacks only" "$1" | grep -qF "python and the template skip"' _ "$RL"
# Build 3 final review, finding 7 (REQ-350, REQ-383; P6 R31): the '- Tag ruleset:' line says that, even with the ruleset,
# a repository admin can push a v* tag (the ruleset's admin bypass, enforce_admins: false).
# Covers: REQ-350
ck "/release's '- Tag ruleset:' line: with the ruleset an admin can still push a v* tag (its admin bypass)" \
  bash -c 'l=$(grep -F -- "- Tag ruleset:" "$1"); grep -qF "with it, a repository admin still can" <<<"$l" && grep -qF "admin bypass" <<<"$l"' _ "$RL"
finish test_release_commands
