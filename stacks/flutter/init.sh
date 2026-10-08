#!/usr/bin/env bash
# flutter stack pack — init.sh (REQ-303/304).
#
# Usage: init.sh package
#   cwd = target directory. env SPECFLOW_NAME, SPECFLOW_PKG (init's
#   candidate: lowercased, non-[a-z0-9] runs -> '_', trimmed). Prints the
#   final package name on stdout and exits 0, or prints one stderr line
#   naming the cause and exits 2. Pure bash + python3 stdlib; no toolchain,
#   no network, no writes.
# Usage: init.sh preflight
#   cwd = target directory. Checks everything `scaffold` needs (the pinned
#   Flutter SDK, its frameworkRevision, its macOS Podfile template) and
#   writes nothing. Prints one stderr line `preflight: missing <item>:
#   <hint>` per gap plus a last line naming `bash scripts/init-project.sh
#   --doctor --stack flutter`, and exits 1 on any gap.
# Usage: init.sh scaffold
#   cwd = target directory. env SPECFLOW_NAME, SPECFLOW_PKG. Runs `flutter
#   create` (macOS only) against the pinned SDK, then copies overlay/ over
#   the generated tree (overlay wins), substituting __PKG__/__NAME__ only in
#   overlay files. Checks every destination before copying and, on any
#   clash, exits 1 naming the path with nothing written. No `pub get`.
# Any other subcommand: usage error (exit 2).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY="$HERE/overlay"
CFG="$HERE/../../scripts/lib/specflow/config.py"
PACK="$HERE/pack.yml"
CMD="${1:-}"

cfg_get() { python3 "$CFG" --file "$PACK" get "$1"; }
cfg_getlist() { python3 "$CFG" --file "$PACK" getlist "$1" 2>/dev/null || true; }

FLUTTER_VERSION="$(cfg_get flutter_version)"
FLUTTER_REVISION="$(cfg_get flutter_revision)"
MACOS_MIN="$(cfg_get macos_min)"

# non-contextual dart keywords (dart.dev/language/keywords), copied at pin
# time from the pinned SDK's packages/flutter_tools/lib/src/commands/
# create_base.dart (_keywords, flutter_revision 5fc346839b5d0eef006ed8404392afb4dfae428d).
# Re-derived at 3.47.6 on 2026-10-04: the list is unchanged from 3.35.5's.
DART_KEYWORDS="abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for function get hide if implements import in inout interface is late library mixin native new null of on operator out part patch required rethrow return set show source static super switch sync this throw true try typedef var void while with yield"
# _packageDependencies from the same file.
PACKAGE_DEPENDENCIES="collection flutter flutter_test meta"
# The generated app's other direct dependencies plus 'test' (create_base.dart's
# default pubspec template).
OTHER_DIRECT_DEPS="cupertino_icons flutter_lints test"

# flutter_version_json — prints `flutter --version --machine`'s JSON once,
# or nothing (and a false return) if flutter is missing or the call fails.
flutter_version_json() {
  command -v flutter >/dev/null 2>&1 || return 1
  flutter --version --machine 2>/dev/null
}

json_field() {  # json_field FIELD < JSON
  python3 -c 'import json, sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1"
}

case "$CMD" in
  package)
    : "${SPECFLOW_NAME:?SPECFLOW_NAME env var required}"
    : "${SPECFLOW_PKG:?SPECFLOW_PKG env var required}"
    PKG="$SPECFLOW_PKG"

    in_list() {
      local needle="$1"; shift
      local w
      for w in "$@"; do [[ "$needle" == "$w" ]] && return 0; done
      return 1
    }

    LOCKED_DEPS=""
    if [[ -f "$OVERLAY/pubspec.lock" ]]; then
      LOCKED_DEPS="$(grep -E '^  [a-zA-Z0-9_]+:$' "$OVERLAY/pubspec.lock" | sed -E 's/^  ([a-zA-Z0-9_]+):$/\1/' | tr '\n' ' ')"
    fi

    # shellcheck disable=SC2086
    if in_list "$PKG" $DART_KEYWORDS; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') is a Dart keyword — choose a different name" >&2
      exit 2
    elif in_list "$PKG" $PACKAGE_DEPENDENCIES; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') clashes with a package flutter create depends on — choose a different name" >&2
      exit 2
    elif in_list "$PKG" $OTHER_DIRECT_DEPS; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') clashes with a skeleton dependency — choose a different name" >&2
      exit 2
    elif [[ -n "$LOCKED_DEPS" ]] && in_list "$PKG" $LOCKED_DEPS; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') clashes with a locked transitive dependency — choose a different name" >&2
      exit 2
    fi

    echo "$PKG"
    ;;

  preflight)
    GAPS=()
    OS="$(uname -s 2>/dev/null || echo unknown)"

    if [[ "$OS" != Darwin ]]; then
      GAPS+=("darwin: v3.2 builds app stacks on macOS only — use a Mac, or the macos-15 CI workflow")
    fi

    VJSON=""
    if ! VJSON="$(flutter_version_json)"; then
      GAPS+=("flutter: $(cfg_get install_macos_flutter)")
    else
      GOT_REV="$(json_field frameworkRevision <<<"$VJSON")"
      GOT_VER="$(json_field frameworkVersion <<<"$VJSON")"
      if [[ "$GOT_REV" != "$FLUTTER_REVISION" ]]; then
        GAPS+=("flutter: found $GOT_VER ($GOT_REV); need $FLUTTER_VERSION ($FLUTTER_REVISION) — $(cfg_get install_macos_flutter)")
      else
        FLUTTER_ROOT="$(json_field flutterRoot <<<"$VJSON")"
        if [[ ! -f "$FLUTTER_ROOT/packages/flutter_tools/templates/cocoapods/Podfile-macos" ]]; then
          GAPS+=("flutter_macos_template: $FLUTTER_ROOT is missing packages/flutter_tools/templates/cocoapods/Podfile-macos — reinstall the pinned SDK")
        fi
      fi
    fi

    if [[ ${#GAPS[@]} -gt 0 ]]; then
      for g in "${GAPS[@]}"; do
        echo "preflight: missing $g" >&2
      done
      echo "bash scripts/init-project.sh --doctor --stack flutter" >&2
      exit 1
    fi
    exit 0
    ;;

  scaffold)
    : "${SPECFLOW_NAME:?SPECFLOW_NAME env var required}"
    : "${SPECFLOW_PKG:?SPECFLOW_PKG env var required}"
    PKG="$SPECFLOW_PKG"
    TARGET="$(pwd)"

    VJSON=""
    if ! VJSON="$(flutter_version_json)"; then
      echo "init.sh scaffold: missing flutter — run bash scripts/init-project.sh --doctor --stack flutter" >&2
      exit 1
    fi
    GOT_REV="$(json_field frameworkRevision <<<"$VJSON")"
    if [[ "$GOT_REV" != "$FLUTTER_REVISION" ]]; then
      GOT_VER="$(json_field frameworkVersion <<<"$VJSON")"
      echo "init.sh scaffold: flutter is $GOT_VER ($GOT_REV); need $FLUTTER_VERSION ($FLUTTER_REVISION) — bash scripts/init-project.sh --doctor --stack flutter" >&2
      exit 1
    fi
    FLUTTER_ROOT="$(json_field flutterRoot <<<"$VJSON")"
    PODFILE_TEMPLATE="$FLUTTER_ROOT/packages/flutter_tools/templates/cocoapods/Podfile-macos"

    WORKDIR="$(mktemp -d)"
    trap 'rm -rf "$WORKDIR"' EXIT
    GENERATED="$WORKDIR/$PKG"
    flutter create --platforms=macos --org com.example --project-name "$PKG" --no-pub "$GENERATED" >/dev/null

    if [[ ! -d "$GENERATED" ]]; then
      echo "init.sh scaffold: flutter create did not produce $GENERATED" >&2
      exit 1
    fi

    # Every MACOSX_DEPLOYMENT_TARGET in the generated project is set to the
    # pack minimum (Xcode 27 rejects the generator's default 10.15).
    PBXPROJ="$GENERATED/macos/Runner.xcodeproj/project.pbxproj"
    if [[ -f "$PBXPROJ" ]]; then
      python3 - "$PBXPROJ" "$MACOS_MIN" <<'PY'
import re, sys
path, macos_min = sys.argv[1:3]
text = open(path).read()
text = re.sub(r"MACOSX_DEPLOYMENT_TARGET = [0-9.]+;", f"MACOSX_DEPLOYMENT_TARGET = {macos_min};", text)
open(path, "w").write(text)
PY
    fi

    # macos/Podfile: flutter create writes none for a plugin-free app; ship
    # one from the SDK's own template, at the pack minimum, so a plugin
    # arriving later still gets the pinned minimum.
    if [[ -f "$PODFILE_TEMPLATE" ]]; then
      mkdir -p "$GENERATED/macos"
      python3 - "$PODFILE_TEMPLATE" "$GENERATED/macos/Podfile" "$MACOS_MIN" <<'PY'
import re, sys
src, dest, macos_min = sys.argv[1:4]
text = open(src).read()
text = re.sub(r"platform :osx, '[0-9.]+'", f"platform :osx, '{macos_min}'", text, count=1)
open(dest, "w").write(text)
PY
    fi

    # The pack ships arm64 only (pack.yml macos_archs): pin the release
    # build to arm64. The pin began as a workaround — Xcode 27's lipo accepts
    # one -verify_arch per invocation, and the earlier Flutter 3.35.5's
    # universal build (arm64 x86_64) failed release_unpack_macos (measured
    # 2026-09-25); Flutter 3.47.6's universal build succeeds on Xcode 27
    # (measured 2026-10-04), so arm64-only is now the pack's choice, not a
    # necessity (a universal bundle doubles the app's size).
    RELEASE_XCCONFIG="$GENERATED/macos/Runner/Configs/Release.xcconfig"
    if [[ -f "$RELEASE_XCCONFIG" ]]; then
      {
        echo ""
        echo "// The specflow flutter pack ships arm64 only (macos_archs); delete this"
        echo "// line for a universal (arm64 x86_64) build, which Flutter 3.47.6 supports."
        echo "ARCHS = arm64"
      } >> "$RELEASE_XCCONFIG"
    fi

    # pubspec.yaml: flutter create writes version: 1.0.0+1; the pack ships
    # every fresh instance at 0.1.0+1.
    PUBSPEC="$GENERATED/pubspec.yaml"
    if [[ -f "$PUBSPEC" ]]; then
      python3 - "$PUBSPEC" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r"(?m)^version: .*$", "version: 0.1.0+1", text, count=1)
open(path, "w").write(text)
PY
    fi

    # Build the destination manifest: generated tree (minus its root
    # README.md and .gitignore, which are skipped) with the overlay laid
    # over it (overlay wins on any clash between the two).
    MANIFEST_PATHS_FILE="$(mktemp)"; MANIFEST_SRC_FILE="$(mktemp)"
    trap 'rm -rf "$WORKDIR" "$MANIFEST_PATHS_FILE" "$MANIFEST_SRC_FILE"' EXIT

    : > "$MANIFEST_PATHS_FILE"; : > "$MANIFEST_SRC_FILE"
    add_entry() {  # add_entry REL_PATH ABS_SRC
      printf '%s\n' "$1" >> "$MANIFEST_PATHS_FILE"
      printf '%s\n' "$2" >> "$MANIFEST_SRC_FILE"
    }

    while IFS= read -r -d '' src; do
      rel="${src#"$GENERATED"/}"
      [[ "$rel" == README.md || "$rel" == .gitignore ]] && continue
      add_entry "$rel" "$src"
    done < <(find "$GENERATED" -type f -print0)

    while IFS= read -r -d '' src; do
      rel="${src#"$OVERLAY"/}"
      add_entry "$rel" "$src"
    done < <(find "$OVERLAY" -type f -print0)

    UNIQ_PATHS_FILE="$(mktemp)"; UNIQ_SRC_FILE="$(mktemp)"
    trap 'rm -rf "$WORKDIR" "$MANIFEST_PATHS_FILE" "$MANIFEST_SRC_FILE" "$UNIQ_PATHS_FILE" "$UNIQ_SRC_FILE"' EXIT
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

    GITIGNORE="$TARGET/.gitignore"
    touch "$GITIGNORE"
    if ! grep -qF '# >>> specflow flutter pack' "$GITIGNORE"; then
      {
        echo '# >>> specflow flutter pack'
        echo '.dart_tool/'
        echo '.flutter-plugins-dependencies'
        echo '**/Flutter/ephemeral/'
        echo '**/Pods/'
        echo '*.iml'
        echo '.idea/'
        echo 'coverage/'
        echo '# <<< specflow flutter pack'
      } >> "$GITIGNORE"
    fi
    ;;

  *)
    echo "usage: init.sh package|preflight|scaffold" >&2
    exit 2
    ;;
esac
