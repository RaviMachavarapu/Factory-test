#!/usr/bin/env bash
# REQ-384, REQ-305 (P6 R18): manifest schema 2 — every artifact with kind and reproducible, a bundle with signed — the
# reproducible subset the notes transcribe, the epoch from the notes' date: (the same at the ship PR's head and at the
# tag, whatever the merge), a deterministic sdist repack; a schema-1 manifest still reads, every entry reproducible.
# Covers: REQ-384
# Covers: REQ-305
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
LIB="$ROOT/scripts/lib/specflow"; M="$LIB/release_manifest.py"
mkdir -p "$W/d"; printf a > "$W/d/x-1.0.0-source.tar"; printf bb > "$W/d/x.dmg"
printf -- '---\nversion: 1.0.0\ndate: 2026-10-05\n---\n# Notes\n' > "$W/notes.md"
ck "epoch: 00:00:00 UTC of the notes' date: (2026-10-05 → 1791158400)" [ "$(python3 "$M" epoch --notes "$W/notes.md")" = 1791158400 ]
printf -- '---\nversion: 1.0.0\n---\n' > "$W/nodate.md"
ck "epoch: notes without a date: exit 2" bash -c 'python3 "$1" epoch --notes "$2" >/dev/null 2>&1; [ $? = 2 ]' _ "$M" "$W/nodate.md"
python3 - "$LIB" "$W/d" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
m.write(sys.argv[2], "1.0.0", "tauri", 1791158400, "a" * 40,
        [("x-1.0.0-source.tar", "source-archive", True), ("x.dmg", "bundle", False, False)])
PY
ck "write: schema 2 with kind, reproducible and the bundle's signed; the top-level signed is the bundle's" python3 - "$W/d/manifest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "specflow-manifest/2" and d["stack"] == "tauri" and d["source_date_epoch"] == 1791158400 and d["tree"] == "a" * 40, d
by = {a["filename"]: a for a in d["artifacts"]}
assert by["x-1.0.0-source.tar"]["kind"] == "source-archive" and by["x-1.0.0-source.tar"]["reproducible"] is True, by
assert by["x.dmg"]["reproducible"] is False and by["x.dmg"]["signed"] is False and d["signed"] is False, d
assert by["x.dmg"]["size"] == 2 and len(by["x.dmg"]["sha256"]) == 64, by
assert [a["filename"] for a in d["artifacts"]] == sorted(by), d
PY
python3 "$M" rows --manifest "$W/d/manifest.json" > "$W/rows"
ck "rows: only the reproducible entries, in the notes' table shape — the bundle is never transcribed" \
  bash -c 'grep -qE "^\| \`x-1\.0\.0-source\.tar\` \| \`[0-9a-f]{64}\` \| 1 \|$" "$1" && ! grep -qF "x.dmg" "$1"' _ "$W/rows"
printf '{"version": "0.0.1", "artifacts": [{"filename": "a.tar.gz", "sha256": "%s", "size": 1}]}\n' "$(printf '0%.0s' $(seq 64))" > "$W/v1.json"
ck "a schema-1 manifest still reads, every entry reproducible" bash -c 'python3 "$1" rows --manifest "$2" | grep -qF "a.tar.gz"' _ "$M" "$W/v1.json"
mk() { python3 - "$1" "$2" <<'PY'
import io, sys, tarfile, time
out, salt = sys.argv[1], int(sys.argv[2])
with tarfile.open(out, "w:gz") as t:
    for name in (["p-1.0/b.py", "p-1.0/a.py"] if salt else ["p-1.0/a.py", "p-1.0/b.py"]):
        data = name.encode(); i = tarfile.TarInfo(name); i.size = len(data)
        i.mtime = int(time.time()) + salt; i.uid = 501 + salt; i.uname = "u%d" % salt
        t.addfile(i, io.BytesIO(data))
PY
}
mk "$W/s1.tar.gz" 0; sleep 1; mk "$W/s2.tar.gz" 7
python3 - "$LIB" "$W" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
for n in ("1", "2"): m.repack_sdist(f"{sys.argv[2]}/s{n}.tar.gz", f"{sys.argv[2]}/r{n}.tar.gz", 1791158400)
PY
ck "repack_sdist: the same members with other mtimes, owners and order repack byte-identically (R18 (c))" cmp -s "$W/r1.tar.gz" "$W/r2.tar.gz"
ck "…every member's mtime is the epoch, uid and gid 0, no owner name" python3 - "$W/r1.tar.gz" <<'PY'
import sys, tarfile
for m in tarfile.open(sys.argv[1]).getmembers():
    assert (m.mtime, m.uid, m.gid, m.uname, m.gname) == (1791158400, 0, 0, "", ""), m
PY
ck "the hook contract names RELEASE_PARTS, RELEASE_COMMIT, SOURCE_DATE_EPOCH from the notes' date:, the committed tree and schema 2" \
  bash -c 'for w in RELEASE_PARTS RELEASE_COMMIT SOURCE_DATE_EPOCH "notes'"'"' date:" "git archive" "specflow-manifest/2" reproducible; do grep -qF -- "$w" "$1" || exit 1; done' _ "$ROOT/scripts/release-stack.sh.template"
S="$W/stub"; git init -q -b main "$S"; (cd "$S" && cp "$ROOT/scripts/release-stack.sh.template" hook.sh && mkdir -p scripts && cp -R "$ROOT/scripts/lib" scripts/ \
  && find scripts -name __pycache__ -prune -exec rm -rf {} + && git add -A && git commit -qm base)
rc=0; (cd "$S" && VERSION=1.0.0 DIST_DIR="$W/sd" bash hook.sh) >/dev/null 2>&1 || rc=$?
ck "the contract's stub enforces the epoch rule: no notes, no SOURCE_DATE_EPOCH → exit 2 (F24)" [ "$rc" = 2 ]
(cd "$S" && SOURCE_DATE_EPOCH=1791158400 VERSION=1.0.0 DIST_DIR="$W/sd" bash hook.sh) >/dev/null
ck "…with SOURCE_DATE_EPOCH: one reproducible source-archive of the committed tree, no version.txt (schema 2's four kinds)" python3 - "$W/sd/manifest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert [(a["filename"], a["kind"], a["reproducible"]) for a in d["artifacts"]] == [("stub-1.0.0-source.tar", "source-archive", True)], d
PY
hk() { rm -rf "$W/$1"; (cd "$S" && SOURCE_DATE_EPOCH=1791158400 VERSION=1.0.0 DIST_DIR="$W/$1" bash hook.sh >/dev/null 2>&1); shasum -a 256 "$W/$1/stub-1.0.0-source.tar" | cut -d' ' -f1; }
H1="$(hk h1)"; H2="$(hk h2)"
ck "reproducible: the stub's archive built twice has one sha256" bash -c '[ -n "$1" ] && [ "$1" = "$2" ]' _ "$H1" "$H2"
(cd "$S" && mkdir -p docs/releases docs/security && echo n > docs/releases/1.0.0-notes.md && echo r > docs/security/1.0.0-review.md && git add docs && git commit -qm "docs only")
H3="$(hk h3)"
ck "…and after a docs-only commit (docs/releases, docs/security): the same sha256, the records are excluded (R18 (i), (ii))" [ "$H3" = "$H1" ]
(cd "$S" && git config tar.umask 0002 && git config core.autocrlf true); H4="$(hk h4)"
ck "…and with a machine's tar.umask 0002 and core.autocrlf true: the same sha256 (R18 pins both)" [ "$H4" = "$H1" ]
# Fix wave 1 (REQ-384): the contract's stub, too, names a RELEASE_COMMIT that is no commit here (exit 2).
# Covers: REQ-384
rc=0; o=$(cd "$S" && RELEASE_COMMIT=0123456789abcdef0123456789abcdef01234567 VERSION=1.0.0 DIST_DIR="$W/sx" bash hook.sh 2>&1) || rc=$?
ck "the stub: RELEASE_COMMIT naming no commit → exit 2, 'is not a commit in this repository'" \
  bash -c '[ "$1" = 2 ] && grep -qF "RELEASE_COMMIT 0123456789abcdef0123456789abcdef01234567 is not a commit in this repository (SPECFLOW_HEAD_SHA set wrongly?)" <<<"$2"' _ "$rc" "$o"
# Task 3.4 (REQ-384, REQ-386; P6 R33, R35): assemble, rewrite-entry and body arrive test-first here (Build 2 shipped only
# epoch and rows). assemble merges the source part and at most one bundle part into the Release's manifest — tag, commit,
# run, image — and refuses two versions or two bundle entries; a subcommand with no arguments is exit 2, usage.
# Covers: REQ-384
for c in assemble rewrite-entry body; do
  ck "release_manifest.py $c with no arguments: exit 2, usage" bash -c 'python3 "$1" "$2" >/dev/null 2>&1; [ $? = 2 ]' _ "$M" "$c"
done
mkdir -p "$W/as/src" "$W/as/b1" "$W/as/b2"; printf s > "$W/as/src/p.tar"; printf b > "$W/as/b1/x.dmg"; printf c > "$W/as/b2/y.dmg"
python3 - "$LIB" "$W/as" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
r = sys.argv[2]
m.write(r + "/src", "1.0.0", "tauri", 1791158400, "a" * 40, [("p.tar", "source-archive", True)])
m.write(r + "/b1", "1.0.0", "tauri", 1791158400, "a" * 40, [("x.dmg", "bundle", False, True)])
m.write(r + "/b2", "1.0.0", "tauri", 1791158400, "a" * 40, [("y.dmg", "bundle", False, False)])
PY
python3 "$M" assemble --out "$W/as/out.json" --tag v1.0.0 --commit "$(printf 'c%.0s' $(seq 40))" --run 12 "$W/as/src/manifest.json" "$W/as/b1/manifest.json"
ck "assemble: the source entry and the one bundle entry, the tag, commit and run recorded, signed taken from the bundle" python3 - "$W/as/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["tag"] == "v1.0.0" and d["commit"] == "c" * 40 and d["run"] == "12" and d["signed"] is True and d["version"] == "1.0.0", d
assert [a["filename"] for a in d["artifacts"]] == ["p.tar", "x.dmg"] and "image" not in d, d
PY
ck "assemble: two bundle entries are refused (the caller passes the signed part in place of the unsigned one): exit 2" \
  bash -c 'python3 "$1" assemble --out "$2/o2.json" --tag v1.0.0 --commit "$3" --run 1 "$2/src/manifest.json" "$2/b1/manifest.json" "$2/b2/manifest.json" >/dev/null 2>&1; [ $? = 2 ] && [ ! -e "$2/o2.json" ]' _ "$M" "$W/as" "$(printf 'c%.0s' $(seq 40))"
python3 - "$W/as/src/manifest.json" "$W/as/other.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d["version"] = "0.9.0"; json.dump(d, open(sys.argv[2], "w"))
PY
ck "assemble: parts of two versions are refused: exit 2" \
  bash -c 'python3 "$1" assemble --out "$2/o3.json" --tag v1.0.0 --commit "$3" --run 1 "$2/src/manifest.json" "$2/other.json" >/dev/null 2>&1; [ $? = 2 ]' _ "$M" "$W/as" "$(printf 'c%.0s' $(seq 40))"
ck "assemble: a commit that is not 40 hex is refused: exit 2" \
  bash -c 'python3 "$1" assemble --out "$2/o4.json" --tag v1.0.0 --commit abc --run 1 "$2/src/manifest.json" >/dev/null 2>&1; [ $? = 2 ]' _ "$M" "$W/as"

# Task 3.4 (REQ-384, REQ-351, REQ-386; P6 R31, R33, R35): the Release body is the tagged notes, a manifest.json line and
# how to verify the release offline against allowed_signers at the anchor; an Image: line when the manifest records an
# image; the tester instructions when its signed is false — rendered from the manifest's entries, never from the stack.
# Covers: REQ-384
# Covers: REQ-351
python3 "$M" body --notes "$W/notes.md" --manifest "$W/d/manifest.json" --anchor v0.9.0 --tag-kind ssh-good > "$W/body.md"
ck "body: the notes' text, without their frontmatter, and a link line to manifest.json" \
  bash -c 'grep -qx "# Notes" "$1" && ! grep -qx "date: 2026-10-05" "$1" && grep -qF "manifest.json" "$1"' _ "$W/body.md"
ck "body: '## Verify this release' names the anchor and the offline verify-tag command (R31)" \
  bash -c 'grep -qx "## Verify this release" "$1" && grep -qF "v0.9.0" "$1" && grep -qF "git -c gpg.ssh.allowedSignersFile=" "$1" && grep -qF "verify-tag v1.0.0" "$1"' _ "$W/body.md"
# Fix wave 1, F (REQ-384, REQ-383): with no anchor (release.yml's anchor step reports '-'), the tag passed only as an
# annotated tag with its fallback recorded: the body says so, honestly, and gives no verify command — never "trust on
# first use", never a command that checks the tag against the tag's own key file.
# Covers: REQ-384
for a in "-" ""; do
  python3 "$M" body --notes "$W/notes.md" --manifest "$W/d/manifest.json" ${a:+--anchor "$a"} --tag-kind unsigned > "$W/body-noanchor.md"
  ck "body with no anchor (--anchor '${a:-<none>}'): annotated, the fallback recorded, no signature to verify; no verify-tag, no TOFU, no self-certifying git show" \
    bash -c 'grep -qx "## Verify this release" "$1" && grep -qF "annotated" "$1" && grep -qF "fallback" "$1" && grep -qF "no signature to verify" "$1" && grep -qF "1.0.0-known-limitations.md" "$1" && ! grep -qF "verify-tag" "$1" && ! grep -qiF "trust on first use" "$1" && ! grep -qF "git show v1.0.0:" "$1"' _ "$W/body-noanchor.md"
done
# Wave 1 round 2 (REQ-350, REQ-383; P6 R31): the text follows the TAG's own verdict (release.yml's verify job, signers.py
# verify), never the mere existence of an anchor — a TOFU anchor exists once allowed_signers lists a key, yet an
# annotated, unsigned tag with its fallback recorded passes --at-tag. With an anchor and an unsigned tag the body says the
# tag is annotated and gives no verify-tag command (which would fail for that tag); ssh-good without an anchor, a missing
# --tag-kind, or any other verdict (gpg-good, unlisted) is bad input: exit 2, no body.
# Covers: REQ-350
# Covers: REQ-384
python3 "$M" body --notes "$W/notes.md" --manifest "$W/d/manifest.json" --anchor v1.1.0 --tag-kind unsigned > "$W/body-anchor-unsigned.md" 2>/dev/null || true
ck "body with an anchor (v1.1.0) and an unsigned tag: annotated, the fallback recorded, no signature to verify — never 'verified against', never verify-tag" \
  bash -c 'grep -qx "## Verify this release" "$1" && grep -qF "annotated" "$1" && grep -qF "no signature to verify" "$1" && grep -qF "1.0.0-known-limitations.md" "$1" && ! grep -qF "verify-tag" "$1" && ! grep -qF "verified against" "$1" && ! grep -qF "allowedSignersFile" "$1"' _ "$W/body-anchor-unsigned.md"
ck "release_body (the function): unsigned with an anchor → the annotated text; ssh-good with one → the verify-tag text; no verdict, gpg-good, or ssh-good without an anchor → ValueError" \
  python3 - "$LIB" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
man = {"version": "1.1.0", "tag": "v1.1.0", "artifacts": [], "signed": None}
b = m.release_body("# N\n", man, anchor="v1.0.0", tag_kind="unsigned")
assert "verify-tag" not in b and "verified against" not in b and "no signature to verify" in b, b
b = m.release_body("# N\n", man, anchor="v1.0.0", tag_kind="ssh-good")
assert "verify-tag v1.1.0" in b and "git show v1.0.0:.github/allowed_signers" in b, b
for kw in ({"anchor": "v1.0.0"}, {"anchor": "v1.0.0", "tag_kind": "gpg-good"}, {"anchor": "-", "tag_kind": "ssh-good"},
           {"anchor": None, "tag_kind": "ssh-good"}):
    try:
        m.release_body("# N\n", man, **kw)
    except ValueError:
        continue
    raise AssertionError(f"release_body accepted {kw}")
PY
for x in "--anchor v0.9.0" "--anchor v0.9.0 --tag-kind gpg-good" "--anchor v0.9.0 --tag-kind unlisted" "--anchor - --tag-kind ssh-good" "--tag-kind ssh-good"; do
  rc=0; python3 "$M" body --notes "$W/notes.md" --manifest "$W/d/manifest.json" $x > "$W/body-bad.md" 2>/dev/null || rc=$?
  ck "body $x: exit 2, no body (the text follows only a verdict release.yml accepts: ssh-good with its anchor, or unsigned)" \
    bash -c '[ "$1" = 2 ] && [ ! -s "$2" ]' _ "$rc" "$W/body-bad.md"
done
python3 - "$W/d/manifest.json" "$W/dimg.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d["image"] = {"name": "ghcr.io/o/r", "tag": "1.0.0", "digest": "sha256:" + "e" * 64}
json.dump(d, open(sys.argv[2], "w"))
PY
ck "body: with an image, an 'Image: ghcr.io/o/r:1.0.0@sha256:…' line (REQ-351: the digest in the Release body)" \
  bash -c 'python3 "$1" body --notes "$2" --manifest "$3" --tag-kind unsigned | grep -qxE "Image: ghcr\.io/o/r:1\.0\.0@sha256:e{64}"' _ "$M" "$W/notes.md" "$W/dimg.json"
ck "…and without one, no Image line" bash -c '! python3 "$1" body --notes "$2" --manifest "$3" --tag-kind unsigned | grep -q "^Image: "' _ "$M" "$W/notes.md" "$W/d/manifest.json"
printf '# Opening an unsigned app\n\nOpen Anyway\n' > "$W/ti.md"
ck "body: signed false → the tester instructions under '## Opening this unsigned app' (REQ-386)" \
  bash -c 'python3 "$1" body --notes "$2" --manifest "$3" --tag-kind unsigned --tester-instructions "$4" | grep -qx "## Opening this unsigned app"' _ "$M" "$W/notes.md" "$W/d/manifest.json" "$W/ti.md"
mkdir -p "$W/rw"; printf old > "$W/rw/x.dmg"; printf 'signed-bytes' > "$W/new.dmg"
python3 - "$LIB" "$W/rw" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import release_manifest as m
m.write(sys.argv[2], "1.0.0", "tauri", 1791158400, "a" * 40, [("x.dmg", "bundle", False, False)])
PY
python3 "$M" rewrite-entry --manifest "$W/rw/manifest.json" --file x.dmg --from "$W/new.dmg" --signed
ck "rewrite-entry: the re-signed bundle replaces the entry's file, its sha256 and size recomputed, signed true everywhere (R33)" \
  python3 - "$W/rw" "$W/new.dmg" <<'PY'
import hashlib, json, os, sys
d = json.load(open(sys.argv[1] + "/manifest.json")); b = [a for a in d["artifacts"] if a["filename"] == "x.dmg"][0]
assert open(sys.argv[1] + "/x.dmg", "rb").read() == b"signed-bytes", "the entry's file is the signed one"
assert b["sha256"] == hashlib.sha256(b"signed-bytes").hexdigest() and b["size"] == len(b"signed-bytes"), b
assert b["signed"] is True and d["signed"] is True, d
PY
ck "body: signed true → no tester instructions" \
  bash -c '! python3 "$1" body --notes "$2" --manifest "$3" --tag-kind unsigned --tester-instructions "$4" | grep -qx "## Opening this unsigned app"' _ "$M" "$W/notes.md" "$W/rw/manifest.json" "$W/ti.md"

finish test_release_manifest
