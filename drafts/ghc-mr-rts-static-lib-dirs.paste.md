_LLM assistance: Claude Code (Claude Opus 5.5) was used while preparing this contribution: for the investigation, the testing, and drafts of the commit message and this description. I have carefully reviewed and revised the submitted material and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

Fixes #27926.

## Changes contained in this patch

The only change is one deleted line in `rts/rts.buildinfo.in`: `extra-lib-dirs-static: @FFILibDir@`.

### Problem

Since 0f53ccc6 ("Use libffi-clib"), `rts/rts.buildinfo.in` sets `extra-lib-dirs-static: @FFILibDir@`. With `--with-system-libffi --with-ffi-libraries`, this stops Cabal from falling back to `extra-lib-dirs` for the RTS's `library-dirs-static`, so the libnuma, libdw and libzstd dirs that hadrian passes go missing from it. Since 1ac1a541, GHC uses `library-dirs-static` when linking without `-dynamic`, so linking executables fails unless those libraries are on the default search path. On macOS, with the wiki's configure line plus IPE compression, even the GHC build fails. See #27926 for details and reproducers.

### Fix

Without the field, the static library dirs fall back to `extra-lib-dirs` again, which `ghc-internal.buildinfo.in` already relies on. libffi's directory stays in all three fields, so linking against a system libffi works as before, statically or not. That's because `extra-lib-dirs: @FFILibDir@` stays: it's how libffi's directory gets into the RTS's package entry at all, and dropping it as well gives `cannot find -lffi`.

Library dirs differ from libraries here. Cabal registers `extra-libraries-static` exactly as given, so the static libraries have to be spelled out, and `rts.cabal` does that. For library dirs, Cabal falls back to `extra-lib-dirs` when no static dirs are given, and setting `extra-lib-dirs-static` switches that fallback off.

### Alternative considered

Hadrian's `cabalExtraDirs` could pass `--extra-lib-dirs-static` as well. But that makes the static list explicit for every package it serves (the compiler, ghci, terminfo, ghc-internal and the RTS), which switches Cabal's fallback off for all of them. Each `extra-lib-dirs` in their `.buildinfo` files would then have to be repeated as `extra-lib-dirs-static`. Otherwise, for example, ghc-internal's iconv dirs would drop out of its static list. `extra-lib-dirs-static` is for static archives that live in other directories than the shared libraries. GHC's configure has only one directory per library, so the RTS has nothing to put there, and leaving the field unset is the right encoding.

Nothing changes for GHC's CI. `FFILibDir` is empty in every job except FreeBSD 14 (`--with-ffi-libraries=/usr/local/lib`). There, the RTS has no other extra library dirs, so `library-dirs-static` stays the RTS's own dir plus `/usr/local/lib`.

### Testing

x86_64-linux, master e7cacf59b8, configured like nixpkgs' GHC HEAD (`--with-system-libffi --with-ffi-libraries=…`, `--enable-numa`, `--enable-dwarf-unwind`, with the libraries in the Nix store), `--flavour=quick+no_dynamic_libs+no_dynamic_ghc`. Each variant was built in a fresh build root, and hello world was linked from a clean environment (`env -i`):

- Without the patch, `library-dirs-static` has only the RTS's own dir and libffi's, and linking fails as shown in #27926.
- With the patch, `library-dirs-static` equals `library-dirs` (the RTS's dir, libffi, elfutils, numactl) in both the installed and the in-place package DB. Hello world links and runs, with and without `-threaded`.

The same on aarch64-darwin (macOS 26.7, Xcode 27.0), configured with the wiki's `--with-ffi-libraries=$sdk_path/usr/lib` plus `--enable-ipe-data-compression` and a libzstd outside the default search path:

- Without the patch, the build fails when linking `_build/stage1/bin/hpc`, with `ld: library 'zstd' not found`.
- With the patch, the build completes, `library-dirs-static` equals `library-dirs` (the RTS's dir, the SDK's `usr/lib`, zstd), and hello world links and runs, with and without `-threaded`.

I've also used the patch in nixpkgs on top of GHC HEAD 10.1.20260810:

- The installed native compiler links and runs hello world from a clean environment as static, `-threaded`, `-dynamic` and `-dynamic -threaded` executables (x86_64-linux).
- With this change, the wasm cross pipeline passes on x86_64-linux, aarch64-linux and aarch64-darwin: the wasm compiler, plus a pure, a C-FFI and a Template Haskell hello world, each run under wasmtime. So does the JavaScript cross build of hello on x86_64-linux. On Linux, these builds link each package's `Setup.hs` with the patched native compiler, which failed before with `cannot find -lnuma`.

To test it yourself, use a fresh build root. In an existing build tree hadrian doesn't pick up this change: it caches the RTS's package description and doesn't track the generated `rts.buildinfo`, so `library-dirs-static` keeps its old value.

## MR Checklist

- [x] This MR solves the problem described in the following issue: #27926
- [ ] A changelog entry was added in `changelog.d/` for user-facing changes (see [changelog guide][changelog]).
      If this MR does not need a changelog entry, the ~"no-changelog" label was applied.
      _No entry: no release has this bug if the fix reaches ghc-10.0 before 10.0.1 (otherwise I'll add one). I can't apply the label myself; see the request below._
- [x] This MR does not make any significant changes to `base`, or it has an accompanying [CLC proposal](https://github.com/haskell/core-libraries-committee#base-package).
- [x] If this MR has the potential to break user programs, the ~"user-facing" label was applied to
      test against head.hackage.
      _Not applicable: it only changes the RTS's registered `library-dirs-static`, and only for builds with `--with-ffi-libraries`._
- [x] All commits are either individually buildable or squashed.
      _One commit._
- [ ] After all approvals and before landing: all fixup commits are squashed with their originating commits.
- [x] Commit messages describe *what they do*, referring to tickets using `#NNNNN` syntax.
- [x] Source comments describing the change were added. For larger changes [notes][notes] and
      cross-references from the relevant places were added (as applicable).
      _Not applicable to a one-line deletion; the commit message and #27926 explain it._
- [ ] [Testcases to the testsuite][adding test] were added (as applicable).
      _None: CI can't trigger this. Its only jobs with `--with-ffi-libraries` (FreeBSD 14) have no libnuma, libdw or libzstd, so a test comparing the RTS's `library-dirs-static` with `library-dirs` would pass there with or without the fix._
- [x] The users guide was updated (as applicable).
      _Not applicable._

Backport: ghc-10.0 has the same bug, including 10.0.1-alpha1, and the patch applies cleanly there. 9.14 and 9.12 aren't affected.

@triagers: could you please add ~"no-changelog" and ~"backport needed:10.0"? I can't set labels myself.

[notes]: https://gitlab.haskell.org/ghc/ghc/wikis/commentary/coding-style#comments-in-the-source-code
[adding test]: https://gitlab.haskell.org/ghc/ghc/wikis/building/running-tests/adding
[changelog]: https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/changelog
