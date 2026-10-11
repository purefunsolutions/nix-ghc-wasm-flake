_LLM assistance: Claude Code (Claude Opus 5.5) was used while preparing this contribution: for the investigation, the testing, and drafts of the commit message, the changelog entry and this description. I have carefully reviewed and revised the submitted material and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

Fixes #27930.

## Changes contained in this patch

configure and ghc-toolchain now accept `wasip1` as the OS of a WASI target triple, as an alias of `wasi` (see #27930). GHC's target platform stays `wasm32-unknown-wasi`, so Cabal still sees `os(wasi)`, and `--target=wasm32-wasi` configures exactly as before. `wasip2` is a different ABI and stays rejected.

The LLVM target keeps `wasip1`, just as it already keeps the `android` and `gnueabi` OS names. configure passes it to the C compiler as `--target`. With `--target=wasm32-unknown-wasi`, clang in nixpkgs' `wasm32-unknown-wasip1` toolchain looks for its linker and compiler-rt under that name, and linking fails (see Testing).

There's also a changelog entry.

### Alternative considered

Since LLVM 22 deprecates `wasm32-wasi`, the LLVM target could become `wasm32-unknown-wasip1` for `wasi` triples too. That would change the C compiler flags for CI and ghc-wasm-meta, so it isn't part of this MR. @TerrorJack, let me know if you'd prefer it.

### Testing

My nixpkgs branch [`ghcwasmhacking`](https://github.com/mikatammi/nixpkgs/tree/ghcwasmhacking) carries [an earlier version of this patch](https://github.com/mikatammi/nixpkgs/blob/b708887d8ad14625acc1fa1877876a06dc7d877a/pkgs/development/compilers/ghc/ghc-wasm-accept-wasip1.patch), with the same effect. With it, the branch's wasm GHC 9.12, 9.14 and HEAD (stock LLVM 21, wasi-libc 32) build on aarch64-darwin, aarch64-linux and x86_64-linux, and programs built with them (C FFI, Template Haskell) run under wasmtime.

On aarch64-darwin, in the build environment of that branch's wasm GHC HEAD (clang 21.1.8, wasi-libc 32) and with its configure flags:

- `--target=wasm32-unknown-wasip1`: master (e7cacf59b8) stops with `Unknown OS wasip1`. With this patch, configure succeeds: GHC target `wasm32-unknown-wasi`, `tgtLlvmTarget = "wasm32-unknown-wasip1"`, the C compiler gets `--target=wasm32-unknown-wasip1`, and ghc-toolchain's target file matches configure's.
- Without the `m4/ghc_llvm_target.m4` change, the C compiler gets `--target=wasm32-unknown-wasi`, and linking with that fails. clang runs a plain `wasm-ld` instead of the toolchain's `wasm32-unknown-wasip1-wasm-ld`, and given a `wasm-ld`, it can't find compiler-rt: `cannot open …/resource-root/lib/wasm32-unknown-wasi/libclang_rt.builtins.a`.
- `--target=wasm32-wasi`: the generated `hadrian/cfg` files are the same as on master.

## MR Checklist

- [x] This MR solves the problem described in the following issue: #27930
- [x] A changelog entry was added in `changelog.d/` for user-facing changes (see [changelog guide][changelog]).
      If this MR does not need a changelog entry, the ~"no-changelog" label was applied.
- [x] This MR does not make any significant changes to `base`, or it has an accompanying [CLC proposal](https://github.com/haskell/core-libraries-committee#base-package).
- [x] If this MR has the potential to break user programs, the ~"user-facing" label was applied to
      test against head.hackage.
      _Not applicable: it only changes how configure parses the target triple._
- [x] All commits are either individually buildable or squashed.
      _One commit._
- [ ] After all approvals and before landing: all fixup commits are squashed with their originating commits.
- [x] Commit messages describe *what they do*, referring to tickets using `#NNNNN` syntax.
- [x] Source comments describing the change were added. For larger changes [notes][notes] and
      cross-references from the relevant places were added (as applicable).
      _Not applicable: it adds `wasip1` to three existing lists of OS names._
- [ ] [Testcases to the testsuite][adding test] were added (as applicable).
      _None: there are no tests for configure's target parsing, and CI configures for `wasm32-wasi`._
- [x] The users guide was updated (as applicable).
      _Not applicable._

Backport: ghc-10.0, ghc-9.14 and ghc-9.12 have the same code, and the patch applies cleanly to all three.

@triagers: could you please add ~wasm, so that the wasm jobs run, and ~"backport needed:10.0", ~"backport needed:9.14" and ~"backport needed:9.12"? I can't set labels myself.

[notes]: https://gitlab.haskell.org/ghc/ghc/wikis/commentary/coding-style#comments-in-the-source-code
[adding test]: https://gitlab.haskell.org/ghc/ghc/wikis/building/running-tests/adding
[changelog]: https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/changelog
