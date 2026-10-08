#!/usr/bin/env bash
# REQ-351, REQ-390 (P6 R20): the python image's decisions, behind the release action's parts (stack python only).
#   release-image.sh <prior|build|publish> --image <ghcr.io/o/r> --version <v> --tag <t> --out <image.json>
#     [--source-url <url>] [--prior <digest|none>]
# Every digest this script prints, records or accepts as --prior is "none" or matches ^sha256:[0-9a-f]{64}$ — anything
# else (a tampered manifest asset, a newline) exits 1, so nothing else can reach GITHUB_OUTPUT or image.json.
# prior   — the image.digest the tag's existing Release records in its manifest.json, or "none" (no Release: gh's
#           "release not found"; a Release with no manifest.json asset exits 1); no registry access. It also writes
#           <out dir>/image-prior.json, {"prior", "first"}: first is true when the tag has no Release and no other
#           published Release records an image: the listing (gh release list --limit 100) is walked newest first until
#           one's manifest.json records an image.digest (a Release with no manifest.json asset, or no image.digest, is
#           passed over; a digest on the way that is not sha256:<64 hex> exits 1) — the package was never pushed by a
#           release.
# build   — RELEASE_COMMIT (required) must be HEAD and the working tree clean (git status --porcelain empty), else exit 1;
#           docker build --no-cache, with the source and version labels, of a temporary context holding only HEAD's
#           committed Dockerfile, its committed requirements-runtime.txt and the one wheel in the out file's directory (never the checkout's ./dist); then
#           release-smoke.sh beside this script. No registry access and no credential.
# publish — (after the caller's login) a prior digest must still be what <image>:<version> names: reused, nothing built
#           or pushed. Otherwise, on a first release (image-prior.json says first) the registry is not read before the
#           push — an anonymous inspect of a package that does not exist is refused at the token endpoint (403, measured),
#           and the job token's answer for a never-pushed package is unmeasured, so the first release never depends on
#           it: nothing pushed before, nothing superseded. Else the current digest is read (digest_of's exact rule). The
#           image is tagged and pushed, the digest the push itself printed is taken (else the local image's RepoDigests
#           entry for <image>; never the registry's answer), the registry's read-back must equal it (else exit 1: the tag
#           moved between the push and the read), and {"name","tag","digest","superseded"} written to --out.
# bash 3.2; python3 stdlib only.
set -uo pipefail

usage() { echo "usage: release-image.sh <prior|build|publish> --image <ref> --version <v> --tag <t> --out <file> [--source-url <url>] [--prior <digest|none>]" >&2; exit 2; }

[ $# -ge 1 ] || usage
CMD="$1"; shift
IMAGE=""; VERSION=""; TAG=""; OUT=""; SOURCE_URL=""; PRIOR="none"
while [ $# -gt 0 ]; do
  case "$1" in
    --image) [ $# -ge 2 ] || usage; IMAGE="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || usage; VERSION="$2"; shift 2 ;;
    --tag) [ $# -ge 2 ] || usage; TAG="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT="$2"; shift 2 ;;
    --source-url) [ $# -ge 2 ] || usage; SOURCE_URL="$2"; shift 2 ;;
    --prior) [ $# -ge 2 ] || usage; PRIOR="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$IMAGE" ] && [ -n "$VERSION" ] && [ -n "$TAG" ] && [ -n "$OUT" ] || usage

DIGEST_RE='^sha256:[0-9a-f]{64}$'
# is_digest VALUE — VALUE is exactly sha256:<64 lowercase hex> (a whole-string match: a newline never passes).
is_digest() { [[ $1 =~ $DIGEST_RE ]]; }
if [ "$PRIOR" != none ] && ! is_digest "$PRIOR"; then
  echo "release-image: --prior must be none or sha256:<64 hex>" >&2
  exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCAL="specflow-release-local:$VERSION"
OUTDIR="$(dirname "$OUT")"
STATE="$OUTDIR/image-prior.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/specflow-image.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# digest_of REF — the digest REF names now: prints it, or "none" for a missing tag. "No such manifest" is an exact rule:
# the inspect fails and its whole error output, with the trailing newline removed, is exactly one line and one of
#   ERROR: <REF>: not found                         (buildx: the registry's 404 for this reference, containerd's ErrNotFound)
#   ERROR: <REF>: manifest unknown                  ERROR: manifest unknown
#   ERROR: <REF>: MANIFEST_UNKNOWN: manifest unknown  ERROR: MANIFEST_UNKNOWN: manifest unknown
# where <REF> is the reference inspected, character for character. Any other failure — an authorisation error (401, 403,
# "denied", a token endpoint's "404 Not Found"), "not found" or "manifest unknown" anywhere else in the text, another
# reference, a second line, no docker or no buildx, a network error — prints the error and returns 1 (fail closed). A
# Digest: line that is not sha256:<64 hex> returns 1 too.
digest_of() {
  local rc=0 d
  d="$(docker buildx imagetools inspect "$1" 2>"$TMP/err")" || rc=$?
  if [ "$rc" != 0 ]; then
    if python3 - "$1" "$TMP/err" <<'PY'
import sys
ref, text = sys.argv[1], open(sys.argv[2], errors="replace").read()
if text.endswith("\n"):
    text = text[:-1]
exact = {f"ERROR: {ref}: not found", f"ERROR: {ref}: manifest unknown", "ERROR: manifest unknown",
         f"ERROR: {ref}: MANIFEST_UNKNOWN: manifest unknown", "ERROR: MANIFEST_UNKNOWN: manifest unknown"}
sys.exit(0 if text in exact else 1)
PY
    then
      echo none
      return 0
    fi
    echo "release-image: cannot read the digest of $1 (fail closed; only a missing manifest reads as none): $(cat "$TMP/err")" >&2
    return 1
  fi
  d="$(printf '%s\n' "$d" | awk '/^Digest:/ { print $2; exit }')"
  is_digest "$d" || { echo "release-image: no sha256:<64 hex> Digest: line in the inspect output for $1" >&2; return 1; }
  printf '%s\n' "$d"
}

# pushed_digest PUSH_LOG — the digest this run's push produced: the "<tag>: digest: sha256:<64 hex> size: N" line docker
# push printed, else the local image's RepoDigests entry for $IMAGE; never read from the registry.
pushed_digest() {
  local d
  d="$(sed -n 's/^.*: digest: \(sha256:[0-9a-f]\{64\}\) size: [0-9][0-9]*$/\1/p' "$1" | tail -n 1)"
  if [ -z "$d" ]; then
    d="$(docker image inspect "$IMAGE:$VERSION" --format '{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null \
      | sed -n "s#^$IMAGE@\(sha256:[0-9a-f]\{64\}\)\$#\1#p" | head -n 1)"
  fi
  is_digest "$d" || { echo "release-image: the push printed no sha256:<64 hex> digest and $IMAGE has no RepoDigests entry" >&2; return 1; }
  printf '%s\n' "$d"
}

write_json() {  # write_json DIGEST SUPERSEDED
  is_digest "$1" || { echo "release-image: refusing to record digest '$1'" >&2; exit 1; }
  [ "$2" = none ] || is_digest "$2" || { echo "release-image: refusing to record superseded '$2'" >&2; exit 1; }
  mkdir -p "$OUTDIR"
  python3 -c 'import json, sys; json.dump({"name": sys.argv[1], "tag": sys.argv[2], "digest": sys.argv[3], "superseded": sys.argv[4]}, open(sys.argv[5], "w")); open(sys.argv[5], "a").write("\n")' \
    "$IMAGE" "$VERSION" "$1" "$2" "$OUT"
}

# manifest_digest FILE — image.digest from a Release's manifest.json: the digest, "none" when it records no image, exit 1
# when the file is unreadable or the digest is not sha256:<64 hex>.
manifest_digest() {
  python3 - "$1" <<'PY'
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
    v = (d.get("image") or {}).get("digest") if isinstance(d, dict) else None
except Exception as e:
    print(f"release-image: unreadable manifest.json: {e}", file=sys.stderr)
    sys.exit(1)
if v is None:
    print("none")
elif isinstance(v, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", v):
    print(v)
else:
    print("release-image: the manifest.json image.digest is not sha256:<64 hex> (a tampered asset?)", file=sys.stderr)
    sys.exit(1)
PY
}

# download TAG DIR — gh release download TAG's manifest.json into DIR; prints "missing" (no Release), "noasset" (no
# manifest.json asset) or "ok"; any other failure prints the error and returns 1.
download() {
  local rc=0 err
  mkdir -p "$2"
  gh release download "$1" --pattern manifest.json --dir "$2" >"$TMP/dl.out" 2>"$TMP/dl.err" || rc=$?
  if [ "$rc" = 0 ]; then echo ok; return 0; fi
  err="$(cat "$TMP/dl.err")"
  case "$err" in
    "release not found") echo missing; return 0 ;;
    "no assets match the file pattern") echo noasset; return 0 ;;
  esac
  echo "release-image: cannot read the Release $1: $err" >&2
  return 1
}

case "$CMD" in
  prior)
    rm -f "$STATE"
    got="$(download "$TAG" "$TMP/this")" || exit 1
    case "$got" in
      noasset)
        echo "release-image: the Release $TAG exists with no manifest.json asset (a draft an earlier publish left?) — inspect it by hand and delete the draft; nothing is pushed" >&2
        exit 1 ;;
      ok)
        prior="$(manifest_digest "$TMP/this/manifest.json")" || exit 1
        first=false ;;
      missing)
        prior=none
        gh release list --limit 100 --json tagName,isDraft,publishedAt >"$TMP/list" 2>"$TMP/list.err" \
          || { echo "release-image: cannot list the Releases (first release undecided): $(cat "$TMP/list.err")" >&2; exit 1; }
        python3 - "$TMP/list" "$TAG" >"$TMP/others" <<'PY' || exit 1
import json, sys
try:
    rs = json.load(open(sys.argv[1]))
    rs = [r for r in rs if not r.get("isDraft") and r.get("tagName") != sys.argv[2] and r.get("publishedAt")]
    if any(not isinstance(r["tagName"], str) or not r["tagName"] or "\n" in r["tagName"] for r in rs):
        raise ValueError("a tagName that is not a one-line string")
except Exception as e:
    print(f"release-image: unreadable Release listing: {e}", file=sys.stderr); sys.exit(1)
rs.sort(key=lambda r: r["publishedAt"], reverse=True)
for r in rs:
    print(r["tagName"])
PY
        # Every other published Release in the listing, newest first, until one's manifest.json records an image.
        first=true; n=0
        while IFS= read -r other <&3; do
          n=$((n + 1))
          got="$(download "$other" "$TMP/other-$n" </dev/null)" || exit 1
          [ "$got" = ok ] || continue
          d="$(manifest_digest "$TMP/other-$n/manifest.json")" || exit 1
          if [ "$d" != none ]; then first=false; break; fi
        done 3<"$TMP/others" ;;
    esac
    mkdir -p "$OUTDIR"
    python3 -c 'import json, sys; json.dump({"prior": sys.argv[1], "first": sys.argv[2] == "true"}, open(sys.argv[3], "w"))' "$prior" "$first" "$STATE" || exit 1
    printf '%s\n' "$prior"
    exit 0
    ;;
  build)
    [ -n "$SOURCE_URL" ] || usage
    if [ -z "${RELEASE_COMMIT:-}" ]; then echo "release-image: RELEASE_COMMIT is required: the build of record is of the release commit" >&2; exit 1; fi
    head="$(git rev-parse -q --verify HEAD 2>/dev/null)" || { echo "release-image: not a git checkout" >&2; exit 1; }
    want="$(git rev-parse -q --verify "$RELEASE_COMMIT^{commit}" 2>/dev/null)" || want=""
    if [ "$head" != "$want" ]; then
      echo "release-image: HEAD $head is not RELEASE_COMMIT $RELEASE_COMMIT; the image is built only from the release commit" >&2
      exit 1
    fi
    dirty="$(git status --porcelain 2>&1)" || { echo "release-image: git status failed: $dirty" >&2; exit 1; }
    if [ -n "$dirty" ]; then
      echo "release-image: the working tree is not clean; the image is built only from the committed tree:" >&2
      printf '%s\n' "$dirty" >&2
      exit 1
    fi
    DIST="$(cd "$OUTDIR" && pwd)" || exit 1
    n=0; whl=""
    for w in "$DIST"/*.whl; do [ -e "$w" ] && { n=$((n + 1)); whl="$w"; }; done
    if [ "$n" != 1 ]; then echo "release-image: expected exactly one wheel in $DIST, found $n" >&2; exit 1; fi
    CTX="$TMP/context"; mkdir -p "$CTX/dist"
    git show "$head:Dockerfile" > "$CTX/Dockerfile" || { echo "release-image: no Dockerfile in the release commit" >&2; exit 1; }
    git show "$head:requirements-runtime.txt" > "$CTX/requirements-runtime.txt" \
      || { echo "release-image: no requirements-runtime.txt in the release commit (the image installs the hash-pinned runtime lock; regenerate it with uv pip compile --generate-hashes)" >&2; exit 1; }
    cp "$whl" "$CTX/dist/" || exit 1
    docker build --no-cache --label "org.opencontainers.image.source=$SOURCE_URL" \
      --label "org.opencontainers.image.version=$VERSION" -t "$LOCAL" "$CTX" || exit 1
    bash "$HERE/release-smoke.sh" --stack python --dist "$DIST" --image "$LOCAL" || exit $?
    exit 0
    ;;
  publish)
    if [ "$PRIOR" != none ]; then
      cur="$(digest_of "$IMAGE:$VERSION")" || exit 1
      if [ "$cur" != "$PRIOR" ]; then
        echo "release-image: $IMAGE:$VERSION names $cur, not the published $PRIOR; a re-run never replaces a published image" >&2
        exit 1
      fi
      write_json "$PRIOR" none
      echo "image: reused $PRIOR (a re-run never replaces a published image)"
      exit 0
    fi
    first=false
    if [ -f "$STATE" ]; then
      first="$(python3 - "$STATE" <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"release-image: unreadable image-prior.json: {e}", file=sys.stderr); sys.exit(1)
if s.get("prior") != "none":
    print("release-image: image-prior.json records a prior digest, but --prior is none", file=sys.stderr); sys.exit(1)
print("true" if s.get("first") is True else "false")
PY
)" || exit 1
    fi
    if [ "$first" = true ]; then
      cur=none
      echo "image: a first release (no earlier Release records an image): the registry is not read before the push"
    else
      cur="$(digest_of "$IMAGE:$VERSION")" || exit 1
    fi
    docker tag "$LOCAL" "$IMAGE:$VERSION" || exit 1
    docker push "$IMAGE:$VERSION" > "$TMP/push.log" 2>&1; prc=$?
    cat "$TMP/push.log"
    [ "$prc" = 0 ] || exit 1
    new="$(pushed_digest "$TMP/push.log")" || exit 1
    back="$(digest_of "$IMAGE:$VERSION")" || exit 1
    if [ "$back" != "$new" ]; then
      echo "release-image: $IMAGE:$VERSION reads back as $back, not the pushed $new — the tag moved between the push and the read; nothing recorded" >&2
      exit 1
    fi
    sup="$cur"; [ "$cur" != "$new" ] || sup=none
    write_json "$new" "$sup"
    echo "image: pushed $IMAGE:$VERSION $new (superseded: $sup)"
    exit 0
    ;;
  *) usage ;;
esac
