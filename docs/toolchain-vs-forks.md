# The stock toolchain vs. GHC's wasm forks

Cheng Shao asked at MuniHac 2026 how the toolchain our nixpkgs builds use differs from the
haskell-wasm forks that GHC's CI uses. Checked 2026-10-11 against ghc-wasm-meta master
(`e56b33ce`) and the fork repositories on gitlab.haskell.org. Older background is in
`research.md` §1.2 and §3a.

## Versions

| | ghc-wasm-meta (GHC's CI) | nixpkgs `ghcwasmhacking` (`b708887`) |
|---|---|---|
| Packaging | haskell-wasm wasi-sdk: upstream `wasi-sdk-29` + 14 build commits, built 2025-12-19 | no wasi-sdk; nixpkgs builds each piece |
| LLVM (clang, wasm-ld) | fork `release/21.x`: upstream as of 2025-12-12 (21.1.8) + 4 patches; built for WebAssembly only | stock 21.1.8, all targets |
| compiler-rt, libc++ | from the same wasi-sdk build | stock 21.1.8 for `wasm32-unknown-wasip1`; libc++ without exceptions, threads or filesystem |
| wasi-libc | fork `master`: upstream of 2025-12-13 + 9 patches | upstream tag `wasi-sdk-32`, default flags; its only patch relaxes the wit-bindgen/wkg version checks |
| Target triple | `wasm32-wasi` | `wasm32-unknown-wasip1` |
| libffi-wasm | CI artifact from 2025-03-10 | tag `20260905` (MIT), plus `libffi.so` for TH |
| node (TH, GHCi) | static 26.11.1 | 24.21.0 |
| wasmtime | haskell-wasm wasm-tools-static `260922` | 49.0.2 |

GHC itself is built with the same flags (upstream's `CONF_CC_OPTS` etc.: `-O3 -mcpu=lime1
-mreference-types -msimd128`, `--keep-section=ghc_wasm_jsffi`, `--stack-first`). The flavour
differs: CI adds `+text_simdutf` and `+host_fully_static`, nixpkgs uses neither.

**The forks' next toolchain** is in progress, not pinned yet:
- wasi-sdk `rebase/llvm23-main`: upstream wasi-sdk 34-rc.3, plus a revert of #637 so `wasm32-wasi`
  keeps working, plus the same build commits;
- LLVM `ghc/release-23.x`, which adds identical code folding to wasm-ld;
- wasi-libc `ghc/main`, which adds UTF-8-only iconv.

## Fork patches the stock toolchain doesn't have

**LLVM** (4):
- `a4a2f322` wasm-ld splits up `__wasm_apply_data_relocs` (llvm#129007, still open). This is
  **the one that matters**. Without it, a very large TH `.so` can exceed V8's function-size
  limit (about 7.65 MB). Our TH tests only load small libraries, so this is untested.
- `e0077c3e` clang runs wasm-opt only for `.so` files, and only with `WASM_SO_OPT`. Stock clang
  runs `wasm-opt` after any optimised link if it finds one in `PATH`. nixpkgs builds have no
  binaryen in `PATH`, so nothing changes there; a user shell with binaryen would differ
  (`--no-wasm-opt` turns it off).
- `abacb164` makes ".size directive ignored for function symbols" an error instead of a warning.
  Diagnostics only.
- `06108a28` reverts an LLVM CMake rpath change. This only affects packaging the toolchain;
  nixpkgs sets rpaths itself.

**wasi-libc** (9):
- `bdc1653b` makes `isatty` always return 0. Stock wasi-libc asks the runtime, so under a
  terminal a program sees a TTY: stdout is line-buffered, and code that checks for a terminal
  (echo control, haskeline) takes its terminal path. **Untested.**
- `dc7c1503`, `f9b395bf`: bulk-memory `memcpy`/`memmove`/`memset`. Performance.
- `845e1c18`, `a573a84e`, `36f81780`: dlmalloc tunings for GHC (`INSECURE`,
  `MORECORE_CONTIGUOUS=0`, no hard-wired `MALLOC_ALIGNMENT`), plus `malloc_inspect_all` for the
  wizer recipe. The RTS has called `sbrk` itself since GHC `558353f4`, and stock dlmalloc
  tolerates that (wasi-libc#334). It works in our tests.
- `42acaa42`, `5108e0b1`, `951e93b3`: build flags (`-O3 -mcpu=lime1 -mreference-types -msimd128
  -D__wasilibc_simd_string`), `libc.so` linked with `--Bsymbolic`, and an LTO fix. Performance
  only. Our wasi-libc uses its default flags.

**wasi-sdk** (14): all build changes:
- Release builds, no ccache, no wasm-component-ld, LTO off by default;
- llc and opt shipped;
- the recommended flags for the sysroot, wasi-libc's `CHECK_SYMBOLS`, and flags for the shared
  libc++;
- `LLVM_TARGETS_TO_BUILD=WebAssembly`, which matters (see below).

## What the differences cost GHC

With the stock toolchain, three things needed GHC patches. GHC's CI doesn't hit them because it
uses the forks.

1. **The triple.** nixpkgs uses `wasm32-unknown-wasip1`, and GHC's configure only accepts the OS
   `wasi`. nixpkgs' clang also looks for compiler-rt under `lib/wasm32-unknown-wasip1/`, so GHC has
   to pass the wasip1 triple on to clang. Fixed by !16795 (#27930).
   - Upstream is moving the same way: wasi-sdk 34 removes `wasm32-wasi` (#637), and clang's
     default became `wasm32-wasip1` (#600). The fork reverts the removal.
2. **wasi-libc ≥ 32** no longer pulls in `<wasi/api.h>` through other headers, so
   `rts/wasm/JSFFI.c` doesn't compile. Fixed by !16794 (#27929).
   - The forks' next wasi-libc (`ghc/main`) already has upstream's `wasi/wasip1.h` split, so it
     will most likely need this too.
3. **A clang built with ARM targets** ships `arm_neon.h`. xxhash's wasm SIMD path includes that
   header and fails, which is our patch 0004 (no XXH3 on 32-bit).
   - wasi-sdk's clang is built for WebAssembly only, and clang generates `arm_neon.h` only for
     ARM/AArch64 targets (`clang/lib/Headers/CMakeLists.txt:452` in 21.1.8). So the fork can't
     hit this.

The other upstream items (hadrian's stage0 libffi, the GHC 10 static library dirs, darwin host
settings, the haddock failure) aren't about the toolchain.

## Coverage so far

- **Works** for GHC 9.12, 9.14 and HEAD on aarch64-darwin, aarch64-linux and x86_64-linux:
  - the compiler builds;
  - hello world runs under wasmtime, with C FFI, a libffi `"wrapper"` callback and native bignum;
  - Template Haskell, through `dyld.mjs` under node;
  - the GHCi debugger, the eventlog and `-hT`, and cost-centre profiling.
- **Not tested:**
  - GHC's testsuite;
  - big programs and large TH libraries (the `__wasm_apply_data_relocs` limit);
  - terminal programs (`isatty`);
  - browser and JSFFI apps;
  - performance against the forks.

## Questions for Cheng

1. Why does `isatty` always return 0: a runtime bug, buffering, or something else?
2. What's blocking llvm#129007 upstream?
3. Would GHC's CI take one job with a stock toolchain (upstream wasi-sdk plus !16795)? It would
   have caught all three issues above.
