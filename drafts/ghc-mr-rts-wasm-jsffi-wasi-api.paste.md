_LLM assistance: Claude Code (Claude Opus 5.5) was used while preparing this contribution: for the investigation, the testing, and drafts of the commit message, the changelog entry and this description. I have carefully reviewed and revised the submitted material and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

Fixes #27929.

## Changes contained in this patch

`rts/wasm/JSFFI.c` now includes `<wasi/api.h>`, which declares the WASI preview 1 API it uses (`__wasi_errno_t`, `__wasi_args_sizes_get()`, `__wasi_args_get()`). Before, it relied on other libc headers to include it. In wasi-libc 32, none of the headers it includes do, so the wasm RTS doesn't compile (see #27929). Where the header is already included indirectly, as with CI's wasi-libc, nothing changes. There's also a changelog entry.

### Testing

- With clang 21.1.8 and wasi-libc 32 (nixpkgs' `pkgsCross.wasm32-wasip1` toolchain, aarch64-darwin), compiling `rts/wasm/JSFFI.c` from master (e7cacf59b8) with the RTS's include paths and `-DCOMPILING_RTS` gives 9 errors, starting with `use of undeclared identifier '__wasi_errno_t'`. With this patch, it compiles.
- nixpkgs carries this patch for its wasm GHC 9.12, 9.14 and HEAD builds, with stock LLVM 21 and wasi-libc 32. They build on aarch64-darwin, aarch64-linux and x86_64-linux, and their tests pass under wasmtime.
- With ~wasm, GHC's wasm jobs build it with ghc-wasm-meta's wasi-sdk.

## MR Checklist

- [x] This MR solves the problem described in the following issue: #27929
- [x] A changelog entry was added in `changelog.d/` for user-facing changes (see [changelog guide][changelog]).
      If this MR does not need a changelog entry, the ~"no-changelog" label was applied.
- [x] This MR does not make any significant changes to `base`, or it has an accompanying [CLC proposal](https://github.com/haskell/core-libraries-committee#base-package).
- [x] If this MR has the potential to break user programs, the ~"user-facing" label was applied to
      test against head.hackage.
      _Not applicable: it only adds an include to the wasm RTS._
- [x] All commits are either individually buildable or squashed.
      _One commit._
- [ ] After all approvals and before landing: all fixup commits are squashed with their originating commits.
- [x] Commit messages describe *what they do*, referring to tickets using `#NNNNN` syntax.
- [x] Source comments describing the change were added. For larger changes [notes][notes] and
      cross-references from the relevant places were added (as applicable).
      _Not applicable to an added include._
- [ ] [Testcases to the testsuite][adding test] were added (as applicable).
      _None: CI's wasi-libc includes the header indirectly, so no CI job can trigger this._
- [x] The users guide was updated (as applicable).
      _Not applicable._

Backport: ghc-10.0, ghc-9.14 and ghc-9.12 have the same code, and the patch applies cleanly to all three.

@triagers: could you please add ~wasm, so that the wasm jobs run, and ~"backport needed:10.0", ~"backport needed:9.14" and ~"backport needed:9.12"? I can't set labels myself.

[notes]: https://gitlab.haskell.org/ghc/ghc/wikis/commentary/coding-style#comments-in-the-source-code
[adding test]: https://gitlab.haskell.org/ghc/ghc/wikis/building/running-tests/adding
[changelog]: https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/changelog
