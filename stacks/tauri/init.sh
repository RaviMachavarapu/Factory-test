#!/usr/bin/env bash
# tauri stack pack — init.sh (REQ-303/304).
#
# Usage: init.sh package
#   cwd = target directory. env SPECFLOW_NAME, SPECFLOW_PKG (init's
#   candidate: lowercased, non-[a-z0-9] runs -> '_', trimmed). Prints the
#   final package name on stdout and exits 0, or prints one stderr line
#   naming the cause and exits 2. Pure bash + python3 stdlib; no toolchain,
#   no network, no writes.
# Usage: init.sh preflight
#   cwd = target directory. Checks everything `scaffold` needs (tools,
#   versions, platform, generator download and integrity) and writes
#   nothing. Prints one stderr line `preflight: missing <item>: <hint>` per
#   gap plus a last line naming `bash scripts/init-project.sh --doctor
#   --stack tauri`, and exits 1 on any gap.
# Usage: init.sh scaffold
#   cwd = target directory. env SPECFLOW_NAME, SPECFLOW_PKG. Fetches and
#   verifies create-tauri-app by sha512 (pack.yml), runs it, then copies
#   overlay/ over the generated tree (overlay wins), substituting
#   __PKG__/__NAME__ only in overlay files. Checks every destination before
#   copying and, on any clash, exits 1 naming the path with nothing written.
# Any other subcommand: usage error (exit 2).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY="$HERE/overlay"
CFG="$HERE/../../scripts/lib/specflow/config.py"
PACK="$HERE/pack.yml"
CMD="${1:-}"

cfg_get() { python3 "$CFG" --file "$PACK" get "$1"; }

CV="$(cfg_get create_tauri_app_version)"
INTEGRITY_MAIN="$(cfg_get create_tauri_app_integrity)"
INTEGRITY_ARM="$(cfg_get create_tauri_app_darwin_arm64_integrity)"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/specflow/create-tauri-app-$CV"

sha512_of() {
  python3 -c 'import base64, hashlib, sys
print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1], "rb").read()).digest()).decode())' "$1"
}

# fetch_generators DIR — populates DIR with the two verified tarballs
# (fetching only when absent). On success, prints nothing and returns 0. On
# failure, prints one message (no trailing newline requirement) and returns
# 1 without having extracted or run anything from an unverified tarball.
fetch_generators() {
  local dir="$1" tA tB
  mkdir -p "$dir" 2>/dev/null || { echo "cannot create cache dir $dir"; return 1; }
  tA="$dir/create-tauri-app-$CV.tgz"
  tB="$dir/create-tauri-app-darwin-arm64-$CV.tgz"
  if [[ ! -f "$tA" || ! -f "$tB" ]]; then
    if ! npm pack --ignore-scripts --pack-destination "$dir" \
         "create-tauri-app@$CV" "create-tauri-app-darwin-arm64@$CV" >/dev/null 2>&1; then
      echo "create-tauri-app generator: npm pack create-tauri-app@$CV failed (network or registry error)"
      return 1
    fi
  fi
  local f want got
  for pair in "$tA:$INTEGRITY_MAIN" "$tB:$INTEGRITY_ARM"; do
    f="${pair%:*}"; want="${pair##*:}"
    if [[ ! -f "$f" ]]; then
      echo "create-tauri-app generator: $f not found after npm pack"
      return 1
    fi
    got="$(sha512_of "$f")"
    if [[ "$got" != "$want" ]]; then
      echo "create-tauri-app generator: $f integrity mismatch (want $want, got $got) — delete it to refetch"
      return 1
    fi
  done
  return 0
}

case "$CMD" in
  package)
    : "${SPECFLOW_NAME:?SPECFLOW_NAME env var required}"
    : "${SPECFLOW_PKG:?SPECFLOW_PKG env var required}"
    PKG="$SPECFLOW_PKG"

    RUST_KEYWORDS="as break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self static struct super trait true type unsafe use where while async await try union abstract become box do final macro override priv typeof unsized virtual yield"
    CARGO_RESERVED="std core alloc test proc_macro"
    WINDOWS_RESERVED="con prn aux nul com1 com2 com3 com4 com5 com6 com7 com8 com9 lpt1 lpt2 lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9"
    SKELETON_DEPS="tauri tauri_build tauri_plugin_opener serde serde_json"

    in_list() {
      local needle="$1"; shift
      local w
      for w in "$@"; do [[ "$needle" == "$w" ]] && return 0; done
      return 1
    }

    # Every crate name locked in overlay/src-tauri/Cargo.lock, read at run
    # time (mirrors the flutter pack's pubspec.lock rule). A package name
    # matching one of these makes cargo disambiguate the lock entry as
    # "name version", so the shipped lock no longer matches and
    # `cargo metadata --locked --offline` (and `cargo test --locked`) fail.
    LOCKED_CRATES=""
    CARGO_LOCK_FOR_PKG_CHECK="$OVERLAY/src-tauri/Cargo.lock"
    if [[ -f "$CARGO_LOCK_FOR_PKG_CHECK" ]]; then
      LOCKED_CRATES="$(grep -E '^name = "' "$CARGO_LOCK_FOR_PKG_CHECK" | sed -E 's/^name = "([^"]+)"/\1/' | tr '\n' ' ')"
    fi

    # shellcheck disable=SC2086
    if in_list "$PKG" $RUST_KEYWORDS; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') is a Rust keyword — choose a different name" >&2
      exit 2
    elif in_list "$PKG" $CARGO_RESERVED; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') is a name Cargo reserves for its own crates — choose a different name" >&2
      exit 2
    elif in_list "$PKG" $WINDOWS_RESERVED; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') is a name reserved on Windows — choose a different name" >&2
      exit 2
    elif in_list "$PKG" $SKELETON_DEPS; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') clashes with a skeleton dependency — choose a different name" >&2
      exit 2
    elif [[ -n "$LOCKED_CRATES" ]] && in_list "$PKG" $LOCKED_CRATES; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') clashes with a locked transitive dependency — choose a different name" >&2
      exit 2
    fi

    echo "$PKG"
    ;;

  preflight)
    GAPS=()
    OS="$(uname -s 2>/dev/null || echo unknown)"
    ARCH="$(uname -m 2>/dev/null || echo unknown)"

    if [[ "$OS" != Darwin ]]; then
      GAPS+=("darwin: v3.2 builds app stacks on macOS only — use a Mac, or the macos-15 CI workflow")
    fi
    if [[ "$ARCH" != arm64 ]]; then
      GAPS+=("arm64: the verified create-tauri-app-darwin-arm64 binary package is arm64 only — use an Apple Silicon Mac")
    fi

    if ! command -v node >/dev/null 2>&1; then
      GAPS+=("node: $(cfg_get install_macos_node)")
    elif ! node --version 2>/dev/null | grep -q '^v24\.'; then
      GAPS+=("node: found $(node --version 2>/dev/null); need v24.x — $(cfg_get install_macos_node)")
    fi
    if ! command -v npm >/dev/null 2>&1; then
      GAPS+=("npm: $(cfg_get install_macos_node)")
    fi

    if command -v npm >/dev/null 2>&1; then
      if ! MSG="$(fetch_generators "$CACHE_DIR" 2>&1)"; then
        GAPS+=("$MSG")
      fi
    fi

    if [[ ${#GAPS[@]} -gt 0 ]]; then
      for g in "${GAPS[@]}"; do
        echo "preflight: missing $g" >&2
      done
      echo "bash scripts/init-project.sh --doctor --stack tauri" >&2
      exit 1
    fi
    exit 0
    ;;

  scaffold)
    : "${SPECFLOW_NAME:?SPECFLOW_NAME env var required}"
    : "${SPECFLOW_PKG:?SPECFLOW_PKG env var required}"
    PKG="$SPECFLOW_PKG"
    TARGET="$(pwd)"

    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
      echo "init.sh scaffold: missing node/npm — run bash scripts/init-project.sh --doctor --stack tauri" >&2
      exit 1
    fi

    if ! MSG="$(fetch_generators "$CACHE_DIR" 2>&1)"; then
      echo "init.sh scaffold: $MSG" >&2
      exit 1
    fi

    GEN_ROOT="$(mktemp -d)"
    trap 'rm -rf "$GEN_ROOT"' EXIT
    mkdir -p "$GEN_ROOT/node_modules/create-tauri-app" "$GEN_ROOT/node_modules/create-tauri-app-darwin-arm64"
    tar -xzf "$CACHE_DIR/create-tauri-app-$CV.tgz" -C "$GEN_ROOT/node_modules/create-tauri-app" --strip-components 1
    tar -xzf "$CACHE_DIR/create-tauri-app-darwin-arm64-$CV.tgz" -C "$GEN_ROOT/node_modules/create-tauri-app-darwin-arm64" --strip-components 1

    WORKDIR="$(mktemp -d)"
    PKG_DASH="${PKG//_/-}"
    (cd "$WORKDIR" && node "$GEN_ROOT/node_modules/create-tauri-app/create-tauri-app.js" "$PKG" \
       --template vanilla-ts --manager npm --identifier "com.example.$PKG_DASH" \
       --tauri-version 2 --yes) >/dev/null
    GENERATED="$WORKDIR/$PKG"
    if [[ ! -d "$GENERATED" ]]; then
      echo "init.sh scaffold: create-tauri-app did not produce $WORKDIR/$PKG" >&2
      exit 1
    fi

    # Build the destination manifest: generated tree (minus its root
    # README.md and .gitignore, which are skipped) with the overlay laid
    # over it (overlay wins on any clash between the two).
    MANIFEST_PATHS_FILE="$(mktemp)"; MANIFEST_SRC_FILE="$(mktemp)"; MANIFEST_KIND_FILE="$(mktemp)"
    trap 'rm -rf "$GEN_ROOT" "$WORKDIR" "$MANIFEST_PATHS_FILE" "$MANIFEST_SRC_FILE" "$MANIFEST_KIND_FILE"' EXIT

    : > "$MANIFEST_PATHS_FILE"; : > "$MANIFEST_SRC_FILE"; : > "$MANIFEST_KIND_FILE"
    add_entry() {  # add_entry REL_PATH ABS_SRC KIND(gen|overlay)
      printf '%s\n' "$1" >> "$MANIFEST_PATHS_FILE"
      printf '%s\n' "$2" >> "$MANIFEST_SRC_FILE"
      printf '%s\n' "$3" >> "$MANIFEST_KIND_FILE"
    }

    while IFS= read -r -d '' src; do
      rel="${src#"$GENERATED"/}"
      [[ "$rel" == README.md || "$rel" == .gitignore ]] && continue
      add_entry "$rel" "$src" gen
    done < <(find "$GENERATED" -type f -print0)

    while IFS= read -r -d '' src; do
      rel="${src#"$OVERLAY"/}"
      add_entry "$rel" "$src" overlay
    done < <(find "$OVERLAY" -type f -print0)

    # De-duplicate: for a path present from both gen and overlay, keep only
    # the last (overlay) entry — overlay is added second above, so build a
    # rel->(src,kind) map with a final pass.
    UNIQ_PATHS_FILE="$(mktemp)"; UNIQ_SRC_FILE="$(mktemp)"
    trap 'rm -rf "$GEN_ROOT" "$WORKDIR" "$MANIFEST_PATHS_FILE" "$MANIFEST_SRC_FILE" "$MANIFEST_KIND_FILE" "$UNIQ_PATHS_FILE" "$UNIQ_SRC_FILE"' EXIT
    python3 - "$MANIFEST_PATHS_FILE" "$MANIFEST_SRC_FILE" "$UNIQ_PATHS_FILE" "$UNIQ_SRC_FILE" <<'PY'
import sys
paths_f, src_f, out_paths, out_src = sys.argv[1:5]
paths = open(paths_f).read().splitlines()
srcs = open(src_f).read().splitlines()
order = []
mapping = {}
for p, s in zip(paths, srcs):
    if p not in mapping:
        order.append(p)
    mapping[p] = s
with open(out_paths, "w") as fp, open(out_src, "w") as fs:
    for p in order:
        fp.write(p + "\n")
        fs.write(mapping[p] + "\n")
PY

    CLASHES=()
    while IFS= read -r rel; do
      if [[ -e "$TARGET/$rel" ]]; then
        CLASHES+=("$rel")
      fi
    done < "$UNIQ_PATHS_FILE"
    if [[ ${#CLASHES[@]} -gt 0 ]]; then
      echo "init.sh scaffold: refusing to overwrite existing path(s): ${CLASHES[*]}" >&2
      exit 1
    fi

    paste -d'\t' "$UNIQ_PATHS_FILE" "$UNIQ_SRC_FILE" | while IFS=$'\t' read -r rel src; do
      dest="$TARGET/$rel"
      mkdir -p "$(dirname "$dest")"
      case "$src" in
        "$OVERLAY"/*)
          sed -e "s/__PKG__/$PKG/g" -e "s/__NAME__/$SPECFLOW_NAME/g" "$src" > "$dest"
          ;;
        *)
          cp "$src" "$dest"
          ;;
      esac
    done

    # The overlay's Cargo.lock was sorted by cargo's (name, version) order for
    # the pinned package name (pin_app, tokenized to __PKG__). Substitution
    # just renamed one [[package]] block in place, which can leave that block
    # out of order for this instance's package name; any lock-writing cargo
    # run (npm run tauri dev, plain cargo build, rust-analyzer) would then
    # rewrite the file. Re-sort now so a fresh instance's tree stays clean.
    CARGO_LOCK="$TARGET/src-tauri/Cargo.lock"
    if [[ -f "$CARGO_LOCK" ]]; then
      python3 - "$CARGO_LOCK" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
parts = re.split(r'(?=^\[\[package\]\]$)', text, flags=re.MULTILINE)
preamble, blocks = parts[0], parts[1:]

def key(block):
    m = re.search(r'name = "([^"]+)"\nversion = "([^"]+)"', block)
    return (m.group(1), [int(x) for x in re.findall(r"\d+", m.group(2))])

blocks.sort(key=key)
open(path, "w").write(preamble + "".join(blocks))
PY
    fi

    GITIGNORE="$TARGET/.gitignore"
    touch "$GITIGNORE"
    if ! grep -qF '# >>> specflow tauri pack' "$GITIGNORE"; then
      {
        echo '# >>> specflow tauri pack'
        echo 'node_modules/'
        echo 'coverage/'
        echo '# <<< specflow tauri pack'
      } >> "$GITIGNORE"
    fi
    ;;

  *)
    echo "usage: init.sh package|preflight|scaffold" >&2
    exit 2
    ;;
esac
