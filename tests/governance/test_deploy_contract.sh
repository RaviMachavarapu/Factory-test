#!/usr/bin/env bash
# REQ-351: scripts/deploy-<env>.sh — generated from the python pack — defines migrate, deploy, smoke and rollback; sourced
# with DRY_RUN=1 it only prints what it would run; each function exits non-zero when its underlying command is stubbed to
# fail. The shipped environment is deploy-local.sh (the GHCR image run with docker, by digest); release.yml and the
# python release action never run a deploy script. Every script runs under a PATH of stubs and a fixed allowlist, and
# only the shipped one's failure paths run (dfe-5).
# Covers: REQ-351
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
shopt -s nullglob
if instance; then scripts=(scripts/deploy-*.sh); else scripts=(stacks/python/deploy.sh); fi
shopt -u nullglob
# The stub docker: records every call; docker inspect answers the running container's version label (STUB_DEPLOYED, or
# fails when it is empty). The stub gh: release download v<X> serves $W/rel/v<X>.json as that Release's manifest.json.
mkdir -p "$W/bin" "$W/rel"
cat > "$W/bin/docker" <<EOF2
#!/usr/bin/env bash
echo "docker \$*" >> "$W/docker.argv"
[ "\${STUB_DOCKER_RC:-0}" = 0 ] || exit "\$STUB_DOCKER_RC"
if [ "\$1" = inspect ]; then [ -n "\${STUB_DEPLOYED:-}" ] || { echo "Error: No such object" >&2; exit 1; }; echo "\$STUB_DEPLOYED"; fi
exit 0
EOF2
cat > "$W/bin/gh" <<EOF2
#!/usr/bin/env bash
echo "gh \$*" >> "$W/gh.argv"
[ "\$1 \$2" = "release download" ] || exit 64
f="$W/rel/\$3.json"; [ -f "\$f" ] || { echo "release not found" >&2; exit 1; }
d=.; prev=""; for a in "\$@"; do [ "\$prev" = --dir ] && d="\$a"; prev="\$a"; done; cat "\$f" > "\$d/manifest.json"
EOF2
chmod +x "$W/bin/docker" "$W/bin/gh"
dg() { printf 'sha256:%064d' 0 | sed "s/0/$1/g"; }   # dg HEXCHAR — a sha256:<64 hex> made of one character
for v in 0.9.0:9 1.0.0:a 1.1.0:b; do printf '{"image": {"digest": "%s"}}\n' "$(dg "${v#*:}")" > "$W/rel/v${v%%:*}.json"; done
# A user's real environment (a fixture): scripts/deploy-staging.sh reaching the environment with ssh. The machine running
# the gates has ssh on its PATH (the sentinel in $W/host); the gates must never run it.
mkdir -p "$W/host" "$W/fx"; printf '#!/usr/bin/env bash\necho "ssh $*" >> "%s/ssh.argv"\n' "$W" > "$W/host/ssh"; chmod +x "$W/host/ssh"
cat > "$W/fx/deploy-staging.sh" <<'EOF2'
#!/usr/bin/env bash
run() { echo "+ $*" >&2; if [[ "${DRY_RUN:-}" == "1" ]]; then return 0; fi; "$@"; }
migrate() { run ssh staging migrate; }
deploy() { run ssh staging "deploy $1"; }
smoke() { run ssh staging smoke; }
rollback() { run ssh staging rollback; }
EOF2
PATH="$W/host:$PATH"; export PATH
G="$W/repo"; git init -q -b main "$G"; (cd "$G" && echo a > f && git add -A && git commit -qm a && git tag -a v0.9.0 -m a && git commit -q --allow-empty -m b && git tag -a v1.0.0 -m b \
  && git commit -q --allow-empty -m c && git tag -a v1.1.0 -m c && git tag -a v1.2.0-rc1 -m rc && git tag -a v2.0.0-demo -m demo && git tag -a v0.0.1-demo -m demo)
# Final review, finding 3 (REQ-351; art-threat-driven-security, dfe-5): every deploy script runs under a PATH of the
# stubs and a fixed allowlist (bash, sh, git and the coreutils the contract uses) — never the host's PATH, where a real
# environment's ssh, kubectl or psql lives; and the failure paths (no DRY_RUN) run only on the shipped deploy-local.sh
# (the template's stacks/python/deploy.sh): another scripts/deploy-<env>.sh is only sourced with DRY_RUN=1.
mkdir -p "$W/safe"
for c in bash sh git sed awk head tail tr cat sort grep cut dirname basename mktemp rm env python3; do
  p=$(command -v "$c" 2>/dev/null) && [ -n "$p" ] && [ "${p#/}" != "$p" ] && ln -sf "$p" "$W/safe/$c"
done
SP="$W/bin:$W/safe"
contract() {  # contract FILE LABEL SHIPPED(0|1)
  local s="$1" l="$2" fns out fn
  fns=$(PATH="$SP" DRY_RUN=1 "$W/safe/bash" -c "source '$s' && declare -F" 2>/dev/null || true)
  for fn in migrate deploy smoke rollback; do ck "$l defines $fn" grep -q " $fn\$" <<<"$fns"; done
  : > "$W/docker.argv"
  out=$(cd "$G" && PATH="$SP" DRY_RUN=1 DEPLOY_IMAGE=ghcr.io/o/r "$W/safe/bash" -c "source '$s' && deploy 1.0.0" 2>&1 || true)
  ck "$l: DRY_RUN=1 deploy 1.0.0 prints its commands (+ …) and runs none" bash -c 'grep -q "^+ " <<<"$1" && [ ! -s "$2" ]' _ "$out" "$W/docker.argv"
  [ "$3" = 1 ] || return 0
  D1=$(dg a); D0=$(dg 9); DB=$(dg b); DE=$(dg e)
  dr() { out=$(cd "$G" && PATH="$SP" DRY_RUN=1 DEPLOY_IMAGE=ghcr.io/o/r "$@" "$W/safe/bash" -c "source '$s' && $DEPLOY_CALL" 2>&1) || true; }
  DEPLOY_CALL="deploy 1.0.0" dr
  # Fix wave 1, item 4 (REQ-351; dfe-5): the image runs by digest — v<version>'s image.digest from its Release's
  # manifest.json (or DEPLOY_DIGEST) — never by the mutable tag; DRY_RUN=1 prints every command, docker rm included.
  ck "$l: DRY_RUN=1 deploy 1.0.0 reads v1.0.0's Release manifest.json and pulls and runs the image by that digest" \
    bash -c 'grep -qF "+ gh release download v1.0.0 --pattern manifest.json" <<<"$1" && grep -qxF "+ docker pull ghcr.io/o/r@$2" <<<"$1" && grep -qE "^\+ docker run -d --rm --name [^ ]+ ghcr.io/o/r@$2\$" <<<"$1"' _ "$out" "$D1"
  ck "$l: …never by the mutable tag (no ghcr.io/o/r:1.0.0 anywhere)" no grep -qF "ghcr.io/o/r:1.0.0" <<<"$out"
  ck "$l: …and DRY_RUN=1 prints docker rm -f too (no swallowed trace)" grep -qE "^\+ docker rm -f [^ ]+$" <<<"$out"
  DEPLOY_CALL="deploy 1.0.0" dr env DEPLOY_DIGEST="$DE"
  ck "$l: DEPLOY_DIGEST overrides the Release's manifest (no gh call)" bash -c 'grep -qxF "+ docker pull ghcr.io/o/r@$2" <<<"$1" && ! grep -q "gh release" <<<"$1"' _ "$out" "$DE"
  : > "$W/docker.argv"; rc=0; (cd "$G" && PATH="$SP" DEPLOY_IMAGE=ghcr.io/o/r DEPLOY_DIGEST="sha256:abc" "$W/safe/bash" -c "source '$s' && deploy 1.0.0") >/dev/null 2>&1 || rc=$?
  ck "$l: a DEPLOY_DIGEST that is not sha256:<64 hex> — non-zero, docker never run" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$W/docker.argv"
  printf '{"image": {"digest": "sha256:short"}}\n' > "$W/rel/v0.8.0.json"; : > "$W/docker.argv"; rc=0
  (cd "$G" && PATH="$SP" DEPLOY_IMAGE=ghcr.io/o/r "$W/safe/bash" -c "source '$s' && deploy 0.8.0") >/dev/null 2>&1 || rc=$?
  ck "$l: a Release manifest whose image.digest is not sha256:<64 hex> — non-zero, docker never run" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$W/docker.argv"
  : > "$W/docker.argv"; rc=0; (cd "$G" && PATH="$SP" DEPLOY_IMAGE=ghcr.io/o/r "$W/safe/bash" -c "source '$s' && deploy '1.0.0;x'") >/dev/null 2>&1 || rc=$?
  ck "$l: a version that is not X.Y.Z — non-zero, docker never run" bash -c '[ "$1" != 0 ] && [ ! -s "$2" ]' _ "$rc" "$W/docker.argv"
  DEPLOY_CALL="deploy 1.0.0" dr env DEPLOY_RUN_ARGS="-p 8080:8080 --read-only"
  ck "$l: DEPLOY_RUN_ARGS reaches docker run, before the image" grep -qE "^\+ docker run -d --rm --name [^ ]+ -p 8080:8080 --read-only ghcr.io/o/r@$D1$" <<<"$out"
  DEPLOY_CALL="smoke" dr
  ck "$l: smoke runs the newest vX.Y.Z release (1.1.0 — never v2.0.0-demo or v1.2.0-rc1) by digest with SPECFLOW_SMOKE=1" \
    grep -qE "^\+ docker run --rm --name [^ ]+ -e SPECFLOW_SMOKE=1 ghcr.io/o/r@$DB$" <<<"$out"
  # Fix wave 1, item 4 (c) (REQ-351): rollback deploys the release before the one running now — the running container's
  # org.opencontainers.image.version label (release-image.sh build sets it) — not the second-newest tag.
  DEPLOY_CALL="rollback" dr env STUB_DEPLOYED=1.0.0
  ck "$l: rollback with 1.0.0 running redeploys 0.9.0 (the release before it), by digest" \
    bash -c 'grep -qxF "+ docker pull ghcr.io/o/r@$2" <<<"$1" && grep -qF "org.opencontainers.image.version" <<<"$1"' _ "$out" "$D0"
  DEPLOY_CALL="rollback" dr env STUB_DEPLOYED=1.1.0
  ck "$l: rollback with 1.1.0 running redeploys 1.0.0" grep -qxF "+ docker pull ghcr.io/o/r@$D1" <<<"$out"
  DEPLOY_CALL="rollback" dr env STUB_DEPLOYED=1.1.0 DEPLOY_DIGEST="$DE"
  ck "$l: rollback never takes DEPLOY_DIGEST (it names the version being deployed, not the one before)" grep -qxF "+ docker pull ghcr.io/o/r@$D1" <<<"$out"
  # P7 R8 (REQ-351; PR #57 verifier run 1, finding 5): stop-then-start stays; with nothing running, rollback names the
  # recovery — a deploy of an earlier release by its version.
  # Covers: REQ-351
  DEPLOY_CALL="rollback" dr env STUB_DEPLOYED=""
  ck "$l: rollback with nothing running names the recovery, deploy <X.Y.Z> of an earlier release" \
    grep -qF "deploy an earlier release by hand: scripts/deploy-local.sh deploy <X.Y.Z>" <<<"$out"
  for dep in 0.9.0 "" "<no value>"; do
    : > "$W/docker.argv"; rc=0; (cd "$G" && PATH="$SP" STUB_DEPLOYED="$dep" DEPLOY_IMAGE=ghcr.io/o/r "$W/safe/bash" -c "source '$s' && rollback") >/dev/null 2>&1 || rc=$?
    ck "$l: rollback with '${dep:-nothing}' running (no earlier release, nothing deployed, no label) — non-zero, nothing pulled" \
      bash -c '[ "$1" != 0 ] && ! grep -q "^docker pull" "$2"' _ "$rc" "$W/docker.argv"
  done
  ck "$l: sourcing it leaves the caller's shell options alone (no errexit, nounset or pipefail)" \
    bash -c 'o=$(PATH="$2" "$3" -c "source \"$1\"; echo \"\$-\"; set -o | grep -E \"^pipefail\"") && ! head -n 1 <<<"$o" | grep -qE "[eu]" && grep -qE "pipefail[[:space:]]+off" <<<"$o"' _ "$s" "$SP" "$W/safe/bash"
  for fn in migrate "deploy 1.0.0" smoke rollback; do
    ck "$l: $fn exits non-zero when its underlying command fails" \
      bash -c 'cd "$4" && ! PATH="$3" STUB_DOCKER_RC=1 STUB_DEPLOYED=1.0.0 DEPLOY_MIGRATE_CMD=false DEPLOY_IMAGE=ghcr.io/o/r "$5" -c "source \"$1\" && $2" >/dev/null 2>&1' _ "$s" "$fn" "$SP" "$G" "$W/safe/bash"
  done
  ck "$l no longer says the contract lands later" no grep -qiE 'contract lands in P6|_deploy_stub' "$s"
}
for s in ${scripts[@]+"${scripts[@]}"}; do
  case "$s" in stacks/python/deploy.sh|scripts/deploy-local.sh) sh=1 ;; *) sh=0 ;; esac
  contract "$ROOT/$s" "$s" "$sh"
done
contract "$W/fx/deploy-staging.sh" "a user's scripts/deploy-staging.sh (fixture)" 0
ck "a deploy-<env>.sh's real commands (ssh here) are never run by the gates" [ ! -s "$W/ssh.argv" ]
ck "…even without DRY_RUN, under the gates' PATH a deploy script cannot reach the host's ssh" \
  bash -c 'cd "$3" && PATH="$2" "$4" -c "source \"$1\" && migrate" >/dev/null 2>&1; [ ! -s "$5" ]' _ "$W/fx/deploy-staging.sh" "$SP" "$G" "$W/safe/bash" "$W/ssh.argv"
ck "…the sentinel is live: on the host's PATH the same call reaches it" \
  bash -c 'cd "$3" && "$4" -c "source \"$1\" && migrate" >/dev/null 2>&1; grep -qx "ssh staging migrate" "$2"' _ "$W/fx/deploy-staging.sh" "$W/ssh.argv" "$G" "$W/safe/bash"
if ! instance; then
  ck "the template source tests the python pack's deploy script" [ "${#scripts[@]}" = 1 ]
fi
# Fix wave 1, item 4 (REQ-351; dfe-5): nor does the python release action (an instance's .github/actions/release) or
# release-image.sh; and a python instance without its deploy-local.sh FAILs here — the contract is never vacuous.
if instance; then PA="$ROOT/.github/actions/release/action.yml"; else PA="$ROOT/stacks/python/release/action.yml"; fi
for f in "$ROOT/.github/workflows/release.yml" "$PA" "$ROOT/scripts/release-image.sh"; do
  ck "${f#$ROOT/} never runs a deploy script (REQ-351)" bash -c '! test -f "$1" || ! grep -qE "deploy(-[a-z]+)?\.sh" "$1"' _ "$f"
done
if instance && [ "$(python3 "$ROOT/scripts/lib/specflow/packinfo.py" --root "$ROOT" stack 2>/dev/null)" = python ]; then
  ck "a python instance ships scripts/deploy-local.sh, and this test ran it" bash -c '[ -f "$1/scripts/deploy-local.sh" ] && printf "%s\n" "${@:2}" | grep -qx scripts/deploy-local.sh' _ "$ROOT" ${scripts[@]+"${scripts[@]}"}
fi
if ! instance; then
  ck "README: the python deploy subsection, at the end of ### Python — deploy-local.sh, deploy-<env>.sh, a GitHub Environment with required reviewers, never in release.yml" \
    bash -c 'b=$(awk "/^#### Deploying a python instance\$/{f=1} f" "$1" | tr "\n" " "); for w in "deploy-local.sh" "deploy-<env>.sh" "GitHub Environment" "required reviewers" "never runs a deploy script" "by digest" "DEPLOY_DIGEST" "DEPLOY_RUN_ARGS" "org.opencontainers.image.version" "the release before"; do grep -qF -- "$w" <<<"$b" || exit 1; done; [ "$(grep -n "^#### Deploying a python instance$" "$1" | cut -d: -f1)" -gt "$(grep -n "^### Python$" "$1" | cut -d: -f1)" ]' _ "$ROOT/README.md"
fi
finish test_deploy_contract
