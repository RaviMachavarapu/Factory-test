#!/usr/bin/env bash
# REQ-371: docs/BACKLOG.md lists every deferred proposal with an id (BL-NNN, unique, never reused — art-naming-tagging);
# each entry has a source, a listed date, a proposal and a status, and a decided one a decision line in the grammar
# naming the retrospective that decided it; every retrospective records exactly one decision line per id still open at
# its date; /retrospective requires it; an instance starts from templates/BACKLOG.md with no entry.
# Covers: REQ-371
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
B=docs/BACKLOG.md
ck "docs/BACKLOG.md exists" test -f "$B"
ck "templates/BACKLOG.md exists and lists no entry" bash -c 'test -f templates/BACKLOG.md && ! grep -qE "^### BL-[0-9]{3}" templates/BACKLOG.md'
ck "every entry is well-formed; ids unique; decided entries name an existing retrospective" python3 - "$B" <<'PY'
import os, re, sys
t = open(sys.argv[1]).read()
ents = re.split(r"(?m)^(?=### BL-\d{3} — )", t)[1:]
ids = [re.match(r"### (BL-\d{3}) — \S", e).group(1) for e in ents]
assert len(ids) == len(set(ids)), [i for i in ids if ids.count(i) > 1]
assert ids == sorted(ids), ids
DEC = r"(accepted \(landed: [^)]+\)|accepted \(target: [^)]+\)|rejected \([^)]+\)|deferred \([^)]+\))"
for i, e in zip(ids, ents):
    for f in ("Source", "Listed", "Proposal", "Status"):
        assert re.search(rf"(?m)^- \*\*{f}:\*\* \S", e), (i, f)
    assert re.search(r"(?m)^- \*\*Listed:\*\* \d{4}-\d{2}-\d{2}$", e), i
    st = re.search(r"(?m)^- \*\*Status:\*\* (open|decided)$", e)
    assert st, (i, "status")
    d = re.search(rf"(?m)^- \*\*Decision:\*\* {DEC} — (docs/retrospectives/\S+\.md)$", e)
    assert (st.group(1) == "decided") == bool(d), (i, "decided needs exactly one Decision line")
    if d:
        assert os.path.isfile(d.group(2)), (i, d.group(2))
PY
# P7 fresh-eyes review, findings 2 and 22 (REQ-371): a retrospective records exactly one decision line for each id still
# open at its date — listed before it and not decided by an earlier retrospective (the date of the file the id's
# Decision line names); an id an earlier retrospective decided needs no line in a later one.
decision_lines() {  # decision_lines ROOT — ROOT's retrospectives each record exactly one line per id open at their date
  python3 - "$1" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
t = open(os.path.join(root, "docs/BACKLOG.md")).read()
DEC = r"(accepted \(landed: [^)]+\)|accepted \(target: [^)]+\)|rejected \([^)]+\)|deferred \([^)]+\))"
ids = {}
for e in re.split(r"(?m)^(?=### BL-\d{3} — )", t)[1:]:
    i = re.match(r"### (BL-\d{3})", e).group(1)
    listed = re.search(r"(?m)^- \*\*Listed:\*\* (\d{4}-\d{2}-\d{2})$", e).group(1)
    d = re.search(r"(?m)^- \*\*Decision:\*\* .* — docs/retrospectives/(\d{4}-\d{2}-\d{2})-\S+\.md$", e)
    ids[i] = (listed, d.group(1) if d else None)
for r in sorted(glob.glob(os.path.join(root, "docs/retrospectives/[0-9]*-*.md"))):
    date = os.path.basename(r)[:10]
    sec = re.search(r"(?ms)^## Decisions on Prior Proposals\s*$(.*?)(?=^## |\Z)", open(r).read())
    for i, (listed, decided) in ids.items():
        if listed < date and (decided is None or decided >= date):
            n = len(re.findall(rf"(?m)^- {i}: {DEC}", sec.group(1))) if sec else 0
            assert n == 1, (os.path.basename(r), i, n)
PY
}
ck "every retrospective records exactly one decision line per id still open at its date" decision_lines .
X="$(mktemp -d)"; mkdir -p "$X/docs/retrospectives"
printf '# Backlog\n\n### BL-001 — one\n- **Source:** s\n- **Listed:** 2026-01-01\n- **Proposal:** p\n- **Status:** decided\n- **Decision:** rejected (no) — docs/retrospectives/2026-02-01-a.md\n\n### BL-002 — two\n- **Source:** s\n- **Listed:** 2026-01-01\n- **Proposal:** p\n- **Status:** open\n' > "$X/docs/BACKLOG.md"
printf '# A\n\n## Decisions on Prior Proposals\n\n- BL-001: rejected (no)\n- BL-002: deferred (until v4)\n\n## Open Questions\n' > "$X/docs/retrospectives/2026-02-01-a.md"
printf '# B\n\n## Decisions on Prior Proposals\n\n- BL-002: deferred (until v4)\n\n## Open Questions\n' > "$X/docs/retrospectives/2026-03-01-b.md"
ck "fixture, two retrospectives: an id decided by the first needs no line in the second" decision_lines "$X"
printf '# B\n\n## Decisions on Prior Proposals\n\n## Open Questions\n' > "$X/docs/retrospectives/2026-03-01-b.md"
ck "fixture: the second retrospective without a line for the id still open — refused" no decision_lines "$X"
printf '# B\n\n## Decisions on Prior Proposals\n\n- BL-002: deferred (until v4)\n- BL-002: rejected (no)\n\n## Open Questions\n' > "$X/docs/retrospectives/2026-03-01-b.md"
ck "fixture: two lines for one id in one retrospective — refused (exactly one)" no decision_lines "$X"
printf '# A\n\n## Decisions on Prior Proposals\n\n- BL-002: deferred (until v4)\n\n## Open Questions\n' > "$X/docs/retrospectives/2026-02-01-a.md"
printf '# B\n\n## Decisions on Prior Proposals\n\n- BL-002: deferred (until v4)\n\n## Open Questions\n' > "$X/docs/retrospectives/2026-03-01-b.md"
ck "fixture: the retrospective that decides an id still records its line" no decision_lines "$X"
rm_tree "$X"
R=.claude/commands/retrospective.md
ck "/retrospective reads docs/BACKLOG.md and requires one decision line per open id, in the grammar" \
  bash -c 't=$(tr "\n" " " < "$1"); grep -qF "docs/BACKLOG.md" <<<"$t" && grep -qF "one line per id" <<<"$t" && grep -qF -- "- BL-NNN: accepted (landed:" <<<"$t" && grep -qF "new \`BL-NNN\`" <<<"$t" && grep -qF "templates/BACKLOG.md" <<<"$t"' _ "$R"
ck "docs/retrospectives/README.md points at the backlog (REQ-371)" grep -qF 'docs/BACKLOG.md' docs/retrospectives/README.md
for w in 'gh pr merge' 'medium_cap' 'next_version' 'profile' 'base binding' 'ruleset' 'GPG' 'GHCR' 'never-pushed' 'Dockerfile' \
         'pull_request_target' 'REQ-392' 'v0.0.1-demo'; do
  factory_doc_ck "the factory's backlog lists the deferred proposal on '$w'" "$B" grep -qF -- "$w" "$B"
done
# P7 fresh-eyes review, finding 1 (REQ-371; P7 R17): "every deferred proposal from prior retrospectives" — the
# 2026-05-28 retrospective's deferred proposals 5, 6, 8 and 10, the 2026-06-09 retrospective's five undecided proposals
# and its carried v0.0.1-demo re-tag each have an entry whose Source names the historical file (removed from the tree in
# 02677f8; read with git show 02677f8^:<path>); one a v3.2 REQ absorbed says which.
factory_doc_ck "the backlog lists every proposal the two prior retrospectives deferred or left undecided, by number" "$B" python3 - "$B" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
src = re.findall(r"(?m)^- \*\*Source:\*\* retrospective `02677f8\^:docs/retrospectives/(2026-05-28-v3-1-cutover|2026-06-09-enforcement-remediation)\.md`, (proposal #\d+|the carried open item)\b", t)
want = {("2026-05-28-v3-1-cutover", f"proposal #{n}") for n in (5, 6, 8, 10)} \
     | {("2026-06-09-enforcement-remediation", f"proposal #{n}") for n in (1, 2, 3, 4, 5)} \
     | {("2026-06-09-enforcement-remediation", "the carried open item")}
assert set(src) == want and len(src) == len(want), sorted(want ^ set(src))
for req in ("REQ-310", "REQ-395", "REQ-382", "REQ-324"):
    assert re.search(rf"(?m)^- \*\*Absorbed:\*\* .*{req}", t), req
PY
# P7 design review, polish item 3 (REQ-371): BL-002's Source names why amendment C did not adopt it (a REQ-322 kernel and
# ADR-002 change), never a P7 ruling it does not rest on (R13 is the backlog's landing, not this decision).
# Covers: REQ-371
factory_doc_ck "BL-002's Source: not adopted by amendment C because it is a REQ-322 kernel and ADR-002 change; no stray P7 R13" "$B" \
  bash -c 'l=$(awk "/^### BL-002 /{f=1; next} /^### /{f=0} f" "$1" | grep -F -- "- **Source:**"); grep -qF "not adopted by amendment C: a REQ-322 kernel and ADR-002 change" <<<"$l" && ! grep -qF "P7 R13" <<<"$l"' _ "$B"
# P7 design review run 2, finding 4 (REQ-371), as retired by the P7 retrospective's documentation patch (its Proposed
# Changes, item 9; BL-041): BL-028..031 keep their Absorbed lines and stay open until a retrospective records their
# decisions (docs/retrospectives/2026-10-04-v3-2-closeout.md's lines carry forward; the next retrospective decides). The
# pin no longer forbids a decided status: an entry is open with no Decision line, or decided with exactly one Decision
# line naming a retrospective — checked on the real backlog and on a fixture where BL-028 is decided.
# Covers: REQ-371
bl28_31() {  # bl28_31 BACKLOG — BL-028..031 each carry an Absorbed line and are open (no Decision) or decided (one Decision)
  python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
for n in (28, 29, 30, 31):
    m = re.search(rf"(?ms)^### BL-0{n} .*?(?=^### |\Z)", t)
    assert m, n
    sec = m.group(0)
    assert re.search(r"(?m)^- \*\*Absorbed:\*\* \S", sec), n
    st = re.search(r"(?m)^- \*\*Status:\*\* (open|decided)$", sec)
    dec = re.findall(r"(?m)^- \*\*Decision:\*\* .* — docs/retrospectives/\d{4}-\d{2}-\d{2}-\S+\.md$", sec)
    assert st and ((st.group(1) == "open" and not dec) or (st.group(1) == "decided" and len(dec) == 1)), n
PY
}
factory_doc_ck "BL-028..031: Absorbed lines kept; each open with no Decision line, or decided with one naming a retrospective" "$B" bl28_31 "$B"
if ! instance; then
BLX="$(mktemp -d)"
python3 - "$B" "$BLX/decided.md" "$BLX/nodecision.md" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"(?ms)^### BL-028 .*?(?=^### |\Z)", t).group(0)
d = m.replace("- **Status:** open\n", "- **Status:** decided\n- **Decision:** accepted (landed: REQ-310) — docs/retrospectives/2099-01-01-x.md\n", 1)
open(sys.argv[2], "w").write(t.replace(m, d, 1))
open(sys.argv[3], "w").write(t.replace(m, m.replace("- **Status:** open\n", "- **Status:** decided\n", 1), 1))
PY
  factory_doc_ck "…a fixture where a retrospective decided BL-028 (one Decision line) passes the pin" "$B" bl28_31 "$BLX/decided.md"
  factory_doc_ck "…a fixture where BL-028 is decided with no Decision line fails it" "$B" no bl28_31 "$BLX/nodecision.md"
rm -rf "$BLX"
fi
# The P7 retrospective's documentation patch (BL-041; docs/retrospectives/2026-10-04-v3-2-closeout.md, Proposed Changes,
# item 4; PR #68 verifier run 1, findings 1–2): the P7 plan's header records what the builds actually changed (D3, D15,
# R1's table), D1's rule change under amendment D, M0b's measurement in UTC and under pull_request only, and Build 2's two
# accepted readings — appended, never rewriting the reviewed text silently.
# Covers: REQ-371
P7P=docs/plans/2026-10-03-factory-v3-2-p7-plan.md
factory_doc_ck "P7 plan header: the corrections the retrospective's documentation patch owes (D1, D3, D14, D15, D17, Build 2's readings)" "$P7P" \
  python3 - "$P7P" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
nc = next(l for l in t.splitlines() if l.startswith("- **Not claimed, with the reason:**"))
assert "`release-tag.sh` is unchanged except its header comment" in nc and "`a465147`" in nc and "`.github/workflows/verifier.yml`" in nc, nc[:200]
assert "`signers.py`, `release-tag.sh` and `release.yml` are unchanged" not in nc
r2 = next(l for l in t.splitlines() if l.startswith("- **R2 — amendment C"))
assert "amendment D (BL-041, D1)" in r2
assert "or any workflow — no longer true for Build 1:" in t
note = re.search(r"(?ms)^\*\*Corrected by the P7 retrospective's documentation patch.*?$", t)
assert note, "the dated note after R1's table"
for f in (".github/workflows/verifier.yml", "scripts/init-project.sh", "tests/governance/test_workflow_health.sh",
          "tests/governance/test_backlog.sh", "tests/governance/test_constitution_articles.sh",
          "tests/governance/test_constitution_amendment_b.sh", "tests/governance/test_reviews_use_slugs.sh",
          "tests/governance/test_spec_commands.sh", "docs/BACKLOG.md"):
    assert f"`{f}`" in note.group(0), f
m0b = next(l for l in t.splitlines() if l.startswith("- **M0b — the timeline probe"))
assert "A merge precondition of Build 1's PR, measured on probe PR #67 (run 37169624336, 2026-10-04 UTC)" in m0b and "Before Build 1's classifier change" not in m0b
r10 = next(l for l in t.splitlines() if l.startswith("- **R10 — REQ-391"))
assert "`tests/governance/test_reviews_use_slugs.sh` (gates section 3) also reads `docs/examples/`" in r10 and "as narrowed by" not in r10, r10[-200:]
for w in ("Still owed under BL-041 (owner kpingali123, before the 3.2.1 ship)", "D13", "D19", "`implements:`", "Review Focus 5",
          "the documents an instance inherits", "M6 article-citation step"):
    assert w in note.group(0), w
assert t.count("Accepted as the plan's reading by the retrospective (`docs/retrospectives/2026-10-04-v3-2-closeout.md`") == 2
s0 = next(l for l in t.splitlines() if l.startswith("- [x] **Step 0: The timeline read"))
assert "**Measured 2026-10-04 UTC" in s0 and "under a `pull_request` event only" in s0 and "not measured" in s0
d17 = next(l for l in t.splitlines() if l.startswith("- D17."))
assert "2026-10-04 UTC" in d17 and "under a `pull_request` event only" in d17
for l in (s0, d17):
    for w in ("Owner: kpingali123.", "a bound waiver naming the merge commit's first parent clears a refused legacy waiver at the tag",
              "`scripts/release-tag.sh 3.2.1 --dry-run`", "does not measure the workflow token",
              "measured by the first `release.yml` run itself", "`waiver-timeline-unknown`"):
        assert w in l, w
PY
# The post-3.2.1 records patch (patch/post-3-2-1-records, 2026-10-05; BL-022): the P7 plan's R18 gains a dated correction
# — the 3.2.1 ship carried each residual to 2027-01-31, not Task 1.6's 2026-12-15 (ADR-002 rule 5, the #76 verifier's
# margin finding) — appended to R18, never rewriting its reviewed text.
# Covers: REQ-371
factory_doc_ck "P7 plan R18: the dated correction (the 3.2.1 ship carried each residual to 2027-01-31, not Task 1.6's 2026-12-15)" "$P7P" \
  python3 - "$P7P" <<'PY'
import sys
t = open(sys.argv[1]).read()
r18 = next(l for l in t.splitlines() if l.startswith("- **R18 — which record of a residual governs"))
assert "carries each of these SEC ids forward (ADR-002 rule 4, `check-security-disposition.sh`) with Task 1.6's expiry" in r18
for w in ("(corrected by the post-3.2.1 records patch, 2026-10-05; BL-022)", "the 3.2.1 ship carried each of these residuals to 2027-01-31, not Task 1.6's 2026-12-15",
          "ADR-002 rule 5", "the PR #76 verifier's margin finding", "`docs/security/3.2.1-disposition.md`"):
    assert w in r18, w
PY
# The same patch (BL-022, BL-043): BL-043's Planned line keeps its 2026-10-04 text and appends that the drop was confirmed by
# the maintainer's merge of PR #77 (a retrospective records the decision), and BL-022's records the release and the cap's
# return to 5; their Status lines are unchanged and neither gains a Decision line (only a retrospective writes those).
# Covers: REQ-371
factory_doc_ck "BL-043 and BL-022: Planned lines record v3.2.1's release (the 2026-10-04 text kept, a dated confirmation by merging PR #77 appended; the cap back to 5); Status unchanged, no new Decision" "$B" \
  python3 - "$B" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
def entry(i):
    return re.search(r"(?ms)^### " + i + r" .*?(?=^### |\Z)", t).group(0)
e43, e22 = entry("BL-043"), entry("BL-022")
p43 = next(l for l in e43.splitlines() if l.startswith("- **Planned:**"))
# The 2026-10-04 text is kept as written (append-only history); the 2026-10-05 line records the merge's confirmation.
for w in ("- **Planned:** none — decided at the 3.2.1 ship (its `/release --tag` posts the comment, or the convention is dropped); owner kpingali123.",
          "2026-10-04: decided at the 3.2.1 ship: proposed dropped, the ship/3.2.1 PR #77",
          "2026-10-05: the maintainer confirmed the drop by merging PR #77 (v3.2.1 released 2026-10-05); the next retrospective records the decision."):
    assert w in p43, w
assert p43.index("2026-10-04:") < p43.index("2026-10-05:"), p43
assert "- **Status:** open" in e43 and "- **Decision:**" not in e43
p22 = next(l for l in e22.splitlines() if l.startswith("- **Planned:**"))
assert "v3.2.1 released 2026-10-05 (tag on `609abbc`, run 37302823217); the cap returned to 5 by `patch/post-3-2-1-records`" in p22, p22
assert "- **Status:** decided" in e22 and e22.count("- **Decision:**") == 1
PY
# The same patch (PR #70 verifier run 1, findings 1, 2, 4, 6): the merged retrospective carries a dated amendment note,
# names PR #69 where it said "this PR", dates PR #70's opening in UTC, and records item 2's patch-tier reading.
# Covers: REQ-371
RETRO=docs/retrospectives/2026-10-04-v3-2-closeout.md
factory_doc_ck "the v3.2 retrospective: the amendment note, PR #69 named for 'this PR', the UTC date, the patch-tier reading" "$RETRO" \
  python3 - "$RETRO" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
n = " ".join(t.split())
for w in ("**Amended after its merge (PR #69, `966aff6`).**", "PR #70 (`patch/medium-cap-5`, `14df67e`)",
          "Each amendment is signed off by its own PR's merge, not by PR #69's.", "BL-037",
          "Nothing below is applied by PR #69 except item 10",
          "Merging PR #69 signed these off; PR #70's and this documentation patch's merges sign off their own amendments",
          "the same UTC date, 2026-10-04 (the retrospective was written on the evening of 2026-10-03 local time)",
          "Amendment D (BL-041) is proposed to add to `.claude/rules/review-gate.md`'s patch-tier bullet",
          "until amendment D lands such a change is outside the patch tier as `.claude/rules/review-gate.md` reads today",
          "went through on the maintainer's judgement, recorded here",
          "owed to the 3.2.1 ship PR, whose security artifacts they are (PR #71 verifier run 1, finding 1), owner kpingali123"):
    assert w in n, w
for w in ("Nothing below is applied by this PR except item 10", "Merging this PR signs these off too",
          "the day after this retrospective was written", "takes the patch tier, as PR #70 did"):
    assert w not in n, w
i = t.index("**Amended after its merge"); assert t.index("Times are UTC.") < i < t.index("**Vocabulary.**")
PY
if ! instance; then
  W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
  D="$W/i"; copy_template "$D"
  ck "init: an instance's docs/BACKLOG.md is templates/BACKLOG.md (the factory's ids are not the instance's)" \
    bash -c 'cd "$1" && bash scripts/init-project.sh --name Py </dev/null >/dev/null 2>&1 && cmp -s docs/BACKLOG.md templates/BACKLOG.md' _ "$D"
  ck "…and the instance passes this test" bash -c 'cd "$1" && bash tests/governance/test_backlog.sh >/dev/null' _ "$D"
  # PR #60 run 1 (REQ-371): a missing templates/BACKLOG.md is a hard failure, never a silent skip that leaves the
  # factory's own backlog (its BL ids) in the new instance.
  D2="$W/i2"; copy_template "$D2"; rm -f "$D2/templates/BACKLOG.md"
  ck "init: a missing templates/BACKLOG.md fails init with a message naming it, never silently keeping the factory's backlog" \
    bash -c 'cd "$1" && ! SPECFLOW_NO_SCAFFOLD=1 bash scripts/init-project.sh --name Py </dev/null >"$1/out" 2>&1 && grep -qF "templates/BACKLOG.md" "$1/out"' _ "$D2"
  # P7 Build 1 fix wave 1, FIX 5 (REQ-371): the guard is a precondition, checked before any effect — a missing template
  # leaves no .specflow.yml behind (a re-run would be refused as "already present") and the factory's tree untouched,
  # and the message never tells the user to re-run a command that would then refuse.
  ck "…before any effect: no .specflow.yml written, docs/BACKLOG.md and stacks/ untouched, no 're-run' advice" \
    bash -c 'cd "$1" && [ ! -e .specflow.yml ] && cmp -s docs/BACKLOG.md "$2/docs/BACKLOG.md" && [ -d stacks ] && ! grep -qi "re-run" out' _ "$D2" "$ROOT"
else
  echo "SKIP (instance: init-project.sh runs only in the template source): the init cases of test_backlog"
fi
# PR #78 verifier run 1 (REQ-371, REQ-382; BL-022): the re-dating patch is item 7's patch and says so — BL-037 and BL-038
# record what PR #78 did, and BL-046 tracks the eight mediums the next ship must bring within cap 5.
# Covers: REQ-371
factory_doc_ck "BL-037 and BL-038: a dated 2026-10-05 note says PR #78 is item 7's re-dating patch; BL-046 tracks the next ship's eight mediums" "$B" \
  python3 - "$B" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
def entry(i):
    return re.search(r"(?ms)^### " + i + r" .*?(?=^### |\Z)", t).group(0)
for i in ("BL-037", "BL-038"):
    e = entry(i)
    assert "2026-10-05: the re-dating patch is PR #78" in e and "item 7" in e, i
e = entry("BL-046")
assert "- **Status:** open" in e and "PR #78 verifier run 1" in e and "SEC-020" in e and "medium_cap" in e
PY

finish test_backlog
