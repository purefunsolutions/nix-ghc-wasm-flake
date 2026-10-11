# Hand-off: GHC issue for the haddock failure in GHC 10 cross builds

Written 2026-10-11 for a new Claude session in `~/ghc`, running in parallel with the wasip1
session (`handoff-ghc-patch-0001.md`). This file is meant to be self-contained.

**Use the `ghc-contribution` skill**: issue workflow, GHC's LLM policy, and `glab` with
`GITLAB_HOST=gitlab.haskell.org`.

## Goal

Report a GHC master regression as an issue: GHC 10 cross builds fail in hadrian's haddock index
step. If the investigation turns up a clean fix, that can follow as an MR, but **the issue comes
first**. Prepare texts locally; **the user files the issue.** This work starts with investigation
and an issue, not a patch, so it doesn't touch the `wip/*` branches. If you need a checkout of
an older commit, use a worktree. `~/ghc-bisect` already exists, detached at `23c9b6c392`.

## The failure

Building a cross compiler from GHC master (seen with wasm and with the JS backend) runs to 99%
and then fails in `Run Haddock BuildIndex`:

```
| Run Haddock BuildIndex: _build/doc/html/libraries/Cabal-syntax-3.16.1.0/Cabal-syntax.haddock (and 45 more) => _build/doc/html/libraries/index.html
Command line: _build/stage1/bin/javascript-unknown-ghcjs-haddock -B_build/stage1/lib --lib=_build/stage1/lib --gen-index --gen-contents -o _build/doc/html/libraries ...
haddock: internal error: _build/stage1/lib/../../stage0/lib/package.conf.d/package.cache: GHC.Unit.Database.readPackageDb: inappropriate type (not enough bytes)
```

## What's known

- **Bisected to `23c9b6c392`** "hadrian: Build stage 2 cross compilers" (Matthew Pickering;
  written 2023-12-21, merged 2026-06-20).
  - Its parent `521e55bf69` builds completely, docs index included; `23c9b6c392` fails as above.
  - Test setup: nixpkgs' JS-backend cross GHC HEAD (x86_64-linux), built from a given GHC commit
    with nixpkgs' workaround removed. The infrastructure is on the NUC (`ssh 10.1.0.17`,
    x86_64-linux):
    - `~/bisect-haddock/bisect.nix`;
    - `~/bisect-haddock/test-rev.sh <full rev>`, which prints good, bad or skip;
    - the logs `~/bisect-haddock/521e55bf69.log` and `23c9b6c392.log`.
- **Hydra history** (nixpkgs' haskell-updates jobset, job
  `pkgsCross.ghcjs.haskell.packages.ghcHEAD.ghc.x86_64-linux`):
  - green on every GHC master snapshot up to 10.1.20260513 (GHC `38b76b2f`);
  - failing since 10.1.20260810 (GHC `556db2f3`), from 2026-08-15. Example log:
    https://hydra.nixos.org/build/347803739/log/raw
- **Scope:** master only. `23c9b6c392` isn't in `ghc-10.0`. 9.12 and 9.14 cross builds produce
  their haddocks fine.
- **nixpkgs works around it** by skipping library haddocks for cross GHC ≥ 10
  (`--docs=no-haddocks`; commit "haskell.compiler: no haddock docs for cross GHC >= 10" in
  `ghcwasmhacking`, github.com/mikatammi/nixpkgs). nixpkgs builds with
  `hadrian <flags> binary-dist-dir`.
- **Related upstream:**
  - **!16291** (Zubin Duggal, closed unmerged 2026-07-02): "hadrian: binary-dist-dir should not
    be the default target". `23c9b6c392` made `binary-dist-dir` the default and added
    `binary-dist-dir-cross`.
  - The package database binary format changed in `1ac1a541` (static linking support; it added
    `extra-libraries-static`). "not enough bytes" fits a stage1 haddock reading a
    `package.cache` written in an older format. **This is a hypothesis, unverified.**
- **No existing issue or MR** (searched 2026-10-11: `readPackageDb`, "not enough bytes",
  `BuildIndex`, `23c9b6c392`, "haddock cross"). Redo the search right before filing.

## The open question: does GHC's own CI hit it?

From `.gitlab/generate-ci/gen_ci.hs` on master:
- Some cross jobs build no docs at all: the Windows ARM ones set `HADRIAN_ARGS = --docs=none`
  ("Cross compiler validate does not need any docs").
- The **wasm jobs do build haddocks** (`--docs=no-sphinx-pdfs --docs=no-sphinx-man`, in
  `make_wasm_jobs`). JS jobs: check which docs flags they get.

So either GHC's wasm CI on master fails at the same step (look at the nightly and master
pipelines since 2026-06-20 with `glab`), or something in nixpkgs' setup differs. Candidates: the
bootstrap compiler, which writes stage0's package database; the `binary-dist-dir` target; or
`--hash-unit-ids`. **Settle this first**, because it decides how the issue reads.

## To do

1. **Duplicate check** with the skill (glab), with the terms above.
2. **CI check:** find the wasm and JS jobs of recent master and nightly pipelines and whether they
   pass the haddock index step. Use `scripts/ghc-mr-ci.py`, or `glab ci` / `glab api` with
   `GITLAB_HOST=gitlab.haskell.org`.
3. **Confirm on current master** (`e7cacf59b8` or newer): run
   `~/bisect-haddock/test-rev.sh <rev>` on the NUC. It takes about an hour. **Ask the user before
   starting it**, and check that the NUC is free first (`ps -eo args | grep [n]ix-build`); it may
   still be running other builds.
4. **Root cause (optional, time-boxed):** read what `23c9b6c392` changed in hadrian's
   documentation rules (`hadrian/src/Rules/Documentation.hs`,
   `hadrian/src/Settings/Builders/Haddock.hs`, the package database setup). Find why the stage1
   haddock reads `stage0/lib/package.conf.d`, and who writes that `package.cache` (the bootstrap
   `ghc-pkg` or an in-tree one). If a small, obviously right fix appears, note it for a follow-up
   MR; don't widen the scope of the issue.
5. **Draft the issue** with the skill's `references/issue.md`:
   - **title:** e.g. "Cross builds fail in the haddock index step since 23c9b6c392";
   - **body:** the error, reproduction, bisect result, affected branches (master, not 10.0),
     the CI finding, the nixpkgs workaround, a link to !16291, and the format hypothesis
     clearly marked as such;
   - start with the LLM disclosure, and save it to
     `~/ghc-wasm-flake/drafts/ghc-issue-haddock-cross.paste.md`.
6. **Stop.** The user files it. Then update the haddock row of the "Upstream tracker" in
   `~/ghc-wasm-flake/README.md` with the issue link. Commit there with
   `Assisted-by: Claude Code (Claude Opus 5.5)` and
   `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`.

## Ground rules (the user's standing preferences)

- **Never file, comment or push anything** without the user's explicit go-ahead.
- **GPG:** remind the user to sign before any push or MR.
- **GHC's LLM policy:** disclosure at the top, short prose, the human as author. Draft for the user
  to review and rework.
- **Ask before long builds or big downloads**, and avoid them entirely if the user mentions mobile
  data roaming.
- **Shell (zsh) pitfalls:**
  - an unquoted `$var` isn't word-split;
  - `$ref:r…` is read as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status;
  - `git cherry-pick` has no `-q`.
