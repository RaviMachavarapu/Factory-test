#!/usr/bin/env bash
# REQ-350, REQ-384 (P6 R15, R31, R34, R35): publish the GitHub Release for a tag, from the parts release.yml's jobs
# uploaded. Usage: release-publish.sh --version <X.Y.Z> --tag <vX.Y.Z> --commit <40-hex> --tag-object <40-hex>
#   --parts <dir> --notes <path> [--anchor <ref>] --tag-kind <ssh-good|unsigned>
#
#   --tag-kind is the tag's own verdict (release.yml's verify job, signers.py verify): the body's 'Verify this release'
#   follows it — the verify-tag command at the anchor only for ssh-good, the annotated-tag text for unsigned whether or
#   not an anchor exists (wave 1 round 2); a missing or other value is usage (exit 2), before any gh call.
#   1. the remote tags are read again (git ls-remote --tags): the tag must still be --tag-object, the tag object verify
#      verified, and peel to --commit, verify's commit — a tag that moved, or was replaced by another tag object on the
#      same commit, publishes nothing (exit 1, before any gh call); the same listing decides --latest: true only when
#      v<version> is the highest vX.Y.Z tag on the remote (a fix release of an older line never becomes "latest");
#   2. the parts are picked by directory name: source/manifest.json always; bundle-signed/ when it exists, else
#      bundle-unsigned/ (never both: the signed part wins); image/image.json is the image record, never a manifest.
#      The chosen directory's provenance decides `signed`, never the part's own manifest (Build 5 fix wave 1, A):
#      bundle-unsigned/ is written by the bundle job after third-party build code ran (npm lifecycle scripts, build.rs,
#      pub hooks), so assemble gets --unsigned-bundle and the Release says signed: false whatever that manifest claims;
#      bundle-signed/ exists only when release.yml's verify-signed succeeded (publish downloads it on that job's
#      success alone: the attestation release.yml has — verify-signed writes no artifact of its own), and its bundle
#      entry must say signed: true, else nothing is published (exit 1, before any gh call);
#   3. <parts>/manifest.json is assembled (release_manifest.py assemble) — an unsigned bundle with no
#      docs/releases/<v>-tester-instructions.md is refused (exit 1, REQ-386) — and the body written from the tagged notes;
#   4. no Release: a draft with no asset, every asset uploaded to it, then published. A draft an earlier run left: its
#      assets uploaded and the body replaced, then published. A published Release (a re-run): its assets replaced in
#      place and its body edited, never deleted, re-created or turned back into a draft (its URL stays). On a re-run,
#      after the upload, every asset the Release holds that the current set does not name is deleted (gh release
#      delete-asset, each logged), so the Release's assets are always what its manifest.json lists.
# Exit 0 published; 1 a refusal or a gh failure (a failure before the publication leaves a draft no consumer sees);
# 2 usage or bad input. bash 3.2 compatible; stdlib python3 only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RM="$HERE/lib/specflow/release_manifest.py"

usage() {
  echo "usage: release-publish.sh --version <X.Y.Z> --tag <vX.Y.Z> --commit <sha> --tag-object <sha> --parts <dir> --notes <path> [--anchor <ref>] --tag-kind <ssh-good|unsigned>" >&2
  exit 2
}

VERSION=""; TAG=""; COMMIT=""; TAGOBJ=""; PARTS=""; NOTES=""; ANCHOR=""; TAGKIND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || usage; VERSION="$2"; shift 2 ;;
    --tag) [ $# -ge 2 ] || usage; TAG="$2"; shift 2 ;;
    --commit) [ $# -ge 2 ] || usage; COMMIT="$2"; shift 2 ;;
    --tag-object) [ $# -ge 2 ] || usage; TAGOBJ="$2"; shift 2 ;;
    --parts) [ $# -ge 2 ] || usage; PARTS="$2"; shift 2 ;;
    --notes) [ $# -ge 2 ] || usage; NOTES="$2"; shift 2 ;;
    --anchor) [ $# -ge 2 ] || usage; ANCHOR="$2"; shift 2 ;;
    --tag-kind) [ $# -ge 2 ] || usage; TAGKIND="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$VERSION" ] && [ -n "$TAG" ] && [ -n "$COMMIT" ] && [ -n "$TAGOBJ" ] && [ -n "$PARTS" ] && [ -n "$NOTES" ] || usage
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$TAG" != "v$VERSION" ]; then
  echo "release-publish: --tag must be v<--version> with --version X.Y.Z (got version=$VERSION tag=$TAG)" >&2
  exit 2
fi
if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || ! [[ "$TAGOBJ" =~ ^[0-9a-f]{40}$ ]]; then
  echo "release-publish: --commit and --tag-object must be 40 lowercase hex characters" >&2
  exit 2
fi
case "$TAGKIND" in
  ssh-good|unsigned) ;;
  *) echo "release-publish: --tag-kind must be ssh-good or unsigned, the tag's own verdict (got '${TAGKIND}')" >&2; exit 2 ;;
esac
if [ "$TAGKIND" = ssh-good ] && { [ -z "$ANCHOR" ] || [ "$ANCHOR" = - ]; }; then
  echo "release-publish: an ssh-good tag is verified against an anchor, but --anchor names none" >&2
  exit 2
fi
[ -d "$PARTS" ] || { echo "release-publish: --parts $PARTS is not a directory" >&2; exit 2; }
[ -f "$NOTES" ] || { echo "release-publish: --notes $NOTES is not a file" >&2; exit 2; }

# (1) The remote tag, read again. The token, when there is one, is given to this git process through the environment
# only (the checkout kept no credential), never written to a config file.
if [ -n "${GH_TOKEN:-}" ]; then
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
  GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
  export GIT_CONFIG_VALUE_0
fi
if ! TAGS="$(git ls-remote --tags origin)"; then
  echo "release-publish: git ls-remote --tags origin failed: the tag cannot be re-read; nothing is published" >&2
  exit 1
fi
obj="$(printf '%s\n' "$TAGS" | awk -v r="refs/tags/$TAG" '$2 == r {print $1; exit}')"
peeled="$(printf '%s\n' "$TAGS" | awk -v r="refs/tags/$TAG^{}" '$2 == r {print $1; exit}')"
if [ "$obj" != "$TAGOBJ" ]; then
  echo "release-publish: the remote tag $TAG is the tag object ${obj:-nothing}, not $TAGOBJ (the one verify verified): the tag was moved or replaced; nothing is published" >&2
  exit 1
fi
if [ "$peeled" != "$COMMIT" ]; then
  echo "release-publish: the remote tag $TAG peels to ${peeled:-nothing}, not $COMMIT (verify's commit): the tag moved; nothing is published" >&2
  exit 1
fi
LATEST="$(printf '%s\n' "$TAGS" | python3 -I -c '
import re, sys
want = tuple(int(x) for x in sys.argv[1].split("."))
seen = [tuple(int(x) for x in m.groups()) for l in sys.stdin for m in [re.search(r"\srefs/tags/v(\d+)\.(\d+)\.(\d+)$", l.rstrip("\n"))] if m]
print("true" if seen and want >= max(seen) else "false")' "$VERSION")"

# (2) The parts.
SRC="$PARTS/source"
[ -f "$SRC/manifest.json" ] || { echo "release-publish: $SRC/manifest.json is missing" >&2; exit 2; }
PART_DIRS="$SRC"
BUNDLE=""; PROVENANCE=""
if [ -f "$PARTS/bundle-signed/manifest.json" ]; then
  BUNDLE="$PARTS/bundle-signed"; PROVENANCE=--signed-bundle
  if ! python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1]))
b = [a for a in m.get("artifacts") or [] if isinstance(a, dict) and a.get("kind") == "bundle"]
sys.exit(0 if len(b) == 1 and b[0].get("signed") is True and m.get("signed") is True else 1)' "$BUNDLE/manifest.json" 2>/dev/null; then
    echo "release-publish: $BUNDLE/manifest.json does not hold one bundle entry saying signed: true, though the part exists only after verify-signed succeeded: nothing is published" >&2
    exit 1
  fi
elif [ -f "$PARTS/bundle-unsigned/manifest.json" ]; then
  BUNDLE="$PARTS/bundle-unsigned"; PROVENANCE=--unsigned-bundle
fi
if [ -n "$BUNDLE" ]; then
  PART_DIRS="$PART_DIRS
$BUNDLE"
fi

# (3) The Release's manifest and body.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/specflow-publish.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
set -- --out "$PARTS/manifest.json" --tag "$TAG" --commit "$COMMIT" --run "${GITHUB_RUN_ID:-0}"
if [ -f "$PARTS/image/image.json" ]; then
  set -- "$@" --image-json "$PARTS/image/image.json"
fi
if [ -n "$PROVENANCE" ]; then
  set -- "$@" "$PROVENANCE"
fi
set -- "$@" "$SRC/manifest.json"
if [ -n "$BUNDLE" ]; then
  set -- "$@" "$BUNDLE/manifest.json"
fi
python3 -I "$RM" assemble "$@"

# An unsigned bundle ships only with its tester instructions (REQ-386): the file /release writes under signing: none. With
# signing: apple release.yml's signing-probe already failed when the secrets were missing; this refusal catches any other
# way an unsigned bundle reaches here (Build 3 final review, finding 10) — before any gh call, so nothing is published.
TESTER="docs/releases/$VERSION-tester-instructions.md"
if python3 -I -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])).get("signed") is False else 1)' "$PARTS/manifest.json"; then
  if [ ! -f "$TESTER" ]; then
    echo "release-publish: the bundle is unsigned and $TESTER does not exist at the tag: an unsigned app ships with its tester instructions (REQ-386); nothing is published" >&2
    exit 1
  fi
fi

BODY="$TMP/body.md"
set -- --notes "$NOTES" --manifest "$PARTS/manifest.json" --tag-kind "$TAGKIND"
if [ -n "$ANCHOR" ]; then
  set -- "$@" --anchor "$ANCHOR"
fi
if [ -f "$TESTER" ]; then
  set -- "$@" --tester-instructions "$TESTER"
fi
python3 -I "$RM" body "$@" > "$BODY"

# The assets: every artifact each selected part's manifest lists, from that part's directory, then manifest.json.
FILES="$(PART_DIRS="$PART_DIRS" python3 -I - "$PARTS" <<'PY'
import json, os, sys
parts, dirs = sys.argv[1], os.environ["PART_DIRS"].splitlines()
for d in dirs:
    with open(os.path.join(d, "manifest.json"), encoding="utf-8") as f:
        for a in json.load(f)["artifacts"]:
            print(os.path.join(d, a["filename"]))
print(os.path.join(parts, "manifest.json"))
PY
)"
set --
while IFS= read -r f; do
  if [ -n "$f" ]; then
    [ -f "$f" ] || { echo "release-publish: $f is listed by a manifest and missing" >&2; exit 1; }
    set -- "$@" "$f"
  fi
done <<EOF
$FILES
EOF

# (4) The Release.
state="absent"
if view="$(gh release view "$TAG" --json tagName,isDraft,assets 2>"$TMP/view.err")"; then
  state="$(printf '%s' "$view" | python3 -I -c 'import json, sys; print("draft" if json.load(sys.stdin).get("isDraft") else "published")')"
else
  if ! grep -qi "release not found" "$TMP/view.err"; then
    cat "$TMP/view.err" >&2
    echo "release-publish: gh release view failed for a reason other than an absent Release" >&2
    exit 1
  fi
fi

# stale_assets — the assets the existing Release holds that this run's set does not name, one per line
stale_assets() {
  printf '%s' "$view" | python3 -I -c '
import json, os, sys
keep = {os.path.basename(a) for a in sys.argv[1:]}
for a in json.load(sys.stdin).get("assets") or []:
    if a.get("name") and a["name"] not in keep:
        print(a["name"])' "$@"
}
prune_stale() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    gh release delete-asset "$TAG" "$name" --yes
    echo "release-publish: deleted the stale asset $name (not in this run's manifest set)"
  done <<EOF
$(stale_assets "$@")
EOF
}

case "$state" in
  absent)
    gh release create "$TAG" --draft --verify-tag --title "$TAG" --notes-file "$BODY"
    gh release upload "$TAG" --clobber "$@"
    gh release edit "$TAG" --draft=false --latest="$LATEST"
    ;;
  draft)
    gh release upload "$TAG" --clobber "$@"
    prune_stale "$@"
    gh release edit "$TAG" --notes-file "$BODY" --draft=false --latest="$LATEST"
    ;;
  published)
    gh release upload "$TAG" --clobber "$@"
    prune_stale "$@"
    gh release edit "$TAG" --notes-file "$BODY" --latest="$LATEST"
    ;;
esac
echo "release-publish: $TAG published ($state)"
