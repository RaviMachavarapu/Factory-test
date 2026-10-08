#!/usr/bin/env bash
# Verifies constitution.md has exactly 12 articles with unique slug fields matching ^art-[a-z0-9-]+$, and (REQ-326,
# amendment C) that every article's "How to apply" names the files that enforce it — each named file exists, each
# named scripts/*.sh is executable (P7 R2(c): a module under scripts/lib/ is imported, and need only exist) — or says
# "convention (no mechanism)". Runs in the template source and in every instance (the constitution ships).
# Covers: REQ-326
set -euo pipefail
FILE="${CONSTITUTION_FILE:-constitution.md}"   # overridable so the pins below can run a scratch constitution
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
ARTICLE_COUNT=$(grep -cE '^## [IVX]+ — ' "$FILE" || true)
[[ "$ARTICLE_COUNT" == "12" ]] || { echo "FAIL: expected 12 articles, found $ARTICLE_COUNT"; exit 1; }
SLUGS=$(grep -oE '^slug: art-[a-z0-9-]+$' "$FILE" || true)
SLUG_COUNT=$(echo "$SLUGS" | grep -c '^slug:' || true)
[[ "$SLUG_COUNT" == "12" ]] || { echo "FAIL: expected 12 slug fields, found $SLUG_COUNT"; exit 1; }
DUPES=$(echo "$SLUGS" | sort | uniq -d || true)
[[ -z "$DUPES" ]] || { echo "FAIL: duplicate slugs: $DUPES"; exit 1; }
python3 - "$FILE" <<'PY' || exit 1
import os, re, sys
t = open(sys.argv[1]).read()
arts = re.split(r"(?m)^## [IVX]+ — ", t)[1:]
ROOTS = {"scripts", ".github", ".claude", "tests", "docs", "schemas", "templates", "stacks", "src", "verification"}
ROOT_FILES = {".gitignore", ".gitleaks.toml", "constitution.md", "CLAUDE.md", "README.md"}
def named(how):
    out = []
    for tok in re.findall(r"`([^`]+)`", how):
        w = tok.split()[0]
        if re.search(r"[<>*]|YYYY", w) or w.startswith("/"):
            continue
        # R2(b): directories are not files — a token ending in "/" never counts, nor one that exists as a directory;
        # any other path under a root counts, dotless ones included (.github/allowed_signers), and must exist.
        if w.endswith("/") or os.path.isdir(w):
            continue
        if w in ROOT_FILES or (w.split("/")[0] in ROOTS and "/" in w):
            out.append(w)
    return out
bad = []
for a in arts:
    slug = re.search(r"(?m)^slug: (art-[a-z0-9-]+)$", a).group(1)
    m = re.search(r"\*\*How to apply:\*\*(.*?)(?=\n---\n|\Z)", a, re.S)
    if not m:
        bad.append(f"{slug}: no How to apply"); continue
    how, files = m.group(1), named(m.group(1))
    if not files and "convention (no mechanism)" not in how:
        bad.append(f"{slug}: names no enforcing file and does not say 'convention (no mechanism)'")
    for p in files:
        if not os.path.isfile(p):
            bad.append(f"{slug}: names {p}, which does not exist")
        elif re.fullmatch(r"scripts/[^/]+\.sh", p) and not os.access(p, os.X_OK):
            bad.append(f"{slug}: {p} is not executable")
if bad:
    print("FAIL: " + "\nFAIL: ".join(bad)); sys.exit(1)
PY
# PR #60 run 1 (REQ-326): a named path with no dot in its last segment (.github/allowed_signers) is a file too, and is
# checked to exist (a directory, with or without its trailing slash, is never a named file: fix wave 1, FIX 3). Pin: a scratch constitution whose first How to apply names a missing dotless path fails.
if [[ -z "${CONSTITUTION_FILE:-}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"   # rm_tree (the harness requires every EXIT trap to use it)
  SCR="$(mktemp -d)"; trap 'rm_tree "$SCR"' EXIT
  awk '/\*\*How to apply:\*\*/ && !d {print $0 " `.github/zz_missing_dotless`"; d = 1; next} {print}' "$FILE" > "$SCR/constitution.md"
  if CONSTITUTION_FILE="$SCR/constitution.md" bash "${BASH_SOURCE[0]}" > "$SCR/out" 2>&1; then
    echo "FAIL: a scratch constitution naming a missing dotless path .github/zz_missing_dotless passed"; exit 1
  fi
  grep -qF '.github/zz_missing_dotless, which does not exist' "$SCR/out" \
    || { echo "FAIL: the missing dotless path was not named in the failure: $(cat "$SCR/out")"; exit 1; }
  # P7 Build 1 fix wave 1, FIX 3 (REQ-326; R2(b): directories are not files): a How to apply that names only directories
  # — `src/`, `docs/`, `verification/` with their slash, or an existing directory without one (`docs/security`) — names
  # no enforcing file and fails; one naming only a dotless regular file (`.github/allowed_signers`) passes.
  howto() {  # howto TEXT OUT — the constitution with its first How to apply's body replaced by TEXT
    python3 - "$FILE" "$1" "$2" <<'PYH'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"\*\*How to apply:\*\*(.*?)(?=\n---\n)", t, re.S)
open(sys.argv[3], "w").write(t[:m.start(1)] + " " + sys.argv[2] + "\n" + t[m.end(1):])
PYH
  }
  howto 'Enforced by `src/`, `docs/`, `verification/` and `docs/security`.' "$SCR/dirs.md"
  if CONSTITUTION_FILE="$SCR/dirs.md" bash "${BASH_SOURCE[0]}" > "$SCR/out" 2>&1; then
    echo "FAIL: a How to apply naming only directories (src/, docs/, verification/, docs/security) passed as naming enforcing files"; exit 1
  fi
  grep -qF "names no enforcing file" "$SCR/out" \
    || { echo "FAIL: the directories-only How to apply failed for another reason: $(cat "$SCR/out")"; exit 1; }
  howto 'Enforced by `.github/allowed_signers`.' "$SCR/dotless.md"
  CONSTITUTION_FILE="$SCR/dotless.md" bash "${BASH_SOURCE[0]}" > "$SCR/out" 2>&1 \
    || { echo "FAIL: a How to apply naming the dotless file .github/allowed_signers did not count it: $(cat "$SCR/out")"; exit 1; }
fi
echo "PASS: constitution.md has 12 articles with unique well-formed slugs; every How to apply names an existing enforcing file or says convention (no mechanism)"
