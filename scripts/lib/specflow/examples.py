#!/usr/bin/env python3
"""REQ-306: the one reader of CLAUDE.md's "## Canonical Example" manifest.

Manifest shape: under the "## Canonical Example" heading, one subsection per
example — a "### <name> (stack: <stack>)" line followed by prose. A
backticked token containing "/" is a path belonging to that example; one
path per token (no brace expansion). A subsection runs to the next "### "
or "## " line, or end of file.

Shared by scripts/init-project.sh and tests/governance/test_examples.sh —
neither should re-parse CLAUDE.md on its own.
"""
import re
import sys

SECTION_RE = re.compile(r'^### (\S+) \(stack: (\S+)\)[ \t]*$', re.MULTILINE)
PATH_RE = re.compile(r'`([^`]*/[^`]*)`')


def _section_end(text, start):
    """Where the subsection starting at `start` (just past its heading) ends:
    the next '### ' or '## ' line, or end of text."""
    m = re.search(r'^#{2,3} ', text[start:], re.MULTILINE)
    return start + m.start() if m else len(text)


def parse(text):
    """Return {name: (stack, [paths])} for every example in the manifest."""
    result = {}
    for m in SECTION_RE.finditer(text):
        name, stack = m.group(1), m.group(2)
        end = _section_end(text, m.end())
        result[name] = (stack, PATH_RE.findall(text[m.end():end]))
    return result


def strip(text, name):
    """Return `text` with the `### <name> (...)` subsection (heading and
    body) removed. Raises KeyError if `name` is not in the manifest."""
    for m in SECTION_RE.finditer(text):
        if m.group(1) != name:
            continue
        end = _section_end(text, m.end())
        return text[:m.start()] + text[end:]
    raise KeyError(name)


def main(argv):
    root = "."
    args = list(argv)
    if len(args) >= 2 and args[0] == "--root":
        root = args[1]
        args = args[2:]
    if not args:
        print("usage: examples.py [--root DIR] names|list NAME|strip NAME", file=sys.stderr)
        return 2

    path = f"{root}/CLAUDE.md"
    with open(path) as f:
        text = f.read()
    manifest = parse(text)

    cmd, rest = args[0], args[1:]
    if cmd == "names":
        for name, (stack, _paths) in manifest.items():
            print(f"{name} {stack}")
        return 0

    if cmd in ("list", "strip"):
        if not rest or rest[0] not in manifest:
            got = rest[0] if rest else ""
            print(f"examples.py: unknown example {got!r}", file=sys.stderr)
            return 2
        name = rest[0]
        if cmd == "list":
            for p in manifest[name][1]:
                print(p)
            return 0
        with open(path, "w") as f:
            f.write(strip(text, name))
        return 0

    print(f"examples.py: unknown command {cmd!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
