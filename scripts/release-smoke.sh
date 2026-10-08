#!/usr/bin/env bash
# REQ-390 (P6 R19, R35): start what a release built, with SPECFLOW_SMOKE=1, and fail unless it exits 0 within the
# deadline (60 s by default). Usage: release-smoke.sh --stack <template|python|tauri|flutter> --dist <dir>
#   [--image <ref>] [--deadline <secs>]. Exit 0 ok; 124 overrun; the command's own status otherwise; 2 usage.
# No coreutils timeout (macOS has none): the command runs under job control (set -m) in a process group of its own,
# is polled once a second, and the whole group is signalled on overrun and after a normal exit, so no helper an app
# spawned outlives the smoke; an overrun prints a one-line reason. The python image runs as a named container
# (docker run --name specflow-smoke-<pid>-<epoch> --rm): killing the docker CLI does not stop a container, so on overrun
# the container is killed by name (docker kill) and on every exit removed (docker rm -f). Limit: a macOS helper launched
# through launchd or XPC is not in the app's process group, so the smoke cannot kill it. bash 3.2 compatible.
set -uo pipefail

usage() { echo "usage: release-smoke.sh --stack <template|python|tauri|flutter> --dist <dir> [--image <ref>] [--deadline <secs>]" >&2; exit 2; }

STACK=""; DIST=""; IMAGE=""; DEADLINE=60
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || usage; STACK="$2"; shift 2 ;;
    --dist) [ $# -ge 2 ] || usage; DIST="$2"; shift 2 ;;
    --image) [ $# -ge 2 ] || usage; IMAGE="$2"; shift 2 ;;
    --deadline) [ $# -ge 2 ] || usage; DEADLINE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "$DEADLINE" in ''|*[!0-9]*) usage ;; esac
[ -n "$STACK" ] || usage
[ -n "$DIST" ] && [ -d "$DIST" ] || usage

TMP="$(mktemp -d "${TMPDIR:-/tmp}/specflow-smoke.XXXXXX")"
MOUNT=""
CONTAINER=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; fi
  if [ -n "$CONTAINER" ]; then docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

# within SECS CMD... — CMD's status, or 124 on overrun; CMD's whole process group is killed either way.
within() {
  local secs="$1" pid pgid i=0 rc=0
  shift
  set -m
  SPECFLOW_SMOKE=1 bash -c 'exec "$@"' _ "$@" &
  pid=$!
  set +m
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  [ -n "$pgid" ] || pgid="$pid"
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge "$secs" ]; then rc=124; break; fi
    sleep 1; i=$((i + 1))
  done
  if [ "$rc" = 124 ]; then
    echo "release-smoke: overrun — the run did not exit within $secs s; its process group is killed (exit 124)" >&2
    kill -TERM -- "-$pgid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$pgid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 124
  fi
  wait "$pid" 2>/dev/null; rc=$?
  kill -TERM -- "-$pgid" 2>/dev/null || true
  sleep 0.2 2>/dev/null || true
  kill -KILL -- "-$pgid" 2>/dev/null || true
  return "$rc"
}

# one_file DIR PATTERN KIND — the single match, or exit 2.
one_file() {
  local n=0 f found=""
  for f in "$1"/$2; do [ -e "$f" ] || continue; n=$((n + 1)); found="$f"; done
  if [ "$n" != 1 ]; then echo "release-smoke: expected exactly one $3 in $1, found $n" >&2; exit 2; fi
  printf '%s\n' "$found"
}

# app_exe APPDIR-PARENT — the one executable under <App>.app/Contents/MacOS, or exit 2.
app_exe() {
  local n=0 apps=0 a f exe=""
  for a in "$1"/*.app; do
    [ -d "$a" ] || continue
    apps=$((apps + 1))
    for f in "$a"/Contents/MacOS/*; do [ -f "$f" ] || continue; n=$((n + 1)); exe="$f"; done
  done
  if [ "$apps" != 1 ] || [ "$n" != 1 ]; then echo "release-smoke: expected exactly one .app with one executable in $1 (found $apps apps, $n executables)" >&2; exit 2; fi
  printf '%s\n' "$exe"
}

case "$STACK" in
  template)
    TAR="$(one_file "$DIST" '*-source.tar' 'source archive')" || exit $?
    mkdir -p "$TMP/x" && tar -xf "$TAR" -C "$TMP/x" || { echo "release-smoke: cannot extract $TAR" >&2; exit 1; }
    ROOTDIR=""; n=0
    for d in "$TMP/x"/*/; do [ -d "$d" ] && { n=$((n + 1)); ROOTDIR="${d%/}"; }; done
    [ "$n" = 1 ] || { echo "release-smoke: the archive must hold one top directory" >&2; exit 1; }
    # shellcheck disable=SC2016
    within "$DEADLINE" bash -c '
      cd "$1" || exit 1
      bad=0
      for f in scripts/*.sh; do
        [ -e "$f" ] || continue
        bash -n "$f" || { echo "release-smoke: $f does not parse" >&2; bad=1; }
      done
      for f in scripts/lib/specflow/*.py; do
        [ -e "$f" ] || continue
        python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])" "$f" || { echo "release-smoke: $f does not parse" >&2; bad=1; }
      done
      bash scripts/next.sh --help >/dev/null || { echo "release-smoke: scripts/next.sh --help failed" >&2; bad=1; }
      [ "$bad" = 0 ] || exit 1
      echo "smoke: template ok"
    ' _ "$ROOTDIR"
    exit $?
    ;;
  python)
    [ -n "$IMAGE" ] || usage
    CONTAINER="specflow-smoke-$$-$(date +%s)"
    rc=0
    within "$DEADLINE" docker run --network none --pull never --name "$CONTAINER" --rm -e SPECFLOW_SMOKE=1 "$IMAGE" || rc=$?
    if [ "$rc" = 124 ]; then
      docker kill "$CONTAINER" >/dev/null 2>&1 || true
    fi
    exit "$rc"
    ;;
  tauri)
    DMG="$(one_file "$DIST" '*.dmg' 'dmg')" || exit $?
    mkdir -p "$TMP/mnt"
    MOUNT="$TMP/mnt"
    hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null || { MOUNT=""; echo "release-smoke: hdiutil attach failed" >&2; exit 1; }
    EXE="$(app_exe "$MOUNT")" || exit $?
    within "$DEADLINE" "$EXE"
    exit $?
    ;;
  flutter)
    ZIP="$(one_file "$DIST" '*.zip' 'zip')" || exit $?
    mkdir -p "$TMP/app"
    ditto -x -k "$ZIP" "$TMP/app" || { echo "release-smoke: ditto failed" >&2; exit 1; }
    EXE="$(app_exe "$TMP/app")" || exit $?
    within "$DEADLINE" "$EXE"
    exit $?
    ;;
  *) usage ;;
esac
