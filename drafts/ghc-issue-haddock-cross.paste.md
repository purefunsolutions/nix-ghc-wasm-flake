_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this report. I have carefully reviewed and revised it and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

## Summary

Since 23c9b6c392 (!15231), a cross build with `finalStage = Stage1` fails in `binary-dist-dir` at the haddock index step. nixpkgs sets `finalStage = Stage1` for all its cross compilers.

```
| Run Haddock BuildIndex: _build/doc/html/libraries/Cabal-syntax-3.16.1.0/Cabal-syntax.haddock (and 45 more) => _build/doc/html/libraries/index.html
Command line: _build/stage1/bin/javascript-unknown-ghcjs-haddock -B_build/stage1/lib --lib=_build/stage1/lib --gen-index --gen-contents -o _build/doc/html/libraries ...
haddock: internal error: _build/stage1/lib/../../stage0/lib/package.conf.d/package.cache: GHC.Unit.Database.readPackageDb: inappropriate type (not enough bytes)
```

23c9b6c392 made the `settings` rule depend on `finalStage` (`hadrian/src/Rules/Generate.hs:260`). With `finalStage = Stage1`, `_build/stage1/lib/settings`, which the cross compiler and haddock in `_build/stage1/bin` use, gets:

```
,("Relative Global Package DB", "package.conf.d")
,("LibDir", "../../stage0/lib/")
```

The rule computes the database path relative to `_build/stage1/lib` (line 266), but `generateSettings` sets `LibDir` to `_build/stage0/lib`, because it checks `crossStage` of the stage below (lines 505-506). So the in-tree cross compiler's global package database is the bootstrap compiler's:

```
$ _build/stage1/bin/javascript-unknown-ghcjs-ghc --print-global-package-db
/.../_build/stage1/lib/../../stage0/lib/package.conf.d
```

Package builds don't notice, because they get `-no-global-package-db` from Cabal's configured GHC options (`hadrian/src/Settings/Builders/Cabal.hs:241`). The index step passes only `-B` and `--lib` (`hadrian/src/Settings/Builders/Haddock.hs:21`), so haddock reads that database. Its `package.cache` was written by the bootstrap `ghc-pkg` (9.10.3 here), and master can't parse it: 1ac1a54108 added fields to the records but kept the header version at 1.0. Adding `--optghc=-no-global-package-db` to the index command avoids the error.

GHC's CI uses the default `finalStage = Stage2`. There the same code points `_build/stage1/lib/settings` at `_build/stage2/lib/package.conf.d`, and the wasm job builds the index fine (job 2669914, on e7cacf59b8).

Is `finalStage = Stage1` still supported for cross builds, now that the cross compiler is the stage 2 compiler? If it is, the in-tree settings need fixing. If it isn't, hadrian could reject it instead of building a compiler that uses the bootstrap package database, and nixpkgs would switch to `Stage2`.

## Steps to reproduce

1. Configure a cross build, here `emconfigure ./configure --target=javascript-unknown-ghcjs` (also seen with wasm32-wasi).
2. Set `finalStage = Stage1` in `hadrian/src/UserSettings.hs`.
3. Build `binary-dist-dir` with library docs, e.g. nixpkgs' flags: `--flavour=release+no_dynamic_libs+no_dynamic_ghc+split_sections --bignum=native --docs=no-sphinx-pdfs --hash-unit-ids binary-dist-dir`.

I tested this only through nixpkgs' derivation (`pkgsCross.ghcjs.buildPackages.haskell.compiler.ghcHEAD`, built from a given GHC commit). The parent 521e55bf69 builds completely, docs index included; 23c9b6c392 fails as above. nixpkgs' Hydra job for this compiler has failed since the 10.1.20260810 snapshot: https://hydra.nixos.org/build/347803739

## Expected behavior

`binary-dist-dir` builds the haddock index as it did before 23c9b6c392, or hadrian rejects `finalStage = Stage1` for a cross build with a clear error.

## Environment

* GHC version used: master. Bisected to 23c9b6c392; the code involved is unchanged on master (e7cacf59b8). ghc-10.0 and older branches don't have 23c9b6c392.
* Operating System: NixOS (nixpkgs build), bootstrap GHC 9.10.3
* System Architecture: x86_64-linux

As a workaround, my nixpkgs branch skips the library haddocks for cross GHC >= 10 (`--docs=no-haddocks`).

cc @mpickering @supersven

/label ~"T::bug"
/label ~"needs triage"
/label ~hadrian
/label ~cross-compilation
