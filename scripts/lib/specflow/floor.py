#!/usr/bin/env python3
"""The one home of the security floor's rules (REQ-330, REQ-331, REQ-332, REQ-388).

Today this module implements the disposition reader and the `suppressions`
subcommand (REQ-388, Task 4 of the P4 plan): every suppression — an
osv-scanner.toml or audit.toml ignore entry, a .gitleaks.toml allowlist entry
beyond the three permitted paths, a .gitleaksignore fingerprint, a bandit
"# nosec", a .bandit or [tool.bandit] key, and any key or table outside a
suppression file's whitelist — must cite a SEC-NNN whose latest disposition
entry is accepted or deferred and whose `suppresses:` names the entry.

Task 5 adds `record` (append one outcome to the record file `floor.sh` and
`run-security-floor.sh` share) and `summarize` (fold those records, plus this
module's own suppression scan, into `.specflow/floor-summary.json`). Task 7
adds `ignores` (the ids of an osv-scanner.toml or audit.toml ignore list still
in date, per the Ruling on expiry — every per-stack security.sh hands its
tool only these, never reading the file itself). Later P4 tasks add
`render`/`check-review` (Task 11), per the plan's "one floor grammar" rule:
only this file writes the floor's summary and judges reviews.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import config  # noqa: E402  (after sys.path insert)
import blocks  # noqa: E402  (the one review/disposition parser, R5)

SKIP_DIRS = {".git", "node_modules", "target", ".venv", "build", "dist"}

PERMITTED_GITLEAKS_PATHS = {
    r"(^|/)\.env\.example$",
    r"^docs/(.*/)?examples/",
    r"^tests/(.*/)?fixtures/",
}

DISPOSITION_RE = re.compile(r"^(?P<ver>\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)-disposition\.md$")
SEC_RE = re.compile(r"SEC-(\d{3})")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


# ---------------------------------------------------------------- utilities

def _die(msg: str, code: int = 2):
    print(f"floor: {msg}", file=sys.stderr)
    sys.exit(code)


def _parse_date(s: str) -> datetime.date:
    return datetime.date.fromisoformat(s.strip())


# ------------------------------------------------------------ disposition
# The block parser and the latest-entry reduction live in blocks.py (R5,
# P4 H4): floor.py keeps no reader of its own. `parse_inline_list` and
# `_version_key` moved there verbatim; call `blocks.parse_inline_list` and
# `blocks.version_key`.

def _entry_to_dict(e) -> dict:
    """An `EntryBlock` (blocks.py) as the flat dict `load_dispositions` has
    always returned: raw string fields plus a parsed `suppresses` list."""
    d = {
        "id": e.id,
        "status": e.status,
        "owner": e.owner,
        "rationale": e.rationale,
        "suppresses": e.suppresses,
    }
    if e.expiry is not None:
        d["expiry"] = e.expiry
    if e.reclassified_by is not None:
        d["reclassified_by"] = e.reclassified_by
    if e.inherited is not None:
        d["inherited"] = e.inherited
    return d


def load_dispositions(root: Path, errors: list | None = None) -> dict[str, dict]:
    """The latest entry per SEC id across `root/docs/security/*-disposition.md`:
    by version across files (R10), and within one file the later block wins.

    Fails closed: a `*-disposition.md` whose name carries no version, an
    unreadable file, a block `config.parse` rejects, a block with no `id:`, and
    a block whose opening `---` never closes are each appended to `errors` as
    `(file, line, message)` — never skipped, so a newer entry cannot silently
    drop out and leave an older accepted one latest."""
    latest = _latest_disposition_entries(root / "docs" / "security", "docs/security", errors)
    return {k: v[0] for k, v in latest.items()}


def _latest_disposition_entries(sec_dir: Path, rel_dir: str, errors: list | None = None) -> dict[str, tuple]:
    """`load_dispositions`' latest-entry rule over one directory's
    `*-disposition.md` files: SEC id -> (entry, file path, block line). The
    higher version file wins, and within one file the later block; errors
    are appended fail-closed exactly as `load_dispositions` documents.

    A thin wrapper over `blocks.latest_entries` (floor mode: no header
    required) that keeps this function's historic return shape."""
    errs = errors if errors is not None else []
    latest = blocks.latest_entries(sec_dir, rel_dir, errs, require_header=False)
    return {sec_id: (_entry_to_dict(l.entry), l.path, l.line) for sec_id, l in latest.items()}


def validate_citation(sec: str | None, name: str, dispositions: dict, ignore_until: str | None = None) -> str | None:
    """None if `name` is validly suppressed by an active `sec`; else the
    problem text."""
    if sec is None:
        return "has no SEC-NNN citation"
    entry = dispositions.get(sec)
    if entry is None:
        return f"cites {sec}, which no disposition entry defines"
    status = entry.get("status")
    if status not in ("accepted", "deferred"):
        return f"cites {sec}, whose latest disposition entry is {status!r}, not accepted or deferred"
    if name not in entry.get("suppresses", []):
        return f"cites {sec}, but its suppresses: does not list {name!r}"
    if ignore_until is not None:
        expiry = entry.get("expiry")
        if expiry:
            try:
                if _parse_date(ignore_until) > _parse_date(expiry):
                    return f"has ignoreUntil {ignore_until}, after {sec}'s expiry {expiry}"
            except ValueError:
                pass
    return None


# ------------------------------------------------------------- file listing

def _is_git_worktree(root: Path) -> bool:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True,
        )
    except OSError:
        return False
    return out.returncode == 0 and out.stdout.strip() == "true"


def _walk_files(root: Path) -> list[Path]:
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            out.append((Path(dirpath) / f).relative_to(root))
    return out


def _git_files(root: Path) -> list[Path]:
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        capture_output=True, text=True,
    )
    names = [n for n in out.stdout.split("\0") if n]
    return [Path(n) for n in names]


def is_template_source(root: Path) -> bool:
    return not (root / ".specflow.yml").exists() and not (root / ".stack").exists() and (root / "stacks").is_dir()


def list_files(root: Path) -> list[Path]:
    """Which files (Interfaces: Suppression scan)."""
    files = _git_files(root) if _is_git_worktree(root) else _walk_files(root)
    if is_template_source(root):
        files = [f for f in files if f.parts[0] != "stacks"]
    return files


def load_source_roots(root: Path) -> list[str]:
    pack = root / ".specflow" / "pack.yml"
    if pack.is_file():
        try:
            cfg = config.parse(pack.read_text())
        except config.ConfigError:
            cfg = {}
        if "source_roots" in cfg:
            roots = config.parse_list(cfg["source_roots"])
            if roots:
                return roots
    return ["src"]


def _under_source_root(rel: Path, source_roots: list[str]) -> bool:
    return any(rel.parts and rel.parts[0] == sr.rstrip("/") for sr in source_roots)


# ---------------------------------------------------------------- line scan

def _find_line(lines: list[str], pattern: str) -> int | None:
    rx = re.compile(pattern)
    for i, line in enumerate(lines, start=1):
        if rx.search(line):
            return i
    return None


def _find_line_with_text(lines: list[str], needle: str) -> int | None:
    for i, line in enumerate(lines, start=1):
        if needle in line:
            return i
    return None


def _trailing_comment(line: str) -> str | None:
    idx = line.find("#")
    if idx == -1:
        return None
    return line[idx + 1 :]


def _cite_from_comment(comment: str | None) -> str | None:
    if not comment:
        return None
    m = SEC_RE.search(comment)
    return f"SEC-{m.group(1)}" if m else None


def _load_toml(path: Path):
    try:
        return tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError):
        return None


def _value_digest(value) -> str:
    """The first 12 hex of the sha256 of `value`'s JSON with sorted keys (TOML
    dates as strings) — part of a config entry's name, so the entry cannot
    change without a disposition change."""
    text = json.dumps(value, sort_keys=True, default=str)
    return hashlib.sha256(text.encode()).hexdigest()[:12]


def _config_entry(rel: str, ln: int | None, lines: list[str], name: str, dispositions: dict,
                   violations: list, suppressions: list, kind: str, value=None, header: str | None = None):
    """A key or table outside a suppression file's whitelist, named
    `<name>[<digest of its value>]`. An array of tables (`value` a non-empty
    list of tables, `header` its dotted table name) is one entry per table,
    each on its own `[[header]]` line with its own `# SEC-NNN` — so a second
    table, or a changed one, cannot ride on an earlier table's SEC id (R9)."""
    if header is not None and isinstance(value, list) and value and all(isinstance(v, dict) for v in value):
        hdr = re.compile(rf"^\s*\[\[\s*{re.escape(header)}\s*\]\]")
        hdr_lines = [i for i, line in enumerate(lines, start=1) if hdr.match(line)]
        if len(hdr_lines) != len(value):
            violations.append((rel, ln or 1, f"{name} is an array of tables: write each table as its own "
                                             f"[[{header}]] whose header line carries its own # SEC-NNN"))
            return
        for hl, table in zip(hdr_lines, value):
            _config_one(rel, hl, lines, f"{name}[{_value_digest(table)}]", dispositions, violations, suppressions, kind)
        return
    _config_one(rel, ln, lines, f"{name}[{_value_digest(value)}]", dispositions, violations, suppressions, kind)


def _config_one(rel: str, ln: int | None, lines: list[str], name: str, dispositions: dict,
                violations: list, suppressions: list, kind: str):
    if ln is None:
        violations.append((rel, 1, f"{name} needs a # SEC-NNN citation"))
        return
    comment = _trailing_comment(lines[ln - 1])
    sec = _cite_from_comment(comment)
    err = validate_citation(sec, name, dispositions)
    if err:
        violations.append((rel, ln, f"{name} {err}"))
    else:
        suppressions.append({"file": rel, "line": ln, "kind": kind, "id": name, "name": name, "sec": sec})


# ------------------------------------------------------------- .gitleaks.toml

def _check_gitleaks_toml(path: Path, rel: str, dispositions: dict):
    violations: list = []
    suppressions: list = []
    try:
        text = path.read_text()
    except OSError:
        return [(rel, 1, "unreadable .gitleaks.toml")], []
    lines = text.splitlines()
    data = _load_toml(path)
    if data is None:
        violations.append((rel, 1, "unparsable .gitleaks.toml"))
        return violations, suppressions

    extend = data.get("extend") if isinstance(data.get("extend"), dict) else {}
    if extend.get("useDefault") is not True:
        violations.append((rel, 1, "[extend] useDefault = true is missing (a config without it scans with no rules)"))

    allowed_top = {"title", "extend", "allowlist", "allowlists"}
    for key in data:
        if key in allowed_top:
            continue
        ln = _find_line(lines, rf"^\s*(\[\[{re.escape(key)}\]\]|\[{re.escape(key)}\]|{re.escape(key)}\s*=)")
        _config_entry(rel, ln, lines, f"{rel}:{key}", dispositions, violations, suppressions, "config",
                      value=data[key], header=key)

    for key in extend:
        if key == "useDefault":
            continue
        ln = _find_line(lines, rf"^\s*{re.escape(key)}\s*=")
        _config_entry(rel, ln, lines, f"{rel}:extend.{key}", dispositions, violations, suppressions, "config",
                      value=extend[key], header=f"extend.{key}")

    allowlists = []
    if isinstance(data.get("allowlist"), dict):
        allowlists.append(data["allowlist"])
    if isinstance(data.get("allowlists"), list):
        allowlists.extend(a for a in data["allowlists"] if isinstance(a, dict))

    allowed_al_keys = {"description", "paths", "regexes", "commits", "stopwords"}
    kind_of = {"paths": "gitleaks-path", "regexes": "gitleaks-regex", "commits": "gitleaks-commit", "stopwords": "gitleaks-stopword"}
    for al in allowlists:
        for key, value in al.items():
            if key not in allowed_al_keys:
                ln = _find_line(lines, rf"^\s*{re.escape(key)}\s*=")
                _config_entry(rel, ln, lines, f"{rel}:allowlist.{key}", dispositions, violations, suppressions, "config",
                              value=value)
                continue
            if key == "description" or not isinstance(value, list):
                continue
            for item in value:
                if not isinstance(item, str):
                    continue
                if key == "paths" and item in PERMITTED_GITLEAKS_PATHS:
                    continue
                ln = _find_line_with_text(lines, item)
                _config_one(rel, ln, lines, item, dispositions, violations, suppressions, kind_of[key])

    return violations, suppressions


def _check_gitleaksignore(path: Path, rel: str, dispositions: dict):
    violations: list = []
    suppressions: list = []
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return [(rel, 1, "unreadable .gitleaksignore")], []
    prev_sec = None
    for i, line in enumerate(lines, start=1):
        s = line.strip()
        if not s:
            prev_sec = None
            continue
        if s.startswith("#"):
            m = re.match(r"#\s*(SEC-\d{3})\b", s)
            prev_sec = m.group(1) if m else None
            continue
        name = s
        sec = prev_sec
        prev_sec = None
        err = validate_citation(sec, name, dispositions)
        if err:
            violations.append((rel, i, f"{name} {err}"))
        else:
            suppressions.append({"file": rel, "line": i, "kind": "gitleaks-fingerprint", "id": name, "name": name, "sec": sec})
    return violations, suppressions


# ------------------------------------------------------------- osv-scanner.toml

def _check_osv_toml(path: Path, rel: str, dispositions: dict):
    violations: list = []
    suppressions: list = []
    try:
        text = path.read_text()
    except OSError:
        return [(rel, 1, "unreadable osv-scanner.toml")], []
    lines = text.splitlines()
    data = _load_toml(path)
    if data is None:
        violations.append((rel, 1, "unparsable osv-scanner.toml"))
        return violations, suppressions

    for key in data:
        if key == "IgnoredVulns":
            continue
        ln = _find_line(lines, rf"^\s*(\[\[{re.escape(key)}\]\]|\[{re.escape(key)}\]|{re.escape(key)}\s*=)")
        _config_entry(rel, ln, lines, f"{rel}:{key}", dispositions, violations, suppressions, "config",
                      value=data[key], header=key)

    entries = data.get("IgnoredVulns")
    if isinstance(entries, list):
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            vid = entry.get("id")
            ln = _find_line_with_text(lines, f'id = "{vid}"') if vid else None
            reason = str(entry.get("reason") or "")
            m = re.match(r"^\s*(SEC-\d{3}):", reason)
            sec = m.group(1) if m else None
            if sec is None:
                violations.append((rel, ln or 1, f"IgnoredVulns {vid!r} has no leading SEC-NNN: in its reason"))
            else:
                ignore_until = entry.get("ignoreUntil")
                if ignore_until is None:
                    violations.append((rel, ln or 1, f"IgnoredVulns {vid!r} citing {sec} is missing ignoreUntil"))
                else:
                    err = validate_citation(sec, vid, dispositions, str(ignore_until))
                    if err:
                        violations.append((rel, ln or 1, f"IgnoredVulns {vid!r} {err}"))
                    else:
                        suppressions.append({"file": rel, "line": ln, "kind": "osv", "id": vid, "name": vid, "sec": sec})
            allowed_entry_keys = {"id", "ignoreUntil", "reason"}
            for k in entry:
                if k not in allowed_entry_keys:
                    ln2 = _find_line(lines, rf"^\s*{re.escape(k)}\s*=")
                    _config_entry(rel, ln2, lines, f"{rel}:IgnoredVulns.{k}", dispositions, violations, suppressions, "config",
                                  value=entry[k])

    return violations, suppressions


# ------------------------------------------------------------- audit.toml

def _check_audit_toml(path: Path, rel: str, dispositions: dict):
    violations: list = []
    suppressions: list = []
    try:
        text = path.read_text()
    except OSError:
        return [(rel, 1, "unreadable audit.toml")], []
    lines = text.splitlines()
    data = _load_toml(path)
    if data is None:
        violations.append((rel, 1, "unparsable audit.toml"))
        return violations, suppressions

    adv = data.get("advisories") if isinstance(data.get("advisories"), dict) else {}
    ignore_list = adv.get("ignore") if isinstance(adv.get("ignore"), list) else []
    for item in ignore_list:
        if not isinstance(item, str):
            continue
        ln = _find_line_with_text(lines, f'"{item}"')
        comment = _trailing_comment(lines[ln - 1]) if ln else None
        sec = _cite_from_comment(comment)
        if sec is None:
            violations.append((rel, ln or 1, f"cargo-audit ignore {item!r} has no SEC-NNN citation"))
            continue
        m = re.search(r"ignoreUntil:\s*(\d{4}-\d{2}-\d{2})", comment)
        if not m:
            violations.append((rel, ln or 1, f"cargo-audit ignore {item!r} citing {sec} is missing 'ignoreUntil: YYYY-MM-DD'"))
            continue
        ignore_until = m.group(1)
        err = validate_citation(sec, item, dispositions, ignore_until)
        if err:
            violations.append((rel, ln or 1, f"cargo-audit ignore {item!r} {err}"))
        else:
            suppressions.append({"file": rel, "line": ln, "kind": "cargo-audit", "id": item, "name": item, "sec": sec})

    for k in adv:
        if k == "ignore":
            continue
        ln = _find_line(lines, rf"^\s*{re.escape(k)}\s*=")
        _config_entry(rel, ln, lines, f"{rel}:advisories.{k}", dispositions, violations, suppressions, "config",
                      value=adv[k], header=f"advisories.{k}")

    for k in data:
        if k == "advisories":
            continue
        ln = _find_line(lines, rf"^\s*(\[\[{re.escape(k)}\]\]|\[{re.escape(k)}\]|{re.escape(k)}\s*=)")
        _config_entry(rel, ln, lines, f"{rel}:{k}", dispositions, violations, suppressions, "config",
                      value=data[k], header=k)

    return violations, suppressions


# ------------------------------------------------------------- bandit config

def _check_bandit_ini(path: Path, rel: str, dispositions: dict):
    violations: list = []
    suppressions: list = []
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return [(rel, 1, "unreadable .bandit")], []
    for i, line in enumerate(lines, start=1):
        s = line.strip()
        if not s or s.startswith("#") or s.startswith("[") or "=" not in s:
            continue
        key = s.split("=", 1)[0].strip()
        prev = lines[i - 2].strip() if i >= 2 else ""
        sec = None
        m = re.match(r"#\s*(SEC-\d{3})\b", prev)
        if m:
            sec = m.group(1)
        name = f"{rel}:{key}"
        err = validate_citation(sec, name, dispositions)
        if err:
            violations.append((rel, i, f"{name} needs a preceding '# SEC-NNN' comment ({err})"))
        else:
            suppressions.append({"file": rel, "line": i, "kind": "bandit-config", "id": name, "name": name, "sec": sec})
    return violations, suppressions


def _check_pyproject_bandit(path: Path, rel: str, dispositions: dict):
    violations: list = []
    suppressions: list = []
    data = _load_toml(path)
    if data is None:
        # Fail closed like every other suppression file (#36 low): bandit may
        # still read a [tool.bandit] table this check cannot see.
        violations.append((rel, 1, "unparsable pyproject.toml"))
        return violations, suppressions
    tool = data.get("tool") if isinstance(data.get("tool"), dict) else {}
    bandit = tool.get("bandit") if isinstance(tool.get("bandit"), dict) else None
    if bandit is None:
        return violations, suppressions
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return [(rel, 1, "unreadable pyproject.toml")], []
    for key in bandit:
        ln = _find_line(lines, rf"^\s*{re.escape(key)}\s*=")
        name = f"{rel}:tool.bandit.{key}"
        if ln is None:
            violations.append((rel, 1, f"{name} needs a # SEC-NNN citation"))
            continue
        comment = _trailing_comment(lines[ln - 1])
        sec = _cite_from_comment(comment)
        err = validate_citation(sec, name, dispositions)
        if err:
            violations.append((rel, ln, f"{name} {err}"))
        else:
            suppressions.append({"file": rel, "line": ln, "kind": "bandit-config", "id": name, "name": name, "sec": sec})
    return violations, suppressions


# ------------------------------------------------------------------- nosec

_NOSEC_RE = re.compile(r"#\s*nosec\b", re.IGNORECASE)
_TESTID_RE = re.compile(r"\bB\d{3}\b")


def _check_nosec(path: Path, rel: str, dispositions: dict):
    violations: list = []
    suppressions: list = []
    try:
        lines = path.read_text().splitlines()
    except (OSError, UnicodeDecodeError):
        return violations, suppressions
    for i, line in enumerate(lines, start=1):
        m = _NOSEC_RE.search(line)
        if not m:
            continue
        code = line[: m.start()].rstrip()
        rest = line[m.end() :]
        ids = _TESTID_RE.findall(rest)
        sec = _cite_from_comment("#" + rest)
        if not ids:
            violations.append((rel, i, f"{rel}:{i} bare '# nosec' has no bandit test id"))
            continue
        digest = hashlib.sha256(code.encode("utf-8")).hexdigest()[:12]
        for test_id in ids:
            name = f"{rel}:{test_id}:{digest}"
            if sec is None:
                violations.append((rel, i, f"{rel}:{i} '# nosec {test_id}' has no SEC-NNN citation"))
                continue
            err = validate_citation(sec, name, dispositions)
            if err:
                violations.append((rel, i, f"{name} {err}"))
            else:
                suppressions.append({"file": rel, "line": i, "kind": "nosec", "id": name, "name": name, "sec": sec})
    return violations, suppressions


# --------------------------------------------------------------------- scan

def suppressions_scan(root: Path):
    root = root.resolve()
    files = list_files(root)
    fileset = set(files)
    violations: list = []
    suppressions: list = []
    dispositions = load_dispositions(root, violations)

    gl_path = Path(".gitleaks.toml")
    if gl_path in fileset:
        v, s = _check_gitleaks_toml(root / gl_path, gl_path.as_posix(), dispositions)
        violations += v
        suppressions += s

    gli_path = Path(".gitleaksignore")
    if gli_path in fileset:
        v, s = _check_gitleaksignore(root / gli_path, gli_path.as_posix(), dispositions)
        violations += v
        suppressions += s

    for f in sorted(files, key=lambda p: p.as_posix()):
        if f.name == "osv-scanner.toml":
            v, s = _check_osv_toml(root / f, f.as_posix(), dispositions)
        elif f.name == "audit.toml":
            v, s = _check_audit_toml(root / f, f.as_posix(), dispositions)
        elif f.name == "pyproject.toml":
            v, s = _check_pyproject_bandit(root / f, f.as_posix(), dispositions)
        else:
            continue
        violations += v
        suppressions += s

    source_roots = load_source_roots(root)
    for f in sorted(files, key=lambda p: p.as_posix()):
        if not _under_source_root(f, source_roots):
            continue
        if f.name == ".bandit":
            v, s = _check_bandit_ini(root / f, f.as_posix(), dispositions)
        elif f.suffix == ".py":
            v, s = _check_nosec(root / f, f.as_posix(), dispositions)
        else:
            continue
        violations += v
        suppressions += s

    violations.sort(key=lambda t: (t[0], t[1]))
    suppressions.sort(key=lambda d: (d["file"], d["line"] or 0))
    return violations, suppressions


# --------------------------------------------------------------- record / summarize

def _git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)


def _head_commit(root: Path) -> str | None:
    out = _git(root, "rev-parse", "HEAD")
    if out.returncode != 0:
        return None
    return out.stdout.strip() or None


def _is_dirty(root: Path) -> bool:
    out = _git(root, "status", "--porcelain", "--untracked-files=no")
    return out.returncode == 0 and bool(out.stdout.strip())


def _detect_stack(root: Path) -> str:
    cfg_path = root / ".specflow.yml"
    if not cfg_path.is_file():
        return "none"
    try:
        cfg = config.parse(cfg_path.read_text())
    except config.ConfigError:
        return "none"
    return cfg.get("stack", "none") or "none"


def _cmd_record(args):
    exit_val: int | None
    if args.exit == "-":
        exit_val = None
    else:
        try:
            exit_val = int(args.exit)
        except ValueError:
            exit_val = None
    record = {
        "tool": args.tool,
        "scope": args.scope,
        "version": args.version,
        "exit": exit_val,
        "status": args.status,
        "result": args.result,
        "command": args.command,
    }
    path = Path(args.file)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")
    sys.exit(0)


def _load_records(path: Path) -> list[dict]:
    records: list[dict] = []
    if not path.is_file():
        return records
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
    return records


def _cmd_summarize(args):
    root = Path(args.root).resolve()
    try:
        records = _load_records(Path(args.records))
    except (OSError, json.JSONDecodeError) as e:
        print(f"floor: unreadable records file {args.records}: {e}", file=sys.stderr)
        sys.exit(2)

    tools = []
    seen: dict[tuple[str, str], int] = {}
    for rec in records:
        key = (rec.get("tool"), rec.get("scope"))
        entry = {
            "tool": rec.get("tool"),
            "scope": rec.get("scope"),
            "version": rec.get("version"),
            "exit": rec.get("exit"),
            "status": rec.get("status"),
            "result": rec.get("result"),
            "command": rec.get("command", ""),
        }
        if key in seen:
            tools[seen[key]] = entry
        else:
            seen[key] = len(tools)
            tools.append(entry)

    violations, suppressions = suppressions_scan(root)
    suppression_errors = [f"{f}:{ln}: {msg}" for f, ln, msg in violations]

    summary = {
        "schema": 1,
        "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "commit": _head_commit(root),
        "dirty": _is_dirty(root),
        "mode": args.mode,
        "stack": _detect_stack(root),
        "tools": tools,
        "suppressions": suppressions,
        "suppression_errors": suppression_errors,
    }
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(summary, indent=2) + "\n")
    sys.exit(0)


# ---------------------------------------------------------------- ignores

def _osv_ignore_entries(path: Path):
    """`[[IgnoredVulns]]` entries of an osv-scanner.toml, as
    `{"id", "sec", "ignore_until"}`. `None` when the file cannot be parsed."""
    data = _load_toml(path)
    if data is None:
        return None
    out = []
    for v in data.get("IgnoredVulns") or []:
        if not isinstance(v, dict):
            continue
        reason = str(v.get("reason") or "")
        m = re.match(r"^\s*(SEC-\d{3}):", reason)
        ignore_until = v.get("ignoreUntil")
        out.append({
            "id": v.get("id"),
            "sec": m.group(1) if m else None,
            "ignore_until": str(ignore_until) if ignore_until is not None else None,
        })
    return out


def _cargo_ignore_entries(path: Path):
    """`[advisories] ignore` entries of an audit.toml, with the `SEC-NNN` and
    `ignoreUntil: YYYY-MM-DD` from the entry's trailing comment (R4: cargo-audit
    itself never reads this file's `ignoreUntil`, so this module parses the
    comment the same way the suppression scan does)."""
    try:
        text = path.read_text()
    except OSError:
        return None
    data = _load_toml(path)
    if data is None:
        return None
    lines = text.splitlines()
    adv = data.get("advisories") if isinstance(data.get("advisories"), dict) else {}
    ignore_list = adv.get("ignore") if isinstance(adv.get("ignore"), list) else []
    out = []
    for item in ignore_list:
        if not isinstance(item, str):
            continue
        ln = _find_line_with_text(lines, f'"{item}"')
        comment = _trailing_comment(lines[ln - 1]) if ln else None
        sec = _cite_from_comment(comment)
        m = re.search(r"ignoreUntil:\s*(\d{4}-\d{2}-\d{2})", comment or "")
        out.append({"id": item, "sec": sec, "ignore_until": m.group(1) if m else None})
    return out


def _cmd_ignores(args):
    root = Path(args.root)
    if args.source == "osv":
        path = root / "osv-scanner.toml"
        entries = _osv_ignore_entries(path) if path.is_file() else []
    else:
        path = root / "src-tauri" / "audit.toml"
        entries = _cargo_ignore_entries(path) if path.is_file() else []
    if path.is_file() and entries is None:
        _die(f"unreadable or unparsable {path}")

    today = datetime.datetime.now(datetime.timezone.utc).date()
    for e in entries:
        eid = e.get("id")
        sec = e.get("sec") or "SEC-???"
        iu = e.get("ignore_until")
        if not eid or not iu:
            continue
        try:
            d = _parse_date(iu)
        except ValueError:
            continue
        if d < today:
            print(f"note: {eid} ({sec}) expired {iu} — no longer ignored", file=sys.stderr)
            continue
        if (d - today).days <= 30:
            print(f"note: {eid} ({sec}) expires {iu}", file=sys.stderr)
        print(eid)
    sys.exit(0)


# ------------------------------------------------------------ expiry notice

EXPIRY_FAIL_DAYS = 30
EXPIRY_WARN_DAYS = 60


def _expiry_dates(root: Path):
    """(file, line, id, kind, date-string) for every advisory ignore's
    `ignoreUntil` (osv-scanner.toml, audit.toml trailing comments) and, per
    directory of `*-disposition.md` files, each SEC id's LATEST entry's
    `expiry:` (`load_dispositions`' rule: the higher version file, then the
    later block — so renewing by appending a newer entry clears the old
    date; PR #36 second run). An unparsable suppression file, or a
    disposition error `load_dispositions` would report, yields
    (file, line, None, "unparsable", None)."""
    out = []
    disposition_dirs = set()
    for f in sorted(list_files(root), key=lambda p: p.as_posix()):
        path = root / f
        if f.name == "osv-scanner.toml":
            entries = _osv_ignore_entries(path)
            if entries is None:
                out.append((path, 1, None, "unparsable", None))
                continue
            lines = path.read_text().splitlines()
            for e in entries:
                ln = _find_line_with_text(lines, f'"{e.get("id")}"') or 1
                if e.get("ignore_until"):
                    out.append((path, ln, e.get("id"), "ignoreUntil", e["ignore_until"]))
        elif f.name == "audit.toml":
            entries = _cargo_ignore_entries(path)
            if entries is None:
                out.append((path, 1, None, "unparsable", None))
                continue
            lines = path.read_text().splitlines()
            for e in entries:
                ln = _find_line_with_text(lines, f'"{e.get("id")}"') or 1
                if e.get("ignore_until"):
                    out.append((path, ln, e.get("id"), "ignoreUntil", e["ignore_until"]))
        elif f.suffix == ".md" and f.name.endswith("-disposition.md") and "security" in f.parts:
            disposition_dirs.add(f.parent)
    for d in sorted(disposition_dirs, key=lambda p: p.as_posix()):
        errors: list = []
        latest = _latest_disposition_entries(root / d, d.as_posix(), errors)
        for rel, ln, _msg in errors:
            out.append((root / rel, ln, None, "unparsable", None))
        for sec_id, (entry, fpath, block_line) in sorted(latest.items()):
            if not entry.get("expiry"):
                continue
            lines = fpath.read_text().splitlines()
            ln = next((i for i in range(block_line, len(lines) + 1)
                       if re.match(r"^expiry:", lines[i - 1])), block_line)
            out.append((fpath, ln, sec_id, "expiry", str(entry["expiry"]).strip()))
    out.sort(key=lambda r: (str(r[0]), r[1]))
    return out


def _cmd_expiry(args):
    """30 days' notice before a pack-shipped suppression lapses (#36): the
    floor goes red on the date itself by design (Ruling on suppression
    expiry); this prints `FAIL expiry` under 30 days (past dates included)
    and `WARN expiry` for 30–60 days, and exits 1 on any FAIL."""
    try:
        today = _parse_date(args.today) if args.today else datetime.datetime.now(datetime.timezone.utc).date()
    except ValueError:
        _die(f"--today {args.today!r} is not YYYY-MM-DD")
    failed = False
    for r in args.root:
        root = Path(r)
        for path, ln, eid, kind, ds in _expiry_dates(root):
            rel = os.path.relpath(path)
            if kind == "unparsable":
                print(f"FAIL expiry {rel}:{ln}: unparsable — its dates cannot be checked")
                failed = True
                continue
            try:
                d = _parse_date(ds)
            except ValueError:
                print(f"FAIL expiry {rel}:{ln}: {eid} {kind} {ds!r} is not a YYYY-MM-DD date")
                failed = True
                continue
            days = (d - today).days
            where = f"{rel}:{ln}: {eid} {kind} {ds}"
            if days < EXPIRY_FAIL_DAYS:
                state = "has passed" if days < 0 else f"is {days} days away (under {EXPIRY_FAIL_DAYS})"
                print(f"FAIL expiry {where} {state} — re-accept it (bump ignoreUntil in osv-scanner.toml and "
                      f"audit.toml, add a disposition entry) or re-pin the lockfiles")
                failed = True
            elif days <= EXPIRY_WARN_DAYS:
                print(f"WARN expiry {where} is {days} days away — the floor fails on that date")
    sys.exit(1 if failed else 0)


# --------------------------------------------------------------------- CLI

def _cmd_suppressions(args):
    root = Path(args.root)
    violations, suppressions = suppressions_scan(root)
    if args.json:
        errors = [f"{f}:{ln}: {msg}" for f, ln, msg in violations]
        print(json.dumps({"suppressions": suppressions, "errors": errors}))
    else:
        for f, ln, msg in violations:
            print(f"{f}:{ln}: {msg}")
    sys.exit(1 if violations else 0)


# --------------------------------------------------------- ## Tools run

TOOLS_HEADER = "| Tool | Scope | Version | Exit | Result |"
SUPPRESSIONS_HEADER = "| File | Line | Id | SEC |"
NOT_RUN_RESULT = "not run — no tracked lockfile"
_VERSION_RE = re.compile(r"^\d+(\.\d+)+$")
_SEC_ROW_RE = re.compile(r"^SEC-\d{3}$")
_PROVENANCE_RE = re.compile(r"scratch instance of template commit ([0-9a-f]{40})")
_FLOOR_SUMMARY_RE = re.compile(r"Floor summary: `[^`]+` at ([0-9a-f]{40}),")
_FLOOR_EVIDENCE_RE = re.compile(r"^Floor evidence: rows sha256 ([0-9a-f]{64})\.$")


def _tool_row(t: dict) -> str:
    ex = t.get("exit")
    ex_s = "-" if ex is None else str(ex)
    return f"| {t.get('tool')} | {t.get('scope')} | {t.get('version')} | {ex_s} | {t.get('result')} |"


def _suppression_row(s: dict) -> str:
    return f"| {s.get('file')} | {s.get('line')} | {s.get('id')} | {s.get('sec')} |"


def _rows_digest(commit: str | None, tool_rows: list[str], sup_rows: list[str]) -> str:
    parts = ([commit] if commit is not None else []) + list(tool_rows) + list(sup_rows)
    return hashlib.sha256("\n".join(parts).encode()).hexdigest()


def _cmd_render(args):
    try:
        summary = json.loads(Path(args.summary).read_text())
    except (OSError, json.JSONDecodeError) as e:
        print(f"floor: render: unreadable summary {args.summary}: {e}", file=sys.stderr)
        sys.exit(2)

    root = Path(args.root)
    errors: list[str] = []
    mode = summary.get("mode")
    if mode != "online":
        errors.append(f"mode is {mode!r}, not online — not evidence")
    head = _head_commit(root)
    commit = summary.get("commit")
    if commit != head:
        errors.append(f"commit {commit!r} is stale (root HEAD is {head!r})")
    if summary.get("dirty"):
        errors.append("the working tree was dirty when the summary was generated")
    for t in summary.get("tools", []):
        status = t.get("status")
        if status not in ("pass", "not-applicable"):
            errors.append(
                f"{t.get('tool')} ({t.get('scope')}) status is {status!r}, not evidence: {t.get('result')}"
            )
    for e in summary.get("suppression_errors", []):
        errors.append(e)

    if errors:
        for e in errors:
            print(f"floor: render: {e}", file=sys.stderr)
        sys.exit(1)

    tool_rows = [_tool_row(t) for t in summary.get("tools", [])]
    sup_rows = [_suppression_row(s) for s in summary.get("suppressions", [])]
    digest = _rows_digest(commit, tool_rows, sup_rows)

    lines = [
        "## Tools run",
        "",
        f"Floor summary: `.specflow/floor-summary.json` at {commit}, generated {summary.get('generated_at')}, mode {mode}.",
        f"Floor evidence: rows sha256 {digest}.",
        "",
        TOOLS_HEADER,
        "|---|---|---|---|---|",
        *tool_rows,
        "",
        "### Active suppressions",
        "",
    ]
    if sup_rows:
        lines += [SUPPRESSIONS_HEADER, "|---|---|---|---|", *sup_rows]
    else:
        lines.append("None.")
    print("\n".join(lines))
    sys.exit(0)


def _is_table_row(line: str) -> bool:
    s = line.strip()
    if not (s.startswith("|") and s.endswith("|")):
        return False
    if set(s) <= set("|-: "):
        return False  # a separator row, e.g. "|---|---|"
    return True


def _row_cells(line: str) -> list[str]:
    s = line.strip()
    if not (s.startswith("|") and s.endswith("|")):
        return []
    return [c.strip() for c in s[1:-1].split("|")]


def _find_heading(lines: list[str], heading: str, start: int = 0, stop: int | None = None) -> int | None:
    stop = len(lines) if stop is None else stop
    for i in range(start, stop):
        if lines[i].strip() == heading:
            return i
    return None


def _section_bounds(lines: list[str], heading: str, level: str) -> tuple[int, int] | None:
    start = _find_heading(lines, heading)
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith(level):
            end = j
            break
    return start, end


def _table_rows(lines: list[str], start: int, end: int, header: str) -> list[str]:
    """Raw row lines (as printed) contiguous right after `header`'s separator,
    within lines[start:end]."""
    hi = _find_heading(lines, header, start, end)
    if hi is None:
        return []
    i = hi + 1
    if i < end and lines[i].strip().startswith("|") and set(lines[i].strip()) <= set("|-: "):
        i += 1
    rows = []
    while i < end and lines[i].strip().startswith("|"):
        rows.append(lines[i])
        i += 1
    return rows


def _load_pack_info(pack_path: Path) -> tuple[list[str], list[str]]:
    if not pack_path.is_file():
        return [], []
    try:
        cfg = config.parse(pack_path.read_text())
    except config.ConfigError:
        return [], []
    lockfiles = config.parse_list(cfg.get("lockfiles", "[]"))
    floor_tools = config.parse_list(cfg.get("floor_tools", "[]"))
    return lockfiles, floor_tools


_REVIEW_NAME_RE = re.compile(r"^(?P<version>\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)-review\.md$")  # DISPOSITION_RE's grammar


def _review_version(path: Path) -> str | None:
    """The version a `<version>-review.md` path names, else None."""
    m = _REVIEW_NAME_RE.match(path.name)
    return m.group("version") if m else None


def _released_on_head(root: Path, path: Path) -> tuple[bool, str]:
    """(released, reason): released is True when the review's version is released on this history and the file
    is the tag's copy — the tag `v<version>` exists, its commit is HEAD or an ancestor of it (`git merge-base
    --is-ancestor`), and the working copy is byte-identical to `v<version>:<path>` (PR #66 verifier run 1:
    "frozen" is a mechanism, not a comment). Otherwise False with the reason: no version in the name, no such
    tag, the tag on another history, the file absent at the tag, or the file edited since the tag."""
    ver = _review_version(path)
    if not ver:
        return False, "the file name carries no version"
    ref = f"refs/tags/v{ver}"
    if _git(root, "rev-parse", "-q", "--verify", f"{ref}^{{commit}}").returncode != 0:
        return False, f"no tag v{ver}"
    if _git(root, "merge-base", "--is-ancestor", ref, "HEAD").returncode != 0:
        return False, f"tag v{ver} is not on HEAD's history"
    try:
        rel = path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return False, "the file is outside --root"
    at_tag = subprocess.run(["git", "-C", str(root), "show", f"{ref}:{rel}"], capture_output=True)  # bytes
    if at_tag.returncode != 0:
        return False, f"the file is absent at v{ver}"
    try:
        current = path.read_bytes()
    except OSError:
        return False, "the file cannot be read"
    if at_tag.stdout != current:
        return False, f"the file differs from v{ver}'s copy (a released review is never edited after its tag)"
    return True, f"released: v{ver} on HEAD's history and the file identical to its copy at the tag"


def _is_shipped_review(path: Path, root: Path, pack_given: bool) -> bool:
    """A review the template or a stack pack ships, rendered once on a scratch
    instance of a template commit that an instance's own history never holds:
    checked with `--pack` (the template-source run over a pack root), a
    `*-skeleton-review.md` (what a pack's overlay copies into an instance), or
    a path CLAUDE.md's "## Canonical Example" manifest lists (the demo). Only
    these may name a provenance commit absent from --root's history."""
    if pack_given or path.name.endswith("-skeleton-review.md"):
        return True
    claude_md = root / "CLAUDE.md"
    if not claude_md.is_file():
        return False
    try:
        import examples  # noqa: PLC0415  (same directory; the one manifest reader)
        manifest = examples.parse(claude_md.read_text())
        rel = path.resolve().relative_to(root.resolve()).as_posix()
    except (ImportError, OSError, ValueError):
        return False
    return any(rel in paths for _stack, paths in manifest.values())


def _cmd_check_review(args):
    path = Path(args.file)
    root = Path(args.root)
    try:
        text = path.read_text()
    except OSError as e:
        print(f"{path}: unreadable: {e}", file=sys.stderr)
        sys.exit(2)

    lines = text.splitlines()
    sec = _section_bounds(lines, "## Tools run", "## ")
    if sec is None:
        print(f"{path}: no '## Tools run' section")
        sys.exit(1)
    s0, s1 = sec
    section = lines[s0:s1]
    has_table = _find_heading(section, TOOLS_HEADER) is not None

    pack_path = Path(args.pack) if args.pack else (root / ".specflow" / "pack.yml")
    lockfiles, floor_tools = _load_pack_info(pack_path)
    has_lockfile = any((root / lf).is_file() for lf in lockfiles)

    violations: list[str] = []

    if not has_table:
        if has_lockfile:
            violations.append(
                "the Tools run section is manual-only, but the product has a lockfile "
                "(the pack's lockfiles) — a tools table is required"
            )
        for v in violations:
            print(f"{path}: {v}")
        sys.exit(1 if violations else 0)

    tool_rows = _table_rows(section, 0, len(section), TOOLS_HEADER)
    present_tools: set[str] = set()
    for row in tool_rows:
        cells = _row_cells(row)
        if len(cells) != 5:
            violations.append(f"malformed Tools run row: {row.strip()}")
            continue
        tool, _scope, version, ex, result = cells
        present_tools.add(tool)
        if not _VERSION_RE.match(version):
            violations.append(f"{tool}: row has no valid version ({version!r})")
        if ex == "-":
            if result != NOT_RUN_RESULT:
                violations.append(
                    f"{tool}: exit '-' is only valid when Result is {NOT_RUN_RESULT!r} (got {result!r})"
                )
        elif not re.fullmatch(r"-?\d+", ex):
            violations.append(f"{tool}: row has a non-integer exit status ({ex!r})")

    required = {"gitleaks", "osv-scanner"}
    if has_lockfile:
        required |= set(floor_tools)
    missing = required - present_tools
    if missing:
        violations.append(f"missing required tool row(s): {', '.join(sorted(missing))}")

    sup_start = _find_heading(section, "### Active suppressions")
    sup_rows: list[str] = []
    if sup_start is None:
        violations.append(f"{path}: no '### Active suppressions' subsection")
    else:
        sup_end = len(section)
        for j in range(sup_start + 1, len(section)):
            if section[j].startswith("## ") or section[j].startswith("### "):
                sup_end = j
                break
        sub = section[sup_start:sup_end]
        if any(line.strip() == "None." for line in sub):
            sup_rows = []
        else:
            sup_rows = _table_rows(sub, 0, len(sub), SUPPRESSIONS_HEADER)
            for row in sup_rows:
                cells = _row_cells(row)
                sec_cell = cells[-1] if cells else ""
                if not _SEC_ROW_RE.match(sec_cell):
                    violations.append(f"suppression row has no valid SEC-NNN: {row.strip()}")

    fs_commit = None
    for l in section:
        m = _FLOOR_SUMMARY_RE.search(l)
        if m:
            fs_commit = m.group(1)
            break
    if fs_commit is None:
        violations.append(f"{path}: no 'Floor summary:' line")

    fe_digest = None
    for l in section:
        m = _FLOOR_EVIDENCE_RE.match(l.strip())
        if m:
            fe_digest = m.group(1)
            break
    if fe_digest is None:
        violations.append(f"{path}: no 'Floor evidence:' line")
    else:
        recomputed = _rows_digest(fs_commit, tool_rows, sup_rows)
        if recomputed != fe_digest:
            violations.append(
                "the Tools run rows differ from what floor.py render printed (evidence digest mismatch)"
            )

    # The provenance path (PR #36 second run): a "scratch instance of template
    # commit <sha>" line replaces the Floor summary: commit check ONLY for a
    # shipped review (`_is_shipped_review`: --pack over stacks/*/overlay, a
    # *-skeleton-review.md an instance received, or a review the Canonical
    # Example lists — docs/security/0.0.1-demo-review.md, whose addendum is
    # rendered on a scratch instance by design). In every other review the
    # line is ignored and the Floor summary: commit must be HEAD or an
    # ancestor of it, so a phrase cannot excuse a foreign summary.
    prov_commit = None
    shipped = _is_shipped_review(path, root, bool(args.pack))
    for l in section:
        m = _PROVENANCE_RE.search(l)
        if m:
            prov_commit = m.group(1)
            break
    check_commit = (prov_commit if shipped else None) or fs_commit
    if check_commit:
        if not _is_git_worktree(root):
            violations.append(f"--root is not a git work tree; cannot confirm {check_commit} is an ancestor of HEAD")
        elif shipped and prov_commit and _git(root, "merge-base", "--is-ancestor", check_commit, "HEAD").returncode != 0:
            # R14/Interfaces: for a template- or pack-shipped review (the only kind whose provenance line is read
            # at all) a provenance commit is not checked against history: an ancestor passes below and any other
            # value passes here, so the rows' tamper evidence is the digest (docs/security/README.md); a shipped
            # review with no provenance line is ancestry-checked like any other, and --root must be a work tree.
            # Before PR #74 this branch took only a commit absent from the object store: a squash merge removes the
            # template branch's commits from main's history while a clone that fetched the branch still holds the
            # objects, so the tauri skeleton review's template commit passed in CI's fresh clone and failed every
            # local gates run after #73. Object existence is a property of the clone, not of the review.
            pass
        else:
            out = _git(root, "merge-base", "--is-ancestor", check_commit, "HEAD")
            released, why = (False, "") if out.returncode == 0 else _released_on_head(root, path)
            if out.returncode != 0 and released:
                # REQ-340, art-branch-as-state: squash merges are permitted, and a squash merge drops the ship
                # branch's commits, so a released review's Floor summary names a commit main's history never
                # holds (the factory's own 3.2.0 review after PR #62). The exemption is narrow: tag v<version> on
                # HEAD's history AND the working copy byte-identical to the tag's copy, so the tag's copy is the
                # record and an edit after the tag fails here; the evidence digest above is still required.
                pass
            elif out.returncode != 0:
                note = ""
                if prov_commit and not shipped:
                    note = (f" (its provenance line naming {prov_commit} is ignored: only a template- or "
                            "pack-shipped review — --pack, a *-skeleton-review.md, or a review CLAUDE.md's "
                            "Canonical Example lists — may use one)")
                ver = _review_version(path)
                if ver:
                    note += (f" — if the ship PR was squash-merged, the commit is gone from history and the review is "
                             f"accepted once tag v{ver} is created on this history and the file equals its copy at "
                             f"the tag (the squash-merge-to-tag window); here: {why}")
                violations.append(
                    f"commit {check_commit} is not HEAD or an ancestor of it in --root's history{note}"
                )

    for v in violations:
        print(f"{path}: {v}")
    sys.exit(1 if violations else 0)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="floor.py")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_sup = sub.add_parser("suppressions")
    p_sup.add_argument("--root", required=True)
    p_sup.add_argument("--json", action="store_true")
    p_sup.set_defaults(func=_cmd_suppressions)

    p_rec = sub.add_parser("record")
    p_rec.add_argument("--file", required=True)
    p_rec.add_argument("--tool", required=True)
    p_rec.add_argument("--scope", required=True)
    p_rec.add_argument("--version", required=True)
    p_rec.add_argument("--exit", required=True)
    p_rec.add_argument("--status", required=True)
    p_rec.add_argument("--result", required=True)
    p_rec.add_argument("--command", default="")
    p_rec.set_defaults(func=_cmd_record)

    p_sum = sub.add_parser("summarize")
    p_sum.add_argument("--records", required=True)
    p_sum.add_argument("--out", required=True)
    p_sum.add_argument("--mode", required=True, choices=["online", "offline"])
    p_sum.add_argument("--root", default=".")
    p_sum.set_defaults(func=_cmd_summarize)

    p_ign = sub.add_parser("ignores")
    p_ign.add_argument("--root", required=True)
    p_ign.add_argument("--source", required=True, choices=["osv", "cargo"])
    p_ign.set_defaults(func=_cmd_ignores)

    p_exp = sub.add_parser("expiry")
    p_exp.add_argument("--root", required=True, action="append")
    p_exp.add_argument("--today", default=None)
    p_exp.set_defaults(func=_cmd_expiry)

    p_ren = sub.add_parser("render")
    p_ren.add_argument("--summary", required=True)
    p_ren.add_argument("--root", default=".")
    p_ren.set_defaults(func=_cmd_render)

    p_chk = sub.add_parser("check-review")
    p_chk.add_argument("file")
    p_chk.add_argument("--root", required=True)
    p_chk.add_argument("--pack", default=None)
    p_chk.set_defaults(func=_cmd_check_review)

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
