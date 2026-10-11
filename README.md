# ghc-wasm-flake Flake

This flake makes it possible to build projects that use GHC's WebAssembly
backend as pure Nix derivations, so building them works the same way as with
any other GHC in nixpkgs instead of assembling the toolchain imperatively in a
devshell. This repository also tracks the upstream pull requests in nixpkgs
and GHC needed to make this work, and aims to support upstream development of
the GHC WASM backend.

## Upstream tracker

Unmerged changes this work needs or carries, by us and by others. The nixpkgs branch
([`ghcwasmhacking`](https://github.com/mikatammi/nixpkgs/tree/ghcwasmhacking)) carries everything
marked "carried". Statuses as of 2026-10-11.

| Where | Change | GHC versions | By | Status | In the nixpkgs branch |
|---|---|---|---|---|---|
| GHC | [!16791](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16791) ([#27926](https://gitlab.haskell.org/ghc/ghc/-/issues/27926)): RTS static library dirs; GHC ≥ 10 can't link programs when libnuma/libdw aren't on the default path | 10.0, HEAD | Mika Tammi | open; also needs a `ghc-10.0` backport | carried (`ghc-10-rts-static-lib-dirs.patch`) |
| GHC | [!16790](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16790) ([#27919](https://gitlab.haskell.org/ghc/ghc/-/issues/27919)): cross `ghc --info` unit ids; breaks cabal-install 3.18 with our wasm GHCs | 9.14, HEAD (9.12: only the `ghc` unit) | Cheng Shao | open; we tested it on aarch64-darwin | not carried (nix builds aren't affected) |
| GHC | accept `wasm32-*-wasip1` target triples | 9.12, 9.14, 10.0, HEAD | Mika Tammi | not submitted yet | carried (`ghc-wasm-accept-wasip1.patch`) |
| GHC | hadrian: don't give a cross compiler's stage0 the target's libffi | 9.12, 9.14, 10.0; HEAD unverified | Mika Tammi | not submitted yet | carried (`hadrian-cross-stage0-no-target-libffi.patch`) |
| GHC | [!16794](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16794) ([#27929](https://gitlab.haskell.org/ghc/ghc/-/issues/27929)): rts: include `<wasi/api.h>` in `JSFFI.c`; the wasm RTS doesn't compile with wasi-libc ≥ 32 | 9.12, 9.14, 10.0, HEAD | Mika Tammi | open; also needs `ghc-10.0`, `ghc-9.14` and `ghc-9.12` backports | carried (`ghc-wasm-rts-include-wasi-api.patch`) |
| GHC | rts: don't compile XXH3 on 32-bit platforms | 9.12, 9.14, 10.0, HEAD | Mika Tammi | not submitted yet | carried (`ghc-wasm-rts-no-xxh3.patch`) |
| GHC | GHC 10's host settings are wrong on darwin (librt, leading underscore, otool, install_name_tool) | HEAD; 10.0 untested | | issue to file | worked around |
| GHC | GHC 10 cross builds fail in the haddock index step; bisected to `23c9b6c392` | HEAD only (not in 10.0) | | issue to file | worked around (no haddocks for cross GHC ≥ 10) |
| nixpkgs | [#561449](https://github.com/NixOS/nixpkgs/pull/561449): `libffi-wasm: init` | all wasm GHCs | ilkecan | open | carried (cherry-picked) |
| nixpkgs | [#558928](https://github.com/NixOS/nixpkgs/pull/558928): shared libraries for GHC's wasm interpreter (Template Haskell) | 9.12 and newer (TH) | ilkecan | open | carried (cherry-picked) |
| nixpkgs | [#225000](https://github.com/NixOS/nixpkgs/pull/225000): the original GHC wasm backend PR | — | sternenseemann | draft since 2023 | two commits ported |
| LLVM | [llvm#129007](https://github.com/llvm/llvm-project/pull/129007): wasm-ld splits huge `__wasm_apply_data_relocs` functions | 9.12 and newer (TH) | dmjio | open | not carried (only matters for very large TH libraries) |

The GHC patches that aren't submitted yet are in [`upstream/ghc/`](upstream/ghc/). The nixpkgs
branch itself isn't meant to become a PR; see [docs/nixpkgs-branch.md](docs/nixpkgs-branch.md).

## Conventions

This repository broadly follows the
[nixpkgs contributing conventions](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md),
though not necessarily in every detail. In particular, commits follow the
nixpkgs automation/AI policy: any non-trivial use of AI tooling is disclosed
with an `Assisted-by:` commit trailer naming the tool and model used.
