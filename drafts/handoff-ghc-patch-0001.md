# Hand-off: upstream GHC patch 0001 (accept `wasm32-*-wasip1` target triples)

Written 2026-10-11 for a new Claude session in `~/ghc`. That session won't see the previous
sessions' memory, so this file is meant to be self-contained. Earlier patches from this project
are GHC !16791 (#27926) and !16794 (#27929); their hand-offs are `handoff-ghc-patch-0005.md` and
`handoff-ghc-patch-0003.md`, and their finished texts are the `drafts/ghc-*rts-*.paste.md` files.

**Use the `ghc-contribution` skill.** It holds the workflow and the rules: issue first,
the smallest correct change, GHC's LLM policy, commit linting, labels and backports, and using
`glab` with `GITLAB_HOST=gitlab.haskell.org`.

## Goal

Turn patch 0001 into a GHC issue plus a merge request against master, with backports to
`ghc-10.0`, `ghc-9.14` and `ghc-9.12`. Prepare everything locally. **The user files the issue,
pushes and opens the MR, after GPG-signing the commit by hand.**

## Where things are

- `~/ghc`: full GHC clone with submodules. Branch **`wip/wasm-accept-wasip1`** is `origin/master`
  (`e7cacf59b8`; master hadn't moved when fetched on 2026-10-11) plus one commit, `580fda2d80`.
  That commit still has the long draft message, the old trailer and a subject that's too long.
- **Don't touch the other `wip/*` branches.** `wip/rts-static-lib-dirs` is !16791 and
  `wip/rts-wasm-jsffi-wasi-api` is !16794. If another Claude session is working in `~/ghc`, use
  a separate worktree (`git -C ~/ghc worktree add ~/ghc-0001 wip/wasm-accept-wasip1`).
- The patch as a file: `~/ghc-wasm-flake/upstream/ghc/0001-configure-accept-wasip1-as-the-OS-part-of-WASI-target-triples.patch`.
  nixpkgs carries it as `ghc-wasm-accept-wasip1.patch` in `~/nixpkgs-ghcwasm.git`
  (branch `ghcwasmhacking`, public at github.com/mikatammi/nixpkgs) for every wasi target.
- An old draft MR text from 2026-10-09 is `~/ghc-wasm-flake/drafts/ghc-mr-wasip1.md`. It's
  outdated (no issue, no disclosure, too long); use it only for facts.

## The change (three files)

- `m4/ghc_convert_os.m4`: `wasi)` becomes `wasi|wasip1)`, so configure's OS is `wasi` either way.
- `utils/ghc-toolchain/src/GHC/Toolchain/ParseTriple.hs`: `"wasip1" -> pure OSWasi`.
- `m4/ghc_llvm_target.m4`: keep `wasip1` in the LLVM target triple, which configure passes to the
  C compiler via `--target`.

GHC's target platform stays `wasm32-unknown-wasi`; Cabal sees `Wasi`, as before.

## Why it's needed

- **The failure:** configuring a cross compiler for `wasm32-unknown-wasip1` (nixpkgs' wasm
  triple) stops with `Unknown OS wasip1`. `GHC_CONVERT_OS` and ghc-toolchain only know `wasi`.
  This is so on master, `ghc-10.0`, `ghc-9.14` and `ghc-9.12`.
- **Upstream toolchains are moving to `wasip1`:**
  - wasi-sdk removed the `wasm32-wasi` target names in version 34 (wasi-sdk#637). The
    haskell-wasm fork reverts that removal, which is why GHC's CI doesn't notice.
  - LLVM 22+ warns on `wasm32-wasi` (llvm#165345).
  - So GHC needs this to use current upstream wasi-sdk or LLVM.
- **Why the LLVM target hunk:** without it, clang gets `--target=wasm32-unknown-wasi`. With
  nixpkgs' toolchain it then looks for compiler-rt in `lib/wasm32-unknown-wasi/`, while compiler-rt
  lives under `wasm32-unknown-wasip1`. The RTS configure then fails with "C compiler cannot create
  executables". `GHC_LLVM_TARGET` already keeps the OS for `*-android*` and `*-gnueabi*`
  triples, and this does the same for `wasip1`.
- **ghc-toolchain:** configure runs it, but its failure is non-fatal ("For now, we don't 'exit'
  even if ghc-toolchain fails", `m4/ghc_toolchain.m4:56` in 9.12/9.14). Check on master whether
  that's still so, and whether the ParseTriple hunk is needed for the smallest correct change or
  only for consistency.
- **Verified:** nixpkgs builds wasm GHC 9.12, 9.14 and HEAD with this patch (stock LLVM 21 and
  wasi-libc 32) on aarch64-darwin, aarch64-linux and x86_64-linux. All build and pass their
  tests under wasmtime.
- **Duplicate check:** done 2026-10-11 with the skill's search for `wasip1`. The only hits are
  #27929 / !16794, which mention wasip1 in passing, and the old closed draft !15157. **Redo it
  right before filing.**

## Design questions (for the user to settle, ideally with Cheng Shao in person)

1. Accepting `wasip1` as an alias of `wasi`, with GHC's platform staying `wasm32-unknown-wasi`:
   fine as is?
2. The LLVM target triple. The patch keeps `wasip1` only when the user asked for it. A
   forward-looking alternative normalizes to `wasm32-unknown-wasip1` for `wasi` too, since
   upstream dropped `wasm32-wasi`. That's a bigger change, though: CI's toolchain is configured
   for `wasm32-wasi`.
3. `wasip2` is a different ABI and stays out of scope.

## To do

1. **Duplicate check** (skill step 1). Then **draft the issue** (`references/issue.md`): "configure
   rejects `wasm32-*-wasip1` target triples". It needs the reproduction, the configure output,
   the affected branches and the upstream-toolchain context. The user files it and tells you the
   number.
2. **Settle the design questions** with the user before polishing.
3. **Polish the commit** (`references/commit.md`, then `scripts/ghc-lint-commit.py`):
   - the subject must be at most 50 characters; the current one is 62. For example,
     `configure: accept wasip1 in WASI target triples` (47);
   - a compact body, then `Fixes #N.` and the trailers
     `Assisted-by: Claude Code (Claude Opus 5.5)` and
     `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`;
   - trim the code comments to the minimum (skill rule 4).
4. **Test** (`references/testing.md`). Ask before long builds.
   - At the configure level: run `./boot` and `./configure --target=wasm32-unknown-wasip1`
     with nixpkgs' wasm toolchain (already in the store), on master and on the branch. Master
     should fail with "Unknown OS wasip1"; the branch should configure, with target platform
     `wasm32-unknown-wasi` and an LLVM target of `wasm32-unknown-wasip1`.
   - The nixpkgs builds above count as the full-build evidence.
5. **Changelog:** probably a `changelog.d/` entry, since this makes `wasip1` triples work, which is
   user-visible. !16791 and !16794 both got one. Ask the user.
6. **Draft the MR description** (`references/merge-request.md`): start with the P3 disclosure,
   mention the backports (10.0, 9.14, 9.12), and ask `@triagers` for ~wasm so the wasm CI jobs
   run.
7. **Stop before pushing.** Remind the user to GPG-sign; they push and open the MR.
8. **After the MR exists**, update its row in the "Upstream tracker" in
   `~/ghc-wasm-flake/README.md`. Commit there with `Assisted-by: Claude Code (Claude Opus 5.5)`
   and `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`.

## Ground rules (the user's standing preferences)

- **Never push, comment or file anything** without the user's explicit go-ahead.
- **GPG:** the user signs commits by hand. Always remind them before any push or MR.
- **GHC's LLM policy:** disclosure at the top of issues and MRs, an `Assisted-by` line on every
  commit, short prose. Draft for the user to review and rework.
- **Ask before big downloads or long builds**, and if the user mentions mobile data roaming,
  avoid them entirely.
- **Shell (zsh) pitfalls:**
  - an unquoted `$var` isn't word-split;
  - `$ref:r…` is read as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status;
  - `git cherry-pick` has no `-q`.
