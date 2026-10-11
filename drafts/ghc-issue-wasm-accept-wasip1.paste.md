_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this report. I have carefully reviewed and revised it and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

## Summary

`./configure --target=wasm32-unknown-wasip1` stops with `Unknown OS wasip1`. `GHC_CONVERT_OS` (`m4/ghc_convert_os.m4`) and ghc-toolchain's `parseOs` only accept `wasi` as the OS of a WASI target.

`wasip1` is now the usual name for WASI preview 1:

- LLVM 22 renamed the `wasm32-wasi` target to `wasm32-wasip1`, and clang warns about `--target=wasm32-wasi` (llvm/llvm-project#165345).
- wasi-sdk 34 removed its `wasm32-wasi` targets; they're now named `wasm32-wasip1` (WebAssembly/wasi-sdk#637).
- nixpkgs' WASI toolchain is `wasm32-unknown-wasip1` (`pkgsCross.wasm32-wasip1`).

GHC's CI configures for `wasm32-wasi`, so it doesn't hit this.

## Steps to reproduce

On master (e7cacf59b8), with a bootstrap GHC and no other flags. configure stops while parsing the target, before it looks for a toolchain:

```
$ ./boot
$ ./configure --target=wasm32-unknown-wasip1 GHC=/nix/store/…-ghc-9.10.3/bin/ghc
...
checking target system type... wasm32-unknown-wasip1
build platform inferred as: aarch64-apple-darwin
host platform inferred as: aarch64-apple-darwin
Unknown OS wasip1
```

With nixpkgs' `wasm32-unknown-wasip1` toolchain (clang 21.1.8, wasi-libc 32) and the flags nixpkgs uses for its wasm GHC, it stops at the same point.

## Expected behavior

configure accepts `wasm32-*-wasip1` like `wasm32-wasi` and configures a WASI cross compiler.

## Environment

* GHC version used: master (e7cacf59b8). ghc-10.0, ghc-9.14 and ghc-9.12 have the same code.
* Operating System: macOS 26.7.1 host, wasm32-wasip1 target. The error comes from configure's target parsing, so the host doesn't matter.
* System Architecture: aarch64 host

I'll open an MR that accepts `wasip1` as an alias of `wasi`. Since ghc-10.0, ghc-9.14 and ghc-9.12 have the same code, I'd like it backported to all three.

cc @TerrorJack

/label ~"T::bug"
/label ~"needs triage"
/label ~wasm
