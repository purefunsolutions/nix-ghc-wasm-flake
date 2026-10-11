# Hand-off: upstream GHC patch 0004 (don't compile XXH3 on 32-bit platforms)

Written 2026-10-11 for a new Claude session in `~/ghc`, the third in parallel. The wasip1 patch
(`handoff-ghc-patch-0001.md`) and the haddock cross-build issue
(`handoff-ghc-haddock-cross-regression.md`) are being worked on at the same time. This file is
meant to be self-contained. Earlier patches from this project are GHC !16791 (#27926) and !16794
(#27929); their finished texts are the `drafts/ghc-*rts-*.paste.md` files.

**Use the `ghc-contribution` skill**: issue first, the smallest correct change, GHC's LLM policy,
commit linting, and `glab` with `GITLAB_HOST=gitlab.haskell.org`.

## Goal

Turn patch 0004 into a GHC issue plus a merge request against master, with backports to
`ghc-10.0`, `ghc-9.14` and `ghc-9.12`. Prepare everything locally. **The user files the issue,
pushes and opens the MR, after GPG-signing the commit by hand.**

## Where things are

- **Work in your own worktree.** Other sessions use `~/ghc`, and switching branches there would
  pull the ground from under them:

      git -C ~/ghc worktree add ~/ghc-0004 wip/rts-no-xxh3-on-32-bit

- Branch **`wip/rts-no-xxh3-on-32-bit`** is `origin/master` (`e7cacf59b8`; master hadn't moved
  when fetched on 2026-10-11) plus one commit, `3ec796bb61`. That commit still has the long draft
  message, the old trailer and a three-line code comment.
- Don't touch the other `wip/*` branches: !16791, !16794 and the wasip1 work.
- The patch as a file: `~/ghc-wasm-flake/upstream/ghc/0004-rts-don-t-compile-XXH3-on-32-bit-platforms.patch`.
  nixpkgs carries it as `ghc-wasm-rts-no-xxh3.patch` in `~/nixpkgs-ghcwasm.git` (branch
  `ghcwasmhacking`, public at github.com/mikatammi/nixpkgs) for every wasi target.

## The change

In `rts/Hash.c`, before `#define XXH_INLINE_ALL` and `#include "xxhash.h"`:

```c
#if WORD_SIZE_IN_BITS != 64
#define XXH_NO_XXH3
#endif
```

The branch currently also has a three-line comment above the define. Per the skill's
smallest-change rule, drop it or cut it to one short line; the reasoning goes into the issue and
the commit message.

## Why it's needed

- **XXH3 is dead code on 32-bit platforms.** `hashBuffer` (`rts/Hash.c:88`) uses
  `XXH3_64bits_withSeed` only when `WORD_SIZE_IN_BITS == 64`, and `XXH32` otherwise.
- **On wasm32 it also breaks the build.** GHC compiles the wasm RTS with `-msimd128` (part of
  upstream's recommended `CONF_CC_OPTS`), so `__wasm_simd128__` is defined. The vendored
  xxhash 0.8.3 then includes `<arm_neon.h>` whenever it can find one (`rts/xxhash.h:3850-3852`,
  "WASM SIMD128 via SIMDe"). It expects SIMDe's NEON emulation, as Emscripten provides. A clang
  built with ARM targets, like most distribution clangs including nixpkgs', ships its own
  `arm_neon.h`, which rejects wasm:

  ```
  rts/xxhash.h:3852: arm_neon.h:28:2: error: "<arm_neon.h> is intended only for ARM and AArch64 targets"
  ```

- **Why GHC's CI doesn't hit it:** its wasm jobs use wasi-sdk's clang. That's most likely built
  for wasm only, without ARM headers. Unverified, so word it carefully.
- **Others hit it too:** haskell.nix works around the same problem by passing `-DXXH_NO_XXH3`
  globally.
- **Verified:** nixpkgs builds wasm GHC 9.12, 9.14 and HEAD with this patch (stock LLVM 21 and
  wasi-libc 32) on aarch64-darwin, aarch64-linux and x86_64-linux. All build and pass their tests
  under wasmtime.
- **Scope:** `rts/Hash.c` and `rts/xxhash.h` are the same on `master`, `ghc-10.0`, `ghc-9.14` and
  `ghc-9.12`, and the patch applies to all four.
- **Duplicate check** (2026-10-11): `XXH_NO_XXH3` only matches #19948 (FreeBSD duplicate
  symbols, 2021, unrelated); `arm_neon.h` only matches #26907 (unrelated); "xxhash wasm" matches
  nothing. **Redo it right before filing.**

## Design questions (for the user)

1. **Condition:** `WORD_SIZE_IN_BITS != 64`, matching `hashBuffer`'s own condition (dead code
   on every 32-bit platform), or wasm only (`wasm32_HOST_ARCH`)? The first is the patch as it
   stands and is easy to justify. A reviewer might prefer the narrower scope.
2. **The root cause is in xxHash's detection:** an `<arm_neon.h>` being findable isn't proof that
   it's SIMDe. Reporting that to xxHash upstream (Cyan4973/xxHash) would be a separate, optional
   follow-up. Editing GHC's vendored `xxhash.h` isn't the way.

## To do

1. **Duplicate check** with the skill (glab). Then **draft the issue** (`references/issue.md`):
   "The wasm RTS doesn't compile with clangs that ship arm_neon.h", with the error, the cause,
   the affected branches and the haskell.nix workaround as a data point. The user files it and
   tells you the number.
2. **Settle the design questions** with the user.
3. **Polish the commit** (`references/commit.md`, then `scripts/ghc-lint-commit.py`):
   - the subject `rts: don't compile XXH3 on 32-bit platforms` is 43 characters, fine;
   - a compact body, then `Fixes #N.` and the trailers
     `Assisted-by: Claude Code (Claude Opus 5.5)` and
     `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`.
4. **Test without a full build** (`references/testing.md` covers compiling one RTS file for a
   cross target). Compile `rts/Hash.c` from master with nixpkgs' wasm clang (already in the
   store), `-msimd128` and the RTS include paths, the same way the 0003 session compiled
   `rts/wasm/JSFFI.c`: it should fail on master and compile with the patch. The nixpkgs builds
   count as the full-build evidence. Ask before any long build.
5. **Changelog:** !16791 and !16794 both got a `changelog.d/` entry. This is a build fix for some
   toolchains; ask the user whether to add one or ask for ~"no-changelog".
6. **Draft the MR description** (`references/merge-request.md`): start with the P3 disclosure,
   mention the backports (10.0, 9.14, 9.12), and ask `@triagers` for ~wasm.
7. **Stop before pushing.** Remind the user to GPG-sign; they push and open the MR.
8. **After the MR exists**, update the XXH3 row in the "Upstream tracker" in
   `~/ghc-wasm-flake/README.md`. Commit there with `Assisted-by: Claude Code (Claude Opus 5.5)`
   and `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`.

## Ground rules (the user's standing preferences)

- **Never push, comment or file anything** without the user's explicit go-ahead.
- **GPG:** the user signs commits by hand. Always remind them before any push or MR.
- **GHC's LLM policy:** disclosure at the top of issues and MRs, an `Assisted-by` line on every
  commit, short prose. Draft for the user to review and rework.
- **Ask before big downloads or long builds**, and avoid them entirely if the user mentions mobile
  data roaming.
- **Shell (zsh) pitfalls:**
  - an unquoted `$var` isn't word-split;
  - `$ref:r…` is read as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status;
  - `git cherry-pick` has no `-q`.
