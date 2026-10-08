#!/usr/bin/env bash
# REQ-360: instantiate the template in a temp dir and run run-quality-gates.sh
# there (exit 0). REQ-305: the installed release hook honours its contract.
# REQ-306: with every example removed the gates stay green. Opt-in with
# SPECFLOW_FIRST_RUN=1; CI runs one case per profile (FIRST_RUN_CASES).
# Covers: REQ-360, REQ-306, REQ-305, REQ-393
set -euo pipefail
[[ "${SPECFLOW_QG_RUNNING:-0}" == 1 ]] && { echo "SKIP: first-run no-op inside the orchestrator (recursion guard)"; exit 0; }
[[ "${SPECFLOW_FIRST_RUN:-0}" == 1 ]] || { echo "SKIP: set SPECFLOW_FIRST_RUN=1 to instantiate and gate a throwaway copy"; exit 0; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
instance && { echo "SKIP: instance — first-run tests the template source"; exit 0; }
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT; GATES_OUT=""
gates() {  # gates DIR LABEL — the instance's gates; on failure the summary keeps floor failures apart (REQ-360)
  local rc=0
  # The instance is never on a ship branch: the release gates derive the ship version from SPECFLOW_HEAD_BRANCH, else
  # GITHUB_HEAD_REF (disposition_gate.ship_branch_version), and on the factory's own ship PR CI's GITHUB_HEAD_REF is
  # ship/<version>, so without unsetting both the instance's gates evaluated that version and failed on its fenced
  # release records (PR #62; tests/governance/test_first_run_env.sh pins this line).
  GATES_OUT=$(cd "$1" && env -u SPECFLOW_QG_RUNNING -u SPECFLOW_FIRST_RUN -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH bash scripts/run-quality-gates.sh 2>&1) || rc=$?
  # The floor assertions grep this file, never $GATES_OUT as an argv: the output is thousands of lines and
  # Linux caps one argument at 128 KiB (MAX_ARG_STRLEN), which made the first-run jobs fail on CI (REQ-360).
  GATES_FILE="$WORK/$(basename "$1").gates.out"; printf '%s\n' "$GATES_OUT" > "$GATES_FILE"
  if [[ $rc -eq 0 ]]; then pass "$2: gates exit 0"; return 0; fi
  fail "$2: gates exit $rc"
  sed -n '/^=== Summary ===/,$p' <<<"$GATES_OUT" | sed 's/^/    /'
  tail -40 <<<"$GATES_OUT" | sed 's/^/    | /'
}
manifest() {  # manifest DIST VERSION SUFFIX [PARTS] — schema 1 or 2; every entry verifies (tests/governance/lib/first_run_manifest.py)
  python3 "$ROOT/tests/governance/lib/first_run_manifest.py" "$@"
}
app_missing() {  # app_missing STACK — the pack prerequisites --doctor reports MISSING (empty: ready)
  local s="$1" out p m=""
  [[ -f "$ROOT/stacks/$s/pack.yml" ]] || { echo "pack stacks/$s/"; return 0; }
  out=$(cd "$ROOT" && bash scripts/init-project.sh --doctor --stack "$s" </dev/null 2>&1 || true)
  for p in $(python3 "$ROOT/scripts/lib/specflow/config.py" --file "$ROOT/stacks/$s/pack.yml" getlist prereqs 2>/dev/null); do
    if grep -q "^MISSING $p:" <<<"$out"; then m="$m $p"; fi
  done
  echo "${m# }"
}
DEFAULT_CASES="guided engineer profiles"
if [[ -z "${FIRST_RUN_CASES:-}" && "$(uname -s)" == Darwin ]]; then
  for s in tauri flutter; do
    m=$(app_missing "$s")
    if [[ -z "$m" ]]; then DEFAULT_CASES="$DEFAULT_CASES $s"
    else echo "SKIP: $s — missing $m (bash scripts/init-project.sh --doctor --stack $s; name it in FIRST_RUN_CASES to run it anyway)"; fi
  done
fi
if [[ -z "${FIRST_RUN_CASES:-}" ]] && command -v cargo-audit >/dev/null 2>&1 && command -v osv-scanner >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v pip-audit >/dev/null 2>&1; then DEFAULT_CASES="$DEFAULT_CASES packfloor"; fi
for c in ${FIRST_RUN_CASES:-$DEFAULT_CASES}; do
  D="$WORK/$c"; copy_template "$D"
  case "$c" in
    guided)
      ck "guided: init with Enter at every prompt" bash -c "cd '$D' && printf '\n\n\n\n\n\n\n\n' | bash scripts/init-project.sh"
      ck "guided: profile recorded" [ "$(python3 "$D/scripts/lib/specflow/config.py" --root "$D" get profile 2>/dev/null)" = guided ]
      gates "$D" "guided/python/lanes/solo"
      ck "guided: the floor ran pip-audit and bandit" bash -c 'grep -q "^PASS floor pip-audit" "$1" && grep -q "^PASS floor bandit" "$1"' _ "$GATES_FILE"
      ck "guided: next.sh on main in the remote-less instance runs (REQ-393)" bash -c "cd '$D' && bash scripts/next.sh --json > '$WORK/next-guided.json'"
      ck "guided: idle, NewBranch(ProposeDesign) rendered design/<slug> then brainstorming, PR state unknown (P5 R4)" python3 - "$WORK/next-guided.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["state"] == {"lane": "none", "phase": "idle"}, d["state"]
assert d["step"] == {"kind": "NewBranch", "proposal": {"kind": "ProposeDesign"}}, d["step"]
assert "git checkout -b design/<slug>" in d["next_step"] and "/superpowers:brainstorming" in d["next_step"], d["next_step"]
assert d["pr_state_known"] is False and d["profile"] == "guided" and d["path"] == "lanes", d
PY
      ck "guided: never awaiting-verifier, never a PR command, in the remote-less instance" \
        bash -c '! grep -qE "awaiting-verifier|gh pr (create|merge)" "$1"' _ "$WORK/next-guided.json"
      ck "guided: release-python.sh runs" bash -c "cd '$D' && SOURCE_DATE_EPOCH=1791158400 VERSION=0.1.0 DIST_DIR='$WORK/dist' bash scripts/release-python.sh"
      ck "guided: dist/manifest.json verifies" python3 - "$WORK/dist" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]; m = json.load(open(os.path.join(d, "manifest.json")))
assert m["version"] == "0.1.0" and m["artifacts"], m
for e in m["artifacts"]:
    p = os.path.join(d, e["filename"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == e["sha256"] and os.path.getsize(p) == e["size"], e
PY
      # Covers: REQ-351
      if [ "${SPECFLOW_DOCKER:-}" = 1 ]; then ck "guided (opt-in docker): the instance's image builds from its own Dockerfile and runs as uid 10001" bash -c 'cd "$1" && mkdir -p dist && cp "$2"/*.whl dist/ && docker build -q -t fr-py:0.1.0 . >/dev/null && u=$(docker run --rm --entrypoint id fr-py:0.1.0 -u); rm -rf dist; [ "$u" = 10001 ]' _ "$D" "$WORK/dist"; fi
      (cd "$D" && python3 scripts/lib/specflow/examples.py names | while read -r n s; do
         python3 scripts/lib/specflow/examples.py list "$n" | while IFS= read -r p; do rm -rf "$p"; done
         python3 scripts/lib/specflow/examples.py strip "$n"; done)
      gates "$D" "guided with every shipped example removed"
      ck "guided (examples removed): the floor ran pip-audit and bandit" bash -c 'grep -q "^PASS floor pip-audit" "$1" && grep -q "^PASS floor bandit" "$1"' _ "$GATES_FILE" ;;
    engineer)
      ck "engineer: init with flags" bash -c "cd '$D' && bash scripts/init-project.sh --name Acme --profile engineer --path regulated --solo false </dev/null"
      gates "$D" "engineer/python/regulated/team"
      ck "engineer: the floor ran pip-audit and bandit" bash -c 'grep -q "^PASS floor pip-audit" "$1" && grep -q "^PASS floor bandit" "$1"' _ "$GATES_FILE"
      ck "engineer: next.sh on main in the remote-less instance runs (REQ-393)" bash -c "cd '$D' && bash scripts/next.sh --json > '$WORK/next-engineer.json'"
      ck "engineer (regulated): idle, NewBranch(ProposeSpec) rendered phase/spec-<slug> then brainstorming (P5 R4)" python3 - "$WORK/next-engineer.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["state"] == {"lane": "none", "phase": "idle"}, d["state"]
assert d["step"] == {"kind": "NewBranch", "proposal": {"kind": "ProposeSpec"}}, d["step"]
assert "git checkout -b phase/spec-<slug>" in d["next_step"] and "/superpowers:brainstorming" in d["next_step"], d["next_step"]
assert d["pr_state_known"] is False and d["profile"] == "engineer" and d["path"] == "regulated", d
PY
      ck "engineer: never awaiting-verifier, never a PR command" bash -c '! grep -qE "awaiting-verifier|gh pr (create|merge)" "$1"' _ "$WORK/next-engineer.json" ;;
    tauri)   # macOS (REQ-360): guided Enter-through with choice 1 — the Mac-desktop pack end to end
      D="$WORK/habit-tracker"; copy_template "$D"   # the default name derives the package habit_tracker
      ck "tauri: guided init, choice 1" bash -c "cd '$D' && printf '\n\n1\n\n' | bash scripts/init-project.sh"
      ck "tauri: stack recorded" [ "$(python3 "$D/scripts/lib/specflow/config.py" --root "$D" get stack 2>/dev/null)" = tauri ]
      ck "tauri: lockfiles and ignore lists committed (H1)" git -C "$D" ls-files --error-unmatch package-lock.json src-tauri/Cargo.lock rust-toolchain.toml src-tauri/audit.toml osv-scanner.toml
      ck "tauri: init left a clean tree" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ]
      gates "$D" "tauri/guided/lanes/solo"
      ck "tauri: the floor ran cargo-audit and npm audit inside the gates" bash -c 'grep -q "^PASS floor cargo-audit" "$1" && grep -q "^PASS floor npm-audit" "$1"' _ "$GATES_FILE"
      # SEC-003 is fixed since the 2026-10-04 re-pin (no unic-* crate left), so only SEC-001 and SEC-002 suppress.
      ck "tauri: the floor summary lists the skeleton's suppressions with SEC-001 and SEC-002" python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); assert sorted({x["sec"] for x in s["suppressions"]}) == ["SEC-001", "SEC-002"] and not s["suppression_errors"], s' "$D/.specflow/floor-summary.json"
      ck "tauri: release-tauri.sh builds the dmg" bash -c "cd '$D' && SOURCE_DATE_EPOCH=1791158400 VERSION=0.1.0 DIST_DIR='$WORK/dist-tauri' bash scripts/release-tauri.sh"
      ck "tauri: the manifest (schema 2) lists the source archive and exactly one .dmg bundle, each verifying" manifest "$WORK/dist-tauri" 0.1.0 .dmg
      ck "tauri: SPECFLOW_SMOKE=1 start-up exits 0 within 60 s" run_within 60 env SPECFLOW_SMOKE=1 "${CARGO_TARGET_DIR:-$D/src-tauri/target}/release/habit_tracker"
      ck "tauri: gates and release leave the tree clean" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ] ;;
    flutter)   # macOS (REQ-360): engineer flags — the multi-platform pack's macOS build end to end
      D="$WORK/acme-notes"; copy_template "$D"
      ck "flutter: init with flags" bash -c "cd '$D' && bash scripts/init-project.sh --name 'Acme Notes' --stack flutter --profile engineer --path regulated --solo false </dev/null"
      ck "flutter: pubspec.lock, osv list, Podfile and plugin registrant committed" git -C "$D" ls-files --error-unmatch pubspec.lock osv-scanner.toml macos/Podfile macos/Flutter/GeneratedPluginRegistrant.swift
      FROOT=$(flutter --version --machine 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["flutterRoot"])' 2>/dev/null || true)
      ck "flutter: the package rule refuses every _keywords and _packageDependencies name of the pinned SDK" python3 - "$FROOT/packages/flutter_tools/lib/src/commands/create_base.dart" "$ROOT/stacks/flutter/init.sh" <<'PY'
import os, re, subprocess, sys
src = open(sys.argv[1]).read()
names = []
for var in ("_keywords", "_packageDependencies"):
    names += re.findall(r"'([a-z_]+)'", re.search("const " + var + r" = <String>\{(.*?)\};", src, re.S).group(1))
assert len(names) > 60, names
env = dict(os.environ, SPECFLOW_NAME="X")
bad = [n for n in names if subprocess.run(["bash", sys.argv[2], "package"], env=dict(env, SPECFLOW_PKG=n), capture_output=True).returncode != 2]
assert not bad, f"not refused: {bad}"
PY
      MIN=$(python3 "$D/scripts/lib/specflow/config.py" --file "$D/.specflow/pack.yml" get macos_min 2>/dev/null || true)
      ck "flutter: every MACOSX_DEPLOYMENT_TARGET is the pack minimum ($MIN)" python3 - "$D/macos/Runner.xcodeproj/project.pbxproj" "$MIN" <<'PY'
import re, sys
vals = set(re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);", open(sys.argv[1]).read()))
assert vals == {sys.argv[2]}, vals
PY
      ck "flutter: Podfile platform is the pack minimum" grep -qE "^platform :osx, '$MIN'" "$D/macos/Podfile"
      ck "flutter: release builds arm64 only (Xcode 27 lipo)" grep -qE '^ARCHS = arm64' "$D/macos/Runner/Configs/Release.xcconfig"
      ck "flutter: init left a clean tree" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ]
      gates "$D" "flutter/engineer/regulated/team"
      ck "flutter: the floor ran osv-scanner on pubspec.lock inside the gates" grep -q '^PASS floor osv-scanner \[pubspec.lock\]' "$GATES_FILE"
      ck "flutter: release-flutter.sh zips the app" bash -c "cd '$D' && SOURCE_DATE_EPOCH=1791158400 VERSION=0.1.0 DIST_DIR='$WORK/dist-flutter' bash scripts/release-flutter.sh"
      ck "flutter: the manifest (schema 2) lists the source archive and exactly one .zip bundle, each verifying" manifest "$WORK/dist-flutter" 0.1.0 .zip
      ck "flutter: SPECFLOW_SMOKE=1 start-up exits 0 within 60 s" run_within 60 env SPECFLOW_SMOKE=1 "$D/build/macos/Build/Products/Release/acme_notes.app/Contents/MacOS/acme_notes"
      ck "flutter: gates and release leave the tree clean" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ] ;;
    tauri-release|flutter-release)   # macOS (REQ-352, REQ-390, REQ-386; P6 Task 5.7): the bundle part, then release-smoke.sh on it
      # Covers: REQ-352
      # Covers: REQ-390
      s="${c%-release}"
      if [[ "$s" == tauri ]]; then
        D="$WORK/habit-tracker"; copy_template "$D"
        ck "$s-release: guided init, choice 1" bash -c "cd '$D' && printf '\n\n1\n\n' | bash scripts/init-project.sh"
      else
        D="$WORK/acme-notes"; copy_template "$D"
        ck "$s-release: init with flags" bash -c "cd '$D' && bash scripts/init-project.sh --name 'Acme Notes' --stack flutter --profile engineer --path regulated --solo false </dev/null"
      fi
      # The release action's own preparation (the gates do it in the other cases): the registries, then the offline build.
      if [[ "$s" == tauri ]]; then ck "$s-release: npm ci and cargo fetch --locked (the action's prepare step)" bash -c "cd '$D' && npm ci && cargo fetch --locked --manifest-path src-tauri/Cargo.toml"
      else ck "$s-release: flutter pub get --enforce-lockfile (the action's prepare step)" bash -c "cd '$D' && flutter pub get --enforce-lockfile"; fi
      ck "$s-release: RELEASE_PARTS=bundle builds the bundle" bash -c "cd '$D' && SOURCE_DATE_EPOCH=1791158400 VERSION=0.1.0 DIST_DIR='$WORK/dist-$s-release' RELEASE_PARTS=bundle bash scripts/release-$s.sh"
      ck "$s-release: the manifest's one bundle entry is signed false, reproducible false, and verifies" python3 - "$WORK/dist-$s-release" "$s" <<'PY'
import hashlib, json, os, sys
d, s = sys.argv[1:3]
m = json.load(open(os.path.join(d, "manifest.json")))
arts = m["artifacts"]
assert m["schema"] == "specflow-manifest/2" and len(arts) == 1, m
a = arts[0]
assert a["kind"] == "bundle" and a["signed"] is False and a["reproducible"] is False, a
assert a["filename"].endswith(".dmg" if s == "tauri" else ".zip"), a
p = os.path.join(d, a["filename"])
assert hashlib.sha256(open(p, "rb").read()).hexdigest() == a["sha256"] and os.path.getsize(p) == a["size"], a
PY
      ck "$s-release: the bundle starts with SPECFLOW_SMOKE=1 and exits 0 within 60 s (release-smoke.sh)" bash -c "cd '$D' && bash scripts/release-smoke.sh --stack $s --dist '$WORK/dist-$s-release' --deadline 60"
      ck "$s-release: the run leaves the tree clean" [ -z "$(git -C "$D" status --porcelain 2>/dev/null)" ] ;;
    profiles)   # REQ-360 on ubuntu: the profile dimension for app stacks, no toolchain (SPECFLOW_NO_SCAFFOLD)
      for s in tauri flutter; do
        for p in guided engineer; do
          E="$WORK/prof-$s-$p/acme"; mkdir -p "$(dirname "$E")"; copy_template "$E"
          ck "$s/$p: scaffold-free init" bash -c "cd '$E' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Acme --stack $s --profile $p --path lanes --solo true </dev/null"
        done
        G="$WORK/prof-$s-guided/acme"; N="$WORK/prof-$s-engineer/acme"
        ck "$s: the profiles differ in exactly .specflow.yml, CLAUDE.md and IDEA.md" [ "$(diff -rq -x .git -x __pycache__ "$G" "$N" | sed -E 's#^Files .*/acme/([^ ]+) and .*#\1#' | LC_ALL=C sort | tr '\n' ' ')" = ".specflow.yml CLAUDE.md IDEA.md " ]
        ck "$s: .specflow.yml differs only in profile" [ "$(diff "$G/.specflow.yml" "$N/.specflow.yml" | grep -E '^[<>]' | tr '\n' '|')" = "< profile: guided|> profile: engineer|" ]
        ck "$s: CLAUDE.md differs only in the rendered Profile line (H4)" [ "$(diff "$G/CLAUDE.md" "$N/CLAUDE.md" | grep -E '^[<>]' | cut -c1-13 | tr '\n' '|')" = "< - Profile: |> - Profile: |" ]
        ck "$s: guided IDEA.md records the stack rationale" grep -q '^## Stack' "$G/IDEA.md"
        ck "$s: engineer IDEA.md has no stack rationale" no grep -q '^## Stack' "$N/IDEA.md"
        ck "$s: CLAUDE.md names the stack" grep -q "^- Language: $s" "$G/CLAUDE.md"
        ck "$s: instance CI runs on macos-15" grep -qE '^    runs-on: macos-15' "$G/.github/workflows/ci.yml"
      done ;;
    packfloor)   # opt-in, network (about 15 s): the real floor tools on every pack's shipped lockfiles and ignore files
      miss=""; for t in cargo-audit osv-scanner npm pip-audit; do command -v "$t" >/dev/null 2>&1 || miss="$miss $t"; done
      if [[ -n "$miss" ]]; then fail "packfloor: missing$miss (bash scripts/init-project.sh --doctor --stack tauri)"; else
        TO="$ROOT/stacks/tauri/overlay"; P="$WORK/packfloor"; mkdir -p "$P"; cp -R "$TO/src-tauri" "$TO/package.json" "$TO/package-lock.json" "$P/"
        ign=$(python3 -c 'import sys, tomllib; print(" ".join("--ignore " + i for i in tomllib.load(open(sys.argv[1], "rb"))["advisories"]["ignore"]))' "$TO/src-tauri/audit.toml")
        ck "packfloor: cargo audit --deny warnings on the tauri Cargo.lock with its SEC-cited ignores" bash -c "cd '$P' && cargo audit --deny warnings --file src-tauri/Cargo.lock $ign"
        ck "packfloor: without them cargo audit still finds the advisories (the ignores are live, not stale)" no bash -c "cd '$P' && cargo audit --deny warnings --file src-tauri/Cargo.lock"
        ck "packfloor: osv-scanner on the tauri lockfiles with the overlay config" osv-scanner scan source --config "$TO/osv-scanner.toml" -L "$TO/package-lock.json" -L "$TO/src-tauri/Cargo.lock"
        ck "packfloor: npm audit --audit-level=high on the tauri lockfile" bash -c "cd '$P' && npm audit --audit-level=high"
        ck "packfloor: osv-scanner on the flutter pubspec.lock" osv-scanner scan source --config "$ROOT/stacks/flutter/overlay/osv-scanner.toml" -L "$ROOT/stacks/flutter/overlay/pubspec.lock"
        ck "packfloor: pip-audit --strict on the python skeleton lockfile" pip-audit -r "$ROOT/stacks/python/skeleton/requirements.txt" --strict --disable-pip --progress-spinner off
      fi ;;
    *) fail "unknown FIRST_RUN_CASES entry '$c'" ;;
  esac
done
finish test_first_run
