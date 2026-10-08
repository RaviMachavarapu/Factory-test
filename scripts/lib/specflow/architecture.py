#!/usr/bin/env python3
"""The ARCHITECTURE exit-gate checker (REQ-333; `.claude/rules/review-gate.md`).

For every live spec (`status` != `superseded`, `type` != `brainstorm`) that
some plan names in its `spec:` field, or whose
`docs/architecture/<slug>-threat-model.md` or `<slug>-overview.md` exists
(the regulated path's `phase/arch-<slug>` PR, which has no plan yet), checks:

  (a) every `[verifiable]`/`[verifiable-model]` REQ the spec tags appears in
      some `docs/architecture/<slug>-overview.md` `kernel_modules[].req_map`
      (`art-kernel-boundary`);
  (b) `docs/architecture/<slug>-threat-model.md` exists, with >= 1 trust
      boundary, >= 1 asset whose `cia` has `c`, `i`, `a` each in {L, M, H},
      and >= 1 STRIDE letter in `stride_per_element` for every
      `dataflow_elements` entry with `external: true`;
  (c) its `## Domain checklist (REQ-333)` table answers all ten domains,
      each with a `dfe-N[, dfe-M]…` citation (naming an id that exists in
      the frontmatter) or `N/A because …` (>= 10 characters of reason).

Spec and plan frontmatter is read with the same flat, single-level
`key: value` reader `check-traceability.sh` uses (comments and quoting
handled the same way) — those documents are prose, not the nested shape
this module parses. Architecture documents (`*-overview.md`,
`*-threat-model.md`) carry a richer, but still narrow, YAML subset: scalars,
`key: []`/`key: [a, b]` inline lists, `key: {a: b, c: d}` inline maps, block
lists of maps (`key:` then `  - k: v` items with `    k: v` continuation
lines), nested block maps of scalars/inline-lists (`key:` then `  k: v`
lines), blank lines, and full-line `#` comments. Anything else is a parse
error (fail closed, exit 2) — this module never guesses.
"""
from __future__ import annotations

import glob
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from frontmatter import TAG_RE, claims, inherited_spec, live_specs, parse_list, read, strip_quotes  # noqa: E402
import config  # noqa: E402

DOMAINS = [
    "Authentication",
    "Authorization",
    "Session",
    "PII and retention",
    "Payments",
    "Secrets at rest",
    "Sensitive logging",
    "Rate limiting",
    "Third-party integrations",
    "Update channel for apps",
]

CIA_LEVELS = {"L", "M", "H"}

DFE_ANSWER_RE = re.compile(r"^(dfe-\d+(?:,\s*dfe-\d+)*)(?::|;|,|$)")
NA_ANSWER_RE = re.compile(r"^N/A because (.{10,})$", re.DOTALL)


class DocError(Exception):
    """A document could not be read: missing YAML frontmatter, or syntax
    outside the documented subset. Callers treat this as exit 2."""


# Flat frontmatter (specs and plans — the same convention
# check-traceability.sh uses) is read with frontmatter.py's TAG_RE,
# live_specs and claims, imported above.


# ------------------------------------------------------- rich YAML subset
# (architecture documents only — see the module docstring for the subset)

def _is_skippable(line: str) -> bool:
    s = line.strip()
    return s == "" or s.startswith("#")


def _split_kv(s: str, path: str) -> tuple[str, str]:
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$", s)
    if not m:
        raise DocError(f"{path}: unrecognised line in the documented subset: {s!r}")
    return m.group(1), m.group(2).rstrip()


def _parse_atom(v: str):
    v = v.strip()
    if v in ("true", "false"):
        return v == "true"
    return strip_quotes(v)


def _parse_value(v: str, path: str):
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        return [] if not inner else [_parse_atom(x) for x in inner.split(",")]
    if v.startswith("{") and v.endswith("}"):
        inner = v[1:-1].strip()
        d: dict = {}
        if inner:
            for pair in inner.split(","):
                if ":" not in pair:
                    raise DocError(f"{path}: unrecognised inline map entry: {pair!r}")
                pk, pv = pair.split(":", 1)
                d[pk.strip()] = _parse_atom(pv)
        return d
    if v[:1] in ("!", "&", "*", "|", ">", "@", "%") or v == "":
        raise DocError(f"{path}: unsupported YAML syntax outside the documented subset: {v!r}")
    return _parse_atom(v)


def _parse_block_list(lines: list[str], path: str) -> list[dict]:
    items: list[dict] = []
    cur: dict | None = None
    for raw in lines:
        indent = len(raw) - len(raw.lstrip(" "))
        content = raw.strip()
        if indent == 2 and content.startswith("- "):
            if cur is not None:
                items.append(cur)
            cur = {}
            k, v = _split_kv(content[2:], path)
            cur[k] = _parse_value(v, path)
        elif indent == 4 and cur is not None:
            k, v = _split_kv(content, path)
            cur[k] = _parse_value(v, path)
        else:
            raise DocError(f"{path}: unexpected line in a block list of maps: {raw!r}")
    if cur is not None:
        items.append(cur)
    return items


def _parse_block_map(lines: list[str], path: str) -> dict:
    d: dict = {}
    for raw in lines:
        indent = len(raw) - len(raw.lstrip(" "))
        if indent != 2:
            raise DocError(f"{path}: unexpected line in a nested block map: {raw!r}")
        k, v = _split_kv(raw.strip(), path)
        d[k] = _parse_value(v, path)
    return d


def rich_frontmatter(path: str) -> dict:
    """Parse the documented subset (see the module docstring). Raises
    DocError on anything else — fail closed."""
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        raise DocError(f"{path}: no YAML frontmatter block")
    lines = m.group(1).split("\n")
    fm: dict = {}
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if _is_skippable(line):
            i += 1
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent != 0:
            raise DocError(f"{path}: unexpected top-level indentation: {line!r}")
        key, rest = _split_kv(line, path)
        i += 1
        if rest != "":
            fm[key] = _parse_value(rest, path)
            continue
        nested: list[str] = []
        while i < n:
            nl = lines[i]
            if _is_skippable(nl):
                i += 1
                continue
            nindent = len(nl) - len(nl.lstrip(" "))
            if nindent == 0:
                break
            nested.append(nl)
            i += 1
        if not nested:
            fm[key] = None
            continue
        fm[key] = _parse_block_list(nested, path) if nested[0].strip().startswith("- ") else _parse_block_map(nested, path)
    return fm


# ----------------------------------------------------------- the checklist

def _checklist_answers(text: str) -> dict[str, str] | None:
    m = re.search(r"^## Domain checklist \(REQ-333\)\s*$", text, re.MULTILINE)
    if not m:
        return None
    rest = text[m.end():]
    stop = re.search(r"^## ", rest, re.MULTILINE)
    body = rest[:stop.start()] if stop else rest
    answers: dict[str, str] = {}
    for line in body.splitlines():
        row = re.match(r"^\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*$", line)
        if not row:
            continue
        domain, answer = row.group(1), row.group(2)
        if domain in ("Domain", "---") or set(domain) <= {"-"}:
            continue
        answers[domain] = answer
    return answers


def _check_checklist(tm_path: str, text: str, dfe_ids: set[str], errors: list[str]) -> None:
    answers = _checklist_answers(text)
    if answers is None:
        errors.append(f"{tm_path}: missing '## Domain checklist (REQ-333)' section")
        return
    for domain in DOMAINS:
        if domain not in answers:
            errors.append(f"{tm_path}: missing checklist row: {domain}")
            continue
        answer = answers[domain]
        dm = DFE_ANSWER_RE.match(answer)
        if dm:
            for did in [x.strip() for x in dm.group(1).split(",")]:
                if did not in dfe_ids:
                    errors.append(f"{tm_path}: checklist row '{domain}' cites unknown element {did}")
            continue
        if NA_ANSWER_RE.match(answer):
            continue
        errors.append(
            f"{tm_path}: checklist row '{domain}' answer {answer!r} is neither 'dfe-N…' nor 'N/A because …'"
        )


def _check_threat_model(tm_path: str, errors: list[str]) -> set[str]:
    if not os.path.exists(tm_path):
        errors.append(f"{tm_path}: missing")
        return set()
    fm = rich_frontmatter(tm_path)
    text = open(tm_path, encoding="utf-8").read()

    trust_boundaries = fm.get("trust_boundaries") or []
    if not trust_boundaries:
        errors.append(f"{tm_path}: no trust boundary")

    assets = fm.get("assets") or []
    full_cia = False
    for a in assets:
        cia = a.get("cia") if isinstance(a, dict) else None
        if isinstance(cia, dict) and all(cia.get(k) in CIA_LEVELS for k in ("c", "i", "a")):
            full_cia = True
            break
    if not full_cia:
        errors.append(f"{tm_path}: no asset with a full CIA rating (c, i, a each L/M/H)")

    dfes = fm.get("dataflow_elements") or []
    dfe_ids = {d.get("id") for d in dfes if isinstance(d, dict) and d.get("id")}
    stride = fm.get("stride_per_element") or {}
    for d in dfes:
        if not isinstance(d, dict) or not d.get("external"):
            continue
        did = d.get("id")
        letters = stride.get(did) or []
        if not letters:
            errors.append(f"{tm_path}: external element {did} has no STRIDE letter in stride_per_element")

    _check_checklist(tm_path, text, dfe_ids, errors)
    return dfe_ids


def _check_overview(ov_path: str, req_ids: set[str], errors: list[str]) -> None:
    if not req_ids:
        return
    if not os.path.exists(ov_path):
        errors.append(f"{ov_path}: missing (needed to map {sorted(req_ids)})")
        return
    fm = rich_frontmatter(ov_path)
    mapped: set[str] = set()
    for km in fm.get("kernel_modules") or []:
        if isinstance(km, dict):
            mapped.update(km.get("req_map") or [])
    for req in sorted(req_ids):
        if f"REQ-{req}" not in mapped:
            errors.append(f"{ov_path}: REQ-{req} is [verifiable*] but appears in no kernel_modules[].req_map")


def _req_map_obligation(slug: str, req_ids: set[str], plans) -> set[str]:
    """R3: the req_map obligation for a spec's [verifiable*] REQs (REQ-NNN
    bare digit ids), scoped to what plans claim.

    - No plan names the spec yet (the ARCHITECTURE PR): every tagged REQ.
    - A plan without implements: walks its spec whole: every tagged REQ.
    - A plan with implements: contributes the tagged REQs it claims.
    The obligation is the union across every plan naming this spec.
    """
    plans_for_slug = [p for p in plans if p.spec == slug]
    if not plans_for_slug:
        return set(req_ids)
    req_full = {f"REQ-{r}" for r in req_ids}
    obligation_full: set[str] = set()
    for p in plans_for_slug:
        if p.implements is None:
            obligation_full |= req_full
        else:
            claimed_full = {i if i.startswith("REQ-") else f"REQ-{i}" for i in p.implements}
            obligation_full |= (req_full & claimed_full)
    return {f[len("REQ-"):] for f in obligation_full}


def _base_ref(root: str) -> str | None:
    """SPECFLOW_BASE_REF when it resolves in `root` (CI's PR base), else None."""
    ref = os.environ.get("SPECFLOW_BASE_REF")
    if not ref:
        return None
    p = subprocess.run(["git", "-C", root, "rev-parse", "-q", "--verify", ref], capture_output=True)
    return ref if p.returncode == 0 else None


def _guided_profile(root: str) -> bool:
    """R4: guided when .specflow.yml's profile (or config.DEFAULTS' value,
    absent the key) is 'guided'. In CI the file is read at the base ref
    (SPECFLOW_BASE_REF), as the verifier's classifier reads its policy keys,
    so a PR cannot flip its own profile to escape the check (dfe-6); a base
    with no .specflow.yml, or no base, falls back to the working tree. Inert
    (False) in the template source, which has no .specflow.yml."""
    ref = _base_ref(root)
    if ref is not None:
        p = subprocess.run(["git", "-C", root, "show", f"{ref}:.specflow.yml"], capture_output=True, text=True)
        if p.returncode == 0:
            cfg = config.parse(p.stdout)
            return cfg.get("profile", config.DEFAULTS["profile"]) == "guided"
    if not os.path.exists(os.path.join(root, ".specflow.yml")):
        return False
    cfg = config.load(root)
    return cfg.get("profile", config.DEFAULTS["profile"]) == "guided"


def _missing_confirmed_by(fm: dict) -> bool:
    return not (fm.get("confirmed_by") or "").strip()


def _check_confirmed_by(root: str, slug: str, req_ids: set[str], ov_path: str, tm_path: str, errors: list[str]) -> None:
    if not _guided_profile(root):
        return
    if inherited_spec(root, slug, _base_ref(root)):
        return  # R4: one of the template's own specs, which every instance inherits
    for path in (ov_path, tm_path):
        if os.path.exists(path) and _missing_confirmed_by(rich_frontmatter(path)):
            errors.append(f"{path}: confirmed_by: missing or empty (profile: guided, REQ-389)")
    req_full = {f"REQ-{r}" for r in req_ids}
    for adr_path in sorted(glob.glob(os.path.join(root, "docs/adr/*.md"))):
        adr_fm, _ = read(adr_path)
        addressed = {a if a.startswith("REQ-") else f"REQ-{a}" for a in parse_list(adr_fm.get("addresses", ""))}
        if not (addressed & req_full):
            continue
        if _missing_confirmed_by(adr_fm):
            errors.append(f"{adr_path}: confirmed_by: missing or empty (profile: guided, REQ-389)")


def check(root: str = ".") -> int:
    specs = live_specs(root)
    c = claims(root)
    named_slugs = c.named_specs

    errors: list[str] = []
    claimed_checked: set[str] = set()
    try:
        for slug, (fm, text) in specs.items():
            ov_path = os.path.join(root, f"docs/architecture/{slug}-overview.md")
            tm_path = os.path.join(root, f"docs/architecture/{slug}-threat-model.md")
            if slug not in named_slugs and not (os.path.exists(ov_path) or os.path.exists(tm_path)):
                continue  # SPECIFY: no plan and no architecture document yet
            req_ids = {m for m in TAG_RE.findall(text)}
            obligation = _req_map_obligation(slug, req_ids, c.plans)
            claimed_checked |= obligation
            _check_overview(ov_path, obligation, errors)
            _check_threat_model(tm_path, errors)
            _check_confirmed_by(root, slug, req_ids, ov_path, tm_path, errors)
    except DocError as e:
        print(str(e))
        return 2

    if errors:
        for e in errors:
            print(e)
        return 1
    print(f"PASS: check-architecture — {len(specs)} live specs, {len(named_slugs)} named by a plan, {len(claimed_checked)} claimed [verifiable*] REQs checked")
    return 0


def main(argv=None) -> None:
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] != "check":
        print(f"architecture.py: unknown subcommand {argv[0]!r}", file=sys.stderr)
        sys.exit(2)
    sys.exit(check())


if __name__ == "__main__":
    main()
