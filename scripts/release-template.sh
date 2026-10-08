#!/usr/bin/env bash
# The template source's own RELEASE hook (REQ-384, P6 R2, R18; REQ-306: init removes this file, an instance never holds it).
# Implements scripts/release-stack.sh.template's contract: one artifact, specflow-factory-<VERSION>-source.tar (kind
# source-archive, reproducible) — the uncompressed git archive of RELEASE_COMMIT's tree (never the working tree) without
# docs/releases and docs/security, every mtime the notes' date: (or SOURCE_DATE_EPOCH) — plus manifest.json (schema 2,
# stack template, signed null). RELEASE_PARTS=bundle: "template: no bundle", nothing written. Exit 2: no notes and no
# SOURCE_DATE_EPOCH, or a RELEASE_COMMIT that is no commit here. No network.
set -euo pipefail

: "${VERSION:?VERSION env var required}"
: "${DIST_DIR:?DIST_DIR env var required}"
PARTS="${RELEASE_PARTS:-all}"
COMMIT="${RELEASE_COMMIT:-HEAD}"
case "$PARTS" in all | reproducible | bundle) ;; *) echo "release: RELEASE_PARTS must be all, reproducible or bundle" >&2; exit 2 ;; esac
if [ "$PARTS" = bundle ]; then echo "template: no bundle"; exit 0; fi

TOP="$(git rev-parse --show-toplevel)"
LIB="$TOP/scripts/lib/specflow"
if ! git rev-parse -q --verify "$COMMIT^{commit}" >/dev/null; then
  echo "RELEASE_COMMIT $COMMIT is not a commit in this repository (SPECFLOW_HEAD_SHA set wrongly?)" >&2
  exit 2
fi
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  EPOCH="$SOURCE_DATE_EPOCH"
else
  NOTES_TMP="$(mktemp)"
  trap 'rm -f "$NOTES_TMP"' EXIT
  if ! git show "$COMMIT:docs/releases/$VERSION-notes.md" > "$NOTES_TMP" 2>/dev/null; then
    echo "no docs/releases/$VERSION-notes.md: run /release first, or set SOURCE_DATE_EPOCH" >&2
    exit 2
  fi
  EPOCH="$(python3 "$LIB/release_manifest.py" epoch --notes "$NOTES_TMP")" || exit 2
fi

NAME="specflow-factory"
TREE="$(git rev-parse "$COMMIT^{tree}")"
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$NAME-$VERSION-source.tar" "$DIST_DIR/manifest.json"
git -c tar.umask=0022 -c core.autocrlf=false archive --format=tar --prefix="$NAME-$VERSION/" --mtime="@$EPOCH" \
  "$TREE" -- . ':(exclude)docs/releases' ':(exclude)docs/security' > "$DIST_DIR/$NAME-$VERSION-source.tar"

python3 - "$LIB" "$DIST_DIR" "$VERSION" "$EPOCH" "$TREE" "$NAME" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import release_manifest as m
lib, dist, version, epoch, tree, name = sys.argv[1:7]
m.write(dist, version, "template", int(epoch), tree, [(f"{name}-{version}-source.tar", "source-archive", True)])
print("Wrote manifest with 1 artifact(s)")
PY
