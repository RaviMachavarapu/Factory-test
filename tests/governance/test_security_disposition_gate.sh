#!/usr/bin/env bash
# REQ-322 (ADR-002's wrapper): scripts/check-security-disposition.sh resolves the version (--version; ship/<version>; else
# each untagged version a changed docs/security/ or docs/releases/ file names; else a SKIP), never re-evaluates a tagged
# version, reads medium_cap and expiry_horizon_days from RUBRIC.md at the base ref (a resolving base without one is
# exit 2), fails any commit that removes an id from any review or disposition, tagged or not (id_removed, read with the
# one parser), reads a tagged prior version from its tag, reduces prior dispositions to the latest entry per id, and maps decide(): 0 PASS, 1 FAIL naming id and
# rule, 2 parser error. Gate mode's joined checks (blocks.check_pair: unique ids, owner/expiry, rationale >= 10
# characters) are parser errors too. A tagged pre-schema prior (no header, no blocks) contributes nothing; the walk
# compares each PR commit with its first parent (a base that advanced is not a removal); renames are seen as a delete
# plus an add; prior versions come from the base ref, the v* tags and the working tree, so a version moved out of
# docs/security/ is still carried forward. Synthetic repositories cloned from one seed under mktemp; a fixed --run-date;
# no network.
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CSD="$ROOT/scripts/check-security-disposition.sh"
ck "scripts/check-security-disposition.sh exists and is executable" test -x "$CSD"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
read -r VH VM VL < <(python3 - "$ROOT/tests/governance/fixtures/cvss4/vectors.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))["vectors"]
print(*(next(c["vector"] for c in v if c["severity"] == s) for s in ("high", "medium", "low")))
PY
)
hdr() { printf -- '---\nschema: specflow-security/1\nkind: %s\nversion: %s\n---\n\n# %s\n\n' "$1" "$2" "$1"; }
docs() {  # docs VERSION "id|severity|vector|status|expiry|carried_from"… — writes the version's review and disposition
  local v="$1" s i sv vec st ex cf; shift
  { hdr review "$v"; for s in "$@"; do IFS='|' read -r i sv vec st ex cf <<<"$s"
      printf -- '---\nid: %s\nseverity: %s\ncvss_vector: %s\ncite: [CWE-20]\naffects: [src/a.py:1]\n' "$i" "$sv" "$vec"
      [ -z "$cf" ] || printf 'carried_from: %s\n' "$cf"; printf -- '---\n\nbody\n\n'; done; } > "$R/docs/security/$v-review.md"
  { hdr disposition "$v"; for s in "$@"; do IFS='|' read -r i sv vec st ex cf <<<"$s"
      printf -- '---\nid: %s\nstatus: %s\nowner: alice\n' "$i" "$st"; [ -z "$ex" ] || printf 'expiry: %s\n' "$ex"
      printf 'rationale: "fixture rationale text"\n---\n\n'; done; } > "$R/docs/security/$v-disposition.md"
}
SEED="$W/seed"; mkdir -p "$SEED/docs/security"; cp -R "$ROOT/scripts" "$SEED/scripts"   # one copy of scripts/ per test
bt=$(printf '\140\140\140')   # a fence, spelled so this plan's own fence survives
printf '# Rubric\n\n%syaml\nmedium_cap: 1\nexpiry_horizon_days: 90\n%s\n' "$bt" "$bt" > "$SEED/docs/security/RUBRIC.md"
(cd "$SEED" && git init -q -b main && git add -A && git commit -qm base)
n=0
mkrepo() {  # a clone of the seed (main: scripts/ and a rubric with cap 1, horizon 90) with its own bare origin; HEAD on ship/1.0.0
  n=$((n + 1)); R="$W/r$n"; git clone -q --bare "$SEED" "$R.git"; git clone -q "$R.git" "$R"
  (cd "$R" && git checkout -qb ship/1.0.0)
}
mkprior() {  # main also carries 0.9.0 (SEC-001: an accepted medium whose expiry has passed), tagged v0.9.0; HEAD on ship/1.1.0
  mkrepo; (cd "$R" && git checkout -q main); docs 0.9.0 "SEC-001|medium|$VM|accepted|2026-09-01|"; commit 0.9.0
  (cd "$R" && git tag v0.9.0 && git push -q origin main && git checkout -qb ship/1.1.0)
}
commit() { (cd "$R" && git add -A && git commit -qm "$1"); }
csd() { rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_BASE_REF=origin/main \
  bash scripts/check-security-disposition.sh --run-date 2026-09-27 "$@" 2>&1) || rc=$?; }
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-15|" "SEC-002|low|$VL|accepted||"; commit s; csd
ck "ship/1.0.0: an accepted medium inside the window and an accepted low pass" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS security-disposition 1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|high|$VH|accepted|2026-10-15|"; commit s; csd
ck "an accepted high fails, naming the id and severe_not_fixed" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 severe_not_fixed" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-15|" "SEC-002|medium|$VM|deferred|2026-10-20|"; commit s; csd
ck "two accepted/deferred mediums over the base's cap of 1 fail medium_cap" bash -c '[ "$1" = 1 ] && grep -q "medium_cap" <<<"$2"' _ "$rc" "$out"
(cd "$R" && sed -i.bak 's/^medium_cap: 1/medium_cap: 9/' docs/security/RUBRIC.md && rm docs/security/RUBRIC.md.bak); commit raise; csd
ck "…and still fail when the PR raises its own cap (the rubric is read at the base ref)" bash -c '[ "$1" = 1 ] && grep -q "medium_cap" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2027-06-01|"; commit s; csd
ck "an expiry beyond the base rubric's 90-day horizon fails expiry_window" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 expiry_window" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|high|$VM|fixed||"; commit s; csd
ck "a severity that is not the vector's band is a parser error (exit 2)" [ "$rc" = 2 ]
mkrepo; docs 1.0.0 "SEC-001|low|$VL|accepted||" "SEC-002|low|$VL|accepted||"; commit two; docs 1.0.0 "SEC-001|low|$VL|accepted||"; commit drop; csd
ck "a commit that removes a review id fails id_removed, naming it" bash -c '[ "$1" = 1 ] && grep -q "SEC-002 id_removed" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb feature/x); echo x > "$R/a.txt"; commit x; csd
ck "a branch whose diff names no versioned security or release doc prints a SKIP" bash -c '[ "$1" = 0 ] && grep -q "^SKIP security-disposition" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb feature/y); docs 1.0.0 "SEC-001|high|$VH|open||"; commit s; csd
ck "on another branch a changed docs/security/1.0.0-* file names the version evaluated" \
  bash -c '[ "$1" = 1 ] && grep -q "1.0.0 SEC-001 severe_not_fixed" <<<"$2"' _ "$rc" "$out"
(cd "$R" && git tag v1.0.0); csd
ck "a tagged version is never re-evaluated (a SKIP naming the tag)" bash -c '[ "$1" = 0 ] && grep -q "tagged v1.0.0" <<<"$2"' _ "$rc" "$out"
mkprior; docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit 1.1.0; csd
ck "a prior medium (0.9.0, expired) missing from 1.1.0 fails carry_forward" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
docs 1.1.0 "SEC-001|medium|$VM|fixed||0.9.0" "SEC-002|low|$VL|accepted||"; commit carry; csd
ck "…re-listed with carried_from: 0.9.0 and fixed, it passes" [ "$rc" = 0 ]
docs 1.1.0 "SEC-001|low|$VL|accepted|2026-10-15|0.9.0" "SEC-002|low|$VL|accepted||"; commit down; csd
ck "…re-listed at low without reclassified_by, it fails carry_forward (the downgrade path)" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
mkprior; docs 0.9.0; docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit "drop SEC-001 from the released 0.9.0"; csd
ck "deleting a finding from a tagged prior version's review and disposition fails id_removed, and the tag still carries it forward" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-001 id_removed" <<<"$2" && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
mkprior; hdr disposition 0.9.0 > "$R/docs/security/0.9.0-disposition.md"; docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit "drop the entry only"; csd
ck "deleting only the prior disposition entry fails id_removed" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 id_removed" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|low|$VL|accepted||" "SEC-002|low|$VL|accepted||"
(cd "$R/docs/security" && sed -i.bak 's/^id: SEC-002$/id: "SEC-002"/' 1.0.0-review.md 1.0.0-disposition.md && rm -f ./*.bak); commit quoted
docs 1.0.0 "SEC-001|low|$VL|accepted||"; commit drop; csd
ck "a quoted id (id: \"SEC-002\") removed later fails id_removed (the walk reads ids with the one parser)" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-002 id_removed" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -q main); docs 0.9.0 "SEC-001|medium|$VM|fixed||"; hdr disposition 0.9.0 > "$R/docs/security/0.9.0-disposition.md"
commit 0.9.0; (cd "$R" && git push -q origin main && git checkout -qb ship/1.1.0); docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit 1.1.0; csd
ck "a prior version's review id with no entry in its disposition is a parser error (exit 2) naming it" \
  bash -c '[ "$1" = 2 ] && grep -q "SEC-001" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-15|"
sed -i.bak 's/^rationale: .*/rationale: "ok"/' "$R/docs/security/1.0.0-disposition.md"; rm "$R/docs/security/1.0.0-disposition.md.bak"; commit short; csd
ck "an accepted medium whose rationale is shorter than 10 characters is a parser error (exit 2) naming it" \
  bash -c '[ "$1" = 2 ] && grep -q "SEC-001: rationale is shorter than 10 characters" <<<"$2"' _ "$rc" "$out"
sed -i.bak '/^rationale: /d' "$R/docs/security/1.0.0-disposition.md"; rm "$R/docs/security/1.0.0-disposition.md.bak"; commit none; csd
ck "…and so is one with no rationale at all" bash -c '[ "$1" = 2 ] && grep -q "rationale" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -q main); printf '# 0.9.0 security review\n\nNo findings; written before the block schema.\n' > "$R/docs/security/0.9.0-review.md"
printf '# 0.9.0 disposition\n\nNothing to dispose.\n' > "$R/docs/security/0.9.0-disposition.md"; commit 0.9.0
(cd "$R" && git tag v0.9.0 && git push -q origin main && git checkout -qb ship/1.1.0); docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit 1.1.0; csd
ck "a tagged pre-schema prior (no header, no blocks) contributes nothing: the next ship PR passes" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS security-disposition 1.1.0" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -qb ship/1.1.0 main); docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit 1.1.0
(cd "$R" && git checkout -q main); docs 0.9.5 "SEC-201|low|$VL|accepted||"; commit 0.9.5; (cd "$R" && git push -q origin main && git checkout -q ship/1.1.0); csd
ck "the base gaining a security id after the branch point is not an id_removed of the PR's" \
  bash -c '[ "$1" = 0 ] && ! grep -q "id_removed" <<<"$2"' _ "$rc" "$out"
(cd "$R" && git merge -q --no-edit origin/main); csd
ck "…nor after the base is merged into the PR branch" bash -c '[ "$1" = 0 ] && ! grep -q "id_removed" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -q main); docs 0.9.0 "SEC-001|medium|$VM|accepted|2026-09-01|"; commit 0.9.0
(cd "$R" && git push -q origin main && git checkout -qb feature/archive && mkdir -p docs/archive && git mv docs/security/0.9.0-review.md docs/security/0.9.0-disposition.md docs/archive/); commit move; csd
ck "moving a version's review and disposition out of docs/security/ fails id_removed (renames are a delete plus an add)" \
  bash -c '[ "$1" != 0 ] && grep -q "SEC-001 id_removed" <<<"$2"' _ "$rc" "$out"
(cd "$R" && git checkout -qb ship/1.1.0 main && mkdir -p docs/archive && git mv docs/security/0.9.0-review.md docs/security/0.9.0-disposition.md docs/archive/)
docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit "move 0.9.0 and ship 1.1.0"; csd
ck "…and a later version must still carry the moved (untagged) version's due entry forward, read at the base" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-001 id_removed" <<<"$2" && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
mkprior; (cd "$R" && mkdir -p docs/archive && git mv docs/security/0.9.0-review.md docs/security/0.9.0-disposition.md docs/archive/)
docs 1.1.0 "SEC-002|low|$VL|accepted||"; commit "move the tagged 0.9.0"; csd
ck "…and a moved tagged version is still read from its tag" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-001 carry_forward" <<<"$2"' _ "$rc" "$out"
mkrepo; (cd "$R" && git checkout -q main && git rm -q docs/security/RUBRIC.md && git commit -qm "drop rubric" && git push -q origin main \
  && git checkout -q ship/1.0.0 && git rebase -q main); mkdir -p "$R/docs/security"; cp "$SEED/docs/security/RUBRIC.md" "$R/docs/security/RUBRIC.md"
docs 1.0.0 "SEC-001|low|$VL|accepted||"; commit s; csd
ck "a base that resolves but has no RUBRIC.md is exit 2 naming the ref (the PR's own rubric is never read in its place)" \
  bash -c '[ "$1" = 2 ] && grep -q "RUBRIC.md" <<<"$2" && grep -q "origin/main" <<<"$2" && ! grep -q "no base ref" <<<"$2"' _ "$rc" "$out"
csd --base origin/no-such-ref
ck "…while a base that does not resolve reads the working tree's, with a note saying the ref does not resolve" \
  bash -c '[ "$1" = 0 ] && grep -q "does not resolve" <<<"$2"' _ "$rc" "$out"
ck "both gates list changed files with --no-renames" \
  bash -c 'grep -qF "\"--no-renames\"" "$1" && grep -qF "\"--no-renames\"" "$2"' _ "$ROOT/scripts/lib/specflow/disposition_gate.py" "$ROOT/scripts/lib/specflow/release_gate.py"
# PR #42 fourth verifier run, code low 4 (REQ-322, REQ-324): a ship/<v> branch whose <v> is not semver (ship/v1.0.0) is a
# clear ERROR (exit 2) naming the branch and the expected form, never a traceback.
mkrepo; (cd "$R" && git checkout -qb ship/v1.0.0); docs 1.0.0 "SEC-001|low|$VL|accepted||"; commit s; csd
ck "ship/v1.0.0: exit 2, an ERROR naming the branch and the expected ship/<major>.<minor>.<patch> form, no traceback" \
  bash -c '[ "$1" = 2 ] && grep -q "^ERROR security-disposition: .*ship/v1.0.0" <<<"$2" && grep -qF "ship/<major>.<minor>.<patch>" <<<"$2" && ! grep -q Traceback <<<"$2"' _ "$rc" "$out"
if ! instance; then
  ck "the tauri pack's migrated skeleton passes (--root, --no-git, the template's rubric, run date 2026-09-27)" \
    bash "$CSD" --root "$ROOT/stacks/tauri/overlay" --version 0.0.0-skeleton --no-git --rubric "$ROOT/docs/security/RUBRIC.md" --run-date 2026-09-27
  rc=0; out=$(bash "$CSD" --root "$ROOT/stacks/tauri/overlay" --version 0.0.0-skeleton --no-git --run-date 2026-09-27 2>&1) || rc=$?
  ck "no RUBRIC.md anywhere and no --rubric is exit 2 (a missing rubric is never a default, R13)" \
    bash -c '[ "$1" = 2 ] && grep -q "RUBRIC.md" <<<"$2"' _ "$rc" "$out"
fi
# PR #54 verifier run 2, code-mode low (REQ-322; dfe-14): with no base given — a non-PR CI event passes an empty
# SPECFLOW_BASE_REF — the wrapper defaults to refs/remotes/origin/main when that ref exists, so a tag named origin/main
# (here on the PR's own head, which would make the PR's security documents look unchanged) cannot shadow it; with no
# remote-tracking ref the short origin/main is the fallback.
# Covers: REQ-322
mkrepo; (cd "$R" && git checkout -q -b work main); docs 1.0.0 "SEC-001|high|$VH|open||"; commit "an open high on a non-ship branch"
git -C "$R" tag origin/main HEAD
rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_BASE_REF= bash scripts/check-security-disposition.sh --run-date 2026-09-27 2>&1) || rc=$?
ck "SPECFLOW_BASE_REF empty, a tag named origin/main on the head: the default base is refs/remotes/origin/main — 1.0.0 evaluated, FAIL (never a SKIP)" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^SKIP security-disposition:" <<<"$2" && grep -q "SEC-001" <<<"$2"' _ "$rc" "$out"
ck "disposition_gate.default_base_ref: refs/remotes/origin/main when it exists, else origin/main (a repository with no remote)" \
  bash -c 'g="$2/norem"; git init -q -b main "$g" && git -C "$g" commit -q --allow-empty -m x && [ "$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import disposition_gate as d; from pathlib import Path; print(d.default_base_ref(Path(sys.argv[2])), d.default_base_ref(Path(sys.argv[3])))" "$3" "$1" "$g")" = "refs/remotes/origin/main origin/main" ]' _ "$R" "$W" "$ROOT/scripts/lib/specflow"
ck "the wrapper calls the kernel and the parser" bash -c 'grep -q "disposition" "$1" && grep -qE "^(import|from) (blocks|disposition)" "$2"' _ "$CSD" "$ROOT/scripts/lib/specflow/disposition_gate.py"
# P6 Task 3.2 (REQ-350, REQ-322; P6 R30): --at-tag replays the gate for the tagged version itself — release.yml's
# tag-time replay — with priors strictly before it and, as the run date, the later of the tag's tagger date and the
# tagged commit's committer date (a tagger date can be backdated; PR #52 run 1, finding 5); without it a tagged version
# is still never re-evaluated, and --at-tag without --version is a usage error. The run-date cases fix the tagged
# commit's committer date, so their expectations do not depend on the day the test runs.
# Covers: REQ-350
# Covers: REQ-322
at() { rc=0; out=$(cd "$R" && env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_BASE_REF=origin/main \
  bash scripts/check-security-disposition.sh "$@" 2>&1) || rc=$?; }
mkrepo; docs 1.0.0 "SEC-001|high|$VH|open||"; commit s; (cd "$R" && GIT_COMMITTER_DATE="2026-10-05T12:00:00Z" git tag -a v1.0.0 -m r)
at --version 1.0.0
ck "tagged v1.0.0 without --at-tag: still a SKIP" bash -c '[ "$1" = 0 ] && grep -q "tagged v1.0.0" <<<"$2"' _ "$rc" "$out"
at --version 1.0.0 --at-tag
ck "--at-tag: the tagged version is evaluated — its open high fails severe_not_fixed" bash -c '[ "$1" = 1 ] && grep -q "SEC-001 severe_not_fixed" <<<"$2"' _ "$rc" "$out"
# Fix wave 1, G (REQ-322, REQ-350): --at-tag reads the documents from the checkout, so the checkout must be the tag's
# tree: HEAD is the tagged commit and git status --porcelain lists nothing — else exit 2, before any evaluation.
# Covers: REQ-322
printf 'stray\n' > "$R/docs/security/stray.md"; at --version 1.0.0 --at-tag; rm -f "$R/docs/security/stray.md"
ck "--at-tag with an untracked file in the checkout: exit 2, naming the working tree — the documents are the tag's tree only" \
  bash -c '[ "$1" = 2 ] && grep -qF "working tree" <<<"$2" && ! grep -q "severe_not_fixed" <<<"$2"' _ "$rc" "$out"
(cd "$R" && git commit -q --allow-empty -m "after the tag"); at --version 1.0.0 --at-tag; (cd "$R" && git reset -q --hard HEAD~1)
ck "--at-tag with HEAD past the tag: exit 2, naming HEAD and the tag" bash -c '[ "$1" = 2 ] && grep -qF "HEAD" <<<"$2" && grep -qF "v1.0.0" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-20|"; GIT_COMMITTER_DATE="2026-10-04T12:00:00Z" commit s
(cd "$R" && GIT_COMMITTER_DATE="2026-10-05T12:00:00Z" git tag -a v1.0.0 -m r)
at --version 1.0.0 --at-tag
ck "--at-tag: a tagger date later than the commit's: the run date is the tagger date, named in the output (re-runs are deterministic)" \
  bash -c '[ "$1" = 0 ] && grep -q "^PASS security-disposition 1.0.0" <<<"$2" && grep -qF "run date 2026-10-05 (tagger date of v1.0.0)" <<<"$2"' _ "$rc" "$out"
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-03|"; GIT_COMMITTER_DATE="2026-10-05T12:00:00Z" commit s
(cd "$R" && GIT_COMMITTER_DATE="2026-09-01T12:00:00Z" git tag -a v1.0.0 -m r)
at --version 1.0.0 --at-tag
ck "--at-tag: a backdated tag (tagger 2026-09-01, commit 2026-10-05) is bounded by the commit — run date 2026-10-05, so the medium that expired 2026-10-03 FAILs" \
  bash -c '[ "$1" = 1 ] && grep -qF "run date 2026-10-05 (committer date of v1.0.0'"'"'s commit, later than its tagger date 2026-09-01)" <<<"$2" && ! grep -q "^PASS security-disposition 1.0.0" <<<"$2"' _ "$rc" "$out"
at --at-tag
ck "--at-tag without --version: exit 2" [ "$rc" = 2 ]
# Build 3 final review, finding 16 (REQ-350, REQ-322): under --at-tag every base-side input — medium_cap and
# expiry_horizon_days, the priors — is read at the tagged commit's first parent (the ship PR's base as merged, what the
# PR-time gate read), never at main's tip: a commit pushed to main after the tag that raises the cap changes nothing.
# Covers: REQ-350
mkrepo; docs 1.0.0 "SEC-001|medium|$VM|accepted|2026-10-20|" "SEC-002|medium|$VM|accepted|2026-10-20|"
GIT_COMMITTER_DATE="2026-10-05T12:00:00Z" commit s; (cd "$R" && git checkout -q main && git merge -q --no-ff ship/1.0.0 -m "Merge pull request #9" \
  && GIT_COMMITTER_DATE="2026-10-05T12:00:00Z" git tag -a v1.0.0 -m r && sed -i.bak 's/^medium_cap: 1/medium_cap: 9/' docs/security/RUBRIC.md \
  && rm docs/security/RUBRIC.md.bak && git commit -qam "after the tag: the cap raised on main" && git push -q origin main && git checkout -q --detach v1.0.0)
at --version 1.0.0 --at-tag
ck "--at-tag: main raised medium_cap after the tag — the rubric is read at the tag's parent (cap 1): two mediums FAIL medium_cap" \
  bash -c '[ "$1" = 1 ] && grep -q "SEC-00[12] medium_cap" <<<"$2" && ! grep -q "^PASS security-disposition 1.0.0" <<<"$2"' _ "$rc" "$out"
finish test_security_disposition_gate
