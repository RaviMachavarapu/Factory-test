#!/usr/bin/env bash
# REQ-323 / REQ-306 / REQ-394: scripts/check-covers.sh fails when a REQ some plan claims (implements:, read through
# frontmatter.py; a plan without implements: walks its spec whole) has no test citing it on a whole '# Covers:' or
# '// Covers:' line under the pack's test_globs or tests/governance/ (fixtures excluded), reporting each uncovered id; a
# Covers line outside tests/governance/ citing a REQ no live spec defines also fails (the interim check test_traceability.sh
# carried until P3, which now delegates here). A citation counts only from a test: tests/governance/test_*.sh (never lib/,
# fixtures/ or another file there) with a check, the Covers line above its finish; or a file under the pack's test_globs
# with a test function, the Covers line in its header comment block. It proves a citation, not that the test exercises
# the REQ (the residual the claim table records). In a git checkout — a worktree's .git file included — only tracked
# files cite. This repository passes it on its own plans.
# Covers: REQ-323
# Covers: REQ-306
# Covers: REQ-394
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
CC="$ROOT/scripts/check-covers.sh"
ck "scripts/check-covers.sh exists and is executable" test -x "$CC"
ck "this repository passes check-covers.sh (every claimed REQ has a test)" bash "$CC"
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
mk() {  # an instance-shaped fixture: a python pack, one spec, one plan claiming REQ-901 and REQ-902, both cited
  A="$W/a"; rm -rf "$A"; mkdir -p "$A/docs/specs" "$A/docs/plans" "$A/.specflow" "$A/tests/unit" "$A/tests/governance/fixtures"
  : > "$A/.specflow.yml"; printf 'stack: python\nsource_roots: [src]\ntest_globs: [tests/**/test_*.py]\n' > "$A/.specflow/pack.yml"
  printf -- '---\ntype: spec\nstatus: accepted\n---\n- **REQ-901:** a.\n- **REQ-902:** b.\n- **REQ-903:** c.\n' > "$A/docs/specs/2099-01-01-x-design.md"
  printf -- '---\ntype: plan\nspec: 2099-01-01-x\nimplements: [REQ-901, REQ-902]  # two\n---\n' > "$A/docs/plans/2099-01-01-x-plan.md"
  printf '# Covers: REQ-901\ndef test_a(): pass\n' > "$A/tests/unit/test_a.py"
  printf '#!/usr/bin/env bash\n# Covers: REQ-902\nsource lib/check.sh\nck "b" true\nfinish test_b\n' > "$A/tests/governance/test_b.sh"
}
cc() { rc=0; out=$(COVERS_BASE_DIR="$A" bash "$CC" 2>&1) || rc=$?; }
mk; cc; ck "fixture: every claimed REQ cited (a pack test glob, a governance test) passes" [ "$rc" = 0 ]
mk; rm "$A/tests/governance/test_b.sh"; cc
ck "an uncovered claimed REQ fails, naming only it" bash -c '[ "$1" = 1 ] && grep -q "REQ-902" <<<"$2" && ! grep -q "REQ-901" <<<"$2"' _ "$rc" "$out"
mk; printf '# Covers: REQ-901, REQ-902\ndef test_a(): pass\n' > "$A/tests/unit/test_a.py"; rm "$A/tests/governance/test_b.sh"; cc
ck "a comma list on one Covers line cites every id" [ "$rc" = 0 ]
mk; rm "$A/tests/governance/test_b.sh"; printf 'x = "# Covers: REQ-902 in a string"\n' > "$A/tests/unit/test_c.py"; cc
ck "a Covers mention inside code (not a whole comment line) cites nothing" [ "$rc" = 1 ]
mk; rm "$A/tests/governance/test_b.sh"; printf '# Covers: REQ-902\n' > "$A/tests/governance/fixtures/f.sh"; cc
ck "a Covers line in tests/governance/fixtures/ cites nothing" [ "$rc" = 1 ]
mk; rm "$A/tests/governance/test_b.sh"; printf '# Covers: REQ-902\n' > "$A/tests/unit/helper.py"; cc
ck "a Covers line outside the pack's test_globs cites nothing" [ "$rc" = 1 ]
mk; printf 'stack: tauri\nsource_roots: [src]\ntest_globs: [src/**/*.test.ts]\n' > "$A/.specflow/pack.yml"; rm "$A/tests/unit/test_a.py"
mkdir -p "$A/src/lib"; printf '// Covers: REQ-901\ntest("g", () => {});\n' > "$A/src/lib/g.test.ts"; cc
ck "a // Covers: line under a TypeScript test glob cites" [ "$rc" = 0 ]
mk; printf -- '---\ntype: plan\nspec: 2099-01-01-x\n---\n' > "$A/docs/plans/2099-01-01-x-plan.md"; cc
ck "a plan without implements: walks its spec whole (REQ-903 uncovered)" bash -c '[ "$1" = 1 ] && grep -q "REQ-903" <<<"$2"' _ "$rc" "$out"
mk; printf '# Covers: REQ-999\n' >> "$A/tests/unit/test_a.py"; cc
ck "a Covers line outside tests/governance/ citing a REQ no live spec defines fails" bash -c '[ "$1" = 1 ] && grep -q "REQ-999" <<<"$2"' _ "$rc" "$out"
mk; printf '# Covers: REQ-999\n' >> "$A/tests/governance/test_b.sh"; cc
ck "…but not under tests/governance/ (an instance may delete the factory spec)" [ "$rc" = 0 ]
mk; printf '#!/usr/bin/env bash\n# Covers: REQ-902\n' > "$A/tests/governance/test_b.sh"; cc
ck "a governance test_*.sh with no check (a shebang and a Covers line only) cites nothing" bash -c '[ "$1" = 1 ] && grep -q "REQ-902" <<<"$2"' _ "$rc" "$out"
mk; printf '#!/usr/bin/env bash\nsource lib/check.sh\nck "b" true\nfinish test_b\n# Covers: REQ-902\n' > "$A/tests/governance/test_b.sh"; cc
ck "a Covers line after finish cites nothing" [ "$rc" = 1 ]
mk; rm "$A/tests/governance/test_b.sh"; mkdir -p "$A/tests/governance/lib"; printf '# Covers: REQ-902
ck() { :; }\n' > "$A/tests/governance/lib/check.sh"; cc
ck "a Covers line in tests/governance/lib/ (the harness) cites nothing" [ "$rc" = 1 ]
mk; rm "$A/tests/governance/test_b.sh"; printf '# Covers: REQ-902\n' > "$A/tests/governance/README.md"; cc
ck "a Covers line in a non-test file under tests/governance/ cites nothing" [ "$rc" = 1 ]
mk; printf '# Covers: REQ-901\nX = 1\n' > "$A/tests/unit/test_a.py"; cc
ck "a pack test file with no test function cites nothing" bash -c '[ "$1" = 1 ] && grep -q "REQ-901" <<<"$2"' _ "$rc" "$out"
mk; printf 'import os\n# Covers: REQ-901\ndef test_a(): pass\n' > "$A/tests/unit/test_a.py"; cc
ck "a pack test file's Covers line below its header comment block cites nothing" bash -c '[ "$1" = 1 ] && grep -q "REQ-901" <<<"$2"' _ "$rc" "$out"
mk; rm -rf "$A/docs/specs" "$A/docs/plans"; cc
ck "no plans and no specs (every example removed, REQ-306) passes" [ "$rc" = 0 ]
mk; mv "$A/tests/governance/test_b.sh" "$W/test_b.sh"; (cd "$A" && git init -q -b main && git add -A && git commit -qm a \
  && git worktree add -q "$W/wt" 2>/dev/null); mkdir -p "$W/wt/tests/governance"; cp "$W/test_b.sh" "$W/wt/tests/governance/test_b.sh"
rc=0; out=$(COVERS_BASE_DIR="$W/wt" bash "$CC" 2>&1) || rc=$?
ck "in a git worktree (.git is a file) only tracked files cite: an untracked test's Covers line cites nothing" \
  bash -c '[ "$1" = 1 ] && grep -q "REQ-902" <<<"$2"' _ "$rc" "$out"
ck "check-covers.sh reads plans through frontmatter.py" grep -qE '(import frontmatter|from frontmatter import)' "$CC"
ck "test_traceability.sh delegates its Covers check to check-covers.sh" grep -qF 'scripts/check-covers.sh' "$ROOT/tests/governance/test_traceability.sh"
ck "test_traceability.sh no longer carries the interim glob" no grep -qF 'Interim REQ-323 check' "$ROOT/tests/governance/test_traceability.sh"
for t in test_traceability_scoping.sh:REQ-327 test_traceability_scoping.sh:REQ-380 test_plan_template.sh:REQ-380 test_analyze_adr_plan_linkage.sh:REQ-380; do
  ck "${t%%:*} cites ${t##*:}, which it exercises" grep -qE "^# Covers: (.*, )?${t##*:}(,|$)" "$ROOT/tests/governance/${t%%:*}"
done
ck "run-quality-gates.sh's Document gates run check-covers.sh" \
  bash -c 'awk "/SECTION \"Document gates\"/{f=1} /SECTION \"Release gates\"/{f=0} f" "$1" | grep -qF "scripts/check-covers.sh"' _ "$ROOT/scripts/run-quality-gates.sh"
finish test_check_covers
