#!/usr/bin/env bash
# python stack pack — the DEPLOY contract (REQ-351). init copies this file to scripts/deploy-local.sh; a real
# environment is a copy, scripts/deploy-<env>.sh, whose credentials live only in a GitHub Environment with required
# reviewers. release.yml never runs a deploy script.
#
# Defines migrate, deploy <version>, smoke and rollback. Only the docker, gh and migrate commands are printed, as
# "+ <command>" on stderr (never the git, mktemp and python3 calls that find the image, the tags and the digest); with
# DRY_RUN=1 a command that changes something (docker pull, docker rm, docker run, the migrate command) is printed and not
# run, while a read (gh release download of a Release's manifest.json, docker inspect of the running container) is
# printed and run — it changes nothing, and the commands after it need its answer. Sourced (with or without arguments)
# it only defines, and never changes the caller's shell options; executed, it runs under set -euo pipefail and
# dispatches to the named function. Each function returns non-zero when its command fails.
#
# The image runs BY DIGEST, never by its mutable tag: <version>'s digest is DEPLOY_DIGEST when set (deploy and smoke
# only), else image.digest in the manifest.json of the GitHub Release v<version> (gh release download, so gh must be
# authenticated for a private repository); it must be sha256:<64 hex>, and the image run is <image>@<digest>.
# Rollback: the version running now is the deployed container's org.opencontainers.image.version label (set by
# scripts/release-image.sh); rollback deploys the release before it — the highest vX.Y.Z tag below that version — by its
# Release's digest, and fails when no container is running, it carries no X.Y.Z label, or no earlier release exists.
# Only vX.Y.Z tags count as releases (never v0.0.1-demo, v1.2.0-rc1 or any other suffix).
#
#   DEPLOY_IMAGE        the image, default ghcr.io/<owner>/<repo> lower-cased from `git remote get-url origin`
#   DEPLOY_DIGEST       the digest deploy and smoke run, overriding the Release's manifest (rollback never reads it)
#   DEPLOY_RUN_ARGS     extra `docker run` arguments for deploy, split on whitespace (no quoting), e.g. "-p 8080:8080"
#   DEPLOY_MIGRATE_CMD  what migrate runs, default `true`
#   DEPLOY_VERSION      the version smoke runs, default the newest vX.Y.Z tag's
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

_NAME="__PKG__"
_DIGEST_RE='^sha256:[0-9a-f]{64}$'
_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# run CMD... — print "+ CMD..." and execute it unless DRY_RUN=1.
run() {
  echo "+ $*" >&2
  if [[ "${DRY_RUN:-}" == "1" ]]; then
    return 0
  fi
  "$@"
}

# _read CMD... — print "+ CMD..." and execute it, under DRY_RUN=1 too (a read changes nothing).
_read() {
  echo "+ $*" >&2
  "$@"
}

_image() {
  if [[ -n "${DEPLOY_IMAGE:-}" ]]; then
    printf '%s\n' "$DEPLOY_IMAGE"
    return 0
  fi
  local url path
  url="$(git remote get-url origin 2>/dev/null)" || { echo "deploy: no DEPLOY_IMAGE and no origin remote" >&2; return 1; }
  path="${url%.git}"
  path="${path#*://}"; path="${path#*@}"; path="${path#*[:/]}"
  path="$(printf '%s' "$path" | awk -F/ '{ if (NF >= 2) print $(NF-1) "/" $NF }' | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$path" ]]; then echo "deploy: cannot read owner/repo from '$url'" >&2; return 1; fi
  printf 'ghcr.io/%s\n' "$path"
}

# _tags — the vX.Y.Z release tags, newest first; nothing else (no demo, rc or other suffixed tag).
_tags() {
  { git tag --list 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'; } || true
}

# _below A B — A's X.Y.Z is lower than B's.
_below() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"
  IFS=. read -r b1 b2 b3 <<<"$2"
  (( a1 < b1 || (a1 == b1 && (a2 < b2 || (a2 == b2 && a3 < b3))) ))
}

# _digest VERSION [env] — the image digest of release VERSION: DEPLOY_DIGEST when "env" is given and it is set, else
# image.digest from the Release v<VERSION>'s manifest.json; exits non-zero unless it is sha256:<64 hex>.
_digest() {
  local version="$1" d="" tmp
  if [[ "${2:-}" == "env" && -n "${DEPLOY_DIGEST:-}" ]]; then
    d="$DEPLOY_DIGEST"
  else
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/deploy.XXXXXX")" || return 1
    if ! _read gh release download "v$version" --pattern manifest.json --dir "$tmp" >/dev/null; then
      rm -rf "$tmp"
      echo "deploy: cannot read the Release v$version's manifest.json" >&2
      return 1
    fi
    d="$(python3 -c 'import json, sys; print((json.load(open(sys.argv[1])).get("image") or {}).get("digest") or "")' "$tmp/manifest.json" 2>/dev/null)" || d=""
    rm -rf "$tmp"
  fi
  if ! [[ $d =~ $_DIGEST_RE ]]; then
    echo "deploy: no sha256:<64 hex> image digest for $version" >&2
    return 1
  fi
  printf '%s\n' "$d"
}

# _deploy_ref REF — pull REF, replace the running container with it.
_deploy_ref() {
  local ref="$1" args=()
  if [[ -n "${DEPLOY_RUN_ARGS:-}" ]]; then
    read -r -a args <<<"$DEPLOY_RUN_ARGS"
  fi
  run docker pull "$ref" || return 1
  run docker rm -f "$_NAME" >/dev/null || true
  run docker run -d --rm --name "$_NAME" ${args[@]+"${args[@]}"} "$ref"
}

migrate() {
  run bash -c "${DEPLOY_MIGRATE_CMD:-true}"
}

deploy() {
  local version="${1:-}" image digest
  if [[ -z "$version" ]]; then echo "usage: deploy <version>" >&2; return 2; fi
  if ! [[ $version =~ $_VERSION_RE ]]; then echo "deploy: the version must be X.Y.Z" >&2; return 2; fi
  image="$(_image)" || return 1
  digest="$(_digest "$version" env)" || return 1
  _deploy_ref "$image@$digest"
}

smoke() {
  local version="${DEPLOY_VERSION:-}" image digest
  if [[ -z "$version" ]]; then
    version="$(_tags | head -n 1)"; version="${version#v}"
  fi
  if [[ -z "$version" ]]; then echo "smoke: no version (set DEPLOY_VERSION or tag a release)" >&2; return 1; fi
  if ! [[ $version =~ $_VERSION_RE ]]; then echo "smoke: the version must be X.Y.Z" >&2; return 2; fi
  image="$(_image)" || return 1
  digest="$(_digest "$version" env)" || return 1
  run docker run --rm --name "$_NAME-smoke" -e SPECFLOW_SMOKE=1 "$image@$digest"
}

rollback() {
  local current prev="" t image digest
  current="$(_read docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$_NAME")" \
    || { echo "rollback: no running $_NAME container to roll back from; deploy an earlier release by hand: scripts/deploy-local.sh deploy <X.Y.Z>" >&2; return 1; }
  if ! [[ $current =~ $_VERSION_RE ]]; then
    echo "rollback: the running $_NAME container carries no X.Y.Z org.opencontainers.image.version label" >&2
    return 1
  fi
  for t in $(_tags); do
    if _below "${t#v}" "$current"; then prev="${t#v}"; break; fi
  done
  if [[ -z "$prev" ]]; then echo "rollback: no vX.Y.Z release before $current to roll back to" >&2; return 1; fi
  image="$(_image)" || return 1
  digest="$(_digest "$prev")" || return 1
  _deploy_ref "$image@$digest"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"
  case "$fn" in
    deploy) shift; deploy "$@" ;;
    migrate|smoke|rollback) "$fn" ;;
    *) echo "usage: deploy-<env>.sh migrate|deploy <version>|smoke|rollback" >&2; exit 2 ;;
  esac
fi
