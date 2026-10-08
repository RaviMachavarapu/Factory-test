#!/usr/bin/env bash
# Governance test (retro 2026-05-28 proposal #2, accepted): article citations
# anywhere in docs/ must use art-* slugs, never Roman numerals
# (art-naming-tagging). Exemptions: superseded specs and archived reviews
# (historical records), and the plans for superseded specs. Since amendment C (REQ-326), every art-* slug cited in
# docs/ and in the files a session reads as instructions must be one constitution.md defines.
set -euo pipefail

ROOT="${SLUGS_TEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"   # SLUGS_TEST_ROOT: the pins below run a scratch tree
cd "$ROOT"

is_exempt() {
  local f="$1"
  case "$f" in
    docs/reviews/archive-*) return 0 ;;
  esac
  # Superseded specs are historical records.
  if head -20 "$f" 2>/dev/null | grep -q '^status: superseded'; then
    return 0
  fi
  return 1
}

# REQ-326 (amendment C; art-naming-tagging; P7 fresh-eyes review, finding 20): the Roman-numeral ban covers docs/ and the
# same instruction files the slug check below walks — constitution.md, CLAUDE.md, README.md and the Markdown under
# .claude/, .github/, schemas/, templates/ and stacks/. constitution.md's own "## IV — " headings and "roman:" fields
# define the numerals and are not citations (the pattern needs "Article"; they are filtered out all the same).
# Covers: REQ-326
# PR #60 run 1 (REQ-310, REQ-326): any CLAUDE.md or CLAUDE.local.md at any depth is loaded as instructions (REQ-310 counts
# nested ones), so the scans cover every one in the tree, not only the root's. Worktrees, vendored and build trees are
# not the repository's own files.
nested_claude_files() {
  find . \( -name .git -o -name node_modules -o -name worktrees -o -name target -o -name .venv -o -name venv \) -prune -o \
    -type f \( -name CLAUDE.md -o -name CLAUDE.local.md \) -print | sed 's|^\./||' | grep -vE '^(CLAUDE\.md)$' || true
}
roman_files() {
  find docs -name '*.md' -type f
  for f in constitution.md CLAUDE.md README.md; do [[ -f "$f" ]] && echo "$f"; done
  for r in .claude .github schemas templates stacks; do [[ -d "$r" ]] && find "$r" -name '*.md' -type f; done
  nested_claude_files
  return 0
}
VIOLATIONS=0
while IFS= read -r f; do
  is_exempt "$f" && continue
  if hits=$(grep -nE 'Articles? (XII|XI|IX|X|VIII|VII|VI|IV|V|III|II|I)\b' "$f" | grep -vE '^[0-9]+:(## [IVX]+ — |roman: [IVX]+$)'); then
    echo "FAIL: $f cites articles by Roman numeral:"
    echo "$hits" | sed 's/^/  /'
    VIOLATIONS=1
  fi
done < <(roman_files)

# REQ-326 (amendment C; art-naming-tagging): docs-wide slug existence — every art-* slug cited anywhere in docs/ and in
# the files a session reads as instructions names an article constitution.md defines. A placeholder (<art-slug>,
# art-<kebab>, art-*) is not a citation. Same exemptions as above.
# Covers: REQ-326
if ! python3 - <<'PY'
import os, re, sys
slugs = set(re.findall(r"(?m)^slug: (art-[a-z0-9-]+)$", open("constitution.md").read()))
assert len(slugs) == 12, slugs
files = [f for f in ("constitution.md", "CLAUDE.md", "README.md") if os.path.isfile(f)]
for r in ("docs", ".claude", ".github", "schemas", "templates", "stacks"):
    for d, _, ns in os.walk(r):
        files += [os.path.join(d, n) for n in ns if n.endswith(".md")]
for d, ds, ns in os.walk("."):
    ds[:] = [x for x in ds if x not in (".git", "node_modules", "worktrees", "target", ".venv", "venv")]
    files += [os.path.relpath(os.path.join(d, n)) for n in ns if n in ("CLAUDE.md", "CLAUDE.local.md")]
files = sorted(set(files))
def exempt(f):
    if f.startswith("docs/reviews/archive-"):
        return True
    head = "".join(open(f, errors="ignore").readlines()[:20])
    return re.search(r"(?m)^status: superseded", head) is not None
bad = []
for f in sorted(files):
    if exempt(f):
        continue
    for i, line in enumerate(open(f, errors="ignore"), 1):
        for m in re.finditer(r"(?<![<\w-])art-[a-z0-9]+(?:-[a-z0-9]+)*", line):
            if m.group(0) not in slugs:
                bad.append(f"{f}:{i}: {m.group(0)}")
for b in bad:
    print(f"FAIL: cites an article slug constitution.md does not define: {b}")
sys.exit(1 if bad else 0)
PY
then
  VIOLATIONS=1
fi

# Pin (REQ-326): a nested CLAUDE.md carrying a Roman-numeral citation, or an undefined slug, in a scratch tree fails the scans.
if [[ -z "${SLUGS_TEST_ROOT:-}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"   # rm_tree (the harness requires every EXIT trap to use it)
  SCR="$(mktemp -d)"; trap 'rm_tree "$SCR"' EXIT
  mkdir -p "$SCR/docs" "$SCR/tests/deep"; cp constitution.md "$SCR/"
  if ! SLUGS_TEST_ROOT="$SCR" bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    echo "FAIL: the scans fail a scratch tree with no violation"; VIOLATIONS=1
  fi
  printf 'See Article IV.\n' > "$SCR/tests/deep/CLAUDE.md"
  if SLUGS_TEST_ROOT="$SCR" bash "${BASH_SOURCE[0]}" >"$SCR/out" 2>&1 || ! grep -qF 'tests/deep/CLAUDE.md cites articles by Roman numeral' "$SCR/out"; then
    echo "FAIL: a nested tests/deep/CLAUDE.md citing Article IV passed the Roman-numeral scan"; VIOLATIONS=1
  fi
  printf 'See art-bogus-slug.\n' > "$SCR/tests/deep/CLAUDE.md"
  if SLUGS_TEST_ROOT="$SCR" bash "${BASH_SOURCE[0]}" >"$SCR/out" 2>&1 || ! grep -qF 'tests/deep/CLAUDE.md:1: art-bogus-slug' "$SCR/out"; then
    echo "FAIL: a nested CLAUDE.md citing an undefined slug passed the slug scan"; VIOLATIONS=1
  fi
fi

if [[ $VIOLATIONS -ne 0 ]]; then
  echo "test_reviews_use_slugs: FAILED — cite by art-<kebab> slug (art-naming-tagging)"
  exit 1
fi
echo "PASS: all docs/ and instruction-file article citations use slugs (no Roman numerals), and every cited art-* slug is defined in constitution.md"
