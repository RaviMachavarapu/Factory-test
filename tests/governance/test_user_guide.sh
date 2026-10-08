#!/usr/bin/env bash
# REQ-308: docs/getting-started.html is the user guide every instance inherits (docs/examples/README.md lists it among
# the inherited documents). It is HTML, so the Markdown document gates never read it; this test pins its claims to the
# code they describe (PR #72 verifier run 1, findings 1, 2 and 5): the seven confirmation points are the kernel's, the
# setup chapter names the push and configure-repo.sh steps init-project.sh prints (init never pushes or protects main),
# the idea headings are templates/IDEA.md's, the stack menu labels are the packs' (template source only), the guide
# states solo mode's limit (the gate is an audit trail the owner can bypass; a free private repository enforces nothing),
# and it carries no home-directory path.
# Covers: REQ-308
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
G="$ROOT/docs/getting-started.html"
ck "the user guide exists" test -f "$G"
ck "the guide names every confirmation point the kernel defines (pipeline.py's CONFIRM_TEXT ids, hyphens as spaces)" python3 - "$ROOT" "$G" <<'PY'
import re, sys
src = open(sys.argv[1] + "/scripts/lib/specflow/pipeline.py").read()
m = re.search(r"CONFIRM_TEXT\s*=\s*\{(.*?)\n\}", src, re.S)
assert m, "CONFIRM_TEXT not found"
ids = re.findall(r'^\s*"([a-z-]+)":', m.group(1), re.M)
assert len(ids) == 7, ids
g = open(sys.argv[2]).read()
for i in ids:
    label = i.replace("-", " ")
    assert re.search(rf"<dt>\s*{re.escape(label)}\s*</dt>", g, re.I), f"missing confirmation point {i!r} as <dt>{label}</dt>"
PY
ck "the setup chapter names the push and configure-repo.sh steps after init (init never pushes or protects main)" \
  bash -c 's=$(awk "/id=\"setup\"/{f=1} /id=\"idea\"/{f=0} f" "$1"); grep -qF "git push -u origin main" <<<"$s" && grep -qF "bash scripts/configure-repo.sh" <<<"$s" && ! grep -qiF "Setup pushes to it" <<<"$s"' _ "$G"
ck "the guide states solo mode's limit: the merge gate is an audit trail the owner can bypass, and a free private repository enforces nothing" \
  bash -c 'grep -qiF "audit trail" "$1" && grep -qiF "free private repository" "$1" && ! grep -qF "It cannot be talked around" "$1"' _ "$G"
ck "the idea chapter uses templates/IDEA.md's headings" python3 - "$ROOT" "$G" <<'PY'
import re, sys
heads = re.findall(r"^## (.+)$", open(sys.argv[1] + "/templates/IDEA.md").read(), re.M)
g = open(sys.argv[2]).read()
for h in heads:
    assert f"## {h}" in g, f"missing idea heading {h!r}"
PY
if ! instance; then
  ck "the stack menu labels are the packs' guided_label values (template source)" python3 - "$ROOT" "$G" <<'PY'
import glob, re, sys
g = open(sys.argv[2]).read()
for p in glob.glob(sys.argv[1] + "/stacks/*/pack.yml"):
    m = re.search(r"^guided_label:\s*(.+)$", open(p).read(), re.M)
    assert m and m.group(1).strip() in g, f"menu label from {p} missing: {m and m.group(1)}"
PY
else
  echo "SKIP (instance: stacks/ is template-only): the stack menu labels"
fi
ck "the guide carries no home-directory path" bash -c '! grep -qE "/(Users|home)/[A-Za-z0-9._-]+/" "$1"' _ "$G"
ck "the README's Quick Start points at the guide before step 0 (setup), not after it" \
  bash -c 'q=$(awk "/^## Quick Start/{f=1; next} /^## /{f=0} f" "$1"); n=$(grep -n "getting-started.html" <<<"$q" | head -1 | cut -d: -f1); z=$(grep -n "^0\\. " <<<"$q" | head -1 | cut -d: -f1); [ -n "$n" ] && [ -n "$z" ] && [ "$n" -lt "$z" ]' _ "$ROOT/README.md"
finish test_user_guide
