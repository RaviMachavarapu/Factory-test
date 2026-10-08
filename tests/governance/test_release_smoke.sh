#!/usr/bin/env bash
# REQ-390 (P6 R19, R35): release-smoke.sh starts what a release built, with SPECFLOW_SMOKE=1, and fails unless it exits 0
# within the deadline (60 s by default) — the template's source archive (extracted: bash -n the scripts, parse the
# modules, next.sh --help) in the default gates; the image (stub docker), the dmg (stub hdiutil, detached on every exit)
# and the zipped .app (stub ditto) here, and for real only in the opt-in runs (Tasks 4.3, 5.7); the app runs in its own
# process group, killed whole, so no helper it spawned outlives the smoke. No coreutils timeout: the script's own
# deadline loop, as on macos-15.
# Covers: REQ-390
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
SM="$ROOT/scripts/release-smoke.sh"
sm() { rc=0; out=$(bash "$SM" "$@" 2>&1) || rc=$?; }
mkdir -p "$W/dist"
if instance; then
  echo "SKIP: the template's archive smoke needs scripts/release-template.sh, which init removes (the python, deadline and usage checks below still run)"
else
  R="$W/r"; mkdir -p "$R"
  (cd "$R" && git init -q -b main && cp -R "$ROOT/scripts" . && find scripts -name __pycache__ -prune -exec rm -rf {} + && git add -A && git commit -qm base)
  (cd "$R" && SOURCE_DATE_EPOCH=1791158400 VERSION=1.0.0 DIST_DIR="$W/dist" bash scripts/release-template.sh) >/dev/null
  sm --stack template --dist "$W/dist"
  ck "template: the extracted archive passes its self-check within 60 s (exit 0)" bash -c '[ "$1" = 0 ] && grep -qF "smoke: template ok" <<<"$2"' _ "$rc" "$out"
  python3 - "$W/dist/specflow-factory-1.0.0-source.tar" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "a") as t:
    data = b"if then fi\n"; i = tarfile.TarInfo("specflow-factory-1.0.0/scripts/broken.sh"); i.size = len(data)
    t.addfile(i, io.BytesIO(data))
PY
  sm --stack template --dist "$W/dist"
  ck "template: a script that does not parse fails the smoke, naming it" bash -c '[ "$1" != 0 ] && grep -qF "broken.sh" <<<"$2"' _ "$rc" "$out"
  D="$W/inst"; copy_template "$D"
  ck "init (scaffold-free) exits 0" bash -c "cd '$D' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Smk --profile engineer --stack python </dev/null >/dev/null 2>&1"
  ck "this test passes inside that instance — the template part SKIPs, the stack-agnostic checks run (F3, F16)" \
    bash -c 'cd "$1" && bash tests/governance/test_release_smoke.sh >/dev/null 2>&1' _ "$D"
fi
mkdir -p "$W/bin"
# Fix wave 1, item 8 (REQ-390; P6 R19): the smoke runs the image offline and never pulls — SPECFLOW_SMOKE needs no
# network, and a missing local tag must not fetch another image from Docker Hub; the stub refuses a run without both.
printf '#!/usr/bin/env bash\necho "docker $*" >> "%s/docker.argv"\n[ "$1" = run ] || exit 0\ncase " $* " in *" --network none "*) ;; *) exit 98 ;; esac\ncase " $* " in *" --pull never "*) ;; *) exit 97 ;; esac\n[ "${STUB_SLEEP:-0}" = 0 ] || sleep "$STUB_SLEEP"\nexit "${STUB_RC:-0}"\n' "$W" > "$W/bin/docker"
chmod +x "$W/bin/docker"
PATH="$W/bin:$PATH" sm --stack python --dist "$W/dist" --image ghcr.io/o/r:1.0.0
ck "python: runs the image named (--name specflow-smoke-…) with --network none --pull never, --rm and SPECFLOW_SMOKE=1 (exit 0)" \
  bash -c '[ "$1" = 0 ] && grep -qE "^docker run --network none --pull never --name specflow-smoke-[A-Za-z0-9_.-]+ --rm -e SPECFLOW_SMOKE=1 ghcr.io/o/r:1.0.0$" "$2"' _ "$rc" "$W/docker.argv"
STUB_RC=3 PATH="$W/bin:$PATH" sm --stack python --dist "$W/dist" --image ghcr.io/o/r:1.0.0
ck "python: the image's non-zero exit is the smoke's" [ "$rc" = 3 ]
: > "$W/docker.argv"; STUB_SLEEP=6 PATH="$W/bin:$PATH" sm --stack python --dist "$W/dist" --image ghcr.io/o/r:1.0.0 --deadline 2
ck "a run that outlives the deadline is killed: exit 124" [ "$rc" = 124 ]
# Fix wave 1, C (REQ-390): killing the docker CLI does not stop the container — the smoke kills the container by its name
# on overrun and removes it on every exit; the overrun prints a one-line reason.
ck "…the container itself is stopped: docker kill and docker rm -f name the container docker run started" python3 - "$W/docker.argv" <<'PY'
import re, sys
a = open(sys.argv[1]).read().splitlines()
name = next(re.search(r"--name (\S+)", l).group(1) for l in a if l.startswith("docker run "))
assert f"docker kill {name}" in a and f"docker rm -f {name}" in a, a
assert a.index(f"docker kill {name}") > 0, a
PY
ck "…and the overrun prints a one-line reason naming the deadline" bash -c 'grep -qE "^release-smoke: .*did not exit within 2 s" <<<"$1"' _ "$out"
: > "$W/docker.argv"; STUB_SLEEP=0 PATH="$W/bin:$PATH" sm --stack python --dist "$W/dist" --image ghcr.io/o/r:1.0.0
ck "…a normal exit removes the container too (docker rm -f, idempotent after --rm) and kills nothing" \
  bash -c 'grep -q "^docker rm -f specflow-smoke-" "$1" && ! grep -q "^docker kill" "$1"' _ "$W/docker.argv"
ck "release-smoke.sh invokes no coreutils timeout (macos-15 has none; a comment naming it is fine)" python3 - "$SM" <<'PY'
import re, sys
code = [re.sub(r"\s#\s.*$", "", l) for l in open(sys.argv[1]) if not l.lstrip().startswith("#")]
bad = [l for l in code if re.search(r"(^|[;&|(`]|\bthen\b|\bdo\b|\$\()\s*(command\s+)?g?timeout\s+[-0-9]", l)]
assert not bad, bad
PY
sm --stack tauri
ck "usage error (no --dist): exit 2" [ "$rc" = 2 ]
# The app branches (R35: Build 3's, so Build 5 never edits the script): a stub app that spawns a helper and records it.
printf '#!/usr/bin/env bash\nsleep 30 & echo $! > "%s/helper.pid"\n[ "${SPECFLOW_SMOKE:-}" = 1 ] || exit 9\nsleep "${STUB_APP_SLEEP:-0}"\nexit 0\n' "$W" > "$W/app.sh"
cat > "$W/bin/hdiutil" <<'EOF2'
#!/usr/bin/env bash
echo "hdiutil $*" >> "$STUB_DIR/hdiutil.argv"
if [ "$1" = attach ]; then
  mp=""; while [ $# -gt 0 ]; do [ "$1" = -mountpoint ] && mp="$2"; shift; done
  mkdir -p "$mp/Habit.app/Contents/MacOS" && cp "$STUB_DIR/app.sh" "$mp/Habit.app/Contents/MacOS/habit" && chmod +x "$mp/Habit.app/Contents/MacOS/habit"
fi
exit 0
EOF2
cat > "$W/bin/ditto" <<'EOF2'
#!/usr/bin/env bash
echo "ditto $*" >> "$STUB_DIR/ditto.argv"
d="${@: -1}"; mkdir -p "$d/Habit.app/Contents/MacOS" && cp "$STUB_DIR/app.sh" "$d/Habit.app/Contents/MacOS/habit" && chmod +x "$d/Habit.app/Contents/MacOS/habit"
EOF2
chmod +x "$W/bin/hdiutil" "$W/bin/ditto"; mkdir -p "$W/tdist" "$W/fdist"; printf x > "$W/tdist/Habit_1.0.0_aarch64.dmg"; printf x > "$W/fdist/habit-1.0.0-macos.zip"
dead() { ! kill -0 "$(cat "$W/helper.pid")" 2>/dev/null; }
: > "$W/hdiutil.argv"; STUB_DIR="$W" PATH="$W/bin:$PATH" sm --stack tauri --dist "$W/tdist"
ck "tauri: the dmg attached read-only, the app run with SPECFLOW_SMOKE=1 (exit 0), the dmg detached" \
  bash -c '[ "$1" = 0 ] && grep -q "^hdiutil attach .*-nobrowse.*-readonly" "$2" && grep -q "^hdiutil detach" "$2"' _ "$rc" "$W/hdiutil.argv"
ck "…the helper the app spawned does not outlive the smoke (its process group is killed)" dead
: > "$W/hdiutil.argv"; STUB_APP_SLEEP=10 STUB_DIR="$W" PATH="$W/bin:$PATH" sm --stack tauri --dist "$W/tdist" --deadline 2
ck "tauri overrun: exit 124, the dmg still detached (the trap), the helper killed with the group" \
  bash -c '[ "$1" = 124 ] && grep -q "^hdiutil detach" "$2"' _ "$rc" "$W/hdiutil.argv"
ck "…the overrun's helper is dead too" dead
: > "$W/ditto.argv"; STUB_DIR="$W" PATH="$W/bin:$PATH" sm --stack flutter --dist "$W/fdist"
ck "flutter: the zip extracted with ditto -x -k, the app run (exit 0), its helper killed" \
  bash -c '[ "$1" = 0 ] && grep -q "^ditto -x -k " "$2"' _ "$rc" "$W/ditto.argv"
ck "…the flutter app's helper is dead" dead
printf x > "$W/tdist/second.dmg"; STUB_DIR="$W" PATH="$W/bin:$PATH" sm --stack tauri --dist "$W/tdist"; rm -f "$W/tdist/second.dmg"
ck "tauri with two dmgs in --dist: exit 2 (which one is the release's?)" [ "$rc" = 2 ]
ck "Glossary Smoke hook: release.yml runs it through release-smoke.sh within 60 seconds; no 'later v3.2 plan'" \
  bash -c 'b=$(awk "\$0==\"### Smoke hook\"{f=1; next} /^### /{f=0} f" "$1" | tr "\n" " "); grep -qF "release-smoke.sh" <<<"$b" && grep -qF "60 seconds" <<<"$b" && ! grep -qF "later v3.2 plan" <<<"$b"' _ "$ROOT/docs/GLOSSARY.md"
ck "Glossary Smoke hook: launchd/XPC helpers are outside the process group (the honest limit); the template's smoke runs now, the image's and the bundle's through Builds 4 and 5's actions" \
  bash -c 'b=$(awk "\$0==\"### Smoke hook\"{f=1; next} /^### /{f=0} f" "$1" | tr "\n" " " | tr -s " "); for w in launchd XPC "outside the process group" "template" "Builds 4 and 5" "docker kill"; do grep -qF "$w" <<<"$b" || { echo "missing $w"; exit 1; }; done' _ "$ROOT/docs/GLOSSARY.md"
finish test_release_smoke
