#!/usr/bin/env bash
# REQ-333: the threat-model template carries the ten-domain checklist; check-architecture.sh fails on an unanswered item
# and on the ARCHITECTURE exit-gate shape .claude/rules/review-gate.md states (every [verifiable*] REQ in some overview
# req_map; >= 1 trust boundary; >= 1 asset with CIA; >= 1 STRIDE letter per external element), for each live spec a plan
# names or whose threat model or overview exists. The demo and v3.2 threat models answer the checklist.
# Covers: REQ-333
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CA="$ROOT/scripts/check-architecture.sh"; TPL="$ROOT/schemas/threat-model-template.md"
[[ -f "$CA" ]] || { fail "scripts/check-architecture.sh missing"; finish test_check_architecture; }
DOMAINS=("Authentication" "Authorization" "Session" "PII and retention" "Payments" "Secrets at rest" "Sensitive logging" "Rate limiting" "Third-party integrations" "Update channel for apps")
ck "schemas/threat-model-template.md exists" test -f "$TPL"
for d in "${DOMAINS[@]}"; do ck "template checklist row: $d" grep -qE "^\| $d \|" "$TPL"; done
for k in assets trust_boundaries dataflow_elements stride_per_element; do ck "template frontmatter key $k" grep -qE "^$k:" "$TPL"; done
ck "template states the answer grammar (dfe-N or 'N/A because …')" grep -qF 'N/A because' "$TPL"
ck "this repository passes check-architecture.sh" bash "$CA"
AC="$ROOT/.claude/commands/architecture.md"
ck "/architecture points at the template" grep -qF 'schemas/threat-model-template.md' "$AC"
ck "/architecture runs check-architecture.sh before the PR" grep -qF 'scripts/check-architecture.sh' "$AC"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
mk() {  # mk — a spec with one [verifiable-model] REQ (and one REQ that only mentions the tag in backticks, as REQ-389 does),
  # a plan naming it, an overview mapping it, a complete threat model whose frontmatter has a full-line # comment and the
  # nested block map stride_per_element (the subset the template documents)
  A="$W/a"; rm -rf "$A"; mkdir -p "$A/docs/specs" "$A/docs/plans" "$A/docs/architecture"
  printf -- '---\ntype: spec\nstatus: accepted\n---\n\n# X\n\n- **REQ-900:** a pure rule. [verifiable-model]\n- **REQ-901:** a doc.\n- **REQ-902:** prose naming the `[verifiable-model]` tag, which is not a tag.\n' > "$A/docs/specs/2099-01-01-x-design.md"
  printf -- '---\ntype: plan\nspec: 2099-01-01-x\nimplements: [REQ-900]\n---\n\n# P\n' > "$A/docs/plans/2099-01-01-x-plan.md"
  OV="$A/docs/architecture/2099-01-01-x-overview.md"; TM="$A/docs/architecture/2099-01-01-x-threat-model.md"
  printf -- '---\nspec: 2099-01-01-x\nkernel_modules:\n  - path: src/x.py\n    req_map: [REQ-900]\n---\n\n# O\n' > "$OV"
  { printf -- '---\nspec: 2099-01-01-x\n# the supported YAML subset: see schemas/threat-model-template.md\nassets:\n  - name: data\n    cia: {c: H, i: M, a: L}\ntrust_boundaries:\n  - name: user-to-app\n    between: [user, app]\n'
    printf 'dataflow_elements:\n  - id: dfe-1\n    name: input\n    external: true\n  - id: dfe-2\n    name: inner\n    external: false\n'
    printf 'stride_per_element:\n  dfe-1: [T, I]\n  dfe-2: []\n---\n\n# T\n\n## Domain checklist (REQ-333)\n\n| Domain | Answer |\n|---|---|\n'
    for d in "${DOMAINS[@]}"; do printf '| %s | N/A because the fixture has no %s surface |\n' "$d" "$d"; done
    printf '\n## Residual risks\n- none\n'; } > "$TM"
}
ca() { rc=0; out=$(ARCH_BASE_DIR="$A" bash "$CA" 2>&1) || rc=$?; }
edit() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
t = open(p).read(); assert old in t, old; open(p, "w").write(t.replace(old, new, 1))
PY
}
S1="| Session | N/A because the fixture has no Session surface |"
mk; ca; ck "fixture: a complete architecture passes (a backticked tag is prose; a # comment and a nested block map parse)" [ "$rc" = 0 ]
mk; edit "$TM" "| Payments | N/A because the fixture has no Payments surface |"$'\n' ""; ca
ck "a missing checklist row fails, naming the domain" bash -c '[ "$1" = 1 ] && grep -q "Payments" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" "$S1" "| Session | later |"; ca
ck "an answer that is neither dfe-N nor 'N/A because …' fails, naming the domain" bash -c '[ "$1" = 1 ] && grep -q "Session" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" "$S1" "| Session | N/A |"; ca
ck "a bare 'N/A' (no reason) fails" [ "$rc" = 1 ]
mk; edit "$TM" "$S1" "| Session | dfe-1: the input carries the session cookie |"; ca
ck "an answer citing an existing dfe-N passes" [ "$rc" = 0 ]
mk; edit "$TM" "$S1" "| Session | dfe-7: no such element |"; ca
ck "an answer citing an unknown dfe-N fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "dfe-7" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" "  dfe-1: [T, I]" "  dfe-1: []"; ca
ck "an external element with no STRIDE letter fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "dfe-1" <<<"$2"' _ "$rc" "$out"
mk; edit "$TM" $'trust_boundaries:\n  - name: user-to-app\n    between: [user, app]\n' $'trust_boundaries: []\n'; ca
ck "no trust boundary fails" [ "$rc" = 1 ]
mk; edit "$TM" "    cia: {c: H, i: M, a: L}" "    cia: {c: H, i: M}"; ca
ck "no asset with a full CIA rating fails" [ "$rc" = 1 ]
mk; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "a [verifiable-model] REQ in no req_map fails, naming it" bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
mk; rm "$TM"; ca
ck "a spec a plan names, with no threat model, fails" [ "$rc" = 1 ]
mk; rm "$A/docs/plans/2099-01-01-x-plan.md" "$TM" "$OV"; ca
ck "a spec no plan names and with no architecture documents yet is not checked (SPECIFY)" [ "$rc" = 0 ]
# P4 final review: on the regulated path the phase/arch-<slug> PR has no plan yet, so the gate it is advertised for
# must still bite there — a spec whose threat model or overview exists is checked even when no plan names it.
mk; rm "$A/docs/plans/2099-01-01-x-plan.md"; edit "$TM" "$S1" "| Session | later |"; ca
ck "a spec no plan names but whose threat model exists is checked (the ARCHITECTURE PR): an unanswered item fails" \
  bash -c '[ "$1" = 1 ] && grep -q "Session" <<<"$2"' _ "$rc" "$out"
mk; rm "$A/docs/plans/2099-01-01-x-plan.md" "$TM"; ca
ck "a spec no plan names, with an overview but no threat model, fails (the ARCHITECTURE PR is incomplete)" [ "$rc" = 1 ]
mk; rm "$A/docs/plans/2099-01-01-x-plan.md"; ca
ck "a complete ARCHITECTURE PR (no plan yet) passes" [ "$rc" = 0 ]
ck "/architecture says the gate checks a spec once its threat model or overview exists" grep -qF 'threat model or overview exists' "$AC"
mk; edit "$A/docs/specs/2099-01-01-x-design.md" "status: accepted" "status: superseded"; rm "$TM"; ca
ck "a superseded spec is not checked" [ "$rc" = 0 ]
mk; edit "$TM" "  dfe-2: []" "  dfe-2: !!set {}"; ca
ck "YAML outside the documented subset is an error naming the line (fail closed)" [ "$rc" = 2 ]
mk; rm -rf "$A/docs/specs" "$A/docs/plans" "$A/docs/architecture"; ca
ck "no docs at all (an instance with every example removed) passes" [ "$rc" = 0 ]

# P3 (REQ-320, REQ-394): the req_map check follows the claims — the union of implements: across plans, read through
# frontmatter.py; a plan without implements: walks its spec whole; before any plan (the ARCHITECTURE PR) every tagged REQ
# must map (R3). REQ-389's check (R4): a guided instance's v3.2-era architecture artifacts carry confirmed_by:.
# Covers: REQ-320
# Covers: REQ-394
# Covers: REQ-389
PL="$A/docs/plans/2099-01-01-x-plan.md"
mk; edit "$PL" "implements: [REQ-900]" "implements: [REQ-901]"; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "a tagged REQ no plan claims need not map once plans name the spec (REQ-320)" [ "$rc" = 0 ]
mk; edit "$PL" $'implements: [REQ-900]\n' ""; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "a plan without implements: walks its spec whole: the unmapped tagged REQ fails" \
  bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
mk; rm "$PL"; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "no plan yet (the ARCHITECTURE PR): every tagged REQ must map" bash -c '[ "$1" = 1 ] && grep -q "REQ-900" <<<"$2"' _ "$rc" "$out"
mk; edit "$PL" "implements: [REQ-900]" "implements: [REQ-900]  # the kernel REQ"; edit "$OV" "req_map: [REQ-900]" "req_map: []"; ca
ck "implements: is read through frontmatter.py (a trailing comment keeps the claim)" [ "$rc" = 1 ]
ADR="$A/docs/adr/001-x.md"
guided() { mkdir -p "$A/docs/adr"; printf 'profile: %s\n' "$1" > "$A/.specflow.yml"
  printf -- '---\nid: ADR-001\nstatus: accepted\naddresses: [REQ-900]\n---\n# A\n' > "$ADR"; }
mk; guided guided; ca
ck "guided: the overview, threat model and ADR for the tagged REQ without confirmed_by: fail, each named" \
  bash -c '[ "$1" = 1 ] && grep -q "overview.md: confirmed_by" <<<"$2" && grep -q "threat-model.md: confirmed_by" <<<"$2" && grep -q "001-x.md: confirmed_by" <<<"$2"' _ "$rc" "$out"
mk; guided guided; for f in "$OV" "$TM" "$ADR"; do edit "$f" $'---\n' $'---\nconfirmed_by: "founder (acknowledged 2099-01-02)"\n'; done; ca
ck "guided: confirmed_by: on each passes" [ "$rc" = 0 ]
mk; guided guided; for f in "$OV" "$TM" "$ADR"; do edit "$f" $'---\n' $'---\nconfirmed_by: ""\n'; done; ca
ck "guided: an empty confirmed_by: fails" [ "$rc" = 1 ]
mk; guided engineer; ca
ck "engineer profile: confirmed_by: is not required" [ "$rc" = 0 ]
mk; guided guided; edit "$A/docs/specs/2099-01-01-x-design.md" "status: accepted" $'status: accepted\ncreated: "2026-05-28"'; ca
ck "guided: a new spec backdated before the cutoff (created: is the author's) is not grandfathered" [ "$rc" = 1 ]
mk; guided guided; edit "$A/docs/specs/2099-01-01-x-design.md" "status: accepted" $'status: accepted\ncreated: "2026-09-28"'; ca
ck "guided: a spec whose slug is not in the inherited list is not grandfathered" [ "$rc" = 1 ]
ck "grandfathering is a fixed list of the template's inherited spec slugs (the demo and the v3.2 spec)" \
  bash -c 'grep -qF "\"2026-05-28-demo-greeting\"" "$1" && grep -qF "\"2026-09-25-factory-v3-2\"" "$1"' _ "$ROOT/scripts/lib/specflow/frontmatter.py"
mk; guided guided; (cd "$A" && git init -q -b main && git add -A && git commit -qm base && git checkout -qb pr \
  && printf 'profile: engineer\n' > .specflow.yml && git commit -qam "flip the profile")
rc=0; out=$(env -u SPECFLOW_BASE_REF ARCH_BASE_DIR="$A" bash "$CA" 2>&1) || rc=$?
ck "locally the working tree's profile applies (engineer: no confirmed_by: needed)" [ "$rc" = 0 ]
rc=0; out=$(cd "$A" && SPECFLOW_BASE_REF=main ARCH_BASE_DIR="$A" bash "$CA" 2>&1) || rc=$?
ck "in CI the base ref's profile governs: a PR flipping guided to engineer still needs confirmed_by:" \
  bash -c '[ "$1" = 1 ] && grep -q "confirmed_by" <<<"$2"' _ "$rc" "$out"
mk; guided guided; printf 'stack: python\n' > "$A/.specflow.yml"; ca
ck "a .specflow.yml with no profile: key is guided (config.DEFAULTS): confirmed_by: is required" [ "$rc" = 1 ]
V32=docs/specs/2026-09-25-factory-v3-2-design.md
if [ -f "$ROOT/$V32" ]; then   # the factory's own v3.2 artifacts, as a guided instance inherits them
  G="$W/inherited"; mkdir -p "$G/docs/specs" "$G/docs/architecture" "$G/docs/adr" "$G/docs/plans"
  cp "$ROOT/$V32" "$G/docs/specs/"; cp "$ROOT"/docs/architecture/2026-09-25-factory-v3-2-*.md "$G/docs/architecture/"
  cp "$ROOT"/docs/adr/002-*.md "$ROOT"/docs/adr/003-*.md "$G/docs/adr/"; cp "$ROOT"/docs/plans/*factory-v3-2*.md "$G/docs/plans/"
  printf 'profile: guided\nstack: python\n' > "$G/.specflow.yml"
  rc=0; out=$(ARCH_BASE_DIR="$G" bash "$CA" 2>&1) || rc=$?
  ck "guided: the inherited v3.2 spec, overview, threat model, ADR-002 and ADR-003 without confirmed_by: pass (R4's cutoff)" [ "$rc" = 0 ]
fi
ck "/architecture says guided artifacts carry confirmed_by:" grep -qF 'confirmed_by:' "$AC"
finish test_check_architecture
