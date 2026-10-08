#!/usr/bin/env bash
# REQ-330 (H1, H12): CI installs gitleaks and osv-scanner from the checksum-verified assets (cached) and runs the floor on
# the full history; every pack action installs its pinned toolchain and the floor tools (REQ-303), cargo-audit with
# cargo install --locked --version, Python tools from hash-pinned lockfiles; app stacks get a checksum-pinned macOS
# Dafny. REQ-360: the first-run jobs can run an instance's floor.
# Covers: REQ-330
# Covers: REQ-303
# Covers: REQ-360
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CI=.github/workflows/ci.yml
job() { awk -v j="  $1:" '$0 == j {f = 1; print; next} f && /^  [A-Za-z#]/ {exit} f' "$CI"; }
gates=$(job gates)
ck "ci.yml gates: checkout with fetch-depth: 0 (gitleaks scans the full history)" grep -qE 'fetch-depth:[[:space:]]*0' <<<"$gates"
ck "ci.yml gates: installs gitleaks and osv-scanner with install-pinned-tool.sh" grep -qE 'install-pinned-tool\.sh.*gitleaks.*osv-scanner' <<<"$gates"
ck "ci.yml gates: …only when no pack toolchain action provides them" grep -qF "hashFiles('.github/actions/toolchain/action.yml') == ''" <<<"$gates"
ck "ci.yml gates: the asset cache is keyed on scripts/pinned-tools.yml" grep -qF 'pinned-tools.yml' <<<"$gates"
if ! instance; then
  fr=$(job first-run)
  ck "first-run job: installs the floor tools" grep -qF 'install-pinned-tool.sh' <<<"$fr"
  ck "first-run job: installs the python instance lockfile (pip-audit, bandit) with --require-hashes" grep -qF 'pip install --require-hashes -r stacks/python/skeleton/requirements.txt' <<<"$fr"
  acts="stacks/python/action.yml stacks/tauri/action.yml stacks/flutter/action.yml"
else
  acts=".github/actions/toolchain/action.yml"
fi
for a in $acts; do
  [[ -f "$a" ]] || continue
  ck "$a: installs gitleaks and osv-scanner from the pinned, checksum-verified assets" grep -qE 'install-pinned-tool\.sh.*gitleaks.*osv-scanner' "$a"
  ck "$a: no 'in P4' placeholder left" no grep -q 'in P4' "$a"
  ck "$a: never turns the floor offline" no grep -q SPECFLOW_FLOOR_OFFLINE "$a"
done
if ! instance; then
  pin=$(python3 scripts/lib/specflow/config.py --file stacks/tauri/pack.yml get cargo_audit_version 2>/dev/null || true)
  ck "tauri pack.yml pins cargo_audit_version ($pin)" [ -n "$pin" ]
  ck "tauri action: cargo install cargo-audit --locked --version, defaulting to the pack pin" \
    bash -c 'grep -qF "cargo install cargo-audit --locked --version" "$1" && grep -qF "$2" "$1"' _ stacks/tauri/action.yml "${pin:-none}"
  ck "tauri action: the cargo-audit binary is cached" bash -c 'grep -q "\.cargo/bin/cargo-audit" "$1" && grep -q "actions/cache@" "$1"' _ stacks/tauri/action.yml
  ck "python action: both lockfiles installed with --require-hashes" \
    bash -c 'grep -qF "pip install --require-hashes -r scripts/requirements.txt" "$1" && grep -qF "pip install --require-hashes -r requirements.txt" "$1"' _ stacks/python/action.yml
  for s in tauri flutter; do
    ck "$s action: Dafny from the checksum-pinned macOS asset when proofs exist" \
      bash -c 'grep -qF "install-pinned-tool.sh dafny" "$1" && grep -qF "hashFiles('"'"'verification/**/*.dfy'"'"')" "$1"' _ "stacks/$s/action.yml"
  done
  ck "python action: no Dafny step (ci.yml's Linux step installs it)" no grep -qi dafny stacks/python/action.yml
  ck "app-stacks.yml: its jobs use the pack actions (which carry the floor tools)" \
    bash -c 'grep -qF "uses: ./stacks/tauri" "$1" && grep -qF "uses: ./stacks/flutter" "$1"' _ .github/workflows/app-stacks.yml
fi
finish test_ci_floor
