# Research: GHC's wasm backend in nixpkgs (state as of 2026-10-09)

Background research for reviving [NixOS/nixpkgs#225000]. Sources are linked inline.
Statements marked *(verified)* were checked directly against source or the binary cache.
Everything else comes from reading upstream repos, issues and PRs. This file is a snapshot;
current state lives in [`../STATUS.md`](../STATUS.md).

[NixOS/nixpkgs#225000]: https://github.com/NixOS/nixpkgs/pull/225000

## 1. The 2023 blockers, revisited

In July 2023 sternenseemann put #225000 on hold for four reasons. On 2026-10-05 he restated
the first two on [#561449](https://github.com/NixOS/nixpkgs/pull/561449): GHC's
wasm backend "uses a fork of wasi-sdk (which we don't) and requires a fork of LLVM (which we
also don't have) since GHC's assumptions about memory have to be accommodated".

| 2023 blocker | Status now | Evidence |
|---|---|---|
| RTS needs a patched wasi-libc (custom dlmalloc/sbrk alignment) | **Resolved** for GHC 9.10.2+, 9.12.1+, 9.14, 10.0 and master. Still present in 9.6, 9.8 and 9.10.1. | See 1.1 |
| GHC's forked wasi-sdk/LLVM (incl. mimalloc) | **Mostly optional.** Only one fork patch matters for correctness, and only for huge TH `.so` files. | See 1.2 |
| GHC itself needed patches (applied in CI) | **Resolved.** | hsc2hs#68 (merged 2023-01-05); process#240 → process#270 (merged 2023-01-09). Today's GHC CI wasm job applies no patches. |
| Custom libffi (libffi-wasm) | **Still required**, but easy to package. | See 1.3 |

### 1.1 RTS memory management (`rts/wasm/OSMem.c`)

- **2023:** the Note at [53ed21c5](https://gitlab.haskell.org/ghc/ghc/-/blob/53ed21c5d142961848f4b24fa8d5f45d500b9494/rts/wasm/OSMem.c)
  said: "We even patch dlmalloc in the libc sysroot shipped in our wasi-sdk release, so that
  whenever dlmalloc calls sbrk(), it extends the linear memory to align to the megablock size".
- **The change:** GHC commit `558353f4` (2024-06-12), "rts: use page sized mblocks on wasm …
  allows us to simplify our wasi-libc fork".
- **Now** (master, ghc-9.12, ghc-9.14): "we bypass dlmalloc, and directly call sbrk() to
  allocate megablocks". The code is `GHC_STATIC_ASSERT(MBLOCK_SIZE == PAGESIZE)` plus
  `return sbrk(PAGESIZE * n);`.
- **What it still relies on**, all present in **stock** wasi-libc:
  - `sbrk` hands out 64 KiB-aligned pages.
  - dlmalloc tolerates other callers of `sbrk` (wasi-libc#334).
  - `__heap_end` exists.
- **Caveat:** GHC's CI only tests with the fork. Stock wasi-libc is untested upstream; this
  project is that test.

### 1.2 The haskell-wasm forks (what ghc-wasm-meta pins today)

- [ghc-wasm-meta](https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta) pins wasi-sdk 29.0
  built from the haskell-wasm fork (GitLab project 3212, 2025-12-19). It is exactly upstream
  tag `wasi-sdk-29` plus build tweaks.
- LLVM: the fork's `release/21.x`, which is 21.1.8 plus 4 patches.
- wasi-libc: the fork's master `951e93b3`, which is upstream wasi-sdk-29 plus 5 commits, then
  9 patches.
- A rebase onto LLVM 23 is in progress.
- The README line "Upstream wasi-sdk won't work yet" dates from Dec 2022 and was never
  re-checked.

**Required for correctness:**
- Only one patch: wasm-ld splits huge `__wasm_apply_data_relocs` functions (fork `a4a2f322`;
  upstream llvm PR #129007 is open).
- It matters only for very large TH `.so` files. Without it, V8's ~7.65 MB function limit
  rejects the library.

**Optional (performance, size, diagnostics):**
- **wasi-libc:**
  - `isatty` always returns 0.
  - Bulk-memory `memcpy`/`memmove`/`memset`.
  - dlmalloc `INSECURE` and `MORECORE_CONTIGUOUS=0`.
  - `malloc_inspect_all`, which only the README's wizer recipe uses.
  - Build flags `-O3 -mcpu=lime1 -mreference-types -msimd128 -D__wasilibc_simd_string`.
  - `libc.so` linked with `--Bsymbolic` (GHC's `Dynamic.hs` says that's only an optimisation).
  - An LTO fix.
  - UTF-8-only iconv.
- **LLVM:**
  - wasm-opt only for `WASM_SO_OPT` (upstream has had `--no-wasm-opt` since LLVM 19).
  - The `.size` warning turned into an error.
  - An rpath revert.
  - ICF in wasm-ld (23.x only).
- **wasi-sdk:**
  - Sysroot built with `-mcpu=lime1 -mreference-types -msimd128`.
  - libc++ built with `-fno-exceptions` and `--Bsymbolic`.
  - Reverts upstream's removal of the `wasm32-wasi` targets (wasi-sdk#637, in 34+).
- **mimalloc:** only `LD_PRELOAD`ed in the fork's CI, to speed up static Alpine host binaries.

### 1.3 libffi

- **Why it's needed:** the RTS always needs libffi. `rts.cabal` uses either the system libffi
  or `libffi-clib` (added 2026-01-14), and wasm uses `LibffiAdjustor.c` for adjustors
  (`foreign import "wrapper"`). GHCi's bytecode FFI uses it too.
- **Why not upstream libffi:** its wasm port, even in v3.8.0 (2026-08), includes
  `emscripten.h`, so it can't target WASI ([nixpkgs#422305](https://github.com/NixOS/nixpkgs/issues/422305)).
- **[libffi-wasm](https://gitlab.haskell.org/haskell-wasm/libffi-wasm):**
  - MIT-licensed since tag `20260905` (after GHC #27696).
  - Built by a small Haskell generator (`language-c`, `async`, calls `clang-format`), then 3 C
    files compiled with any wasm clang using `-mcpu=mvp -Oz`.
  - Produces `libffi.a`, plus a PIC `libffi.so` for TH.
  - Its own CI uses **upstream** wasi-sdk-34.
- **Long term:** GHC #22590 (open) plans a replacement.

## 2. New problems the 2023 PR never hit

### 2.1 The `wasip1` target triple *(verified)*

- nixpkgs renamed `wasi32` to `wasm32-wasip1` (config `wasm32-unknown-wasip1`;
  [#537429](https://github.com/NixOS/nixpkgs/pull/537429), 2026-07). `wasi32` is now an alias
  with the same config.
- nixpkgs' `config.sub` (gnu-config 2024-01-01) keeps `wasm32-unknown-wasip1` unchanged.
- GHC's `m4/ghc_convert_os.m4` only matches `wasi)`, so configure fails with "Unknown OS
  wasip1". This holds on master, ghc-9.14 and ghc-9.12.
- ghc-toolchain's `utils/ghc-toolchain/src/GHC/Toolchain/ParseTriple.hs` only matches `"wasi"`.
  Configure always runs ghc-toolchain, but its failure is non-fatal ("For now, we don't 'exit'
  even if ghc-toolchain fails", `m4/ghc_toolchain.m4:56`).
- No GHC issue or MR mentions `wasip1` (searched 2026-10-09).
- After patching the m4, GHC's `TargetPlatform` is assembled from the converted parts
  (`$2Platform="$2Arch-$2Vendor-$2OS"`), i.e. `wasm32-unknown-wasi`. That's what Cabal sees,
  and Cabal classifies it as `Wasi`.
- LLVM 22+ warns on `wasm32-wasi` (llvm#165345); LLVM 21 doesn't.

### 2.2 macOS hosts: GHC #26021 *(verified)*

- [GHC #26021](https://gitlab.haskell.org/ghc/ghc/-/issues/26021) (open): "Hadrian fatal error
  when building wasm target if host ghc uses clang". Related: #24939.
- Hadrian passes the target's `--target=wasm32-…` to the **stage0** clang. The build then fails
  at `_build/stage0/utils/unlit/build/c/fs.o`.
- Bisected to `9995c2b7` ("Support for ARM64 Windows (LLVM-enabled)", 2025-05-04). That commit
  is in ghc-9.14 (9.14.1 release, 9.14.2 RCs), ghc-10.0 and master, **not ghc-9.12**.
- nixpkgs' darwin stdenv uses clang, so expect 9.14/HEAD wasm builds to fail on aarch64-darwin.
  Linux (gcc host) is unaffected.

### 2.3 Linker name *(verified)*

- nixpkgs points GHC's `LD`, "ld command" and "Merge objects command" at `${targetPrefix}ld`.
  For LLVM bintools that is a symlink to `lld`.
- lld (LLVM 21, `lld/Common/DriverDispatcher.cpp`) picks its flavour from the program name:
  `parseProgname` splits on `-` and maps `ld` to **Gnu/ELF**, but `wasm` to Wasm.
- So `wasm32-unknown-wasip1-ld` behaves as the ELF linker, while `wasm32-unknown-wasip1-wasm-ld`
  (also provided by nixpkgs' LLVM bintools) behaves as the wasm linker.

### 2.4 Other nixpkgs defaults that are wrong for wasm (verified by `nix eval` on master eb8ab82)

- The wasm cc is `wasm32-unknown-wasip1-clang-wrapper-21.1.8`; libc is
  `wasilibc-static-…-32`. `hostPlatform.isStatic = true`, `hasSharedLibraries = false`.
- `useLLVM` is true for wasm (`common-have-ncg.nix` doesn't know wasm has an NCG), giving the
  flavour `release+llvm+no_dynamic_libs+no_dynamic_ghc+split_sections`.
- `enableRelocatedStaticLibs` (cross default) adds `-fPIC -fexternal-dynamic-refs`.
  haskell.nix excludes both for wasm.
- `isStatic` adds `--flags=-dynamic-system-linker`. That drops `CAN_LOAD_DLL`, which wasm TH
  needs later.
- `targetPackages.libffi` = upstream libffi 3.8.0, which is broken for WASI.
- `haskell.compiler.ghc914` (gmp variant) needs gmp-static for wasi, which fails to build. The
  `native-bignum` variants avoid it. `haskellPackages` for static hosts is already
  native-bignum ghc912.
- Cabal names wasm executables `<name>.wasm` (`exeExtension (Platform Wasm32 _) = "wasm"`).
- The WASI emulator is wasmtime (`lib/systems/default.nix`).

### 2.5 Template Haskell (next milestone, not this one)

- Supported since GHC 9.12.1 (!12555, merged 2024-10-18); browser mode came in 9.14 (!14099).
- How it works: GHC runs `node dyld.mjs <libdir> libHSghci*.so`. dyld is a JS dynamic linker
  using the `dylink.0` convention. It loads `libc.so` first, then the RTS and Haskell `.so`
  files, and cannot load `.o`/`.a`.
- Node requirement: 22.18+ or 24.2+ (#26965).
- **Shared libraries:**
  - nixpkgs' stock wasilibc 32 **already ships** `lib/wasm32-wasip1/libc.so`, `libdl.so`,
    `libsetjmp.so` and `libwasi-emulated-*.so` *(verified in the cache.nixos.org x86_64-linux
    output)*.
  - #561449's libffi-wasm builds only `libffi.a`; TH also needs `libffi.so`.
  - libc++ `.so` is needed only for C++ (`text_simdutf`).
- **Library dir:** dyld takes it from the last `libraries:` entry of `$CC --print-search-dirs`
  (`compiler/GHC/Runtime/Interpreter/Init.hs`). That needs a patch with nixpkgs' cc-wrapper;
  haskell.nix patches `compiler/GHC.hs`.

## 3. Upstream's recommended build (ghc-wasm-meta `pkgs/wasi-sdk-setup-hook.sh`)

```
AR=llvm-ar CC=<wasm clang> CXX=<wasm clang++> LD=wasm-ld NM=llvm-nm OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump RANLIB=llvm-ranlib SIZE=llvm-size STRINGS=llvm-strings STRIP=llvm-strip CC_FOR_BUILD=cc
CONF_CC_OPTS_STAGE2="-Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128"
CONF_CXX_OPTS_STAGE2="-fno-exceptions -Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128"
CONF_GCC_LINKER_OPTS_STAGE2="-Wl,--error-limit=0,--keep-section=ghc_wasm_jsffi,--keep-section=target_features,--stack-first,--strip-debug"
CONF_*_STAGE1 = the STAGE2 values
./configure --target=wasm32-wasi --with-intree-gmp --with-system-libffi
hadrian/build --flavour=release[+text_simdutf] --docs=no-sphinx-pdfs --docs=no-sphinx-man binary-dist
```

- **Flavour:** CI adds `+host_fully_static`; nixpkgs doesn't need that. Avoid
  `+no_dynamic_libs` if TH is wanted.
- **CPU and LLVM:** `-mcpu=lime1` needs LLVM ≥ 20; nixpkgs has 21.1.8.
- **Tail calls:** opt-in with `-mtail-call`, off since 2025-09-24 because of WebKit.
- **wasm features:** GHC's code generator marks objects with bulk-memory, mutable-globals,
  nontrapping-fptoint, reference-types and sign-ext.
- **wasm-ld flags:**
  - Keep the `ghc_wasm_jsffi` section, which JSFFI needs.
  - `--stack-first` is recommended.
  - `--growable-table` is no longer used.
- **Versions:**
  - There is no GHC 9.16; it became 10.0 (`10.0.1-alpha1`, 2026-09-17). Master is 10.1.
  - ghc-wasm-meta's 9.10/9.12/9.14 flavours come from haskell-wasm/ghc fork branches (the fork's
    ghc-9.14 is upstream + ~107 backports). Its default is 9.14.
  - haskell.nix builds upstream 9.12.4/9.14.1 for wasm in CI.

## 4. nixpkgs: what #225000 did and where it stands now

PR [#225000](https://github.com/NixOS/nixpkgs/pull/225000) targeted `haskell-updates`, has 8
commits from 2023 and is now conflicting.

| Hunk | Status | Notes |
|---|---|---|
| emscripten `bintools.isLLVM` | obsolete | Strip now goes through `toolPath`; LLVM bintools carry `isLLVM`/`targetPrefix`; `dontStrip` already covers wasm. |
| common-hadrian `pkgsBuildBuild`/`depsBuildBuild` | already in tree | `depsBuildBuild = [ buildCC ncurses ]` |
| `CC/AR/LD_STAGE0` exports | already in tree | in `preConfigure` |
| `libffiAttr` hack | superseded | `targetLibs.libffi` from targetPackages; #561449 / our GHC-only wiring |
| `useLLVM` off for wasm | **still needed** | now in `common-have-ncg.nix` |
| `enableNativeBignum` for wasm | **still needed** | gmp has `platforms = all`, so `availableOn` never triggers |
| `enableShared` off for wasm | already true implicitly | wasi is `isStatic`; #558928 goes the other way for TH |
| `enableTerminfo` off for wasm | **needed for HEAD** | cross builds older than 9.15.20250808 already skip terminfo |
| no libiconv for wasm | optional | wasi's libiconv is a header stub (`libcIconv`) |
| LLVM 16 libcxx/libcxxabi wasm fixes | obsolete | llvm/16 is gone; runtimes build handles wasm; no `hasThreads` |
| `libffi-wasm` codegen (non-hackage) + `libffi-wasm-ghc` | superseded | #561449 (`pkgs/by-name/li/libffi-wasm`) |
| wasilibc 19→20, threads option | obsolete | wasilibc 32 (CMake); only the C/C++ wasmtime test is still useful |
| all-packages: wasm `haskellPackages`, min LLVM 16 | obsolete / already true | static hosts use native-bignum ghc912; global LLVM 21 |
| haskell-packages libffi/LLVM overrides | obsolete | one shared LLVM for all GHCs; no per-target special-casing |
| release-cross / release-haskell jobs | **still needed** | `wasiCommon`; a `pkgsCross.wasm32-wasip1` block mirroring `ghcjs` |

Already merged since 2023 (useful context):
- [#537425](https://github.com/NixOS/nixpkgs/pull/537425): wasilibc 27→32, CMake build.
- [#537429](https://github.com/NixOS/nixpkgs/pull/537429): wasip1 rename.
- #455043/#454709: libcxx hardening fix.
- [#553410](https://github.com/NixOS/nixpkgs/pull/553410): generic-builder support for GHC's wasm
  interpreter (no iserv-proxy, nodejs, no library profiling).
- [#553415](https://github.com/NixOS/nixpkgs/pull/553415): matching Haddock for cross builds.

## 5. Related nixpkgs PRs and issues

| # | What | State |
|---|---|---|
| [220835](https://github.com/NixOS/nixpkgs/issues/220835) | Tracking issue: `pkgsCross.wasi32…ghc` | open; last comment 2024-11, unanswered |
| [225000](https://github.com/NixOS/nixpkgs/pull/225000) | sternenseemann's wasm GHC PR | open, stale, conflicting |
| [241739](https://github.com/NixOS/nixpkgs/pull/241739) | wasilibc threads + test (sternenseemann) | open, stale |
| [553410](https://github.com/NixOS/nixpkgs/pull/553410) / [553415](https://github.com/NixOS/nixpkgs/pull/553415) | ilkecan: generic-builder wasm interpreter / Haddock | merged 2026-08-23 (wolfgangwalther) |
| [558928](https://github.com/NixOS/nixpkgs/pull/558928) | ilkecan: shared libs for the wasm interpreter (TH) | open; 0 reviews |
| [561449](https://github.com/NixOS/nixpkgs/pull/561449) | ilkecan: `libffi-wasm: init at 20260905` (+ global `libffi` = libffi-wasm on wasi32) | open; sternenseemann objected 2026-10-05; Ericson2314 requested |
| [422305](https://github.com/NixOS/nixpkgs/issues/422305) | `pkgsCross.wasi32.libffi` build failure | open |
| [537433](https://github.com/NixOS/nixpkgs/pull/537433) | systems: add wasip2 | open |
| [445672](https://github.com/NixOS/nixpkgs/pull/445672) | cross TH + tests (alexfmpe) | open; adjacent |

## 6. Other Nix efforts

- **[ilkecan/ghc-wasm-nix](https://github.com/ilkecan/ghc-wasm-nix):** bindist-only by design.
  - Re-callPackages ghc-wasm-meta's `wasm32-wasi-ghc.nix`/`wasi-sdk.nix` and makes the bindist
    look like a nixpkgs compiler (`targetPrefix = "wasm32-wasi-"`, `enableShared = true`, …).
  - Builds a haskell package set via `pkgsCross.wasi32.callPackage
    <nixpkgs>/pkgs/development/haskell-modules`.
  - Checks: node/wasmtime/wasmer/wasmedge runs, TH, cross-package TH, haddock, wasm-opt.
  - It also has the before/after `--override-input nixpkgs` repro pattern that wolfgangwalther
    asked for.
- **[haskell.nix](https://github.com/input-output-hk/haskell.nix):** from source, cached in CI
  (ghc9124 and ghc9141 on x86_64-linux and aarch64-darwin).
  - PRs #2351 (hamishmack), #2440 (TerrorJack), #2463/#2464 (ncaq); docs in
    `docs/tutorials/wasm.md`.
  - `overlays/wasm.nix`: LLVM 21 + `haskell-wasm-llvm-project.patch`; wasilibc overridden to the
    **haskell-wasm fork**, built with `make default libc_so`.
  - `compiler/ghc/default.nix`:
    - libffi-wasm `.a` + `.so`; `--with-system-libffi`.
    - `enableShared` on for wasm.
    - Flavour `quick+native_bignum+no_profiled_libs`.
    - `stage1.*.ghc.*.opts += -optc-Wno-error=int-conversion -optc-O3 -optc-mcpu=lime1
      -optc-mreference-types -optc-msimd128 -optc-DXXH_NO_XXH3` and
      `stage1.*.ghc.cpp.opts += -optc-fno-exceptions`.
    - `LD=wasm-ld`; no `-fPIC`/`-fexternal-dynamic-refs` for wasm.
    - Patches `compiler/GHC.hs` to give dyld the wasilibc dir; a node wrapper with one flattened
      lib dir for TH.
  - Pinned before the wasip1 rename (hard-codes `wasm32-unknown-wasi`).
- **ghc-wasm-meta's own flake:** bindists only. ghc-wasm-meta#19 "make a proper nixpkgs
  package" (2026-04) is still open.
- **ners/nix-wasm** (used by maralorn's reflex-platform fork and 2026.nixcon.org), miso, agda,
  exomonad: all bindist-based.
- **Discourse:**
  - NixOS #38318 (2024): sternenseemann called packaging "a nightmare".
  - Haskell Discourse #14336 (2026): pointed to the ghc-wasm-meta flake.

## 7. People and channels

- **GHC wasm:** Cheng Shao (@TerrorJack) is the sole maintainer of the backend, ghc-wasm-meta,
  libffi-wasm and the forks. Matrix: `#haskell.wasm:matrix.org`. GHC issues use the `wasm`
  label:
  - #25917 (P::high): toolchain requirements checked at configure time.
  - #26812: bundling the cross toolchain.
  - #26021 / #24939: host GHC uses clang.
  - #26939, #22590.
- **nixpkgs Haskell team** (`#haskell:nixos.org`; GitHub team `NixOS/haskell`):
  - sternenseemann owns the GHC builders.
  - wolfgangwalther merges haskell-modules changes and wants before/after repros.
  - maralorn ships wasm via obelisk/nix-wasm.
  - cdepillabout.
  - Guidance: base Haskell work on, and target PRs to, `haskell-updates`.
- **ilkecan:** the active nixpkgs contributor on wasm (#553410, #553415, #558928, #561449,
  ghc-wasm-nix).
- **wasilibc:** rvolosatovs and wucke13 (maintainers); sepointon (wasip1 rename, wasilibc 32).
- **Cross-compilation design:** Ericson2314. **ghcjs/cross TH:** alexfmpe.
- **haskell.nix:** hamishmack, angerman, ncaq.

## 8. Process notes

- **nixpkgs `CONTRIBUTING.md` "Automation/AI policy":** LLM-assisted commits need an
  `Assisted-by:` trailer (tool + model); `Co-authored-by` doesn't count. PR texts and comments
  need their own disclosure, and a responsible human must review.
- **Formatting:** nixpkgs CI enforces `nix fmt` (treefmt: nixfmt, nixf-diagnose, …).
- **haskell-updates** shares the binary cache with master. On 2026-10-09 it carried GHC 9.12.5,
  9.14.2 and HEAD 10.1.20260810, with `ghc912` → 9.12.5.
