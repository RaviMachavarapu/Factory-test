#!/usr/bin/env bash
# REQ-324: scripts/verify-release.sh is a PR-time gate that run-quality-gates.sh runs (section 7) for a ship/<v> branch's version and each version whose
# docs/releases/<v>-notes.md differs from the base (SPECFLOW_BASE_REF, default origin/main): the three release docs exist,
# v<version> is not yet tagged, the notes' ## Artifacts rows equal dist/manifest.json row for row when it is present (else
# every row has the file | sha256 | size shape), known-limitations names every accepted or deferred SEC id,
# check-security-disposition.sh passes, and every [verifiable*] REQ of every live spec is claimed by a plan on the base ref
# and carries a // Proves: header. With dist/manifest.json present, every listed dist/ file must hash to its sha256 and
# size. In an instance only the template's own inherited specs are skipped, by slug — never by a spec's own created:
# date, and whether the tree is an instance is judged at the base ref. The previous release (the latest earlier version
# whose notes are on the base) must carry a v<prev> tag object that is signed and verifies or whose known-limitations
# records the annotated-tag fallback, on a commit that is an ancestor of the base. An SSH signature is checked against
# .github/allowed_signers as of the newest earlier SSH-signed release tag, back to trust on first use (signers.py, P6 R3),
# and an SSH-signed v<prev> must sit on a first-parent commit of the base (anchor-off-main, the tag-time rule). A
# lightweight, unrecorded-unsigned, BAD-signature, refused-SSH (unlisted, tagger-mismatch, revoked, anchor-off-main and
# the other signers.py refusals) or off-branch tag FAILs; a missing tag (art-release-readiness: the tag is created after
# that merge) is a WARN, and so is a signature this machine cannot check — a GPG signature, or an SSH one with no
# allowed_signers key at the anchor. Under SPECFLOW_QG_RUNNING it never re-runs the gates. The tagged demo is not evaluated.
# Covers: REQ-324
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
SHA=$(printf x | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
VL=$(python3 -c 'import json, sys; print(next(c["vector"] for c in json.load(open(sys.argv[1]))["vectors"] if c["severity"] == "low"))' \
  "$ROOT/tests/governance/fixtures/cvss4/vectors.json")
hdr() { printf -- '---\nschema: specflow-security/1\nkind: %s\nversion: 1.0.0\n---\n\n# %s\n\n' "$1" "$1"; }
SEED="$W/seed"; mkdir -p "$SEED/docs/specs" "$SEED/docs/plans" "$SEED/docs/security" "$SEED/verification/x"
cp -R "$ROOT/scripts" "$SEED/scripts"   # one copy of scripts/ per test
printf -- '---\ntype: spec\nstatus: accepted\n---\n- **REQ-900:** k. [verifiable-model]\n' > "$SEED/docs/specs/2099-01-01-x-design.md"
printf -- '---\ntype: plan\nspec: 2099-01-01-x\nimplements: [REQ-900]\n---\n' > "$SEED/docs/plans/2099-01-01-x-plan.md"
printf -- '// Proves: REQ-900\nlemma L() ensures true {}\n' > "$SEED/verification/x/k.dfy"
bt=$(printf '\140\140\140')
printf '%syaml\nmedium_cap: 5\nexpiry_horizon_days: 180\n%s\n' "$bt" "$bt" > "$SEED/docs/security/RUBRIC.md"
(cd "$SEED" && git init -q -b main && git add -A && git commit -qm base)
n=0
mkrepo() {  # a clone of the seed (main: scripts/, a spec with one [verifiable-model] REQ, a plan claiming it, its proof, a
  # rubric) with its own bare origin; HEAD on ship/1.0.0 with complete 1.0.0 security and release docs, committed
  n=$((n + 1)); R="$W/r$n"; git clone -q --bare "$SEED" "$R.git"; git clone -q "$R.git" "$R"
  # origin names github.com/o/r — the repository the notes' Release link must name — and git reaches the bare clone
  # through url.<bare>.insteadOf (the gate reads remote.origin.url as configured, never the rewritten URL)
  git -C "$R" remote set-url origin https://github.com/o/r.git; git -C "$R" config url."$R.git".insteadOf https://github.com/o/r.git
  (cd "$R" && git checkout -qb ship/1.0.0); mkdir -p "$R/docs/releases"
  hdr review > "$R/docs/security/1.0.0-review.md"; hdr disposition > "$R/docs/security/1.0.0-disposition.md"
  printf '# Notes\n\nRelease: https://github.com/o/r/releases/tag/v1.0.0\n\n## Artifacts\n\n| Filename | SHA-256 | Size (bytes) |\n|---|---|---|\n| `x-1.0.0.tar.gz` | `%s` | 1 |\n' "$SHA" \
    > "$R/docs/releases/1.0.0-notes.md"
  echo '# Migration' > "$R/docs/releases/1.0.0-migration.md"; echo '# Known limitations' > "$R/docs/releases/1.0.0-known-limitations.md"
  (cd "$R" && git add -A && git commit -qm "release docs (REQ-324)")
}
vr() { rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH -u SPECFLOW_HEAD_SHA -u GITHUB_ACTIONS SPECFLOW_RELEASE_BUILD=0 SPECFLOW_QG_RUNNING=1 SPECFLOW_BASE_REF=origin/main \
  bash scripts/verify-release.sh "$@" 2>&1) || rc=$?; }
mkrepo; vr
ck "complete 1.0.0 release docs pass" bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
ck "under SPECFLOW_QG_RUNNING it does not re-run the gates" grep -qF 'not re-running the gates' <<<"$out"
mkrepo; rm "$R/docs/releases/1.0.0-migration.md"; vr
ck "a missing migration doc fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "1.0.0-migration.md" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git reset -q HEAD~1); vr
ck "untracked release docs (not yet added) differ from the base: evaluated, not skipped" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git tag v1.0.0); vr
ck "notes changed for an already tagged v1.0.0 fail (the tag must not exist yet)" bash -c '[ "$1" = 1 ] && grep -q "v1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; printf '# Notes\n' > "$R/docs/releases/1.0.0-notes.md"; vr
ck "notes without an Artifacts table fail, saying so" bash -c '[ "$1" = 1 ] && grep -q "Artifacts" <<<"$2"' _ "$rc" "$out"
mkrepo; mkdir -p "$R/dist"; printf x > "$R/dist/x-1.0.0.tar.gz"
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$R/dist/manifest.json"; vr
ck "with dist/manifest.json present, rows equal to the manifest pass" [ "$rc" = 0 ]
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}, {"filename": "y.whl", "sha256": "%s", "size": 2}]}\n' \
  "$SHA" "$SHA" > "$R/dist/manifest.json"; vr
ck "…a manifest row the notes do not transcribe fails" bash -c '[ "$1" = 1 ] && grep -q "y.whl" <<<"$2"' _ "$rc" "$out"
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$R/dist/manifest.json"
printf y > "$R/dist/x-1.0.0.tar.gz"; vr
ck "…a dist/ file whose bytes no longer hash to the manifest's sha256 fails, naming it" \
  bash -c '[ "$1" = 1 ] && grep -q "dist/x-1.0.0.tar.gz" <<<"$2" && grep -q "sha256" <<<"$2"' _ "$rc" "$out"
rm "$R/dist/x-1.0.0.tar.gz"; vr
ck "…and a listed dist/ file that is missing fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "dist/x-1.0.0.tar.gz" <<<"$2"' _ "$rc" "$out"
printf x > "$R/dist/x-1.0.0.tar.gz"
printf '{"version": "1.0.0", "artifacts": [{"filename": "../x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$R/dist/manifest.json"; vr
ck "…and a manifest filename outside dist/ fails" bash -c '[ "$1" = 1 ] && grep -q "outside dist/" <<<"$2"' _ "$rc" "$out"
printf '{"version": "1.0.0", "artifacts": [{"file": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$R/dist/manifest.json"; vr
ck "…an entry without filename (the key every release hook writes) fails, naming the key" \
  bash -c '[ "$1" = 1 ] && grep -q "filename" <<<"$2"' _ "$rc" "$out"
if [ -f "$ROOT/scripts/release-stack.sh.template" ]; then   # the hook contract every stack's release.sh follows
mkrepo; rm -f "$R/docs/releases/1.0.0-notes.md"; (cd "$R" && SOURCE_DATE_EPOCH=1791158400 VERSION=1.0.0 DIST_DIR="$R/dist" bash scripts/release-stack.sh.template >/dev/null)
python3 - "$R" <<'PY'   # transcribe the hook's real manifest into the notes, as /release does before verify-release
import json, sys
r = sys.argv[1]; m = json.load(open(f"{r}/dist/manifest.json"))
rows = "".join(f"| `{a['filename']}` | `{a['sha256']}` | {a['size']} |\n" for a in m["artifacts"])
open(f"{r}/docs/releases/1.0.0-notes.md", "w").write("# Notes\n\nRelease: https://github.com/o/r/releases/tag/v1.0.0\n\n## Artifacts\n\n| Filename | SHA-256 | Size (bytes) |\n|---|---|---|\n" + rows)
PY
vr; ck "a manifest written by the release-hook template ({filename, sha256, size}), transcribed, passes" [ "$rc" = 0 ]
fi
mkrepo
printf -- '---\nid: SEC-001\nseverity: low\ncvss_vector: %s\ncite: [CWE-20]\naffects: [a:1]\n---\n\nbody\n' "$VL" >> "$R/docs/security/1.0.0-review.md"
printf -- '---\nid: SEC-001\nstatus: accepted\nowner: alice\nrationale: "fixture rationale text"\n---\n' >> "$R/docs/security/1.0.0-disposition.md"; vr
ck "known-limitations missing an accepted SEC id fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "SEC-001" <<<"$2"' _ "$rc" "$out"
echo '- SEC-0010 and XSEC-001: other ids' >> "$R/docs/releases/1.0.0-known-limitations.md"; vr
ck "…an id that only appears inside a longer token (SEC-0010, XSEC-001) does not name it: still fails (a \bSEC-NNN\b word match)" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-001 (accepted) not named" <<<"$2"' _ "$rc" "$out"
echo '- SEC-001: accepted low' >> "$R/docs/releases/1.0.0-known-limitations.md"; vr
ck "…naming it passes" [ "$rc" = 0 ]
sed -i.bak 's/^status: accepted/status: open/' "$R/docs/security/1.0.0-disposition.md"; rm "$R/docs/security/1.0.0-disposition.md.bak"
printf -- '---\nid: SEC-002\nseverity: low\ncvss_vector: %s\ncite: [CWE-20]\naffects: [a:1]\n---\n' "$VL" >> "$R/docs/security/1.0.0-review.md"; vr
ck "a disposition that fails check-security-disposition.sh fails verify-release, naming it" \
  bash -c '[ "$1" != 0 ] && grep -q "security-disposition" <<<"$2"' _ "$rc" "$out"
mkrepo; printf -- '- **REQ-901:** k2. [verifiable-model]\n' >> "$R/docs/specs/2099-01-01-x-design.md"; vr
ck "a [verifiable*] REQ no merged plan claims fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "REQ-901" <<<"$2"' _ "$rc" "$out"
mkrepo; printf 'stack: python\n' > "$R/.specflow.yml"
printf -- '---\ntype: spec\nstatus: accepted\ncreated: "2026-09-01"\n---\n- **REQ-950:** k3. [verifiable-model]\n' > "$R/docs/specs/2099-02-02-y-design.md"; vr
ck "in an instance, a new spec backdated before the cutoff is not skipped as inherited (its unclaimed REQ fails)" \
  bash -c '[ "$1" = 1 ] && grep -q "REQ-950" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -q main && printf -- '---\ntype: spec\nstatus: accepted\n---\n- **REQ-960:** f. [verifiable-model]\n' \
  > docs/specs/2026-09-25-factory-v3-2-design.md && git add -A && git commit -qm f && git push -q origin main && git checkout -q ship/1.0.0 \
  && git rebase -q main); : > "$R/.stack"; vr
ck "a template-source PR that adds .stack does not skip the template's own spec (instance-ness is judged at the base)" \
  bash -c '[ "$1" = 1 ] && grep -q "REQ-960" <<<"$2" && grep -q "\.stack" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -q main && printf 'stack: python\n' > .specflow.yml \
  && printf -- '---\ntype: plan\nspec: 2099-02-02-y\nimplements: [REQ-950]\n---\n' > docs/plans/2099-02-02-y-plan.md \
  && git add -A && git commit -qm y && git push -q origin main && git checkout -q ship/1.0.0 && git rebase -q main)
printf -- '---\ntype: spec\nstatus: accepted\ncreated: "2026-09-27"\n---\n- **REQ-950:** k3. [verifiable-model]\n' > "$R/docs/specs/2099-02-02-y-design.md"; vr
ck "in an instance, a new spec backdated to 2026-09-27 whose [verifiable*] REQ is claimed but unproved fails (inherited = fixed slugs)" \
  bash -c '[ "$1" = 1 ] && grep -q "REQ-950 claimed but no // Proves" <<<"$2"' _ "$rc" "$out"
mkrepo; rm "$R/verification/x/k.dfy"; vr
ck "a claimed [verifiable*] REQ without a // Proves: header fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
prev() {  # prev [KL-LINE] — mkrepo, then main also carries $PV's (default 0.9.0) notes and known-limitations (KL-LINE in
  # it); HEAD rebased
  local v="${PV:-0.9.0}"
  mkrepo; (cd "$R" && git checkout -q main && mkdir -p docs/releases && printf '# %s\n' "$v" > "docs/releases/$v-notes.md" \
    && printf '# Known limitations\n\n%s\n' "${1:-}" > "docs/releases/$v-known-limitations.md" && git add -A && git commit -qm "$v" \
    && git push -q origin main && git checkout -q ship/1.0.0 && git rebase -q main)
}
followup() {  # followup KL-LINE [COMMITTER-DATE] — a docs PR merged to main appends KL-LINE to $PV's known-limitations
  local v="${PV:-0.9.0}"
  (cd "$R" && git checkout -q main && printf '%s\n' "$1" >> "docs/releases/$v-known-limitations.md" && git add -A \
    && GIT_COMMITTER_DATE="${2:-}" git commit -qm "follow-up: record the fallback" && git push -q origin main \
    && git checkout -q ship/1.0.0 && git rebase -q main)
}
FB='- Annotated-tag fallback: v0.9.0 is annotated, not signed (no GPG key at tag time); follow-up: re-tag it signed.'
prev; vr
ck "the previous release's notes on the base with no v0.9.0 tag: a WARN naming it (the tag is created after its merge), not a FAIL" \
  bash -c '[ "$1" = 0 ] && grep -q "^WARN verify-release 1.0.0: .*v0.9.0" <<<"$2"' _ "$rc" "$out"
prev "$FB"; (cd "$R" && git tag v0.9.0 main); vr
ck "a lightweight v0.9.0 fails, naming it (a release tag is a tag object), even with the fallback recorded" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.9.0.*lightweight" <<<"$2"' _ "$rc" "$out"
prev; (cd "$R" && git tag -a -m 0.9.0 v0.9.0 main); vr
ck "an annotated, unsigned v0.9.0 with no fallback in 0.9.0's known-limitations fails, naming the file" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.9.0.*0.9.0-known-limitations.md" <<<"$2"' _ "$rc" "$out"
prev "$FB"; (cd "$R" && git tag -a -m 0.9.0 v0.9.0 main); vr
ck "…with the annotated-tag fallback recorded in 0.9.0's known-limitations on the base: passes, no WARN" \
  bash -c '[ "$1" = 0 ] && ! grep -q "^WARN" <<<"$2" && ! grep -q "v0.9.0" <<<"$(grep "^FAIL" <<<"$2")"' _ "$rc" "$out"
prev '- No annotated-tag fallback was needed for v0.9.0: it is signed.'; (cd "$R" && git tag -a -m 0.9.0 v0.9.0 main); vr
ck "a line merely naming 'annotated' and 'fallback' (\"no annotated-tag fallback was needed\") records nothing: an annotated, unsigned v0.9.0 still fails" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.9.0.*0.9.0-known-limitations.md" <<<"$2"' _ "$rc" "$out"
prev '- Annotated-tag fallback: `v0.9.0` is annotated, not signed (no GPG key at tag time); follow-up: re-tag it signed once a key is configured.'
(cd "$R" && git tag -a -m 0.9.0 v0.9.0 main); vr
ck "the exact line /release writes (release.md step 5, the '- Annotated-tag fallback:' prefix) records it: passes" \
  bash -c '[ "$1" = 0 ] && ! grep -q "v0.9.0" <<<"$(grep "^FAIL" <<<"$2")"' _ "$rc" "$out"
ck "release.md tells /release the gate reads that exact prefix, not any line naming 'annotated' and 'fallback'" \
  bash -c 'grep -qF "Annotated-tag fallback:" "$1" && ! grep -qF "naming both" "$1"' _ "$ROOT/.claude/commands/release.md"
# PR #42 third verifier run, finding 3 (REQ-324): the fallback is read from that version's known-limitations AT ITS
# TAG; the base is read only as it stood when the tag was created (the /release stop-and-follow-up-docs-PR path, whose
# docs PR merges before the tag is created). A line added to a released doc after its tag records nothing. Released
# docs are never edited after the tag; the inherited demo release (0.0.1-demo) is grandfathered by its known version:
# its legacy prose (a line naming "annotated" and "fallback", not negated) is its record.
# P7 R11 (REQ-324, REQ-391): the inherited demo's released known-limitations is unchanged since its tag, except the
# /release follow-up's removal of its stale "## Unsigned tag (follow-up required)" section once v0.0.1-demo is re-tagged
# SSH-signed by a key .github/allowed_signers lists (verified, never a marker substring) — exactly that section removed,
# nothing else changed (design review, polish item 3: a pure-removal rule would admit deleting any section). These
# checks exercise the released-document rule of the re-tag follow-up, never verify-release.sh or release_gate.py, so they
# cover REQ-391 alone (fix wave 1, finding 4); REQ-324 is cited where verify-release.sh runs.
# Covers: REQ-391
demo_kl_ok() {  # demo_kl_ok REPO FILE — unchanged since v0.0.1-demo, or the tag is SSH-signed by a listed key and FILE is the tagged one minus that section
  git -C "$1" diff --quiet v0.0.1-demo -- "$2" && return 0
  demo_tag_signed "$1" || return 1
  git -C "$1" show "v0.0.1-demo:$2" | python3 -c '
import re, sys
old, new = sys.stdin.read(), open(sys.argv[1]).read()
m = re.search(r"(?ms)^## Unsigned tag \(follow-up required\)\n.*?(?=^## |\Z)", old)
sys.exit(0 if m and new == old[:m.start()] + old[m.end():] else 1)' "$1/$2"
}
# "Signed" as review-gate.md's RELEASE exit gate and art-release-readiness read it since amendment C: SSH-signed and
# verified against .github/allowed_signers (P7 Build 2 final review, finding 3 — a marker substring in the tag object
# proves nothing). git verify-tag runs with the signers file as committed at REPO's HEAD (never the working tree, never the
# local configuration: gpg.ssh.program pinned to the ssh-keygen on PATH), with .github/revoked_signers at HEAD as the
# revocation list when it lists a key, and the principal ssh-keygen reports must be the tag's tagger (signers.py's
# GOOD_RE and its tagger binding). signers.verify itself is not used: its anchor is the newest earlier SSH-signed release
# tag below the tag's commit, and the demo's commit (792cecb) has none and no allowed_signers (it would say no-anchor).
demo_tag_signed() {  # demo_tag_signed REPO
  local a v te out rc=0 keygen
  keygen="$(command -v ssh-keygen)" || return 1
  [ "$(git -C "$1" cat-file -t refs/tags/v0.0.1-demo 2>/dev/null)" = tag ] || return 1
  te="$(git -C "$1" for-each-ref --format='%(taggeremail)' refs/tags/v0.0.1-demo | sed 's/^<//; s/>$//')"
  [ -n "$te" ] || return 1
  a="$(mktemp)"; v="$(mktemp)"
  if ! git -C "$1" show HEAD:.github/allowed_signers > "$a" 2>/dev/null; then rm -f "$a" "$v"; return 1; fi
  set -- "$1" -c "gpg.ssh.program=$keygen" -c "gpg.ssh.allowedSignersFile=$a"
  if git -C "$1" show HEAD:.github/revoked_signers 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' > "$v"; then
    set -- "$@" -c "gpg.ssh.revocationFile=$v"
  fi
  out="$(git -C "$@" verify-tag refs/tags/v0.0.1-demo 2>&1)" || rc=1
  rm -f "$a" "$v"
  [ "$rc" = 0 ] && grep -qF "Good \"git\" signature for $te with " <<<"$out"
}
if git -C "$ROOT" rev-parse -q --verify refs/tags/v0.0.1-demo >/dev/null 2>&1 \
   && git -C "$ROOT" cat-file -e v0.0.1-demo:docs/releases/0.0.1-demo-known-limitations.md 2>/dev/null; then
  ck "the released v0.0.1-demo known-limitations is unchanged since its tag, or lost only its stale fallback section by the /release follow-up (the tag SSH-signed by a listed key, verified)" \
    demo_kl_ok "$ROOT" docs/releases/0.0.1-demo-known-limitations.md
fi
# The fixture repository commits .github/allowed_signers listing the key K for the fixture's tagger (check.sh's
# specflow-test@example.invalid); U is a key nobody lists. "Signed" means signed by a listed key and verified (P7 Build 2
# final review, finding 3): an unsigned tag carrying the signature marker in its message, and a real signature by an
# unlisted or a revoked key, are refused.
# Fix wave 1, findings 2 and 3: $DK and its keys live under $W, which the EXIT trap removes, so an aborted step leaks
# nothing; and the fixtures need an ssh-keygen that can sign (-Y sign, OpenSSH 8.0+), as the SSH cases below do — without
# one they SKIP visibly instead of aborting the whole test.
DK="$W/demo-kl"; mkdir -p "$DK"
dk_ssh() {  # dk_ssh — ssh-keygen is on PATH and signs (-Y sign)
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  rm -f "$DK.probe" "$DK.probe.pub"
  ssh-keygen -q -t ed25519 -N "" -C probe -f "$DK.probe" </dev/null >/dev/null 2>&1 || return 1
  printf x | ssh-keygen -Y sign -n git -f "$DK.probe" >/dev/null 2>&1
}
if dk_ssh; then
  ssh-keygen -q -t ed25519 -N "" -C demo -f "$DK.key" </dev/null; ssh-keygen -q -t ed25519 -N "" -C other -f "$DK.other" </dev/null
  (cd "$DK" && git init -q -b main && mkdir .github \
    && printf 'specflow-test@example.invalid namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$DK.key.pub")" > .github/allowed_signers \
    && printf '# KL\n\n## Unsigned tag (follow-up required)\nannotated fallback\n\n## No other findings\nnone\n' > kl.md \
    && git add -A && git commit -qm one && git tag -a -m demo v0.0.1-demo && sed -i.bak '3,5d' kl.md && rm -f kl.md.bak && git commit -qam removal)
  C1=$(git -C "$DK" rev-parse HEAD~1)
  dtag() { git -C "$DK" tag -d v0.0.1-demo >/dev/null 2>&1 || true; git -C "$DK" "$@"; }   # re-create v0.0.1-demo on C1
  ck "fixture: an annotated (unsigned) demo tag and the section's removal — refused" no demo_kl_ok "$DK" kl.md
  printf 'demo\n-----BEGIN SSH SIGNATURE-----\nU1NIU0lHAAAAAQ==\n-----END SSH SIGNATURE-----\n' > "$DK.msg"
  dtag tag -a -F "$DK.msg" v0.0.1-demo "$C1"
  ck "fixture: the marker is in the unsigned tag object (the next check is not vacuous)" \
    bash -c 'git -C "$1" cat-file -p refs/tags/v0.0.1-demo | grep -qF -- "-----BEGIN SSH SIGNATURE-----"' _ "$DK"
  ck "fixture: an unsigned demo tag whose message carries a fake SSH signature block, and the section's removal — refused" \
    no demo_kl_ok "$DK" kl.md
  dtag -c gpg.format=ssh -c user.signingkey="$DK.other" tag -s -m demo v0.0.1-demo "$C1"
  ck "fixture: a demo tag SSH-signed by a key .github/allowed_signers does not list, and the section's removal — refused" \
    no demo_kl_ok "$DK" kl.md
  dtag -c gpg.format=ssh -c user.signingkey="$DK.key" tag -s -m demo v0.0.1-demo "$C1"
  ck "fixture: a demo tag SSH-signed by the listed key and the stale fallback section removed — admitted" demo_kl_ok "$DK" kl.md
  (cd "$DK" && git checkout -q v0.0.1-demo -- kl.md && sed -i.bak '6,7d' kl.md && rm -f kl.md.bak && git commit -qam other)
  ck "fixture: an SSH-signed demo tag and another section removed (a pure removal, not the fallback section) — refused" no demo_kl_ok "$DK" kl.md
  (cd "$DK" && git checkout -q HEAD~1 -- kl.md && echo "a line added after the tag" >> kl.md && git commit -qam addition)
  ck "fixture: an SSH-signed demo tag, the section removed and a line added — refused" no demo_kl_ok "$DK" kl.md
  (cd "$DK" && git checkout -q HEAD~2 -- kl.md && cut -d' ' -f1,2 "$DK.key.pub" > .github/revoked_signers && git add -A && git commit -qm revoke)
  ck "fixture: the section removed, the tag SSH-signed by the listed key that .github/revoked_signers now lists — refused" \
    no demo_kl_ok "$DK" kl.md
else
  echo "SKIP: no ssh-keygen that signs (-Y sign) on PATH — the demo re-tag fixtures (listed, unlisted, revoked, fake-block tags) did not run"
fi
prev; followup "$FB"; (cd "$R" && git tag -a -m 0.9.0 v0.9.0 main~1); vr
ck "the follow-up path: the tag's tree lacks the line, a docs PR merged to the base before the tag was created records it: passes" \
  bash -c '[ "$1" = 0 ] && ! grep -q "v0.9.0" <<<"$(grep "^FAIL" <<<"$2")"' _ "$rc" "$out"
prev; (cd "$R" && GIT_COMMITTER_DATE="@1700000000 +0000" git tag -a -m 0.9.0 v0.9.0 main); followup "$FB" "@1800000000 +0000"; vr
ck "a fallback line added to the released known-limitations after the tag was created records nothing: fails, naming the file" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.9.0.*0.9.0-known-limitations.md" <<<"$2"' _ "$rc" "$out"
DEMO_LEGACY='The release tag `v0.0.1-demo` is **annotated**, not **signed**. `art-release-readiness` standing rule is signed tags; annotated is permitted only as a fallback when GPG is unavailable in the implementation environment, with this follow-up recorded.'
PV=0.0.1-demo prev "$DEMO_LEGACY"; (cd "$R" && git tag -a -m demo v0.0.1-demo main); vr
ck "the inherited demo release (0.0.1-demo): its legacy prose naming 'annotated' and 'fallback' at its tag records it: passes" \
  bash -c '[ "$1" = 0 ] && ! grep -q "v0.0.1-demo" <<<"$(grep "^FAIL" <<<"$2")"' _ "$rc" "$out"
PV=0.0.1-demo prev '- No annotated-tag fallback was needed for v0.0.1-demo.'; (cd "$R" && git tag -a -m demo v0.0.1-demo main); vr
ck "…a negated legacy line ('No annotated-tag fallback was needed') records nothing, even for the demo: fails" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.0.1-demo.*0.0.1-demo-known-limitations.md" <<<"$2"' _ "$rc" "$out"
prev 'v0.9.0 is annotated; annotated is permitted only as a fallback when GPG is unavailable.'; (cd "$R" && git tag -a -m 0.9.0 v0.9.0 main); vr
ck "…and the legacy phrase is the demo's alone: for any other version it records nothing (the exact prefix is the rule)" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.9.0.*0.9.0-known-limitations.md" <<<"$2"' _ "$rc" "$out"
ck "release.md writes the rule down: a released doc is never edited after its tag, with the two exceptions" \
  bash -c 'grep -qF "is never edited after its tag" "$1" && grep -qF "docs/security/README.md" "$1"' _ "$ROOT/.claude/commands/release.md"
ck "review-gate.md's RELEASE exit gate writes the same rule down" \
  bash -c 'grep "RELEASE exit gate" "$1" | grep -qF "is never edited after its tag"' _ "$ROOT/.claude/rules/review-gate.md"
prev "$FB"; (cd "$R" && git checkout -q --detach main && git commit -q --allow-empty -m side && git tag -a -m 0.9.0 v0.9.0 \
  && git checkout -q ship/1.0.0); vr
ck "a v0.9.0 (fallback recorded) on a commit that is not an ancestor of the base fails, naming it" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.9.0.*ancestor" <<<"$2"' _ "$rc" "$out"
# P6 Task 1.1 (REQ-383, REQ-324; P6 R3): the previous release tag's SSH signature is checked against allowed_signers at
# the anchor — unlisted is a FAIL, no anchor key a WARN.
# Covers: REQ-383
# Covers: REQ-324
if command -v ssh-keygen >/dev/null 2>&1; then   # SSH signing, checked against .github/allowed_signers at the anchor (P6 R3)
  prev; SK="$W/sk$n"; ssh-keygen -q -t ed25519 -N '' -C t -f "$SK" </dev/null >/dev/null
  (cd "$R" && git checkout -q main && mkdir -p .github \
    && printf 'specflow-test@example.invalid namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$SK.pub")" > .github/allowed_signers \
    && git add .github && git commit -qm signers && git commit -q --allow-empty -m "after signers" && git push -q origin main \
    && git checkout -q ship/1.0.0 && git rebase -q main && git -c gpg.format=ssh -c user.signingkey="$SK" tag -s -m 0.9.0 v0.9.0 main); vr
  ck "an SSH-signed v0.9.0 whose key the anchor's allowed_signers lists (tagger = principal): passes, no WARN" \
    bash -c '[ "$1" = 0 ] && ! grep -q "^WARN" <<<"$2"' _ "$rc" "$out"
  ssh-keygen -q -t ed25519 -N '' -C u -f "$W/uk$n" </dev/null >/dev/null
  (cd "$R" && git tag -d v0.9.0 >/dev/null && git -c gpg.format=ssh -c user.signingkey="$W/uk$n" tag -s -m 0.9.0 v0.9.0 main); vr
  ck "…signed by a key allowed_signers does not list: FAIL unlisted — no longer a WARN (P6 R3, dfe-12)" \
    bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: previous release tag v0.9.0: .*unlisted" <<<"$2"' _ "$rc" "$out"
  prev; (cd "$R" && git -c gpg.format=ssh -c user.signingkey="$SK" tag -s -m 0.9.0 v0.9.0 main); vr
  ck "…an SSH signature with no allowed_signers key at the anchor: a WARN naming why, not a FAIL" \
    bash -c '[ "$1" = 0 ] && grep -q "^WARN verify-release 1.0.0: previous release tag v0.9.0 is signed but cannot be checked here (no-anchor)" <<<"$2"' _ "$rc" "$out"
  # Fix wave 2 (REQ-383, REQ-324; C5): the PR-time check applies the anchor's first-parent rule — an SSH-signed v0.9.0
  # on a PR's intermediate commit (an ancestor of the base, not a first-parent one) FAILs anchor-off-main, as the
  # tag-time anchor walk refuses it, so PR time and tag time agree.
  prev; (cd "$R" && git checkout -q main && mkdir -p .github \
    && printf 'specflow-test@example.invalid namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$SK.pub")" > .github/allowed_signers \
    && git add .github && git commit -qm signers && git commit -q --allow-empty -m "after signers" \
    && git checkout -qb feat && git commit -q --allow-empty -m "PR commit 1" && git commit -q --allow-empty -m "PR commit 2" \
    && git checkout -q main && git merge -q --no-ff feat -m "Merge pull request #2" && git push -q origin main \
    && git checkout -q ship/1.0.0 && git rebase -q main && git -c gpg.format=ssh -c user.signingkey="$SK" tag -s -m 0.9.0 v0.9.0 feat~1); vr
  ck "an SSH-signed v0.9.0 on a PR's intermediate commit (an ancestor of the base, not first-parent): FAIL anchor-off-main, as at tag time" \
    bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: previous release tag v0.9.0.*anchor-off-main" <<<"$2"' _ "$rc" "$out"
else
  echo "SKIP: no ssh-keygen on PATH — the previous release's SSH-signature cases did not run"
fi
pgptag() {  # pgptag STUB-BODY — prev (no fallback), then v0.9.0 is a tag object carrying a fake PGP signature block, and
  # gpg.program is a stub (STUB-BODY) standing in for gpg's answer; no real keys
  prev; printf '#!/bin/sh\ncat >/dev/null\n%s\n' "$1" > "$W/gpg$n"; chmod +x "$W/gpg$n"
  (cd "$R" && t=$(printf 'object %s\ntype commit\ntag v0.9.0\ntagger T <t@example.invalid> 1700000000 +0000\n\n0.9.0\n-----BEGIN PGP SIGNATURE-----\n\niQEzBAABCAAdFiEEfake\n=abcd\n-----END PGP SIGNATURE-----\n' \
    "$(git rev-parse main)" | git hash-object -t tag -w --stdin) && git update-ref refs/tags/v0.9.0 "$t" && git config gpg.program "$W/gpg$n")
}
pgptag 'echo "gpg: Can'"'"'t check signature: No public key" >&2; exit 1'; vr
ck "a PGP-signed v0.9.0 whose key is absent here (No public key), no fallback recorded: a WARN naming gpg-unverifiable and release.yml's SSH-only check (P6 R27), and passes" \
  bash -c '[ "$1" = 0 ] && grep -q "^WARN verify-release 1.0.0: previous release tag v0.9.0 is signed but cannot be checked here (gpg-unverifiable); release.yml refuses it at the tag, where it verifies SSH signatures against .github/allowed_signers (P6 R27)" <<<"$2" && ! grep -qF "from Build 3" <<<"$2"' _ "$rc" "$out"
pgptag 'echo "gpg: BAD signature from \"T <t@example.invalid>\"" >&2; exit 1'; vr
ck "a PGP-signed v0.9.0 with a BAD signature fails, naming it, even though a key was present" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v0.9.0.*BAD signature" <<<"$2"' _ "$rc" "$out"
pgptag 'echo "[GNUPG:] NEWSIG"; echo "[GNUPG:] GOODSIG 0123456789ABCDEF T <t@example.invalid>"
echo "[GNUPG:] VALIDSIG 0123456789ABCDEF0123456789ABCDEF01234567 2023-11-14 1700000000 0 4 0 1 10 00 0123456789ABCDEF0123456789ABCDEF01234567"
echo "[GNUPG:] TRUST_ULTIMATE 0 pgp"; exit 0'; vr
ck "a PGP-signed v0.9.0 whose signature verifies (git tag -v), no fallback recorded: passes, no WARN" \
  bash -c '[ "$1" = 0 ] && ! grep -q "^WARN" <<<"$2"' _ "$rc" "$out"
pgptag 'exit 0'; (cd "$R" && git config gpg.program "$W/absent-gpg$n"); vr
ck "a PGP-signed v0.9.0 where gpg is absent here: a WARN (cannot be verified on this machine), not a FAIL" \
  bash -c '[ "$1" = 0 ] && grep -q "^WARN verify-release 1.0.0: previous release tag v0.9.0 is signed but cannot be checked here (gpg-unverifiable)" <<<"$2"' _ "$rc" "$out"
# PR #42 third verifier run, code medium (REQ-324): a ship/<v> PR is evaluated for <v> from its branch name, as the
# disposition gate resolves it (disposition_gate.ship_branch_version), so a ship PR that never adds its notes FAILs
# "three docs exist" instead of printing a SKIP.
mkrepo; (cd "$R" && git rm -q docs/releases/1.0.0-notes.md && git commit -qm "no notes"); vr
ck "a ship/1.0.0 PR with no 1.0.0 notes is evaluated from its branch name: fails, naming the missing notes (not a SKIP)" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: docs/releases/1.0.0-notes.md missing" <<<"$2" && ! grep -q "^SKIP" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb feature/w main); rc=0
out=$(cd "$R" && env -u GITHUB_HEAD_REF SPECFLOW_HEAD_BRANCH=ship/2.0.0 SPECFLOW_QG_RUNNING=1 SPECFLOW_BASE_REF=origin/main \
  bash scripts/verify-release.sh 2>&1) || rc=$?
ck "…the branch comes from SPECFLOW_HEAD_BRANCH (CI's PR head) when set" \
  bash -c '[ "$1" != 0 ] && grep -q "^FAIL verify-release 2.0.0: docs/releases/2.0.0-notes.md missing" <<<"$2"' _ "$rc" "$out"
ck "release_gate.py reuses the disposition gate's ship/<v> resolution" grep -qF 'disposition_gate.ship_branch_version' "$ROOT/scripts/lib/specflow/release_gate.py"
# PR #42 fourth verifier run, code low 4 (REQ-324, REQ-322): a non-semver ship/<v> branch is a clear ERROR, not a traceback.
mkrepo; (cd "$R" && git checkout -qb ship/v1.0.0); vr
ck "ship/v1.0.0: exit 2, an ERROR naming the branch and the expected ship/<major>.<minor>.<patch> form, no traceback" \
  bash -c '[ "$1" = 2 ] && grep -q "^ERROR verify-release: .*ship/v1.0.0" <<<"$2" && grep -qF "ship/<major>.<minor>.<patch>" <<<"$2" && ! grep -q Traceback <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb feature/z main); echo z > "$R/z.txt"; (cd "$R" && git add -A && git commit -qm z); vr
ck "no release notes differ from the base: a SKIP" bash -c '[ "$1" = 0 ] && grep -q "^SKIP verify-release" <<<"$2"' _ "$rc" "$out"
ck "the gates' Release gates section runs verify-release.sh" \
  bash -c 'awk "/SECTION \"Release gates\"/{f=1} /SECTION \"Summary\"/{f=0} f" "$1" | grep -qF "scripts/verify-release.sh"' _ "$ROOT/scripts/run-quality-gates.sh"
# PR #48 verifier run 3, code low a (REQ-324): check_req_claims' note for an inherited spec in an instance is pinned
# exactly — "<slug> is inherited from the template; not checked in an instance", with no stale plan tag after it.
# Covers: REQ-324
IR="$W/inherited"; mkdir -p "$IR/docs/specs"
( cd "$IR" && git init -q && printf 'profile: engineer\n' > .specflow.yml \
  && printf -- '---\ntype: spec\nstatus: approved\n---\n# demo\n' > docs/specs/2026-05-28-demo-greeting-design.md \
  && git add -A && git commit -qm base )
ck "check_req_claims notes an inherited spec in an instance with the exact text" \
  python3 - "${SPECFLOW_RG_LIB:-$ROOT/scripts/lib/specflow}" "$IR" <<'PYR'
import sys; sys.path.insert(0, sys.argv[1]); from pathlib import Path; import release_gate as rg
fails, notes = rg.check_req_claims(Path(sys.argv[2]), "HEAD")
want = "2026-05-28-demo-greeting is inherited from the template; not checked in an instance"
assert want in notes, notes
assert not any("F-10/W-7" in n for n in notes), notes
PYR
# P6 Task 2.3 (REQ-324, REQ-384; P6 R26): with no dist/manifest.json, verify-release.sh builds the reproducible subset
# itself — RELEASE_PARTS=reproducible, from the tree of SPECFLOW_HEAD_SHA (HEAD when it is unset) — and compares the
# notes' rows with it; a mismatch prints the expected rows, and transcribing them does not move the archive.
# Covers: REQ-384
if instance; then
  echo "SKIP: the CI-path checks build the template's own source archive (init removes release-template.sh and template-pack.yml)"
else
# The seed's scripts/ copy tracks __pycache__ files the host's runs rewrite: commits below name their paths (never -a), and
# vrb writes no bytecode, so only the commits the case makes can move the tree the build archives.
# vrb runs the build path: it unsets SPECFLOW_HEAD_SHA as vr unsets SPECFLOW_HEAD_BRANCH — ci.yml's gates step exports both
# (this task adds the first), and in CI the scratch repository would otherwise be asked to build the factory PR's head
# SHA, which it does not contain (PR #52 verifier run 1, finding 1); a case that needs a head SHA passes VRB_HEAD_SHA.
# VRB_BASE overrides the base ref (default the short origin/main a local run uses); VRB_RB exports SPECFLOW_RELEASE_BUILD.
vrb() { rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH -u SPECFLOW_HEAD_SHA -u GITHUB_ACTIONS -u SPECFLOW_RELEASE_BUILD PYTHONDONTWRITEBYTECODE=1 SPECFLOW_QG_RUNNING=1 \
  SPECFLOW_BASE_REF="${VRB_BASE:-origin/main}" ${VRB_HEAD_SHA:+"SPECFLOW_HEAD_SHA=$VRB_HEAD_SHA"} ${VRB_GHA:+"GITHUB_ACTIONS=$VRB_GHA"} \
  ${VRB_RB:+"SPECFLOW_RELEASE_BUILD=$VRB_RB"} bash scripts/verify-release.sh "$@" 2>&1) || rc=$?; }
# ci.yml's gates step's SPECFLOW_BASE_REF for a PR to main (its format() template with the base filled in)
CIB=$(python3 - "$ROOT/.github/workflows/ci.yml" <<'PYB'
import re, sys
m = re.search(r"SPECFLOW_BASE_REF: \$\{\{ github\.event_name == 'pull_request' && format\('([^']*)', github\.base_ref\)", open(sys.argv[1]).read())
print(m.group(1).replace("{0}", "main") if m else "")
PYB
)
mkrepo
(cd "$R" && { printf -- '---\nversion: 1.0.0\ndate: 2026-10-05\n---\n'; cat docs/releases/1.0.0-notes.md; } > n && mv n docs/releases/1.0.0-notes.md && git commit -qm "notes date" -- docs/releases/1.0.0-notes.md); vrb
ck "CI path: the notes' row is not the built archive's — FAIL, then the expected rows from the CI build" \
  bash -c '[ "$1" = 1 ] && grep -qF "expected Artifacts rows" <<<"$2" && grep -qF "specflow-factory-1.0.0-source.tar" <<<"$2"' _ "$rc" "$out"
grep -E '^\| `specflow-factory-1\.0\.0-source\.tar`' <<<"$out" | head -1 > "$W/row"
(cd "$R" && python3 - "$W/row" <<'PY'
import re, sys
p = "docs/releases/1.0.0-notes.md"; row = open(sys.argv[1]).read().strip()
t = re.sub(r"^\| `x-1\.0\.0\.tar\.gz`.*$", row, open(p).read(), flags=re.M); open(p, "w").write(t)
PY
git commit -qm "transcribe CI's rows" -- docs/releases/1.0.0-notes.md); vrb
ck "…after transcribing the printed row: PASS — the transcription commit did not move the archive (R18)" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
# Build 2 fix wave 2 (REQ-384, REQ-324; PR #54 verifier run 1, finding 1): checkout's fetch-depth: 0 brings tags, and git
# resolves a short name's refs/tags/<name> before refs/remotes/<name>. A tag literally named origin/main, on a commit
# whose .specflow.yml makes the base an instance of another stack, must not change what the gate reads when it is given
# ci.yml's base ref (refs/remotes/origin/<base>); the short origin/main, a local run's default, is shadowed by it — the
# residual dfe-14 records (a developer's own run only).
# Covers: REQ-384
# Covers: REQ-324
(cd "$R" && git checkout -q -b decoy refs/remotes/origin/main && printf 'stack: python\n' > .specflow.yml && git add .specflow.yml \
  && git commit -qm "a decoy base (REQ-384)" -- .specflow.yml && git tag origin/main && git checkout -q ship/1.0.0 && git branch -q -D decoy)
VRB_BASE="$CIB" vrb
ck "a tag named origin/main (its commit: an instance, stack python): given ci.yml's base ref ($CIB) the gate reads the branch — PASS" \
  bash -c '[ "$1" = refs/remotes/origin/main ] && [ "$2" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$3"' _ "$CIB" "$rc" "$out"
VRB_BASE=origin/main vrb
ck "…the short origin/main is shadowed by that tag (a local run's residual): the stack is read at the tag — FAIL, release-python.sh" \
  bash -c '[ "$1" = 1 ] && grep -qF "release-python.sh" <<<"$2"' _ "$rc" "$out"
# PR #54 verifier run 2, code-mode low (REQ-324; dfe-14): with no base given at all — a non-PR CI event passes an empty
# SPECFLOW_BASE_REF, and a local run may pass none — the gate defaults to refs/remotes/origin/main when that ref exists,
# so the tag above cannot shadow the default either; the short origin/main is the fallback only with no such ref.
# Covers: REQ-324
rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH -u SPECFLOW_HEAD_SHA -u GITHUB_ACTIONS -u SPECFLOW_RELEASE_BUILD \
  PYTHONDONTWRITEBYTECODE=1 SPECFLOW_QG_RUNNING=1 SPECFLOW_BASE_REF= bash scripts/verify-release.sh 2>&1) || rc=$?
ck "…with SPECFLOW_BASE_REF empty (a non-PR event) the default is refs/remotes/origin/main, not the tag-shadowed short name — PASS" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
git -C "$R" tag -d origin/main >/dev/null
(cd "$R" && echo python > .stack); vrb; rm -f "$R/.stack"
ck "…an instance marker the head adds (.stack, here uncommitted) does not swap the release stack: read at the base (P6 R2)" [ "$rc" = 0 ]
SPECFLOW_HEAD_SHA=$(printf 'f%.0s' $(seq 40)) vrb
ck "…an inherited SPECFLOW_HEAD_SHA (in CI, the factory PR's head, absent here) never reaches the scratch repository: vrb unsets it" [ "$rc" = 0 ]
(cd "$R" && echo x > scripts/zz-uncommitted.sh); vrb; rm -f "$R/scripts/zz-uncommitted.sh"
ck "…the CI path never reads the working tree: an uncommitted file under scripts/ changes nothing" [ "$rc" = 0 ]
H=$(git -C "$R" rev-parse HEAD); (cd "$R" && git checkout -q -b merge-ref && echo "# main moved" >> scripts/next.sh && git commit -qm "main moved since the ship branch was cut" -- scripts/next.sh)
vrb; ck "…on GitHub's merge ref (HEAD's tree is not the head's) the build without SPECFLOW_HEAD_SHA differs: FAIL" [ "$rc" = 1 ]
VRB_HEAD_SHA="$H" vrb
ck "…with SPECFLOW_HEAD_SHA set explicitly to the PR head, its tree is built — the tree release-build uploads — and the transcribed row passes (F7)" [ "$rc" = 0 ]
(cd "$R" && git checkout -q ship/1.0.0)
# The reproducibility rule: the hook builds the same archive twice, and again after a docs-only commit in a scratch clone.
arch() { (cd "$R" && rm -rf "$W/d$1" && RELEASE_COMMIT="${2:-HEAD}" VERSION=1.0.0 DIST_DIR="$W/d$1" RELEASE_PARTS=reproducible SOURCE_DATE_EPOCH=1791158400 \
  bash scripts/release-template.sh >/dev/null && python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$W/d$1/specflow-factory-1.0.0-source.tar"); }
S1=$(arch a); S2=$(arch b)
(cd "$R" && echo "more notes" >> docs/releases/1.0.0-migration.md && git commit -qm "docs-only (REQ-384)" -- docs/releases/1.0.0-migration.md)
S3=$(arch c)
ck "the reproducible archive: identical sha256 built twice, and again after a docs-only commit (R18)" \
  bash -c '[ -n "$1" ] && [ "$1" = "$2" ] && [ "$1" = "$3" ]' _ "$S1" "$S2" "$S3"
# Build 2 final review, critical (REQ-324, REQ-384; art-release-readiness; P6 R26): in CI — SPECFLOW_HEAD_SHA set, or
# GITHUB_ACTIONS — the gate never reads dist/: a ship PR's forced dist/, or one PR-head code wrote into the checkout
# before the gate ran, would let the author choose the manifest the notes are compared with. CI always builds the PR
# head's tree. Locally (neither set) dist/manifest.json, CI's downloaded artifact under /release, is still compared.
mkrepo
(cd "$R" && { printf -- '---\nversion: 1.0.0\ndate: 2026-10-05\n---\n'; cat docs/releases/1.0.0-notes.md; } > n && mv n docs/releases/1.0.0-notes.md && git commit -qm "notes date" -- docs/releases/1.0.0-notes.md)
mkdir -p "$R/dist"; printf x > "$R/dist/x-1.0.0.tar.gz"
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$R/dist/manifest.json"
vrb; ck "a forged dist/ whose manifest matches forged notes rows: locally (no SPECFLOW_HEAD_SHA, no GITHUB_ACTIONS) dist/ is the record — PASS" [ "$rc" = 0 ]
VRB_HEAD_SHA=$(git -C "$R" rev-parse HEAD) vrb
ck "…in CI (SPECFLOW_HEAD_SHA set) dist/ is ignored and the head's tree is built: FAIL, then the expected rows" \
  bash -c '[ "$1" = 1 ] && grep -qF "expected Artifacts rows" <<<"$2" && grep -qF "specflow-factory-1.0.0-source.tar" <<<"$2"' _ "$rc" "$out"
VRB_GHA=true vrb
ck "…in CI (GITHUB_ACTIONS=true, no SPECFLOW_HEAD_SHA) dist/ is ignored too: FAIL" bash -c '[ "$1" = 1 ] && grep -qF "expected Artifacts rows" <<<"$2"' _ "$rc" "$out"
# Build 2 fix wave 2 (REQ-324, REQ-384; PR #54 verifier run 1, finding 4): SPECFLOW_RELEASE_BUILD=0 is a local-only
# switch. In CI PR-head code that runs before the gate (an earlier gates step) can write it into $GITHUB_ENV, so the gate
# ignores it there and always builds and compares; outside CI it still leaves the shape-only check (vr above).
# Covers: REQ-324
# Covers: REQ-384
VRB_GHA=true VRB_RB=0 vrb
ck "…in CI (GITHUB_ACTIONS=true) with SPECFLOW_RELEASE_BUILD=0 exported: ignored — still built and compared, FAIL with the expected rows" \
  bash -c '[ "$1" = 1 ] && grep -qF "expected Artifacts rows" <<<"$2"' _ "$rc" "$out"
VRB_HEAD_SHA=$(git -C "$R" rev-parse HEAD) VRB_RB=0 vrb
ck "…in CI (SPECFLOW_HEAD_SHA set) with SPECFLOW_RELEASE_BUILD=0: ignored too — FAIL with the expected rows" \
  bash -c '[ "$1" = 1 ] && grep -qF "expected Artifacts rows" <<<"$2"' _ "$rc" "$out"
(cd "$R" && git add -f dist && git commit -qm "a committed dist/ (REQ-324)" -- dist); vrb
ck "a committed dist/ FAILs wherever the gate runs, naming it (dist/ is gitignored, never the record)" \
  bash -c '[ "$1" = 1 ] && grep -qF "dist/ is tracked" <<<"$2"' _ "$rc" "$out"
fi

# P6 Task 2.5 (REQ-384; F11): the notes link to the Release that release.yml will create.
# Covers: REQ-384
mkrepo; (cd "$R" && sed -i.bak '/^Release: /d' docs/releases/1.0.0-notes.md && rm docs/releases/1.0.0-notes.md.bak && git commit -qam "no link"); vr
ck "notes without the Release link line FAIL, naming it" bash -c '[ "$1" = 1 ] && grep -qF "releases/tag/v1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; vr; ck "…with it (mkrepo's notes carry it): passes" [ "$rc" = 0 ]
# Fix wave 1 (REQ-324, REQ-384): the link must name THIS repository — owner/repo from remote.origin.url, the path part
# only (https, ssh://, and scp-like ssh with a github.com-<alias> host alias alike) — else a FAIL naming the expected
# prefix; with no origin URL, or a local one, the check WARNs that it is local-only.
# Covers: REQ-384
# Covers: REQ-324
mkrepo; (cd "$R" && sed -i.bak 's|^Release: https://github.com/o/r/|Release: https://github.com/other/repo/|' docs/releases/1.0.0-notes.md \
  && rm docs/releases/1.0.0-notes.md.bak && git commit -qam "another repository's link"); vr
ck "a Release link naming another repository FAILs, naming the expected prefix from origin" \
  bash -c '[ "$1" = 1 ] && grep -qF "https://github.com/o/r/releases/tag/v1.0.0" <<<"$(grep "^FAIL" <<<"$2")"' _ "$rc" "$out"
for u in git@github.com-appsconsultants:o/r.git ssh://git@github.com/o/r https://github.com/O/R; do
  mkrepo; git -C "$R" remote set-url origin "$u"; git -C "$R" config url."$R.git".insteadOf "$u"; vr
  ck "origin $u: the path part o/r is matched (host alias and case ignored) — passes, no WARN about the link" \
    bash -c '[ "$1" = 0 ] && ! grep -q "^WARN.*Release link" <<<"$2"' _ "$rc" "$out"
done
mkrepo; git -C "$R" config --unset remote.origin.url; vr
ck "no origin URL: the Release link's repository is not checked — a WARN that says so (local-only), not a FAIL" \
  bash -c '[ "$1" = 0 ] && grep -q "^WARN verify-release 1.0.0: .*Release link.*local-only" <<<"$2"' _ "$rc" "$out"
mkrepo; git -C "$R" remote set-url origin "$R.git"; vr
ck "a local-path origin: the same WARN (local-only), not a FAIL" bash -c '[ "$1" = 0 ] && grep -q "^WARN verify-release 1.0.0: .*Release link.*local-only" <<<"$2"' _ "$rc" "$out"
# Fix wave 1 (REQ-324, REQ-384): an explicit --manifest PATH that does not exist is a FAIL naming the path — never a
# fall-through to the build or to the shape-only check (measured: SPECFLOW_RELEASE_BUILD=0 gave no FAIL).
# Covers: REQ-324
mkrepo; vr --manifest "$W/nonexistent/m.json"
ck "verify-release.sh --manifest <missing path>: FAIL naming the path" \
  bash -c '[ "$1" = 1 ] && grep -qF "$3" <<<"$(grep "^FAIL" <<<"$2")"' _ "$rc" "$out" "$W/nonexistent/m.json"
# P6 Task 3.2 (REQ-350, REQ-324, REQ-383; P6 R27, R30): --at-tag — release.yml's replay — needs v<version> on HEAD,
# verified (SSH by an anchored key, or annotated with the fallback recorded by _fallback_recorded's rule: at the tag, or
# on origin/main as it stood when the tag was created), replays the disposition gate with --at-tag, and never re-runs
# the gates. --artifacts-only — build-source's comparison — needs neither history nor the tag.
# Covers: REQ-350
FB1='- Annotated-tag fallback: `v1.0.0` is annotated, not signed (neither a GPG nor an SSH signing key at tag time); follow-up: re-tag it signed once a key is configured.'
mkrepo; (cd "$R" && printf '%s\n' "$FB1" >> docs/releases/1.0.0-known-limitations.md && git commit -qam fallback && git tag -a -m r v1.0.0)
rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_RELEASE_BUILD=0 SPECFLOW_BASE_REF=origin/main bash scripts/verify-release.sh --version 1.0.0 --at-tag 2>&1) || rc=$?
ck "--at-tag: an annotated v1.0.0 on HEAD with the fallback at the tag passes, and the gates are not re-run" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2" && ! grep -qF "=== Summary ===" <<<"$2"' _ "$rc" "$out"
# Fix wave 1, G (REQ-324, REQ-350): the documents are read from the checkout, which must be the tag's tree — an untracked
# file (here tester instructions the tag does not carry) is a FAIL naming the working tree, never read as the tag's.
# Covers: REQ-324
printf '# Opening an unsigned app\n' > "$R/docs/releases/1.0.0-tester-instructions.md"; vr --version 1.0.0 --at-tag; rm -f "$R/docs/releases/1.0.0-tester-instructions.md"
ck "--at-tag with an untracked file in the checkout: FAIL — the working tree is not v1.0.0's tree (git status --porcelain)" \
  bash -c '[ "$1" != 0 ] && grep -q "^FAIL verify-release 1.0.0: .*working tree" <<<"$2"' _ "$rc" "$out"
(cd "$R" && git commit -q --allow-empty -m later); vr --version 1.0.0 --at-tag
ck "--at-tag: v1.0.0 not on HEAD — FAIL" bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v1.0.0 does not peel to HEAD" <<<"$2"' _ "$rc" "$out"
# One repository for the absent-tag, the unsigned and the signature cases (the gates' 3-minute budget, final review
# finding 1): no v1.0.0, then an annotated v1.0.0 without the fallback, then the signed ones below.
mkrepo; vr --version 1.0.0 --at-tag
ck "--at-tag with no v1.0.0: FAIL — the replay runs only at a tag" bash -c '[ "$1" = 1 ] && grep -q "v1.0.0 does not exist" <<<"$2"' _ "$rc" "$out"
# The signing anchor (trust on first use): .github/allowed_signers on main lists k1 for t@example.com, below the tag.
# Fix wave 1, finding 2: these cases need an ssh-keygen that signs, as the demo re-tag fixtures do — without one they
# SKIP visibly instead of aborting the whole test.
if dk_ssh; then
  ssh-keygen -q -t ed25519 -N '' -C k1 -f "$W/k1"; ssh-keygen -q -t ed25519 -N '' -C k2 -f "$W/k2"
  (cd "$R" && git checkout -q main && mkdir -p .github && printf 't@example.com %s\n' "$(cat "$W/k1.pub")" > .github/allowed_signers \
    && git add -A && git commit -qm "the signing anchor" && git push -q origin main && git checkout -q ship/1.0.0 && git rebase -q main)
  (cd "$R" && git tag -a -m r v1.0.0); vr --version 1.0.0 --at-tag
  ck "--at-tag: an annotated v1.0.0 without the fallback at the tag — FAIL" bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v1.0.0.*unsigned" <<<"$2"' _ "$rc" "$out"
  # Build 3 final review, finding 9 (REQ-383, REQ-350; P6 R27): the release tag's own signature at the tag, through
  # check_tag_at_head — an SSH signature by the anchored key with the tagger as its principal passes; an unlisted key, a
  # tagger the key is not listed for, and any GPG signature (R27: SSH only) FAIL. Throwaway ssh-keygen keys; the signing
  # configuration is given on the command line only.
  # Covers: REQ-383
  sg() { git -C "$R" tag -d v1.0.0 >/dev/null 2>&1 || true
    (cd "$R" && GIT_COMMITTER_EMAIL="$2" git -c gpg.format=ssh -c user.signingKey="$W/$1" tag -s -m r v1.0.0); }
  sg k1 t@example.com; vr --version 1.0.0 --at-tag
  ck "--at-tag: v1.0.0 SSH-signed by k1, listed for its tagger t@example.com at the anchor: PASS" \
    bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
  sg k2 t@example.com; vr --version 1.0.0 --at-tag
  ck "--at-tag: signed by k2, which the anchor does not list: FAIL unlisted" \
    bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: v1.0.0: its signature does not verify (unlisted" <<<"$2"' _ "$rc" "$out"
  sg k1 other@example.com; vr --version 1.0.0 --at-tag
  ck "--at-tag: signed by k1 with tagger other@example.com (k1 is listed for t@example.com): FAIL tagger-mismatch" \
    bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: v1.0.0: its signature does not verify (tagger-mismatch" <<<"$2"' _ "$rc" "$out"
  git -C "$R" tag -d v1.0.0 >/dev/null
  printf 'object %s\ntype commit\ntag v1.0.0\ntagger T <t@example.com> 1791200000 +0000\n\nr\n-----BEGIN PGP SIGNATURE-----\n\nwsBcBAABCAAQBQJnAAAACRAAAAAAAAAAAA\n=AAAA\n-----END PGP SIGNATURE-----\n' \
    "$(git -C "$R" rev-parse HEAD)" | git -C "$R" mktag > "$W/pgptag"; git -C "$R" update-ref refs/tags/v1.0.0 "$(cat "$W/pgptag")"
  printf '#!/bin/sh\necho "gpg: Can'"'"'t check signature: No public key" >&2\nexit 2\n' > "$W/stubgpg"; chmod +x "$W/stubgpg"
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gpg.program GIT_CONFIG_VALUE_0="$W/stubgpg" vr --version 1.0.0 --at-tag
  ck "--at-tag: a GPG-signed v1.0.0 (a stub gpg that cannot check it): FAIL with R27's message — the replay takes SSH signatures only" \
    bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: v1.0.0 carries a GPG signature (gpg-unverifiable)" <<<"$2"' _ "$rc" "$out"
else
  echo "SKIP: no ssh-keygen that signs (-Y sign) on PATH — the --at-tag signing-anchor, SSH-signature and GPG cases did not run"
fi
# The dates are OFFSETS in seconds from the seed commit M's committer time, never literal epochs: the gate picks the
# newest commit on origin/main touching the file whose committer time is not after the tagger time, and M itself
# touches it at test time, so a literal fallback date went stale once the clock passed it (2026-10-04T07:46Z: the
# fixture's 1791100000 fell behind M's "now" and M, without the fallback, became the newest; main's gates went red).
fu() {  # fu FALLBACK-OFFSET — release.md's stop path: the ship PR merged as M; a follow-up docs PR records the
  # fallback on origin/main (committed at M's time + OFFSET seconds); HEAD detached at M; tag with tg TAGGER-OFFSET
  mkrepo; M=$(git -C "$R" rev-parse HEAD); T0=$(git -C "$R" log -1 --format=%ct "$M")
  (cd "$R" && git checkout -q -b fu && printf '%s\n' "$FB1" >> docs/releases/1.0.0-known-limitations.md \
    && GIT_COMMITTER_DATE="@$((T0 + $1)) +0000" git commit -qam "follow-up docs PR: the fallback" && git push -q origin fu:main && git checkout -q --detach "$M")
}
tg() { git -C "$R" tag -d v1.0.0 >/dev/null 2>&1 || true; (cd "$R" && GIT_COMMITTER_DATE="@$((T0 + $1)) +0000" git tag -a -m r v1.0.0 "$M"); }
fu 1000; tg 2000; vr --version 1.0.0 --at-tag
ck "--at-tag: the fallback merged to origin/main before the tag was created, the tag on the earlier M (the stop path): PASS (F6, F18)" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS verify-release 1.0.0" <<<"$2"' _ "$rc" "$out"
tg 500; vr --version 1.0.0 --at-tag
ck "…a fallback committed to origin/main after the tag was created records nothing: FAIL" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL verify-release 1.0.0: .*v1.0.0.*unsigned" <<<"$2"' _ "$rc" "$out"
mkrepo; git clone -q --depth 1 --branch ship/1.0.0 "file://$R" "$W/shallow$n"
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 1}]}\n' "$SHA" > "$W/am$n.json"
rc=0; out=$(cd "$W/shallow$n" && python3 scripts/lib/specflow/release_gate.py --version 1.0.0 --manifest "$W/am$n.json" --artifacts-only 2>&1) || rc=$?
ck "--artifacts-only in a depth-1 clone with no v1.0.0: the rows equal the manifest — PASS, no tag, history or disposition check (F19, F28)" \
  bash -c '[ "$1" = 0 ] && ! grep -qiE "tag|disposition" <<<"$(grep -E "^(FAIL|WARN)" <<<"$2")"' _ "$rc" "$out"
printf '{"version": "1.0.0", "artifacts": [{"filename": "x-1.0.0.tar.gz", "sha256": "%s", "size": 2}]}\n' "$SHA" > "$W/am$n.json"
rc=0; out=$(cd "$W/shallow$n" && python3 scripts/lib/specflow/release_gate.py --version 1.0.0 --manifest "$W/am$n.json" --artifacts-only 2>&1) || rc=$?
ck "…a row that differs from the manifest: FAIL with the expected rows" bash -c '[ "$1" = 1 ] && grep -qF "expected Artifacts rows" <<<"$2"' _ "$rc" "$out"
# P6 Task 3.2 (REQ-352, REQ-386; P6 R22, R23, R35): an app-stack ship PR's notes carry the store checklist (release.yml
# cannot edit a tagged file) and, with signing: none, its tester instructions exist; the stack is the governing pack's,
# read at the base as instance-ness is. Template source only: it copies stacks/tauri/pack.yml, and init removes stacks/.
# Covers: REQ-352
# Covers: REQ-386
if instance; then echo "SKIP: the tauri pack lives in the template source (init removes stacks/)"; else
mkrepo; (cd "$R" && git checkout -q main && printf 'profile: engineer\npath: lanes\nstack: tauri\nsolo: true\nsigning: none\n' > .specflow.yml \
  && mkdir -p .specflow && cp "$ROOT/stacks/tauri/pack.yml" .specflow/pack.yml && git add -A && git commit -qm "a tauri instance" \
  && git push -q origin main && git checkout -q ship/1.0.0 && git rebase -q main); vr
ck "a tauri ship PR whose notes lack '## macOS distribution checklist' FAILs, naming the heading" \
  bash -c '[ "$1" = 1 ] && grep -qF "## macOS distribution checklist" <<<"$2"' _ "$rc" "$out"
ck "…and, with signing: none and no docs/releases/1.0.0-tester-instructions.md, FAILs naming that file" grep -qF '1.0.0-tester-instructions.md' <<<"$out"
(cd "$R" && printf '\n## macOS distribution checklist\n\n1. ...\n' >> docs/releases/1.0.0-notes.md \
  && printf '# Opening an unsigned app\n\nOpen Anyway\n' > docs/releases/1.0.0-tester-instructions.md && git add -A && git commit -qm "checklist and tester instructions"); vr
ck "…with the checklist appended and the tester instructions committed: neither FAIL" \
  bash -c '! grep -E "^FAIL" <<<"$1" | grep -qE "macOS distribution checklist|tester-instructions"' _ "$out"
# Fix wave 1, G (REQ-352, REQ-350): at the tag, the app-stack rules read the stack at the TAG's tree (packinfo at
# refs/tags/v<v>), as release.yml's job selection does — a ship PR that makes the tree a tauri instance is held to them.
mkrepo; (cd "$R" && printf 'profile: engineer\npath: lanes\nstack: tauri\nsolo: true\nsigning: none\n' > .specflow.yml \
  && mkdir -p .specflow && cp "$ROOT/stacks/tauri/pack.yml" .specflow/pack.yml && printf '%s\n' "$FB1" >> docs/releases/1.0.0-known-limitations.md \
  && git add -A && git commit -qm "the ship PR makes it a tauri instance" && git tag -a -m r v1.0.0); vr --version 1.0.0 --at-tag
ck "--at-tag: the stack is read at the tag's tree (tauri there, the template at its parent): the checklist FAIL is raised" \
  bash -c '[ "$1" = 1 ] && grep -qF "## macOS distribution checklist" <<<"$2"' _ "$rc" "$out"
mkrepo; vr
ck "a template-source ship PR (stack template) is asked for neither the checklist nor tester instructions" \
  bash -c '[ "$1" = 0 ] && ! grep -qF "macOS distribution checklist" <<<"$2" && ! grep -qF "tester-instructions" <<<"$2"' _ "$rc" "$out"
fi
finish test_verify_release
