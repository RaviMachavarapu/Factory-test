#!/usr/bin/env bash
# REQ-303: every pack has every required file. REQ-304 (python in P1a): the
# skeleton passes lint, format, tests with no hand edits. REQ-305: release.sh
# honours VERSION/DIST_DIR and writes manifest.json. Template source only.
# Covers: REQ-303, REQ-304, REQ-305
# Covers: REQ-325, REQ-332, REQ-388
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — init removed stacks/"; exit 0; }
CFG="$ROOT/scripts/lib/specflow/config.py"
val() { python3 "$CFG" --file "$1" "${@:2}" 2>/dev/null || true; }
shopt -s nullglob
ck "stacks/python present" test -d stacks/python
for d in stacks/*/; do
  s=$(basename "$d"); req="init.sh gates.sh security.sh release.sh action.yml pack.yml"
  if [[ $s == python ]]; then req="$req Dockerfile deploy.sh"; else req="$req store-checklist.md"; fi
  for f in $req; do ck "$s: $f present" test -f "$d$f"; done
  for f in "$d"*.sh; do ck "$f executable" test -x "$f"; ck "$f parses" bash -n "$f"; done
  for k in stack source_roots test_globs coverage_exclude guided_choice guided_label guided_rationale testing prereqs ci_runs_on; do
    ck "$s: pack.yml declares $k" python3 "$CFG" --file "${d}pack.yml" get "$k"
  done
  ck "$s: pack.yml stack matches the directory" [ "$(val "${d}pack.yml" get stack)" = "$s" ]
  # Fix wave 1 (REQ-384; P6 R15, R35): release-build.yml sets up the governing pack's python_version for every stack's
  # reproducible subset and refuses an empty one, so every pack declares it (Build 2's key; Build 4 pins python's patch).
  # Covers: REQ-384
  ck "$s: pack.yml declares python_version (release-build.yml's Python for the reproducible subset)" \
    bash -c '[[ $(python3 "$1" --file "$2" get python_version 2>/dev/null) =~ ^3\.[0-9]+(\.[0-9]+)?$ ]]' _ "$CFG" "${d}pack.yml"
  for t in $(val "${d}pack.yml" getlist prereqs); do
    for k in check install_macos install_linux; do ck "$s: ${k}_$t" python3 "$CFG" --file "${d}pack.yml" get "${k}_$t"; done
  done
  ck "$s: composite action" grep -qE '^[[:space:]]*using:[[:space:]]*"?composite"?' "${d}action.yml"
done
P="$ROOT/stacks/python"
for tk in ruff:ruff black:black pytest:pytest pytest-cov:pytest_cov build:build setuptools:setuptools wheel:wheel pip-audit:pip_audit bandit:bandit; do
  t=${tk%%:*}; k=${tk##*:}
  pin=$(grep -iE "^$t==" "$P/skeleton/requirements.txt" 2>/dev/null | head -1 | sed -E 's/^[^=]+==([^ ;\\]+).*/\1/' || true)
  ck "$t pin '$pin' equals pack.yml ${k}_version" [ -n "$pin" -a "$(val "$P/pack.yml" get "${k}_version")" = "$pin" ]
done
ck "lockfile is hash-pinned" grep -q -- '--hash=sha256:' "$P/skeleton/requirements.txt"
ck "lockfile made by uv pip compile --universal" grep -qE 'uv pip compile .*--universal' "$P/skeleton/requirements.txt"
ck "runtime lock: skeleton/requirements-runtime.in and its lock, made by uv pip compile --generate-hashes" \
  bash -c 'test -f "$1/skeleton/requirements-runtime.in" && grep -qE "uv pip compile .*--generate-hashes" "$1/skeleton/requirements-runtime.txt"' _ "$P"
ck "sourcing deploy.sh with no arguments returns 0" env DRY_RUN=1 bash -c "source '$P/deploy.sh'"
fns=$(DRY_RUN=1 bash -c "source '$P/deploy.sh' && declare -F" 2>/dev/null || true)
for fn in migrate deploy smoke rollback; do ck "deploy.sh defines $fn" grep -q " $fn\$" <<<"$fns"; done
ck "Dockerfile FROM python:" grep -q '^FROM python:' "$P/Dockerfile"
ck "Dockerfile has the __PKG__ token" grep -q __PKG__ "$P/Dockerfile"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT; cd "$W"
ck "scaffold runs" env SPECFLOW_NAME="Acme Tools" SPECFLOW_PKG=acme_tools bash "$P/init.sh" scaffold
for f in pyproject.toml requirements.in requirements.txt src/acme_tools/__main__.py tests/acme_tools/test_acme_tools_smoke.py; do ck "skeleton has $f" test -f "$f"; done
ck "tokens substituted" no grep -rqE '__PKG__|__NAME__' .
ck "skeleton passes ruff" python3 -m ruff check src tests
ck "skeleton passes black" python3 -m black --check -q src tests
ck "skeleton test passes" python3 -m pytest -q tests
ck "SPECFLOW_SMOKE=1 start-up exits 0" env SPECFLOW_SMOKE=1 python3 -m src.acme_tools
# W-10: a sibling package sharing the name prefix must not be swept into the
# wheel by a setuptools `include` glob.
mkdir -p src/acme_tools_extra && echo '' > src/acme_tools_extra/__init__.py
# P6 Task 2.1 (P6 R18, R35): set-up only, no check of its own — the scaffold becomes a committed repository and
# SOURCE_DATE_EPOCH is set (a dry run: no notes) before every hook run, which today's python hook ignores and Build 4's
# reads, so this block needs no edit when Build 4 lands. The checks below still exercise the VERSION/DIST_DIR contract
# as specified (REQ-305, the header's Covers line); the P6 extension of that contract (the committed tree, the epoch) is
# asserted by Build 4's test_release_python.sh, not here (fix wave 1: this block cited REQ-305 for behaviour it does not
# assert).
export SOURCE_DATE_EPOCH=1791158400
cm() { git add -A && git commit -qm "$1"; }
git init -q -b main . && printf 'dist\nd2\n__pycache__\n.pytest_cache\n.ruff_cache\n' > .git/info/exclude && cm "scaffold, with the W-10 sibling"
ck "release.sh runs (build tools: pip install -r scripts/requirements.txt)" env VERSION=0.1.0 DIST_DIR="$W/dist" bash "$P/release.sh"
ck "manifest verifies: sdist + wheel, sha256, size" python3 - "$W/dist" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
names = [e["filename"] for e in m["artifacts"]]
assert m["version"] == "0.1.0" and any(n.endswith(".whl") for n in names) and any(n.endswith(".tar.gz") for n in names), m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
ck "wheel excludes a sibling package sharing the name prefix (W-10)" python3 - "$W/dist" <<'PY'
import glob, sys, zipfile
d = sys.argv[1]
whl = glob.glob(d + "/*.whl")[0]
names = zipfile.ZipFile(whl).namelist()
assert not any(n.startswith("acme_tools_extra/") for n in names), names
PY
ck "release.sh refuses a VERSION unlike pyproject.toml" no env VERSION=9.9.9 DIST_DIR="$W/d2" bash "$P/release.sh"

# A package name at scripts/init-project.sh's 40-char cap (REQ-304: --name up
# to 64 chars must not force black to wrap the skeleton's import line).
W2="$(mktemp -d)"; OLD_PWD="$(pwd)"; cd "$W2"
CAPPED_PKG="$(python3 -c 'print(("alongprojectnameforblackwrap" * 3)[:40])')"
ck "capped-length scaffold runs" env SPECFLOW_NAME="Long Name" SPECFLOW_PKG="$CAPPED_PKG" bash "$P/init.sh" scaffold
ck "capped-length skeleton passes ruff" python3 -m ruff check src tests
ck "capped-length skeleton passes black" python3 -m black --check -q src tests
ck "capped-length skeleton test passes" python3 -m pytest -q tests
cd "$OLD_PWD"
rm -rf "$W2"
sed -i.bak 's/version = "0.1.0"/version = "0.2.0"/' pyproject.toml && rm -f pyproject.toml.bak && cm 0.2.0
ck "release.sh reused on the same DIST_DIR" env VERSION=0.2.0 DIST_DIR="$W/dist" bash "$P/release.sh"
ck "second release's manifest holds only the new version's artifacts" python3 - "$W/dist" <<'PY'
import json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
names = [e["filename"] for e in m["artifacts"]]
assert m["version"] == "0.2.0", m
assert all("0.1.0" not in n for n in names), names
assert any(n.endswith(".whl") for n in names) and any(n.endswith(".tar.gz") for n in names), names
PY

# REQ-305 fix: python's build tool canonicalises a pre-release version per
# PEP 440 (e.g. "1.0.0-rc.1" -> "1.0.0rc1" in the artifact filenames), so
# release.sh must not filter built artifacts by matching the raw VERSION
# string against filenames — that drops every artifact and silently writes
# a "0 artifact(s)" manifest that still passes the release gate.
W3="$(mktemp -d)"; cd "$W3"
ck "non-canonical-version scaffold runs" env SPECFLOW_NAME="Acme Tools" SPECFLOW_PKG=acme_tools bash "$P/init.sh" scaffold
git init -q -b main . && printf 'dist\n__pycache__\n.pytest_cache\n.ruff_cache\n' > .git/info/exclude && cm "scaffold"
sed -i.bak 's/version = "0.1.0"/version = "1.0.0-rc.1"/' pyproject.toml && rm -f pyproject.toml.bak && cm rc
ck "release.sh runs with a non-canonical (PEP 440 pre-release) VERSION" env VERSION=1.0.0-rc.1 DIST_DIR="$W3/dist" bash "$P/release.sh"
ck "manifest holds exactly one wheel and one sdist for the non-canonical version" python3 - "$W3/dist" <<'PY'
import json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
names = [e["filename"] for e in m["artifacts"]]
wheels = [n for n in names if n.endswith(".whl")]
sdists = [n for n in names if n.endswith(".tar.gz")]
assert m["version"] == "1.0.0-rc.1", m
assert len(wheels) == 1 and len(sdists) == 1, names
PY
cd "$OLD_PWD"
rm -rf "$W3"
rm -rf "$W/.git"; unset SOURCE_DATE_EPOCH

# --- package rules are pack-owned (H3): init.sh package prints the package or refuses with exit 2 ---
rc_of() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
mkdir -p "$W/pk"
pkg() { (cd "$W/pk" && env SPECFLOW_NAME="$2" SPECFLOW_PKG="$3" bash "$1/init.sh" package 2>/dev/null); }
ck "python: package keeps a valid candidate" [ "$(pkg "$P" 'Acme Tools' acme_tools)" = acme_tools ]
ck "python: package caps the length at 40" [ "$(pkg "$P" Long "$(printf 'a%.0s' $(seq 1 50))" | wc -c | tr -d ' ')" = 41 ]
for n in calendar email class pytest src tests conftest; do ck "python: package '$n' refused (exit 2)" [ "$(rc_of pkg "$P" X "$n")" = 2 ]; done
mkdir -p "$W/pk/src/acme_tools"
ck "python: a package clashing with src/<pkg> is refused (exit 2)" [ "$(rc_of pkg "$P" X acme_tools)" = 2 ]
rm -rf "$W/pk/src"
mkdir -p "$W/pk/tests/acme_tools"
ck "python: a package clashing with tests/<pkg> is refused (exit 2, W-4)" [ "$(rc_of pkg "$P" X acme_tools)" = 2 ]
rm -rf "$W/pk/tests"
ck "python: preflight needs nothing (exit 0)" bash -c "cd '$W/pk' && SPECFLOW_NAME=X SPECFLOW_PKG=x bash '$P/init.sh' preflight"
ck "python: an unknown subcommand exits 2" [ "$(rc_of bash -c "cd '$W/pk' && bash '$P/init.sh' frobnicate")" = 2 ]

# --- tauri pack (REQ-303/304/305): static contract; no toolchain, no network ---
T="$ROOT/stacks/tauri"; TO="$T/overlay"; tv() { val "$T/pack.yml" get "$1"; }
ck "stacks/tauri present" test -d "$T"
for k in create_tauri_app_version tauri_cli_version rust_version node_version vitest_version vitest_coverage_version macos_host macos_min macos_archs lockfile; do
  ck "tauri: pack.yml pins $k" [ -n "$(tv $k)" ]
done
for k in create_tauri_app_integrity create_tauri_app_darwin_arm64_integrity; do
  ck "tauri: pack.yml pins $k by sha512 (dfe-4)" grep -qE '^sha512-[A-Za-z0-9+/]{86}==$' <<<"$(tv $k)"
done
ck "tauri: guided choice 1, a Mac desktop app" [ "$(tv guided_choice):$(tv guided_label)" = "1:a Mac desktop app" ]
ck "tauri: CI runner is macos-15" [ "$(tv ci_runs_on)" = macos-15 ]
ck "tauri: coverage_exclude per REQ-325" [ "$(val "$T/pack.yml" getlist coverage_exclude | tr '\n' ' ')" = "src-tauri/src/main.rs src-tauri/src/lib.rs src/main.ts " ]
ck "tauri: rust-toolchain.toml pins rust_version" grep -qE "^channel *= *\"$(tv rust_version)\"" "$TO/rust-toolchain.toml"
ck "tauri: package.json pins the CLI, vitest and coverage exactly" python3 - "$TO/package.json" "$(tv tauri_cli_version)" "$(tv vitest_version)" "$(tv vitest_coverage_version)" <<'PY'
import json, sys
dev = json.load(open(sys.argv[1]))["devDependencies"]
want = {"@tauri-apps/cli": sys.argv[2], "vitest": sys.argv[3], "@vitest/coverage-v8": sys.argv[4]}
assert all(dev.get(k) == v for k, v in want.items()), (dev, want)
PY
for f in vitest.config.ts src/lib/greet.ts src/lib/greet.test.ts src-tauri/src/commands.rs src-tauri/src/lib.rs src-tauri/audit.toml osv-scanner.toml; do
  ck "tauri overlay has $f" test -f "$TO/$f"
done
ck "tauri: commands.rs carries a #[cfg(test)] test" grep -q '#\[cfg(test)\]' "$TO/src-tauri/src/commands.rs"
ck "tauri: lib.rs wires commands and honours SPECFLOW_SMOKE" bash -c "grep -q 'mod commands' '$TO/src-tauri/src/lib.rs' && grep -q SPECFLOW_SMOKE '$TO/src-tauri/src/lib.rs'"
ck "tauri: vitest coverage excludes src/main.ts" grep -q 'src/main.ts' "$TO/vitest.config.ts"
ck "tauri: init.sh reads the generator pins from pack.yml and never runs npx" bash -c "grep -q create_tauri_app_version '$T/init.sh' && grep -q create_tauri_app_integrity '$T/init.sh' && grep -q -- '--template vanilla-ts' '$T/init.sh' && ! grep -qE 'create-tauri-app@[0-9]' '$T/init.sh' && ! grep -q npx '$T/init.sh'"
for w in 'npm ci' 'vitest run' 'cargo llvm-cov' src-tauri; do ck "tauri: gates.sh runs $w" grep -qF -- "$w" "$T/gates.sh"; done
for w in --frozen CI=true CARGO_TARGET_DIR; do ck "tauri: release.sh uses $w" grep -qF -- "$w" "$T/release.sh"; done
ck "tauri: release.sh never uses --locked alone (cargo could fetch)" no grep -qE -- '--locked' "$T/release.sh"
ck "tauri: action's rust-cache is switchable with configurable workspaces" bash -c "grep -q 'rust_cache' '$T/action.yml' && grep -q 'cargo_workspaces' '$T/action.yml'"
ck "tauri: action installs the pinned node and rust" bash -c "grep -q actions/setup-node '$T/action.yml' && grep -qF '$(tv node_version)' '$T/action.yml' && grep -q 'rustup toolchain install' '$T/action.yml' && grep -qF '$(tv rust_version)' '$T/action.yml'"
for w in 'Apple Developer Program' APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD notarytool stapler Gatekeeper 'App Store' 'Developer ID' .dmg; do
  ck "tauri: store-checklist names $w" grep -qF -- "$w" "$T/store-checklist.md"
done
for k in $(val "$T/pack.yml" getlist prereqs); do ck "tauri: install_linux_$k is honest (macOS only)" grep -qi macos <<<"$(tv "install_linux_$k")"; done
ck "tauri: Calendar is a valid package" [ "$(pkg "$T" Calendar calendar)" = calendar ]
for n in match tauri std serde_json; do ck "tauri: package '$n' refused (exit 2)" [ "$(rc_of pkg "$T" X "$n")" = 2 ]; done
for n in log time url; do ck "tauri: package '$n' (a locked crate) refused (exit 2)" [ "$(rc_of pkg "$T" X "$n")" = 2 ]; done
# release.sh contract without a toolchain: a fake npm stands in for `npm run tauri -- build`.
R="$W/rel-tauri"; mkdir -p "$R/bin" "$R/app/node_modules" "$R/app/src-tauri/target/release/bundle/dmg"
printf '{"version": "0.1.0"}\n' > "$R/app/src-tauri/tauri.conf.json"
echo stale > "$R/app/src-tauri/target/release/bundle/dmg/old_0.0.9_aarch64.dmg"
cat > "$R/bin/npm" <<'FAKE'
#!/usr/bin/env bash
touch "$FAKE_MARK"; printf '%s\n' "$@" > "$FAKE_ARGV"; echo "${CI:-unset}" > "$FAKE_CI"
d="${CARGO_TARGET_DIR:-src-tauri/target}/release/bundle/dmg"; mkdir -p "$d"
for n in $FAKE_DMGS; do head -c 2048 /dev/urandom > "$d/$n"; done
FAKE
chmod +x "$R/bin/npm"
trel() { (cd "$R/app" && env -u CI -u CARGO_TARGET_DIR RELEASE_PARTS=bundle PATH="$R/bin:$PATH" FAKE_MARK="$R/mark" FAKE_ARGV="$R/argv" FAKE_CI="$R/ci" "$@" bash "$T/release.sh"); }
ck "tauri release: a VERSION unlike tauri.conf.json is refused" [ "$(rc_of trel VERSION=9.9.9 DIST_DIR="$R/d0" FAKE_DMGS=x.dmg)" != 0 ]
ck "tauri release: the refusal comes before building" no test -e "$R/mark"
ck "tauri release: one dmg built" trel VERSION=0.1.0 DIST_DIR="$R/d1" FAKE_DMGS=fix_0.1.0_aarch64.dmg
ck "tauri release: manifest lists exactly the new dmg, verified" python3 - "$R/d1" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
assert m["version"] == "0.1.0" and [e["filename"] for e in m["artifacts"]] == ["fix_0.1.0_aarch64.dmg"], m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
ck "tauri release: a stale dmg is cleared before building" no test -e "$R/app/src-tauri/target/release/bundle/dmg/old_0.0.9_aarch64.dmg"
ck "tauri release: the build runs with CI=true (no Finder layout step, no Automation prompt)" [ "$(cat "$R/ci" 2>/dev/null)" = true ]
ck "tauri release: cargo runs --frozen (no network in a release hook)" grep -qx -- --frozen "$R/argv"
ck "tauri release: dmg bundles only" grep -qx dmg "$R/argv"
ck "tauri release: two dmgs are refused" [ "$(rc_of trel VERSION=0.1.0 DIST_DIR="$R/d2" FAKE_DMGS='a.dmg b.dmg')" != 0 ]
ck "tauri release: honours CARGO_TARGET_DIR" trel VERSION=0.1.0 DIST_DIR="$R/d4" CARGO_TARGET_DIR="$R/tgt" FAKE_DMGS=ct_0.1.0_aarch64.dmg
ck "tauri release: the CARGO_TARGET_DIR dmg is the one shipped" test -f "$R/d4/ct_0.1.0_aarch64.dmg"
rm -rf "$R/app/node_modules"
ck "tauri release: missing node_modules is refused" [ "$(rc_of trel VERSION=0.1.0 DIST_DIR="$R/d3" FAKE_DMGS=fix.dmg)" != 0 ]
# init.sh preflight/scaffold without a toolchain: fake npm and node stand in for the registry and the generator.
# (Guarded: under set -e the harness setup would abort the whole test before the pack exists.)
if [[ ! -f "$T/init.sh" ]]; then fail "tauri: init.sh missing — scaffold harness not run"; else
S="$W/scaf-tauri"; mkdir -p "$S/bin" "$S/tgz" "$S/root/scripts/lib/specflow" "$S/root/stacks"
cp "$ROOT/scripts/lib/specflow/config.py" "$S/root/scripts/lib/specflow/"; cp -R "$T" "$S/root/stacks/tauri"; ST="$S/root/stacks/tauri"
CV=$(tv create_tauri_app_version)
for n in create-tauri-app create-tauri-app-darwin-arm64; do
  mkdir -p "$S/src/$n/package"; printf '{"name": "%s", "version": "%s"}\n' "$n" "$CV" > "$S/src/$n/package/package.json"
  tar -czf "$S/tgz/$n-$CV.tgz" -C "$S/src/$n" package
done
sri() { python3 -c 'import base64, hashlib, sys; print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1], "rb").read()).digest()).decode())' "$1"; }
setpin() { python3 - "$ST/pack.yml" "$1" "$2" <<'PY'
import re, sys
p, k, v = sys.argv[1:4]; t = open(p).read()
t, n = re.subn(rf"(?m)^{k}:.*$", f"{k}: {v}", t); assert n == 1, k
open(p, "w").write(t)
PY
}
cat > "$S/bin/npm" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == pack ]] || exit 0
dest=""; while [[ $# -gt 0 ]]; do [[ "$1" == --pack-destination ]] && dest="$2"; shift; done
cp "$FAKE_TGZ"/*.tgz "$dest/"
FAKE
cat > "$S/bin/node" <<'FAKE'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && { echo v24.8.0; exit 0; }
shift; printf '%s\n' "$@" > "$FAKE_ARGS"; p="$1"
mkdir -p "$p/src" "$p/src-tauri/src" "$p/src-tauri/icons"
printf '{"name": "%s", "version": "0.1.0"}\n' "$p" > "$p/package.json"
echo 'generated main' > "$p/src/main.ts"; echo 'generated lib' > "$p/src-tauri/src/lib.rs"
printf '{"version": "0.1.0", "identifier": "com.example.%s"}\n' "$p" > "$p/src-tauri/tauri.conf.json"
printf '\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80' > "$p/src-tauri/icons/icon.png"
echo 'generator readme' > "$p/README.md"; echo 'node_modules' > "$p/.gitignore"
FAKE
chmod +x "$S/bin/npm" "$S/bin/node"
tscaf() { (cd "$1" && env PATH="$S/bin:$PATH" XDG_CACHE_HOME="$S/cache" FAKE_TGZ="$S/tgz" FAKE_ARGS="$S/args" SPECFLOW_NAME='Habit Tracker' SPECFLOW_PKG=habit_tracker bash "$ST/init.sh" "$2"); }
setpin create_tauri_app_integrity "sha512-$(printf 'A%.0s' $(seq 1 86))=="
setpin create_tauri_app_darwin_arm64_integrity "$(sri "$S/tgz/create-tauri-app-darwin-arm64-$CV.tgz")"
mkdir -p "$S/bad"; echo keep > "$S/bad/README.md"
ck "tauri scaffold: a tarball unlike its pinned sha512 is refused (exit 1)" [ "$(rc_of tscaf "$S/bad" scaffold)" = 1 ]
ck "tauri scaffold: the generator never ran from an unverified tarball" no test -e "$S/args"
ck "tauri scaffold: that refusal wrote nothing" [ "$(ls -A "$S/bad")" = README.md ]
ck "tauri preflight: a tarball unlike its pin fails the preflight (exit 1)" bash -c "out=\$( (cd '$S/bad' && env PATH='$S/bin:$PATH' XDG_CACHE_HOME='$S/cache' FAKE_TGZ='$S/tgz' SPECFLOW_NAME=X SPECFLOW_PKG=x bash '$ST/init.sh' preflight) 2>&1); [ \$? = 1 ] && grep -q '^preflight: .*integrity' <<<\"\$out\""
setpin create_tauri_app_integrity "$(sri "$S/tgz/create-tauri-app-$CV.tgz")"
A="$S/app"; mkdir -p "$A"; echo 'my readme' > "$A/README.md"; printf 'mine/\n' > "$A/.gitignore"
ck "tauri scaffold: verified tarballs scaffold (exit 0)" tscaf "$A" scaffold
ck "tauri scaffold: the generator got the pinned template and identifier" bash -c "grep -qx vanilla-ts '$S/args' && grep -qx com.example.habit-tracker '$S/args'"
ck "tauri scaffold: an existing README.md is kept" [ "$(cat "$A/README.md")" = 'my readme' ]
ck "tauri scaffold: .gitignore keeps its lines, skips the generator's, gains the block once" bash -c "grep -qx 'mine/' '$A/.gitignore' && ! grep -qx node_modules '$A/.gitignore' && [ \$(grep -c '^# >>> specflow tauri pack' '$A/.gitignore') = 1 ]"
ck "tauri scaffold: the overlay wins and its tokens are substituted" python3 - "$A" <<'PY'
import json, pathlib, sys
a = pathlib.Path(sys.argv[1])
assert json.load(open(a / "package.json"))["name"] == "habit_tracker"
assert "mod commands" in (a / "src-tauri/src/lib.rs").read_text()
for p in a.rglob("*"):
    if p.is_file() and p.suffix != ".png":
        assert b"__PKG__" not in p.read_bytes() and b"__NAME__" not in p.read_bytes(), p
PY
ck "tauri scaffold: generated binaries are copied byte for byte" python3 -c 'import sys; sys.exit(open(sys.argv[1], "rb").read() != b"\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80")' "$A/src-tauri/icons/icon.png"
ck "tauri scaffold: generated files the overlay does not replace are kept" test -f "$A/src/main.ts"
cp "$A/.gitignore" "$S/gi.before"
rc=0; out=$(tscaf "$A" scaffold 2>&1) || rc=$?
ck "tauri scaffold: a second run refuses (exit 1)" [ "$rc" = 1 ]
ck "tauri scaffold: the refusal names the clashing file" grep -qE 'package\.json|src/|src-tauri/' <<<"$out"
ck "tauri scaffold: the refused run changed nothing" cmp -s "$A/.gitignore" "$S/gi.before"
B="$S/again"; mkdir -p "$B"; printf '# >>> specflow tauri pack\nnode_modules/\ncoverage/\n# <<< specflow tauri pack\n' > "$B/.gitignore"
tscaf "$B" scaffold >/dev/null 2>&1 || true
ck "tauri scaffold: an existing block is not appended again" [ "$(grep -c '^# >>> specflow tauri pack' "$B/.gitignore")" = 1 ]
ck "tauri init.sh: an unknown subcommand exits 2" [ "$(rc_of tscaf "$A" frobnicate)" = 2 ]
if [ -x /usr/bin/node ] || [ -x /bin/node ]; then echo "SKIP: node in /usr/bin or /bin — missing-node preflight case not run"; else
  mkdir -p "$S/nonode"; ln -s "$(command -v python3)" "$S/nonode/python3"; cp "$S/bin/npm" "$S/nonode/npm"
  rc=0; out=$(cd "$A" && env PATH="$S/nonode:/usr/bin:/bin" XDG_CACHE_HOME="$S/cache" FAKE_TGZ="$S/tgz" SPECFLOW_NAME=X SPECFLOW_PKG=x bash "$ST/init.sh" preflight 2>&1) || rc=$?
  ck "tauri preflight: missing node exits 1" [ "$rc" = 1 ]
  ck "tauri preflight: names node and the doctor" bash -c "grep -q '^preflight: missing node' <<<\"\$1\" && grep -qF -- '--doctor --stack tauri' <<<\"\$1\"" _ "$out"
fi
fi   # scaffold harness

# --- lockfiles are committed (H1) and the advisory lists were enumerated against them (REQ-304) ---
ck ".gitignore no longer ignores *.lock (H1; REQ-334's first clause)" no grep -qxF '*.lock' "$ROOT/.gitignore"
for f in Cargo.lock src-tauri/Cargo.lock pubspec.lock uv.lock package-lock.json; do ck "git would track $f" no git -C "$ROOT" check-ignore -q --no-index "$f"; done
for f in package-lock.json src-tauri/Cargo.lock; do ck "tauri overlay ships $f with the __PKG__ token" grep -q __PKG__ "$TO/$f"; done
# The Task 3 scaffold harness ($A, package habit_tracker) now receives the overlay Cargo.lock.
ck "tauri: the instance Cargo.lock keeps cargo's (name, version) order after substitution" python3 - "${A:-/nonexistent}/src-tauri/Cargo.lock" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
assert "__PKG__" not in text and 'name = "habit_tracker"' in text
ids = [(n, [int(x) for x in re.findall(r"\d+", v)]) for n, v in re.findall(r'\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"', text)]
assert ids and ids == sorted(ids), "[[package]] blocks out of cargo's order"
PY
ck "tauri: audit.toml was enumerated against the shipped Cargo.lock" python3 - "$TO" <<'PY'
import hashlib, pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1]); text = (o / "src-tauri/audit.toml").read_text()
lock = hashlib.sha256((o / "src-tauri/Cargo.lock").read_bytes()).hexdigest()
assert re.search(r"cargo-audit \d+\.\d+\.\d+ on \d{4}-\d{2}-\d{2}", text), "header must name the cargo-audit version and date"
assert f"src-tauri/Cargo.lock sha256 {lock}" in text, f"header must record src-tauri/Cargo.lock sha256 {lock}"
for i in tomllib.loads(text)["advisories"]["ignore"]:
    line = next(l for l in text.splitlines() if f'"{i}"' in l)
    assert re.search(r"# SEC-\d{3} reason: .+; ignoreUntil: \d{4}-\d{2}-\d{2}\s*$", line), line
PY
ck "tauri: osv-scanner.toml was enumerated against the shipped lockfiles" python3 - "$TO" <<'PY'
import datetime, hashlib, pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1]); text = (o / "osv-scanner.toml").read_text()
assert re.search(r"osv-scanner \d+\.\d+\.\d+ on \d{4}-\d{2}-\d{2}", text), "header must name the osv-scanner version and date"
for lock in ("package-lock.json", "src-tauri/Cargo.lock"):
    h = hashlib.sha256((o / lock).read_bytes()).hexdigest()
    assert f"{lock} sha256 {h}" in text, f"header must record {lock} sha256 {h}"
for v in tomllib.loads(text).get("IgnoredVulns", []):
    assert v.get("id") and v.get("reason") and isinstance(v.get("ignoreUntil"), datetime.date), v
    assert re.match(r"SEC-\d{3}: ", v["reason"]), v
PY
# patch/tauri-repin (REQ-304, REQ-388): the 2026-10-02 re-pin. cargo-audit 0.22.2 --deny warnings failed the macOS
# first run on a yanked yoke-derive 0.8.3; the minimal `cargo update -p yoke-derive` moved it to 0.8.4 and nothing else,
# and the advisories were re-enumerated that day (the same seven; osv-scanner 2.6.0 reported RUSTSEC-2024-0429 unused,
# since its GHSA alias already filters the glib group, so osv-scanner.toml drops it while audit.toml keeps it).
ck "tauri: the shipped Cargo.lock locks no yanked version cargo-audit --deny warnings rejects (yoke-derive 0.8.3 -> 0.8.4)" python3 - "$TO" <<'PY'
import pathlib, re, sys
text = (pathlib.Path(sys.argv[1]) / "src-tauri/Cargo.lock").read_text()
locked = set(re.findall(r'\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"', text))
yanked = {("yoke-derive", "0.8.3")}
assert not locked & yanked, sorted(locked & yanked)
assert ("yoke-derive", "0.8.4") in locked, "yoke-derive 0.8.4 expected"
PY
# patch/pin-bump-2026-11 (REQ-334, REQ-304, REQ-388; retrospective 2026-10-04-v3-2-closeout.md, Proposed Changes item 1):
# the 2026-10-04 re-pin regenerated both lockfiles (tauri 2.12, @tauri-apps/cli 2.12.1, vitest 5.0.3). urlpattern 0.6.0
# no longer pulls the unic-* family, so SEC-003's five advisories are gone: its ignores leave both files, its entry is
# fixed (an id is never removed), and SEC-001/SEC-002 are renewed to 2027-03-24.
ck "tauri: audit.toml and osv-scanner.toml record the 2026-10-04 re-enumeration (cargo-audit 0.22.2, osv-scanner 2.6.0)" \
  bash -c 'grep -qF "cargo-audit 0.22.2 on 2026-10-04 against" "$1" && grep -qF "osv-scanner 2.6.0 on 2026-10-04 against" "$2"' _ "$TO/src-tauri/audit.toml" "$TO/osv-scanner.toml"
ck "tauri: the shipped Cargo.lock locks no unic-* crate, no suppression cites SEC-003, and SEC-003 is fixed, suppressing nothing" python3 - "$TO" <<'PY'
import pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1])
lock = (o / "src-tauri/Cargo.lock").read_text()
assert not re.findall(r'^name = "(unic-[^"]+)"$', lock, re.M), re.findall(r'^name = "(unic-[^"]+)"$', lock, re.M)
audit = (o / "src-tauri/audit.toml").read_text(); osv = (o / "osv-scanner.toml").read_text()
assert "SEC-003" not in "".join(l for l in audit.splitlines(True) if not l.startswith("#")), "audit.toml still cites SEC-003"
assert all("SEC-003" not in v["reason"] for v in tomllib.loads(osv).get("IgnoredVulns", [])), "osv-scanner.toml still cites SEC-003"
text = (o / "docs/security/0.0.0-skeleton-disposition.md").read_text()
blk = next(b for b in re.findall(r"^---\n(.*?)\n---$", text, re.M | re.S) if re.search(r"^id: SEC-003$", b, re.M))
assert re.search(r"^status: fixed$", blk, re.M) and re.search(r"^suppresses: \[\]$", blk, re.M), blk
assert "no longer reachable" in blk, blk
PY
ck "tauri: every ignoreUntil and every accepted skeleton entry's expiry: is 2027-03-24 (the 2026-10-04 renewal)" python3 - "$TO" <<'PY'
import datetime, pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1]); want = datetime.date(2027, 3, 24)
osv = tomllib.loads((o / "osv-scanner.toml").read_text()).get("IgnoredVulns", [])
assert osv and all(v["ignoreUntil"] == want for v in osv), osv
audit = [l for l in (o / "src-tauri/audit.toml").read_text().splitlines() if l.strip().startswith('"')]
assert audit and all(l.rstrip().endswith("ignoreUntil: 2027-03-24") for l in audit), audit
text = (o / "docs/security/0.0.0-skeleton-disposition.md").read_text()
for b in re.findall(r"^---\n(.*?)\n---$", text, re.M | re.S):
    if re.search(r"^status: accepted$", b, re.M):
        assert re.search(r"^expiry: 2027-03-24$", b, re.M), b
PY
ck "tauri: osv-scanner.toml keeps no ignore osv-scanner 2.6.0 reports unused (RUSTSEC-2024-0429 is filtered by its GHSA alias)" python3 - "$TO" <<'PY'
import pathlib, sys, tomllib
o = pathlib.Path(sys.argv[1])
osv = [v["id"] for v in tomllib.loads((o / "osv-scanner.toml").read_text()).get("IgnoredVulns", [])]
assert "RUSTSEC-2024-0429" not in osv and "GHSA-wrw7-89jp-8q8g" in osv, osv
assert "RUSTSEC-2024-0429" in tomllib.loads((o / "src-tauri/audit.toml").read_text())["advisories"]["ignore"]
PY
ck "tauri: the skeleton review and disposition record the 2026-10-04 re-enumeration and its Cargo.lock sha256" python3 - "$TO" <<'PY'
import hashlib, pathlib, sys
o = pathlib.Path(sys.argv[1]); sd = o / "docs/security"
lock = hashlib.sha256((o / "src-tauri/Cargo.lock").read_bytes()).hexdigest()
for name in ("0.0.0-skeleton-review.md", "0.0.0-skeleton-disposition.md"):
    flat = " ".join((sd / name).read_text().split())
    assert "re-enumerated on 2026-10-04" in flat and lock in flat, name
PY
SD="$TO/docs/security"
ck "tauri: the pack ships the skeleton's review and disposition (the SEC-NNN its suppressions cite, REQ-388)" test -f "$SD/0.0.0-skeleton-review.md" -a -f "$SD/0.0.0-skeleton-disposition.md"
ck "tauri: every suppressed advisory is listed by exactly one skeleton disposition entry" python3 - "$TO" <<'PY'
import pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1])
ids = set(tomllib.loads((o / "src-tauri/audit.toml").read_text())["advisories"]["ignore"])
ids |= {v["id"] for v in tomllib.loads((o / "osv-scanner.toml").read_text()).get("IgnoredVulns", [])}
listed = []
for block in re.findall(r"^---\n(.*?)\n---$", (o / "docs/security/0.0.0-skeleton-disposition.md").read_text(), re.M | re.S):
    m = re.search(r"^suppresses:\s*\[(.*)\]\s*$", block, re.M)
    if m:
        listed += [x.strip() for x in m.group(1).split(",") if x.strip()]
assert sorted(listed) == sorted(ids), (sorted(listed), sorted(ids))
PY
ck "tauri: the scaffolded instance receives the skeleton disposition" test -f "${A:-/nonexistent}/docs/security/0.0.0-skeleton-disposition.md"
# P4 final review: the skeleton disposition is inherited by every tauri instance, so it is recorded as the pack's,
# not under a person's handle, and each entry says the instance's first /security-review must confirm it; its expiry
# is a known limitation (README) and a mandatory /retrospective bump item.
ck "tauri: every skeleton disposition entry is owned by the pack (no personal handle) and marked inherited, confirm at the first /security-review" python3 - "$TO" <<'PY'
import pathlib, re, sys
text = (pathlib.Path(sys.argv[1]) / "docs/security/0.0.0-skeleton-disposition.md").read_text()
blocks = [b for b in re.findall(r"^---\n(.*?)\n---$", text, re.M | re.S) if re.search(r"^id:", b, re.M)]
assert blocks, "no entries"
for b in blocks:
    assert re.search(r"^owner: tauri-pack$", b, re.M), b
    m = re.search(r"^inherited: (.+)$", b, re.M)
    assert m and "first /security-review" in m.group(1), b
PY
SKX=$(python3 -c 'import re, sys; print(sorted(set(re.findall(r"^expiry: (\S+)$", open(sys.argv[1]).read(), re.M)))[0])' "$TO/docs/security/0.0.0-skeleton-disposition.md")
ck "tauri: README records the skeleton disposition's expiry ($SKX) as a known limitation" bash -c 'awk "/^### Tauri\$/{f=1; next} /^### /{f=0} f" "$1" | grep -qF "$2"' _ "$ROOT/README.md" "$SKX"
# #36 medium 1: the recovery an EXISTING instance can actually do itself — a template re-pin never reaches it — is
# spelled out in full in the README's known limitation and in every inherited: text: bump ignoreUntil in
# osv-scanner.toml AND in src-tauri/audit.toml's trailing comments, and add disposition entries under the instance's
# own version. #36 medium 3: the README also says the lapse is calendar-triggered by design and names the 30-day test.
TAURI_README=$(awk '/^### Tauri$/{f=1; next} /^### /{f=0} f' "$ROOT/README.md" | tr '\n' ' ' | tr -s ' ')
for w in 'ignoreUntil' 'osv-scanner.toml' 'src-tauri/audit.toml' "under the instance's own version" 'never reaches an existing instance' \
         'calendar-triggered by design' 'test_suppression_expiry.sh'; do
  ck "tauri: README's known limitation gives the instance-side recovery: '$w'" grep -qF -- "$w" <<<"$TAURI_README"
done
# A fixed entry (SEC-003 since the 2026-10-04 re-pin) suppresses nothing and has no expiry, so its inherited:
# text renews nothing; every other entry gives the recovery steps (REQ-334).
ck "tauri: every accepted skeleton disposition inherited: text gives the same instance-side recovery steps; a fixed one renews nothing" python3 - "$TO" <<'PY'
import pathlib, re, sys
text = (pathlib.Path(sys.argv[1]) / "docs/security/0.0.0-skeleton-disposition.md").read_text()
blocks = [b for b in re.findall(r"^---\n(.*?)\n---$", text, re.M | re.S) if re.search(r"^id: SEC-", b, re.M)]
assert len(blocks) == 3, len(blocks)
for b in blocks:
    inh = re.search(r"^inherited: (.+)$", b, re.M).group(1)
    if re.search(r"^status: fixed$", b, re.M):
        assert "ignoreUntil" not in inh and "before this expiry" not in inh, inh
        for w in ("no longer locks any unic-* crate", "nothing is suppressed", "carries this id forward as fixed", "renews nothing"):
            assert w in inh, (w, inh)
        continue
    for w in ("ignoreUntil", "osv-scanner.toml", "src-tauri/audit.toml", "the instance's own version", "never reaches"):
        assert w in inh, (w, inh)
PY
# #36 medium 4 (art-threat-driven-security): the skeleton review every instance inherits cites its CWEs by their real
# names, carries each advisory's CVSS v4.0 vector, and says the pack
# author's severities are provisional until an instance's second reviewer confirms them (the solo rule).
ck "tauri: the skeleton review's SEC entries carry vectors, cite CWE-758 by its name, and are marked provisional" python3 - "$TO" <<'PY'
import pathlib, re, sys
text = (pathlib.Path(sys.argv[1]) / "docs/security/0.0.0-skeleton-review.md").read_text()
blocks = {re.search(r"^id: (SEC-\d{3})$", b, re.M).group(1): b
          for b in re.findall(r"^---\n(.*?)\n---$", text, re.M | re.S) if re.search(r"^id: SEC-", b, re.M)}
assert sorted(blocks) == ["SEC-001", "SEC-002", "SEC-003"], sorted(blocks)
for sec, b in blocks.items():
    assert re.search(r"^cvss_vector: CVSS:4\.0/\S+$", b, re.M) and not re.search(r"^vector:", b, re.M), (sec, b)
assert "pending (P3 schema)" not in text
assert "cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N" in blocks["SEC-001"]
flat = " ".join(text.split())
assert "improper handling of an exceptional condition" not in flat
assert "CWE-758, Reliance on Undefined, Unspecified, or Implementation-Defined Behavior" in flat
summary = flat.split("## Tools run")[0]
assert "provisional" in summary and "second reviewer" in summary and "art-threat-driven-security" in summary, summary
PY
ck "/retrospective's bump list names the pack-shipped skeleton dispositions' expiry" grep -qF 'skeleton disposition' "$ROOT/.claude/commands/retrospective.md"
# PR #36 second run, medium (REQ-388, REQ-331): the skeleton's lapse has an owner, a re-pin deadline and its triggers
# (2027-03-24 since the 2026-10-04 renewal; warn and fail dates are floor.py expiry's 60- and 30-day thresholds).
for f in README.md .claude/commands/retrospective.md; do
  flat=$(tr '\n' ' ' < "$ROOT/$f" | tr -s ' ')
  for w in 'kpingali123' '2027-02-13' 'from 2027-01-23' 'from 2027-02-23' 'test_suppression_expiry.sh' 'app-stacks.yml' \
           'weekly schedule' 'scaffolded after 2027-03-24 fails its first gates run until it renews'; do
    ck "$f names the tauri lapse's owner, deadline and triggers: '$w'" grep -qF -- "$w" <<<"$flat"
  done
done
ck "/security-review says to re-own and confirm inherited entries" grep -qF 'inherited:' "$ROOT/.claude/commands/security-review.md"

# --- flutter pack (REQ-303/304): static contract; no toolchain, no network ---
F="$ROOT/stacks/flutter"; FO="$F/overlay"; fv() { val "$F/pack.yml" get "$1"; }
ck "stacks/flutter present" test -d "$F"
for k in flutter_version macos_host lockfile; do ck "flutter: pack.yml pins $k" [ -n "$(fv $k)" ]; done
ck "flutter: guided choice 3, a multi-platform app" [ "$(fv guided_choice):$(fv guided_label)" = "3:a multi-platform app" ]
ck "flutter: CI runner is macos-15" [ "$(fv ci_runs_on)" = macos-15 ]
ck "flutter: pack minimum macOS 12.0 (Xcode 27 rejects 10.15)" [ "$(fv macos_min)" = 12.0 ]
ck "flutter: arm64 only (Xcode 27 lipo)" [ "$(fv macos_archs)" = arm64 ]
ck "flutter: coverage_exclude" [ "$(val "$F/pack.yml" getlist coverage_exclude | tr '\n' ' ')" = "lib/main.dart " ]
for f in lib/main.dart lib/app.dart test/widget_test.dart osv-scanner.toml; do ck "flutter overlay has $f" test -f "$FO/$f"; done
ck "flutter: main.dart honours SPECFLOW_SMOKE" grep -q SPECFLOW_SMOKE "$FO/lib/main.dart"
ck "flutter: the widget test imports the package by token" grep -qF 'package:__PKG__/app.dart' "$FO/test/widget_test.dart"
ck "flutter: init.sh creates macOS only and rewrites the minimum" bash -c "grep -q macos_min '$F/init.sh' && grep -q flutter_version '$F/init.sh' && grep -q -- '--platforms=macos' '$F/init.sh' && grep -q MACOSX_DEPLOYMENT_TARGET '$F/init.sh' && grep -q 'platform :osx' '$F/init.sh' && grep -q 'ARCHS' '$F/init.sh'"
for w in 'flutter pub get --enforce-lockfile' 'dart analyze --fatal-infos' 'flutter test'; do ck "flutter: gates.sh runs $w" grep -qF -- "$w" "$F/gates.sh"; done
ck "flutter: pack.yml pins the SDK by a 40-hex frameworkRevision (dfe-4)" grep -qE '^[0-9a-f]{40}$' <<<"$(fv flutter_revision)"
ck "flutter: action verifies the SDK revision and precaches macOS" bash -c "grep -qF '$(fv flutter_revision)' '$F/action.yml' && grep -q 'rev-parse HEAD' '$F/action.yml' && grep -qF 'flutter precache --macos' '$F/action.yml' && ! grep -q subosito '$F/action.yml'"
ck "flutter: the doctor check and install hint both verify the revision" bash -c "[ \$(grep -E '^(check|install_macos)_flutter:' '$F/pack.yml' | grep -cF '$(fv flutter_revision)') = 2 ]"
ck "flutter: init.sh checks the SDK revision, not the tag" grep -q flutter_revision "$F/init.sh"
# patch/pin-bump-2026-11 (REQ-334, REQ-303; retrospective 2026-10-04-v3-2-closeout.md, Proposed Changes item 1): every
# copy of the Flutter pin names pack.yml's flutter_version and flutter_revision — the action's defaults, README's clone
# and SHA check, and init.sh's note of the revision its Dart keyword list was copied from.
ck "flutter: action.yml's defaults are pack.yml's flutter_version and flutter_revision" \
  bash -c 'grep -qF "default: \"$2\"" "$1" && grep -qF "default: \"$3\"" "$1"' _ "$F/action.yml" "$(fv flutter_version)" "$(fv flutter_revision)"
ck "flutter: README clones pack.yml's flutter_version and checks its flutter_revision" \
  bash -c 'grep -qF -- "--branch $2 https://github.com/flutter/flutter.git" "$1" && grep -qF "rev-parse HEAD)\" = $3" "$1"' _ "$ROOT/README.md" "$(fv flutter_version)" "$(fv flutter_revision)"
ck "flutter: init.sh's Dart keyword list cites the pinned flutter_revision" grep -qF "flutter_revision $(fv flutter_revision))" "$F/init.sh"
ck "flutter: no copy names a Flutter release other than the pinned one as current (init.sh, store-checklist.md)" python3 - "$F" "$(fv flutter_version)" <<'PY'
import pathlib, re, sys
f, pinned = pathlib.Path(sys.argv[1]), sys.argv[2]
for name in ("init.sh", "store-checklist.md"):
    flat = " ".join(" ".join(re.sub(r"^\s*#\s?", "", l) for l in (f / name).read_text().splitlines()).split())
    for m in re.finditer(r"Flutter (3\.\d+\.\d+)", flat):
        ctx = flat[m.start():m.start() + 160]
        assert m.group(1) == pinned or "measured 2026-09-25" in ctx or "earlier" in ctx, (name, ctx)
PY
ck "flutter: release.sh builds with --no-pub (no network in a release hook)" grep -qF -- '--no-pub' "$F/release.sh"
for w in 'Apple Developer Program' APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD notarytool stapler Gatekeeper 'App Store' 'Developer ID' ditto .zip; do
  ck "flutter: store-checklist names $w" grep -qF -- "$w" "$F/store-checklist.md"
done
ck "flutter: store-checklist puts the macOS minimum in project.pbxproj (where init.sh rewrites it)" grep -qF 'project.pbxproj' "$F/store-checklist.md"
ck "flutter: store-checklist does not claim Release.xcconfig carries MACOSX_DEPLOYMENT_TARGET" no grep -qE 'Release\.xcconfig[^\n]*MACOSX_DEPLOYMENT_TARGET' "$F/store-checklist.md"
ck "tauri: init.sh preflight has no unused HAVE_NODE variable" no grep -q HAVE_NODE "$T/init.sh"
for k in $(val "$F/pack.yml" getlist prereqs); do ck "flutter: install_linux_$k is honest (macOS only)" grep -qi macos <<<"$(fv "install_linux_$k")"; done
ck "flutter: Calendar is a valid package" [ "$(pkg "$F" Calendar calendar)" = calendar ]
for n in flutter flutter_test test class library import late required async source collection meta cupertino_icons flutter_lints; do
  ck "flutter: package '$n' refused (exit 2)" [ "$(rc_of pkg "$F" X "$n")" = 2 ]
done
# release.sh contract without a toolchain: fake flutter and ditto stand in for the build and the zip.
R="$W/rel-flutter"; mkdir -p "$R/bin" "$R/app/build/macos/Build/Products/Release/old.app"
printf 'name: fix\nversion: 0.1.0+1\n' > "$R/app/pubspec.yaml"
cat > "$R/bin/flutter" <<'FAKE'
#!/usr/bin/env bash
touch "$FAKE_MARK"; printf '%s\n' "$@" > "$FAKE_ARGV"; d=build/macos/Build/Products/Release
for n in $FAKE_APPS; do mkdir -p "$d/$n.app/Contents/MacOS"; head -c 2048 /dev/urandom > "$d/$n.app/Contents/MacOS/$n"; done
FAKE
cat > "$R/bin/ditto" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do src="${dest:-}"; dest="$a"; done
python3 -c 'import os, shutil, sys; shutil.make_archive(sys.argv[2][:-4], "zip", os.path.dirname(sys.argv[1]), os.path.basename(sys.argv[1]))' "$src" "$dest"
FAKE
chmod +x "$R/bin/flutter" "$R/bin/ditto"
frel() { (cd "$R/app" && env RELEASE_PARTS=bundle PATH="$R/bin:$PATH" FAKE_MARK="$R/mark" FAKE_ARGV="$R/argv" "$@" bash "$F/release.sh"); }
ck "flutter release: a VERSION unlike pubspec.yaml is refused" [ "$(rc_of frel VERSION=0.2.0 DIST_DIR="$R/d0" FAKE_APPS=fix)" != 0 ]
ck "flutter release: the refusal comes before building" no test -e "$R/mark"
ck "flutter release: one zipped app built" frel VERSION=0.1.0 DIST_DIR="$R/d1" FAKE_APPS=fix
ck "flutter release: manifest lists exactly one .zip, verified" python3 - "$R/d1" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
names = [e["filename"] for e in m["artifacts"]]
assert m["version"] == "0.1.0" and len(names) == 1 and names[0].endswith(".zip"), m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
ck "flutter release: a stale .app is cleared before building" no test -e "$R/app/build/macos/Build/Products/Release/old.app"
ck "flutter release: the build runs --release --no-pub (no network)" bash -c "grep -qx -- --release '$R/argv' && grep -qx -- --no-pub '$R/argv'"
ck "flutter release: two apps are refused" [ "$(rc_of frel VERSION=0.1.0 DIST_DIR="$R/d2" FAKE_APPS='a b')" != 0 ]
# init.sh preflight/scaffold without a toolchain: a fake flutter stands in for the SDK and its generator.
if [[ ! -f "$F/init.sh" ]]; then fail "flutter: init.sh missing — scaffold harness not run"; else
S="$W/scaf-flutter"; SR="$S/sdk"; mkdir -p "$S/bin" "$SR/packages/flutter_tools/templates/cocoapods" "$S/root/scripts/lib/specflow" "$S/root/stacks"
cp "$ROOT/scripts/lib/specflow/config.py" "$S/root/scripts/lib/specflow/"; cp -R "$F" "$S/root/stacks/flutter"; SF="$S/root/stacks/flutter"
printf "platform :osx, '10.15'\n\nflutter_macos_podfile_setup\n" > "$SR/packages/flutter_tools/templates/cocoapods/Podfile-macos"
cat > "$S/bin/flutter" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf '{\n  "frameworkVersion": "%s",\n  "frameworkRevision": "%s",\n  "flutterRoot": "%s"\n}\n' "$FAKE_VER" "$FAKE_REV" "$FAKE_ROOT"; exit 0; fi
[[ "${1:-}" == create ]] || exit 0
for a in "$@"; do d="$a"; done; p=""; while [[ $# -gt 0 ]]; do [[ "$1" == --project-name ]] && p="$2"; shift; done
mkdir -p "$d/lib" "$d/test" "$d/macos/Runner.xcodeproj" "$d/macos/Runner/Configs" "$d/macos/Runner/Assets.xcassets/AppIcon.appiconset"
printf 'name: %s\nversion: 1.0.0+1\n' "$p" > "$d/pubspec.yaml"
echo 'generated main' > "$d/lib/main.dart"; echo 'generated test' > "$d/test/widget_test.dart"
for i in 1 2 3; do echo '    MACOSX_DEPLOYMENT_TARGET = 10.15;'; done > "$d/macos/Runner.xcodeproj/project.pbxproj"
echo '#include "../../Flutter/Flutter-Release.xcconfig"' > "$d/macos/Runner/Configs/Release.xcconfig"
printf '\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80' > "$d/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png"
echo 'generator readme' > "$d/README.md"; echo '.dart_tool/' > "$d/.gitignore"
FAKE
chmod +x "$S/bin/flutter"
fscaf() { (cd "$1" && env PATH="$S/bin:$PATH" FAKE_ROOT="$SR" FAKE_VER="$(fv flutter_version)" FAKE_REV="${FAKE_REV_OVERRIDE:-$(fv flutter_revision)}" SPECFLOW_NAME='Acme Notes' SPECFLOW_PKG=acme_notes bash "$SF/init.sh" "$2"); }
mkdir -p "$S/old"
ck "flutter scaffold: another SDK revision is refused (exit 1)" [ "$(FAKE_REV_OVERRIDE=0000000000000000000000000000000000000000 rc_of fscaf "$S/old" scaffold)" = 1 ]
ck "flutter scaffold: that refusal wrote nothing" [ -z "$(ls -A "$S/old")" ]
ck "flutter preflight: another SDK revision fails the preflight (exit 1)" [ "$(FAKE_REV_OVERRIDE=0000000000000000000000000000000000000000 rc_of fscaf "$S/old" preflight)" = 1 ]
A="$S/app"; mkdir -p "$A"; echo 'my readme' > "$A/README.md"; printf 'mine/\n' > "$A/.gitignore"
ck "flutter scaffold: the pinned SDK scaffolds (exit 0)" fscaf "$A" scaffold
ck "flutter scaffold: every MACOSX_DEPLOYMENT_TARGET is the pack minimum" python3 - "$A/macos/Runner.xcodeproj/project.pbxproj" "$(fv macos_min)" <<'PY'
import re, sys
vals = re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);", open(sys.argv[1]).read())
assert len(vals) == 3 and set(vals) == {sys.argv[2]}, vals
PY
ck "flutter scaffold: Podfile from the SDK template at the pack minimum" [ "$(head -1 "$A/macos/Podfile" 2>/dev/null)" = "platform :osx, '$(fv macos_min)'" ]
ck "flutter scaffold: Release.xcconfig gains ARCHS = arm64 once" [ "$(grep -c '^ARCHS = arm64$' "$A/macos/Runner/Configs/Release.xcconfig" 2>/dev/null)" = 1 ]
ck "flutter scaffold: version 0.1.0+1" grep -qx 'version: 0.1.0+1' "$A/pubspec.yaml"
ck "flutter scaffold: the overlay replaces the generated main.dart" grep -q SPECFLOW_SMOKE "$A/lib/main.dart"
ck "flutter scaffold: overlay tokens substituted" bash -c "grep -qF 'package:acme_notes/app.dart' '$A/test/widget_test.dart' && grep -qF 'Hello from Acme Notes' '$A/lib/app.dart'"
ck "flutter scaffold: generated binaries are copied byte for byte" python3 -c 'import sys; sys.exit(open(sys.argv[1], "rb").read() != b"\x89PNG\r\n\x1a\n\x00\xff\xfe__PKG__\x80")' "$A/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png"
ck "flutter scaffold: an existing README.md is kept" [ "$(cat "$A/README.md")" = 'my readme' ]
ck "flutter scaffold: .gitignore keeps its lines, skips the generator's, gains the block once" bash -c "grep -qx 'mine/' '$A/.gitignore' && grep -qx '.idea/' '$A/.gitignore' && [ \$(grep -c '^# >>> specflow flutter pack' '$A/.gitignore') = 1 ]"
cp "$A/.gitignore" "$S/gi.before"; cp "$A/pubspec.yaml" "$S/pub.before"
rc=0; out=$(fscaf "$A" scaffold 2>&1) || rc=$?
ck "flutter scaffold: a second run refuses (exit 1)" [ "$rc" = 1 ]
ck "flutter scaffold: the refusal names the clashing file" grep -qE 'pubspec\.yaml|lib/|test/|macos/' <<<"$out"
ck "flutter scaffold: the refused run changed nothing" bash -c "cmp -s '$A/.gitignore' '$S/gi.before' && cmp -s '$A/pubspec.yaml' '$S/pub.before'"
B="$S/again"; mkdir -p "$B"; printf '# >>> specflow flutter pack\n.dart_tool/\n# <<< specflow flutter pack\n' > "$B/.gitignore"
fscaf "$B" scaffold >/dev/null 2>&1 || true
ck "flutter scaffold: an existing block is not appended again" [ "$(grep -c '^# >>> specflow flutter pack' "$B/.gitignore")" = 1 ]
ck "flutter init.sh: an unknown subcommand exits 2" [ "$(rc_of fscaf "$A" frobnicate)" = 2 ]
if [ -x /usr/bin/flutter ] || [ -x /bin/flutter ]; then echo "SKIP: flutter in /usr/bin or /bin — missing-flutter preflight case not run"; else
  mkdir -p "$S/noflutter"; ln -s "$(command -v python3)" "$S/noflutter/python3"
  rc=0; out=$(cd "$A" && env PATH="$S/noflutter:/usr/bin:/bin" SPECFLOW_NAME=X SPECFLOW_PKG=x bash "$SF/init.sh" preflight 2>&1) || rc=$?
  ck "flutter preflight: missing flutter exits 1" [ "$rc" = 1 ]
  ck "flutter preflight: names flutter and the doctor" bash -c "grep -q '^preflight: missing flutter' <<<\"\$1\" && grep -qF -- '--doctor --stack flutter' <<<\"\$1\"" _ "$out"
fi
fi   # scaffold harness

ck "flutter overlay ships pubspec.lock" test -s "$FO/pubspec.lock"
ck "flutter overlay ships the plugin registrant pub get would write" bash -c "grep -q 'import FlutterMacOS' '$FO/macos/Flutter/GeneratedPluginRegistrant.swift' && grep -q 'func RegisterGeneratedPlugins' '$FO/macos/Flutter/GeneratedPluginRegistrant.swift'"
for n in clock fake_async stack_trace; do ck "flutter: package '$n' (a locked dependency) refused (exit 2)" [ "$(rc_of pkg "$F" X "$n")" = 2 ]; done
ck "flutter: osv-scanner.toml was enumerated against the shipped pubspec.lock" python3 - "$FO" <<'PY'
import datetime, hashlib, pathlib, re, sys, tomllib
o = pathlib.Path(sys.argv[1]); text = (o / "osv-scanner.toml").read_text()
h = hashlib.sha256((o / "pubspec.lock").read_bytes()).hexdigest()
assert re.search(r"osv-scanner \d+\.\d+\.\d+ on \d{4}-\d{2}-\d{2}", text), "header must name the osv-scanner version and date"
assert f"pubspec.lock sha256 {h}" in text, f"header must record pubspec.lock sha256 {h}"
for v in tomllib.loads(text).get("IgnoredVulns", []):
    assert v.get("id") and v.get("reason") and isinstance(v.get("ignoreUntil"), datetime.date), v
    assert re.match(r"SEC-\d{3}: ", v["reason"]), v
PY

# P7 R8 (REQ-303, REQ-351): the floor's osv-scanner reads every lockfile a pack lists — run-security-floor.sh admits a
# lockfile by basename (LOCKFILE_PATTERN), not by the pack's lockfiles:, so the pattern must match each listed basename.
# Covers: REQ-303
ck "every lockfile a pack's lockfiles: lists matches run-security-floor.sh's LOCKFILE_PATTERN (osv-scanner scans it)" python3 - "$ROOT" <<'PY'
import glob, os, re, subprocess, sys
root = sys.argv[1]
pat = re.search(r"(?m)^LOCKFILE_PATTERN='([^']+)'$", open(os.path.join(root, "scripts/run-security-floor.sh")).read()).group(1)
packs = glob.glob(os.path.join(root, "stacks/*/pack.yml")) + [p for p in (os.path.join(root, ".specflow/pack.yml"),) if os.path.isfile(p)]
assert packs, "no pack"
for pk in packs:
    lfs = subprocess.run([sys.executable, os.path.join(root, "scripts/lib/specflow/config.py"), "--file", pk, "getlist", "lockfiles"],
                         capture_output=True, text=True, check=True).stdout.split()
    for lf in lfs:
        assert re.match(pat, os.path.basename(lf)), (pk, lf)
PY

finish test_stack_packs
