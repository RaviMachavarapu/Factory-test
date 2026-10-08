#!/usr/bin/env bash
# REQ-321 (R15): per-commit test-first over the PR's commits. Walks
# `git rev-list --reverse --no-merges <base>..<head>` and fails when a
# commit adds or changes a source file (under the pack's source_roots, not
# matching its test_globs or non_source) with no matching test change (the
# pack's test_first_rules, packinfo.py) in that commit or an earlier one —
# for a Rust cfg_test rule, a #[cfg(test)] hunk in the same .rs file also
# counts — or when no listed commit message and no PR body cites a
# REQ-NNN. The walk judges with the pack as committed at the base ref
# (packinfo.load_at_ref), never the PR head's, so a PR cannot widen its own
# non_source/test_globs or narrow its source_roots/test_first_rules, and
# instance-ness (.specflow.yml or .stack) is judged at the base as well; --pack
# FILE overrides both. See Interfaces "scripts/check-test-first.sh" and R15 in
# docs/plans/2026-09-27-factory-v3-2-p3-plan.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="$(pwd)"
BASE="${SPECFLOW_BASE_REF:-}"
HEAD_REV="HEAD"
PR_BODY_FILE=""
PACK_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --head) HEAD_REV="$2"; shift 2 ;;
    --pr-body-file) PR_BODY_FILE="$2"; shift 2 ;;
    --pack) PACK_FILE="$2"; shift 2 ;;
    --root) DATA_ROOT="$2"; shift 2 ;;
    *) echo "check-test-first: unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$DATA_ROOT"

python3 - "$ROOT" "$BASE" "$HEAD_REV" "$PR_BODY_FILE" "$PACK_FILE" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

lib_root, base, head, pr_body_file, pack_file = sys.argv[1:6]
sys.path.insert(0, os.path.join(lib_root, "scripts/lib/specflow"))
import packinfo  # noqa: E402

REQ_RE = re.compile(r"REQ-\d{3}")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
PIN_BUMP_GLOBS = (".github/workflows/*.yml", "stacks/*/action.yml")


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def git_out(*args):
    p = git(*args)
    if p.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {p.stderr.strip()}")
    return p.stdout


try:
    pack = packinfo.load(".", pack_file=pack_file or None)
except packinfo.PackError as e:
    die(f"check-test-first: {e}")
head_pack = pack

# Order (Interfaces): the pack, then every source root must match a tracked
# file, then the no-base SKIP, then the commit walk. With a base, the roots
# are checked against the pack that governs (the base's), after it is read.


def check_roots(p):
    missing = [r for r in p.source_roots if not git("ls-files", "--", r).stdout.strip()]
    if missing:
        die("check-test-first: source root matches no tracked file: " + ", ".join(missing))


if not base:
    check_roots(pack)
    print("SKIP test-first: no PR range (no --base and no SPECFLOW_BASE_REF — a push to main has none)")
    sys.exit(0)

if git("rev-parse", "-q", "--verify", base).returncode != 0:
    # In a PR the range must exist: an unresolvable base is an error, never a pass (PR #42 code mode). Outside
    # one (a local run with a stale ref) it stays a loud SKIP.
    in_pr = bool(os.environ.get("SPECFLOW_BASE_REF")) or bool(pr_body_file) \
        or os.environ.get("GITHUB_EVENT_NAME", "") in ("pull_request", "pull_request_target")
    if in_pr:
        die(f"check-test-first: base {base!r} does not resolve in a PR context "
            f"(SPECFLOW_BASE_REF, GITHUB_EVENT_NAME or --pr-body-file) — fetch it (fetch-depth: 0)")
    print(f"SKIP test-first: no PR range (--base {base!r} does not resolve, outside a PR)")
    sys.exit(0)

if not pack_file:
    # The policy is the base's (final-review finding 7): a PR's own edit to
    # .specflow/pack.yml or scripts/template-pack.yml takes effect after merge,
    # and so does adding or deleting .specflow.yml/.stack (PR #42: instance-ness
    # is judged at the base too).
    mismatch = packinfo.instance_mismatch_note(".", base)
    if mismatch:
        print(mismatch)
    try:
        base_pack = packinfo.load_at_ref(".", base)
    except packinfo.PackError as e:
        die(f"check-test-first: {e}")
    if base_pack is None:
        print(f"note: test-first: {base} is the template source with no scripts/template-pack.yml (the PR that adds it) — "
              f"judged with the PR's own {head_pack.origin}, not a control")
    else:
        if not packinfo.same_policy(base_pack, head_pack):
            print(f"note: test-first: judged with the base's pack ({base_pack.origin}); "
                  f"the PR's own changes to {head_pack.origin} take effect after merge")
        pack = base_pack

check_roots(pack)

commits = [l for l in git_out("rev-list", "--reverse", "--no-merges", f"{base}..{head}").splitlines() if l]


def changed_files(c):
    out = []
    for line in git_out("diff-tree", "--no-commit-id", "-r", "--no-renames", "--name-status", c).splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        out.append((parts[0][0], parts[-1]))
    return out


def file_diff(c, path):
    return git_out("diff", "-U0", f"{c}^", c, "--", path)


def post_text(c, path):
    p = git("show", f"{c}:{path}")
    return p.stdout if p.returncode == 0 else ""


def is_meaningful(line):
    s = line.strip()
    if not s:
        return False
    return not any(s.startswith(p) for p in ("#", "//", "/*", "*"))


def added_lines(diff_text):
    return [l[1:] for l in diff_text.splitlines() if l.startswith("+") and not l.startswith("+++")]


def has_meaningful_addition(diff_text):
    return any(is_meaningful(l) for l in added_lines(diff_text))


def cfg_test_ranges(text):
    # (start, end) 1-indexed inclusive line ranges of every `#[cfg(test)]`
    # module (the attribute line through the matching closing brace),
    # located by brace balance from the following `mod ... {` line.
    lines = text.splitlines()
    n = len(lines)
    ranges = []
    i = 0
    while i < n:
        if lines[i].strip() == "#[cfg(test)]":
            start = i
            j = i + 1
            while j < n and j - i <= 5 and "mod" not in lines[j]:
                j += 1
            if j < n and "mod" in lines[j] and "{" in lines[j]:
                depth, started, k = 0, False, j
                while k < n:
                    depth += lines[k].count("{") - lines[k].count("}")
                    started = started or "{" in lines[k]
                    if started and depth <= 0:
                        break
                    k += 1
                ranges.append((start + 1, min(k, n - 1) + 1))
                i = k + 1
                continue
        i += 1
    return ranges


def has_cfg_test_addition(diff_text, post):
    ranges = cfg_test_ranges(post)
    if not ranges:
        return False
    cur = None
    for line in diff_text.splitlines():
        m = HUNK_RE.match(line)
        if m:
            cur = int(m.group(1))
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            if cur is not None:
                if any(a <= cur <= b for a, b in ranges) and is_meaningful(line[1:]):
                    return True
                cur += 1
        elif line.startswith("-"):
            pass  # a removed (pre-image) line never advances the post pointer
    return False


USES_RE = re.compile(r"^(\s*(?:-\s+)?uses:\s*)([^@\s]+)@(\S+)(\s+#.*)?$")


def is_pin_bump(path, diff_text):
    # R15: a pin bump replaces each `uses: <action>@<ref>` line with the same
    # action (same indentation and step dash) at another ref, and nothing
    # else: removed and added lines pair up one to one, in order, and only
    # the ref and its trailing version comment change. A `run:` line that
    # merely mentions `uses:`, a deleted step, or a different action is not.
    if not any(packinfo.match(g, path) for g in PIN_BUMP_GLOBS):
        return False
    removed, added = [], []
    in_hunk = False
    for l in diff_text.splitlines():
        if HUNK_RE.match(l):
            in_hunk = True
            continue
        if not in_hunk:
            continue  # the diff header (diff --git, index, ---/+++ file names)
        if l.startswith("-"):
            removed.append(l[1:])
        elif l.startswith("+"):
            added.append(l[1:])
    if not removed or len(removed) != len(added):
        return False
    for old_line, new_line in zip(removed, added):
        mo, mn = USES_RE.match(old_line), USES_RE.match(new_line)
        if not mo or not mn:
            return False
        if mo.group(1) != mn.group(1) or mo.group(2) != mn.group(2):
            return False
    return True


rules_satisfied = set()
failures = []
source_change_count = 0
req_cited = False

for c in commits:
    files = changed_files(c)
    if REQ_RE.search(git_out("log", "-1", "--format=%B", c)):
        req_cited = True

    for idx, rule in enumerate(pack.rules):
        if idx in rules_satisfied:
            continue
        for status, path in files:
            if status not in ("A", "M"):
                continue
            satisfied = False
            if packinfo.is_test(pack, path) and any(packinfo.match(g, path) for g in rule.tests):
                if has_meaningful_addition(file_diff(c, path)):
                    satisfied = True
            if not satisfied and rule.cfg_test and path.endswith(".rs") and packinfo.match(rule.source, path):
                if has_cfg_test_addition(file_diff(c, path), post_text(c, path)):
                    satisfied = True
            if satisfied:
                rules_satisfied.add(idx)
                break

    for status, path in files:
        if status not in ("A", "M"):
            continue
        if not packinfo.is_source(pack, path):
            continue
        d = file_diff(c, path)
        if is_pin_bump(path, d):
            continue
        source_change_count += 1
        rule_idx = next((i for i, r in enumerate(pack.rules) if packinfo.match(r.source, path)), None)
        if rule_idx is None or rule_idx not in rules_satisfied:
            r = pack.rules[rule_idx] if rule_idx is not None else None
            tests_desc = " | ".join(r.tests + (("cfg-test",) if r and r.cfg_test else ())) if r else "?"
            src_desc = r.source if r else "?"
            sha7 = git_out("rev-parse", "--short", c).strip()
            failures.append(
                f"FAIL test-first {sha7} {path}: no matching test change in this or an earlier commit "
                f"(rule '{src_desc} -> {tests_desc}')"
            )

if source_change_count == 0:
    print("SKIP test-first: the PR touches no source file")
    sys.exit(0)

if not req_cited:
    body = ""
    if pr_body_file and os.path.isfile(pr_body_file):
        body = open(pr_body_file, encoding="utf-8").read()
    if not REQ_RE.search(body):
        failures.append("FAIL test-first: no REQ-NNN cited in any commit message or the PR body")

if failures:
    for f in failures:
        print(f)
    sys.exit(1)

print(
    f"PASS test-first: {len(commits)} commits, {source_change_count} source changes, "
    "each with a test in the same or an earlier commit; REQ cited"
)
PY
