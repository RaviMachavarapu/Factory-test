# Examples (factory only)

The factory's index of its worked examples. This file is fenced out of every instance (`scripts/factory-only.txt`); the
examples themselves are listed in `CLAUDE.md`'s "Canonical Example" manifest.

- `habit-tracker/` — the tauri example (REQ-391): documents only, kept by a tauri instance, removed by every other stack.
- The demo greeting (python): `docs/specs/2026-05-28-demo-greeting-design.md` and its derived artifacts, listed in the manifest.

## The habit-tracker walk (REQ-391)

By hand, in a throwaway instance repository; agents never run these. `export GH_TOKEN="$(gh auth token --user kpingali123)"`
first in every shell that runs `gh`.

- **M1 — the throwaway instance (R10).** After `v3.2.0`'s Release is published: `git clone https://github.com/Apps-Consultants/factory.git habit-tracker && cd habit-tracker && git checkout --detach v3.2.0 && rm -rf .git && git init -b main`; create an empty private repository (a personal account reproduces the founder's free-plan path — about 200 macOS minutes a month, one tauri release costs about 100; the evidence records which account and plan), `git remote add origin <url>`. The factory is private: the HTTPS clone needs `gh auth setup-git` first (or clone over the SSH alias, `git@github.com-appsconsultants:Apps-Consultants/factory.git`). **Probe the `release` environment on the chosen plan** (fresh-eyes review, finding 17): `release.yml`'s `signing-probe` job declares `environment: release` unconditionally (`release.yml:460`, and the macOS job `:491`), and whether a job that names an environment runs on a GitHub Free personal private repository is unmeasured — after M2's `configure-repo.sh`, read `gh api repos/<owner>/<repo>/environments` and record the answer; if the environment cannot exist there, use an organisation repository or a public one for the walk and record which. Keep: the repository URL (or a description), the account and plan, the environment probe's answer, the commit `v3.2.0` names.
- **M2 — init.** First `bash scripts/init-project.sh --doctor --stack tauri` on the build Mac (Rust, Node, the Xcode command-line tools; fix every `MISSING` line it prints), then `bash scripts/init-project.sh` interactively: profile guided (Enter), name "Habit Tracker", "What are you building?" → the Mac desktop choice (tauri), solo (Enter); then `git push -u origin main` and `bash scripts/configure-repo.sh` (on a free private repository it reports the 403s; keep its output). Keep: the init transcript, `.specflow.yml`.
- **M3 — the walk.** In Claude Code inside the instance, run `/next` at every step and do what it prints or runs, from `IDEA.md` (a macOS habit tracker: add a habit, check it off today, a streak) through `design/<slug>` (brainstorm, spec, architecture, plan, tasks, analyze), every `build/<slug>-N`, to `ship/0.1.0`; run the verifier in a second terminal exactly as `/next` prints it; merge only when `/next` prints the merge. **Save every `/next` output** to `transcripts/NN-<where>.txt` as you go (NN two digits in run order, `<where>` the branch with `/` → `_`, or `main`). **Before `ship/0.1.0`** (fresh-eyes review, finding 17): the instance's `.github/allowed_signers` starts comment-only (`init-project.sh:684-694`), and `release-tag.sh` refuses an SSH-signed tag no anchor or first-use key covers (exit 6) — so add the maintainer's own key line (`<git email> namespaces="git" <the .pub contents>`, exactly as `git config user.email` spells it) by a reviewed `patch/allowed-signers` PR merged before the ship branch is cut (trust on first use: the key is trusted from the release after the first one tagged on a commit that lists it — the instance's first release `v0.1.0` then verifies as the first-use tag). If the maintainer instead takes the guided `unsigned-tag` path at M4, skip this and record the annotated fallback. Keep: every PR number and its verifier marker comment link.
- **M4 — the release.** After the ship PR merges: `/next` prints `/release --tag 0.1.0` (SSH signing configured per the instance's README; or the guided `unsigned-tag` confirmation and the annotated fallback); then `gh run watch` on the instance's `release.yml` run until it publishes. Keep: the Release URL, the run id, `manifest.json` (`signed: false`), the tester-instructions file.
- **M5 — the second Mac.** On another Mac (not the build machine), signed in to GitHub with an account that can read the private instance repository (a private repository's Release assets need it — or the walk used a public repository, M1), download the bundle from the Release page and follow `docs/releases/0.1.0-tester-instructions.md` exactly as written until the app opens and a habit can be checked off. Keep: the macOS version, each step that worked or did not, one screenshot reference (not committed), and a note of any instruction that was wrong — a wrong instruction is a finding for the retrospective, not a fix in the instance.
- **M6 — the copy-back (R10).** In the factory, on `patch/habit-tracker-example` from `main`: copy the instance's `docs/` tree at its Release commit to `docs/examples/habit-tracker/docs/`, the transcripts to `docs/examples/habit-tracker/transcripts/`, replace every home-directory path in the **whole copied tree** with `~` — transcripts and `docs/` alike, CI paths too, since `test_examples.sh` greps all of `docs/examples/habit-tracker/` for `/(Users|home)/<name>/` (`grep -rlE '/(Users|home)/[A-Za-z0-9._-]+/' docs/examples/habit-tracker | xargs sed -i '' -E "s#$HOME#~#g; s#/(Users|home)/[A-Za-z0-9._-]+/#~/#g"`, then the same `grep -rE` prints nothing), run `gitleaks dir docs/examples --config <a config with useDefault = true and no allowlist> --no-banner --redact` (nothing found), run `bash tests/governance/test_reviews_use_slugs.sh` on the copied tree before the gates (the docs-wide article-citation check reads every Markdown file under `docs/`, `docs/examples/` included: a copied document that cites an article by Roman numeral, or by an `art-` slug this factory's `constitution.md` does not define, fails the factory's gates, a slug in backticks included; rewrite each such citation in the copy as the factory's slug and note the change in the example README's Evidence section; added to M6 by amendment D's PR, 2026-10-04, BL-041), update `docs/examples/habit-tracker/README.md`'s status line to `Status: walked on YYYY-MM-DD from v3.2.0; Release: <URL>.` and add the evidence (M1–M5) to its `## Evidence` section (facts about the example, never the checklist, which stays in the fenced `docs/examples/README.md`); run the gates; open the PR; the verifier runs as for any PR; merge.

### M6's copy rule (what "the instance's `docs/` tree" means)

Copy only the walked instance's own pipeline artifacts, as tracked at its Release commit: `docs/specs/`, `docs/adr/`,
`docs/architecture/`, `docs/plans/`, its own release's security records `docs/security/<version>-*` and release records
`docs/releases/<version>-*` (the tester instructions `docs/releases/0.1.0-tester-instructions.md` among them),
`docs/reviews/`, and `docs/retrospectives/` if the walk ran one; then the transcripts. Copy never `docs/examples/` (an
instance made from `v3.2.0` carries this example's pending README there, and a blind copy would nest
`docs/examples/habit-tracker/docs/examples/habit-tracker/README.md`), and never a document the instance inherited from
this template rather than wrote: `docs/adr/002-security-disposition-decision.md`, `docs/adr/README.md`,
`docs/architecture/README.md`, `docs/security/README.md`, `docs/security/RUBRIC.md`, `docs/releases/README.md`,
`docs/releases/store-checklist.md`, `docs/releases/tester-instructions.md` (the template the instance's own tester
instructions are generated from), `docs/retrospectives/README.md`, `docs/GLOSSARY.md`, `docs/BACKLOG.md` and
`docs/getting-started.html` (the user guide) — those are the factory's own documents, already here. `test_examples.sh` measures that inherited set in a scratch tauri instance,
fails when this list misses one of them, and fails when `docs/examples/habit-tracker/docs/` holds `docs/examples/` or any
of them.

## External product (REQ-392)

Met: a repository other than the factory and other than the throwaway habit tracker (unless the maintainer decides at the
retrospective to keep the habit tracker as the product, recorded on BL-019), created from `v3.2.0` (or `fbd432a`), driven
by the maintainer through the lanes path via `/next` (design, build(s), ship), whose `release.yml` run published a non-draft
GitHub Release from a `v<X.Y.Z>` tag on its `main`.

Recorded either way, by a reviewed `patch/` PR: the repository (or a description, if private), the Release URL, the
`release.yml` run id, and the manifest's `signed` value.

Status: not met (the v3.2.0 release's known-limitations (ship PR #62) records the gate as open; docs/BACKLOG.md BL-019).
