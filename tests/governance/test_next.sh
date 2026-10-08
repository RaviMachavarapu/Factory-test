#!/usr/bin/env bash
# REQ-341 (ADR-003; P5 R7, R8): scripts/next.sh collects the Facts from the tree — the design lane's artifacts by slug,
# tagged REQs and the architecture gate, the plan's "## Build N" sections, the source diff against the base, the ship
# lane's documents by version, the gates only when asked — calls derive, and prints state, next step, notes and --explain
# reasons, or --json. It writes nothing. Without a remote it never calls gh and never proposes creating a PR
# (pr_state_known false). REQ-340: both paths' branches; --path overrides the configured path for one run; a plan's
# "## Build N" sections are numbered from 1 with no gap, and a gap is noted (P5 R6). The seed is synthetic
# (tests/governance/fixtures/next/seed/), so the test runs the same in the template source and in every instance.
# P5 final review: phase/security and phase/release read next_version's documents only; a sec- design slug is unknown.
# Covers: REQ-341
# Covers: REQ-340
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
mkdir -p "$W/bin"; printf '#!/usr/bin/env bash\necho "$*" >> "%s/gh.called"; exit 1\n' "$W" > "$W/bin/gh"; chmod +x "$W/bin/gh"
SEED="$W/seed"; next_seed "$SEED"
repo() {  # repo NAME BRANCH [PATH] — a remote-less clone of the seed on BRANCH (path lanes unless given); sets D
  D="$W/$1"; git clone -q "$SEED" "$D"; git -C "$D" remote remove origin
  if [ "${3:-lanes}" != lanes ]; then
    printf 'profile: engineer\npath: %s\nsolo: true\n' "$3" > "$D/.specflow.yml"; git -C "$D" commit -qam "path $3"
  fi
  if [ "$2" != main ]; then git -C "$D" checkout -q -b "$2"; fi
}
nx() { rc=0; (cd "$D" && PATH="$W/bin:$PATH" next_sh "$@") > "$W/out" 2>&1 || rc=$?; }
has() { grep -qF -- "$1" "$W/out"; }
line() { grep -E "^$1: " "$W/out" || true; }
commit() { git -C "$D" add -A && git -C "$D" commit -qm "$1"; }
DS=docs/specs/2026-09-28-greet; DP=docs/plans/2026-09-28-greet-plan.md
repo main-lanes main; nx
ck "main, no remote, lanes: state none idle" has 'state: none idle'
ck "…next: design/<slug>, then brainstorming (P5 R4)" bash -c 'grep -qF "git checkout -b design/<slug>" <<<"$1" && grep -qF "/superpowers:brainstorming" <<<"$1"' _ "$(line next)"
ck "…says it cannot see PRs, proposes no PR, and never called gh" \
  bash -c 'grep -q "^note: cannot see PRs" "$1" && ! grep -qF "gh pr create" "$1" && [ ! -e "$2" ]' _ "$W/out" "$W/gh.called"
# Round 3b re-review D4 (REQ-341): on main without a remote, --explain says the release facts need the PR state, which
# could not be read — never "not collected here" (they are collected from the PR state when it is readable).
nx --explain
ck "main, no remote, --explain: unbuilt/next_version need the PR state, not readable here; never 'not collected here'" \
  bash -c 'l=$(grep -E "^why: unbuilt, untagged_ship, next_version, ship_phases_merged:" "$1"); grep -qF "the PR state could not be read" <<<"$l" && ! grep -qF "not collected here" "$1"' _ "$W/out"
repo main-reg main regulated; nx
ck "main, no remote, regulated: idle proposes phase/spec-<slug>, then brainstorming" \
  bash -c 'grep -q "^state: none idle" "$1" && grep -F "next: " "$1" | grep -qF "git checkout -b phase/spec-<slug>"' _ "$W/out"
repo design-full design/greet; nx
ck "design lane with every artifact, no remote: open-pr, explained, never gh pr create (NoBlindCreatePr)" \
  bash -c 'grep -q "^state: design open-pr" "$1" && grep -F "next: " "$1" | grep -qF "cannot see PRs" && ! grep -qF "gh pr create" "$1"' _ "$W/out"
before=$(cd "$D" && git status --porcelain --ignored && git for-each-ref)
nx --explain
ck "next.sh writes nothing: no file, index or ref changes (--explain included)" \
  [ "$before" = "$(cd "$D" && git status --porcelain --ignored && git for-each-ref)" ]
ck "--explain gives each fact the design lane read and where it came from" \
  bash -c 'grep -q "^why: .*spec" "$1" && grep -q "^why: .*check-architecture.sh" "$1" && grep -q "^why: .*analyze" "$1"' _ "$W/out"
repo design-noplan design/greet; git -C "$D" rm -q "$DP"; commit "no plan"; nx
ck "…without the plan: design plan, /specflow-plan greet" bash -c 'grep -q "^state: design plan" "$1" && grep -qF "/specflow-plan greet" "$1"' _ "$W/out"
repo design-noov design/greet; git -C "$D" rm -q docs/architecture/2026-09-28-greet-overview.md; commit "no overview"; nx
ck "…a tagged REQ, no overview, the plan present: design architecture (a gate, REQ-320)" \
  bash -c 'grep -q "^state: design architecture" "$1" && grep -qF "/architecture 2026-09-28-greet" "$1"' _ "$W/out"
repo design-bs design/greet; git -C "$D" rm -q "$DS-design.md" "$DP"; commit "brainstorm only"; nx
ck "…the brainstorm alone: design specify" has 'state: design specify'
repo design-none design/greet; git -C "$D" rm -q "$DS-design.md" "$DS-brainstorm.md" "$DP"; commit "nothing"; nx
ck "…nothing: design brainstorm" has 'state: design brainstorm'
repo design-specfirst design/greet; git -C "$D" rm -q "$DS-brainstorm.md" "$DP"; commit "spec, no brainstorm"; nx
ck "…a spec without a brainstorm never sends the user back: design plan (after the last present)" has 'state: design plan'
repo build build/greet-1; nx
ck "build/<slug>-1 and no '## Build 1' in the plan: build unknown-build, explained" \
  bash -c 'grep -q "^state: build unknown-build" "$1" && grep -qF "## Build 1" "$1"' _ "$W/out"
printf '\n## Build 1: greet\n' >> "$D/$DP"; commit "build 1"; nx
ck "…with the section, no source change: build implement" has 'state: build implement'
echo 'X = 1' > "$D/src/greet/extra.py"; commit "source"; nx
ck "…with a source change against main: build open-pr" has 'state: build open-pr'
repo gap build/greet-2; printf '\n## Build 1: a\n\n## Build 3: c\n' >> "$D/$DP"; commit "a gap"; nx
ck "a plan with Build 1 and Build 3: build/<slug>-2 is unknown-build, and a note names the gap (REQ-340: from 1, no gap)" \
  bash -c 'grep -q "^state: build unknown-build" "$1" && grep "^note: " "$1" | grep -qF "numbered from 1 with no gap"' _ "$W/out"
repo ship ship/0.1.0; nx
ck "ship/0.1.0 without security docs: ship security, /security-review 0.1.0" \
  bash -c 'grep -q "^state: ship security" "$1" && grep -qF "/security-review 0.1.0" "$1"' _ "$W/out"
mkdir -p "$D/docs/security"; : > "$D/docs/security/0.1.0-review.md"; : > "$D/docs/security/0.1.0-disposition.md"; commit sec; nx
ck "…with them: ship release, /release 0.1.0" bash -c 'grep -q "^state: ship release" "$1" && grep -qF "/release 0.1.0" "$1"' _ "$W/out"
mkdir -p "$D/docs/releases"; for k in notes migration known-limitations; do : > "$D/docs/releases/0.1.0-$k.md"; done; commit rel; nx
ck "…with the three release docs: ship open-pr" has 'state: ship open-pr'
repo validate phase/validate regulated
printf '#!/usr/bin/env bash\nexit "${STUB_GATES_RC:-0}"\n' > "$D/scripts/run-quality-gates.sh"; commit "stub gates"; nx
ck "phase/validate without --gates: validate gates; next is next.sh --gates" \
  bash -c 'grep -q "^state: validate gates" "$1" && grep -qF "bash scripts/next.sh --gates" "$1"' _ "$W/out"
nx --gates
ck "…--gates runs the gates; green: validate open-pr" has 'state: validate open-pr'
STUB_GATES_RC=1 nx --gates
ck "…red: validate gates" has 'state: validate gates'
repo chore chore/x; nx
ck "chore/x: none unknown-branch" has 'state: none unknown-branch'
repo retro phase/retro-2026-09-28; nx
ck "a retrospective branch: unknown to the kernel, explained as /retrospective (P5 R8)" \
  bash -c 'grep -q "^state: none unknown-branch" "$1" && grep -qF "/retrospective" "$1"' _ "$W/out"
repo js build/greet-1; nx --json
ck "--json: the documented keys; pr_state_known false; null for facts the lane does not read" python3 - "$W/out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
need = {"state", "step", "next_step", "open_lanes", "open_lane_prs", "confirm", "pr_state_known", "path", "profile",
        "facts", "findings", "explain", "notes"}
assert need <= set(d), sorted(need - set(d))
assert d["state"] == {"lane": "build", "phase": "unknown-build"} and d["pr_state_known"] is False and d["open_lanes"] == []
assert d["step"] == {"kind": "ExplainUnknown", "why": "BuildUnknown"} and d["facts"]["has_security_docs"] is None
PY
repo tsrc main; git -C "$D" rm -q .specflow.yml; mkdir -p "$D/stacks/python"; echo 'stack: python' > "$D/stacks/python/pack.yml"; commit "template source"; nx
# P6 Task 5.6 (REQ-341; the hits table): the template note says the factory walks the lanes path from P6.
# Covers: REQ-341
ck "the template source: the defaults apply, and a note says the factory walks the lanes path from P6 (REQ-381)" \
  bash -c 'grep -q "^note: template source" "$1" && grep -qF "the factory walks the lanes path from P6 (REQ-381)" "$1" && grep -qF -- "--path regulated" "$1" && grep -q "^state: none idle" "$1"' _ "$W/out"
nx --path regulated
ck "--path regulated overrides the configured path for one run, and says so" \
  bash -c 'grep -qF "git checkout -b phase/spec-<slug>" "$1" && grep -qF "path regulated (--path)" "$1"' _ "$W/out"
repo badcfg main; printf 'path: sideways\n' > "$D/.specflow.yml"; nx
ck "a path that is neither lanes nor regulated: exit 2, ERROR next" bash -c '[ "$1" = 2 ] && grep -q "^ERROR next" "$2"' _ "$rc" "$W/out"
D="$W/notgit"; mkdir -p "$D/scripts"; cp -R "$ROOT/scripts/next.sh" "$ROOT/scripts/lib" "$D/scripts/"; nx
ck "outside a git repository: exit 2, ERROR next" bash -c '[ "$1" = 2 ] && grep -q "^ERROR next" "$2"' _ "$rc" "$W/out"
# P5 final review (ADR-003: phase/security and phase/release take their version from next_version): a seed holding an
# earlier release's untagged documents (an instance keeps the demo's 0.0.1-demo docs, never its tag) is not the release
# under way — only next_version's documents count, and the step names that version.
demo() {  # demo — the demo release's security and release documents, untagged
  mkdir -p "$D/docs/security" "$D/docs/releases"
  : > "$D/docs/security/0.0.1-demo-review.md"; : > "$D/docs/security/0.0.1-demo-disposition.md"
  for k in notes migration known-limitations; do : > "$D/docs/releases/0.0.1-demo-$k.md"; done; commit demo
}
repo sec phase/security regulated; demo; nx --explain
ck "phase/security with only the untagged demo docs: security security, /security-review 0.1.0 (next_version, no tag yet)" \
  bash -c 'grep -q "^state: security security" "$1" && grep -qxF "next: /security-review 0.1.0" "$1" && grep -q "^why: .*next_version" "$1"' _ "$W/out"
: > "$D/docs/security/0.1.0-review.md"; : > "$D/docs/security/0.1.0-disposition.md"; commit sec010; nx
ck "…with 0.1.0's review and disposition: security open-pr" has 'state: security open-pr'
repo rel phase/release regulated; demo; nx
ck "phase/release with only the untagged demo docs: release release, /release 0.1.0" \
  bash -c 'grep -q "^state: release release" "$1" && grep -qxF "next: /release 0.1.0" "$1"' _ "$W/out"
git -C "$D" tag v0.1.0; nx
ck "…after v0.1.0: the version is 0.2.0" bash -c 'grep -q "^state: release release" "$1" && grep -qxF "next: /release 0.2.0" "$1"' _ "$W/out"
for k in notes migration known-limitations; do : > "$D/docs/releases/0.2.0-$k.md"; done; commit rel020; nx
ck "…with 0.2.0's three release docs: release open-pr" has 'state: release open-pr'
repo secslug design/sec-x; nx
ck "design/sec-x: unknown-branch, explained — a slug starting with sec- would make its build branch build/sec-x-N, the back-edge's name" \
  bash -c 'grep -q "^state: none unknown-branch" "$1" && grep -q "^next: .*sec-" "$1"' _ "$W/out"
# PR #48 verifier low 3 (REQ-341, REQ-308): --json carries the glossary-links line's data as "terms" (each term with its
# docs/GLOSSARY.md anchor, as the text form's terms: line), and "explain" is an array of reasons.
# Covers: REQ-308
repo jt design/greet; nx --json --explain; cp "$W/out" "$W/jt.json"; nx
ck "--json: a terms key with each term and its glossary anchor, the same terms the text form's terms: line links" \
  python3 - "$W/jt.json" "$W/out" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d["terms"], list) and d["terms"], d.get("terms")
assert all(set(t) == {"term", "anchor"} for t in d["terms"]), d["terms"]
line = next(l for l in open(sys.argv[2]) if l.startswith("terms: "))
assert line.strip() == "terms: " + ", ".join(f"{t['term']} (docs/GLOSSARY.md#{t['anchor']})" for t in d["terms"]), line
assert isinstance(d["explain"], list) and all(isinstance(x, str) for x in d["explain"])
PY


# PR #48 CI (REQ-341, REQ-342): ci.yml's gates job exports SPECFLOW_BASE_REF (refs/remotes/origin/<PR base>, the full ref since P6 Build 2) and SPECFLOW_HEAD_BRANCH
# for its gate scripts. /next is a local tool: a SPECFLOW_BASE_REF that is not in this checkout is ignored with a why:
# line, never an error, and SPECFLOW_HEAD_BRANCH never names the branch; an explicit --base that is not here stays one.
# Covers: REQ-341, REQ-342
repo cienv main
nxci() { rc=0; (cd "$D" && export SPECFLOW_BASE_REF=origin/phase/not-in-this-checkout SPECFLOW_HEAD_BRANCH=impl/plan-9-x \
  && PATH="$W/bin:$PATH" bash scripts/next.sh "$@") > "$W/out" 2>&1 || rc=$?; }
nxci --explain
ck "CI's SPECFLOW_BASE_REF not in this checkout: main still derives none idle, exit 0" bash -c '[ "$1" = 0 ] && grep -q "^state: none idle" "$2"' _ "$rc" "$W/out"
ck "…a why: line names the ignored variable and the base used instead" \
  bash -c 'grep -qE "^why: SPECFLOW_BASE_REF=origin/phase/not-in-this-checkout is not in this checkout .*ignored, base main used" "$1" && grep -q "^why: branch main parses as" "$1" && ! grep -qF "impl/plan-9-x" "$1"' _ "$W/out"
nxci --base origin/nope
ck "an explicit --base that is not in this checkout is still an error (exit 2)" \
  bash -c '[ "$1" = 2 ] && grep -qF "ERROR next: base ref origin/nope is not in this checkout" "$2"' _ "$rc" "$W/out"
# Build 2 fix wave 2 (REQ-341; PR #54 verifier run 1, finding 1): ci.yml's gates step now exports SPECFLOW_BASE_REF as
# the full ref refs/remotes/origin/<base> (a tag named origin/<base> shadows the short name). /next stays a local tool on
# the short name, but names the base branch from either form, so a full ref never reaches gh pr create --base or the
# verifier line as "refs/remotes/origin/main".
# Covers: REQ-341
ck "pipeline.base_name: refs/remotes/origin/<b>, origin/<b> and a bare <b> name branch <b>; none names main" python3 - "$ROOT/scripts/lib/specflow" <<'PYN'
import sys; sys.path.insert(0, sys.argv[1]); import pipeline as p
for ref, want in (("refs/remotes/origin/main", "main"), ("refs/remotes/origin/phase/x", "phase/x"), ("origin/main", "main"),
                  ("origin/phase/x", "phase/x"), ("main", "main"), (None, "main"), ("", "main")):
    got = p.base_name(ref)
    assert got == want, (ref, got, want)
PYN
repo cienv-full main
(cd "$D" && git update-ref refs/remotes/origin/main HEAD)
rc=0; (cd "$D" && export SPECFLOW_BASE_REF=refs/remotes/origin/main && PATH="$W/bin:$PATH" bash scripts/next.sh --explain) > "$W/out" 2>&1 || rc=$?
ck "SPECFLOW_BASE_REF=refs/remotes/origin/main (ci.yml's form) in this checkout: used as the base, exit 0" \
  bash -c '[ "$1" = 0 ] && grep -q "^why: base refs/remotes/origin/main at " "$2"' _ "$rc" "$W/out"

# P5 lows patch (PR #48 verifier runs 5-7, the seed's ids; REQ-341): the /next seed's REQ and ADR ids are fixture-local —
# no live spec under docs/ defines its REQ and no live ADR carries its ADR id or number (the demo owns ADR-001; its REQs start at REQ-200).
ck "the /next seed's REQ and ADR ids are defined by no live document under docs/" python3 - "$ROOT" <<'PYI'
import os, re, sys
root = sys.argv[1]; seed = os.path.join(root, "tests/governance/fixtures/next/seed")
def defined(base):
    reqs, adrs = set(), set()
    for d, _, fs in os.walk(os.path.join(base, "docs")):
        for f in fs:
            if not f.endswith(".md"):
                continue
            s = open(os.path.join(d, f), encoding="utf-8").read()
            reqs |= set(re.findall(r"(?m)^- \*\*(REQ-\d{3}):\*\*", s))
            adrs |= set(re.findall(r"(?m)^id: (ADR-\d{3})\s*$", s))
            m = re.match(r"^(\d{3})-", f)
            if os.path.basename(d) == "adr" and m:
                adrs.add("ADR-" + m.group(1))
    return reqs, adrs
sr, sa = defined(seed); lr, la = defined(root)
assert sr and sa, (sr, sa)
assert not (sr & lr) and not (sa & la), (sorted(sr & lr), sorted(sa & la))
PYI

# P6 Task 1.5 (REQ-342, REQ-341; P6 R9): on a ship branch the ship-pr point names its reference — the previous release's
# tag, else the base — and lists the suppression entries added since it, as explain-only facts (the kernel unchanged).
# Covers: REQ-342
repo ship1 main
(cd "$D" && mkdir -p docs/releases && printf -- '---\nversion: 0.9.0\ndate: 2026-09-01\n---\n# 0.9.0\n' > docs/releases/0.9.0-notes.md \
  && git add -A && git commit -qm 0.9.0 && git tag -a v0.9.0 -m 0.9.0 && git checkout -qb ship/1.0.0)
cp "$ROOT/tests/governance/fixtures/next/osv-scanner-sec901.toml" "$D/osv-scanner.toml"
mkdir -p "$D/docs/security"; printf -- '# Security Disposition\n\n---\nid: SEC-901\nstatus: accepted\nowner: alice\nexpiry: 2099-06-30\nrationale: "fixture: accepted, no known exploit"\nsuppresses: [GHSA-aaaa-bbbb-cccc]\n---\n' > "$D/docs/security/1.0.0-disposition.md"
commit "a suppression"
nx --json
ck "ship/1.0.0: ship.reference is v0.9.0 (previous-tag), and the new osv-scanner ignore is listed with its SEC id" python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))["ship"]
assert s["reference"] == "v0.9.0" and s["reference_kind"] == "previous-tag", s
assert [(e["file"], e["sec"]) for e in s["suppressions_added"]] == [("osv-scanner.toml", "SEC-901")], s' "$W/out"
nx
ck "…the text output names them on a ship: line" has 'ship: reference v0.9.0 (previous release tag); 1 suppression entry added'
# Fix wave 2 (REQ-342; P6 R9, C8): the reference is the tag as this checkout sees it — /next never verifies it.
nx --explain
ck "…--explain says the reference is the previous release tag as this checkout sees it, unverified" \
  has 'why: ship reference: v0.9.0 (unverified: the tag as this checkout sees it'
# Fix wave 1, E (REQ-342, REQ-350): release.yml exists, so the explain line names it in the present tense.
ck "…and that release-tag.sh and release.yml verify release tags, with no 'from Build 3' qualifier" \
  bash -c 'grep -qF "release-tag.sh and release.yml verify release tags" "$1" && ! grep -qF "from Build 3" "$1"' _ "$W/out"
git -C "$D" tag -d v0.9.0 >/dev/null; nx --json
ck "…with no previous release tag the reference is the base (reference_kind base)" python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))["ship"]; assert s["reference_kind"] == "base", s' "$W/out"
repo notship main; nx --json
ck "off the ship lane, ship is null" python3 -c 'import json, sys; assert json.load(open(sys.argv[1]))["ship"] is None' "$W/out"

# P6 Task 5.3 (REQ-354; P6 R23): /next --explain names signing: and what release.yml does with it.
# Covers: REQ-354
repo sg main; printf 'profile: engineer\npath: lanes\nstack: tauri\nsolo: true\nsigning: none\n' > "$D/.specflow.yml"; commit "a tauri instance"; nx --explain
ck "signing none on a tauri instance: release.yml records signed: false and attaches tester instructions" \
  has 'why: signing none (.specflow.yml; REQ-354): release.yml records signed: false and attaches tester instructions'
# Build 5 fix wave 1, C (REQ-354; P6 R23): the line says what release.yml does — signing: none with the five secrets
# present still signs (signing-probe reports present, sign runs); signing: apple without them publishes nothing — and it
# is stack-aware: python and the template build no bundle, so their line names no tester instructions.
# Covers: REQ-354
ck "...and says that with all five APPLE_* secrets in the release environment, signing-probe reports present and sign runs" \
  has 'release.yml records signed: false and attaches tester instructions, unless the release environment holds all five APPLE_* secrets: then signing-probe reports present and sign runs (signed: true)'
sed -i.bak 's/^signing: none$/signing: apple/' "$D/.specflow.yml" && rm -f "$D/.specflow.yml.bak"; commit "signing apple"; nx --explain
ck "...signing apple: release.yml signs and notarizes" has 'why: signing apple (.specflow.yml; REQ-354): release.yml signs and notarizes'
ck "...and publishes nothing when the release environment lacks any of the five secrets (signing-probe fails)" \
  has 'release.yml signs and notarizes, and publishes nothing when the release environment lacks any of the five APPLE_* secrets (signing-probe fails)'
repo sgp main; printf 'profile: engineer\npath: lanes\nstack: python\nsolo: true\nsigning: none\n' > "$D/.specflow.yml"; commit "a python instance"; nx --explain
ck "a python instance: no bundle to sign (R23), and the signing line names no tester instructions" \
  bash -c 'grep -qxF "why: signing none (.specflow.yml; REQ-354): stack python builds no bundle (R23): nothing to sign or notarize" "$1" && ! grep "^why: signing" "$1" | grep -qi tester' _ "$W/out"
repo sg2 main; git -C "$D" rm -q .specflow.yml; mkdir -p "$D/stacks/python"; echo "stack: python" > "$D/stacks/python/pack.yml"; commit "template source"; nx --explain
ck "the template source (no .specflow.yml): no bundle to sign" has 'why: signing none (template source: config.DEFAULTS; no bundle to sign)'
ck "…and its signing line names no tester instructions" bash -c '! grep "^why: signing" "$1" | grep -qi tester' _ "$W/out"

# P6 Task 5.6 (REQ-341; P6 R4): a follow-on design lane (design/greet-p2) of an existing spec resolves the spec, its
# brainstorm and its architecture through its plan's spec: once the plan exists — so the architecture gate is honoured —
# and derives brainstorm before that. Facts only: the kernel is unchanged.
# Covers: REQ-341
repo follow design/greet-p2; nx --explain
ck "design/greet-p2 with no plan yet: design brainstorm (nothing to resolve through)" has 'state: design brainstorm'
printf -- '---\ntype: plan\nphase: PLAN\nspec: 2026-09-28-greet\ndecisions: [ADR-991]\nimplements: [REQ-991]\ncreated: "2026-10-01"\n---\n\n# Greet p2\n\n## Build 1: more\n' \
  > "$D/docs/plans/2026-10-01-greet-p2-plan.md"; commit "p2 plan"; nx --explain
ck "…with the plan naming spec: 2026-09-28-greet, the spec is resolved through it, and --explain says so" \
  has "why: spec 2026-09-28-greet resolved through docs/plans/2026-10-01-greet-p2-plan.md's spec: (a follow-on design lane, P6 R4)"
ck "…has_spec, has_brainstorm and spec_has_tagged_reqs read the resolved spec" \
  bash -c 'grep -qE "^why: has_spec is True: docs/specs/2026-09-28-greet-design.md" "$1" && grep -qE "^why: has_brainstorm is True" "$1" && grep -qE "^why: spec_has_tagged_reqs is True" "$1"' _ "$W/out"
ck "…the architecture gate reads the spec's own overview and threat model, not the design slug's" \
  bash -c '! grep -qF "greet-p2-overview.md" "$1" && grep -qE "^why: arch_complete is " "$1"' _ "$W/out"
ck "…so the lane derives analyze or open-pr, never brainstorm" bash -c 'grep -qE "^state: design (analyze|open-pr)$" "$1"' _ "$W/out"
printf -- '---\ntype: plan\nspec: 2099-01-01-nowhere\n---\n' > "$D/docs/plans/2026-10-01-greet-p2-plan.md"; commit "bad spec"; nx --explain
ck "…a plan whose spec: names no live spec resolves nothing: the slug's own (absent) spec, explained" \
  bash -c 'grep -qE "^why: has_spec is False" "$1" && grep -qF "names no live spec" "$1"' _ "$W/out"
# Build 5 fix wave 1, D (REQ-341; P6 R4): two dated plans of the design slug — the NEWEST one's spec: is resolved, as
# plan_path picks the newest; and the safety property: a resolved spec with tagged REQs but no overview or threat model
# of its own derives design architecture, never analyze or open-pr.
# Covers: REQ-341
printf -- '---\ntype: plan\nspec: 2099-01-01-nowhere\n---\n' > "$D/docs/plans/2026-10-01-greet-p2-plan.md"
printf -- '---\ntype: plan\nphase: PLAN\nspec: 2026-09-28-greet\ndecisions: [ADR-991]\nimplements: [REQ-991]\ncreated: "2026-10-02"\n---\n\n# Greet p2\n\n## Build 1: more\n' \
  > "$D/docs/plans/2026-10-02-greet-p2-plan.md"; commit "two dated plans"; nx --explain
ck "two dated plans of the slug: the newest (2026-10-02) resolves the spec, never the older one" \
  bash -c 'grep -qF "resolved through docs/plans/2026-10-02-greet-p2-plan.md" "$1" && ! grep -qF "2026-10-01-greet-p2-plan.md'"'"'s spec:" "$1"' _ "$W/out"
git -C "$D" rm -q docs/architecture/2026-09-28-greet-overview.md; commit "the resolved spec loses its overview"; nx --explain
ck "…a resolved spec with tagged REQs and no overview of its own: design architecture (the gate holds through the plan)" \
  bash -c 'grep -q "^state: design architecture$" "$1" && grep -qE "^why: spec_has_tagged_reqs is True" "$1"' _ "$W/out"
git -C "$D" checkout -q HEAD~1 -- docs/architecture/2026-09-28-greet-overview.md; git -C "$D" rm -q docs/plans/2026-10-02-greet-p2-plan.md; commit "back to one plan"
# F17: the resolution is the design lane's alone — a build lane of the follow-on plan reads its Build N from that plan,
# never from the resolved spec's other plans (the seed's 2026-09-28-greet-plan.md also has "## Build 1").
printf -- '---\ntype: plan\nphase: PLAN\nspec: 2026-09-28-greet\ndecisions: [ADR-991]\nimplements: [REQ-991]\ncreated: "2026-10-01"\n---\n\n# Greet p2\n\n## Build 1: more\n' \
  > "$D/docs/plans/2026-10-01-greet-p2-plan.md"; commit "p2 plan again"; git -C "$D" checkout -q -b build/greet-p2-1; nx --explain
ck "build/greet-p2-1: Build 1 is read from docs/plans/2026-10-01-greet-p2-plan.md, never the resolved spec's 2026-09-28-greet-plan.md" \
  bash -c 'grep -qF "of docs/plans/2026-10-01-greet-p2-plan.md" "$1" && ! grep -qF "of docs/plans/2026-09-28-greet-plan.md" "$1" && ! grep -qF "resolved through" "$1"' _ "$W/out"

finish test_next
