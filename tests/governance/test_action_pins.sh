#!/usr/bin/env bash
# REQ-334 (dfe-4): every GitHub Action is pinned to a full commit SHA with a version comment; every workflow has a
# top-level read-only permissions: block, and no job elevates (only release.yml may: publish for contents, image and prune
# for packages — REQ-350, REQ-351, P6 R15; test_release_workflow.sh pins which); Dependabot
# watches pip (scripts/) and github-actions; /retrospective bumps the pinned tool downloads and the pack actions' pins.
# Covers: REQ-334
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
shopt -s nullglob
files=(.github/workflows/*.yml .github/actions/*/action.yml)
if ! instance; then files+=(stacks/*/action.yml stacks/*/release/action.yml); fi
shopt -u nullglob
ck "there are workflow and action files to check (${#files[@]})" [ "${#files[@]}" -gt 2 ]
for f in "${files[@]}"; do
  bad=$(grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:' "$f" | grep -vE 'uses:[[:space:]]+\./' \
        | grep -vE 'uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*[[:space:]]*$' || true)
  ck "$f: every uses: is a 40-hex SHA with a '# vX.Y.Z' comment (or a local ./ action)" [ -z "$bad" ]
  if [ -n "$bad" ]; then printf '    %s\n' "$bad"; fi
done
for wf in .github/workflows/*.yml; do
  ck "$wf: a top-level permissions: block" grep -qE '^permissions:' "$wf"
  top=$(awk '/^permissions:/{f=1; next} f && /^[^ ]/{exit} f' "$wf")
  ck "$wf: top-level permissions are read-only" bash -c 'grep -qE "^permissions:[[:space:]]*(read-all|\{\})?[[:space:]]*$" "$2" && ! grep -qE ":[[:space:]]*write" <<<"$1"' _ "$top" "$wf"
  if [[ "$(basename "$wf")" != release.yml ]]; then
    ck "$wf: no job elevates to write (only release.yml may: publish, image and prune, P6 R15)" no grep -qE '^[[:space:]]+[a-z-]+:[[:space:]]*write' "$wf"
  fi
done
D=.github/dependabot.yml
ck "$D exists" test -f "$D"
ck "$D: version 2" grep -qE '^version:[[:space:]]*2[[:space:]]*$' "$D"
ck "$D: pip for /scripts and github-actions for /" python3 - "$D" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
eco = {}
for b in re.split(r"\n\s*-\s+package-ecosystem:", "\n" + t)[1:]:
    name = b.split("\n", 1)[0].strip().strip('"')
    d = re.search(r'^\s*directory:\s*"?([^"\n]+)"?\s*$', b, re.M)
    eco[name] = d.group(1).strip() if d else None
assert eco.get("pip") == "/scripts" and eco.get("github-actions") == "/", eco
PY
ck "$D: every ecosystem has a schedule" [ "$(grep -cE '^[[:space:]]+interval:' "$D")" -ge 2 ]
R=.claude/commands/retrospective.md
ck "/retrospective bumps scripts/pinned-tools.yml" bash -c 'grep -qF "scripts/pinned-tools.yml" "$1" && grep -qi "bump" "$1"' _ "$R"
ck "/retrospective bumps the pack actions' SHA pins (Dependabot watches only .github/workflows)" grep -qF 'stacks/*/action.yml' "$R"
# Build 5 fix wave 1, F (REQ-334; P6 R35): the app release actions are pack composites too — pinned with a version
# comment here, and bumped by hand by /retrospective (in an instance, .github/actions/release/action.yml, already in the
# .github/actions/*/action.yml glob above).
# Covers: REQ-334
if instance; then echo "SKIP: the pack release actions live in the template source"; else
  ck "the pack release actions are in the pin check's file list (template source)" \
    bash -c '[ "$(printf "%s\n" "$@" | grep -c "^stacks/.*/release/action.yml$")" -ge 2 ]' _ "${files[@]}"
fi
ck "/retrospective bumps the pack release actions' SHA pins (stacks/*/release/action.yml)" grep -qF 'stacks/*/release/action.yml' "$R"
# Every use of one action pins the same SHA everywhere it appears (workflows, .github/actions, and in the template
# source the pack actions), so a bump that reaches only what Dependabot watches (.github/workflows) is caught here
# rather than left to drift until /retrospective (REQ-334, dfe-4; patch/action-bumps, 2026-09-28).
drift=$(python3 - "${files[@]}" <<'PY2'
import re, sys
pins = {}
for f in sys.argv[1:]:
    for m in re.finditer(r"uses:\s+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(?:/[A-Za-z0-9_./-]+)?@([0-9a-f]{40})\s+#\s+(v[0-9.]+)", open(f).read()):
        pins.setdefault(m.group(1), {}).setdefault(m.group(2) + " " + m.group(3), set()).add(f)
for action, by_pin in sorted(pins.items()):
    if len(by_pin) > 1:
        print(action + ": " + "; ".join(pin + " in " + ",".join(sorted(fs)) for pin, fs in sorted(by_pin.items())))
PY2
)
ck "every action is pinned to one SHA across workflows and pack actions (no drift)" [ -z "$drift" ]
if [ -n "$drift" ]; then printf '    %s\n' "$drift"; fi
# patch/pin-bump-2026-11 (REQ-334; retrospective 2026-10-04-v3-2-closeout.md, Proposed Changes item 1): actions/setup-node
# v5 and later cache automatically once package.json names npm as its packageManager; every setup-node step in the
# workflows and pack composites passes package-manager-cache: false, so the bump from v4.4.0 keeps v4's no-cache
# behaviour and no build restores an npm cache it did not ask for.
nocache=$(python3 - "${files[@]}" <<'PY3'
import re, sys
bad = []
for f in sys.argv[1:]:
    lines = open(f).read().splitlines()
    for i, l in enumerate(lines):
        if re.search(r"uses:\s+actions/setup-node@", l):
            ind = len(l) - len(l.lstrip(" -"))
            step = []
            for n in lines[i + 1:]:
                if n.strip() and (len(n) - len(n.lstrip(" ")) < ind or n.lstrip().startswith("- ")):
                    break
                step.append(n)
            if not any(re.match(r"\s+package-manager-cache:\s*false\s*$", s) for s in step):
                bad.append(f"{f}:{i + 1}")
print(" ".join(bad))
PY3
)
ck "every actions/setup-node step sets package-manager-cache: false (v4's behaviour under v5+)" [ -z "$nocache" ]
if [ -n "$nocache" ]; then printf '    %s\n' "$nocache"; fi
finish test_action_pins
