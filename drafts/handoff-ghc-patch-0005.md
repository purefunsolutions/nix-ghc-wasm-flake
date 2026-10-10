# Hand-off: upstream GHC patch 0005 (RTS static library dirs)

Written 2026-10-10 at the end of the ghc-wasm-flake session, for a new session in `~/ghc`. That
session won't see the previous session's memory, so this file is meant to be self-contained.

## Goal

Polish GHC patch 0005, "rts: don't restrict the RTS's static library dirs to libffi's", into a
merge request against `ghc/ghc` master, with a backport request for `ghc-10.0`. Prepare
everything locally. **The user pushes and opens the MR, after GPG-signing the commits by hand**
(see "Ground rules").

## Where things are

- `~/ghc`: full GHC clone with submodules. Branch **`wip/rts-static-lib-dirs`** is
  `origin/master` (`e7cacf59b8`, 2026-10-09) plus the patch commit `097449f66a` (author Mika
  Tammi). The other `wip/*` branches hold patches 0001–0004 (wasm-related) and are out of scope.
- The same patch as a file:
  `~/ghc-wasm-flake/upstream/ghc/0005-rts-don-t-restrict-the-RTS-s-static-library-dirs-to-libffi-s.patch`.
  It's byte-identical to nixpkgs' copy `pkgs/development/compilers/ghc/ghc-10-rts-static-lib-dirs.patch`
  in `~/nixpkgs-ghcwasm.git`, branch `ghcwasmhacking` (public at
  github.com/mikatammi/nixpkgs). There, nixpkgs commit `029b3ffff911` applies it to GHC ≥ 9.15.
- Project docs: `~/ghc-wasm-flake` (branch `initial`): `results/notes.md` (findings, in
  chronological order), `docs/upstream-check.md`, `STATUS.md`. Put drafts in
  `~/ghc-wasm-flake/drafts/`.

## The change

Delete one line from `rts/rts.buildinfo.in`:

```
-extra-lib-dirs-static: @FFILibDir@
```

## Root cause and evidence

- GHC `1ac1a541` ("Support statically linking executables properly", #26434 / !14935) added
  static-linking fields to `rts.buildinfo.in`. GHC `0f53ccc6` ("Use libffi-clib", January 2026)
  turned them into `extra-lib-dirs: @FFILibDir@` and `extra-lib-dirs-static: @FFILibDir@`.
- Cabal's `extraLibDirsStaticOrFallback` (`libraries/Cabal/Cabal/src/Distribution/Simple/Register.hs`,
  around line 579) uses `extra-lib-dirs` for `library-dirs-static` when no static dirs are given.
  When configure gets `--with-ffi-libraries`, the static list is non-empty, so that fallback no
  longer happens. The directories hadrian passes with `--extra-lib-dirs`
  (`cabalExtraDirs`, `hadrian/src/Settings/Packages.hs` around lines 424 and 459: libnuma, libdw,
  libzstd) then go missing from the RTS's `library-dirs-static`.
- **Symptom** (nixpkgs' native GHC HEAD 10.1.20260810, the same derivation Hydra builds): even
  hello world fails to link outside the nix build environment.
  - x86_64-linux: `ld.gold: error: cannot find -lelf`, `-ldw`, `-lnuma`.
  - aarch64-linux: `-lnuma` only, since the RTS there has no libdw support.

  In `rts-1.0.3.conf`, `library-dirs` lists numactl and elfutils, but `library-dirs-static`
  lists only libffi. Cross builds fail as well, because `Setup.hs` gets linked for the build
  platform without those paths.
- **GHC 9.14.1 is fine**: its `library-dirs-static` has elfutils and numactl, and hello world links.
- **The fix is verified in nixpkgs** (on the 10.1.20260810 snapshot):
  - the rebuilt native GHC HEAD lists libffi, elfutils and numactl in `library-dirs-static`;
  - hello world links and runs, with and without `-threaded`;
  - the full wasm HEAD pipelines pass on x86_64-linux and aarch64-linux.
- **Scope:** `master` and `ghc-10.0` both have the regression (10.0.1-alpha1 is already
  tagged), and the patch applies cleanly to both. `ghc-9.14` and `ghc-9.12` don't have it.
- **Why upstream hasn't seen it:** it needs both `--with-ffi-libraries` and libnuma or libdw
  outside the linker's default search path. That happens with non-FHS layouts such as Nix and
  probably Guix. GHC's CI and bindists don't pass that flag, and FHS distributions don't need
  it. GHC 10 isn't released yet either.
- **No existing issue or MR** (searched 2026-10-10). Related items:
  - #26914 (closed): in ghc.nix, `mostly_static` failed with `cannot find -l:libnuma.a` and the
    test was disabled. That test asks for static `libnuma.a`, so it's not the same bug, but it's
    related.
  - #26434 / !14935: the origin of the static fields.
  - #20759 (open): wire up `library-dirs-static`.
  - #27663 (open): the derivation of `EXTRA_LIBS` in the same file. Adjacent, not a duplicate.

## To do

1. `git fetch`, and check that `rts/rts.buildinfo.in` hasn't changed on master since `0f53ccc6`.
   If it has, rebase `wip/rts-static-lib-dirs`.
2. Read GHC's conventions: `.gitlab/merge_request_templates/Default.md` (it asks for a
   `changelog.d/` entry for user-facing changes, or the `no-changelog` label; see the
   [changelog guide](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/changelog)),
   `HACKING.md`, and the commit style of recent `rts:` commits. Decide whether to file an issue
   first (GHC often has "Fixes #NNNN" in the commit). Probably yes, and the MR references it.
3. Polish the commit message. It currently ends with
   `Assisted-by: Claude Code (claude-opus-5-5)`. **Ask the user which trailer format to use for
   GHC**: the nixpkgs one above, or ghc-wasm-flake's `Assisted-by: Claude Code (Claude Opus 5.5)`
   plus `Signed-off-by`. GHC has no in-repo AI policy, but the user discloses AI assistance
   everywhere.
4. Test on current master. The bug only shows with `--with-ffi-libraries` and libnuma/libdw
   outside the default path, so test in a Nix-based setup:
   - **ghc.nix** (it passes libffi and numactl from the store) or a nix shell, building with
     hadrian. Compare `library-dirs-static` in `_build/stage1/lib/package.conf.d/rts-*.conf`
     with and without the patch, then link hello world outside the shell environment.
   - Or **through nixpkgs**: override `haskell.compiler.ghcHEAD`'s `ghcSrc` with this branch.
     Change the source via `ghcSrc` (`.override`), never via `overrideAttrs` patches: hadrian is
     a separate derivation built from `ghcSrc`, and patching only the compiler breaks the build
     whenever a change touches hadrian. A working example is `/tmp/ghcwasm-scratch/mr16790/default.nix`.
   - Use Linux; macOS has no libnuma or libdw. The NUC (`ssh 10.1.0.17`, x86_64-linux, 8 cores)
     suits this. Run builds there detached (`setsid nohup … &`) and keep logs.
   - Optionally consider a regression test (e.g. checking the RTS package's static library
     dirs). Reviewers may ask.
5. Draft the issue text and the MR description into `~/ghc-wasm-flake/drafts/`:
   reproduction, root cause, fix, the `ghc-10.0` backport request, related issues, and an AI
   disclosure line.
6. Stop before pushing: remind the user to GPG-sign, then let them push to their fork on
   gitlab.haskell.org and open the MR.

## Ground rules (the user's standing preferences)

- **Never push or post anything** (GitLab, GitHub, Matrix) without the user's explicit go-ahead.
  Prepare drafts instead.
- **GPG:** the user signs commits by hand. Always remind them to sign before any push or MR.
- **AI disclosure** on every commit and on MR and issue texts.
- **Commit messages**, in nixpkgs style: a compact subject, and only sometimes a short
  explanation.
- **Downloads:** ask before big ones if the user says they're on mobile data roaming. They
  weren't when this was written.
- **Shell (zsh) pitfalls** seen in this project:
  - an unquoted `$var` is not word-split;
  - `$ref:r…` gets parsed as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status;
  - `git cherry-pick` has no `-q`.
- **Machines:**
  - the Mac (aarch64-darwin, 16 cores);
  - a Linux VM used as a nix remote builder. It shares the Mac's cores, so run one Linux build
    at a time;
  - the NUC.

## Loose ends from the previous session

- A verification build of the JS backend's GHC HEAD (`pkgsCross.ghcjs.haskell.packages.ghcHEAD.hello`,
  testing the widened haddock workaround in nixpkgs) was running on the NUC. Its log is
  `~/ghcwasm/results/logs/x86_64-linux-js-ghcHEAD.log` there, and it ends with `exit=<code>`.
- `~/ghc-wasm-flake` branch `initial` has unsigned commits waiting for the user's GPG signature.
  `TODO.md` there is a temporary backlog, to be dropped before merging `initial`.
