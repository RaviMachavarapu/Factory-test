#!/usr/bin/env bash
# REQ-306: governance tests are example-independent; examples are listed in
# CLAUDE.md "Canonical Example" (examples.py, shared with init); the
# placeholder proof lives in templates/.
# Covers: REQ-306
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
EXPY="$ROOT/scripts/lib/specflow/examples.py"
ck "example.dfy left verification/" no test -e verification/example.dfy
ck "example.dfy lives in templates/" test -f templates/example.dfy
ck "docs point at templates/example.dfy" no grep -q verification/example.dfy verification/README.md src/contracts/README.md
instance && { echo "SKIP: remaining cases run in the template source"; finish test_examples; exit 0; }
names=$(python3 "$EXPY" --root "$ROOT" names 2>/dev/null || true)
ck "manifest lists demo_greeting (stack: python)" grep -qx 'demo_greeting python' <<<"$names"
count=0
while read -r n s; do
  [[ -z "$n" ]] && continue
  while IFS= read -r p; do count=$((count + 1)); ck "manifest path exists: $p" test -e "$p"; done < <(python3 "$EXPY" --root "$ROOT" list "$n")
done <<<"$names"
ck "manifest lists paths" [ "$count" -gt 0 ]
WORK="$(mktemp -d)"; trap 'rm_tree "$WORK"' EXIT
D="$WORK/stripped"; copy_template "$D"
while read -r n s; do
  [[ -z "$n" ]] && continue
  (cd "$D" && python3 scripts/lib/specflow/examples.py list "$n" | while IFS= read -r p; do rm -rf "$p"; done \
     && python3 scripts/lib/specflow/examples.py strip "$n")
done <<<"$names"
ck "demo removed" no test -e "$D/src/demo_greeting"
ck "demo manifest entry stripped" no grep -q '^### demo_greeting' "$D/CLAUDE.md"
for t in spec_lifecycle plan_template traceability analyze_adr_plan_linkage; do
  ck "test_$t passes with every example removed" bash -c "cd '$D' && bash tests/governance/test_$t.sh"
done
# A deleted spec takes its proofs with it: a // Proves: header naming a REQ no live spec defines dangles (REQ-327), so
# the factory's own proofs (verification/factory_v3_2/, REQ-322) go with the factory spec here.
rm -f "$D"/docs/specs/*.md "$D"/docs/plans/*.md; rm -rf "$D"/verification/*/
for t in spec_lifecycle plan_template traceability; do
  ck "test_$t passes with empty docs/specs, docs/plans and proofs" bash -c "cd '$D' && bash tests/governance/test_$t.sh"
done
# 4. Other stacks' examples are dropped — real packs, scaffold skipped (no toolchain in the default gates).
for s in tauri flutter; do
  [[ -d "$ROOT/stacks/$s" ]] || { fail "stacks/$s missing"; continue; }
  D="$WORK/other-$s"; copy_template "$D"
  ck "init --stack $s (SPECFLOW_NO_SCAFFOLD=1) exits 0" bash -c "cd '$D' && SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Habit --stack $s </dev/null"
  while IFS= read -r p; do ck "$s instance drops $p" no test -e "$D/$p"; done < <(python3 "$EXPY" --root "$ROOT" list demo_greeting)
  ck "$s CLAUDE.md drops demo_greeting" no grep -q '^### demo_greeting' "$D/CLAUDE.md"
  ck "$s instance has the store checklist" test -f "$D/docs/releases/store-checklist.md"
done
D="$WORK/py"; copy_template "$D"
ck "python init exits 0" bash -c "cd '$D' && bash scripts/init-project.sh --name Py </dev/null"
ck "python instance keeps its example" test -d "$D/src/demo_greeting"
ck "python CLAUDE.md keeps demo_greeting" grep -q '^### demo_greeting' "$D/CLAUDE.md"

# REQ-389 (R4): a freshly initialised guided instance passes check-architecture.sh — the demo and the inherited factory
# v3.2 artifacts are grandfathered by their slugs (frontmatter.INHERITED_SPEC_SLUGS) (gates section 6, the CI first-run (guided) job).
# Covers: REQ-389
for s in tauri flutter; do
  D="$WORK/other-$s"
  if [ -f "$D/.specflow.yml" ]; then
    ck "$s guided instance: check-architecture.sh passes (inherited artifacts grandfathered)" bash -c "cd '$D' && bash scripts/check-architecture.sh"
  fi
done
ck "python guided instance: check-architecture.sh passes (demo and v3.2 grandfathered)" bash -c "cd '$WORK/py' && bash scripts/check-architecture.sh"
# P5 R11 (H7; REQ-306): instances do not receive the factory's own design documents and proofs. scripts/factory-only.txt
# lists them; init removes every match and the manifest, walking the new tree (no .git exists yet); every factory
# document the template ships is matched — any path naming factory-v3-2, any ADR addressing a REQ of the factory spec
# except ADR-002 (it governs every instance's disposition gate), any review the examples manifest does not list, any
# proof of a factory REQ, any test outside tests/governance/ whose Covers line cites a factory REQ — so a REQ, ADR,
# proof or test added to them later is fenced with them; no document an instance's
# sessions read cites a fenced ADR by id.
# Covers: REQ-306
M="$ROOT/scripts/factory-only.txt"
ck "the fence manifest exists in the template source" test -f "$M"
ck "every manifest line matches a tracked path, and every factory document is matched" python3 - "$ROOT" "$M" <<'PY'
import fnmatch, os, re, subprocess, sys
root, man = sys.argv[1:]
globs = [l.strip() for l in open(man) if l.strip() and not l.lstrip().startswith("#")]
files = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, check=True).stdout.split()
hit = lambda g, f: f.startswith(g) if g.endswith("/") else fnmatch.fnmatch(f, g)
# A release's own records (docs/security|releases/<version>-*.md) arrive on its ship PR, so the glob fencing them may
# land first and match nothing until then; every other glob must match a tracked path.
release_glob = lambda g: re.fullmatch(r"docs/(security|releases)/\d+\.\d+\.\d+-\*\.md", g)
for g in globs:
    assert release_glob(g) or any(hit(g, f) for f in files), f"{g} matches nothing"
spec = open(os.path.join(root, "docs/specs/2026-09-25-factory-v3-2-design.md")).read()
reqs = set(re.findall(r"-\s+\*\*(REQ-\d{3}):?\*\*", spec))
ex = subprocess.run(["python3", os.path.join(root, "scripts/lib/specflow/examples.py"), "--root", root, "list", "demo_greeting"],
                    capture_output=True, text=True, check=True).stdout.split()
need = [f for f in files if re.search(r"factory[-_]v3[-_]2", f) and f.startswith(("docs/", "verification/"))]
for f in files:
    p = os.path.join(root, f)
    if f.startswith("docs/adr/0") and f.endswith(".md") and f != "docs/adr/002-security-disposition-decision.md":
        m = re.search(r"^addresses:\s*\[(.*?)\]", open(p).read(), re.M)
        if m and set(re.findall(r"REQ-\d{3}", m.group(1))) & reqs:
            need.append(f)
    if f.startswith("docs/reviews/") and f not in ex and not f.endswith("README.md"):
        need.append(f)
    # The factory's own release records (security review/disposition, notes/migration/known-limitations): an instance
    # keeps docs/security/README.md, RUBRIC.md, the store checklist and the demo's records (the manifest lists those).
    if re.fullmatch(r"docs/(security|releases)/\d+\.\d+\.\d+[^/]*\.md", f) and f not in ex:
        need.append(f)
    # The factory's own retrospectives (REQ-306, REQ-371): a dated docs/retrospectives/<YYYY-MM-DD>-<topic>.md decides the
    # factory's BL ids and proposes changes to its own documents; an instance keeps docs/retrospectives/README.md only
    # (the v3.2 closeout retrospective made a scaffolded tauri instance inherit the file, 2026-10-04).
    if re.fullmatch(r"docs/retrospectives/\d{4}-\d{2}-\d{2}-[^/]+\.md", f):
        need.append(f)
    # A test outside tests/governance/ whose Covers line cites a factory REQ: check-covers.sh rejects there a REQ no
    # live spec defines, and an instance has no factory spec (the first-run regression of tests/unit/test_render_dashboard.py).
    if f.startswith("tests/") and not f.startswith("tests/governance/") and not f.endswith("/"):
        try:
            cov = set(re.findall(r"REQ-\d{3}", " ".join(re.findall(r"Covers:.*", open(p, errors="ignore").read()))))
        except (IsADirectoryError, FileNotFoundError):
            cov = set()
        if cov & reqs:
            need.append(f)
    if f.startswith("verification/") and f.endswith(".dfy"):
        if set(re.findall(r"Proves:\s*(REQ-\d{3})", "".join(open(p).readlines()[:5]))) & reqs:
            need.append(f)
missing = sorted({f for f in need if not any(hit(g, f) for g in globs)})
assert not missing, missing
PY
# 2026-10-03 (REQ-306): the factory's 3.2.0 security and release records are fenced like its spec and plans; the demo's
# 0.0.1-demo records stay (the python example's). 2026-10-04 (REQ-306, BL-022): the 3.2.1 records likewise, fenced before
# the ship/3.2.1 PR adds them (a release-record glob may match nothing until then).
ck "the fence manifest lists the factory's 3.2.0 security and release records" \
  bash -c 'grep -qxF "docs/security/3.2.0-*.md" "$1" && grep -qxF "docs/releases/3.2.0-*.md" "$1"' _ "$M"
ck "the fence manifest lists the factory's 3.2.1 security and release records" \
  bash -c 'grep -qxF "docs/security/3.2.1-*.md" "$1" && grep -qxF "docs/releases/3.2.1-*.md" "$1"' _ "$M"
ck "no fence glob matches the demo's 0.0.1-demo records, the security README/RUBRIC or the releases README/store checklist" python3 - "$M" <<'PY'
import fnmatch, sys
globs = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.lstrip().startswith("#")]
keep = ["docs/security/0.0.1-demo-review.md", "docs/security/0.0.1-demo-disposition.md", "docs/releases/0.0.1-demo-notes.md",
        "docs/releases/0.0.1-demo-migration.md", "docs/releases/0.0.1-demo-known-limitations.md",
        "docs/security/README.md", "docs/security/RUBRIC.md", "docs/releases/README.md", "docs/releases/store-checklist.md"]
hit = [(g, d) for g in globs for d in keep if (d.startswith(g) if g.endswith("/") else fnmatch.fnmatch(d, g))]
assert not hit, hit
PY
FENCED='docs/(specs|architecture|plans|reviews)/[^ )`]*(factory-v3-2|p1a-fresh-eyes|template-objective)|verification/factory_v3_2|docs/adr/003-|ADR-003'
for s in tauri flutter; do
  D="$WORK/other-$s"
  [ -f "$D/.specflow.yml" ] || continue
  ck "$s instance: no fenced document, no factory proof, no manifest" \
    bash -c 'cd "$1" && ! git ls-files | grep -qE "$2" && [ ! -e scripts/factory-only.txt ]' _ "$D" "$FENCED"
  ck "$s instance: ADR-002 stays — it defines the disposition gate the instance runs (P5 R11)" \
    test -f "$D/docs/adr/002-security-disposition-decision.md"
  ck "$s instance: traceability, covers and the ADR linkage pass with the factory documents gone" \
    bash -c "cd '$D' && bash scripts/check-traceability.sh >/dev/null && bash scripts/check-covers.sh >/dev/null && bash scripts/analyze-adr-plan-linkage.sh >/dev/null"
  ck "$s instance: no .dfy file is left, so Dafny is not needed" bash -c '! find "$1/verification" -name "*.dfy" 2>/dev/null | grep -q .' _ "$D"
  ck "$s instance: the documents a user or a session reads name no removed path and cite no fenced ADR by id" bash -c \
    'cd "$1" && ! git grep -qE "$2" -- README.md CLAUDE.md docs/GLOSSARY.md docs/security .claude .github schemas templates verification/README.md' _ "$D" "$FENCED"
done
D="$WORK/py"
ck "python instance: the demo's proof and review stay, and no factory proof or review arrives" \
  bash -c 'test -f "$1/verification/demo_greeting/greeting.dfy" && test -f "$1/docs/reviews/2026-05-28-v3.1-demo-review.md" && ! test -e "$1/verification/factory_v3_2" && [ "$(ls "$1/docs/reviews" | wc -l | tr -d " ")" = 1 ]' _ "$D"
ck "python instance: the tests that read factory documents skip them cleanly" \
  bash -c "cd '$D' && for t in state_model disposition_kernel threat_model_current; do bash tests/governance/test_\$t.sh >/dev/null 2>&1 || { echo \$t; exit 1; }; done"
for s in tauri flutter; do
  [ -f "$WORK/other-$s/.specflow.yml" ] || continue
  ck "$s instance: the pipeline directories stay after the fence empties them (the tests write into docs/specs)" \
    bash -c 'cd "$1" && test -d docs/specs && test -d docs/plans && test -d docs/architecture && test -d verification && ! test -e verification/factory_v3_2' _ "$WORK/other-$s"
done
# REQ-391, REQ-306 (P7 R10): the second worked example — documents only, under docs/examples/habit-tracker/, listed in
# the manifest as habit_tracker (stack: tauri): a tauri instance keeps it, every other stack's init removes it and its
# subsection; no pipeline gate reads it — traceability, covers, the ADR linkage, the architecture check and the
# disposition gate read only the top-level pipeline directories (measured below against a base ref, with a positive
# control) — while the docs-wide article-citation check (test_reviews_use_slugs.sh) does read it (pinned below; P7 Build 2
# final review, findings 1, 4 and 5); it holds .md and .txt files only; no secret hides under the gitleaks allowlist for
# docs/**/examples/; no transcript carries a home directory path.
# Covers: REQ-391
# Covers: REQ-306
ck "manifest lists habit_tracker (stack: tauri)" grep -qx 'habit_tracker tauri' <<<"$names"
ck "the example's paths are its README and its tree" \
  bash -c '[ "$(python3 "$1" --root "$2" list habit_tracker | sort | tr "\n" " ")" = "docs/examples/habit-tracker/ docs/examples/habit-tracker/README.md " ]' _ "$EXPY" "$ROOT"
ck "the example is documents only: .md and .txt files, nothing else" \
  bash -c '! find "$1/docs/examples/habit-tracker" -type f ! -name "*.md" ! -name "*.txt" | grep -q .' _ "$ROOT"
ck "the example's README states its status, provenance and layout, and has an Evidence section" \
  bash -c 'f="$1/docs/examples/habit-tracker/README.md"; grep -qE "^Status: (pending the maintainer'"'"'s walk \(REQ-391\)\.|walked on [0-9]{4}-[0-9]{2}-[0-9]{2} from (v3\.2\.0|fbd432a); Release: https://\S+\.)$" "$f" && grep -qx "## Evidence" "$f" && for w in "profile: guided" "solo: true" "tester instructions" "second Mac" "transcripts/"; do grep -qF -- "$w" "$f" || exit 1; done' _ "$ROOT"
ck "the example's README carries no factory-maintainer instruction (it ships to tauri instances): no M1–M6 checklist, no gitleaks recipe" \
  bash -c '! grep -qE "^- \*\*M[0-9]+ —|Maintainer checklist|gitleaks dir" "$1/docs/examples/habit-tracker/README.md"' _ "$ROOT"
ck "the example's README names the one check that reads it (the docs-wide article-citation check) and no longer says no gate reads it" \
  bash -c 'f="$1/docs/examples/habit-tracker/README.md"; ! grep -qF "read by any gate" "$f" && grep -qF "test_reviews_use_slugs.sh" "$f"' _ "$ROOT"
ck "while pending, the README and the manifest subsection state the walk as intent (no tester has opened anything) and point at the Status line" \
  bash -c 'f="$1/docs/examples/habit-tracker/README.md"; c=$(awk "/^### habit_tracker \\(stack: tauri\\)\$/{f=1; next} /^##/{f=0} f" "$1/CLAUDE.md"); grep -q "^Status: pending" "$f" || exit 0; ! grep -qiE "tester opened" "$f" && ! grep -qiE "tester opened" <<<"$c" && grep -qF "Status line" <<<"$c" && grep -qF "Status line" "$f"' _ "$ROOT"
# Fix wave 1, finding 6: the present tense ("a tester opens the bundle") reads as fact too — while pending, both say the
# tester will open it.
ck "while pending, the README and the manifest subsection put the second Mac in the future: a tester will open the bundle, never opens or opened it" \
  bash -c 'f="$1/docs/examples/habit-tracker/README.md"; c=$(awk "/^### habit_tracker \\(stack: tauri\\)\$/{f=1; next} /^##/{f=0} f" "$1/CLAUDE.md"); grep -q "^Status: pending" "$f" || exit 0; for t in "$(cat "$f")" "$c"; do t=$(tr "\n" " " <<<"$t"); ! grep -qiE "tester (on a second Mac )?open(s|ed)|bundle a tester opens" <<<"$t" && grep -qiE "will open" <<<"$t" || exit 1; done' _ "$ROOT"
ck "once walked, the copied docs/ tree and at least one /next transcript exist" \
  bash -c 'f="$1/docs/examples/habit-tracker"; grep -q "^Status: pending" "$f/README.md" || { test -d "$f/docs/specs" && ls "$f"/transcripts/[0-9][0-9]-*.txt >/dev/null 2>&1; }' _ "$ROOT"
ck "no transcript or copied document names a home directory" \
  bash -c '! grep -rqE "/(Users|home)/[A-Za-z0-9._-]+/" "$1/docs/examples/habit-tracker"' _ "$ROOT"
if command -v gitleaks >/dev/null 2>&1; then
  printf 'title = "no allowlist"\n[extend]\nuseDefault = true\n' > "$WORK/noallow.toml"
  ck "gitleaks with no allowlist finds nothing under docs/examples/ (the template's .gitleaks.toml skips it)" \
    gitleaks dir "$ROOT/docs/examples" --config "$WORK/noallow.toml" --no-banner --redact
else
  echo "SKIP: gitleaks is not on PATH — the no-allowlist secret scan of docs/examples/ did not run"
fi
# The python and flutter instances scaffolded above (SPECFLOW_NO_SCAFFOLD=1 for flutter) are the non-tauri stacks checked.
for D in "$WORK/py" "$WORK/other-flutter"; do
  ck "$(basename "$D") init dropped the habit-tracker example and its subsection" \
    bash -c 'cd "$1" && ! test -e docs/examples/habit-tracker && ! { test -d docs/examples && find docs/examples -type f | grep -q .; } && ! grep -q "habit_tracker" CLAUDE.md' _ "$D"
done
D="$WORK/other-tauri"
ck "tauri instance keeps docs/examples/habit-tracker/ and its subsection, and loses the factory's docs/examples/README.md" \
  bash -c 'test -f "$1/docs/examples/habit-tracker/README.md" && grep -q "^### habit_tracker (stack: tauri)" "$1/CLAUDE.md" && ! test -e "$1/docs/examples/README.md"' _ "$D"
# Fix wave 1, finding 7 (REQ-391): M6 copies back only the walked instance's own pipeline artifacts. An instance created
# from v3.2.0 already carries the pending stub under docs/examples/ and the documents init leaves under docs/ (ADR-002,
# the security README and rubric, the store checklist, the glossary, the backlog …), so a blind copy of its docs/ tree
# would nest docs/examples/habit-tracker/docs/examples/ and duplicate factory documents. The inherited set is measured:
# every file the scratch tauri instance holds under docs/ outside docs/examples/.
git -C "$D" ls-files docs | grep -v '^docs/examples/' > "$WORK/inherited.txt" || true
cat > "$WORK/copyclean.sh" <<'SH'
# copyclean.sh EXAMPLE INHERITED — EXAMPLE's copied docs/ holds no docs/examples/ and none of the inherited documents
E="$1/docs"; [ -d "$E" ] || exit 0
[ ! -e "$E/examples" ] || { echo "nested docs/examples/"; exit 1; }
while IFS= read -r p; do [ ! -e "$E/${p#docs/}" ] || { echo "inherited $p copied"; exit 1; }; done < "$2"
SH
ck "the scratch tauri instance's inherited docs/ set is measured (ADR-002, the glossary, the security rubric among them)" \
  bash -c 'for p in docs/adr/002-security-disposition-decision.md docs/GLOSSARY.md docs/security/RUBRIC.md; do grep -qx "$p" "$1" || exit 1; done' _ "$WORK/inherited.txt"
ck "the example's copied docs/ tree, when present, holds no docs/examples/ and no document the instance inherited" \
  bash "$WORK/copyclean.sh" "$ROOT/docs/examples/habit-tracker" "$WORK/inherited.txt"
mkdir -p "$WORK/hx-nest/docs/examples/habit-tracker" "$WORK/hx-glossary/docs"
echo x > "$WORK/hx-nest/docs/examples/habit-tracker/README.md"; echo x > "$WORK/hx-glossary/docs/GLOSSARY.md"
ck "negative controls: a nested docs/examples/ and a copied GLOSSARY.md are refused" \
  bash -c '! bash "$1" "$2/hx-nest" "$3" && ! bash "$1" "$2/hx-glossary" "$3"' _ "$WORK/copyclean.sh" "$WORK" "$WORK/inherited.txt"
# The plant: a spec, a plan, two ADRs and a security review — a [verifiable-model] REQ the plan claims with no proof, a
# missing ADR-009 the plan names, a duplicate ADR-001, a security review with no disposition — committed on a branch of
# the tauri instance whose refs/remotes/origin/main is init's commit, so the disposition gate evaluates (with no base ref
# it SKIPs, which would prove nothing).
cat > "$WORK/plant.sh" <<'SH'
set -e
E="$1"; mkdir -p "$E/specs" "$E/security" "$E/adr" "$E/plans"
printf -- "---\ntype: spec\n---\n- **REQ-001:** x [verifiable-model]\n" > "$E/specs/2026-10-05-habit-tracker-design.md"
printf -- "---\ntype: plan\nspec: 2026-10-05-habit-tracker\ndecisions: [ADR-009]\nimplements: [REQ-001]\n---\n" > "$E/plans/2026-10-05-habit-tracker-plan.md"
for n in 101 102; do printf -- "---\nid: ADR-001\n---\n# ADR-001\n" > "$E/adr/$n-x.md"; done
printf "SEC-001\n" > "$E/security/0.1.0-review.md"
git add -A && git commit -qm plant
SH
cat > "$WORK/gates.sh" <<'SH'
# gates.sh WANT — WANT=0: every document gate exits 0; WANT=1: every one exits non-zero. The scratch instance is never on
# a ship branch, so GITHUB_HEAD_REF and SPECFLOW_HEAD_BRANCH are unset (fix wave 1, finding 1; main's e73a942).
for g in check-traceability check-covers analyze-adr-plan-linkage check-architecture check-security-disposition; do
  rc=0; env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_BASE_REF=refs/remotes/origin/main bash "scripts/$g.sh" >/dev/null 2>&1 || rc=$?
  if [ "$1" = 0 ]; then [ "$rc" = 0 ] || { echo "$g exited $rc"; exit 1; }; else [ "$rc" != 0 ] || { echo "$g exited 0"; exit 1; }; fi
done
SH
cat > "$WORK/csd.sh" <<'SH'
# csd.sh — the disposition gate's own output against the instance's base ref, off any ship branch (as gates.sh)
env -u GITHUB_HEAD_REF -u SPECFLOW_HEAD_BRANCH SPECFLOW_BASE_REF=refs/remotes/origin/main bash scripts/check-security-disposition.sh
SH
ck "the tauri instance gets a base ref (refs/remotes/origin/main at init's commit)" \
  bash -c 'cd "$1" && git rev-parse -q --verify HEAD >/dev/null && git update-ref refs/remotes/origin/main HEAD' _ "$D"
ck "positive control: the same plant under the top-level docs/ fails every document gate, the disposition gate included" \
  bash -c 'cd "$1" && git checkout -qb plant-top refs/remotes/origin/main && bash "$2/plant.sh" docs && bash "$2/gates.sh" 1' _ "$D" "$WORK"
ck "the example is inert: the same plant under the example tree leaves every document gate green, the disposition gate SKIPping it as no docs/security/ change" \
  bash -c 'cd "$1" && git checkout -qb plant-example refs/remotes/origin/main && bash "$2/plant.sh" docs/examples/habit-tracker/docs && bash "$2/gates.sh" 0 && bash "$2/csd.sh" | grep -qF "touches no docs/security/"' _ "$D" "$WORK"
# P7 Build 2 fix wave 1, finding 1 (REQ-306): the scratch instance is never on the factory's ship branch. The disposition
# gate takes the ship version from SPECFLOW_HEAD_BRANCH, else GITHUB_HEAD_REF (disposition_gate.ship_branch_version), and
# on the factory's own ship PR CI exports GITHUB_HEAD_REF=ship/<version>: inherited, the instance evaluated that version,
# whose records are fenced out, and the inert check went red (main's e73a942 fixed the same leak in test_first_run.sh).
# Both plants give the same results with either variable naming a ship branch.
# Covers: REQ-306
for v in GITHUB_HEAD_REF SPECFLOW_HEAD_BRANCH; do
  ck "with $v=ship/9.9.9 exported (CI on a ship PR), the positive control still fails every document gate" \
    bash -c 'cd "$1" && git checkout -q plant-top && export "$3=ship/9.9.9" && bash "$2/gates.sh" 1' _ "$D" "$WORK" "$v"
  ck "with $v=ship/9.9.9 exported (CI on a ship PR), the example is still inert: every document gate green, the disposition gate SKIPping it" \
    bash -c 'cd "$1" && git checkout -q plant-example && export "$3=ship/9.9.9" && bash "$2/gates.sh" 0 && bash "$2/csd.sh" | grep -qF "touches no docs/security/"' _ "$D" "$WORK" "$v"
done
# Pinned the other way: the docs-wide article-citation check reads the example, so a copied-back document that cites an
# article by Roman numeral or by an undefined slug fails it (M6 in docs/examples/README.md runs it on the copied tree).
# Whether it should skip docs/examples/ is recorded in the plan's Build 2 "Deferred corrections", not decided here.
ck "the docs-wide article-citation check passes on the tauri instance with the example as shipped" \
  bash -c 'cd "$1" && bash tests/governance/test_reviews_use_slugs.sh' _ "$D"
ck "the docs-wide article-citation check reads the example: an undefined slug and a Roman-numeral citation planted there fail it, naming the file" \
  bash -c 'cd "$1" && f=docs/examples/habit-tracker/docs/specs/brainstorm.md && printf "Per Article %s and %s.\n" IV "art-bogus" > "$f" && rc=0 && out=$(bash tests/governance/test_reviews_use_slugs.sh 2>&1) || rc=$?; rm -f "$f"; [ "$rc" != 0 ] && grep -qF "$f cites articles by Roman numeral" <<<"$out" && grep -qF "$f:1: art-bogus" <<<"$out"' _ "$D"
# REQ-392 (P7 R12): the factory's record of the external product: what met looks like, the fields, the status.
# Covers: REQ-392
X="$ROOT/docs/examples/README.md"
factory_doc_ck "docs/examples/README.md records REQ-392: the definition of met, the fields, and a status line" "$X" \
  bash -c 'grep -q "^## External product (REQ-392)$" "$1" && for w in "release.yml" "run id" "Release URL" "signed" "BL-019"; do grep -qF -- "$w" "$1" || exit 1; done && grep -qE "^Status: (not met \(the v3\.2\.0 release'"'"'s known-limitations \(ship PR #62\) records the gate as open; docs/BACKLOG\.md BL-019\)\.|met on [0-9]{4}-[0-9]{2}-[0-9]{2}: .+)$" "$1"' _ "$X"
# Fix wave 1, finding 8: the status line names the v3.2.0 release's known-limitations without assuming it is on this
# tree (it arrives with the ship PR, #62, which may merge after this build); once it is here, it records the gate.
KL="$ROOT/docs/releases/3.2.0-known-limitations.md"
if [ -f "$KL" ]; then
  factory_doc_ck "the v3.2.0 known-limitations the status line names records the external-product gate (REQ-392)" "$KL" grep -qE "^## .*REQ-392" "$KL"
else
  echo "SKIP: docs/releases/3.2.0-known-limitations.md is not on this tree yet (ship PR #62) — the REQ-392 status line's source is not checked"
fi
factory_doc_ck "the fence lists docs/examples/README.md" "$ROOT/scripts/factory-only.txt" grep -qx 'docs/examples/README.md' "$ROOT/scripts/factory-only.txt"
# REQ-391 (P7 R10; design review, polish item 3): the walk's checklist is the factory maintainer's — it lives in the fenced
# index, never in the README that ships to tauri instances.
factory_doc_ck "docs/examples/README.md carries the habit-tracker walk's checklist M1–M6 and its gitleaks step" "$X" \
  bash -c 's=$(awk "/^## The habit-tracker walk \\(REQ-391\\)\$/{f=1; next} /^## /{f=0} f" "$1"); for m in 1 2 3 4 5 6; do grep -qE "^- \*\*M$m — " <<<"$s" || exit 1; done; grep -qF "gitleaks" <<<"$s"' _ "$X"
# P7 Build 2 final review, findings 2 and 7: Task 2.1 copies M1–M6 verbatim from the plan's "Maintainer checklist" — each
# bullet equals the plan's, so the environment probe stays after M2's configure-repo.sh, and the private-clone note, the
# allowed_signers line format, the unsigned-tag choice and the second Mac's account survive; M6's article-citation step is
# part of M6 itself in both (amendment D's PR folded the index's separate paragraph into it, BL-041).
P7PLAN="$ROOT/docs/plans/2026-10-03-factory-v3-2-p7-plan.md"
factory_doc_ck "docs/examples/README.md's M1–M6 equal the plan's Maintainer checklist bullets, verbatim (the probe after M2, the private clone)" "$P7PLAN" \
  python3 - "$X" "$P7PLAN" <<'PY'
import re, sys
idx, plan = (open(p).read() for p in sys.argv[1:])
walk = re.search(r"(?ms)^## The habit-tracker walk \(REQ-391\)\n(.*?)(?=^## |\Z)", idx).group(1)
check = re.search(r"(?ms)^## Maintainer checklist .*?\n(.*?)(?=^## |\Z)", plan).group(1)
for n in range(1, 7):
    a = re.search(rf"(?m)^- \*\*M{n} — .*$", walk)
    b = re.search(rf"(?m)^- \*\*M{n} — .*$", check)
    assert a and b and a.group(0) == b.group(0), n
m1 = re.search(r"(?m)^- \*\*M1 — .*$", walk).group(0)
assert "gh auth setup-git" in m1 and "after M2's `configure-repo.sh`" in m1
PY
factory_doc_ck "docs/examples/README.md: M6's copy-back runs the docs-wide article-citation check on the copied tree" "$X" \
  bash -c 's=$(awk "/^## The habit-tracker walk \\(REQ-391\\)\$/{f=1; next} /^## /{f=0} f" "$1"); grep -qF "bash tests/governance/test_reviews_use_slugs.sh" <<<"$s"' _ "$X"
# Fix wave 1, finding 7 (REQ-391): the copy rule names what M6 copies and excludes docs/examples/ and every document the
# scratch tauri instance inherited (measured above), so the rule tracks init.
factory_doc_ck "docs/examples/README.md: M6's copy rule copies only the instance's own artifacts, never docs/examples/ and never a document the instance inherited" "$X" \
  bash -c 's=$(awk "/^### M6.s copy rule/{f=1; next} /^##/{f=0} f" "$1" | tr "\n" " "); [ -n "$s" ] || exit 1; for w in "docs/specs/" "docs/adr/" "docs/architecture/" "docs/plans/" "docs/security/<version>-" "docs/releases/<version>-" "docs/reviews/" "docs/retrospectives/" "never \`docs/examples/\`"; do grep -qF -- "$w" <<<"$s" || exit 1; done; while IFS= read -r p; do grep -qF -- "\`$p\`" <<<"$s" || { echo "$p"; exit 1; }; done < "$2"' _ "$X" "$WORK/inherited.txt"
finish test_examples
