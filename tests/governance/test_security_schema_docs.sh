#!/usr/bin/env bash
# REQ-332 / REQ-322: the shipped security documents are in the block schema. The demo review and disposition gain the
# schema header only (a schema migration, not an addendum — docs/security/README.md); the tauri skeleton review's findings
# carry a cvss_vector whose band is the recorded severity, with the metric reasoning in the body, and its disposition keeps
# suppresses: and inherited:. RUBRIC.md carries expiry_horizon_days (ADR-002 rule 5). A carried-forward finding
# (carried_from:) re-lists an id without redefining it (check-traceability.sh's SEC uniqueness) only when an earlier
# version's review defines it; an unreadable review (an unterminated block, an unparsable block) fails the check closed.
# Covers: REQ-332
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
B="$ROOT/scripts/lib/specflow/blocks.py"
pair() { python3 "$B" check "$1-review.md" "$1-disposition.md"; }
if [[ -f "$ROOT/docs/security/0.0.1-demo-review.md" ]]; then
  ck "the demo review and disposition parse in the schema (zero findings)" pair "$ROOT/docs/security/0.0.1-demo"
  ck "the demo review still carries exactly one addendum" [ "$(grep -c '^### Addendum' "$ROOT/docs/security/0.0.1-demo-review.md")" = 1 ]
fi
if ! instance; then
  S="$ROOT/stacks/tauri/overlay/docs/security/0.0.0-skeleton"
  ck "the tauri skeleton review and disposition parse in the schema (each severity is its vector's finding_severity)" pair "$S"
  ck "SEC-002 and SEC-003 say they are informational (0.0 vectors, R20)" [ "$(grep -ci 'informational' "$S-review.md")" -ge 2 ]
  ck "no skeleton finding is 'pending'" no grep -qF 'pending (P3 schema)' "$S-review.md"
  ck "no skeleton finding uses the old vector: key" no grep -qE '^vector:' "$S-review.md"
  ck "each skeleton finding carries a metric-reasoning table" [ "$(grep -c '^| Attack Vector |' "$S-review.md")" -ge 3 ]
  ck "each skeleton reasoning table has RUBRIC.md's | Metric | Value | Why | header row" [ "$(grep -c '^| Metric | Value | Why |$' "$S-review.md")" -ge 3 ]
  ck "each skeleton reasoning table has exactly one |---|---|---| separator, directly under its | Metric | Value | Why | header (a stray one renders as a row of dashes)" \
    awk '$0 == "|---|---|---|" && prev != "| Metric | Value | Why |" {bad=1} {prev=$0} END {exit bad}' "$S-review.md"
  ck "the skeleton disposition keeps suppresses: and inherited: on all three entries" \
    bash -c '[ "$(grep -c "^suppresses:" "$1")" = 3 ] && [ "$(grep -c "^inherited:" "$1")" = 3 ]' _ "$S-disposition.md"
  ck "the skeleton disposition's preamble says its accepted entries expire 2027-03-24 (renewed 2026-10-04) and the first /security-review after that date must refresh or fix SEC-001 (ADR-002 rule 4)" \
    bash -c 'pre=$(awk "/^id: SEC-001/{exit} {print}" "$1"); grep -qF "expire on 2027-03-24" <<<"$pre" && grep -qF "refresh or fix" <<<"$pre" && grep -qF "SEC-001" <<<"$pre" && grep -qF "rule 4" <<<"$pre"' _ "$S-disposition.md"
  # PR #42 fourth verifier run, doc low 8 (REQ-388, REQ-332): SEC-002/SEC-003's exploitability metrics are scored from
  # their advisories' facts (a Linux-only build dependency; a parser fed the app's own bundled config), not worst-case
  # placeholders, with one real reason per metric; every impact stays N, so the score stays 0.0 and the band low (R20).
  ck "SEC-002/SEC-003: vectors scored from the advisories' facts, one distinct reason per metric, all impacts N (0.0)" python3 - "$S-review.md" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
want = {"SEC-002": "CVSS:4.0/AV:L/AC:H/AT:P/PR:H/UI:A/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
        "SEC-003": "CVSS:4.0/AV:L/AC:H/AT:P/PR:H/UI:P/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N"}
for sec, vec in want.items():
    body = text.split(f"id: {sec}\n", 1)[1].split("\n---\nid: ", 1)[0]
    assert f"cvss_vector: {vec}" in body, (sec, "vector")
    rows = [l for l in body.splitlines() if l.startswith("| ") and not l.startswith("| Metric |")]
    whys = [r.rstrip(" |").rsplit(" | ", 1)[1] for r in rows]
    assert len(rows) == 6 and len(set(whys)) == 6, (sec, whys)
    assert "no exploit exists" not in body and "regardless of this value" not in body, sec
PY
  # PR #42 third verifier run, finding 2 (REQ-388, REQ-322): rule 4 covers prior entries of medium and above only, so
  # it enforces SEC-001's renewal; SEC-002 (low) is renewed by the floor's ignoreUntil date alone. SEC-003 (low) is fixed
  # since the 2026-10-04 re-pin (no unic-* crate left), so no ignoreUntil covers it any more.
  ck "the skeleton preamble says rule 4 covers SEC-001 (medium) and the floor's ignoreUntil alone covers SEC-002 (low)" \
    bash -c 'pre=$(awk "/^id: SEC-001/{exit} {print}" "$1" | tr "\n" " " | tr -s " "); grep -qF "rule 4 covers SEC-001 (medium)" <<<"$pre" && grep -qF "the floor'"'"'s \`ignoreUntil\` date alone covers SEC-002 (low)" <<<"$pre" && ! grep -qF "refresh or fix SEC-001, SEC-002 and SEC-003" <<<"$pre"' _ "$S-disposition.md"
fi
RB="$ROOT/docs/security/RUBRIC.md"; RM="$ROOT/docs/security/README.md"
# 2026-10-03 (REQ-322, art-threat-driven-security): the maintainer raised medium_cap from 5 to 10 for v3.2.0, in RUBRIC.md's
# medium_cap: field by its own reviewed PR (ADR-002); the dated note names the decision, the nine ids and its dated end.
# PR #59 verifier run 1, finding 1 (REQ-322, REQ-306): the override is the template source's alone — init resets an
# instance's RUBRIC.md to medium_cap 5 and drops the note (test_init.sh), so an instance reads 5 and no factory record.
NINE_IDS="SEC-006, SEC-007, SEC-008, SEC-009, SEC-010, SEC-011, SEC-012, SEC-013, SEC-014"
rubric_cap_is() {  # rubric_cap_is N — the gate's own reader (disposition_gate.resolve_rubric) parses (N, 180)
  python3 -c '
import sys; sys.path.insert(0, sys.argv[1] + "/scripts/lib/specflow")
from pathlib import Path; import disposition_gate as g
cap, hz, _, _ = g.resolve_rubric(Path(sys.argv[1]), sys.argv[1] + "/docs/security/RUBRIC.md", None, False)
assert (cap, hz) == (int(sys.argv[2]), 180), (cap, hz)' "$ROOT" "$1"
}
if ! instance; then
  # 2026-10-04 (REQ-322; the P7 retrospective, docs/retrospectives/2026-10-04-v3-2-closeout.md, PR #69): the override was
  # restored to 5 by its own reviewed PR (PR #70), as the record promised; the record stays, closed by a dated line naming
  # the retrospective. That line's closing words are corrected (PR #71 verifier run 1, finding 1): the next ship brings
  # the mediums within 5 by fixes or the cap is re-decided by its own reviewed PR (BL-022) — re-decided, the v3.2.1 record.
  # 2026-10-04 (REQ-322, BL-022, art-threat-driven-security): the maintainer's v3.2.1 decision raises medium_cap from 5 to
  # 8 by this record's own reviewed PR (patch/ship-3-2-1-prereqs), merged before the ship PR it governs because ADR-002
  # reads the cap from the base ref: the seven carried accepted or deferred mediums plus SEC-020 (BL-037), whose base
  # text verifier.yml still prints on a stacked PR. The override covers the 3.2.1 ship alone and ends by a reduction PR after its Release, or by 2026-12-15 at the latest.
  # 2026-10-05 (REQ-322, BL-022): v3.2.1 is released (tag on 609abbc, release run 37302823217), and the reduction PR the
  # record promised (patch/post-3-2-1-records) returns medium_cap to 5; the record stays, closed by a dated line, and its
  # carried-expiries phrase gains a dated correction: the 3.2.1 disposition re-accepted all eight to 2027-01-31.
  SEVEN_IDS="SEC-007, SEC-008, SEC-009, SEC-010, SEC-012, SEC-013, SEC-014"
  RUBRIC_END=2026-12-15
  ck "RUBRIC.md: medium_cap 5 (returned after the 3.2.1 Release) and expiry_horizon_days 180" bash -c 'grep -qE "^medium_cap: 5([^0-9]|$)" "$1" && grep -qE "^expiry_horizon_days: 180" "$1"' _ "$RB"
  ck "RUBRIC.md: the gate's reader parses medium_cap 5 and expiry_horizon_days 180" rubric_cap_is 5
  ck "RUBRIC.md: the v3.2.1 record is closed by a dated line (after the Release, the run, the tag, the reduction PR, the lapse rule retired)" \
    bash -c 'n=$(tr "\n" " " <"$1" | tr -s " "); for w in "2026-10-05, after the v3.2.1 Release (run 37302823217, tag \`v3.2.1\` on \`609abbc\`): returned to 5 by this record'"'"'s own reduction PR (\`patch/post-3-2-1-records\`), as promised; the lapse rule is retired to a fixture again"; do grep -qF -- "$w" <<<"$n" || { echo "missing: $w"; exit 1; }; done' _ "$RB"
  ck "RUBRIC.md: the v3.2.1 record's carried-expiries phrase carries the dated correction (all eight re-accepted to 2027-01-31, ADR-002 rule 5, the threat model re-aligned)" \
    bash -c 'n=$(tr "\n" " " <"$1" | tr -s " "); for w in "the other five re-accepted in the threat model to 2026-12-15 (corrected 2026-10-05: the 3.2.1 disposition re-accepted all eight, the seven and SEC-020, to 2027-01-31 (within ADR-002 rule 5 window from the review run date, with the margin past the tag date the #76 verifier asked for), and the post-3.2.1 records patch re-aligns the threat model to it)"; do grep -qF -- "$w" <<<"$n" || { echo "missing: $w"; exit 1; }; done' _ "$RB"
  ck "RUBRIC.md: the dated note records the maintainer's 2026-10-03 decision (5 to 10, the nine ids, its dated end, in the past tense)" \
    bash -c 'n=$(tr "\n" " " <"$1" | tr -s " "); for w in "2026-10-03, maintainer decision for v3.2.0" "raised from 5 to 10" "nine accepted or deferred mediums ($2)" "owner kpingali123, expiry 2026-10-12" "returned to 5 on 2026-10-04 by PR #70" "retired to a fixture by that PR and re-armed by"; do grep -qF -- "$w" <<<"$n" || { echo "missing: $w"; exit 1; }; done; ! grep -qF "returns to 5 by 2026-10-12 unless re-decided" <<<"$n" || { echo "present-tense lapse sentence still there"; exit 1; }' _ "$RB" "$NINE_IDS"
  ck "RUBRIC.md: the override record is closed by the P7 retrospective's dated line (restored to 5, the retrospective file, the corrected closing words)" \
    bash -c 'n=$(tr "\n" " " <"$1" | tr -s " "); for w in "2026-10-04, P7 retrospective" "restored to 5" "docs/retrospectives/2026-10-04-v3-2-closeout.md" "the next ship brings the mediums within 5 by fixes or the cap is re-decided by its own reviewed PR (BL-022) — re-decided: the 2026-10-04 v3.2.1 record below"; do grep -qF -- "$w" <<<"$n" || { echo "missing: $w"; exit 1; }; done; ! grep -qF "carries the nine forward under 5" <<<"$n" || { echo "old closing words still there"; exit 1; }' _ "$RB"
  ck "RUBRIC.md: the v3.2.1 record names the decision, 5 to 8, the seven ids, that they are not fixed in 3.2.1, SEC-020, the deferrals, the own reviewed PR, its end and the instance reset" \
    bash -c 'n=$(tr "\n" " " <"$1" | tr -s " "); for w in "2026-10-04, maintainer decision for v3.2.1" "raised from 5 to 8" "seven accepted or deferred mediums ($2)" "SEC-020" "BL-013 and BL-023 (the v3.3 design lane)" "BL-016 and BL-017 (the first signed instance release known to the maintainer)" "2026-11-15 for SEC-010 and SEC-012" "the other five re-accepted in the threat model to $3" "BL-037" "valid only while the 3.2.1 review records SEC-006 and SEC-011 fixed (PR #65 removed their causes), SEC-005 fixed or left open, and SEC-021 low; otherwise the cap is re-decided by a reviewed PR" "reserves the eighth place for SEC-020 should that review accept or defer it" "covers the 3.2.1 ship alone" "PR #76" "the '"'"'own reviewed PR'"'"' ADR-002 names, merged before the ship PR it governs because the gate reads the cap from the base ref" "returns to 5 by a reduction PR right after the 3.2.1 Release is published, and by $3 at the latest" "gives a new instance \`medium_cap: 5\` and no override record" "the Release end is convention (no mechanism); only the date is enforced" "The seven are not fixed in 3.2.1: their fixes are deferred to the v3.3 design lane (BL-013, BL-023) or to the first signed instance release (BL-016, BL-017), and the cap is raised instead of fixing them before the ship."; do grep -qF -- "$w" <<<"$n" || { echo "missing: $w"; exit 1; }; done; ! grep -qF "or re-accepted them to" <<<"$n" || { echo "old deferral sentence still there"; exit 1; }' _ "$RB" "$SEVEN_IDS" "$RUBRIC_END"
  # PR #59 verifier run 1, finding 3 (REQ-322): the nine ids are checkable once the ship PR lands — then they are exactly
  # the 3.2.0 review's mediums the 3.2.0 disposition accepts or defers.
  if [[ -f "$ROOT/docs/security/3.2.0-review.md" && -f "$ROOT/docs/security/3.2.0-disposition.md" ]]; then
    ck "RUBRIC.md: the note's nine ids are the 3.2.0 review's accepted or deferred mediums" python3 - "$ROOT" "$NINE_IDS" <<'PYN'
import sys; sys.path.insert(0, sys.argv[1] + "/scripts/lib/specflow"); import blocks
d = sys.argv[1] + "/docs/security/3.2.0-"
rv = blocks.parse_review(open(d + "review.md").read(), "docs/security/3.2.0-review.md", version="3.2.0")
dp = blocks.parse_disposition(open(d + "disposition.md").read(), "docs/security/3.2.0-disposition.md", version="3.2.0")
med = {f.id for f in rv.findings if str(getattr(f.severity, "value", f.severity)) == "medium"}
ad = {e.id for e in dp.entries if e.id in med and e.status in ("accepted", "deferred")}
want = set(sys.argv[2].split(", "))
assert ad == want, (sorted(ad), sorted(want))
PYN
  fi
  # The lapse rule (PR #59 verifier run 1, finding 2; REQ-322, art-threat-driven-security), retired to a fixture by PR #70,
  # re-armed for the v3.2.1 override (PR #76) and retired to a fixture again by the reduction PR after the 3.2.1 Release
  # (patch/post-3-2-1-records, 2026-10-05): the cap is 5 again, so no calendar date can turn main's gates red. The rule
  # is kept as a fixture so a future override records a dated end the same way.
  cap_lapsed() {  # cap_lapsed RUBRIC DATE END — true when DATE is past END while medium_cap is still raised (not 5)
    [[ "$2" > "$3" ]] && ! grep -qE "^medium_cap: 5([^0-9]|$)" "$1"
  }
  RB_RAISED="$(mktemp)"; printf 'medium_cap: 10\n' > "$RB_RAISED"
  RB_RESTORED="$(mktemp)"; printf 'medium_cap: 5\n' > "$RB_RESTORED"
  ck "…a raised override: the day after its end has lapsed (fixture)" cap_lapsed "$RB_RAISED" 2026-10-13 2026-10-12
  ck "…a raised override: its end date has not (fixture)" no cap_lapsed "$RB_RAISED" 2026-10-12 2026-10-12
  ck "…a restored RUBRIC.md never lapses: medium_cap 5 on any date (fixture)" no cap_lapsed "$RB_RESTORED" 2099-01-01 2026-10-12
  RB_RAISED8="$(mktemp)"; printf 'medium_cap: 8\n' > "$RB_RAISED8"
  ck "…a raised override (the v3.2.1 shape, cap 8): the day after its end has lapsed (fixture)" cap_lapsed "$RB_RAISED8" 2026-12-16 "$RUBRIC_END"
  ck "…a raised override (the v3.2.1 shape, cap 8): its end date has not (fixture)" no cap_lapsed "$RB_RAISED8" 2026-12-15 "$RUBRIC_END"
  rm -f "$RB_RAISED" "$RB_RESTORED" "$RB_RAISED8"
  ck "…the restored live RUBRIC.md never lapses: medium_cap 5 on any date" no cap_lapsed "$RB" 2099-01-01 "$RUBRIC_END"
else
  ck "RUBRIC.md (instance): medium_cap 5, the constitution's default, and expiry_horizon_days 180" bash -c 'grep -qE "^medium_cap: 5([^0-9]|$)" "$1" && grep -qE "^expiry_horizon_days: 180" "$1"' _ "$RB"
  ck "RUBRIC.md (instance): no factory override record" bash -c '! grep -qF "Override record" "$1" && ! grep -qF "maintainer decision for v3.2.0" "$1" && ! grep -qF "maintainer decision for v3.2.1" "$1"' _ "$RB"
  ck "RUBRIC.md (instance): the gate's reader parses medium_cap 5 and expiry_horizon_days 180" rubric_cap_is 5
fi
ck "RUBRIC.md: a 0.0 vector is an informational low (R20), and an open medium is not capped (the residual reviewers look for)" \
  bash -c 'grep -qF "0.0" "$1" && grep -qiF "informational" "$1" && grep -qiF "long-open mediums" "$1"' _ "$RB"
ck "RUBRIC.md: a carried-forward downgrade re-accepted as low has no expiry upper bound (rule 5 covers mediums only), so the reviewer checks its expiry" \
  bash -c 'grep -qF "no expiry upper bound" "$1" && grep -qF "rule 5" "$1"' _ "$RB"
ck "README: per-finding frontmatter points at the schema template, not 'spec § Artifact Schemas'" \
  bash -c 'grep -qF "schemas/security-disposition-template.md" "$1" && ! grep -qF "Artifact Schemas" "$1"' _ "$RM"
sm=$(awk '/^## Schema migrations$/{f=1; next} /^## /{f=0} f' "$RM")
for w in 'specflow-security/1' '0.0.1-demo-review.md' '0.0.1-demo-disposition.md' 'no SEC' 'not an addendum' '0.0.0-skeleton'; do
  ck "README Schema migrations states '$w'" grep -qF -- "$w" <<<"$sm"
done
# PR #42 fifth verifier run, finding 1 (REQ-332): the verifier APPROVED #42, so no waiver comment exists; the standing
# rule puts the maintainer's confirmation in the merge or approval comment of the PR that uses the exception (as the PR
# template says), and #42's own confirmation is its merge commit message.
ck "README Schema migrations: the maintainer confirms the exception in the merge or approval comment of the PR that uses it" \
  grep -qF "the merge or approval comment of the PR that uses the exception" <<<"$(tr '\n' ' ' <<<"$sm" | tr -s ' ')"
ck "README Schema migrations: no waiver is assumed" no grep -qiF "waiver" <<<"$sm"
ck "README Schema migrations: PR #42's confirmation is cited where it is (its merge commit message, 1ee84c8)" \
  grep -qF "the merge commit message of PR #42 (1ee84c8)" <<<"$(tr '\n' ' ' <<<"$sm" | tr -s ' ')"
# PR #42 fourth verifier run, doc medium 5 (REQ-332): the exception is narrow — only into a new schema version's syntax,
# with each key rename listed explicitly under its schema version, never a free-form "key renames".
ck "README Schema migrations: only into a new schema version's syntax, no free-form 'key renames'" \
  bash -c 'grep -qF "into a new schema version'"'"'s syntax:" <<<"$1" && ! grep -qF "key renames)" <<<"$1"' _ "$sm"
ck "README Schema migrations: a key is renamed only where that schema version's entry lists the rename explicitly" \
  bash -c 'grep -qF "lists the rename explicitly" <<<"$1" && grep -qF "Key renames: \`vector:\` → \`cvss_vector:\`" <<<"$1"' _ "$sm"
for f in "$ROOT/schemas/security-disposition-template.md" "$RB" "$ROOT/.claude/commands/security-review.md"; do
  ck "$(basename "$f") says a finding's cvss_vector is base metrics only (severity is the base score; Threat, Environmental, Supplemental metrics refused)" \
    bash -c 'grep -qiF "base metrics only" "$1" && grep -qF "Environmental" "$1"' _ "$f"
done
ck "the schema template says 'an expired date'" no grep -qF 'a expired date' "$ROOT/schemas/security-disposition-template.md"
# Amendment B (REQ-343): the 0.0 row is the constitution's own, no longer an interim reading.
# Covers: REQ-343
ck "the schema template's band table matches RUBRIC.md: none 0.0 is informational (art-threat-driven-security's row), low is 0.1–3.9, never 'none/low 0.0–3.9', no interim reading" \
  bash -c 'grep -qF "0.1–3.9" "$1" && grep -qF "art-threat-driven-security" "$1" && grep -qiF "informational" "$1" && ! grep -qF "0.0–3.9" "$1" && ! grep -qiF "interim reading" "$1"' _ "$ROOT/schemas/security-disposition-template.md"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
T="$W/t"; mkdir -p "$T/docs/security" "$T/docs/specs" "$T/docs/plans"
printf -- '---\nid: SEC-001\nseverity: medium\n---\n' > "$T/docs/security/0.0.0-skeleton-review.md"
printf -- '---\nid: SEC-001\nseverity: medium\ncarried_from: 0.0.0-skeleton\n---\n' > "$T/docs/security/0.1.0-review.md"
ck "a carried-forward finding (carried_from:) is a reference, not a second definition" env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
printf -- '---\nid: SEC-001\nseverity: medium\n---\n' > "$T/docs/security/0.1.0-review.md"
ck "…without carried_from: it is a duplicate definition" no env TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh"
printf -- '---\nid: SEC-001\nseverity: medium\ncarried_from: 0.0.0-skeleton\n---\n' > "$T/docs/security/0.1.0-review.md"
printf -- '---\nid: SEC-001\nseverity: medium\ncarried_from: 0.0.0-skeleton\n---\n' > "$T/docs/security/0.2.0-review.md"
printf -- '---\nid: SEC-002\nseverity: medium\ncarried_from: 0.0.0-skeleton\n---\n' > "$T/docs/security/0.3.0-review.md"
printf -- '---\nid: SEC-002\nseverity: medium\n---\n' > "$T/docs/security/0.4.0-review.md"
rc=0; out=$(TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh" 2>&1) || rc=$?
ck "a carried_from: naming no earlier definition of the id counts as a definition (SEC-002 defined twice)" \
  bash -c '[ "$1" != 0 ] && grep -q "SEC-002" <<<"$2" && ! grep -q "SEC-001 is defined" <<<"$2"' _ "$rc" "$out"
rm "$T/docs/security/0.3.0-review.md" "$T/docs/security/0.4.0-review.md" "$T/docs/security/0.2.0-review.md"
printf -- '---\nid: SEC-001\nseverity: medium\n---\n\n---\nid: SEC-009\n' > "$T/docs/security/0.1.0-review.md"
rc=0; out=$(TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh" 2>&1) || rc=$?
ck "an unterminated block no longer hides a review (and its duplicate SEC-001) from the uniqueness check: it fails, naming the file" \
  bash -c '[ "$1" != 0 ] && grep -q "0.1.0-review.md" <<<"$2"' _ "$rc" "$out"
printf -- '---\nid: SEC-003\n  nested: yaml\n---\n' > "$T/docs/security/0.1.0-review.md"
rc=0; out=$(TRACE_BASE_DIR="$T" bash "$ROOT/scripts/check-traceability.sh" 2>&1) || rc=$?
ck "…nor does an unparsable block" bash -c '[ "$1" != 0 ] && grep -q "0.1.0-review.md" <<<"$2"' _ "$rc" "$out"
# P5 R18 (H8; REQ-332): the tauri skeleton review names its rulings by plan and labels the informational findings'
# exploitability rows as shape only — a header and prose edit under the schema-migration rule: no SEC id added, removed
# or re-scored.
# Covers: REQ-332
SKR="$ROOT/stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md"
if [ -f "$SKR" ]; then
  ck "the skeleton review cites P4 R12, never a bare R12" \
    bash -c 'grep -qF "P4 R12" "$1" && ! sed "s/P4 R12//g" "$1" | grep -qE "(^|[^0-9A-Za-z])R12([^0-9]|$)"' _ "$SKR"
  ck "the skeleton review cites no bare R20; the informational row is art-threat-driven-security's" \
    bash -c '! grep -qE "(^|[^0-9A-Za-z])R20([^0-9]|$)" "$1" && grep -qF "art-threat-driven-security" "$1"' _ "$SKR"
  ck "SEC-002's and SEC-003's metric tables are labelled as recorded for the vector's shape only" \
    [ "$(grep -c "Recorded for the vector's shape only" "$SKR")" -ge 2 ]
  ck "no id, severity or vector changed since P4's review shipped (b3db479)" bash -c \
    'diff <(git -C "$2" show b3db479:stacks/tauri/overlay/docs/security/0.0.0-skeleton-review.md | grep -E "^(id|severity|cvss_vector):") <(grep -E "^(id|severity|cvss_vector):" "$1")' _ "$SKR" "$ROOT"
fi
ck "docs/security/README.md lists P5's skeleton-review migration (header and prose only)" \
  bash -c 'awk "/^## Schema migrations$/{f=1; next} /^## /{f=0} f" "$1" | grep -qF "P5"' _ "$RM"
# Scoped re-review N2 (REQ-389, REQ-322): the guided profile's /next writes confirmed_by: into the header block of the
# security review and the disposition at ship-pr; the schema documents it as an optional header key, and a header
# carrying it parses (blocks.parse_review / parse_disposition) and passes check-security-disposition.sh on the demo pair.
# Covers: REQ-389
TPLS="$ROOT/schemas/security-disposition-template.md"
ck "the schema documents confirmed_by: as an optional header key (guided profile, REQ-389, written by /next at ship-pr)" \
  bash -c 'awk "/^## The header block/{f=1; next} /^## /{f=0} f" "$1" | tr "\n" " " | tr -s " " | grep -qF "guided profile, REQ-389: \`<handle> <YYYY-MM-DD>\`, written by \`/next\` at \`ship-pr\`"' _ "$TPLS"
if [ -f "$ROOT/docs/security/0.0.1-demo-review.md" ]; then
  CR="$W/confirmed"; mkdir -p "$CR/docs/security"
  for k in review disposition; do
    awk 'NR==1{print; next} !d && /^version: /{print; print "confirmed_by: octocat 2026-09-29"; d=1; next} {print}' \
      "$ROOT/docs/security/0.0.1-demo-$k.md" > "$CR/docs/security/0.0.1-demo-$k.md"
  done
  ck "…a demo review and disposition whose headers carry confirmed_by: parse (blocks.parse_review / parse_disposition)" \
    python3 - "$ROOT/scripts/lib/specflow" "$CR/docs/security" <<'PYC'
import sys; sys.path.insert(0, sys.argv[1]); import blocks
d = sys.argv[2]
for k, f in (("review", blocks.parse_review), ("disposition", blocks.parse_disposition)):
    t = open(f"{d}/0.0.1-demo-{k}.md").read()
    assert "\nconfirmed_by: octocat 2026-09-29\n" in t.split("\n---\n", 1)[0] + "\n", k
    f(t, f"docs/security/0.0.1-demo-{k}.md", version="0.0.1-demo")
PYC
  ck "…and pass check-security-disposition.sh (--no-git)" \
    bash "$ROOT/scripts/check-security-disposition.sh" --root "$CR" --version 0.0.1-demo --no-git \
      --rubric "$ROOT/docs/security/RUBRIC.md" --run-date 2026-09-29
fi
# PR #78 verifier run 1 (REQ-322; BL-022): the 2026-10-05 record says what the next ship must do with the eight mediums.
# Covers: REQ-322
if ! instance; then  # the override record is the template source's alone; an instance's RUBRIC.md carries none
  ck "RUBRIC.md: the 2026-10-05 record says the next ship brings the eight mediums within 5 or re-decides the cap (BL-046)" \
    bash -c 'n=$(tr "\n" " " <"$1" | tr -s " "); grep -qF "the next ship brings them within 5 by fixes or downgrades or re-decides the cap by its own reviewed PR (BL-046)" <<<"$n"' _ "$RB"
fi

finish test_security_schema_docs
