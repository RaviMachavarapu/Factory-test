"""scripts/lib/specflow/release_gate.py — the PR-time release gate (REQ-324; R14).

Behind scripts/verify-release.sh. Resolves which version(s) to evaluate (a `ship/<version>` head branch's version, as the
disposition gate resolves it, and each version whose docs/releases/<v>-notes.md differs from the base — committed,
uncommitted, or untracked), then for each:
the three release docs exist; v<version> is not yet a tag (REQ-324: the tag must not yet exist at PR time);
the notes link to this repository's Release (owner/repo from origin's URL; no origin URL, or a local one: a WARN);
the notes' `## Artifacts` table rows equal the reproducible entries of --manifest PATH (a missing PATH FAILs), else — only outside CI —
dist/manifest.json when present, else (unless SPECFLOW_RELEASE_BUILD=0 outside CI, which leaves the shape-only check — in CI
the variable is ignored, since PR-head code in an earlier step could write it into $GITHUB_ENV) of the CI
build of the reproducible subset — the stack's scripts/release-<stack>.sh (the stack read at the base ref) with
RELEASE_PARTS=reproducible on the tree of SPECFLOW_HEAD_SHA (HEAD when unset), R26 — both ways, a mismatch followed by
the expected rows; in CI (SPECFLOW_HEAD_SHA set, or GITHUB_ACTIONS=true) dist/ is never read, so neither a committed
dist/ nor one PR-head code wrote into the checkout can choose the manifest; a tracked dist/ FAILs wherever the gate
runs; every row has the file | sha256 | size shape; known-limitations names every SEC id whose current disposition entry is
accepted or deferred; scripts/check-security-disposition.sh passes; and every [verifiable*] REQ of every live
spec (working tree) is claimed by a plan at the base ref (the union of implements:, or a whole-walked spec)
and carries a `// Proves: REQ-NNN` header in some verification/**/*.dfy (working tree) — in an instance, one of
the template's own specs (frontmatter.INHERITED_SPEC_SLUGS, present at the base ref) is skipped, never a spec
by its own created: date; whether the tree is an instance is judged at the base ref (packinfo.is_instance_at_ref).
With dist/manifest.json read (outside CI), every listed dist/ file hashes to its sha256 and size. The previous release's v<prev>
tag (the latest earlier version whose notes are on the base) must be a tag object whose signature verifies (SSH:
against .github/allowed_signers as of the newest earlier SSH-signed release tag, back to trust on first use,
signers.py; an SSH-signed one on a first-parent commit of the base) or whose known-limitations records the
annotated-tag fallback (at the tag, or on the base as it stood when the tag was created), on an ancestor of the base;
only a missing v<prev> is a WARN (R19). The previous release is found by its notes (which release must carry a proper
tag is what main says shipped), while signers.py's anchor is found by tags alone (only a signature carries trust).

Exit 0 (every evaluated version passed, or nothing to evaluate), 1 (any FAIL), 2 (any ERROR; 2 wins).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blocks  # noqa: E402
import config  # noqa: E402
import disposition_gate  # noqa: E402
import frontmatter  # noqa: E402
import packinfo  # noqa: E402
import release_manifest  # noqa: E402

REL_NOTES_RE = re.compile(r"^docs/releases/(?P<v>[^/]+)-notes\.md$")
PROVES_RE = re.compile(r"//\s*Proves:\s*(REQ-\d{3})")
SEC_WORD_RE = re.compile(r"\bSEC-\d{3}\b")


class GateError(Exception):
    """A parser-level (exit 2) problem: unreadable or unparsable input."""


# --------------------------------------------------------------------------------------------------------- git


def _git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)


def _git_lines(root: Path, *args: str) -> list:
    p = _git(root, *args)
    if p.returncode != 0:
        return []
    return [l for l in p.stdout.splitlines() if l]


def _base_resolves(root: Path, ref: str | None) -> bool:
    if not ref:
        return False
    return _git(root, "rev-parse", "-q", "--verify", ref).returncode == 0


def _tag_exists(root: Path, version: str) -> bool:
    return _git(root, "rev-parse", "-q", "--verify", f"refs/tags/v{version}").returncode == 0


def _git_show_text(root: Path, ref: str, path: str) -> str:
    p = _git(root, "show", f"{ref}:{path}")
    if p.returncode != 0:
        raise GateError(f"cannot read {ref}:{path}: {p.stderr.strip()}")
    return p.stdout


def _changed_files(root: Path, base_ref: str) -> set:
    """Committed since the merge-base with base_ref, uncommitted and untracked; --no-renames lists a moved file
    at its old path as well as its new one (disposition_gate.py's reading)."""
    names = set()
    committed = _git(root, "diff", "--no-renames", "--name-only", f"{base_ref}...HEAD")
    if committed.returncode != 0:  # no merge-base (unrelated histories): the plain two-tree diff
        committed = _git(root, "diff", "--no-renames", "--name-only", base_ref, "HEAD")
    names |= {l for l in committed.stdout.splitlines() if l}
    names |= set(_git_lines(root, "diff", "--no-renames", "--name-only", "HEAD"))
    names |= set(_git_lines(root, "ls-files", "--others", "--exclude-standard"))
    return names


# ---------------------------------------------------------------------------------------------- version resolution


def resolve_versions(root: Path, version_arg: str | None, base_ref: str | None):
    """Returns (versions: list[str], skip_reason: str | None). A `ship/<version>` head branch always evaluates that
    version (disposition_gate.ship_branch_version, R11), so a ship PR that never adds its notes FAILs "three docs
    exist" rather than SKIPping; each version whose notes differ from the base is evaluated too."""
    if version_arg:
        return [version_arg], None
    versions = set()
    ship = disposition_gate.ship_branch_version(root)
    if ship:
        versions.add(ship)
    if not _base_resolves(root, base_ref):
        if versions:
            return sorted(versions, key=blocks.version_key), None
        return [], (f"no base ref {base_ref}" if base_ref else "no base ref")
    changed = _changed_files(root, base_ref)
    for f in changed:
        m = REL_NOTES_RE.match(f)
        if m:
            versions.add(m.group("v"))
    if not versions:
        return [], f"no release notes differ from {base_ref}"
    return sorted(versions, key=blocks.version_key), None


# --------------------------------------------------------------------------------------------------- REQ claims


def _plan_frontmatters_at_ref(root: Path, ref: str) -> list:
    paths = _git_lines(root, "ls-tree", "-r", "--name-only", ref, "--", "docs/plans")
    out = []
    for p in sorted(pp for pp in paths if pp.endswith(".md")):
        out.append(frontmatter.parse_text(_git_show_text(root, ref, p)))
    return out


def _claims_at_ref(root: Path, ref: str):
    """Returns (implemented: set[str], whole_specs: set[str]) — the base-ref twin of frontmatter.claims(),
    read with git ls-tree/git show instead of the filesystem (R14: plans are read at the base ref)."""
    implemented: set = set()
    whole_specs: set = set()
    for fm in _plan_frontmatters_at_ref(root, ref):
        spec = fm.get("spec", "")
        if "implements" in fm:
            for item in frontmatter.parse_list(fm["implements"]):
                if re.match(r"^REQ-\d{3}$", item):
                    implemented.add(item)
        elif spec:
            whole_specs.add(spec)
    return implemented, whole_specs


def _has_proof(root: Path, req: str) -> bool:
    for p in root.glob("verification/**/*.dfy"):
        try:
            head = p.read_text().splitlines()[:5]
        except OSError:
            continue
        for line in head:
            m = PROVES_RE.search(line)
            if m and m.group(1) == req:
                return True
    return False


def check_req_claims(root: Path, base_ref: str | None) -> tuple:
    """Returns (fail_lines, note_lines)."""
    fails: list = []
    notes: list = []
    if not _base_resolves(root, base_ref):
        notes.append(f"no base ref {base_ref}: REQ claim check skipped" if base_ref else "no base ref: REQ claim check skipped")
        return fails, notes
    implemented, whole_specs = _claims_at_ref(root, base_ref)
    # Instance-ness is judged at the base (PR #42 code mode): a template-source PR that adds .stack or
    # .specflow.yml does not skip the template's own specs.
    is_instance = packinfo.is_instance_at_ref(root, base_ref)
    mismatch = packinfo.instance_mismatch_note(root, base_ref)
    if mismatch:
        notes.append(mismatch[len("note: "):])
    for slug, (fm, text) in sorted(frontmatter.live_specs(str(root)).items()):
        if is_instance and frontmatter.inherited_spec(str(root), slug, base_ref):
            notes.append(f"{slug} is inherited from the template; not checked in an instance")
            continue
        for req in sorted(frontmatter.tagged_reqs(text)):
            claimed = slug in whole_specs or req in implemented
            if not claimed:
                fails.append(
                    f"{req} ([verifiable*], {slug}) is claimed by no merged plan's implements: (base {base_ref})"
                )
                continue
            if not _has_proof(root, req):
                fails.append(f"{req} claimed but no // Proves: {req} header found in verification/**/*.dfy")
    return fails, notes


# ------------------------------------------------------------------------------------------- Artifacts table


def _parse_artifacts_rows(text: str):
    """Returns (rows: list[(file, sha256, size)], bad: list[(lineno, raw)]) over the `## Artifacts` section,
    or None when the section is absent."""
    m = re.search(r"^## Artifacts\n(.*?)(?=\n## |\Z)", text, re.S | re.M)
    if m is None:
        return None
    rows: list = []
    bad: list = []
    for i, line in enumerate(m.group(1).splitlines(), start=1):
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if not cells or cells[0].lower() == "filename":
            continue
        if all(set(c) <= set("-: ") for c in cells):
            continue
        if len(cells) != 3:
            bad.append((i, line))
            continue
        fname, sha, size = (c.strip("`") for c in cells)
        if not fname or not re.fullmatch(r"[0-9a-f]{64}", sha) or not re.fullmatch(r"\d+", size):
            bad.append((i, line))
            continue
        rows.append((fname, sha, int(size)))
    return rows, bad


def _check_dist_files(root: Path, manifest_rows: list) -> list:
    """Every manifest entry's dist/<filename> exists and hashes to its sha256 and size (the RELEASE exit gate's
    "dist/manifest.json checksums verify")."""
    import hashlib

    fails: list = []
    dist = (root / "dist").resolve()
    for fname, sha, size in manifest_rows:
        p = (root / "dist" / fname).resolve()
        if "/" in fname or "\\" in fname or fname in ("", ".", "..") or p.parent != dist:
            fails.append(f"dist/manifest.json entry {fname!r} names a path outside dist/")
            continue
        if not p.is_file():
            fails.append(f"dist/{fname} is listed in dist/manifest.json but missing")
            continue
        data = p.read_bytes()
        got = hashlib.sha256(data).hexdigest()
        if got != sha:
            fails.append(f"dist/{fname} sha256 {got} does not match dist/manifest.json's {sha}")
        if len(data) != size:
            fails.append(f"dist/{fname} is {len(data)} bytes, dist/manifest.json says {size}")
    return fails


def _ci() -> bool:
    """In CI the gates step exports SPECFLOW_HEAD_SHA (ci.yml) and the runner sets GITHUB_ACTIONS: dist/ is never read
    there (Build 2 final review: a forced or PR-written dist/ would let the author choose the manifest)."""
    return bool(os.environ.get("SPECFLOW_HEAD_SHA")) or os.environ.get("GITHUB_ACTIONS") == "true"


def _tracked_dist(root: Path) -> list:
    """dist/ paths in the index or in the tree of SPECFLOW_HEAD_SHA (HEAD when unset): dist/ is gitignored and never
    committed, so any is a FAIL."""
    commit = os.environ.get("SPECFLOW_HEAD_SHA") or "HEAD"
    names = set(_git_lines(root, "ls-files", "--", "dist"))
    names |= set(_git_lines(root, "ls-tree", "-r", "--name-only", commit, "dist"))
    return sorted(names)


def _build_manifest(root: Path, version: str, base_ref: str | None = None):
    """The CI path (R26): run the governing stack's hook with RELEASE_PARTS=reproducible on the tree of
    SPECFLOW_HEAD_SHA (HEAD when unset; on a PR the checkout's HEAD is GitHub's merge ref, R18 (ii)) into a temporary
    directory. The stack is read at the base ref (packinfo.stack with ref; R2), so a branch that adds or deletes
    .specflow.yml or .stack cannot swap the hook; outside CI an unresolvable base falls back to the checkout. Returns
    (manifest dict | None, source label, fail line | None). Never reads the working tree's files for the build: the hook
    exports RELEASE_COMMIT's tree itself (the hook script itself is the checkout's, PR-head code: a gate-code residual)."""
    import tempfile

    commit = os.environ.get("SPECFLOW_HEAD_SHA") or "HEAD"
    label = f"the CI build of {commit[:12]}"
    if _base_resolves(root, base_ref):
        ref = base_ref
    elif _ci():
        return None, label, f"cannot resolve the base {base_ref} to read the release stack at it"
    else:
        ref = None
    try:
        stack = packinfo.stack(root, ref)
    except packinfo.PackError as e:
        return None, label, f"cannot resolve the release stack to build the Artifacts rows: {e}"
    hook = root / "scripts" / f"release-{stack}.sh"
    if not hook.is_file():
        return None, label, f"scripts/release-{stack}.sh is missing: cannot build the reproducible subset"
    with tempfile.TemporaryDirectory() as tmp:
        env = {k: v for k, v in os.environ.items() if k != "SOURCE_DATE_EPOCH"}
        env.update({"VERSION": version, "DIST_DIR": tmp, "RELEASE_PARTS": "reproducible", "RELEASE_COMMIT": commit})
        p = subprocess.run(["bash", str(hook)], cwd=str(root), env=env, capture_output=True, text=True)
        if p.returncode != 0:
            last = next((l for l in reversed((p.stdout + "\n" + p.stderr).splitlines()) if l.strip()), "")
            return None, label, f"scripts/release-{stack}.sh failed (exit {p.returncode}) building the reproducible subset: {last}"
        try:
            manifest = json.loads((Path(tmp) / "manifest.json").read_text())
        except (OSError, json.JSONDecodeError) as e:
            return None, label, f"scripts/release-{stack}.sh wrote no readable manifest.json: {e}"
    return manifest, label, None


def _compare_rows(manifest: dict, rows: list, label: str, fails: list, extra: list) -> bool:
    """The notes' rows equal the manifest's reproducible entries, both ways (a non-reproducible entry is never
    required and, when transcribed, not a FAIL). On a mismatch the expected rows follow the FAIL lines."""
    entries = manifest.get("artifacts", [])
    required = {(e["filename"], e["sha256"], int(e["size"])) for e in entries if e.get("reproducible", True)}
    allowed = {(e["filename"], e["sha256"], int(e["size"])) for e in entries}
    row_set = set(rows)
    for r in sorted(required - row_set):
        fails.append(f"{label} entry {r[0]} not transcribed into the notes' Artifacts table")
    for r in sorted(row_set - allowed):
        fails.append(f"the notes' Artifacts row {r[0]} is not in {label}")
    if required != (row_set & required) or row_set - allowed:
        extra.append(f"expected Artifacts rows (from {label}):")
        extra.extend(l for l in release_manifest.rows_markdown(sorted(required)).splitlines())
        return False
    return True


def check_artifacts(root: Path, version: str, notes_text: str, manifest_arg: str | None = None,
                    extra: list | None = None, base_ref: str | None = None, at_tag: bool = False) -> list:
    """FAIL lines for the notes' Artifacts table. The rows are compared with, in order: --manifest PATH; else, outside
    CI only, dist/manifest.json (whose dist/ files must also hash; under /release, CI's downloaded artifact); else the
    reproducible subset built from SPECFLOW_HEAD_SHA's tree (R26), unless SPECFLOW_RELEASE_BUILD=0 outside CI, which
    leaves only the row shape checked. SPECFLOW_RELEASE_BUILD is a local-only switch: in CI it is ignored (Build 2 fix
    wave 2: PR-head code in an earlier gates step could write it into $GITHUB_ENV and turn the comparison into the shape
    check). In CI dist/ is never read, and a tracked dist/ FAILs everywhere. `extra` collects the unprefixed lines that
    follow the FAILs (the expected rows). `at_tag` (release.yml's `verify`, P6 R30): never builds the subset and never
    reads dist/ — the comparison with the build is `build-source`'s (`--artifacts-only`); only the row shape, a tracked
    dist/ and, when --manifest is given, that manifest are checked."""
    extra = extra if extra is not None else []
    fails: list = []
    parsed = _parse_artifacts_rows(notes_text)
    if parsed is None or (not parsed[0] and not parsed[1]):
        fails.append(f"docs/releases/{version}-notes.md has no ## Artifacts table with a data row")
        return fails
    rows, bad = parsed
    for i, line in bad:
        fails.append(f"docs/releases/{version}-notes.md Artifacts row {i} does not have the file | sha256 | size shape ({line})")
    tracked = _tracked_dist(root)
    if tracked:
        shown = ", ".join(tracked[:3]) + (", …" if len(tracked) > 3 else "")
        fails.append(f"dist/ is tracked ({shown}): dist/ is gitignored and never committed — the notes are compared "
                     f"with a CI build of the reproducible subset, never a committed manifest (P6 R26)")
    if manifest_arg:
        manifest_path = Path(manifest_arg)
        if not manifest_path.is_file():
            # an explicit --manifest is the record asked for: never a fall-through to the build or the shape check
            fails.append(f"--manifest {manifest_arg} does not exist (or is not a file): the Artifacts rows were not compared")
            return fails
    elif at_tag:
        manifest_path = None  # the replay at the tag never reads dist/ and never builds
    elif _ci():
        manifest_path = None  # in CI dist/ is never read: always the build below
    else:
        manifest_path = root / "dist/manifest.json"
    if manifest_path is not None and manifest_path.is_file():
        label = manifest_arg or "dist/manifest.json"
        try:
            manifest = json.loads(manifest_path.read_text())
        except json.JSONDecodeError as e:
            return [f"{label}: {e}"]
        manifest_rows: list = []
        key_missing = False
        for i, e in enumerate(manifest.get("artifacts", []), start=1):
            for key in ("filename", "sha256", "size"):
                if key not in e:
                    fails.append(f"{label} entry {i} has no {key}")
                    key_missing = True
                    break
            else:
                manifest_rows.append((e["filename"], e["sha256"], int(e["size"])))
        if not manifest_arg:
            fails.extend(_check_dist_files(root, manifest_rows))
        if not key_missing:
            _compare_rows(manifest, rows, label, fails, extra)
    elif at_tag:
        pass
    elif _ci() or os.environ.get("SPECFLOW_RELEASE_BUILD") != "0":
        manifest, label, err = _build_manifest(root, version, base_ref)
        if err:
            fails.append(err)
        else:
            _compare_rows(manifest, rows, label, fails, extra)
    return fails


def origin_repo(root: Path):
    """(owner/repo | None, origin URL | None) from `git config --get remote.origin.url` as configured (never the
    insteadOf-rewritten URL): the path part only, so https://host/o/r(.git), ssh://user@host/o/r and the scp-like
    user@host-alias:o/r.git all give o/r whatever the host (a github.com-<alias> SSH host alias included). A local
    path or file:// origin, or none, gives None."""
    p = _git(root, "config", "--get", "remote.origin.url")
    url = p.stdout.strip() if p.returncode == 0 else ""
    if not url:
        return None, None
    m = re.match(r"^([a-zA-Z][a-zA-Z0-9+.-]*)://[^/]+/(.+)$", url)
    if m:
        path = None if m.group(1).lower() == "file" else m.group(2)
    else:
        m = re.match(r"^(?:[^@/:\s]+@)?[^/:\s]+:(?!/)(.+)$", url)
        path = m.group(1) if m else None
    if not path:
        return None, url
    parts = [s for s in re.sub(r"\.git/?$", "", path.rstrip("/")).split("/") if s]
    if len(parts) < 2:
        return None, url
    return f"{parts[-2]}/{parts[-1]}", url


def check_release_link(root: Path, version: str, notes_text: str) -> tuple:
    """REQ-384: the notes link to the Release of THIS repository (docs/releases/ is in no archive, so the link is no
    fixpoint); release.yml creates it (REQ-350). The repository is origin's owner/repo
    (`origin_repo`); with no origin URL, or a local one, the repository is not checked and a WARN says so
    (local-only). Returns (warns, fails)."""
    repo, url = origin_repo(root)
    links = re.findall(r"^Release: https://github\.com/([^/\s]+/[^/\s]+)/releases/tag/v" + re.escape(version) + r"$",
                       notes_text, re.M)
    if not links:
        want = f"https://github.com/{repo}" if repo else "https://github.com/<owner>/<repo>"
        return [], [f"docs/releases/{version}-notes.md has no line 'Release: {want}/releases/tag/v{version}' "
                    f"(the link to this repository's Release)"]
    if repo is None:
        why = f"origin {url} is not a remote repository URL" if url else "no origin remote URL"
        return [f"WARN verify-release {version}: {why}: the notes' Release link's repository is not checked (local-only)"], []
    if any(l.lower() == repo.lower() for l in links):
        return [], []
    return [], [f"docs/releases/{version}-notes.md's Release link names {links[0]}, not this repository: expected the prefix "
                f"https://github.com/{repo}/releases/tag/v{version} (origin {url})"]


# --------------------------------------------------------------------------------------------------- known-limitations


def check_known_limitations(root: Path, version: str) -> list:
    fails: list = []
    disp_path = root / f"docs/security/{version}-disposition.md"
    if not disp_path.is_file():
        return fails  # check-security-disposition.sh reports "run /security-review"
    try:
        disp = blocks.parse_disposition(disp_path.read_text(), disp_path.name, version=version, require_header=True)
    except blocks.BlockError:
        return fails  # surfaced by check-security-disposition.sh
    kl_path = root / f"docs/releases/{version}-known-limitations.md"
    kl_text = kl_path.read_text() if kl_path.is_file() else ""
    named = set(SEC_WORD_RE.findall(kl_text))  # a whole-word match: SEC-0010 or XSEC-001 does not name SEC-001
    for e in disp.entries:
        if e.status in ("accepted", "deferred") and e.id not in named:
            fails.append(f"{e.id} ({e.status}) not named in docs/releases/{version}-known-limitations.md")
    return fails


# --------------------------------------------------------------------------------------------------- disposition gate


def run_disposition_gate(root: Path, version: str, base_ref: str | None, at_tag: bool = False) -> tuple:
    """Returns (lines: list[str], code: int). `at_tag` replays the gate for the tagged version itself (REQ-350)."""
    cmd = ["bash", str(root / "scripts/check-security-disposition.sh"), "--version", version, "--root", str(root)]
    if base_ref:
        cmd += ["--base", base_ref]
    if at_tag:
        cmd.append("--at-tag")
    p = subprocess.run(cmd, capture_output=True, text=True)
    lines = [l for l in (p.stdout + p.stderr).splitlines() if l]
    return lines, p.returncode


# ------------------------------------------------------------------------------------------- previous release's tag


# The exact line prefix `/release` (release.md step 5) writes. A line that merely names "annotated" and "fallback"
# ("no annotated-tag fallback was needed") records nothing.
FALLBACK_RE = re.compile(r"^- Annotated-tag fallback:", re.M)
# The inherited demo release predates that line; its known-limitations recorded the fallback in prose. It alone, by its
# known version (the by-known-slug pattern of frontmatter.INHERITED_SPEC_SLUGS), is read with the legacy rule: a line
# naming both "annotated" and "fallback" that is not negated (no/not/never/without/none within three words before
# either word).
LEGACY_FALLBACK_VERSIONS = ("0.0.1-demo",)
_LEGACY_BOTH_RE = re.compile(r"(?i)^(?=.*\bannotated\b)(?=.*\bfallback\b).*$", re.M)
_LEGACY_NEGATED_RE = re.compile(r"(?i)\b(?:no|not|never|without|none)\b(?:\W+\w+){0,2}?\W+(?:annotated|fallback)\b")


def _records_fallback(text: str, version: str) -> bool:
    if FALLBACK_RE.search(text):
        return True
    if version in LEGACY_FALLBACK_VERSIONS:
        return any(not _LEGACY_NEGATED_RE.search(line) for line in _LEGACY_BOTH_RE.findall(text))
    return False


def _tagger_time(root: Path, version: str):
    """The tagger time of refs/tags/v<version> as git parses the tag header (for-each-ref %(taggerdate:unix)), never a
    regular expression over the raw object; None when there is no tagger."""
    ref = f"refs/tags/v{version}"
    for line in _git_lines(root, "for-each-ref", "--format=%(refname)%00%(taggerdate:unix)", ref):
        name, _, when = line.partition("\0")
        if name == ref and when.strip().isdigit() and int(when) > 0:
            return int(when)
    return None


def _fallback_recorded(root: Path, base_ref: str, version: str) -> bool:
    """That version's known-limitations records the annotated-tag fallback (a line starting `- Annotated-tag
    fallback:`, the line `/release` writes; for the inherited demo release alone, its legacy prose). It is read AT THE
    TAG first; when the tag's tree does not record it, the base is read only as it stood when the tag was created (the
    newest commit on the base touching the file whose committer time is not after the tagger time): the /release
    stop-and-follow-up-docs-PR path, whose docs PR merges before the tag is created. A line added after the tag was
    created records nothing — a released doc is never edited after its tag (release.md)."""
    path = f"docs/releases/{version}-known-limitations.md"
    at_tag = _git(root, "show", f"refs/tags/v{version}:{path}")
    if at_tag.returncode == 0 and _records_fallback(at_tag.stdout, version):
        return True
    tagged_at = _tagger_time(root, version)
    if tagged_at is None:
        return False
    best = None
    for line in _git_lines(root, "log", "--format=%H %ct", base_ref, "--", path):
        sha, ct = line.split()
        if int(ct) <= tagged_at and (best is None or int(ct) > best[1]):
            best = (sha, int(ct))
    if best is None:
        return False
    p = _git(root, "show", f"{best[0]}:{path}")
    return p.returncode == 0 and _records_fallback(p.stdout, version)


# gpg/ssh could not check the signature on this machine: no signer key here, or no gpg to run at all. Anything else
# that fails `git tag -v` (a BAD signature, an unrecognised error) fails closed.
UNVERIFIABLE_RE = re.compile(
    r"No public key|Can't check signature|No principal matched|allowedSignersFile needs to be configured"
    r"|cannot (?:exec|run) |gpg: (?:command )?not found|no gpg", re.I)


def earlier_releases(root: Path, version: str, base_ref: str | None) -> list:
    """Every version earlier than `version` whose docs/releases/<v>-notes.md is on `base_ref`, newest first."""
    if not _base_resolves(root, base_ref):
        return []
    before = blocks.version_key(version)
    prev = []
    for path in _git_lines(root, "ls-tree", "-r", "--name-only", base_ref, "--", "docs/releases"):
        m = REL_NOTES_RE.match(path)
        if m and re.match(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$", m.group("v")) \
                and blocks.version_key(m.group("v")) < before:
            prev.append(m.group("v"))
    return sorted(set(prev), key=blocks.version_key, reverse=True)


def previous_release(root: Path, version: str, base_ref: str | None) -> str | None:
    """The latest version earlier than `version` whose docs/releases/<v>-notes.md is on `base_ref`, else None."""
    prev = earlier_releases(root, version, base_ref)
    return prev[0] if prev else None


def check_previous_tag(root: Path, version: str, base_ref: str | None) -> tuple:
    """Returns (warn_lines, fail_lines). The previous release is the latest earlier version whose notes are on the
    base (previous_release). Its `v<prev>` tag, when it exists, must be a tag object (a lightweight tag FAILs) on an
    ancestor of the base (the merge commit, or an earlier one on the base), and an SSH-signed one must sit on a
    first-parent commit of the base — `anchor-off-main` otherwise, the rule the tag-time anchor walk applies, so PR time
    and tag time agree (P6 R3). signers.verify decides the rest:
      - unsigned (annotated, no signature block): PASS only when that version's known-limitations records the
        annotated-tag fallback at the tag, or on the base as it stood when the tag was created, else FAIL
        (art-release-readiness; _fallback_recorded);
      - ssh-good, gpg-good: PASS (an SSH signature is checked against .github/allowed_signers as of the previous
        release's tag, back to trust on first use, P6 R3);
      - bad, unlisted, tagger-mismatch, revoked, revocation-unreadable, revocation-malformed, anchor-off-main,
        anchor-unverified, shallow, git-error: FAIL
        naming the kind (the released reading: revocation at the tag's own tree, so a released tag's verdict is fixed
        once it exists; the tag-time reading in release-tag.sh and release.yml also reads it on the base's tip);
      - gpg-unverifiable (a GPG signature this machine cannot check) and no-anchor (an SSH signature with no anchor
        key): a WARN, never a FAIL; release.yml refuses them at the tag (signers.py previous) and verifies SSH signatures against .github/allowed_signers there
        (P6 R27).
    A MISSING tag is a WARN: `/release` tags after the ship PR merges (R19), so the next ship PR is where a forgotten
    tag surfaces."""
    import signers  # lazy: signers imports this module for previous_release / UNVERIFIABLE_RE
    if not _base_resolves(root, base_ref):
        return [], []
    latest = previous_release(root, version, base_ref)
    if latest is None:
        return [], []
    tag = f"v{latest}"
    if not _tag_exists(root, latest):
        return [f"WARN verify-release {version}: docs/releases/{latest}-notes.md is on {base_ref} but {tag} is not "
                f"tagged — tag and sign it (/release, after its merge) before this release ships (R19)"], []
    warns, fails = [], []
    v = signers.verify(root, tag, base_ref, released=True)
    if v.kind == "lightweight":
        fails.append(f"previous release tag {tag} is lightweight ({v.detail}) — "
                     f"re-create it signed (git tag -s) or annotated with the fallback recorded")
    elif v.kind == "unsigned":
        if not _fallback_recorded(root, base_ref, latest):
            fails.append(f"previous release tag {tag}: it is annotated but unsigned, and "
                         f"docs/releases/{latest}-known-limitations.md records no annotated-tag fallback at the "
                         f"tag or on {base_ref} before the tag was created — re-tag it signed, or record the "
                         f"fallback (a follow-up docs PR) and re-create the annotated tag after that merge")
    elif v.kind in ("ssh-good", "gpg-good"):
        pass
    elif v.kind in ("gpg-unverifiable", "no-anchor"):
        warns.append(f"WARN verify-release {version}: previous release tag {tag} is signed but cannot be checked here "
                     f"({v.kind}); release.yml refuses it at the tag, where it verifies SSH signatures against .github/allowed_signers "
                     f"(P6 R27)")
    else:
        fails.append(f"previous release tag {tag}: its signature does not verify ({v.kind}: {v.detail}) — a BAD, "
                     f"unlisted or otherwise unverifiable signature is never a fallback; re-tag it signed")
    ssh_signed = v.kind != "lightweight" and \
        bool(signers.SSH_BLOCK_RE.search(_git(root, "cat-file", "tag", f"refs/tags/{tag}").stdout or ""))
    if ssh_signed:
        commit = _git(root, "rev-parse", f"refs/tags/{tag}^{{commit}}").stdout.strip()
        if commit not in set(_git_lines(root, "rev-list", "--first-parent", base_ref)):
            fails.append(f"previous release tag {tag}: anchor-off-main — it is SSH-signed but its commit is not a "
                         f"first-parent commit of {base_ref} (a tag on a PR's commit); the tag-time anchor walk "
                         f"refuses it too (P6 R3)")
    if _git(root, "merge-base", "--is-ancestor", f"refs/tags/{tag}", base_ref).returncode != 0:
        fails.append(f"previous release tag {tag} is not on {base_ref} (its commit is not an ancestor of the base) — "
                     f"it must tag {latest}'s merge commit")
    return warns, fails


# ------------------------------------------------------------------------------------------ app-stack release rules

# The stacks that ship a macOS bundle (P6 R22, R35). The governing pack's stack, never the checkout's guess: read at the
# base ref as instance-ness is. Python and the template have no bundle and are asked for neither the checklist nor tester
# instructions.
APP_STACKS = ("tauri", "flutter")
CHECKLIST_HEADING = "## macOS distribution checklist"


def check_app_stack(root: Path, version: str, notes_text: str, base_ref: str | None) -> tuple:
    """Returns (warn_lines, fail_lines). An app-stack ship PR's notes carry `## macOS distribution checklist` (release.yml
    cannot edit a tagged file, so /release appends store-checklist.md to the notes; REQ-352, R22) and, with
    `signing: none` (config.py at the head; R23), docs/releases/<v>-tester-instructions.md exists (REQ-386). `base_ref` is
    the ref the stack is read at: the PR's base at PR time; under --at-tag the tag itself (refs/tags/v<v>^{commit}), as
    release.yml's job selection reads it (fix wave 1, G)."""
    ref = base_ref if _base_resolves(root, base_ref) else None
    try:
        stack = packinfo.stack(root, ref)
    except packinfo.PackError as e:
        if "template-pack.yml in the template source" in str(e):  # neither an instance nor the template source: no pack to key on
            return [f"note: verify-release {version}: no governing pack to read the release stack from ({e}): "
                    f"the app-stack release rules were not checked"], []
        return [], [f"cannot resolve the release stack to apply the app-stack release rules: {e}"]
    if stack not in APP_STACKS:
        return [], []
    fails: list = []
    if not re.search(r"^" + re.escape(CHECKLIST_HEADING) + r"\s*$", notes_text, re.M):
        fails.append(f"docs/releases/{version}-notes.md has no '{CHECKLIST_HEADING}' section: {stack} is an app stack, "
                     f"so /release appends docs/releases/store-checklist.md under it (release.yml cannot edit a tagged file; R22)")
    try:
        signing = config.load(root).get("signing") or config.DEFAULTS["signing"]
    except config.ConfigError as e:
        return [], fails + [f"cannot read signing from .specflow.yml: {e}"]
    if signing == "none" and not (root / f"docs/releases/{version}-tester-instructions.md").is_file():
        fails.append(f"docs/releases/{version}-tester-instructions.md is missing: {stack} ships an unsigned bundle "
                     f"(signing: none), so /release writes the tester instructions from docs/releases/tester-instructions.md (R23)")
    return [], fails


# ------------------------------------------------------------------------------------------------- at the tag


def check_tag_at_head(root: Path, version: str, base_ref: str | None) -> list:
    """release.yml's replay (--at-tag; REQ-350, P6 R27, R30): v<version> exists, is a tag object, peels to HEAD, and
    verifies — SSH by an anchored key (signers.verify), or annotated with the fallback recorded by the rule the PR-time
    previous-tag check applies (_fallback_recorded: at the tag, or on the base as it stood when the tag was created, so
    the release.md stop path's follow-up docs PR counts; F6, F18). Any other kind — a GPG signature included — FAILs."""
    import signers  # lazy: signers imports this module
    tag = f"v{version}"
    if not _tag_exists(root, version):
        return [f"{tag} does not exist: --at-tag replays the release checks only at a tag"]
    v = signers.verify(root, tag, base_ref or "origin/main", released=False)
    if v.kind == "lightweight":
        return [f"{tag} is lightweight ({v.detail}): a release tag is a tag object, signed or annotated with the fallback recorded"]
    peeled = _git(root, "rev-parse", f"refs/tags/{tag}^{{commit}}").stdout.strip()
    head = _git(root, "rev-parse", "HEAD").stdout.strip()
    fails: list = []
    if not peeled or peeled != head:
        fails.append(f"{tag} does not peel to HEAD ({peeled[:12] or 'unresolved'} vs {head[:12]}): the replay runs on the tagged commit")
    if v.kind == "ssh-good":
        pass
    elif v.kind == "unsigned":
        if not _fallback_recorded(root, base_ref or "origin/main", version):
            fails.append(f"{tag} is annotated but unsigned, and docs/releases/{version}-known-limitations.md records no "
                         f"annotated-tag fallback at the tag or on {base_ref} before the tag was created")
    elif v.kind == "gpg-good" or v.kind == "gpg-unverifiable":
        fails.append(f"{tag} carries a GPG signature ({v.kind}): the replay at the tag (release.yml, P6 R27) takes SSH signatures only; re-tag it with an SSH key")
    else:
        fails.append(f"{tag}: its signature does not verify ({v.kind}: {v.detail})")
    return fails


# --------------------------------------------------------------------------------------------------- evaluation


def evaluate_version(root: Path, version: str, base_ref: str | None, manifest_arg: str | None = None,
                     at_tag: bool = False) -> tuple:
    """Returns (lines: list[str], code: int) — 0 PASS, 1 FAIL, 2 ERROR. `at_tag` is release.yml's replay (R30): the tag
    must exist, verify and peel to HEAD, and the checkout must be the tag's tree — `git status --porcelain` lists
    nothing (disposition_gate.tag_tree_mismatch), because the documents are read from the checkout, never through `git
    show` (P6 fix wave 1, G); the app-stack rules read the stack at the tag's tree; the subset is never built; the gates
    are never re-run (verify-release.sh)."""
    lines: list = []
    fails: list = []
    errors: list = []
    extra: list = []  # unprefixed lines after the FAILs: the expected Artifacts rows

    for suffix in ("notes", "migration", "known-limitations"):
        p = root / f"docs/releases/{version}-{suffix}.md"
        if not p.is_file():
            fails.append(f"docs/releases/{version}-{suffix}.md missing")

    tree_why = None
    if at_tag:
        tag_fails = check_tag_at_head(root, version, base_ref)
        if not _tag_exists(root, version):  # nothing to replay: the one FAIL, not the checks that read the tag
            return [f"FAIL verify-release {version}: {f}" for f in tag_fails], 1
        fails.extend(tag_fails)
        # the documents below are read from the checkout: it must be the tag's tree (HEAD is checked above)
        tree_why = disposition_gate.tag_tree_mismatch(root, version)
        if tree_why and "working tree" in tree_why:
            fails.append(tree_why)
    elif _tag_exists(root, version):
        fails.append(f"tag v{version} already exists (must not exist yet)")

    notes_path = root / f"docs/releases/{version}-notes.md"
    if notes_path.is_file():
        link_warns, link_fails = check_release_link(root, version, notes_path.read_text())
        lines.extend(link_warns)
        fails.extend(link_fails)
        fails.extend(check_artifacts(root, version, notes_path.read_text(), manifest_arg, extra, base_ref, at_tag))
        # at the tag, the stack is read at the TAG's tree (packinfo at refs/tags/v<v>), as release.yml's job selection
        # reads it — never the parent's or main's tip
        app_ref = f"refs/tags/v{version}^{{commit}}" if at_tag else base_ref
        app_warns, app_fails = check_app_stack(root, version, notes_path.read_text(), app_ref)
        lines.extend(app_warns)
        fails.extend(app_fails)

    fails.extend(check_known_limitations(root, version))
    prev_warns, prev_fails = check_previous_tag(root, version, base_ref)
    lines.extend(prev_warns)
    fails.extend(prev_fails)

    if tree_why:  # not the tag's tree: the replay's own FAIL above stands; the disposition replay would refuse (exit 2)
        disp_lines, disp_code = [f"note: verify-release {version}: the security-disposition replay is skipped: {tree_why}"], 1
    else:
        disp_lines, disp_code = run_disposition_gate(root, version, base_ref, at_tag)
    lines.extend(disp_lines)
    if disp_code == 2:
        errors.append("check-security-disposition.sh exited 2")
    elif disp_code == 1:
        fails.append("check-security-disposition.sh failed")

    req_fails, req_notes = check_req_claims(root, base_ref)
    lines.extend(f"note: {n}" for n in req_notes)
    fails.extend(req_fails)

    out = lines
    if errors:
        out = out + [f"ERROR verify-release {version}: {e}" for e in errors] + [f"FAIL verify-release {version}: {f}" for f in fails]
        return out + extra, 2
    if fails:
        out = out + [f"FAIL verify-release {version}: {f}" for f in fails] + extra
        return out, 1
    if at_tag:
        return out + [f"PASS verify-release {version}: v{version} is a verified tag on HEAD, 3 release docs, Artifacts table "
                      f"shape checked, known-limitations complete, security-disposition replayed at the tag, REQ claims "
                      f"and proofs checked, previous release's tag checked (the gates and the build are not re-run)"], 0
    out = out + [f"PASS verify-release {version}: 3 release docs, tag not yet created, Artifacts table checked, "
                 f"known-limitations complete, security-disposition passed, REQ claims and proofs checked, previous release's tag checked"]
    return out, 0


def artifacts_only(root: Path, version: str, manifest_arg: str, base_ref: str | None) -> int:
    """release.yml's `build-source` (F19, F28): only the notes' Artifacts rows against the manifest the job just built —
    no tag, signature, previous-tag, history or disposition check, so a depth-1 checkout with no tag object suffices."""
    notes_path = root / f"docs/releases/{version}-notes.md"
    if not notes_path.is_file():
        print(f"FAIL verify-release {version}: docs/releases/{version}-notes.md missing")
        return 1
    extra: list = []
    fails = check_artifacts(root, version, notes_path.read_text(), manifest_arg, extra, base_ref)
    for f in fails:
        print(f"FAIL verify-release {version}: {f}")
    for line in extra:
        print(line)
    if fails:
        return 1
    print(f"PASS verify-release {version}: the notes' Artifacts rows equal {manifest_arg} (artifacts only)")
    return 0


# --------------------------------------------------------------------------------------------------------- main


def main(argv):
    p = argparse.ArgumentParser(prog="release_gate.py")
    p.add_argument("version_pos", nargs="?", default=None, metavar="VERSION")
    p.add_argument("--version")
    p.add_argument("--root", default=".")
    p.add_argument("--base")
    p.add_argument("--manifest")
    p.add_argument("--at-tag", action="store_true",
                   help="release.yml's replay: v<version> must be a verified tag on HEAD; never builds, never runs the gates")
    p.add_argument("--artifacts-only", action="store_true",
                   help="only the notes' Artifacts rows against --manifest (release.yml's build-source)")
    args = p.parse_args(argv)

    root = Path(args.root)
    base_ref = args.base or os.environ.get("SPECFLOW_BASE_REF") or disposition_gate.default_base_ref(root)
    version_arg = args.version or args.version_pos

    if args.artifacts_only or args.at_tag:
        if not version_arg:
            print("ERROR verify-release: --at-tag and --artifacts-only need --version")
            return 2
        if args.artifacts_only and (args.at_tag or not args.manifest):
            print("ERROR verify-release: --artifacts-only needs --manifest and takes no --at-tag")
            return 2
    if args.artifacts_only:
        return artifacts_only(root, version_arg, args.manifest, base_ref)

    try:
        versions, skip_reason = resolve_versions(root, version_arg, base_ref)
    except disposition_gate.GateError as e:
        print(f"ERROR verify-release: {e}")
        return 2
    if not versions:
        print(f"SKIP verify-release: {skip_reason}")
        return 0

    any_error = False
    any_fail = False
    for v in versions:
        lines, code = evaluate_version(root, v, base_ref, args.manifest, args.at_tag)
        for line in lines:
            print(line)
        if code == 2:
            any_error = True
        elif code == 1:
            any_fail = True

    if any_error:
        return 2
    if any_fail:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
