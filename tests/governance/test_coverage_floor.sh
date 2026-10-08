#!/usr/bin/env bash
# REQ-325: coverage_min (default 80) is a per-toolchain line threshold. Python: the core gates run pytest with --cov=src
# --cov-fail-under=$MIN and always its own --cov-config (scripts/lib/specflow/coverage.sh), pytest-cov hash-pinned in
# both lockfiles; CI also reads coverage_min at the base ref (git show + config.py, never attestation.py's policy) and
# applies the higher value, and refuses a coverage_exclude entry the base does not have, so a PR can neither lower its
# own floor (P2's deferral) nor widen its exclusions; a repository coverage config (omit, exclude_lines) is never read, and
# the gate's own config excludes no lines, so an in-source '# pragma: no cover' narrows nothing. SPECFLOW_COVERAGE_MIN
# can raise the resolved floor, never lower it (the higher value governs). pytest's own configuration is isolated too
# (-c <temp ini>, pythonpath carried from a fixed allowlist, -p no:cacheprovider): no addopts or conftest.py switches it off.
# Covers: REQ-325
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CV="$ROOT/scripts/lib/specflow/coverage.sh"; CFG="$ROOT/scripts/lib/specflow/config.py"
ck "scripts/lib/specflow/coverage.sh exists" test -f "$CV"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
py() {  # py DIR full|part — a src/ package with two functions; the test calls both, or one
  mkdir -p "$1/src/m" "$1/tests"; : > "$1/src/__init__.py"; : > "$1/src/m/__init__.py"
  printf 'def a():\n    return 1\n\n\ndef b():\n    x = 2\n    y = x + 1\n    return y\n' > "$1/src/m/core.py"
  if [ "$2" = full ]; then printf 'from src.m.core import a, b\n\n\ndef test_ab():\n    assert a() == 1 and b() == 3\n' > "$1/tests/test_core.py"
  else printf 'from src.m.core import a\n\n\ndef test_a():\n    assert a() == 1\n' > "$1/tests/test_core.py"; fi
}
py "$W/full" full; py "$W/part" part
run_cov() { rc=0; out=$(cd "$1" && bash -c 'source "$1"; pytest_cov "$2"' _ "$CV" "$2" 2>&1) || rc=$?; }
run_cov "$W/full" 80; ck "a fully covered src/ passes coverage_min 80" [ "$rc" = 0 ]
run_cov "$W/part" 80; ck "src/ at 50% fails coverage_min 80, saying so" bash -c '[ "$1" != 0 ] && grep -q "80" <<<"$2"' _ "$rc" "$out"
run_cov "$W/part" 40; ck "…and passes coverage_min 40" [ "$rc" = 0 ]
ck "a coverage run leaves no .coverage file in the tree" [ ! -e "$W/full/.coverage" -a ! -e "$W/part/.coverage" ]
printf '[run]\nomit = src/m/core.py\n[report]\nexclude_lines =\n    .*\n' > "$W/part/.coveragerc"
printf '[tool.coverage.report]\nexclude_lines = [".*"]\n' > "$W/part/pyproject.toml"; cp "$W/part/.coveragerc" "$W/part/setup.cfg"
run_cov "$W/part" 80
ck "a repository .coveragerc, setup.cfg or pyproject.toml omit/exclude_lines is ignored (own --cov-config): still fails 80" [ "$rc" != 0 ]
rm -f "$W/part/.coveragerc" "$W/part/setup.cfg" "$W/part/pyproject.toml"
py "$W/prag" part; printf 'def a():\n    return 1\n\n\ndef b():  # pragma: no cover\n    x = 2\n    y = x + 1\n    return y\n' > "$W/prag/src/m/core.py"
run_cov "$W/prag" 100
ck "an in-source '# pragma: no cover' does not narrow what the floor measures (the uncalled function still counts)" [ "$rc" != 0 ]
# PR #42 fourth verifier run, doc medium 2 (REQ-325): pytest's own configuration is isolated — pytest runs with -c <a temp
# ini> carrying only pythonpath (a fixed allowlist, never addopts) and -p no:cacheprovider, so no pytest.ini, tox.ini,
# setup.cfg or pyproject.toml addopts, and no conftest.py hook, can switch measurement (and --cov-fail-under) off.
for cf in pyproject.toml pytest.ini setup.cfg tox.ini; do
  py "$W/off-$cf" part
  case "$cf" in
    pyproject.toml) printf '[tool.pytest.ini_options]\naddopts = "--no-cov"\n' ;;
    setup.cfg)      printf '[tool:pytest]\naddopts = --no-cov\n' ;;
    *)              printf '[pytest]\naddopts = --no-cov\n' ;;
  esac > "$W/off-$cf/$cf"
  run_cov "$W/off-$cf" 80
  ck "a $cf 'addopts = --no-cov' does not switch the floor off: 50% still fails coverage_min 80" \
    bash -c '[ "$1" != 0 ] && grep -q "80" <<<"$2"' _ "$rc" "$out"
done
py "$W/off-conftest" part
printf 'def pytest_load_initial_conftests(early_config, parser, args):\n    args.append("--no-cov")\n\n\ndef pytest_configure(config):\n    config.option.no_cov = True\n' > "$W/off-conftest/conftest.py"
cp "$W/off-conftest/conftest.py" "$W/off-conftest/tests/conftest.py"
run_cov "$W/off-conftest" 80
ck "a conftest.py that sets --no-cov (initial-conftest hook, config.option) does not switch the floor off: still fails 80" \
  bash -c '[ "$1" != 0 ] && grep -q "80" <<<"$2"' _ "$rc" "$out"
py "$W/ppath" full; mkdir -p "$W/ppath/lib"; printf 'def one():\n    return 1\n' > "$W/ppath/lib/helper.py"
printf 'from helper import one\nfrom src.m.core import a, b\n\n\ndef test_ab():\n    assert a() == one() and b() == 3\n' > "$W/ppath/tests/test_core.py"
printf '[tool.pytest.ini_options]\npythonpath = ["lib"]\naddopts = "--no-cov"\n' > "$W/ppath/pyproject.toml"
run_cov "$W/ppath" 80
ck "pyproject.toml's pythonpath (the allowlisted key) is carried into the gate's own ini: a test importing from it passes 80" [ "$rc" = 0 ]
ck "no .pytest_cache is written (-p no:cacheprovider)" [ ! -e "$W/ppath/.pytest_cache" -a ! -e "$W/part/.pytest_cache" ]
ck "coverage.sh runs pytest with its own -c ini, --rootdir and -p no:cacheprovider" \
  bash -c 'grep -qF -- "-c \"\$pyini\"" "$1" && grep -qF -- "--rootdir" "$1" && grep -qF -- "-p no:cacheprovider" "$1"' _ "$CV"
G="$W/g"; mkdir -p "$G"
(cd "$G" && git init -q -b main && printf 'coverage_min: 90\n' > .specflow.yml && git add -A && git commit -qm base \
   && git checkout -qb pr && printf 'coverage_min: 50\n' > .specflow.yml && git commit -qam lower)
res() { (cd "$G" && env -u SPECFLOW_COVERAGE_MIN SPECFLOW_BASE_REF="$1" bash -c 'source "$1"; coverage_min_resolve' _ "$CV" 2>&1); }
ck "CI: when the PR lowers coverage_min, the base's value governs (90, not 50)" grep -q '^90 ' <<<"$(res main)"
(cd "$G" && printf 'coverage_min: 95\n' > .specflow.yml && git commit -qam raise)
ck "a PR may raise its own floor (95)" grep -q '^95 ' <<<"$(res main)"
ck "locally (no SPECFLOW_BASE_REF) the working tree's value applies" grep -q '^95 ' <<<"$(res '')"
res_env() { (cd "$G" && SPECFLOW_COVERAGE_MIN="$1" SPECFLOW_BASE_REF=main bash -c 'source "$1"; coverage_min_resolve' _ "$CV" 2>&1); }
ck "SPECFLOW_COVERAGE_MIN below the resolved floor never lowers it (the higher value, 95, governs)" grep -q '^95 ' <<<"$(res_env 50)"
ck "…and above it raises the floor (99)" grep -q '^99 ' <<<"$(res_env 99)"
ck "coverage.sh reads the base value itself (git show + config.py), never through attestation.py's policy" \
  bash -c 'grep -qF "git show" "$1" && ! grep -qF "attestation.py" "$1"' _ "$CV"
ck "attestation.py policy is unchanged: solo, profile and path only (the verifier's classifier calls it)" \
  no grep -qF 'coverage_min' "$ROOT/scripts/lib/specflow/attestation.py"
mkdir -p "$G/.specflow"; (cd "$G" && git checkout -q main && printf 'coverage_exclude: []\n' > .specflow/pack.yml && git add -A \
   && git commit -qm pack && git checkout -q pr && git merge -q main -m m && printf 'coverage_exclude: [src/m/core.py]\n' > .specflow/pack.yml \
   && git commit -qam widen)
rc=0; out=$(cd "$G" && SPECFLOW_BASE_REF=main bash -c 'source "$1"; pack_coverage_exclude' _ "$CV" 2>&1) || rc=$?
ck "a coverage_exclude entry the base does not have fails, naming it" bash -c '[ "$1" != 0 ] && grep -q "coverage_exclude gains src/m/core.py" <<<"$2"' _ "$rc" "$out"
Q="$ROOT/scripts/run-quality-gates.sh"
ck "the gates source coverage.sh, export SPECFLOW_COVERAGE_MIN and run pytest through pytest_cov" \
  bash -c 'grep -q "lib/specflow/coverage.sh" "$1" && grep -q "export SPECFLOW_COVERAGE_MIN" "$1" && grep -q "pytest_cov" "$1"' _ "$Q"
ck "ci.yml passes the base ref to the gates" grep -qF 'SPECFLOW_BASE_REF' "$ROOT/.github/workflows/ci.yml"
ck "coverage.sh reads coverage_exclude from the pack (never a literal list)" grep -qF 'getlist coverage_exclude' "$CV"
if ! instance; then
  ck "the python pack's coverage_exclude is []" [ -z "$(python3 "$CFG" --file "$ROOT/stacks/python/pack.yml" getlist coverage_exclude)" ]
  for f in scripts/requirements.in stacks/python/skeleton/requirements.in; do ck "$f lists pytest-cov as a range" grep -qE '^pytest-cov[<>=!~ ]' "$ROOT/$f"; done
  for f in scripts/requirements.txt stacks/python/skeleton/requirements.txt; do
    ck "$f pins pytest-cov with a hash" python3 - "$ROOT/$f" <<'PY'
import re, sys
t = open(sys.argv[1]).read().replace("\\\n", " ")
assert re.search(r"^pytest-cov==[\w.]+ .*--hash=sha256:[0-9a-f]{64}", t, re.M)
PY
  done
  ck "pack.yml pytest_cov_version equals the skeleton lockfile's pin" \
    bash -c 'v=$(python3 "$1" --file "$2" get pytest_cov_version); grep -q "^pytest-cov==$v " "$3"' _ "$CFG" "$ROOT/stacks/python/pack.yml" "$ROOT/stacks/python/skeleton/requirements.txt"
fi
# REQ-325, app stacks: tauri runs vitest with --coverage.thresholds.lines=$MIN and cargo llvm-cov --fail-under-lines $MIN;
# flutter runs flutter test --coverage then the pack's lcov-threshold.sh; every exclusion list equals pack.yml's
# coverage_exclude. Stub toolchains record argv (no Rust, Node or Flutter needed).
if ! instance; then
  T="$ROOT/stacks/tauri"; F="$ROOT/stacks/flutter"
  ck "tauri pins cargo-llvm-cov and lists it and llvm-tools as prerequisites" \
    bash -c 'grep -q "^cargo_llvm_cov_version: " "$1" && grep -qE "^prereqs: .*cargo_llvm_cov" "$1" && grep -qE "^prereqs: .*llvm_tools" "$1" \
      && grep -q "^install_macos_cargo_llvm_cov: cargo install cargo-llvm-cov --locked --version" "$1"' _ "$T/pack.yml"
  ck "the tauri action installs cargo-llvm-cov at the pack's version, and llvm-tools" \
    bash -c 'v=$(sed -n "s/^cargo_llvm_cov_version: //p" "$2"); grep -qF "default: \"$v\"" "$1" && grep -qF "cargo install cargo-llvm-cov --locked" "$1" && grep -qF "llvm-tools" "$1"' _ "$T/action.yml" "$T/pack.yml"
  ck "the tauri overlay's rust-toolchain.toml asks for llvm-tools" grep -qF 'llvm-tools' "$T/overlay/rust-toolchain.toml"
  ck "vitest.config.ts excludes exactly pack.yml's TypeScript coverage_exclude entries (plus the tests)" \
    python3 - "$T/overlay/vitest.config.ts" "$T/pack.yml" "$CFG" <<'PY'
import re, subprocess, sys
cfg = open(sys.argv[1]).read()
got = {x.strip().strip('"') for x in re.search(r"exclude:\s*\[([^\]]*)\]", cfg).group(1).split(",") if x.strip()}
pack = subprocess.run([sys.executable, sys.argv[3], "--file", sys.argv[2], "getlist", "coverage_exclude"],
                      capture_output=True, text=True, check=True).stdout.split()
assert got == {p for p in pack if p.endswith(".ts")} | {"src/**/*.test.ts"}, got
PY
  stub() {  # stub DIR TOOL [SNIPPET] — records argv to DIR/TOOL.argv, runs SNIPPET, exits 0
    cat > "$1/bin/$2" <<EOF
#!/usr/bin/env bash
{ printf '%s\n' "\$@"; echo ---; } >> "$1/$2.argv"
${3:-:}
exit 0
EOF
    chmod +x "$1/bin/$2"; }
  inst() {  # inst DIR PACK — an instance-shaped directory with the pack's pack.yml and the coverage helpers
    mkdir -p "$1/bin" "$1/inst/.specflow" "$1/inst/scripts/lib/specflow" "$1/inst/src-tauri"
    cp "$2" "$1/inst/.specflow/pack.yml"; cp "$CFG" "$CV" "$1/inst/scripts/lib/specflow/"; }
  S="$W/tauri"; inst "$S" "$T/pack.yml"; for t in npm npx cargo; do stub "$S" "$t"; done
  rc=0; (cd "$S/inst" && PATH="$S/bin:$PATH" SPECFLOW_COVERAGE_MIN=80 bash "$T/gates.sh") >/dev/null 2>&1 || rc=$?
  ck "tauri gates.sh passes against stub toolchains" [ "$rc" = 0 ]
  ck "tauri: vitest runs with --coverage and --coverage.thresholds.lines=80" \
    bash -c 'tr "\n" " " < "$1" | grep -qF "vitest run --coverage --coverage.thresholds.lines=80"' _ "$S/npx.argv"
  ck "tauri: cargo llvm-cov --locked --fail-under-lines 80 replaces cargo test" \
    bash -c 'tr "\n" " " < "$1" | grep -qF "llvm-cov --locked --fail-under-lines 80" && ! grep -qx test "$1"' _ "$S/cargo.argv"
  ck "tauri: the llvm-cov ignore regex comes from pack.yml (main.rs and lib.rs out, commands.rs in)" python3 - "$S/cargo.argv" <<'PY'
import re, sys
a = open(sys.argv[1]).read().split("\n"); rx = re.compile(a[a.index("--ignore-filename-regex") + 1])
assert rx.search("/x/src-tauri/src/main.rs") and rx.search("/x/src-tauri/src/lib.rs"), rx.pattern
assert not rx.search("/x/src-tauri/src/commands.rs"), rx.pattern
PY
  S3="$W/tauri-nors"; sed 's|^coverage_exclude: .*|coverage_exclude: [src/main.ts]|' "$T/pack.yml" > "$W/tauri-nors.yml"
  inst "$S3" "$W/tauri-nors.yml"; for t in npm npx cargo; do stub "$S3" "$t"; done
  rc=0; (cd "$S3/inst" && PATH="$S3/bin:$PATH" SPECFLOW_COVERAGE_MIN=80 bash "$T/gates.sh") >/dev/null 2>&1 || rc=$?
  ck "tauri: with no .rs entry in coverage_exclude, llvm-cov gets no --ignore-filename-regex (an empty one matches every path)" \
    bash -c '[ "$1" = 0 ] && grep -qF -- "--fail-under-lines" "$2" && ! grep -qF -- "--ignore-filename-regex" "$2"' _ "$rc" "$S3/cargo.argv"
  LC="$F/lcov-threshold.sh"
  lc() { rc=0; out=$(bash "$LC" "$@" 2>&1) || rc=$?; }
  printf 'SF:lib/app.dart\nDA:1,1\nDA:2,1\nDA:3,1\nDA:4,0\nend_of_record\nSF:lib/main.dart\nDA:1,0\nDA:2,0\nend_of_record\n' > "$W/lcov.info"
  lc "$W/lcov.info" 80; ck "lcov-threshold.sh: 3 of 6 lines is below 80" [ "$rc" = 1 ]
  lc "$W/lcov.info" 70 --exclude lib/main.dart; ck "…excluding lib/main.dart, 3 of 4 lines (75%) clears 70" [ "$rc" = 0 ]
  lc "$W/lcov.info" 80 --exclude lib/main.dart; ck "…and misses 80, printing 75" bash -c '[ "$1" = 1 ] && grep -q "75" <<<"$2"' _ "$rc" "$out"
  lc "$W/none.info" 80; ck "a missing lcov file is an error (exit 2), never a pass" [ "$rc" = 2 ]
  : > "$W/empty.info"; lc "$W/empty.info" 80; ck "an lcov file with no records is an error (exit 2)" [ "$rc" = 2 ]
  S2="$W/flutter"; inst "$S2" "$F/pack.yml"; cp "$LC" "$S2/inst/scripts/lcov-threshold.sh"; stub "$S2" dart
  stub "$S2" flutter 'if [ "$*" = "test --coverage" ]; then mkdir -p coverage; printf "SF:lib/app.dart\nDA:1,1\nend_of_record\nSF:lib/main.dart\nDA:1,0\nend_of_record\n" > coverage/lcov.info; fi'
  rc=0; (cd "$S2/inst" && PATH="$S2/bin:$PATH" SPECFLOW_COVERAGE_MIN=80 bash "$F/gates.sh") >/dev/null 2>&1 || rc=$?
  ck "flutter gates.sh runs flutter test --coverage and excludes pack.yml's lib/main.dart (1 of 1 line: passes 80)" \
    bash -c '[ "$1" = 0 ] && grep -qx -e --coverage "$2"' _ "$rc" "$S2/flutter.argv"
  ck "init copies the flutter pack's lcov-threshold.sh into scripts/" grep -qF 'lcov-threshold.sh' "$ROOT/scripts/init-project.sh"
fi
finish test_coverage_floor
