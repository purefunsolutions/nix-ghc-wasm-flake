_I used Claude Code (Claude Opus 5.5) to investigate this and to draft this report. I have reviewed and revised it and take responsibility for it._

`xxhash.c` doesn't compile for wasm32 with `-msimd128` when clang has its own `<arm_neon.h>`. Clang generates that header whenever it is built with the ARM or AArch64 target ([CMakeLists.txt](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.8/clang/lib/Headers/CMakeLists.txt#L452-L454)), so Xcode's clang and nixpkgs' clang, for example, have it. With Xcode's clang 21.0.0 (the `-D` flags only avoid needing a wasm libc):

```
$ clang --target=wasm32 -msimd128 -O2 -ffreestanding -DXXH_NO_STDLIB \
    -DXXH_memcpy=__builtin_memcpy -DXXH_memset=__builtin_memset -DXXH_memcmp=__builtin_memcmp \
    -c xxhash.c
In file included from xxhash.c:42:
In file included from ./xxhash.h:3879:
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/21/include/arm_neon.h:28:2: error: "<arm_neon.h> is intended only for ARM and AArch64 targets"
   28 | #error "<arm_neon.h> is intended only for ARM and AArch64 targets"
      |  ^
In file included from xxhash.c:42:
./xxhash.h:4132:9: error: unknown type name 'uint64x2_t'; did you mean 'uint64_t'?
[...]
fatal error: too many errors emitted, stopping now [-ferror-limit=]
20 errors generated.
```

nixpkgs' `pkgsCross.wasm32-wasip1` clang 21.1.8 with wasi-libc fails the same way with just `-msimd128`. `-DXXH_VECTOR=XXH_SCALAR` doesn't help: the `#error` remains. It compiles without `-msimd128`, or with `-DXXH_NO_XXH3`.

Since #825 (v0.8.2), both the intrinsics include ([xxhash.h#L3874-L3879](https://github.com/Cyan4973/xxHash/blob/680bf463fa1ca0461b9a7c2dab7556e1f54cf4cf/xxhash.h#L3874-L3879)) and the `XXH_VECTOR` auto-selection ([xxhash.h#L4005-L4013](https://github.com/Cyan4973/xxHash/blob/680bf463fa1ca0461b9a7c2dab7556e1f54cf4cf/xxhash.h#L4005-L4013)) take `defined(__wasm_simd128__) && XXH_HAS_INCLUDE(<arm_neon.h>)` to mean Emscripten's SIMDe `arm_neon.h`. Clang's own header stops with `#error` on anything but ARM and AArch64, and the include doesn't look at `XXH_VECTOR`. wasi-sdk doesn't hit this, because it builds clang with only the WebAssembly target ([wasi-sdk-toolchain.cmake](https://github.com/WebAssembly/wasi-sdk/blob/5a0bf653a1a06e1c18867567c5937006d3394a69/cmake/wasi-sdk-toolchain.cmake#L228)).

This breaks GHC's wasm RTS, which vendors xxHash and is compiled with `-msimd128`: https://gitlab.haskell.org/ghc/ghc/-/work_items/27931. haskell.nix works around it with `-DXXH_NO_XXH3` ([default.nix](https://github.com/input-output-hk/haskell.nix/blob/1dde0b46d3daa5bf0ff3ea6332d579a1943b4a0c/compiler/ghc/default.nix#L437)).

Proposed fix: auto-select NEON for WASM SIMD128 only on Emscripten, and on other wasm toolchains include `<arm_neon.h>` only when `XXH_VECTOR` is set to `XXH_NEON`. With it, the builds above take the scalar path and Emscripten's output doesn't change (details below). I'll send a PR.

<details>
<summary>Build matrix, before and after the proposed fix</summary>

Before is `dev` at 680bf46, after is the same plus the proposed patch.

```
wasip1-clang  nixpkgs pkgsCross.wasm32-wasip1 clang 21.1.8, wasi-libc 32
xcode-clang   Apple clang 21.0.0 (clang-2100.3.34.2), --target=wasm32 -ffreestanding -DXXH_NO_STDLIB
              -DXXH_memcpy=__builtin_memcpy -DXXH_memset=__builtin_memset -DXXH_memcmp=__builtin_memcmp
emcc          nixpkgs emscripten 6.0.9 (clang 22.1.8)
emcc+node     the ubuntu-wasm CI command, node 24.21.0:
              CC=emcc CPPFLAGS="<flags>" RUN_ENV=node NODE_JS=1 make clean check
wasip1+simde  wasip1-clang with -isystem <dir> holding only Emscripten's SIMDe arm_neon.h,
              plus -DSIMDE_FLOAT16_API=1 (clang 21 has no _Float16 on wasm32)

Each compile row is "<compiler> -O2 <flags> -c xxhash.c". XXH_VECTOR is read with -E -dM,
the arm_neon.h column says whether the header was included (-H), and #error is the one from
clang's arm_neon.h.

                                                | before                       | after
setup         flags                             | result XXH_VECTOR arm_neon.h | result XXH_VECTOR arm_neon.h
wasip1-clang  -                                 | ok     SCALAR     no         | ok     SCALAR     no
wasip1-clang  -msimd128                         | #error NEON       yes        | ok     SCALAR     no
wasip1-clang  -msimd128 -DXXH_VECTOR=XXH_SCALAR | #error SCALAR     yes        | ok     SCALAR     no
wasip1-clang  -msimd128 -DXXH_VECTOR=XXH_NEON   | #error NEON       yes        | #error NEON       yes
wasip1-clang  -msimd128 -DXXH_NO_XXH3           | ok     -          no         | ok     -          no
xcode-clang   -msimd128                         | #error NEON       yes        | ok     SCALAR     no
xcode-clang   -msimd128 -DXXH_VECTOR=XXH_SCALAR | #error SCALAR     yes        | ok     SCALAR     no
emcc          -                                 | ok     SCALAR     no         | ok     SCALAR     no
emcc          -msimd128                         | ok     NEON       yes        | ok     NEON       yes
emcc          -msimd128 -DXXH_VECTOR=XXH_NEON   | ok     NEON       yes        | ok     NEON       yes
emcc          -msimd128 -DXXH_VECTOR=XXH_SCALAR | ok     SCALAR     yes        | ok     SCALAR     yes
emcc+node     -msimd128                         | pass                         | pass
emcc+node     -DXXH_VECTOR=XXH_NEON -msimd128   | pass                         | pass
wasip1+simde  -msimd128                         | ok     NEON       yes        | ok     SCALAR     no
wasip1+simde  -msimd128 -DXXH_VECTOR=XXH_NEON   | ok     NEON       yes        | ok     NEON       yes
wasip1+simde  -msimd128 -DXXH_VECTOR=XXH_SCALAR | ok     SCALAR     yes        | ok     SCALAR     no
```

- The four emcc objects are byte-identical before and after. So are the wasip1+simde objects with an explicit `XXH_VECTOR`.
- After the patch, `-msimd128` and `-msimd128 -DXXH_VECTOR=XXH_SCALAR` give byte-identical objects, with both clangs.
- Native arm64 objects (NEON and scalar) and x86-64 objects (SSE2, AVX2, AVX-512 and scalar) from Xcode's clang are byte-identical before and after.

</details>
