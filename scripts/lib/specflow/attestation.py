#!/usr/bin/env python3
"""The one home of the attestation rules (REQ-311, ADR-003).

Marker grammar, HTML-comment sanitising, verdict derivation, the findings
digest, the base-ref prompt hash, the base-ref policy read, and the review
scope classifier all live here as pure functions behind thin `argparse`
subcommands, so both the CI check (`attestation.py check`) and
`run-verifier.sh` (the base ref's copy) share one implementation rather than
two copies of the same rules. `next.sh` imports this module as a second
consumer, through `pr_attestation`: the one function that gathers a PR's inputs
and classifies them, which the CI check calls too.

This module never trusts the working tree for anything that must be read at
a git ref (the prompt hash, policy, review scope): those subcommands take
`--ref`/`--base`/`--head` and call out to `git show`/`git diff`.

The Dependabot exemption (REQ-334 as amended, dfe-13; REQ-311; P4) needs more
than "every commit's GitHub author is dependabot[bot]" (P2's rule): a
commit's author *email* is anyone-settable by whoever has push access, so an
author match alone proves nothing about who actually made the commit. The
exemption also requires every commit to carry `verification.verified: true`
with a committer login in `DEPENDABOT_COMMITTERS` — but that does not tie a
commit to Dependabot either: GitHub gives every commit made through its API or
UI committer web-flow and verified=true with a caller-chosen author (real
Dependabot commits are committed by web-flow, measured 2026-09-27), so anyone
with write access can create such a commit through the GitHub API. It only
rules out a plain `git push` with a forged author. The real limit is the
content rule: a diff that touches only dependency manifests/lockfiles (never
`.github/`), adds no file the base lacks, lists exactly the base's dependency
names in every manifest kind and moves versions and nothing else, with every
npm lockfile entry resolved to the public registry's tarball of its own
package and version (`DEPENDENCY_FILES`, `dependabot_exemption`'s content
rules). A forged commit can still move an existing dependency to another
registry version of the same package unreviewed — threat-model dfe-13's
residual.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import random
import re
import subprocess
import sys
import tomllib
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import config  # noqa: E402  (after sys.path insert)

# --- field grammars, shared by make_marker and parse_marker ---------------

MODES = ("full", "persona", "code", "full+code", "persona+code", "skipped")
VERDICTS = ("APPROVE", "REQUEST_CHANGES")
ORIGINS = ("headless", "in-session")

_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_MODEL = re.compile(r"^[A-Za-z0-9._:\[\]-]+$")

FIELD_PATTERNS = {
    "mode": lambda v: v in MODES,
    "sha": lambda v: bool(_HEX40.match(v)),
    "base": lambda v: bool(_HEX40.match(v)),
    "prompt_sha256": lambda v: v == "null" or bool(_HEX64.match(v)),
    "model": lambda v: v == "none" or bool(_MODEL.match(v)),
    "verdict": lambda v: v in VERDICTS,
    "digest": lambda v: bool(_HEX64.match(v)),
    "origin": lambda v: v in ORIGINS,
}

FIELD_ORDER = ("mode", "sha", "base", "prompt_sha256", "model", "verdict", "digest", "origin")

MARKER_RE = re.compile(
    r"^<!-- specflow-verifier:(?P<mode>[^\s]+) sha:(?P<sha>[^\s]+) base:(?P<base>[^\s]+) "
    r"prompt_sha256:(?P<prompt_sha256>[^\s]+) model:(?P<model>[^\s]+) verdict:(?P<verdict>[^\s]+) "
    r"digest:(?P<digest>[^\s]+) origin:(?P<origin>[^\s]+) -->$"
)

_SHA40 = re.compile(r"\A[0-9a-f]{40}\Z")

# P7 R4 (REQ-382): a waiver binds a base as a marker does. Bound: `... sha:<head> base:<base> -->`; legacy: `... sha:<head> -->`
# (judged by the PR's timeline instead). Any other first line starting `<!-- specflow-verifier:waive` is malformed.
WAIVER_RE = re.compile(r"^<!-- specflow-verifier:waive sha:(?P<sha>[0-9a-f]{40})(?: base:(?P<base>[0-9a-f]{40}))? -->$")


class AttestationError(Exception):
    def __init__(self, message: str, code: int = 2):
        super().__init__(message)
        self.code = code


# --- marker -----------------------------------------------------------------

def make_marker(*, mode, sha, base, prompt_sha256, model, verdict, digest, origin) -> str:
    fields = {
        "mode": mode,
        "sha": sha,
        "base": base,
        "prompt_sha256": prompt_sha256,
        "model": model,
        "verdict": verdict,
        "digest": digest,
        "origin": origin,
    }
    for name in FIELD_ORDER:
        v = fields[name]
        if not FIELD_PATTERNS[name](v):
            raise AttestationError(f"marker: invalid {name}: {v!r}")
    return (
        "<!-- specflow-verifier:{mode} sha:{sha} base:{base} prompt_sha256:{prompt_sha256} "
        "model:{model} verdict:{verdict} digest:{digest} origin:{origin} -->"
    ).format(**fields)


def parse_marker(line: str):
    """Parse a marker's first line. Returns a dict of fields, or None when
    `line` does not match the grammar at all."""
    m = MARKER_RE.match(line.strip())
    if not m:
        return None
    return m.groupdict()


# --- sanitising (dfe-8) ------------------------------------------------------

def _sanitize_pass(text: str) -> str:
    """One left-to-right scan removing HTML comments. Exposed for
    `sanitize`'s fixpoint loop: a single pass can rejoin fragments on
    either side of a removed comment into a brand-new `<!--` sequence
    (e.g. `<<!-- x -->!-- y -->` -> `<!-- y -->`), so one pass alone is
    not enough to guarantee no comment opener survives."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        start = text.find("<!--", i)
        if start == -1:
            out.append(text[i:])
            break
        out.append(text[i:start])
        end = text.find("-->", start + 4)
        if end == -1:
            # Unterminated: neutralise the opener and keep the rest as text.
            out.append("&lt;!-- ")
            i = start + 4
            continue
        i = end + 3
    return "".join(out)


def sanitize(text: str) -> str:
    """Strip every HTML comment, including multi-line ones, so the model
    cannot smuggle a forged marker or hidden text into the posted comment.
    An unterminated `<!--` is neutralised (HTML-escaped) rather than left to
    swallow the remainder of the comment silently.

    Idempotent by construction: removing a comment can rejoin the text on
    either side of it into a *new* `<!--...-->` sequence (a fragment ending
    in `<` immediately followed by a fragment starting `!-- ... -->`), so a
    single pass is not sufficient. Re-scan to a fixpoint — each pass either
    removes a real comment or permanently escapes an unterminated opener, so
    the text only shrinks or stays the same and this always converges, with
    no raw `<!--` left in the result."""
    result = text
    for _ in range(len(text) + 1):
        nxt = _sanitize_pass(result)
        if nxt == result:
            break
        result = nxt
    # Collapse the whitespace-only lines left behind by removed comments
    # (trailing blanks, then a blank line) into one blank line. Runs of
    # spaces/tabs elsewhere, and the next line's leading indentation, are
    # kept: posted findings keep code in fenced blocks and nested lists.
    result = re.sub(r"[ \t]*\n[ \t]*\n", "\n\n", result)
    return result


# --- verdict ------------------------------------------------------------------

def verdict(text: str) -> str:
    """The verdict is the tail's last non-empty line, exactly `APPROVE` or
    `REQUEST_CHANGES`. Anything else (trailing punctuation, extra text,
    wrong case, no non-empty line at all) is not a verdict."""
    lines = [ln.rstrip("\r") for ln in text.split("\n")]
    non_empty = [ln for ln in lines if ln.strip() != ""]
    if not non_empty:
        raise AttestationError("verdict: no non-empty line", code=9)
    last = non_empty[-1].strip()
    if last not in VERDICTS:
        raise AttestationError(f"verdict: last non-empty line is not a verdict: {last!r}", code=9)
    return last


# --- digest -------------------------------------------------------------------

def normalize(t: str) -> str:
    return t.replace("\r\n", "\n").rstrip("\n") + "\n"


def digest(tail: str) -> str:
    return hashlib.sha256(normalize(tail).encode("utf-8")).hexdigest()


# --- git helpers ----------------------------------------------------------

def _git_show(ref: str, path: str) -> bytes:
    """`git show ref:path`. Raises AttestationError(code=3) when the path is
    absent at that ref (the caller decides what "absent" means); any other
    git failure raises AttestationError(code=2) with git's message."""
    proc = subprocess.run(
        ["git", "show", f"{ref}:{path}"], capture_output=True
    )
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", "replace")
        if "does not exist" in stderr or "exists on disk, but not in" in stderr or "fatal: path" in stderr:
            raise AttestationError(f"absent: {path} at {ref}", code=3)
        raise AttestationError(stderr.strip() or f"git show {ref}:{path} failed", code=2)
    return proc.stdout


def _path_exists_at_ref(ref: str, path: str) -> bool:
    try:
        _git_show(ref, path)
        return True
    except AttestationError as e:
        if e.code == 3:
            return False
        raise


# --- prompt hash --------------------------------------------------------------

SKILL_PATH = ".claude/skills/verifier/SKILL.md"
PROMPT_PATH = ".claude/skills/verifier/headless-prompt.md"


def prompt_hash(ref: str) -> str:
    """sha256(SKILL.md bytes + NUL + headless-prompt.md bytes) at `ref`. A
    ref without the prompt template predates attestation (exit 3)."""
    try:
        skill_bytes = _git_show(ref, SKILL_PATH)
    except AttestationError as e:
        if e.code == 3:
            raise AttestationError("base-predates-attestation: no SKILL.md at ref", code=3)
        raise
    try:
        prompt_bytes = _git_show(ref, PROMPT_PATH)
    except AttestationError as e:
        if e.code == 3:
            raise AttestationError("base-predates-attestation: no headless-prompt.md at ref", code=3)
        raise
    return hashlib.sha256(skill_bytes + b"\x00" + prompt_bytes).hexdigest()


# --- policy -------------------------------------------------------------------

def policy(ref: str) -> dict:
    """Read `solo`, `profile`, `path` at `ref` (never the working tree),
    filled with config.DEFAULTS for whatever `.specflow.yml` at that ref
    does not set. A `solo` value other than `true`/`false` fails closed
    (exit 4)."""
    try:
        text = _git_show(ref, ".specflow.yml").decode("utf-8")
        cfg = config.parse(text)
    except AttestationError as e:
        if e.code == 3:
            cfg = {}
        else:
            raise
    except config.ConfigError as e:
        raise AttestationError(f"policy: {e}", code=4)
    solo = cfg.get("solo", config.DEFAULTS["solo"])
    if solo not in ("true", "false"):
        raise AttestationError(f"policy: solo: {solo!r} must be true or false", code=4)
    profile = cfg.get("profile", config.DEFAULTS["profile"])
    path = cfg.get("path", config.DEFAULTS["path"])
    return {"solo": solo, "profile": profile, "path": path}


# --- review scope (REQ-310, H8) -----------------------------------------------

# .gitignore (art-secrets-hygiene's .env* guard) and .gitattributes (filters,
# diff drivers) are configuration the repository's behaviour depends on: code.
_OTHER_BASENAMES_EXACT = {".editorconfig"}
# Licence and notice files are "other" only as these exact repository-root
# paths: src/LICENSE_check.py or docs/NOTICE is code like anything else.
_OTHER_ROOT_PATHS = {"LICENSE", "LICENSE.md", "LICENSE.txt", "NOTICE", "NOTICE.md", "NOTICE.txt"}
_OTHER_IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico")

# .md paths under these prefixes are both a document and code.
_DOC_AND_CODE_PREFIXES = (".claude/", ".github/")


def _is_model_instruction_md(path: str) -> bool:
    """Markdown that instances load as session instructions (#33 fourth run
    finding 10), so it is both a document and code: any CLAUDE.md or
    CLAUDE.local.md at any depth (Claude Code loads nested ones from every
    subdirectory it works in — PR #34 third-run finding 4), Markdown under a
    stack's overlay/ or skeleton/ directory (init-project.sh copies these into
    a new project), and Markdown under templates/. overlay/ and skeleton/
    count only as the third segment, stacks/<stack>/overlay/... (PR #34
    second-run finding 7): stacks/overlay/x.md is a plain document."""
    parts = path.split("/")
    if parts[-1] in ("CLAUDE.md", "CLAUDE.local.md"):
        return True
    if parts[0] == "templates" and len(parts) > 1:
        return True
    if parts[0] == "stacks" and len(parts) > 1:
        if len(parts) > 3 and parts[2] in ("overlay", "skeleton"):
            return True
    return False


def _basename(path: str) -> str:
    return path.rsplit("/", 1)[-1]


def _is_other(path: str) -> bool:
    base = _basename(path)
    if base in _OTHER_BASENAMES_EXACT:
        return True
    if path in _OTHER_ROOT_PATHS:
        return True
    lower = base.lower()
    if any(lower.endswith(ext) for ext in _OTHER_IMAGE_EXTS):
        return True
    return False


def _classify_path(path: str):
    """Return a set of {"doc", "code"} (never both empty unless "other")."""
    if _is_other(path):
        return set()
    is_md = path.endswith(".md")
    if is_md:
        if path.startswith(_DOC_AND_CODE_PREFIXES) or _is_model_instruction_md(path):
            return {"doc", "code"}
        return {"doc"}
    return {"code"}


def review_scope(base: str, head: str) -> dict:
    proc = subprocess.run(
        # --no-renames: a rename is listed as its old path (a deletion) and its
        # new path (an addition), so renaming a gated file to an allowlisted
        # name (constitution.md -> constitution.png) cannot leave review.
        ["git", "diff", "--no-renames", "--name-only", f"{base}...{head}"],
        capture_output=True,
    )
    if proc.returncode != 0:
        raise AttestationError(proc.stderr.decode("utf-8", "replace").strip() or "git diff failed", code=2)
    paths = [p for p in proc.stdout.decode("utf-8").splitlines() if p]
    docs = []
    codes = []
    others = []
    for p in paths:
        classes = _classify_path(p)
        if not classes:
            others.append(p)
            continue
        if "doc" in classes:
            docs.append(p)
        if "code" in classes:
            codes.append(p)
    if docs and codes:
        mode = "full+code"
    elif docs:
        mode = "full"
    elif codes:
        mode = "code"
    else:
        mode = "skipped"
    return {"mode": mode, "docs": docs, "code": codes, "other": others}


# --- classifier (REQ-311, REQ-382; dfe-2; ADR-003) --------------------------
#
# Reduces a PR's comments to ADR-003's Attestation = none | approve |
# request_changes | waiver. One per-comment judgement (reason, blocking or
# not, accepted state) applies the rules in the stated order; classify()
# and explain() share this one function so the rules are written once.

_TRUSTED = ("OWNER", "MEMBER", "COLLABORATOR")
DEPENDABOT = "dependabot[bot]"

# REQ-334 as amended (dfe-13): a verified commit's committer is dependabot[bot]
# itself, or web-flow for a commit made through the GitHub API/UI. Real
# Dependabot commits are committed by web-flow (measured 2026-09-27), which is
# also what any write-access user's API commit gets — this narrows, it does not
# authenticate; the content rules are the real limit.
DEPENDABOT_COMMITTERS = {"dependabot[bot]", "web-flow"}

# R11: a path is a dependency file when its basename is one of these, at any
# depth, and it is not under .github/ (checked separately: Dependabot never
# edits its own workflow files or configuration, and .github/dependabot.yml
# is excluded on purpose — see the plan's Ruling R11). pyproject.toml and
# .github/dependabot.yml are deliberately absent.
DEPENDENCY_FILES = {
    "requirements.txt", "requirements.in", "package.json", "package-lock.json",
    "Cargo.toml", "Cargo.lock", "pubspec.yaml", "pubspec.lock",
}


def commit_author(commit):
    """One entry of `gh api pulls/<pr>/commits` → its author's GitHub login,
    or, when GitHub could not map the author to an account (`author` null),
    "<name> <<email>>" from the commit itself — a string that can never
    equal a login, so a null author never counts as dependabot[bot]."""
    a = commit.get("author")
    if isinstance(a, dict) and a.get("login"):
        return a["login"]
    ca = (commit.get("commit") or {}).get("author") or {}
    return f"{ca.get('name', '')} <{ca.get('email', '')}>"


def commit_committer(commit):
    """One entry of `gh api pulls/<pr>/commits` → its committer's GitHub
    login, or None when GitHub could not map it (a null `committer`, or the
    key missing) — never a string that could coincidentally match a
    `DEPENDABOT_COMMITTERS` entry."""
    c = commit.get("committer")
    if isinstance(c, dict) and c.get("login"):
        return c["login"]
    return None


def _sha7(commit):
    sha = commit.get("sha") or ""
    return sha[:7] if sha else "0000000"


# --- Dependabot content rules (R11 "Content, not just paths") ---------------

_REQ_HASH_RE = re.compile(r"^\s*--hash=sha256:[0-9a-f]{64}\s*\\?\s*$")
# An environment marker after `;` may hold anything but `--`: pip reads a
# per-line option (`--config-settings`, `--global-option`, …) after the marker,
# and no PEP 508 marker contains `--` (#36 low).
_REQ_MARKER = r"(\s*;(?:(?!--).)+)?"
_REQ_TXT_RE = re.compile(r"^[A-Za-z0-9._-]+(\[[A-Za-z0-9,._-]+\])?==[^\s;]+" + _REQ_MARKER + r"\s*\\?\s*$")
_REQ_IN_RE = re.compile(r"^[A-Za-z0-9._-]+(\[[A-Za-z0-9,._-]+\])?(==|>=|<=|!=|~=|>|<)[^\s;]+" + _REQ_MARKER + r"\s*\\?\s*$")

_NPM_DEP_KEYS = ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies")
# A registry range only (#36 second run, low): every comparator carries a
# version that starts with a digit, so a dist-tag (`latest`, `next`, `beta`),
# a bare `*`/`x`, or any token without a digit is refused — a pinned range
# cannot become a floating tag. Forms: `^1.2.3`, `~1.2`, `>=1.0.0 <2.0.0`,
# `>= 1.0.0`, `1.x`, `1.0.0 - 2.0.0`, `^1.0.0 || ^2.0.0`, `1.2.3-beta.1`.
_NPM_COMPARATOR = r"(?:[<>]=?|[=^~])?\s*v?\d+(?:\.(?:\d+|[xX*])){0,2}(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"
_NPM_RANGE = (r"(?:" + _NPM_COMPARATOR + r"\s+-\s+" + _NPM_COMPARATOR
              + r"|" + _NPM_COMPARATOR + r"(?:\s+" + _NPM_COMPARATOR + r")*)")
_NPM_VERSION_RE = re.compile(r"^\s*" + _NPM_RANGE + r"(?:\s*\|\|\s*" + _NPM_RANGE + r")*\s*$")


def _npm_version_ok(v):
    """True when `v` is a registry range `_NPM_VERSION_RE` accepts."""
    return isinstance(v, str) and bool(_NPM_VERSION_RE.match(v))


_CARGO_DEP_KEYS = ("dependencies", "dev-dependencies", "build-dependencies")
_CARGO_LOCK_OK_SOURCES = (
    None,
    "registry+https://github.com/rust-lang/crates.io-index",
    "sparse+https://index.crates.io/",
)

_PUBSPEC_LINE_RE = re.compile(r'^\s+[a-z0-9_]+:\s*["\']?[\^~<>=]*\d[\w.+-]*["\']?\s*$')


def _lines(text):
    return text.splitlines() if text else []


def _added_lines(base, head):
    """The head's lines absent from the base's (R9/R11's "added lines")."""
    base_lines = set(_lines(base))
    return [ln for ln in _lines(head) if ln not in base_lines]


def _requirement_names(text, pattern):
    """The PEP 503-normalised project names `text` pins or constrains — one per
    line matching `pattern`; comments, blanks, hash and option lines skipped."""
    names = set()
    for ln in _lines(text):
        stripped = ln.strip()
        if stripped == "" or stripped.startswith("#") or _REQ_HASH_RE.match(ln) or stripped.startswith("-"):
            continue
        if pattern.match(stripped):
            name = re.match(r"^[A-Za-z0-9._-]+", stripped).group(0)
            names.add(re.sub(r"[-_.]+", "-", name).lower())
    return names


_REQ_SPEC_PARTS_RE = re.compile(
    r"^(?P<name>[A-Za-z0-9._-]+)(?P<extras>\[[^\]]*\])?(?:==|>=|<=|!=|~=|>|<)[^\s;]+(?P<rest>.*)$")


def _requirements_model(text, pattern):
    """A requirements file read both ways (#36 second run, high): its option
    lines (every line starting with `-`: `--index-url`, `--extra-index-url`,
    `--find-links`, `--trusted-host`, `--pre`, `-r`, `-c`, `-e`, …), each
    project's requirement lines and the `--hash=` lines that follow them
    (hashes before any requirement are orphans), and every other
    non-comment line. Comments and blanks carry no meaning and are skipped."""
    options, others, orphans, reqs = Counter(), Counter(), set(), {}
    cur = None
    for ln in _lines(text):
        s = ln.strip()
        if s == "" or s.startswith("#"):
            continue
        if _REQ_HASH_RE.match(ln):
            h = s.rstrip("\\").strip()
            (reqs[cur]["hashes"] if cur is not None else orphans).add(h)
            continue
        cur = None
        if s.startswith("-"):
            options[s.rstrip("\\").strip()] += 1
        elif pattern.match(s):
            m = _REQ_SPEC_PARTS_RE.match(s.rstrip("\\").strip())
            cur = re.sub(r"[-_.]+", "-", m.group("name")).lower()
            entry = reqs.setdefault(cur, {"specs": set(), "identity": set(), "hashes": set()})
            entry["specs"].add(s.rstrip("\\").strip())
            entry["identity"].add((cur, m.group("extras") or "", m.group("rest").strip()))
        else:
            others[s] += 1
    return options, others, orphans, reqs


def _requirements_rule(path, base, head, is_in):
    """Only versions (and, with them, hashes) of the base's pins move — checked
    both ways (#36 second run, high). Refused: a new or dropped project
    (`new-dependency`); any option line the head REMOVES (`removed-option` —
    dropping `--index-url` sends pip to public PyPI) and any other
    non-requirement line it removes (`removed-line`); a pin whose extras or
    environment marker change (`requirement-line`); a `--hash=` line added,
    removed or rewritten for a project whose version did not change, or an
    orphan hash changed (`hash-changed`); and, on the added side, any line
    that is not a plain pin, a hash or a comment (`requirement-line`: an
    index/find-links/trusted-host option, a URL, a VCS or `@` source)."""
    pattern = _REQ_IN_RE if is_in else _REQ_TXT_RE
    if _requirement_names(base, pattern) != _requirement_names(head, pattern):
        return False, f"content:{path}:new-dependency"
    b_opts, b_other, b_orphans, b_reqs = _requirements_model(base, pattern)
    h_opts, h_other, h_orphans, h_reqs = _requirements_model(head, pattern)
    if b_opts - h_opts:
        return False, f"content:{path}:removed-option"
    if b_other - h_other:
        return False, f"content:{path}:removed-line"
    for name in sorted(set(b_reqs) | set(h_reqs)):
        b = b_reqs.get(name) or {"specs": set(), "identity": set(), "hashes": set()}
        h = h_reqs.get(name) or {"specs": set(), "identity": set(), "hashes": set()}
        if b["identity"] != h["identity"]:
            return False, f"content:{path}:requirement-line"
        if b["specs"] == h["specs"] and b["hashes"] != h["hashes"]:
            return False, f"content:{path}:hash-changed"
    if b_orphans != h_orphans:
        return False, f"content:{path}:hash-changed"
    for ln in _added_lines(base, head):
        stripped = ln.strip()
        if stripped == "" or stripped.startswith("#"):
            continue
        if _REQ_HASH_RE.match(ln):
            continue
        if stripped.startswith("-") or "://" in ln or " @ " in ln or "git+" in ln:
            return False, f"content:{path}:requirement-line"
        if pattern.match(stripped):
            continue
        return False, f"content:{path}:requirement-line"
    return True, None


def _package_json_rule(path, base, head):
    b = json.loads(base) if base else {}
    h = json.loads(head) if head else {}
    b2 = {k: v for k, v in b.items() if k not in _NPM_DEP_KEYS}
    h2 = {k: v for k, v in h.items() if k not in _NPM_DEP_KEYS}
    if b2 != h2:
        return False, f"content:{path}:non-dependency-key"
    for key in _NPM_DEP_KEYS:
        if set(b.get(key) or {}) != set(h.get(key) or {}):
            return False, f"content:{path}:new-dependency"
    for key in _NPM_DEP_KEYS:
        for v in (h.get(key) or {}).values():
            if not _npm_version_ok(v):
                return False, f"content:{path}:non-registry-spec"
    # Both ways (#36 second run, high): a base entry that is not a registry
    # range (an `npm:` alias, `file:`, a git/GitHub/URL spec) may not move at
    # all — collapsing it to a range would fetch the public package of that
    # name instead.
    for key in _NPM_DEP_KEYS:
        bmap, hmap = b.get(key) or {}, h.get(key) or {}
        for name, bv in bmap.items():
            if hmap.get(name) != bv and not _npm_version_ok(bv):
                return False, f"content:{path}:source-changed"
    return True, None


_NPM_REGISTRY = "https://registry.npmjs.org/"
_NPM_NAME_RE = re.compile(r"^(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*$", re.IGNORECASE)
_SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$")


def _npm_tarball_url(name, version):
    """The public registry's tarball URL for `name`@`version`: the package
    path, then `/-/`, then the unscoped basename and version
    (`@scope/pkg` → `…/@scope/pkg/-/pkg-1.0.0.tgz`)."""
    return f"{_NPM_REGISTRY}{name}/-/{name.rsplit('/', 1)[-1]}-{version}.tgz"


_NPM_DEP_MAPS = ("dependencies", "optionalDependencies", "peerDependencies", "devDependencies")


def _package_lock_rule(path, base, head):
    """Fails closed (#36 high). A lockfile with no `packages` map — lockfile
    version 1, whose entries sit under nested `dependencies` maps — is refused
    outright (`lockfile-v1`), never walked: npm 7+ writes `packages`, so
    Dependabot never produces a v1-only file. In `packages`, every
    `node_modules/<name>` entry (scoped names and nested paths included) must
    carry a plain semver `version`, no alias `name` of its own, and a
    `resolved` that is exactly the public registry's tarball of that name and
    version (`_npm_tarball_url`); a missing `resolved` is allowed (npm then
    fetches that name and version from the registry). A workspace entry (a
    key outside `node_modules/`) may carry no `resolved` at all. So an entry
    cannot point at a VCS/URL source or at another package's tarball; it can
    still move to another registry version of the same package (dfe-13's
    residual). Both sides must carry `packages` (P5 final review): a base
    without one (`base-lockfile-v1`) leaves nothing to check growth against,
    so it fails closed. A v2 file's legacy top-level `dependencies` tree —
    what npm 6 installs from — must mirror `packages` entry for entry
    (`legacy-dependencies`)."""
    h = json.loads(head)
    if not isinstance(h, dict) or "packages" not in h:
        return False, f"content:{path}:lockfile-v1"
    if base is not None:
        b_doc = json.loads(base)
        if not isinstance(b_doc, dict) or not isinstance(b_doc.get("packages"), dict):
            return False, f"content:{path}:base-lockfile-v1"
    packages = h["packages"]
    if not isinstance(packages, dict):
        return False, f"content:{path}:resolved"
    for key, entry in packages.items():
        if not isinstance(entry, dict):
            return False, f"content:{path}:resolved"
        resolved = entry.get("resolved")
        marker = "node_modules/"
        if marker not in key:
            if resolved is not None or entry.get("link"):
                return False, f"content:{path}:resolved"
            continue
        name = key.rsplit(marker, 1)[1]
        version = entry.get("version")
        if (not _NPM_NAME_RE.match(name) or entry.get("link")
                or ("name" in entry and entry["name"] != name)
                or not isinstance(version, str) or not _SEMVER_RE.match(version)):
            return False, f"content:{path}:resolved"
        if resolved is not None and resolved != _npm_tarball_url(name, version):
            return False, f"content:{path}:resolved"
    # R10: an npm lockfile may not grow. A `node_modules/<name>` key the base's
    # `packages` map lacks, or a name added to any entry's dependency maps, is
    # refused; ranges may move and entries may disappear.
    b0 = json.loads(base) if base else {}
    b0_packages = b0.get("packages") if isinstance(b0, dict) else None
    if isinstance(b0_packages, dict):
        for key in packages:
            if "node_modules/" in key and key not in b0_packages:
                return False, f"content:{path}:new-entry"
        for key, entry in packages.items():
            bentry = b0_packages.get(key)
            if not isinstance(bentry, dict):
                continue
            for field in _NPM_DEP_MAPS:
                added = set(entry.get(field) or {}) - set(bentry.get(field) or {})
                if added:
                    return False, f"content:{path}:dependency-added"
    # Both ways (#36 second run, high): an entry the base pins with a
    # `resolved` keeps one (dropping it lets npm fetch the name from the
    # public registry), and its `integrity` changes only with its version.
    b = json.loads(base) if base else {}
    b_packages = b.get("packages") if isinstance(b, dict) else None
    if isinstance(b_packages, dict):
        for key, bentry in b_packages.items():
            hentry = packages.get(key)
            if not isinstance(bentry, dict) or not isinstance(hentry, dict):
                continue
            if bentry.get("resolved") is not None and hentry.get("resolved") is None:
                return False, f"content:{path}:source-changed"
            if bentry.get("version") == hentry.get("version") and bentry.get("integrity") != hentry.get("integrity"):
                return False, f"content:{path}:hash-changed"
    if "dependencies" in h and not _npm_legacy_mirrors(h["dependencies"], packages, "node_modules/"):
        return False, f"content:{path}:legacy-dependencies"
    return True, None


def _npm_legacy_mirrors(tree, packages, prefix):
    """True when every entry of a v2 lockfile's legacy `dependencies` tree (at
    any depth) has the `packages` entry at its path with the same version,
    and its `resolved` and `integrity`, where present, equal that entry's (a
    legacy `resolved` must be the registry tarball when `packages` has none)."""
    if not isinstance(tree, dict):
        return False
    for name, entry in tree.items():
        key = prefix + name
        pentry = packages.get(key)
        if not isinstance(entry, dict) or not isinstance(pentry, dict):
            return False
        if entry.get("version") != pentry.get("version"):
            return False
        want = pentry.get("resolved") or _npm_tarball_url(name, pentry.get("version"))
        if entry.get("resolved") is not None and entry.get("resolved") != want:
            return False
        if entry.get("integrity") is not None and entry.get("integrity") != pentry.get("integrity"):
            return False
        if "dependencies" in entry and not _npm_legacy_mirrors(entry["dependencies"], packages, key + "/node_modules/"):
            return False
    return True


def _reduce_cargo_table(table):
    reduced = {}
    for name, spec in table.items():
        if isinstance(spec, str):
            reduced[name] = {}
        elif isinstance(spec, dict):
            reduced[name] = {k: v for k, v in spec.items() if k != "version"}
        else:
            reduced[name] = spec
    return reduced


def _reduce_cargo_toml(doc):
    """`doc` with every dependency table (dependencies, dev-dependencies,
    build-dependencies, and their target.* forms) reduced to each entry's
    keys other than `version` — a string entry (`serde = "1.0.0"`) reduces to
    `{}`. Everything else (a `[patch]`/`[replace]` table, features, …) is left
    untouched, so it still shows up in an equality check against the base."""
    result = dict(doc)
    for k in _CARGO_DEP_KEYS:
        if isinstance(result.get(k), dict):
            result[k] = _reduce_cargo_table(result[k])
    target = result.get("target")
    if isinstance(target, dict):
        new_target = {}
        for tname, t in target.items():
            if isinstance(t, dict):
                t = dict(t)
                for k in _CARGO_DEP_KEYS:
                    if isinstance(t.get(k), dict):
                        t[k] = _reduce_cargo_table(t[k])
            new_target[tname] = t
        result["target"] = new_target
    return result


def _cargo_dependency_names(doc):
    """(table path, name) for every entry of every dependency table,
    `target.*` forms included."""
    names = set()
    for k in _CARGO_DEP_KEYS:
        if isinstance(doc.get(k), dict):
            names |= {(k, n) for n in doc[k]}
    target = doc.get("target")
    if isinstance(target, dict):
        for tname, t in target.items():
            if isinstance(t, dict):
                for k in _CARGO_DEP_KEYS:
                    if isinstance(t.get(k), dict):
                        names |= {(f"target.{tname}.{k}", n) for n in t[k]}
    return names


def _cargo_toml_rule(path, base, head):
    b = tomllib.loads(base) if base else {}
    h = tomllib.loads(head) if head else {}
    if _cargo_dependency_names(b) != _cargo_dependency_names(h):
        return False, f"content:{path}:new-dependency"
    if _reduce_cargo_toml(b) != _reduce_cargo_toml(h):
        return False, f"content:{path}:non-version-change"
    return True, None


def _cargo_lock_rule(path, base, head):
    """Every package's source is crates.io (or none: a path/workspace
    member). Both ways (#36 second run, high): a name the base lists keeps one
    of the base's sources for it (`source-changed` — a private registry
    swapped for crates.io is dependency confusion), and a (name, version,
    source) the base lists keeps its `checksum` (`hash-changed`)."""
    b = tomllib.loads(base) if base else {}
    h = tomllib.loads(head) if head else {}
    b_sources, b_sums = {}, {}
    for pkg in b.get("package", []):
        b_sources.setdefault(pkg.get("name"), set()).add(pkg.get("source"))
        b_sums[(pkg.get("name"), pkg.get("version"), pkg.get("source"))] = pkg.get("checksum")
    for pkg in h.get("package", []):
        name = pkg.get("name")
        if name in b_sources and pkg.get("source") not in b_sources[name]:
            return False, f"content:{path}:source-changed"
        key = (name, pkg.get("version"), pkg.get("source"))
        if key in b_sums and b_sums[key] != pkg.get("checksum"):
            return False, f"content:{path}:hash-changed"
    for pkg in h.get("package", []):
        if pkg.get("source") not in _CARGO_LOCK_OK_SOURCES:
            return False, f"content:{path}:source"
    return True, None


_PUBSPEC_DEP_SECTIONS = ("dependencies", "dev_dependencies", "dependency_overrides")


def _pubspec_dependency_names(text):
    """(section, name) for every entry indented directly under a top-level
    `dependencies:`/`dev_dependencies:`/`dependency_overrides:` key —
    a line-based reading (stdlib only, no YAML parser), so a flow-style map
    or an unusual indent yields names the head/base comparison still sees."""
    names, section, indent = set(), None, None
    for ln in _lines(text):
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            continue
        if not ln[0].isspace():
            key = ln.split(":", 1)[0].strip()
            section = key if key in _PUBSPEC_DEP_SECTIONS else None
            indent = None
            if section is not None and ln.split(":", 1)[1].strip() not in ("", "{}"):
                names.add((section, "<inline>" + ln.split(":", 1)[1].strip()))
            continue
        if section is None:
            continue
        width = len(ln) - len(ln.lstrip())
        if indent is None:
            indent = width
        if width == indent:
            names.add((section, ln.strip().split(":", 1)[0].strip()))
    return names


def _pubspec_model(text):
    """A line-based reading of pubspec.yaml for the both-ways check (#36
    second run, high): each dependency entry's inline value, its `version:`
    sub-key, and every other sub-line (`hosted:`, `url:`, `name:`, `path:`,
    `git:`, `ref:`, `sdk:`, … — its source), plus every line outside the
    dependency sections (`outside`)."""
    entries, outside = {}, Counter()
    section, indent, cur = None, None, None
    for ln in _lines(text):
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            continue
        if not ln[0].isspace():
            key = ln.split(":", 1)[0].strip()
            section = key if key in _PUBSPEC_DEP_SECTIONS else None
            indent, cur = None, None
            if section is None or ln.split(":", 1)[1].strip() not in ("", "{}"):
                outside[ln.rstrip()] += 1
            continue
        if section is None:
            outside[ln.rstrip()] += 1
            continue
        width = len(ln) - len(ln.lstrip())
        if indent is None:
            indent = width
        if width == indent:
            name, _, val = ln.strip().partition(":")
            cur = (section, name.strip())
            entries[cur] = {"inline": val.strip() or None, "version": None, "source": []}
        elif width > indent and cur is not None:
            if ln.strip().split(":", 1)[0].strip() == "version":
                entries[cur]["version"] = ln.strip()
            else:
                entries[cur]["source"].append(ln.rstrip())
        else:
            outside[ln.rstrip()] += 1
    return entries, outside


def _pubspec_yaml_rule(path, base, head):
    """Only versions of the base's dependencies move — checked both ways (#36
    second run, high). Refused: a new or dropped entry (`new-dependency`);
    an entry whose source sub-keys (`hosted:`, `url:`, `path:`, `git:`,
    `ref:`, `sdk:`, …) differ at all, that changes between the inline and
    the map form, that gains or drops its `version:` key, or whose inline
    value was not a version (`source-changed` — collapsing `hosted:`/`git:`
    to a plain version moves the package to pub.dev); a line outside the
    dependency sections removed (`removed-line`) or added/changed
    (`non-version-line`); and any added line that is not a version line."""
    if _pubspec_dependency_names(base) != _pubspec_dependency_names(head):
        return False, f"content:{path}:new-dependency"
    b_entries, b_outside = _pubspec_model(base)
    h_entries, h_outside = _pubspec_model(head)
    for key in sorted(set(b_entries) | set(h_entries)):
        b, h = b_entries.get(key), h_entries.get(key)
        if b is None or h is None or b["source"] != h["source"]:
            return False, f"content:{path}:source-changed"
        if (b["inline"] is None) != (h["inline"] is None) or (b["version"] is None) != (h["version"] is None):
            return False, f"content:{path}:source-changed"
        if b["inline"] != h["inline"] and not _PUBSPEC_LINE_RE.match(f"  {key[1]}: {b['inline']}"):
            return False, f"content:{path}:source-changed"
    if b_outside - h_outside:
        return False, f"content:{path}:removed-line"
    if h_outside - b_outside:
        return False, f"content:{path}:non-version-line"
    for ln in _added_lines(base, head):
        if ln.strip() == "":
            continue
        if not _PUBSPEC_LINE_RE.match(ln):
            return False, f"content:{path}:non-version-line"
    return True, None


_PUBSPEC_LOCK_SOURCE_KEYS = ("source", "description", "name", "url", "path", "relative", "ref")
_PUBSPEC_LOCK_HASH_KEYS = ("sha256", "resolved-ref")


def _pubspec_lock_packages(text):
    """name -> {key: value} for every entry under `packages:`, its nested
    `description:` keys flattened (quotes stripped)."""
    pkgs, in_packages, indent, cur = {}, False, None, None
    for ln in _lines(text):
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            continue
        if not ln[0].isspace():
            in_packages, indent, cur = ln.strip() == "packages:", None, None
            continue
        if not in_packages:
            continue
        width = len(ln) - len(ln.lstrip())
        if indent is None:
            indent = width
        if width == indent:
            cur = ln.strip().rstrip(":").strip().strip('"').strip("'")
            pkgs[cur] = {}
            continue
        if cur is None:
            continue
        k, _, v = ln.strip().partition(":")
        v = v.strip().strip('"').strip("'")
        if v:
            pkgs[cur][k.strip()] = v
    return pkgs


def _pubspec_lock_rule(path, base, head):
    """Both ways (#36 second run, high): a package the base lists keeps its
    source — `source:`, a `description`'s `name`/`url`/`path`/`ref` (a
    removed or changed `url:` is `source-changed`) — and its `sha256` (or a
    git `resolved-ref`) changes only with its `version` (`hash-changed`).
    Any added `source: git`/`source: path` line, or an added `url:` other
    than https://pub.dev, is refused (`source`)."""
    b_pkgs, h_pkgs = _pubspec_lock_packages(base), _pubspec_lock_packages(head)
    for name in sorted(set(b_pkgs) & set(h_pkgs)):
        b, h = b_pkgs[name], h_pkgs[name]
        if any(b.get(k) != h.get(k) for k in _PUBSPEC_LOCK_SOURCE_KEYS):
            return False, f"content:{path}:source-changed"
        if b.get("version") == h.get("version") and any(b.get(k) != h.get(k) for k in _PUBSPEC_LOCK_HASH_KEYS):
            return False, f"content:{path}:hash-changed"
    for ln in _added_lines(base, head):
        stripped = ln.strip()
        if stripped in ("source: git", "source: path"):
            return False, f"content:{path}:source"
        if stripped.startswith("url:"):
            val = stripped.split(":", 1)[1].strip().strip('"').strip("'")
            if val != "https://pub.dev":
                return False, f"content:{path}:source"
    return True, None


_CONTENT_RULES = {
    "package.json": _package_json_rule,
    "package-lock.json": _package_lock_rule,
    "Cargo.toml": _cargo_toml_rule,
    "Cargo.lock": _cargo_lock_rule,
    "pubspec.yaml": _pubspec_yaml_rule,
    "pubspec.lock": _pubspec_lock_rule,
}


_LOCKFILES = ("package-lock.json", "Cargo.lock", "pubspec.lock")


def _content_rule(path, base, head):
    """The content rule for `path`'s basename, applied to `base`/`head`
    texts (either may be None). A deletion (`head` is None), a file the base
    does not have (`base` is None: `new-lockfile` or `new-manifest` — a new
    file moves no version the base lists, so it is never exempt, #36/#35)
    and an unparsable file each fail with their own reason (R11 step 6)."""
    if head is None:
        return False, f"content:{path}:deleted"
    basename = _basename(path)
    if base is None:
        return False, f"content:{path}:{'new-lockfile' if basename in _LOCKFILES else 'new-manifest'}"
    try:
        if basename in ("requirements.txt", "requirements.in"):
            return _requirements_rule(path, base, head, basename == "requirements.in")
        rule = _CONTENT_RULES.get(basename)
        if rule is not None:
            return rule(path, base, head)
    except Exception:
        return False, f"content:{path}:unparsable"
    return True, None


def dependabot_exemption(pr_author, commits, files, contents):
    """The Dependabot exemption (R11; REQ-334 as amended, dfe-13; REQ-311;
    P4): checks in order, the first failure is the reason. Returns
    `(bool, reason)`; `reason` is `"exempt-dependabot"` on success.

    1. the PR must be opened by dependabot[bot] (identity by opener);
    2. every commit must exist, be authored by dependabot[bot], be
       *verified*, and be committed by dependabot[bot] or web-flow — an
       author match alone (P2's original rule) is not enough, because the
       commit author's email is anyone-settable by whoever has push access.
       This step only rules out a plain `git push` with a forged author: an
       API-made commit is verified and committed by web-flow with any
       author, so a write-access user can still pass it (dfe-13's residual);
    3. every changed path must be a known dependency manifest or lockfile,
       never under `.github/` — a path match alone is not enough, because
       Dependabot could otherwise carry an edit to gate code or its own
       workflow configuration through unreviewed;
    4. every changed file's content must move only versions (`_content_rule`)
       of the dependencies the base already lists, compared base-to-head
       BOTH ways (#36 second run) — a file the base lacks is refused
       (`new-lockfile`/`new-manifest`); a new dependency in any manifest (a
       new pin in requirements.in/.txt, a new key in a package.json
       dependency map or a pubspec dependency section, a new Cargo.toml
       entry) is refused as `new-dependency`; a line the head REMOVES is
       refused unless it is a version or hash line of a dependency whose
       version moved: a removed pip option line (`--index-url`,
       `--extra-index-url`, `--find-links`, `--trusted-host`, any `-` line)
       is `removed-option`; a changed source — a pubspec entry's `hosted:`/
       `url:`/`path:`/`git:`/`ref:`/`sdk:` sub-keys, a package.json alias/
       file/git/URL spec, a pubspec.lock `url:`/`source:`, a Cargo.lock
       package's `source`, a package-lock entry's dropped `resolved` — is
       `source-changed`; a Cargo.toml `registry`/`git`/`path` key or a
       `[patch]`/`[replace]` table added or removed is `non-version-change`;
       and a `--hash=`, `sha256`, `checksum` or `integrity` changes only for
       a dependency whose version changed (`hash-changed`). An npm lockfile
       without a `packages` map is refused (`lockfile-v1`) and each entry's
       `resolved` must be its own package's registry tarball; a package.json
       range must stay a registry range (never a dist-tag such as `latest`).
       What remains (dfe-13's residual): a dependency can still move to
       another registry version of the same package, on the same source."""
    if pr_author != DEPENDABOT:
        return False, "not-dependabot"
    if not commits:
        return False, "no-commits"
    for c in commits:
        sha7 = _sha7(c)
        if commit_author(c) != DEPENDABOT:
            return False, f"commit-author:{sha7}"
        if commit_committer(c) not in DEPENDABOT_COMMITTERS:
            return False, f"committer:{sha7}"
        verification = (c.get("commit") or {}).get("verification") or {}
        if verification.get("verified") is not True:
            return False, f"unverified:{sha7}"
    if not files:
        return False, "files-unknown"
    for p in sorted(files):
        if p.startswith(".github/"):
            return False, f"workflow-path:{p}"
        if _basename(p) not in DEPENDENCY_FILES:
            return False, f"not-a-dependency-file:{p}"
    if contents is None:
        return False, "content-unknown"
    for p in sorted(files):
        if p not in contents:
            return False, "content-unknown"
        entry = contents[p]
        ok, reason = _content_rule(p, entry.get("base"), entry.get("head"))
        if not ok:
            return False, reason
    return True, "exempt-dependabot"


def dependabot_exempt(pr_author, commits, files, contents):
    """`dependabot_exemption`'s bool half, for callers that only need the
    yes/no answer (`classify`)."""
    ok, _ = dependabot_exemption(pr_author, commits, files, contents)
    return ok


_WAIVER_TRUSTED = ("OWNER", "MEMBER")
# R9: GitHub's MEMBER is any organisation member, read-only ones included, and a
# COLLABORATOR may hold only the read or triage role, so a MEMBER's or a
# COLLABORATOR's marker-bearing comment (a marker or a waiver) counts only when
# the commenter's repository role is one of these (P5 final review: the same
# read-only principal can neither waive nor supply, or block, the review).
_WAIVER_ROLES = ("admin", "maintain", "write")
WRITER_ROLES = _WAIVER_ROLES
_NON_WRITER_ROLES = ("read", "triage", "none")  # the only KNOWN non-writing roles (rule 1b)
_KNOWN_ROLES = _WAIVER_ROLES + _NON_WRITER_ROLES


def resolve_role(raw):
    """A login's repository role as rule 1b reads it: a known role name, or
    None when it is unreadable. `raw` is what the lookup (or the test-only
    `--permissions` map) gives: a `{role_name, permission}` object, a bare
    role string, or None. A `role_name` outside admin/maintain/write/read/
    triage/none — an organisation custom role's own name, or an empty string
    — says nothing about writing: it is resolved through the legacy
    `permission` field (admin/write/read/none; maintain/triage as named),
    and a role neither field recognises is unreadable (never accepted, keeps
    blocking), never a known non-writer — a dropped block would fail open."""
    if isinstance(raw, str):
        return raw if raw in _KNOWN_ROLES else None
    if isinstance(raw, dict):
        for key in ("role_name", "permission"):
            v = raw.get(key)
            if isinstance(v, str) and v in _KNOWN_ROLES:
                return v
    return None
_ROLE_CHECKED = ("MEMBER", "COLLABORATOR")
MARKER_OCCURRENCE = "<!-- specflow-verifier:"


def _judge_comment(c, *, head, prompt_sha256_or_None, solo, pr_author, required_mode, commit_authors=None,
                   permissions=None, bases=None, base_changes=None, waiver_bases=None):
    """Judge one comment against the classifier rules, in order. Returns
    None when the comment bears no marker occurrence at all (it is then
    not a marker-bearing comment and takes no part in classification).
    Otherwise returns a dict: id, created_at, html_url, reason, blocking,
    accepted, kind (the comment's own state when accepted, else None)."""
    body = c.get("body") or ""
    if MARKER_OCCURRENCE not in body:
        return None

    cid = c["id"]
    created_at = c["created_at"]
    updated_at = c.get("updated_at", created_at)
    html_url = c.get("html_url", "")
    assoc = c.get("author_association", "")
    login = c.get("user", {}).get("login", "")

    def judged(reason, *, blocking=False, accepted=False, kind=None):
        return {
            "id": cid, "created_at": created_at, "html_url": html_url,
            "reason": reason, "blocking": blocking, "accepted": accepted, "kind": kind,
        }

    # 1. Author association: outsiders can never block and are never accepted.
    if assoc not in _TRUSTED:
        return judged("untrusted-author")

    # 1b. Repository role (R9): a MEMBER or COLLABORATOR counts only with a
    # writing role (resolve_role: a custom or empty role_name is read through
    # the legacy permission field, else it is unreadable). A KNOWN
    # non-writing role (read, triage, none — no other) neither
    # accepts nor blocks: judged before any blocking rule, so a read-only
    # principal cannot block either. An UNREADABLE role fails closed in both
    # directions (PR #48 verifier high): the comment is never accepted as an
    # approval or a waiver, but keeps its blocking classification — the
    # blocking rules run as for a writer and a blocking result still blocks,
    # its reason suffixed `-permission-unknown`; a REQUEST_CHANGES for the
    # head still counts as one (`request-changes-permission-unknown`, which a
    # newer accepted APPROVE or waiver supersedes exactly as a writer's).
    if assoc in _ROLE_CHECKED:
        kind = "waiver" if WAIVER_RE.match(body.split("\n", 1)[0].strip()) else "marker"
        role = resolve_role((permissions or {}).get(login))
        if role is not None and role not in _WAIVER_ROLES:
            return judged(f"{kind}-not-writer")
        if role is None:
            j = _judge_rules(c, body=body, judged=judged, head=head, prompt_sha256_or_None=prompt_sha256_or_None,
                             solo=solo, pr_author=pr_author, required_mode=required_mode,
                             commit_authors=commit_authors, bases=bases, base_changes=base_changes,
                             waiver_bases=waiver_bases)
            if j["blocking"]:
                j["reason"] = f"{j['reason']}-permission-unknown"
                return j
            if j["accepted"] and j["kind"] == "request_changes":
                j["reason"] = "request-changes-permission-unknown"
                return j
            return judged(f"{kind}-permission-unknown")

    return _judge_rules(c, body=body, judged=judged, head=head, prompt_sha256_or_None=prompt_sha256_or_None,
                        solo=solo, pr_author=pr_author, required_mode=required_mode,
                        commit_authors=commit_authors, bases=bases, base_changes=base_changes,
                        waiver_bases=waiver_bases)


def _judge_rules(c, *, body, judged, head, prompt_sha256_or_None, solo, pr_author, required_mode, commit_authors,
                 bases, base_changes=None, waiver_bases=None):
    """Rules 2–6 for one marker-bearing comment whose author passed rules 1
    and 1b (or whose role is unknown: see rule 1b)."""
    created_at = c["created_at"]
    updated_at = c.get("updated_at", created_at)
    assoc = c.get("author_association", "")
    login = c.get("user", {}).get("login", "")

    # 2. More than one marker occurrence: blocking only when the comment
    # names the head, like rule 3 (a pasted waiver line in a comment about a
    # stale head must not block every later head until it is deleted).
    if body.count(MARKER_OCCURRENCE) > 1:
        return judged("multiple-markers", blocking=f"sha:{head}" in body)

    # 3. Edited: blocking only when the edited comment names the head (a
    # trivial edit to the newest REQUEST_CHANGES must not revive an older
    # APPROVE).
    if updated_at != created_at:
        names_head = f"sha:{head}" in body
        return judged("edited", blocking=names_head)

    # 4. The (single) marker occurrence's position and line-1 grammar.
    if body.find(MARKER_OCCURRENCE) != 0:
        return judged("marker-not-first-line")
    parts = body.split("\n", 1)
    line1 = parts[0].strip()
    tail = parts[1] if len(parts) > 1 else ""
    m_full = MARKER_RE.match(line1)
    m_waive = WAIVER_RE.match(line1)
    if not m_full and not m_waive:
        return judged("malformed")
    sha = (m_full or m_waive).group("sha")
    if sha != head:
        return judged("stale-sha")

    if m_waive:
        # 6. Waivers, judged whether or not the base has a prompt template.
        if assoc not in _WAIVER_TRUSTED:
            return judged("waiver-not-maintainer")
        rationale = tail.strip()
        if len(rationale) < 20:
            return judged("short-rationale")
        # Team mode: "other than the author" covers the PR opener and every
        # author of its commits (#33 third bootstrap medium).
        if not solo and (login == pr_author or login in (commit_authors or ())):
            return judged("self-waiver")
        # P7 R4: a bound waiver is judged by the marker's base rule; a legacy one stands only while the PR's timeline
        # shows no base change after it. Each refuses and never blocks. None skips the rule (fixtures 1-102, classify CLI).
        # A commit-level judgement (release-check's direct push) passes `waiver_bases`: a bound waiver there must name
        # the commit's first parent exactly, never another base with the same merge base (fix wave 1, FIX 11).
        wbase = m_waive.group("base")
        wb = waiver_bases if waiver_bases is not None else bases
        if wbase is not None:
            if wb is not None and not bool(wb.get(wbase, False)):
                return judged("waiver-base-mismatch")
        elif base_changes is not None:
            # Fail closed (P7 Build 1 fix wave 1): an unreadable timeline, or any time — the waiver's own or a base
            # event's — that is not an ISO-8601 UTC second (empty, null, malformed) is waiver-timeline-unknown; the
            # string comparison below is sound only between two such values.
            if (base_changes == "unknown" or not isinstance(base_changes, list) or not _is_utc_second(created_at)
                    or not all(_is_utc_second(t) for t in base_changes)):
                return judged("waiver-timeline-unknown")
            if any(t >= created_at for t in base_changes):  # the same second counts as after (fail closed)
                return judged("waiver-unbound-retargeted")
        return judged("accepted", accepted=True, kind="waiver")

    # 5. Attestation markers.
    fields = m_full.groupdict()
    if prompt_sha256_or_None is None:
        return judged("base-predates-attestation")
    if fields["prompt_sha256"] != prompt_sha256_or_None:
        return judged("prompt-mismatch")
    recomputed = digest(tail)
    if fields["digest"] != recomputed:
        return judged("digest-mismatch", blocking=True)
    tail_lines = [ln.strip() for ln in tail.split("\n") if ln.strip() != ""]
    last = tail_lines[-1] if tail_lines else None
    if fields["verdict"] != last:
        return judged("verdict-mismatch", blocking=True)
    normalized_mode = fields["mode"].replace("persona", "full")
    if normalized_mode != required_mode:
        return judged("mode-mismatch")
    # The marker is bound to the diff it reviewed (P5 final review): its
    # recorded base must give the head the same merge base as the PR's
    # current base. A PR retargeted onto another base (or whose base branch
    # was rewritten) reviews another diff, so its old APPROVE is refused
    # (base-mismatch). Only the ACCEPTANCE of an approval needs the base to
    # match (PR #48 verifier run 2, code-mode high): a REQUEST_CHANGES for
    # the head stands whatever diff it reviewed, until a newer accepted
    # comment supersedes it — it still counts as one
    # (request-changes-base-mismatch), so a retarget never revives an older
    # APPROVE over it. `bases` maps a recorded base SHA to that judgement;
    # None (fixtures and the classify CLI, which have no repository) skips
    # the rule.
    base_ok = bases is None or (bool(_SHA40.match(fields["base"])) and bool(bases.get(fields["base"], False)))
    if not base_ok and fields["verdict"] == "APPROVE":
        return judged("base-mismatch")
    if fields["origin"] == "in-session" and solo:
        return judged("in-session-in-solo")
    kind = "approve" if fields["verdict"] == "APPROVE" else "request_changes"
    if not base_ok:
        return judged("request-changes-base-mismatch", accepted=True, kind=kind)
    return judged("accepted", accepted=True, kind=kind)


def _judge_all(comments, *, head, prompt_sha256_or_None, solo, pr_author, required_mode, commit_authors=None,
               permissions=None, bases=None, base_changes=None, waiver_bases=None):
    out = []
    for c in comments:
        j = _judge_comment(
            c, head=head, prompt_sha256_or_None=prompt_sha256_or_None,
            solo=solo, pr_author=pr_author, required_mode=required_mode,
            commit_authors=commit_authors, permissions=permissions, bases=bases, base_changes=base_changes,
            waiver_bases=waiver_bases,
        )
        if j is not None:
            out.append(j)
    return out


def _newest(items):
    return max(items, key=lambda j: (j["created_at"], j["id"]))


def classify(comments, head, prompt_sha256_or_None, solo, pr_author, required_mode, *,
             commit_authors=None, commits=None, files=None, contents=None, permissions=None, bases=None,
             base_changes=None, waiver_bases=None):
    """Reduce `comments` to exactly {"state", "reason", "comment_id"}.
    `commit_authors` is the set of the PR's commit authors (see
    commit_author); None means unknown, and it still feeds the team
    self-waiver rule even when the Dependabot exemption does not apply. The
    exemption itself (REQ-334 as amended, dfe-13) is decided from `commits`,
    `files` and `contents` only — `commit_authors` alone never exempts (with
    `commits` absent the reason is `no-commits`). `permissions` maps a login to
    its repository role (R9): a MEMBER's or COLLABORATOR's marker or waiver
    needs admin, maintain or write; a login with no entry is unknown and fails
    closed. `bases` maps each marker's recorded base SHA to whether it gives
    the head the PR's current merge base (None skips that rule); waivers are judged through it too
    when bound. `base_changes` lists the `created_at` of the PR's base timeline events (base_ref_*,
    automatic_base_change*), or "unknown" when the timeline could not be read (P7 R4): a legacy waiver stands only
    while none is at or after its own second (None skips that rule). `waiver_bases`, when given (a commit-level
    judgement), replaces `bases` for bound waivers: each recorded base maps to whether it is exactly the commit's first
    parent."""
    if dependabot_exempt(pr_author, commits, files, contents):
        return {"state": "approve", "reason": "exempt-dependabot", "comment_id": None}

    if commit_authors is None and commits:
        commit_authors = {commit_author(c) for c in commits}

    judged = _judge_all(
        comments, head=head, prompt_sha256_or_None=prompt_sha256_or_None,
        solo=solo, pr_author=pr_author, required_mode=required_mode,
        commit_authors=commit_authors, permissions=permissions, bases=bases, base_changes=base_changes,
        waiver_bases=waiver_bases,
    )

    blocking = [j for j in judged if j["blocking"]]
    if blocking:
        newest = _newest(blocking)
        return {"state": "request_changes", "reason": newest["reason"], "comment_id": newest["id"]}

    accepted = [j for j in judged if j["accepted"]]
    if accepted:
        newest = _newest(accepted)
        # "accepted", request-changes-permission-unknown (rule 1b: a block whose author's role is unreadable) or
        # request-changes-base-mismatch (a request for changes stands whatever diff it reviewed)
        return {"state": newest["kind"], "reason": newest["reason"], "comment_id": newest["id"]}

    if judged:
        newest = _newest(judged)
        return {"state": "none", "reason": newest["reason"], "comment_id": None}

    return {"state": "none", "reason": "no-marker", "comment_id": None}


def explain(comments, head, prompt_sha256_or_None, solo, pr_author, required_mode, *, commit_authors=None,
            permissions=None, bases=None, base_changes=None, waiver_bases=None):
    """Every marker-bearing comment that was not accepted, newest first, as
    (comment_id, html_url, reason) — including a REQUEST_CHANGES counted for
    an author whose role is unreadable (request-changes-permission-unknown)
    or recorded against another base (request-changes-base-mismatch)."""
    judged = _judge_all(
        comments, head=head, prompt_sha256_or_None=prompt_sha256_or_None,
        solo=solo, pr_author=pr_author, required_mode=required_mode,
        commit_authors=commit_authors, permissions=permissions, bases=bases, base_changes=base_changes,
        waiver_bases=waiver_bases,
    )
    rejected = [j for j in judged if j["reason"] != "accepted"]
    rejected.sort(key=lambda j: (j["created_at"], j["id"]), reverse=True)
    return [(j["id"], j["html_url"], j["reason"]) for j in rejected]


_BLOCKING_WHY = {
    "multiple-markers": "carries more than one specflow-verifier marker",
    "edited": "was edited after it was posted",
    "digest-mismatch": "does not match its findings digest",
    "verdict-mismatch": "states a verdict its findings do not end with",
}


def _git_rev_parse(rev: str) -> str:
    proc = subprocess.run(["git", "rev-parse", rev], capture_output=True)
    if proc.returncode != 0:
        raise AttestationError(
            proc.stderr.decode("utf-8", "replace").strip() or f"git rev-parse {rev} failed", code=2
        )
    return proc.stdout.decode("utf-8").strip()


def _comment_by_id(comments, cid):
    for c in comments:
        if c.get("id") == cid:
            return c
    return None


def _marker_base(comment):
    body = comment.get("body") or ""
    line1 = body.split("\n", 1)[0].strip()
    m = MARKER_RE.match(line1) or WAIVER_RE.match(line1)
    return m.group("base") if m else None


def _load_comments_json(text: str):
    """Decode `text` as one or more concatenated JSON values (as `gh api
    --paginate` prints one array per page, back to back with no separator),
    flattening any arrays found into a single list of comment objects."""
    dec = json.JSONDecoder()
    text = text.strip()
    comments = []
    idx = 0
    n = len(text)
    while idx < n:
        obj, end = dec.raw_decode(text, idx)
        if isinstance(obj, list):
            comments.extend(obj)
        else:
            comments.append(obj)
        idx = end
        while idx < n and text[idx] in " \t\r\n":
            idx += 1
    return comments


def _gh_json_list(endpoint):
    """`gh api --paginate <endpoint>` as one flat list; raises
    AttestationError(code 2) when gh fails."""
    proc = subprocess.run(["gh", "api", "--paginate", endpoint], capture_output=True)
    if proc.returncode != 0:
        raise AttestationError(proc.stderr.decode("utf-8", "replace").strip() or "gh api failed", code=2)
    try:
        return _load_comments_json(proc.stdout.decode("utf-8", "replace"))
    except ValueError as e:  # an answer that is not JSON is a failed read, named, never a traceback (fix wave 1)
        raise AttestationError(f"gh api {endpoint}: the answer is not JSON ({e})", code=2) from None


def _load_json_file_list(path):
    with open(path) as f:
        data = json.load(f)
    return [data] if isinstance(data, dict) else data


def _load_files_file(path):
    """`--files FILE`: one path per line, or a JSON list."""
    with open(path) as f:
        text = f.read().strip()
    if not text:
        return []
    if text.lstrip().startswith("["):
        return json.loads(text)
    return [ln for ln in text.splitlines() if ln.strip()]


def _load_contents_file(path):
    """`--contents FILE`: a JSON object in the `contents` shape
    (`{path: {"base": text_or_None, "head": text_or_None}}`)."""
    with open(path) as f:
        return json.load(f)


def _git_diff_files(base: str, head: str):
    """`git diff --no-renames --name-only <base>...<head>` (fail closed on a
    git failure, code 2)."""
    proc = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", f"{base}...{head}"], capture_output=True
    )
    if proc.returncode != 0:
        raise AttestationError(proc.stderr.decode("utf-8", "replace").strip() or "git diff failed", code=2)
    return [p for p in proc.stdout.decode("utf-8").splitlines() if p]


def _git_merge_base(base: str, head: str) -> str:
    proc = subprocess.run(["git", "merge-base", base, head], capture_output=True)
    if proc.returncode != 0:
        raise AttestationError(proc.stderr.decode("utf-8", "replace").strip() or "git merge-base failed", code=2)
    return proc.stdout.decode("utf-8").strip()


def _git_contents(base_ref: str, head: str, files):
    """The Dependabot content rule only ever needs a known dependency file's
    text (never `.github/`'s), so contents are fetched only for those paths —
    every other path already fails the path check before content is read.
    Texts come from `git show <merge-base>:<p>` and `git show <head>:<p>`; a
    path absent on one side is `None` (a deletion, or the file is new)."""
    candidates = [p for p in files if not p.startswith(".github/") and _basename(p) in DEPENDENCY_FILES]
    if not candidates:
        return {}
    mb = _git_merge_base(base_ref, head)
    contents = {}
    for p in candidates:
        try:
            b = _git_show(mb, p).decode("utf-8", "replace")
        except AttestationError as e:
            if e.code != 3:
                raise
            b = None
        try:
            h = _git_show(head, p).decode("utf-8", "replace")
        except AttestationError as e:
            if e.code != 3:
                raise
            h = None
        contents[p] = {"base": b, "head": h}
    return contents


def _repo_role_lookup(repo, login):
    """`gh api repos/<repo>/collaborators/<login>/permission`: ({role_name,
    permission}, None) on success — the raw pair, which resolve_role()
    reads — or (None, why) on any failure; `why` says what failed, for the
    check's and next.sh's explanations (a failed lookup is never silent)."""
    try:
        proc = subprocess.run(["gh", "api", f"repos/{repo}/collaborators/{login}/permission"], capture_output=True)
        if proc.returncode != 0:
            err = proc.stderr.decode("utf-8", "replace").strip().splitlines()
            return None, f"gh api exited {proc.returncode}" + (f": {err[-1]}" if err else "")
        d = json.loads(proc.stdout.decode("utf-8"))
        if not isinstance(d, dict):
            return None, "gh api returned no role_name or permission"
        return {"role_name": d.get("role_name"), "permission": d.get("permission")}, None
    except (OSError, ValueError, AttributeError) as e:
        return None, f"{type(e).__name__}: {e}"


def _repo_role(repo, login):
    """The resolved role alone (resolve_role); None on any failure or an
    unrecognised role (the comment, or next.sh's human approval, then fails
    closed)."""
    return resolve_role(_repo_role_lookup(repo, login)[0])


repo_role = _repo_role  # the public name next.sh uses for a reviewer's role (P5 final review)


def _role_logins(comments):
    """Logins of the MEMBERs and COLLABORATORs whose comment bears a marker
    occurrence (a marker or a waiver): rule 1b needs each one's role."""
    out = []
    for c in comments:
        if c.get("author_association") not in _ROLE_CHECKED:
            continue
        login = c.get("user", {}).get("login", "")
        if MARKER_OCCURRENCE in (c.get("body") or "") and login and login not in out:
            out.append(login)
    return out


def _marker_bases(comments, base_sha, head):
    """{recorded base SHA: bool} for every marker line in `comments`: True when
    the recorded base is the current base tip, or gives the head the same merge
    base as the current base does (the reviewed diff is the current diff).
    A base git cannot resolve is False (fail closed), and so is a recorded
    base that is not 40 lowercase hex characters: it is never handed to git,
    where a value starting with '-' would read as an option (PR #48 verifier
    run 2, code-mode low)."""
    now = _git_merge_base(base_sha, head)
    out = {}
    for c in comments:
        b = _marker_base(c)
        if not b or b in out:
            continue
        if not _SHA40.match(b):
            out[b] = False
            continue
        if b == base_sha:
            out[b] = True
            continue
        proc = subprocess.run(["git", "merge-base", b, head], capture_output=True)
        out[b] = proc.returncode == 0 and proc.stdout.decode("utf-8").strip() == now
    return out


def _waiver_base_changes(gh_json, repo, pr, comments, head):
    """P7 R4: the `created_at` of each of the PR's base timeline events (`_is_base_event`), read only when some comment's
    first line is a legacy (unbound) waiver naming `head`; "unknown" when that read fails (fail closed); [] for a
    commit-level judgement (pr=None: a commit has no timeline); None when no legacy waiver needs it."""
    legacy = False
    for c in comments:
        line1 = (c.get("body") or "").split("\n", 1)[0].strip()
        m = WAIVER_RE.match(line1)
        if m and m.group("base") is None and m.group("sha") == head:
            legacy = True
            break
    if not legacy:
        return None
    if pr is None:
        return []
    try:
        events = gh_json(f"repos/{repo}/issues/{pr}/timeline")
    except (AttestationError, ValueError):  # a failed read, or an answer that is not JSON (fix wave 1): fail closed
        return "unknown"
    if not isinstance(events, list):
        return "unknown"
    times = []
    for e in events:
        if not isinstance(e, dict) or not _is_base_event(e.get("event")):
            continue
        t = e.get("created_at")
        if not _is_utc_second(t):
            return "unknown"  # a base event with no readable time: fail closed
        times.append(t)
    return times


_UTC_SECOND = re.compile(r"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")


def _is_utc_second(t):
    """True for a GitHub timestamp, YYYY-MM-DDTHH:MM:SSZ: the only form whose string order is time order."""
    return isinstance(t, str) and bool(_UTC_SECOND.match(t))


def _is_base_event(name):
    """P7 Build 1 final review: every timeline event about the PR's base counts as a base change — base_ref_changed (a
    retarget), automatic_base_change_succeeded/_failed (GitHub's retarget when the base branch is deleted; whether that
    path also records base_ref_changed is unmeasured), base_ref_force_pushed (a base rewrite) and base_ref_deleted.
    Fail closed: an event of either family named later by GitHub counts too; head_ref_* events never do."""
    return isinstance(name, str) and (name.startswith("base_ref_") or name.startswith("automatic_base_change"))


def pr_attestation(*, repo, pr, head, base_ref, pr_author, gh_json=_gh_json_list, commits=None, files=None,
                   contents=None, comments=None, permissions=None):
    """The one function that gathers a PR's inputs (commits, files and
    contents at base_ref..head, policy and prompt hash at the base, review
    scope, comments, each MEMBER or COLLABORATOR commenter's role, and each
    marker's recorded base against the current merge base) and classifies them;
    the CI check and next.sh both call it (REQ-311). Returns classify()'s
    dict plus `judged` (the explain list), `required_mode`, `prompt_sha256`
    (None when the base predates attestation), `solo`, `comment` ({id,
    html_url, body} of the decisive comment, or None) and, for the check's
    messages, `comments`, `base_sha`, `exempt_reason` and `role_unknown`
    ({login: why} for each MEMBER or COLLABORATOR whose role could not be
    read: rule 1b never accepts their comment, and it keeps blocking). Raises
    AttestationError (code 2) when gh, git or the config cannot be read. Any
    input passed in is used as given, never fetched (the tests' files)."""
    if commits is None:
        commits = gh_json(f"repos/{repo}/pulls/{pr}/commits")
    commit_authors = {commit_author(c) for c in commits}
    if files is None:
        files = _git_diff_files(base_ref, head)
    if contents is None:
        contents = _git_contents(base_ref, head, files)

    exempt_ok, exempt_reason = dependabot_exemption(pr_author, commits, files, contents)
    if exempt_ok:
        try:
            solo_e = policy(base_ref)["solo"] == "true"
        except AttestationError:
            solo_e = None
        return {"state": "approve", "reason": "exempt-dependabot", "comment_id": None, "judged": [],
                "required_mode": None, "prompt_sha256": None, "solo": solo_e, "comment": None,
                "comments": [], "base_sha": None, "exempt_reason": exempt_reason, "role_unknown": {}}

    try:
        pol = policy(base_ref)
    except AttestationError as e:
        if e.code == 4:
            m = re.search(r"solo: (.+) must be true or false", str(e))
            val = m.group(1) if m else str(e)
            raise AttestationError(f"attestation: .specflow.yml at the base has solo: {val}; expected true or false", code=2)
        raise
    solo = pol["solo"] == "true"

    try:
        phash = prompt_hash(base_ref)
    except AttestationError as e:
        if e.code != 3:
            raise
        phash = None

    required_mode = review_scope(base_ref, head)["mode"]
    base_sha = _git_rev_parse(base_ref)
    if comments is None:
        comments = gh_json(f"repos/{repo}/issues/{pr}/comments")

    role_unknown = {}
    if permissions is None:
        permissions = {}
        for login in _role_logins(comments):
            role, why = _repo_role_lookup(repo, login)
            if role is not None:
                permissions[login] = role
            else:
                role_unknown[login] = why
    else:
        role_unknown = {login: "no role supplied (--permissions)" for login in _role_logins(comments)
                        if login not in permissions}
    for login in _role_logins(comments):
        if login in permissions and resolve_role(permissions[login]) is None:
            raw = permissions[login]
            if isinstance(raw, dict):
                raw = {"role_name": raw.get("role_name"), "permission": raw.get("permission")}
            role_unknown[login] = f"unrecognised role {json.dumps(raw)}: neither role_name nor permission names a known role"
    bases = _marker_bases(comments, base_sha, head)
    base_changes = _waiver_base_changes(gh_json, repo, pr, comments, head)
    # R4: a bound waiver on a commit (pr=None) names the commit's first parent — `base_ref` there — exactly
    waiver_bases = None if pr is not None else {b: b == base_sha for b in (_marker_base(c) for c in comments) if b}

    result = classify(comments, head, phash, solo, pr_author, required_mode, commit_authors=commit_authors,
                      commits=commits, files=files, contents=contents, permissions=permissions, bases=bases,
                      base_changes=base_changes, waiver_bases=waiver_bases)
    c = _comment_by_id(comments, result["comment_id"]) if result["comment_id"] is not None else None
    out = dict(result)
    out.update({
        "judged": explain(comments, head, phash, solo, pr_author, required_mode, commit_authors=commit_authors,
                          permissions=permissions, bases=bases, base_changes=base_changes, waiver_bases=waiver_bases),
        "required_mode": required_mode, "prompt_sha256": phash, "solo": solo,
        "comment": None if c is None else {
            "id": c.get("id"), "html_url": c.get("html_url", ""), "body": c.get("body", ""),
            "login": (c.get("user") or {}).get("login", ""), "association": c.get("author_association", ""),
            "role": resolve_role(permissions.get((c.get("user") or {}).get("login", "")))},
        "comments": comments, "base_sha": base_sha, "exempt_reason": exempt_reason,
        "role_unknown": role_unknown,
    })
    return out


# The verifier bootstrap a maintainer types: main's reviewed copy for every PR, stacked or not (the SEC-004 back-edge;
# REQ-385 as amended) — a stacked PR's base is unreviewed and its script is never piped into bash; by the full ref, since
# a tag named origin/main would shadow the short name (PR #54 verifier run 2, finding 3).
VERIFIER_BOOTSTRAP_OBJ = "refs/remotes/origin/main:scripts/run-verifier.sh"


def check(*, repo, pr, head, base_ref, base_name, pr_author, comments_file=None, commits_file=None,
          files_file=None, contents_file=None, permissions_file=None) -> int:
    """The CI check: reduce the PR's comments to ADR-003's Attestation and
    print exactly the messages `attestation.py check`'s callers rely on.
    Returns the process exit code (0 pass, 1 fail, 2 gh/git/config failure).
    It classifies only through pr_attestation()."""
    try:
        commits = _load_json_file_list(commits_file) if commits_file else None
        files = _load_files_file(files_file) if files_file else None
        contents = _load_contents_file(contents_file) if contents_file else None
        comments = _load_json_file_list(comments_file) if comments_file else None
        permissions = None
        if permissions_file:
            with open(permissions_file) as f:
                permissions = json.load(f)
        r = pr_attestation(repo=repo, pr=pr, head=head, base_ref=base_ref, pr_author=pr_author, commits=commits,
                           files=files, contents=contents, comments=comments, permissions=permissions)
    except AttestationError as e:
        print(str(e), file=sys.stderr)
        return 2

    if r["reason"] == "exempt-dependabot":
        print(f"attestation: approve (exempt-dependabot) for {head[:7]}")
        return 0
    if pr_author == DEPENDABOT:
        print(f"attestation: dependabot[bot] PR not exempt ({r['exempt_reason']}) — the verifier must review it")
    phash, base_sha, comments = r["prompt_sha256"], r["base_sha"], r["comments"]
    for login, why in sorted((r.get("role_unknown") or {}).items()):
        print(f"attestation: {login}'s repository role could not be read ({why}): their marker or waiver is never "
              f"accepted, and a blocking one still blocks (REQ-382, R9)")
    result = r
    state, reason, comment_id = result["state"], result["reason"], result["comment_id"]

    if state in ("approve", "waiver"):
        print(f"attestation: {state} ({reason}) for {head[:7]}")
        if state == "waiver":
            c = _comment_by_id(comments, comment_id)
            html_url = c.get("html_url", "") if c else ""
            print(f"record the waiver in the PR body: {html_url} (REQ-382)")
        return 0

    if state == "none":
        if phash is None:
            print(
                f"attestation: the base {base_name} ({base_sha[:7]}) predates the P2 verifier, so no verifier "
                f"marker can be accepted for {head[:7]}. From a checkout of the PR head, in a terminal outside "
                f"any Claude Code session, run: bash scripts/run-verifier.sh {pr} --bootstrap — read its "
                f"findings, then post a comment whose first line is <!-- specflow-verifier:waive sha:{head} base:{base_sha} --> "
                f"followed by a rationale of 20+ characters naming the bootstrap comment (REQ-382)"
            )
            return 1
        print(
            f"attestation: no accepted verifier comment for {head[:7]}. From a terminal outside any Claude Code "
            f"session run: git show {VERIFIER_BOOTSTRAP_OBJ} | bash -s -- {pr}"
        )
        for cid, html_url, why_r in r["judged"]:
            line = f"{html_url}: {why_r}"
            if why_r == "base-mismatch":
                line += (" — this review was of another diff: the PR's base was retargeted or rewritten since, so its "
                         "merge base moved; re-run the verifier")
            if why_r in ("waiver-base-mismatch", "waiver-unbound-retargeted", "waiver-timeline-unknown"):
                line += (f" — a waiver binds the base it was posted against: post <!-- specflow-verifier:waive "
                         f"sha:{head} base:{base_sha} --> with a rationale (REQ-382)")
            if why_r in ("prompt-mismatch", "mode-mismatch"):
                c = _comment_by_id(comments, cid)
                marker_base = _marker_base(c) if c else None
                if marker_base and marker_base != base_sha:
                    line += (
                        f" — the base branch moved since this review ({marker_base[:7]} → {base_sha[:7]}): "
                        f"push or rebase, then re-run the verifier"
                    )
            print(line)
        return 1

    # state == "request_changes"
    c = _comment_by_id(comments, comment_id)
    html_url = c.get("html_url", "") if c else ""
    if reason in ("accepted", "request-changes-permission-unknown", "request-changes-base-mismatch"):
        print(
            f"attestation: the verifier requested changes on {head[:7]} ({html_url}): address the findings, "
            f"push, and re-run git show {VERIFIER_BOOTSTRAP_OBJ} | bash -s -- {pr}; a "
            f"maintainer may instead waive with a rationale (REQ-382)"
        )
        if reason == "request-changes-permission-unknown":
            print(f"attestation: {html_url}: request-changes-permission-unknown — its author's repository role could "
                  f"not be read, so it still counts as a request for changes (an unreadable role never approves)")
        elif reason == "request-changes-base-mismatch":
            print(f"attestation: {html_url}: request-changes-base-mismatch — it reviewed another diff (the PR's base "
                  f"was retargeted or rewritten since), and a request for changes on this head stands until a newer "
                  f"accepted APPROVE or waiver supersedes it")
    else:
        base_reason = reason[:-len("-permission-unknown")] if reason.endswith("-permission-unknown") else reason
        why = _BLOCKING_WHY.get(base_reason, base_reason)
        if base_reason != reason:
            why += " (its author's repository role could not be read: it still blocks)"
        print(f"attestation: {html_url} {why}; delete it and re-run the verifier")
    return 1


def _fixture_orders(n):
    if n <= 6:
        return [list(o) for o in itertools.permutations(range(n))]
    rng = random.Random(0)
    orders = [list(range(n))]
    for _ in range(200):
        o = list(range(n))
        rng.shuffle(o)
        orders.append(o)
    return orders


def fixture(path):
    """Classify `path`'s comments in their given order and in every
    permutation (all when <= 6 comments, else 200 seeded shuffles),
    comparing classify()'s result with `expect` as whole dicts. Returns
    (ok, message): message is empty on success, else the first mismatch."""
    with open(path) as f:
        data = json.load(f)
    ctx = data["context"]
    comments = data["comments"]
    expect = data["expect"]
    head = ctx["head"]
    prompt_sha256_or_None = ctx.get("prompt_sha256")
    solo = bool(ctx["solo"])
    pr_author = ctx["pr_author"]
    required_mode = ctx["required_mode"]
    ca = ctx.get("commit_authors")
    commit_authors = None if ca is None else set(ca)
    commits = ctx.get("commits")
    files = ctx.get("files")
    contents = ctx.get("contents")
    permissions = ctx.get("permissions")
    bases = ctx.get("bases")
    base_changes = ctx.get("base_changes")
    waiver_bases = ctx.get("waiver_bases")

    for order in _fixture_orders(len(comments)):
        ordered = [comments[i] for i in order]
        result = classify(
            ordered, head=head, prompt_sha256_or_None=prompt_sha256_or_None,
            solo=solo, pr_author=pr_author, required_mode=required_mode,
            commit_authors=commit_authors, commits=commits, files=files, contents=contents,
            permissions=permissions, bases=bases, base_changes=base_changes, waiver_bases=waiver_bases,
        )
        if result != expect:
            return False, (
                f"{path}: order {order} gave {json.dumps(result)}, expected {json.dumps(expect)}"
            )
    return True, ""


# --- CLI ----------------------------------------------------------------------

def _read_stdin() -> str:
    return sys.stdin.read()


def _cmd_marker(args):
    try:
        print(make_marker(
            mode=args.mode, sha=args.sha, base=args.base,
            prompt_sha256=args.prompt_sha256, model=args.model,
            verdict=args.verdict, digest=args.digest, origin=args.origin,
        ))
    except AttestationError as e:
        print(str(e), file=sys.stderr)
        sys.exit(e.code)


def _cmd_sanitize(_args):
    sys.stdout.write(sanitize(_read_stdin()))


def _cmd_verdict(_args):
    try:
        print(verdict(_read_stdin()))
    except AttestationError as e:
        print(str(e), file=sys.stderr)
        sys.exit(e.code)


def _cmd_digest(_args):
    print(digest(_read_stdin()))


def _cmd_prompt_hash(args):
    try:
        print(prompt_hash(args.ref))
    except AttestationError as e:
        print(str(e), file=sys.stderr)
        sys.exit(e.code)


def _cmd_policy(args):
    try:
        p = policy(args.ref)
    except AttestationError as e:
        print(str(e), file=sys.stderr)
        sys.exit(e.code)
    print(f"solo={p['solo']}")
    print(f"profile={p['profile']}")
    print(f"path={p['path']}")


def _cmd_review_scope(args):
    try:
        result = review_scope(args.base, args.head)
    except AttestationError as e:
        print(str(e), file=sys.stderr)
        sys.exit(e.code)
    print(json.dumps(result))


# --- release-check (REQ-350, REQ-311, REQ-334; P6 R11, R28) ---------------------------------------------------------
#
# The tag-time re-check: every first-parent commit of the base ref in <previous release tag>..<tag commit>, reduced
# through pr_attestation — the CI check's own classifier — and nothing else; no classifier rule is added or weakened.

_PRE_TRANSFER_KEY = "attestation_since"
_SUBJECT_PR = re.compile(r"(?:\(#(\d+)\)\s*$|^Merge pull request #(\d+)\b)")


def _git_out(*args):
    proc = subprocess.run(["git", *args], capture_output=True)
    if proc.returncode != 0:
        raise AttestationError(proc.stderr.decode("utf-8", "replace").strip() or f"git {' '.join(args)} failed", code=2)
    return proc.stdout.decode("utf-8")


def _git_ok(*args):
    return subprocess.run(["git", *args], capture_output=True).returncode == 0


def _dir_json(directory, name):
    """`<directory>/<name>` as a JSON list; an absent file is []. None when no directory was given (fetch from gh)."""
    if directory is None:
        return None
    p = Path(directory) / name
    return _load_json_file_list(p) if p.is_file() else []


def _pre_transfer_boundary(tag_commit, first_parents, earlier_tags):
    """The `attestation_since` sha from the template source's pack metadata as committed at the tag's tree (never the
    working tree or the PR head), or None when the pack carries none (every merge is judged). Fail closed (exit 2): a
    value that is not 40 hex, or not a first-parent commit of the base ref; a key in an instance's pack (only the template
    source names a boundary — an instance judges every merge); and a value that differs from the one committed at the
    newest earlier release tag whose tree carries the key (`earlier_tags`, newest first) — the boundary is introduced
    once and never moves, so after the release that introduced it, it can never fall inside a release range. An earlier
    tag with no pack file carries no key and is passed over; one whose pack cannot be read is named in a one-line note
    on stderr and passed over too, so the walk compares the value with the next older tag that carries the key (P6 R28;
    PR #56 verifier run 1, V2: visible, never silent — a released tree cannot be repaired, so failing closed on it would
    block every later release)."""
    import packinfo
    try:
        instance = packinfo.is_instance_at_ref(".", tag_commit)
        value = packinfo.get(".", _PRE_TRANSFER_KEY, ref=tag_commit)
    except packinfo.PackError as e:
        if str(e).startswith("no pack file"):
            return None
        raise AttestationError(f"release-check: {e}", code=2)
    if not value:
        return None
    if instance:
        raise AttestationError(f"release-check: {_PRE_TRANSFER_KEY} is set in an instance's pack (.specflow/pack.yml at the "
                               f"tag): only the template source's pack names a boundary; an instance judges every merge", code=2)
    if not _SHA40.match(value):
        raise AttestationError(f"release-check: {_PRE_TRANSFER_KEY} is not 40 lowercase hex characters: {value!r}", code=2)
    if value not in first_parents:
        raise AttestationError(f"release-check: {_PRE_TRANSFER_KEY} {value[:7]} is not a first-parent commit of the base ref", code=2)
    for tag in earlier_tags:
        name = tag.rsplit("/", 1)[-1].removesuffix("^{commit}")
        try:
            if packinfo.is_instance_at_ref(".", tag):
                continue
            before = packinfo.get(".", _PRE_TRANSFER_KEY, ref=tag)
        except packinfo.PackError as e:
            if not str(e).startswith("no pack file"):
                print(f"note: release-check: the pack at {name} cannot be read ({e}); its {_PRE_TRANSFER_KEY} is not "
                      f"compared — the walk goes on to the next earlier release tag", file=sys.stderr)
            continue
        if before:
            if before != value:
                raise AttestationError(f"release-check: {_PRE_TRANSFER_KEY} moved since {name} "
                                       f"({before[:7]} there, {value[:7]} at the tag): the boundary is introduced once and "
                                       f"never moves", code=2)
            break
    return value


def _git_remotes():
    """The configured remote names (`git remote`); empty when git fails — a short form is then stripped only for
    `origin/`."""
    proc = subprocess.run(["git", "remote"], capture_output=True)
    if proc.returncode != 0:
        return set()
    return {r for r in proc.stdout.decode("utf-8", "replace").split() if r}


def base_branch(base_ref):
    """The branch a PR's `base.ref` names for `--base-ref`: `refs/remotes/<remote>/` stripped for any remote (a remote
    name has no slash, so `refs/remotes/upstream/team/main` is `team/main`), `refs/heads/` stripped, and the short form
    `<remote>/` stripped for `origin` and for any configured remote (`git remote`) — never only its last segment; a
    short name whose first segment is not a remote (`team/main`, a local branch) is kept whole."""
    if base_ref.startswith("refs/remotes/"):
        rest = base_ref[len("refs/remotes/"):]
        remote, sep, branch = rest.partition("/")
        if remote and sep and branch:
            return branch
        return base_ref
    if base_ref.startswith("refs/heads/"):
        return base_ref[len("refs/heads/"):]
    remote, sep, branch = base_ref.partition("/")
    if sep and remote and branch and (remote == "origin" or remote in _git_remotes()):
        return branch
    return base_ref


def default_base_ref():
    """release-check's base when none is given: the full ref `refs/remotes/origin/main` when it resolves — git resolves
    a short name's refs/tags/<name> before refs/remotes/<name>, so a tag named origin/main would shadow it — else the
    short `origin/main`, a local checkout's own view (CI code always passes the full ref)."""
    if _git_ok("rev-parse", "-q", "--verify", "refs/remotes/origin/main^{commit}"):
        return "refs/remotes/origin/main"
    return "origin/main"


def _pr_candidates(repo, sha, base_name):
    """The merged PRs (base `base_name`) GitHub associates with a first-parent commit (`gh api
    repos/<repo>/commits/<sha>/pulls`), as (exact, others), each [{number, head, author, merge_commit_sha}]. Only an
    EXACT association — the PR's merge_commit_sha is the commit (a merge or a squash) — judges the commit; containment
    never does (a rebase merge's earlier commits, a fast-forward push of a head): `others` only names the PR in a direct
    push's line."""
    items = _gh_json_list(f"repos/{repo}/commits/{sha}/pulls")
    merged = [i for i in items if isinstance(i, dict) and i.get("merged_at") and (i.get("base") or {}).get("ref") == base_name]

    def entry(i):
        return {"number": i["number"], "head": (i.get("head") or {}).get("sha", ""),
                "author": (i.get("user") or {}).get("login", ""), "merge_commit_sha": i.get("merge_commit_sha") or ""}
    return ([entry(i) for i in merged if i.get("merge_commit_sha") == sha],
            [entry(i) for i in merged if i.get("merge_commit_sha") != sha])


def _merge_content_mismatch(sha, parent, parents, head):
    """None when `sha` carries exactly `head` merged onto `parent` — a merge commit whose parents are [parent, head], or a
    single-parent (squash) commit — with the tree `git merge-tree --write-tree <parent> <head>` writes; else the reason.
    The PR's verdict is for its head: a commit that adds anything to it is not that PR's merge."""
    if len(parents) > 2:
        return f"{len(parents)} parents"
    if len(parents) == 2 and parents[1] != head:
        return f"its second parent {parents[1][:7]} is not the PR's head {head[:7]}"
    proc = subprocess.run(["git", "merge-tree", "--write-tree", parent, head], capture_output=True)
    if proc.returncode == 1:
        return f"the PR's head {head[:7]} does not merge cleanly onto {parent[:7]}"
    if proc.returncode != 0:
        raise AttestationError(proc.stderr.decode("utf-8", "replace").strip() or "git merge-tree failed", code=2)
    expected = proc.stdout.decode("utf-8").split("\n", 1)[0].strip()
    actual = _git_out("rev-parse", f"{sha}^{{tree}}").strip()
    if expected != actual:
        return f"its tree {actual[:7]} is not the PR's head merged onto its parent ({expected[:7]})"
    return None


_ATTESTATION_PATH = "scripts/lib/specflow/attestation.py"


def _attestation_introduced(tag_full):
    """The oldest first-parent commit of the tag whose tree carries attestation.py, or None. Only commits whose parent is
    a strict ancestor of it predate attestation; after it, a parent without the module is a FAIL, never a skip."""
    fps = _git_out("rev-list", "--first-parent", "--reverse", tag_full).split()
    if not fps:
        return None
    proc = subprocess.run(["git", "cat-file", "--batch-check"], capture_output=True,
                          input="".join(f"{c}:{_ATTESTATION_PATH}\n" for c in fps).encode())
    if proc.returncode != 0:
        raise AttestationError(proc.stderr.decode("utf-8", "replace").strip() or "git cat-file failed", code=2)
    for c, line in zip(fps, proc.stdout.decode("utf-8").splitlines()):
        if not line.rstrip().endswith(" missing"):
            return c
    return None


# review-gate.md's minor exception (art-review-gate): a direct push may touch no phase artifact (specs, ADRs, plans,
# security — RUBRIC.md included — releases, architecture), not constitution.md, and no code or model-instruction path
# (review_scope's code list, which the prefixes below repeat for the directories the exception names).
_MINOR_EXCEPTION_DENIED_PREFIXES = ("docs/specs/", "docs/adr/", "docs/plans/", "docs/security/", "docs/releases/",
                                    "docs/architecture/", "src/", "verification/", "scripts/", ".github/", ".claude/")
_MINOR_EXCEPTION_DENIED_PATHS = ("constitution.md",)


def _release_published(repo, tag):
    """True when the GitHub Release of `tag` exists and is published (not a draft), read with `gh api
    repos/<repo>/releases/tags/<tag>`; False on a 404 (no Release). Any other failure is exit 2 (fail closed)."""
    proc = subprocess.run(["gh", "api", f"repos/{repo}/releases/tags/{tag}"], capture_output=True)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", "replace").strip()
        if "HTTP 404" in err or "Not Found" in err:
            return False
        raise AttestationError(f"release-check: the GitHub Release of {tag} cannot be read: {err or 'gh api failed'}", code=2)
    try:
        data = json.loads(proc.stdout.decode("utf-8"))
    except ValueError as e:
        raise AttestationError(f"release-check: the GitHub Release of {tag} is not JSON: {e}", code=2)
    return isinstance(data, dict) and data.get("tag_name") == tag and data.get("draft") is False


def release_check(repo, version, tag_commit, base_ref=None, since=None, prs=None, comments_dir=None,
                  commits_dir=None, permissions=None, out=print):
    """Judge every first-parent commit of `base_ref` (default: default_base_ref()) since the previous published release;
    returns the exit code (0 all accepted, 1 any FAIL, 2 gh or git failure). Output lines are R28's, oldest first, one
    per first-parent commit, then a summary whose count is ok + skipped + FAIL. A commit is judged by a PR only through
    the exact association (merge_commit_sha); a commit with none is a direct push, and so is a second commit naming a PR
    already judged (a PR merges once: skipping it would un-judge a commit)."""
    import release_gate
    if base_ref is None:
        base_ref = default_base_ref()
    tag_full = _git_out("rev-parse", "--verify", f"{tag_commit}^{{commit}}").strip()
    first_parents = set(_git_out("rev-list", "--first-parent", base_ref).split())
    if tag_full not in first_parents:
        out(f"FAIL {tag_full[:7]} tag-commit-off-main (not a first-parent commit of {base_ref})")
        return 1
    earlier_tags = [f"refs/tags/v{p}" for p in release_gate.earlier_releases(Path("."), version, base_ref)
                    if _git_ok("rev-parse", "-q", "--verify", f"refs/tags/v{p}^{{commit}}")]
    boundary = _pre_transfer_boundary(tag_full, first_parents, [f"{t}^{{commit}}" for t in earlier_tags])

    if since is None:
        # the newest earlier release tag whose GitHub Release is published: a tag whose own release.yml run refused (no
        # Release, or a draft), like a release left untagged, is walked through, never a starting point — its merges are
        # judged with this one's (more, never fewer)
        for t in earlier_tags:
            if _release_published(repo, t[len("refs/tags/"):]):
                since = t
                break
    rng = f"{since}..{tag_full}" if since else tag_full
    commits = _git_out("rev-list", "--first-parent", "--reverse", rng).split()
    base_name = base_branch(base_ref)
    introduced = None
    judged_at = {}  # PR number -> the sha7 of the commit it judged

    counts = Counter()
    for sha in commits:
        s7 = sha[:7]
        parents = _git_out("rev-list", "--parents", "-n", "1", sha).split()[1:]
        if not parents:
            out(f"skip {s7} root")
            counts["root"] += 1
            continue
        parent = parents[0]
        cands, assoc = None, []
        if prs is not None:
            pr = prs.get(sha)
            cands = [pr] if pr else []
        if boundary is not None and sha != boundary and _git_ok("merge-base", "--is-ancestor", sha, boundary):
            n = (cands[0] if cands else {}).get("number")
            if n is None:
                m = _SUBJECT_PR.search(_git_out("log", "-1", "--format=%s", sha).strip())
                n = m.group(1) or m.group(2) if m else None
            out(f"skip {s7} pre-transfer" + (f" #{n}" if n else ""))
            counts["pre-transfer"] += 1
            continue
        if cands is None:
            cands, assoc = _pr_candidates(repo, sha, base_name)
        again = [c for c in cands if c.get("number") in judged_at]
        cands = [c for c in cands if c.get("number") not in judged_at]
        if cands:
            n = cands[0]["number"]
            if not _git_ok("cat-file", "-e", f"{parent}:{_ATTESTATION_PATH}"):
                if introduced is None:
                    introduced = _attestation_introduced(tag_full) or ""
                if introduced and parent != introduced and _git_ok("merge-base", "--is-ancestor", parent, introduced):
                    out(f"skip {s7} predates-attestation")
                    counts["predates-attestation"] += 1
                else:
                    out(f"FAIL #{n} attestation-missing {s7} (its parent {parent[:7]} carries no {_ATTESTATION_PATH}, "
                        f"which an earlier first-parent commit did: nothing judged this merge)")
                    counts["FAIL"] += 1
                continue
            pr, why = None, None
            for cand in cands:
                if not cand.get("head") or not _git_ok("cat-file", "-e", f"{cand['head']}^{{commit}}"):
                    why = why or ("head-missing", f"(fetch the PR heads: git fetch <remote> '+refs/pull/*/head:refs/remotes/<remote>/pr/*')")
                    continue
                mismatch = _merge_content_mismatch(sha, parent, parents, cand["head"])
                if mismatch:
                    why = why if why and why[0] == "merge-content-mismatch" else ("merge-content-mismatch", f"({mismatch}; a "
                          f"maintainer waiver on the commit is the remedy)")
                    continue
                pr = cand
                break
            if pr is None:
                out(f"FAIL #{n} {why[0]} {s7} {why[1]}")
                counts["FAIL"] += 1
                continue
            n = pr["number"]
            judged_at[n] = s7
            res = pr_attestation(repo=repo, pr=n, head=pr["head"], base_ref=parent, pr_author=pr.get("author", ""),
                                 commits=_dir_json(commits_dir, f"{n}.json"), comments=_dir_json(comments_dir, f"{n}.json"),
                                 permissions=permissions)
            if res["state"] in ("approve", "waiver"):
                label = "exempt-dependabot" if res["reason"] == "exempt-dependabot" else res["state"]
                out(f"ok #{n} {label} {s7}")
                counts["ok"] += 1
            elif pr.get("author") == DEPENDABOT and res.get("exempt_reason") not in (None, "exempt-dependabot"):
                # the PR's only route was the exemption: its refusal is the reason (the classifier's none is a symptom)
                out(f"FAIL #{n} dependabot:{res['exempt_reason']} {s7} (the Dependabot exemption refused it; the "
                    f"classifier: {res['state']}, {res['reason']})")
                counts["FAIL"] += 1
            else:
                line = f"FAIL #{n} {res['state']} ({res['reason']}) {s7}"
                if res["reason"] in ("waiver-unbound-retargeted", "waiver-timeline-unknown"):
                    line += (f"; remedy: a maintainer posts on PR #{n} <!-- specflow-verifier:waive sha:{pr['head']} "
                             f"base:{parent} --> with a rationale")
                out(line)
                counts["FAIL"] += 1
            continue
        # no exact PR: say which PR GitHub merely associates with it (containment), or which already judged one
        if again:
            nopr = f" (no-pr: #{again[0]['number']} was already judged at {judged_at[again[0]['number']]})"
        elif assoc:
            mcs = assoc[0].get("merge_commit_sha") or ""
            nopr = (f" (no-pr: #{assoc[0]['number']} contains it but merged as {mcs[:7] or 'nothing'}, not this commit; "
                    f"containment never judges a commit)")
        else:
            nopr = ""
        # a direct push: accepted unwaived only inside review-gate.md's minor exception (no code, no phase artifact, no
        # constitution.md), else only under a maintainer's marker or waiver on the commit (R28's remedy) — never the
        # Dependabot exemption, whose identity leg is the PR opener and a direct push has none
        scope = review_scope(parent, sha)
        code = list(scope["code"])
        phase = [p for p in scope["docs"] + scope["other"] if p not in code
                 and (p.startswith(_MINOR_EXCEPTION_DENIED_PREFIXES) or p in _MINOR_EXCEPTION_DENIED_PATHS)]
        if not code and not phase:
            out(f"ok {s7} direct-push documents-only")
            counts["ok"] += 1
            continue
        what = f"code: {', '.join(code + phase)}" if code else f"phase-artifact: {', '.join(phase)}"
        comments = _dir_json(comments_dir, f"commit-{sha}.json")
        if comments is None:
            comments = _gh_json_list(f"repos/{repo}/commits/{sha}/comments")
        comments = [c for c in comments if isinstance(c, dict) and MARKER_OCCURRENCE in (c.get("body") or "")]
        if not comments:
            out(f"FAIL {s7} direct-push {what}{nopr}")
            counts["FAIL"] += 1
            continue
        cj = _dir_json(commits_dir, f"commit-{sha}.json")
        if cj is None:
            cj = _load_json_file_list_from_obj(_gh_json_list(f"repos/{repo}/commits/{sha}"))
        author = commit_author(cj[0]) if cj else ""
        res = pr_attestation(repo=repo, pr=None, head=sha, base_ref=parent, pr_author=author, commits=cj,
                             comments=comments, permissions=permissions)
        if res["state"] in ("approve", "waiver") and res["reason"] != "exempt-dependabot":
            out(f"ok {s7} direct-push {res['state']}")
            counts["ok"] += 1
        else:
            out(f"FAIL {s7} direct-push {what} (on the commit: {res['state']}, {res['reason']}){nopr}")
            counts["FAIL"] += 1
    skipped = sum(counts[k] for k in ("root", "predates-attestation", "pre-transfer"))
    out(f"release-check {version}: {len(commits)} first-parent commits since {since or 'the root'}: {counts['ok']} ok, "
        f"{skipped} skipped (root {counts['root']}, predates-attestation {counts['predates-attestation']}, "
        f"pre-transfer {counts['pre-transfer']}), {counts['FAIL']} FAIL")
    return 1 if counts["FAIL"] else 0


def _load_json_file_list_from_obj(data):
    return [data] if isinstance(data, dict) else data


def _cmd_release_check(args):
    try:
        prs = json.load(open(args.prs)) if args.prs else None
        perms = json.load(open(args.permissions)) if args.permissions else None
        rc = release_check(args.repo, args.version, args.tag_commit, base_ref=args.base_ref, since=args.since, prs=prs,
                           comments_dir=args.comments_dir, commits_dir=args.commits_dir, permissions=perms)
    except (AttestationError, OSError, ValueError) as e:
        msg = str(e)
        print(msg if msg.startswith("release-check:") else f"release-check: {msg}", file=sys.stderr)
        sys.exit(2)
    sys.exit(rc)


def _solo_type(v):
    if v not in ("true", "false"):
        raise argparse.ArgumentTypeError("must be true or false")
    return v == "true"


def _cmd_classify(args):
    with open(args.comments) as f:
        comments = json.load(f)
    prompt_sha256_or_None = None if args.base_predates else args.prompt_sha256
    result = classify(
        comments, head=args.head, prompt_sha256_or_None=prompt_sha256_or_None,
        solo=args.solo, pr_author=args.pr_author, required_mode=args.required_mode,
    )
    print(json.dumps(result))


def _cmd_check(args):
    rc = check(
        repo=args.repo, pr=args.pr, head=args.head, base_ref=args.base_ref,
        base_name=args.base_name, pr_author=args.pr_author, comments_file=args.comments,
        commits_file=args.commits, files_file=args.files, contents_file=args.contents,
        permissions_file=args.permissions,
    )
    sys.exit(rc)


def _cmd_fixture(args):
    ok, message = fixture(args.path)
    if not ok:
        print(message, file=sys.stderr)
        sys.exit(1)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="attestation.py")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_marker = sub.add_parser("marker")
    p_marker.add_argument("--mode", required=True)
    p_marker.add_argument("--sha", required=True)
    p_marker.add_argument("--base", required=True)
    p_marker.add_argument("--prompt-sha256", required=True)
    p_marker.add_argument("--model", required=True)
    p_marker.add_argument("--verdict", required=True)
    p_marker.add_argument("--digest", required=True)
    p_marker.add_argument("--origin", required=True)
    p_marker.set_defaults(func=_cmd_marker)

    p_sanitize = sub.add_parser("sanitize")
    p_sanitize.set_defaults(func=_cmd_sanitize)

    p_verdict = sub.add_parser("verdict")
    p_verdict.set_defaults(func=_cmd_verdict)

    p_digest = sub.add_parser("digest")
    p_digest.set_defaults(func=_cmd_digest)

    p_prompt_hash = sub.add_parser("prompt-hash")
    p_prompt_hash.add_argument("--ref", required=True)
    p_prompt_hash.set_defaults(func=_cmd_prompt_hash)

    p_policy = sub.add_parser("policy")
    p_policy.add_argument("--ref", required=True)
    p_policy.set_defaults(func=_cmd_policy)

    p_review_scope = sub.add_parser("review-scope")
    p_review_scope.add_argument("--base", required=True)
    p_review_scope.add_argument("--head", required=True)
    p_review_scope.set_defaults(func=_cmd_review_scope)

    p_classify = sub.add_parser("classify")
    p_classify.add_argument("--comments", required=True)
    p_classify.add_argument("--head", required=True)
    p_classify.add_argument("--pr-author", required=True)
    p_classify.add_argument("--solo", required=True, type=_solo_type)
    p_classify.add_argument("--required-mode", required=True)
    prompt_group = p_classify.add_mutually_exclusive_group(required=True)
    prompt_group.add_argument("--prompt-sha256")
    prompt_group.add_argument("--base-predates", action="store_true")
    p_classify.set_defaults(func=_cmd_classify)

    p_check = sub.add_parser("check")
    p_check.add_argument("--repo", required=True)
    p_check.add_argument("--pr", required=True)
    p_check.add_argument("--head", required=True)
    p_check.add_argument("--base-ref", required=True)
    p_check.add_argument("--base-name", required=True)
    p_check.add_argument("--pr-author", required=True)
    p_check.add_argument("--comments")
    p_check.add_argument("--commits")
    p_check.add_argument("--files")
    p_check.add_argument("--contents")
    p_check.add_argument("--permissions", help="test-only JSON {login: role}; verifier.yml never passes it")
    p_check.set_defaults(func=_cmd_check)

    p_rc = sub.add_parser("release-check")
    p_rc.add_argument("--repo", required=True)
    p_rc.add_argument("--version", required=True)
    p_rc.add_argument("--tag-commit", required=True)
    p_rc.add_argument("--base-ref", help="default: refs/remotes/origin/main when it resolves, else origin/main")
    p_rc.add_argument("--since", help="preview-only: overrides the start of the range (P6 R28's preview); release.yml "
                                      "and release-tag.sh never pass it")
    p_rc.add_argument("--prs", help="test-only JSON {sha: {number, head, author} | null}; no workflow or script passes it")
    p_rc.add_argument("--comments-dir", help="test-only: <number>.json, commit-<sha>.json")
    p_rc.add_argument("--commits-dir", help="test-only: <number>.json, commit-<sha>.json")
    p_rc.add_argument("--permissions", help="test-only JSON {login: role}; no workflow or script passes it")
    p_rc.set_defaults(func=_cmd_release_check)

    p_fixture = sub.add_parser("fixture")
    p_fixture.add_argument("path")
    p_fixture.set_defaults(func=_cmd_fixture)

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
