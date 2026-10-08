#!/usr/bin/env bash
# REQ-345: the idea-seed issue template (no workflow consumed it) is gone and nothing outside the history points at it;
# IDEA.md is the single entry point. REQ-334 (P5 R15): Dependabot batches each ecosystem into one weekly PR, and the file,
# the glossary and README say how a batch merges — gate-tool pip bumps and workflow action bumps are never exempt, so the
# maintainer folds the batch into one attested patch/<slug> PR and closes the Dependabot PRs as superseded.
# Covers: REQ-345
# Covers: REQ-334
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
ck "the idea-seed issue template is removed" no test -e .github/ISSUE_TEMPLATE/idea-seed.yml
ck "no issue template is left" bash -c '! ls .github/ISSUE_TEMPLATE/* >/dev/null 2>&1'
ck "nothing outside the history references idea-seed" \
  bash -c '! git grep -qF "idea-seed" -- . ":!docs/reviews" ":!docs/specs" ":!docs/plans" ":!tests/governance/test_github_surface.sh"'
ck "IDEA.md stays the entry point (init copies templates/IDEA.md)" bash -c 'test -f templates/IDEA.md && grep -qF "templates/IDEA.md" scripts/init-project.sh'
DB=.github/dependabot.yml
ck "dependabot.yml: pip at /scripts and github-actions at /, weekly, each one group of every update" python3 - "$DB" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
blocks = re.split(r"\n  - package-ecosystem: ", "\n" + t.split("\nupdates:", 1)[1])[1:]
eco = {b.split("\n", 1)[0].strip(): b for b in blocks}
assert set(eco) == {"pip", "github-actions"}, sorted(eco)
assert 'directory: "/scripts"' in eco["pip"] and 'directory: "/"' in eco["github-actions"]
for name, b in eco.items():
    assert "interval: weekly" in b, name
    assert "groups:" in b and re.search(r'patterns:\s*\[\s*"\*"\s*\]', b), name
PY
cm=$(grep -E '^#' "$DB" | tr '\n' ' ')
for w in 'patch/<slug>' 'superseded' 'stacks/python/skeleton/requirements.txt' '.github/'; do
  ck "dependabot.yml's comment says '$w'" grep -qF -- "$w" <<<"$cm"
done
gd=$(awk '/^### Dependabot exemption$/{f=1; next} /^### /{f=0} f' docs/GLOSSARY.md | tr '\n' ' ')
ck "the glossary's Dependabot entry: a batch is folded into one attested patch/<slug> PR, the rest superseded" \
  bash -c 'grep -qF "patch/<slug>" <<<"$1" && grep -qi "superseded" <<<"$1"' _ "$gd"
ck "README says how a Dependabot batch merges" \
  bash -c 'grep -i "dependabot" README.md | grep -qF "patch/<slug>"'
# PR #48 verifier run 3, finding 5 (REQ-334): the three places a maintainer reads the Dependabot batching rule say which
# check stops which bump — an action bump touches .github/, which the classifier's exemption refuses; a gate-tool pip bump
# that moves only scripts/requirements.txt is exempt from the verifier check but fails the gates check's
# test_python_lockfiles.sh (one pin in both lockfiles), which enforce_admins: false lets an admin merge past; any other
# pin's bump passes both. None says "never merge(s) exempt".
cmj=$(grep -E '^#' "$DB" | sed -E 's/^# ?//' | tr '\n' ' ' | tr -s ' ')
rdp=$(awk 'BEGIN{RS=""} /Dependabot opens one weekly PR/' README.md | tr '\n' ' ' | tr -s ' ')
gdn=$(tr -s ' ' <<<"$gd")
for src in cmj rdp gdn; do
  t=${!src}
  for w in 'test_python_lockfiles.sh' 'ruff, black, pytest, pytest-cov' 'enforce_admins: false' 'exempt from the verifier check' \
           'refuses' 'build, setuptools, wheel' 'test_stack_packs.sh'; do
    ck "Dependabot rule ($src) names which check blocks which bump: '$w'" bash -c 'grep -qF -- "$2" <<<"$1" || grep -qF -- "$(tr -d "\`" <<<"$2")" <<<"$(tr -d "\`" <<<"$1")"' _ "$t" "$w"
  done
  ck "Dependabot rule ($src) no longer says 'never merge(s) exempt'" bash -c '! grep -qE "never merges? exempt" <<<"$1"' _ "$t"
done
finish test_github_surface
