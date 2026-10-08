#!/usr/bin/env bash
# The onboarding surface (README, CLAUDE.md, glossary, init, rules) describes
# the current pipeline for both profiles and both paths; no stale copies
# (2026-06-09 review Theme 3; REQ-308); README and CLAUDE.md drop SpecKit (REQ-302).
# Covers: REQ-308, REQ-302, REQ-310, REQ-312, REQ-382
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
section() { awk -v h="$2" '$0 ~ "^## " h {f=1; next} /^## /{f=0} f' "$1"; }
subsection() { awk -v h="$2" '$0 ~ "^#### " h "$" {f=1; next} f && /^#### |^### /{exit} f' "$1"; }
for ph in BRAINSTORM SPECIFY ARCHITECTURE PLAN TASKS ANALYZE IMPLEMENT VALIDATE SECURITY RELEASE; do ck "README names $ph" grep -q "$ph" README.md; done
for s in init-project.sh run-quality-gates.sh run-verifier.sh analyze-adr-plan-linkage.sh; do ck "README mentions $s" grep -q "$s" README.md; done
ck "no stale superpowers:brainstorm" no grep -rqE 'superpowers:brainstorm([^i]|$)' README.md CLAUDE.md scripts/init-project.sh templates .claude/commands
ck "no specflow-scaffold copies" [ ! -e specflow-scaffold -a ! -e specflow-scaffold.zip ]
ck "no root rule duplicates" [ ! -e review-gate.md -a ! -e tdd.md ]
ck "tdd.md cites art-test-first" grep -q art-test-first .claude/rules/tdd.md
for d in docs/adr docs/architecture docs/security docs/releases docs/retrospectives tests/governance; do ck "init creates $d" grep -q "$d" scripts/init-project.sh; done
ck "init writes .specflow.yml" grep -q '\.specflow\.yml' scripts/init-project.sh
ck "init is v3.2" grep -q 'v3\.2' scripts/init-project.sh
ck "init no longer v2 or v3.1" no grep -qE 'SpecFlow v2|v3\.1' scripts/init-project.sh
aud=$(section README.md 'Who this is for')
for w in guided engineer 'You get' 'You do not get yet' hosting auto-update signing Windows Linux mobile; do ck "audience names '$w'" grep -qi -- "$w" <<<"$aud"; done
ck "fully tested defined with the security floor" grep -qi 'security floor' <<<"$(grep -i 'fully tested' <<<"$aud" || true)"
ck "Quick Start step 0 runs init" grep -qE '^0\. .*init-project\.sh' <<<"$(section README.md 'Quick Start')"
ck "Quick Start step 0 no longer claims path is asked first (F-5/W-8)" no grep -q 'profile and path first' README.md
ck "Quick Start step 0 names the guided menu question" grep -qi 'what are you building' <<<"$(section README.md 'Quick Start')"
pre=$(section README.md 'Prerequisites')
ck "prerequisites: ### Python" grep -q '^### Python' <<<"$pre"
for os in macOS Ubuntu; do ck "prerequisites cover $os" grep -q "$os" <<<"$pre"; done
ck "prerequisites give --version checks" grep -q -- '--version' <<<"$pre"
ck "prerequisites give --doctor" grep -q 'init-project.sh --doctor' <<<"$pre"
for os in macOS Ubuntu; do
  block=$(subsection README.md "$os")
  ck "$os block installs git" grep -qi 'git' <<<"$block"
  ck "$os block installs gh" grep -qi 'gh ' <<<"$block"
  ck "$os block installs jq" grep -qi 'jq' <<<"$block"
  ck "$os block installs Claude Code" grep -qi 'claude-code\|claude --version' <<<"$block"
  ck "$os block gives a --version check for git/gh/jq/claude" [ "$(grep -c -- '--version' <<<"$block")" -ge 4 ]
  ck "$os block installs Superpowers" grep -qi 'superpowers' <<<"$block"
done
pysub() { awk -v h="$1" '/^### Python/{p=1;next} p && /^### /{exit} p && $0 ~ "^#### " h "$" {f=1;next} f && /^#### /{exit} f' README.md; }
for os in macOS Ubuntu; do
  block=$(pysub "$os")
  ck "Python $os block installs 3.12" grep -q '3\.12' <<<"$block"
  ck "Python $os block creates a venv (Homebrew and Ubuntu pythons are externally managed)" grep -q -- '-m venv' <<<"$block"
  ck "Python $os block activates the venv before pip" python3 -c 'import sys; s=sys.stdin.read(); sys.exit(not (0 <= s.find("activate") < s.find("pip install")))' <<<"$block"
  ck "Python $os block installs scripts/requirements.txt" grep -q 'pip install -r scripts/requirements.txt' <<<"$block"
done
ck "--doctor's gate-tool advice creates a venv" grep -q 'python3 -m venv' scripts/init-project.sh
ck "Dafny only when the project has proofs" grep -qiE 'only (when|if)' <<<"$(grep -i dafny <<<"$pre" || true)"
ck "README links docs/GLOSSARY.md" grep -q docs/GLOSSARY.md README.md
n=$(grep -c '^### ' docs/GLOSSARY.md 2>/dev/null || true); ck "glossary has 20+ terms (${n:-0})" [ "${n:-0}" -ge 20 ]
for f in README.md CLAUDE.md; do
  for b in 'design/<slug>' 'build/<slug>-N' 'build/sec-<id>' 'ship/<version>' 'patch/<slug>' 'phase/spec-<slug>' 'phase/arch-<slug>' 'phase/plan-<slug>' 'impl/plan-N-<plan slug>' 'impl/sec-<id>'; do
    ck "$f names $b" grep -qF "$b" "$f"
  done
done
for c in specify specflow-plan specflow-tasks analyze; do ck "CLAUDE.md names /$c" grep -qE "\`/$c[ \`]" CLAUDE.md; done
ck "README and CLAUDE.md drop SpecKit (REQ-302)" no grep -qiE 'speckit|spec-kit' README.md CLAUDE.md
ck "README states the public-repository trade-off" grep -qi 'public repositor' README.md
# #33 fourth run finding 6: even a public repository does not enforce the gate mechanically — an admin can merge
# past the checks and, under pull_request, the workflow file comes from the PR.
fprn=$(awk '/^A note on free private repositories/{f=1} /^## Quick Start/{exit} f' README.md | tr '\n' ' ' | tr -s ' ')
ck "README's public-repository sentence no longer promises mechanical enforcement" no grep -qi 'enforce the gate mechanically' <<<"$fprn"
ck "README's public-repository sentence names the admin bypass and the PR-supplied workflow file" \
  bash -c 'grep -qi "admin" <<<"$1" && grep -qF "verifier.yml" <<<"$1"' _ "$fprn"
# Private organisation membership may report CONTRIBUTOR/NONE, which rejects a member's marker or waiver (PR #34
# verifier finding 11: cite GitHub's documented values and say only what the docs say).
enfn=$(awk '/merges via PR with:/{f=1} /^## Key Files/{exit} f' README.md | tr '\n' ' ' | tr -s ' ')
ck "README: private organisation membership may report CONTRIBUTOR/NONE, rejecting a member's marker or waiver" \
  bash -c 'grep -qF "author_association" <<<"$1" && grep -qF "CONTRIBUTOR" <<<"$1" && grep -qF "NONE" <<<"$1" && grep -qi "membership public" <<<"$1" && grep -qF "OWNER" <<<"$1"' _ "$enfn"
ck "README: the author_association sentence cites GitHub's documented values" \
  grep -qF 'https://docs.github.com/en/graphql/reference/enums#commentauthorassociation' <<<"$enfn"
ck "README: quotes the documented MEMBER meaning and says the private/not-visible case is undocumented" \
  bash -c 'grep -qF "a member of the organization that owns the repository" <<<"$1" && grep -qi "visible to" <<<"$1" && grep -qi "viewer" <<<"$1" && grep -qi "do not say" <<<"$1"' _ "$enfn"
# PR #34 second-run finding 7: widening the classifier re-scopes open PRs that touch model-instruction Markdown.
ck "README: an open PR touching model-instruction Markdown moves from full to full+code; its APPROVE is mode-mismatch until re-run" \
  bash -c 'grep -qF "from \`full\` to \`full+code\`" <<<"$1" && grep -qF "mode-mismatch" <<<"$1" && grep -qi "until the verifier is re-run" <<<"$1"' _ "$enfn"
# PR #34 third-run finding 6: a skill or prompt change moves prompt_sha256 at main, so every open PR's APPROVE is
# rejected as prompt-mismatch until re-run — not only PRs touching instruction Markdown.
ck "README: a skill/prompt change invalidates every open PR's APPROVE (prompt-mismatch) until re-run" \
  bash -c 'grep -qF "prompt-mismatch" <<<"$1" && grep -qF "headless-prompt.md" <<<"$1" && grep -qF "prompt_sha256" <<<"$1"' _ "$enfn"
ck "README: model-instruction Markdown is any CLAUDE.md or CLAUDE.local.md at any depth" \
  bash -c 'grep -qF "CLAUDE.local.md" <<<"$1" && grep -qi "any depth" <<<"$1"' _ "$enfn"
# P1b (REQ-308): app-stack prerequisites, honest about macOS-only, and the new terms.
appsec() { awk -v h="$1" '$0 ~ "^### " h {f=1; next} f && /^##/{exit} f' README.md; }
for s in Tauri Flutter; do
  blk=$(appsec "$s")
  ck "prerequisites: ### $s" grep -q . <<<"$blk"
  ck "$s: copy-paste installs with --version checks" grep -q -- '--version' <<<"$blk"
  ck "$s: xcode-select --install" grep -qF 'xcode-select --install' <<<"$blk"
  ck "$s: --doctor for the stack" grep -qiF -- "--doctor --stack $(tr '[:upper:]' '[:lower:]' <<<"$s")" <<<"$blk"
  ck "$s: honest one-line Linux note" grep -qiE 'macos only|only on macos' <<<"$blk"
  ck "$s: states the per-PR macOS CI cost and the monthly budget" bash -c "grep -qi 'macOS minutes' <<<\"\$1\" && grep -q '200' <<<\"\$1\"" _ "$blk"
done
ck "Tauri: sources ~/.cargo/env before verifying rustup (fresh shell has no ~/.cargo/bin on PATH)" python3 -c 'import sys; s=sys.stdin.read(); a=s.find(".cargo/env"); b=s.find("rustup --version"); sys.exit(not (0 <= a < b))' <<<"$(appsec Tauri)"
ck "CLAUDE.md project map names .specflow/pack.yml (the instance path) and stacks/<stack>/ (template source)" bash -c "grep -q '.specflow/pack.yml' CLAUDE.md && grep -qF 'stacks/<stack>/' CLAUDE.md"
# The pinned rust_version comes from the tauri pack: stacks/tauri/pack.yml in the template source, .specflow/pack.yml in
# a tauri instance; any other instance (no tauri pack) checks that the line names an exact x.y.z toolchain.
trv() { python3 scripts/lib/specflow/config.py --file "$1" get "$2" 2>/dev/null || true; }
TRV=$(trv stacks/tauri/pack.yml rust_version)
[[ -z "$TRV" && "$(trv .specflow/pack.yml stack)" == tauri ]] && TRV=$(trv .specflow/pack.yml rust_version)
if [[ -n "$TRV" ]]; then
  ck "Tauri: installs the pinned Rust toolchain (the tauri pack's rust_version, $TRV)" grep -qF "rustup toolchain install $TRV " <<<"$(appsec Tauri)"
else
  ck "Tauri: installs a pinned Rust toolchain (an exact x.y.z)" grep -qE 'rustup toolchain install [0-9]+\.[0-9]+\.[0-9]+ ' <<<"$(appsec Tauri)"
fi
ck "Flutter: verifies the SDK revision after cloning" grep -qF 'rev-parse HEAD' <<<"$(appsec Flutter)"
ck "the free-private-repository note mentions macOS minutes" awk '/free-tier private GitHub repository|free private repositor/{f=1} f && /macOS minutes/{hit=1} /^## Quick Start/{exit} END{exit !hit}' README.md
ck "the first-run row says app stacks run only when --doctor finds them" bash -c "grep -E 'test_first_run\.sh' README.md | grep -q -- '--doctor'"
ck "Flutter: flutter precache --macos" grep -qF 'flutter precache --macos' <<<"$(appsec Flutter)"
ck "app sections sit before ### Python" awk '/^### Tauri/{t=NR} /^### Flutter/{f=NR} /^### Python/{p=NR} END{exit !(t && f && p && t < p && f < p)}' README.md
ck "audience names the app stacks" grep -qE 'Tauri' <<<"$aud"
for t in 'Pack minimum' 'Smoke hook' 'Store checklist'; do ck "glossary defines $t" grep -qx "### $t" docs/GLOSSARY.md; done
ck "CLAUDE.md maps the store checklist" grep -qF 'docs/releases/store-checklist.md' CLAUDE.md
ck "README documents SPECFLOW_NO_SCAFFOLD as test-only" grep -q 'SPECFLOW_NO_SCAFFOLD' README.md

# F-6: a python instance keeps the demo's .dfy proofs, so the default Enter
# path needs Dafny — README must give an install command, not just a caveat.
ck "prerequisites: ### Dafny" grep -q '^### Dafny' README.md
ck "### Dafny sits before ### Python" awk '/^### Dafny/{d=NR} /^### Python/{p=NR} END{exit !(d && p && d < p)}' README.md
dafny_blk=$(appsec Dafny)
ck "Dafny: macOS install" grep -qF 'brew install dafny' <<<"$dafny_blk"
ck "Dafny: Ubuntu install (pinned 4.11.0)" grep -qF 'dafny-lang/dafny/releases/download/v4.11.0' <<<"$dafny_blk"
ck "Dafny: --version check" grep -q -- '--version' <<<"$dafny_blk"
ck "Dafny: names removing the demo to skip it" grep -qF 'verification/demo_greeting' <<<"$dafny_blk"
ck "Dafny: Ubuntu unzip is sudo (R-7 — /opt is root-owned)" grep -qF 'sudo unzip' <<<"$dafny_blk"
ck "Dafny: Ubuntu wget lands in /tmp, not cwd (R-7)" grep -qF -- '-P /tmp' <<<"$dafny_blk"


# REQ-395: where Actions cannot start jobs, the README says what still checks a PR — in the enforcement section the spec
# names and in the free-private-repositories note — and /next, which exists, never prints a merge command without an
# APPROVE for the head.
fpr=$(awk '/^A note on free private repositories/{f=1} /^## Quick Start/{exit} f' README.md)
enf=$(awk '/merges via PR with:/{f=1} /^## Key Files/{exit} f' README.md)
ck "README states the Actions-cannot-start-jobs paragraph once (#33 third bootstrap F8)" [ "$(tr '\n' ' ' < README.md | grep -o 'cannot start jobs' | wc -l | tr -d ' ')" = 1 ]
ck "README's free-private-repositories note points at the enforcement section instead of repeating it" grep -qi 'enforcement' <<<"$fpr"
ck "README (enf): when Actions cannot start jobs, /next and the local gates are the only checks (REQ-395)" \
  bash -c 'grep -qi "cannot start" <<<"$1" && grep -qF "/next" <<<"$1" && grep -qF "run-quality-gates.sh" <<<"$1"' _ "$enf"
ck "README (enf): /next is present — it never prints a merge command without an APPROVE; no 'later plan'" \
  bash -c 'grep -qF "never prints a merge command" <<<"$1" && ! grep -qiE "later plan|\(P5\)" <<<"$1"' _ "$enf"

# P2 (REQ-310/312/313/382/395): the verifier process as it now is, everywhere a user reads it.
# PR #54 verifier run 2, finding 3 (REQ-385, REQ-313): the base by its full ref refs/remotes/origin/<base> — a tag named
# origin/<base> that git fetch auto-follows would otherwise pipe its own run-verifier.sh into bash.
# Covers: REQ-385
for f in README.md .github/PULL_REQUEST_TEMPLATE.md .claude/commands/analyze.md scripts/init-project.sh .claude/rules/review-gate.md docs/GLOSSARY.md; do
  ck "$f runs the verifier from the base ref" grep -qF 'scripts/run-verifier.sh | bash -s --' "$f"
  ck "$f no longer tells users to run the PR's own copy" no grep -qE '(^|[^:])scripts/run-verifier\.sh <PR' "$f"
  # SEC-004 (high; dfe-9; REQ-385, REQ-313): main's reviewed copy for every PR, never a (stacked) base branch's.
  ck "$f prints main's bootstrap by the full ref refs/remotes/origin/main, never the short name or a base branch's copy (SEC-004)" \
    bash -c 'grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s --" "$1" && ! grep -qE "git show [^ ]?origin/[^ ]*:scripts/run-verifier|origin/<base>:scripts/run-verifier" "$1"' _ "$f"
done
ck "run-verifier.sh's header, usage and refusals print main's bootstrap by the full ref, never the short name or the base's copy (SEC-004)" \
  bash -c 'grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s --" "$1" && grep -qF "base_full=\"refs/remotes/origin/\$base_ref\"" "$1" && ! grep -qF "git show \$base_full:scripts/run-verifier.sh | bash -s --" "$1" && ! grep -qE "git show [^ ]?origin/[^ ]*:scripts/run-verifier|origin/<base>:scripts/run-verifier" "$1"' _ scripts/run-verifier.sh
for s in 'Verifier findings posted' 'Quality gates (pytest'; do
  ck "no user-facing file names the retired check '$s'" no git grep -qF "$s" -- README.md CLAUDE.md docs/GLOSSARY.md .claude .github scripts
done
for t in 'Attestation marker' 'Code mode' 'Solo mode' 'Verifier' 'Waiver'; do ck "glossary defines $t" grep -qx "### $t" docs/GLOSSARY.md; done
gl() { awk -v h="### $1" '$0 == h {f = 1; next} /^### /{f = 0} f' docs/GLOSSARY.md; }
ck "glossary: the marker is judged, not merely present" bash -c 'grep -qi verdict <<<"$1" && grep -q sha <<<"$1" && ! grep -qi "does not judge" <<<"$1"' _ "$(gl 'Attestation marker')"
ck "glossary: solo mode is a self-attested audit trail" grep -qiE 'self-attested|audit trail' <<<"$(gl 'Solo mode')"
ck "glossary: a waiver needs 20 characters" grep -q '20' <<<"$(gl 'Waiver')"
ck "glossary terms stay alphabetical" bash -c 'grep "^### " docs/GLOSSARY.md | sed "s/^### //" | LC_ALL=C sort -f -c'
pre=$(awk '/^## Prerequisites/{f=1} f; /^### Tauri/{exit}' README.md)
ck "README prerequisites name gitleaks for the verifier (H10)" bash -c 'grep -q gitleaks <<<"$1" && grep -qF "brew install gitleaks" <<<"$1"' _ "$pre"
ck "README prerequisites pin the gitleaks version checked and the minimum" bash -c 'grep -qF "8.30.1" <<<"$1" && grep -qF "8.19" <<<"$1"' _ "$pre"
ck "README names the isolation canary" grep -qF 'run-verifier.sh --canary' README.md
ck "README says how to recover when the findings scan stops a post" bash -c 'grep -i gitleaks README.md | grep -qiE "false positive|re-run|waive"'
ck "README configure-repo row names the stable checks" bash -c 'grep -E "configure-repo\.sh" README.md | grep -q gates'
ck "README says solo mode is tamper-evident, not enforced" grep -qi 'tamper-evident' README.md
ck "PR template records waivers (REQ-382)" grep -qi 'waive' .github/PULL_REQUEST_TEMPLATE.md
ck "CLAUDE.md maps the attestation module" grep -qF 'scripts/lib/specflow/attestation.py' CLAUDE.md

# Verifier findings on #33 (REQ-311, REQ-382, REQ-310): the glossary matches the classifier; solo/team approval wording.
ck "glossary: markers are accepted from OWNER, MEMBER or COLLABORATOR" grep -qF 'OWNER, MEMBER or COLLABORATOR' <<<"$(gl 'Attestation marker' | tr '\n' ' ')"
ck "glossary: waivers come from OWNER or MEMBER" grep -qF 'OWNER or MEMBER' <<<"$(gl 'Waiver' | tr '\n' ' ')"
ck "glossary: code mode counts .gitignore and .gitattributes as code; only root LICENSE/NOTICE files are neither" \
  bash -c 'grep -qF ".gitignore" <<<"$1" && grep -qF ".gitattributes" <<<"$1" && grep -qi "root" <<<"$1" && grep -qF "LICENSE" <<<"$1"' _ "$(gl 'Code mode' | tr '\n' ' ')"
ck "README: edited re-runs gates on every title or body edit, which waivers make routine" \
  bash -c 'grep -qF "edited" <<<"$1" && grep -qi "title or body edit" <<<"$1" && grep -qi "waiver" <<<"$1"' _ "$(awk '/free-tier private GitHub repository/{f=1} /^## Quick Start/{exit} f' README.md | tr '\n' ' ' | tr -s ' ')"
ck "init next steps no longer say 'a human approves' in every mode" no grep -qF 'a human approves and merges' scripts/init-project.sh
ck "init next steps: team mode needs a human other than the author; solo's second review is the APPROVE" \
  bash -c 'grep -qi "in team mode a human other than the author approves" <<<"$1" && grep -qi "in solo mode the verifier.s APPROVE is the second review" <<<"$1"' _ "$(tr '\n' ' ' < scripts/init-project.sh | tr -s ' ')"

# P4 (REQ-330, H6, H12): the floor tools are prerequisites, installed from checksum-verified assets; the floor is online.
# Covers: REQ-330
pre=$(awk '/^## Prerequisites/{f=1; next} /^## /{if (f) exit} f' README.md)
ck "README prerequisites name osv-scanner (the floor's advisory scan)" grep -q 'osv-scanner' <<<"$pre"
ck "README prerequisites give the checksum-verified installer" grep -qF 'install-pinned-tool.sh' <<<"$pre"
ck "README says what SPECFLOW_FLOOR_OFFLINE=1 does" grep -qF 'SPECFLOW_FLOOR_OFFLINE' <<<"$pre"
ck "README Tauri prerequisites install cargo-audit locked at a version" grep -qE 'cargo install cargo-audit --locked --version [0-9.]+' <<<"$pre"

# P4 (REQ-330, REQ-334, REQ-388): the floor, suppressions and the Dependabot rule, where a user reads them.
# Covers: REQ-334
# Covers: REQ-388
g=docs/GLOSSARY.md
sf=$(awk '/^### Security floor$/{f=1; next} /^### /{f=0} f' "$g")
ck "glossary: Security floor is the tool floor (gitleaks, osv-scanner, run-security-floor.sh)" \
  bash -c 'grep -q gitleaks <<<"$1" && grep -q osv-scanner <<<"$1" && grep -q run-security-floor.sh <<<"$1"' _ "$sf"
ck "glossary: floor failures are listed apart from gate failures" grep -qi 'apart from gate failures' <<<"$sf"
ck "glossary defines Suppression" grep -qx '### Suppression' "$g"
sp=$(awk '/^### Suppression$/{f=1; next} /^### /{f=0} f' "$g")
ck "glossary: a suppression cites a SEC-NNN listed in suppresses:" bash -c 'grep -q "SEC-NNN" <<<"$1" && grep -q "suppresses:" <<<"$1"' _ "$sp"
db=$(awk '/^### Dependabot exemption$/{f=1; next} /^### /{f=0} f' "$g")
for w in verified web-flow '.github/' lockfile; do ck "glossary: Dependabot exemption states '$w'" grep -qF "$w" <<<"$db"; done
ck "glossary: the Dependabot entry no longer defers the rule to P4" no grep -qF "are P4's" <<<"$db"
cl=$(grep -F 'dependabot[bot]' .claude/rules/review-gate.md | head -1)
for w in verified web-flow '.github/'; do ck "review-gate.md claim row: Dependabot states '$w'" grep -qF "$w" <<<"$cl"; done
gb=$(awk '/Mechanical gates in CI/{f=1} /Verifier review, run locally/{exit} f' README.md)
ck "README gates bullet names the security floor and its separate report" bash -c 'grep -qi "security floor" <<<"$1" && grep -qi "floor failures" <<<"$1"' _ "$gb"
ck "CLAUDE.md project map names the floor scripts" bash -c 'grep -q run-security-floor.sh CLAUDE.md && grep -q check-suppressions.sh CLAUDE.md && grep -q install-pinned-tool.sh CLAUDE.md'
ck "docs/security/README.md explains Tools run and suppresses:" bash -c 'grep -q "Tools run" docs/security/README.md && grep -q "suppresses:" docs/security/README.md'

# P3 (REQ-321, REQ-323, REQ-325, REQ-322, REQ-324): the mechanized gates, where a user or a session reads them.
# Covers: REQ-321
# Covers: REQ-323
# Covers: REQ-325
g=docs/GLOSSARY.md
cf=$(awk '/^### Coverage floor$/{f=1; next} /^### /{f=0} f' "$g")
for w in 'pytest --cov=src' 'cargo llvm-cov' 'vitest' 'lcov-threshold.sh' 'base ref'; do ck "glossary Coverage floor: '$w'" grep -qF "$w" <<<"$cf"; done
ca=$(awk '/^### Covers annotation$/{f=1; next} /^### /{f=0} f' "$g")
ck "glossary Covers annotation: // Covers: and check-covers.sh" bash -c 'grep -qF "// Covers:" <<<"$1" && grep -qF "check-covers.sh" <<<"$1"' _ "$ca"
for h in 'Disposition gate' 'Test-first check'; do ck "glossary defines $h" grep -qx "### $h" "$g"; done
ck "tdd.md: check-test-first.sh is live, not 'a later plan'" \
  bash -c 'grep -qF "check-test-first.sh" "$1" && ! grep -qF "until then it is not" "$1" && ! grep -qF "(P3) adds" "$1"' _ .claude/rules/tdd.md
ck "verifier SKILL.md: code mode no longer 'stands in … until P3'" no grep -qF 'until P3 builds it' .claude/skills/verifier/SKILL.md
row=$(grep -F '| Test-first per commit |' .claude/rules/review-gate.md || true)
ck "review-gate.md claim row: test-first is check-test-first.sh in ci.yml, not a convention" \
  bash -c 'grep -qF "scripts/check-test-first.sh" <<<"$1" && grep -qF ".github/workflows/ci.yml" <<<"$1" && ! grep -qF "Convention until" <<<"$1"' _ "$row"
for w in 'scripts/check-security-disposition.sh' 'scripts/verify-release.sh' 'tests/governance/fixtures/disposition'; do
  ck "review-gate.md's claim table names $w" grep -qF "$w" .claude/rules/review-gate.md
done
ck "review-gate.md RELEASE exit gate: verify-release.sh at PR time, the tag after the merge" \
  bash -c 'l=$(grep -F "RELEASE exit gate" "$1"); grep -qF "verify-release.sh" <<<"$l" && grep -qi "after the merge" <<<"$l"' _ .claude/rules/review-gate.md
ck "CLAUDE.md's project map names the P3 scripts and schema" \
  bash -c 'for s in check-test-first.sh check-covers.sh check-security-disposition.sh verify-release.sh template-pack.yml security-disposition-template.md; do grep -qF "$s" CLAUDE.md || exit 1; done'
gb=$(awk '/Mechanical gates in CI/{f=1} /Verifier review, run locally/{exit} f' README.md)
for w in 'coverage' 'test-first' 'check-security-disposition.sh' 'verify-release.sh'; do ck "README gates bullet: '$w'" grep -qiF "$w" <<<"$gb"; done
ck "review-gate.md RELEASE exit gate: 'tag missing' is judged after the merge (art-release-readiness), not an interim reading" \
  bash -c 'l=$(grep -F "RELEASE exit gate" "$1"); grep -qF "tag missing" <<<"$l" && grep -qF "after the merge" <<<"$l" && ! grep -qiF "interim" <<<"$l"' _ .claude/rules/review-gate.md
ck "verifier SKILL.md: 'tag missing' is judged after the merge, per art-release-readiness" \
  bash -c 'grep -qF "tag missing" "$1" && grep -qF "judged after the merge" "$1" && grep -qF "art-release-readiness" "$1"' _ .claude/skills/verifier/SKILL.md
ck "review-gate.md claim row: the checker proves a test changed, not that it exercises the change" grep -qF 'not that the test exercises' <<<"$row"
if [ -f docs/specs/2026-09-25-factory-v3-2-design.md ]; then   # an instance may delete the factory spec
  ck "the v3.2 spec's amended: records the P3 rulings (P4's precedent)" \
    bash -c 'awk "/^amended:/{f=1; next} /^[a-z_]+:/{f=0} f" "$1" | grep -F "P3 IMPLEMENT" | grep -qF "REQ-322"' _ docs/specs/2026-09-25-factory-v3-2-design.md
fi

# PR #42 findings 1, 2, 3, 7 and code mode (REQ-324, REQ-322), settled by amendment B (REQ-343): the previous-tag control
# is the CI check plus the PR template's checkbox, never the verifier; the 0.0 row is the constitution's own.
# Covers: REQ-324
# Covers: REQ-322
rg=.claude/rules/review-gate.md; sk=.claude/skills/verifier/SKILL.md
rel=$(grep -F "RELEASE exit gate" "$rg")
ck "RELEASE exit gate: R19's control is verify-release.sh's previous-tag check and the PR template's checkbox, not the verifier" \
  bash -c 'grep -qF "PR template" <<<"$1" && grep -qF "git tag -v" <<<"$1" && grep -qF "ancestor" <<<"$1" && grep -qF "The verifier is not part of this control" <<<"$1"' _ "$rel"
ck "RELEASE exit gate: no longer 'the next ship PR checks the previous release's tag' as the whole control" \
  no grep -qF "the replacement control — the next ship PR checks the previous release's tag — is mechanical only as" <<<"$rel"
# Covers: REQ-343
ck "RELEASE exit gate: no interim reading, no override of the article, no deadline; the 0.0 row cites art-threat-driven-security" \
  bash -c '! grep -qiF "interim reading" <<<"$1" && ! grep -qF "overrides the article" <<<"$1" && ! grep -qF "2026-10-31" <<<"$1" && grep -qF "art-threat-driven-security" <<<"$1"' _ "$rel"
# PR #42 fourth verifier run, doc medium 4 (REQ-324): the RELEASE exit-gate bullet opens with the PR-time rule, says the
# tag is created and signed after the merge, and states the unverifiable-signature WARN as the claim row and
# release_gate.py do.
ck "RELEASE exit gate opens with the PR-time rule, not 'tag exists and is signed'" \
  bash -c 'grep -q "^- RELEASE exit gate, at PR time" <<<"$1" && ! grep -qF "tag \`v<version>\` exists and is signed" <<<"$1"' _ "$rel"
ck "RELEASE exit gate: the tag is created and signed after the merge" grep -qF 'After the merge, the tag `v<version>` is created and signed' <<<"$rel"
ck "RELEASE exit gate: a signature this machine cannot check is a WARN, never a FAIL; a BAD signature FAILs" \
  bash -c 'grep -qF "is a WARN, never a FAIL" <<<"$1" && grep -qF "a BAD signature" <<<"$1" && grep -qF "no public key or no gpg" <<<"$1"' _ "$rel"
vr=$(grep -F "| At PR time, a ship PR's release docs" "$rg" || true)
ck "the verify-release claim row lists what the previous-tag check checks and its one gap (a missing tag is a WARN)" \
  bash -c 'grep -qF "tag object" <<<"$1" && grep -qF "only a WARN" <<<"$1" && grep -qF "public key" <<<"$1"' _ "$vr"
tf=$(grep -F "| Test-first per commit |" "$rg" || true)
ck "the test-first claim row: instance-ness at the base, and the head-copy residual" \
  bash -c 'grep -qF ".stack" <<<"$1" && grep -qF "PR head'"'"'s own" <<<"$1"' _ "$tf"
s7=$(grep -E "^7\. " "$sk" || true)
ck "verifier SKILL.md step 7 depends on nothing the headless verifier cannot see, and states no deadline" \
  bash -c '! grep -qiF "PR body" <<<"$1" && ! grep -qF "WARN verify-release" <<<"$1" && grep -qF "standing informational finding" <<<"$1" && grep -qF "art-release-readiness" <<<"$1" && ! grep -qF "2026-10-31" <<<"$1" && ! grep -qiF "interim" <<<"$1"' _ "$s7"
ck "the PR template's RELEASE checkbox: the maintainer confirms the previous tag, as art-release-readiness requires" \
  bash -c 'grep -qE "^- \[ \] .*previous release.*tag.*art-release-readiness" "$1" && ! grep -qF "R19" "$1"' _ .github/PULL_REQUEST_TEMPLATE.md
ck "RUBRIC.md: the 0.0 row is art-threat-driven-security's own; no interim paragraph, no deadline" \
  bash -c 'grep -qF "art-threat-driven-security" "$1" && ! grep -qiF "interim reading" "$1" && ! grep -qF "2026-10-31" "$1"' _ docs/security/RUBRIC.md
if [ -f docs/specs/2026-09-25-factory-v3-2-design.md ]; then
  ck "the v3.2 spec's P3 amended: entry records R19 and R20 with amendment B's tracking id (REQ-343)" \
    bash -c 'e=$(awk "/^amended:/{f=1; next} /^[a-z_]+:/{f=0} f" "$1" | grep -F "P3 IMPLEMENT"); grep -qF "(R19)" <<<"$e" && grep -qF "REQ-343" <<<"$e" && grep -qF "R20" <<<"$e"' _ docs/specs/2026-09-25-factory-v3-2-design.md
fi

# PR #42 findings 8 and 11 (REQ-322, REQ-323): the README says when the disposition gate runs; the glossary's Covers
# placement reads without knowing the harness.
ck "README: the disposition gate runs on any PR that changes a security document, and on ship PRs" \
  bash -c 'grep -qiF "any PR that changes a security document" <<<"$1" && grep -qF "ship PR" <<<"$1"' _ "$gb"
ck "glossary Covers annotation: no bare '(the line above its finish)'" no grep -qF 'the line above its `finish`' <<<"$ca"
ck "glossary Covers annotation: says where in a governance test the line goes" grep -qF 'before the `finish` call that ends' <<<"$ca"

# PR #42 fifth verifier run, findings 4 and 5 (REQ-322, REQ-325): the project map names every scripts/lib/specflow
# module P3 added; the glossary says the disposition gate runs at PR time and blocks RELEASE through that PR.
ck "CLAUDE.md's project map names scripts/lib/specflow/disposition_gate.py and coverage.sh" \
  bash -c 'grep -qF "disposition_gate.py" CLAUDE.md && grep -qF "scripts/lib/specflow/coverage.sh" CLAUDE.md'
dg=$(gl 'Disposition gate' | tr '\n' ' ' | tr -s ' ')
ck "glossary Disposition gate: not 'the RELEASE-blocking check'" no grep -qF 'the RELEASE-blocking check' <<<"$dg"
ck "glossary Disposition gate: runs at PR time on any PR changing a security document and every ship/<version> PR (gates section 7)" \
  bash -c 'grep -qF "at PR time" <<<"$1" && grep -qF "any PR that changes a security document" <<<"$1" && grep -qF "every \`ship/<version>\` PR" <<<"$1" && grep -qF "section 7" <<<"$1" && grep -qF "blocks RELEASE by blocking that PR" <<<"$1"' _ "$dg"

# P5 final review (amendment B, art-review-gate): the solo APPROVE is self-attested on any GitHub plan; a free private
# repository in addition enforces neither the checks nor the review. /next's merge command is bound to the head.
solo_gl=$(gl 'Solo mode' | tr '\n' ' ' | tr -s ' ')
ck "glossary Solo mode: on any GitHub plan the APPROVE is self-attested and forgeable — not 'not server-enforced on a free private repository'" \
  bash -c 'grep -qF "on any GitHub plan" <<<"$1" && grep -qi "forge" <<<"$1" && ! grep -qF "not server-enforced on a free private repository" <<<"$1"' _ "$solo_gl"
hum=$(awk '/^- \*\*Human approval\*\*/{f=1} f && /^$/{exit} f' README.md | tr '\n' ' ' | tr -s ' ')
ck "README Human approval: the solo APPROVE is self-attested on any GitHub plan; a free private repository enforces neither checks nor review" \
  bash -c 'grep -qF "on any GitHub plan" <<<"$1" && grep -qi "forge" <<<"$1" && grep -qi "free private repositor" <<<"$1" && ! grep -qF "not enforced** on a free private repository" <<<"$1"' _ "$hum"
ck "README (enf): the merge command /next prints is bound to the head (--match-head-commit)" grep -qF -- '--match-head-commit' <<<"$enf"

# PR #48 verifier low 10 (REQ-341, REQ-306): instance-facing text says an instance's edit to state.py gets no proof check
# (the Dafny model stays in the template) and that code mode names it as gate code.
# Covers: REQ-341, REQ-306
nop='an instance'"'"'s edit to `state.py` gets no proof check'
for e in Derive 'Factory documents'; do
  ck "glossary $e: $nop, and code mode names it as gate code" \
    bash -c 'grep -qF "$2" <<<"$1" && grep -qF "gate code" <<<"$1"' _ "$(gl "$e" | tr '\n' ' ' | tr -s ' ')" "$nop"
done
ck "review-gate.md's /next merge row: $nop" \
  bash -c 'grep -F "| \`/next\` prints a merge command only" .claude/rules/review-gate.md | grep -qF "$1"' _ "$nop"

# PR #48 verifier run 2, F10 (REQ-341, REQ-306): CLAUDE.md (instance-facing) does not call state.py proved there — the
# proof stays in the template source, and an instance keeps only the fixtures (no fenced path: instances lose
# verification/factory_v3_2/, test_examples.sh).
# Covers: REQ-341, REQ-306
ck "CLAUDE.md: state.py is the kernel, proved in the template source by state.dfy; an instance keeps only the fixtures" \
  bash -c 'grep -qF "\`scripts/lib/specflow/state.py\` (its kernel, proved in the template source by the Dafny model \`state.dfy\` (an instance keeps only the fixtures))" CLAUDE.md && ! grep -qF "its proved kernel, REQ-341" CLAUDE.md'

# Wave-4 re-review low 4 (REQ-340, P5 R12): README says where the proof jobs run as verifier.yml and the threat model's
# dfe-7 row do — design/, build/, ship/, impl/, phase/plan-, phase/validate, phase/security and phase/release heads.
# Covers: REQ-340
rd=$(tr '\n' ' ' < README.md | tr -s ' ')
ck "README: the proof jobs run on design/, build/, ship/, impl/, phase/plan-, phase/validate, phase/security and phase/release heads" \
  grep -qF 'Dafny verification and contract-alignment checks on `design/`, `build/`, `ship/`, `impl/`, `phase/plan-`, `phase/validate`, `phase/security` and `phase/release` heads (and any PR labelled `has-verification`; not `patch/`)' <<<"$rd"
ck "README no longer says the proof jobs run only on implementation and validate branches" \
  no grep -qF 'contract-alignment checks on implementation and validate branches' <<<"$rd"

# P6 Task 2.5 (REQ-384; P6 R18): the glossary's Manifest entry says schema 2, the reproducible subset, and that CI's
# manifest is the record.
# Covers: REQ-384
g() { awk -v h="### $1" '$0==h{f=1; next} /^### /{f=0} f' docs/GLOSSARY.md | tr '\n' ' ' | tr -s ' '; }
ck "Glossary Manifest: schema 2, the reproducible subset, CI's manifest is the record" \
  bash -c 'grep -qF "specflow-manifest/2" <<<"$1" && grep -qF "reproducible" <<<"$1" && grep -qF "is the record" <<<"$1"' _ "$(g Manifest)"
# Fix wave 1 (REQ-384): release.yml arrives with Build 3 — an instance initialised between Build 2 and Build 3 has none,
# so the entry says from when it holds (Build 3's Task 3.5 removes the qualifier and flips this pin).
ck "Glossary Manifest: release.yml's manifest is attached to the Release, with no 'from Build 3' qualifier (P6 Task 3.5)" \
  bash -c 'grep -qF "release.yml" <<<"$1" && ! grep -qF "from Build 3" <<<"$1"' _ "$(g Manifest)"
# PR #54 verifier run 1, finding 3 and run 2, finding 2 (REQ-384, REQ-352; art-release-readiness): the interim window
# closed when the second of P6 Builds 4 and 5 merged (Build 5, 2026-10-03; owner kpingali123): README's "Known interim
# limitation" paragraph is gone (R35's interim-window edit), and with it the only sentence that claimed a verifier
# lapse check (PR #57 verifier run 1, finding 1: no skill text carries one) — no other README sentence claims it.
# Covers: REQ-384
ck "README: the interim-window paragraph is gone — no 'Known interim limitation', no 'until P6', no verifier lapse claim" python3 - README.md <<'PYK'
import sys
t = open(sys.argv[1]).read(); flat = " ".join(t.split())
for w in ("Known interim limitation", "until P6", "interim window", "lapsed, unextended", "verifier reports a ship PR after"):
    assert w not in flat, w
PYK
# PR #54 verifier run 2, finding 9 (art-naming-tagging): the image digest is the Release manifest's top-level image
# object (schema 2), never an artifacts entry with a reproducible flag.
# Covers: REQ-384
ck "Glossary Manifest: the image digest is the Release manifest's top-level image object, not an artifacts entry" \
  bash -c 'grep -qF "top-level \`image\` object" <<<"$1" && grep -qF "\`artifacts\` entry" <<<"$1" && ! grep -qF "bundles, the image digest" <<<"$1"' _ "$(g Manifest)"
# P6 Task 5.4 (REQ-308; P6 R22): the surfaces say what P6 shipped — no "later v3.2 plan" for signing or the checklist.
# Covers: REQ-308
ck "CLAUDE.md: the checklist goes under ## macOS distribution checklist; verify-release.sh and release.yml refuse notes that lack that heading (P6 R22)" \
  bash -c 'l=$(grep -F "docs/releases/store-checklist.md" "$1"); grep -qF "appended to each release'"'"'s notes by \`/release\` under \`## macOS distribution checklist\`" <<<"$l" && grep -qF "whose notes lack that heading" <<<"$l" && ! grep -qF "refuses an app release without it" <<<"$l"' _ CLAUDE.md
ck "README Signing row: macOS signing when the Apple secrets exist, else tester instructions; no 'later v3.2 plans'" \
  bash -c 'l=$(grep -F "| **Signing** |" "$1"); grep -qF "Apple secrets" <<<"$l" && grep -qF "tester instructions" <<<"$l" && ! grep -qF "later v3.2 plans" <<<"$l"' _ README.md
ck "Glossary: Release workflow defined; Store checklist ends with the re-run sentence" \
  bash -c 'grep -qx "### Release workflow" "$1" && grep -qF "observe \`signed: true\`" <<<"$(awk "\$0==\"### Store checklist\"{f=1; next} /^### /{f=0} f" "$1")"' _ docs/GLOSSARY.md
# P6 Task 5.6 (REQ-308; P6 R4, R5, R6): the glossary says how a follow-on design lane is named and derived, how
# next_version relates to a chosen release version, and how the template source runs /next.
# Covers: REQ-308
# Final review, finding 6 (REQ-350; P6 R30, R26): the Release workflow entry says what the tag replays — gates section 7,
# never sections 1–6 — what the rebuild is compared with — the notes' Artifacts rows — and that the draft is published
# once every asset is attached.
# Covers: REQ-350
ck "Glossary Release workflow: replays gates section 7 only (never sections 1–6), compares with the notes' Artifacts rows, publishes the draft once every asset is attached" \
  bash -c 'grep -qF "gates section 7" <<<"$1" && grep -qF "never sections 1–6" <<<"$1" && grep -qF "Artifacts rows" <<<"$1" && grep -qF "every asset is attached" <<<"$1" && ! grep -qF "replays the gates," <<<"$1" && ! grep -qF "manifest CI built at PR time" <<<"$1"' _ "$(g 'Release workflow')"
ck "Glossary Design lane: the follow-on slug, brainstorm until its plan exists, then the spec through the plan's spec:" \
  bash -c 'grep -qF "follow-on design lane" <<<"$1" && grep -qF "through the plan'"'"'s \`spec:\`" <<<"$1"' _ "$(g 'Design lane')"
ck "Glossary Ship lane: /next proposes ship/<next_version>; another version's branch is started by hand" \
  bash -c 'grep -qF "ship/<next_version>" <<<"$1" && grep -qF "by hand" <<<"$1"' _ "$(g 'Ship lane')"
ck "Glossary /next: the template source's sessions run next.sh --profile engineer --explain" grep -qF -- '--profile engineer --explain' <<<"$(g '/next')"
# Build 5 fix wave 1, H (REQ-352, REQ-350; P6 R32, R30): README's Signing row says where the five secrets live and that a
# GitHub Free private repository cannot hold them; the Platforms row no longer lists signing among what is missing; the
# Release workflow entry says the tag replays only the release checks and compares with the tagged notes' rows.
# Covers: REQ-352
ck "README Signing row: the five Apple secrets are environment secrets of release; a GitHub Free private repository cannot hold them" \
  bash -c 'l=$(grep -F "| **Signing** |" "$1"); grep -qF "environment secrets of the \`release\` environment" <<<"$l" && grep -qF "GitHub Free private repository" <<<"$l"' _ README.md
ck "README Platforms row: no 'signing automation' among what you do not get" \
  bash -c 'l=$(grep -F "| **Platforms** |" "$1"); [ -n "$l" ] && ! grep -qF "signing automation" <<<"$l"' _ README.md
# Covers: REQ-350
ck "Glossary Release workflow: replays only the release checks, compares with the rows the tagged notes transcribed" \
  bash -c 'grep -qF "only the release checks" <<<"$1" && grep -qF "the notes at the tag transcribed" <<<"$1"' _ "$(g 'Release workflow')"
# Build 5 fix wave 1, D (REQ-341; P6 R4): the Design lane entry names the newest plan and the residual — any lane may
# name any live spec, /next is advisory, the verifier reads the documents.
# Covers: REQ-341
ck "Glossary Design lane: the newest dated plan; any live spec may be named — /next advisory, the verifier reads the documents" \
  bash -c 'grep -qF "the newest, when several are" <<<"$1" && grep -qF "any live spec" <<<"$1" && grep -qF "advisory" <<<"$1" && grep -qF "verifier reads the documents" <<<"$1"' _ "$(g 'Design lane')"
# PR #58 verifier run 2 (REQ-308): the Signing row says what signing: apple with a missing secret does -- nothing published.
# Covers: REQ-308
ck "README Signing row: signing: apple with any secret missing fails the release and publishes nothing; signing: none ships unsigned" \
  bash -c 'l=$(grep -F "| **Signing** |" "$1"); grep -qF "\`signing: apple\` and any secret missing the release fails and publishes nothing" <<<"$l" && grep -qF "\`signing: none\`" <<<"$l"' _ README.md
# P7 Build 1 final review (finding 4; REQ-386, REQ-308): release.yml's signing-probe sets present=true whenever all five
# secrets exist, whatever signing: says, and sign runs on it — so the Signing row says "whenever the five Apple secrets
# exist", and "an unsigned bundle with tester instructions" only for signing: none with the secrets absent. The probe
# step itself is run here (signing: none and all five secrets: present=true), so the row is held to the behaviour.
# Covers: REQ-386
# Covers: REQ-308
ck "README Signing row: signing and notarization whenever the five Apple secrets exist; unsigned with tester instructions only for signing: none with the secrets absent" \
  bash -c 'l=$(grep -F "| **Signing** |" "$1"); grep -qF "macOS signing and notarization whenever the five Apple secrets exist" <<<"$l" && grep -qF "with \`signing: none\` and the secrets absent, an unsigned bundle with tester instructions" <<<"$l" && ! grep -qF "when \`signing: apple\` and the five Apple secrets exist" <<<"$l"' _ README.md
if [ -f .github/workflows/release.yml ]; then
  PW=$(mktemp -d)
  python3 - .github/workflows/release.yml > "$PW/probe.sh" <<'PYP'
import sys
t = open(sys.argv[1]).read().split("\n")
i = next(k for k, l in enumerate(t) if l.strip() == "- name: Probe the signing secrets")
j = next(k for k in range(i, len(t)) if t[k].strip() == "run: |")
ind = len(t[j + 1]) - len(t[j + 1].lstrip())
out = []
for l in t[j + 1:]:
    if l.strip() and len(l) - len(l.lstrip()) < ind:
        break
    out.append(l[ind:])
print("\n".join(out))
PYP
  : > "$PW/gho"; prc=0
  env -i PATH="$PATH" GITHUB_OUTPUT="$PW/gho" SIGNING=none APPLE_CERTIFICATE_P12=x APPLE_CERTIFICATE_PASSWORD=x APPLE_ID=x \
    APPLE_TEAM_ID=x APPLE_APP_PASSWORD=x bash -e "$PW/probe.sh" >/dev/null 2>&1 || prc=$?
  ck "…release.yml's signing-probe, signing: none with all five secrets: present=true (sign runs), as the row says" \
    bash -c '[ "$1" = 0 ] && grep -qx "present=true" "$2"' _ "$prc" "$PW/gho"
  rm -rf "$PW"
fi
finish test_onboarding_surface
