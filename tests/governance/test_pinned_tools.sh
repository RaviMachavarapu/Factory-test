#!/usr/bin/env bash
# REQ-330 (H3): gitleaks, osv-scanner and Dafny come from release assets whose sha256 the repository pins
# (scripts/pinned-tools.yml, copied from each release's checksum file; Dafny publishes none, so its hash was computed
# from the asset). The installer verifies on every run, cached or not, and installs nothing on a mismatch.
# Covers: REQ-330
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
PIN="$ROOT/scripts/pinned-tools.yml"; INST="$ROOT/scripts/install-pinned-tool.sh"; CFG="$ROOT/scripts/lib/specflow/config.py"
[[ -f "$INST" ]] || { fail "scripts/install-pinned-tool.sh missing"; finish test_pinned_tools; }
get() { python3 "$CFG" --file "$1" get "$2" 2>/dev/null || true; }
ck "gitleaks pinned at 8.30.1 (the version the verifier's findings scan was checked against)" [ "$(get "$PIN" gitleaks_version)" = 8.30.1 ]
ck "osv-scanner pinned at 2.6.0" [ "$(get "$PIN" osv_scanner_version)" = 2.6.0 ]
ck "Dafny pinned at 4.11.0 (ci.yml's version)" [ "$(get "$PIN" dafny_version)" = 4.11.0 ]
for k in gitleaks_sha256_darwin_arm64 gitleaks_sha256_linux_x64 osv_scanner_sha256_darwin_arm64 osv_scanner_sha256_linux_amd64 \
         dafny_sha256_arm64_macos dafny_sha256_x64_ubuntu; do
  ck "pinned-tools.yml: $k is a sha256" bash -c '[[ "$1" =~ ^[0-9a-f]{64}$ ]]' _ "$(get "$PIN" "$k")"
done
ck "Dafny's ubuntu pin is the one ci.yml already verifies" grep -qF "$(get "$PIN" dafny_sha256_x64_ubuntu)" "$ROOT/.github/workflows/ci.yml"
# The 2026-10-04 pin bump (retrospective 2026-10-04-v3-2-closeout.md, Proposed Changes item 1): every workflow that
# installs Dafny from its Linux zip fetches the pinned version's x64-ubuntu-22.04 asset and checks the pinned sha256 —
# ci.yml's two steps and verifier.yml's verify-dafny step never drift from pinned-tools.yml.
dv="$(get "$PIN" dafny_version)"; dsha="$(get "$PIN" dafny_sha256_x64_ubuntu)"
for wf in ci.yml verifier.yml; do
  ck "$wf: every Dafny zip URL is v$dv's x64-ubuntu-22.04 asset, every Dafny checksum the pin" python3 -c 'import re, sys
t = open(sys.argv[1]).read(); v, sha = sys.argv[2], sys.argv[3]
urls = re.findall(r"https://github.com/dafny-lang/dafny/releases/download/\S+", t)
sums = re.findall(r"echo \"([0-9a-f]{64})  \$RUNNER_TEMP/dafny.zip\"", t)
assert urls and len(urls) == len(sums), (urls, sums)
want = "https://github.com/dafny-lang/dafny/releases/download/v%s/dafny-%s-x64-ubuntu-22.04.zip" % (v, v)
assert all(u == want for u in urls), urls
assert all(s == sha for s in sums), sums' "$ROOT/.github/workflows/$wf" "$dv" "$dsha"
done
ck "downloads use curl --proto =https --tlsv1.2 -fsSL" grep -qE "curl --proto '?=https'? --tlsv1\.2 -fsSL" "$INST"

W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
B="$W/bin"; A="$W/assets"; mkdir -p "$B" "$A/pkg"
cat > "$B/curl" <<'EOF'
#!/usr/bin/env bash
# Stub curl: -o FILE URL copies $STUB_ASSETS/<basename of URL> to FILE, or exits 22 (HTTP 404) as curl -f does.
out=""; url=""; prev=""
for a in "$@"; do case "$prev" in -o) out="$a" ;; esac; case "$a" in https://*) url="$a" ;; esac; prev="$a"; done
echo "$url" >> "$STUB_ASSETS/curl.urls"
f="$STUB_ASSETS/$(basename "$url")"; [ -f "$f" ] || exit 22
cp "$f" "$out"
EOF
chmod +x "$B/curl"
printf '#!/bin/sh\necho 8.30.1\n' > "$A/pkg/gitleaks"; chmod +x "$A/pkg/gitleaks"
tar -czf "$A/gitleaks_8.30.1_linux_x64.tar.gz" -C "$A/pkg" gitleaks
printf '#!/bin/sh\necho "osv-scanner version: 2.6.0"\n' > "$A/osv-scanner_linux_amd64"
python3 - "$A/dafny-4.11.0-x64-ubuntu-22.04.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    i = zipfile.ZipInfo("dafny/dafny"); i.external_attr = 0o755 << 16
    z.writestr(i, "#!/bin/sh\necho 4.11.0\n")
PY
sha() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
printf 'gitleaks_version: 8.30.1\ngitleaks_sha256_linux_x64: %s\nosv_scanner_version: 2.6.0\nosv_scanner_sha256_linux_amd64: %s\ndafny_version: 4.11.0\ndafny_sha256_x64_ubuntu: %s\n' \
  "$(sha "$A/gitleaks_8.30.1_linux_x64.tar.gz")" "$(sha "$A/osv-scanner_linux_amd64")" "$(sha "$A/dafny-4.11.0-x64-ubuntu-22.04.zip")" > "$W/pins.yml"
inst() { rc=0; out=$(PATH="$B:$PATH" STUB_ASSETS="$A" SPECFLOW_TOOL_OS="${OS:-Linux}" SPECFLOW_TOOL_ARCH="${ARCH:-x86_64}" \
  bash "$INST" --pins "$W/pins.yml" --cache "$W/cache" --dest "$W/dest" "$@" 2>&1) || rc=$?; }
inst gitleaks osv-scanner dafny
ck "installs all three: exit 0" [ "$rc" = 0 ]
ck "gitleaks from its release URL for linux x64" grep -qxF 'https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz' "$A/curl.urls"
ck "osv-scanner from its release URL for linux amd64" grep -qxF 'https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_linux_amd64' "$A/curl.urls"
ck "Dafny from its release URL for ubuntu x64" grep -qxF 'https://github.com/dafny-lang/dafny/releases/download/v4.11.0/dafny-4.11.0-x64-ubuntu-22.04.zip' "$A/curl.urls"
ck "installed binaries are executable and report the pinned versions" \
  bash -c '[ "$("$1/gitleaks")" = 8.30.1 ] && "$1/osv-scanner" | grep -q 2.6.0 && [ "$("$1/dafny/dafny")" = 4.11.0 ]' _ "$W/dest"
# Dafny 4.10 renamed the release assets (macOS 13 and Ubuntu 22.04 builds): on Apple silicon the installer fetches
# dafny-<version>-arm64-macos-13.zip and checks it against dafny_sha256_arm64_macos.
python3 - "$A/dafny-4.11.0-arm64-macos-13.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    i = zipfile.ZipInfo("dafny/dafny"); i.external_attr = 0o755 << 16
    z.writestr(i, "#!/bin/sh\necho 4.11.0 arm64\n")
PY
printf 'dafny_version: 4.11.0\ndafny_sha256_arm64_macos: %s\n' "$(sha "$A/dafny-4.11.0-arm64-macos-13.zip")" > "$W/pins-mac.yml"
rm -f "$A/curl.urls"; rc=0; out=$(PATH="$B:$PATH" STUB_ASSETS="$A" SPECFLOW_TOOL_OS=Darwin SPECFLOW_TOOL_ARCH=arm64 \
  bash "$INST" --pins "$W/pins-mac.yml" --cache "$W/cache-mac" --dest "$W/dest-mac" dafny 2>&1) || rc=$?
ck "Darwin/arm64: Dafny from its release URL for arm64-macos-13, verified, installed" \
  bash -c '[ "$1" = 0 ] && grep -qxF "https://github.com/dafny-lang/dafny/releases/download/v4.11.0/dafny-4.11.0-arm64-macos-13.zip" "$2" && [ "$("$3/dafny/dafny")" = "4.11.0 arm64" ]' _ "$rc" "$A/curl.urls" "$W/dest-mac"
rm -f "$A/curl.urls"; inst gitleaks
ck "a cached, verified asset is reused (no download)" bash -c '[ "$1" = 0 ] && [ ! -e "$2" ]' _ "$rc" "$A/curl.urls"
printf 'tampered\n' >> "$W/cache/gitleaks_8.30.1_linux_x64.tar.gz"; rm -rf "$W/dest"; inst gitleaks
ck "a tampered cached asset is discarded and fetched again (verified on every run)" bash -c '[ "$1" = 0 ] && [ -s "$2" ] && [ -x "$3/gitleaks" ]' _ "$rc" "$A/curl.urls" "$W/dest"
printf 'x\n' >> "$A/osv-scanner_linux_amd64"; rm -rf "$W/cache" "$W/dest"; inst osv-scanner
ck "a download whose sha256 differs from the pin: exit 1, 'checksum mismatch', nothing installed" \
  bash -c '[ "$1" = 1 ] && grep -qi "checksum mismatch" <<<"$2" && [ ! -e "$3/osv-scanner" ]' _ "$rc" "$out" "$W/dest"
rm "$A/gitleaks_8.30.1_linux_x64.tar.gz"; rm -rf "$W/cache"; inst gitleaks
ck "a failed download (HTTP 404): exit 1" [ "$rc" = 1 ]
inst trivy
ck "an unknown tool: usage error (exit 2)" [ "$rc" = 2 ]
OS=Darwin ARCH=x86_64 inst gitleaks
ck "no pinned asset for this platform (Intel macOS): exit 3, naming brew as the version-only fallback" bash -c '[ "$1" = 3 ] && grep -qF "brew install gitleaks" <<<"$2"' _ "$rc" "$out"
# P4 final review: a checksum-matching asset that will not extract, or a DEST that cannot be written, is exit 1 with
# no 'installed' line — an older binary already at DEST must never be logged as the pinned install.
A2="$W/assets2"; mkdir -p "$A2"
printf 'not a tarball\n' > "$A2/gitleaks_8.30.1_linux_x64.tar.gz"; printf 'not a zip\n' > "$A2/dafny-4.11.0-x64-ubuntu-22.04.zip"
cp "$A/osv-scanner_linux_amd64" "$A2/osv-scanner_linux_amd64" 2>/dev/null || printf '#!/bin/sh\necho "osv-scanner version: 2.6.0"\n' > "$A2/osv-scanner_linux_amd64"
printf 'gitleaks_version: 8.30.1\ngitleaks_sha256_linux_x64: %s\nosv_scanner_version: 2.6.0\nosv_scanner_sha256_linux_amd64: %s\ndafny_version: 4.11.0\ndafny_sha256_x64_ubuntu: %s\n' \
  "$(sha "$A2/gitleaks_8.30.1_linux_x64.tar.gz")" "$(sha "$A2/osv-scanner_linux_amd64")" "$(sha "$A2/dafny-4.11.0-x64-ubuntu-22.04.zip")" > "$W/pins2.yml"
inst2() { rc=0; out=$(PATH="$B:$PATH" STUB_ASSETS="$A2" SPECFLOW_TOOL_OS=Linux SPECFLOW_TOOL_ARCH=x86_64 \
  bash "$INST" --pins "$W/pins2.yml" --cache "$W/cache2" --dest "${DEST2:-$W/dest2}" "$@" 2>&1) || rc=$?; }
mkdir -p "$W/dest2"; printf '#!/bin/sh\necho 8.0.0\n' > "$W/dest2/gitleaks"; chmod +x "$W/dest2/gitleaks"
inst2 gitleaks
ck "a checksum-matching gitleaks archive that will not extract: exit 1, no 'installed' line" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^installed" <<<"$2"' _ "$rc" "$out"
inst2 dafny
ck "a checksum-matching Dafny zip that will not extract: exit 1, no 'installed' line" \
  bash -c '[ "$1" = 1 ] && ! grep -q "^installed" <<<"$2"' _ "$rc" "$out"
: > "$W/notadir"; DEST2="$W/notadir/sub" inst2 osv-scanner
ck "a DEST that cannot be created: exit 1, no 'installed' line" bash -c '[ "$1" = 1 ] && ! grep -q "^installed" <<<"$2"' _ "$rc" "$out"
if [[ "${PINNED_TOOLS_LIVE:-0}" == 1 ]]; then   # opt-in, network, about 5 s: the pins equal the published checksum files
  gl=$(curl --proto '=https' --tlsv1.2 -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt)
  os=$(curl --proto '=https' --tlsv1.2 -fsSL https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_SHA256SUMS)
  ck "live: gitleaks linux x64 pin = release checksum" grep -qF "$(get "$PIN" gitleaks_sha256_linux_x64)  gitleaks_8.30.1_linux_x64.tar.gz" <<<"$gl"
  ck "live: gitleaks darwin arm64 pin = release checksum" grep -qF "$(get "$PIN" gitleaks_sha256_darwin_arm64)  gitleaks_8.30.1_darwin_arm64.tar.gz" <<<"$gl"
  ck "live: osv-scanner linux amd64 pin = release checksum" grep -qF "$(get "$PIN" osv_scanner_sha256_linux_amd64)  osv-scanner_linux_amd64" <<<"$os"
  ck "live: osv-scanner darwin arm64 pin = release checksum" grep -qF "$(get "$PIN" osv_scanner_sha256_darwin_arm64)  osv-scanner_darwin_arm64" <<<"$os"
else
  echo "SKIP: live checksum comparison (PINNED_TOOLS_LIVE=1 compares the pins with each release's checksum file)"
fi
# PR #36 second run, low (REQ-330): install_dafny extracts with unzip -o into --dest only after fetch_verified has
# checked the pinned sha256 — a comment says so, and the order holds.
ck "install_dafny: fetch_verified precedes unzip -o, and a comment says the overwrite is safe only after the checksum" python3 -c 'import sys
t = open(sys.argv[1]).read()
body = t[t.index("install_dafny() {"):]
body = body[:body.index("\n}\n")]
fv, uz = body.index("fetch_verified "), body.index("unzip -q -o")
assert fv < uz, (fv, uz)
comments = " ".join(l.strip().lstrip("#").strip() for l in body.splitlines() if l.strip().startswith("#"))
assert "unzip -o" in comments and "checksum" in comments and "verified first" in comments, comments' "$ROOT/scripts/install-pinned-tool.sh"
finish test_pinned_tools
