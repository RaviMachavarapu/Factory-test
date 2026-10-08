#!/usr/bin/env bash
# REQ-323 / REQ-306 / REQ-394 (R18): the repository self-check — every REQ some
# plan claims (implements:, read through frontmatter.py; a plan without
# implements: walks its spec whole) needs a test that cites it on a whole
# "# Covers: REQ-NNN" or "// Covers: REQ-NNN" line, under the pack's
# test_globs or tests/governance/ (fixtures excluded either way). Only a
# test cites: a tests/governance/test_*.sh with a check (ck), the Covers
# line above its finish (never lib/, fixtures/ or any other file there), or a
# file under the pack's test_globs with a test function (def test_, test(,
# it(, #[test], …), the Covers line in its header comment block. It proves a
# citation, not that the test exercises the REQ — code mode reads that. A
# Covers line outside tests/governance/ that cites a REQ no live spec defines is
# also an error (an instance may delete the inherited factory spec, so
# tests/governance/'s own citations of it are exempt). test_traceability.sh
# delegates its former interim check here (REQ-323).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# COVERS_BASE_DIR lets the fixture test point the walker at a synthetic
# instance (same convention as TRACE_BASE_DIR/ARCH_BASE_DIR).
cd "${COVERS_BASE_DIR:-$ROOT}"

WORK_ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) WORK_ROOT="$2"; shift 2 ;;
    *) echo "check-covers.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$WORK_ROOT"

python3 - "$ROOT" <<'PY'
import os
import re
import subprocess
import sys

WORK = os.getcwd()
sys.path.insert(0, os.path.join(sys.argv[1], "scripts/lib/specflow"))
from frontmatter import claims, live_specs  # noqa: E402
import packinfo  # noqa: E402

# The "defined" set is every bolded "- **REQ-NNN**" list item, [verifiable*]
# tag or not (check-traceability.sh's own "defined" set): a REQ with no
# verification tag is still a REQ a spec defines, and a stray Covers line
# citing an undefined number is the typo this half of the check catches.
DEFINED_RE = re.compile(r"-\s+\*\*REQ-(\d{3}):?\*\*")

try:
    pack = packinfo.load(WORK)
except packinfo.PackError as e:
    print(f"ERROR check-covers: {e}")
    sys.exit(2)

# --- What is owed: every REQ some plan claims, by frontmatter.claims() ---
specs = live_specs(WORK)
defined = set()
for _slug, (_fm, text) in specs.items():
    defined |= {f"REQ-{n}" for n in DEFINED_RE.findall(text)}

owed = {}  # REQ-NNN -> the plan path that first claims it
for plan in claims(WORK).plans:
    if plan.implements is None:
        entry = specs.get(plan.spec)
        if entry is None:
            continue
        _fm, text = entry
        for n in DEFINED_RE.findall(text):
            owed.setdefault(f"REQ-{n}", plan.path)
    else:
        for item in plan.implements:
            if re.match(r"^REQ-\d{3}$", item):
                owed.setdefault(item, plan.path)

# --- Walk every tracked file for a whole '# Covers:' / '// Covers:' line ---
COVERS_RE = re.compile(r"^\s*(?:#|//)\s*Covers:\s*(REQ-\d{3}(?:\s*,\s*REQ-\d{3})*)\s*$")
SKIP_DIRS = {".git", "node_modules", "target", ".venv", "build", "dist"}


def walk_files(root):
    # A git checkout lists its tracked files; os.path.exists, not isdir, so a worktree (whose .git is a file)
    # counts too and never picks up untracked files (PR #42 code mode).
    if os.path.exists(os.path.join(root, ".git")):
        out = subprocess.run(
            ["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True
        ).stdout
        for rel in out.splitlines():
            if os.path.isfile(os.path.join(root, rel)):
                yield rel
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fname in filenames:
            fpath = os.path.join(dirpath, fname)
            yield os.path.relpath(fpath, root)


GOV_TEST_RE = re.compile(r"^tests/governance/test_[^/]*\.sh$")


def is_covering_location(posix_rel):
    """tests/governance/test_*.sh, plus the pack's test_globs outside
    tests/governance/ (R18; final review): a fixture, the harness under
    lib/, or any other file under tests/governance/ cites nothing, even when
    a pack (like the template's) lists fixtures/** or lib/** in its own
    test_globs (REQ-321's sense of "test", not REQ-323's)."""
    if posix_rel.startswith("tests/governance/"):
        return bool(GOV_TEST_RE.match(posix_rel))
    return packinfo.is_test(pack, posix_rel)


GOV_CHECK_RE = re.compile(r"(^|[\s;&|({])(ck|fail)\s|\bexit\s+[1-9]")  # a check that can fail
FINISH_RE = re.compile(r"^\s*finish\b")
TEST_FN_RE = re.compile(
    r"^\s*(async\s+)?def\s+test_|^\s*class\s+Test"          # python
    r"|\b(test|it|testWidgets)(\.\w+)?\s*\("                 # vitest/jest/dart
    r"|#\[(\w+::)*test\b"                                    # rust
    r"|(^|[\s;&|({])ck\s"                                     # a governance-style shell check
)


def _is_comment_or_blank(line):
    s = line.strip()
    return not s or s.startswith(("#", "//", "/*", "*"))


def citing_lines(posix_rel, lines):
    """The 0-based indexes of the lines that may cite: in a governance
    test with a check (ck, fail, or an exit 1 path), every line above its
    finish (the whole file for an older test with no finish); in a pack test file
    with a test function, the leading comment block (before the first
    non-comment, non-blank line). A file that tests nothing cites nothing."""
    code = [l for l in lines if not _is_comment_or_blank(l)]
    if GOV_TEST_RE.match(posix_rel):
        if not any(GOV_CHECK_RE.search(l) for l in code):
            return range(0)
        fin = next((i for i, l in enumerate(lines) if FINISH_RE.match(l)), None)
        return range(len(lines) if fin is None else fin)
    if not any(TEST_FN_RE.search(l) for l in code):
        return range(0)
    end = next((i for i, l in enumerate(lines) if not _is_comment_or_blank(l)), len(lines))
    return range(end)


errors = []
covered = set()

for rel in walk_files(WORK):
    posix_rel = rel.replace(os.sep, "/")
    if not is_covering_location(posix_rel):
        continue
    fpath = os.path.join(WORK, rel)
    try:
        lines = open(fpath, encoding="utf-8", errors="ignore").readlines()
    except OSError:
        continue
    under_governance = posix_rel.startswith("tests/governance/")
    allowed = citing_lines(posix_rel, lines)
    for i, line in enumerate(lines, start=1):
        m = COVERS_RE.match(line.rstrip("\n"))
        if not m:
            continue
        reqs = [f"REQ-{n}" for n in re.findall(r"REQ-(\d{3})", m.group(1))]
        for req in reqs:
            if (i - 1) in allowed:
                covered.add(req)
            # REQ-306: with no live spec left at all (every example removed),
            # there is no REQ inventory to check a citation against — the
            # dangling check is then vacuous, not a FAIL over stale test files.
            if specs and not under_governance and req not in defined:
                errors.append(f"{posix_rel}:{i}: cites {req}, which no live spec defines")

for req in sorted(owed):
    if req not in covered:
        plan_rel = os.path.relpath(owed[req], WORK)
        errors.append(
            f"{req} (claimed by {plan_rel}) — no test cites it "
            f"(# Covers: / // Covers: under the pack's test_globs or tests/governance/)"
        )

if errors:
    print("FAIL: check-covers:")
    for e in sorted(errors):
        print("  -", e)
    sys.exit(1)

print(f"PASS: check-covers — {len(owed)} claimed REQs, each cited by a test")
PY
