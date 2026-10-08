#!/usr/bin/env python3
"""The one reader of .specflow.yml (REQ-301).

Flat key: value parsing only — no PyYAML, no nesting. A legacy `.stack` file
(one bare word) is a fallback for the `stack` key alone, and only when
`--root` is used (never for `--file`, and never when `.specflow.yml` itself
already carries a `stack:` key).

Configuration, not pipeline state (art-branch-as-state): this file only ever
records how the project is configured (profile, path, stack, ...), never
where the pipeline currently stands.
"""
from __future__ import annotations

import sys
from pathlib import Path

KEYS = ("profile", "path", "stack", "solo", "coverage_min", "signing")

DEFAULTS = {
    "profile": "guided",
    "path": "lanes",
    "stack": "python",
    "solo": "true",
    "coverage_min": "80",
    "signing": "none",
}


class ConfigError(ValueError):
    """A .specflow.yml (or --file) document could not be parsed or is invalid."""


def _strip_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def _strip_comment(s: str) -> str:
    # Drop a trailing " #..." comment: a '#' that follows whitespace, or
    # starts the value, outside any quoted span. A '#' inside quotes, or
    # glued to a preceding non-whitespace char, is left alone.
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


def parse(text: str) -> dict:
    """Parse a flat `key: value` document. Blank lines and full-line `#`
    comments are ignored. An indented line, or a line with no `:`, is a
    parse error (it signals nested YAML, which this reader does not
    support)."""
    cfg: dict[str, str] = {}
    for raw in text.splitlines():
        if not raw.strip():
            continue
        if raw.lstrip().startswith("#"):
            continue
        if raw[0] in (" ", "\t"):
            raise ConfigError(f"indented line (nested YAML is not supported): {raw!r}")
        if ":" not in raw:
            raise ConfigError(f"line has no ':': {raw!r}")
        k, v = raw.split(":", 1)
        k = k.strip()
        if not k:
            raise ConfigError(f"empty key: {raw!r}")
        cfg[k] = _strip_quotes(_strip_comment(v.strip()))
    return cfg


def parse_list(s: str):
    """Parse a flat `[a, "b", c]` flow-sequence value."""
    s = s.strip().strip("[]")
    if not s:
        return []
    return [_strip_quotes(x) for x in s.split(",") if _strip_quotes(x)]


def load(root: Path) -> dict:
    """Load `<root>/.specflow.yml`, falling back to a legacy `<root>/.stack`
    (a bare stack name) to supply `stack` only when the file itself is
    absent, or present but missing that key."""
    root = Path(root)
    cfg: dict[str, str] = {}
    yml = root / ".specflow.yml"
    if yml.is_file():
        cfg = parse(yml.read_text())
    if "stack" not in cfg:
        legacy = root / ".stack"
        if legacy.is_file():
            stack = legacy.read_text().strip()
            if stack:
                cfg["stack"] = stack
    return cfg


def validate(cfg: dict) -> list:
    """Return one message per key whose value is not allowed. An empty list
    means the config is valid."""
    errors = []
    allowed = {
        "profile": ("guided", "engineer"),
        "path": ("lanes", "regulated"),
        "stack": ("python", "tauri", "flutter"),
        "solo": ("true", "false"),
        "signing": ("none", "apple"),  # P6 R23: none (the five APPLE_* secrets absent) or apple (all five present)
    }
    for key, choices in allowed.items():
        if key not in cfg:
            continue
        v = cfg[key]
        if choices is None:
            if not v:
                errors.append(f"{key}: must be non-empty")
        elif v not in choices:
            errors.append(f"{key}: {v!r} must be one of {', '.join(choices)}")
    if "coverage_min" in cfg:
        v = cfg["coverage_min"]
        try:
            n = int(v)
            if not 0 <= n <= 100:
                raise ValueError
        except ValueError:
            errors.append(f"coverage_min: {v!r} must be an integer 0-100")
    return errors


def dump(cfg: dict) -> str:
    """Render `cfg` (filled with DEFAULTS for any missing key) as the
    canonical `.specflow.yml` document, KEYS in order."""
    filled = dict(DEFAULTS)
    filled.update(cfg)
    lines = ["# SpecFlow configuration, not pipeline state (art-branch-as-state)"]
    for k in KEYS:
        lines.append(f"{k}: {filled[k]}")
    return "\n".join(lines) + "\n"


def _die(msg: str, code: int = 2):
    print(f"config: {msg}", file=sys.stderr)
    sys.exit(code)


def main(argv):
    root = None
    file_path = None
    args = list(argv)
    while args and args[0] in ("--root", "--file"):
        flag = args.pop(0)
        if not args:
            _die(f"{flag} needs a value")
        val = args.pop(0)
        if flag == "--root":
            root = Path(val)
        else:
            file_path = Path(val)

    if not args:
        _die("usage: config.py [--root DIR | --file PATH] get|getlist|write|validate ...")
    cmd = args.pop(0)

    def _load():
        try:
            if file_path is not None:
                if not file_path.is_file():
                    raise ConfigError(f"{file_path} not found")
                return parse(file_path.read_text())
            r = root or Path(".")
            return load(r)
        except ConfigError as e:
            _die(str(e))

    if cmd == "get":
        if not args:
            _die("get needs KEY")
        key = args.pop(0)
        default = None
        have_default = False
        if args:
            if args[0] != "--default" or len(args) < 2:
                _die(f"unrecognised arguments to get: {args}")
            have_default = True
            default = args[1]
        cfg = _load()
        if key in cfg:
            print(cfg[key])
            return
        if have_default:
            print(default)
            return
        sys.exit(1)

    if cmd == "getlist":
        if not args:
            _die("getlist needs KEY")
        key = args.pop(0)
        cfg = _load()
        if key not in cfg:
            sys.exit(1)
        for item in parse_list(cfg[key]):
            print(item)
        return

    if cmd == "write":
        if file_path is not None:
            _die("write requires --root, not --file")
        r = root or Path(".")
        try:
            existing = load(r)
        except ConfigError as e:
            _die(str(e))
        cfg = dict(existing)
        for kv in args:
            if "=" not in kv:
                _die(f"write arguments must be KEY=VALUE: {kv!r}")
            k, v = kv.split("=", 1)
            cfg[k] = v
        r.mkdir(parents=True, exist_ok=True)
        (r / ".specflow.yml").write_text(dump(cfg))
        return

    if cmd == "validate":
        cfg = _load()
        errors = validate(cfg)
        if errors:
            for e in errors:
                print(e, file=sys.stderr)
            sys.exit(2)
        return

    _die(f"unknown command: {cmd!r}")


if __name__ == "__main__":
    main(sys.argv[1:])
