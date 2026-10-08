#!/usr/bin/env bash
# Checksum-verifying installer for the security floor's pinned tool assets (REQ-330).
#
# Usage: install-pinned-tool.sh TOOL... --dest DIR [--pins FILE] [--cache DIR]
#   TOOL is one of: gitleaks, osv-scanner, dafny
#
# Every asset is verified against scripts/pinned-tools.yml (or --pins) on every run,
# cached or not: a cache hit whose sha256 no longer matches the pin is discarded and
# re-fetched, and a downloaded asset whose sha256 differs from the pin is deleted and
# nothing is installed.
#
# Exit codes: 0 ok; 1 download/checksum/extract/copy failure; 2 usage error;
#             3 no pinned asset for this platform (prints the brew fallback).
# Each install_* runs as `install_x || …`, which suspends set -e inside it, so
# every step that can fail carries its own `|| return 1`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "install-pinned-tool: $1" >&2; exit "${2:-2}"; }

PINS="$ROOT/scripts/pinned-tools.yml"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/specflow-tools"
DEST=""
TOOLS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="${2:-}"; shift 2 ;;
    --pins) PINS="${2:-}"; shift 2 ;;
    --cache) CACHE="${2:-}"; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) TOOLS+=("$1"); shift ;;
  esac
done

[ -n "$DEST" ] || die "--dest is required"
[ "${#TOOLS[@]}" -gt 0 ] || die "no TOOL given"
[ -f "$PINS" ] || die "pins file not found: $PINS"

CFG="$ROOT/scripts/lib/specflow/config.py"
pin() { python3 "$CFG" --file "$PINS" get "$1" 2>/dev/null || true; }

OS="${SPECFLOW_TOOL_OS:-$(uname -s)}"
ARCH="${SPECFLOW_TOOL_ARCH:-$(uname -m)}"

case "$OS/$ARCH" in
  Darwin/arm64)
    PLATFORM_GITLEAKS="darwin_arm64"; PLATFORM_OSV="darwin_arm64"; PLATFORM_DAFNY="arm64-macos-13" ;;
  Linux/x86_64|Linux/amd64)
    PLATFORM_GITLEAKS="linux_x64"; PLATFORM_OSV="linux_amd64"; PLATFORM_DAFNY="x64-ubuntu-22.04" ;;
  *)
    PLATFORM_GITLEAKS=""; PLATFORM_OSV=""; PLATFORM_DAFNY="" ;;
esac

sha256_of() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }

# fetch_verified ASSET URL PIN_SHA — ensures $CACHE/ASSET exists and matches PIN_SHA,
# (re)downloading as needed. Returns 0 with the file in place, 1 on failure.
fetch_verified() {
  local asset="$1" url="$2" want="$3"
  mkdir -p "$CACHE" || return 1
  local path="$CACHE/$asset"
  if [ -f "$path" ]; then
    local have
    have="$(sha256_of "$path")"
    if [ "$have" != "$want" ]; then
      rm -f "$path"
    fi
  fi
  if [ ! -f "$path" ]; then
    if ! curl --proto '=https' --tlsv1.2 -fsSL -o "$path" "$url"; then
      rm -f "$path"
      echo "install-pinned-tool: download failed: $url" >&2
      return 1
    fi
    local got
    got="$(sha256_of "$path")"
    if [ "$got" != "$want" ]; then
      rm -f "$path"
      echo "install-pinned-tool: checksum mismatch for $asset (expected $want, got $got)" >&2
      return 1
    fi
  fi
  return 0
}

install_gitleaks() {
  if [ -z "$PLATFORM_GITLEAKS" ]; then
    echo "install-pinned-tool: no pinned gitleaks asset for $OS/$ARCH; brew install gitleaks" >&2
    return 3
  fi
  local version asset url want
  version="$(pin gitleaks_version)"
  asset="gitleaks_${version}_${PLATFORM_GITLEAKS}.tar.gz"
  url="https://github.com/gitleaks/gitleaks/releases/download/v${version}/${asset}"
  want="$(pin "gitleaks_sha256_${PLATFORM_GITLEAKS}")"
  [ -n "$want" ] || { echo "install-pinned-tool: no pinned sha256 for gitleaks_sha256_${PLATFORM_GITLEAKS}" >&2; return 3; }
  fetch_verified "$asset" "$url" "$want" || return 1
  mkdir -p "$DEST" || return 1
  tar -xzf "$CACHE/$asset" -C "$DEST" gitleaks || { echo "install-pinned-tool: cannot extract gitleaks from $asset" >&2; return 1; }
  chmod +x "$DEST/gitleaks" || return 1
  echo "installed gitleaks $version -> $DEST/gitleaks"
}

install_osv_scanner() {
  if [ -z "$PLATFORM_OSV" ]; then
    echo "install-pinned-tool: no pinned osv-scanner asset for $OS/$ARCH; brew install osv-scanner" >&2
    return 3
  fi
  local version asset url want
  version="$(pin osv_scanner_version)"
  asset="osv-scanner_${PLATFORM_OSV}"
  url="https://github.com/google/osv-scanner/releases/download/v${version}/${asset}"
  want="$(pin "osv_scanner_sha256_${PLATFORM_OSV}")"
  [ -n "$want" ] || { echo "install-pinned-tool: no pinned sha256 for osv_scanner_sha256_${PLATFORM_OSV}" >&2; return 3; }
  fetch_verified "$asset" "$url" "$want" || return 1
  mkdir -p "$DEST" || return 1
  cp "$CACHE/$asset" "$DEST/osv-scanner" || { echo "install-pinned-tool: cannot copy osv-scanner to $DEST" >&2; return 1; }
  chmod +x "$DEST/osv-scanner" || return 1
  echo "installed osv-scanner $version -> $DEST/osv-scanner"
}

install_dafny() {
  if [ -z "$PLATFORM_DAFNY" ]; then
    echo "install-pinned-tool: no pinned dafny asset for $OS/$ARCH; brew install dafny" >&2
    return 3
  fi
  local version asset url want pinkey
  version="$(pin dafny_version)"
  asset="dafny-${version}-${PLATFORM_DAFNY}.zip"
  url="https://github.com/dafny-lang/dafny/releases/download/v${version}/${asset}"
  case "$PLATFORM_DAFNY" in
    arm64-macos-13) pinkey="dafny_sha256_arm64_macos" ;;
    x64-ubuntu-22.04) pinkey="dafny_sha256_x64_ubuntu" ;;
    *) pinkey="" ;;
  esac
  want="$(pin "$pinkey")"
  [ -n "$want" ] || { echo "install-pinned-tool: no pinned sha256 for $pinkey" >&2; return 3; }
  fetch_verified "$asset" "$url" "$want" || return 1
  # Order matters: unzip -o below overwrites whatever is already in --dest,
  # which is safe only because fetch_verified has checked the archive's pinned
  # sha256 checksum first (it returns non-zero, and we stop, on a mismatch).
  # Keep the checksum verified first — never extract before it.
  mkdir -p "$DEST" || return 1
  unzip -q -o "$CACHE/$asset" -d "$DEST" || { echo "install-pinned-tool: cannot extract $asset" >&2; return 1; }
  chmod +x "$DEST/dafny/dafny" || return 1
  echo "installed dafny $version -> $DEST/dafny/dafny"
}

rc=0
for tool in "${TOOLS[@]}"; do
  case "$tool" in
    gitleaks) install_gitleaks || { r=$?; [ "$r" -gt "$rc" ] && rc=$r; } ;;
    osv-scanner) install_osv_scanner || { r=$?; [ "$r" -gt "$rc" ] && rc=$r; } ;;
    dafny) install_dafny || { r=$?; [ "$r" -gt "$rc" ] && rc=$r; } ;;
    *) die "unknown tool: $tool" ;;
  esac
done

exit "$rc"
