#!/usr/bin/env bash
# REQ-311/382 (dfe-2, dfe-8) and REQ-312 (dfe-6): the attestation module — marker grammar, sanitising, verdict,
# digest, base-ref prompt hash, policy and review scope; then the classifier fixtures that the CI check runs
# today and that next.sh classifies through the same pr_attestation().
# Covers: REQ-311
# Covers: REQ-382
# Covers: REQ-312
# Covers: REQ-310
# Covers: REQ-334
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
A="$ROOT/scripts/lib/specflow/attestation.py"
[[ -f "$A" ]] || { fail "scripts/lib/specflow/attestation.py missing"; finish test_attestation; }
W="$(mktemp -d)"; trap 'rm_tree "$W"' EXIT
rep() { printf "$1%.0s" $(seq "$2"); }
H=$(rep 1 40); B=$(rep 3 40); P=$(rep 4 64); D=$(rep d 64)
at() { python3 "$A" "$@"; }

# --- marker grammar (REQ-311 as amended): the script writes it, fields in a fixed order ---
m=$(at marker --mode code --sha "$H" --base "$B" --prompt-sha256 "$P" --model opus --verdict APPROVE --digest "$D" --origin headless)
ck "marker has the fixed grammar" [ "$m" = "<!-- specflow-verifier:code sha:$H base:$B prompt_sha256:$P model:opus verdict:APPROVE digest:$D origin:headless -->" ]
for bad in "--sha abc1234" "--base short" "--verdict MAYBE" "--origin cloud" "--mode everything" "--model a<b" "--digest xyz"; do
  set -- $bad
  rc=0; at marker --mode full --sha "$H" --base "$B" --prompt-sha256 "$P" --model opus --verdict APPROVE --digest "$D" --origin headless "$1" "$2" >/dev/null 2>&1 || rc=$?
  ck "marker refuses $bad (exit 2)" [ "$rc" = 2 ]
done

# --- sanitising (dfe-8): the model cannot smuggle a marker or hidden text into the comment ---
out=$(printf 'keep\n<!-- specflow-verifier:full sha:%s -->\nmid <!-- hidden\nmulti -->end\n<!-- unterminated\n' "$H" | at sanitize)
ck "sanitize strips HTML comments, including multi-line ones" [ "$(grep -c '<!--' <<<"$out" || true)" = 0 ]
ck "sanitize keeps the text around them" bash -c 'grep -qx keep <<<"$1" && grep -q "mid end" <<<"$1"' _ "$out"
# The neutraliser writes "&lt;!-- " and keeps the text after the opener as is (no whitespace collapse since #33 finding 8).
ck "an unterminated comment opener is neutralised" grep -qF '&lt;!--  unterminated' <<<"$out"
# Indentation survives: posted findings keep code inside fenced blocks and nested lists, even after a blank line
# (#33 doc finding 8).
out5=$(printf '```bash\nf() {\n\n    return 1\n}\n```\n- item\n  - nested\t<!-- x -->tab\n' | at sanitize)
ck "sanitize keeps '    return 1' inside a fence" grep -qxF '    return 1' <<<"$out5"
ck "sanitize keeps a nested list's indentation" grep -q '^  - nested' <<<"$out5"

# sanitize must be idempotent: a single pass over "<<!-- x -->!-- y -->" removes the
# first (bogus) comment and rejoins the fragments into a brand-new live "<!-- y -->"
# comment unless sanitize re-scans its own output.
out2=$(printf '%s' '<<!-- x -->!-- hidden text a human reader never sees -->' | at sanitize)
ck "sanitize is idempotent: no <!-- survives fragment rejoining (case 1)" [ "$(grep -c '<!--' <<<"$out2" || true)" = 0 ]

out3=$(printf '%s' "<<!-- x -->!-- specflow-verifier:waive sha:$H -->" | at sanitize)
ck "sanitize is idempotent: no <!-- survives fragment rejoining (case 2)" [ "$(grep -c '<!--' <<<"$out3" || true)" = 0 ]

out4=$(printf '%s' '<!<!-- -->-- y -->' | at sanitize)
ck "sanitize is idempotent: no <!-- survives fragment rejoining (case 3)" [ "$(grep -c '<!--' <<<"$out4" || true)" = 0 ]

# --- verdict: the last non-empty line, exactly ---
v() { printf "$1" | at verdict; }
ck "verdict: last non-empty line APPROVE" [ "$(v 'x\nAPPROVE\n\n  \n')" = APPROVE ]
ck "verdict: REQUEST_CHANGES after an APPROVE line" [ "$(v 'APPROVE\nREQUEST_CHANGES\n')" = REQUEST_CHANGES ]
for bad in 'APPROVE\nmore text\n' 'Verdict: APPROVE\n' 'approve\n' '' 'APPROVE.\n'; do
  rc=0; v "$bad" >/dev/null 2>&1 || rc=$?; ck "no verdict in '$bad' (exit 9)" [ "$rc" = 9 ]
done

# --- digest: CRLF and trailing newlines do not change it; content does ---
sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'; }
ck "digest normalises CRLF and trailing newlines" [ "$(printf 'a\r\nb\n\n' | at digest)" = "$(printf 'a\nb\n' | sha)" ]
ck "digest differs when the text differs" [ "$(printf 'a\n' | at digest)" != "$(printf 'b\n' | at digest)" ]

# --- prompt hash and policy come from a ref, never the working tree (dfe-1, dfe-6) ---
G="$W/g"; mkdir -p "$G/.claude/skills/verifier"; (cd "$G" && git init -q -b main)
printf 'skill v1\n' > "$G/.claude/skills/verifier/SKILL.md"; (cd "$G" && git add -A && git commit -qm predates)
rc=0; (cd "$G" && at prompt-hash --ref HEAD) >/dev/null 2>&1 || rc=$?
ck "prompt-hash: a ref without the prompt template predates attestation (exit 3)" [ "$rc" = 3 ]
printf 'prompt v1 @MODE@\n' > "$G/.claude/skills/verifier/headless-prompt.md"; (cd "$G" && git add -A && git commit -qm v1)
want=$(cd "$G" && python3 -c 'import hashlib, subprocess as s
g = lambda p: s.run(["git", "show", "HEAD:" + p], capture_output=True, check=True).stdout
print(hashlib.sha256(g(".claude/skills/verifier/SKILL.md") + b"\0" + g(".claude/skills/verifier/headless-prompt.md")).hexdigest())')
ck "prompt-hash = sha256(SKILL.md NUL headless-prompt.md) at the ref" [ "$(cd "$G" && at prompt-hash --ref HEAD)" = "$want" ]
printf 'skill v2 (working tree only)\n' > "$G/.claude/skills/verifier/SKILL.md"
ck "prompt-hash reads the ref, never the working tree" [ "$(cd "$G" && at prompt-hash --ref HEAD)" = "$want" ]
(cd "$G" && git checkout -q -- .)
ck "policy: config.py defaults at a ref without .specflow.yml" [ "$(cd "$G" && at policy --ref HEAD | tr '\n' ' ')" = "solo=true profile=guided path=lanes " ]
printf 'solo: false\nprofile: engineer\npath: regulated\n' > "$G/.specflow.yml"; (cd "$G" && git add .specflow.yml && git commit -qm team)
printf 'solo: true\n' > "$G/.specflow.yml"
ck "policy: the ref's values win over the working tree" [ "$(cd "$G" && at policy --ref HEAD | tr '\n' ' ')" = "solo=false profile=engineer path=regulated " ]
(cd "$G" && git checkout -q -- .)
Y="$W/y"; mkdir -p "$Y"; (cd "$Y" && git init -q -b main && printf 'solo: maybe\n' > .specflow.yml && git add -A && git commit -qm odd)
rc=0; (cd "$Y" && at policy --ref HEAD) >/dev/null 2>&1 || rc=$?
ck "policy: a solo value other than true/false fails closed (exit 4)" [ "$rc" = 4 ]

# --- review scope (REQ-310, H8): documents; everything else is code unless allowlisted; it fails toward review ---
Z="$W/z"; mkdir -p "$Z"; (cd "$Z" && git init -q -b main && echo a > README.md && git add -A && git commit -qm base)
zb=$(git -C "$Z" rev-parse HEAD); i=0
scope() {  # scope SNIPPET [FIELD] — commit SNIPPET's changes on a branch off $zb and print review-scope's FIELD (default mode; lists space-joined)
  i=$((i + 1)); (cd "$Z" && git checkout -q -B "t$i" "$zb" && eval "$1" && git add -A && git commit -qm "t$i" \
  && python3 "$A" review-scope --base "$zb" --head HEAD | python3 -c 'import json, sys
v = json.load(sys.stdin)[sys.argv[1]]; print(v if isinstance(v, str) else " ".join(v))' "${2:-mode}"); }
ck "documents only → full" [ "$(scope 'echo x > notes.md')" = full ]
ck "template: scripts/ → code" [ "$(scope 'mkdir -p scripts; echo x > scripts/a.sh')" = code ]
ck "template: .github/ → code" [ "$(scope 'mkdir -p .github/workflows; echo x > .github/workflows/a.yml')" = code ]
ck "template: stacks/ → code" [ "$(scope 'mkdir -p stacks/x; echo x > stacks/x/init.sh')" = code ]
ck "documents + tests → full+code" [ "$(scope 'echo x > b.md; mkdir -p tests; echo x > tests/t.txt')" = full+code ]
ck "neither (allowlisted only) → skipped" [ "$(scope 'echo x > .editorconfig; echo x > LICENSE; mkdir -p docs; echo x > docs/a.png')" = skipped ]
ck "a .md under scripts/ is a document" [ "$(scope 'mkdir -p scripts; echo x > scripts/README.md')" = full ]
# Model-instruction Markdown (#33 fourth run finding 10): files instances load as session instructions are doc AND
# code — root CLAUDE.md, any CLAUDE.md under stacks/, stacks' overlay/ and skeleton/ Markdown, and templates/ Markdown.
for f in CLAUDE.md stacks/tauri/CLAUDE.md stacks/python/overlay/CLAUDE.md stacks/tauri/overlay/docs/guide.md \
         stacks/flutter/skeleton/README.md templates/IDEA.md templates/sub/PROGRESS.md; do
  ck "$f → full+code (model-instruction Markdown)" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = full+code ]
done
# …but not every Markdown file near them: a stack's own checklist, docs/, a lower-case claude.md.
# PR #34 second-run finding 7: overlay/ and skeleton/ count only as the third segment (stacks/<stack>/overlay/…).
for f in stacks/tauri/overlay/README.md stacks/python/skeleton/src/notes.md; do
  ck "$f → full+code (stacks/<stack>/overlay|skeleton/)" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = full+code ]
done
for f in stacks/overlay/x.md stacks/skeleton/y.md stacks/tauri/docs/overlay/z.md; do
  ck "$f → full (overlay/skeleton not the third segment)" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = full ]
done
# PR #34 third-run finding 4: Claude Code loads a nested CLAUDE.md (and CLAUDE.local.md) from any subdirectory, so
# every one of them is instruction Markdown, wherever it sits.
for f in docs/CLAUDE.md src/CLAUDE.md a/b/CLAUDE.local.md CLAUDE.local.md; do
  ck "$f → full+code (a CLAUDE.md or CLAUDE.local.md at any depth)" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = full+code ]
done
for f in stacks/tauri/store-checklist.md docs/templates/x.md docs/claude.md; do
  ck "$f → full (a document only)" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = full ]
done
ck "the other list names what nobody reviews" [ "$(scope 'echo x > .editorconfig' other)" = .editorconfig ]
# .gitignore guards art-secrets-hygiene (.env*) and .gitattributes changes filters: both are code (#33 finding 5).
for f in .gitignore .gitattributes; do ck "$f → code" [ "$(scope "echo x > '$f'")" = code ]; done
# LICENSE/NOTICE are other only as exact repository-root names; anything else so named is code (#33 finding 6).
for f in LICENSE LICENSE.md LICENSE.txt NOTICE NOTICE.md NOTICE.txt; do ck "root $f → skipped" [ "$(scope "echo x > '$f'")" = skipped ]; done
for f in src/LICENSE_check.py scripts/NOTICE_hook.sh LICENSE-check.sh NOTICE_gen.py docs/LICENSE; do
  ck "$f → code" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = code ]
done
ck "the code list names the code" [ "$(scope 'mkdir -p tests; echo x > tests/t.txt; echo y > c.md' code)" = tests/t.txt ]
# Fail toward review: manifests, lockfiles, build and suppression configs, and any pack's sources and tests are code.
for f in requirements.txt pyproject.toml package.json Cargo.toml Cargo.lock pubspec.yaml pubspec.lock Dockerfile deploy.sh \
         .gitleaks.toml src/a.py lib/a.dart test/a_test.dart src-tauri/tauri.conf.json src-tauri/tests/a.rs .specflow/pack.yml; do
  ck "$f → code" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = code ]
done
ck ".specflow.yml is configuration the gates read → code" [ "$(scope 'echo "solo: false" > .specflow.yml')" = code ]
# The verifier's own skill and prompt, rules and commands are .md but gate code too: both parts see them.
for f in .claude/skills/verifier/SKILL.md .claude/skills/verifier/headless-prompt.md .claude/rules/tdd.md .claude/commands/analyze.md .github/PULL_REQUEST_TEMPLATE.md; do
  ck "$f → full+code" [ "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'")" = full+code ]
  ck "$f is in both lists" bash -c '[ "$1" = "$3" ] && [ "$2" = "$3" ]' _ \
    "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'" docs)" "$(scope "mkdir -p \"\$(dirname '$f')\"; echo x > '$f'" code)" "$f"
done
(cd "$Z" && git checkout -q main && mkdir -p .specflow && printf 'source_roots: [lib]\n' > .specflow/pack.yml && git add -A && git commit -qm pack)
zb=$(git -C "$Z" rev-parse HEAD)
ck "a pack at the base changes nothing: src/ is still code" [ "$(scope 'mkdir -p src; echo x > src/a.py')" = code ]
# A rename is a deletion plus an addition: the old path is classified too, so a gated file cannot leave review by
# being renamed to an allowlisted name (#33 bootstrap verifier high: review_scope must diff with --no-renames).
(cd "$Z" && git checkout -q main && mkdir -p tests/governance scripts \
  && printf 'art one\nart two\nart three\n' > constitution.md && printf 'check one\ncheck two\n' > tests/governance/test_x.sh \
  && printf 'print(1)\nprint(2)\n' > scripts/x.py && git add -A && git commit -qm gated)
zb=$(git -C "$Z" rev-parse HEAD)
ck "rename constitution.md → constitution.png is full, not skipped" [ "$(scope 'git mv constitution.md constitution.png')" = full ]
ck "…and constitution.md is in the docs list" grep -qw constitution.md <<<"$(scope 'git mv constitution.md constitution.png' docs)"
ck "rename tests/governance/test_x.sh → x.png is code, not skipped" [ "$(scope 'git mv tests/governance/test_x.sh x.png')" = code ]
ck "rename scripts/x.py → docs/x.md is full+code, not full" [ "$(scope 'mkdir -p docs; git mv scripts/x.py docs/x.md')" = full+code ]

# --- classifier (REQ-311, REQ-382; dfe-2): one fixture per rule, every fixture under every permutation.
# The CI check runs this same module; next.sh classifies through the same pr_attestation().
FX="$ROOT/tests/governance/fixtures/attestation"
n=0; for f in "$FX"/*.json; do n=$((n + 1)); ck "fixture $(basename "$f")" python3 "$A" fixture "$f"; done
ck "81 or more fixtures ($n)" [ "$n" -ge 81 ]
for r in approve request-changes edited untrusted-author stale-sha prompt-mismatch base-predates digest-mismatch multiple-markers \
         marker-not-first-line malformed newest-wins reroll in-session-team in-session-solo waiver-solo-self waiver-team-self \
         waiver-team-other waiver-short waiver-collaborator dependabot skipped no-comments permutation same-timestamp mode-mismatch persona-counts-as-full \
         waiver-base-predates marker-and-waiver-base-predates edited-newer-rc verdict-mismatch multiple-markers-stale \
         dependabot-all-commits dependabot-foreign-commit waiver-team-commit-author \
         dependabot-unverified dependabot-foreign-committer dependabot-bot-committer dependabot-source-file dependabot-workflow-uses \
         dependabot-files-unknown dependabot-nested-lockfiles dependabot-config-file dependabot-verification-missing dependabot-pyproject \
         dependabot-foreign-opener dependabot-null-committer dependabot-index-url dependabot-package-scripts dependabot-cargo-patch \
         dependabot-pubspec-overrides dependabot-contents-unknown \
         dependabot-new-npm-dependency dependabot-new-requirements-in-dependency dependabot-new-requirements-txt-dependency \
         dependabot-new-pubspec-dependency dependabot-version-only-moves \
         dependabot-npm-lockfile-v1 dependabot-npm-lockfile-git-resolved dependabot-npm-lockfile-foreign-package \
         dependabot-new-lockfile dependabot-new-cargo-dependency dependabot-npm-lockfile-scoped-nested \
         dependabot-requirements-removed-index-url dependabot-requirements-hash-rewritten dependabot-requirements-bump-new-hashes \
         dependabot-pubspec-hosted-collapsed dependabot-pubspec-git-collapsed dependabot-pubspec-caret-bump \
         dependabot-package-json-source-collapsed dependabot-package-json-dist-tag; do
  ck "a fixture covers rule '$r'" bash -c 'ls "$1"/[0-9][0-9]-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
# P4 final review, #35 medium 1 and #36 (REQ-334, dfe-13): only versions of the base's dependencies move — a new
# dependency in EVERY manifest kind is refused as new-dependency (npm, requirements.in/.txt, pubspec, Cargo), a lockfile
# the base lacks as new-lockfile, and the npm lockfile rule fails closed: a lockfileVersion 1 file (no packages map) is
# refused outright (lockfile-v1, never walked), and every resolved URL must be the registry tarball of the entry's own
# package and version (a git+ssh:// source or another package's tarball is resolved). Each fixture's reason is pinned,
# so a no-marker outcome for some other reason cannot pass for the rule under test.
while read -r fx want; do
  ck "$fx: refused as content:<path>:$want" python3 -c 'import json, sys
sys.path.insert(0, sys.argv[1]); import attestation as a
c = json.load(open(sys.argv[2]))["context"]
ok, reason = a.dependabot_exemption(c["pr_author"], c["commits"], c["files"], c["contents"])
assert not ok and reason.startswith("content:") and reason.endswith(":" + sys.argv[3]), (ok, reason)' "$ROOT/scripts/lib/specflow" "$FX/$fx.json" "$want"
done <<'EOF_REASONS'
53-dependabot-new-npm-dependency new-dependency
54-dependabot-new-requirements-in-dependency new-dependency
55-dependabot-new-requirements-txt-dependency new-dependency
56-dependabot-new-pubspec-dependency new-dependency
58-dependabot-npm-lockfile-v1 lockfile-v1
59-dependabot-npm-lockfile-git-resolved resolved
60-dependabot-npm-lockfile-foreign-package resolved
61-dependabot-new-lockfile new-lockfile
62-dependabot-new-cargo-dependency new-dependency
64-dependabot-requirements-removed-index-url removed-option
65-dependabot-requirements-hash-rewritten hash-changed
67-dependabot-pubspec-hosted-collapsed source-changed
68-dependabot-pubspec-git-collapsed source-changed
70-dependabot-package-json-source-collapsed source-changed
71-dependabot-package-json-dist-tag non-registry-spec
EOF_REASONS
ck "every file a base lacks is refused: new-lockfile for each lockfile kind, new-manifest for each manifest kind" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
heads = {"package-lock.json": "{\"lockfileVersion\": 3, \"packages\": {}}", "Cargo.lock": "", "pubspec.lock": "packages: {}\n",
         "package.json": "{}", "requirements.txt": "", "requirements.in": "", "Cargo.toml": "", "pubspec.yaml": "name: x\n"}
for f, h in heads.items():
    ok, r = a._content_rule("d/" + f, None, h)
    want = "new-lockfile" if f.endswith(".lock") or f == "package-lock.json" else "new-manifest"
    assert not ok and r == "content:d/" + f + ":" + want, (f, ok, r)' "$ROOT/scripts/lib/specflow"
ck "npm lockfile: an entry whose version is not plain semver, an alias (name: differs), or a non-dict packages map is refused" python3 -c 'import json, sys
sys.path.insert(0, sys.argv[1]); import attestation as a
R = "https://registry.npmjs.org/"
def lk(pk): return json.dumps({"lockfileVersion": 3, "packages": pk})
base = lk({"node_modules/lodash": {"version": "4.17.20", "resolved": R + "lodash/-/lodash-4.17.20.tgz"}})
for head in (lk({"node_modules/lodash": {"version": "4.17.21", "resolved": R + "lodash/-/lodash-4.17.20.tgz"}}),
             lk({"node_modules/lodash": {"name": "evil", "version": "1.0.0", "resolved": R + "evil/-/evil-1.0.0.tgz"}}),
             lk({"node_modules/lodash": {"version": "github:evil/lodash"}}),
             lk({"node_modules/lodash": {"version": "4.17.21", "resolved": "http://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz"}}),
             lk({"node_modules/lodash": {"version": "4.17.21", "resolved": R + "lodash/-/lodash-4.17.21.tgz?x=/evil/-/evil-1.0.0.tgz"}}),
             json.dumps({"lockfileVersion": 2, "packages": []})):
    ok, r = a._content_rule("package-lock.json", base, head)
    assert not ok, (head, r)' "$ROOT/scripts/lib/specflow"
# PR #36 second verifier run, high (REQ-334, dfe-13): the content rules compare base and head BOTH ways — a line the
# head REMOVES is refused unless it is a version or hash line of a dependency whose version moved in the same diff, and
# hash/checksum/integrity lines change only for a dependency whose version changed (fixtures 64–71 above; these pin the
# lockfile and remaining manifest kinds, each with its reason).
ck "requirements: every removed pip option line is refused as removed-option (any -- line, -r/-c/-e included)" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
for opt in ("--extra-index-url https://x.invalid/simple", "--find-links https://x.invalid/", "--trusted-host x.invalid",
            "--pre", "--only-binary :all:", "-r base.txt", "-c constraints.txt", "-e ./pkg", "-i https://x.invalid/simple"):
    for f in ("requirements.txt", "requirements.in"):
        ok, r = a._content_rule(f, opt + "\npytest==9.1.0\n", "pytest==9.1.1\n")
        assert not ok and r == "content:" + f + ":removed-option", (opt, f, ok, r)' "$ROOT/scripts/lib/specflow"
ck "requirements: a hash added at an unchanged version, or a pin whose extras or marker change, is refused" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
A = "    --hash=sha256:" + "a" * 64; B = "    --hash=sha256:" + "b" * 64
ok, r = a._content_rule("requirements.txt", "pytest==9.1.0 \\\n" + A + "\n", "pytest==9.1.0 \\\n" + A + " \\\n" + B + "\n")
assert not ok and r == "content:requirements.txt:hash-changed", r
ok, r = a._content_rule("requirements.txt", "pytest==9.1.0 ; python_version >= \"3.12\"\n", "pytest==9.1.1\n")
assert not ok and r == "content:requirements.txt:requirement-line", r' "$ROOT/scripts/lib/specflow"
ck "pubspec.yaml: a removed path:/sdk:/url: sub-key or a changed git ref: is source-changed; a removed non-dependency line is removed-line" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
cases = [("dependencies:\n  foo:\n    path: ../foo\n", "dependencies:\n  foo: ^1.0.0\n", "source-changed"),
         ("dependencies:\n  flutter:\n    sdk: flutter\n", "dependencies:\n  flutter: ^3.0.0\n", "source-changed"),
         ("dependencies:\n  foo:\n    hosted:\n      name: foo\n      url: https://p.invalid\n    version: ^1.0.0\n",
          "dependencies:\n  foo:\n    hosted:\n      name: foo\n    version: ^1.0.1\n", "source-changed"),
         ("dependencies:\n  foo:\n    git:\n      url: https://g.invalid/foo.git\n      ref: 1.0.0\n",
          "dependencies:\n  foo:\n    git:\n      url: https://g.invalid/foo.git\n      ref: 1.0.1\n", "source-changed"),
         ("name: app\npublish_to: none\ndependencies:\n  foo: ^1.0.0\n", "name: app\ndependencies:\n  foo: ^1.0.1\n", "removed-line")]
for b, h, want in cases:
    ok, r = a._content_rule("pubspec.yaml", b, h)
    assert not ok and r == "content:pubspec.yaml:" + want, (b, h, ok, r)' "$ROOT/scripts/lib/specflow"
ck "pubspec.lock: a removed url:, a moved url:, or a sha256 changed at the same version is refused" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
def lk(url, src, sha, ver):
    d = "      name: foo\n      sha256: \"" + sha + "\"\n" + ("      url: \"" + url + "\"\n" if url else "")
    return "packages:\n  foo:\n    dependency: \"direct main\"\n    description:\n" + d + "    source: " + src + "\n    version: \"" + ver + "\"\n"
P = "https://pub.private.example.invalid"
base = lk(P, "hosted", "a" * 64, "1.0.0")
for head, want in ((lk(None, "hosted", "b" * 64, "1.0.1"), "source-changed"),
                   (lk("https://pub.dev", "hosted", "b" * 64, "1.0.1"), "source-changed"),
                   (lk(P, "hosted", "b" * 64, "1.0.0"), "hash-changed")):
    ok, r = a._content_rule("pubspec.lock", base, head)
    assert not ok and r == "content:pubspec.lock:" + want, (head, ok, r)
ok, r = a._content_rule("pubspec.lock", lk("https://pub.dev", "hosted", "a" * 64, "1.0.0"), lk("https://pub.dev", "hosted", "b" * 64, "1.0.1"))
assert ok, r' "$ROOT/scripts/lib/specflow"
ck "Cargo.lock: a package whose source moves, or whose checksum changes at the same version, is refused" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
def lk(src, ver, ck): return "version = 3\n\n[[package]]\nname = \"serde\"\nversion = \"" + ver + "\"\nsource = \"" + src + "\"\nchecksum = \"" + ck + "\"\n"
CI = "registry+https://github.com/rust-lang/crates.io-index"
ok, r = a._content_rule("Cargo.lock", lk("registry+https://private.example.invalid/index", "1.0.0", "a" * 64), lk(CI, "1.0.1", "b" * 64))
assert not ok and r == "content:Cargo.lock:source-changed", r
ok, r = a._content_rule("Cargo.lock", lk(CI, "1.0.0", "a" * 64), lk(CI, "1.0.0", "b" * 64))
assert not ok and r == "content:Cargo.lock:hash-changed", r
ok, r = a._content_rule("Cargo.lock", lk(CI, "1.0.0", "a" * 64), lk(CI, "1.0.1", "b" * 64))
assert ok, r' "$ROOT/scripts/lib/specflow"
ck "package-lock.json: a removed resolved, or an integrity changed at the same version, is refused" python3 -c 'import json, sys
sys.path.insert(0, sys.argv[1]); import attestation as a
R = "https://registry.npmjs.org/"
def lk(v, res, integ):
    e = {"version": v, "integrity": integ}
    if res: e["resolved"] = R + "lodash/-/lodash-" + v + ".tgz"
    return json.dumps({"lockfileVersion": 3, "packages": {"node_modules/lodash": e}})
ok, r = a._content_rule("package-lock.json", lk("4.17.20", True, "sha512-a"), lk("4.17.21", False, "sha512-b"))
assert not ok and r == "content:package-lock.json:source-changed", r
ok, r = a._content_rule("package-lock.json", lk("4.17.20", True, "sha512-a"), lk("4.17.20", True, "sha512-b"))
assert not ok and r == "content:package-lock.json:hash-changed", r
ok, r = a._content_rule("package-lock.json", lk("4.17.20", True, "sha512-a"), lk("4.17.21", True, "sha512-b"))
assert ok, r' "$ROOT/scripts/lib/specflow"
ck "package.json: a file:/git/URL spec collapsing to a range is source-changed; Cargo.toml: a removed registry/git/path key is refused" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
for spec in ("file:../foo", "git+https://g.invalid/foo.git", "https://x.invalid/foo.tgz", "github:o/foo"):
    ok, r = a._content_rule("package.json", "{\"dependencies\": {\"foo\": \"" + spec + "\"}}", "{\"dependencies\": {\"foo\": \"^1.0.1\"}}")
    assert not ok and r == "content:package.json:source-changed", (spec, ok, r)
for sub in ("registry = \"private\"", "git = \"https://g.invalid/serde\"", "path = \"../serde\""):
    ok, r = a._content_rule("Cargo.toml", "[dependencies]\nserde = { version = \"1.0.0\", " + sub + " }\n", "[dependencies]\nserde = \"1.0.1\"\n")
    assert not ok and r == "content:Cargo.toml:non-version-change", (sub, ok, r)' "$ROOT/scripts/lib/specflow"
# #36 second run, low: a pinned range may not become a dist-tag or any token without a digit (latest, next, *).
ck "_NPM_VERSION_RE: ranges pass; dist-tags and digitless tokens are refused" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
for v in ("^18.2.0", "~1.2.3", ">=1.0.0 <2.0.0", "1.x", "1.0.0 - 2.0.0", "^1.0.0 || ^2.0.0", "1.2.3-beta.1", ">= 1.0.0"):
    assert a._npm_version_ok(v), v
for v in ("latest", "next", "*", "x", "", "beta", "^1.0.0 || latest", "next-2", "1.0.0 latest"):
    assert not a._npm_version_ok(v), v' "$ROOT/scripts/lib/specflow"
# #36 low: a pip per-line option after a ; environment marker is not a requirement line.
ck "requirements.txt: a per-line pip option after a ; marker (--config-settings) is refused" python3 -c 'import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
b = "pytest==9.1.0 ; python_version >= \"3.12\"\n"
h = "pytest==9.1.1 ; python_version >= \"3.12\" --config-settings editable_mode=compat\n"
ok, r = a._content_rule("requirements.txt", b, h)
assert not ok, r
assert a._REQ_TXT_RE.match(b.strip()) and not a._REQ_TXT_RE.match(h.strip())' "$ROOT/scripts/lib/specflow"
ck "rule 2: a stale two-marker comment is judged multiple-markers, non-blocking (#32 finding 1)" python3 -c 'import json, sys
sys.path.insert(0, sys.argv[1]); import attestation as a
d = json.load(open(sys.argv[2])); c = d["context"]
r = a.explain(d["comments"], c["head"], c["prompt_sha256"], c["solo"], c["pr_author"], c["required_mode"])
assert r == [(1, d["comments"][0]["html_url"], "multiple-markers")], r' "$ROOT/scripts/lib/specflow" "$FX/32-multiple-markers-stale.json"
ck "fixtures cite REQ-NNN, never REQUEST-NNN (art-naming-tagging)" no grep -rqE 'REQUEST-[0-9]' "$FX"
ck "test_template_instantiation.sh carries # Covers: REQ-312" grep -qx '# Covers: REQ-312' "$ROOT/tests/governance/test_template_instantiation.sh"
ck "test_verifier_process.sh carries # Covers: REQ-311" grep -qx '# Covers: REQ-311' "$ROOT/tests/governance/test_verifier_process.sh"
ck "the permutation fixture holds at least five comments" python3 -c 'import json, sys; assert len(json.load(open(sys.argv[1]))["comments"]) >= 5' "$FX/24-permutation.json"
ck "states are exactly ADR-003's Attestation" python3 -c 'import glob, json, sys
s = {json.load(open(f))["expect"]["state"] for f in glob.glob(sys.argv[1] + "/*.json")}
assert s == {"none", "approve", "request_changes", "waiver"}, s' "$FX"
# a wrong expectation must fail the fixture runner (it is not vacuous)
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["expect"]["state"] = "none"; json.dump(d, open(sys.argv[2], "w"))' "$FX/01-approve.json" "$W/wrong.json"
ck "fixture runner rejects a wrong expectation" no python3 "$A" fixture "$W/wrong.json"
ck "classify returns exactly state, reason and comment_id" python3 -c 'import json, subprocess, sys
d = json.load(open(sys.argv[2])); c = d["context"]; f = sys.argv[3]
json.dump(d["comments"], open(f, "w"))
a = [sys.executable, sys.argv[1], "classify", "--comments", f, "--head", c["head"], "--pr-author", c["pr_author"],
     "--solo", str(c["solo"]).lower(), "--required-mode", c["required_mode"], "--prompt-sha256", c["prompt_sha256"]]
r = json.loads(subprocess.run(a, capture_output=True, text=True, check=True).stdout)
assert sorted(r) == ["comment_id", "reason", "state"], r' "$A" "$FX/24-permutation.json" "$W/c24.json"
rc=0; python3 "$A" classify --comments "$W/c24.json" --head "$H" --pr-author alice --solo maybe --required-mode full --prompt-sha256 "$P" >/dev/null 2>&1 || rc=$?
ck "classify accepts only --solo true or false (usage error otherwise)" [ "$rc" = 2 ]

# --- check: what the verifier job runs — comments via gh api, policy/prompt/scope at the base ref (H4, dfe-6) ---
S="$W/stub"; stub_bin "$S"
(cd "$G" && git checkout -q -b pr && mkdir -p docs && echo x > docs/a.md && git add -A && git commit -qm pr)
GH=$(git -C "$G" rev-parse HEAD); GB=$(git -C "$G" rev-parse main)
PH=$(cd "$G" && at prompt-hash --ref "$GB")
tail=$'## SpecFlow verifier (full mode)\n\nNo findings.\nAPPROVE'
dg=$(printf '%s\n' "$tail" | at digest)
mk() { at marker --mode full --sha "$GH" --base "$GB" --prompt-sha256 "$PH" --model opus --verdict "$1" --digest "$2" --origin "$3"; }
comments() { python3 -c 'import json, sys
print(json.dumps([{"id": 1, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-09-26T10:00:00Z",
  "updated_at": "2026-09-26T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-1", "body": sys.argv[1]}]))' "$1" > "$S/comments.json"; }
chk() { rm -f "$S/gh.argv"; rc=0; out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$GH" \
  --base-ref "$GB" --base-name main --pr-author "${1:-alice}" 2>&1) || rc=$?; }
comments "$(mk APPROVE "$dg" headless)"$'\n'"$tail"; chk
ck "check passes an APPROVE for the head (exit 0)" [ "$rc" = 0 ]
ck "check read the comments through gh api" grep -q 'repos/o/r/issues/7/comments' "$S/gh.argv"
comments "$(mk APPROVE "$dg" in-session)"$'\n'"$tail"; chk
ck "in-session passes when solo is false at the base (the base commit says so)" [ "$rc" = 0 ]
(cd "$G" && git checkout -q main && printf 'solo: true\n' > .specflow.yml && git commit -qam solo && git checkout -q pr && git rebase -q main)
GH=$(git -C "$G" rev-parse HEAD); GB=$(git -C "$G" rev-parse main)
comments "$(mk APPROVE "$dg" in-session)"$'\n'"$tail"; chk
ck "in-session fails when solo is true at the base (exit 1)" [ "$rc" = 1 ]
ck "…naming the headless command, the base by its full ref (PR #54 verifier run 2, finding 3)" grep -qF 'git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7' <<<"$out"
# SEC-004 (high; dfe-9; REQ-385, REQ-313): for a stacked PR the check names main's reviewed copy, never the base's script.
# Covers: REQ-385
rc=0; out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$GH" \
  --base-ref "$GB" --base-name 'phase/plan-x' --pr-author alice 2>&1) || rc=$?
ck "…on a stacked PR the headless command is still main's copy, never the base's (SEC-004)" \
  bash -c 'grep -qF "git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7" <<<"$1" && ! grep -qF "phase/plan-x:scripts/run-verifier" <<<"$1"' _ "$out"
rct=$'## SpecFlow verifier (full mode)\n\n- [art-test-first] high: no test\nREQUEST_CHANGES'
comments "$(mk REQUEST_CHANGES "$(printf '%s\n' "$rct" | at digest)" headless)"$'\n'"$rct"; chk
ck "REQUEST_CHANGES fails (exit 1) and names the fix" bash -c '[ "$1" = 1 ] && grep -q "requested changes" <<<"$2" && grep -q "waive" <<<"$2"' _ "$rc" "$out"
rc=0; out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$GH" \
  --base-ref "$GB" --base-name 'phase/plan-x' --pr-author alice 2>&1) || rc=$?
ck "…on a stacked PR the re-run command is main's copy, never the base's (SEC-004)" \
  bash -c '[ "$1" = 1 ] && grep -qF "re-run git show refs/remotes/origin/main:scripts/run-verifier.sh | bash -s -- 7" <<<"$2" && ! grep -qF "phase/plan-x:scripts/run-verifier" <<<"$2"' _ "$rc" "$out"
# Dependabot (REQ-311; REQ-334 as amended, dfe-13; P4): exempt only when the opener and every commit author map to
# dependabot[bot], every commit is verified with committer dependabot[bot] or web-flow, every changed path is a
# dependency manifest or lockfile outside .github/, and each file's change passes its content rule (versions only).
# Commits come from gh api pulls/<pr>/commits (or --commits FILE), paths from git diff --no-renames <base>...<head>
# (or --files FILE), texts from git show at the merge base and the head (or --contents FILE).
cmt() { python3 -c 'import json, sys
out = []
for spec in sys.argv[1:]:
    p = spec.split(":"); a = p[0]; c = p[1] if len(p) > 1 else "web-flow"; v = p[2] if len(p) > 2 else "true"
    out.append({"sha": "0" * 40, "author": None if a == "-" else {"login": a},
                "committer": None if c == "-" else {"login": c},
                "commit": {"author": {"name": "dependabot[bot]" if a == "-" else a, "email": "x@example.invalid"},
                           "verification": {"verified": v == "true", "reason": "valid" if v == "true" else "unsigned"}}})
print(json.dumps(out))' "$@"; }
# The dependency base (depsbase) already lists pytest, so deps only moves its version (P4 final review: a
# dependency the base does not list is new-dependency, never a version move).
(cd "$G" && git checkout -q -b depsbase "$GB" && mkdir -p scripts \
  && printf 'pytest==9.1.0 \\\n    --hash=sha256:%s\n' "$(printf 'b%.0s' $(seq 64))" > scripts/requirements.txt \
  && printf 'pytest>=8,<10\n' > scripts/requirements.in && git add -A && git commit -qm depsbase \
  && git checkout -q -b deps depsbase \
  && printf 'pytest==9.1.1 \\\n    --hash=sha256:%s\n' "$(printf 'a%.0s' $(seq 64))" > scripts/requirements.txt \
  && printf 'pytest>=9,<10\n' > scripts/requirements.in && git add -A && git commit -qm deps \
  && git checkout -q -b idx depsbase && mkdir -p scripts \
  && printf -- '--extra-index-url https://pypi.example.invalid/simple\npytest==9.1.1\n' > scripts/requirements.txt \
  && git add -A && git commit -qm idx && git checkout -q pr)
DH=$(git -C "$G" rev-parse deps); IH=$(git -C "$G" rev-parse idx); DB=$(git -C "$G" rev-parse depsbase)
chkc() {  # chkc HEAD PR_AUTHOR [ARGS…] — the check against HEAD with base depsbase, stubs first; sets rc and out
  local h="$1"; shift; rm -f "$S/gh.argv"; rc=0
  out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$h" \
    --base-ref "$DB" --base-name main --pr-author "$@" 2>&1) || rc=$?
}
cp "$S/comments.json" "$W/rc-comments.json"; echo '[]' > "$S/comments.json"
printf 'scripts/requirements.txt\nscripts/requirements.in\n' > "$W/deps.txt"
cmt 'dependabot[bot]' 'dependabot[bot]' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "Dependabot PR: verified web-flow commits by dependabot[bot], a version-only change to dependency files: exempt" bash -c '[ "$1" = 0 ] && grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
ck "…having read the commits through gh api --paginate pulls/7/commits" bash -c 'grep -qx "repos/o/r/pulls/7/commits" "$1" && grep -qx -- --paginate "$1"' _ "$S/gh.argv"
chkc "$DH" 'dependabot[bot]'
ck "…the same without --files: paths from git diff <base>...<head>, texts from git show — exempt" bash -c '[ "$1" = 0 ] && grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
chkc "$DH" mallory
ck "…the same commits and diff in a PR opened by someone else: not exempt (identity by opener)" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
chkc "$IH" 'dependabot[bot]'
ck "…an added --extra-index-url in requirements.txt: not exempt (content rule)" bash -c '[ "$1" = 1 ] && grep -q "not exempt (content:scripts/requirements.txt:requirement-line" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]' mallory > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…one commit by someone else: not exempt, fails with no marker" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2" && grep -q "no accepted verifier comment" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]' - > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…a commit whose GitHub author is null: not exempt (fail closed)" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
echo '[]' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…no commits listed: not exempt (fail closed)" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:web-flow:false' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…an unverified commit (an author email anyone with push access can set): not exempt, and says why" bash -c '[ "$1" = 1 ] && grep -q "not exempt (unverified" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:mallory' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…a verified commit whose committer is neither dependabot[bot] nor web-flow: not exempt" bash -c '[ "$1" = 1 ] && grep -q "not exempt (committer" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:-' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…a null committer: not exempt (committer:<sha7>)" bash -c '[ "$1" = 1 ] && grep -q "not exempt (committer:0000000" <<<"$2"' _ "$rc" "$out"
cmt 'dependabot[bot]:dependabot[bot]' > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --files "$W/deps.txt"
ck "…committer dependabot[bot] is accepted" [ "$rc" = 0 ]
cmt 'dependabot[bot]' > "$S/commits.json"; printf '.github/workflows/ci.yml\n' > "$W/wf.txt"; chkc "$GH" 'dependabot[bot]' --files "$W/wf.txt"
ck "…a uses: bump under .github/workflows/ needs attestation" bash -c '[ "$1" = 1 ] && grep -q "not exempt (workflow-path" <<<"$2"' _ "$rc" "$out"
printf 'scripts/requirements.txt\nsrc/app.py\n' > "$W/src.txt"; chkc "$GH" 'dependabot[bot]' --files "$W/src.txt"
ck "…a source file beside the lockfile needs attestation" bash -c '[ "$1" = 1 ] && grep -q "not exempt (not-a-dependency-file" <<<"$2"' _ "$rc" "$out"
chkc "$GH" 'dependabot[bot]'
ck "…without --files the paths come from git diff <base>...<head> (here docs/a.md): not exempt" bash -c '[ "$1" = 1 ] && grep -q "docs/a.md" <<<"$2"' _ "$rc" "$out"
printf 'scripts/requirements.txt\n' > "$W/one.txt"
python3 -c 'import json; print(json.dumps({"scripts/requirements.txt": {"base": "pytest==9.1.0\n", "head": "pytest==9.1.1\n"}}))' > "$W/contents.json"
chkc "$GH" 'dependabot[bot]' --files "$W/one.txt" --contents "$W/contents.json"
ck "check --contents FILE supplies the texts instead of git show (here for a head that lacks the file): exempt" [ "$rc" = 0 ]
cmt 'dependabot[bot]' > "$W/dcommits.json"; cmt mallory > "$S/commits.json"; chkc "$DH" 'dependabot[bot]' --commits "$W/dcommits.json" --files "$W/deps.txt"
ck "check --commits FILE reads the commits from FILE instead of gh" bash -c '[ "$1" = 0 ] && ! grep -q "pulls/7/commits" "$2"' _ "$rc" "$S/gh.argv"
cmt mallory > "$W/mcommits.json"; chkc "$DH" 'dependabot[bot]' --commits "$W/mcommits.json" --files "$W/deps.txt"
ck "check --commits FILE with a foreign commit: not exempt" bash -c '[ "$1" = 1 ] && ! grep -q "exempt-dependabot" <<<"$2"' _ "$rc" "$out"
rm -f "$S/commits.json"; cp "$W/rc-comments.json" "$S/comments.json"
# A blocking reason: an edited comment for the head fails and says to delete it (fixtures 03, 30)
python3 -c 'import json, sys; c = json.load(open(sys.argv[1])); c[0]["updated_at"] = "2026-09-26T10:05:00Z"; json.dump(c, open(sys.argv[1], "w"))' "$S/comments.json"; chk
ck "an edited REQUEST_CHANGES for the head fails and says to delete it" bash -c '[ "$1" = 1 ] && grep -q "was edited" <<<"$2" && grep -q "delete it" <<<"$2"' _ "$rc" "$out"
# The base moved after the review and changed the skill: prompt-mismatch, and the message says push or rebase (H: moved base)
comments "$(mk APPROVE "$dg" headless)"$'\n'"$tail"
(cd "$G" && git checkout -q main && printf 'skill v3\n' > .claude/skills/verifier/SKILL.md && git commit -qam "skill moves" && git checkout -q pr)
OLDGB="$GB"; GB=$(git -C "$G" rev-parse main); chk
ck "a base that moved and changed the skill: fails as prompt-mismatch" bash -c '[ "$1" = 1 ] && grep -q "prompt-mismatch" <<<"$2"' _ "$rc" "$out"
ck "…saying the base moved and to push or rebase" bash -c 'grep -q "base branch moved" <<<"$1" && grep -qE "push or rebase" <<<"$1"' _ "$out"
(cd "$G" && git checkout -q main && printf 'unrelated\n' > other.txt && git add other.txt && git commit -qm "base moves, skill unchanged" && git checkout -q pr)
GB=$(git -C "$G" rev-parse main)
comments "$(at marker --mode full --sha "$GH" --base "$OLDGB" --prompt-sha256 "$(cd "$G" && at prompt-hash --ref "$GB")" --model opus --verdict APPROVE --digest "$dg" --origin headless)"$'\n'"$tail"; chk
ck "a base that moved without changing the prompt still passes" [ "$rc" = 0 ]
# A base that predates attestation: the message names --bootstrap and the waiver, never the base-ref pipe (P2's own PR)
GB=$(git -C "$G" rev-list --max-parents=0 main); chk
ck "base predates attestation: fails (exit 1)" [ "$rc" = 1 ]
ck "…naming --bootstrap from the head checkout" grep -qF "bash scripts/run-verifier.sh 7 --bootstrap" <<<"$out"
ck "…giving the bound waiver line for this head" grep -qE "<!-- specflow-verifier:waive sha:$GH base:[0-9a-f]{40} -->" <<<"$out"
ck "…and not the base-ref pipe (the base's script is pre-P2)" no grep -qF 'bash -s --' <<<"$out"
GB=$(git -C "$G" rev-parse main)

# --- the workflows run exactly this, under stable ids (REQ-312) ---
V=.github/workflows/verifier.yml; C=.github/workflows/ci.yml
job() { awk -v j="  $2:" '$0==j{f=1; print; next} f && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{exit} f' "$1"; }
vj=$(job "$V" verifier)
ck "verifier.yml has job 'verifier' named 'verifier'" grep -qE '^    name: verifier$' <<<"$vj"
ck "ci.yml has job 'gates' named 'gates'" grep -qE '^    name: gates$' <<<"$(job "$C" gates)"
ck "the verifier job runs the base's copy of the shared classifier at the base branch's current tip (H11)" grep -qF 'python3 "$ATTESTATION" check --repo "$REPO" --pr "$PR" --head "$HEAD_SHA" --base-ref "$BASE" --base-name "$BASE_REF" --pr-author "$PR_AUTHOR"' <<<"$vj"
ck "the verifier job fetches the base branch's tip first" grep -qF 'git fetch --quiet origin "+refs/heads/$BASE_REF:refs/remotes/origin/$BASE_REF"' <<<"$vj"
for e in github.event.pull_request.head.sha github.event.pull_request.user.login github.base_ref github.event.pull_request.number; do
  ck "the verifier job passes $e" grep -qF "$e" <<<"$vj"
done
ck "the verifier job never uses the event's stale base.sha (gh run rerun replays it)" no grep -qF 'pull_request.base.sha' <<<"$vj"
ck "the verifier job checks out full history for base-ref reads" grep -qE 'fetch-depth:[[:space:]]*0' <<<"$vj"
ck "no workflow greps comment bodies for the marker (H4)" no grep -qE "grep -q '?specflow-verifier" "$V"
ck "no workflow reads .specflow.yml from the PR head (dfe-6)" no grep -qE '\.specflow\.yml' "$V" "$C"

# P5 (REQ-382 as amended, R9; REQ-334, R10; REQ-311): a MEMBER's waiver counts only with a writing repository role, an
# npm lockfile may not grow, and pr_attestation() is the one entry point the CI check and next.sh share.
# Covers: REQ-382
# Covers: REQ-334
# Covers: REQ-311
for r in waiver-member-write waiver-member-maintain waiver-member-read-rejected waiver-member-triage-rejected \
         waiver-member-permission-unknown waiver-owner-no-lookup dependabot-npm-lockfile-new-entry \
         dependabot-npm-lockfile-dependency-added dependabot-npm-lockfile-range-moves dependabot-npm-lockfile-entry-removed; do
  ck "fixture for $r" bash -c 'ls "$1"/*-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
ck "every fixture whose accepted waiver comes from a MEMBER names that member's role in its context" python3 - "$FX" <<'PY'
import glob, json, os, sys
for p in glob.glob(os.path.join(sys.argv[1], "*.json")):
    d = json.load(open(p))
    if d["expect"].get("state") != "waiver":
        continue
    c = next(c for c in d["comments"] if c["id"] == d["expect"]["comment_id"])
    if c["author_association"] == "MEMBER":
        assert c["user"]["login"] in (d["context"].get("permissions") or {}), os.path.basename(p)
PY
ck "check() classifies only through pr_attestation(), which calls classify()" python3 - "$A" <<'PY'
import ast, sys
t = ast.parse(open(sys.argv[1]).read())
fn = {n.name: n for n in t.body if isinstance(n, ast.FunctionDef)}
calls = lambda f: {c.func.id for c in ast.walk(fn[f]) if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)}
assert "pr_attestation" in fn and "pr_attestation" in calls("check") and "classify" in calls("pr_attestation")
assert "classify" not in calls("check")
PY
ck "verifier.yml never passes the test-only --permissions input" no grep -qF -- '--permissions' .github/workflows/verifier.yml
ck "no workflow passes the test-only --permissions input (review-gate.md's waiver row: a workflow that does is gate code)" \
  no grep -qF -- '--permissions' .github/workflows/*.yml
waiver() {  # waiver LOGIN ASSOCIATION — one waiver comment for the head, as the check reads it
  python3 -c 'import json, sys
print(json.dumps([{"id": 5, "user": {"login": sys.argv[1]}, "author_association": sys.argv[2],
  "created_at": "2026-09-28T10:00:00Z", "updated_at": "2026-09-28T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-5",
  "body": "<!-- specflow-verifier:waive sha:" + sys.argv[3] + " -->\nReviewed by hand: a maintainer-decided waiver."}]))' "$1" "$2" "$GH" > "$S/comments.json"
}
waiver bob MEMBER; echo '{"permission": "write", "role_name": "write"}' > "$S/permission.json"; chk
ck "a MEMBER with the write role: the waiver passes, after a lookup of that member's repository role" \
  bash -c '[ "$1" = 0 ] && grep -q "repos/o/r/collaborators/bob/permission" "$2"' _ "$rc" "$S/gh.argv"
echo '{"permission": "read", "role_name": "read"}' > "$S/permission.json"; chk
ck "a read-only MEMBER's waiver fails as waiver-not-writer" bash -c '[ "$1" = 1 ] && grep -q "waiver-not-writer" <<<"$2"' _ "$rc" "$out"
rm -f "$S/permission.json"; chk
ck "a MEMBER whose role cannot be read: the waiver fails closed (waiver-permission-unknown)" \
  bash -c '[ "$1" = 1 ] && grep -q "waiver-permission-unknown" <<<"$2"' _ "$rc" "$out"
echo '{"bob": "maintain"}' > "$W/perms.json"
rm -f "$S/gh.argv"; rc=0; out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$GH" \
  --base-ref "$GB" --base-name main --pr-author alice --permissions "$W/perms.json" 2>&1) || rc=$?
ck "check --permissions FILE (test-only) supplies the roles instead of gh" bash -c '[ "$1" = 0 ] && ! grep -q collaborators "$2"' _ "$rc" "$S/gh.argv"
waiver alice OWNER; chk
ck "an OWNER's waiver needs no role lookup" bash -c '[ "$1" = 0 ] && ! grep -q collaborators "$2"' _ "$rc" "$S/gh.argv"
rg=.claude/rules/review-gate.md
wrow=$(grep -F '| Waivers need a maintainer' "$rg" || true)
ck "review-gate.md's waiver row: a MEMBER needs the admin, maintain or write role; unreadable fails closed; no 'deferred to P5'" \
  bash -c 'grep -qF "admin, maintain or write" <<<"$1" && grep -qi "fails closed" <<<"$1" && ! grep -qF "deferred to P5" <<<"$1"' _ "$wrow"
ck "the glossary's Waiver entry says the same" \
  bash -c 'w=$(awk "/^### Waiver$/{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " "); grep -qF "admin, maintain or write" <<<"$w" && ! grep -qF "deferred to P5" <<<"$w"'
ck "review-gate.md's Dependabot row: an npm lockfile gains no entry and no dependency name" \
  bash -c 'grep -F "dependabot[bot]" "$1" | grep -qF "no \`node_modules/\` entry"' _ "$rg"

# P5 final review (REQ-382, R9 applied to markers; REQ-311; REQ-334, R10): a MEMBER's or COLLABORATOR's marker counts
# only with a writing repository role, and a non-writer's marker never blocks; a marker is bound to its base — its
# recorded base must give the head the same merge base as the PR's current base, so a retargeted PR's old marker is
# refused (base-mismatch); a base package-lock.json with no packages map fails closed, and a v2 lockfile's legacy
# dependencies tree must mirror the packages map.
for r in marker-member-read-rejected marker-collaborator-triage-rejected marker-member-permission-unknown \
         marker-collaborator-write marker-base-mismatch marker-base-bound marker-read-only-cannot-block \
         dependabot-npm-lockfile-base-v1 dependabot-npm-lockfile-legacy-tree dependabot-npm-lockfile-v2-mirror; do
  ck "fixture for $r" bash -c 'ls "$1"/*-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
ck "every fixture with an accepted comment from a MEMBER or COLLABORATOR names that login's role in its context" python3 - "$FX" <<'PY2'
import glob, json, os, sys
for p in glob.glob(os.path.join(sys.argv[1], "*.json")):
    d = json.load(open(p))
    if d["expect"].get("comment_id") is None:
        continue
    c = next(c for c in d["comments"] if c["id"] == d["expect"]["comment_id"])
    if c["author_association"] in ("MEMBER", "COLLABORATOR") and not d["expect"]["reason"].endswith("-permission-unknown"):
        assert c["user"]["login"] in (d["context"].get("permissions") or {}), os.path.basename(p)
PY2
ck "the npm lockfile fixtures fail for the reason they name (base-lockfile-v1, legacy-dependencies)" python3 - "$A" "$FX" <<'PY2'
import json, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1])); import attestation as a
for n, want in (("89-dependabot-npm-lockfile-base-v1.json", "content:package-lock.json:base-lockfile-v1"),
                ("90-dependabot-npm-lockfile-legacy-tree.json", "content:package-lock.json:legacy-dependencies"),
                ("91-dependabot-npm-lockfile-v2-mirror.json", None)):
    c = json.load(open(os.path.join(sys.argv[2], n)))["context"]
    ok, why = a.dependabot_exemption(c["pr_author"], c["commits"], c["files"], c["contents"])
    assert (why == want) if want else ok, (n, ok, why)
PY2
comments_by() {  # comments_by LOGIN ASSOCIATION BODY — one comment, as the check reads it
  python3 -c 'import json, sys
print(json.dumps([{"id": 9, "user": {"login": sys.argv[1]}, "author_association": sys.argv[2], "created_at": "2026-09-28T10:00:00Z",
  "updated_at": "2026-09-28T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-9", "body": sys.argv[3]}]))' "$@" > "$S/comments.json"; }
PH=$(cd "$G" && at prompt-hash --ref "$GB")
comments_by bob MEMBER "$(mk APPROVE "$dg" headless)"$'\n'"$tail"
echo '{"permission": "read", "role_name": "read"}' > "$S/permission.json"; chk
ck "a read-only MEMBER's APPROVE marker fails as marker-not-writer, after a lookup of that member's role" \
  bash -c '[ "$1" = 1 ] && grep -q "marker-not-writer" <<<"$2" && grep -q "repos/o/r/collaborators/bob/permission" "$3"' _ "$rc" "$out" "$S/gh.argv"
echo '{"permission": "write", "role_name": "write"}' > "$S/permission.json"; chk
ck "…with the write role the same marker passes" [ "$rc" = 0 ]
rm -f "$S/permission.json"; comments_by carol COLLABORATOR "$(mk APPROVE "$dg" headless)"$'\n'"$tail"; chk
ck "a COLLABORATOR whose role cannot be read: the marker fails closed (marker-permission-unknown)" \
  bash -c '[ "$1" = 1 ] && grep -q "marker-permission-unknown" <<<"$2"' _ "$rc" "$out"
# The retarget: impl is stacked on plan, whose commit X no review saw; the marker reviewed plan..impl only.
(cd "$G" && git checkout -q -b planx main && mkdir -p docs && echo x > docs/x.md && git add -A && git commit -qm "X, unreviewed" \
  && git checkout -q -b implx && echo y > docs/y.md && git add -A && git commit -qm "Y" && git checkout -q pr)
XB=$(git -C "$G" rev-parse planx); YH=$(git -C "$G" rev-parse implx)
chkr() {  # chkr BASE_REF — the check of implx against BASE_REF, the marker recorded against planx
  rm -f "$S/gh.argv"; rc=0
  out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$YH" --base-ref "$1" \
    --base-name main --pr-author alice 2>&1) || rc=$?
}
comments_by alice OWNER "$(at marker --mode full --sha "$YH" --base "$XB" --prompt-sha256 "$PH" --model opus --verdict APPROVE --digest "$dg" --origin headless)"$'\n'"$tail"
chkr "$XB"
ck "a stacked PR's marker, judged against the base it reviewed: passes" [ "$rc" = 0 ]
chkr "$GB"
ck "…the same PR retargeted to main while the plan branch is unmerged (X enters its diff, same mode, same prompt): fails as base-mismatch" \
  bash -c '[ "$1" = 1 ] && grep -q "base-mismatch" <<<"$2" && grep -qi "re-run the verifier" <<<"$2"' _ "$rc" "$out"
(cd "$G" && git checkout -q -b mainx main && git merge -q --no-ff -m "merge planx" planx && git checkout -q pr)
chkr "$(git -C "$G" rev-parse mainx)"
ck "…retargeted after the plan branch merged with a merge commit (the merge base, so the diff, is unchanged): passes" [ "$rc" = 0 ]
# PR #48 verifier run 2, code-mode high (REQ-311, REQ-382): base-mismatch refuses only the ACCEPTANCE of an APPROVE. A
# REQUEST_CHANGES for the head stands whatever diff it reviewed (request-changes-base-mismatch) until a newer accepted
# APPROVE or waiver supersedes it, so a retarget never revives an older APPROVE over it.
# Covers: REQ-311, REQ-382
for r in marker-request-changes-base-mismatch-blocks marker-request-changes-base-mismatch-superseded; do
  ck "fixture for $r" bash -c 'ls "$1"/*-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
bmrc=$'## SpecFlow verifier (full mode)\n\nFindings noted.\nREQUEST_CHANGES'; bmdg=$(printf '%s\n' "$bmrc" | at digest)
bmap="$(at marker --mode full --sha "$YH" --base "$GB" --prompt-sha256 "$PH" --model opus --verdict APPROVE --digest "$dg" --origin headless)"$'\n'"$tail"
bmrq="$(at marker --mode full --sha "$YH" --base "$XB" --prompt-sha256 "$PH" --model opus --verdict REQUEST_CHANGES --digest "$bmdg" --origin headless)"$'\n'"$bmrc"
two_owner() {  # two_owner OLDER NEWER — two OWNER comments for the check, the second one minute newer
  python3 -c 'import json, sys
c = lambda i, t, body: {"id": i, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": t, "updated_at": t,
  "html_url": "https://github.com/o/r/pull/7#issuecomment-%d" % i, "body": body}
print(json.dumps([c(1, "2026-09-29T10:00:00Z", sys.argv[1]), c(2, "2026-09-29T10:01:00Z", sys.argv[2])]))' "$1" "$2" > "$S/comments.json"; }
two_owner "$bmap" "$bmrq"; chkr "$GB"
ck "retargeted to main: a newer REQUEST_CHANGES recorded against the old base still blocks an older APPROVE whose base matches (exit 1)" \
  bash -c '[ "$1" = 1 ] && grep -q "requested changes" <<<"$2" && grep -q "request-changes-base-mismatch" <<<"$2"' _ "$rc" "$out"
two_owner "$bmrq" "$bmap"; chkr "$GB"
ck "…a newer APPROVE whose base matches supersedes that REQUEST_CHANGES (exit 0)" [ "$rc" = 0 ]
# PR #48 verifier run 2, code-mode low 1 (REQ-311): a marker's recorded base must be 40 lowercase hex characters; any
# other token is base-mismatch and is never handed to git (a value starting with '-' would read as an option).
# Covers: REQ-311
ck "fixture for marker-base-not-a-sha" bash -c 'ls "$1"/*-marker-base-not-a-sha.json >/dev/null 2>&1' _ "$FX"
ck "_marker_bases passes git only 40-hex recorded bases, and maps any other token to False" python3 - "$A" <<'PY5'
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(sys.argv[1])); import attestation as a
seen = []
class R:
    returncode, stdout, stderr = 0, b"m" * 1, b""
def fake(argv, **k):
    seen.append(list(argv)); return R()
a.subprocess.run = fake
a._git_merge_base = lambda b, h: "m"
body = lambda base: {"body": "<!-- specflow-verifier:full sha:%s base:%s prompt_sha256:%s model:opus verdict:APPROVE digest:%s origin:headless -->\nx"
                     % ("1" * 40, base, "4" * 64, "d" * 64)}
out = a._marker_bases([body("--output=/tmp/x"), body("-c"), body("ABCDEF" + "0" * 34), body("5" * 40)], "3" * 40, "1" * 40)
assert out.get("--output=/tmp/x") is False and out.get("-c") is False and out.get("ABCDEF" + "0" * 34) is False, out
assert all(not t.startswith("-") for argv in seen for t in argv[2:]), seen
assert any(argv[:3] == ["git", "merge-base", "5" * 40] for argv in seen), seen
PY5
bmp='a `REQUEST_CHANGES` recorded against another base still blocks (`request-changes-base-mismatch`) until a newer accepted `APPROVE` or waiver supersedes it'
ck "review-gate.md's retarget step: only an APPROVE is refused as base-mismatch; a REQUEST_CHANGES still blocks" \
  bash -c 'awk "/^6\. After merge/{f=1} /^This is the operational rule/{f=0} f" "$1" | tr "\n" " " | tr -s " " | grep -qF "$2"' _ .claude/rules/review-gate.md "$bmp"
ck "the glossary's Attestation marker entry says the same" \
  bash -c 'awk "\$0==\"### Attestation marker\"{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " " | grep -qF "$1"' _ "$bmp"
factory_doc_ck "the threat model's dfe-2 row says the same" docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'grep "^| dfe-2 |" docs/architecture/2026-09-25-factory-v3-2-threat-model.md | grep -qF "$1"' _ "$bmp"
ck "README says the same" bash -c 'tr "\n" " " < README.md | tr -s " " | grep -qF "$1"' _ "$bmp"
factory_doc_ck "the spec's P5 IMPLEMENT amended: entry says the same" docs/specs/2026-09-25-factory-v3-2-design.md \
  bash -c 'grep -F "P5 IMPLEMENT PR" docs/specs/2026-09-25-factory-v3-2-design.md | grep -qF "a REQUEST_CHANGES recorded against another base still blocks (request-changes-base-mismatch) until a newer accepted APPROVE or waiver supersedes it"'
comments "$(mk APPROVE "$dg" headless)"$'\n'"$tail"

# PR #48 verifier high (REQ-382, R9; REQ-311): rule 1b fails closed in BOTH directions. A MEMBER's or COLLABORATOR's
# comment whose repository role cannot be read is never accepted as an approval or a waiver, but keeps its blocking
# classification — an edited, multi-marker, digest- or verdict-mismatched comment naming the head still blocks, and a
# REQUEST_CHANGES for the head still counts as one (a newer accepted APPROVE supersedes it, as a writer's) — with a
# reason naming both facts (<reason>-permission-unknown). A KNOWN non-writing role (read, triage, none) neither accepts
# nor blocks (*-not-writer). A failed role lookup is named, with its login and why, in the check's output.
# Covers: REQ-382, REQ-311
for r in marker-member-permission-unknown-request-changes-blocks marker-member-permission-unknown-edited-blocks \
         marker-member-permission-unknown-digest-mismatch-blocks marker-member-read-request-changes-not-blocking \
         marker-member-permission-unknown-request-changes-superseded; do
  ck "fixture for $r" bash -c 'ls "$1"/*-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
ck "fixture 92 is literally the case: a writing MEMBER's REQUEST_CHANGES with an unreadable role next to an OWNER's older APPROVE fails the check" \
  python3 - "$FX/92-marker-member-permission-unknown-request-changes-blocks.json" <<'PY3'
import json, sys
d = json.load(open(sys.argv[1]))
by = {c["author_association"]: c for c in d["comments"]}
assert d["context"]["permissions"] == {} and set(by) == {"OWNER", "MEMBER"}
assert "verdict:APPROVE" in by["OWNER"]["body"] and "verdict:REQUEST_CHANGES" in by["MEMBER"]["body"]
assert by["OWNER"]["created_at"] < by["MEMBER"]["created_at"]
assert d["expect"] == {"state": "request_changes", "reason": "request-changes-permission-unknown", "comment_id": by["MEMBER"]["id"]}
PY3
rctail=$'## SpecFlow verifier (full mode)\n\nFindings noted.\nREQUEST_CHANGES'; rcdg=$(printf '%s\n' "$rctail" | at digest)
python3 -c 'import json, sys
c = lambda i, who, assoc, t, body: {"id": i, "user": {"login": who}, "author_association": assoc, "created_at": t,
  "updated_at": t, "html_url": "https://github.com/o/r/pull/7#issuecomment-%d" % i, "body": body}
print(json.dumps([c(1, "alice", "OWNER", "2026-09-28T10:00:00Z", sys.argv[1]), c(2, "bob", "MEMBER", "2026-09-28T10:01:00Z", sys.argv[2])]))' \
  "$(mk APPROVE "$dg" headless)"$'\n'"$tail" "$(mk REQUEST_CHANGES "$rcdg" headless)"$'\n'"$rctail" > "$S/comments.json"
rm -f "$S/permission.json"; chk
ck "the check: a MEMBER's REQUEST_CHANGES whose role lookup failed, beside an OWNER's older APPROVE, fails (exit 1)" \
  bash -c '[ "$1" = 1 ] && grep -q "requested changes" <<<"$2" && grep -q "permission-unknown\|could not be read" <<<"$2"' _ "$rc" "$out"
ck "…and names the login whose role could not be read, and why (never silent)" \
  bash -c 'grep -q "bob" <<<"$1" && grep -qi "role could not be read" <<<"$1" && grep -q "404" <<<"$1"' _ "$out"
echo '{"permission": "read", "role_name": "read"}' > "$S/permission.json"; chk
ck "…with bob's role known to be read: the REQUEST_CHANGES neither blocks nor is accepted — the OWNER's APPROVE passes" [ "$rc" = 0 ]
rm -f "$S/permission.json"
comments "$(mk APPROVE "$dg" headless)"$'\n'"$tail"

# PR #48 verifier high, the prose (REQ-382, REQ-311): every surface that describes rule 1b says it fails closed in both
# directions — an unreadable role is never accepted and keeps blocking; a known non-writing role neither accepts nor blocks.
# Covers: REQ-382, REQ-311
r1b='an unreadable role is never accepted and keeps blocking; a known `read`, `triage` or `none` role neither accepts nor blocks'
ck "review-gate.md's waiver row states rule 1b in both directions" grep -qF "$r1b" <<<"$(grep -F '| Waivers need a maintainer' "$rg")"
ck "review-gate.md's /next merge row states it for the attestation /next reads" \
  bash -c 'grep -F "| \`/next\` prints a merge command only" "$1" | grep -qF "$2"' _ "$rg" "$r1b"
for e in Waiver 'Attestation marker'; do
  ck "the glossary's $e entry states rule 1b in both directions" \
    bash -c 'awk -v h="### $1" "\$0==h{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " " | grep -qF "$2"' _ "$e" "$r1b"
done

# Scoped re-review of the fix wave (REQ-382, R9; REQ-311): rule 1b knows only read, triage and none as non-writing
# roles. `role_name` is an organisation custom role's own name (or empty) even when its base permission is write, so any
# other role_name is resolved through the legacy `permission` field; neither field recognised → unreadable (never
# accepted, keeps blocking) — never a dropped block. The check's real lookup and --permissions share that shape.
# Covers: REQ-382, REQ-311
for r in marker-member-custom-role-write-request-changes-blocks marker-member-custom-role-read-not-blocking \
         marker-member-role-unrecognised-blocks; do
  ck "fixture for $r" bash -c 'ls "$1"/*-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
ck "fixtures 97–99 carry {role_name, permission} objects and each MEMBER comment is judged as its rule says" python3 - "$A" "$FX" <<'PY4'
import json, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1])); import attestation as a
for n, want in (("97-marker-member-custom-role-write-request-changes-blocks.json", None),
                ("98-marker-member-custom-role-read-not-blocking.json", "marker-not-writer"),
                ("99-marker-member-role-unrecognised-blocks.json", "request-changes-permission-unknown")):
    d = json.load(open(os.path.join(sys.argv[2], n))); c = d["context"]
    assert isinstance(c["permissions"]["bob"], dict), n
    got = {i: r for i, _, r in a.explain(d["comments"], c["head"], c["prompt_sha256"], c["solo"], c["pr_author"],
                                         c["required_mode"], permissions=c["permissions"])}
    assert got.get(2) == want, (n, got)
assert a.resolve_role({"role_name": "custom-x", "permission": "admin"}) == "admin"
assert a.resolve_role({"role_name": "maintain", "permission": "write"}) == "maintain"
assert a.resolve_role({"role_name": "custom-x", "permission": "pull"}) is None
assert a.resolve_role("custom-x") is None and a.resolve_role("") is None and a.resolve_role(None) is None
assert a.resolve_role("none") == "none" and a.resolve_role("triage") == "triage"
PY4
python3 -c 'import json, sys
c = lambda i, who, assoc, t, body: {"id": i, "user": {"login": who}, "author_association": assoc, "created_at": t,
  "updated_at": t, "html_url": "https://github.com/o/r/pull/7#issuecomment-%d" % i, "body": body}
print(json.dumps([c(1, "alice", "OWNER", "2026-09-28T10:00:00Z", sys.argv[1]), c(2, "bob", "MEMBER", "2026-09-28T10:01:00Z", sys.argv[2])]))' \
  "$(mk APPROVE "$dg" headless)"$'\n'"$tail" "$(mk REQUEST_CHANGES "$rcdg" headless)"$'\n'"$rctail" > "$S/comments.json"
echo '{"permission": "write", "role_name": "custom-release-manager"}' > "$S/permission.json"; chk
ck "the check: a custom role_name with the legacy permission write — the MEMBER's newer REQUEST_CHANGES blocks (exit 1)" \
  bash -c '[ "$1" = 1 ] && grep -q "requested changes" <<<"$2"' _ "$rc" "$out"
echo '{"permission": "read", "role_name": "custom-observer"}' > "$S/permission.json"; chk
ck "…a custom role_name with the legacy permission read: neither blocks nor is accepted — the OWNER's APPROVE passes" [ "$rc" = 0 ]
echo '{"permission": "", "role_name": ""}' > "$S/permission.json"; chk
ck "…both fields empty: unreadable — it still blocks, and the check names bob and the raw value" \
  bash -c '[ "$1" = 1 ] && grep -q "permission-unknown" <<<"$2" && grep -q "bob.*role could not be read.*role_name" <<<"$2"' _ "$rc" "$out"
echo '{"permission": "pull", "role_name": "custom-auditor"}' > "$S/permission.json"; chk
ck "…unrecognised values in both fields: unreadable, it still blocks" bash -c '[ "$1" = 1 ] && grep -q "custom-auditor" <<<"$2"' _ "$rc" "$out"
rm -f "$S/permission.json"
for pv in '{"bob": {"role_name": "custom-release-manager", "permission": "write"}}:1' \
          '{"bob": {"role_name": "custom-observer", "permission": "read"}}:0' '{"bob": "custom-release-manager"}:1'; do
  echo "${pv%:*}" > "$W/perms.json"
  rm -f "$S/gh.argv"; rc=0; out=$(cd "$G" && PATH="$S/bin:$PATH" STUB_DIR="$S" python3 "$A" check --repo o/r --pr 7 --head "$GH" \
    --base-ref "$GB" --base-name main --pr-author alice --permissions "$W/perms.json" 2>&1) || rc=$?
  ck "check --permissions accepts the {role_name, permission} shape: ${pv%:*} → exit ${pv##*:}" [ "$rc" = "${pv##*:}" ]
done
comments "$(mk APPROVE "$dg" headless)"$'\n'"$tail"
r1c='any other role name is resolved through the legacy `permission` field, else treated as unreadable'
ck "review-gate.md's waiver row names only read, triage and none as known non-writing roles" \
  bash -c 'grep -F "| Waivers need a maintainer" "$1" | grep -qF "$2"' _ "$rg" "$r1c"
ck "review-gate.md's /next merge row says the same" \
  bash -c 'grep -F "| \`/next\` prints a merge command only" "$1" | grep -qF "$2"' _ "$rg" "$r1c"
for e in Waiver 'Attestation marker'; do
  ck "the glossary's $e entry says the same" \
    bash -c 'awk -v h="### $1" "\$0==h{f=1; next} /^### /{f=0} f" docs/GLOSSARY.md | tr "\n" " " | tr -s " " | grep -qF "$2"' _ "$e" "$r1c"
done
factory_doc_ck "the threat model's dfe-2 row says the same" docs/architecture/2026-09-25-factory-v3-2-threat-model.md \
  bash -c 'grep "^| dfe-2 |" docs/architecture/2026-09-25-factory-v3-2-threat-model.md | grep -qF "$1"' _ "$r1c"

# PR #48 verifier run 2, code-mode high part 2 (REQ-382): rule 1b's known non-writing roles neither accepting nor blocking
# stays as designed; review-gate.md's waiver row states in one sentence that this narrows the pre-P5 rule, and why.
# Covers: REQ-382
nar='This narrows the pre-P5 rule, under which a `MEMBER`'"'"'s comment blocked regardless of repository role: a `MEMBER` or `COLLABORATOR` whose role is known to be `read`, `triage` or `none` can no longer block, because a principal who cannot approve cannot block either — otherwise a read-only organisation member could hold any PR with a hand-posted `REQUEST_CHANGES` (REQ-382 as amended, plan R9).'
ck "review-gate.md's waiver row states the narrowing of the pre-P5 rule and why" \
  bash -c 'grep -F "| Waivers need a maintainer" "$1" | grep -qF "$2"' _ "$rg" "$nar"

# P6 Task 3.1 (REQ-350, REQ-311; PR #52 verifier run 1, finding 9): the classifier's test-only inputs — check's
# --permissions, release-check's --prs, --comments-dir and --commits-dir — are never passed by a workflow,
# release-tag.sh (whose preflight calls release-check) or release-publish.sh; a file that passes one is gate code.
# release-publish.sh is checked once Task 3.4 creates it.
# Covers: REQ-311
for f in .github/workflows/*.yml scripts/release-tag.sh scripts/release-publish.sh; do
  [ -f "$f" ] || continue
  for o in --permissions --prs --comments-dir --commits-dir; do
    ck "$f never passes the test-only $o input" no grep -qF -- "$o" "$f"
  done
done
# PR #56 verifier run 1, V3 (REQ-350; P6 R28): release-check's --since overrides the start of the judged range for the
# preview only — its help says so, and no workflow, release-tag.sh or release-publish.sh passes it (a comment naming it
# is not a call); one that did would shorten the tag-time re-check, and is gate code.
# Covers: REQ-350
ck "release-check --help marks --since preview-only (never passed by release.yml or release-tag.sh)" \
  bash -c 'python3 "$1" release-check --help | tr -s " \n" " " | grep -qF -- "--since SINCE preview-only: overrides the start of the range"' _ "$ROOT/scripts/lib/specflow/attestation.py"
for f in .github/workflows/*.yml scripts/release-tag.sh scripts/release-publish.sh; do
  [ -f "$f" ] || continue
  ck "$f never passes release-check's preview-only --since" bash -c '! grep -v "^[[:space:]]*#" "$1" | grep -qF -- "--since"' _ "$f"
done
# P7 R4 (REQ-382, REQ-311; dfe-2): waivers bind a base as markers do. A bound waiver is judged by the marker's base rule
# (waiver-base-mismatch); a legacy waiver stands only while the PR's timeline shows no base change after it
# (waiver-unbound-retargeted; waiver-timeline-unknown when the timeline cannot be read). Each refuses, never blocks.
# Covers: REQ-382
# Covers: REQ-311
for r in waiver-bound-accepted waiver-bound-base-mismatch waiver-unbound-no-retarget waiver-unbound-retargeted \
         waiver-unbound-retarget-before waiver-unbound-timeline-unknown waiver-bound-base-malformed \
         waiver-unbound-time-empty waiver-unbound-time-null waiver-unbound-retarget-same-second waiver-unbound-time-malformed \
         waiver-commit-bound-not-first-parent; do
  ck "a fixture covers rule '$r'" bash -c 'ls "$1"/[0-9][0-9][0-9]-"$2".json >/dev/null 2>&1' _ "$FX" "$r"
done
ck "114 or more fixtures" [ "$(ls "$FX"/*.json | wc -l)" -ge 114 ]
ck "a refused waiver never blocks: an older accepted APPROVE stands over a newer mismatched or retargeted waiver" python3 - "$ROOT/scripts/lib/specflow" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import attestation as a
H, B, B2, P = "1" * 40, "3" * 40, "5" * 40, "4" * 64
tail = "## SpecFlow verifier (full mode)\n\nNo findings.\nAPPROVE"
appr = a.make_marker(mode="full", sha=H, base=B, prompt_sha256=P, model="opus", verdict="APPROVE",
                     digest=a.digest(tail), origin="headless")
c1 = {"id": 1, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-05T09:00:00Z",
      "updated_at": "2026-10-05T09:00:00Z", "html_url": "u1", "body": appr + "\n" + tail}
for line, kw in ((f"<!-- specflow-verifier:waive sha:{H} base:{B2} -->", {"bases": {B: True, B2: False}}),
                 (f"<!-- specflow-verifier:waive sha:{H} -->", {"bases": {B: True}, "base_changes": ["2026-10-05T11:00:00Z"]})):
    c2 = {"id": 2, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-05T10:00:00Z",
          "updated_at": "2026-10-05T10:00:00Z", "html_url": "u2", "body": line + "\nReviewed by hand: a maintainer-decided waiver."}
    r = a.classify([c1, c2], H, P, True, "alice", "full", **kw)
    assert r["state"] == "approve" and r["comment_id"] == 1, r
PY
ck "pr_attestation reads the timeline only for a legacy waiver naming the head: [] keeps it, a later base_ref_changed or a failed read refuses it" \
  python3 - "$ROOT/scripts/lib/specflow" "$G" "$GB" "$GH" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); os.chdir(sys.argv[2]); import attestation as a
GB, GH = sys.argv[3:5]
def w(line):
    return [{"id": 5, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-05T10:00:00Z",
             "updated_at": "2026-10-05T10:00:00Z", "html_url": "u5", "body": line + "\nReviewed by hand: a maintainer-decided waiver."}]
legacy = f"<!-- specflow-verifier:waive sha:{GH} -->"
bound = f"<!-- specflow-verifier:waive sha:{GH} base:{a._git_rev_parse(GB)} -->"
def run(comments, timeline):
    calls = []
    def gh(ep):
        calls.append(ep)
        if ep.endswith("/timeline"):
            if isinstance(timeline, Exception):
                raise timeline
            return timeline
        assert ep.endswith("/comments"), ep
        return comments
    r = a.pr_attestation(repo="o/r", pr=7, head=GH, base_ref=GB, pr_author="alice", gh_json=gh, commits=[], permissions={})
    return r, [c for c in calls if c.endswith("/timeline")]
ev = lambda at: {"event": "base_ref_changed", "created_at": at}
r, tl = run(w(legacy), [])
assert (r["state"], r["reason"]) == ("waiver", "accepted") and tl == ["repos/o/r/issues/7/timeline"], (r, tl)
r, _ = run(w(legacy), [{"event": "labeled", "created_at": "2026-10-05T12:00:00Z"}, ev("2026-10-05T09:00:00Z")])
assert r["state"] == "waiver", r
r, _ = run(w(legacy), [ev("2026-10-05T11:00:00Z")])
assert (r["state"], r["reason"]) == ("none", "waiver-unbound-retargeted"), r
r, _ = run(w(legacy), a.AttestationError("gh: Server Error (HTTP 502)", code=2))
assert (r["state"], r["reason"]) == ("none", "waiver-timeline-unknown"), r
r, tl = run(w(bound), [ev("2026-10-05T11:00:00Z")])
assert r["state"] == "waiver" and tl == [], (r, tl)
r, tl = run([], [])
assert tl == [], tl
PY
# P7 Build 1 final review (findings 2, 7): GitHub records the automatic retarget it makes when a stacked PR's base branch
# is deleted as automatic_base_change_succeeded (or _failed), and a base rewrite as base_ref_force_pushed; nothing
# measured whether either also emits base_ref_changed. Every base_ref_* or automatic_base_change* event at or after the
# waiver's second refuses a legacy waiver (fail closed); a base event with no readable time is an unreadable timeline;
# a head event (head_ref_force_pushed) is not a base change.
# Covers: REQ-382
ck "pr_attestation: any base_ref_* or automatic_base_change* event at or after a legacy waiver refuses it; one with no time reads as an unreadable timeline" \
  python3 - "$ROOT/scripts/lib/specflow" "$G" "$GB" "$GH" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); os.chdir(sys.argv[2]); import attestation as a
GB, GH = sys.argv[3:5]
W = "2026-10-05T10:00:00Z"
comments = [{"id": 5, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": W, "updated_at": W,
             "html_url": "u5", "body": f"<!-- specflow-verifier:waive sha:{GH} -->\nReviewed by hand: a maintainer-decided waiver."}]
def run(timeline):
    def gh(ep):
        return timeline if ep.endswith("/timeline") else comments
    return a.pr_attestation(repo="o/r", pr=7, head=GH, base_ref=GB, pr_author="alice", gh_json=gh, commits=[], permissions={})
for name in ("automatic_base_change_succeeded", "automatic_base_change_failed", "base_ref_force_pushed", "base_ref_deleted",
             "base_ref_changed"):
    r = run([{"event": name, "created_at": "2026-10-05T11:00:00Z"}])
    assert (r["state"], r["reason"]) == ("none", "waiver-unbound-retargeted"), (name, r)
    r = run([{"event": name, "created_at": "2026-10-05T09:00:00Z"}])
    assert r["state"] == "waiver", (name, r)
r = run([{"event": "base_ref_changed", "created_at": W}])
assert (r["state"], r["reason"]) == ("none", "waiver-unbound-retargeted"), ("same second", r)
for ev in ({"event": "automatic_base_change_succeeded"}, {"event": "base_ref_changed", "created_at": None}):
    r = run([ev])
    assert (r["state"], r["reason"]) == ("none", "waiver-timeline-unknown"), (ev, r)
r = run([{"event": "head_ref_force_pushed", "created_at": "2026-10-05T11:00:00Z"}, {"event": "labeled", "created_at": "2026-10-05T11:00:00Z"}])
assert r["state"] == "waiver", r
PY
printf '[{"event": "labeled", "created_at": "2026-09-28T09:00:00Z"}]\n[{"event": "base_ref_changed", "created_at": "2026-09-28T11:00:00Z"}]\n' > "$S/timeline.json"
waiver alice OWNER; chk
ck "check: a legacy waiver whose PR timeline's second page holds a later base_ref_changed fails as waiver-unbound-retargeted (gh --paginate pages are flattened)" \
  bash -c '[ "$1" = 1 ] && grep -q "waiver-unbound-retargeted" <<<"$2" && grep -q "repos/o/r/issues/7/timeline" "$3"' _ "$rc" "$out" "$S/gh.argv"
ck "…and prints the bound waiver to post instead, this head and this base named (waiver-unbound-retargeted)" \
  grep -qF "waiver-unbound-retargeted — a waiver binds the base it was posted against: post <!-- specflow-verifier:waive sha:$GH base:$GB -->" <<<"$out"
# P7 Build 1 fix wave 1, FIX 1 (R4: the timeline read fails closed): a gh answer that is not JSON is an unreadable
# timeline — waiver-timeline-unknown with the bound-waiver hint, never a traceback and never acceptance.
# Covers: REQ-382
printf 'this is not JSON <html>' > "$S/timeline.json"
waiver alice OWNER; chk
ck "check: a timeline answer that is not JSON refuses a legacy waiver as waiver-timeline-unknown (exit 1, no traceback)" \
  bash -c '[ "$1" = 1 ] && grep -q "waiver-timeline-unknown" <<<"$2" && ! grep -q "Traceback" <<<"$2"' _ "$rc" "$out"
ck "…and prints the bound waiver to post instead (waiver-timeline-unknown)" \
  grep -qF "waiver-timeline-unknown — a waiver binds the base it was posted against: post <!-- specflow-verifier:waive sha:$GH base:$GB -->" <<<"$out"
rm -f "$S/timeline.json"; chk
ck "…with no timeline event the same waiver passes (the stub answers [])" [ "$rc" = 0 ]
python3 -c 'import json, sys
print(json.dumps([{"id": 5, "user": {"login": "alice"}, "author_association": "OWNER",
  "created_at": "2026-09-28T10:00:00Z", "updated_at": "2026-09-28T10:00:00Z", "html_url": "https://github.com/o/r/pull/7#issuecomment-5",
  "body": "<!-- specflow-verifier:waive sha:" + sys.argv[1] + " base:" + "9" * 40 + " -->\nReviewed by hand: a maintainer-decided waiver."}]))' "$GH" > "$S/comments.json"
chk
ck "check: a bound waiver naming another base fails as waiver-base-mismatch and prints the bound waiver for this base" \
  bash -c '[ "$1" = 1 ] && grep -qF "waiver-base-mismatch — a waiver binds the base it was posted against: post <!-- specflow-verifier:waive sha:$2 base:$3 -->" <<<"$4"' _ "$rc" "$GH" "$GB" "$out"
# P7 Build 1 fix wave 1, FIX 11 (R4; REQ-382's P7 sentence): a bound waiver posted on a commit (release-check's direct
# push, pr=None) names the commit's first parent — literally: a sibling of the commit has the same merge base with it
# as the first parent does, which the marker's rule accepts, but the waiver's rule does not.
# Covers: REQ-382
ck "pr_attestation, commit level: a bound waiver is accepted only when it names the commit's first parent, never a base with the same merge base" \
  python3 - "$ROOT/scripts/lib/specflow" "$G" "$GB" "$GH" <<'PY'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1]); os.chdir(sys.argv[2]); import attestation as a
GH = sys.argv[4]
P1 = a._git_rev_parse(GH + "^")  # the judged commit's first parent: release-check's base_ref for a direct push
tree = subprocess.run(["git", "rev-parse", P1 + "^{tree}"], capture_output=True, text=True, check=True).stdout.strip()
sib = subprocess.run(["git", "commit-tree", tree, "-p", P1, "-m", "a sibling of the judged commit"], capture_output=True,
                     text=True, check=True).stdout.strip()
assert a._git_merge_base(sib, GH) == a._git_merge_base(P1, GH) == P1  # the marker's rule would accept sib
def run(base):
    w = [{"id": 5, "user": {"login": "alice"}, "author_association": "OWNER", "created_at": "2026-10-05T10:00:00Z",
          "updated_at": "2026-10-05T10:00:00Z", "html_url": "u5",
          "body": f"<!-- specflow-verifier:waive sha:{GH} base:{base} -->\nReviewed by hand: a maintainer-decided waiver."}]
    def gh(ep):
        raise AssertionError(ep)
    return a.pr_attestation(repo="o/r", pr=None, head=GH, base_ref=P1, pr_author="alice", gh_json=gh, commits=[],
                            comments=w, permissions={})
r = run(P1)
assert r["state"] == "waiver", r
r = run(sib)
assert (r["state"], r["reason"]) == ("none", "waiver-base-mismatch"), r
PY
finish test_attestation
