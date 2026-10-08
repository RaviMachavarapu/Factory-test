#!/usr/bin/env bash
# REQ-388 as amended (dfe-11): every suppression — an osv-scanner.toml or audit.toml ignore entry, a .gitleaks.toml
# allowlist entry beyond the three permitted paths, a .gitleaksignore fingerprint, a bandit "# nosec", a .bandit or
# [tool.bandit] key, and any key or table outside a suppression file's whitelist — cites a SEC-NNN whose latest
# disposition entry is accepted or deferred and names the entry in suppresses: (so an allowlist or ignore set cannot
# grow, or ride on an old SEC id, without a disposition change). In the template source the root run leaves stacks/
# to the per-pack-root runs; git-ignored copies are never scanned.
# Covers: REQ-388
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CS="$ROOT/scripts/check-suppressions.sh"
[[ -f "$CS" ]] || { fail "scripts/check-suppressions.sh missing"; finish test_suppressions; }
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
ck ".gitleaks.toml present" test -f "$ROOT/.gitleaks.toml"
ck ".gitleaks.toml extends gitleaks' default rules (a config without them scans with no rules)" python3 - "$ROOT/.gitleaks.toml" <<'PY'
import sys, tomllib
assert tomllib.load(open(sys.argv[1], "rb")).get("extend", {}).get("useDefault") is True
PY
if ! instance; then
  ck "the template's allowlist is exactly .env.example, docs/**/examples/**, tests/**/fixtures/**" python3 - "$ROOT/.gitleaks.toml" <<'PY'
import sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb")); al = c.get("allowlist", {})
assert set(al) <= {"description", "paths"}, al
assert al["paths"] == [r"(^|/)\.env\.example$", r"^docs/(.*/)?examples/", r"^tests/(.*/)?fixtures/"], al["paths"]
assert "allowlists" not in c and "rules" not in c
PY
fi
ck "this repository passes its own suppression check" bash "$CS" --root "$ROOT"

case_root() {  # case_root NAME [ENTRY…] — a fresh root with one disposition: SEC-001 accepted (suppresses two ids plus
  # each ENTRY name, JSON-quoted), SEC-002 fixed
  C="$W/$1"; shift; rm -rf "$C"; mkdir -p "$C/docs/security"
  local sup; sup=$(python3 -c 'import json, sys; print(", ".join(["RUSTSEC-2099-0001", "GHSA-aaaa-bbbb-cccc"] + [json.dumps(x) for x in sys.argv[1:]]))' ${1+"$@"})
  cat > "$C/docs/security/0.1.0-disposition.md" <<EOF
# Security Disposition — v0.1.0

---
id: SEC-001
status: accepted
owner: alice
expiry: 2099-06-30
rationale: "fixture: unmaintained crate, no known vulnerability"
suppresses: [$sup]
---

---
id: SEC-002
status: fixed
owner: alice
rationale: "fixture: upgraded"
suppresses: [RUSTSEC-2099-0002]
---
EOF
}
chk() { rc=0; out=$(bash "$CS" --root "$C" 2>&1) || rc=$?; }
audit() { mkdir -p "$C/src-tauri"; printf '[advisories]\nignore = [\n  %s\n]\n' "$1" > "$C/src-tauri/audit.toml"; }
osv() { mkdir -p "$(dirname "$C/${4:-osv-scanner.toml}")"; printf '[[IgnoredVulns]]\nid = "%s"\nignoreUntil = %s\nreason = "%s"\n' "$1" "$2" "$3" > "$C/${4:-osv-scanner.toml}"; }
gl() {  # gl EXTRA_LINE — the permitted allowlist plus EXTRA_LINE (may be empty)
  { printf '[extend]\nuseDefault = true\n\n[allowlist]\npaths = [\n'
    printf "  '''%s''',\n" '(^|/)\.env\.example$' '^docs/(.*/)?examples/' '^tests/(.*/)?fixtures/'
    if [ -n "$1" ]; then printf '%s\n' "$1"; fi
    printf ']\n'; } > "$C/.gitleaks.toml"
}
case_root ok; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01'; chk
ck "an audit.toml entry citing an accepted SEC that lists it: pass" [ "$rc" = 0 ]
js=$(bash "$CS" --root "$C" --json)
ck "--json lists it with its kind, id and SEC" python3 -c 'import json, sys
s = json.loads(sys.argv[1])["suppressions"]
assert [(x["kind"], x["id"], x["sec"]) for x in s] == [("cargo-audit", "RUSTSEC-2099-0001", "SEC-001")], s' "$js"
case_root nosec; audit '"RUSTSEC-2099-0001",  # reason: no citation'; chk
ck "an ignore entry without a SEC-NNN fails, naming file and line" bash -c '[ "$1" = 1 ] && grep -q "src-tauri/audit.toml:3" <<<"$2"' _ "$rc" "$out"
case_root unknown; audit '"RUSTSEC-2099-0001",  # SEC-009 reason: x'; chk
ck "citing a SEC-NNN no disposition defines fails" bash -c '[ "$1" = 1 ] && grep -q "SEC-009" <<<"$2"' _ "$rc" "$out"
case_root fixed; audit '"RUSTSEC-2099-0002",  # SEC-002 reason: x'; chk
ck "citing a SEC-NNN whose latest entry is fixed fails (the suppression outlived its finding)" bash -c '[ "$1" = 1 ] && grep -q "SEC-002" <<<"$2"' _ "$rc" "$out"
case_root unlisted; audit '"RUSTSEC-2099-0003",  # SEC-001 reason: reused id'; chk
ck "an active SEC-NNN reused for an id its suppresses: omits fails (the ignore set grew)" bash -c '[ "$1" = 1 ] && grep -q "RUSTSEC-2099-0003" <<<"$2"' _ "$rc" "$out"
case_root osvok; osv GHSA-aaaa-bbbb-cccc 2099-01-01 'SEC-001: fixture'; chk
ck "an IgnoredVulns reason starting with an active SEC-NNN that lists the id: pass" [ "$rc" = 0 ]
case_root osvbad; osv GHSA-aaaa-bbbb-cccc 2099-01-01 'fixture without a citation'; chk
ck "an IgnoredVulns reason without a leading SEC-NNN fails" [ "$rc" = 1 ]
case_root osvlate; osv GHSA-aaaa-bbbb-cccc 2100-01-01 'SEC-001: fixture'; chk
ck "an ignoreUntil after the disposition entry's expiry fails" bash -c '[ "$1" = 1 ] && grep -qi "expiry" <<<"$2"' _ "$rc" "$out"
case_root nested; osv GHSA-zzzz-zzzz-zzzz 2099-01-01 'no citation' sub/osv-scanner.toml; chk
ck "an osv-scanner.toml in a subdirectory is checked too" bash -c '[ "$1" = 1 ] && grep -q "sub/osv-scanner.toml" <<<"$2"' _ "$rc" "$out"
case_root glbase; gl ''; chk
ck "a .gitleaks.toml with only the three permitted paths: pass" [ "$rc" = 0 ]
case_root glgrow; gl "  '''^src/'''"; chk
ck "an allowlist path beyond the three without a SEC-NNN fails (the allowlist grew)" bash -c '[ "$1" = 1 ] && grep -q "gitleaks.toml" <<<"$2"' _ "$rc" "$out"
case_root glcited '^src/generated/'; gl "  '''^src/generated/''',  # SEC-001 generated test keys"; chk
ck "…and passes when the new entry cites an active SEC-NNN whose suppresses: names it" [ "$rc" = 0 ]
case_root glreuse; gl "  '''^src/generated/''',  # SEC-001 generated test keys"; chk
ck "an allowlist path citing an active SEC-NNN whose suppresses: omits it fails (no riding on an old id)" bash -c '[ "$1" = 1 ] && grep -qF "^src/generated/" <<<"$2"' _ "$rc" "$out"
case_root glnodefault; printf '[allowlist]\npaths = []\n' > "$C/.gitleaks.toml"; chk
ck "a .gitleaks.toml that drops the default rules fails" bash -c '[ "$1" = 1 ] && grep -q useDefault <<<"$2"' _ "$rc" "$out"
case_root glregex; printf "[extend]\nuseDefault = true\n[allowlist]\nregexes = [\n  '''AKIA.*''',\n]\n" > "$C/.gitleaks.toml"; chk
ck "an allowlist regex without a SEC-NNN fails" [ "$rc" = 1 ]
case_root glignore; printf 'abc123:src/a.py:generic-api-key:4\n' > "$C/.gitleaksignore"; chk
ck "a .gitleaksignore fingerprint without a preceding '# SEC-NNN' line fails" [ "$rc" = 1 ]
case_root glignoreok 'abc123:src/a.py:generic-api-key:4'; printf '# SEC-001 fixture key\nabc123:src/a.py:generic-api-key:4\n' > "$C/.gitleaksignore"; chk
ck "…and passes with one" [ "$rc" = 0 ]
case_root nosec2; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec B602\n' > "$C/src/app/x.py"; chk
ck "a '# nosec' under a source root without a SEC-NNN fails, naming file and line" bash -c '[ "$1" = 1 ] && grep -q "src/app/x.py:2" <<<"$2"' _ "$rc" "$out"
d=$(python3 -c 'import hashlib; print(hashlib.sha256(b"subprocess.run(\"ls\", shell=True)").hexdigest()[:12])')
case_root nosec3 "src/app/x.py:B602:$d"; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec B602 SEC-001\n' > "$C/src/app/x.py"; chk
ck "…and passes when it cites an active SEC-NNN listing <file>:<test id>:<digest of the code>" [ "$rc" = 0 ]
case_root nosecreuse; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec B602 SEC-001\n' > "$C/src/app/x.py"; chk
ck "a '# nosec' citing an active SEC-NNN that does not list it fails, printing the name to list" bash -c '[ "$1" = 1 ] && grep -qF "src/app/x.py:B602:$3" <<<"$2"' _ "$rc" "$out" "$d"
case_root nosecbare "src/app/x.py:B602:$d"; mkdir -p "$C/src/app"; printf 'import subprocess\nsubprocess.run("ls", shell=True)  # nosec SEC-001\n' > "$C/src/app/x.py"; chk
ck "a bare '# nosec' (no bandit test id) fails" bash -c '[ "$1" = 1 ] && grep -qi "test id" <<<"$2"' _ "$rc" "$out"
case_root latest; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: x'
printf -- '---\nid: SEC-001\nstatus: fixed\nowner: alice\nrationale: "fixture: upgraded in 0.10.0"\n---\n' > "$C/docs/security/0.10.0-disposition.md"
printf -- '---\nid: SEC-001\nstatus: accepted\nowner: alice\nexpiry: 2099-06-30\nrationale: "fixture: older entry"\nsuppresses: [RUSTSEC-2099-0001]\n---\n' > "$C/docs/security/0.9.0-disposition.md"; chk
ck "the latest entry per id wins by version (0.10.0 after 0.9.0 and 0.1.0): fixed, so the suppression fails" [ "$rc" = 1 ]
# P4 final review: the disposition reader fails closed. A block config.parse rejects, a block with no id:, and a
# *-disposition.md whose name carries no version are suppression errors, never skipped — otherwise a newer entry
# that marks an id fixed could be ignored and an older accepted one stay latest. Within one file a later block for
# the same id wins (the file's last word on it).
case_root dispbad; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01'
printf -- '---\nid: SEC-001\nstatus: fixed\nowner: alice\nrationale: "fixture: upgraded in 0.2.0"\n  a stray indented line\n---\n' > "$C/docs/security/0.2.0-disposition.md"; chk
ck "an unparsable block in a newer disposition fails the check (fail closed), naming the file" \
  bash -c '[ "$1" = 1 ] && grep -qF "docs/security/0.2.0-disposition.md" <<<"$2"' _ "$rc" "$out"
case_root dispnoid; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01'
printf -- '---\nId: SEC-001\nstatus: fixed\nowner: alice\nrationale: "fixture: upgraded in 0.2.0"\n---\n' > "$C/docs/security/0.2.0-disposition.md"; chk
ck "a disposition block with no id: fails the check" bash -c '[ "$1" = 1 ] && grep -qF "0.2.0-disposition.md" <<<"$2"' _ "$rc" "$out"
case_root dispname; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01'
printf -- '---\nid: SEC-001\nstatus: fixed\nowner: alice\nrationale: "fixture: upgraded"\n---\n' > "$C/docs/security/next-disposition.md"; chk
ck "a *-disposition.md with no recognisable version fails the check, naming it" bash -c '[ "$1" = 1 ] && grep -qF "next-disposition.md" <<<"$2"' _ "$rc" "$out"
case_root dispwithin; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01'
printf -- '\n---\nid: SEC-001\nstatus: fixed\nowner: alice\nrationale: "fixture: upgraded later in the same release"\n---\n' >> "$C/docs/security/0.1.0-disposition.md"; chk
ck "within one file, a later block for the same id wins (here: fixed, so the suppression fails)" \
  bash -c '[ "$1" = 1 ] && grep -q "fixed" <<<"$2"' _ "$rc" "$out"
case_root dispunterm; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01'
printf -- '---\nid: SEC-001\nstatus: fixed\nowner: alice\nrationale: "fixture: upgraded in 0.2.0, closing fence forgotten"\n' > "$C/docs/security/0.2.0-disposition.md"; chk
ck "a newer disposition whose final block never closes fails the check (fail closed), naming 'unterminated disposition block'" \
  bash -c '[ "$1" = 1 ] && grep -qF "docs/security/0.2.0-disposition.md" <<<"$2" && grep -qF "unterminated disposition block" <<<"$2"' _ "$rc" "$out"
# Advisory ignores carry an ignoreUntil (the floor applies it to every tool; the check compares it with expiry only).
case_root osvnountil; printf '[[IgnoredVulns]]\nid = "GHSA-aaaa-bbbb-cccc"\nreason = "SEC-001: fixture"\n' > "$C/osv-scanner.toml"; chk
ck "an IgnoredVulns without ignoreUntil fails" bash -c '[ "$1" = 1 ] && grep -q ignoreUntil <<<"$2"' _ "$rc" "$out"
case_root auditnountil; audit '"RUSTSEC-2099-0001",  # SEC-001 reason: fixture'; chk
ck "an audit.toml entry without 'ignoreUntil: YYYY-MM-DD' fails" bash -c '[ "$1" = 1 ] && grep -q ignoreUntil <<<"$2"' _ "$rc" "$out"
# Config-level routes: every key or table outside a suppression file's whitelist is an entry that cites a SEC-NNN.
case_root osvpkg; printf '[[PackageOverrides]]\nname = "lodash"\necosystem = "npm"\nignore = true\n' > "$C/osv-scanner.toml"; chk
ck "an osv-scanner.toml [[PackageOverrides]] (a whole-package ignore) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q PackageOverrides <<<"$2"' _ "$rc" "$out"
# A config entry is named <file>:<dotted key>[<digest>] — the first 12 hex of the sha256 of its value's JSON with
# sorted keys — and an array of tables is one entry per table, each with its own # SEC-NNN on its own header line,
# so a second table, or a changed one, cannot ride on an old SEC id (R9; P4 final review).
dg() { python3 -c 'import hashlib, json, sys; print(hashlib.sha256(json.dumps(json.loads(sys.argv[1]), sort_keys=True).encode()).hexdigest()[:12])' "$1"; }
LOD=$(dg '{"name": "lodash", "ecosystem": "npm", "ignore": true}')
PKG_LOD='[[PackageOverrides]]  # SEC-001 fixture\nname = "lodash"\necosystem = "npm"\nignore = true\n'
case_root osvpkgok "osv-scanner.toml:PackageOverrides[$LOD]"; printf "$PKG_LOD" > "$C/osv-scanner.toml"; chk
ck "…and passes when its header cites an active SEC-NNN that lists osv-scanner.toml:PackageOverrides[<digest>]" [ "$rc" = 0 ]
case_root osvpkgbare 'osv-scanner.toml:PackageOverrides'; printf "$PKG_LOD" > "$C/osv-scanner.toml"; chk
ck "…a disposition listing the bare key osv-scanner.toml:PackageOverrides no longer covers a table, and the output names the entry to list" \
  bash -c '[ "$1" = 1 ] && grep -qF "osv-scanner.toml:PackageOverrides[$3]" <<<"$2"' _ "$rc" "$out" "$LOD"
case_root osvpkgride "osv-scanner.toml:PackageOverrides[$LOD]"; printf "$PKG_LOD"'\n[[PackageOverrides]]\nname = "evil"\necosystem = "npm"\nignore = true\n' > "$C/osv-scanner.toml"; chk
ck "a second, uncited [[PackageOverrides]] does not ride on the first table's SEC-NNN" bash -c '[ "$1" = 1 ] && grep -q "PackageOverrides" <<<"$2"' _ "$rc" "$out"
case_root osvpkgride2 "osv-scanner.toml:PackageOverrides[$LOD]"; printf "$PKG_LOD"'\n[[PackageOverrides]]  # SEC-001\nname = "evil"\necosystem = "npm"\nignore = true\n' > "$C/osv-scanner.toml"; chk
ck "…nor does a second table citing the same SEC-NNN that does not list it" [ "$rc" = 1 ]
case_root osvpkgchanged "osv-scanner.toml:PackageOverrides[$LOD]"; printf '[[PackageOverrides]]  # SEC-001 fixture\necosystem = "npm"\nignore = true\n' > "$C/osv-scanner.toml"; chk
ck "a cited table whose content changed (here: every npm package) no longer matches its listed name" [ "$rc" = 1 ]
case_root osvpkginline "osv-scanner.toml:PackageOverrides[$LOD]"; printf 'PackageOverrides = [{name = "lodash", ecosystem = "npm", ignore = true}]  # SEC-001\n' > "$C/osv-scanner.toml"; chk
ck "an inline array of tables fails: each table needs its own [[header]] line and citation" bash -c '[ "$1" = 1 ] && grep -qF "[[PackageOverrides]]" <<<"$2"' _ "$rc" "$out"
R1=$(dg '{"id": "a", "regex": "x^"}')
case_root glrulesride ".gitleaks.toml:rules[$R1]"; printf 'stack: python\n' > "$C/.specflow.yml"
printf "[extend]\nuseDefault = true\n\n[[rules]]  # SEC-001\nid = \"a\"\nregex = '''x^'''\n\n[[rules]]\nid = \"b\"\nregex = '''x^'''\n" > "$C/.gitleaks.toml"; chk
ck "a second, uncited .gitleaks.toml [[rules]] does not ride on the first" [ "$rc" = 1 ]
case_root glrulesok ".gitleaks.toml:rules[$R1]"; printf 'stack: python\n' > "$C/.specflow.yml"
printf "[extend]\nuseDefault = true\n\n[[rules]]  # SEC-001\nid = \"a\"\nregex = '''x^'''\n" > "$C/.gitleaks.toml"; chk
ck "…while one cited [[rules]] table listed by its digest passes" [ "$rc" = 0 ]
DR1=$(dg '["generic-api-key"]')
case_root gldisok ".gitleaks.toml:extend.disabledRules[$DR1]"; printf '[extend]\nuseDefault = true\ndisabledRules = ["generic-api-key"]  # SEC-001\n' > "$C/.gitleaks.toml"; chk
ck "a cited [extend] disabledRules listed by its digest passes" [ "$rc" = 0 ]
case_root gldisgrow ".gitleaks.toml:extend.disabledRules[$DR1]"; printf '[extend]\nuseDefault = true\ndisabledRules = ["generic-api-key", "aws-access-token"]  # SEC-001\n' > "$C/.gitleaks.toml"; chk
ck "…and fails once it grows without a disposition change" [ "$rc" = 1 ]
case_root gldisabled; printf '[extend]\nuseDefault = true\ndisabledRules = ["generic-api-key"]\n' > "$C/.gitleaks.toml"; chk
ck "a .gitleaks.toml [extend] disabledRules without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q disabledRules <<<"$2"' _ "$rc" "$out"
case_root glrules; printf 'stack: python\n' > "$C/.specflow.yml"; printf "[extend]\nuseDefault = true\n\n[[rules]]\nid = \"generic-api-key\"\nregex = '''x^'''\n" > "$C/.gitleaks.toml"; chk
ck "an instance's .gitleaks.toml [[rules]] (overriding a default rule) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q rules <<<"$2"' _ "$rc" "$out"
case_root audittarget; printf '[advisories]\nignore = []\n\n[target]\nos = "linux"\n' > "$C/audit.toml"; chk
ck "an audit.toml table beyond [advisories] ignore ([target]) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q target <<<"$2"' _ "$rc" "$out"
case_root banditini; mkdir -p "$C/src"; printf '[bandit]\nskips = B602\n' > "$C/src/.bandit"; chk
ck "a .bandit file under a source root (bandit reads it unasked) without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -qF "src/.bandit" <<<"$2"' _ "$rc" "$out"
case_root banditpy; printf '[tool.bandit]\nskips = ["B602"]\n' > "$C/pyproject.toml"; chk
ck "a [tool.bandit] key in pyproject.toml without a SEC-NNN fails" bash -c '[ "$1" = 1 ] && grep -q "tool.bandit" <<<"$2"' _ "$rc" "$out"
# #36 low: an unparsable pyproject.toml is a violation, like every other suppression file (fail closed) — bandit
# would read a [tool.bandit] table the check could not see.
case_root banditbad; printf '[tool.bandit\nskips = ["B602"]\n' > "$C/pyproject.toml"; chk
ck "an unparsable pyproject.toml fails the check, naming it (fail closed)" bash -c '[ "$1" = 1 ] && grep -q "unparsable pyproject.toml" <<<"$2"' _ "$rc" "$out"
# Which files: the template source leaves stacks/ to the per-pack-root runs; git-ignored copies never enter.
case_root tmpl; mkdir -p "$C/stacks/x/overlay"; printf '[advisories]\nignore = [\n  "RUSTSEC-2099-0009",\n]\n' > "$C/stacks/x/overlay/audit.toml"; chk
ck "template-shaped root: an uncited stacks/x/overlay/audit.toml is left to the pack-root run (root check passes)" [ "$rc" = 0 ]
rc=0; out=$(bash "$CS" --root "$C/stacks/x/overlay" 2>&1) || rc=$?
ck "…and the pack-root run fails on it" bash -c '[ "$1" = 1 ] && grep -q "RUSTSEC-2099-0009" <<<"$2"' _ "$rc" "$out"
printf 'stack: python\n' > "$C/.specflow.yml"; chk
ck "…while in an instance nothing under stacks/ is skipped" [ "$rc" = 1 ]
case_root ignored; mkdir -p "$C/wt/copy"; printf '[advisories]\nignore = [\n  "RUSTSEC-2099-0009",\n]\n' > "$C/wt/copy/audit.toml"
printf 'wt/\n' > "$C/.gitignore"; (cd "$C" && git init -q -b main && git add -A && git commit -qm ignored); chk
ck "in a git work tree, an ignored copy (as .claude/worktrees/* is) is never scanned" [ "$rc" = 0 ]

# H4 (REQ-388): each pack root's suppressions cite a SEC-NNN its own shipped disposition defines (template source only).
if ! instance; then
  shopt -s nullglob
  for r in "$ROOT"/stacks/*/overlay "$ROOT"/stacks/*/skeleton; do ck "${r#$ROOT/}: suppressions cite the pack's own active SEC-NNN" bash "$CS" --root "$r"; done
  shopt -u nullglob
fi
finish test_suppressions
