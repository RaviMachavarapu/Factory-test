#!/usr/bin/env python3
"""A PreToolUse hook on Bash that asks before a push to `main` or a `gh pr merge` (BL-001; REQ-371, REQ-385).

`.claude/settings.json` registers it for the Bash tool. It reads the hook input (JSON on stdin: `tool_input.command`
and `cwd`), splits the command into simple commands (`&&`, `||`, `;`, `|`, `&`, newlines, `$( )` and `( )`, the
argument of `bash -c`/`sh -c`/`eval`), and, for each `git push`, resolves the destination ref of every refspec —
`+main`, `HEAD:main`, `<src>:main`, `:main`, `refs/heads/main`, `--all`/`--mirror`, any remote name — and, for a push
with no refspec, the current branch (and, under `push.default=upstream` or `matching`, its upstream or every branch),
in the directory `cd` and `git -C` leave.
When any destination is `main`, or the command runs `gh pr merge` (an env prefix such as `GH_TOKEN=... gh pr merge`
included), it prints a `permissionDecision: ask` and the session asks the user first.

It asks, never denies: guided `/next` runs the merge after the user's yes (P5 R14), and merges stay the maintainer's.
Like `permissions.ask`, it is a local convenience, not a control: project hooks are per-checkout and editable by any
PR (dfe-10); `main`'s server-side protection is unchanged — and it binds non-admins only (`enforce_admins: false`), so for
a repository admin, a solo owner included, or on a free-plan private repository, the user's yes is the only gate. It errs toward asking (a command it cannot parse that
mentions `git`/`push` or `gh`/`merge` asks). Residuals: a git alias (`git p`), a script that pushes (`bash x.sh`), a
`remote.<name>.push` mapping and `gh api` merges are not resolved; nor are shell variables and command substitutions
(`git push origin "$B"`, `git push origin $(git branch --show-current)`), commands run through `xargs` or `find -exec`,
a wrapper's flag values (`sudo -u root git push …` reads as program `root`) and, for a push with no explicit ref, a
`--git-dir` repository's branch (the branch is read from the working directory, so `git --git-dir=<x> push` from a
checkout on `main` asks and from a feature branch stays silent); `main` is hard-coded.

Stdlib only; exits 0 always (exit 2 would block the tool call).
"""
from __future__ import annotations

import fnmatch
import json
import os
import re
import shlex
import subprocess
import sys

MAIN = "main"
PUNCT = "();<>|&\n"
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"env", "command", "builtin", "exec", "nohup", "time", "sudo", "nice"}
SHELLS = {"bash", "sh", "zsh", "dash"}
GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env"}
GH_VALUE_OPTS = {"-R", "--repo", "--hostname"}
PUSH_VALUE_OPTS = {"--repo", "-o", "--push-option", "--receive-pack", "--exec"}


def tokens(cmd: str) -> list[str]:
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=PUNCT)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""  # a `#` mid-word is not a comment in bash; reading one as text only over-asks
    return list(lex)


def simple_commands(cmd: str) -> list[list[str]]:
    out: list[list[str]] = []
    cur: list[str] = []
    skip_next = False
    for t in tokens(cmd):
        if skip_next:
            skip_next = False
            continue
        if t and all(c in PUNCT for c in t):
            if "<" in t or ">" in t:  # a redirection: drop it and its target word
                skip_next = not t.endswith("&") or t in (">&", "<&")
                continue
            if cur:
                out.append(cur)
            cur = []
            continue
        cur.append(t)
    if cur:
        out.append(cur)
    return out


def strip_prefix(words: list[str]) -> list[str]:
    i = 0
    while i < len(words):
        w = words[i]
        if ASSIGN.match(w) or w in WRAPPERS or (i > 0 and words[0] in WRAPPERS and w.startswith("-")):
            i += 1
            continue
        break
    return words[i:]


def git(cwd: str, *args: str) -> str | None:
    try:
        r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    except OSError:
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def short(ref: str) -> str:
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def is_main(ref: str) -> bool:
    ref = short(ref)
    return ref == MAIN or ("*" in ref and fnmatch.fnmatchcase(MAIN, ref))


def current_branch(cwd: str) -> str | None:
    return git(cwd, "symbolic-ref", "-q", "--short", "HEAD")


def push_reasons(args: list[str], cwd: str) -> list[str]:
    positional: list[str] = []
    every = False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            positional += args[i + 1:]
            break
        if a in PUSH_VALUE_OPTS:
            i += 2
            continue
        if a in ("--all", "--mirror", "--branches"):
            every = True
        if a.startswith("-") and a != "-":
            i += 1
            continue
        positional.append(a)
        i += 1
    if every:
        return ["git push --all/--mirror pushes every branch, main included"]
    refspecs = positional[1:]
    branch = current_branch(cwd)
    if not refspecs:
        if branch is None:
            return [f"git push with no refspec, and the current branch in {cwd} cannot be resolved"]
        if branch == MAIN:
            return ["git push with no refspec while on main"]
        mode = git(cwd, "config", "--get", "push.default") or "simple"
        if mode == "matching":
            return ["git push with no refspec under push.default=matching pushes every matching branch, main included"]
        upstream = git(cwd, "config", "--get", f"branch.{branch}.merge")
        if mode in ("upstream", "tracking") and upstream and is_main(upstream):
            return [f"git push with no refspec on {branch}, whose upstream is main (push.default={mode})"]
        return []  # simple (the default) refuses a differently named upstream; current pushes to {branch}
    reasons = []
    for spec in refspecs:
        spec = spec.lstrip("+")
        src, _, dst = spec.partition(":")
        if not dst:
            dst = src
        if dst in ("HEAD", "@"):
            if branch is None:
                reasons.append(f"git push {spec}: the current branch in {cwd} cannot be resolved")
                continue
            dst = branch
        if is_main(dst):
            reasons.append(f"git push {spec} updates main")
    return reasons


def reasons_for(cmd: str, cwd: str, depth: int = 0) -> list[str]:
    reasons: list[str] = []
    for words in simple_commands(cmd):
        words = strip_prefix(words)
        if not words:
            continue
        prog = os.path.basename(words[0])
        if prog == "cd":
            target = os.path.expanduser(words[1]) if len(words) > 1 else os.path.expanduser("~")
            cwd = os.path.normpath(os.path.join(cwd, target))
            continue
        if depth < 3 and prog in SHELLS and "-c" in words[1:]:
            j = words.index("-c", 1)
            if j + 1 < len(words):
                reasons += reasons_for(words[j + 1], cwd, depth + 1)
            continue
        if depth < 3 and prog == "eval":
            reasons += reasons_for(" ".join(words[1:]), cwd, depth + 1)
            continue
        if prog == "gh":
            # Drop flags and the values of gh's value-taking global flags (-R/--repo, --hostname), so
            # `gh -R o/r pr merge 5` and `gh pr --repo o/r merge 5` read as `pr merge` too.
            rest, k = [], 1
            while k < len(words):
                if words[k] in GH_VALUE_OPTS:
                    k += 2
                    continue
                if not words[k].startswith("-"):
                    rest.append(words[k])
                k += 1
            if rest[:2] == ["pr", "merge"]:
                reasons.append("gh pr merge: merges are the maintainer's")
            continue
        if prog != "git":
            continue
        gcwd, i = cwd, 1
        while i < len(words):
            w = words[i]
            if w in GIT_VALUE_OPTS:
                if w == "-C" and i + 1 < len(words):
                    gcwd = os.path.normpath(os.path.join(gcwd, os.path.expanduser(words[i + 1])))
                i += 2
                continue
            if w.startswith("-"):
                i += 1
                continue
            break
        if i < len(words) and words[i] == "push":
            reasons += push_reasons(words[i + 1:], gcwd)
    return reasons


def decide(payload: dict) -> list[str]:
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    cwd = payload.get("cwd") or os.getcwd()
    if not isinstance(cmd, str) or not cmd.strip():
        return []
    try:
        return reasons_for(cmd, cwd)
    except Exception as e:  # noqa: BLE001 — err toward asking on anything that looks like a push or a merge
        if re.search(r"\bgit\b.*\bpush\b|\bgh\b.*\bmerge\b", cmd, re.S):
            return [f"could not parse the command ({type(e).__name__}); it may push or merge"]
        return []


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    if not isinstance(payload, dict):
        return 0
    reasons = decide(payload)
    if reasons:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "BL-001: " + "; ".join(dict.fromkeys(reasons))
            + " — confirm before it runs (main's merges and pushes are the maintainer's)",
        }}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # noqa: BLE001 — never exit 2, which would block the tool call
        sys.exit(0)
