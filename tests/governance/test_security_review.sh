#!/usr/bin/env bash
# REQ-332: docs/security/<version>-review.md carries a mandatory "## Tools run" section — each floor tool with version,
# exit status and a one-line result, and every active suppression with its SEC-NNN — rendered by floor.py from the
# floor's summary and checked against it (an evidence digest over the rows; a commit in the repository's history); a
# review listing only manual review fails when the product has a lockfile (the pack's lockfiles; scripts/requirements.txt
# alone does not count). render refuses a summary that is not evidence. SEC ids are unique by definition, not by mention.
# Covers: REQ-332
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
FP="$ROOT/scripts/lib/specflow/floor.py"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
G="$W/g"; mkdir -p "$G"; (cd "$G" && git init -q -b main && echo x > a && git add a && git commit -qm a)
HS=$(git -C "$G" rev-parse HEAD)
summary() {  # summary MODE COMMIT ERRORS TOOL… — TOOL is name|scope|exit|status|result ("-": not run); one suppression
  python3 - "$@" > "$W/sum.json" <<'PY'
import json, sys
mode, commit, errors = sys.argv[1:4]
ver = {"gitleaks": "8.30.1", "osv-scanner": "2.6.0", "pip-audit": "2.10.1", "bandit": "1.9.4"}
tools = []
for spec in sys.argv[4:]:
    name, scope, ex, status, result = spec.split("|")
    tools.append({"tool": name, "scope": scope, "version": ver[name], "exit": None if ex == "-" else int(ex),
                  "status": status, "result": result, "command": name})
print(json.dumps({"schema": 1, "generated_at": "2026-09-26T20:00:00Z", "commit": commit, "dirty": False, "mode": mode,
  "stack": "python", "tools": tools,
  "suppressions": [{"file": "src-tauri/audit.toml", "line": 11, "kind": "cargo-audit", "id": "RUSTSEC-2024-0370",
                    "name": "RUSTSEC-2024-0370", "sec": "SEC-002"}],
  "suppression_errors": [e for e in errors.split(";") if e]}))
PY
}
GL='gitleaks|.|0|pass|clean'; OS='osv-scanner|.|0|pass|clean'; ONA='osv-scanner|.|-|not-applicable|not run — no tracked lockfile'
PA='pip-audit|requirements.txt|0|pass|clean'; BA='bandit|src|0|pass|clean'
render() { rc=0; md=$(cd "${RD:-$G}" && python3 "$FP" render --summary "$W/sum.json" --root . 2>"$W/render.err") || rc=$?; }
sub() { python3 -c 'import sys; p, a, b = sys.argv[1:4]; t = open(p).read(); assert a in t, a; open(p, "w").write(t.replace(a, b, 1))' "$@"; }
nosub() { python3 -c 'import sys; print(sys.stdin.read().split("\n### Active suppressions")[0])'; }

summary online "$HS" '' "$GL" "$OS"; render
ck "render: exit 0 for an online summary of HEAD" [ "$rc" = 0 ]
ck "render: '## Tools run' heading" grep -qx '## Tools run' <<<"$md"
ck "render: the tools table header" grep -qxF '| Tool | Scope | Version | Exit | Result |' <<<"$md"
ck "render: one row per tool with version and exit" bash -c 'grep -qxF "| gitleaks | . | 8.30.1 | 0 | clean |" <<<"$1" && grep -qxF "| osv-scanner | . | 2.6.0 | 0 | clean |" <<<"$1"' _ "$md"
ck "render: '### Active suppressions' with each SEC-NNN" bash -c 'grep -qx "### Active suppressions" <<<"$1" && grep -qxF "| src-tauri/audit.toml | 11 | RUSTSEC-2024-0370 | SEC-002 |" <<<"$1"' _ "$md"
ck "render: names the summary's commit" grep -qF "$HS" <<<"$md"
ck "render: the evidence line (a sha256 over the commit and the rows)" grep -qE '^Floor evidence: rows sha256 [0-9a-f]{64}\.$' <<<"$md"
summary online "$HS" '' "$GL" "$ONA"; render
ck "render: a tool that was not run prints '-' in the Exit cell" grep -qxF '| osv-scanner | . | 2.6.0 | - | not run — no tracked lockfile |' <<<"$md"
mkdir -p "$G/docs/security"; RG="$G/docs/security/0.1.0-review.md"; NA="$md"
rg() { printf '# Security Review — v0.1.0\n\n## Summary\n0 findings.\n\n%s\n' "$1" > "$RG"; }
crg() { rc=0; out=$(python3 "$FP" check-review "$RG" --root "$G" 2>&1) || rc=$?; }
rg "$NA"; crg
ck "round trip: a rendered section, with a tool not run, passes check-review" [ "$rc" = 0 ]
sub "$RG" '| gitleaks | . | 8.30.1 | 0 | clean |' '| gitleaks | . | 8.30.1 | 0 | clean (manual check) |'; crg
ck "a hand-edited row fails: the evidence digest no longer matches" bash -c '[ "$1" = 1 ] && grep -qi digest <<<"$2"' _ "$rc" "$out"
rg "$NA"; sub "$RG" '| - | not run — no tracked lockfile |' '| - | clean |'; crg
ck "a '-' exit is accepted only with the result 'not run — no tracked lockfile'" bash -c '[ "$1" = 1 ] && grep -qi exit <<<"$2"' _ "$rc" "$out"
summary offline "$HS" '' "$GL" 'osv-scanner|.|-|skipped-offline|SPECFLOW_FLOOR_OFFLINE=1'; render
ck "render refuses an offline summary (not evidence)" [ "$rc" = 1 ]
summary online "$(printf '0%.0s' $(seq 40))" '' "$GL" "$OS"; render
ck "render refuses a summary of another commit (stale)" [ "$rc" = 1 ]
summary online "$HS" '' "$GL" 'osv-scanner|.|127|lookup-failed|lookup failed — no such host'; render
ck "render refuses a summary with a failed lookup (no evidence)" [ "$rc" = 1 ]
summary online "$HS" 'src-tauri/audit.toml:3: RUSTSEC-2099-0003 is not in the suppresses: of SEC-001' "$GL" "$OS"; render
ck "render refuses a summary with suppression errors, listing them" bash -c '[ "$1" = 1 ] && grep -q RUSTSEC-2099-0003 "$2"' _ "$rc" "$W/render.err"

R="$W/r"; mkdir -p "$R/docs/security" "$R/.specflow" "$R/scripts"; : > "$R/scripts/requirements.txt"
(cd "$R" && git init -q -b main && git add -A && git commit -qm r); HR=$(git -C "$R" rev-parse HEAD)
RV="$R/docs/security/0.1.0-review.md"
rev() { printf '# Security Review — v0.1.0\n\n## Summary\n0 findings.\n\n%s\n' "$1" > "$RV"; }
cr() { rc=0; out=$(python3 "$FP" check-review "$RV" --root "$R" 2>&1) || rc=$?; }
rev $'## Findings\nNone.'; cr
ck "a review with no '## Tools run' section fails" bash -c '[ "$1" = 1 ] && grep -q "Tools run" <<<"$2"' _ "$rc" "$out"
rev $'## Tools run\n- Manual review by reviewer: @alice'; cr
ck "manual-only with no product lockfile passes (scripts/requirements.txt alone does not count)" [ "$rc" = 0 ]
summary online "$HR" '' "$GL" "$OS"; RD="$R" render; rev "$(nosub <<<"$md")"; cr
ck "a tools table without '### Active suppressions' fails even with no product lockfile" bash -c '[ "$1" = 1 ] && grep -q "Active suppressions" <<<"$2"' _ "$rc" "$out"
printf 'stack: python\nlockfiles: [requirements.txt]\nfloor_tools: [pip-audit, bandit]\n' > "$R/.specflow/pack.yml"; : > "$R/requirements.txt"
rev $'## Tools run\n- Manual review by reviewer: @alice'; cr
ck "manual-only when the pack's lockfile exists fails" bash -c '[ "$1" = 1 ] && grep -qi "manual" <<<"$2"' _ "$rc" "$out"
summary online "$HR" '' "$GL" "$OS" "$PA" "$BA"; RD="$R" render; FULL="$md"; rev "$FULL"; cr
ck "a rendered table with gitleaks, osv-scanner and the pack's floor_tools passes" [ "$rc" = 0 ]
summary online "$HR" '' "$GL" "$OS" "$PA"; RD="$R" render; rev "$md"; cr
ck "a missing pack floor tool row fails, naming it" bash -c '[ "$1" = 1 ] && grep -q bandit <<<"$2"' _ "$rc" "$out"
rev "$FULL"; sub "$RV" '| requirements.txt | 2.10.1 | 0 |' '| requirements.txt |  | 0 |'; cr
ck "a row without a version fails" bash -c '[ "$1" = 1 ] && grep -qi version <<<"$2"' _ "$rc" "$out"
rev "$FULL"; sub "$RV" '| requirements.txt | 2.10.1 | 0 |' '| requirements.txt | 2.10.1 | ok |'; cr
ck "a row without a numeric exit status fails" bash -c '[ "$1" = 1 ] && grep -qi exit <<<"$2"' _ "$rc" "$out"
rev "$(nosub <<<"$FULL")"; cr
ck "a missing '### Active suppressions' subsection fails" bash -c '[ "$1" = 1 ] && grep -q "Active suppressions" <<<"$2"' _ "$rc" "$out"
rev "$FULL"; sub "$RV" '| SEC-002 |' '| 002 |'; cr
ck "a suppression row without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q "SEC" <<<"$2"' _ "$rc" "$out"
summary online "$HS" '' "$GL" "$OS" "$PA" "$BA"; render; rev "$md"; cr
ck "a section rendered at a commit outside this repository's history fails" bash -c '[ "$1" = 1 ] && grep -qi ancestor <<<"$2"' _ "$rc" "$out"

# P4 final review: a provenance line ("scratch instance of template commit <40-hex>") may name a commit absent from
# --root's history only for a pack-shipped review (--pack, or a *-skeleton-review.md an instance received from its
# pack); any other review must name a commit in the history, so the line cannot excuse a review from the rule.
ABSENT=$(printf 'f%.0s' $(seq 40)); PROV="Floor run on a scratch instance of template commit $ABSENT (working tree)."
summary online "$HS" '' "$GL" "$OS" "$PA" "$BA"; render; PMD=$(awk -v p="$PROV" 'NR == 1 {print; print ""; print p; next} {print}' <<<"$md")
rev "$PMD"; cr
ck "a provenance line naming a commit absent from the repository does not excuse an ordinary review" \
  bash -c '[ "$1" = 1 ] && grep -qF "$3" <<<"$2"' _ "$rc" "$out" "$ABSENT"
rc=0; out=$(python3 "$FP" check-review "$RV" --root "$R" --pack "$R/.specflow/pack.yml" 2>&1) || rc=$?
ck "…while a pack-shipped review (--pack) may name the template commit it was rendered from" [ "$rc" = 0 ]
SKR="$R/docs/security/0.0.0-skeleton-review.md"; cp "$RV" "$SKR"
rc=0; out=$(python3 "$FP" check-review "$SKR" --root "$R" 2>&1) || rc=$?; rm -f "$SKR"
ck "…as may a *-skeleton-review.md an instance received from its pack" [ "$rc" = 0 ]
# PR #74 (main at 3fbba23): a squash merge removes the template branch's commits from main's history, but a clone
# that fetched the branch still holds the object, so "absent from the repository" (cat-file) and "absent from
# HEAD's history" (ancestry) differ: the tauri skeleton review's template commit 7f20c16 passed in CI's fresh clone
# and failed every local gates run. A shipped review's provenance commit is accepted when it is not an ancestor of
# HEAD whether or not the object is still in the store; an ordinary review is still refused either way.
# Covers: REQ-332
(cd "$R" && git checkout -q -b side && echo s > side.txt && git add side.txt && git commit -qm side && git checkout -q main)
SIDE=$(git -C "$R" rev-parse side); PROV2="Floor run on a scratch instance of template commit $SIDE (working tree)."
rev "$(awk -v p="$PROV2" 'NR == 1 {print; print ""; print p; next} {print}' <<<"$md")"
rc=0; out=$(python3 "$FP" check-review "$RV" --root "$R" --pack "$R/.specflow/pack.yml" 2>&1) || rc=$?
ck "a pack-shipped review naming a template commit the store holds but HEAD's history does not (a squash-merged branch) passes" [ "$rc" = 0 ]
cp "$RV" "$SKR"; rc=0; out=$(python3 "$FP" check-review "$SKR" --root "$R" 2>&1) || rc=$?; rm -f "$SKR"
ck "…and so does the *-skeleton-review.md copy of it" [ "$rc" = 0 ]
cr
ck "an ordinary review with that provenance line and a foreign Floor summary is still refused (the line is ignored, as the ABSENT case above pins)" bash -c '[ "$1" = 1 ] && grep -qi ancestor <<<"$2"' _ "$rc" "$out"
# PR #36 second run, medium (REQ-332): the provenance path counts for shipped reviews only — an ordinary review whose
# provenance line names an ancestor of HEAD still has its Floor summary: commit checked, so a foreign summary fails.
summary online "$HS" '' "$GL" "$OS" "$PA" "$BA"; render
rev "$(awk -v p="Floor run on a scratch instance of template commit $HR (x)." 'NR == 1 {print; print ""; print p; next} {print}' <<<"$md")"; cr
ck "an ordinary review with a provenance line naming an ancestor but a foreign Floor summary: commit is rejected" \
  bash -c '[ "$1" = 1 ] && grep -qF "$3" <<<"$2" && grep -qi ancestor <<<"$2"' _ "$rc" "$out" "$HS"
SRMD=$(tr '\n' ' ' < "$ROOT/docs/security/README.md" | tr -s ' ')
for w in 'The provenance line counts for shipped reviews only' 'stacks/*/overlay/docs/security/' \
         'docs/security/0.0.1-demo-review.md' 'every other review' 'its `Floor summary:` commit must be HEAD or an ancestor'; do
  ck "docs/security/README.md limits the provenance path to shipped reviews: '$w'" grep -qF -- "$w" <<<"$SRMD"
done
ck "docs/security/README.md names floor.py check-review, not a nonexistent check-review.sh" \
  bash -c '! grep -qF "check-review.sh" "$1" && grep -qF "floor.py check-review" "$1"' _ "$ROOT/docs/security/README.md"
ck "docs/security/README.md states the pack-shipped provenance exception" grep -qF 'skeleton-review.md' "$ROOT/docs/security/README.md"
# P4 final review: a released review is never rewritten in place — the demo's floor run is a dated addendum after
# its original Tools run lines (art-threat-driven-security: SECURITY artifacts are versioned per re-entry).
DR="$ROOT/docs/security/0.0.1-demo-review.md"
if [ -f "$DR" ]; then
  ck "the released demo review keeps its original Tools run lines first; the floor run is a dated addendum after them" python3 - "$DR" <<'PY'
import sys
t = open(sys.argv[1]).read()
a = t.index("## Tools run\n- Manual review by reviewer: @apingali\n")
b = t.index("### Addendum 2026-09-27 (P4): security floor run")
c = t.index("| Tool | Scope | Version | Exit | Result |")
assert a < b < c, (a, b, c)
PY
fi
# #36 medium 2 (art-threat-driven-security: SECURITY artifacts are versioned per re-entry): the demo review's
# post-tag floor addendum is a recorded one-off exception — docs/security/README.md says only the demo may carry one,
# why, and that every later release produces a new versioned review; the addendum points at that record.
SRM=$(tr '\n' ' ' < "$ROOT/docs/security/README.md" | tr -s ' ')
for w in 'one-off exception' '0.0.1-demo-review.md' 'after its tag' 'new versioned review'; do
  ck "docs/security/README.md records the post-tag addendum exception: '$w'" grep -qF -- "$w" <<<"$SRM"
done
if [ -f "$DR" ]; then
  ck "the demo review's addendum cites the one-off exception in docs/security/README.md" \
    bash -c 'tr "\n" " " < "$1" | tr -s " " | grep -qF "one-off exception recorded in docs/security/README.md"' _ "$DR"
fi
# PR #36 second run, medium (REQ-332): the demo addendum says what its gitleaks and osv-scanner rows cover.
if [ -f "$DR" ]; then
  for w in "gitleaks and osv-scanner rows cover the scratch instance's history and lockfiles, not this repository's" \
           "this repository's own floor runs in every gates job"; do
    ck "the demo addendum states its rows' scope: '$w'" bash -c 'tr "\n" " " < "$1" | tr -s " " | grep -qF -- "$2"' _ "$DR" "$w"
  done
fi
# #36 medium 3: a provenance line names the committed template revision the floor ran at — never "(working tree)",
# which render refuses — and its "Floor run <date>" agrees with the rendered summary's generated date.
prov_ok() { python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
if "scratch instance of template commit" not in t:
    sys.exit(0)
assert "(working tree)" not in t, "provenance says (working tree)"
run = re.search(r"Floor run (\d{4}-\d{2}-\d{2})", t)
gen = re.search(r"generated (\d{4}-\d{2}-\d{2})T", t)
assert run and gen and run.group(1) == gen.group(1), (run and run.group(1), gen and gen.group(1))
PY
}
shopt -s nullglob
for f in "$ROOT"/docs/security/*-review.md "$ROOT"/stacks/*/overlay/docs/security/*-review.md; do
  ck "${f#$ROOT/}: provenance names a commit (no working tree) and its floor-run date matches the summary" prov_ok "$f"
done
shopt -u nullglob
shopt -s nullglob
for f in "$ROOT"/docs/security/*-review.md; do ck "${f#$ROOT/} has a valid '## Tools run'" python3 "$FP" check-review "$f" --root "$ROOT"; done
if ! instance; then
  for f in "$ROOT"/stacks/*/overlay/docs/security/*-review.md; do
    r="${f%/docs/security/*}"; ck "${f#$ROOT/} (pack-shipped) has a valid '## Tools run'" python3 "$FP" check-review "$f" --root "$r" --pack "${r%/overlay}/pack.yml"
  done
fi
shopt -u nullglob
SR="$ROOT/.claude/commands/security-review.md"
ck "/security-review runs the floor first" grep -qF 'bash scripts/run-security-floor.sh' "$SR"
ck "/security-review pastes floor.py render's output (never a paraphrase)" grep -qF 'floor.py render' "$SR"
ck "/security-review checks the review with floor.py check-review and check-suppressions.sh" bash -c 'grep -qF "floor.py check-review" "$1" && grep -qF "check-suppressions.sh" "$1"' _ "$SR"
ck "/security-review: SEC ids continue after the highest defined and are never reused" grep -qi 'never reuse' "$SR"
ck "/security-review: a suppression's disposition entry lists the ids in suppresses:" grep -qF 'suppresses:' "$SR"

T="$W/trace"; mkdir -p "$T/docs/security" "$T/docs/specs" "$T/docs/plans"
printf -- '# R1\n\n---\nid: SEC-001\nseverity: low\n---\n' > "$T/docs/security/0.0.0-skeleton-review.md"
printf -- '# R2\n\n## Tools run\n\n| File | Line | Id | SEC |\n|---|---|---|---|\n| a | 1 | X | SEC-001 |\n' > "$T/docs/security/0.1.0-review.md"
ck "citing an earlier SEC id in a later review is a reference, not a duplicate" env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
printf -- '\n---\nid: SEC-001\nseverity: low\n---\n' >> "$T/docs/security/0.1.0-review.md"
ck "defining the same SEC id in two reviews still fails" no env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
# P5 R17 (H12, H13; REQ-332, REQ-331 as context): the floor's thresholds stay REQ-331's; /security-review runs each
# thresholded tool once more a level lower and records what it finds as findings; a table-less Tools run is conformant
# where the product has no pack lockfile (the template source's demo) and fails where it has one.
# Covers: REQ-332
if [ -d "$ROOT/stacks/python" ]; then
  ck "python's security hook keeps bandit --severity-level high" grep -qF -- '--severity-level high' "$ROOT/stacks/python/security.sh"
  ck "tauri's security hook keeps npm audit --audit-level=high" grep -qF -- '--audit-level=high' "$ROOT/stacks/tauri/security.sh"
fi
SRC=$(tr '\n' ' ' < "$ROOT/.claude/commands/security-review.md")
ck "/security-review runs bandit at medium and npm audit at moderate, recording the results as findings" \
  bash -c 'grep -qF -- "--severity-level medium" <<<"$1" && grep -qF -- "--audit-level=moderate" <<<"$1" && grep -qi "record each result as a finding" <<<"$1"' _ "$SRC"
ck "docs/security/README.md: below the floor's threshold needs no SEC-NNN suppression" \
  grep -qi 'below the floor.s threshold needs no' "$ROOT/docs/security/README.md"
T13="$W/h13"; mkdir -p "$T13/docs/security"
printf '## Tools run\n\nManual review only.\n\n## Findings\n\nNone.\n' > "$T13/docs/security/9.9.9-review.md"
ck "a table-less Tools run passes check-review where the product has no pack lockfile (the template source's case)" \
  python3 "$FP" check-review "$T13/docs/security/9.9.9-review.md" --root "$T13"
mkdir -p "$T13/.specflow"; printf 'lockfiles: [uv.lock]\n' > "$T13/.specflow/pack.yml"; : > "$T13/uv.lock"
ck "…and fails once the pack's lockfile exists" no python3 "$FP" check-review "$T13/docs/security/9.9.9-review.md" --root "$T13"

# REQ-332, REQ-340, art-branch-as-state (the factory's first squash-merged ship PR, #62, 2026-10-03): squash merges are permitted, and a
# squash merge drops the branch commits, so a released review's Floor summary names a commit that main's history
# never holds. check-review accepts that commit only once the review's version is released — tag v<version> on
# HEAD's history — and still requires the evidence digest; untagged, or with the tag off this history, it fails,
# naming the squash-merge-to-tag window. Reproduced with a real squash merge (main was red at 9f6c685).
# Covers: REQ-332
# Covers: REQ-340
# Final review finding 7 (BL-040): floor.py's exemption comment keeps REQ-340, the REQ whose body permits squash
# merges, beside the article slug.
ck "floor.py's squash-merge exemption comment cites REQ-340 beside art-branch-as-state" \
  grep -qF '# REQ-340, art-branch-as-state: squash merges are permitted' "$FP"
SQ="$W/sq"; mkdir -p "$SQ"; (cd "$SQ" && git init -q -b main && echo x > a && git add a && git commit -qm a)
(cd "$SQ" && git checkout -q -b ship/0.2.0 && echo y > b && git add b && git commit -qm b)
HB=$(git -C "$SQ" rev-parse HEAD)
summary online "$HB" '' "$GL" "$OS"; RD="$SQ" render; unset RD
mkdir -p "$SQ/docs/security"; printf '# Security Review — v0.2.0\n\n## Summary\n0 findings.\n\n%s\n' "$md" > "$SQ/docs/security/0.2.0-review.md"
(cd "$SQ" && git add -A && git commit -qm review && git checkout -q main && git merge -q --squash ship/0.2.0 && git commit -qm "squash" && git branch -q -D ship/0.2.0)
csq() { rc=0; out=$(python3 "$FP" check-review "$SQ/docs/security/0.2.0-review.md" --root "$SQ" 2>&1) || rc=$?; }
csq
ck "squash-merged, untagged: check-review fails, naming the squash-merge-to-tag window (the commit is gone from history)" bash -c '[ "$1" = 1 ] && grep -qi "squash" <<<"$2" && grep -qF "v0.2.0" <<<"$2"' _ "$rc" "$out"
(cd "$SQ" && git tag v0.2.0)
csq
ck "squash-merged and tagged v0.2.0 on HEAD: the released review passes (the digest still checked)" [ "$rc" = 0 ]
sub "$SQ/docs/security/0.2.0-review.md" '| gitleaks | . | 8.30.1 | 0 | clean |' '| gitleaks | . | 8.30.1 | 0 | clean (edited) |'; csq
ck "squash-merged and tagged, but a row edited: the digest mismatch still fails" bash -c '[ "$1" = 1 ] && grep -qi digest <<<"$2"' _ "$rc" "$out"
(cd "$SQ" && git checkout -q -- docs/security/0.2.0-review.md)
# PR #66 verifier run 1 (medium): "frozen" is a mechanism, not a comment — the released exemption holds only while the
# working copy is byte-identical to the tag's copy (git show v<version>:<path>); an edit outside the rows leaves the
# digest intact, so the digest alone would not catch it.
# Covers: REQ-332
printf '\nEdited after the tag.\n' >> "$SQ/docs/security/0.2.0-review.md"; csq
ck "squash-merged and tagged, but the file differs from v0.2.0's copy (an edit outside the rows): fails, naming the tag" bash -c '[ "$1" = 1 ] && grep -qF "v0.2.0" <<<"$2" && grep -qi "differs\|identical" <<<"$2"' _ "$rc" "$out"
(cd "$SQ" && git checkout -q -- docs/security/0.2.0-review.md && git tag -d v0.2.0 >/dev/null && git checkout -q -b other "$(git rev-list --max-parents=0 HEAD)" && echo z > c && git add c && git commit -qm c && git tag v0.2.0 && git checkout -q main)
csq
ck "squash-merged with v0.2.0 on another history (not an ancestor of HEAD): fails" [ "$rc" = 1 ]

# BL-040 (PR #66 verifier run 2): check-review's three untested refusals. Each is reached through the squash-merge
# fixture: the Floor summary commit is not an ancestor of HEAD, so the released exemption is tried and refused.
# The first two print _released_on_head's reason (the tag is moved back to HEAD for them); the third, a name with
# no version, reaches _released_on_head too, but _cmd_check_review appends its reason only when the name carries a
# version, so the plain ancestry refusal is printed with no squash-merge note. A pin of existing behaviour.
# Covers: REQ-332
(cd "$SQ" && git tag -d v0.2.0 >/dev/null && git tag v0.2.0 && git tag v0.3.0)
cp "$SQ/docs/security/0.2.0-review.md" "$W/0.2.0-review.md"
rc=0; out=$(python3 "$FP" check-review "$W/0.2.0-review.md" --root "$SQ" 2>&1) || rc=$?
ck "a review outside --root, tag v0.2.0 on HEAD: fails, naming 'the file is outside --root'" bash -c '[ "$1" = 1 ] && grep -qF "the file is outside --root" <<<"$2"' _ "$rc" "$out"
cp "$SQ/docs/security/0.2.0-review.md" "$SQ/docs/security/0.3.0-review.md"
rc=0; out=$(python3 "$FP" check-review "$SQ/docs/security/0.3.0-review.md" --root "$SQ" 2>&1) || rc=$?
ck "a new, uncommitted 0.3.0 review with tag v0.3.0 on HEAD: fails, naming 'the file is absent at v0.3.0'" bash -c '[ "$1" = 1 ] && grep -qF "the file is absent at v0.3.0" <<<"$2"' _ "$rc" "$out"
cp "$SQ/docs/security/0.2.0-review.md" "$SQ/docs/security/foo-review.md"
rc=0; out=$(python3 "$FP" check-review "$SQ/docs/security/foo-review.md" --root "$SQ" 2>&1) || rc=$?
ck "a review whose name carries no version: the plain ancestry refusal, with no squash-merge note" bash -c '[ "$1" = 1 ] && grep -qF "is not HEAD or an ancestor" <<<"$2" && ! grep -qi "squash" <<<"$2"' _ "$rc" "$out"
rm -f "$SQ/docs/security/0.3.0-review.md" "$SQ/docs/security/foo-review.md"

finish test_security_review
