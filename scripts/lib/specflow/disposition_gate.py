"""scripts/lib/specflow/disposition_gate.py — the PR-time security-disposition gate (REQ-322, ADR-002; R11-R13).

Behind scripts/check-security-disposition.sh. Resolves which version(s) to evaluate (R11), walks every changed
docs/security/*-review.md or *-disposition.md revision to catch a removed id (R12), reads each evaluated version's
prior entries — a tagged prior version from its tag, an untagged one from the working tree (R12) — reduced to the
latest entry per id with blocks.latest_entries, and calls disposition.decide() over the pure records. It does no
scoring or parsing of its own beyond wiring: cvss4 (via blocks) derives severity, blocks.py is the one reader of
the schema, disposition.py is the one decision kernel.

Exit 0 (every evaluated version passed, or nothing to evaluate), 1 (any FAIL), 2 (any ERROR; 2 wins).
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blocks  # noqa: E402
import config  # noqa: E402
import disposition  # noqa: E402
import records  # noqa: E402

SEC_FILE_RE = re.compile(r"^docs/security/(?P<v>[^/]+)-(?:review|disposition)\.md$")
REL_FILE_RE = re.compile(r"^docs/releases/(?P<v>[^/]+)-(?:notes|migration|known-limitations)\.md$")
DEFAULT_MEDIUM_CAP = 5
DEFAULT_EXPIRY_HORIZON_DAYS = 180


class GateError(Exception):
    """A parser-level (exit 2) problem: an unreadable, mismatched or unparsable security document."""


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


def default_base_ref(root: Path) -> str:
    """The base when neither --base nor SPECFLOW_BASE_REF names one — a non-PR CI event (ci.yml passes it empty) or a
    local run: the full ref refs/remotes/origin/main when it exists, since git resolves a short name's refs/tags/<name>
    before refs/remotes/<name> and a tag named origin/main would shadow it (PR #54 verifier run 2, code-mode low);
    else the short origin/main, a local checkout's own view."""
    if _git(root, "rev-parse", "-q", "--verify", "refs/remotes/origin/main^{commit}").returncode == 0:
        return "refs/remotes/origin/main"
    return "origin/main"


def _tag_exists(root: Path, version: str) -> bool:
    return _git(root, "rev-parse", "-q", "--verify", f"refs/tags/v{version}").returncode == 0


def _git_show_text(root: Path, ref: str, path: str) -> str:
    p = _git(root, "show", f"{ref}:{path}")
    if p.returncode != 0:
        raise GateError(f"cannot read {ref}:{path}: {p.stderr.strip()}")
    return p.stdout


def _changed_files(root: Path, base_ref: str) -> set:
    """What the PR changes: committed since the merge-base with base_ref (a base that advanced after the branch
    point contributes nothing), plus uncommitted and untracked files. --no-renames: a moved file is listed at its
    old path (a delete) as well as its new one, so moving a security document out of docs/security/ is seen."""
    names = set()
    committed = _git(root, "diff", "--no-renames", "--name-only", f"{base_ref}...HEAD")
    if committed.returncode != 0:  # no merge-base (unrelated histories): the plain two-tree diff
        committed = _git(root, "diff", "--no-renames", "--name-only", base_ref, "HEAD")
    names |= {l for l in committed.stdout.splitlines() if l}
    names |= set(_git_lines(root, "diff", "--no-renames", "--name-only", "HEAD"))
    names |= set(_git_lines(root, "ls-files", "--others", "--exclude-standard"))
    return names


# ------------------------------------------------------------------------------------------------ id removal walk


def _list_security_files_at(root: Path, ref: str | None) -> list:
    if ref is None:
        d = root / "docs" / "security"
        if not d.is_dir():
            return []
        return sorted(
            f"docs/security/{p.name}" for p in d.iterdir() if SEC_FILE_RE.match(f"docs/security/{p.name}")
        )
    out = _git_lines(root, "ls-tree", "-r", "--name-only", ref, "--", "docs/security")
    return sorted(p for p in out if SEC_FILE_RE.match(p))


def _read_text_at(root: Path, ref: str | None, path: str) -> str:
    if ref is None:
        return (root / path).read_text()
    return _git_show_text(root, ref, path)


def _ids_per_file_at(root: Path, ref: str | None) -> dict:
    result = {}
    for path in _list_security_files_at(root, ref):
        text = _read_text_at(root, ref, path)
        ids = set()
        try:
            for blk in blocks.split_blocks(text, path):
                fields = config.parse(blk.body)
                if fields.get("id"):
                    ids.add(fields["id"])
        except (blocks.BlockError, config.ConfigError) as e:
            raise GateError(str(e)) from e
        result[path] = ids
    return result


def _file_version(path: str) -> str:
    m = SEC_FILE_RE.match(path)
    return m.group("v") if m else "?"


def id_removal_walk(root: Path, base_ref: str) -> list:
    """R12: whenever the PR changes any docs/security/ review or disposition file, compare every PR commit
    (`rev-list base_ref..HEAD`, merges included) with its own first parent, then the working tree with HEAD; report
    each id present before and missing after as a FAIL line. Comparing with the first parent, never with the base
    tip, means ids the base gained after the branch point are not the PR's removals, and a merge of the base into
    the PR branch removes nothing it does not actually drop. Raises GateError on an unparsable revision."""
    if not _base_resolves(root, base_ref):
        return []
    changed = _changed_files(root, base_ref)
    if not any(SEC_FILE_RE.match(f) for f in changed):
        return []
    cache: dict = {}

    def ids_at(ref):
        if ref not in cache:
            cache[ref] = _ids_per_file_at(root, ref)
        return cache[ref]

    pairs = []
    for c in _git_lines(root, "rev-list", "--reverse", f"{base_ref}..HEAD"):
        parents = (_git_lines(root, "rev-list", "--parents", "-n", "1", c) or [""])[0].split()[1:]
        if parents:
            pairs.append((parents[0], c, f"commit {c[:7]}"))
    head = (_git_lines(root, "rev-parse", "HEAD") or [None])[0]
    if head:
        pairs.append((head, None, "working tree"))
    fail_lines = []
    seen = set()
    for before, after, label in pairs:
        prev, cur = ids_at(before), ids_at(after)
        for path in sorted(set(prev) | set(cur)):
            removed = prev.get(path, set()) - cur.get(path, set())
            for rid in sorted(removed):
                line = f"FAIL security-disposition {_file_version(path)} {rid} id_removed ({label})"
                if line not in seen:
                    seen.add(line)
                    fail_lines.append(line)
    return fail_lines


# ---------------------------------------------------------------------------------------------- version resolution


def ship_branch_version(root: Path) -> str | None:
    """R11: the version a `ship/<version>` head branch names (SPECFLOW_HEAD_BRANCH, else GITHUB_HEAD_REF, else the
    checked-out branch), or None. Shared with release_gate.resolve_versions. A `ship/<v>` whose <v> is not
    <major>.<minor>.<patch>[-<pre>] (VERSION_RE; e.g. `ship/v1.0.0`) raises GateError, which both gates report as an
    ERROR (exit 2) naming the branch — never a traceback from comparing a non-numeric version key."""
    import os

    branch = (
        os.environ.get("SPECFLOW_HEAD_BRANCH")
        or os.environ.get("GITHUB_HEAD_REF")
        or (_git_lines(root, "rev-parse", "--abbrev-ref", "HEAD") or [""])[0]
    )
    m = re.match(r"^ship/(.+)$", branch or "")
    if not m:
        return None
    if not VERSION_RE.match(m.group(1)):
        raise GateError(
            f"head branch {branch} names version {m.group(1)!r}, which is not semver — "
            f"expected ship/<major>.<minor>.<patch>[-<pre>], e.g. ship/1.0.0"
        )
    return m.group(1)


def resolve_versions(root: Path, version_arg: str | None, base_ref: str | None, use_git: bool):
    """Returns (versions: list[str], skip_reason: str | None). R11."""
    if version_arg:
        return [version_arg], None
    if not use_git:
        return [], "no --version and --no-git"
    ship = ship_branch_version(root)
    if ship:
        return [ship], None
    if not _base_resolves(root, base_ref):
        return [], f"no base ref {base_ref}" if base_ref else "no base ref"
    changed = _changed_files(root, base_ref)
    versions = set()
    for f in changed:
        m2 = SEC_FILE_RE.match(f) or REL_FILE_RE.match(f)
        if m2:
            versions.add(m2.group("v"))
    if not versions:
        return [], "the PR touches no docs/security/ or docs/releases/ file naming a version"
    return sorted(versions, key=blocks.version_key), None


# --------------------------------------------------------------------------------------------------------- rubric


def _extract_rubric_block(text: str) -> dict:
    m = re.search(r"```yaml\n(.*?)\n```", text, re.S)
    if not m:
        return {}
    try:
        return config.parse(m.group(1))
    except config.ConfigError as e:
        raise GateError(f"RUBRIC.md: unparsable yaml block: {e}") from e


def resolve_rubric(root: Path, rubric_arg: str | None, base_ref: str | None, use_git: bool):
    """Returns (medium_cap, expiry_horizon_days, source, notes). Raises GateError on an invalid or missing
    rubric (R13), including a base ref that resolves but carries no RUBRIC.md; the working tree's copy is read only
    when the base does not resolve (with a note saying so) or under --no-git."""
    notes = []
    text = None
    source = None
    if rubric_arg:
        p = Path(rubric_arg)
        if not p.is_file():
            raise GateError(f"--rubric {rubric_arg}: not found")
        text = p.read_text()
        source = rubric_arg
    elif use_git and base_ref and _base_resolves(root, base_ref):
        # The base resolves: its rubric governs, and a base without one is an error — never the PR's own copy,
        # which would let the PR set its own medium_cap and expiry_horizon_days (PR #42 code mode).
        try:
            text = _git_show_text(root, base_ref, "docs/security/RUBRIC.md")
        except GateError as e:
            raise GateError(f"no docs/security/RUBRIC.md at {base_ref} (the base resolves; the PR's own copy is not "
                            f"read in its place); pass --rubric") from e
        source = f"{base_ref}:docs/security/RUBRIC.md"
    if text is None:
        wt = root / "docs/security/RUBRIC.md"
        if wt.is_file():
            text = wt.read_text()
            source = "docs/security/RUBRIC.md"
            if use_git and base_ref:
                notes.append(f"no base ref {base_ref} (it does not resolve): reading docs/security/RUBRIC.md from the "
                             f"working tree (not a control)")
        else:
            where = f"{base_ref} does not resolve and" if use_git and base_ref else "--no-git, and"
            raise GateError(f"no docs/security/RUBRIC.md: {where} none is in the working tree; pass --rubric")
    fields = _extract_rubric_block(text)
    cap = fields.get("medium_cap")
    if cap is None:
        notes.append(f"medium_cap absent from RUBRIC.md; default {DEFAULT_MEDIUM_CAP}")
        cap = DEFAULT_MEDIUM_CAP
    else:
        try:
            cap = int(cap)
        except ValueError as e:
            raise GateError(f"RUBRIC.md: medium_cap {cap!r} is not an integer") from e
        if cap < 0:
            raise GateError(f"RUBRIC.md: medium_cap {cap} must be >= 0")
    horizon = fields.get("expiry_horizon_days")
    if horizon is None:
        notes.append(f"expiry_horizon_days absent from RUBRIC.md; default {DEFAULT_EXPIRY_HORIZON_DAYS}")
        horizon = DEFAULT_EXPIRY_HORIZON_DAYS
    else:
        try:
            horizon = int(horizon)
        except ValueError as e:
            raise GateError(f"RUBRIC.md: expiry_horizon_days {horizon!r} is not an integer") from e
        if horizon < 1:
            raise GateError(f"RUBRIC.md: expiry_horizon_days {horizon} must be >= 1")
    return cap, horizon, source, notes


# ------------------------------------------------------------------------------------------------------ priors


def _parse_date(s: str | None) -> date | None:
    if not s:
        return None
    return datetime.strptime(s, "%Y-%m-%d").date()


VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$")


def _candidate_prior_versions(root: Path, before_version: str, base_ref: str | None, use_git: bool) -> list:
    """Every version earlier than before_version that the working tree's docs/security/, the base ref's
    docs/security/ or a `v*` tag names — never the working tree alone, so a PR that moves or deletes a prior
    version's documents does not drop it from carry-forward (R12)."""
    versions = set()
    for path in _list_security_files_at(root, None):
        versions.add(_file_version(path))
    if use_git:
        if _base_resolves(root, base_ref):
            for path in _list_security_files_at(root, base_ref):
                versions.add(_file_version(path))
        for tag in _git_lines(root, "tag", "-l", "v*"):
            if VERSION_RE.match(tag[1:]):
                versions.add(tag[1:])
    before_key = blocks.version_key(before_version)
    return sorted((v for v in versions if blocks.version_key(v) < before_key), key=blocks.version_key)


def _exists_at(root: Path, ref: str, path: str) -> bool:
    return _git(root, "cat-file", "-e", f"{ref}:{path}").returncode == 0


def read_priors(root: Path, before_version: str, use_git: bool, base_ref: str | None = None):
    """Returns (prior_entries: list[records.PriorEntry], review_ids_by_version: dict[str, set[str]]). Raises
    GateError on a parser problem: a version's review/disposition id sets do not match (R12), or the reduced
    latest entries cannot be read.

    Each prior version is read from its tag when tagged (the header optional there: a pre-schema file with no
    blocks contributes nothing, ADR-002), else from the working tree, else — moved or deleted by this PR — from
    the base ref (both header-required)."""
    candidates = _candidate_prior_versions(root, before_version, base_ref, use_git)
    review_ids_by_version: dict = {}
    sev_by_version_id: dict = {}
    tagged_dir = Path(tempfile.mkdtemp(prefix="specflow-priors-tagged-"))
    priors_dir = Path(tempfile.mkdtemp(prefix="specflow-priors-"))
    try:
        for v in candidates:
            rv_rel, ds_rel = f"docs/security/{v}-review.md", f"docs/security/{v}-disposition.md"
            tagged = use_git and _tag_exists(root, v)
            if tagged:
                have = (_exists_at(root, f"v{v}", rv_rel), _exists_at(root, f"v{v}", ds_rel))
                if not any(have):
                    continue  # a release with no security documents at its tag
                rv_text = _git_show_text(root, f"v{v}", rv_rel)
                ds_text = _git_show_text(root, f"v{v}", ds_rel)
            elif (root / rv_rel).is_file() and (root / ds_rel).is_file():
                rv_text, ds_text = (root / rv_rel).read_text(), (root / ds_rel).read_text()
            elif use_git and _base_resolves(root, base_ref) and _exists_at(root, base_ref, rv_rel) \
                    and _exists_at(root, base_ref, ds_rel):
                rv_text = _git_show_text(root, base_ref, rv_rel)
                ds_text = _git_show_text(root, base_ref, ds_rel)
            else:
                continue
            try:
                rv = blocks.parse_review(rv_text, f"{v}-review.md", version=v, require_header=not tagged)
                ds = blocks.parse_disposition(ds_text, f"{v}-disposition.md", version=v, require_header=not tagged)
            except blocks.BlockError as e:
                raise GateError(str(e)) from e
            rv_ids = {f.id for f in rv.findings}
            ds_ids = {e.id for e in ds.entries}
            missing_in_ds = sorted(rv_ids - ds_ids)
            missing_in_rv = sorted(ds_ids - rv_ids)
            if missing_in_ds:
                raise GateError(f"{v}-review.md: {missing_in_ds[0]} has no entry in {v}-disposition.md")
            if missing_in_rv:
                raise GateError(f"{v}-disposition.md: {missing_in_rv[0]} has no finding in {v}-review.md")
            review_ids_by_version[v] = rv_ids
            for f in rv.findings:
                sev_by_version_id[(v, f.id)] = f.severity
            ((tagged_dir if tagged else priors_dir) / f"{v}-disposition.md").write_text(ds_text)
        errors: list = []
        latest = blocks.latest_entries(priors_dir, "docs/security", errors, before=before_version, require_header=True)
        # Tagged versions (header optional) reduce apart; the two sets hold disjoint versions, so the higher
        # version wins across them exactly as within one reduction.
        for eid, l in blocks.latest_entries(tagged_dir, "docs/security", errors, before=before_version,
                                            require_header=False).items():
            cur = latest.get(eid)
            if cur is None or blocks.version_key(l.version) > blocks.version_key(cur.version):
                latest[eid] = l
        if errors:
            rel, line, msg = errors[0]
            raise GateError(f"{rel}:{line}: {msg}")
        prior_entries = []
        for eid, l in latest.items():
            sev = sev_by_version_id.get((l.version, eid))
            if sev is None:
                raise GateError(f"{l.version}: {eid} has no finding in {l.version}-review.md")
            prior_entries.append(
                records.PriorEntry(
                    id=eid,
                    severity=records.Severity(sev),
                    status=records.Status(l.entry.status),
                    expiry=_parse_date(l.entry.expiry),
                    version=l.version,
                )
            )
        return prior_entries, review_ids_by_version
    finally:
        shutil.rmtree(priors_dir, ignore_errors=True)
        shutil.rmtree(tagged_dir, ignore_errors=True)


# --------------------------------------------------------------------------------------------------- at the tag


def tag_run_date(root: Path, version: str):
    """--at-tag's run date (P6 R30; PR #52 verifier run 1, finding 5): the LATER of the tag's tagger date and the tagged
    commit's committer date, in UTC, so a tagger who backdates the tag (GIT_COMMITTER_DATE) is bounded below by the
    commit it tags (for a ship PR GitHub merged: GitHub's merge time) and a re-run is deterministic. Returns
    (date, label) or None when v<version> does not resolve to a commit. A lightweight tag has no tagger date: the
    committer date alone."""
    ref = f"refs/tags/v{version}"
    ct = _git(root, "log", "-1", "--format=%ct", f"{ref}^{{commit}}")
    if ct.returncode != 0 or not ct.stdout.strip().isdigit():
        return None
    commit_ts = int(ct.stdout.strip())
    tagger_ts = None
    for line in _git_lines(root, "for-each-ref", "--format=%(refname)%00%(taggerdate:unix)", ref):
        name, _, when = line.partition("\0")
        if name == ref and when.strip().isdigit() and int(when) > 0:
            tagger_ts = int(when)

    def day(ts: int) -> date:
        return datetime.fromtimestamp(ts, timezone.utc).date()

    if tagger_ts is None:
        return day(commit_ts), f"run date {day(commit_ts).isoformat()} (committer date of v{version}'s commit; no tagger date)"
    if commit_ts > tagger_ts:
        return day(commit_ts), (f"run date {day(commit_ts).isoformat()} (committer date of v{version}'s commit, "
                                f"later than its tagger date {day(tagger_ts).isoformat()})")
    return day(tagger_ts), f"run date {day(tagger_ts).isoformat()} (tagger date of v{version})"


def tag_tree_mismatch(root: Path, version: str) -> str | None:
    """--at-tag reads the release and security documents from the checkout, never through `git show`: so the checkout
    must BE the tag's tree — HEAD is v<version>'s commit and `git status --porcelain` lists nothing (an untracked file
    counts; ignored files and python's own __pycache__ do not) — or the replay would judge files the tag does not carry (P6 fix wave 1, G).
    release.yml's verify job checks the tag out and writes nothing tracked or untracked before the replay. Returns the
    reason the checkout is not the tag's tree, or None."""
    tc = _git(root, "rev-parse", "-q", "--verify", f"refs/tags/v{version}^{{commit}}")
    head = _git(root, "rev-parse", "-q", "--verify", "HEAD")
    if tc.returncode != 0:
        return f"v{version} does not resolve to a commit"
    if head.stdout.strip() != tc.stdout.strip():
        return (f"HEAD ({head.stdout.strip()[:12] or 'unresolved'}) is not v{version}'s commit "
                f"({tc.stdout.strip()[:12]}): the replay reads the documents from the checkout, which must be the tag's")
    st = _git(root, "status", "--porcelain")
    if st.returncode != 0:
        return "git status failed: whether the working tree is the tag's tree is unknown"
    # the bytecode python itself writes beside the modules running the replay is not a document (a repository's
    # .gitignore normally hides it; a scratch clone may not)
    dirty = [l for l in st.stdout.splitlines() if l.strip() and "__pycache__/" not in l and not l.rstrip().endswith(".pyc")]
    if dirty:
        return (f"the working tree is not v{version}'s tree (git status --porcelain lists {len(dirty)} path(s), e.g. "
                f"{dirty[0][3:]}): the replay reads the documents from the checkout, which must be the tag's tree")
    return None


def tag_base_ref(root: Path, version: str) -> str | None:
    """--at-tag's base (Build 3 final review, finding 16): the tagged commit's first parent — the ship PR's base as merged,
    which is what the PR-time gate read — as a full sha, or the tagged commit itself when it has no parent; None when
    v<version> does not resolve. Every base-side input of the replay (the rubric, the priors, the id walk; release_gate's
    app-stack rule) is read there, never at main's tip, which can carry commits pushed after the tag."""
    for ref in (f"refs/tags/v{version}^{{commit}}^1", f"refs/tags/v{version}^{{commit}}"):
        p = _git(root, "rev-parse", "-q", "--verify", ref)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip()
    return None


# --------------------------------------------------------------------------------------------------- evaluation


def _to_findings(review) -> list:
    return [
        records.Finding(id=f.id, severity=records.Severity(f.severity), cvss_vector=f.cvss_vector)
        for f in review.findings
    ]


def _to_entries(disp) -> list:
    return [
        records.Entry(
            id=e.id,
            status=records.Status(e.status),
            owner=e.owner,
            expiry=_parse_date(e.expiry),
            rationale=e.rationale,
            reclassified_by=e.reclassified_by,
        )
        for e in disp.entries
    ]


def evaluate_version(root: Path, version: str, medium_cap: int, horizon: int, run_date: date,
                      use_git: bool, rubric_source: str | None, base_ref: str | None = None) -> tuple:
    """Returns (lines: list[str], code: int) — 0 PASS, 1 FAIL, 2 ERROR."""
    review_path = root / f"docs/security/{version}-review.md"
    disposition_path = root / f"docs/security/{version}-disposition.md"
    if not review_path.is_file() or not disposition_path.is_file():
        return [f"ERROR security-disposition {version}: run /security-review"], 2
    try:
        review = blocks.parse_review(review_path.read_text(), review_path.name, version=version, require_header=True)
        disp = blocks.parse_disposition(
            disposition_path.read_text(), disposition_path.name, version=version, require_header=True
        )
    except blocks.BlockError as e:
        return [f"ERROR security-disposition {e}"], 2

    # Gate mode's joined checks (R5): unique ids per file, owner/expiry on an accepted/deferred medium-or-above,
    # rationale of at least 10 characters — parser-level errors, never FAIL.
    pair_errors = blocks.check_pair(review, disp)
    if pair_errors:
        names = {"review": review_path.name, "disposition": disposition_path.name}
        return [f"ERROR security-disposition {names.get(e.rel, e.rel)}:{e.line}: {e.message}" for e in pair_errors], 2

    try:
        prior_entries, review_ids_by_version = read_priors(root, version, use_git, base_ref)
    except GateError as e:
        return [f"ERROR security-disposition {e}"], 2

    for f in review.findings:
        if f.carried_from and f.id not in review_ids_by_version.get(f.carried_from, set()):
            return [
                f"ERROR security-disposition {version}-review.md: {f.id}: carried_from {f.carried_from!r} "
                f"does not name a version whose review defines or carries {f.id}"
            ], 2

    try:
        verdict = disposition.decide(
            _to_findings(review), _to_entries(disp), prior_entries, medium_cap, horizon, run_date
        )
    except ValueError as e:
        return [f"ERROR security-disposition {version}: {e}"], 2

    if verdict.passed:
        due = sum(1 for p in prior_entries if disposition.due(p))
        return [
            f"PASS security-disposition {version}: {len(review.findings)} findings, {due} prior entries due, "
            f"medium_cap {medium_cap} and expiry_horizon_days {horizon} from {rubric_source}, "
            f"run date {run_date.isoformat()}"
        ], 0
    return [f"FAIL security-disposition {version} {v.id} {v.rule.value}" for v in verdict.violations], 1


# --------------------------------------------------------------------------------------------------------- main


def main(argv):
    import os

    p = argparse.ArgumentParser(prog="disposition_gate.py")
    p.add_argument("--version")
    p.add_argument("--root", default=".")
    p.add_argument("--base")
    p.add_argument("--run-date")
    p.add_argument("--rubric")
    p.add_argument("--no-git", action="store_true")
    p.add_argument("--at-tag", action="store_true",
                   help="release.yml's replay: evaluate the tagged --version itself (priors strictly before it)")
    args = p.parse_args(argv)
    if args.at_tag and not args.version:
        print("ERROR security-disposition: --at-tag needs --version")
        return 2

    root = Path(args.root)
    use_git = not args.no_git
    base_ref = args.base or os.environ.get("SPECFLOW_BASE_REF") or (default_base_ref(root) if use_git else None)
    run_date = _parse_date(args.run_date)
    if args.at_tag:
        if not use_git:
            print("ERROR security-disposition: --at-tag reads the tag and cannot run with --no-git")
            return 2
        tagged = tag_run_date(root, args.version)
        if tagged is None:
            print(f"ERROR security-disposition: --at-tag: v{args.version} does not resolve to a commit")
            return 2
        why = tag_tree_mismatch(root, args.version)
        if why:
            print(f"ERROR security-disposition: --at-tag: {why}")
            return 2
        if run_date is None:
            run_date, label = tagged
            print(f"note: {label}")
        tb = tag_base_ref(root, args.version)
        print(f"note: --at-tag reads the rubric and the priors at v{args.version}'s parent {tb[:12]} (the ship PR's base as "
              f"merged), not at {base_ref}")
        base_ref = tb
    run_date = run_date or date.today()

    try:
        medium_cap, horizon, rubric_source, notes = resolve_rubric(root, args.rubric, base_ref, use_git)
    except GateError as e:
        print(f"ERROR security-disposition: {e}")
        return 2
    for n in notes:
        print(f"note: {n}")

    any_error = False
    any_fail = False

    if use_git:
        try:
            walk_lines = id_removal_walk(root, base_ref)
        except GateError as e:
            print(f"ERROR security-disposition: {e}")
            return 2
        for line in walk_lines:
            print(line)
        if walk_lines:
            any_fail = True

    try:
        versions, skip_reason = resolve_versions(root, args.version, base_ref, use_git)
    except GateError as e:
        print(f"ERROR security-disposition: {e}")
        return 2
    if not versions:
        print(f"SKIP security-disposition: {skip_reason}")
        if any_fail:
            return 1
        return 0

    for v in versions:
        if use_git and _tag_exists(root, v) and not (args.at_tag and v == args.version):
            print(f"SKIP security-disposition {v}: tagged v{v} — a released version is never re-evaluated")
            continue
        lines, code = evaluate_version(root, v, medium_cap, horizon, run_date, use_git, rubric_source, base_ref)
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
