#!/usr/bin/env bash
# REQ-300 (--doctor) / REQ-308: --doctor names each missing prerequisite with
# its install command, changes nothing, exits 1 if any is missing; Dafny only
# while proofs exist.
# Covers: REQ-300, REQ-308
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — doctor fixtures run in the template source"; exit 0; }
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT
D="$WORK/t"; copy_template "$D"; BIN="$WORK/bin"; mkdir -p "$BIN"   # no gh, claude, dafny
for t in bash sh env python3 git sed awk grep tr cat dirname basename uname mkdir rm cp mv ls head tail find sort wc jq xargs; do
  p=$(command -v "$t" 2>/dev/null || true); if [[ "$p" == /* ]]; then ln -sf "$p" "$BIN/$t"; fi
done
doctor() { (cd "$1" && PATH="$BIN" bash scripts/init-project.sh --doctor --stack python </dev/null 2>&1); }
rc=0; out=$(doctor "$D") || rc=$?
ck "doctor exits 1 when prerequisites are missing" [ "$rc" = 1 ]
for t in gh claude; do ck "MISSING $t: <install command>" grep -qE "^MISSING $t: .+" <<<"$out"; done
for t in gitleaks osv-scanner; do ck "MISSING $t: the checksum-verified installer (a floor tool on every stack, REQ-330)" grep -qE "^MISSING $t: .*install-pinned-tool\.sh $t" <<<"$out"; done
ck "python doctor checks the python floor tools (pip-audit, bandit)" bash -c 'grep -qE "^(ok +|MISSING )pip_audit" <<<"$1" && grep -qE "^(ok +|MISSING )bandit" <<<"$1"' _ "$out"
ck "git reported present" grep -qE '^ok +git' <<<"$out"
if find "$D/verification" -name '*.dfy' | grep -q .; then ck "dafny required while proofs exist" grep -qE '^MISSING dafny: .+' <<<"$out"
  # The Ubuntu hint names the Dafny that CI pins (scripts/pinned-tools.yml) and its x64-ubuntu-22.04 asset, the name
  # Dafny's releases carry since 4.10 (the 2026-10-04 pin bump, retrospective item 1).
  # The doctor prints the hint for the OS uname names, so a uname stub that answers Linux selects the Ubuntu one.
  dv=$(python3 "$D/scripts/lib/specflow/config.py" --file "$D/scripts/pinned-tools.yml" get dafny_version)
  LBIN="$WORK/binlinux"; mkdir -p "$LBIN"; cp -P "$BIN"/* "$LBIN"/; rm -f "$LBIN/uname"
  printf '#!/bin/sh\necho Linux\n' > "$LBIN/uname"; chmod +x "$LBIN/uname"
  lout=$(cd "$D" && PATH="$LBIN" bash scripts/init-project.sh --doctor --stack python </dev/null 2>&1 || true)
  ck "dafny's Ubuntu hint names the pinned v$dv x64-ubuntu-22.04 zip" grep -qE "^MISSING dafny: .*releases/download/v$dv/dafny-$dv-x64-ubuntu-22\.04\.zip" <<<"$lout"
fi
find "$D/verification" -name '*.dfy' -delete
ck "dafny not demanded without proofs" no grep -q dafny <<<"$(doctor "$D" || true)"
ck "doctor changed nothing" [ ! -e "$D/.specflow.yml" -a ! -e "$D/.git" -a -d "$D/stacks" ]
D="$WORK/inst"; copy_template "$D"
ck "instance init" bash -c "cd '$D' && bash scripts/init-project.sh --name Inst --profile engineer </dev/null"
out=$(cd "$D" && bash scripts/init-project.sh --doctor </dev/null 2>&1 || true)
ck "doctor in an instance reports git" grep -qE '^ok +git' <<<"$out"
ck "doctor in an instance needs no stacks/" no grep -q 'stacks/' <<<"$out"

# H2: a stack whose pack is absent is MISSING, never "0 missing".
D="$WORK/nopack"; copy_template "$D"; rm -rf "$D/stacks/tauri"
rc=0; out=$(cd "$D" && bash scripts/init-project.sh --doctor --stack tauri </dev/null 2>&1) || rc=$?
ck "doctor --stack tauri without its pack exits 1" [ "$rc" = 1 ]
ck "doctor names the missing pack" grep -qE '^MISSING pack tauri: .*stacks/tauri/' <<<"$out"
rc=0; out=$(cd "$WORK/inst" && bash scripts/init-project.sh --doctor --stack flutter </dev/null 2>&1) || rc=$?
ck "doctor in a python instance refuses another stack (exit 1)" [ "$rc" = 1 ]
ck "that refusal names the instance's stack" grep -qE '^MISSING pack flutter: .*python' <<<"$out"
# H3: ruff and black are the python pack's gate tools, not every stack's.
D="$WORK/stubdoc"; copy_template "$D"; stub_pack "$D" tauri 1 'a Mac desktop app'
out=$(cd "$D" && bash scripts/init-project.sh --doctor --stack tauri </dev/null 2>&1 || true)
ck "app-stack doctor checks pytest (the factory's own tests)" grep -qE '^(ok +|MISSING )python3 -m pytest' <<<"$out"
ck "app-stack doctor does not demand ruff or black" no grep -qE 'ruff|black' <<<"$out"
out=$(cd "$D" && bash scripts/init-project.sh --doctor --stack python </dev/null 2>&1 || true)
ck "python doctor still checks ruff and black" grep -qF 'pytest|ruff|black' <<<"$out"

# REQ-330 (H6): the tauri floor needs cargo-audit, installed locked at the pack's version.
DT="$WORK/tauridoc"; copy_template "$DT"
out=$(cd "$DT" && PATH="$BIN" bash scripts/init-project.sh --doctor --stack tauri </dev/null 2>&1 || true)
ck "tauri doctor reports cargo-audit" grep -qE '^MISSING cargo_audit: .+' <<<"$out"
if [[ "$(uname -s)" == Darwin ]]; then ck "…with the pinned, locked install" grep -qE '^MISSING cargo_audit: cargo install cargo-audit --locked --version [0-9.]+' <<<"$out"; fi
# An instance's doctor names no stacks/ path even when the python floor tools are missing (the :27 check, exercised where
# it can fail: minimal PATH, and pip_audit/bandit made absent with the floor_stubs modules — the host python3 has both).
PS="$WORK/pystub"; floor_stubs "$PS"
out=$(cd "$WORK/inst" && PATH="$BIN" PYTHONPATH="$PS/py" STUB_PIP_AUDIT_MISSING=1 STUB_BANDIT_MISSING=1 bash scripts/init-project.sh --doctor </dev/null 2>&1 || true)
ck "instance doctor, pip-audit missing: the hash-pinned install of the instance lockfile" grep -qE '^MISSING pip_audit: pip install --require-hashes -r requirements\.txt' <<<"$out"
ck "…and the output still names no stacks/ path" no grep -q 'stacks/' <<<"$out"
ck "stacks/{python,tauri}/pack.yml: no install_* value names a stacks/ path (an instance prints them)" no grep -qE '^install_[a-z_]+:.*stacks/' stacks/python/pack.yml stacks/tauri/pack.yml

finish test_init_doctor
