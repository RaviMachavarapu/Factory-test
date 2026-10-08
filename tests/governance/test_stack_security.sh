#!/usr/bin/env bash
# REQ-331: each pack's security.sh runs the pinned real CLIs and fails on any finding its ignore file does not list;
# thresholds only where the tool has them (bandit, npm). REQ-303: packs declare floor_tools and lockfiles.
# Template source only (init removes stacks/); stub tools, no toolchain, no network.
# Covers: REQ-331
# Covers: REQ-303
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — init removed stacks/"; exit 0; }
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
S="$W/stub"; floor_stubs "$S"; CFG="$ROOT/scripts/lib/specflow/config.py"
for s in python tauri flutter; do
  ck "$s: security.sh is no longer the P4 stub" no grep -q 'security floor lands in P4' "$ROOT/stacks/$s/security.sh"
  ck "$s: security.sh sources the floor helper" grep -q 'scripts/lib/specflow/floor.sh' "$ROOT/stacks/$s/security.sh"
  ck "$s: pack.yml declares floor_tools" python3 "$CFG" --file "$ROOT/stacks/$s/pack.yml" getlist floor_tools
  ck "$s: pack.yml declares lockfiles" python3 "$CFG" --file "$ROOT/stacks/$s/pack.yml" getlist lockfiles
done
mkinst() {  # mkinst STACK — a stub instance: the floor helpers, the pack's pack.yml and security script; sets I
  I="$W/$1"; rm -rf "$I"; mkdir -p "$I/scripts/lib/specflow" "$I/.specflow"
  cp "$ROOT"/scripts/lib/specflow/{config.py,floor.py,floor.sh,blocks.py,cvss4.py,cvss4_data.py} "$I/scripts/lib/specflow/"
  cp "$ROOT/stacks/$1/pack.yml" "$I/.specflow/pack.yml"; cp "$ROOT/stacks/$1/security.sh" "$I/scripts/security-$1.sh"
  printf 'stack: %s\n' "$1" > "$I/.specflow.yml"
}
sec() {  # sec STACK [VAR=VALUE…] — the installed security script, stubs first, the caller's SPECFLOW_FLOOR_OFFLINE dropped; sets rc and out
  local s="$1"; shift; rm -f "$S"/*.argv; rc=0
  out=$(cd "$W/$s" && PATH="$S/bin:$PATH" PYTHONPATH="$S/py" STUB_DIR="$S" env -u SPECFLOW_FLOOR_OFFLINE "$@" bash "scripts/security-$s.sh" 2>&1) || rc=$?
}
argv() { awk '/^---$/{exit} {print}' "$S/$1.argv" 2>/dev/null || true; }
pair() { awk -v a="$1" -v b="$2" 'p == a && $0 == b {f = 1} {p = $0} END {exit !f}'; }
h64() { printf "$1%.0s" $(seq 64); }

# --- python: pip-audit on the product lockfile (ignores from osv-scanner.toml), bandit per source root ---
mkinst python; mkdir -p "$I/src/app"; printf 'x = 1\n' > "$I/src/app/__init__.py"
printf 'pytest==9.1.1 \\\n    --hash=sha256:%s\n' "$(h64 a)" > "$I/requirements.txt"
printf '[[IgnoredVulns]]\nid = "PYSEC-2099-1"\nignoreUntil = 2099-01-01\nreason = "SEC-001: fixture"\n\n[[IgnoredVulns]]\nid = "PYSEC-2000-1"\nignoreUntil = 2000-01-01\nreason = "SEC-001: fixture, expired"\n' > "$I/osv-scanner.toml"
sec python
ck "python: clean, exit 0" [ "$rc" = 0 ]
pa=$(argv pip_audit)
ck "python: pip-audit -r requirements.txt" pair -r requirements.txt <<<"$pa"
for f in --strict --disable-pip; do ck "python: pip-audit $f" grep -qx -- "$f" <<<"$pa"; done
ck "python: pip-audit --ignore-vuln from osv-scanner.toml" pair --ignore-vuln PYSEC-2099-1 <<<"$pa"
ck "python: an IgnoredVulns whose ignoreUntil has passed is not ignored (every tool expires it as osv-scanner does)" no grep -qx PYSEC-2000-1 <<<"$pa"
ck "…and the floor says so" grep -q 'PYSEC-2000-1.*expired' <<<"$out"
ba=$(argv bandit)
ck "python: bandit -r src" pair -r src <<<"$ba"
ck "python: bandit --severity-level high --confidence-level medium" bash -c 'awk "p == \"--severity-level\" && \$0 == \"high\" {a = 1} p == \"--confidence-level\" && \$0 == \"medium\" {b = 1} {p = \$0} END {exit !(a && b)}" <<<"$1"' _ "$ba"
for f in -b --baseline -s --skip -c --configfile --ini; do ck "python: bandit gets no $f (no baseline, no skips, no config; R16)" no grep -qx -- "$f" <<<"$ba"; done
ck "python: a floor line per tool, with scope and version" \
  bash -c 'grep -q "^PASS floor pip-audit \[requirements.txt\] (2.10.1, exit 0)" <<<"$1" && grep -q "^PASS floor bandit \[src\] (1.9.4, exit 0)" <<<"$1"' _ "$out"
sec python STUB_PIP_AUDIT_RC=1
ck "python: a pip-audit finding fails (exit 1, FAIL floor pip-audit)" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit" <<<"$2"' _ "$rc" "$out"
sec python STUB_BANDIT_RC=1
ck "python: a bandit finding fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor bandit" <<<"$2"' _ "$rc" "$out"
sec python STUB_PIP_AUDIT_RC=1 STUB_PIP_AUDIT_MSG="requests.exceptions.ConnectionError: HTTPSConnectionPool(host='pypi.org', port=443): Max retries exceeded"
ck "python: a pip-audit connection error is 'lookup failed', never findings" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit .*lookup failed" <<<"$2" && ! grep -q "^FAIL floor pip-audit.*findings" <<<"$2"' _ "$rc" "$out"
sec python STUB_PIP_AUDIT_MISSING=1
ck "python: pip-audit missing is a hard FAIL naming the hash-pinned install" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit.*(missing)" <<<"$2" && grep -qF "pip install --require-hashes -r requirements.txt" <<<"$2"' _ "$rc" "$out"
sec python SPECFLOW_FLOOR_OFFLINE=1
ck "python offline: pip-audit skipped loudly, bandit (local) still runs" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP floor pip-audit" <<<"$2" && grep -q "^PASS floor bandit" <<<"$2"' _ "$rc" "$out"
ck "python offline: pip-audit never invoked" [ ! -s "$S/pip_audit.argv" ]
rm "$I/requirements.txt"; mkdir -p "$I/scripts"; printf 'pytest==9.1.1 \\\n    --hash=sha256:%s\n' "$(h64 b)" > "$I/scripts/requirements.txt"
sec python
ck "python: no product lockfile, so scripts/requirements.txt is audited with a printed note (H16)" \
  bash -c '[ "$1" = 0 ] && grep -q "no product lockfile" <<<"$2"' _ "$rc" "$out"
ck "…pip-audit -r scripts/requirements.txt" pair -r scripts/requirements.txt <<<"$(argv pip_audit)"

# --- tauri: cargo audit with audit.toml's ignores as --ignore; npm audit filtered by osv-scanner.toml ---
mkinst tauri; mkdir -p "$I/src-tauri"; : > "$I/src-tauri/Cargo.lock"; echo '{}' > "$I/package-lock.json"
printf '[advisories]\nignore = [\n  "RUSTSEC-2099-0001",  # SEC-001 reason: fixture; ignoreUntil: 2099-01-01\n  "RUSTSEC-2000-0001",  # SEC-001 reason: fixture, expired; ignoreUntil: 2000-01-01\n]\n' > "$I/src-tauri/audit.toml"
printf '[[IgnoredVulns]]\nid = "GHSA-aaaa-bbbb-cccc"\nignoreUntil = 2099-01-01\nreason = "SEC-002: fixture"\n' > "$I/osv-scanner.toml"
sec tauri
ck "tauri: clean, exit 0" [ "$rc" = 0 ]
ca=$(argv cargo)
ck "tauri: cargo audit" [ "$(head -1 <<<"$ca")" = audit ]
ck "tauri: --deny warnings" pair --deny warnings <<<"$ca"
ck "tauri: --file src-tauri/Cargo.lock" pair --file src-tauri/Cargo.lock <<<"$ca"
ck "tauri: audit.toml's entry passed as --ignore (cargo-audit never reads src-tauri/audit.toml itself, R4)" pair --ignore RUSTSEC-2099-0001 <<<"$ca"
ck "tauri: an entry whose ignoreUntil has passed is not passed (the same expiry as osv-scanner's)" no grep -qx RUSTSEC-2000-0001 <<<"$ca"
na=$(argv npm)
ck "tauri: npm audit --audit-level=high --json" bash -c 'grep -qx audit <<<"$1" && grep -qx -- --audit-level=high <<<"$1" && grep -qx -- --json <<<"$1"' _ "$na"
npmv() { python3 -c 'import json, sys
print(json.dumps({"vulnerabilities": {"pkg": {"severity": sys.argv[1], "via": [{"source": 1, "severity": sys.argv[1], "url": "https://github.com/advisories/" + sys.argv[2]}]}}}))' "$1" "$2" > "$S/npm-audit.json"; }
npmv high GHSA-xxxx-yyyy-zzzz; sec tauri STUB_NPM_RC=1
ck "tauri: a high npm advisory not in osv-scanner.toml fails, naming it" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor npm-audit" <<<"$2" && grep -q GHSA-xxxx-yyyy-zzzz <<<"$2"' _ "$rc" "$out"
npmv high GHSA-aaaa-bbbb-cccc; sec tauri STUB_NPM_RC=1
ck "tauri: a high npm advisory listed in osv-scanner.toml passes" bash -c '[ "$1" = 0 ] && grep -q "^PASS floor npm-audit" <<<"$2"' _ "$rc" "$out"
npmv moderate GHSA-xxxx-yyyy-zzzz; sec tauri
ck "tauri: a moderate npm advisory is below the threshold" [ "$rc" = 0 ]
# P4 final review: the npm filter fails closed. A high or critical entry passes only when every advisory behind it
# carries a GHSA id the ignore list names; an advisory with no GHSA url (none, or npm's own advisory url) fails, as
# does an entry whose only via names a package the report does not list. npm's stderr never reaches the JSON.
npmraw() { python3 -c 'import json, sys; print(json.dumps({"vulnerabilities": json.loads(sys.argv[1])}))' "$1" > "$S/npm-audit.json"; }
npmraw '{"pkg": {"severity": "high", "via": [{"source": 1, "severity": "high", "title": "x"}]}}'; sec tauri STUB_NPM_RC=1
ck "tauri: a high npm advisory with no url fails (fail closed), never PASS" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor npm-audit" <<<"$2"' _ "$rc" "$out"
npmraw '{"pkg": {"severity": "critical", "via": [{"source": 1099, "severity": "critical", "url": "https://npmjs.com/advisories/1099"}]}}'; sec tauri STUB_NPM_RC=1
ck "tauri: a critical npm advisory with an npm-style url (no GHSA id) fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor npm-audit" <<<"$2"' _ "$rc" "$out"
npmraw '{"pkg": {"severity": "high", "via": ["ghost"]}}'; sec tauri STUB_NPM_RC=1
ck "tauri: a high entry whose only via names a package the report does not list fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor npm-audit" <<<"$2"' _ "$rc" "$out"
npmraw '{"dep": {"severity": "high", "via": ["pkg"]}, "pkg": {"severity": "high", "via": [{"source": 1, "severity": "high", "url": "https://github.com/advisories/GHSA-aaaa-bbbb-cccc"}]}}'; sec tauri STUB_NPM_RC=1
ck "tauri: a transitive high entry whose via is a listed package carrying an ignored GHSA passes" bash -c '[ "$1" = 0 ] && grep -q "^PASS floor npm-audit" <<<"$2"' _ "$rc" "$out"
rm -f "$S/npm-audit.json"; sec tauri STUB_NPM_MSG="npm warn config production Use --omit=dev instead."
ck "tauri: an npm warning on stderr does not turn a clean audit into 'error, not findings'" bash -c '[ "$1" = 0 ] && grep -q "^PASS floor npm-audit" <<<"$2"' _ "$rc" "$out"
echo '{"error": {"code": "ENOTFOUND", "summary": "registry unreachable"}}' > "$S/npm-audit.json"; sec tauri STUB_NPM_RC=1
ck "tauri: npm audit's own network error fails closed as 'lookup failed', not findings" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor npm-audit .*lookup failed" <<<"$2"' _ "$rc" "$out"
rm -f "$S/npm-audit.json"; sec tauri STUB_CARGO_RC=1
ck "tauri: a cargo-audit finding fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor cargo-audit" <<<"$2"' _ "$rc" "$out"
sec tauri STUB_CARGO_MISSING=1
ck "tauri: cargo-audit missing is a hard FAIL naming the pinned, locked install" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor cargo-audit.*(missing)" <<<"$2" && grep -qF "cargo install cargo-audit --locked --version" <<<"$2"' _ "$rc" "$out"
sec tauri SPECFLOW_FLOOR_OFFLINE=1
ck "tauri offline: both advisory lookups skipped loudly, exit 0" \
  bash -c '[ "$1" = 0 ] && grep -q "^SKIP floor cargo-audit" <<<"$2" && grep -q "^SKIP floor npm-audit" <<<"$2"' _ "$rc" "$out"

# --- flutter: osv-scanner on pubspec.lock with the instance's osv-scanner.toml; dart analyze stays in the gates hook ---
mkinst flutter; : > "$I/pubspec.lock"; printf '# no ignores\n' > "$I/osv-scanner.toml"
sec flutter
ck "flutter: clean, exit 0" [ "$rc" = 0 ]
oa=$(argv osv-scanner)
ck "flutter: osv-scanner scan source --config osv-scanner.toml -L pubspec.lock" \
  bash -c '[ "$(sed -n 1,2p <<<"$1" | tr "\n" " ")" = "scan source " ] && grep -qx -- --config <<<"$1" && grep -qx osv-scanner.toml <<<"$1" && grep -qx pubspec.lock <<<"$1"' _ "$oa"
sec flutter STUB_OSV_SCANNER_RC=1
ck "flutter: an advisory fails" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner" <<<"$2"' _ "$rc" "$out"
ck "flutter: dart analyze --fatal-infos stays in the gates hook (R7)" grep -q 'dart analyze --fatal-infos' "$ROOT/stacks/flutter/gates.sh"
ck "flutter: security.sh does not run dart analyze a second time" no grep -q 'dart analyze' "$ROOT/stacks/flutter/security.sh"
# The caller's SPECFLOW_FLOOR_OFFLINE never leaks into sec(): a maintainer who
# runs the gates offline gets the documented SKIP lines, not a gate failure here
# (REQ-360 keeps floor failures and gate failures apart).
if [ -z "${STACK_SECURITY_NESTED:-}" ]; then
  ck "the whole file passes under an exported SPECFLOW_FLOOR_OFFLINE=1" \
    env SPECFLOW_FLOOR_OFFLINE=1 STACK_SECURITY_NESTED=1 bash "${BASH_SOURCE[0]}"
fi
finish test_stack_security
