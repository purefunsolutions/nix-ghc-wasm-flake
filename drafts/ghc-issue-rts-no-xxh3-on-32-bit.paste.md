_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this report. I have carefully reviewed and revised it and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

## Summary

The wasm RTS doesn't compile with `-msimd128` (part of ghc-wasm-meta's recommended `CONF_CC_OPTS_STAGE2`) if clang ships its own `<arm_neon.h>`, as it does when built with the ARM or AArch64 target. nixpkgs' clang is one example.

Since b19ec331a4 (xxHash 0.8.2, GHC 9.10.1), `rts/xxhash.h` includes `<arm_neon.h>` whenever `__wasm_simd128__` is defined and `__has_include(<arm_neon.h>)` is true (`rts/xxhash.h:3850-3852`). It expects SIMDe's NEON emulation, which Emscripten provides ([xxHash#825](https://github.com/Cyan4973/xxHash/pull/825)). Clang's own `arm_neon.h` stops with an `#error` on targets other than ARM and AArch64. xxHash 0.8.4 (!16708) has the same check. I've reported this upstream as [xxHash#1165](https://github.com/Cyan4973/xxHash/issues/1165).

That code belongs to XXH3, which the RTS doesn't use on 32-bit platforms: `hashBuffer` calls `XXH3_64bits_withSeed` only when `WORD_SIZE_IN_BITS == 64`, and `XXH32` otherwise (`rts/Hash.c:88-92`).

GHC's CI doesn't hit this: wasi-sdk builds clang with only the WebAssembly target ([wasi-sdk-toolchain.cmake](https://gitlab.haskell.org/haskell-wasm/wasi-sdk/-/blob/881f679eed49fad24fe56609c1fea54f97580b37/cmake/wasi-sdk-toolchain.cmake#L89)), and clang only generates `arm_neon.h` when the ARM or AArch64 target is built ([clang/lib/Headers/CMakeLists.txt](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.8/clang/lib/Headers/CMakeLists.txt#L452-L454)). haskell.nix builds its wasm GHC with `-optc-DXXH_NO_XXH3` ([compiler/ghc/default.nix](https://github.com/input-output-hk/haskell.nix/blob/1dde0b46d3daa5bf0ff3ea6332d579a1943b4a0c/compiler/ghc/default.nix#L437)).

## Steps to reproduce

Compile `rts/Hash.c` from master with clang 21.1.8 and wasi-libc 32 (here nixpkgs' `pkgsCross.wasm32-wasip1` toolchain), ghc-wasm-meta's `CONF_CC_OPTS_STAGE2`, the RTS's include paths and `-DCOMPILING_RTS`:

```
$ wasm32-unknown-wasip1-cc -Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128 \
    -DCOMPILING_RTS -DFS_NAMESPACE=rts -Irts -Irts/include \
    -idirafter <rts include dir of an installed wasm GHC> -fsyntax-only rts/Hash.c
In file included from rts/Hash.c:19:
In file included from rts/xxhash.h:3852:
/nix/store/…-wasm32-unknown-wasip1-clang-wrapper-21.1.8/resource-root/include/arm_neon.h:28:2: error: "<arm_neon.h> is intended only for ARM and AArch64 targets"
   28 | #error "<arm_neon.h> is intended only for ARM and AArch64 targets"
      |  ^
In file included from rts/Hash.c:19:
rts/xxhash.h:4090:9: error: unknown type name 'uint64x2_t'; did you mean 'uint64_t'?
[...]
20 errors generated.
```

Without `-msimd128`, or with `-DXXH_NO_XXH3`, it compiles. A full build of nixpkgs' wasm GHC from the ghc-9.12 branch stops at the same `#error`.

## Expected behavior

The wasm RTS compiles with `-msimd128`, whether or not clang has ARM targets.

## Environment

* GHC version used: master (e7cacf59b8), and the ghc-9.12 branch. ghc-10.0 and ghc-9.14 have the same code.
* Operating System: macOS 26.7.1 and Linux hosts, wasm32-wasi target. The error comes from clang's headers, so the host doesn't matter.
* System Architecture: aarch64 hosts

I'll open an MR that defines `XXH_NO_XXH3` in `rts/Hash.c` when the word size isn't 64 bits. Since ghc-10.0, ghc-9.14 and ghc-9.12 have the same code, I'd like it backported to all three.

cc @TerrorJack

/label ~"T::bug"
/label ~"needs triage"
/label ~wasm
