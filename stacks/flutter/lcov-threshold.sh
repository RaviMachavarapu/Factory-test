#!/usr/bin/env bash
# stacks/flutter/lcov-threshold.sh LCOV MIN [--exclude PATH]... — REQ-325's lcov line-coverage
# floor. Sums DA:<line>,<hits> records per SF: file (paths normalised relative to the cwd),
# skipping any file named by a repeated --exclude. Prints "PASS coverage <x.y>% of <n> lines
# (min <MIN>%)" or "FAIL coverage <x.y>% of <n> lines, below min <MIN>%", each noting the
# excluded files when any were given. Exit 0 (>= MIN), 1 (< MIN), 2 (an unreadable file, no SF:
# record, or a MIN outside 0-100). stdlib python3 only; run by gates.sh, never in a test (the
# test stubs an lcov file directly).
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: lcov-threshold.sh LCOV MIN [--exclude PATH]..." >&2
  exit 2
fi
LCOV="$1"; MIN="$2"; shift 2

case "$MIN" in
  ''|*[!0-9]*)
    echo "lcov-threshold.sh: MIN must be an integer 0-100, got: $MIN" >&2
    exit 2
    ;;
esac
if [ "$MIN" -gt 100 ]; then
  echo "lcov-threshold.sh: MIN must be an integer 0-100, got: $MIN" >&2
  exit 2
fi
if [ ! -r "$LCOV" ]; then
  echo "lcov-threshold.sh: cannot read $LCOV" >&2
  exit 2
fi

python3 - "$LCOV" "$MIN" "$@" <<'PY'
import sys

lcov_path, minimum = sys.argv[1], int(sys.argv[2])
rest = sys.argv[3:]

excludes = set()
i = 0
while i < len(rest):
    if rest[i] == "--exclude" and i + 1 < len(rest):
        excludes.add(rest[i + 1])
        i += 2
    else:
        print(f"lcov-threshold.sh: unknown argument: {rest[i]}", file=sys.stderr)
        sys.exit(2)

with open(lcov_path) as f:
    text = f.read()

saw_sf = False
current_excluded = False
hit = 0
found = 0
for line in text.splitlines():
    if line.startswith("SF:"):
        saw_sf = True
        current_excluded = line[3:].strip() in excludes
    elif line.startswith("DA:") and not current_excluded:
        _, rest_da = line.split(":", 1)
        _, hits = rest_da.split(",", 1)
        found += 1
        if int(hits) > 0:
            hit += 1

if not saw_sf:
    print(f"lcov-threshold.sh: no SF: record in {lcov_path}", file=sys.stderr)
    sys.exit(2)

pct = (hit / found * 100.0) if found else 0.0
note = f" (excluding {', '.join(sorted(excludes))})" if excludes else ""
if pct >= minimum:
    print(f"PASS coverage {pct:.1f}% of {found} lines (min {minimum}%){note}")
    sys.exit(0)
else:
    print(f"FAIL coverage {pct:.1f}% of {found} lines, below min {minimum}%{note}")
    sys.exit(1)
PY
