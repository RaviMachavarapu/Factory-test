#!/usr/bin/env bash
# python stack pack — init.sh (REQ-303/304).
#
# Usage: init.sh package
#   cwd = target directory. env SPECFLOW_NAME, SPECFLOW_PKG (init's candidate).
#   Prints the final package name on stdout and exits 0, or prints one stderr
#   line naming the cause and exits 2. Pure bash + python3 stdlib; no
#   toolchain, no network, no writes.
# Usage: init.sh preflight
#   cwd = target directory. env SPECFLOW_NAME, SPECFLOW_PKG. Checks
#   everything `scaffold` needs before init writes anything: dry-runs every
#   skeleton destination and exits 1 naming the first one that already
#   exists.
# Usage: init.sh scaffold
#   cwd = target directory. env SPECFLOW_NAME, SPECFLOW_PKG.
#   Copies this pack's skeleton/ into cwd, substituting __PKG__/__NAME__ in
#   paths and file contents. Never overwrites an existing file (exit 1).
# Any other subcommand: usage error (exit 2).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKEL="$HERE/skeleton"
CMD="${1:-}"

case "$CMD" in
  package)
    : "${SPECFLOW_NAME:?SPECFLOW_NAME env var required}"
    : "${SPECFLOW_PKG:?SPECFLOW_PKG env var required}"

    # Cap the derived package name so `from src.<pkg>.__main__ import main` in
    # the skeleton's smoke test stays within black's 88-column line length no
    # matter how long --name is (a --name up to the 64-char limit would
    # otherwise produce a package name long enough to force black to wrap
    # that import, failing run-quality-gates.sh with no hand edits —
    # REQ-304).
    PKG="${SPECFLOW_PKG:0:40}"
    PKG="$(printf '%s' "$PKG" | sed -E 's/_+$//')"

    # 'src', 'tests' and 'conftest' are the skeleton's own top-level layout
    # names (src/<pkg>/, tests/<pkg>/) and pytest's fixture-file name — a
    # package named after any of them produces a skeleton that fails
    # run-quality-gates.sh with no hand edits (W-4, REQ-304): e.g. --name Src
    # collides with the src/ layout itself, and --name Conftest produces
    # tests/conftest/, which pytest's own conftest.py collection can shadow.
    # Reject outright, before checking whether anything actually clashes on
    # disk.
    case "$PKG" in
      src|tests|conftest)
        echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') is a name the skeleton's own layout reserves — choose a different name" >&2
        exit 2
        ;;
    esac

    if [[ -e "src/$PKG" ]]; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') clashes with existing src/$PKG" >&2
      exit 2
    fi

    if [[ -e "tests/$PKG" ]]; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') clashes with existing tests/$PKG" >&2
      exit 2
    fi

    # A package that shadows a Python keyword, a stdlib module (e.g.
    # 'calendar', 'email', 'logging', 'types') or the 'pytest' package itself
    # produces a skeleton that fails run-quality-gates.sh with no hand edits
    # (REQ-304): the stdlib collision breaks imports once tests/<pkg>/ or
    # src/<pkg>/ shadows it on sys.path, and a keyword or 'pytest' breaks
    # ruff/black/pytest collection outright. Reject before anything is
    # written.
    PKG_COLLISION="$(python3 - "$PKG" <<'PY'
import keyword
import sys

pkg = sys.argv[1]
if keyword.iskeyword(pkg):
    print("a Python keyword")
elif pkg in sys.stdlib_module_names:
    print("a Python standard-library module name")
elif pkg == "pytest":
    print("the pytest package name")
PY
)"
    if [[ -n "$PKG_COLLISION" ]]; then
      echo "package '$PKG' (derived from --name '$SPECFLOW_NAME') is $PKG_COLLISION — choose a different name" >&2
      exit 2
    fi

    echo "$PKG"
    ;;

  preflight)
    : "${SPECFLOW_NAME:?SPECFLOW_NAME env var required}"
    : "${SPECFLOW_PKG:?SPECFLOW_PKG env var required}"

    # Python's scaffold needs only bash and sed (both required to run
    # init-project.sh itself), so the only real gap left to check is a
    # destination the skeleton would write already existing — scaffold
    # itself refuses mid-copy on the first clash it hits (F-3/W-3), which by
    # then can leave docs/, config, and pack hooks already written. Dry-run
    # every skeleton destination here, before init writes anything.
    TARGET="$(pwd)"
    while IFS= read -r -d '' src; do
      rel="${src#"$SKEL"/}"
      dest_rel="${rel//__PKG__/$SPECFLOW_PKG}"
      dest="$TARGET/$dest_rel"
      if [[ -e "$dest" ]]; then
        echo "preflight: destination already exists and the skeleton would write it: $dest_rel" >&2
        exit 1
      fi
    done < <(find "$SKEL" -type f -print0)
    exit 0
    ;;

  scaffold)
    : "${SPECFLOW_NAME:?SPECFLOW_NAME env var required}"
    : "${SPECFLOW_PKG:?SPECFLOW_PKG env var required}"

    TARGET="$(pwd)"

    while IFS= read -r -d '' src; do
      rel="${src#"$SKEL"/}"
      dest_rel="${rel//__PKG__/$SPECFLOW_PKG}"
      dest="$TARGET/$dest_rel"
      if [[ -e "$dest" ]]; then
        echo "init.sh scaffold: refusing to overwrite existing file: $dest_rel" >&2
        exit 1
      fi
      mkdir -p "$(dirname "$dest")"
      sed -e "s/__PKG__/$SPECFLOW_PKG/g" -e "s/__NAME__/$SPECFLOW_NAME/g" "$src" > "$dest"
    done < <(find "$SKEL" -type f -print0)
    ;;

  *)
    echo "usage: init.sh package|preflight|scaffold" >&2
    exit 2
    ;;
esac
