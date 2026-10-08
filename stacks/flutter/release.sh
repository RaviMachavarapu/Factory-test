#!/usr/bin/env bash
# flutter stack pack — RELEASE hook (REQ-305). Implements the
# scripts/release-stack.sh.template contract for a flutter-stack instance.
#
# Contract (see scripts/release-stack.sh.template):
#   Inputs (env): VERSION, DIST_DIR
#   Optional: RELEASE_PARTS (all | reproducible | bundle), RELEASE_COMMIT,
#             SOURCE_DATE_EPOCH (P6 R18).
#   Outputs: reproducible = <name>-<version>-source.tar (the committed tree,
#            no toolchain needed); bundle = one zipped .app (reproducible
#            false, signed false until release.yml's sign job), built in the
#            checkout; plus $DIST_DIR/manifest.json (schema 2).
#   Constraints: no outbound network calls — flutter build runs --no-pub
#   (the gates already ran `flutter pub get --enforce-lockfile`).
set -euo pipefail

: "${VERSION:?VERSION env var required}"
: "${DIST_DIR:?DIST_DIR env var required}"

read -r PUBSPEC_NAME PUBSPEC_BASE_VERSION <<<"$(python3 -c '
import re
text = open("pubspec.yaml").read()
name = re.search(r"(?m)^name: *(.+)$", text).group(1).strip()
version = re.search(r"(?m)^version: *(.+)$", text).group(1).strip()
print(name, version.split("+", 1)[0])
')"
NAME="$PUBSPEC_NAME"
STACK=flutter

if [[ "$VERSION" != "$PUBSPEC_BASE_VERSION" ]]; then
  echo "release.sh: VERSION=$VERSION does not match pubspec.yaml .version=$PUBSPEC_BASE_VERSION" >&2
  exit 1
fi

PARTS="${RELEASE_PARTS:-all}"
COMMIT="${RELEASE_COMMIT:-HEAD}"
case "$PARTS" in all | reproducible | bundle) ;; *) echo "release.sh: RELEASE_PARTS must be all, reproducible or bundle" >&2; exit 2 ;; esac

# The bundle part alone needs neither git nor the notes: it builds in the checkout and records what it can (the source
# part's manifest supplies the epoch and tree in release.yml's assembled Release).
TOP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$TOP/scripts/lib/specflow"
# The factory's library: the checkout's, else the one beside this hook (scripts/ in an instance, the template's
# scripts/ from stacks/<stack>/) — a bundle-only run in a bare checkout still writes its manifest through it.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for cand in "$LIB" "$HERE/lib/specflow" "$HERE/../../scripts/lib/specflow"; do
  if [ -f "$cand/release_manifest.py" ]; then LIB="$cand"; break; fi
done
EPOCH="${SOURCE_DATE_EPOCH:-}"
TREE=""
if [ "$PARTS" != bundle ]; then
  if ! git rev-parse -q --verify "$COMMIT^{commit}" >/dev/null; then
    echo "RELEASE_COMMIT $COMMIT is not a commit in this repository (SPECFLOW_HEAD_SHA set wrongly?)" >&2
    exit 2
  fi
  # The epoch is 00:00:00 UTC of the notes' date: (R18 iii), or SOURCE_DATE_EPOCH for a dry run.
  if [ -z "$EPOCH" ]; then
    NOTES_TMP="$(mktemp)"
    trap 'rm -f "$NOTES_TMP"' EXIT
    if ! git show "$COMMIT:docs/releases/$VERSION-notes.md" > "$NOTES_TMP" 2>/dev/null; then
      echo "no docs/releases/$VERSION-notes.md: run /release first, or set SOURCE_DATE_EPOCH" >&2
      exit 2
    fi
    EPOCH="$(python3 -I "$LIB/release_manifest.py" epoch --notes "$NOTES_TMP")" || exit 2
  fi
  TREE="$(git rev-parse "$COMMIT^{tree}")"
fi
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/manifest.json"
ENTRIES=()

# Reproducible part: the source archive of the committed tree (R18), exactly as scripts/release-template.sh writes it.
if [ "$PARTS" != bundle ]; then
  SRC="$NAME-$VERSION-source.tar"
  rm -f "$DIST_DIR/$SRC"
  git -c tar.umask=0022 -c core.autocrlf=false archive --format=tar --prefix="$NAME-$VERSION/" --mtime="@$EPOCH" \
    "$TREE" -- . ':(exclude)docs/releases' ':(exclude)docs/security' > "$DIST_DIR/$SRC"
  ENTRIES+=("$SRC:source-archive:1")
fi

# Bundle part: built in the checkout, never reproducible.
if [ "$PARTS" != reproducible ]; then
  RELEASE_DIR="build/macos/Build/Products/Release"
  rm -rf "$RELEASE_DIR"

  # --no-pub keeps this release hook off the network entirely; the gates have
  # already run `flutter pub get --enforce-lockfile`.
  flutter build macos --release --no-pub

  shopt -s nullglob
  apps=("$RELEASE_DIR"/*.app)
  shopt -u nullglob
  if [[ ${#apps[@]} -ne 1 ]]; then
    echo "release.sh: expected exactly one .app in $RELEASE_DIR, found ${#apps[@]}: ${apps[*]}" >&2
    exit 1
  fi
  APP="${apps[0]}"

  ZIP_DIR="$(mktemp -d)"
  ZIP_NAME="${PUBSPEC_NAME}-${VERSION}-macos-arm64.zip"
  ZIP_PATH="$ZIP_DIR/$ZIP_NAME"

  # ditto keeps code-signing metadata and extended attributes, unlike zip(1).
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"
  cp "$ZIP_PATH" "$DIST_DIR/"
  rm -rf "$ZIP_DIR"
  ENTRIES+=("$ZIP_NAME:bundle:0")
fi

# The manifest, through release_manifest.py write (schema 2; the bundle part alone has no epoch or tree: null).
set --
if [ -n "$EPOCH" ] && [ -n "$TREE" ]; then set -- --epoch "$EPOCH" --tree "$TREE"; fi
for e in "${ENTRIES[@]}"; do  # NAME:KIND:REPRO, split from the right as the name may hold a colon
  rest="${e%:*}"
  set -- "$@" --artifact "${rest%:*}" "${rest##*:}" "${e##*:}"
done
python3 -I "$LIB/release_manifest.py" write --dist "$DIST_DIR" --version "$VERSION" --stack "$STACK" "$@"
