#!/usr/bin/env bash
# REQ-351 (P6 R20, dfe-5): delete the one GHCR version a release superseded, and nothing else.
#   release-ghcr-prune.sh --owner <o> --package <p> --superseded <digest|none>
# With "none": nothing to do. Otherwise the version whose name is that digest is found through gh api (orgs/ first,
# users/ on a 404) and deleted only when it carries no tag now; any other untagged version is never touched.
# It runs after publish, when the Release already exists (release.yml: a failure here is a warning), so every GitHub
# failure — a 401, 403, 404 on both scopes, 429, 5xx or network error, an unreadable listing, a refused or failed
# delete — prints a ::warning:: and exits 0, leaving the superseded version in place. Only a programming error exits 1:
# missing arguments, or a --superseded that is neither none nor sha256:<64 hex>.
# bash 3.2; python3 stdlib only.
set -uo pipefail

usage() { echo "usage: release-ghcr-prune.sh --owner <o> --package <p> --superseded <sha256:<64 hex>|none>" >&2; exit 1; }
OWNER=""; PKG=""; SUP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --owner) [ $# -ge 2 ] || usage; OWNER="$2"; shift 2 ;;
    --package) [ $# -ge 2 ] || usage; PKG="$2"; shift 2 ;;
    --superseded) [ $# -ge 2 ] || usage; SUP="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$OWNER" ] && [ -n "$PKG" ] && [ -n "$SUP" ] || usage
DIGEST_RE='^sha256:[0-9a-f]{64}$'
[ "$SUP" = none ] || [[ $SUP =~ $DIGEST_RE ]] || usage

if [ "$SUP" = none ]; then echo "prune: nothing superseded"; exit 0; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/specflow-prune.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

warn() { echo "::warning::prune: $1 — the superseded image version $SUP is left in place"; exit 0; }
oneline() { tr '\n' ' ' <"$1" | cut -c1-300; }

BASE=""
for scope in orgs users; do
  rc=0
  gh api --paginate "$scope/$OWNER/packages/container/$PKG/versions" >"$TMP/versions" 2>"$TMP/err" || rc=$?
  if [ "$rc" = 0 ]; then BASE="$scope/$OWNER/packages/container/$PKG/versions"; break; fi
  case "$(cat "$TMP/err")" in
    *"(HTTP 404)"*|*"Not Found"*) continue ;;
  esac
  warn "GitHub did not answer the $scope/ listing ($(oneline "$TMP/err"))"
done
[ -n "$BASE" ] || warn "the package is not found under orgs/ or users/ (404)"

# The id of the version named SUP, when it is untagged; "tagged" when it still carries a tag; empty when absent.
verdict="$(python3 - "$TMP/versions" "$SUP" <<'PY'
import json, sys
text = open(sys.argv[1]).read(); dec = json.JSONDecoder(); i = 0; vs = []
while True:
    while i < len(text) and text[i].isspace():
        i += 1
    if i >= len(text):
        break
    v, i = dec.raw_decode(text, i)
    vs.extend(v if isinstance(v, list) else [v])
for v in vs:
    if v.get("name") == sys.argv[2]:
        tags = ((v.get("metadata") or {}).get("container") or {}).get("tags") or []
        if tags:
            print("tagged")
        elif isinstance(v.get("id"), int):
            print(v["id"])
        else:
            sys.exit("no integer id")
        break
PY
)" || warn "the versions listing is unreadable"

case "$verdict" in
  "") echo "prune: $SUP is not among the package's versions; nothing deleted"; exit 0 ;;
  tagged) echo "prune: $SUP still carries a tag; kept"; exit 0 ;;
esac

rc=0
gh api --method DELETE "$BASE/$verdict" >"$TMP/out" 2>"$TMP/err" || rc=$?
[ "$rc" = 0 ] || warn "GitHub refused or failed the delete ($(oneline "$TMP/err"))"
echo "prune: deleted version $verdict ($SUP)"
exit 0
