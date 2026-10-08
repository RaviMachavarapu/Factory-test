#!/usr/bin/env bash
# #36 medium (REQ-388, REQ-331; the plan's Ruling on suppression expiry): the floor goes red, by design, on the day a
# pack-shipped suppression's ignoreUntil passes — for the template's own gates and for every instance scaffolded from
# the pack. This test gives 30 days' notice: in the template source it FAILS when any ignoreUntil in
# stacks/*/{overlay,skeleton} (osv-scanner.toml, or an audit.toml entry's trailing comment) or any pack-shipped
# disposition expiry: is less than 30 days away (today from `date`), naming the file and the date, and it prints a
# WARN line when one is 30–60 days away. Re-accept (new ignoreUntil in both files, a new disposition entry) or re-pin.
# Covers: REQ-388
# Covers: REQ-331
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
FP="$ROOT/scripts/lib/specflow/floor.py"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
ex() { rc=0; out=$(python3 "$FP" expiry --today 2030-01-01 --root "$W/p" 2>&1) || rc=$?; }
pk() {  # pk OSV_DATE AUDIT_DATE DISPOSITION_DATE — a pack root with one entry of each kind
  rm -rf "$W/p"; mkdir -p "$W/p/src-tauri" "$W/p/docs/security"
  printf '[[IgnoredVulns]]\nid = "RUSTSEC-2099-0001"\nignoreUntil = %s\nreason = "SEC-001: x"\n' "$1" > "$W/p/osv-scanner.toml"
  printf '[advisories]\nignore = [\n  "RUSTSEC-2099-0002",  # SEC-001 reason: x; ignoreUntil: %s\n]\n' "$2" > "$W/p/src-tauri/audit.toml"
  printf -- '# D\n\n---\nid: SEC-001\nstatus: accepted\nowner: p\nexpiry: %s\nrationale: "x"\nsuppresses: [RUSTSEC-2099-0001, RUSTSEC-2099-0002]\n---\n' "$3" > "$W/p/docs/security/0.0.0-skeleton-disposition.md"
}
pk 2030-04-01 2030-04-01 2030-04-01; ex
ck "every date 90 days away: passes, nothing printed" bash -c '[ "$1" = 0 ] && [ -z "$2" ]' _ "$rc" "$out"
pk 2030-01-11 2030-04-01 2030-04-01; ex
ck "an osv-scanner.toml ignoreUntil 10 days away fails, naming the file and the date" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL expiry .*osv-scanner.toml:[0-9]*: RUSTSEC-2099-0001 ignoreUntil 2030-01-11" <<<"$2"' _ "$rc" "$out"
pk 2030-04-01 2030-01-11 2030-04-01; ex
ck "an audit.toml trailing-comment ignoreUntil 10 days away fails, naming the file and the date" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL expiry .*src-tauri/audit.toml:3: RUSTSEC-2099-0002 ignoreUntil 2030-01-11" <<<"$2"' _ "$rc" "$out"
pk 2030-04-01 2030-04-01 2029-12-01; ex
ck "a pack-shipped disposition expiry already past fails, naming the file and the date" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL expiry .*0.0.0-skeleton-disposition.md:[0-9]*: SEC-001 expiry 2029-12-01" <<<"$2"' _ "$rc" "$out"
pk 2030-01-30 2030-04-01 2030-04-01; ex
ck "29 days away still fails (under 30)" [ "$rc" = 1 ]
pk 2030-02-15 2030-02-15 2030-02-15; ex
ck "45 days away: passes with a WARN line per entry, naming the file and the date" \
  bash -c '[ "$1" = 0 ] && [ "$(grep -c "^WARN expiry .*2030-02-15" <<<"$2")" = 3 ] && ! grep -q "^FAIL" <<<"$2"' _ "$rc" "$out"
pk 2030-03-02 2030-04-01 2030-04-01; ex
ck "60 days away still warns; 61 does not" bash -c '[ "$1" = 0 ] && grep -q "^WARN" <<<"$2"' _ "$rc" "$out"
pk 2030-03-03 2030-04-01 2030-04-01; ex
ck "…61 days away prints nothing" bash -c '[ "$1" = 0 ] && [ -z "$2" ]' _ "$rc" "$out"
printf 'not = [toml\n' > "$W/p/osv-scanner.toml"; ex
ck "an unparsable suppression file fails (fail closed)" bash -c '[ "$1" = 1 ] && grep -q "unparsable" <<<"$2"' _ "$rc" "$out"

# PR #36 second run, medium (REQ-388): only each SEC id's LATEST disposition entry is judged (load_dispositions' rule:
# the higher version file, then the later block) — renewing by appending a newer block clears the old date.
renew() { printf -- '\n---\nid: SEC-001\nstatus: accepted\nowner: m\nexpiry: %s\nrationale: "renewed"\nsuppresses: [RUSTSEC-2099-0001, RUSTSEC-2099-0002]\n---\n' "$1" >> "$2"; }
pk 2030-04-01 2030-04-01 2029-12-01; renew 2030-06-01 "$W/p/docs/security/0.0.0-skeleton-disposition.md"; ex
ck "an old expiry superseded by a newer block with a later expiry passes (the old date is not judged)" \
  bash -c '[ "$1" = 0 ] && ! grep -q "2029-12-01" <<<"$2"' _ "$rc" "$out"
pk 2030-04-01 2030-04-01 2029-12-01
printf -- '# D\n' > "$W/p/docs/security/0.1.0-disposition.md"; renew 2030-06-01 "$W/p/docs/security/0.1.0-disposition.md"; ex
ck "…as does one superseded by an entry under a newer version's disposition file" \
  bash -c '[ "$1" = 0 ] && ! grep -q "2029-12-01" <<<"$2"' _ "$rc" "$out"
pk 2030-04-01 2030-04-01 2030-06-01; renew 2029-12-01 "$W/p/docs/security/0.0.0-skeleton-disposition.md"; ex
ck "…while a newer block whose expiry has passed still fails, naming the newer block's line" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL expiry .*0.0.0-skeleton-disposition.md:1[0-9]: SEC-001 expiry 2029-12-01" <<<"$2"' _ "$rc" "$out"

# The real check: every pack root in the template source, today's date.
if ! instance; then
  shopt -s nullglob; roots=(); for r in "$ROOT"/stacks/*/overlay "$ROOT"/stacks/*/skeleton; do roots+=(--root "$r"); done; shopt -u nullglob
  if [[ ${#roots[@]} -gt 0 ]]; then
    today=$(date -u +%Y-%m-%d); rc=0; out=$(python3 "$FP" expiry --today "$today" "${roots[@]}" 2>&1) || rc=$?
    while IFS= read -r l; do case "$l" in WARN*) echo "$l" ;; FAIL*) fail "$l" ;; esac; done <<<"$out"
    ck "no pack-shipped suppression or disposition expires within 30 days of $today" [ "$rc" = 0 ]
  fi
fi
finish test_suppression_expiry
