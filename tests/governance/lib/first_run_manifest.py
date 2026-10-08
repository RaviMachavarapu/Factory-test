"""test_first_run.sh's manifest helper (REQ-352, REQ-305): DIST/manifest.json verifies for VERSION.

    python3 first_run_manifest.py DIST VERSION SUFFIX [PARTS]

Every entry's sha256 and size must match its file under DIST. Schema 1 ({version, artifacts: [{filename, sha256, size}]},
no `schema` key): exactly one artifact, ending in SUFFIX. Schema 2 (`specflow-manifest/2`, written by
release_manifest.py write): exactly one `bundle` entry, ending in SUFFIX, whose `signed` is the top-level one; under
PARTS=all (the hooks' default RELEASE_PARTS) also exactly one reproducible `source-archive` entry and a non-null
source_date_epoch and tree; under PARTS=bundle nothing else. Exit 0 when it verifies, 1 (with the reason) when not.
"""

import hashlib
import json
import os
import sys

SCHEMA2 = "specflow-manifest/2"


def _verify(d, a):
    p = os.path.join(d, a["filename"])
    if os.path.basename(a["filename"]) != a["filename"] or not os.path.isfile(p):
        return f"{a['filename']}: no such file in {d}"
    with open(p, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    if sha != a["sha256"] or os.path.getsize(p) != a["size"]:
        return f"{a['filename']}: sha256 or size does not match its entry"
    return None


def check(d, version, suffix, parts="all"):
    if parts not in ("all", "bundle"):
        return f"PARTS must be all or bundle, not {parts!r}"
    with open(os.path.join(d, "manifest.json"), encoding="utf-8") as f:
        m = json.load(f)
    if m.get("version") != version:
        return f"version {m.get('version')!r}, expected {version!r}"
    arts = m.get("artifacts") or []
    for a in arts:
        err = _verify(d, a)
        if err:
            return err
    if "schema" not in m:  # schema 1
        if len(arts) != 1 or not arts[0]["filename"].endswith(suffix):
            return f"schema 1: expected exactly one artifact ending in {suffix}: {arts}"
        return None
    if m["schema"] != SCHEMA2:
        return f"unknown schema {m['schema']!r}"
    bundles = [a for a in arts if a.get("kind") == "bundle"]
    if len(bundles) != 1 or not bundles[0]["filename"].endswith(suffix):
        return f"schema 2: expected exactly one bundle entry ending in {suffix}: {arts}"
    if m.get("signed") is not bundles[0].get("signed"):
        return f"schema 2: top-level signed {m.get('signed')!r} is not the bundle's {bundles[0].get('signed')!r}"
    others = [a for a in arts if a is not bundles[0]]
    if parts == "bundle":
        if others:
            return f"schema 2 (bundle): unexpected entries {others}"
        return None
    srcs = [
        a
        for a in others
        if a.get("kind") == "source-archive" and a.get("reproducible") is True
    ]
    if len(srcs) != 1 or len(others) != 1:
        return f"schema 2 (all): expected the bundle and exactly one reproducible source-archive entry: {arts}"
    if m.get("source_date_epoch") is None or not m.get("tree"):
        return "schema 2 (all): source_date_epoch and tree must be set"
    return None


def main(argv):
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    err = check(*argv)
    if err:
        print(f"first_run_manifest: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
