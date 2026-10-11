Title: Cross builds pass the target's libffi dirs to stage0 ghci

_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this report. I have carefully reviewed and revised it and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

## Summary

configure's `--with-ffi-includes` and `--with-ffi-libraries` describe the target's libffi. Since b2721819f3, hadrian passes them to the `ghci` package at every stage (`builder (Cabal Setup) ? cabalExtraDirs ffiIncludeDir ffiLibraryDir` in `hadrian/src/Settings/Packages.hs`). In a cross build, stage0 `ghci` is built for the build platform, and its registration puts the target's libffi on the stage1 compiler's link line.

With a wasm32-wasi target and libffi-wasm, gold takes the wasm `libffi.a` for the bootstrap RTS's `-lffi` and fails. ELF cross builds may get away with it, because the linker can skip an incompatible archive (not tested). #21932 (loongarch64, 9.2.3) looks like the header side of the same bug: stage0 `ghci`'s `GHCi/FFI.hsc` gets compiled against the target's `ffitarget.h`.

Master doesn't have the bug since 23c9b6c392: in a cross build, stages 0 and 1 take these settings from `hadrian/cfg/system.config.host`, which leaves them empty. Without the fix, nixpkgs' wasm GHC HEAD (556db2f32f) builds on x86_64-linux, and its hello test passes under wasmtime. ghc-10.0, ghc-9.14 and ghc-9.12 still have the bug.

## Steps to reproduce

Build 9.14.1 for wasm32-wasi on x86_64-linux, with GHC 9.10.3 (built with system libffi) as the bootstrap compiler and libffi-wasm as the target's libffi. I used the nixpkgs recipe on my branch ([common-hadrian.nix](https://github.com/mikatammi/nixpkgs/blob/b708887d8ad1/pkgs/development/compilers/ghc/common-hadrian.nix)) without its patch for this issue. The relevant configure flags:

```
--target=wasm32-unknown-wasip1 --with-system-libffi
--with-ffi-includes=/nix/store/…-libffi-wasm-static-wasm32-unknown-wasip1-20260905-dev/include
--with-ffi-libraries=/nix/store/…-libffi-wasm-static-wasm32-unknown-wasip1-20260905/lib
```

(`wasip1` needs !16795; the libffi dirs don't depend on the triple.) `hadrian binary-dist-dir` then fails to link the stage1 compiler:

```
| Run Ghc LinkHs (Stage0 InTreeLibs): _build/stage0/ghc/build/Main.o (and 9 more) => _build/stage0/bin/wasm32-unknown-wasip1-ghc
…/binutils-2.46/bin/ld.gold: error: ffi: plugin failed to claim member ffi.o at 386
…/binutils-2.46/bin/ld.gold: error: ffi: plugin failed to claim member ffi_call.o at 1156
_build/stage0/lib/../lib/x86_64-linux-ghc-9.10.3-b0b4/ghci-9.14.1-83ae/libHSghci-9.14.1-83ae.a(FFI.o):function ghcizm9zi14zi1zm83ae_GHCiziFFI_zdwffiType_info:(.text+0xe6): error: undefined reference to 'ffi_type_sint16'
[… more undefined ffi_* references from ghci's FFI.o and the bootstrap RTS …]
collect2: error: ld returned 1 exit status
```

`ffi.o` and `ffi_call.o` are members of libffi-wasm's `libffi.a`. The same link command also has `-I/nix/store/…-libffi-wasm-static-wasm32-unknown-wasip1-20260905-dev/include`.

## Expected behavior

The stage1 compiler links. As on master, stage0 packages of a cross build don't get the target's libffi dirs.

## Environment

* GHC version used: 9.14.1; ghc-9.12 and ghc-10.0 have the same code
* Operating System: Linux build platform (nixpkgs), wasm32-wasi target
* System Architecture: x86_64

I'll open MRs against ghc-10.0, ghc-9.14 and ghc-9.12 that leave the libffi dirs out for stage0 of a cross build. Master doesn't need the change, so they target the release branches directly.

/label ~"T::bug"
/label ~"needs triage"
/label ~hadrian
