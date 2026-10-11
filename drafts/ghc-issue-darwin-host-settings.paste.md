_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this report. I have carefully reviewed and revised it and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

## Summary

On master, a cross compiler can't be built on a macOS host. Since 23c9b6c392 (!15231), a cross build compiles stage 1 and its libraries, RTS included, for the host: `targetStage` returns the host target for them (`hadrian/src/Oracles/Setting.hs:238-250`), and `lookupStageBuildConfig` reads `system.config.host` (`hadrian/src/Hadrian/Oracles/TextFile.hs:57-78`). The host templates hardcode values that are right on Linux but wrong on darwin:

- `hadrian/cfg/system.config.host.in:61`: `use-lib-rt = YES`, but macOS has no librt. The target's `system.config.target.in:67` uses configure's `@UseLibrt@`.
- `hadrian/cfg/default.host.target.in:10`: `tgtSymbolsHaveLeadingUnderscore = False`, but Mach-O symbols have a leading underscore.
- `hadrian/cfg/default.host.target.in:49-50`: `tgtOtool = Nothing` and `tgtInstallNameTool = Nothing`. GHC runs both after linking for darwin (`runInjectRPaths`, `compiler/GHC/Linker/Executable.hs:347-348`), so it tries to run an empty program path.

`default.target.in` fills the same fields from configure (`@LeadingUnderscoreBool@`, `@OtoolCmdMaybeProg@`, `@InstallNameToolCmdMaybeProg@`). 521e55bf69 began filling in the host template from `*_STAGE0` values and says there is more to do; `configure.ac:1117` still calls most of its values dummies that are never used.

GHC's CI doesn't hit this because all its cross jobs run on Linux hosts (`.gitlab/generate-ci/gen_ci.hs`).

## Steps to reproduce

Build a cross compiler on a macOS host. I built a wasm32-wasi one on aarch64-darwin through my nixpkgs branch (`pkgsCross.wasm32-wasip1.buildPackages.haskell.compiler.ghcHEAD`, GHC 556db2f32f; the code above is the same on master e7cacf59b8). The branch's other GHC patches don't touch these files. The errors came one at a time, each after I had worked around the previous one.

Configuring the host RTS:

```
Error: [Cabal-4345]
Missing dependency on a foreign library:
* Missing (or bad) C library: rt
```

Linking `unlit` for the host. The message ends at the colon because the path is empty:

```
| Run Ghc LinkHs Stage1: _build/stage1/utils/unlit/build/c/fs.o (and 1 more) => _build/stage1/bin/wasm32-unknown-wasip1-unlit
ghc: otool: could not execute:
```

Linking Haskell programs for the host, here `runghc`. The C symbols that Haskell and Cmm code reference lack the underscore:

```
Undefined symbols for architecture arm64:
...
  "user_era", referenced from:
      stg_upd_frame_info in libHSrts-1.0.3.a(Updates.o)
      ...
     (maybe you meant: _user_era)
...
ld: symbol(s) not found for architecture arm64
```

Setting only these four values for darwin (`use-lib-rt = NO`, `tgtSymbolsHaveLeadingUnderscore = True`, and the paths of otool and install_name_tool) is enough: the cross compiler then builds, and hello-world programs, one of them with Template Haskell, run under wasmtime.

## Expected behavior

Cross compilers build on macOS hosts, with host settings that match the host.

## Environment

* GHC version used: master (e7cacf59b8), since 23c9b6c392. From reading the code, ghc-10.0 isn't affected: it has no `system.config.host.in`, and its in-tree compilers only get the target's `.target` file (`targetStage (Stage1 {}) = getTargetTarget`).
* Operating System: macOS 26.7.1 host, wasm32-wasi target. The values don't depend on the target, so other targets should fail the same way, but I've only tried wasm.
* System Architecture: aarch64 host

Possible fixes: configure could take these values from the bootstrap compiler's `--info`, which has "Leading underscore", "otool command" and "install_name_tool command", as it already does for other `*_STAGE0` values (`configure.ac:173-199`), and check librt with `CC_STAGE0`. Or the host target could come from ghc-toolchain, which already finds otool and install_name_tool and checks the underscore (`utils/ghc-toolchain/exe/Main.hs:487-499`).

Related: #26720 would turn the otool error into a clear message.

cc @mpickering @supersven

/label ~"T::bug"
/label ~"needs triage"
/label ~hadrian
/label ~cross-compilation
/label ~"OS:macOS"
