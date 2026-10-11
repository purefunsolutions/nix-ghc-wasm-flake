# Hand-off: GHC issue for GHC 10's host settings on darwin

Written 2026-10-11 for a new Claude session in `~/ghc`, one of five running in parallel. The
others work on patches 0001, 0002 and 0004 and on the haddock cross-build issue (the other
`handoff-*.md` files in this directory). This file is meant to be self-contained.

**Use the `ghc-contribution` skill**: issue workflow, GHC's LLM policy, and `glab` with
`GITLAB_HOST=gitlab.haskell.org`.

## Goal

Report as a GHC issue: on master, cross compilers built on a macOS host fail. Hadrian's host
templates hardcode values that are wrong for darwin. If a clean fix shows up, it can follow as
an MR, but **the issue comes first**. Prepare texts locally; **the user files the issue.**

## Where things are

- There's no branch for this yet. For a fix, use your own worktree from master, e.g.
  `git -C ~/ghc worktree add -b wip/hadrian-darwin-host-settings ~/ghc-darwin-host origin/master`.
  Don't touch the other `wip/*` branches.
- **The nixpkgs workaround** is in `pkgs/development/compilers/ghc/common-hadrian.nix` (around
  line 669) in `~/nixpkgs-ghcwasm.git`, branch `ghcwasmhacking` (public at
  github.com/mikatammi/nixpkgs). It's applied when `targetPlatform.isWasm &&
  hostPlatform.isDarwin && lib.versionAtLeast version "9.15"`:

  ```
  substituteInPlace hadrian/cfg/system.config.host.in \
    --replace-fail "use-lib-rt        = YES" "use-lib-rt        = NO"
  substituteInPlace hadrian/cfg/default.host.target.in \
    --replace-fail "tgtSymbolsHaveLeadingUnderscore = False" "tgtSymbolsHaveLeadingUnderscore = True" \
    --replace-fail "tgtOtool = Nothing" 'tgtOtool = Just (Program {prgPath = "<cctools>/bin/otool", prgFlags = []})' \
    --replace-fail "tgtInstallNameTool = Nothing" 'tgtInstallNameTool = Just (Program {prgPath = "<cctools>/bin/install_name_tool", prgFlags = []})'
  ```

- **The build notes:** `~/ghc-wasm-flake/results/notes.md`, the "darwin HEAD" entries (librt
  around line 119, otool 144, symbol names 203, green 251).

## The failures

These come from nixpkgs' wasm GHC HEAD (10.1.20260810, GHC `556db2f32f`) on an aarch64-darwin
host. They appeared one at a time; each showed up only after the previous one was worked around.

1. `Missing (or bad) C library: rt` when configuring the RTS for the host.
2. `ghc: otool: could not execute:` when the stage1 compiler links a program for the host
   (`utils/unlit`). The message ends after the colon because the program path is empty.
3. `"user_era", referenced from: … (maybe you meant: _user_era)` when linking host programs:
   symbol names lack Mach-O's leading underscore.

The empty `install_name_tool` was fixed together with otool, so it never produced its own error.
With all four values fixed, wasm GHC HEAD builds on aarch64-darwin, and the hello-world tests,
Template Haskell included, pass under wasmtime.

## Causes

- On master, when cross compiling, stages 0 and 1 build for the host. This came with
  `23c9b6c392` "hadrian: Build stage 2 cross compilers" (Matthew Pickering, from !15231
  "Stage2 cross-compilers" by Sven Tennie, merged 2026-06-23):
  - `targetStage` (`hadrian/src/Oracles/Setting.hs:238-250`) returns the host target for those
    stages;
  - `lookupStageBuildConfig` (`hadrian/src/Hadrian/Oracles/TextFile.hs:72-78`) reads
    `system.config.host` for them. That only happens when cross compiling (lines 57-63), which
    is why native darwin builds are fine.
- **`hadrian/cfg/system.config.host.in:61`** hardcodes `use-lib-rt = YES`. The target's
  `system.config.target.in:67` uses configure's `@UseLibrt@`. Hadrian turns it into the rts
  package's `librt` flag (`hadrian/src/Settings/Packages.hs:406`). macOS has no librt; Linux
  does, so the hardcoded value happens to be right on Linux hosts.
- **`hadrian/cfg/default.host.target.in`** (hadrian's `buildTargetFile`, `hadrian/src/Base.hs:94`;
  `hostTargetFile` is the same file) hardcodes:
  - `tgtSymbolsHaveLeadingUnderscore = False` (line 10);
  - `tgtOtool = Nothing` (line 49);
  - `tgtInstallNameTool = Nothing` (line 50).

  The target template `default.target.in` fills the same fields from configure:
  `@LeadingUnderscoreBool@`, `@OtoolCmdMaybeProg@` and `@InstallNameToolCmdMaybeProg@`.
- **This is known unfinished work.** `521e55bf69` "hadrian: Fill in more of the default.host
  toolchain file" (Matthew Pickering, also in !15231) started filling the host template
  from `*_STAGE0` configure values (`@CC_STAGE0@`, `@NmCmdStage0@`, `@LdIsGNULd_STAGE0Bool@`, …).
  Its message says "There is still more work to be done". These four values are part of that.

## Scope

- **master:** affected since `23c9b6c392`. The templates haven't changed since nixpkgs' snapshot
  `556db2f32f`. Recheck with `git -C ~/ghc log --oneline 556db2f32f..origin/master -- hadrian/cfg/`.
- **ghc-10.0:** probably not affected. It has no `system.config.host.in`, and its
  `default.host.target.in` has the same three hardcoded values. But in 10.0 only stage0 uses the
  host target (`targetStage (Stage1 {}) = getTargetTarget`), and stage0 is the bootstrap compiler.
  9.14 has the same template, and its wasm build on darwin is green. **Confirm by reading the
  code**; no build needed.
- **Which targets:** the values don't depend on the target, so this likely breaks every cross
  build on a macOS host, not just wasm. Only wasm was tested; say so.
- **Why GHC's CI doesn't notice:** every cross job runs on a Linux host
  (`.gitlab/generate-ci/gen_ci.hs`: wasm on Alpine, JS on Debian 11, aarch64, riscv64 and
  loongarch64 on Debian 13, Windows Arm64 on Debian 12 with Wine).

## Related

- **#26720** (open, newcomer task, "Guard tool execution against empty tool path"): GHC should
  refuse to run an empty tool path from `default.host.target`. That would turn failure 2 into a
  clear message, but not fix the values.
- #26939 ("ghc-toolchain configuration difference for alpine wasi job") matched `tgtOtool` in the
  duplicate search. It's about the target's configuration, so probably unrelated, but read it.

## Possible fix directions (for a follow-up MR, only after the issue)

1. Follow `521e55bf69`: have configure find host values and substitute them, like the target's.
   That means otool and install_name_tool for the build machine, and leading underscore and
   librt checked with `CC_STAGE0`. Or derive them from the build OS.
2. Take them from the bootstrap compiler, which is the host toolchain. Its settings already
   contain "Leading underscore", "otool command" and "install_name_tool command" for the build
   platform.
3. Whatever ghc-toolchain's direction is. It generates `.target` files, so check whether it
   already produces a host one.

The issue can mention these briefly without picking one.

## Duplicate check (2026-10-11)

- `default.host.target`: #26720 (related, above) and #24525 (Windows bindists, unrelated).
- `system.config.host` and `use-lib-rt`: nothing.
- `tgtOtool`: #26939 (above) and #27871 (mingw bindists, unrelated).
- **Redo it right before filing.** Also try `otool: could not execute`, `user_era`, "Missing (or
  bad) C library: rt" and "leading underscore".

## To do

1. **Confirm the causes on master** by reading: the templates, `targetStage`,
   `lookupHostBuildConfig`. Then confirm the 10.0 scope and the CI claim.
2. **Duplicate check** with the skill (glab).
3. **Draft the issue** with the skill's `references/issue.md`:
   - **title:** e.g. "Cross builds on macOS hosts fail: hadrian's host config hardcodes librt,
     otool and symbol prefix";
   - **body:** the three errors, the causes with `file:line`, the scope (master, not 10.0;
     probably every darwin-hosted cross build, only wasm tested), why CI misses it, the nixpkgs
     workaround as evidence that these four values are all it takes, links to !15231,
     `521e55bf69` and #26720, and the fix directions in a sentence or two;
   - start with the LLM disclosure, keep it short, and save it to
     `~/ghc-wasm-flake/drafts/ghc-issue-darwin-host-settings.paste.md`.
4. **Stop.** The user files it. Then update the darwin host-settings row of the "Upstream
   tracker" in `~/ghc-wasm-flake/README.md`: link the issue, and replace "10.0 untested" with what
   step 1 found. Commit there with `Assisted-by: Claude Code (Claude Opus 5.5)` and
   `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`.
5. **Report back** for nixpkgs: the workaround's condition `versionAtLeast version "9.15"` would
   also match a future GHC 10.0 package. That has no `system.config.host.in`, so `--replace-fail`
   would fail. If 10.0 is unaffected, the condition should be `versionAtLeast version "10.1"`.
   The main session changes the nixpkgs branch; don't push it.
6. **Optional MR**, only after the issue exists and the user agrees: the fix, tested on darwin
   through nixpkgs with the workaround removed. That's a long build on this Mac, so ask first,
   and don't overlap it with Linux builds.

## Ground rules (the user's standing preferences)

- **Never file, comment or push anything** without the user's explicit go-ahead.
- **GPG:** remind the user to sign before any push or MR.
- **GHC's LLM policy:** disclosure at the top, short prose, the human as author. Draft for the user
  to review and rework.
- **Ask before long builds or big downloads**, and avoid them entirely if the user mentions mobile
  data roaming.
- **Builds:** one architecture at a time. The Mac's Linux VM shares the Mac's cores, so don't
  overlap darwin and Linux builds there.
- **Shell (zsh) pitfalls:**
  - an unquoted `$var` isn't word-split;
  - `$ref:r…` is read as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status;
  - `git cherry-pick` has no `-q`.
