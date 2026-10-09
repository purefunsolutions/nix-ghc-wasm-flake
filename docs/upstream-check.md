# Upstream status of our GHC changes (2026-10-28)

Where each GHC change the nixpkgs branch needs stands upstream. The branch fetches the changes
that have a GHC merge request from GitLab with `fetchpatch2`, pinned to the merge requests'
commits; `upstream/ghc/` keeps only the one without a merge request. The README's upstream tracker
has the current status of each.

| Change | nixpkgs applies it to | Upstream |
| -- | -- | -- |
| Accept `wasm32-*-wasip1` triples | all wasm GHCs (9.12, 9.14, HEAD) | [!16795](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16795) ([#27930](https://gitlab.haskell.org/ghc/ghc/-/issues/27930)); backports to 10.0, 9.14 and 9.12 wanted |
| RTS: `<wasi/api.h>` in `JSFFI.c` | all wasm GHCs | [!16794](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16794) ([#27929](https://gitlab.haskell.org/ghc/ghc/-/issues/27929)); backports to 10.0, 9.14 and 9.12 wanted |
| xxHash includes `<arm_neon.h>` for wasm SIMD | all wasm GHCs | Fixed in xxHash ([#1182](https://github.com/Cyan4973/xxHash/pull/1182), not released yet). GHC [!16708](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16708) bumps the vendored copy to 0.8.4 and [!16879](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16879) to xxHash's dev branch; issue [#27931](https://gitlab.haskell.org/ghc/ghc/-/issues/27931). All GHC versions here vendor the same 0.8.3, so both bumps apply to each. |
| RTS: static library dirs | GHC ≥ 10, all targets (native too) | [!16791](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16791) ([#27926](https://gitlab.haskell.org/ghc/ghc/-/issues/27926)): a regression from `0f53ccc6`, also on `ghc-10.0` |
| Hadrian: no target libffi dirs for a cross compiler's stage0 (`upstream/ghc/0002-…`) | all wasm GHCs | Issue [#28053](https://gitlab.haskell.org/ghc/ghc/-/issues/28053); no MR yet. Master doesn't need it since `23c9b6c392` (stage 2 cross compilers) looks the dirs up per stage; `ghc-10.0`, `ghc-9.14` and `ghc-9.12` still do. |
| GHC 10's darwin host templates: librt, leading underscore, otool, install_name_tool | wasm GHC ≥ 10 on darwin (nixpkgs patches the templates) | Issue [#28054](https://gitlab.haskell.org/ghc/ghc/-/issues/28054); master only |
| The haddock index step reads the stage0 package db in cross builds | GHC ≥ 10 cross compilers (nixpkgs builds no haddocks there) | Issue [#28055](https://gitlab.haskell.org/ghc/ghc/-/issues/28055); bisected to `23c9b6c392`, master only. [!15417](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/15417) fixes it: tested 2026-10-28 on x86_64-linux and aarch64-darwin. On our 2026-08-10 snapshot it needs `5939ceaf1f`, `a6061455d5` and `f217fc315b` under it. |
| Cross `ghc --info` unit ids, which cabal-install 3.18 needs | not carried: Nix builds don't notice | [!16790](https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16790) merged on 2026-10-11, master only |
| The dyld library dir via `getGccSearchDirectory` (nixpkgs substitutes it) | wasm GHC ≥ 9.12 (Template Haskell) | Same code in all versions; maybe a feature MR for a configurable dir |
| `dyld.mjs`'s interpreter line → a node wrapper | wasm GHC ≥ 9.12 (Template Haskell) | None: nixpkgs packaging |

Related upstream items worth linking:

- **#26720** (open, newcomer task): GHC should refuse to run an empty tool path from
  `default.host.target`. That's the same symptom as our darwin `otool: could not execute:`. It
  doesn't fix the wrong template values, though.
- **#26434 / !14935** (static linking support, which introduced the static fields) and **#20759**
  (open since 2021: wire up `library-dirs-static`). Context for !16791.
- **#26914** (closed 2026-07-27): in ghc.nix, the `mostly_static` test failed with
  `cannot find -l:libnuma.a`, and the test was disabled for setups without a static toolchain.
  It's not the same bug (that test asks for a static `libnuma.a`), but it's the same
  missing-directory territory seen from a Nix environment.
- **#26965** (open): `dyld.mjs` needs Node ≥ 22.18 (`import.meta.main`). nixpkgs' node 24 is fine.
- **#27079 / !15770**: `dyld.mjs` was broken on the `ghc-9.12` branch. It's fixed there; our 9.12
  Template Haskell works.
- **#26047** (open): hadrian hardcodes values better placed in `.cabal` files. General background
  for the hadrian patch.
