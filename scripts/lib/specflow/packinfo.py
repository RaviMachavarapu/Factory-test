#!/usr/bin/env python3
"""The one reader of a stack pack's REQ-321 metadata (R15; Task 10; Task 13 reuses it).

`load(root)` returns the pack's `source_roots`, `test_globs`, `test_first_rules`
(as parsed `Rule`s), `non_source` globs and `coverage_exclude`, from whichever
file actually governs this tree: `.specflow/pack.yml` in an instance,
`scripts/template-pack.yml` in the template source (no `.specflow.yml`, no
`.stack`), or python's own defaults when an instance has neither (`config.py`
is not involved: this is pack metadata, not `.specflow.yml` policy).

`load_at_ref(root, ref)` reads the governing file as committed at a git ref
(the PR's base), judging instance-ness at that ref as well, so a PR cannot
relax its own test-first policy (final-review finding: the pack was read
from the PR head; PR #42: adding or deleting `.specflow.yml`/`.stack` swapped
it).

`match()` is the one glob matcher every REQ-321 caller uses: `**/` matches
zero or more whole directories, a trailing `**` matches everything below,
and a bare `*`/`?` stay within one path segment. `is_test()`/`is_source()`
compose it with a pack's `test_globs`/`non_source`/`source_roots`.

Stdlib only.
"""
from __future__ import annotations

import functools
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import config  # noqa: E402


class PackError(ValueError):
    """The pack file is missing, unreadable, or a `test_first_rules` item is malformed."""


@dataclass(frozen=True)
class Rule:
    source: str
    tests: tuple[str, ...]
    cfg_test: bool


@dataclass(frozen=True)
class Pack:
    origin: str
    source_roots: tuple[str, ...]
    test_globs: tuple[str, ...]
    rules: tuple[Rule, ...]
    non_source: tuple[str, ...]
    coverage_exclude: tuple[str, ...]


# --------------------------------------------------------------------------------------------------- glob matching


@functools.lru_cache(maxsize=None)
def _compile(pattern: str) -> re.Pattern:
    # Translate a REQ-321 glob to an anchored regex: "**/" matches zero or
    # more whole directories (including none — so "tests/**/test_*.py"
    # matches "tests/test_m.py" as well as "tests/sub/test_m.py"); a bare
    # trailing "**" matches everything below (including the path itself,
    # since only file paths are ever matched); "*" and "?" never cross a
    # "/"; everything else is a literal.
    i, n, out = 0, len(pattern), []
    while i < n:
        if pattern[i : i + 3] == "**/":
            out.append("(?:.*/)?")
            i += 3
            continue
        if pattern[i:] == "**":
            out.append(".*")
            i += 2
            continue
        c = pattern[i]
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def match(pattern: str, path: str) -> bool:
    """`path` is POSIX and relative (no leading `./`)."""
    return _compile(pattern).match(path) is not None


def is_test(pack: Pack, path: str) -> bool:
    return any(match(g, path) for g in pack.test_globs)


def is_source(pack: Pack, path: str) -> bool:
    under_root = any(path == r or path.startswith(r.rstrip("/") + "/") for r in pack.source_roots)
    if not under_root:
        return False
    if is_test(pack, path):
        return False
    if any(match(g, path) for g in pack.non_source):
        return False
    return True


# --------------------------------------------------------------------------------------------------------- loading


def _parse_rule(item: str) -> Rule:
    if "->" not in item:
        raise PackError(f"test_first_rules item has no '->': {item!r}")
    src, rest = item.split("->", 1)
    src = src.strip()
    if not src:
        raise PackError(f"test_first_rules item has an empty source side: {item!r}")
    tests: list[str] = []
    cfg_test = False
    for t in rest.split("|"):
        t = t.strip()
        if not t:
            continue
        if t == "cfg-test":
            cfg_test = True
        else:
            tests.append(t)
    if not tests and not cfg_test:
        raise PackError(f"test_first_rules item has no test side: {item!r}")
    return Rule(source=src, tests=tuple(tests), cfg_test=cfg_test)


def _build(cfg: dict, origin: str) -> Pack:
    source_roots = tuple(config.parse_list(cfg.get("source_roots", "")))
    test_globs = tuple(config.parse_list(cfg.get("test_globs", "")))
    non_source = tuple(config.parse_list(cfg.get("non_source", "")))
    coverage_exclude = tuple(config.parse_list(cfg.get("coverage_exclude", "")))
    if not source_roots:
        raise PackError(f"{origin}: no source_roots")
    if "test_first_rules" in cfg:
        rules = tuple(_parse_rule(item) for item in config.parse_list(cfg["test_first_rules"]))
    else:
        # Without the key, each source root gets `<root>/** -> <every test glob>`.
        rules = tuple(Rule(source=f"{r.rstrip('/')}/**", tests=test_globs, cfg_test=False) for r in source_roots)
    return Pack(
        origin=origin,
        source_roots=source_roots,
        test_globs=test_globs,
        rules=rules,
        non_source=non_source,
        coverage_exclude=coverage_exclude,
    )


def load(root: str | Path, pack_file: str | None = None) -> Pack:
    """`pack_file` (`--pack FILE` in every caller) overrides the usual
    instance/template-source detection outright."""
    if pack_file:
        p = Path(pack_file)
        if not p.is_file():
            raise PackError(f"{pack_file} not found")
        try:
            cfg = config.parse(p.read_text())
        except config.ConfigError as e:
            raise PackError(f"{pack_file}: {e}") from e
        return _build(cfg, str(pack_file))

    root = Path(root)
    is_instance = (root / ".specflow.yml").is_file() or (root / ".stack").is_file()
    if is_instance:
        pack_path = root / ".specflow" / "pack.yml"
        if pack_path.is_file():
            try:
                cfg = config.parse(pack_path.read_text())
            except config.ConfigError as e:
                raise PackError(f".specflow/pack.yml: {e}") from e
            return _build(cfg, ".specflow/pack.yml")
        # python's own defaults (an instance with no pack file copied yet).
        return Pack(
            origin="python defaults (no .specflow/pack.yml)",
            source_roots=("src",),
            test_globs=("tests/**/test_*.py",),
            rules=(Rule(source="src/**", tests=("tests/**/test_*.py",), cfg_test=False),),
            non_source=(),
            coverage_exclude=(),
        )

    template_pack = root / "scripts" / "template-pack.yml"
    if not template_pack.is_file():
        raise PackError(f"no scripts/template-pack.yml in the template source at {root}")
    try:
        cfg = config.parse(template_pack.read_text())
    except config.ConfigError as e:
        raise PackError(f"scripts/template-pack.yml: {e}") from e
    return _build(cfg, "scripts/template-pack.yml")


INSTANCE_MARKERS = (".specflow.yml", ".stack")


def _is_instance(root: Path) -> bool:
    return any((root / m).is_file() for m in INSTANCE_MARKERS)


def _at_ref(root: Path, ref: str, path: str) -> bool:
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{ref}:{path}"],
                          capture_output=True).returncode == 0


def is_instance_at_ref(root: str | Path, ref: str) -> bool:
    """An instance at `ref`: `.specflow.yml` or `.stack` committed there. A PR that adds or deletes either file
    cannot change what its own base is (PR #42 code-mode finding)."""
    return any(_at_ref(Path(root), ref, m) for m in INSTANCE_MARKERS)


def instance_mismatch_note(root: str | Path, ref: str) -> str | None:
    """A note naming the marker file(s) when the working tree and `ref` disagree about instance-ness, else None."""
    root = Path(root)
    base, head = is_instance_at_ref(root, ref), _is_instance(root)
    if base == head:
        return None
    if base:
        files = [m for m in INSTANCE_MARKERS if _at_ref(root, ref, m) and not (root / m).is_file()]
        what = f"the working tree lacks {', '.join(files)} that {ref} has"
    else:
        files = [m for m in INSTANCE_MARKERS if (root / m).is_file() and not _at_ref(root, ref, m)]
        what = f"the working tree has {', '.join(files)} that {ref} lacks"
    return (f"note: {what}; judged as at {ref} ({'an instance' if base else 'the template source'}) — "
            f"instance-ness is read at the base, so the PR cannot swap its own policy")


def load_at_ref(root: str | Path, ref: str) -> Pack | None:
    """The governing pack as committed at `ref`, with instance-ness judged at `ref` too (`is_instance_at_ref`):
    `.specflow/pack.yml` at the ref in an instance (python's defaults when the ref has none, as `load` does),
    `scripts/template-pack.yml` at the ref in the template source. Returns None only when the ref is the template
    source and has no `scripts/template-pack.yml` (the bootstrap PR that adds it); raises PackError when the file at
    the ref cannot be parsed."""
    root = Path(root)
    instance = is_instance_at_ref(root, ref)
    rel = ".specflow/pack.yml" if instance else "scripts/template-pack.yml"
    p = subprocess.run(["git", "-C", str(root), "show", f"{ref}:{rel}"], capture_output=True, text=True)
    if p.returncode != 0:
        if instance:
            return Pack(
                origin=f"python defaults (no {rel} at {ref})",
                source_roots=("src",),
                test_globs=("tests/**/test_*.py",),
                rules=(Rule(source="src/**", tests=("tests/**/test_*.py",), cfg_test=False),),
                non_source=(),
                coverage_exclude=(),
            )
        return None
    try:
        cfg = config.parse(p.stdout)
    except config.ConfigError as e:
        raise PackError(f"{ref}:{rel}: {e}") from e
    return _build(cfg, f"{ref}:{rel}")


def _ref_resolves(root: Path, ref: str) -> bool:
    return subprocess.run(["git", "-C", str(root), "rev-parse", "-q", "--verify", f"{ref}^{{commit}}"],
                          capture_output=True).returncode == 0


def _read(root: Path, ref: str | None, rel: str) -> str | None:
    """`rel`'s text in the checkout (ref None) or as committed at `ref`; None when it is absent there."""
    if ref is None:
        p = root / rel
        return p.read_text() if p.is_file() else None
    p = subprocess.run(["git", "-C", str(root), "show", f"{ref}:{rel}"], capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


def _instance(root: Path, ref: str | None) -> bool:
    if ref is None:
        return _is_instance(root)
    if not _ref_resolves(root, ref):
        raise PackError(f"cannot resolve {ref} to read the governing pack there")
    return is_instance_at_ref(root, ref)


def stack(root: str | Path, ref: str | None = None) -> str:
    """The governing pack's stack (P6 R2): `.specflow/pack.yml`'s `stack:` in an instance, else the `.specflow.yml`'s
    `stack`, else a legacy `.stack` (config.load's order), else python; `scripts/template-pack.yml`'s (`template`) in
    the template source. With `ref` (the PR's base), instance-ness and every file are read as committed at that ref, as
    `load_at_ref` reads the test-first policy, so a branch that adds or deletes `.specflow.yml` or `.stack` cannot swap
    which release hook runs (Build 2 final review); without it, the checkout. CI passes the base as the full
    `refs/remotes/origin/<base>` (a tag named `origin/<base>` would shadow the short name). An instance's
    `.specflow/pack.yml` or `.specflow.yml` that does not parse raises PackError — never python's hook by default."""
    root = Path(root)
    if _instance(root, ref):
        for rel in (".specflow/pack.yml", ".specflow.yml"):
            text = _read(root, ref, rel)
            try:
                v = config.parse(text).get("stack") if text is not None else None
            except config.ConfigError as e:
                # fail closed (Build 2 fix wave 2): a file that does not parse never falls through to python's hook
                raise PackError(f"{f'{ref}:{rel}' if ref else rel}: {e}") from e
            if v:
                return str(v)
        legacy = _read(root, ref, ".stack")
        if legacy and legacy.strip():
            return legacy.strip()
        return "python"
    where = f"{ref}:scripts/template-pack.yml" if ref else "scripts/template-pack.yml"
    text = _read(root, ref, "scripts/template-pack.yml")
    if text is None:
        raise PackError(f"no {where} in the template source at {root}")
    try:
        v = config.parse(text).get("stack")
    except config.ConfigError as e:
        raise PackError(f"{where}: {e}") from e
    if not v:
        raise PackError(f"{where} has no stack:")
    return str(v)


def get(root: str | Path, key: str, ref: str | None = None) -> str:
    """One key of the governing pack (P6 R15, F35, F36): `.specflow/pack.yml` in an instance, `scripts/template-pack.yml`
    in the template source, read at `ref` when given (as `stack`). A key the pack does not carry prints empty (an
    instance without it keeps its line)."""
    root = Path(root)
    rel = ".specflow/pack.yml" if _instance(root, ref) else "scripts/template-pack.yml"
    where = f"{ref}:{rel}" if ref else str(root / rel)
    text = _read(root, ref, rel)
    if text is None:
        raise PackError(f"no pack file at {where}")
    try:
        v = config.parse(text).get(key)
    except config.ConfigError as e:
        raise PackError(f"{where}: {e}") from e
    return "" if v is None else str(v)


def same_policy(a: Pack, b: Pack) -> bool:
    """True when two packs carry the same test-first policy (origin aside)."""
    return (a.source_roots, a.test_globs, a.rules, a.non_source) == (b.source_roots, b.test_globs, b.rules, b.non_source)


def main(argv: list[str]) -> int:
    args = list(argv)
    root, ref = ".", None
    while args[:1] in (["--root"], ["--ref"]) and len(args) >= 2:
        if args[0] == "--root":
            root = args[1]
        else:
            ref = args[1]
        args = args[2:]
    if args != ["stack"] and not (len(args) == 2 and args[0] == "get"):
        print("usage: packinfo.py [--root DIR] [--ref REF] stack | get KEY", file=sys.stderr)
        return 2
    try:
        print(stack(root, ref) if args == ["stack"] else get(root, args[1], ref))
    except PackError as e:
        print(f"packinfo: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
