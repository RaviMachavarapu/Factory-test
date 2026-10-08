#!/usr/bin/env python3
"""The one frontmatter reader (REQ-394, REQ-380).

Lifted verbatim (behaviour, comments and REQ citations) from
`scripts/check-traceability.sh:22-69`, `scripts/analyze-adr-plan-linkage.sh:20-66`
and `scripts/lib/specflow/architecture.py:69-107`'s flat reader: the
strip-quotes / strip-comment rules REQ-380 established, the frontmatter
block reader, the inline-list reader, the tag regex and the plan-claims
walk. Those three modules import this one instead of carrying their own
copies; `scripts/check-covers.sh` does too (Task 13).

Stdlib only. Callers pass the repository root to the heredoc
(`python3 - "$ROOT" <<'PY'`) and insert `<root>/scripts/lib/specflow` into
`sys.path`, since some callers' `*_BASE_DIR` moves the cwd to fixture docs.

`config.py` and `attestation.py` keep their own copies of this reading
logic: `verifier.yml` and `run-verifier.sh` materialise each of them ALONE
from the base ref with `git show`, so an import of a sibling module in
either would break that base-ref-only run — they must stay self-contained.
"""
from __future__ import annotations

import glob
import os
import re
import subprocess
from dataclasses import dataclass


def strip_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def strip_comment(s: str) -> str:
    # Drop a trailing " #..." YAML comment: a '#' that follows whitespace,
    # or starts the value, outside of any quoted span. A '#' inside quotes,
    # or glued to a preceding non-whitespace char, is left alone.
    out = []
    in_quote = None
    prev_ws = True
    for c in s:
        if in_quote:
            out.append(c)
            if c == in_quote:
                in_quote = None
            continue
        if c in ("'", '"'):
            in_quote = c
            out.append(c)
            prev_ws = False
            continue
        if c == "#" and prev_ws:
            break
        out.append(c)
        prev_ws = c.isspace()
    return "".join(out)


def parse_text(text: str) -> dict:
    # REQ-327: strip surrounding quotes so `key: ""` parses as empty, not
    # as the two-character truthy string '""'.
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    fm: dict = {}
    if m:
        for line in m.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                fm[k.strip()] = strip_quotes(strip_comment(v.strip()))
    return fm


def read(path: str) -> tuple[dict, str]:
    text = open(path, encoding="utf-8").read()
    return parse_text(text), text


def parse_list(s: str) -> list[str]:
    s = s.strip().strip("[]")
    if not s:
        return []
    return [strip_quotes(x) for x in s.split(",") if strip_quotes(x)]


# Same tag regex as (moved verbatim from) check-traceability.sh:139-140: a
# REQ in backticks is prose about the tag, not a tag.
TAG_RE = re.compile(r"\*\*REQ-(\d{3}):?\*\*[^\n]*(?<!`)\[verifiable(?:-model)?\](?!`)")


def tagged_reqs(text: str) -> set[str]:
    return {f"REQ-{m}" for m in TAG_RE.findall(text)}


def spec_slug(path: str) -> str:
    basename = os.path.basename(path)
    if basename.endswith("-design.md"):
        return basename[: -len("-design.md")]
    return basename[: -len(".md")]


# R4 (final review): the specs every instance inherits from the template, named by slug. Grandfathering from the
# checks a spec written after v3.2 owes (REQ-389's confirmed_by:, verify-release's claimed-and-proved) is decided by
# this fixed list, never by a spec's own `created:` date, which its author writes (a backdated new spec is not
# inherited).
INHERITED_SPEC_SLUGS = ("2026-05-28-demo-greeting", "2026-09-25-factory-v3-2")


def _git_ok(root: str, *args: str) -> bool:
    try:
        return subprocess.run(["git", "-C", root, *args], capture_output=True).returncode == 0
    except OSError:
        return False


def inherited_spec(root: str, slug: str, base_ref: str | None = None) -> bool:
    """True for one of the template's own specs. When `base_ref` resolves in `root`, the spec file must also exist
    at that ref, so a PR cannot add a new spec under an inherited slug and have it grandfathered."""
    if slug not in INHERITED_SPEC_SLUGS:
        return False
    if base_ref and _git_ok(root, "rev-parse", "-q", "--verify", base_ref):
        return any(_git_ok(root, "cat-file", "-e", f"{base_ref}:docs/specs/{slug}{suffix}")
                   for suffix in ("-design.md", ".md"))
    return True


def live_specs(root: str = ".") -> dict[str, tuple[dict, str]]:
    """docs/specs/*.md whose type is not brainstorm and status is not superseded."""
    specs: dict[str, tuple[dict, str]] = {}
    for p in sorted(glob.glob(os.path.join(root, "docs/specs/*.md"))):
        fm, text = read(p)
        if fm.get("status") == "superseded":
            continue
        if fm.get("type") == "brainstorm":
            continue
        specs[spec_slug(p)] = (fm, text)
    return specs


@dataclass(frozen=True)
class Plan:
    path: str
    spec: str
    implements: list[str] | None
    created: str


@dataclass(frozen=True)
class Claims:
    implemented: set[str]
    whole_specs: set[str]
    named_specs: set[str]
    plans: list[Plan]


def claims(root: str = ".") -> Claims:
    """Walk docs/plans/*.md in sorted order.

    Lenient: `implemented` holds only well-formed REQ-NNN items (as full
    "REQ-NNN" tags); validation errors (a malformed item, an item not
    defined by the plan's own spec, an empty implements:) stay with
    check-traceability.sh and analyze-adr-plan-linkage.sh, which read
    `plans` themselves to report them.
    """
    implemented: set[str] = set()
    whole_specs: set[str] = set()
    named_specs: set[str] = set()
    plans: list[Plan] = []
    for p in sorted(glob.glob(os.path.join(root, "docs/plans/*.md"))):
        fm, _ = read(p)
        spec = fm.get("spec", "")
        if spec:
            named_specs.add(spec)
        if "implements" in fm:
            items = parse_list(fm["implements"])
            for item in items:
                if re.match(r"^REQ-\d{3}$", item):
                    implemented.add(item)
            implements: list[str] | None = items
        else:
            implements = None
            if spec:
                whole_specs.add(spec)
        plans.append(Plan(path=p, spec=spec, implements=implements, created=fm.get("created", "")))
    return Claims(implemented=implemented, whole_specs=whole_specs, named_specs=named_specs, plans=plans)
