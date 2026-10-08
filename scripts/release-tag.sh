#!/usr/bin/env bash
# scripts/release-tag.sh — tag the ship PR's merge commit after the merge (REQ-383; P6 R3, R17, R27).
# Usage: release-tag.sh <version> [--annotated] [--dry-run] [--no-push]
#
# Exit codes:
#   0  tagged (and pushed unless --no-push), or --dry-run printed the decision
#   2  a precondition failed: a bad version; not on main; a dirty tree (untracked files count); HEAD is not
#      <remote>/main after `git fetch <remote> main --tags`; v<version> exists locally or on the remote; no first-parent
#      commit of <remote>/main added docs/releases/<version>-notes.md (the ship PR has not merged); the release docs on
#      <remote>/main differ from the ship PR's merge commit (the follow-up fallback line aside); --annotated with an SSH
#      signer; ssh-keygen not on PATH for an SSH tag
#   3  no signer at all (`signers.py signing-kind` prints none) and no --annotated
#   4  --annotated, but known-limitations on <remote>/main has no `- Annotated-tag fallback:` line (stop: a follow-up
#      docs PR records it first)
#   5  a non-SSH signer only (signing-kind gpg or other): the tag path is SSH-only (release.yml accepts SSH signatures
#      only; P6 R27)
#   6  the signed tag did not verify against the anchor — the local tag is deleted, nothing pushed; the advice printed
#      is the verdict's own (advice() below: unlisted, tagger-mismatch, revoked, revocation-unreadable/-malformed,
#      anchor-off-main, anchor-unverified, no-anchor, shallow, git-error, bad)
#   7  the tag-time re-check failed: attestation.py release-check judged a merged PR (or a direct push of code) since the
#      previous release unattested, or could not run (gh or git failed — fail closed); a maintainer waiver posted on the PR
#      for its merged head (on the commit, for a direct push) clears it (R28)
#   8  `git ls-remote --tags <remote>` failed (authentication, network): whether v<version> exists there is unknown,
#      so nothing is tagged — never read as "absent on the remote"
#   9  `git push` failed: the local tag this run created is deleted, so a re-run starts clean
#   10 `git tag -s` itself failed (no ssh-agent or key, a cancelled passphrase, user.signingkey naming a missing
#      file): no tag was created, nothing pushed
#   11 the previous release is not verifiably released — the check release.yml's "Resolve the stack and the previous
#      release" step runs (signers.py previous, one function): its notes are on <remote>/main but v<prev> is missing (tag
#      the earlier release first), or v<prev> is lightweight, gpg-unverifiable, no-anchor or refused; checked before
#      anything is signed or pushed, so /release --tag never pushes a tag release.yml would refuse
#
# A tag is signed with SSH. With no signer configured or usable — signing-kind none
# (art-release-readiness: no signer at all — SSH, GPG or X.509 — configured or held) —
# the script refuses (exit 3) rather than falling back: it creates an annotated tag
# only when the engineer passes --annotated explicitly and the fallback is already recorded on main (exit 4 otherwise).
# The tagged commit is the newest first-parent commit of <remote>/main that added the notes, and the release docs
# there must be what <remote>/main holds (the follow-up fallback line aside), so an aborted, reverted ship is never
# tagged. --annotated is the engineer path's flag: guided /next passes it only after its unsigned-tag confirmation
# point — a convention the script cannot check (it prints a reminder before it proceeds).
#
# What the script and signers.py read — the signing-forge enumeration (P6 R17). All of it is the operator's own
# machine; the pre-push verification pins what would widen trust, and
# release.yml re-verifies the pushed tag in a clean runner (residual: the local verification still trusts the local
# git and ssh-keygen binaries themselves). Every
# python3 runs as `python3 -I -B`: isolated (PYTHONPATH, PYTHONHOME, PYTHONSTARTUP and the user site are ignored —
# PYTHONPATH could otherwise shadow a module and change a verdict) and writing no __pycache__; the inputs that remain
# are PATH (which python3, git, gh, ssh-keygen and gpg run) and GH_* (GH_TOKEN, GH_HOST, GH_REPO, GH_CONFIG_DIR: whose
# GitHub the re-check reads).
#   Environment: SPECFLOW_RELEASE_REMOTE (default origin); GH_TOKEN (gh's authentication — the tag-time re-check);
#     GIT_COMMITTER_NAME and GIT_COMMITTER_EMAIL (they set the tagger and win over user.email/user.name); PATH (git,
#     python3, gpg, and the ssh-keygen that verifies, resolved with command -v and pinned as gpg.ssh.program);
#     SSH_AUTH_SOCK (an agent that signs); git's own environment (GIT_DIR, GIT_CONFIG_GLOBAL, GIT_CONFIG_COUNT/KEY/VALUE).
#   git config: user.email, user.name (the tagger); gpg.format, user.signingkey, gpg.ssh.defaultKeyCommand,
#     gpg.program, gpg.openpgp.program (signing-kind, and the signing itself); gpg.ssh.program (the signing only —
#     verification pins the ssh-keygen on PATH); gpg.ssh.allowedSignersFile (never read: the anchor's copy is passed);
#     gpg.ssh.revocationFile (replaced by .github/revoked_signers when that lists a key; otherwise it can only narrow);
#     tag.gpgSign (forced off for an annotated tag).
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1  # (ignored under -I; python3 -I -B writes no __pycache__ into the tree the clean check judges)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNERS="$HERE/lib/specflow/signers.py"
REMOTE="${SPECFLOW_RELEASE_REMOTE:-origin}"
VERSION=""; ANNOTATED=0; DRY=0; PUSH=1

die() { local rc="$1"; shift; printf 'release-tag: %s\n' "$*" >&2; exit "$rc"; }

# advice KIND — what an exit 6 means and what to do, for that verdict only
advice() {
  case "$1" in
    unlisted) echo "unlisted: the signing key is not in .github/allowed_signers at the anchor — add it by PR; a key is trusted from the release after the first one tagged on a commit that lists it" ;;
    tagger-mismatch) echo "tagger-mismatch: the tagger email (git config user.email, or GIT_COMMITTER_EMAIL) must equal the key's principal in .github/allowed_signers, exactly and case-sensitively" ;;
    revoked) echo "revoked: the key is listed in .github/revoked_signers at the tag or on $REMOTE/main — sign with another listed key" ;;
    revocation-unreadable) echo "revocation-unreadable: git could not read .github/revoked_signers at the tag or on $REMOTE/main — check the clone (git fsck) and run it again" ;;
    revocation-malformed) echo "revocation-malformed: a line of .github/revoked_signers is not '<keytype> <base64>' — fix the file by PR, then run it again" ;;
    anchor-off-main) echo "anchor-off-main: the newest earlier SSH-signed v* tag is not on a first-parent commit of $REMOTE/main (a tag pushed on a PR's commit) — stop and ask the maintainer" ;;
    anchor-unverified) echo "anchor-unverified: the newest earlier SSH-signed v* tag, the anchor, does not itself verify — stop and ask the maintainer" ;;
    no-anchor) echo "no-anchor: no first-parent commit of $REMOTE/main before the tagged commit lists a key in .github/allowed_signers — merge a key by PR, then ship a release" ;;
    shallow) echo "shallow: this clone is shallow — git fetch --unshallow, then run it again" ;;
    git-error) echo "git-error: git could not read the history the anchor needs — check the clone (git fsck) and run it again" ;;
    *) echo "$1: the signature itself does not verify — check the signing key and run it again" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --annotated) ANNOTATED=1 ;;
    --dry-run) DRY=1 ;;
    --no-push) PUSH=0 ;;
    -*) die 2 "unknown option $1" ;;
    *) [ -z "$VERSION" ] || die 2 "one version only"; VERSION="$1" ;;
  esac
  shift
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 2 "the version must be X.Y.Z (got '${VERSION}')"
TAG="v$VERSION"

[ "$(git branch --show-current)" = main ] || die 2 "not on main — check out main and pull first"
[ -z "$(git status --porcelain)" ] || die 2 "the working tree is not clean (untracked files count) — commit or remove them"
git fetch -q "$REMOTE" main --tags || die 2 "git fetch $REMOTE main --tags failed"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$REMOTE/main")" ] || die 2 "HEAD is not $REMOTE/main — pull main first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then die 2 "$TAG already exists locally"; fi
if ! remote_tag=$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG" 2>&1); then
  die 8 "git ls-remote --tags $REMOTE failed, so whether $TAG exists there is unknown (authentication or network) — nothing tagged: $(printf '%s' "$remote_tag" | tail -n 1)"
fi
[ -z "$remote_tag" ] || die 2 "$TAG already exists on $REMOTE"

NOTES="docs/releases/$VERSION-notes.md"
M="$(git log --max-count=1 --first-parent --diff-merges=first-parent --diff-filter=A --no-patch --format=%H "$REMOTE/main" -- "$NOTES")"
[ -n "$M" ] || die 2 "no first-parent commit on $REMOTE/main added $NOTES — the ship PR has not merged"

KL="docs/releases/$VERSION-known-limitations.md"
# docs_at REF FILE — the file at REF ('-' when absent); known-limitations without the follow-up's fallback line
docs_at() { git show "$1:$2" 2>/dev/null || echo -; }
for f in "$NOTES" "docs/releases/$VERSION-migration.md" "$KL"; do
  a="$(docs_at "$M" "$f")"; b="$(docs_at "$REMOTE/main" "$f")"
  if [ "$f" = "$KL" ]; then a="$(grep -v '^- Annotated-tag fallback:' <<<"$a" || true)"; b="$(grep -v '^- Annotated-tag fallback:' <<<"$b" || true)"; fi
  [ "$a" = "$b" ] || die 2 "$f on $REMOTE/main differs from the ship PR's merge commit ${M:0:7} (the newest first-parent commit that added $NOTES) — the release docs changed after the merge; the tag must carry what main says shipped: ship the change as its own release"
done
fallback_recorded() { git show "$REMOTE/main:$KL" 2>/dev/null | grep -q '^- Annotated-tag fallback:'; }

KIND_LINE="$(python3 -I -B "$SIGNERS" --root . signing-kind)"
KIND="${KIND_LINE%% *}"

case "$KIND" in
  gpg|other)
    die 5 "only a non-SSH signer is available ($KIND_LINE); the tag path is SSH-only (release.yml accepts SSH signatures only; P6 R27). Configure SSH signing:
  git config --local gpg.format ssh
  git config --local user.signingkey ~/.ssh/<your key>.pub
  git config --local gpg.ssh.allowedSignersFile .github/allowed_signers" ;;
  none)
    [ "$ANNOTATED" = 1 ] || die 3 "no signer is configured or held ($KIND_LINE). Configure an SSH one (git config --local gpg.format ssh; git config --local user.signingkey <key>.pub), or confirm the unsigned-tag point and re-run with --annotated"
    fallback_recorded || die 4 "--annotated needs the fallback recorded on $REMOTE/main first: $KL has no '- Annotated-tag fallback:' line. Stop: record it in a follow-up docs PR, then re-run"
    printf 'note: --annotated is the engineer path: guided /next passes it only after its unsigned-tag confirmation point (P6 R17; a convention this script cannot check)\n'
    KIND_NAME=annotated ;;
  ssh)
    [ "$ANNOTATED" = 0 ] || die 2 "--annotated is only for a machine with no signing key; an SSH key is configured, so the tag is signed"
    command -v ssh-keygen >/dev/null 2>&1 || die 2 "ssh-keygen is not on PATH — the signed tag cannot be verified before the push"
    KIND_NAME=ssh ;;
  *) die 2 "unexpected signing kind: $KIND_LINE" ;;
esac

# The previous release (REQ-383; fix wave 1, B): the same check release.yml's resolve step runs, before anything is
# signed or pushed.
prc=0; pout="$(python3 -I -B "$SIGNERS" --root . --base-ref "refs/remotes/$REMOTE/main" previous --version "$VERSION" 2>&1)" || prc=$?
if [ "$prc" != 0 ]; then
  printf '%s\n' "$pout" >&2
  die 11 "the previous release is not verifiably released (signers.py previous exit $prc; release.yml would refuse $TAG at the tag) — nothing tagged. Tag the earlier release first (/release --tag <its version>), or re-create a lightweight or unverifiable previous tag as an SSH-signed one (or annotated with its fallback recorded), then run this again"
fi
printf '%s\n' "$pout"

# The tag-time re-check (REQ-350; P6 R11, R28): every PR merged since the previous release, through the CI check's own
# classifier (attestation.py release-check) — fail early, before anything is tagged or pushed. release.yml runs the same
# check on the pushed tag.
# A squash-merged PR's head commit is not in a normal clone: fetch every PR head so the classifier can judge it.
git fetch -q "$REMOTE" "+refs/pull/*/head:refs/remotes/$REMOTE/pr/*" \
  || die 7 "the tag-time re-check could not fetch the PR heads (git fetch $REMOTE +refs/pull/*/head failed: authentication or network) — nothing tagged"
REPO="$(gh repo view --json nameWithOwner 2>/dev/null | python3 -I -B -c 'import json, sys; print(json.load(sys.stdin)["nameWithOwner"])' 2>/dev/null)" \
  || die 7 "the tag-time re-check could not run: gh repo view failed (GH_TOKEN, network) — nothing tagged"
rrc=0; rout="$(python3 -I -B "$HERE/lib/specflow/attestation.py" release-check --repo "$REPO" --version "$VERSION" --tag-commit "$M" --base-ref "refs/remotes/$REMOTE/main" 2>&1)" || rrc=$?
if [ "$rrc" != 0 ]; then
  printf '%s\n' "$rout" >&2
  die 7 "the tag-time re-check failed (exit $rrc) — nothing tagged. A head-missing line means the PR head is not in this clone (git fetch $REMOTE '+refs/pull/*/head:refs/remotes/$REMOTE/pr/*'); a maintainer waiver posted on a rejected PR for its merged head clears it (a direct push of code: a waiver comment on the commit naming its sha, R28), then run this again"
fi
printf 'tag: %s on %s (%s)\n' "$TAG" "${M:0:7}" "$KIND_NAME"
[ "$DRY" = 0 ] || exit 0

if [ "$KIND_NAME" = ssh ]; then
  if ! git tag -s "$TAG" -m "Release $TAG" "$M"; then
    die 10 "git tag -s $TAG failed — no tag was created, nothing pushed. Likely causes: no ssh-agent or key loaded, a cancelled passphrase, or user.signingkey naming a missing file ($(git config user.signingkey 2>/dev/null || echo unset)); fix the signer and run it again"
  fi
  # signers.py pins gpg.ssh.program to the ssh-keygen on PATH and gpg.ssh.allowedSignersFile to the anchor's copy
  vrc=0; vout="$(python3 -I -B "$SIGNERS" --root . --base-ref "refs/remotes/$REMOTE/main" verify --tag "$TAG" 2>&1)" || vrc=$?
  if [ "$vrc" != 0 ] || ! grep -q '^kind: ssh-good' <<<"$vout"; then
    git tag -d "$TAG" >/dev/null
    printf '%s\n' "$vout" >&2
    vkind="$(sed -n 's/^kind: \([^ ]*\).*/\1/p' <<<"$vout" | head -n 1)"
    die 6 "$TAG did not verify against the anchor (${vkind:-git-error}) — local tag deleted, nothing pushed. $(advice "${vkind:-git-error}")"
  fi
  printf 'anchor: %s\n' "$(python3 -I -B "$SIGNERS" --root . --base-ref "refs/remotes/$REMOTE/main" anchor --tag "$TAG" 2>&1 | sed 's/^anchor: //' | head -n 1)"
  printf 'verified: %s\n' "$(grep '^kind: ' <<<"$vout" | head -n 1)"
else
  git -c tag.gpgSign=false tag -a "$TAG" -m "Release $TAG" "$M"
fi

if [ "$PUSH" = 1 ]; then
  if ! pout="$(git push -q "$REMOTE" "refs/tags/$TAG" 2>&1)"; then
    git tag -d "$TAG" >/dev/null 2>&1 || true
    printf '%s\n' "$pout" >&2
    die 9 "git push $REMOTE refs/tags/$TAG failed — the local $TAG this run created is deleted, so a re-run starts clean; fix the push (authentication, the tag ruleset) and run it again"
  fi
  printf 'pushed: %s to %s\n' "$TAG" "$REMOTE"
fi
if [ "$KIND_NAME" = ssh ] && fallback_recorded; then
  printf 'follow-up: remove the "- Annotated-tag fallback:" line from %s in a follow-up docs PR (the tag is signed)\n' "$KL"
fi
if git cat-file -e "$REMOTE/main:.github/workflows/release.yml" 2>/dev/null; then
  printf 'next: release.yml runs on the push of %s — gh run list --workflow release.yml --limit 1\n' "$TAG"
else
  printf 'next: no .github/workflows/release.yml on %s/main (an instance initialised before it existed): nothing re-verifies %s in a clean runner, so this local verification was the only one; the next ship PR'"'"'s verify-release.sh reads the tag\n' "$REMOTE" "$TAG"
fi
