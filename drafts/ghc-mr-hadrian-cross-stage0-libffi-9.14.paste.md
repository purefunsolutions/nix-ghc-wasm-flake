Title: [ghc-9.14] hadrian: no target libffi for cross stage0 ghci (#NNNNN)
Target branch: ghc-9.14

_LLM assistance: Claude Code (Claude Opus 5.5) was used while preparing this contribution: for the investigation, the testing, and drafts of the commit message and this description. I have carefully reviewed and revised the submitted material and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

Fixes #NNNNN.

## Changes contained in this patch

One line in `hadrian/src/Settings/Packages.hs`: the `ghci` package now gets configure's libffi dirs only when it isn't stage0 of a cross build (`orM [notStage0, notCross]`). Those dirs are the target's, but a cross build's stage0 is built for the build platform (see #NNNNN). Native builds, and stage 1 onwards, get the same flags as before.

Master doesn't need this: since 23c9b6c392, a cross build reads stage0's libffi dirs from `hadrian/cfg/system.config.host`, which leaves them empty. That commit is part of a large rework, so this MR targets ghc-9.14 directly, like the ones for ghc-10.0 and ghc-9.12.

### Testing

- Without the fix, a wasm32-wasi cross build of 9.14.1 on x86_64-linux fails to link the stage1 compiler (log in #NNNNN).
- nixpkgs builds its wasm GHC 9.12 and 9.14 with this fix on aarch64-darwin, aarch64-linux and x86_64-linux, and their tests pass under wasmtime. nixpkgs spells the condition `expr (notM cross)`, which is how `notCross` is defined (`hadrian/src/Expression.hs:169-170`).
- [PENDING] nixpkgs' wasm GHC HEAD (556db2f32f, which has 23c9b6c392) builds and passes its test on x86_64-linux without the fix.
- Hadrian builds with this commit on ghc-10.0, ghc-9.14 and ghc-9.12 (nixpkgs' `make-hadrian.nix` with GHC 9.10.3, x86_64-linux).
- CI can't trigger the bug, because no CI job passes `--with-ffi-*` to a cross build. The wasm jobs take libffi-wasm from the wasi-sdk sysroot ([ghc-wasm-meta's `setup.sh`](https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta/-/blob/e56b33ce9104/setup.sh#L117-118)), so their libffi dirs are empty.

## MR Checklist

- [x] This MR solves the problem described in the following issue: #NNNNN
- [ ] A changelog entry was added in `changelog.d/` for user-facing changes (see [changelog guide][changelog]).
      If this MR does not need a changelog entry, the ~"no-changelog" label was applied.
      _No entry, since release branches don't check for one. I can add one if the release notes should mention this._
- [x] This MR does not make any significant changes to `base`, or it has an accompanying [CLC proposal](https://github.com/haskell/core-libraries-committee#base-package).
- [x] If this MR has the potential to break user programs, the ~"user-facing" label was applied to
      test against head.hackage.
      _Not applicable: build system only._
- [x] All commits are either individually buildable or squashed.
      _One commit._
- [ ] After all approvals and before landing: all fixup commits are squashed with their originating commits.
- [x] Commit messages describe *what they do*, referring to tickets using `#NNNNN` syntax.
- [x] Source comments describing the change were added. For larger changes [notes][notes] and
      cross-references from the relevant places were added (as applicable).
      _One line._
- [ ] [Testcases to the testsuite][adding test] were added (as applicable).
      _None: CI can't trigger this (see Testing)._
- [x] The users guide was updated (as applicable).
      _Not applicable._

@triagers: could you please add ~hadrian? I can't set labels myself.

[notes]: https://gitlab.haskell.org/ghc/ghc/wikis/commentary/coding-style#comments-in-the-source-code
[adding test]: https://gitlab.haskell.org/ghc/ghc/wikis/building/running-tests/adding
[changelog]: https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/changelog
