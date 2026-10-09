# Status: pure-Nix GHC wasm backend in nixpkgs

_Last updated: 2026-10-09 (MuniHac 2026)._ Details and sources: [docs/research.md](docs/research.md).
Plan: [docs/plan.md](docs/plan.md). Branch layout: [docs/nixpkgs-branch.md](docs/nixpkgs-branch.md).

## Goal

nixpkgs builds a wasm32-wasi GHC **purely from source with its stock toolchain**: LLVM 21 and
upstream wasilibc 32. No bindists, no haskell-wasm forks. This repo's hello-world flake is the
proof. It takes nixpkgs from branch `ghcwasmhacking` of github.com/mikatammi/nixpkgs (based
on `haskell-updates`).

## TL;DR of the research

- **The reasons #225000 stalled in 2023 are mostly gone.**
  - GHC's RTS no longer needs a patched wasi-libc (GHC `558353f4`, 2024-06).
  - GHC's CI no longer patches GHC.
  - Only one patch in the forked toolchain matters for correctness, and only for huge Template
    Haskell `.so` files.
- **Still needed:**
  - libffi-wasm (ilkecan's #561449).
  - A few nixpkgs GHC-builder fixes.
- **New since then:**
  - GHC rejects nixpkgs' `wasm32-unknown-wasip1` triple.
  - GHC #26021 breaks 9.14+/HEAD wasm builds on macOS hosts.
  - nixpkgs points GHC at lld in ELF mode instead of `wasm-ld`.

## Result matrix

**Everything below is green on a single nixpkgs commit, `93f4824cc1ee` (2026-10-09):** every GHC
version × system × hello (C-FFI hello, pure hello, Template Haskell hello), each run under wasmtime.

Cells: compiler / hello (the C-FFI hello world) / pure = `hello-pure`. `hello` = `hello-wasm.wasm a b`
prints the expected 5 lines under wasmtime. Template Haskell (`hello-th`) is tracked separately below.

| GHC | aarch64-darwin | aarch64-linux | x86_64-linux |
|---|---|---|---|
| 9.12 (`ghc912`) | **✓ / ✓ (pure ✓)** | **✓ / ✓ (pure ✓)** | **✓ / ✓ (pure ✓)** |
| 9.14 (`ghc914`) | **✓ / ✓ (pure ✓)** | **✓ / ✓ (pure ✓)** | **✓ / ✓ (pure ✓)** |
| HEAD (`ghcHEAD`) | **✓ / ✓ (pure ✓)** | **✓ / ✓ (pure ✓)** | **✓ / ✓ (pure ✓)** |

Toolchain sanity: the wasilibc C/C++ test and libffi-wasm's upstream test suite pass on all three systems.
Build log of findings: [results/notes.md](results/notes.md).

**First green build (2026-10-09):** aarch64-linux, GHC 9.12.5-rc3, built from source with stock
nixpkgs LLVM 21 + wasilibc 32 (nixpkgs `404cf810318c`). `hello-wasm.wasm a b` prints all 5
expected lines under wasmtime (including C FFI and a `foreign import "wrapper"` callback via
libffi-wasm); the same `.wasm` also runs unchanged under wasmtime on aarch64-darwin. The
installed compiler's settings: target platform `wasm32-unknown-wasi` (OSWasi), C flags start
with `--target=wasm32-unknown-wasip1`, merge-objects = `wasm32-unknown-wasip1-wasm-ld`.

## Template Haskell

Part of `ghcwasmhacking` since 2026-10-09: ilkecan's #558928, `libffi.so`, and the wasm
interpreter setup (commits 15–17); flake outputs `hello-th-<ghc>`. `hello-th` runs splices
(including one from another module) in GHC's wasm interpreter, `dyld.mjs` under node. (Results
below were built on the former separate branch, `ghcwasmhacking-th`.)

- **TH works:** with the x86_64-linux 9.12 TH compiler, `hello-th` compiles, links and prints the
  expected output under wasmtime. This was checked by hand with the interpreter line swapped
  (see results/notes.md).
- The one bug found: `dyld.mjs`'s interpreter line got longer than Linux's 256-byte limit once
  `env` and node were pinned by store path. It is now started through a binary node wrapper
  carrying each version's flags (`7012299d6f89`).
- **TH is green for 9.12 and 9.14 on all three systems** (compiler, `hello-th` and the
  wasmtime output check, all in the nix sandbox). The first green build was aarch64-darwin 9.12.

| GHC | aarch64-darwin | aarch64-linux | x86_64-linux |
|---|---|---|---|
| 9.12 | **✓** | **✓** | **✓** |
| 9.14 | **✓** | **✓** | **✓** |
| HEAD | **✓** | **✓** | **✓** |

## Blockers and where they belong

| Blocker | Where to fix | State |
|---|---|---|
| libffi for wasi | nixpkgs (#561449, ilkecan); our GHC-only wiring | in branch |
| `wasip1` OS not accepted by GHC configure/ghc-toolchain | GHC upstream MR + nixpkgs patch | in branch; MR draft in `drafts/` |
| GHC #26021 (stage0 clang gets the wasm `--target`) on macOS, 9.14+ | GHC upstream | not triggered with nixpkgs: the darwin cc-wrapper's `-mmacos-version-min` makes GHC's `-Werror` probe fail (see results/notes.md); still worth fixing upstream |
| darwin libiconv leaking into the wasm target's deps (unspliced) | nixpkgs common-hadrian | fixed in branch |
| hadrian gives stage0 (host) the target's libffi dirs → stage1 link picks libffi-wasm | GHC/hadrian upstream + nixpkgs patch | fixed in branch; patch in `upstream/ghc/0002-…` |
| GHC passes clang `--target=wasm32-unknown-wasi` (normalized OS) → wrong compiler-rt dir | GHC upstream (part of the wasip1 patch) | fixed in branch |
| RTS `JSFFI.c` uses WASI API without `<wasi/api.h>` (needed with wasilibc 32) | GHC upstream + nixpkgs patch | fixed in branch; `upstream/ghc/0003-…` |
| xxhash includes `<arm_neon.h>` for wasm SIMD (nixpkgs clang ships it) | GHC upstream + nixpkgs patch | fixed in branch; `upstream/ghc/0004-…` |
| GHC ≥ 10 host templates hardcode `use-lib-rt = YES` (`system.config.host.in`) and `tgtOtool`/`tgtInstallNameTool = Nothing` (`default.host.target.in`); both break macOS hosts | GHC upstream; nixpkgs patches the templates | worked around (darwin + HEAD only) |
| GHC ≥ 10 cross: haddock's index step can't read the stage0 package db (`readPackageDb: … not enough bytes`) | GHC/hadrian upstream | worked around: no haddocks for wasm GHC ≥ 10 |
| `LD` = lld in ELF mode | nixpkgs common-hadrian | in branch |
| `useLLVM`/native bignum/terminfo/PIC/dynamic-system-linker defaults | nixpkgs common-hadrian | in branch |
| GHC ≥ 10 RTS: `extra-lib-dirs-static: @FFILibDir@` disables Cabal's fallback, so executables can't find libnuma/libdw; native ghcHEAD can't link hello world, cross `Setup.hs` fails | GHC upstream (`upstream/ghc/0005-…`) + nixpkgs patch | fixed in branch; verified on x86_64-linux and aarch64-linux |
| TH: shared libs, `libffi.so`, dyld lib dir, `dyld.mjs` interpreter line too long for Linux | nixpkgs (#558928 + TH branch); GHC (configurable dyld lib dir) | in TH branch; TH verified at runtime on x86_64-linux 9.12 |

## Coordination map

- **GHC upstream** (Cheng Shao/@TerrorJack; `#haskell.wasm:matrix.org`; GHC `wasm` label):
  - the `wasip1` MR;
  - a #26021 fix;
  - a configurable dyld lib dir;
  - a data point for #25917.
- **haskell-wasm / ghc-wasm-meta#19**: stock-toolchain results; which fork patches can go
  upstream (llvm#129007).
- **nixpkgs Haskell team** (`#haskell:nixos.org`): GHC builder PRs go to `haskell-updates`;
  libffi placement is sternenseemann's call; wolfgangwalther wants before/after repros.
- **ilkecan**: #558928 and #561449 are integrated in the branch; share results and the GHC-only
  libffi wiring.
- **wasilibc** (rvolosatovs, wucke13, sepointon): test addition.

## Open questions for upstream

_To be written after the builds: only what they leave unresolved._
