#!/usr/bin/env bash
# REQ-301: config.py is the one flat reader of .specflow.yml (no PyYAML); a
# legacy .stack is a fallback; no shipped script reads .stack on its own.
# Covers: REQ-301
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CFG="$ROOT/scripts/lib/specflow/config.py"
[[ -f "$CFG" ]] || { fail "scripts/lib/specflow/config.py missing"; finish test_config; }
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
get() { python3 "$CFG" --root "$1" get "${@:2}" 2>/dev/null || true; }
is() { [ "$(get "$1" "$2" "${@:4}")" = "$3" ]; }   # is DIR KEY WANT [--default V]
mkdir -p "$W/a" "$W/b" "$W/c" "$W/d" "$W/e" "$W/f"
cat > "$W/a/.specflow.yml" <<'EOF'
# SpecFlow configuration (not pipeline state)
profile: "engineer"   # who drives
stack: python

solo: 'false'
coverage_min: 85
EOF
ck "double quotes and trailing comment stripped" is "$W/a" profile engineer
ck "single quotes stripped" is "$W/a" solo false
ck "plain value" is "$W/a" coverage_min 85
echo flutter > "$W/b/.stack"; ck ".stack used when .specflow.yml is absent" is "$W/b" stack flutter
printf 'profile: guided\n' > "$W/c/.specflow.yml"; echo tauri > "$W/c/.stack"
ck ".stack fills a missing stack key" is "$W/c" stack tauri
echo flutter > "$W/a/.stack"; ck ".specflow.yml wins over .stack" is "$W/a" stack python
ck "missing key exits non-zero" no python3 "$CFG" --root "$W/d" get stack
ck "--default applies" is "$W/d" stack none --default none
printf 'stack:\n  name: python\n' > "$W/e/.specflow.yml"
rc=0; python3 "$CFG" --root "$W/e" get stack >/dev/null 2>&1 || rc=$?; ck "nested YAML exits 2" [ "$rc" = 2 ]
python3 "$CFG" --root "$W/f" write stack=python profile=engineer
ck "write emits the six keys in order" [ "$(grep -oE '^[a-z_]+:' "$W/f/.specflow.yml" | tr -d ':' | tr '\n' ' ')" = "profile path stack solo coverage_min signing " ]
ck "write keeps arguments" is "$W/f" profile engineer
ck "write fills defaults" is "$W/f" path lanes
ck "file says configuration, not state" grep -q art-branch-as-state "$W/f/.specflow.yml"
ck "written file validates" python3 "$CFG" --root "$W/f" validate
printf 'profile: boss\nstack: go\n' > "$W/f/.specflow.yml"
rc=0; out=$(python3 "$CFG" --root "$W/f" validate 2>&1) || rc=$?
ck "validate exits 2" [ "$rc" = 2 ]; ck "validate names profile" grep -q profile <<<"$out"; ck "validate names stack" grep -q stack <<<"$out"
printf 'source_roots: [src, "lib"]\n' > "$W/p.yml"
ck "getlist splits a flow list" [ "$(python3 "$CFG" --file "$W/p.yml" getlist source_roots | tr '\n' ' ')" = "src lib " ]
while IFS= read -r f; do
  [[ "$f" == tests/governance/test_config.sh ]] || ck "$f reads .stack only as a fallback" grep -qE '\.specflow\.yml|specflow/config\.py' "$f"
done < <(grep -rlE --exclude-dir=__pycache__ '\.stack([^a-zA-Z_/-]|$)' scripts stacks .github .claude/commands tests/governance 2>/dev/null || true)
ck "quality-gates-stack.sh.template removed (packs replace it)" no test -e scripts/quality-gates-stack.sh.template
ck "run-quality-gates.sh reads the stack via config.py" grep -q lib/specflow/config.py scripts/run-quality-gates.sh
ck "/release reads the stack via config.py" grep -q lib/specflow/config.py .claude/commands/release.md
# P6 Task 3.2 (REQ-354; P6 R23): signing is none or apple; config.validate refuses anything else.
# Covers: REQ-354
for v in none apple; do
  mkdir -p "$W/sg-$v"; python3 "$CFG" --root "$W/sg-$v" write stack=tauri profile=engineer "signing=$v" >/dev/null
  ck "signing: $v validates" python3 "$CFG" --root "$W/sg-$v" validate
done
mkdir -p "$W/sg-gpg"; python3 "$CFG" --root "$W/sg-gpg" write stack=tauri profile=engineer >/dev/null
sed -i.bak 's/^signing: .*/signing: gpg/' "$W/sg-gpg/.specflow.yml" && rm -f "$W/sg-gpg/.specflow.yml.bak"
ck "signing: gpg is refused, naming the key" bash -c '! python3 "$1" --root "$2" validate 2>"$2/err" && grep -q signing "$2/err"' _ "$CFG" "$W/sg-gpg"
finish test_config
