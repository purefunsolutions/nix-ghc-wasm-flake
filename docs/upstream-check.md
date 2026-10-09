# Upstream check: are our GHC patches already in GHC? (2026-10-10)

I searched GHC's GitLab issues and MRs (title and description) and read the relevant files on
`master`, `ghc-9.14` and `ghc-9.12`. **None of our fixes exists upstream, and there is no
issue or MR for any of them.**

| Patch | nixpkgs applies it to | master / ghc-9.14 / ghc-9.12 | Upstream target |
|---|---|---|---|
| `0001` accept `wasm32-*-wasip1` | all wasm GHCs (9.12, 9.14, HEAD) | not fixed in any (only `wasi`) | master + backports |
| `0002` hadrian: no target libffi dirs for stage0 | all wasm GHCs | not fixed in any | master + backports |
| `0003` rts: `<wasi/api.h>` in `JSFFI.c` | all wasm GHCs | not fixed in any | master + backports |
| `0004` rts: no XXH3 on 32-bit | all wasm GHCs | not fixed in any | master + backports |
| `0005` rts: static library dirs | GHC ≥ 10 (all targets, including native) | regression on master only (`0f53ccc6`) | master |
| GHC 10 darwin host templates: librt, leading underscore, otool, install_name_tool (no patch file yet) | wasm GHC ≥ 10 on darwin | master only | issue (+ MR) |
| haddock index reads the stage0 package db (workaround: no haddocks) | wasm GHC ≥ 10 | master only | issue |
| dyld library dir via `getGccSearchDirectory` (nixpkgs substitution) | wasm GHC ≥ 9.12 (TH) | same code in all | maybe a feature MR (configurable dir) |
| `dyld.mjs` interpreter line → node wrapper | wasm GHC ≥ 9.12 (TH) | n/a, nixpkgs packaging | none |

Related upstream items worth linking:
- **#26720** (open, newcomer task): GHC should refuse to run an empty tool path from
  `default.host.target`. That's the same symptom as our darwin `otool: could not execute:`.
  It doesn't fix the wrong template values, though.
- **#26434 / !14935** (static linking support, which introduced the static fields) and **#20759**
  (open since 2021: wire up `library-dirs-static`). Context for `0005`.
- **#26965** (open): `dyld.mjs` needs Node ≥ 22.18 (`import.meta.main`). nixpkgs' node 24 is fine.
- **#27079 / !15770**: `dyld.mjs` was broken on the ghc-9.12 branch. It's fixed there; our 9.12
  TH works.
- **#26047** (open): hadrian hardcodes values better placed in `.cabal` files. General
  background for `0002`.
