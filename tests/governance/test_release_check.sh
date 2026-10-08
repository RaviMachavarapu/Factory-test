#!/usr/bin/env bash
# REQ-350 (P6 R11, R28): attestation.py release-check judges every first-parent commit of main since the previous
# release through pr_attestation — the CI check's own classifier, the Dependabot exemption included — accepting an
# APPROVE, a waiver or the exemption; listing the root commit and PRs merged onto a base that predates attestation.py;
# accepting a direct push only inside the doc-only minor exception (no code, no phase artifact, no constitution.md) or
# under a maintainer's waiver on the commit; a PR-judged commit must carry exactly its reviewed head merged onto its
# parent; the range starts at the newest earlier release whose GitHub Release is published. REQ-311: one classifier.
# REQ-334: a Dependabot PR is attested by the same rule that let it merge — and a direct push never by that exemption.
# Covers: REQ-350
# Covers: REQ-311
# Covers: REQ-334
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
A="$ROOT/scripts/lib/specflow/attestation.py"; R="$W/r"; F="$W/fx"; mkdir -p "$F/comments" "$F/commits"
git init -q -b main "$R"
c() { (cd "$R" && eval "$1" && git add -A && git commit -qm "$2" && git rev-parse HEAD); }
# git merge --squash prints "Squash commit -- not updating HEAD" on stdout even with -q (measured, F4): silenced, so the
# function's output is the commit id alone
squash() { (cd "$R" && git checkout -qb "$1" && eval "$2" && git add -A && git commit -qm "$1 head" && git checkout -q main \
  && git merge -q --squash "$1" >/dev/null && git commit -qm "$1 (squash)" && git rev-parse HEAD); }
C0=$(c 'echo root > README.md' "init's first commit")
C1=$(c 'echo old > old.sh' "PR #1, before attestation existed")
C2=$(c 'mkdir -p scripts .claude/skills && cp -R "$ROOT/scripts/lib" scripts/ && cp -R "$ROOT/.claude/skills/verifier" .claude/skills/ && cp "$ROOT/constitution.md" . && printf "requests==2.32.3\n" > requirements.txt && mkdir -p docs/releases && printf -- "---\nversion: 0.9.0\ndate: 2026-09-01\n---\n" > docs/releases/0.9.0-notes.md' "PR #2 lands attestation.py (and 0.9.0's notes)")
C3=$(squash pr3 'echo tool > tool.sh'); H3=$(git -C "$R" rev-parse pr3)
C4=$(c 'mkdir -p docs && printf "# Guide\n" > docs/guide.md' "direct push: a document")
C5=$(squash pr5 'printf "requests==2.32.4\n" > requirements.txt'); H5=$(git -C "$R" rev-parse pr5)   # its authorship is the commits fixture's
python3 - "$ROOT/scripts/lib/specflow" "$R" "$F" "$C2" "$H3" "$H5" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); os.chdir(sys.argv[2]); import attestation as a
F, base, h3, h5 = sys.argv[3:7]
tail = "## SpecFlow verifier (code mode)\n\nNo findings.\nAPPROVE"
mk = a.make_marker(mode="code", sha=h3, base=base, prompt_sha256=a.prompt_hash(base), model="opus", verdict="APPROVE",
                   digest=a.digest(tail), origin="headless")
json.dump([{"id": 1, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T10:00:00Z",
            "updated_at": "2026-10-01T10:00:00Z", "html_url": "https://github.com/o/r/pull/3#issuecomment-1",
            "body": mk + "\n" + tail}], open(f"{F}/comments/3.json", "w"))
json.dump([{"sha": h3, "author": {"login": "alice"}, "committer": {"login": "alice"},
            "commit": {"verification": {"verified": False}}}], open(f"{F}/commits/3.json", "w"))
json.dump([{"sha": h5, "author": {"login": "dependabot[bot]"}, "committer": {"login": "web-flow"},
            "commit": {"verification": {"verified": True}}}], open(f"{F}/commits/5.json", "w"))
json.dump([], open(f"{F}/comments/5.json", "w"))
PY
prs() { python3 -c 'import json, sys; a = sys.argv[1:]; print(json.dumps({a[i]: (None if a[i + 1] == "-" else {"number": int(a[i + 1]), "head": a[i + 2], "author": a[i + 3]}) for i in range(0, len(a), 4)}))' "$@" > "$F/prs.json"; }
prs "$C0" - - - "$C1" 1 "$C1" alice "$C2" 2 "$C2" alice "$C3" 3 "$H3" alice "$C4" - - - "$C5" 5 "$H5" "dependabot[bot]"
mkdir -p "$W/ghbin" "$W/ghfx"; export GHFX="$W/ghfx"
cat > "$W/ghbin/gh" <<EOF
#!/bin/sh
echo "\$@" >> "$W/gh.log"
for a in "\$@"; do ep="\$a"; done
f="\${GHFX:-/nonexistent}/\$(printf '%s' "\$ep" | tr / _).json"
if [ -f "\$f.err" ]; then cat "\$f.err" >&2; exit 1; fi
if [ -f "\$f" ]; then cat "\$f"; exit 0; fi
case "\$ep" in repos/*/releases/tags/*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;; esac
echo "[]"
EOF
chmod +x "$W/ghbin/gh"
echo '{}' > "$F/perm.json"
rch() { rc=0; out=$(cd "$R" && PATH="$W/ghbin:$PATH" python3 "$A" release-check --repo o/r --version 1.0.0 --base-ref main --tag-commit "$1" --prs "$F/prs.json" --comments-dir "$F/comments" \
  --commits-dir "$F/commits" --permissions "$F/perm.json" 2>&1) || rc=$?; }
rch "$C5"
ck "release-check: the root commit and the PRs onto a pre-attestation base are listed, not judged" \
  bash -c 'grep -q "^skip ${2:0:7} root" <<<"$1" && grep -q "^skip ${3:0:7} predates-attestation" <<<"$1" && grep -q "^skip ${4:0:7} predates-attestation" <<<"$1"' _ "$out" "$C0" "$C1" "$C2"
ck "…PR #3's APPROVE for its merged head, against its merge parent's prompt hash: ok" grep -q "^ok #3 approve ${C3:0:7}" <<<"$out"
ck "…a direct push of a plain document (docs/guide.md): ok (the minor exception)" grep -q "^ok ${C4:0:7} direct-push documents-only" <<<"$out"
ck "…Dependabot's version-only PR #5 is attested by the same exemption rule, with no marker (REQ-334)" grep -q "^ok #5 exempt-dependabot ${C5:0:7}" <<<"$out"
ck "…all accepted: exit 0" [ "$rc" = 0 ]
rch "$H3"
ck "release-check: a --tag-commit that is not a first-parent commit of main (PR #3's unmerged head): FAIL tag-commit-off-main, exit 1, before any walk (PR #52 run 1, finding 3)" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} tag-commit-off-main" <<<"$2" && ! grep -qE "^(ok|skip) " <<<"$2"' _ "$rc" "$out" "$H3"
C6=$(c 'echo code > other.sh' "direct push: code"); prs "$C0" - - - "$C1" 1 "$C1" alice "$C2" 2 "$C2" alice "$C3" 3 "$H3" alice "$C4" - - - "$C5" 5 "$H5" "dependabot[bot]" "$C6" - - -
rch "$C6"
ck "release-check: a direct push touching a code path FAILs, naming the path: exit 1" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: other.sh" <<<"$2"' _ "$rc" "$out" "$C6"
# R28's remedy: a maintainer waiver posted as a comment on the pushed commit, judged by the same classifier.
python3 - "$F" "$C6" <<'PY'
import json, sys
F, c6 = sys.argv[1:3]
body = f"<!-- specflow-verifier:waive sha:{c6} -->\nPushed past protection during an outage; reviewed after the fact by the maintainer."
json.dump([{"id": 9, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T11:00:00Z",
            "updated_at": "2026-10-01T11:00:00Z", "html_url": f"https://github.com/o/r/commit/{c6}#commitcomment-9", "body": body}],
          open(f"{F}/comments/commit-{c6}.json", "w"))
json.dump([{"sha": c6, "author": {"login": "alice"}, "committer": {"login": "alice"},
            "commit": {"verification": {"verified": False}}}], open(f"{F}/commits/commit-{c6}.json", "w"))
PY
rch "$C6"
ck "…a maintainer waiver on that commit clears it: ok direct-push waiver, exit 0 (R28's remedy; one classifier; labelled by what was accepted)" \
  bash -c '[ "$1" = 0 ] && grep -q "^ok ${3:0:7} direct-push waiver" <<<"$2"' _ "$rc" "$out" "$C6"
python3 - "$F" "$C6" <<'PY'
import json, sys
F, c6 = sys.argv[1:3]; p = f"{F}/comments/commit-{c6}.json"; c = json.load(open(p))
c[0]["author_association"] = "NONE"; json.dump(c, open(p, "w"))
PY
rch "$C6"
ck "…a waiver from a non-maintainer does not: the FAIL stands, exit 1" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: other.sh" <<<"$2"' _ "$rc" "$out" "$C6"
rm -f "$F/comments/commit-$C6.json" "$F/commits/commit-$C6.json"
# P7 R4 (REQ-382, REQ-311): a commit-level waiver has no timeline; a bound one is judged by the base rule against the
# commit's first parent — naming the parent passes, naming another commit is refused; a legacy one passes as before.
# Covers: REQ-382
cw() { python3 - "$F" "$C6" "$1" <<'PY'
import json, sys
F, c6, base = sys.argv[1:4]
line = f"<!-- specflow-verifier:waive sha:{c6}" + (f" base:{base}" if base != "-" else "") + " -->"
json.dump([{"id": 9, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T11:00:00Z",
            "updated_at": "2026-10-01T11:00:00Z", "html_url": f"https://github.com/o/r/commit/{c6}#commitcomment-9",
            "body": line + "\nPushed past protection during an outage; reviewed after the fact by the maintainer."}],
          open(f"{F}/comments/commit-{c6}.json", "w"))
json.dump([{"sha": c6, "author": {"login": "alice"}, "committer": {"login": "alice"}, "commit": {"verification": {"verified": False}}}],
          open(f"{F}/commits/commit-{c6}.json", "w"))
PY
}
cw "$C5"; rch "$C6"
ck "a bound waiver on the pushed commit naming its first parent: ok direct-push waiver" bash -c '[ "$1" = 0 ] && grep -q "^ok ${3:0:7} direct-push waiver" <<<"$2"' _ "$rc" "$out" "$C6"
cw "$C4"; rch "$C6"
ck "…naming another commit (an older first-parent commit): FAIL direct-push, waiver-base-mismatch" bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push .*waiver-base-mismatch" <<<"$2"' _ "$rc" "$out" "$C6"
cw -; rch "$C6"
ck "…a legacy waiver on the commit: ok, and no timeline is read for a commit" bash -c '[ "$1" = 0 ] && ! grep -q "/timeline" "$3"' _ "$rc" "$out" "$W/gh.log"
rm -f "$F/comments/commit-$C6.json" "$F/commits/commit-$C6.json"
# P7 R4, the remedy (fresh-eyes review, finding 15): a merged PR whose legacy waiver precedes a retarget FAILs, naming the
# remedy; a bound waiver posted on that PR naming the merge's first parent clears it.
python3 - "$F" "$H3" <<'PY'
import json, sys
F, h3 = sys.argv[1:3]
json.dump([{"id": 3, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T10:00:00Z",
            "updated_at": "2026-10-01T10:00:00Z", "html_url": "https://github.com/o/r/pull/3#issuecomment-3",
            "body": f"<!-- specflow-verifier:waive sha:{h3} -->\nReviewed by hand: a maintainer-decided waiver."}], open(f"{F}/comments/3.json", "w"))
PY
printf '[{"event": "base_ref_changed", "created_at": "2026-10-01T11:00:00Z"}]\n' > "$GHFX/repos_o_r_issues_3_timeline.json"; rch "$C5"
ck "a merged PR whose legacy waiver precedes a retarget: FAIL #3 none (waiver-unbound-retargeted), naming the bound-waiver remedy with the merge's parent" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL #3 none (waiver-unbound-retargeted)" <<<"$2" && grep -qF "remedy" <<<"$2" && grep -qF "base:$3" <<<"$2"' _ "$rc" "$out" "$C2"
python3 - "$F" "$H3" "$C2" <<'PY'
import json, sys
F, h3, parent = sys.argv[1:4]; p = f"{F}/comments/3.json"; c = json.load(open(p))
c.append({"id": 4, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-06T10:00:00Z",
          "updated_at": "2026-10-06T10:00:00Z", "html_url": "https://github.com/o/r/pull/3#issuecomment-4",
          "body": f"<!-- specflow-verifier:waive sha:{h3} base:{parent} -->\nRe-waived after the retarget: the merged diff was re-read."})
json.dump(c, open(p, "w"))
PY
rch "$C5"
ck "…a bound waiver on PR #3 naming its merge's first parent clears it: ok #3 waiver" bash -c '[ "$1" = 0 ] && grep -q "^ok #3 waiver" <<<"$2"' _ "$rc" "$out"
rm -f "$GHFX/repos_o_r_issues_3_timeline.json"
echo '[]' > "$F/comments/3.json"; rch "$C5"
ck "release-check: PR #3 with no marker FAILs as none: exit 1" bash -c '[ "$1" = 1 ] && grep -q "^FAIL #3 none" <<<"$2"' _ "$rc" "$out"
# (final review, finding 17) the range starts at the newest earlier release tag whose GitHub Release is published: a tag
# whose own release.yml run refused (no Release, or a draft) excuses nothing before it.
git -C "$R" tag -a v0.9.0 -m 0.9.0 "$C4"; RV="$W/ghfx/repos_o_r_releases_tags_v0.9.0.json"; rch "$C5"
ck "release-check --version 1.0.0, v0.9.0 tagged but no Release (gh: 404): walked through — PR #3 is judged (FAIL #3 none), exit 1" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL #3 none" <<<"$2" && grep -q "since the root" <<<"$2"' _ "$rc" "$out"
ck "…the Release was looked up read-only (gh api repos/o/r/releases/tags/v0.9.0)" grep -qF "repos/o/r/releases/tags/v0.9.0" "$W/gh.log"
printf '{"tag_name": "v0.9.0", "draft": true}\n' > "$RV"; rch "$C5"
ck "…a draft Release: walked through too (FAIL #3 none)" bash -c '[ "$1" = 1 ] && grep -q "^FAIL #3 none" <<<"$2"' _ "$rc" "$out"
printf '{"tag_name": "v0.9.0", "draft": false}\n' > "$RV"; rch "$C5"
ck "…a published Release: the walk starts at v0.9.0, so nothing before it — PR #3 included — is listed, exit 0 (F20)" \
  bash -c '[ "$1" = 0 ] && grep -q "^ok #5 " <<<"$2" && for s in "$3" "$4" "$5" "$6" "$7"; do ! grep -qF "${s:0:7}" <<<"$2" || exit 1; done' _ "$rc" "$out" "$C0" "$C1" "$C2" "$C3" "$C4"
rm -f "$RV"; echo "gh: HTTP 502 Bad Gateway" > "$RV.err"; rch "$C5"
ck "…a Release that cannot be read (gh fails, not a 404): exit 2 (fail closed)" [ "$rc" = 2 ]
rm -f "$RV.err"; git -C "$R" tag -d v0.9.0 >/dev/null; : > "$W/gh.log"
ck "release-check reduces PRs only through pr_attestation — never classify, _judge_comment or parse_marker (REQ-311)" python3 - "$A" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
fn = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "release_check")
called = {n.func.id for n in ast.walk(fn) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
assert "pr_attestation" in called and not called & {"classify", "_judge_comment", "_judge_all", "parse_marker"}, called
PY
# R28's decision (2026-10-01): attestation_since, read through packinfo at the tag's tree, lists every first-parent commit
# before it as pre-transfer (no gh call, never a FAIL); the boundary itself and later merges are judged.
echo '[]' > "$F/comments/3.json"   # PR #3 would FAIL if judged
prs "$C0" - - - "$C1" 1 "$C1" alice "$C2" 2 "$C2" alice "$C3" 3 "$H3" alice "$C4" - - - "$C5" 5 "$H5" "dependabot[bot]" "$C6" - - -
git -C "$R" rm -q -f other.sh && git -C "$R" commit -qm "drop other.sh" && C7=$(git -C "$R" rev-parse HEAD) && prs "$C0" - - - "$C1" 1 "$C1" alice "$C2" 2 "$C2" alice "$C3" 3 "$H3" alice "$C4" - - - "$C5" 5 "$H5" "dependabot[bot]" "$C6" - - - "$C7" - - -
# the template-source layout: scripts/template-pack.yml carries the key; committed at C7 (the tag commit)
setkey() { (cd "$R" && mkdir -p scripts && printf 'stack: template\nattestation_since: %s\n' "$1" > scripts/template-pack.yml && git add -A && git commit -qm "pack $1" && git rev-parse HEAD); }
C8=$(setkey "$C5")
prs "$C0" - - - "$C1" 1 "$C1" alice "$C2" 2 "$C2" alice "$C3" 3 "$H3" alice "$C4" - - - "$C5" 5 "$H5" "dependabot[bot]" "$C6" - - - "$C7" - - - "$C8" - - -
echo '{"alice": "admin"}' > "$F/perm.json"
rch "$C8"
ck "attestation_since: a commit before the boundary is listed 'skip … pre-transfer #<n>' (PR #3's FAIL is not judged); never a FAIL" \
  bash -c 'grep -q "^skip ${2:0:7} pre-transfer #3" <<<"$1" && ! grep -q "^FAIL #3" <<<"$1" && grep -q "^skip ${3:0:7} pre-transfer" <<<"$1"' _ "$out" "$C3" "$C4"
ck "…the boundary commit itself is judged (Dependabot's PR #5: ok), as is every later merge" \
  bash -c 'grep -q "^ok #5 exempt-dependabot ${2:0:7}" <<<"$1" && grep -q "^FAIL ${3:0:7} direct-push code: other.sh" <<<"$1"' _ "$out" "$C5" "$C6"
ck "…the summary counts pre-transfer separately" bash -c 'grep -q "pre-transfer [1-9]" <<<"$1"' _ "$out"
# (final review, findings 5, 19) introduced once, never moved: once an earlier release tag's tree carries the key, the
# tagged value must equal it.
git -C "$R" tag -a v0.9.0 -m 0.9.0 "$C8"; C8B=$(setkey "$C6"); rch "$C8B"
ck "attestation_since moved (C5 → C6) since v0.9.0, whose tree carries it: exit 2, naming the key and v0.9.0" \
  bash -c '[ "$1" = 2 ] && grep -q "attestation_since" <<<"$2" && grep -qF "v0.9.0" <<<"$2"' _ "$rc" "$out"
C8C=$(setkey "$C5"); rch "$C8C"
ck "…the same value as at v0.9.0: accepted (pre-transfer listed, no exit 2)" bash -c '[ "$1" != 2 ] && grep -q "^skip ${3:0:7} pre-transfer #3" <<<"$2"' _ "$rc" "$out" "$C3"
git -C "$R" tag -d v0.9.0 >/dev/null; : > "$W/gh.log"   # the Release lookups above were for v0.9.0, not a pre-transfer commit
# PR #56 verifier run 1, V2 (REQ-350; P6 R28): a pack that cannot be read at an earlier release tag (here v0.9.0's
# template-pack.yml has a line with no ':') is named on stderr — one line, the tag and the error — and the never-moves walk
# goes on to the next older tag that carries the key (v0.8.0 at C8, whose value is C5): a moved value still exits 2
# against v0.8.0, the same value is accepted. A tag with no pack file at all carries no key and is passed over silently.
git -C "$R" tag -a v0.8.0 -m 0.8.0 "$C8"
CM=$(c 'printf "stack: template\nnot a key line\n" > scripts/template-pack.yml && printf -- "---\nversion: 0.8.0\ndate: 2026-08-01\n---\n" > docs/releases/0.8.0-notes.md' "0.9.0's pack, unreadable")
git -C "$R" tag -a v0.9.0 -m 0.9.0 "$CM"
C8D=$(setkey "$C6"); rch "$C8D"
ck "an unreadable pack at v0.9.0: a one-line note names v0.9.0 and the walk goes on — C6 moved since v0.8.0 (C5): exit 2 naming v0.8.0" \
  bash -c '[ "$1" = 2 ] && [ "$(grep -c "^note: release-check: .*v0\.9\.0" <<<"$2")" = 1 ] && grep -qF "line has no" <<<"$2" && grep -q "moved since v0\.8\.0 " <<<"$2"' _ "$rc" "$out"
C8E=$(setkey "$C5"); rch "$C8E"
ck "…the same value as at v0.8.0: accepted, with the note on stderr (no exit 2)" \
  bash -c '[ "$1" != 2 ] && grep -q "^note: release-check: .*v0\.9\.0" <<<"$2" && grep -q "^skip ${3:0:7} pre-transfer #3" <<<"$2"' _ "$rc" "$out" "$C3"
ck "…and the note goes to stderr, never stdout (the report stays one line per commit)" \
  bash -c 'o=$(cd "$1" && PATH="$2:$PATH" python3 "$3" release-check --repo o/r --version 1.0.0 --base-ref main --tag-commit "$4" --prs "$5/prs.json" --comments-dir "$5/comments" --commits-dir "$5/commits" --permissions "$5/perm.json" 2>/dev/null); ! grep -q "^note:" <<<"$o"' _ "$R" "$W/ghbin" "$A" "$C8E" "$F"
git -C "$R" tag -d v0.8.0 >/dev/null; git -C "$R" tag -a v0.8.0 -m 0.8.0 "$C4"; rch "$C8E"
ck "…an earlier tag with no pack file (v0.8.0 at C4) carries no key: passed over with no note; only v0.9.0's unreadable pack is named" \
  bash -c '[ "$1" != 2 ] && [ "$(grep -c "^note: " <<<"$2")" = 1 ] && ! grep -q "^note: .*v0\.8\.0" <<<"$2"' _ "$rc" "$out"
git -C "$R" tag -d v0.8.0 v0.9.0 >/dev/null; : > "$W/gh.log"
# (fix wave 1, A7) the no-gh-call claim, measured: no --prs, --comments-dir, --commits-dir or --permissions, so every
# lookup goes through the stub gh, which records each call; the pre-transfer commits (C0-C4) must appear in none of them,
# and the post-boundary commit (C5, the boundary itself) must be looked up.
mkdir -p "$W/ghfx-empty"; : > "$W/gh.log"
rc=0; out=$(cd "$R" && GHFX="$W/ghfx-empty" PATH="$W/ghbin:$PATH" python3 "$A" release-check --repo o/r --version 1.0.0 --base-ref main --tag-commit "$C8C" 2>&1) || rc=$?
ck "release-check with no fixtures (every lookup through the recording stub gh): the pre-transfer commits are listed, never looked up; the post-boundary commit is" \
  bash -c 'grep -q "^skip ${3:0:7} pre-transfer" <<<"$2" && grep -qF "$4" "$1" && for s in "${@:5}"; do ! grep -qF "$s" "$1" || exit 1; done' _ "$W/gh.log" "$out" "$C3" "$C5" "$C0" "$C1" "$C2" "$C3" "$C4"
ck "…every gh call that names a commit names a post-boundary one" python3 - "$W/gh.log" "$C5" "$C6" "$C7" "$C8" "$C8B" "$C8C" <<'PY2'
import re, sys
post = set(sys.argv[2:]); lines = open(sys.argv[1]).read().splitlines()
named = [s for l in lines for s in re.findall(r"\b[0-9a-f]{40}\b", l)]
assert named and set(named) <= post, (named, post)
PY2
: > "$W/gh.log"
C9=$(setkey "$(printf 'z%.0s' $(seq 1 40))")
rch "$C9"
ck "attestation_since that is not 40 hex: exit 2 (fail closed)" bash -c '[ "$1" = 2 ]' _ "$rc"
C10=$(setkey "$H3")
rch "$C10"
ck "attestation_since off the first-parent chain (PR #3's unmerged head): exit 2" bash -c '[ "$1" = 2 ]' _ "$rc"
C11=$(c 'rm -rf scripts/template-pack.yml; mkdir -p .specflow && printf "stack: python\n" > .specflow/pack.yml; printf "stack: python\\n" > .specflow.yml' "an instance pack without the key")
rch "$C11"
ck "an instance's pack without the key: every merge is judged (nothing is pre-transfer)" bash -c '! grep -q "^skip .* pre-transfer" <<<"$1" && grep -q "^FAIL #3 none" <<<"$1"' _ "$out"
ck "…no gh call was made for any pre-transfer commit (the stub gh recorded none)" bash -c '[ ! -s "$1/gh.log" ]' _ "$W"
C12=$(c 'printf "stack: python\nattestation_since: %s\n" "$C5" > .specflow/pack.yml' "an instance pack that carries the key")
rch "$C12"
ck "an instance's pack carrying attestation_since: exit 2 — only the template source's pack may name a boundary" \
  bash -c '[ "$1" = 2 ] && grep -q "attestation_since" <<<"$2"' _ "$rc" "$out"
# --- Build 3 final review (REQ-350, REQ-311, REQ-334; P6 R28 as corrected; .claude/rules/review-gate.md's minor
# exception): the fixes are pinned below, each on a branch of its own so the main walk above stays as it was.
# Covers: REQ-350
# Covers: REQ-334
on_branch() { (cd "$R" && git checkout -q -B "$1" "$2"); }
rcb() {  # rcb BRANCH TAG-COMMIT [ARGS…] — release-check with --base-ref BRANCH, the fixtures above, the stub gh
  local b="$1" t="$2"; shift 2; rc=0; out=$(cd "$R" && PATH="$W/ghbin:$PATH" python3 "$A" release-check --repo o/r --version 1.0.0 --base-ref "$b" \
    --tag-commit "$t" --comments-dir "$F/comments" --commits-dir "$F/commits" --permissions "$F/perm.json" "$@" 2>&1) || rc=$?; }
# (findings 3, 15) a direct push is accepted unwaived only inside the minor exception: no phase artifact (specs, ADRs,
# plans, security — RUBRIC.md included — releases, architecture) and no constitution.md, each its own FAIL.
on_branch pa "$C5"; PA=""
for p in docs/security/1.0.0-disposition.md docs/security/RUBRIC.md constitution.md docs/specs/x-design.md docs/adr/009-x.md \
         docs/plans/x-plan.md docs/releases/1.0.0-notes.md docs/architecture/x-threat-model.md; do
  (cd "$R" && mkdir -p "$(dirname "$p")" && echo "medium_cap: 99" >> "$p" && git add -A && git commit -qm "direct push: $p")
  PA="$PA $(git -C "$R" rev-parse HEAD):$p"
done
(cd "$R" && git checkout -q main)
rcb pa "$(git -C "$R" rev-parse pa)" --since "$C5"
for e in $PA; do
  ck "a direct push of ${e#*:} is outside the minor exception: FAIL direct-push phase-artifact, never documents-only" \
    bash -c 'grep -q "^FAIL ${2:0:7} direct-push phase-artifact: ${3//./\\.}$" <<<"$1" && ! grep -q "^ok ${2:0:7}" <<<"$1"' _ "$out" "${e%%:*}" "${e#*:}"
done
ck "…exit 1" [ "$rc" = 1 ]
# (findings 4, 18) a direct push never reaches the Dependabot exemption: an API-made commit authored dependabot[bot]
# (verified, committer web-flow) that only moves a version, with a comment that carries no marker, is a FAIL without the
# classifier; with a marker-bearing comment from a non-maintainer, the exemption the classifier would grant is refused.
on_branch db "$C5"; D1=$(c 'printf "requests==2.32.5\n" > requirements.txt' "direct push: a version bump"); (cd "$R" && git checkout -q main)
python3 - "$F" "$D1" <<'PY'
import json, sys
F, d1 = sys.argv[1:3]
json.dump([{"sha": d1, "author": {"login": "dependabot[bot]"}, "committer": {"login": "web-flow"},
            "commit": {"verification": {"verified": True}}}], open(f"{F}/commits/commit-{d1}.json", "w"))
json.dump([{"id": 5, "user": {"login": "carol"}, "author_association": "CONTRIBUTOR", "created_at": "2026-10-01T11:00:00Z",
            "updated_at": "2026-10-01T11:00:00Z", "html_url": "https://github.com/o/r/commit/x#commitcomment-5", "body": "looks fine"}],
          open(f"{F}/comments/commit-{d1}.json", "w"))
PY
rcb db "$D1" --since "$C5"
ck "a forged-Dependabot direct push with a comment that carries no marker: FAIL direct-push code, exit 1 (never 'ok … waiver')" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: requirements.txt" <<<"$2" && ! grep -q "^ok ${3:0:7}" <<<"$2"' _ "$rc" "$out" "$D1"
python3 - "$F" "$D1" <<'PY'
import json, sys
F, d1 = sys.argv[1:3]
body = f"<!-- specflow-verifier:waive sha:{d1} -->\nA waiver from someone who is not a maintainer of this repository."
json.dump([{"id": 6, "user": {"login": "carol"}, "author_association": "NONE", "created_at": "2026-10-01T11:00:00Z",
            "updated_at": "2026-10-01T11:00:00Z", "html_url": "https://github.com/o/r/commit/x#commitcomment-6", "body": body}],
          open(f"{F}/comments/commit-{d1}.json", "w"))
PY
rcb db "$D1" --since "$C5"
ck "…with a marker-bearing comment from a non-maintainer: the classifier runs, its Dependabot exemption is refused — FAIL, exit 1" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: requirements.txt" <<<"$2" && ! grep -q "exempt-dependabot" <<<"$(grep "^ok" <<<"$2")"' _ "$rc" "$out" "$D1"
# (finding 14) predates-attestation is the history before attestation.py first appears on the first-parent chain, never a
# later window: a PR that moves the module makes the next merges FAIL attestation-missing, the restore included.
on_branch mv "$C5"
M1=$(c 'git mv scripts/lib/specflow/attestation.py scripts/lib/specflow/attest_core.py' "PR #20 moves attestation.py")
M2=$(c 'echo backdoor > backdoor.sh' "PR #21, unreviewed")
M3=$(c 'git mv scripts/lib/specflow/attest_core.py scripts/lib/specflow/attestation.py' "PR #22 restores it")
(cd "$R" && git checkout -q main)
prs "$M1" 20 "$M1" alice "$M2" 21 "$M2" alice "$M3" 22 "$M3" alice
rcb mv "$M3" --since "$C5" --prs "$F/prs.json"
ck "a PR merged onto a parent without attestation.py after the module first appeared: FAIL attestation-missing (#21, #22), never a skip" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL #21 attestation-missing ${3:0:7}" <<<"$2" && grep -q "^FAIL #22 attestation-missing ${4:0:7}" <<<"$2" && ! grep -q "^skip .* predates-attestation" <<<"$2"' _ "$rc" "$out" "$M2" "$M3"
# (finding 13) every PR-judged commit carries exactly the reviewed head merged onto its parent: a merge commit's parents
# are [parent, head] and its tree is git merge-tree's; a single-parent (squash) commit's tree is the same. The PR is found
# through gh api commits/<sha>/pulls (no --prs), and only through the EXACT association — the PR's merge_commit_sha is
# the commit (fix wave 1, A2): never by containment, so a commit GitHub merely associates with a PR is a direct push
# (no-pr); a PR whose base is another branch is not this branch's.
E="$W/e"; git init -q -b main "$E"
ce() { (cd "$E" && eval "$1" && git add -A && git commit -qm "$2" && git rev-parse HEAD); }
E0=$(ce 'echo root > README.md' root)
E1=$(ce 'mkdir -p scripts .claude/skills && cp -R "$ROOT/scripts/lib" scripts/ && cp -R "$ROOT/.claude/skills/verifier" .claude/skills/ && cp "$ROOT/constitution.md" .' "attestation.py lands")
(cd "$E" && git checkout -qb h7 && echo feature > feature.sh && git add -A && git commit -qm "PR #7 head"); H7=$(git -C "$E" rev-parse h7)
(cd "$E" && git checkout -qb m1 main && git merge -q --squash h7 >/dev/null && git commit -qm "PR #7 (#7)"); S7=$(git -C "$E" rev-parse m1)
(cd "$E" && git checkout -qb m2 main && git merge -q --no-ff --no-commit h7 && echo evil > backdoor.sh && git add -A && git commit -qm "Merge pull request #7"); X=$(git -C "$E" rev-parse m2)
(cd "$E" && git checkout -qb m3 main && git merge -q --squash h7 >/dev/null && echo evil > backdoor.sh && git add -A && git commit -qm "PR #7 (#7)"); Y=$(git -C "$E" rev-parse m3)
(cd "$E" && git checkout -qb m4 main && git merge -q --ff-only h7); (cd "$E" && git checkout -qb m5 main && git merge -q --squash h7 >/dev/null && git commit -qm "PR #7, merged into develop (#7)"); S5=$(git -C "$E" rev-parse m5)
mkdir -p "$W/ghfx"
python3 - "$ROOT/scripts/lib/specflow" "$E" "$F" "$W/ghfx" "$E1" "$H7" "$S7" "$X" "$Y" "$S5" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); os.chdir(sys.argv[2]); import attestation as a
F, gh, e1, h7, s7, x, y, s5 = sys.argv[3:11]
tail = "## SpecFlow verifier (code mode)\n\nNo findings.\nAPPROVE"
mk = a.make_marker(mode="code", sha=h7, base=e1, prompt_sha256=a.prompt_hash(e1), model="opus", verdict="APPROVE",
                   digest=a.digest(tail), origin="headless")
json.dump([{"id": 7, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T10:00:00Z",
            "updated_at": "2026-10-01T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-7",
            "body": mk + "\n" + tail}], open(f"{F}/comments/7.json", "w"))
json.dump([{"sha": h7, "author": {"login": "alice"}, "committer": {"login": "alice"},
            "commit": {"verification": {"verified": False}}}], open(f"{F}/commits/7.json", "w"))
def pr(base, mcs): return {"number": 7, "merged_at": "2026-10-01T12:00:00Z", "base": {"ref": base}, "merge_commit_sha": mcs,
                           "head": {"sha": h7}, "user": {"login": "alice"}}
for sha, item in ((s7, pr("m1", s7)), (x, pr("m2", x)), (y, pr("m3", None)), (h7, pr("m4", None)), (s5, pr("develop", s5))):
    json.dump([item], open(f"{gh}/repos_o_r_commits_{sha}_pulls.json", "w"))
PY
rce() { rc=0; out=$(cd "$E" && GHFX="$W/ghfx" PATH="$W/ghbin:$PATH" python3 "$A" release-check --repo o/r --version 1.0.0 --base-ref "$1" --tag-commit "$2" \
  --since "$E1" --comments-dir "$F/comments" --commits-dir "$F/commits" --permissions "$F/perm.json" 2>&1) || rc=$?; }
rce m1 "$S7"
ck "the exact association (merge_commit_sha) of a squash whose tree is the head's merged onto its parent: ok #7 approve, exit 0" \
  bash -c '[ "$1" = 0 ] && grep -q "^ok #7 approve ${3:0:7}" <<<"$2"' _ "$rc" "$out" "$S7"
rce m2 "$X"
ck "an evil merge — parents [parent, the approved head] plus a file nobody reviewed, exactly associated: FAIL #7 merge-content-mismatch" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL #7 merge-content-mismatch ${3:0:7}" <<<"$2"' _ "$rc" "$out" "$X"
rce m3 "$Y"
ck "a squash-shaped commit with that extra file, associated non-exactly (merge_commit_sha is not it): a direct push — FAIL no-pr naming #7, never judged by #7's marker" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: .*(no-pr: #7 " <<<"$2" && ! grep -q "^ok #7" <<<"$2"' _ "$rc" "$out" "$Y"
rce m4 "$H7"
ck "no containment: a fast-forward push of the reviewed head, associated non-exactly, is a direct push — FAIL no-pr, never ok #7 (fix wave 1, A2)" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: feature.sh (no-pr: #7 " <<<"$2" && ! grep -q "^ok #7" <<<"$2"' _ "$rc" "$out" "$H7"
rce m5 "$S5"
ck "a PR merged into another base (develop) is not this branch's: the commit is judged as a direct push of code — FAIL" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: feature.sh" <<<"$2"' _ "$rc" "$out" "$S5"
ck "…every lookup went through gh api repos/o/r/commits/<sha>/pulls" bash -c 'grep -q "repos/o/r/commits/$2/pulls" "$1/gh.log"' _ "$W" "$S5"
# --- fix wave 1 (REQ-350, REQ-311, REQ-334; P6 R28): the accounting, the exact-PR rule, the base's branch name, the
# default base, the Dependabot reason, the error prefix.
# Covers: REQ-350
# (A1) one output line per first-parent commit, always: the summary's N equals ok + skipped + FAIL and the line count.
counted() { python3 - "$1" <<'PY2'
import re, sys
out = sys.argv[1].splitlines()
body = [l for l in out if re.match(r"^(ok|skip|FAIL) ", l)]
m = next(re.search(r": (\d+) first-parent commits since .*: (\d+) ok, (\d+) skipped \(.*\), (\d+) FAIL$", l) for l in out if l.startswith("release-check "))
n, ok, sk, fl = map(int, m.groups())
assert n == ok + sk + fl == len(body), (n, ok, sk, fl, len(body))
assert ok == sum(l.startswith("ok ") for l in body) and sk == sum(l.startswith("skip ") for l in body), out
PY2
}
rch "$C5"; ck "the main walk: one line per first-parent commit; the summary's N = ok + skipped + FAIL = the lines (A1)" counted "$out"
rce m4 "$H7"; ck "…and on a walk with a no-pr direct push" counted "$out"
# (A2) a rebase merge: GitHub rewrites the PR's two commits onto main and records the LAST one as merge_commit_sha; the
# first carries a partial tree and no exact PR, so it is a direct push (R28: the factory merges by squash or merge commit).
(cd "$E" && git checkout -qb h8 "$E1" && echo a > ra.sh && git add -A && git commit -qm "PR #8 one" && echo b > rb.sh && git add -A && git commit -qm "PR #8 two")
H8=$(git -C "$E" rev-parse h8)
(cd "$E" && git checkout -qb m6 "$E1" && GIT_COMMITTER_DATE="@1791300000 +0000" git cherry-pick h8~1 h8 >/dev/null)
RB1=$(git -C "$E" rev-parse m6~1); RB2=$(git -C "$E" rev-parse m6)
python3 - "$ROOT/scripts/lib/specflow" "$E" "$F" "$W/ghfx" "$E1" "$H8" "$RB1" "$RB2" <<'PY2'
import json, os, sys
sys.path.insert(0, sys.argv[1]); os.chdir(sys.argv[2]); import attestation as a
F, gh, e1, h8, rb1, rb2 = sys.argv[3:9]
tail = "## SpecFlow verifier (code mode)\n\nNo findings.\nAPPROVE"
mk = a.make_marker(mode="code", sha=h8, base=e1, prompt_sha256=a.prompt_hash(e1), model="opus", verdict="APPROVE",
                   digest=a.digest(tail), origin="headless")
json.dump([{"id": 8, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-01T10:00:00Z",
            "updated_at": "2026-10-01T10:00:00Z", "html_url": "https://github.com/o/r/pull/8#issuecomment-8",
            "body": mk + "\n" + tail}], open(f"{F}/comments/8.json", "w"))
json.dump([{"sha": h8, "author": {"login": "alice"}, "committer": {"login": "alice"},
            "commit": {"verification": {"verified": False}}}], open(f"{F}/commits/8.json", "w"))
pr = {"number": 8, "merged_at": "2026-10-01T12:00:00Z", "base": {"ref": "m6"}, "merge_commit_sha": rb2,
      "head": {"sha": h8}, "user": {"login": "alice"}}
for sha in (rb1, rb2):
    json.dump([pr], open(f"{gh}/repos_o_r_commits_{sha}_pulls.json", "w"))
PY2
rce m6 "$RB2"
ck "a rebase-merge chain: the last commit (merge_commit_sha) is judged by PR #8 — ok #8 approve" grep -q "^ok #8 approve ${RB2:0:7}" <<<"$out"
ck "…the earlier commit, associated with #8 only by containment, is a direct push: FAIL no-pr naming #8, exit 1" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: ra.sh (no-pr: #8 " <<<"$2"' _ "$rc" "$out" "$RB1"
ck "…one line each, counted" counted "$out"
# (A2) a PR whose base is not main, exactly associated with the commit: not this branch's PR — a direct push.
rce m5 "$S5"
ck "an exact association to a PR merged into develop, walked with --base-ref m5: FAIL direct-push, never ok #7" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL ${3:0:7} direct-push code: feature.sh" <<<"$2" && ! grep -q "^ok #7" <<<"$2"' _ "$rc" "$out" "$S5"
# (A3) the branch name is --base-ref with refs/remotes/<remote>/, refs/heads/ or a remote's short form stripped — never its last segment.
# (A4) with no --base-ref, the base is refs/remotes/origin/main when it resolves: a tag named origin/main never shadows it.
sq() {  # sq BRANCH MESSAGE BASE-NAME — a squash of h7 onto E1 on BRANCH, exactly PR #7's merge into BASE-NAME
  (cd "$E" && git checkout -qb "$1" "$E1" && git merge -q --squash h7 >/dev/null && git commit -qm "$2") >/dev/null
  local s; s=$(git -C "$E" rev-parse "$1")
  python3 -c 'import json, sys; json.dump([{"number": 7, "merged_at": "2026-10-01T12:00:00Z", "base": {"ref": sys.argv[3]}, "merge_commit_sha": sys.argv[2], "head": {"sha": sys.argv[4]}, "user": {"login": "alice"}}], open(sys.argv[1], "w"))' \
    "$W/ghfx/repos_o_r_commits_${s}_pulls.json" "$s" "$3" "$H7"
  printf '%s\n' "$s"
}
SM=$(sq simmain "PR #7 into simmain (#7)" simmain); rce refs/heads/simmain "$SM"
ck "--base-ref refs/heads/simmain: the PR whose base is simmain is this branch's — ok #7 approve (A3)" grep -q "^ok #7 approve ${SM:0:7}" <<<"$out"
ST=$(sq team/main "PR #7 into team/main (#7)" team/main); git -C "$E" update-ref refs/remotes/origin/team/main "$ST"; rce refs/remotes/origin/team/main "$ST"
ck "--base-ref refs/remotes/origin/team/main: the branch is team/main, not its last segment — ok #7 approve (A3)" grep -q "^ok #7 approve ${ST:0:7}" <<<"$out"
SO=$(sq om "PR #7 into main (#7)" main); git -C "$E" update-ref refs/remotes/origin/main "$SO"; rce refs/remotes/origin/main "$SO"
ck "--base-ref refs/remotes/origin/main: the branch is main — ok #7 approve (A3)" grep -q "^ok #7 approve ${SO:0:7}" <<<"$out"
# (A3) any remote's base ref parses (SPECFLOW_RELEASE_REMOTE=upstream passes refs/remotes/upstream/main): the remote
# name has no slash, so refs/remotes/<remote>/ is stripped for every remote, and a configured remote's short form too.
SU=$(sq um "PR #7 into main via upstream (#7)" main); git -C "$E" update-ref refs/remotes/upstream/main "$SU"; rce refs/remotes/upstream/main "$SU"
ck "--base-ref refs/remotes/upstream/main: the branch is main, so PR #7 (base.ref main) is judged as a PR — ok #7 approve, exit 0, never direct-push (A3)" \
  bash -c '[ "$1" = 0 ] && grep -q "^ok #7 approve ${3:0:7}" <<<"$2" && ! grep -q "direct-push" <<<"$2"' _ "$rc" "$out" "$SU"
git -C "$E" remote add upstream "$W/no-such-upstream"; rce upstream/main "$SU"
ck "--base-ref upstream/main, upstream a configured remote: the branch is main — ok #7 approve (A3)" grep -q "^ok #7 approve ${SU:0:7}" <<<"$out"
git -C "$E" remote remove upstream
git -C "$E" tag origin/main "$H7"
rc=0; out=$(cd "$E" && GHFX="$W/ghfx" PATH="$W/ghbin:$PATH" python3 "$A" release-check --repo o/r --version 1.0.0 --tag-commit "$SO" \
  --since "$E1" --comments-dir "$F/comments" --commits-dir "$F/commits" --permissions "$F/perm.json" 2>&1) || rc=$?
ck "no --base-ref, a decoy tag named origin/main present: the default is refs/remotes/origin/main — ok #7 approve, never tag-commit-off-main (A4)" \
  bash -c '[ "$1" = 0 ] && grep -q "^ok #7 approve ${3:0:7}" <<<"$2" && ! grep -q "tag-commit-off-main" <<<"$2"' _ "$rc" "$out" "$SO"
git -C "$E" tag -d origin/main >/dev/null
ck "attestation.py's release-check: no --base-ref default of the bare short origin/main in the parser (A4)" \
  bash -c '! grep -qE "add_argument\(\"--base-ref\", default=\"origin/main\"\)" "$1"' _ "$A"
# (A5) a Dependabot PR the exemption refuses reports the exemption's reason, not the classifier's none (no-marker).
# Covers: REQ-334
(cd "$R" && git checkout -qb pr9 "$C5" && printf "requests==2.32.4\nflask==3.0.0\n" > requirements.txt && git commit -qam "pr9 head" \
  && git checkout -qb dep "$C5" && git merge -q --squash pr9 >/dev/null && git commit -qm "pr9 (#9)" && git checkout -q main)
D9=$(git -C "$R" rev-parse dep); H9=$(git -C "$R" rev-parse pr9)
python3 -c 'import json, sys; json.dump([{"sha": sys.argv[2], "author": {"login": "dependabot[bot]"}, "committer": {"login": "web-flow"}, "commit": {"verification": {"verified": True}}}], open(sys.argv[1], "w")); json.dump([], open(sys.argv[3], "w"))' \
  "$F/commits/9.json" "$H9" "$F/comments/9.json"
prs "$D9" 9 "$H9" "dependabot[bot]"
rcb dep "$D9" --since "$C5" --prs "$F/prs.json"
ck "a Dependabot PR that adds a dependency: FAIL #9 dependabot:<the exemption's reason> (new-dependency), never 'none (no-marker)' (A5)" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL #9 dependabot:.*new-dependency" <<<"$2" && ! grep -q "^FAIL #9 none" <<<"$2"' _ "$rc" "$out"
# (A6) a fail-closed exit 2 names release-check once.
C13=$(c 'mkdir -p scripts && printf "stack: template\nattestation_since: nothex\n" > scripts/template-pack.yml && rm -f .specflow/pack.yml .specflow.yml' "a malformed key")
rch "$C13"
ck "an exit-2 message is prefixed 'release-check:' once, never 'release-check: release-check:' (A6)" \
  bash -c '[ "$1" = 2 ] && grep -qF "release-check: attestation_since" <<<"$2" && ! grep -qF "release-check: release-check:" <<<"$2"' _ "$rc" "$out"
finish test_release_check
