#!/usr/bin/env bash
# REQ-383 (P6 R3, R17, R27; dfe-12): the signing anchor and the tag command. signers.py verifies a release tag's SSH
# signature against .github/allowed_signers as committed at the newest earlier SSH-signed release tag — a first-parent commit of main
# whose own signature verifies, back to trust on first use: the first key-listing commit after the newest key-less one,
# a strict ancestor of the tag — never the current tree; it binds the key's principal to the tagger's email, exactly
# (git itself does not), and honours .github/revoked_signers at the tag; release-tag.sh (Task 1.2) tags the ship PR's
# merge commit after the merge. REQ-306: an instance — however it inherited the factory's history — trusts no key of
# the factory's.
# Covers: REQ-383
# Covers: REQ-306
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
SG="$ROOT/scripts/lib/specflow/signers.py"
key() { ssh-keygen -q -t ed25519 -N '' -C "$1" -f "$W/$1" </dev/null >/dev/null; }
kline() { printf '%s namespaces="git" %s\n' "$1" "$(cut -d' ' -f1-2 "$W/$2.pub")"; }
key maint; key intruder
R="$W/r"; git init -q -b main "$R"
(cd "$R" && mkdir -p .github && printf '# allowed signers\n' > .github/allowed_signers && echo a > f && git add -A && git commit -qm "no key yet")
(cd "$R" && kline maint@example.invalid maint >> .github/allowed_signers && git commit -qam "first key")
FIRST=$(git -C "$R" rev-parse HEAD)
rel() {  # rel VERSION [DIR] — the release's notes on main (previous_release reads them), a first-parent commit of its own
  (cd "${2:-$R}" && mkdir -p docs/releases && printf -- '---\nversion: %s\ndate: 2026-10-05\n---\n' "$1" > "docs/releases/$1-notes.md" \
    && git add -A && git commit -qm "release $1")
}
# stag NAME TAGGER KEY [COMMIT] — the tagger through GIT_COMMITTER_EMAIL: check.sh exports it, and it wins over
# -c user.email (measured; F5, F12)
stag() { GIT_COMMITTER_EMAIL="$2" git -C "$R" -c gpg.format=ssh -c user.signingkey="$W/$3.pub" tag -s "$1" -m "Release $1" ${4:-HEAD}; }
sg() { local d="$R"; if [ "$1" = -C ]; then d="$2"; shift 2; fi
  rc=0; out=$(cd "$d" && python3 "$SG" --root . --base-ref main "$@" 2>&1) || rc=$?; }

rel 1.0.0; stag v1.0.0 maint@example.invalid maint; sg anchor --tag v1.0.0
ck "no previous release: the anchor is TOFU — the first commit after the key-less one whose file lists a key, a strict ancestor of the tag" \
  bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: $3 (tofu)" ]' _ "$rc" "$out" "$FIRST"
sg verify --tag v1.0.0
ck "signed by the anchored key, tagger = principal: exit 0, ssh-good" \
  bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good principal: maint@example.invalid tagger: maint@example.invalid" <<<"$2"' _ "$rc" "$out"
(cd "$R" && kline intruder@example.invalid intruder >> .github/allowed_signers && git commit -qam "a merger adds a key"); rel 1.1.0
stag v1.1.0 intruder@example.invalid intruder; sg anchor --tag v1.1.0
ck "the anchor for v1.1.0 is the previous release's tag, v1.0.0, which itself verifies" [ "$out" = "anchor: v1.0.0 (previous-release)" ]
sg verify --tag v1.1.0
ck "a key added after the anchor is not trusted for this release: exit 1, unlisted (dfe-12)" bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted" <<<"$2"' _ "$rc" "$out"
stag v1.0.5 intruder@example.invalid intruder; sg verify --tag v1.1.0
ck "a lower-version tag on the tagged commit itself (v1.0.5, the intruder's; not a strict ancestor) is never an anchor: still unlisted against v1.0.0 (F1, F37)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted .*anchor: v1.0.0" <<<"$2"' _ "$rc" "$out"
git -C "$R" tag -d v1.1.0 >/dev/null; stag v1.1.0 someone@example.invalid maint; sg verify --tag v1.1.0
ck "the anchored key under a tagger who is not its principal: exit 1, tagger-mismatch" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: tagger-mismatch principal: maint@example.invalid tagger: someone@example.invalid" <<<"$2"' _ "$rc" "$out"
git -C "$R" tag -d v1.1.0 >/dev/null; stag v1.1.0 MAINT@example.invalid maint; sg verify --tag v1.1.0
ck "…the principal comparison is exact and case-sensitive: tagger MAINT@example.invalid is tagger-mismatch (F12)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: tagger-mismatch" <<<"$2"' _ "$rc" "$out"
git -C "$R" tag -d v1.1.0 >/dev/null; stag v1.1.0 maint@example.invalid maint
git -C "$R" config gpg.ssh.allowedSignersFile "$W/nonexistent"; sg verify --tag v1.0.0
ck "a local gpg.ssh.allowedSignersFile never replaces the anchor's copy" [ "$rc" = 0 ]
git -C "$R" config --unset gpg.ssh.allowedSignersFile
V100=$(git -C "$R" rev-parse 'v1.0.0^{commit}'); git -C "$R" tag -d v1.0.0 >/dev/null; stag v1.0.0 intruder@example.invalid intruder "$V100"
sg verify --tag v1.1.0
ck "a previous release tag that does not verify against its own anchor: exit 1, anchor-unverified — never a fall-back to TOFU (F1)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: anchor-unverified" <<<"$2"' _ "$rc" "$out"
git -C "$R" tag -d v1.0.0 >/dev/null; stag v1.0.0 maint@example.invalid maint "$V100"
(cd "$R" && printf '# revoked signers\n%s\n' "$(cut -d' ' -f1-2 "$W/maint.pub")" > .github/revoked_signers && git add -A && git commit -qm "revoke maint"); rel 1.2.0
stag v1.2.0 maint@example.invalid maint; sg verify --tag v1.2.0
ck "a key listed in .github/revoked_signers at the tag's own tree: exit 1, revoked (F37)" bash -c '[ "$1" = 1 ] && grep -q "^kind: revoked" <<<"$2"' _ "$rc" "$out"
Q="$W/q"; git init -q -b main "$Q"   # F1: a previous release tag on a PR's intermediate commit, whose key the PR later removed
(cd "$Q" && mkdir -p .github docs/releases && kline maint@example.invalid maint > .github/allowed_signers && echo a > f && git add -A \
  && git commit -qm "first key" && git commit -q --allow-empty -m "after the key" && git checkout -qb feat \
  && kline intruder@example.invalid intruder >> .github/allowed_signers && printf -- '---\nversion: 0.5.0\ndate: 2026-10-01\n---\n' > docs/releases/0.5.0-notes.md \
  && git add -A && git commit -qm "PR commit 1: a key and the 0.5.0 notes" && kline maint@example.invalid maint > .github/allowed_signers \
  && git commit -qam "PR commit 2: the key removed again" && git checkout -q main && git merge -q --no-ff feat -m "Merge pull request #1")
F1=$(git -C "$Q" rev-parse feat~1); rel 1.0.0 "$Q"
R0="$R"; R="$Q"; stag v0.5.0 maint@example.invalid maint "$F1"; stag v1.0.0 intruder@example.invalid intruder; sg verify --tag v1.0.0; R="$R0"
ck "a previous release tag on a PR's intermediate commit (an ancestor of main, not a first-parent one): exit 1, anchor-off-main (F1)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: anchor-off-main" <<<"$2"' _ "$rc" "$out"
# PR #52 verifier run 1, finding 2 (R3's order): only an SSH-signed previous tag is held to the first-parent test — an
# annotated, unsigned or a lightweight one on that same intermediate commit never anchors, so TOFU applies, not a refusal.
QROOT=$(git -C "$Q" rev-list --max-parents=0 main)
for kind in annotated lightweight; do
  git -C "$Q" tag -d v0.5.0 >/dev/null
  if [ "$kind" = annotated ]; then git -C "$Q" tag -a v0.5.0 -m "0.5.0, unsigned" "$F1"; else git -C "$Q" tag v0.5.0 "$F1"; fi
  sg -C "$Q" anchor --tag v1.0.0
  ck "an $kind, unsigned previous release tag off the first-parent chain: TOFU (the first key-listing commit), not anchor-off-main" \
    bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: $3 (tofu)" ]' _ "$rc" "$out" "$QROOT"
  sg -C "$Q" verify --tag v1.0.0
  ck "…v1.0.0, signed by a key the TOFU anchor does not list, is unlisted against it — never anchor-off-main ($kind previous tag)" \
    bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted" <<<"$2"' _ "$rc" "$out"
done
git -C "$R" tag -a v0.9.0 -m annotated "$FIRST"; sg verify --tag v0.9.0
ck "an annotated, unsigned tag: exit 3, unsigned" bash -c '[ "$1" = 3 ] && grep -q "^kind: unsigned" <<<"$2"' _ "$rc" "$out"
git -C "$R" tag v0.8.0 "$FIRST"; sg verify --tag v0.8.0
ck "a lightweight tag: exit 1, lightweight" bash -c '[ "$1" = 1 ] && grep -q "^kind: lightweight" <<<"$2"' _ "$rc" "$out"
t=$(printf 'object %s\ntype commit\ntag v0.7.0\ntagger T <t@example.invalid> 1700000000 +0000\n\n0.7.0\n-----BEGIN PGP SIGNATURE-----\n\niQEzBAABCAAdFiEEfake\n=abcd\n-----END PGP SIGNATURE-----\n' \
  "$FIRST" | git -C "$R" hash-object -t tag -w --stdin)
git -C "$R" update-ref refs/tags/v0.7.0 "$t"
printf '#!/bin/sh\ncat >/dev/null\necho "gpg: Can'"'"'t check signature: No public key" >&2\nexit 1\n' > "$W/gpg"; chmod +x "$W/gpg"
git -C "$R" config gpg.program "$W/gpg"; sg verify --tag v0.7.0
ck "a GPG-signed tag this machine has no key for: exit 4, gpg-unverifiable — read from gpg's stderr, never --raw (F15; release.yml refuses it, P6 R27)" \
  bash -c '[ "$1" = 4 ] && grep -q "^kind: gpg-unverifiable" <<<"$2"' _ "$rc" "$out"
git -C "$R" config --unset gpg.program
N="$W/none"; git init -q -b main "$N"; (cd "$N" && echo a > f && git add -A && git commit -qm c)
GIT_COMMITTER_EMAIL=maint@example.invalid git -C "$N" -c gpg.format=ssh -c user.signingkey="$W/maint.pub" tag -s v1.0.0 -m r
sg -C "$N" verify --tag v1.0.0
ck "an SSH-signed tag with no allowed_signers key anywhere: exit 4, no-anchor (decided before git runs)" bash -c '[ "$1" = 4 ] && grep -q "^kind: no-anchor" <<<"$2"' _ "$rc" "$out"
(cd "$N" && mkdir -p .github && kline maint@example.invalid maint > .github/allowed_signers && git add -A && git commit -qm "the ship PR adds the first key")
GIT_COMMITTER_EMAIL=maint@example.invalid git -C "$N" -c gpg.format=ssh -c user.signingkey="$W/maint.pub" tag -s v1.1.0 -m r
sg -C "$N" verify --tag v1.1.0
ck "the newest earlier SSH-signed tag (v1.0.0, itself no-anchor) must verify: exit 1, anchor-unverified — never passed over" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: anchor-unverified" <<<"$2"' _ "$rc" "$out"
git -C "$N" tag -d v1.0.0 >/dev/null; sg -C "$N" verify --tag v1.1.0
ck "a first key added in the tagged commit itself is never its own anchor (TOFU is a strict ancestor): exit 4, no-anchor (F1)" \
  bash -c '[ "$1" = 4 ] && grep -q "^kind: no-anchor" <<<"$2"' _ "$rc" "$out"
git -C "$R" config gpg.format ssh; git -C "$R" config user.signingkey "$W/maint.pub"; sg signing-kind
ck "signing-kind: gpg.format ssh + user.signingkey → ssh" grep -q '^ssh' <<<"$out"
git -C "$R" config --unset gpg.format; sg signing-kind
ck "signing-kind: user.signingkey without gpg.format ssh → gpg" grep -q '^gpg (' <<<"$out"
git -C "$R" config --unset user.signingkey; sg signing-kind
ck "signing-kind: no key → none" grep -q '^none' <<<"$out"
# Build 1 final review (REQ-383; P6 R3 as corrected, dfe-12): the TOFU walk is bounded to the tag's own history, so a
# released tag's verdict is fixed once it exists — a key-less interval on main after it (a rotation done as two PRs, a
# key removed and re-added) changes neither its verdict nor the next release's anchor on it.
sgt() { GIT_COMMITTER_EMAIL="$3" git -C "$1" -c gpg.format=ssh -c user.signingkey="$W/$4.pub" tag -s "$2" -m "Release $2" ${5:-HEAD}; }
key newkey; key m2
X="$W/x"; git init -q -b main "$X"
(cd "$X" && mkdir -p .github && printf '# allowed signers\n' > .github/allowed_signers && echo a > f && git add -A && git commit -qm "no key yet" \
  && kline maint@example.invalid maint >> .github/allowed_signers && git commit -qam "first key")
XFIRST=$(git -C "$X" rev-parse HEAD); rel 2.0.0 "$X"; sgt "$X" v2.0.0 maint@example.invalid maint
(cd "$X" && printf '# allowed signers\n' > .github/allowed_signers && git commit -qam "rotation PR 1: the only key removed" \
  && kline maint@example.invalid maint >> .github/allowed_signers && kline new@example.invalid newkey >> .github/allowed_signers \
  && git commit -qam "rotation PR 2: the key re-added beside a new one")
rel 2.1.0 "$X"; sgt "$X" v2.1.0 maint@example.invalid maint
sg -C "$X" anchor --tag v2.0.0
ck "a key-less commit on main after a signed release does not move its TOFU anchor: still the first key commit before it" \
  bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: $3 (tofu)" ]' _ "$rc" "$out" "$XFIRST"
sg -C "$X" verify --tag v2.0.0
ck "…the released v2.0.0 still verifies ssh-good after the key was removed and re-added on main (its verdict is fixed once tagged)" \
  bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good principal: maint@example.invalid" <<<"$2"' _ "$rc" "$out"
sg -C "$X" verify --tag v2.1.0
ck "…the next release, signed by the same listed key, is anchored on v2.0.0 and ssh-good — never anchor-unverified" \
  bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good .*anchor: v2.0.0" <<<"$2"' _ "$rc" "$out"
git -C "$X" tag -d v2.1.0 >/dev/null; sgt "$X" v2.1.0 new@example.invalid newkey; sg -C "$X" verify --tag v2.1.0
ck "…the rotated-in key is not trusted until the release after one tagged on a commit that lists it: unlisted against v2.0.0" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted .*anchor: v2.0.0" <<<"$2"' _ "$rc" "$out"
# Fix wave 2 (REQ-383; P6 R3(i) as amended, the open finding B): the anchor candidates are the v<X.Y.Z> TAGS below the
# version whose commits are strict ancestors of the tag's commit, newest first — never the notes on main. The newest
# SSH-signed one must verify (else anchor-unverified); an unsigned, lightweight or GPG-signed one is passed over; only
# when no candidate is SSH-signed is the anchor TOFU. So a reviewed docs PR that deletes earlier releases' notes moves
# nothing.
Y="$W/y"; git init -q -b main "$Y"
(cd "$Y" && mkdir -p .github && printf '# allowed signers\n' > .github/allowed_signers && echo a > f && git add -A && git commit -qm "no key yet" \
  && kline old@example.invalid maint >> .github/allowed_signers && git commit -qam "first key")
rel 1.0.0 "$Y"; sgt "$Y" v1.0.0 old@example.invalid maint
(cd "$Y" && { printf '# allowed signers\n'; kline new@example.invalid newkey; } > .github/allowed_signers && git commit -qam "rotation: old removed (not revoked), new added")
rel 1.1.0 "$Y"; sgt "$Y" v1.1.0 old@example.invalid maint
sg -C "$Y" verify --tag v1.1.0
ck "after a rotation the next release is signed by the old key, still listed at the anchor v1.0.0: ssh-good" bash -c '[ "$1" = 0 ]' _ "$rc"
rel 1.2.0 "$Y"; sgt "$Y" v1.2.0 old@example.invalid maint; sg -C "$Y" verify --tag v1.2.0
ck "…a stolen old key signing v1.2.0 is unlisted against v1.1.0" bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted .*anchor: v1.1.0" <<<"$2"' _ "$rc" "$out"
(cd "$Y" && git rm -q docs/releases/1.0.0-notes.md docs/releases/1.1.0-notes.md && git commit -qm "docs: the earlier releases' notes deleted (a reviewed docs PR)")
sg -C "$Y" verify --tag v1.2.0
ck "deleting the earlier releases' notes never moves the anchor: the stolen old key is still unlisted against the tag v1.1.0 (finding B)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted .*anchor: v1.1.0" <<<"$2"' _ "$rc" "$out"
(cd "$Y" && printf -- '---\nversion: 1.1.5\ndate: 2026-10-05\n---\n' > docs/releases/1.1.5-notes.md && git add -A && git commit -qm "docs: notes for a version never tagged")
sg -C "$Y" verify --tag v1.2.0
ck "…notes for a version that was never tagged are irrelevant to the anchor: still unlisted against v1.1.0" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted .*anchor: v1.1.0" <<<"$2"' _ "$rc" "$out"
V110=$(git -C "$Y" rev-parse 'v1.1.0^{commit}'); git -C "$Y" tag -d v1.1.0 >/dev/null; sg -C "$Y" anchor --tag v1.2.0
ck "the newest SSH-signed tag deleted: the next older SSH-signed tag, v1.0.0, anchors (R3's caveat; the ruleset protects tags)" \
  bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: v1.0.0 (previous-release)" ]' _ "$rc" "$out"
t=$(printf 'object %s\ntype commit\ntag v1.1.0\ntagger T <old@example.invalid> 1700000000 +0000\n\n1.1.0\n-----BEGIN PGP SIGNATURE-----\n\niQEzBAABCAAdFiEEfake\n=abcd\n-----END PGP SIGNATURE-----\n' \
  "$V110" | git -C "$Y" hash-object -t tag -w --stdin); git -C "$Y" update-ref refs/tags/v1.1.0 "$t"; sg -C "$Y" anchor --tag v1.2.0
ck "…replaced by a GPG-signed tag (a garbage signature block): passed over to v1.0.0" bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: v1.0.0 (previous-release)" ]' _ "$rc" "$out"
git -C "$Y" tag -d v1.1.0 >/dev/null; git -C "$Y" tag v1.1.0 "$V110"; sg -C "$Y" anchor --tag v1.2.0
ck "…replaced by a lightweight tag: passed over to v1.0.0" bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: v1.0.0 (previous-release)" ]' _ "$rc" "$out"
git -C "$Y" tag -d v1.1.0 >/dev/null; git -C "$Y" tag -a v1.1.0 -m "1.1.0, unsigned" "$V110"; sg -C "$Y" anchor --tag v1.2.0
ck "…replaced by an annotated, unsigned tag: passed over to v1.0.0" bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: v1.0.0 (previous-release)" ]' _ "$rc" "$out"
# Fix wave 2 (C10): with no SSH-signed candidate left the anchor is TOFU, which re-trusts the keys of the newest key-listing run's first commit — a key
# removed but not revoked among them (R3's TOFU caveat); revocation on main is the defence at tag time.
P="$W/p"; git init -q -b main "$P"
(cd "$P" && mkdir -p .github && printf '# allowed signers\n' > .github/allowed_signers && echo a > f && git add -A && git commit -qm "no key yet" \
  && kline maint@example.invalid maint >> .github/allowed_signers && git commit -qam "first key" \
  && { printf '# allowed signers\n'; kline new@example.invalid newkey; } > .github/allowed_signers && git commit -qam "rotation: maint removed (not revoked)")
PFIRST=$(git -C "$P" rev-parse HEAD~1)
rel 1.0.0 "$P"; sgt "$P" v1.0.0 maint@example.invalid maint; rel 1.1.0 "$P"; sgt "$P" v1.1.0 maint@example.invalid maint
sg -C "$P" verify --tag v1.1.0
ck "the removed key signing v1.1.0 is unlisted against v1.0.0, whose tree lists only the new key" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted .*anchor: v1.0.0" <<<"$2"' _ "$rc" "$out"
P100=$(git -C "$P" rev-parse 'v1.0.0^{commit}'); git -C "$P" tag -d v1.0.0 >/dev/null; sg -C "$P" anchor --tag v1.1.0
ck "the only SSH-signed earlier tag deleted: no candidate is SSH-signed, so the anchor is TOFU" \
  bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: $3 (tofu)" ]' _ "$rc" "$out" "$PFIRST"
sg -C "$P" verify --tag v1.1.0
ck "…and TOFU re-trusts the newest key-listing run's keys, the removed-but-not-revoked key among them (R3's caveat)" \
  bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good .*anchor: $3" <<<"$2"' _ "$rc" "$out" "$PFIRST"
git -C "$P" tag -a v1.0.0 -m "1.0.0, unsigned" "$P100"; sg -C "$P" anchor --tag v1.1.0
ck "the only SSH-signed earlier tag replaced by an annotated, unsigned one: TOFU" \
  bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: $3 (tofu)" ]' _ "$rc" "$out" "$PFIRST"
(cd "$P" && printf '# revoked signers\n%s\n' "$(cut -d' ' -f1-2 "$W/maint.pub")" > .github/revoked_signers && git add -A && git commit -qm "revoke maint")
sg -C "$P" verify --tag v1.1.0
ck "…the defence: the key revoked on main refuses it at tag time (revoked)" bash -c '[ "$1" = 1 ] && grep -q "^kind: revoked" <<<"$2"' _ "$rc" "$out"
# Build 1 final review (REQ-383; P6 R3 as corrected): at tag time revocation is read at the tag's tree AND at the base's
# tip — a key revoked on main after the ship PR merged, before the tag, is refused; a released tag's own verdict
# (--released, the reading anchors and the PR-time previous-tag check use) is the tag's tree only.
Z="$W/z"; git init -q -b main "$Z"
(cd "$Z" && mkdir -p .github && printf '# allowed signers\n' > .github/allowed_signers && echo a > f && git add -A && git commit -qm "no key yet" \
  && kline maint@example.invalid maint >> .github/allowed_signers && kline m2@example.invalid m2 >> .github/allowed_signers && git commit -qam "two keys")
rel 1.0.0 "$Z"; sgt "$Z" v1.0.0 maint@example.invalid maint; rel 1.1.0 "$Z"; ZSHIP=$(git -C "$Z" rev-parse HEAD)
(cd "$Z" && printf '# revoked signers\n%s\n' "$(cut -d' ' -f1-2 "$W/m2.pub")" > .github/revoked_signers && git add -A && git commit -qm "revoke m2 (it leaked)")
sgt "$Z" v1.1.0 m2@example.invalid m2 "$ZSHIP"; sg -C "$Z" verify --tag v1.1.0
ck "a key revoked on main after the ship PR merged signs the ship merge commit: revoked at tag time (not ssh-good)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: revoked" <<<"$2"' _ "$rc" "$out"
sg -C "$Z" verify --tag v1.1.0 --released
ck "…the released reading (--released) reads revocation at the tag's tree only" bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good" <<<"$2"' _ "$rc" "$out"
# Build 1 final review (REQ-383): a shallow clone never reaches TOFU — the walk would treat the boundary as the start of
# history and trust a key added after the real TOFU commit.
git clone -q --depth 2 "file://$X" "$W/shallow"
sgt "$W/shallow" v9.0.0 maint@example.invalid maint; sg -C "$W/shallow" verify --tag v9.0.0
ck "a shallow clone: exit 1, kind shallow — never a TOFU anchor" bash -c '[ "$1" = 1 ] && grep -q "^kind: shallow" <<<"$2"' _ "$rc" "$out"
sg -C "$W/shallow" anchor --tag v9.0.0
ck "…anchor on a shallow clone: exit 1, shallow" bash -c '[ "$1" = 1 ] && grep -q "^shallow" <<<"$2"' _ "$rc" "$out"
# Build 1 final review and fix wave 2 (REQ-383; art-release-readiness; C3): signing-kind is ssh | gpg | other | none,
# and none means no signer at all — an X.509 or other gpg.format, an SSH default-key command or a GPG secret key for the
# committer's email is a signer, so --annotated is never offered; the reason names what was found.
git -C "$R" config gpg.format x509; git -C "$R" config user.signingkey somekey; sg signing-kind
ck "signing-kind: gpg.format x509 is a signer: other, naming x509 (release-tag.sh exits 5, never the annotated path)" \
  bash -c 'grep -q "^other (" <<<"$1" && grep -qi "x509" <<<"$1"' _ "$out"
git -C "$R" config --unset user.signingkey; sg signing-kind
ck "signing-kind: gpg.format x509 without user.signingkey is still other, not none" grep -q '^other (' <<<"$out"
git -C "$R" config gpg.format smime-ish; git -C "$R" config user.signingkey somekey; sg signing-kind
ck "signing-kind: any gpg.format other than ssh or openpgp, with a key configured: other, naming the value" \
  bash -c 'grep -q "^other (" <<<"$1" && grep -qF "smime-ish" <<<"$1"' _ "$out"
git -C "$R" config --unset user.signingkey
git -C "$R" config gpg.format ssh; git -C "$R" config gpg.ssh.defaultKeyCommand "ssh-add -L"; sg signing-kind
ck "signing-kind: gpg.format ssh with gpg.ssh.defaultKeyCommand is an SSH signer" \
  bash -c 'grep -q "^ssh" <<<"$1" && grep -qF "defaultKeyCommand" <<<"$1"' _ "$out"
git -C "$R" config --unset gpg.ssh.defaultKeyCommand; sg signing-kind
ck "signing-kind: gpg.format ssh with neither a key nor a default-key command: none, saying so" \
  bash -c 'grep -q "^none (" <<<"$1" && grep -qF "gpg.format is ssh" <<<"$1"' _ "$out"
git -C "$R" config --unset gpg.format
printf '#!/bin/sh\nc=0; s=0; for a; do [ "$a" = --with-colons ] && c=1; [ "$a" = --list-secret-keys ] && s=1; done\n[ "$s$c" = 11 ] || exit 2\necho "sec:u:255:22:0123456789ABCDEF:1700000000:::u:::scSC:::+:::ed25519:::0:"\necho "uid:u::::1700000000::FFFF::T <specflow-test@example.invalid>::::::::::0:"\n' > "$W/gpgsec"
printf '#!/bin/sh\necho "gpg: error reading key: No secret key" >&2\nexit 2\n' > "$W/gpgnone"
printf '#!/bin/sh\necho "gpg: WARNING: unsafe permissions on homedir"\nexit 0\n' > "$W/gpgnoise"; chmod +x "$W/gpgsec" "$W/gpgnone" "$W/gpgnoise"
git -C "$R" config gpg.program "$W/gpgsec"; sg signing-kind
ck "signing-kind: no user.signingkey but a GPG secret key for the committer's email (--with-colons, a sec record): gpg, not none" \
  bash -c 'grep -q "^gpg (" <<<"$1" && grep -qF "secret key" <<<"$1"' _ "$out"
git -C "$R" config gpg.program "$W/gpgnone"; sg signing-kind
ck "signing-kind: no key configured and gpg has no secret key for the committer: none, saying so" \
  bash -c 'grep -q "^none" <<<"$1" && grep -qF "no GPG secret key" <<<"$1"' _ "$out"
git -C "$R" config gpg.program "$W/gpgnoise"; sg signing-kind
ck "signing-kind: gpg output with no sec record (a warning on stdout, exit 0) is no secret key: none" grep -q '^none' <<<"$out"
git -C "$R" config --unset gpg.program
# Fix wave 2 (REQ-383; C1): revocation fails closed — a git error reading .github/revoked_signers is
# revocation-unreadable and a malformed file revocation-malformed, both refused; never read as "absent".
key m3; key m4
RV="$W/rv"; git init -q -b main "$RV"
(cd "$RV" && mkdir -p .github && printf '# allowed signers\n' > .github/allowed_signers && echo a > f && git add -A && git commit -qm "no key yet" \
  && kline maint@example.invalid maint >> .github/allowed_signers && printf '# revoked signers\n%s\n' "$(cut -d' ' -f1-2 "$W/m3.pub")" > .github/revoked_signers \
  && git add -A && git commit -qm "first key; m3 revoked")
rel 1.0.0 "$RV"; sgt "$RV" v1.0.0 maint@example.invalid maint
sg -C "$RV" verify --tag v1.0.0
ck "a well-formed revoked_signers that does not list the signing key: ssh-good" bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good" <<<"$2"' _ "$rc" "$out"
(cd "$RV" && printf '# revoked signers\nmaint@example.invalid namespaces="git" %s\n' "$(cut -d' ' -f1-2 "$W/m3.pub")" > .github/revoked_signers && git commit -qam "revoked_signers in allowed_signers format")
sg -C "$RV" verify --tag v1.0.0
ck "revoked_signers on main in allowed_signers format: exit 1, revocation-malformed (refused, never read as absent)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: revocation-malformed" <<<"$2"' _ "$rc" "$out"
(cd "$RV" && printf '# revoked signers\nssh-ed25519 not*base64!\n' > .github/revoked_signers && git commit -qam "garbage base64")
sg -C "$RV" verify --tag v1.0.0
ck "revoked_signers with garbage base64: exit 1, revocation-malformed" bash -c '[ "$1" = 1 ] && grep -q "^kind: revocation-malformed" <<<"$2"' _ "$rc" "$out"
(cd "$RV" && printf '# revoked signers\n%s\n' "$(cut -d' ' -f1-2 "$W/m4.pub")" > .github/revoked_signers && git commit -qam "m4 revoked")
RB=$(git -C "$RV" rev-parse HEAD:.github/revoked_signers); rm -f "$RV/.git/objects/${RB:0:2}/${RB:2}"
sg -C "$RV" verify --tag v1.0.0
ck "revoked_signers on main that git cannot read (its blob missing): exit 1, revocation-unreadable — never absent" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: revocation-unreadable" <<<"$2"' _ "$rc" "$out"
# Fix wave 2 (REQ-383; C2): the tagger is git's own parse of the tag header (for-each-ref %(taggeremail)), never a
# regular expression over the raw object — a header with two angle-bracket pairs, or a fake tagger line in the message.
htag() {  # htag DIR NAME KEY HEADER MESSAGE — a hand-built tag object on HEAD, SSH-signed over its payload as git signs one
  local c p="$W/payload"; c=$(git -C "$1" rev-parse HEAD)
  { printf 'object %s\ntype commit\ntag %s\n' "$c" "$2"; [ -z "$4" ] || printf '%s\n' "$4"; printf '\n%s\n' "$5"; } > "$p"
  rm -f "$p.sig"; ssh-keygen -q -Y sign -n git -f "$W/$3" "$p" </dev/null >/dev/null 2>&1
  git -C "$1" update-ref "refs/tags/$2" "$(cat "$p" "$p.sig" | git -C "$1" hash-object --literally -t tag -w --stdin)"
}
H="$W/h"; git init -q -b main "$H"
(cd "$H" && mkdir -p .github && printf '# allowed signers\n' > .github/allowed_signers && echo a > f && git add -A && git commit -qm "no key yet" \
  && kline maint@example.invalid maint >> .github/allowed_signers && git commit -qam "first key" && git commit -q --allow-empty -m "later")
htag "$H" v1.0.0 maint 'tagger Evil <intruder@example.invalid> <maint@example.invalid> 1700000000 +0000' 'Release v1.0.0'
sg -C "$H" verify --tag v1.0.0
ck "a tagger header with two angle-bracket pairs: git's parse (the first) is the tagger — tagger-mismatch, never the last pair" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: tagger-mismatch principal: maint@example.invalid tagger: intruder@example.invalid" <<<"$2"' _ "$rc" "$out"
htag "$H" v1.0.1 maint '' "$(printf 'Release v1.0.1\ntagger M <maint@example.invalid> 1700000000 +0000')"
sg -C "$H" verify --tag v1.0.1
ck "a tag object with no tagger header (a fake tagger line in its message): exit 1, bad, naming the missing tagger" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: bad" <<<"$2" && grep -qi "no tagger" <<<"$2"' _ "$rc" "$out"
# Fix wave 2 (C10, C4(d)): local configuration never widens trust — a gpg.ssh.allowedSignersFile that lists the intruder
# is overridden by the anchor's copy, and a gpg.ssh.program that fakes a good signature is replaced by the ssh-keygen
# on PATH for every verification.
sgt "$H" v2.0.0 intruder@example.invalid intruder
kline intruder@example.invalid intruder > "$W/wide-allowed"; git -C "$H" config gpg.ssh.allowedSignersFile "$W/wide-allowed"
sg -C "$H" verify --tag v2.0.0
ck "a local gpg.ssh.allowedSignersFile that lists the intruder does not widen trust: unlisted" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted" <<<"$2"' _ "$rc" "$out"
git -C "$H" config --unset gpg.ssh.allowedSignersFile
cat > "$W/fakessh" <<'EOF'
#!/bin/sh
case " $* " in *" sign "*) exec ssh-keygen "$@" ;; esac
case " $* " in *find-principals*) echo "${FAKE_PRINCIPAL:-intruder@example.invalid}"; exit 0 ;; esac
cat >/dev/null 2>&1
echo "Good \"git\" signature for ${FAKE_PRINCIPAL:-intruder@example.invalid} with ED25519 key SHA256:fake"
exit 0
EOF
chmod +x "$W/fakessh"; git -C "$H" config gpg.ssh.program "$W/fakessh"
sg -C "$H" verify --tag v2.0.0
ck "a local gpg.ssh.program that fakes a good signature is never used to verify: unlisted (ssh-keygen from PATH, pinned)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted" <<<"$2"' _ "$rc" "$out"
git -C "$H" config --unset gpg.ssh.program
# Fix wave 2 (C6): a later commit never changes a tag's verdict — every key commented out, then the intruder's
# key added, in two later PRs, moves neither v2.0.0's anchor nor its verdict.
(cd "$X" && printf '# allowed signers\n' > .github/allowed_signers && git commit -qam "later PR 1: every key commented out" \
  && kline intruder@example.invalid intruder >> .github/allowed_signers && git commit -qam "later PR 2: the intruder's key alone")
sg -C "$X" anchor --tag v2.0.0
ck "a key-less commit and a re-add after the tag: v2.0.0's TOFU anchor is unchanged" bash -c '[ "$1" = 0 ] && [ "$2" = "anchor: $3 (tofu)" ]' _ "$rc" "$out" "$XFIRST"
sg -C "$X" verify --tag v2.0.0
ck "…and its verdict is unchanged: ssh-good (a later key-less commit cannot un-verify an earlier tag)" bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good" <<<"$2"' _ "$rc" "$out"
# Fix wave 2 (C10): a git error during the first-parent walk is a refusal (git-error), never "no anchor".
rc=0; out=$(cd "$X" && python3 "$SG" --root . --base-ref no/such/ref verify --tag v2.0.0 2>&1) || rc=$?
ck "a base ref git cannot walk: exit 1, git-error — never no-anchor (exit 4, a WARN at PR time)" \
  bash -c '[ "$1" = 1 ] && grep -q "^kind: git-error" <<<"$2"' _ "$rc" "$out"
if ! instance; then
  ck ".github/allowed_signers: one key line — the maintainer's git email, namespaces=\"git\", an ssh-ed25519 key" \
    bash -c 'k=$(grep -vE "^(#|$)" "$1"); [ "$(printf "%s\n" "$k" | wc -l | tr -d " ")" = 1 ] && grep -qE "^ashwin\.pingali@geninspired\.com namespaces=\"git\" ssh-ed25519 [A-Za-z0-9+/]{68}$" <<<"$k"' _ "$ROOT/.github/allowed_signers"
  ck ".github/allowed_signers carries no private key material" no grep -q 'PRIVATE KEY' "$ROOT/.github/allowed_signers"
  ck ".github/revoked_signers exists and revokes nothing yet" bash -c 'test -f "$1" && ! grep -qvE "^(#|$)" "$1"' _ "$ROOT/.github/revoked_signers"
  D="$W/inst"; copy_template "$D"
  ck "init (scaffold-free) exits 0" bash -c "cd '$D' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Sig --profile engineer --stack python </dev/null >/dev/null 2>&1"
  ck "an instance's .github/allowed_signers lists no key — the factory maintainer's never reaches it (REQ-306)" \
    bash -c 'test -f "$1" && ! grep -qvE "^(#|$)" "$1" && grep -qi "add your key" "$1"' _ "$D/.github/allowed_signers"
  # F2: an instance made by `git clone` (the factory's key-listing history kept) or by "Use this template" (one commit,
  # the factory tree, key included) trusts its owner's first key PR — TOFU starts after init's key-less commit — and
  # never the factory maintainer's key its history lists.
  FT="$W/factory"; copy_template "$FT"; { printf '# allowed signers\n'; kline factory@example.invalid intruder; } > "$FT/.github/allowed_signers"
  (cd "$FT" && git init -q -b main && git add -A && git commit -qm "factory history" && git commit -q --allow-empty -m "more factory history")
  git clone -q "$FT" "$W/clone"
  mkdir -p "$W/tmpl"; git -C "$FT" archive HEAD | tar -xf - -C "$W/tmpl"; (cd "$W/tmpl" && git init -q -b main && git add -A && git commit -qm "Initial commit")
  for I in "$W/clone" "$W/tmpl"; do
    b=$(basename "$I")
    ck "$b: init (scaffold-free) on an inherited history exits 0" \
      bash -c "cd '$I' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Own --profile engineer --stack python </dev/null >/dev/null 2>&1"
    (cd "$I" && kline owner@example.invalid maint >> .github/allowed_signers && git commit -qam "the owner's key, by PR" && git commit -q --allow-empty -m "later work")
    rel 0.1.0 "$I"
    R0="$R"; R="$I"; stag v0.1.0 owner@example.invalid maint; sg verify --tag v0.1.0
    ck "$b: the owner's first signed tag verifies against the owner's key PR (TOFU after init's key-less commit, F2)" \
      bash -c '[ "$1" = 0 ] && grep -q "^kind: ssh-good principal: owner@example.invalid" <<<"$2"' _ "$rc" "$out"
    git -C "$I" tag -d v0.1.0 >/dev/null; stag v0.1.0 factory@example.invalid intruder; sg verify --tag v0.1.0; R="$R0"
    ck "$b: a tag signed by the factory maintainer's key, which the inherited history lists, is unlisted (REQ-306, F2)" \
      bash -c '[ "$1" = 1 ] && grep -q "^kind: unlisted" <<<"$2"' _ "$rc" "$out"
  done
fi
# REQ-383 (Task 1.2; P6 R17, R27): release-tag.sh tags the ship PR's merge commit on main after the merge — SSH-signed and
# verified against the anchor, or annotated only with --annotated and the fallback already on main; never GPG alone.
# Covers: REQ-383
O="$W/origin.git"; T="$W/t"; git init -q --bare "$O"; git init -q -b main "$T"
(cd "$T" && cp -R "$ROOT/scripts" . && find scripts -name __pycache__ -prune -exec rm -rf {} + \
  && { [ ! -f scripts/template-pack.yml ] || { grep -v '^attestation_since:' scripts/template-pack.yml > scripts/template-pack.yml.new && mv scripts/template-pack.yml.new scripts/template-pack.yml; }; } \
  && mkdir -p .github docs/releases && kline specflow-test@example.invalid maint > .github/allowed_signers \
  && git add -A && git commit -qm base && git remote add origin "$O" && git push -q origin main)
# Task 3.1 (REQ-350; R28): release-tag.sh runs the tag-time re-check, which asks gh — a stub gh answers: the repository
# is o/r; every merge commit is the exact merge of a PR (a number of its own) whose head is the merge's second parent
# and which carries a maintainer waiver for that head (the PR's review, which the fixture does not run); every other
# first-parent commit is a direct push, whose comments are none or — with STUB_WAIVE set — a maintainer waiver naming
# that commit. No GitHub Release exists (a 404 is "[]" here: not published). Build 3 final review (findings 3, 13, 15):
# the fixture's follow-up documents are PRs, as release.md has them — a direct push of a release document is a phase
# artifact, outside the minor exception.
export STUB_PRS_DIR="$W/stubprs"; mkdir -p "$STUB_PRS_DIR"
mkdir -p "$W/ghbin"; cat > "$W/ghbin/gh" <<'GH'
#!/bin/sh
case "$*" in
  "repo view"*) echo '{"nameWithOwner": "o/r"}' ;;
  *"/issues/"*"/comments")
    n=$(echo "$*" | sed 's|.*issues/\([0-9]*\)/comments.*|\1|')
    if [ -f "$STUB_PRS_DIR/$n" ]; then
      printf '[{"id": 2, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T11:00:00Z", "updated_at": "2026-10-01T11:00:00Z", "html_url": "https://github.com/o/r/pull/%s", "body": "<!-- specflow-verifier:waive sha:%s -->\\nThe PR, reviewed by the maintainer in the fixture."}]\n' "$n" "$(cat "$STUB_PRS_DIR/$n")"
    else echo '[]'; fi ;;
  *"/comments")
    if [ -n "${STUB_WAIVE:-}" ]; then
      sha=$(echo "$*" | sed 's|.*commits/\([0-9a-f]*\)/comments|\1|')
      printf '[{"id": 1, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T11:00:00Z", "updated_at": "2026-10-01T11:00:00Z", "html_url": "https://github.com/o/r/commit/%s", "body": "<!-- specflow-verifier:waive sha:%s -->\\nReviewed after the fact by the maintainer."}]\n' "$sha" "$sha"
    else echo '[]'; fi ;;
  *"/commits/"*"/pulls")
    if [ -n "${STUB_PR_HEAD:-}" ] && [ "$(echo "$*" | sed 's|.*commits/\([0-9a-f]*\)/pulls.*|\1|')" = "${STUB_PR_SHA:-}" ]; then
      printf '[{"number": 9, "merged_at": "2026-10-01T10:00:00Z", "merge_commit_sha": "%s", "base": {"ref": "main"}, "head": {"sha": "%s"}, "user": {"login": "alice"}}]\n' "$STUB_PR_SHA" "$STUB_PR_HEAD"
    else
      sha=$(echo "$*" | sed 's|.*commits/\([0-9a-f]*\)/pulls.*|\1|')
      if p2=$(git rev-parse -q --verify "$sha^2" 2>/dev/null); then
        n=$(( $(ls "$STUB_PRS_DIR" | wc -l) + 100 )); echo "$p2" > "$STUB_PRS_DIR/$n"
        printf '[{"number": %s, "merged_at": "2026-10-01T10:00:00Z", "merge_commit_sha": "%s", "base": {"ref": "main"}, "head": {"sha": "%s"}, "user": {"login": "alice"}}]\n' "$n" "$sha" "$p2"
      else echo '[]'; fi
    fi ;;
  *"/commits/"*) echo '{"sha": "x", "author": {"login": "alice"}, "committer": {"login": "alice"}, "commit": {"verification": {"verified": false}}}' ;;
  *) echo '[]' ;;
esac
GH
chmod +x "$W/ghbin/gh"
(cd "$T" && git checkout -qb ship/1.0.0 && for d in notes migration known-limitations; do printf '# %s\n' "$d" > "docs/releases/1.0.0-$d.md"; done \
  && git add -A && git commit -qm "release docs" && git checkout -q main && git merge -q --no-ff ship/1.0.0 -m "Merge ship/1.0.0" && git push -q origin main)
M=$(git -C "$T" rev-parse HEAD)
rt() { rc=0; out=$(cd "$T" && PATH="$W/ghbin:$PATH" bash scripts/release-tag.sh "$@" 2>&1) || rc=$?; }
ssh_on() { git -C "$T" config gpg.format ssh; git -C "$T" config user.signingkey "$W/$1.pub"; }
key_off() { git -C "$T" config --unset gpg.format || true; git -C "$T" config --unset user.signingkey || true; }
tagged() { git -C "$T" rev-parse -q --verify "refs/tags/$1" >/dev/null; }
rt 1.0
ck "release-tag.sh: a version that is not X.Y.Z: exit 2" [ "$rc" = 2 ]
(cd "$T" && git checkout -q ship/1.0.0); rt 1.0.0; (cd "$T" && git checkout -q main)
ck "release-tag.sh: not on main: exit 2" [ "$rc" = 2 ]
rt 2.0.0
ck "release-tag.sh: no first-parent commit on origin/main added docs/releases/2.0.0-notes.md (not merged): exit 2" [ "$rc" = 2 ]
key_off; rt 1.0.0
ck "release-tag.sh: no SSH signing key and no --annotated: exit 3, nothing tagged" bash -c '[ "$1" = 3 ]' _ "$rc"
ck "…v1.0.0 does not exist" no tagged v1.0.0
rt 1.0.0 --annotated
ck "release-tag.sh: --annotated without the fallback line on main: exit 4 (the stop path), nothing tagged" \
  bash -c '[ "$1" = 4 ] && grep -qF "Annotated-tag fallback" <<<"$2"' _ "$rc" "$out"
git -C "$T" config user.signingkey "$W/maint.pub"; rt 1.0.0
ck "release-tag.sh: GPG alone (user.signingkey, no gpg.format ssh): exit 5 with the SSH set-up steps (P6 R27)" \
  bash -c '[ "$1" = 5 ] && grep -qF "gpg.format ssh" <<<"$2"' _ "$rc" "$out"
git -C "$T" config gpg.format x509; rt 1.0.0
ck "release-tag.sh: an X.509 signer (signing-kind other): exit 5, never the annotated path" \
  bash -c '[ "$1" = 5 ] && grep -qF "gpg.format ssh" <<<"$2"' _ "$rc" "$out"
ssh_on intruder; rt 1.0.0
ck "release-tag.sh: a key the anchor does not list: exit 6, the local tag deleted, nothing pushed" \
  bash -c '[ "$1" = 6 ] && [ -z "$(git -C "$2" ls-remote --tags origin v1.0.0)" ]' _ "$rc" "$T"
ck "…and no local v1.0.0 is left behind" no tagged v1.0.0
ck "…exit 6 prints the advice for its own kind only (unlisted: add the key by PR), not the other kinds' (C4(c))" \
  bash -c 'grep -qF "unlisted: the signing key is not in .github/allowed_signers" <<<"$1" && ! grep -qF "sign with another listed key" <<<"$1" && ! grep -qF "git fetch --unshallow" <<<"$1"' _ "$out"
git -C "$T" config gpg.ssh.program "$W/fakessh"; export FAKE_PRINCIPAL=specflow-test@example.invalid; rt 1.0.0; unset FAKE_PRINCIPAL
ck "release-tag.sh: a local gpg.ssh.program that fakes a good signature: the pre-push verify uses ssh-keygen from PATH — exit 6, nothing pushed" \
  bash -c '[ "$1" = 6 ] && [ -z "$(git -C "$2" ls-remote --tags origin v1.0.0)" ]' _ "$rc" "$T"
git -C "$T" config --unset gpg.ssh.program
ssh_on maint; rt 1.0.0 --dry-run
ck "release-tag.sh --dry-run: prints the decision (ssh, on the merge commit) and tags nothing" \
  bash -c '[ "$1" = 0 ] && grep -qF "(ssh)" <<<"$2" && grep -qF "${3:0:7}" <<<"$2"' _ "$rc" "$out" "$M"
ck "…v1.0.0 still does not exist" no tagged v1.0.0
# Finding 1 (REQ-350; R28): a squash-merged PR's head commit is not in the maintainer's clone — release-tag.sh fetches
# refs/pull/*/head before the re-check, so the PR is judged on its real head instead of failing head-missing.
HC="$W/headclone"; git clone -q -b main "$O" "$HC"
PRH=$(cd "$HC" && git checkout -q -b prx && echo pr > pr.txt && git add -A && git commit -qm "pr head" && git rev-parse HEAD && git push -q origin HEAD:refs/pull/9/head)
PRH=$(printf '%s' "$PRH" | head -n 1)
ck "…setup: the PR head is on origin's refs/pull/9/head and absent from the maintainer's clone" \
  bash -c '! git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null && git -C "$3" cat-file -e "$2^{commit}"' _ "$T" "$PRH" "$O"
rc=0; out=$(cd "$T" && STUB_PR_SHA="$M" STUB_PR_HEAD="$PRH" PATH="$W/ghbin:$PATH" bash scripts/release-tag.sh 1.0.0 --dry-run 2>&1) || rc=$?
ck "release-tag.sh: a PR-mapped commit whose head is only on refs/pull/*/head is fetched first — the check judges it, never head-missing (here its content check: that head is not the merge's)" \
  bash -c '! grep -qF "FAIL #9 head-missing" <<<"$1" && grep -qF "FAIL #9 merge-content-mismatch" <<<"$1" && git -C "$2" cat-file -e "$3^{commit}"' _ "$out" "$T" "$PRH"
(cd "$T" && echo dirty > stray.txt); rt 1.0.0; rm -f "$T/stray.txt"
ck "release-tag.sh: a dirty tree: exit 2" [ "$rc" = 2 ]
rt 1.0.0
ck "release-tag.sh: exit 0 — v1.0.0 is an SSH-signed tag object on the ship PR's merge commit, pushed" \
  bash -c '[ "$1" = 0 ] && [ "$(git -C "$2" cat-file -t v1.0.0)" = tag ] && [ "$(git -C "$2" rev-parse "v1.0.0^{commit}")" = "$3" ] && git -C "$2" cat-file tag v1.0.0 | grep -qF "BEGIN SSH SIGNATURE" && [ -n "$(git -C "$2" ls-remote --tags origin v1.0.0)" ]' _ "$rc" "$T" "$M"
ck "…it prints the verification" bash -c 'grep -q "^verified: kind: ssh-good" <<<"$1"' _ "$out"
# Fix wave 2 round 2 (REQ-383; C9): release.yml is Build 3's — with no .github/workflows/release.yml on origin/main the
# script never tells the maintainer to watch a run of it; it says this local verification was the only one.
ck "…with no release.yml on origin/main: no 'next: release.yml runs' line; it says the local verification was the only one, naming no build" \
  bash -c '! grep -qF "next: release.yml runs" <<<"$1" && grep -q "^next: no .github/workflows/release.yml" <<<"$1" && grep -qF "the only one" <<<"$1" && ! grep -qF "Build 3" <<<"$1"' _ "$out"
rt 1.0.0
ck "release-tag.sh: v1.0.0 already exists: exit 2" [ "$rc" = 2 ]
(cd "$T" && git checkout -qb ship/1.1.0 && for d in notes migration; do printf '# %s\n' "$d" > "docs/releases/1.1.0-$d.md"; done \
  && mkdir -p .github/workflows && printf 'name: release\n' > .github/workflows/release.yml \
  && printf '# KL\n\n- Annotated-tag fallback: `v1.1.0` is annotated, not signed (neither a GPG nor an SSH signing key at tag time); follow-up: re-tag it signed once a key is configured.\n' > docs/releases/1.1.0-known-limitations.md \
  && git add -A && git commit -qm "1.1.0 docs" && git checkout -q main && git merge -q --no-ff ship/1.1.0 -m "Merge ship/1.1.0" && git push -q origin main)
key_off; git -C "$T" config tag.gpgSign true; STUB_WAIVE=1 rt 1.1.0 --annotated
ck "release-tag.sh: no SSH key, --annotated, the fallback on main: exit 0, an annotated, unsigned tag object, pushed (tag.gpgSign true ignored)" \
  bash -c '[ "$1" = 0 ] && [ "$(git -C "$2" cat-file -t v1.1.0)" = tag ] && ! git -C "$2" cat-file tag v1.1.0 | grep -q "BEGIN .*SIGNATURE" && [ -n "$(git -C "$2" ls-remote --tags origin v1.1.0)" ]' _ "$rc" "$T"
ck "…with release.yml on origin/main, it points at the run the push starts" \
  bash -c 'grep -qF "next: release.yml runs on the push of v1.1.0" <<<"$1"' _ "$out"
ck "…--annotated prints, before it proceeds, that it is the engineer path (guided /next passes it only after the unsigned-tag confirmation)" \
  bash -c 'grep -qF "engineer path" <<<"$1" && grep -qF "unsigned-tag" <<<"$1"' _ "$out"
git -C "$T" config --unset tag.gpgSign
# Build 1 final review (REQ-383; P6 R17): the tag goes on the NEWEST first-parent commit that added the notes, and the
# release docs at it must be what main says shipped — an aborted, reverted ship PR is never tagged.
(cd "$T" && git checkout -qb ship/2.0.0 && for d in notes migration known-limitations; do printf 'OLD %s\n' "$d" > "docs/releases/2.0.0-$d.md"; done \
  && git add -A && git commit -qm "2.0.0 docs (aborted)" && git checkout -q main && git merge -q --no-ff ship/2.0.0 -m "Merge ship/2.0.0")
MOLD=$(git -C "$T" rev-parse HEAD)
(cd "$T" && git checkout -qb revert-2.0.0 && git revert --no-edit -m 1 HEAD >/dev/null && git checkout -q main && git merge -q --no-ff revert-2.0.0 -m "Merge revert-2.0.0" \
  && git checkout -qb ship/2.0.0-b && for d in notes migration known-limitations; do printf 'REAL %s\n' "$d" > "docs/releases/2.0.0-$d.md"; done \
  && git add -A && git commit -qm "2.0.0 docs" && git checkout -q main && git merge -q --no-ff ship/2.0.0-b -m "Merge ship/2.0.0-b" && git push -q origin main)
MREAL=$(git -C "$T" rev-parse HEAD)
ssh_on maint; rt 2.0.0 --dry-run
ck "release-tag.sh: a reverted ship PR re-shipped — the tag goes on the newest merge that added the notes, never the aborted one" \
  bash -c '[ "$1" = 0 ] && grep -qF "on ${2:0:7} (ssh)" <<<"$3" && ! grep -qF "${4:0:7}" <<<"$3"' _ "$rc" "$MREAL" "$out" "$MOLD"
(cd "$T" && git checkout -qb edit-2.0.0 && printf 'REAL notes, edited after the merge\n' > docs/releases/2.0.0-notes.md && git commit -qam "docs: notes edited after the merge" \
  && git checkout -q main && git merge -q --no-ff edit-2.0.0 -m "Merge edit-2.0.0" && git push -q origin main)
rt 2.0.0 --dry-run
ck "release-tag.sh: release docs on main that differ from the ship PR's merge commit: exit 2, naming the file, nothing tagged" \
  bash -c '[ "$1" = 2 ] && grep -qF "docs/releases/2.0.0-notes.md" <<<"$2" && ! git -C "$3" rev-parse -q --verify refs/tags/v2.0.0 >/dev/null' _ "$rc" "$out" "$T"
# 2.1.0's previous release is 2.0.0 (its notes are on main): it is tagged first, as the preflight requires (fix wave 1, B)
git -C "$T" tag -a -m "Release v2.0.0" v2.0.0 "$MREAL"
(cd "$T" && git checkout -qb ship/2.1.0 && for d in notes migration known-limitations; do printf '# %s\n' "$d" > "docs/releases/2.1.0-$d.md"; done \
  && git add -A && git commit -qm "2.1.0 docs" && git checkout -q main && git merge -q --no-ff ship/2.1.0 -m "Merge ship/2.1.0")
M21=$(git -C "$T" rev-parse HEAD)
(cd "$T" && git checkout -qb fallback-2.1.0 && printf -- '- Annotated-tag fallback: `v2.1.0` is annotated, not signed (neither a GPG nor an SSH signing key at tag time); follow-up: re-tag it signed once a key is configured.\n' >> docs/releases/2.1.0-known-limitations.md \
  && git commit -qam "docs: record the annotated-tag fallback (the exit 4 follow-up)" && git checkout -q main && git merge -q --no-ff fallback-2.1.0 -m "Merge fallback-2.1.0" && git push -q origin main)
key_off; rt 2.1.0 --annotated --dry-run
ck "release-tag.sh: known-limitations differing only by the follow-up's fallback line still tags the ship PR's merge commit" \
  bash -c '[ "$1" = 0 ] && grep -qF "on ${2:0:7} (annotated)" <<<"$3"' _ "$rc" "$M21" "$out"
# Fix wave 2 (REQ-383; C4(a), (b)): a remote whose tags cannot be read is a refusal of its own (exit 8), never "absent";
# a failed push is exit 9 and deletes the local tag it created, so a re-run starts clean.
mkdir -p "$W/shim"; printf '#!/bin/sh\nif [ "$1" = ls-remote ]; then echo "fatal: Could not read from remote repository." >&2; exit 128; fi\nexec "%s" "$@"\n' "$(command -v git)" > "$W/shim/git"; chmod +x "$W/shim/git"
rc=0; out=$(cd "$T" && PATH="$W/shim:$PATH" bash scripts/release-tag.sh 2.1.0 --annotated --dry-run 2>&1) || rc=$?
ck "release-tag.sh: git ls-remote --tags fails (auth, network): exit 8, naming it — never 'absent on the remote'" \
  bash -c '[ "$1" = 8 ] && grep -qF "ls-remote" <<<"$2"' _ "$rc" "$out"
printf '#!/bin/sh\necho "rejected by a hook" >&2\nexit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"; rt 2.1.0 --annotated
ck "release-tag.sh: the push fails: exit 9, and the local tag it created is deleted" bash -c '[ "$1" = 9 ] && grep -qF "push" <<<"$2"' _ "$rc" "$out"
ck "…no local v2.1.0 is left behind" no tagged v2.1.0
# Build 1 re-review (REQ-383; P6 R17): `git tag -s` itself failing (no agent or key, a cancelled passphrase, a
# user.signingkey naming a missing file) is exit 10 with advice — never git's own 128 outside the exit table.
git -C "$T" config gpg.format ssh; git -C "$T" config user.signingkey "$W/no-such-key.pub"; rt 2.1.0
ck "release-tag.sh: git tag -s fails (user.signingkey names a missing file): exit 10, naming the likely causes and that no tag was created" \
  bash -c '[ "$1" = 10 ] && grep -qF "git tag -s" <<<"$2" && grep -qF "no tag was created" <<<"$2" && grep -qF "user.signingkey" <<<"$2"' _ "$rc" "$out"
ck "…no local v2.1.0 is left behind (exit 10)" no tagged v2.1.0
key_off
ck "…exit 10 is in the script header's exit table, release.md's \"Tag the release\" exit list and the plan's R17 Interfaces alike (the plan where present)" \
  bash -c 'grep -qF "#   10 \`git tag -s\` itself failed" "$1" && grep -qF -- "- exit 10: signing the tag itself failed" "$2" && { [ ! -f "$3" ] || grep -qF "\`10\` \`git tag -s\` itself failed" "$3"; }' _ \
  "$ROOT/scripts/release-tag.sh" "$ROOT/.claude/commands/release.md" "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
rm -f "$O/hooks/pre-receive"; rt 2.1.0 --annotated
ck "…a re-run after the push is fixed tags and pushes (never 'already exists locally')" \
  bash -c '[ "$1" = 0 ] && [ -n "$(git -C "$2" ls-remote --tags origin v2.1.0)" ]' _ "$rc" "$T"
# Fix wave 1, E (REQ-383, REQ-350): release.yml exists (Build 3), so the "from Build 3 on" qualifiers Build 1 wrote are
# false now: none is left in release-tag.sh, signers.py, release_gate.py, pipeline.py or release.md.
ck "release-tag.sh, signers.py, release_gate.py, pipeline.py and release.md carry no 'from Build 3' / Build-3's-release.yml qualifier" bash -c '
hits=$(grep -nE "[Ff]rom Build 3|Build 3.s release\.yml|arrives with Build 3|until then this local" "$@" || true)
[ -z "$hits" ] || { printf "%s\n" "$hits"; exit 1; }' _ "$ROOT/scripts/release-tag.sh" "$ROOT/scripts/lib/specflow/signers.py" \
  "$ROOT/scripts/lib/specflow/release_gate.py" "$ROOT/scripts/lib/specflow/pipeline.py" "$ROOT/.claude/commands/release.md"
ck "release-tag.sh's header: release.yml re-verifies the pushed tag in a clean runner (present tense)" \
  bash -c 'h=$(sed -n "1,/^set -euo pipefail/p" "$1"); grep -qF "release.yml re-verifies the pushed tag in a clean runner" <<<"$h"' _ "$ROOT/scripts/release-tag.sh"
# Fix wave 2 (REQ-383; C4(e)): the script header enumerates every environment variable and git configuration key the
# script and signers.py read (the signing-forge enumeration).
ck "release-tag.sh's header names every environment variable and git config key it reads" bash -c '
h=$(sed -n "1,/^set -euo pipefail/p" "$1")
for w in SPECFLOW_RELEASE_REMOTE GH_TOKEN "GH_*" PYTHONPATH "python3 -I" GIT_COMMITTER_EMAIL PATH SSH_AUTH_SOCK gpg.format user.signingkey gpg.ssh.defaultKeyCommand \
         gpg.program gpg.openpgp.program gpg.ssh.program gpg.ssh.allowedSignersFile gpg.ssh.revocationFile tag.gpgSign user.email; do
  grep -qF -- "$w" <<<"$h" || { echo "missing $w"; exit 1; }
done' _ "$ROOT/scripts/release-tag.sh"
# Build 1 re-review (REQ-383; P6 R3): the signer files' header comments — the factory's and the comment-only copies
# init-project.sh writes into an instance — say what signers.py does: allowed_signers as of the newest earlier SSH-signed
# v<X.Y.Z> tag among the tag's first-parent ancestors (others passed over; TOFU when none), revoked_signers read at the tag
# and, at tag time, on main's tip too.
ck "the allowed_signers/revoked_signers headers (factory and init-project.sh's) name the anchor and the revocation reads as signers.py has them" \
  bash -c 'for f in "$1" "$3"; do grep -qF "newest earlier SSH-signed" "$f" && grep -qF "passed over" "$f" && ! grep -qF "previous release'"'"'s tag" "$f" || { echo "allowed: $f"; exit 1; }; done
  for f in "$2" "$3"; do grep -qF "on main'"'"'s tip" "$f" && ! grep -qF "in the tag'"'"'s own tree, is refused" "$f" || { echo "revoked: $f"; exit 1; }; done' _ \
  "$ROOT/.github/allowed_signers" "$ROOT/.github/revoked_signers" "$ROOT/scripts/init-project.sh"
# PR #53 verifier run 1, finding 4 (REQ-383; P6 R17): the three exit tables agree on exit 6 — every verdict release-tag.sh's
# advice() names, and `bad` (its default: a BAD signature, a tag with no tagger, ssh-keygen absent), appears in the
# script header's exit 6 entry, release.md's "- exit 6:" line and the plan's Interfaces exit 6 entry (where present).
# Covers: REQ-383
ck "exit 6's verdicts — advice()'s labels and bad — agree across the script header, release.md and the plan's Interfaces" \
  python3 - "$ROOT/scripts/release-tag.sh" "$ROOT/.claude/commands/release.md" "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md" <<'PY'
import os, re, sys
sh = open(sys.argv[1]).read()
body = sh[sh.index("advice() {"):]; body = body[:body.index("\n}\n")]
kinds = re.findall(r"^\s+([a-z][a-z-]*)\) echo", body, re.M) + ["bad"]
assert len(kinds) >= 11, kinds
hdr = sh[sh.index("#   6 "):sh.index("#   7 ")].replace("revocation-unreadable/-malformed", "revocation-unreadable, revocation-malformed")
x6 = next(l for l in open(sys.argv[2]).read().splitlines() if l.strip().startswith("- exit 6:"))
miss = [("header", k) for k in kinds if not re.search(r"\b%s\b" % re.escape(k), hdr)]
miss += [("release.md", k) for k in kinds if "`%s`" % k not in x6]
if os.path.exists(sys.argv[3]):
    pl = open(sys.argv[3]).read(); e6 = pl[pl.index("`6` the signed tag did not verify"):]; e6 = e6[:e6.index("`7` ")]
    miss += [("plan", k) for k in kinds if "`%s`" % k not in e6]
assert not miss, miss
PY
# PR #53 verifier run 1, finding 5 (REQ-383, REQ-306; P6 R3(i)): the signer headers (the factory's and init-project.sh's)
# draw candidates from all strict ancestors; an SSH-signed one off the first-parent chain is refused (anchor-off-main),
# not passed over; only unsigned, lightweight and GPG-signed candidates are passed over.
# Covers: REQ-383
ck "the allowed_signers headers (factory and init-project.sh's): strict ancestors; off the first-parent chain refused (anchor-off-main)" \
  bash -c 'for f in "$1" "$2"; do h=$(grep "^#" "$f" | tr "\n" " " | tr -s " #" "  "); [ "$f" = "$2" ] && h=$(sed -n "/^cat > .github\/allowed_signers/,/^SIGNERS/p" "$f" | tr "\n" " " | tr -s " #" "  ")
    for w in "strict ancestors" "anchor-off-main" "refused" "unsigned, lightweight and GPG-signed" "passed over"; do grep -qF -- "$w" <<<"$h" || { echo "$f: missing $w"; exit 1; }; done
    ! grep -qF "first-parent ancestors" <<<"$h" || { echo "$f: still first-parent ancestors"; exit 1; }; done' _ \
  "$ROOT/.github/allowed_signers" "$ROOT/scripts/init-project.sh"
# Task 3.1 (REQ-350; P6 R28): release-tag.sh runs the tag-time re-check before it tags — fail early.
# Covers: REQ-350
(cd "$T" && echo code > zz.sh && git add -A && git commit -qm "a direct push of code" && git checkout -qb ship/1.2.0 \
  && for d in notes migration known-limitations; do printf '# %s\n' "$d" > "docs/releases/1.2.0-$d.md"; done \
  && git add -A && git commit -qm docs && git checkout -q main && git merge -q --no-ff ship/1.2.0 -m "Merge ship/1.2.0" && git push -q origin main)
ssh_on maint; rt 1.2.0
ck "release-tag.sh: the re-check finds a direct push of code since v1.1.0 — exit 7, nothing tagged" bash -c '[ "$1" = 7 ] && grep -qF "direct-push code: zz.sh" <<<"$2"' _ "$rc" "$out"
ck "…v1.2.0 does not exist" no tagged v1.2.0
ck "…exit 7 names the waiver remedy (a maintainer waiver on the PR or on the commit, R28)" bash -c 'grep -qF "maintainer waiver" <<<"$1"' _ "$out"
# Fix wave 1, B (REQ-383; P6 R17, R30): release-tag.sh runs, before it signs or pushes, the previous-release check
# release.yml's "Resolve the stack and the previous release" step runs — one function, signers.previous_release_check
# (CLI: signers.py previous --version) — so /release --tag never pushes a tag release.yml would refuse.
# Covers: REQ-383
M12=$(git -C "$T" rev-parse HEAD)
(cd "$T" && git checkout -qb ship/1.3.0 && for d in notes migration known-limitations; do printf '# %s\n' "$d" > "docs/releases/1.3.0-$d.md"; done \
  && git add -A && git commit -qm "1.3.0 docs" && git checkout -q main && git merge -q --no-ff ship/1.3.0 -m "Merge ship/1.3.0" && git push -q origin main)
ssh_on maint; rt 1.3.0
ck "release-tag.sh: the previous release 1.2.0 has notes on main but no v1.2.0: exit 11 before signing, naming it — nothing tagged (release.yml refuses it too)" \
  bash -c '[ "$1" = 11 ] && grep -qF "v1.2.0" <<<"$2" && grep -qF "no tag" <<<"$2"' _ "$rc" "$out"
ck "…v1.3.0 does not exist (exit 11)" no tagged v1.3.0
git -C "$T" tag v1.2.0 "$M12"; rt 1.3.0
ck "release-tag.sh: a lightweight previous tag v1.2.0: exit 11 naming lightweight, nothing tagged" \
  bash -c '[ "$1" = 11 ] && grep -qF "lightweight" <<<"$2"' _ "$rc" "$out"
ck "…v1.3.0 still does not exist" no tagged v1.3.0
pv() { rc=0; out=$(cd "$T" && python3 "$SG" --root . --base-ref refs/remotes/origin/main previous --version "$@" 2>&1) || rc=$?; }
pv 1.3.0
ck "signers.py previous --version 1.3.0 (lightweight v1.2.0): exit 1, previous-refused: v1.2.0 lightweight" \
  bash -c '[ "$1" = 1 ] && grep -q "^previous-refused: v1.2.0 lightweight" <<<"$2"' _ "$rc" "$out"
git -C "$T" tag -d v1.2.0 >/dev/null
printf 'object %s\ntype commit\ntag v1.2.0\ntagger T <t@example.com> 1791200000 +0000\n\nr\n-----BEGIN PGP SIGNATURE-----\n\nwsBcBAABCAAQBQJnAAAACRAAAAAAAAAAAA\n=AAAA\n-----END PGP SIGNATURE-----\n' \
  "$M12" | git -C "$T" mktag > "$W/pgptag"; git -C "$T" update-ref refs/tags/v1.2.0 "$(cat "$W/pgptag")"
printf '#!/bin/sh\necho "gpg: Can'"'"'t check signature: No public key" >&2\nexit 2\n' > "$W/stubgpg"; chmod +x "$W/stubgpg"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gpg.program GIT_CONFIG_VALUE_0="$W/stubgpg" pv 1.3.0
ck "…a GPG-signed v1.2.0 this machine cannot check: exit 1, previous-refused: v1.2.0 gpg-unverifiable" \
  bash -c '[ "$1" = 1 ] && grep -q "^previous-refused: v1.2.0 gpg-unverifiable" <<<"$2"' _ "$rc" "$out"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gpg.program GIT_CONFIG_VALUE_0="$W/stubgpg" rt 1.3.0
ck "…and release-tag.sh refuses it: exit 11 naming gpg-unverifiable" bash -c '[ "$1" = 11 ] && grep -qF "gpg-unverifiable" <<<"$2"' _ "$rc" "$out"
git -C "$T" tag -d v1.2.0 >/dev/null; git -C "$T" tag -a -m "Release v1.2.0" v1.2.0 "$M12"; pv 1.3.0
ck "…an annotated v1.2.0: exit 0, previous: v1.2.0 unsigned (release.yml's 0|3; the fallback is the next ship PR's check)" \
  bash -c '[ "$1" = 0 ] && grep -q "^previous: v1.2.0 unsigned" <<<"$2"' _ "$rc" "$out"
pv 1.0.0
ck "…no earlier release: exit 0, previous: -" bash -c '[ "$1" = 0 ] && grep -qx "previous: -" <<<"$2"' _ "$rc" "$out"
ck "release-tag.sh and release.yml's resolve step both call signers.py previous (one function), never their own copy of the rule" \
  bash -c 'grep -qF "\"\$SIGNERS\" --root . --base-ref \"refs/remotes/\$REMOTE/main\" previous --version" "$1" && s=$(sed -n "/- name: Resolve the stack and the previous release/,/- name: Re-check/p" "$2") && grep -qF "signers.py --root . --base-ref refs/remotes/origin/main previous --version" <<<"$s" && ! grep -qF "previous_release(" <<<"$s" && ! grep -qF -- "--released" <<<"$s"' _ \
  "$ROOT/scripts/release-tag.sh" "$ROOT/.github/workflows/release.yml"
ck "exit 11 is in the script header's exit table, release.md's exit list and the plan's R17 Interfaces (the plan where present)" \
  bash -c 'grep -qF "#   11 the previous release" "$1" && grep -qF -- "- exit 11:" "$2" && { [ ! -f "$3" ] || grep -qF "\`11\` the previous release" "$3"; }' _ \
  "$ROOT/scripts/release-tag.sh" "$ROOT/.claude/commands/release.md" "$ROOT/docs/plans/2026-10-01-factory-v3-2-p6-plan.md"
# Fix wave 1, K (REQ-383, REQ-350; P6 R17): every python3 the tag path runs is isolated (-I): PYTHONPATH and the user
# site cannot change a verdict. A PYTHONPATH carrying a json.py that records its import is never read.
mkdir -p "$W/evil"; printf 'open("%s/evil.hit", "w").write("x")\nraise SystemExit(99)\n' "$W" > "$W/evil/json.py"
rc=0; out=$(cd "$T" && PYTHONPATH="$W/evil" PATH="$W/ghbin:$PATH" bash scripts/release-tag.sh 1.3.0 --dry-run 2>&1) || rc=$?
ck "release-tag.sh --dry-run with PYTHONPATH naming a json.py: never imported (python3 -I)" bash -c '[ ! -e "$1/evil.hit" ]' _ "$W"
ck "every python3 run in release.yml, release-tag.sh and release-publish.sh is python3 -I" python3 - "$ROOT/.github/workflows/release.yml" "$ROOT/scripts/release-tag.sh" "$ROOT/scripts/release-publish.sh" <<'PY'
import re, sys
bad = []
for p in sys.argv[1:]:
    for n, l in enumerate(open(p), 1):
        if l.lstrip().startswith("#"):
            continue
        for m in re.finditer(r"\bpython3\b(?! -I\b)", l):
            bad.append(f"{p}:{n}: {l.strip()[:100]}")
assert not bad, bad
PY
key_off
finish test_release_tag
