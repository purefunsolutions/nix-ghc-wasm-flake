_LLM assistance: Claude Code (Claude Opus 5.5) was used while preparing this contribution: for the investigation, the testing, and drafts of the commit message, the changelog entry and this description. I have carefully reviewed and revised the submitted material and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

Fixes #27931.

## Changes contained in this patch

`rts/Hash.c` now defines `XXH_NO_XXH3` unless `WORD_SIZE_IN_BITS` is 64, the condition under which `hashBuffer` uses XXH3. On 32-bit platforms `hashBuffer` uses `XXH32`, so XXH3 was dead code there. On wasm32 with `-msimd128`, XXH3 also includes `<arm_neon.h>` whenever clang has one, which fails with a clang that has ARM targets (see #27931). On 64-bit platforms nothing changes. There's also a changelog entry.

xxHash 0.8.4 (!16708) has the same check, so the bump doesn't make this redundant. The two MRs don't touch the same file. I've reported the check upstream as [xxHash#1165](https://github.com/Cyan4973/xxHash/issues/1165).

### Testing

- With nixpkgs' clang 21.1.8 for wasm32-wasip1 (aarch64-darwin) and ghc-wasm-meta's `CONF_CC_OPTS_STAGE2`, compiling `rts/Hash.c` from master (e7cacf59b8) with the RTS's include paths and `-DCOMPILING_RTS` gives 20 errors, starting with `"<arm_neon.h> is intended only for ARM and AArch64 targets"`. With this patch it compiles, and the object file is identical to master's compiled with `-DXXH_NO_XXH3`. Without `-msimd128`, the object file is the same with and without the patch.
- nixpkgs carries this patch for its wasm GHC 9.12, 9.14 and HEAD builds, with stock LLVM 21 and wasi-libc 32. They build on aarch64-darwin, aarch64-linux and x86_64-linux, and their tests pass under wasmtime.
- With ~wasm, GHC's wasm jobs build it with wasi-sdk's clang, which is built for WebAssembly only (see #27931). I haven't built it for other 32-bit platforms, and the i386 jobs don't run by default.

## MR Checklist

- [x] This MR solves the problem described in the following issue: #27931
- [x] A changelog entry was added in `changelog.d/` for user-facing changes (see [changelog guide][changelog]).
      If this MR does not need a changelog entry, the ~"no-changelog" label was applied.
- [x] This MR does not make any significant changes to `base`, or it has an accompanying [CLC proposal](https://github.com/haskell/core-libraries-committee#base-package).
- [x] If this MR has the potential to break user programs, the ~"user-facing" label was applied to
      test against head.hackage.
      _Not applicable: it only leaves unused code out of the RTS on 32-bit platforms._
- [x] All commits are either individually buildable or squashed.
      _One commit._
- [ ] After all approvals and before landing: all fixup commits are squashed with their originating commits.
- [x] Commit messages describe *what they do*, referring to tickets using `#NNNNN` syntax.
- [x] Source comments describing the change were added. For larger changes [notes][notes] and
      cross-references from the relevant places were added (as applicable).
      _Not applicable to a three-line `#define`._
- [ ] [Testcases to the testsuite][adding test] were added (as applicable).
      _None: CI's clang is built for WebAssembly only, so no CI job can trigger this._
- [x] The users guide was updated (as applicable).
      _Not applicable._

Backport: ghc-10.0, ghc-9.14 and ghc-9.12 have the same code, and the patch applies cleanly to all three.

@triagers: could you please add ~wasm, so that the wasm jobs run, and ~"backport needed:10.0", ~"backport needed:9.14" and ~"backport needed:9.12"? I can't set labels myself.

[notes]: https://gitlab.haskell.org/ghc/ghc/wikis/commentary/coding-style#comments-in-the-source-code
[adding test]: https://gitlab.haskell.org/ghc/ghc/wikis/building/running-tests/adding
[changelog]: https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/changelog
