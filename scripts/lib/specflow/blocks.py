#!/usr/bin/env python3
"""scripts/lib/specflow/blocks.py — the one parser of `---`-fenced blocks in
`docs/security/*-review.md` and `*-disposition.md` (REQ-322, REQ-332, R5).

The schema is documented in `schemas/security-disposition-template.md`. Two
modes share this one parser:

- **floor mode** (P4's behaviour, kept): a schema header is optional, and
  `latest_entries` reads only disposition files, for the suppression scan
  and the expiry notice. `floor.py` imports this module and keeps no
  reader of its own.
- **gate mode** (`check(review_path, disposition_path)`; the disposition
  gate and `verify-release.sh`): the header is required, ids are unique
  per current file, and an accepted/deferred entry joined to a
  medium-or-above finding must carry `owner:` and `expiry:`.

Both modes share one latest-entry reduction (`latest_entries`): the higher
version wins, and within one file the later block wins.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import config  # noqa: E402  (after sys.path insert)
import cvss4  # noqa: E402

FILENAME_RE_TMPL = r"^(?P<ver>\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)-{kind}\.md$"

FINDING_KEYS = {"id", "severity", "cvss_vector", "cite", "affects", "carried_from"}
FINDING_REQUIRED = {"id", "severity", "cvss_vector", "cite", "affects"}
ENTRY_KEYS = {
    "id", "status", "owner", "expiry", "rationale",
    "reclassified_by", "suppresses", "inherited",
}
ENTRY_REQUIRED = {"id", "status"}
STATUSES = {"open", "fixed", "accepted", "deferred"}
SEVERITIES = {"critical", "high", "medium", "low"}
SCHEMA_ID = "specflow-security/1"
MEDIUM_UP = {"medium", "high", "critical"}


class BlockError(ValueError):
    """A review or disposition block is malformed. `.rel`, `.line`,
    `.message` — `str()` is `"<rel>:<line>: <message>"`."""

    def __init__(self, rel: str, line: int, message: str):
        self.rel = rel
        self.line = line
        self.message = message
        super().__init__(f"{rel}:{line}: {message}")


@dataclass(frozen=True)
class Block:
    line: int
    body: str


@dataclass(frozen=True)
class Header:
    schema: str
    kind: str
    version: str
    line: int


@dataclass(frozen=True)
class FindingBlock:
    id: str
    severity: str
    cvss_vector: str
    cite: list
    affects: list
    carried_from: str | None
    line: int


@dataclass(frozen=True)
class EntryBlock:
    id: str
    status: str
    owner: str
    expiry: str | None
    rationale: str
    reclassified_by: str | None
    suppresses: list
    inherited: str | None
    line: int


@dataclass(frozen=True)
class Review:
    header: Header | None
    findings: list = field(default_factory=list)


@dataclass(frozen=True)
class Disposition:
    header: Header | None
    entries: list = field(default_factory=list)


@dataclass(frozen=True)
class Latest:
    entry: EntryBlock
    version: str
    path: Path
    line: int


# ------------------------------------------------------------- splitting

def split_blocks(text: str, rel: str) -> list[Block]:
    """Split `text` into its `---`-fenced block bodies, each with the
    1-based line number of its opening fence. An opening fence with no
    closing fence raises `BlockError` (fail closed: P4's text,
    "unterminated disposition block")."""
    lines = text.splitlines()
    blocks: list[Block] = []
    i, n = 0, len(lines)
    while i < n:
        if lines[i].strip() == "---":
            j = i + 1
            body_lines = []
            while j < n and lines[j].strip() != "---":
                body_lines.append(lines[j])
                j += 1
            if j >= n:
                raise BlockError(rel, i + 1, "unterminated disposition block")
            blocks.append(Block(i + 1, "\n".join(body_lines)))
            i = j + 1
            continue
        i += 1
    return blocks


def version_key(v: str):
    """Sort key for a `MAJOR.MINOR.PATCH[-pre]` version: numeric release
    triple, then a pre-release sorts before its release
    (`0.0.0-skeleton` < `0.0.1-demo` < `0.9.0` < `0.10.0`)."""
    main, _, pre = v.partition("-")
    parts = tuple(int(p) if p.isdigit() else p for p in main.split("."))
    return (parts, 0 if pre == "" else -1, pre)


def parse_inline_list(s: str) -> list[str]:
    """Parse a flat `[a, "b, c", d]` inline list. An item holding a comma,
    a quote, a space or a `#` is a double-quoted JSON string; other items
    are split on commas and stripped (moved from floor.py, P4 H4)."""
    import json

    s = s.strip()
    if not (s.startswith("[") and s.endswith("]")):
        return []
    inner = s[1:-1]
    tokens: list[str] = []
    buf = ""
    in_str = False
    i = 0
    while i < len(inner):
        c = inner[i]
        if in_str:
            buf += c
            if c == '"' and (i == 0 or inner[i - 1] != "\\"):
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            buf += c
            i += 1
            continue
        if c == ",":
            tokens.append(buf)
            buf = ""
            i += 1
            continue
        buf += c
        i += 1
    if buf.strip():
        tokens.append(buf)
    out = []
    for tok in tokens:
        tok = tok.strip()
        if not tok:
            continue
        if tok.startswith('"') and tok.endswith('"'):
            try:
                out.append(json.loads(tok))
                continue
            except json.JSONDecodeError:
                pass
        out.append(tok)
    return out


def filename_version(path: Path, kind: str) -> str | None:
    import re

    m = re.match(FILENAME_RE_TMPL.format(kind=kind), path.name)
    return m.group("ver") if m else None


def _read_header(blocks: list[Block], rel: str, kind: str, expect_version: str | None,
                  require_header: bool) -> tuple[Header | None, int]:
    """Consume a leading header block if present. Returns `(header, next
    block index)`. A first block with no `schema:` key is not a header (it
    is the file's first finding/entry block); in that case `require_header`
    decides whether the file is well-formed."""
    if not blocks:
        if require_header:
            raise BlockError(rel, 1, f"no schema header ({TEMPLATE_PATH})")
        return None, 0
    first = blocks[0]
    try:
        fields = config.parse(first.body)
    except config.ConfigError as e:
        raise BlockError(rel, first.line, f"unparsable block: {e}") from e
    if "schema" not in fields:
        if require_header:
            raise BlockError(rel, 1, f"no schema header ({TEMPLATE_PATH})")
        return None, 0
    if fields["schema"] != SCHEMA_ID:
        raise BlockError(rel, first.line, f"unknown schema {fields['schema']!r} (expected {SCHEMA_ID!r})")
    if fields.get("kind") != kind:
        raise BlockError(rel, first.line, f"header kind {fields.get('kind')!r} does not match the file ({kind})")
    version = fields.get("version", "")
    if expect_version is not None and version != expect_version:
        raise BlockError(
            rel, first.line,
            f"header version {version!r} does not match the file name's version {expect_version!r}",
        )
    return Header(fields["schema"], fields.get("kind", ""), version, first.line), 1


TEMPLATE_PATH = "schemas/security-disposition-template.md"


# --------------------------------------------------------------- review

def parse_review(text: str, rel: str, *, version: str | None = None,
                  require_header: bool = True) -> Review:
    """Parse a review file's blocks: an optional/required header, then
    finding blocks. Each finding's `severity` is checked against
    `cvss4.finding_severity(cvss_vector)` (a base-only vector: any Threat,
    Environmental or Supplemental metric is refused, since severity is the
    CVSS v4.0 base score); a mismatch, an invalid vector,
    an unknown key, a missing required key, or a `carried_from` that does
    not name a version earlier than `version` each raise `BlockError`."""
    blocks = split_blocks(text, rel)
    header, idx = _read_header(blocks, rel, "review", version, require_header)
    findings = []
    for blk in blocks[idx:]:
        try:
            fields = config.parse(blk.body)
        except config.ConfigError as e:
            raise BlockError(rel, blk.line, f"unparsable finding block: {e}") from e
        fid = fields.get("id", "?")
        unknown = set(fields) - FINDING_KEYS
        if unknown:
            raise BlockError(rel, blk.line, f"{fid}: unknown key(s) {sorted(unknown)} in finding block")
        missing = FINDING_REQUIRED - set(fields)
        if missing:
            raise BlockError(rel, blk.line, f"{fid}: finding block missing {sorted(missing)}")
        vector = fields["cvss_vector"]
        try:
            band = cvss4.finding_severity(vector)
            sc = cvss4.score(vector)
        except cvss4.CvssError as e:
            raise BlockError(rel, blk.line, f"{fid}: cvss_vector: {e}") from e
        stated = fields["severity"]
        if stated not in SEVERITIES:
            raise BlockError(rel, blk.line, f"{fid}: unknown severity {stated!r}")
        if stated != band:
            raise BlockError(
                rel, blk.line,
                f"{fid}: severity {stated} but cvss_vector scores {sc} ({band})",
            )
        carried_from = fields.get("carried_from") or None
        if carried_from is not None:
            if version is None or version_key(carried_from) >= version_key(version):
                raise BlockError(
                    rel, blk.line,
                    f"{fid}: carried_from {carried_from!r} does not name a version earlier than {version!r}",
                )
        findings.append(FindingBlock(
            id=fid,
            severity=stated,
            cvss_vector=vector,
            cite=config.parse_list(fields.get("cite", "[]")),
            affects=config.parse_list(fields.get("affects", "[]")),
            carried_from=carried_from,
            line=blk.line,
        ))
    return Review(header, findings)


# ---------------------------------------------------------- disposition

def parse_disposition(text: str, rel: str, *, version: str | None = None,
                       require_header: bool = False) -> Disposition:
    """Parse a disposition file's blocks: an optional/required header,
    then entry blocks. An unknown key or unknown `status` raises
    `BlockError`; `owner`/`expiry`/`rationale` presence rules that need
    the joined finding's severity are `check_pair`'s (gate mode only)."""
    blocks = split_blocks(text, rel)
    header, idx = _read_header(blocks, rel, "disposition", version, require_header)
    entries = []
    for blk in blocks[idx:]:
        try:
            fields = config.parse(blk.body)
        except config.ConfigError as e:
            raise BlockError(rel, blk.line, f"unparsable disposition block: {e}") from e
        eid = fields.get("id")
        if not eid:
            raise BlockError(rel, blk.line, "disposition block has no id:")
        unknown = set(fields) - ENTRY_KEYS
        if unknown:
            raise BlockError(rel, blk.line, f"{eid}: unknown key(s) {sorted(unknown)} in disposition block")
        missing = ENTRY_REQUIRED - set(fields)
        if missing:
            raise BlockError(rel, blk.line, f"{eid}: disposition block missing {sorted(missing)}")
        status = fields["status"]
        if status not in STATUSES:
            raise BlockError(rel, blk.line, f"{eid}: unknown status {status!r}")
        entries.append(EntryBlock(
            id=eid,
            status=status,
            owner=fields.get("owner", ""),
            expiry=fields.get("expiry") or None,
            rationale=fields.get("rationale", ""),
            reclassified_by=fields.get("reclassified_by") or None,
            suppresses=parse_inline_list(fields.get("suppresses", "[]")),
            inherited=fields.get("inherited") or None,
            line=blk.line,
        ))
    return Disposition(header, entries)


# ---------------------------------------------------------------- gate

def check_pair(review: Review, disposition: Disposition) -> list[BlockError]:
    """Gate-mode checks that join the pair: unique ids within each; an
    accepted/deferred entry joined to a medium-or-above finding has
    `owner:` and `expiry:`; every entry's `rationale` is at least 10
    characters."""
    errors: list[BlockError] = []
    seen: dict[str, int] = {}
    for f in review.findings:
        if f.id in seen:
            errors.append(BlockError("review", f.line, f"{f.id}: duplicate finding id (first at line {seen[f.id]})"))
        else:
            seen[f.id] = f.line
    sev_by_id = {f.id: f.severity for f in review.findings}

    seen_e: dict[str, int] = {}
    for e in disposition.entries:
        if e.id in seen_e:
            errors.append(BlockError("disposition", e.line, f"{e.id}: duplicate entry id (first at line {seen_e[e.id]})"))
        else:
            seen_e[e.id] = e.line
        if len(e.rationale) < 10:
            errors.append(BlockError("disposition", e.line, f"{e.id}: rationale is shorter than 10 characters"))
        if e.status in ("accepted", "deferred"):
            joined = sev_by_id.get(e.id)
            if joined in MEDIUM_UP:
                if not e.owner:
                    errors.append(BlockError("disposition", e.line, f"{e.id}: accepted/deferred at {joined} needs owner:"))
                if not e.expiry:
                    errors.append(BlockError("disposition", e.line, f"{e.id}: accepted/deferred at {joined} needs expiry:"))
    return errors


def check(review_path: Path, disposition_path: Path) -> list[BlockError]:
    """Gate mode over a review/disposition pair: read both with the header
    required, then `check_pair`. Returns the collected errors (empty means
    the pair is well-formed)."""
    errors: list[BlockError] = []
    rv_rel = review_path.name
    ds_rel = disposition_path.name
    rv_version = filename_version(review_path, "review")
    ds_version = filename_version(disposition_path, "disposition")
    review = Review(None, [])
    disposition = Disposition(None, [])
    try:
        review = parse_review(review_path.read_text(), rv_rel, version=rv_version, require_header=True)
    except BlockError as e:
        errors.append(e)
    try:
        disposition = parse_disposition(disposition_path.read_text(), ds_rel, version=ds_version, require_header=True)
    except BlockError as e:
        errors.append(e)
    if not errors:
        errors.extend(check_pair(review, disposition))
    return errors


# ------------------------------------------------------- latest entries

def latest_entries(sec_dir: Path, rel_dir: str, errors: list, *, before: str | None = None,
                    require_header: bool = False) -> dict[str, Latest]:
    """The latest disposition entry per id across `sec_dir`'s
    `*-disposition.md` files (floor mode by default): the higher version
    wins, and within one file the later block wins; a version `>= before`
    (when given) is excluded. Parser errors are appended to `errors` as
    `(rel, line, message)` — fail closed, never dropped, never raised."""
    best: dict[str, tuple] = {}
    if not sec_dir.is_dir():
        return {}
    for f in sorted(sec_dir.iterdir()):
        if not f.name.endswith("-disposition.md") or not f.is_file():
            continue
        rel = f"{rel_dir}/{f.name}"
        version = filename_version(f, "disposition")
        if version is None:
            errors.append((
                rel, 1,
                "is a disposition file whose name carries no <version> "
                "(expected <MAJOR.MINOR.PATCH[-pre]>-disposition.md); its entries would be ignored",
            ))
            continue
        if before is not None and version_key(version) >= version_key(before):
            continue
        try:
            text = f.read_text()
        except OSError as e:
            errors.append((rel, 1, f"unreadable disposition file: {e}"))
            continue
        try:
            disposition = parse_disposition(text, rel, version=version, require_header=require_header)
        except BlockError as e:
            errors.append((e.rel, e.line, e.message))
            continue
        vkey = version_key(version)
        for order, e in enumerate(disposition.entries):
            key = (vkey, order)
            prev = best.get(e.id)
            if prev is None or key > prev[0]:
                best[e.id] = (key, Latest(e, version, f, e.line))
    return {k: v[1] for k, v in best.items()}


# ------------------------------------------------------------------ CLI

def _cmd_check(args):
    errors = check(Path(args.review), Path(args.disposition))
    if not errors:
        print("PASS: security blocks — well-formed")
        return 0
    for e in errors:
        print(str(e))
    return 2


def _cmd_latest_before(args):
    """`latest DIR --before V`: /security-review's carry-forward listing. The prior versions are read exactly as
    the disposition gate reads them (disposition_gate.read_priors, R12: a tagged version from its tag, else the
    working tree, else the base ref when `--base` is given), and each latest entry is joined to its version's
    review for the severity. Prints `<id> <version> <status> <severity>` per id; exit 2 on any parser problem."""
    import disposition_gate  # lazy: disposition_gate imports this module
    sec = Path(args.dir).resolve()
    if sec.name != "security" or sec.parent.name != "docs":
        print(f"{args.dir}: --before needs DIR to be <root>/docs/security (priors are read by path at tags)",
              file=sys.stderr)
        return 2
    root = sec.parent.parent
    use_git = disposition_gate._git(root, "rev-parse", "--git-dir").returncode == 0
    for f in sorted(sec.glob("*-disposition.md")):
        v = filename_version(f, "disposition")
        if v is not None and version_key(v) < version_key(args.before) \
                and not (sec / f"{v}-review.md").is_file() and not (use_git and disposition_gate._tag_exists(root, v)):
            print(f"{args.dir}/{f.name}:1: has no {v}-review.md beside it; its entries' severity is unknown",
                  file=sys.stderr)
            return 2
    try:
        priors, _ = disposition_gate.read_priors(root, args.before, use_git, args.base)
    except disposition_gate.GateError as e:
        print(str(e), file=sys.stderr)
        return 2
    for p in sorted(priors, key=lambda p: p.id):
        print(f"{p.id} {p.version} {p.status.value} {p.severity.value}")
    return 0


def _cmd_latest(args):
    if args.before is not None:
        return _cmd_latest_before(args)
    errors: list = []
    latest = latest_entries(Path(args.dir), Path(args.dir).as_posix(), errors, before=args.before)
    for rel, line, message in errors:
        print(f"{rel}:{line}: {message}", file=sys.stderr)
    for eid in sorted(latest):
        l = latest[eid]
        print(f"{eid} {l.version} {l.entry.status}")
    return 2 if errors else 0


def main(argv):
    p = argparse.ArgumentParser(prog="blocks.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    pc = sub.add_parser("check")
    pc.add_argument("review")
    pc.add_argument("disposition")
    pl = sub.add_parser("latest")
    pl.add_argument("dir")
    pl.add_argument("--before")
    pl.add_argument("--base")
    args = p.parse_args(argv)
    if args.cmd == "check":
        return _cmd_check(args)
    if args.cmd == "latest":
        return _cmd_latest(args)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
