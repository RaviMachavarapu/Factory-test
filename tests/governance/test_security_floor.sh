#!/usr/bin/env bash
# REQ-330: the security floor — gitleaks over the full history with the repository's .gitleaks.toml, osv-scanner over
# every tracked lockfile with one config, then the instance's security-<stack>.sh; a missing floor tool is a hard FAIL
# with an install hint (as for Dafny); a machine-readable summary for /security-review; SPECFLOW_FLOOR_OFFLINE=1 skips
# the advisory lookups loudly. REQ-360: run-quality-gates.sh reports floor failures apart from gate failures.
# Covers: REQ-330
# Covers: REQ-360
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
[[ -f "$ROOT/scripts/run-security-floor.sh" ]] || { fail "scripts/run-security-floor.sh missing"; finish test_security_floor; }
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
S="$W/stub"; floor_stubs "$S"
MIN="$W/min"; mkdir -p "$MIN"   # system tools only: the host's real gitleaks and osv-scanner cannot leak in
for t in bash sh env python3 git sed awk grep tr cat dirname basename uname mkdir rm cp mv ls head tail find sort wc date mktemp tee cut xargs; do
  p=$(command -v "$t" 2>/dev/null || true); if [[ "$p" == /* ]]; then ln -sf "$p" "$MIN/$t"; fi
done
R="$W/repo"; mkdir -p "$R/scripts/lib/specflow"
cp "$ROOT/scripts/run-security-floor.sh" "$ROOT/scripts/run-quality-gates.sh" "$R/scripts/"
cp "$ROOT"/scripts/lib/specflow/{config.py,floor.py,floor.sh,blocks.py,cvss4.py,cvss4_data.py} "$R/scripts/lib/specflow/"
cp "$ROOT/.gitleaks.toml" "$R/"; printf '.specflow/floor-summary.json\n' > "$R/.gitignore"
(cd "$R" && git init -q -b main && git add -A && git commit -qm base)
SUM="$R/.specflow/floor-summary.json"
fl() {  # fl [VAR=VALUE…] — the floor in $R with stub tools only; sets rc and out
  rm -f "$S"/*.argv; rc=0
  out=$(cd "$R" && PATH="$S/bin:$MIN" PYTHONPATH="$S/py" STUB_DIR="$S" env -u SPECFLOW_FLOOR_OFFLINE "$@" bash scripts/run-security-floor.sh 2>&1) || rc=$?
}
first() { awk '/^---$/{exit} {print}' "$S/$1.argv" 2>/dev/null || true; }
pair() { awk -v a="$1" -v b="$2" 'p == a && $0 == b {f = 1} {p = $0} END {exit !f}'; }

# 1. No tracked lockfile: gitleaks over the full history with the repository's config; osv-scanner a noted PASS.
fl
ck "clean repository, no lockfile: exit 0" [ "$rc" = 0 ]
g=$(first gitleaks)
ck "gitleaks git (full history), not dir" [ "$(head -1 <<<"$g")" = git ]
for f in --no-banner --redact --ignore-gitleaks-allow; do ck "gitleaks $f" grep -qx -- "$f" <<<"$g"; done
ck "gitleaks --config .gitleaks.toml (the repository's allowlist)" pair --config .gitleaks.toml <<<"$g"
ck "gitleaks scans the repository root (last argument .)" [ "$(tail -1 <<<"$g")" = . ]
for f in --baseline-path -b; do ck "gitleaks: no $f (the floor passes no baseline, R16)" no grep -qx -- "$f" <<<"$g"; done
ck "osv-scanner not run without a tracked lockfile, and the floor says so" \
  bash -c '[ ! -s "$1" ] && grep -q "^PASS floor osv-scanner \[\.\] .*no tracked lockfile" <<<"$2"' _ "$S/osv-scanner.argv" "$out"
ck "the summary is written" test -s "$SUM"
ck "summary: schema 1, online, HEAD, clean, gitleaks pass 8.30.1, osv-scanner not-applicable" python3 - "$SUM" "$(git -C "$R" rev-parse HEAD)" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert s["schema"] == 1 and s["mode"] == "online" and s["commit"] == sys.argv[2] and s["dirty"] is False, s
t = {r["tool"]: r for r in s["tools"]}
assert t["gitleaks"]["status"] == "pass" and t["gitleaks"]["version"] == "8.30.1" and t["gitleaks"]["exit"] == 0, t
assert t["osv-scanner"]["status"] == "not-applicable" and t["osv-scanner"]["exit"] is None, t
assert t["osv-scanner"]["result"] == "not run — no tracked lockfile", t
assert s["suppressions"] == [] and s["suppression_errors"] == [], s
PY
fl GITLEAKS_CONFIG=/nonexistent.toml GITLEAKS_CONFIG_TOML='title = "x"'
ck "gitleaks never sees GITLEAKS_CONFIG or GITLEAKS_CONFIG_TOML from the environment" [ "$(cat "$S/gitleaks.env")" = "unset unset" ]

# 2. Tracked lockfiles, one config for all; an untracked lockfile is not the product's.
(cd "$R" && mkdir -p sub loose && printf 'six==1.17.0\n' > requirements.txt && : > sub/Cargo.lock && git add -A && git commit -qm locks && : > loose/package-lock.json)
fl
o=$(first osv-scanner)
ck "osv-scanner scan source, never -r" bash -c '[ "$(sed -n 1,2p <<<"$1" | tr "\n" " ")" = "scan source " ] && ! grep -qx -- -r <<<"$1"' _ "$o"
ck "…-L for exactly the tracked lockfiles" [ "$(awk 'p == "-L" {print} {p = $0}' <<<"$o" | LC_ALL=C sort | tr '\n' ' ')" = "requirements.txt sub/Cargo.lock " ]
ck "…one --config even without an osv-scanner.toml (per-directory configs never apply)" \
  bash -c 'c=$(awk "p == \"--config\" {print} {p = \$0}" <<<"$1"); [ -n "$c" ] && [ "$c" != osv-scanner.toml ]' _ "$o"
(cd "$R" && printf '# no ignores\n' > osv-scanner.toml && git add -A && git commit -qm cfg)
fl
ck "…--config osv-scanner.toml when the repository has one" pair --config osv-scanner.toml <<<"$(first osv-scanner)"
fl STUB_OSV_SCANNER_RC=1
ck "an advisory: exit 1, FAIL floor osv-scanner" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner" <<<"$2"' _ "$rc" "$out"
ck "…a findings line, never 'lookup failed'" bash -c 'grep -q "^FAIL floor osv-scanner.*findings" <<<"$1" && ! grep -q "lookup failed" <<<"$1"' _ "$out"
fl STUB_OSV_SCANNER_RC=128
ck "exit 128 with tracked lockfiles is a FAIL, never the 'no package sources' PASS" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner" <<<"$2"' _ "$rc" "$out"
ck "…reported as an error, not as findings" grep -q '^FAIL floor osv-scanner .*error, not findings' <<<"$out"
fl STUB_OSV_SCANNER_RC=127 STUB_OSV_SCANNER_MSG='failed to fetch: Post "https://api.osv.dev/v1/querybatch": dial tcp: lookup api.osv.dev: no such host'
ck "a network failure (exit 127, no such host): FAIL floor osv-scanner … lookup failed, with the rerun hint" \
  bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner .*lookup failed" <<<"$2" && grep -qF SPECFLOW_FLOOR_OFFLINE=1 <<<"$2" && ! grep -q "^FAIL floor osv-scanner.*findings" <<<"$2"' _ "$rc" "$out"
ck "…recorded as lookup-failed in the summary" python3 -c 'import json, sys
t = {r["tool"]: r for r in json.load(open(sys.argv[1]))["tools"]}; assert t["osv-scanner"]["status"] == "lookup-failed", t' "$SUM"
fl STUB_GITLEAKS_RC=1
ck "a leak: exit 1, FAIL floor gitleaks" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor gitleaks" <<<"$2"' _ "$rc" "$out"
ck "…recorded as fail, exit 1, in the summary" python3 -c 'import json, sys
t = {r["tool"]: r for r in json.load(open(sys.argv[1]))["tools"]}; assert t["gitleaks"]["status"] == "fail" and t["gitleaks"]["exit"] == 1, t' "$SUM"

# 3. A missing floor tool is a hard FAIL with an install hint, even offline (REQ-330: as for Dafny).
fl STUB_GITLEAKS_MISSING=1
ck "gitleaks missing: exit 1, FAIL floor gitleaks (missing), naming the checksum-verified installer and --doctor" bash -c \
  '[ "$1" = 1 ] && grep -q "^FAIL floor gitleaks \[\.\] (missing)" <<<"$2" && grep -qF "install-pinned-tool.sh gitleaks" <<<"$2" && grep -qF -- "--doctor" <<<"$2"' _ "$rc" "$out"
fl STUB_OSV_SCANNER_MISSING=1 SPECFLOW_FLOOR_OFFLINE=1
ck "osv-scanner missing is a FAIL even offline" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor osv-scanner.*(missing)" <<<"$2"' _ "$rc" "$out"

# 4. Offline (R2): every tool present; gitleaks (local) runs; advisory lookups skipped loudly and marked.
fl SPECFLOW_FLOOR_OFFLINE=1
ck "offline: exit 0, gitleaks ran, osv-scanner not invoked" bash -c '[ "$1" = 0 ] && [ -s "$2" ] && [ ! -s "$3" ]' _ "$rc" "$S/gitleaks.argv" "$S/osv-scanner.argv"
ck "offline: the SKIP line says it is not evidence" grep -q '^SKIP floor osv-scanner.*not valid evidence' <<<"$out"
ck "offline: summary mode offline, osv-scanner skipped-offline" python3 -c 'import json, sys
s = json.load(open(sys.argv[1])); t = {r["tool"]: r for r in s["tools"]}
assert s["mode"] == "offline" and t["osv-scanner"]["status"] == "skipped-offline", s' "$SUM"

# 5. Template source: the root scan leaves stacks/ out; each pack root is scanned with its own config.
(cd "$R" && mkdir -p stacks/tauri/overlay stacks/python/skeleton stacks/flutter/skeleton && : > stacks/tauri/overlay/package-lock.json \
  && printf '# pack config\n' > stacks/tauri/overlay/osv-scanner.toml && printf 'six==1.17.0\n' > stacks/python/skeleton/requirements.txt \
  && printf '# the runtime lock: no runtime dependency yet\n\n' > stacks/python/skeleton/requirements-runtime.txt \
  && : > stacks/flutter/skeleton/requirements-runtime.txt && git add -A && git commit -qm packs)
fl
ck "template: three osv-scanner runs (root, python skeleton, tauri overlay)" [ "$(grep -cx -- --- "$S/osv-scanner.argv")" = 3 ]
# P7 Build 1 fix wave 1, FIX 10 (REQ-330): osv-scanner 2.6.0 exits 128 ("No package sources found") when every lockfile it
# is given lists no package — the python skeleton's empty requirements-runtime.txt alone. A requirements*.txt with no
# requirement line is left out with a printed note; a root whose every tracked lockfile is such a file is a noted PASS,
# osv-scanner not run (the flutter skeleton above); one beside a real lockfile is scanned without it.
ck "an empty requirements-runtime.txt beside requirements.txt: the python skeleton's run passes -L requirements.txt alone" \
  python3 -c 'import sys
runs = [r.split("\n") for r in open(sys.argv[1]).read().split("---\n") if r.strip()]
py = [r for r in runs if any(a.startswith("stacks/python/skeleton/") for a in r)]
assert len(py) == 1 and [b for a, b in zip(py[0], py[0][1:]) if a == "-L"] == ["stacks/python/skeleton/requirements.txt"], py' "$S/osv-scanner.argv"
ck "…and prints a note naming the file left out" \
  grep -qF 'NOTE floor osv-scanner [stacks/python/skeleton]: stacks/python/skeleton/requirements-runtime.txt lists no package — not scanned' <<<"$out"
# PR #65 verifier run 1, code mode (REQ-330): the omission reaches the floor record the review's '## Tools run' renders,
# not stdout alone — the scanned root's result names the empty lockfile left out; a root whose every lockfile is empty
# records the one not-run result check-review accepts beside exit '-', so the rendered section round-trips.
ck "the floor record: the python skeleton's osv-scanner result names the empty lockfile left out" python3 - "$SUM" <<'PY2'
import json, sys
t = {(x["tool"], x["scope"]): x for x in json.load(open(sys.argv[1]))["tools"]}
r = t[("osv-scanner", "stacks/python/skeleton")]
assert r["status"] == "pass" and r["result"] == "clean; empty lockfile stacks/python/skeleton/requirements-runtime.txt omitted", r
PY2
ck "the floor record renders a '## Tools run' that check-review accepts (the all-empty root's not-run row included)" \
  bash -c 'cd "$1" && md=$(python3 scripts/lib/specflow/floor.py render --summary "$2" --root .) && grep -qF "| osv-scanner | stacks/flutter/skeleton |" <<<"$md" && mkdir -p "$3/docs/security" && printf "# Security Review — v0.1.0\n\n## Summary\n0 findings.\n\n%s\n" "$md" > "$3/docs/security/0.1.0-review.md" && python3 scripts/lib/specflow/floor.py check-review "$3/docs/security/0.1.0-review.md" --root .' _ "$R" "$SUM" "$W/rt"
ck "a root whose only lockfile lists no package: a noted PASS, osv-scanner not run" \
  bash -c 'grep -q "^PASS floor osv-scanner \[stacks/flutter/skeleton\] .*not run — no tracked lockfile lists a package" <<<"$1" && ! grep -qx "stacks/flutter/skeleton/requirements-runtime.txt" "$2"' _ "$out" "$S/osv-scanner.argv"
ck "template: the root run names no stacks/ path" no grep -q '^stacks/' <<<"$(first osv-scanner)"
ck "template: the tauri overlay run uses the overlay's own osv-scanner.toml" grep -qx stacks/tauri/overlay/osv-scanner.toml "$S/osv-scanner.argv"
ck "template: a pack root's result carries its scope" grep -q '^PASS floor osv-scanner \[stacks/tauri/overlay\]' <<<"$out"

# 6. Instance: the stack's security script runs after the core floor and is recorded; a missing one is a FAIL.
(cd "$R" && git rm -rq stacks && printf 'stack: python\n' > .specflow.yml && git add -A && git commit -qm instance)
cat > "$R/scripts/security-python.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source scripts/lib/specflow/floor.sh
floor_tool --online pip-audit requirements.txt 'echo pip-audit 2.10.1' 'pip install --require-hashes -r requirements.txt' -- bash -c 'exit "${FAKE_RC:-0}"'
EOF
chmod +x "$R/scripts/security-python.sh"
fl
ck "instance: the stack script's tool is in the summary" python3 -c 'import json, sys
assert "pip-audit" in [r["tool"] for r in json.load(open(sys.argv[1]))["tools"]]' "$SUM"
fl FAKE_RC=1
ck "instance: the stack script's failure fails the floor" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor pip-audit" <<<"$2"' _ "$rc" "$out"
chmod -x "$R/scripts/security-python.sh"; fl
ck "instance: a configured stack without an executable security script is a FAIL" bash -c '[ "$1" = 1 ] && grep -q "^FAIL floor security-python.sh" <<<"$2"' _ "$rc" "$out"
chmod +x "$R/scripts/security-python.sh"

# 7. REQ-360: the gates run the floor as its own section and list floor failures apart from gate failures.
qg() { rc=0; out=$(cd "$R" && PATH="$S/bin:$MIN" PYTHONPATH="$S/py" STUB_DIR="$S" env -u SPECFLOW_QG_RUNNING -u SPECFLOW_FLOOR_OFFLINE "$@" bash scripts/run-quality-gates.sh 2>&1) || rc=$?; }
qg STUB_OSV_SCANNER_RC=1
ck "gates: a '=== Security floor ===' section" grep -qx '=== Security floor ===' <<<"$out"
ck "gates: exit 1" [ "$rc" = 1 ]
sm=$(sed -n '/^=== Summary ===/,$p' <<<"$out")
ck "summary: the missing hook is listed under Gate failures" bash -c 'sed -n "/^Gate failures/,/^Floor failures/p" <<<"$1" | grep -q "FAIL scripts/quality-gates-python.sh"' _ "$sm"
ck "summary: the advisory is under Floor failures, and no floor line is under Gate failures" bash -c \
  'sed -n "/^Floor failures/,\$p" <<<"$1" | grep -q "FAIL floor osv-scanner" && ! sed -n "/^Gate failures/,/^Floor failures/p" <<<"$1" | grep -q "FAIL floor"' _ "$sm"
printf '#!/usr/bin/env bash\necho PASS lint\n' > "$R/scripts/quality-gates-python.sh"; chmod +x "$R/scripts/quality-gates-python.sh"
qg
ck "gates all green: 'Gate failures: none', 'Floor failures: none', 'All quality gates passed'" bash -c \
  '[ "$1" = 0 ] && grep -qx "Gate failures: none" <<<"$2" && grep -qx "Floor failures: none" <<<"$2" && grep -qx "All quality gates passed" <<<"$2"' _ "$rc" "$out"
ck "this repository's gates run the floor" grep -q 'run-security-floor.sh' "$ROOT/scripts/run-quality-gates.sh"
ck ".specflow/floor-summary.json is gitignored (a run leaves the tree clean)" git -C "$ROOT" check-ignore -q --no-index .specflow/floor-summary.json
ck "no workflow sets SPECFLOW_FLOOR_OFFLINE (CI evidence is always online)" no grep -rq SPECFLOW_FLOOR_OFFLINE "$ROOT/.github"
finish test_security_floor
