#!/usr/bin/env bash
# REQ-322 / REQ-332: blocks.py is the one parser of review and disposition blocks (schemas/security-disposition-template.md):
# a header block (schema, kind, version), finding blocks (id, severity, cvss_vector, cite, affects, carried_from) and
# entries (id, status, owner, expiry, rationale, reclassified_by, suppresses, inherited). Duplicate ids, unknown keys, an
# invalid vector, a severity that is not the vector's band, an unterminated block, a missing header (gate mode) and, once
# joined, an accepted/deferred medium-or-above entry without owner or expiry are parser errors (exit 2). The latest-entry
# reduction (versions by semver) is one function; floor.py imports it and keeps no reader of its own (P4 H4).
# Covers: REQ-322
# Covers: REQ-332
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; B="$LIB/blocks.py"; FP="$LIB/floor.py"; TPL="$ROOT/schemas/security-disposition-template.md"
ck "blocks.py exists" test -f "$B"
for k in 'schema: specflow-security/1' 'kind: review' 'kind: disposition' 'cvss_vector:' 'carried_from:' 'reclassified_by:' 'suppresses:' 'inherited:'; do
  ck "the schema template shows '$k'" grep -qF "$k" "$TPL"
done
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
read -r VH VM VL < <(python3 - "$ROOT/tests/governance/fixtures/cvss4/vectors.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))["vectors"]
print(*(next(c["vector"] for c in v if c["severity"] == s) for s in ("high", "medium", "low")))
PY
)
hdr() { printf -- '---\nschema: specflow-security/1\nkind: %s\nversion: %s\n---\n\n# %s\n\n' "$1" "$2" "$1"; }
finding() { printf -- '---\nid: %s\nseverity: %s\ncvss_vector: %s\ncite: [CWE-20]\naffects: [src/a.py:1]\n---\n\nbody\n\n' "$1" "$2" "$3"; }
entry() { printf -- '---\nid: %s\nstatus: %s\nowner: %s\n' "$1" "$2" "${4-alice}"
  [ -z "${3:-}" ] || printf 'expiry: %s\n' "$3"; printf 'rationale: "fixture rationale text"\n---\n\n'; }
edit() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
t = open(p).read(); assert old in t, old; open(p, "w").write(t.replace(old, new, 1))
PY
}
D="$W/docs/security"; mkdir -p "$D"; RV="$D/1.0.0-review.md"; DS="$D/1.0.0-disposition.md"
ok() { { hdr review 1.0.0; finding SEC-001 medium "$VM"; finding SEC-002 low "$VL"; } > "$RV"
       { hdr disposition 1.0.0; entry SEC-001 accepted 2026-12-01; entry SEC-002 accepted; } > "$DS"; }
bc() { rc=0; out=$(python3 "$B" check "$RV" "$DS" 2>&1) || rc=$?; }
ok; bc; ck "a well-formed pair parses (an accepted low needs no expiry)" [ "$rc" = 0 ]
ok; finding SEC-001 low "$VL" >> "$RV"; bc
ck "a duplicate review id is a parser error (exit 2) naming it" bash -c '[ "$1" = 2 ] && grep -q "SEC-001" <<<"$2"' _ "$rc" "$out"
ok; entry SEC-002 fixed >> "$DS"; bc
ck "a duplicate disposition id is a parser error naming it" bash -c '[ "$1" = 2 ] && grep -q "SEC-002" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" "severity: medium" "severity: high"; bc
ck "a severity that is not the vector's band is a parser error naming both" \
  bash -c '[ "$1" = 2 ] && grep -q "high" <<<"$2" && grep -q "medium" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" "cvss_vector: CVSS:4.0/AV:" "cvss_vector: CVSS:4.0/AV:Q/X:"; bc
ck "an invalid vector is a parser error naming cvss_vector" bash -c '[ "$1" = 2 ] && grep -q "cvss_vector" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" "expiry: 2026-12-01" "expirey: 2026-12-01"; bc
ck "an unknown key is a parser error naming it (a typo never drops a field)" bash -c '[ "$1" = 2 ] && grep -q "expirey" <<<"$2"' _ "$rc" "$out"
ck "floor mode (require_header=False) also rejects an unknown key" python3 - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import blocks
text = "---\nid: SEC-001\nstatus: accepted\nowner: alice\nexpirey: 2026-12-01\nrationale: \"x\"\n---\n"
try:
    blocks.parse_disposition(text, "fixture", require_header=False)
    sys.exit(1)
except blocks.BlockError as e:
    sys.exit(0 if "expirey" in str(e) else 1)
PY
ok; edit "$DS" "owner: alice" "owner: "; bc
ck "an accepted medium without owner is a parser error" bash -c '[ "$1" = 2 ] && grep -q "owner" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" $'expiry: 2026-12-01\n' ""; bc
ck "an accepted medium without expiry is a parser error" bash -c '[ "$1" = 2 ] && grep -q "expiry" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" "status: accepted" "status: waived"; bc
ck "an unknown status is a parser error naming it" bash -c '[ "$1" = 2 ] && grep -q "waived" <<<"$2"' _ "$rc" "$out"
ok; edit "$DS" $'schema: specflow-security/1\n' ""; bc
ck "gate mode: a disposition without the schema header is a parser error" bash -c '[ "$1" = 2 ] && grep -q "schema" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" "version: 1.0.0" "version: 1.0.1"; bc
ck "a header version that is not the file name's is a parser error naming it" bash -c '[ "$1" = 2 ] && grep -q "1.0.1" <<<"$2"' _ "$rc" "$out"
ok; printf -- '---\nid: SEC-003\nstatus: fixed\n' >> "$DS"; bc
ck "an unterminated block is a parser error (fail closed)" bash -c '[ "$1" = 2 ] && grep -qi "unterminated" <<<"$2"' _ "$rc" "$out"
ok; edit "$RV" $'affects: [src/a.py:1]\n---' $'affects: [src/a.py:1]\ncarried_from: 2.0.0\n---'; bc
ck "carried_from must name an earlier version" bash -c '[ "$1" = 2 ] && grep -q "carried_from" <<<"$2"' _ "$rc" "$out"
Z="CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N"
ok; finding SEC-003 low "$Z" >> "$RV"; entry SEC-003 accepted >> "$DS"; bc
ck "an informational finding (0.0: every impact N) is severity low (R20)" [ "$rc" = 0 ]
ok; finding SEC-003 medium "$Z" >> "$RV"; entry SEC-003 fixed >> "$DS"; bc
ck "…and a 0.0 vector at any other severity is a parser error naming the id" bash -c '[ "$1" = 2 ] && grep -q "SEC-003" <<<"$2"' _ "$rc" "$out"
C="CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N"
ok; finding SEC-003 critical "$C" >> "$RV"; entry SEC-003 fixed >> "$DS"; bc
ck "a base-only critical vector (9.3) is severity critical" [ "$rc" = 0 ]
for x in "/MVC:N/MVI:N/MVA:N:MVC" "/E:U:E" "/S:N:S"; do
  ok; finding SEC-003 low "$C${x%:*}" >> "$RV"; entry SEC-003 accepted >> "$DS"; bc
  ck "severity is the base score: a vector carrying ${x##*:} is a parser error naming it (the band is never lowered below the base)" \
    bash -c '[ "$1" = 2 ] && grep -q "SEC-003" <<<"$2" && grep -q "'"'"'$3'"'"'" <<<"$2" && grep -q "base score" <<<"$2"' _ "$rc" "$out" "${x##*:}"
done
ok; edit "$RV" $'id: SEC-002\n' $'id: "SEC-002"\n'; bc
ck "a quoted id is the bare id (values through config.parse, one reading for the gate and R12's walk)" [ "$rc" = 0 ]
L="$W/l"; mkdir -p "$L"
{ hdr disposition 0.9.0; entry SEC-001 accepted 2026-12-01; } > "$L/0.9.0-disposition.md"
{ hdr disposition 0.10.0; entry SEC-001 fixed; } > "$L/0.10.0-disposition.md"
{ hdr disposition 0.0.0-skeleton; entry SEC-002 accepted 2026-12-01; } > "$L/0.0.0-skeleton-disposition.md"
ck "latest entry per id orders versions by semver (0.10.0 after 0.9.0; a pre-release before its release)" \
  bash -c 'o=$(python3 "$1" latest "$2"); grep -qx "SEC-001 0.10.0 fixed" <<<"$o" && grep -qx "SEC-002 0.0.0-skeleton accepted" <<<"$o"' _ "$B" "$L"
# /security-review's carry-forward listing (PR #42 second verifier run, medium 3): `latest DIR --before V` reads the
# prior versions as the disposition gate does (disposition_gate.read_priors, R12: a tagged version from its tag, else
# the working tree) and joins each latest entry to its version's review for the severity: `id version status severity`.
G="$W/g"; GS="$G/docs/security"; mkdir -p "$GS"
{ hdr review 0.9.0; finding SEC-001 medium "$VM"; finding SEC-002 low "$VL"; } > "$GS/0.9.0-review.md"
{ hdr disposition 0.9.0; entry SEC-001 accepted 2026-12-01; entry SEC-002 accepted; } > "$GS/0.9.0-disposition.md"
(cd "$G" && git init -q -b main && git add -A && git commit -qm r && git tag v0.9.0)
edit "$GS/0.9.0-disposition.md" "status: accepted" "status: fixed"   # a working-tree edit to a released version
{ hdr review 0.9.5; finding SEC-003 high "$VH"; } > "$GS/0.9.5-review.md"
{ hdr disposition 0.9.5; entry SEC-003 open; } > "$GS/0.9.5-disposition.md"
{ hdr review 0.10.0; finding SEC-001 medium "$VM"; } > "$GS/0.10.0-review.md"
{ hdr disposition 0.10.0; entry SEC-001 fixed; } > "$GS/0.10.0-disposition.md"
rc=0; out=$(cd "$G" && python3 "$B" latest docs/security --before 0.10.0 2>&1) || rc=$?
ck "latest --before 0.10.0 lists id version status severity, the tagged 0.9.0 read from its tag, 0.10.0 left out" \
  bash -c '[ "$1" = 0 ] && [ "$2" = "$(printf "SEC-001 0.9.0 accepted medium\nSEC-002 0.9.0 accepted low\nSEC-003 0.9.5 open high")" ]' _ "$rc" "$out"
rm "$GS/0.9.5-review.md"; rc=0; out=$(cd "$G" && python3 "$B" latest docs/security --before 0.10.0 2>&1) || rc=$?
ck "…and a prior disposition whose review is missing is an error (exit 2), never a guessed severity" \
  bash -c '[ "$1" = 2 ] && grep -q "0.9.5" <<<"$2"' _ "$rc" "$out"
ck "/security-review's carry-forward names latest --before \$ARGUMENTS" \
  grep -qF 'python3 scripts/lib/specflow/blocks.py latest docs/security --before $ARGUMENTS' "$ROOT/.claude/commands/security-review.md"
# PR #42 third verifier run, low 7 (REQ-322): the documented command passes --base, as the gate reads priors, so a prior
# version present only on the base branch is listed too.
ck "/security-review's carry-forward command passes --base \"\${SPECFLOW_BASE_REF:-origin/main}\" (the gate's reading)" \
  grep -qF 'python3 scripts/lib/specflow/blocks.py latest docs/security --before $ARGUMENTS --base "${SPECFLOW_BASE_REF:-origin/main}"' "$ROOT/.claude/commands/security-review.md"
H="$W/h"; HS="$H/docs/security"; mkdir -p "$HS"
{ hdr review 0.9.0; finding SEC-001 medium "$VM"; } > "$HS/0.9.0-review.md"
{ hdr disposition 0.9.0; entry SEC-001 accepted 2026-12-01; } > "$HS/0.9.0-disposition.md"
(cd "$H" && git init -q -b main && git add -A && git commit -qm r && git checkout -qb ship/1.0.0 && git rm -q docs/security/0.9.0-*.md \
  && git commit -qm gone)
rc=0; out=$(cd "$H" && python3 "$B" latest docs/security --before 1.0.0 --base main 2>&1) || rc=$?
ck "latest --before --base lists a prior version present only on the base branch" \
  bash -c '[ "$1" = 0 ] && [ "$2" = "SEC-001 0.9.0 accepted medium" ]' _ "$rc" "$out"
ck "floor.py imports blocks.py" grep -qE '^(import blocks|from blocks import)' "$FP"
for f in _parse_disposition_blocks_at parse_inline_list _version_key; do
  ck "floor.py no longer defines $f (one reader)" no grep -qE "^def $f\(" "$FP"
done
finish test_security_blocks
