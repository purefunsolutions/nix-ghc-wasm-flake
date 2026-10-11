# Hand-off: upstream GHC patch 0002 (no target libffi for a cross compiler's stage0)

Written 2026-10-11 for a new Claude session in `~/ghc`, one of five running in parallel. The
others work on wasip1 (`handoff-ghc-patch-0001.md`), XXH3 (`handoff-ghc-patch-0004.md`), the
haddock cross-build issue (`handoff-ghc-haddock-cross-regression.md`) and the darwin host
settings (`handoff-ghc-darwin-host-settings.md`). This file is meant to be self-contained.
Earlier patches from this project are GHC !16791 (#27926) and !16794 (#27929); their finished
texts are the `drafts/ghc-*rts-*.paste.md` files.

**Use the `ghc-contribution` skill**: issue first, the smallest correct change, GHC's LLM policy,
commit linting, and `glab` with `GITLAB_HOST=gitlab.haskell.org`.

## Goal

First find out whether GHC master still needs this patch. Reading the code says it doesn't, but
the release branches do (see below); a build has to confirm that. Then turn it into an issue plus
merge request(s) for the affected branches. Prepare everything locally. **The user files the
issue, pushes and opens the MRs, after GPG-signing the commits by hand.**

## Where things are

- **Work in your own worktree.** Other sessions use `~/ghc`:

      git -C ~/ghc worktree add ~/ghc-0002 wip/hadrian-cross-stage0-libffi

- Branch **`wip/hadrian-cross-stage0-libffi`** is `origin/master` (`e7cacf59b8`; master hadn't
  moved when fetched on 2026-10-11) plus one commit, `408003f0a9`. That commit still has the
  long draft message, the old trailer, a 68-character subject and a three-line code comment.
- Don't touch the other `wip/*` branches: !16791, !16794, `wip/wasm-accept-wasip1` and
  `wip/rts-no-xxh3-on-32-bit` each belong to someone else.
- The patch as a file: `~/ghc-wasm-flake/upstream/ghc/0002-hadrian-don-t-use-the-target-s-libffi-for-a-cross-compiler-s-stage0.patch`.
  nixpkgs carries it as `hadrian-cross-stage0-no-target-libffi.patch` for every wasi target
  (9.12, 9.14 and HEAD) in `pkgs/development/compilers/ghc/common-hadrian.nix`, in
  `~/nixpkgs-ghcwasm.git` (branch `ghcwasmhacking`, public at github.com/mikatammi/nixpkgs).

## The change

`hadrian/src/Settings/Packages.hs`, in the `ghc` package's arguments (master line 161; 10.0: 166,
9.14: 158, 9.12: 164):

```haskell
-            builder (Cabal Setup) ? cabalExtraDirs ffiIncludeDir ffiLibraryDir
+            builder (Cabal Setup) ? orM [notStage0, expr (notM cross)] ? cabalExtraDirs ffiIncludeDir ffiLibraryDir
```

Per the skill's smallest-change rule, drop the three-line comment above it or cut it to one line.

## The bug

- configure's `--with-ffi-includes` and `--with-ffi-libraries` describe the **target's** libffi.
  Hadrian passes them to every build of the `ghc` package. That includes the stage0 build, which
  the bootstrap compiler builds for the build platform and links into the stage1 compiler.
- **Seen with wasm** (x86_64-linux, GHC 9.14.1, 2026-10-09): linking the stage1 compiler failed
  with `ld.gold: error: ffi: plugin failed to claim member ffi.o`, then undefined `ffi_call` /
  `ffi_type_*` from the bootstrap RTS. `-L<libffi-wasm>/lib` ended up on the host link line, so
  the bootstrap RTS's `-lffi` picked the wasm archive.
- ELF cross targets survive, because the linker skips incompatible archives. Wasm archives make
  gold's plugin fail instead. aarch64-linux and darwin weren't tried without the patch.
- haskell.nix avoids it by not passing `--with-ffi-*` for wasm at all. That leaves the installed
  rts without libffi's library directory.
- **Verified:** nixpkgs builds wasm GHC 9.12, 9.14 and HEAD with the patch (stock LLVM 21,
  wasi-libc 32) on aarch64-darwin, aarch64-linux and x86_64-linux, and they pass their tests
  under wasmtime. 10.0: the patch applies, but nixpkgs has no 10.0 package, so it's not built.

## Is master still affected? Probably not

`23c9b6c392` "hadrian: Build stage 2 cross compilers" (Matthew Pickering, from !15231
"Stage2 cross-compilers", merged 2026-06-23; **not** in `ghc-10.0`) changed how hadrian looks up
these settings:
- `Packages.hs:38-39` on master: `ffiIncludeDir <- staged (buildSetting FfiIncludeDir)`. The
  release branches use `getSetting FfiIncludeDir`, the same value for every stage.
- `hadrian/src/Hadrian/Oracles/TextFile.hs:57-78`: when cross compiling, stages 0 and 1 read
  `system.config.host` (`lookupHostBuildConfig`).
- `hadrian/cfg/system.config.host.in:45-47`: `use-system-ffi = NO`, and `ffi-include-dir` and
  `ffi-lib-dir` are empty.

So on master the stage0 `ghc` library should get no libffi directories, and the patch would be a
no-op there. It still applies, because the line itself didn't change.

nixpkgs' ghcHEAD is GHC `556db2f32f` (10.1.20260810), which already contains `23c9b6c392`. Since
then only `5939ceaf1f` (Windows path conventions) touched the files involved, and not these
settings. So nixpkgs' HEAD is as good as master for this question. Rerun that check:

    git -C ~/ghc log --oneline 556db2f32f..origin/master -- hadrian/src/Settings/Packages.hs \
      hadrian/cfg/system.config.host.in hadrian/src/Hadrian/Oracles/TextFile.hs

## The proof build

Build nixpkgs' wasm GHC HEAD **without** the patch on x86_64-linux, where gold failed. Use the NUC
(`ssh 10.1.0.17`, x86_64-linux). It has `~/nixpkgs-ghcwasm.git` at the branch tip (`b708887`) and
the flake's copy in `~/ghcwasm` (old name).

1. **Ask the user first.** The build takes one to two hours. The NUC may be busy: other sessions
   use it, and profiling rebuilds were running there on 2026-10-11. Check with
   `ps -eo args | grep '[n]ix'`. Run one build at a time.
2. On the NUC, make a local test branch. **Never push it**:

       git -C ~/nixpkgs-ghcwasm.git worktree add -b test/0002-no-patch ~/nixpkgs-0002-test ghcwasmhacking

   In its `common-hadrian.nix`, move `./hadrian-cross-stage0-no-target-libffi.patch` out of the
   `isWasi` list into its own `lib.optionals (stdenv.targetPlatform.isWasi && lib.versionOlder
   version "10.1")`. Use `"10.1"`, not `"9.15"`: 10.0 still needs the patch. Commit.
3. Build the HEAD hello check, which builds the compiler first:

       cd ~/ghcwasm && nix build -L --override-input nixpkgs \
         "git+file://$HOME/nixpkgs-ghcwasm.git?ref=test/0002-no-patch" .#checks.x86_64-linux.hello-ghcHEAD

4. **Expected:** it links the stage1 compiler and passes. If so, master doesn't need the patch.
   If it fails at the stage1 link like 9.14.1 did, master is still affected. Then also look at
   stage 1, which master builds for the host as well when cross compiling (`isHostStage`,
   `hadrian/src/Oracles/Setting.hs:238-250`).

A real master build through a `ghcSrc` override would be stronger. It's much more work, though,
and isn't needed while the check above shows no relevant change since the snapshot.

## Where the fix goes

- **If master is unaffected (expected):** master needs nothing, and the fix goes to the release
  branches: `ghc-10.0`, `ghc-9.14`, and `ghc-9.12` if it still gets releases.
  - GHC's normal route is master first, then backports (skill section 8). Here master is fixed
    by a big rework that won't be backported. So the MRs would target the release branches
    directly.
  - **Settle the route with the user**, and explain it in the issue.
  - Check that the patch applies with the skill's throwaway-index command. Branch each MR from its
    release branch, e.g.
    `git -C ~/ghc worktree add -b wip/hadrian-cross-stage0-libffi-10.0 ~/ghc-0002-10.0 origin/ghc-10.0`.
- **If master is affected after all:** a normal master MR with backports. Check first whether
  stage 1 needs the same condition.

## Duplicate check (2026-10-11)

- `plugin failed to claim`: nothing.
- `ffiLibraryDir`: only #26047 ("Hadrian should not hardcode values that would be better
  specified declaratively in .cabal files"), which is general.
- "libffi stage0": only unrelated hits.
- Older, closed and different: #16950 ("Hadrian using system libffi support results in bad gcc
  command") and #20579 ("--with-system-ffi hadrian build fails with missing ffi.h").
- **Redo it right before filing.** Also try `with-ffi-libraries` and "cross libffi".

## Design questions (for the user)

1. **The condition:** `orM [notStage0, expr (notM cross)]` keeps the directories for stage0 of a
   native build, where the target's libffi is also the host's. Fine as the minimal fix, or
   should stage0 never get them?
2. **The route:** release-branch MRs (expected), and which branches.

## To do

1. **Confirm the code reading** above on master, and rerun the snapshot check.
2. **The proof build**, after asking the user.
3. **Duplicate check** with the skill. Then **draft the issue** (`references/issue.md`) into
   `~/ghc-wasm-flake/drafts/ghc-issue-hadrian-cross-stage0-libffi.paste.md`:
   - **title:** e.g. "Cross builds link the stage1 compiler with the target's libffi";
   - **body:** the error, the cause, and the affected branches (9.12, 9.14, 10.0; master not
     since `23c9b6c392`, with the proof build as evidence);
   - start with the LLM disclosure.

   The user files it and tells you the number.
4. **Settle the design questions** with the user.
5. **Polish the commit(s)** (`references/commit.md`, then `scripts/ghc-lint-commit.py`):
   - a subject of at most 50 characters, e.g. `hadrian: no target libffi dirs for cross stage0`
     (47);
   - a compact body, `Fixes #N.`, then `Assisted-by: Claude Code (Claude Opus 5.5)` and
     `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`.
6. **Testing:** the nixpkgs builds of 9.12 and 9.14 with the patch are the full-build evidence.
   A 10.0 build is optional; ask before starting one.
7. **Changelog:** a build-system fix, so probably ~"no-changelog". Ask the user.
8. **Draft the MR description(s)** (`references/merge-request.md`):
   - start with the P3 disclosure;
   - say why master doesn't need it;
   - ask `@triagers` for the labels (~hadrian, and ~wasm so the wasm jobs run).
9. **Stop before pushing.** Remind the user to GPG-sign; they push and open the MRs.
10. **Report back.** If master turned out unaffected, nixpkgs can stop applying the patch for GHC
    ≥ 10.1; the test branch's change is exactly that. The main session updates the nixpkgs
    branch, so don't push it.
11. **After the issue or MR exists**, update the hadrian libffi row of the "Upstream tracker" in
    `~/ghc-wasm-flake/README.md`: its versions column says "HEAD unverified", which the build
    settles. Commit there with `Assisted-by: Claude Code (Claude Opus 5.5)` and
    `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`.

## Ground rules (the user's standing preferences)

- **Never push, comment or file anything** without the user's explicit go-ahead.
- **GPG:** the user signs commits by hand. Always remind them before any push or MR.
- **GHC's LLM policy:** disclosure at the top of issues and MRs, an `Assisted-by` line on every
  commit, short prose. Draft for the user to review and rework.
- **Ask before big downloads or long builds**, and avoid them entirely if the user mentions mobile
  data roaming.
- **Builds:** one architecture at a time. The Mac's Linux VM shares the Mac's cores, so don't
  overlap darwin and Linux builds there.
- **Shell (zsh) pitfalls:**
  - an unquoted `$var` isn't word-split;
  - `$ref:r…` is read as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status;
  - `git cherry-pick` has no `-q`.
