#!/usr/bin/env bash
# Mechanical traceability checker (P3 of the 2026-06-09 review).
# Walks the chain the constitution promises is walkable
# (art-naming-tagging, art-specification-primacy, art-formal-verification):
#   - REQ IDs defined at most once across live (non-superseded) specs
#   - ADR ids unique; SEC ids unique
#   - every [verifiable]/[verifiable-model] REQ that a plan implements
#     (implements:, or a plan without the field walks its spec whole) has a
#     Dafny proof carrying a matching "// Proves:" header
#   - no proof cites a REQ that no live spec defines
#     (verification/example.dfy is the documented placeholder — exempt)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# TRACE_BASE_DIR lets the fixture test point the walker at synthetic docs
# (same convention as LINKAGE_BASE_DIR in analyze-adr-plan-linkage.sh).
cd "${TRACE_BASE_DIR:-$ROOT}"

python3 - "$ROOT" <<'PY'
import glob, os, re, sys
from pathlib import Path

sys.path.insert(0, os.path.join(sys.argv[1], "scripts/lib/specflow"))
from frontmatter import TAG_RE, parse_list, read
import blocks
import config

errors = []

# --- Spec inventory -------------------------------------------------------
live_specs, defined = {}, {}
for p in sorted(glob.glob("docs/specs/*.md")):
    fm, text = read(p)
    if fm.get("status") == "superseded":
        continue
    if fm.get("type") == "brainstorm":
        continue  # brainstorm notes are not live specs (not a REQ source)
    live_specs[p] = (fm, text)
    for req in set(re.findall(r"-\s+\*\*REQ-(\d{3}):?\*\*", text)):
        defined.setdefault(req, []).append(p)

for req, files in sorted(defined.items()):
    if len(set(files)) > 1:
        errors.append(f"REQ-{req} defined in multiple live specs: {sorted(set(files))}")

# --- Plan-scoped proof obligations (REQ-327, REQ-380) --------------------
# A proof is owed only once a tagged REQ is actually implemented: named in
# some plan's implements:, or its whole spec is walked because a plan has
# no implements: field (grandfathered whole-spec plans, e.g. the demo).
# implements: present but empty is a silent opt-out — reject it.
implemented, walked_whole_specs = set(), set()
for p in sorted(glob.glob("docs/plans/*.md")):
    fm, _ = read(p)
    if "implements" in fm:
        implements = parse_list(fm["implements"])
        if not implements:
            errors.append(f"{p}: implements: is empty ([], bare, or \"\") — not a valid scope (silent opt-out)")
            continue
        plan_spec_path = f"docs/specs/{fm.get('spec', '')}-design.md"
        for item in implements:
            m = re.match(r"^REQ-(\d{3})$", item)
            if not m:
                errors.append(f"{p}: implements: '{item}' is not REQ-NNN")
                continue
            num = m.group(1)
            if num not in defined:
                errors.append(f"{p}: implements: REQ-{num}, which no live spec defines")
                continue
            if plan_spec_path not in defined[num]:
                errors.append(f"{p}: implements: REQ-{num} is not defined in this plan's spec ({fm.get('spec','')})")
                continue
            implemented.add(num)
    else:
        spec_slug = fm.get("spec", "")
        if spec_slug:
            walked_whole_specs.add(spec_slug)

# --- Verifiable REQs need proofs -----------------------------------------
proves = {}
for p in sorted(glob.glob("verification/**/*.dfy", recursive=True)):
    if p == "verification/example.dfy":
        continue
    head = "".join(open(p).readlines()[:5])
    for req in re.findall(r"Proves: REQ-(\d{3})", head):
        proves.setdefault(req, []).append(p)

for spec, (fm, text) in live_specs.items():
    if fm.get("extended_by"):
        continue  # the extending spec is the live tip
    basename = os.path.basename(spec)
    if basename.endswith("-design.md"):
        slug = basename[:-len("-design.md")]
    else:
        slug = basename[:-len(".md")]
    owed = slug in walked_whole_specs
    for req in TAG_RE.findall(text):
        if not (owed or req in implemented):
            continue  # not yet implemented by any plan — no proof owed yet
        if req not in proves:
            errors.append(f"REQ-{req} ({spec}) is [verifiable*] and implemented but no proof carries 'Proves: REQ-{req}'")

# --- Dangling proof references --------------------------------------------
for req, files in sorted(proves.items()):
    if req not in defined:
        errors.append(f"proof(s) {files} prove REQ-{req}, which no live spec defines")

# --- ADR / SEC id uniqueness ----------------------------------------------
seen = {}
for p in sorted(glob.glob("docs/adr/*.md")):
    fm, _ = read(p)
    aid = fm.get("id", "")
    if aid:
        if aid in seen:
            errors.append(f"duplicate ADR id {aid}: {seen[aid]} and {p}")
        seen[aid] = p

sec_seen = {}
# A SEC id is *defined* by a finding block with no `carried_from:` key (a
# later review's suppressions-table row citing it, or a re-listed
# `carried_from:` finding, is a reference, not a redefinition — Task 11 of
# the P4 plan, R6 of P3). A `carried_from:` block is exempt only when an
# earlier version's review defines the same id without one; otherwise it
# counts as a definition. A review that cannot be read (an unterminated
# block, an unparsable block) is an error, never skipped (fail closed).
sec_blocks = []  # (version or None, SEC number, carried, path)
for p in sorted(glob.glob("docs/security/*-review.md")):
    ver = blocks.filename_version(Path(p), "review")
    try:
        for blk in blocks.split_blocks(open(p).read(), p):
            try:
                fields = config.parse(blk.body)
            except config.ConfigError as e:
                errors.append(f"{p}:{blk.line}: unparsable block ({e}); its SEC ids cannot be checked for uniqueness")
                continue
            m = re.match(r"^SEC-(\d{3})$", fields.get("id", ""))
            if m:
                sec_blocks.append((ver, m.group(1), "carried_from" in fields, p))
    except blocks.BlockError as e:
        errors.append(f"{e}; its SEC ids cannot be checked for uniqueness")
fresh = [(v, n) for v, n, carried, _p in sec_blocks if not carried]
for ver, num, carried, p in sec_blocks:
    if carried and ver is not None and any(
        fv is not None and fn == num and blocks.version_key(fv) < blocks.version_key(ver) for fv, fn in fresh
    ):
        continue
    sec_seen.setdefault(num, set()).add(p)
for sec, files in sec_seen.items():
    if len(files) > 1:
        errors.append(f"SEC-{sec} is defined in multiple reviews: {sorted(files)}")

if errors:
    print("FAIL: traceability check:")
    for e in errors:
        print("  -", e)
    sys.exit(1)

n_ver = sum(1 for s,(fm,t) in live_specs.items()
            for _ in TAG_RE.findall(t))
print(f"PASS: traceability — {len(defined)} REQs across {len(live_specs)} live specs, "
      f"{len(proves)} proven, {len(implemented)} claimed by plans, no duplicates or dangling references")
PY
