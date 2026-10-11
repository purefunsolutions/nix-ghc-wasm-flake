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
marked "carried". Statuses as of 2026-10-28.

| Where | Change | GHC versions | By | Status | In the nixpkgs branch |
| -- | -- | -- | -- | -- | -- |
| GHC | [!16791](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16791) ([#27926](https://gitlab.haskell.org/ghc/ghc/-/issues/27926)): RTS static library dirs; GHC ≥ 10 can't link programs when libnuma/libdw aren't on the default path | 10.0, HEAD | Mika Tammi | open; wasm CI testsuite green; also needs a `ghc-10.0` backport | carried (fetched from the MR) |
| GHC | [!16790](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16790) ([#27919](https://gitlab.haskell.org/ghc/ghc/-/issues/27919)): newer cabal-install (3.18+) on wasm GHCs; it fixes cross `ghc --info` unit ids, without which 3.18 breaks | 9.14, HEAD (9.12: only the `ghc` unit) | Cheng Shao | ✅ merged 2026-10-11 (`f217fc315b`, in batch !16797); we tested it on aarch64-darwin | not carried (nix builds aren't affected) |
| GHC | [!16795](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16795) ([#27930](https://gitlab.haskell.org/ghc/ghc/-/issues/27930)): accept `wasm32-*-wasip1` triples; configure stops with `Unknown OS wasip1` | 9.12, 9.14, 10.0, HEAD | Mika Tammi | open, Blocked on Review (Cheng asked to review); wasm CI testsuite green (9,865 passes, 0 unexpected); also needs `ghc-10.0`, `ghc-9.14` and `ghc-9.12` backports | carried (fetched from the MR) |
| GHC | hadrian: keep the target's libffi away from stage0; a cross compiler's stage0 was handed it | 9.12, 9.14, 10.0 (not master since `23c9b6c392`) | Mika Tammi | issue [#28053](https://gitlab.haskell.org/ghc/ghc/-/issues/28053) filed; MR not submitted yet | carried (`hadrian-cross-stage0-no-target-libffi.patch`) |
| GHC | [!16794](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16794) ([#27929](https://gitlab.haskell.org/ghc/ghc/-/issues/27929)): rts: include `<wasi/api.h>` in `JSFFI.c`; the wasm RTS doesn't compile with wasi-libc ≥ 32 | 9.12, 9.14, 10.0, HEAD | Mika Tammi | open, Blocked on Review (Cheng asked to review); wasm CI testsuite green; also needs `ghc-10.0`, `ghc-9.14` and `ghc-9.12` backports | carried (fetched from the MR) |
| GHC | rts: don't compile XXH3 on 32-bit platforms | 9.12, 9.14, 10.0, HEAD | Mika Tammi | issue [#27931](https://gitlab.haskell.org/ghc/ghc/-/issues/27931) filed; MR not submitted yet; the backports need it even if master gets the xxHash bump (!16879) | not carried (the branch takes the xxHash bumps instead) |
| GHC | [!16708](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16708) ([#27824](https://gitlab.haskell.org/ghc/ghc/-/issues/27824)): xxhash: bump to v0.8.4; doesn't fix #27931 by itself (0.8.4 has the same `arm_neon.h` check), but !16879 builds on it | HEAD (+ 9.14, 10.0 backports) | Cheng Shao | approved by AndreasK 2026-10-13; waits for Cheng to amend the commit message | carried (fetched from the MR) |
| GHC | [!16879](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16879) ([#27931](https://gitlab.haskell.org/ghc/ghc/-/issues/27931)): xxhash: bump to xxHash `dev` (`658147a68334`), which has xxHash#1182; on top of !16708 | HEAD | Mika Tammi | draft, DO NOT MERGE until xxHash v0.8.5 is released; tested with 9.12, 9.14 and HEAD on aarch64-darwin | carried (its xxHash dev commit, fetched from the MR) |
| GHC | hadrian: fill in the host config for darwin; it hardcodes librt, leading underscore, otool and install_name_tool, so cross builds on macOS hosts fail for every target | HEAD only (not in 10.0, by reading the code) | Mika Tammi | issue [#28054](https://gitlab.haskell.org/ghc/ghc/-/issues/28054) filed; MR not submitted yet | worked around |
| GHC | hadrian: cross builds with `finalStage = Stage1` (nixpkgs' setting) fail in the haddock index step; the in-tree settings point at the bootstrap compiler's package database; bisected to `23c9b6c392` | HEAD only (not in 10.0) | Mika Tammi | issue [#28055](https://gitlab.haskell.org/ghc/ghc/-/issues/28055) filed; fixed by [!15417](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/15417) (Sven Tennie), tested 2026-10-28 on x86_64-linux and aarch64-darwin | worked around (no haddocks for cross GHC ≥ 10) |
| nixpkgs | [#561449](https://github.com/NixOS/nixpkgs/pull/561449): `libffi-wasm: init` | all wasm GHCs | ilkecan | open | carried (cherry-picked) |
| nixpkgs | [#558928](https://github.com/NixOS/nixpkgs/pull/558928): shared libraries for the wasm interpreter; needed for Template Haskell | 9.12 and newer (TH) | ilkecan | open | carried (cherry-picked) |
| nixpkgs | [#225000](https://github.com/NixOS/nixpkgs/pull/225000): the original GHC wasm backend PR | — | sternenseemann | draft since 2023 | two commits ported |
| LLVM | [llvm#129007](https://github.com/llvm/llvm-project/pull/129007): wasm-ld: split a huge relocs function; `__wasm_apply_data_relocs` overflows for very large TH libraries | 9.12 and newer (TH) | dmjio | open | not carried (only matters for very large TH libraries) |
| xxHash | [#1182](https://github.com/Cyan4973/xxHash/pull/1182) ([#1165](https://github.com/Cyan4973/xxHash/issues/1165)): xxhash.h: don't mistake clang's `arm_neon.h` for SIMDe; wasm `-msimd128` builds of GHC's vendored copy fail with `#error` | 9.12, 9.14, 10.0, HEAD (vendored copy) | Mika Tammi | ✅ merged 2026-10-28 (`d16ca2b`), not in a release yet (latest: v0.8.4); GHC vendors 0.8.3 and still needs its own fix | carried, through GHC !16879 |
| xxHash | [#1193](https://github.com/Cyan4973/xxHash/pull/1193): ci: test WebAssembly/WASI with clang and wasi-libc, so the code paths #1182 changed stay tested | — | Mika Tammi | open (since 2026-10-28); CI green | not carried (CI only) |
| nixpkgs | my other patches, in the [`ghcwasmhacking`](https://github.com/mikatammi/nixpkgs/tree/ghcwasmhacking) branch; GHC builder, wasilibc, LLVM and cross-compilation fixes, see [docs/nixpkgs-branch.md](docs/nixpkgs-branch.md) | all wasm GHCs | Mika Tammi | not submitted yet; to be split into PRs | carried (it is the branch) |

The GHC patches that aren't submitted yet are in [`upstream/ghc/`](upstream/ghc/). The nixpkgs
branch itself isn't meant to become a PR; see [docs/nixpkgs-branch.md](docs/nixpkgs-branch.md).

## Conventions

This repository broadly follows the
[nixpkgs contributing conventions](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md),
though not necessarily in every detail. In particular, commits follow the
nixpkgs automation/AI policy: any non-trivial use of AI tooling is disclosed
with an `Assisted-by:` commit trailer naming the tool and model used.
