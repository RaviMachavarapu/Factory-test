#!/usr/bin/env bash
# REQ-126: Walks docs/plans/*.md frontmatter and docs/adr/*.md frontmatter,
# exits non-zero if any [verifiable]/[verifiable-model] REQ in a plan's source spec
# lacks an accepted ADR in the plan's decisions: field whose addresses: includes it.
# art-formal-verification, art-kernel-boundary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# LINKAGE_BASE_DIR lets the fixture test point the walker at synthetic docs.
cd "${LINKAGE_BASE_DIR:-$ROOT}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 required for ANALYZE check"
  exit 2
fi

python3 - "$ROOT" <<'PY'
import os, re, sys, glob

sys.path.insert(0, os.path.join(sys.argv[1], "scripts/lib/specflow"))
from frontmatter import TAG_RE, parse_list, read

def verifiable_reqs(spec_path):
    if not os.path.exists(spec_path):
        return []
    body = open(spec_path).read()
    # Match: - **REQ-NNN:** ... [verifiable] / [verifiable-model]
    # A backtick-quoted `[verifiable]` is prose ABOUT the tag, not a tag —
    # REQ-126's own description mentions it (false-positive bug, 2026-06-09).
    return list(TAG_RE.findall(body))

# Collect ADRs
adrs = {}
for p in sorted(glob.glob("docs/adr/*.md")):
    fm, _ = read(p)
    aid = fm.get("id", "").strip()
    if not aid:
        continue
    adrs[aid] = {
        "status": fm.get("status", "").strip(),
        "addresses": parse_list(fm.get("addresses", "")),
        "path": p,
    }

# Walk plans
errors = []
checked = 0
skipped = []
for plan_path in sorted(glob.glob("docs/plans/*.md")):
    fm, _ = read(plan_path)
    spec_slug = fm.get("spec", "").strip()
    if not spec_slug:
        # No silent skips: a plan without spec: frontmatter escapes this
        # gate entirely — say so every run (2026-06-09 review, Theme 6).
        skipped.append(plan_path)
        continue
    decisions = parse_list(fm.get("decisions", ""))
    spec_path = f"docs/specs/{spec_slug}-design.md"
    if not os.path.exists(spec_path):
        errors.append(f"  {plan_path}: spec: {spec_slug} does not resolve to a file ({spec_path})")
        continue
    reqs = verifiable_reqs(spec_path)
    # implements: scopes the ADR check to the REQs this plan actually
    # delivers (REQ-380). No key at all -> walk the spec whole (demo plan is
    # grandfathered). Key present but empty (bare, "", or []) -> silent
    # opt-out, reject. An item that is not REQ-NNN is rejected individually
    # (same rule check-traceability.sh applies) rather than silently
    # narrowing scope.
    if "implements" in fm:
        implements = parse_list(fm["implements"])
        if not implements:
            errors.append(f"  {plan_path}: implements: is empty ([], bare, or \"\") — not a valid scope (silent opt-out)")
            continue
        valid_implements = []
        for item in implements:
            if not re.match(r"^REQ-\d{3}$", item):
                errors.append(f"  {plan_path}: implements: '{item}' is not REQ-NNN")
                continue
            valid_implements.append(item)
        reqs = [r for r in reqs if f"REQ-{r}" in valid_implements]
    if not reqs:
        continue
    checked += 1
    for req in reqs:
        req_id = f"REQ-{req}"
        covered = False
        for adr_id in decisions:
            adr = adrs.get(adr_id)
            if adr and adr["status"] == "accepted" and req_id in adr["addresses"]:
                covered = True
                break
        if not covered:
            errors.append(f"  {plan_path}: {req_id} not covered by any accepted ADR in decisions: {decisions}")

for p in skipped:
    print(f"SKIP (no spec: frontmatter — outside the gate): {p}")

if errors:
    print("FAIL: ADR-PLAN linkage check (REQ-126):")
    for e in errors:
        print(e)
    sys.exit(1)

print(f"PASS: ADR-PLAN linkage check (REQ-126) — {checked} plan(s) verified, {len(skipped)} skipped")
PY
