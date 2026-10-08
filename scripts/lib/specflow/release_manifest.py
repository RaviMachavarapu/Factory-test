#!/usr/bin/env python3
"""scripts/lib/specflow/release_manifest.py — manifest schema 2 and the reproducible subset (REQ-384, REQ-305; P6 R18).

`dist/manifest.json` (schema `specflow-manifest/2`): version, stack, source_date_epoch, tree, artifacts (sorted by
filename; each filename, sha256, size, kind, reproducible, and for a bundle signed) and a top-level `signed` (null
without a bundle, else the bundle's). A schema-1 manifest ({version, artifacts: [{filename, sha256, size}]}) still
reads, every entry counting as reproducible. The notes' Artifacts table transcribes exactly the reproducible entries.

The epoch is 00:00:00 UTC of the release notes' frontmatter `date:` (R18 (iii)), a value in the tree. `repack_sdist`
makes a setuptools sdist deterministic (R18 (c)). Build 3 (Task 3.4) adds, test-first, what release.yml's publish and
signing steps need: `assemble` (the Release's manifest: the parts merged, the tag, commit, run and image recorded),
`rewrite_entry` (a re-signed bundle replaces its entry) and `release_body` (the Release's text, rendered from the
manifest's entries, never from the stack's name).

CLI: epoch --notes PATH | rows --manifest PATH | write --dist DIR --version V --stack S [--epoch N] [--tree T]
--artifact NAME KIND 0|1 ... | assemble --out PATH --tag T --commit C --run N [--image-json PATH]
[--unsigned-bundle | --signed-bundle] PART...
| rewrite-entry --manifest PATH --file NAME --from PATH [--signed] | body --notes PATH --manifest PATH
[--tester-instructions PATH] [--anchor REF] --tag-kind ssh-good|unsigned. Exit 2 on bad input. Stdlib only.
"""
from __future__ import annotations

import argparse
import calendar
import datetime
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frontmatter  # noqa: E402

SCHEMA = "specflow-manifest/2"
KINDS = ("source-archive", "sdist", "wheel", "bundle")


def epoch_from_notes(path: str) -> int:
    fm, _ = frontmatter.read(path)
    d = fm.get("date", "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", d):
        raise ValueError(f"{path}: frontmatter date: must be YYYY-MM-DD, got {d!r}")
    try:
        dt = datetime.datetime.strptime(d, "%Y-%m-%d")
    except ValueError as e:
        raise ValueError(f"{path}: {e}") from None
    return calendar.timegm(dt.timetuple())


def _sha(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write(dist: str, version: str, stack: str, epoch: int | None, tree: str | None, entries) -> dict:
    """dist/manifest.json from the entries (name, kind, reproducible[, signed]). The bundle part alone (an app hook's
    RELEASE_PARTS=bundle) knows neither the epoch nor the tree: both are null there, and the source part's manifest
    supplies them in the Release release.yml assembles."""
    arts = []
    signed = None
    for e in entries:
        name, kind, repro = e[0], e[1], bool(e[2])
        if kind not in KINDS:
            raise ValueError(f"unknown artifact kind {kind!r}")
        path = os.path.join(dist, name)
        a = {"filename": name, "sha256": _sha(path), "size": os.path.getsize(path), "kind": kind, "reproducible": repro}
        if kind == "bundle":
            a["signed"] = bool(e[3]) if len(e) > 3 else False
            signed = a["signed"]
        arts.append(a)
    arts.sort(key=lambda a: a["filename"])
    m = {"schema": SCHEMA, "version": version, "stack": stack,
         "source_date_epoch": int(epoch) if epoch is not None else None, "tree": tree or None,
         "artifacts": arts, "signed": signed}
    with open(os.path.join(dist, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2)
        f.write("\n")
    return m


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    if not isinstance(m, dict) or not isinstance(m.get("artifacts"), list):
        raise ValueError(f"{path}: not a manifest")
    return m


def reproducible_rows(m: dict) -> list:
    rows = []
    for a in m["artifacts"]:
        if a.get("reproducible", True):  # schema 1 carries no flag: every entry counts
            rows.append((a["filename"], a["sha256"], a["size"]))
    return sorted(rows)


def rows_markdown(rows) -> str:
    return "".join(f"| `{n}` | `{s}` | {z} |\n" for n, s, z in rows)


def repack_sdist(src: str, dst: str, epoch: int) -> None:
    """A deterministic sdist: members sorted, mtime the epoch, uid/gid 0, no owner names, modes 0755/0644, PAX
    headers dropped, gzip header mtime 0 and no name (R18 (c))."""
    with tarfile.open(src, "r:*") as t:
        members = sorted(t.getmembers(), key=lambda m: m.name)
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as out:
            for m in members:
                i = tarfile.TarInfo(m.name)
                i.type = m.type
                i.mtime = int(epoch)
                i.uid = i.gid = 0
                i.uname = i.gname = ""
                if m.isdir() or (m.mode & 0o111):
                    i.mode = 0o755
                else:
                    i.mode = 0o644
                if m.issym() or m.islnk():
                    i.linkname = m.linkname
                if m.isfile():
                    i.size = m.size
                    out.addfile(i, t.extractfile(m))
                else:
                    out.addfile(i)
    with open(dst, "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as gz:
            gz.write(buf.getvalue())


BUNDLE_PROVENANCE = ("unsigned", "signed")


def assemble(parts: list, tag: str, commit: str, run: str, image: dict | None = None,
             bundle: str | None = None) -> dict:
    """The Release's manifest (specflow-manifest/2 plus tag, commit, run and, for python, image) from the parts' manifests:
    the first is the source part (version, stack, epoch and tree come from it); every artifact of every part is kept,
    sorted by filename; at most one bundle entry (the caller passes the signed part in place of the unsigned one, R33);
    `signed` is the bundle's, else null. Parts of two versions, a repeated filename, two bundles or a commit that is not
    40 lowercase hex are ValueError.

    `bundle` is the bundle part's provenance, which the caller knows from the directory it chose and which decides
    `signed` (Build 5 fix wave 1, A): "unsigned" (bundle-unsigned/, written by the bundle job after third-party build
    code ran) forces every bundle entry's and the top-level `signed` to false, whatever that part's manifest claims;
    "signed" (bundle-signed/, which release.yml downloads only when verify-signed succeeded) requires exactly one bundle
    entry saying signed: true, else ValueError. None keeps the entry's own value (a caller with no bundle part)."""
    if bundle is not None and bundle not in BUNDLE_PROVENANCE:
        raise ValueError(f"bundle provenance must be one of {', '.join(BUNDLE_PROVENANCE)}, got {bundle!r}")
    if not parts:
        raise ValueError("no part manifest given")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError(f"commit {commit!r} is not 40 lowercase hex characters")
    version = parts[0].get("version")
    arts: list = []
    seen: set = set()
    for p in parts:
        if p.get("version") != version:
            raise ValueError(f"parts of two versions: {version!r} and {p.get('version')!r}")
        for a in p["artifacts"]:
            if a["filename"] in seen:
                raise ValueError(f"{a['filename']} is in two parts")
            seen.add(a["filename"])
            arts.append(dict(a))
    bundles = [a for a in arts if a.get("kind") == "bundle"]
    if len(bundles) > 1:
        raise ValueError(f"{len(bundles)} bundle entries: a Release carries one (the signed part replaces the unsigned)")
    if bundle == "unsigned":
        for a in bundles:
            a["signed"] = False
    elif bundle == "signed" and (len(bundles) != 1 or bundles[0].get("signed") is not True):
        raise ValueError("the signed bundle part must hold one bundle entry saying signed: true (verify-signed checks it)")
    arts.sort(key=lambda a: a["filename"])
    first = parts[0]
    m = {"schema": SCHEMA, "version": version, "stack": first.get("stack"),
         "source_date_epoch": first.get("source_date_epoch"), "tree": first.get("tree"), "artifacts": arts,
         "signed": bool(bundles[0].get("signed", False)) if bundles else None,
         "tag": tag, "commit": commit, "run": str(run)}
    if image is not None:
        m["image"] = {"name": image["name"], "tag": image["tag"], "digest": image["digest"]}
    return m


def rewrite_entry(manifest_path: str, filename: str, new_path: str, signed: bool) -> None:
    """The re-signed bundle replaces the entry's file beside the manifest; its sha256 and size are recomputed and its
    `signed` (and the top-level one) set (R33)."""
    m = load(manifest_path)
    entry = next((a for a in m["artifacts"] if a["filename"] == filename), None)
    if entry is None:
        raise ValueError(f"{manifest_path} has no entry {filename!r}")
    dest = os.path.join(os.path.dirname(os.path.abspath(manifest_path)), filename)
    if os.path.abspath(new_path) != dest:
        shutil.copyfile(new_path, dest)
    entry["sha256"] = _sha(dest)
    entry["size"] = os.path.getsize(dest)
    if entry.get("kind") == "bundle":
        entry["signed"] = bool(signed)
        m["signed"] = bool(signed)
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2)
        f.write("\n")


def _strip_frontmatter(text: str) -> str:
    m = re.match(r"---[ \t]*\n.*?\n---[ \t]*\n", text, re.S)
    return text[m.end():] if m else text


TAG_KINDS = ("ssh-good", "unsigned")


def release_body(notes_text: str, manifest: dict, tester_instructions: str | None = None,
                 anchor: str | None = None, tag_kind: str | None = None) -> str:
    """The Release's text: the notes without their frontmatter; a manifest.json line; for python an `Image:` line; how
    to verify the tag, chosen by the TAG's own verdict (`tag_kind`, release.yml's verify job: signers.py verify) and never
    by whether an anchor exists — a TOFU anchor exists once allowed_signers lists a key, yet an annotated, unsigned tag
    with its fallback recorded passes --at-tag (wave 1 round 2): `ssh-good` → the offline verification against
    allowed_signers at the anchor (R31), which must then be a ref; `unsigned` → the honest statement that the tag is
    annotated with its fallback recorded and carries no signature to verify, whatever the anchor. Any other verdict, or
    none, is ValueError: release.yml publishes no other kind. And, when the manifest says the bundle is unsigned and
    instructions are given, them under `## Opening this unsigned app`. Every line is rendered from the manifest's entries,
    its `signed` and the tag's verdict, never from the stack's name (R35)."""
    if tag_kind not in TAG_KINDS:
        raise ValueError(f"the tag's verdict must be one of {', '.join(TAG_KINDS)} (release.yml publishes no other), "
                         f"got {tag_kind!r}")
    if tag_kind == "ssh-good" and (not anchor or anchor == "-"):
        raise ValueError("an ssh-good tag is verified against an anchor, but none was given")
    version = manifest["version"]
    tag = manifest.get("tag") or f"v{version}"
    out = [_strip_frontmatter(notes_text).strip("\n"), ""]
    out.append("The attached `manifest.json` lists every artifact of this release with its SHA-256 and size.")
    img = manifest.get("image")
    if img:
        out += ["", f"Image: {img['name']}:{img['tag']}@{img['digest']}"]
    out += ["", "## Verify this release", ""]
    if tag_kind == "unsigned":
        # release.yml accepted the tag only as an annotated tag with the fallback recorded, so there is no signature to
        # verify — say so, with or without an anchor, and give no command that would fail for this tag or check it
        # against a key file it carries itself (fix wave 1, F; wave 1 round 2)
        out.append(f"This release's tag `{tag}` is annotated, not signed: the annotated-tag fallback is recorded in "
                   f"`docs/releases/{version}-known-limitations.md`, so there is no signature to verify. "
                   f"`git cat-file tag {tag}` shows the tag object.")
    else:
        out.append(f"The tag is verified against `.github/allowed_signers` as committed at the signing anchor `{anchor}`, "
                   "never the file at the tag. Check it offline:")
        out += ["", f"    git show {anchor}:.github/allowed_signers > allowed_signers",
                f"    git -c gpg.ssh.allowedSignersFile=allowed_signers verify-tag {tag}"]
    if manifest.get("signed") is False and tester_instructions:
        body = tester_instructions.strip("\n")
        lines = body.split("\n")
        if lines and lines[0].startswith("# "):
            lines = lines[1:]
        out += ["", "## Opening this unsigned app", "", "\n".join(lines).strip("\n")]
    return "\n".join(out).rstrip("\n") + "\n"


def _die(msg: str) -> None:
    print(f"release_manifest: {msg}", file=sys.stderr)
    sys.exit(2)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="release_manifest.py")
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("epoch"); p.add_argument("--notes", required=True)
    p = sub.add_parser("rows"); p.add_argument("--manifest", required=True)
    p = sub.add_parser("write")
    p.add_argument("--dist", required=True); p.add_argument("--version", required=True)
    p.add_argument("--stack", dest="pack", required=True); p.add_argument("--epoch", type=int); p.add_argument("--tree")
    p.add_argument("--artifact", nargs=3, action="append", required=True, metavar=("NAME", "KIND", "REPRODUCIBLE"))
    p = sub.add_parser("assemble")
    p.add_argument("--out", required=True); p.add_argument("--tag", required=True)
    p.add_argument("--commit", required=True); p.add_argument("--run", required=True)
    p.add_argument("--image-json"); p.add_argument("parts", nargs="+")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--unsigned-bundle", action="store_true"); g.add_argument("--signed-bundle", action="store_true")
    p = sub.add_parser("rewrite-entry")
    p.add_argument("--manifest", required=True); p.add_argument("--file", required=True)
    p.add_argument("--from", dest="src", required=True); p.add_argument("--signed", action="store_true")
    p = sub.add_parser("body")
    p.add_argument("--notes", required=True); p.add_argument("--manifest", required=True)
    p.add_argument("--tester-instructions"); p.add_argument("--anchor")
    p.add_argument("--tag-kind", required=True, choices=TAG_KINDS)
    try:
        a = ap.parse_args(argv)
    except SystemExit:
        return 2
    try:
        if a.cmd == "epoch":
            print(epoch_from_notes(a.notes))
        elif a.cmd == "rows":
            sys.stdout.write(rows_markdown(reproducible_rows(load(a.manifest))))
        elif a.cmd == "write":
            entries = []
            for name, kind, repro in a.artifact:
                if repro not in ("0", "1") or os.path.basename(name) != name:
                    raise ValueError(f"--artifact {name} {kind} {repro}: a basename, a kind and 0 or 1")
                entries.append((name, kind, repro == "1"))
            m = write(a.dist, a.version, a.pack, a.epoch, a.tree, entries)
            print(f"Wrote manifest with {len(m['artifacts'])} artifact(s)")
        elif a.cmd == "assemble":
            image = None
            if a.image_json:
                with open(a.image_json, encoding="utf-8") as f:
                    image = json.load(f)
                for k in ("name", "tag", "digest"):
                    if not image.get(k):
                        raise ValueError(f"{a.image_json} has no {k}")
            m = assemble([load(x) for x in a.parts], a.tag, a.commit, a.run, image,
                         "unsigned" if a.unsigned_bundle else "signed" if a.signed_bundle else None)
            with open(a.out, "w", encoding="utf-8") as f:
                json.dump(m, f, indent=2)
                f.write("\n")
        elif a.cmd == "rewrite-entry":
            rewrite_entry(a.manifest, a.file, a.src, a.signed)
        elif a.cmd == "body":
            with open(a.notes, encoding="utf-8") as f:
                notes = f.read()
            ti = None
            if a.tester_instructions:
                with open(a.tester_instructions, encoding="utf-8") as f:
                    ti = f.read()
            sys.stdout.write(release_body(notes, load(a.manifest), ti, a.anchor, a.tag_kind))
        else:
            ap.print_usage(sys.stderr)
            return 2
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as e:
        print(f"release_manifest: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
