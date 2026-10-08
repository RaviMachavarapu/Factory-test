#!/usr/bin/env bash
# python stack pack — RELEASE hook (REQ-305, REQ-384; P6 R18, R20). Implements the
# scripts/release-stack.sh.template contract for a python-stack instance.
#
# Contract (see scripts/release-stack.sh.template):
#   Inputs (env): VERSION, DIST_DIR, optional RELEASE_PARTS (all | reproducible |
#            bundle), RELEASE_COMMIT (default HEAD), SOURCE_DATE_EPOCH (else 00:00:00
#            UTC of docs/releases/<VERSION>-notes.md's date: at RELEASE_COMMIT).
#   Outputs: sdist + wheel under $DIST_DIR/, plus $DIST_DIR/manifest.json
#            (schema specflow-manifest/2, stack python, both artifacts reproducible,
#            signed null), written through scripts/lib/specflow/release_manifest.py.
#   Build:   from RELEASE_COMMIT's committed tree (git archive, docs/releases and
#            docs/security excluded) in a temporary directory, never the working
#            tree; SOURCE_DATE_EPOCH exported; the sdist re-packed deterministically.
#   RELEASE_PARTS=bundle: "python: no bundle (the image is release.yml's image job)",
#            nothing written.
#   Exit:    0, or non-zero (2: no notes and no SOURCE_DATE_EPOCH, or a RELEASE_COMMIT
#            that is no commit here; 1: VERSION differs from pyproject.toml).
#   Constraints: no outbound network calls (--no-isolation, offline build).
set -euo pipefail

: "${VERSION:?VERSION env var required}"
: "${DIST_DIR:?DIST_DIR env var required}"
PARTS="${RELEASE_PARTS:-all}"
COMMIT="${RELEASE_COMMIT:-HEAD}"
case "$PARTS" in all | reproducible | bundle) ;; *) echo "release: RELEASE_PARTS must be all, reproducible or bundle" >&2; exit 2 ;; esac
if [ "$PARTS" = bundle ]; then echo "python: no bundle (the image is release.yml's image job)"; exit 0; fi

# release_manifest.py: an instance runs scripts/release-python.sh (the library is scripts/lib/specflow beside it); the
# template source runs stacks/python/release.sh (two levels up, under scripts/).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/lib/specflow/release_manifest.py" ]; then
  LIB="$HERE/lib/specflow"
else
  LIB="$HERE/../../scripts/lib/specflow"
fi
if ! git rev-parse -q --verify "$COMMIT^{commit}" >/dev/null; then
  echo "RELEASE_COMMIT $COMMIT is not a commit in this repository (SPECFLOW_HEAD_SHA set wrongly?)" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  EPOCH="$SOURCE_DATE_EPOCH"
else
  if ! git show "$COMMIT:docs/releases/$VERSION-notes.md" > "$WORK/notes.md" 2>/dev/null; then
    echo "no docs/releases/$VERSION-notes.md: run /release first, or set SOURCE_DATE_EPOCH" >&2
    exit 2
  fi
  EPOCH="$(python3 "$LIB/release_manifest.py" epoch --notes "$WORK/notes.md")" || exit 2
fi
export SOURCE_DATE_EPOCH="$EPOCH"

TREE="$(git rev-parse "$COMMIT^{tree}")"
SRC="$WORK/src"
mkdir -p "$SRC"
git -c tar.umask=0022 -c core.autocrlf=false archive --format=tar --mtime="@$EPOCH" "$TREE" \
  -- . ':(exclude)docs/releases' ':(exclude)docs/security' | tar -xf - -C "$SRC"

# From here on, everything reads the exported tree, never the checkout.
cd "$SRC"
PROJECT_VERSION="$(python3 - <<'PY'
import tomllib
with open("pyproject.toml", "rb") as f:
    data = tomllib.load(f)
print(data["project"]["version"])
PY
)"
if [[ "$VERSION" != "$PROJECT_VERSION" ]]; then
  echo "release.sh: VERSION=$VERSION does not match pyproject.toml [project].version=$PROJECT_VERSION" >&2
  exit 1
fi

# A fresh outdir, so a reused $DIST_DIR can never leak a stale-version file into
# the manifest. Python's build tool canonicalises versions per PEP 440 ("1.0.0-rc.1"
# builds as "1.0.0rc1"), so artifacts are taken from what the build produced, not
# matched against the raw $VERSION (a filename match would write a manifest with
# 0 artifacts and exit 0, passing the release gate with nothing in it:
# art-release-readiness).
BUILD_DIR="$WORK/build"
mkdir -p "$BUILD_DIR"
python3 -m build --no-isolation --sdist --wheel --outdir "$BUILD_DIR"

mkdir -p "$DIST_DIR"
python3 - "$LIB" "$BUILD_DIR" "$DIST_DIR" "$VERSION" "$EPOCH" "$TREE" <<'PY'
import os, shutil, sys
sys.path.insert(0, sys.argv[1])
import release_manifest as m
lib, build_dir, dist, version, epoch, tree = sys.argv[1:7]
names = sorted(os.listdir(build_dir))
wheels = [n for n in names if n.endswith(".whl")]
sdists = [n for n in names if n.endswith(".tar.gz")]
if len(wheels) != 1 or len(sdists) != 1:
    print("release.sh: expected exactly one .whl and one .tar.gz from the build, found "
          f"{len(wheels)} wheel(s) and {len(sdists)} sdist(s): {names}", file=sys.stderr)
    sys.exit(1)
entries = []
for name in wheels + sdists:
    dest = os.path.join(dist, name)
    if name.endswith(".tar.gz"):
        m.repack_sdist(os.path.join(build_dir, name), dest, int(epoch))
        entries.append((name, "sdist", True))
    else:
        shutil.copyfile(os.path.join(build_dir, name), dest)
        entries.append((name, "wheel", True))
m.write(dist, version, "python", int(epoch), tree, entries)
print(f"Wrote manifest with {len(entries)} artifact(s)")
PY
