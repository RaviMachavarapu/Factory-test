# Habit tracker — the second worked example (REQ-391)

A macOS habit tracker (add a habit, check it off today, see a streak) to be taken through the lanes path of this
pipeline, from `IDEA.md` to a published GitHub Release, to show a stack other than the python demo working end to end. It
complements the demo greeting (the python example, which stays with a python instance). The Status line at the end of
this file says whether the walk has happened: while it says pending, this directory holds only this README and the
sections below describe how the example is to be made, not what has happened.

This directory holds documents only: Markdown and text files. No source code, no second stack skeleton, no proof ships
with it. No pipeline gate reads it: traceability, covers, the ADR linkage, the architecture check, the security-disposition
gate and the release gate read only the top-level pipeline directories (`docs/specs/`, `docs/plans/`, `docs/adr/`,
`docs/architecture/`, `docs/security/`, `docs/releases/`), so a spec, plan, ADR or security review here does not count as
one of your own, and the gates' secret scan skips it (`.gitleaks.toml` allowlists example directories). One check does
read it: the docs-wide article-citation check, `tests/governance/test_reviews_use_slugs.sh`, reads every Markdown file
under `docs/`, so an article cited here by Roman numeral, or by a slug your `constitution.md` does not define, fails your
gates — after a retrospective renames or removes an article's slug, update the citations here as well.

## Provenance

How the example is made; the Evidence section records what actually happened once it has been walked.

- A throwaway instance repository, created from the factory release `v3.2.0` (or from commit `fbd432a` if the walk began
  before `v3.2.0` was tagged; the status line and the evidence say which).
- Stack: tauri (a macOS desktop app). Configuration: `profile: guided`, `solo: true`, the lanes path.
- Driven by `/next` at every step: `design/<slug>` (brainstorm, spec, architecture, plan, tasks, analyze), each
  `build/<slug>-N`, then `ship/0.1.0`.
- To be released as an unsigned bundle: the Release will carry the generated tester instructions, and a tester on a
  second Mac will open the bundle by following those tester instructions exactly as written.

## Layout

```
docs/examples/habit-tracker/README.md       this file
docs/examples/habit-tracker/docs/           the instance's docs/ tree, as committed there at its Release
docs/examples/habit-tracker/transcripts/    every /next output in run order: NN-<where>.txt, NN two digits,
                                            <where> the branch with / replaced by _ (03-design_habit-tracker.txt)
```

The `docs/` tree and the `transcripts/` directory arrive once the example has been walked; until then only this file is
here. Every home-directory path in the copied files is written as `~`.

## Evidence

(Filled in once the example has been walked: the repository and plan used, the pull requests and their verifier
markers, the Release URL and `release.yml` run, the manifest, and what the second Mac showed.)

Status: pending the maintainer's walk (REQ-391).
