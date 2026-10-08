#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R5–R7, R20): with a remote, next.sh reads the PRs through gh — the branch's newest PR, the open lane
# PRs and whose they are, merged PRs and tags for unbuilt builds, the untagged ship and the next version — and reduces the
# branch PR's comments with attestation.pr_attestation (REQ-311: one classifier). REQ-385: an open PR with no marker
# renders the second-terminal instruction; a REQUEST_CHANGES prints the findings and no merge command; a merge is printed
# only on an APPROVE (and, in team mode, a human approval — reviewDecision, or the reviews at the head when GitHub
# leaves it empty). REQ-382: an accepted waiver the PR body does not link is reported under --explain. P5 R21: a merged
# PR of an earlier use of a fixed branch name is not the branch's PR; a base or merge commit missing locally fails safe
# and is explained. P5 R22: a PR stacked on the branch turns the merge into a merge commit plus the retarget, and a
# stacked PR's verifier instruction names its unreviewed base PR and pipes main's reviewed run-verifier.sh, never the
# base's (the SEC-004 back-edge, superseding R22's warning). The factory's own PRs derive on main for both
# paths. A gh failure fails safe. pipeline.py never reads a marker or waiver itself (REQ-311). P5 final review: the merge
# command is bound to the judged head (--match-head-commit); a fork PR sharing the branch name is never the branch's PR
# nor stacked on it; in team mode with an empty reviewDecision only a writing, non-author, non-committer reviewer's
# approval counts; a read-only MEMBER's hand-posted marker is refused and --explain names the decisive comment's poster;
# a stacked PR retargeted onto main before its base merged loses its marker (base-mismatch); a sec- plan is not tracked.
# Covers: REQ-341
# Covers: REQ-385
# Covers: REQ-382
# Covers: REQ-311
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
A="$ROOT/scripts/lib/specflow/attestation.py"; S="$W/stub"; mkdir -p "$S/bin"
cat > "$S/bin/gh" <<'EOF'
#!/usr/bin/env bash
S="${STUB_DIR:?}"; { printf '%s\n' "$@"; echo ---; } >> "$S/gh.argv"
[ -z "${GH_REPO:-}" ] || echo "GH_REPO=$GH_REPO" >> "$S/gh.env"
[ -z "${STUB_GH_FAIL:-}" ] || { echo 'gh: HTTP 502' >&2; exit 1; }
case "$1 ${2:-}" in
  "repo view") echo '{"nameWithOwner": "o/r"}' ;;
  "pr list")   python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(json.dumps(d["prs"] if isinstance(d, dict) else d))' "$S/prs.json" ;;
  "pr view")   if printf '%s\n' "$@" | grep -qx reviews; then f="$S/reviews-$3.json"; d='{"reviews": []}'; else f="$S/files-$3.json"; d='{"files": []}'; fi
               if [ -f "$f" ]; then cat "$f"; else echo "$d"; fi ;;
  "api user")  echo "{\"login\": \"${STUB_LOGIN:-alice}\"}" ;;
  api\ *)
    case "$*" in
      */issues/*/comments*) n=$(sed -E 's#.*/issues/([0-9]+)/comments.*#\1#' <<<"$*"); f="$S/comments-$n.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
      */issues/*/timeline*) n=$(sed -E 's#.*/issues/([0-9]+)/timeline.*#\1#' <<<"$*"); f="$S/timeline-$n.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
      */pulls/*/commits*) n=$(sed -E 's#.*/pulls/([0-9]+)/commits.*#\1#' <<<"$*"); f="$S/commits-$n.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
      */collaborators/*/permission*)  # $S/perm-<login> holds a role, or 404; no file: write
        l=$(sed -E 's#.*/collaborators/([^/]+)/permission.*#\1#' <<<"$*"); r=$(cat "$S/perm-$l" 2>/dev/null || echo write)
        if [ "$r" = 404 ]; then echo 'gh: Not Found (HTTP 404)' >&2; exit 1; fi; echo "{\"permission\": \"$r\", \"role_name\": \"$r\"}" ;;
      *) echo "stub gh: unexpected api call: $*" >&2; exit 64 ;;
    esac ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 64 ;;
esac
EOF
chmod +x "$S/bin/gh"
SEED="$W/seed"; next_seed "$SEED"
git init -q --bare -b main "$W/origin.git"   # check.sh sets GIT_CONFIG_GLOBAL=/dev/null: without -b, HEAD is master and clones check out nothing
git -C "$SEED" remote add origin "$W/origin.git"; git -C "$SEED" push -q origin main
repo() {  # repo NAME BRANCH — a clone with origin; a non-main BRANCH gets one commit and is pushed; sets D and HEAD_SHA
  D="$W/$1"; git clone -q "$W/origin.git" "$D"
  if [ "$2" != main ]; then
    git -C "$D" checkout -q -b "$2"; echo "$1" > "$D/note-$1.txt"; git -C "$D" add -A; git -C "$D" commit -qm "$1"; git -C "$D" push -q origin "$2"
  fi
  HEAD_SHA=$(git -C "$D" rev-parse HEAD)
}
prs() {  # prs "NUMBER HEAD BASE STATE AUTHOR [HEAD_OID [REVIEW_DECISION [BODY_URL]]]" … — gh pr list's answer
  python3 - "$@" > "$S/prs.json" <<'PY'
import json, os, sys
out = []
for row in sys.argv[1:]:
    n, head, base, state, author, *rest = row.split()
    out.append({"number": int(n), "headRefName": head, "baseRefName": base, "state": state, "author": {"login": author},
                "mergedAt": "2026-09-28T10:00:00Z" if state == "MERGED" else None,
                "mergeCommit": {"oid": "0" * 40} if state == "MERGED" else None,
                "reviewDecision": rest[1] if len(rest) > 1 and rest[1] != "-" else "", "isDraft": False,
                "headRefOid": rest[0] if rest else "1" * 40, "url": f"https://github.com/o/r/pull/{n}",
                "body": ("waiver: " + rest[2]) if len(rest) > 2 else ""})
forks = set(os.environ.get("STUB_FORKS", "").split())
if os.environ.get("STUB_BASE_OID"):  # gh's baseRefOid (the base tip GitHub holds), when a case sets it
    for d in out:
        d["baseRefOid"] = os.environ["STUB_BASE_OID"]
for d in out:
    d["isCrossRepository"] = str(d["number"]) in forks
    d["headRepositoryOwner"] = {"login": "mallory" if d["isCrossRepository"] else "o"}
print(json.dumps(out))
PY
}
comment() {  # comment VERDICT|waive [LOGIN ASSOC [BASE_REF]] — $S/comments-7.json: one valid comment (OWNER alice) for HEAD_SHA against origin/main
  python3 - "$A" "$D" "$HEAD_SHA" "$1" "${2:-alice}" "${3:-OWNER}" "${4:-origin/main}" > "$S/comments-7.json" <<'PY'
import json, subprocess, sys
a, d, head, verdict, login, assoc, bref = sys.argv[1:]
def at(*args, inp=None):
    return subprocess.run(["python3", a, *args], cwd=d, input=inp, capture_output=True, text=True, check=True).stdout.strip()
if verdict == "waive":
    body = f"<!-- specflow-verifier:waive sha:{head} -->\nReviewed by hand: the maintainer decided this one."
elif verdict.startswith("waive:"):
    wb = subprocess.run(["git", "rev-parse", verdict[6:]], cwd=d, capture_output=True, text=True, check=True).stdout.strip()
    body = f"<!-- specflow-verifier:waive sha:{head} base:{wb} -->\nReviewed by hand: the maintainer decided this one."
else:
    tail = "## SpecFlow verifier\n\n- [art-test-first] high: an example finding\n" + verdict
    base = subprocess.run(["git", "rev-parse", bref], cwd=d, capture_output=True, text=True, check=True).stdout.strip()
    mode = json.loads(at("review-scope", "--base", bref, "--head", head))["mode"]
    body = at("marker", "--mode", mode, "--sha", head, "--base", base, "--prompt-sha256", at("prompt-hash", "--ref", bref),
              "--model", "opus", "--verdict", verdict, "--digest", at("digest", inp=tail + "\n"), "--origin", "headless") + "\n" + tail
print(json.dumps([{"id": 1, "user": {"login": login}, "author_association": assoc, "created_at": "2026-09-28T10:00:00Z",
                   "updated_at": "2026-09-28T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-1", "body": body}]))
PY
}
nx() { rc=0; rm -f "$S/gh.argv"; (cd "$D" && PATH="$S/bin:$PATH" STUB_DIR="$S" next_sh "$@") > "$W/out" 2>&1 || rc=$?; }
has() { grep -qF -- "$1" "$W/out"; }
repo av design/x; prs "7 design/x main OPEN alice $HEAD_SHA"; rm -f "$S"/comments-*.json; nx
ck "an open PR with no marker: design awaiting-verifier" has 'state: design awaiting-verifier'
ck "…the next line is REQ-385's second-terminal instruction, verbatim, in the base-ref form (repo = git's toplevel: /var is /private/var on macOS)" \
  bash -c 'want="next: In a second terminal, not inside Claude — open a new terminal window (Terminal.app or your shell) and run: cd $(printf %q "$(git -C "$2" rev-parse --show-toplevel)") && git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7; when it prints \"Findings posted to PR #7\", return here and run /next."; grep -qxF -- "$want" "$1"' _ "$W/out" "$D"
ck "…no merge command; the comments were read through gh" bash -c '! grep -qF "gh pr merge" "$1" && grep -q "issues/7/comments" "$2"' _ "$W/out" "$S/gh.argv"
nx --explain
ck "…--explain names the base it judged against and its date (next.sh never fetches, P5 R7)" \
  bash -c 'grep -qE "^why: base origin/main at [0-9a-f]{7}, committed " "$1"' _ "$W/out"
comment APPROVE; nx --profile guided
ck "an APPROVE for the head, solo: awaiting-merge, gh pr merge 7 --squash bound to the attested head, and the guided merge confirmation" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qxF "next: gh pr merge 7 --squash --match-head-commit $2" "$1" && grep -q "^confirm: merge" "$1"' _ "$W/out" "$HEAD_SHA"
prs "7 design/x main OPEN alice $HEAD_SHA" "8 build/x-1 design/x OPEN alice"; nx
ck "…with PR #8 stacked on design/x: exactly two commands, a merge commit first, then #8 retargeted (P5 R22; #48 run 4 finding 6)" \
  bash -c 'grep -qxF "next: gh pr merge 7 --merge --match-head-commit $2 && gh pr edit 8 --base main" "$1" && ! grep -qF -- "--squash" "$1"' _ "$W/out" "$HEAD_SHA"
ck "…the explanation is a note line, not part of the command" \
  bash -c 'grep -q "^note: PR #8 is stacked on this branch" "$1" && ! grep "^next:" "$1" | grep -qF "stacked"' _ "$W/out"
prs "7 design/x main OPEN alice $HEAD_SHA"
comment REQUEST_CHANGES; nx
ck "a REQUEST_CHANGES: blocked, the findings printed with their URL, no merge command (REQ-385)" \
  bash -c 'grep -q "^state: design blocked" "$1" && grep -q "^findings:" "$1" && grep -qF "an example finding" "$1" && grep -qF "issuecomment-1" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
comment waive; nx --explain
ck "a waiver the PR body does not link: accepted, and --explain says it is not linked (P5 R20)" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qF "not linked from the PR body" "$1"' _ "$W/out"
prs "7 design/x main OPEN alice $HEAD_SHA - https://github.com/o/r/pull/7#issuecomment-1"; nx --explain
ck "…linked: no such line" no has 'not linked from the PR body'
# P7 R4 (REQ-382, REQ-385): /next uses the classifier's waiver rules — a legacy waiver followed by a retarget, or a bound
# waiver whose base gives the head another merge base, never reaches awaiting-merge.
# Covers: REQ-382
printf '[{"event": "base_ref_changed", "created_at": "2026-09-28T11:00:00Z"}]\n' > "$S/timeline-7.json"
prs "7 design/x main OPEN alice $HEAD_SHA"; comment waive; nx --explain
ck "a legacy waiver posted before a later base_ref_changed: never awaiting-merge, --explain names waiver-unbound-retargeted" \
  bash -c '! grep -q "^state: design awaiting-merge" "$1" && grep -qF "waiver-unbound-retargeted" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
rm -f "$S/timeline-7.json"; # (the seed has one commit, so its root IS origin/main's tip: the bound waiver names the head itself, whose merge base with
# the head is the head, not the base's tip — another diff)
comment "waive:$HEAD_SHA"; nx --explain
ck "a bound waiver whose base gives the head another merge base: never awaiting-merge, --explain names waiver-base-mismatch" \
  bash -c '! grep -q "^state: design awaiting-merge" "$1" && grep -qF "waiver-base-mismatch" "$1"' _ "$W/out"
prs "7 design/x main OPEN alice $HEAD_SHA - https://github.com/o/r/pull/7#issuecomment-1"
# PR #48 verifier high (REQ-382, R9; REQ-311): a writing MEMBER's REQUEST_CHANGES whose role lookup fails, next to an
# OWNER's older APPROVE, still blocks through next.sh (never awaiting-merge), and --explain names the failed lookup.
comment APPROVE; cp "$S/comments-7.json" "$W/own.json"; comment REQUEST_CHANGES bob MEMBER
python3 - "$W/own.json" "$S/comments-7.json" <<'PY'
import json, sys
own, rc = json.load(open(sys.argv[1]))[0], json.load(open(sys.argv[2]))[0]
rc.update(id=2, created_at="2026-09-28T10:01:00Z", updated_at="2026-09-28T10:01:00Z", html_url=rc["html_url"].replace("-1", "-2"))
json.dump([own, rc], open(sys.argv[2], "w"))
PY
echo 404 > "$S/perm-bob"; nx --explain
ck "a MEMBER's REQUEST_CHANGES whose role cannot be read, beside an OWNER's older APPROVE: blocked, never awaiting-merge, no merge command" \
  bash -c 'grep -q "^state: design blocked" "$1" && ! grep -q "awaiting-merge" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
ck "…--explain names bob's failed role lookup and why (never silent)" \
  bash -c 'grep -qE "^why: .*bob.*role could not be read.*404" "$1" && grep -qF "request-changes-permission-unknown" "$1"' _ "$W/out"
rm -f "$S/perm-bob"
# PR #48 verifier low (art-review-gate): pr_attestation returning no solo (the Dependabot-exempt path with an unreadable
# base policy) fails safe to team mode — never the checkout's .specflow.yml (solo: true here) — and --explain says so.
(cd "$D" && PATH="$S/bin:$PATH" STUB_DIR="$S" PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/scripts/lib/specflow" > "$W/out" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import attestation, pipeline
attestation.pr_attestation = lambda **k: {"state": "approve", "reason": "exempt-dependabot", "comment_id": None,
                                          "judged": [], "solo": None, "comment": None, "role_unknown": {}}
sys.exit(pipeline.derive_cmd(["--explain"]))
PY
) || true
ck "an attestation with no solo (base policy unreadable): team mode assumed, awaiting-human-review, never the working tree's solo: true" \
  bash -c 'grep -q "^state: design awaiting-human-review" "$1" && ! grep -qF "gh pr merge" "$1" && grep -qE "^why: .*solo false" "$1"' _ "$W/out"
ck "…--explain says the base's solo could not be read and team mode is assumed" \
  bash -c 'grep -qiE "^why: .*could not read .*solo.*team mode" "$1"' _ "$W/out"
# Scoped re-review N3 (REQ-385, art-review-gate): pr_attestation raising AttestationError (the PR's comments or the base
# policy unreadable) fails safe to team mode — solo false, never the checkout's solo: true — with attestation none, and
# --explain says why; no merge command.
# Covers: REQ-385
(cd "$D" && PATH="$S/bin:$PATH" STUB_DIR="$S" PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT/scripts/lib/specflow" > "$W/out" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import attestation, pipeline
def boom(**k):
    raise attestation.AttestationError("stub: comments unreadable")
attestation.pr_attestation = boom
sys.exit(pipeline.derive_cmd(["--explain"]))
PY
) || true
ck "pr_attestation raising AttestationError: solo false (team mode, fail safe), never the working tree's solo: true" \
  bash -c 'grep -qE "^why: branch .*, solo false$" "$1" && grep -q "^state: design awaiting-verifier" "$1"' _ "$W/out"
ck "…--explain says the attestation could not be read, attestation none, team mode assumed" \
  bash -c 'grep -qE "^why: the PR.s attestation could not be read \(stub: comments unreadable\): attestation none; team mode assumed" "$1"' _ "$W/out"
ck "…attestation none (awaiting-verifier) and no merge command" \
  bash -c 'grep -qE "^why: .*: attestation none;" "$1" && ! grep -qE "^why: attestation (approve|waiver)" "$1" && ! grep -qF "gh pr merge" "$1" && ! grep -q "awaiting-merge" "$1"' _ "$W/out"
repo team design/y
(cd "$W" && git clone -q origin.git teambase && cd teambase && printf 'profile: engineer\npath: lanes\nsolo: false\n' > .specflow.yml && git commit -qam team && git push -q origin main)
git -C "$D" fetch -q origin && git -C "$D" rebase -q origin/main && git -C "$D" push -q -f origin design/y; HEAD_SHA=$(git -C "$D" rev-parse HEAD)
prs "7 design/y main OPEN alice $HEAD_SHA -"; comment APPROVE; nx
ck "team mode (solo read at the base): an APPROVE without a human approval is awaiting-human-review, no merge" \
  bash -c 'grep -q "^state: design awaiting-human-review" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
prs "7 design/y main OPEN alice $HEAD_SHA APPROVED"; nx
ck "…with reviewDecision APPROVED: awaiting-merge" has 'state: design awaiting-merge'
prs "7 design/y main OPEN alice $HEAD_SHA -"
printf '{"reviews": [{"author": {"login": "%s"}, "state": "APPROVED", "commit": {"oid": "%s"}}]}\n' alice "$HEAD_SHA" > "$S/reviews-7.json"; nx
ck "…reviewDecision empty, only the author's own approval: still awaiting-human-review (P5 R21(d))" has 'state: design awaiting-human-review'
review() {  # review LOGIN ASSOCIATION — $S/reviews-7.json: one APPROVED review at HEAD_SHA
  printf '{"reviews": [{"author": {"login": "%s"}, "authorAssociation": "%s", "state": "APPROVED", "commit": {"oid": "%s"}}]}\n' "$1" "$2" "$HEAD_SHA" > "$S/reviews-7.json"; }
review bob MEMBER; nx --explain
ck "…reviewDecision empty (no required review), a writing MEMBER's APPROVED review at the head: awaiting-merge, read with gh pr view --json reviews (P5 R21(d))" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qx reviews "$2" && grep -qx "repos/o/r/collaborators/bob/permission" "$2"' _ "$W/out" "$S/gh.argv"
ck "…and --explain says nothing server-side enforces that approval (reviewDecision empty)" has 'nothing server-side enforces'
# PR #48 verifier run 2, code-mode low 3 (REQ-385, REQ-341): a CHANGES_REQUESTED review at any commit that was not
# dismissed (and not followed by the same reviewer's approval) means no human approval, even when reviewDecision is empty.
printf '{"reviews": [{"author": {"login": "bob"}, "authorAssociation": "MEMBER", "state": "CHANGES_REQUESTED", "submittedAt": "2026-09-28T09:00:00Z", "commit": {"oid": "%s"}}, {"author": {"login": "carol"}, "authorAssociation": "OWNER", "state": "APPROVED", "submittedAt": "2026-09-28T10:00:00Z", "commit": {"oid": "%s"}}]}\n' "$(printf '2%.0s' $(seq 40))" "$HEAD_SHA" > "$S/reviews-7.json"; nx --explain
ck "…an undismissed CHANGES_REQUESTED at an earlier commit, beside an OWNER's approval at the head: awaiting-human-review, explained" \
  bash -c 'grep -q "^state: design awaiting-human-review" "$1" && grep -qE "^why: .*bob.*requested changes" "$1"' _ "$W/out"
printf '{"reviews": [{"author": {"login": "bob"}, "authorAssociation": "MEMBER", "state": "CHANGES_REQUESTED", "submittedAt": "2026-09-28T09:00:00Z", "commit": {"oid": "%s"}}, {"author": {"login": "bob"}, "authorAssociation": "MEMBER", "state": "APPROVED", "submittedAt": "2026-09-28T10:00:00Z", "commit": {"oid": "%s"}}]}\n' "$(printf '2%.0s' $(seq 40))" "$HEAD_SHA" > "$S/reviews-7.json"; nx
ck "…the same reviewer's later approval at the head replaces their change request: awaiting-merge" has 'state: design awaiting-merge'
printf '{"reviews": [{"author": {"login": "bob"}, "authorAssociation": "MEMBER", "state": "DISMISSED", "submittedAt": "2026-09-28T09:00:00Z", "commit": {"oid": "%s"}}, {"author": {"login": "carol"}, "authorAssociation": "OWNER", "state": "APPROVED", "submittedAt": "2026-09-28T10:00:00Z", "commit": {"oid": "%s"}}]}\n' "$(printf '2%.0s' $(seq 40))" "$HEAD_SHA" > "$S/reviews-7.json"; nx
ck "…a dismissed change request no longer counts: awaiting-merge" has 'state: design awaiting-merge'
review rando NONE; nx --explain
ck "…an APPROVED review from a user with no repository association (NONE): not the human approval, awaiting-human-review" \
  bash -c 'grep -q "^state: design awaiting-human-review" "$1" && grep -qF "rando" "$1"' _ "$W/out"
review bob MEMBER; echo read > "$S/perm-bob"; nx
ck "…a read-only MEMBER's APPROVED review: awaiting-human-review" has 'state: design awaiting-human-review'
echo 404 > "$S/perm-bob"; nx
ck "…a MEMBER whose role cannot be read: awaiting-human-review (fails closed)" has 'state: design awaiting-human-review'
rm -f "$S/perm-bob"
printf '[{"sha": "%s", "author": {"login": "bob"}, "committer": {"login": "alice"}, "commit": {"author": {"name": "bob", "email": "b@example.invalid"}}}]\n' "$HEAD_SHA" > "$S/commits-7.json"; nx --explain
ck "…an APPROVED review from an author of one of the PR's commits: not the human approval, awaiting-human-review" \
  bash -c 'grep -q "^state: design awaiting-human-review" "$1" && grep -qF "commit" "$1"' _ "$W/out"
rm -f "$S/commits-7.json"
rm -f "$S/reviews-7.json"
repo gone design/z; prs "6 design/z main CLOSED alice $HEAD_SHA" "7 design/z main MERGED alice $HEAD_SHA"; nx
ck "the branch's newest PR decides (#7 merged over #6 closed): design merged, check out main" \
  bash -c 'grep -q "^state: design merged" "$1" && grep -qF "git checkout main && git pull --ff-only" "$1"' _ "$W/out"
prs "7 design/z main CLOSED alice $HEAD_SHA"; nx
ck "a closed, unmerged PR: design closed" has 'state: design closed'
prs "7 design/z main OPEN alice $(printf '2%.0s' $(seq 40))"; rm -f "$S"/comments-*.json; nx --explain
ck "a PR head not in this checkout: attestation none (fail safe), explained" \
  bash -c 'grep -q "^state: design awaiting-verifier" "$1" && grep -qF "not in this checkout" "$1"' _ "$W/out"
prs "7 design/z phase/plan-x OPEN alice $HEAD_SHA" "6 phase/plan-x main OPEN alice $HEAD_SHA"; nx --explain
# SEC-004 (high; dfe-9, dfe-10; REQ-385 as amended by the SEC-004 back-edge): the instruction pipes main's reviewed copy for
# a stacked PR too, and names the base PR as unreviewed; no origin/<base>:scripts/run-verifier.sh ever appears.
ck "a stacked PR whose base was never fetched: awaiting-verifier, the instruction pipes main's reviewed run-verifier.sh and names the unreviewed base PR #6 (P5 R21(b); SEC-004)" \
  bash -c 'grep -q "^state: design awaiting-verifier" "$1" && grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7" "$1" && grep -qF "the base PR #6 is unreviewed; its diff is reviewed by its own PR" "$1" && grep -qF "merge #6 first, then retarget" "$1"' _ "$W/out"
ck "…no origin/<base>:scripts/run-verifier.sh, by any spelling, anywhere in /next's output (SEC-004)" \
  bash -c '! grep -qE "origin/phase/plan-x:scripts/run-verifier|Warning: origin/phase/plan-x" "$1"' _ "$W/out"
ck "…--explain: the base is not in this checkout, so no marker is read (fail safe)" has 'base origin/phase/plan-x not in this checkout'
# PR #48 verifier run 2, code-mode low 2 (REQ-341, REQ-385): with the base or the head missing locally, solo is never the
# working tree's (solo: true here, committed locally only): team mode is assumed, and --explain says so.
printf 'profile: engineer\npath: lanes\nsolo: true\n' > "$D/.specflow.yml"; git -C "$D" commit -qam "solo locally"
prs "7 design/z phase/plan-x OPEN alice $(git -C "$D" rev-parse HEAD)"; nx --explain
ck "…a base missing locally with a working tree that says solo: true: team mode assumed (solo false), explained" \
  bash -c 'grep -qE "^why: .*solo false" "$1" && grep -qiE "^why: .*base origin/phase/plan-x not in this checkout.*team mode assumed" "$1"' _ "$W/out"
prs "7 design/z main OPEN alice $(printf '2%.0s' $(seq 40))"; nx --explain
ck "…a PR head missing locally: team mode assumed too (solo false), explained" \
  bash -c 'grep -qE "^why: .*solo false" "$1" && grep -qiE "^why: .*not in this checkout.*team mode assumed" "$1"' _ "$W/out"
repo reuse phase/validate; prs "5 phase/validate main MERGED alice $(printf '3%.0s' $(seq 40))"; nx --explain
ck "a fixed name reused after a release: the old merged PR #5 (another head) is not this branch's PR — validate gates, never merged (P5 R21(a))" \
  bash -c 'grep -q "^state: validate gates" "$1" && grep -qF "earlier use of this branch name" "$1"' _ "$W/out"
prs "5 phase/validate main MERGED alice $HEAD_SHA"; nx
ck "…the same merged PR at this HEAD is the branch's PR: validate merged" has 'state: validate merged'
repo mainown main; prs "12 build/a-1 main OPEN alice" "15 build/b-1 main OPEN alice" "9 build/c-1 main OPEN bob"; nx
ck "main with the user's open lane PRs: awaiting-merge, check out the lowest own (#12)" \
  bash -c 'grep -q "^state: none awaiting-merge" "$1" && grep -qF "next: gh pr checkout 12" "$1"' _ "$W/out"
ck "…another user's PR is listed with the dfe-10 warning, never proposed" \
  bash -c 'grep "^open lanes:" "$1" | grep -qF "#9 (bob" && grep "^open lanes:" "$1" | grep -qF "dfe-10"' _ "$W/out"
prs "9 build/c-1 main OPEN bob"; nx
ck "main with only another user's open PR: not blocked by it" bash -c '! grep -q "^state: none awaiting-merge" "$1" && grep -q "^open lanes:" "$1"' _ "$W/out"
prs "19 build/a-1 main MERGED alice" "20 ship/0.2.0 main MERGED alice"; nx
# P6 Task 1.5 (REQ-342; P6 R17, R27): a merged ship PR renders /release --tag; only no signer at all (signing-kind none) reaches the unsigned-tag point.
# Covers: REQ-342
nx --explain
ck "a merged ship PR with no tag: ship tag, next: /release --tag 0.2.0 (P6 R17)" \
  bash -c 'grep -q "^state: ship tag" "$1" && grep -qx "next: /release --tag 0.2.0" "$1"' _ "$W/out"
ck "…--explain says which tag kind /release --tag will make, and why" has 'why: tag kind: none ('
nx --profile guided
ck "…no signing key at all (signing-kind none): the unsigned-tag point applies (P6 R17)" has 'confirm: unsigned-tag'
git -C "$D" config user.signingkey /nonexistent.pub; nx --profile guided
ck "…GPG alone is a signer, so no unsigned-tag point: /release --tag stops at exit 5 with the SSH set-up steps (P6 R27; Build 1 final review)" \
  bash -c '! grep -q "^confirm: unsigned-tag" "$1"' _ "$W/out"
git -C "$D" config gpg.format ssh; nx --profile guided
ck "…gpg.format ssh with user.signingkey: no unsigned-tag point" bash -c '! grep -q "^confirm: unsigned-tag" "$1"' _ "$W/out"
git -C "$D" config --unset gpg.format; git -C "$D" config --unset user.signingkey
git -C "$D" tag -a v0.2.0 -m v0.2.0; nx --explain
ck "…once v0.2.0 exists: ready-to-ship ship/0.3.0 (the build PR's merge commit is not in the tag)" \
  bash -c 'grep -q "^state: none ready-to-ship" "$1" && grep -qF "git checkout -b ship/0.3.0" "$1"' _ "$W/out"
ck "…a merge commit missing from the checkout counts as not released, and --explain says so (P5 R21(c))" \
  has 'is not in this checkout: counted as not released'
# Round 3b re-review D4 (REQ-341): the why line names where unbuilt/next_version came from — the merged PRs read
# through gh and this checkout's tags — never "not collected here".
ck "…--explain on main: unbuilt/next_version derived from the merged PRs read through gh and the tags, never 'not collected here'" \
  bash -c 'l=$(grep -E "^why: unbuilt, untagged_ship, next_version, ship_phases_merged:" "$1"); grep -qF "derived from the 2 merged PRs read through gh and this checkout" <<<"$l" && ! grep -qF "not collected here" "$1"' _ "$W/out"
git -C "$D" tag -d v0.2.0 >/dev/null
# PR #48 scoped re-review N5 (REQ-341): the version a merged phase/release PR's docs/releases/<v>-notes.md names is
# validated with the ship/<version> rule (release_gate.py's VERSION_RE); an invalid one derives ExplainUnknown naming
# the file — never a git tag --list pattern (a * would look tagged) and never a rendered tag command.
# Covers: REQ-341
prs "19 build/a-1 main MERGED alice" "21 phase/release main MERGED alice"
echo '{"files": [{"path": "docs/releases/1.0.0;x-notes.md"}]}' > "$S/files-21.json"; nx --json
ck "a merged phase/release PR whose notes file is 1.0.0;x-notes.md: ExplainUnknown naming the file, no tag command" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["step"]["kind"] == "ExplainUnknown", d["step"]
assert "docs/releases/1.0.0;x-notes.md" in d["next_step"], d["next_step"]
assert "tag v" not in d["next_step"] and d["state"]["phase"] != "ready-to-ship", d' "$W/out"
echo '{"files": [{"path": "docs/releases/*-notes.md"}]}' > "$S/files-21.json"; git -C "$D" tag -a v0.2.0 -m v0.2.0; nx --json
ck "…*-notes.md beside a v0.2.0 tag: ExplainUnknown naming the file (a * never looks tagged), never ready-to-ship" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["step"]["kind"] == "ExplainUnknown", d["step"]
assert "docs/releases/*-notes.md" in d["next_step"], d["next_step"]
assert d["state"]["phase"] != "ready-to-ship", d["state"]' "$W/out"
git -C "$D" tag -d v0.2.0 >/dev/null
# Round 3b re-review D2 (REQ-341): the guard mirrors the kernel's lane naming — the tag row's lane is ship on the lanes
# path and release on the regulated path (a wrapper-side fail-safe outside state.dfy).
nx --json
ck "…the bad notes file on the lanes path: state ship tag" python3 -c 'import json, sys; d = json.load(open(sys.argv[1]))["state"]; assert (d["lane"], d["phase"]) == ("ship", "tag"), d' "$W/out"
nx --json --path regulated
ck "…on the regulated path: state release tag (the kernel's regulated tag row), never ship" python3 -c 'import json, sys; d = json.load(open(sys.argv[1]))["state"]; assert (d["lane"], d["phase"]) == ("release", "tag"), d' "$W/out"
# Round 3b re-review D1 (REQ-341): the bad file is flagged only while its PR is not released and no later merged
# phase/release PR names a valid version: a follow-up PR naming one clears it, so the advice can be followed.
echo '{"files": [{"path": "docs/releases/1.0.0;x-notes.md"}]}' > "$S/files-21.json"
echo '{"files": [{"path": "docs/releases/0.3.0-notes.md"}]}' > "$S/files-22.json"
prs "19 build/a-1 main MERGED alice" "21 phase/release main MERGED alice" "22 phase/release main MERGED alice"; nx --json
ck "…a later merged phase/release PR naming 0.3.0, no tag: the tag step /release --tag 0.3.0, never the dead end" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["step"]["kind"] != "ExplainUnknown", d["step"]
assert d["state"]["phase"] == "tag" and d["next_step"] == "/release --tag 0.3.0", d' "$W/out"
git -C "$D" tag -a v0.3.0 -m v0.3.0; nx --json
ck "…with its tag v0.3.0: ready-to-ship, never the dead end" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["step"]["kind"] != "ExplainUnknown" and d["state"]["phase"] == "ready-to-ship", d' "$W/out"
git -C "$D" tag -d v0.3.0 >/dev/null
prs "19 build/a-1 main MERGED alice" "22 phase/release main MERGED alice" "23 phase/release main MERGED alice"
cp "$S/files-21.json" "$S/files-23.json"; nx --json
ck "…a bad notes file merged after the valid one: still ExplainUnknown naming it" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["step"]["kind"] == "ExplainUnknown" and "1.0.0;x-notes.md" in d["next_step"], d' "$W/out"
rm -f "$S/files-21.json" "$S/files-22.json" "$S/files-23.json"
printf -- '---\ntype: plan\nspec: 2026-09-28-habit\n---\n\n## Build 1: a\n\n## Build 2: b\n' > "$D/docs/plans/2026-09-28-habit-plan.md"
git -C "$D" add -A; git -C "$D" commit -qm habit
prs "30 build/habit-1 main MERGED alice"; nx
ck "a plan whose Build 1 merged and Build 2 did not: next-build build/habit-2" \
  bash -c 'grep -q "^state: none next-build" "$1" && grep -qF "git checkout -b build/habit-2" "$1"' _ "$W/out"
# PR #48 scoped re-review N1 (REQ-341, REQ-340; supersedes run 3's name-agnostic rule): on the regulated path a merged
# impl/plan-<token>-<name> PR marks done Build <token> of the plan whose slug is <name> only — the token compared as a
# string, never reduced to digits (1a, 1b and 1 are three tokens); a <name> matching no plan slug counts for nothing and
# --explain names it.
# Covers: REQ-340
prs "30 impl/plan-1-habit main MERGED alice"; nx --path regulated
ck "regulated: a merged impl/plan-1-habit marks the habit plan's Build 1 done: next impl/plan-2-habit" \
  bash -c 'grep -q "^state: none next-build" "$1" && grep -qF "git checkout -b impl/plan-2-habit" "$1"' _ "$W/out"
prs "30 impl/plan-1-something-else main MERGED alice"; nx --path regulated --explain
ck "…a merged impl/plan-1-something-else (no plan has that slug) marks nothing: next impl/plan-1-habit, and --explain names it" \
  bash -c 'grep -qF "git checkout -b impl/plan-1-habit" "$1" && grep -qE "^why: .*impl/plan-1-something-else matches no plan slug" "$1"' _ "$W/out"
prs "30 impl/plan-1a-habit main MERGED alice" "31 impl/plan-1b-habit main MERGED alice"; nx --path regulated
ck "…impl/plan-1a-habit and impl/plan-1b-habit are tokens 1a and 1b, never Build 1: next impl/plan-1-habit" \
  has 'git checkout -b impl/plan-1-habit'
printf -- '---\ntype: plan\nspec: 2026-09-28-garden\n---\n\n## Build 1: a\n' > "$D/docs/plans/2026-09-28-garden-plan.md"
git -C "$D" add -A; git -C "$D" commit -qm garden
prs "30 impl/plan-1-habit main MERGED alice"; nx --path regulated
ck "…two plans with a Build 1: impl/plan-1-habit marks habit's Build 1 only: next impl/plan-1-garden" has 'git checkout -b impl/plan-1-garden'
git -C "$D" rm -q docs/plans/2026-09-28-garden-plan.md; git -C "$D" commit -qm "no garden"
# PR #48 verifier run 3, code low c (REQ-341): a plan slug comes from the file name; one that is not a branch-name token
# (here a shell metacharacter) derives ExplainUnknown naming the file — never a git checkout -b command.
# Covers: REQ-341
BADP='docs/plans/2026-09-28-a;touch pwned-plan.md'
printf -- '---\ntype: plan\nspec: 2026-09-28-a\n---\n\n## Build 1: a\n' > "$D/$BADP"; git -C "$D" add -A; git -C "$D" commit -qm bad
prs "30 build/habit-1 main MERGED alice"; nx
ck "a plan file whose slug has a shell metacharacter: no command, the file named" \
  bash -c 'grep -q "^next: " "$1" && ! grep -qF "git checkout -b" "$1" && grep "^next: " "$1" | grep -qF "$2"' _ "$W/out" "$BADP"
nx --json
ck "…--json: the step is ExplainUnknown" python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d["step"]["kind"] == "ExplainUnknown", d["step"]' "$W/out"
# Scoped re-review N4: the state no longer claims next-build once the proposal became ExplainUnknown.
ck "…--json: the state is unknown-build, never next-build" python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d["state"]["phase"] == "unknown-build", d["state"]' "$W/out"
# Scoped re-review N3: the rendered next_step is an explanation, not a command (it starts with no command word and
# carries no git checkout).
ck "…the rendered next_step is no command" python3 -c '
import json, re, sys
n = json.load(open(sys.argv[1]))["next_step"]
assert not re.match(r"\s*(git|gh|bash|sh|cd|/)\b", n), n
assert "git checkout" not in n and "&&" not in n, n' "$W/out"
nx
ck "…the state: line says build unknown-build (state.dfy's UnknownBuild row is lane build), never next-build" bash -c 'grep -q "^state: build unknown-build" "$1" && ! grep -q "next-build" "$1"' _ "$W/out"
nx --path regulated
ck "…on the regulated path too: build unknown-build (round 3b re-review D2)" bash -c 'grep -q "^state: build unknown-build" "$1" && ! grep -qF "git checkout -b" "$1"' _ "$W/out"
git -C "$D" rm -q "$BADP"; git -C "$D" commit -qm "no bad plan"
TOK='compared as a string, never reduced to digits'; NOM='matches no plan slug'
[ -f "$ROOT/docs/plans/2026-09-28-factory-v3-2-p5-plan.md" ] && ck "the plan's Interfaces \"PR state\" states the strict impl rule (the name must be the plan's slug), never the name-agnostic one" \
  bash -c 'l=$(grep -F "**PR state** (Task 6)" "$1"); grep -qF "a merged \`impl/plan-<token>-<name>\` PR" <<<"$l" && grep -qF "$2" <<<"$l" && grep -qF "$3" <<<"$l" && ! grep -qE "regardless of \`<name>\`|several plans have" <<<"$l"' _ "$ROOT/docs/plans/2026-09-28-factory-v3-2-p5-plan.md" "$TOK" "$NOM"
ck "the glossary's Regulated path entry states the strict impl rule, never the name-agnostic one" \
  bash -c 'e=$(awk "/^### Regulated path$/{f=1; next} /^### /{f=0} f" "$1" | tr "\n" " "); grep -qF "$2" <<<"$e" && grep -qF "$3" <<<"$e" && ! grep -qE "whatever \`<name>\`|several plans" <<<"$e"' _ "$ROOT/docs/GLOSSARY.md" "$TOK" "$NOM"
repo factory main; git -C "$D" rm -q .specflow.yml; mkdir -p "$D/stacks/python"; echo 'stack: python' > "$D/stacks/python/pack.yml"
git -C "$D" add -A; git -C "$D" commit -qm "template source"
cp "$ROOT/tests/governance/fixtures/next/factory-prs.json" "$S/prs.json"; STUB_LOGIN=kpingali123 nx
ck "the factory's own history on main, template source (lanes by default): ready-to-ship ship/0.1.0, with the note" \
  bash -c 'grep -q "^state: none ready-to-ship" "$1" && grep -qF "git checkout -b ship/0.1.0" "$1" && grep -q "^note: template source" "$1"' _ "$W/out"
STUB_LOGIN=kpingali123 nx --path regulated
ck "…with --path regulated: ready-to-ship, phase/validate (P5 R6)" has 'git checkout -b phase/validate'
# N1 (REQ-341, REQ-340): the reviewer's scenario — a P6-style plan with Builds 1–3 beside the factory's merged
# impl/plan-0/1/2/3/4-<name> PRs, none of whose names is the plan's slug: /next proposes Build 1, never ship or validate.
# Covers: REQ-340
printf -- '---\ntype: plan\nspec: 2026-09-29-factory-v3-2-p6\n---\n\n## Build 1: a\n\n## Build 2: b\n\n## Build 3: c\n' \
  > "$D/docs/plans/2026-09-29-factory-v3-2-p6-plan.md"; git -C "$D" add -A; git -C "$D" commit -qm p6
STUB_LOGIN=kpingali123 nx
ck "…a P6-style plan with Builds 1–3 (lanes): next-build build/factory-v3-2-p6-1, never ship" \
  bash -c 'grep -q "^state: none next-build" "$1" && grep -qF "git checkout -b build/factory-v3-2-p6-1" "$1" && ! grep -qF "ship/" "$1"' _ "$W/out"
STUB_LOGIN=kpingali123 nx --path regulated
ck "…(regulated): next-build impl/plan-1-factory-v3-2-p6, never phase/validate" \
  bash -c 'grep -q "^state: none next-build" "$1" && grep -qF "git checkout -b impl/plan-1-factory-v3-2-p6" "$1" && ! grep -qF "phase/validate" "$1"' _ "$W/out"
git -C "$D" rm -q docs/plans/2026-09-29-factory-v3-2-p6-plan.md; git -C "$D" commit -qm "no p6"
repo ghfail design/w; prs "7 design/w main OPEN alice $HEAD_SHA"; STUB_GH_FAIL=1 nx --explain
ck "gh failing with a remote: PR state unknown, no PR proposed, explained (fail safe)" \
  bash -c 'grep -q "^note: cannot see PRs" "$1" && ! grep -qF "gh pr create" "$1" && ! grep -qE "^state: .*awaiting" "$1"' _ "$W/out"
# From here the base is team mode (solo: false, pushed above): reviewDecision APPROVED stands in for the human approval.
repo fork design/f; STUB_FORKS=9 prs "7 design/f main OPEN alice $HEAD_SHA APPROVED" "9 design/f main OPEN mallory $HEAD_SHA APPROVED"; comment APPROVE; nx --explain
ck "a higher-numbered fork PR with the same head branch name is never the branch's PR: the user's own #7 is chosen" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qF "gh pr merge 7 " "$1" && ! grep -qF "gh pr merge 9" "$1" && grep -qF "#9" "$1" && grep -qi "fork" "$1"' _ "$W/out"
STUB_FORKS=11 prs "7 design/f main OPEN alice $HEAD_SHA APPROVED" "11 build/f-1 design/f OPEN mallory"; nx
ck "…and a fork PR based on the branch is not counted as stacked on it" bash -c '! grep -qF "gh pr edit 11" "$1" && grep -qF -- "--squash" "$1"' _ "$W/out"
repo readonly design/r; prs "7 design/r main OPEN alice $HEAD_SHA APPROVED"; comment APPROVE bob MEMBER; echo read > "$S/perm-bob"; nx --explain
ck "a hand-posted APPROVE marker from a read-only MEMBER is not accepted: awaiting-verifier, marker-not-writer explained, no merge" \
  bash -c 'grep -q "^state: design awaiting-verifier" "$1" && grep -qF "marker-not-writer" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
rm -f "$S/perm-bob"; nx --explain
ck "…from a writing MEMBER: accepted, and --explain names who posted the decisive comment" \
  bash -c 'grep -q "^state: design awaiting-merge" "$1" && grep -qE "^why: .*posted by bob \(MEMBER" "$1"' _ "$W/out"
# The retarget (finding 14): impl stacked on a plan branch whose commit no review saw; the marker reviewed plan..impl only.
D="$W/retarget"; git clone -q "$W/origin.git" "$D"
git -C "$D" checkout -q -b phase/plan-adv; echo x > "$D/adv-x.txt"; git -C "$D" add -A; git -C "$D" commit -qm "X"; git -C "$D" push -q origin phase/plan-adv
git -C "$D" checkout -q -b impl/plan-8-adv; echo y > "$D/adv-y.txt"; git -C "$D" add -A; git -C "$D" commit -qm "Y"; git -C "$D" push -q origin impl/plan-8-adv
HEAD_SHA=$(git -C "$D" rev-parse HEAD)
prs "7 impl/plan-8-adv phase/plan-adv OPEN alice $HEAD_SHA APPROVED"; comment APPROVE alice OWNER origin/phase/plan-adv; nx
ck "a stacked PR with an APPROVE against its own base: awaiting-merge" has 'state: impl awaiting-merge'
# Wave-4 re-review low 1 (REQ-385): nested stack — #9 stacked on this PR, which is itself stacked on phase/plan-adv. #9 is
# retargeted to THIS PR's own base, never main (a retarget to main would turn its marker base-mismatch).
prs "7 impl/plan-8-adv phase/plan-adv OPEN alice $HEAD_SHA APPROVED" "9 impl/plan-9-adv impl/plan-8-adv OPEN alice"; nx
ck "…with #9 stacked on it: the merge commit, then #9 retargeted to this PR's own base (phase/plan-adv), not main" \
  bash -c 'grep -qxF "next: gh pr merge 7 --merge --match-head-commit $2 && gh pr edit 9 --base phase/plan-adv" "$1" && grep -q "^note: PR #9 is stacked on this branch.*retargeted to phase/plan-adv" "$1"' _ "$W/out" "$HEAD_SHA"
prs "7 impl/plan-8-adv phase/plan-adv OPEN alice $HEAD_SHA APPROVED"
prs "7 impl/plan-8-adv main OPEN alice $HEAD_SHA APPROVED"; nx --explain
ck "…retargeted to main while its plan branch is unmerged: the old marker is refused (base-mismatch), awaiting-verifier, no merge" \
  bash -c 'grep -q "^state: impl awaiting-verifier" "$1" && grep -qF "base-mismatch" "$1" && ! grep -qF "gh pr merge" "$1"' _ "$W/out"
# PR #48 verifier run 2, code-mode high (REQ-311, REQ-385): base-mismatch refuses only an APPROVE's acceptance; a newer
# REQUEST_CHANGES recorded against the old base still blocks an older APPROVE against the current base, and a newer
# matching APPROVE supersedes it.
comment APPROVE alice OWNER origin/main; cp "$S/comments-7.json" "$W/bm-ap.json"
comment REQUEST_CHANGES alice OWNER origin/phase/plan-adv; cp "$S/comments-7.json" "$W/bm-rc.json"
bm_two() {  # bm_two OLDER NEWER — $S/comments-7.json: the two one-comment files, the second one minute newer
  python3 - "$1" "$2" "$S/comments-7.json" <<'PY'
import json, sys
a, b = json.load(open(sys.argv[1]))[0], json.load(open(sys.argv[2]))[0]
b.update(id=2, created_at="2026-09-28T10:01:00Z", updated_at="2026-09-28T10:01:00Z", html_url=b["html_url"].replace("-1", "-2"))
json.dump([a, b], open(sys.argv[3], "w"))
PY
}
bm_two "$W/bm-ap.json" "$W/bm-rc.json"; nx --explain
ck "…a newer REQUEST_CHANGES recorded against the old base, beside an older APPROVE against main: blocked, no merge (request-changes-base-mismatch)" \
  bash -c 'grep -q "^state: impl blocked" "$1" && ! grep -qF "gh pr merge" "$1" && grep -qF "request-changes-base-mismatch" "$1"' _ "$W/out"
bm_two "$W/bm-rc.json" "$W/bm-ap.json"; nx
ck "…a newer APPROVE against main supersedes it: awaiting-merge" has 'state: impl awaiting-merge'
repo secslug main
printf -- '---\ntype: plan\nspec: 2026-09-28-sec-x\n---\n\n## Build 1: a\n' > "$D/docs/plans/2026-09-28-sec-x-plan.md"; git -C "$D" add -A; git -C "$D" commit -qm sec-x
prs "40 build/greet-1 main MERGED alice"; nx --explain
ck "a plan whose slug starts with sec- is not proposed as build/sec-<slug>-N (it would parse as the back-edge): no next-build loop, explained" \
  bash -c '! grep -qF "build/sec-x-1" "$1" && ! grep -q "^state: none next-build" "$1" && grep -qE "^why: .*sec-" "$1"' _ "$W/out"
ck "pipeline.py reads no marker or waiver itself: its only route to an attestation is attestation.pr_attestation (REQ-311)" \
  python3 - "$ROOT/scripts/lib/specflow/pipeline.py" <<'PY'
import ast, sys
src = open(sys.argv[1]).read()
assert "specflow-verifier" not in src, "pipeline.py spells the marker prefix"
calls = set()
for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.Call):
        calls.add(n.func.attr if isinstance(n.func, ast.Attribute) else getattr(n.func, "id", ""))
    if isinstance(n, ast.ImportFrom) and (n.module or "").split(".")[-1] == "attestation":
        assert {a.name for a in n.names} <= {"pr_attestation"}, [a.name for a in n.names]
assert not calls & {"parse_marker", "_judge_comment", "classify"}, sorted(calls & {"parse_marker", "_judge_comment", "classify"})
assert "pr_attestation" in calls, "pipeline.py never calls attestation.pr_attestation"
PY
# PR #48 CI env audit (REQ-341): /next reads the PRs of this checkout's own repository — gh never gets a GH_REPO from the
# environment (it would point every gh call at another repository), nor does CI's SPECFLOW_HEAD_BRANCH name the branch.
# Covers: REQ-341
repo ghr design/ghr; prs "7 design/ghr main OPEN alice $HEAD_SHA"; rm -f "$S"/comments-*.json "$S/gh.env"
rc=0; rm -f "$S/gh.argv"; (cd "$D" && GH_REPO=evil/other SPECFLOW_HEAD_BRANCH=impl/plan-9-x PATH="$S/bin:$PATH" STUB_DIR="$S" \
  bash scripts/next.sh) > "$W/out" 2>&1 || rc=$?
ck "GH_REPO in the environment never reaches gh; the branch is still design/ghr (awaiting-verifier)" \
  bash -c '[ ! -e "$1" ] && grep -q "^state: design awaiting-verifier" "$2" && grep -q "issues/7/comments" "$3"' _ "$S/gh.env" "$W/out" "$S/gh.argv"

# P5 lows patch (PR #48 verifier run 7, code finding 3; REQ-385, REQ-341): next.sh never fetches, so a stale origin/<base>
# means the policy, prompt hash and marker are judged at an older base than CI's. gh's baseRefOid differing from the
# checkout's origin/<base> prints a note (always) and a why line (--explain) naming both and the fetch; equal: nothing.
repo stale design/stale; rm -f "$S"/comments-*.json; comment APPROVE
STUB_BASE_OID=ffffffffffffffffffffffffffffffffffffffff prs "7 design/stale main OPEN alice $HEAD_SHA"; nx --explain
ck "a stale origin/main (gh's baseRefOid differs): a note names both tips and git fetch origin main" \
  bash -c 'grep -qE "^note: origin/main here is at [0-9a-f]{7}, but GitHub.s main is at fffffff: this checkout.s base is stale \(git fetch origin main\)" "$1"' _ "$W/out"
ck "…and --explain says the marker, policy and prompt hash were judged at the local copy" \
  bash -c 'grep -qE "^why: .*judged at this checkout.s origin/main, not the base CI reads" "$1"' _ "$W/out"
STUB_BASE_OID=$(git -C "$D" rev-parse origin/main) prs "7 design/stale main OPEN alice $HEAD_SHA"; nx --explain
ck "…gh's baseRefOid equal to origin/main: no stale-base note" no has "this checkout's base is stale"

finish test_next_prs
