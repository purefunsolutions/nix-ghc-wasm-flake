_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this report. I have carefully reviewed and revised it and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

## Summary

If GHC is configured with `--with-system-libffi --with-ffi-libraries=DIR`, the registered `rts` package has `DIR` in `library-dirs-static`, but not the directories hadrian passes for libnuma, libdw and libzstd: those end up only in `library-dirs`. GHC takes the `-L` flags for linking an executable without `-dynamic` from `library-dirs-static`, so even hello world fails to link unless these libraries are on the linker's default search path.

Cause: two changes from January 2026 combine.

- 1ac1a541 (!14935, #26434) made GHC take those `-L` flags from `library-dirs-static` instead of `library-dirs`.
- 0f53ccc6 ("Use libffi-clib", !14996) moved libffi's directory from hadrian's `--extra-lib-dirs` into `rts/rts.buildinfo.in`, including

  ```
  extra-lib-dirs-static: @FFILibDir@
  ```

  Cabal registers `extra-lib-dirs` as `library-dirs-static` only if no static library dirs are given (`extraLibDirsStaticOrFallback` in `Distribution.Simple.Register`). With `--with-ffi-libraries` the list isn't empty, so that fallback no longer happens.

This shows up with non-FHS layouts such as Nix, e.g. with nixpkgs' `haskell.compiler.ghcHEAD`. It also shows up on macOS with the configure line from the [wiki](https://gitlab.haskell.org/ghc/ghc/-/wikis/building/preparation/mac-osx) (`--with-ffi-libraries=$sdk_path/usr/lib`) plus `--enable-ipe-data-compression`, if libzstd is outside the linker's default search path. There, the GHC build itself fails (see below). GHC's CI doesn't hit it: its only jobs with `--with-ffi-libraries` (FreeBSD 14) build an RTS without libnuma, libdw or libzstd.

## Steps to reproduce

On x86_64-linux, configure master with libffi, libnuma and libdw outside the default search path (here from the Nix store; the run below also used nixpkgs' toolchain and its other configure flags), then build:

```
./configure --with-system-libffi \
    --with-ffi-includes=/nix/store/…-libffi-3.8.0-dev/include \
    --with-ffi-libraries=/nix/store/…-libffi-3.8.0/lib \
    --enable-numa \
    --with-libnuma-includes=/nix/store/…-numactl-2.0.18-dev/include \
    --with-libnuma-libraries=/nix/store/…-numactl-2.0.18/lib \
    --enable-dwarf-unwind \
    --with-libdw-includes=/nix/store/…-elfutils-0.195-dev/include \
    --with-libdw-libraries=/nix/store/…-elfutils-0.195/lib
hadrian/build -j --flavour=quick+no_dynamic_libs+no_dynamic_ghc --docs=none
```

The registered RTS (`_build/stage1/lib/package.conf.d/rts-1.0.3.conf`, store hashes shortened) then has:

```
library-dirs:
    ${pkgroot}/../lib/x86_64-linux-ghc-10.1.20261010/rts-1.0.3
    /nix/store/…-libffi-3.8.0/lib
    /nix/store/…-elfutils-0.195/lib
    /nix/store/…-numactl-2.0.18/lib

library-dirs-static:
    ${pkgroot}/../lib/x86_64-linux-ghc-10.1.20261010/rts-1.0.3
    /nix/store/…-libffi-3.8.0/lib
```

Linking hello world from a clean environment (`env -i`, so nothing like Nix's `NIX_LDFLAGS` adds the missing directories) then fails, with or without `-threaded`:

```
$ _build/stage1/bin/ghc Hello.hs
[1 of 2] Compiling Main             ( Hello.hs, Hello.o )
[2 of 2] Linking Hello
/nix/store/…-binutils-2.46/bin/ld.gold: error: cannot find -lelf
/nix/store/…-binutils-2.46/bin/ld.gold: error: cannot find -ldw
/nix/store/…-binutils-2.46/bin/ld.gold: error: cannot find -lnuma
[35 undefined references to dwfl_*, numa_* and mbind]
collect2: error: ld returned 1 exit status
<no location info>: error:
    `cc' failed in phase `Linker'. (Exit code: 1)
```

Inside Nix builds, the build environment adds these directories, which hides the problem. In nixpkgs, cross builds fail too: they link each package's `Setup.hs` with the native GHC HEAD, without these directories.

On aarch64-darwin (macOS 26.7, Xcode 27.0's clang and ld), the wiki's configure line plus IPE compression fails during the build itself:

```
./configure --with-system-libffi --with-intree-gmp \
    --with-ffi-libraries=$sdk_path/usr/lib --with-ffi-includes=$sdk_path/usr/include/ffi \
    --enable-ipe-data-compression \
    --with-libzstd-includes=/nix/store/…-zstd-1.5.7-dev/include \
    --with-libzstd-libraries=/nix/store/…-zstd-1.5.7/lib
```

(I also passed `--with-curses-*` for the stage0 `terminfo`, because my boot compiler came from Nix.) The RTS then has `library-dirs-static: ${pkgroot}/…/rts-1.0.3 $sdk_path/usr/lib`, without zstd's directory, and linking `_build/stage1/bin/hpc` fails:

```
| Run Ghc LinkHs Stage1: _build/stage1/utils/hpc/build/Main.o (and 17 more) => _build/stage1/bin/hpc
ld: library 'zstd' not found
clang: error: linker command failed with exit code 1 (use -v to see invocation)
`gcc' failed in phase `Linker'. (Exit code: 1)
```

## Expected behavior

`library-dirs-static` lists the same directories as `library-dirs`, as with GHC 9.14, and executables link.

## Environment

* GHC version used: master (e7cacf59b8). ghc-10.0 is affected too, including 10.0.1-alpha1; 9.14 and 9.12 aren't.
* Operating System: Linux (NixOS / nixpkgs); macOS 26.7 (Xcode 27.0: Apple clang 21, ld-27037)
* System Architecture: x86_64 (Linux), aarch64 (macOS). On aarch64-linux, where nixpkgs builds the RTS without libdw, only `-lnuma` is missing.

I'll open an MR with a fix (drop the field). Since ghc-10.0 is affected, I'd like it backported there. Could a triager milestone this for 10.0.1?

Related: #26434 / !14935 (added the static fields), #20759.

cc @maerwald @alt-romes

/label ~"T::bug"
/label ~"needs triage"
