"""scripts/lib/specflow/signers.py — the signing anchor: a release tag verified against allowed_signers (REQ-383; P6 R3).

A release tag `v<V>` is verified with the SSH signers file as committed at the *anchor*, never the current tree:
  1. the candidates are the existing `v<X.Y.Z>` TAGS below V whose commits are strict ancestors of the tag's commit,
     newest first (semver order) — tags, never the release notes on the base, so a reviewed docs PR that deletes
     earlier releases' notes moves nothing (P6 R3(i), fix wave 2). The NEWEST candidate decides: SSH-signed → it is the
     anchor, provided its commit is a first-parent commit of the base (`anchor-off-main`) and it itself verifies
     `ssh-good` against its own anchor, recursively (`anchor-unverified`); unsigned, lightweight or GPG-signed → it is
     passed over and the next older candidate is considered;
  2. only when no candidate is SSH-signed, trust on first use (TOFU), bounded to the tag's own history: among the
     first-parent commits of the base that are strict ancestors of the tag's commit, the oldest one after the newest
     whose `.github/allowed_signers` is absent or lists no key, provided it lists a key; with none, `no-anchor`.
     Because neither step looks past the tag's commit, a tag's verdict is fixed once it exists: a later key-less
     commit cannot un-verify an earlier tag.
A shallow clone is `shallow`; a git error anywhere in the walk is `git-error` (refused, never "no anchor"). git itself
does not bind a key's principal to the tagger, so `verify` does: the principal git finds must equal the tagger's email
as git parses the tag header (`git for-each-ref %(taggeremail:trim)`), exactly and case-sensitively
(`tagger-mismatch`); a tag object with no tagger is `bad`. Every SSH verification pins `gpg.ssh.program` to the
`ssh-keygen` on PATH and `gpg.ssh.allowedSignersFile` to the anchor's copy, so local configuration never widens trust.
`.github/revoked_signers` is read from the tag's own tree and, at tag time (the default; release-tag.sh and
release.yml), also from the base's tip — revocation only narrows trust; `released=True` (`--released`: anchors and the PR-time
previous-tag check) reads the tag's tree only. A key listed there is `revoked`; a file git cannot read is
`revocation-unreadable` and a line that is not `<keytype> <base64>` is `revocation-malformed` (both refused).

CLI: signers.py --root DIR [--base-ref REF] verify --tag T [--released] | anchor --tag T | signing-kind |
previous --version V (previous_release_check: exit 0 the previous release is tagged and verifies as released, or there
is none; 1 untagged or refused; release.yml and release-tag.sh both run it)
Exit codes of verify: 0 ssh-good/gpg-good; 1 refusal (bad, unlisted, tagger-mismatch, revoked, revocation-unreadable,
revocation-malformed, anchor-off-main, anchor-unverified, shallow, lightweight, git-error); 3 unsigned; 4
gpg-unverifiable or no-anchor; 2 usage or a missing tag. signing-kind prints ssh | gpg | other | none and the reason:
ssh (gpg.format ssh with user.signingkey or gpg.ssh.defaultKeyCommand), gpg (OpenPGP: a user.signingkey, or a GPG
secret key for the committer's email), other (any other gpg.format, x509 included), none only when no signer is
configured or usable at all.
Stdlib only; git is the only subprocess (and the ssh-keygen it calls), plus `gpg --list-secret-keys` for signing-kind.
"""
from __future__ import annotations

import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blocks  # noqa: E402
import release_gate  # noqa: E402

SSH_BLOCK_RE = re.compile(r"^-----BEGIN SSH SIGNATURE-----$", re.M)
PGP_BLOCK_RE = re.compile(r"^-----BEGIN PGP SIGNATURE-----$", re.M)
GOOD_RE = re.compile(r'Good "git" signature for (\S+) with ')
BAD_RE = re.compile(r"BAD signature", re.I)
RELEASE_TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
KEY_TYPES = ("ssh-ed25519", "ssh-rsa", "ssh-dss", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521",
             "sk-ssh-ed25519@openssh.com", "sk-ecdsa-sha2-nistp256@openssh.com")
ALLOWED = ".github/allowed_signers"
REVOKED = ".github/revoked_signers"

REFUSALS = ("bad", "unlisted", "tagger-mismatch", "revoked", "revocation-unreadable", "revocation-malformed",
            "anchor-off-main", "anchor-unverified", "shallow", "lightweight", "git-error")
EXIT = {"ssh-good": 0, "gpg-good": 0, "unsigned": 3, "gpg-unverifiable": 4, "no-anchor": 4}


class Anchor(NamedTuple):
    ref: str
    how: str


class Refusal(NamedTuple):
    kind: str
    detail: str


class Verdict(NamedTuple):
    kind: str
    principal: str
    tagger: str
    anchor: str
    detail: str


class UsageError(Exception):
    pass


class GitError(Exception):
    """git could not answer (a missing object, an unknown ref): the caller refuses, never reads it as absent."""


def _git(root, *args: str, env=None) -> subprocess.CompletedProcess:
    e = dict(os.environ)
    e["LC_ALL"] = "C"
    if env:
        e.update(env)
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, env=e,
                          stdin=subprocess.DEVNULL)


def _ok(root, *args: str) -> str:
    """git's stdout; GitError when git fails."""
    p = _git(root, *args)
    if p.returncode != 0:
        last = ((p.stderr or "").strip().splitlines() or ["failed"])[-1]
        raise GitError(f"git {' '.join(args)}: {last}")
    return p.stdout


def _key_lines(text: str) -> list:
    return [l for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#")]


def _read(root, ref: str, path: str) -> Optional[str]:
    """The file at `ref`, None when the path is absent there; GitError when git cannot answer (an unknown ref, a
    missing object) — never read as absent."""
    entry = _ok(root, "ls-tree", "-z", ref, "--", path)
    if not entry:
        return None
    meta = entry.split("\t", 1)[0].split()
    if len(meta) != 3 or meta[1] != "blob":
        raise GitError(f"{path} at {ref} is not a file")
    return _ok(root, "cat-file", "blob", meta[2])


def _cfg(root, key: str) -> str:
    return _git(root, "config", key).stdout.strip()


def _committer_email(root) -> str:
    m = re.search(r"<([^>]*)>", _git(root, "var", "GIT_COMMITTER_IDENT").stdout)
    return m.group(1) if m else ""


def _gpg_secret_key(root, email: str) -> tuple:
    """(held, program): a GPG secret key for `email` — a `sec` record of `<gpg> --batch --with-colons
    --list-secret-keys <email>` — that git signs with when no user.signingkey is set; probed only when the configured
    program (gpg.openpgp.program, gpg.program, else gpg) exists."""
    prog = _cfg(root, "gpg.openpgp.program") or _cfg(root, "gpg.program") or "gpg"
    if not email or not (shutil.which(prog) or os.path.isfile(prog)):
        return False, prog
    try:
        p = subprocess.run([prog, "--batch", "--with-colons", "--list-secret-keys", email], capture_output=True,
                           text=True, timeout=20, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return False, prog
    held = p.returncode == 0 and any(l.split(":")[0] == "sec" and l.split(":")[1:2] != ["r"]
                                     for l in p.stdout.splitlines() if ":" in l)
    return held, prog


def signing_kind(root) -> tuple:
    """Returns (kind, reason): ssh | gpg | other | none. `none` means no signer is configured or usable at all — the only
    case in which art-release-readiness permits an annotated tag; the tag path is SSH-only (release-tag.sh and
    release.yml), so gpg and other stop release-tag.sh (exit 5). The reason names what was found."""
    fmt = _cfg(root, "gpg.format")
    key = _cfg(root, "user.signingkey")
    dkc = _cfg(root, "gpg.ssh.defaultKeyCommand")
    if fmt == "ssh":
        if key:
            return "ssh", "gpg.format is ssh and user.signingkey is set"
        if dkc:
            return "ssh", "gpg.format is ssh and gpg.ssh.defaultKeyCommand is set"
        return "none", "gpg.format is ssh but neither user.signingkey nor gpg.ssh.defaultKeyCommand is set"
    if fmt not in ("", "openpgp"):
        return "other", (f"gpg.format is {fmt} (not ssh or openpgp)" + (" and user.signingkey is set" if key else "")
                         + "; the tag path is SSH-only (release.yml's too)")
    what = f"gpg.format is {fmt}" if fmt else "gpg.format is unset (OpenPGP)"
    if key:
        return "gpg", f"{what} and user.signingkey is set; the tag path is SSH-only (release.yml's too)"
    email = _committer_email(root)
    held, prog = _gpg_secret_key(root, email)
    if held:
        return "gpg", (f"{what}, no user.signingkey, and {prog} holds a GPG secret key for {email}, which git signs with; "
                       "the tag path is SSH-only (release.yml's too)")
    return "none", f"{what}, no user.signingkey is set, and {prog} holds no GPG secret key for {email or 'the committer'}"


def _tag_info(root, tag: str):
    """Returns (object type, raw tag text, signature kind 'ssh'|'pgp'|'none', tagger email as git parses the header —
    '' when there is none); UsageError when the tag is missing."""
    p = _git(root, "cat-file", "-t", f"refs/tags/{tag}")
    if p.returncode != 0:
        raise UsageError(f"no such tag: {tag}")
    otype = p.stdout.strip()
    if otype != "tag":
        return otype, "", "none", ""
    raw = _ok(root, "cat-file", "tag", f"refs/tags/{tag}")
    tagger = ""
    for line in _ok(root, "for-each-ref", "--format=%(refname)%00%(taggeremail:trim)", f"refs/tags/{tag}").splitlines():
        ref, _, email = line.partition("\0")
        if ref == f"refs/tags/{tag}":
            tagger = email.strip()
    sig = "ssh" if SSH_BLOCK_RE.search(raw) else "pgp" if PGP_BLOCK_RE.search(raw) else "none"
    return otype, raw, sig, tagger


def _commit(root, tag: str) -> str:
    return _ok(root, "rev-parse", f"refs/tags/{tag}^{{commit}}").strip()


def _first_parent(root, ref: str) -> list:
    return _ok(root, "rev-list", "--first-parent", ref).split()


def _is_shallow(root) -> bool:
    return _ok(root, "rev-parse", "--is-shallow-repository").strip() == "true"


def _strict_ancestors(root, tc: str) -> set:
    return set(_ok(root, "rev-list", tc).split()) - {tc}


def _candidates(root, tag: str, below: set) -> list:
    """The v<X.Y.Z> tags below the tag's version whose commits are strict ancestors of the tag's commit (`below`),
    newest first (semver order). A v-tag that does not peel to a commit can anchor nothing and is skipped."""
    version = tag[1:] if tag.startswith("v") else tag
    top = blocks.version_key(version)
    found = []
    for name in _ok(root, "for-each-ref", "--format=%(refname:strip=2)", "refs/tags/").split():
        if not RELEASE_TAG_RE.match(name) or blocks.version_key(name[1:]) >= top:
            continue
        p = _git(root, "rev-parse", "-q", "--verify", f"refs/tags/{name}^{{commit}}")
        if p.returncode == 0 and p.stdout.strip() in below:
            found.append(name)
    return sorted(found, key=lambda n: blocks.version_key(n[1:]), reverse=True)


def _tofu(root, below: set, base_ref: str) -> Optional[Anchor]:
    """TOFU bounded to the tag's own history: only first-parent commits of the base that are strict ancestors of the
    tag's commit (`below`) are walked, newest first, so nothing merged after the tag can move its anchor."""
    oldest = None
    for c in _first_parent(root, base_ref):   # newest first
        if c not in below:
            continue
        text = _read(root, c, ALLOWED)
        if text is None or not _key_lines(text):
            break
        oldest = c
    return Anchor(oldest, "tofu") if oldest else None


_anchor_memo: dict = {}
_verify_memo: dict = {}


def anchor(root, tag: str, base_ref: str = "origin/main"):
    key = (str(root), tag, base_ref)
    if key not in _anchor_memo:
        try:
            _anchor_memo[key] = _anchor(root, tag, base_ref)
        except GitError as e:
            _anchor_memo[key] = Refusal("git-error", f"git could not walk the anchor's history: {e}")
    return _anchor_memo[key]


def _anchor(root, tag: str, base_ref: str):
    if _is_shallow(root):
        return Refusal("shallow", "this clone is shallow (git rev-parse --is-shallow-repository); the anchor walk needs "
                                  "the whole first-parent history — fetch it in full (fetch-depth: 0)")
    below = _strict_ancestors(root, _commit(root, tag))
    base_fp = None
    for ptag in _candidates(root, tag, below):
        otype, _raw, sig, _tagger = _tag_info(root, ptag)
        if otype != "tag" or sig != "ssh":
            continue   # lightweight, unsigned or GPG-signed: passed over to the next older candidate (P6 R3(i))
        if base_fp is None:
            base_fp = set(_first_parent(root, base_ref))
        if _commit(root, ptag) not in base_fp:
            return Refusal("anchor-off-main", f"{ptag}, the newest earlier SSH-signed release tag, is not on a "
                                              f"first-parent commit of {base_ref}")
        pv = verify(root, ptag, base_ref, released=True)
        if pv.kind != "ssh-good":
            return Refusal("anchor-unverified", f"the newest earlier SSH-signed release tag {ptag} does not verify "
                                                f"({pv.kind})")
        return Anchor(ptag, "previous-release")
    return _tofu(root, below, base_ref)


def _tmp(text: str) -> str:
    fd, path = tempfile.mkstemp(prefix="specflow-signers-")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    return path


def _revocation_lines(text: str, where: str):
    """The key lines of a revoked_signers file as `<keytype> <base64>`; a Refusal('revocation-malformed') for any line
    that is not one (an allowed_signers-format line, an unknown key type, base64 that does not decode to that key)."""
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        f = line.split()
        ok = len(f) >= 2 and f[0] in KEY_TYPES
        if ok:
            try:
                blob = base64.b64decode(f[1], validate=True)
                ok = blob[4:4 + len(f[0])] == f[0].encode() and int.from_bytes(blob[:4], "big") == len(f[0])
            except (ValueError, TypeError):
                ok = False
        if not ok:
            return Refusal("revocation-malformed", f"{REVOKED} at {where}, line {n}, is not '<keytype> <base64>' "
                                                   "(the first two fields of a .pub file)")
        out.append(f"{f[0]} {f[1]}")
    return out


def verify(root, tag: str, base_ref: str = "origin/main", released: bool = False) -> Verdict:
    """released=False (tag time): revocation is read at the tag's tree and at the base's tip; released=True (an anchor,
    the PR-time previous-tag check): at the tag's tree only, so a released tag's verdict is fixed once it exists."""
    key = (str(root), tag, base_ref, released)
    if key not in _verify_memo:
        try:
            _verify_memo[key] = _verify(root, tag, base_ref, released)
        except GitError as e:
            _verify_memo[key] = Verdict("git-error", "-", "-", "-", f"git could not read what the verdict needs: {e}")
    return _verify_memo[key]


def _last_line(err: str) -> str:
    bad = [l for l in err.strip().splitlines() if BAD_RE.search(l)]
    lines = err.strip().splitlines()
    return (bad or lines or ["no output"])[-1]


def _verify(root, tag: str, base_ref: str, released: bool) -> Verdict:
    otype, raw, sig, tagger_email = _tag_info(root, tag)
    tagger = tagger_email or "-"
    if otype != "tag":
        return Verdict("lightweight", "-", "-", "-", f"{tag} is a {otype or 'unknown'} ref, not a tag object")
    if sig == "none":
        return Verdict("unsigned", "-", tagger, "-", "a tag object with no signature block")
    if sig == "pgp":
        p = _git(root, "verify-tag", f"refs/tags/{tag}")
        err = p.stderr or ""
        if p.returncode == 0:
            return Verdict("gpg-good", "-", tagger, "-", "")
        if BAD_RE.search(err) is None and release_gate.UNVERIFIABLE_RE.search(err):
            return Verdict("gpg-unverifiable", "-", tagger, "-", _last_line(err))
        return Verdict("bad", "-", tagger, "-", _last_line(err))
    if not tagger_email:
        return Verdict("bad", "-", "-", "-", "the tag object has no tagger (git for-each-ref reads no tagger email), so "
                                             "no principal can be bound to it")
    keygen = shutil.which("ssh-keygen")
    if not keygen:
        return Verdict("bad", "-", tagger, "-", "ssh-keygen is not on PATH, so the SSH signature cannot be verified")
    a = anchor(root, tag, base_ref)
    if isinstance(a, Refusal):
        return Verdict(a.kind, "-", tagger, "-", a.detail)
    if a is None:
        return Verdict("no-anchor", "-", tagger, "-", "no .github/allowed_signers key at any anchor")
    allowed = _read(root, a.ref, ALLOWED)
    if allowed is None or not _key_lines(allowed):
        return Verdict("no-anchor", "-", tagger, a.ref, f"{ALLOWED} at {a.ref} lists no key")
    revoked = []
    where = [(f"refs/tags/{tag}^{{commit}}", "the tag's tree")] + ([] if released else [(base_ref, f"{base_ref}'s tip")])
    for ref, label in where:
        try:
            text = _read(root, ref, REVOKED)
        except GitError as e:
            return Verdict("revocation-unreadable", "-", tagger, a.ref, f"{REVOKED} at {label} cannot be read: {e}")
        if text is None:
            continue
        lines = _revocation_lines(text, label)
        if isinstance(lines, Refusal):
            return Verdict(lines.kind, "-", tagger, a.ref, lines.detail)
        revoked += [(l, label) for l in lines]
    tmps = [_tmp(allowed)]
    pins = ["-c", f"gpg.ssh.program={keygen}", "-c", f"gpg.ssh.allowedSignersFile={tmps[0]}"]
    try:
        p = _git(root, *pins, "verify-tag", f"refs/tags/{tag}")
        err = p.stderr or ""
        gm = GOOD_RE.search(err)
        if p.returncode == 0 and gm:
            principal = gm.group(1)
            if revoked:
                tmps.append(_tmp("\n".join(l for l, _ in revoked) + "\n"))
                p2 = _git(root, *pins, "-c", f"gpg.ssh.revocationFile={tmps[-1]}", "verify-tag", f"refs/tags/{tag}")
                if p2.returncode != 0:
                    at = " or ".join(sorted({label for _, label in revoked}))
                    return Verdict("revoked", principal, tagger, a.ref, f"the signing key is listed in {REVOKED} at {at}")
            if principal != tagger_email:
                return Verdict("tagger-mismatch", principal, tagger, a.ref,
                               f"the key is listed for {principal}, the tagger is {tagger}")
            return Verdict("ssh-good", principal, tagger, a.ref, "")
        if "No principal matched" in err:
            return Verdict("unlisted", "-", tagger, a.ref, f"the signing key is not listed in {ALLOWED} at {a.ref}")
        return Verdict("bad", "-", tagger, a.ref, _last_line(err))
    finally:
        for t in tmps:
            try:
                os.remove(t)
            except OSError:
                pass


# The verdicts a previous release tag may carry for a new release to proceed at the tag: the ones release.yml's resolve
# step accepted (verify --released exit 0 or 3). An unsigned (annotated) tag passes here; whether its fallback was
# recorded is the next ship PR's check (release_gate.check_previous_tag), as before.
PREVIOUS_OK = ("ssh-good", "gpg-good", "unsigned")


def previous_release_check(root, version: str, base_ref: str) -> tuple:
    """The previous-release preflight release.yml's "Resolve the stack and the previous release" step and
    release-tag.sh both run (one function, so /release --tag never pushes a tag release.yml would refuse; P6 fix wave 1,
    B). The previous release is release_gate.previous_release (the newest earlier version whose notes are on
    `base_ref`). Returns (ok, line): no previous release → (True, "previous: -"); notes on the base but no
    v<prev> tag → (False, "previous-untagged: …") — stricter than the PR-time WARN, a refusal at the tag; a tag whose
    released reading (verify(released=True)) is not ssh-good, gpg-good or unsigned — lightweight, gpg-unverifiable,
    no-anchor or any refusal — → (False, "previous-refused: v<prev> <kind>: …"); else (True, "previous: v<prev> <kind>")."""
    prev = release_gate.previous_release(Path(root), version, base_ref)
    if not prev:
        return True, "previous: -"
    tag = f"v{prev}"
    if _git(root, "rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}").returncode != 0:
        return False, (f"previous-untagged: {tag} has notes on {base_ref} but no tag: tag the earlier release first "
                       f"(/release --tag {prev}), then this one")
    v = verify(root, tag, base_ref, released=True)
    if v.kind in PREVIOUS_OK:
        return True, f"previous: {tag} {v.kind}"
    return False, f"previous-refused: {tag} {v.kind}: {v.detail or 'the previous release tag does not verify as released'}"


def main(argv) -> int:
    ap = argparse.ArgumentParser(prog="signers.py")
    ap.add_argument("--root", default=".")
    ap.add_argument("--base-ref", default="origin/main")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("verify", "anchor"):
        sp = sub.add_parser(name)
        sp.add_argument("--tag", required=True)
        if name == "verify":
            sp.add_argument("--released", action="store_true",
                            help="the released reading: revocation at the tag's tree only (anchors, the PR-time check)")
    sub.add_parser("signing-kind")
    sp = sub.add_parser("previous", help="the previous-release preflight (release.yml and release-tag.sh)")
    sp.add_argument("--version", required=True)
    args = ap.parse_args(argv)
    root = args.root
    if args.cmd == "previous":
        try:
            ok, line = previous_release_check(root, args.version, args.base_ref)
        except UsageError as e:
            print(f"signers: {e}", file=sys.stderr)
            return 2
        except GitError as e:
            print(f"previous-refused: git-error: {e}")
            return 1
        print(line)
        return 0 if ok else 1
    if args.cmd == "signing-kind":
        kind, reason = signing_kind(root)
        print(f"{kind} ({reason})")
        return 0
    try:
        if args.cmd == "anchor":
            _tag_info(root, args.tag)
            a = anchor(root, args.tag, args.base_ref)
            if isinstance(a, Refusal):
                print(f"{a.kind}: {a.detail}")
                return 1
            if a is None:
                print("no anchor")
                return 3
            print(f"anchor: {a.ref} ({a.how})")
            return 0
        v = verify(root, args.tag, args.base_ref, released=args.released)
    except UsageError as e:
        print(f"signers: {e}", file=sys.stderr)
        return 2
    except GitError as e:
        print(f"git-error: {e}")
        return 1
    print(f"kind: {v.kind} principal: {v.principal} tagger: {v.tagger} anchor: {v.anchor}")
    if v.detail:
        print(f"detail: {v.detail}")
    return EXIT.get(v.kind, 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
