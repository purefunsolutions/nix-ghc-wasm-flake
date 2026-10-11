# Hand-off: fix xxHash's WASM SIMD128 `<arm_neon.h>` detection upstream

Written 2026-10-11 by the Claude session that upstreams GHC patch 0004 (`~/ghc-0004`), for a new
Claude session in **`~/xxHash`**. That session has none of this session's memory, so this file is
meant to be self-contained. Line numbers are for xxHash `dev` at `680bf46`; they shift if `dev`
moves.

## Goal

File an issue at [Cyan4973/xxHash](https://github.com/Cyan4973/xxHash) and open a pull request
against **`dev`** that fixes the detection. Prepare everything locally. **The user approves every
outward step** (fork, push, issue, PR, comments).

## Where things are

- **Clone:** `~/xxHash`, `origin` = `https://github.com/Cyan4973/xxHash.git`, branch `dev` at
  `680bf46` ("Merge pull request #1155", 2026-09-20), latest tag `v0.8.4`. Clean working tree.
- **No fork yet:** `github.com/mikatammi/xxHash` gives 404. `gh` 2.102.0 is logged in as
  `mikatammi` (keyring, ssh git protocol, scopes `gist`, `read:org`, `repo`). After the user's OK:
  `gh repo fork Cyan4973/xxHash --clone=false --remote=false`, then
  `git remote add mikatammi git@github.com:mikatammi/xxHash.git` (the same layout as `~/ghc`:
  `origin` upstream over HTTPS, the fork under the user's name).
- **Drafts** go in `~/ghc-wasm-flake/drafts/`, e.g. `xxhash-issue-wasm-arm-neon.md` and
  `xxhash-pr-wasm-arm-neon.md`, next to the GHC drafts. That directory is tracked in git and other
  sessions have uncommitted files there; don't commit anything there without asking.
- **The GHC side:** GHC vendors xxHash 0.8.3 in `rts/xxhash.h`. Its own fix (GHC patch 0004,
  branch `wip/rts-no-xxh3-on-32-bit` in `~/ghc-0004`) defines `XXH_NO_XXH3` in `rts/Hash.c` on
  32-bit platforms, because GHC only uses XXH3 on 64-bit. GHC needs it anyway, for its vendored
  copy and the backports to 9.12/9.14/10.0, so the xxHash fix complements it and doesn't replace
  it. The GHC issue draft is `~/ghc-wasm-flake/drafts/ghc-issue-rts-no-xxh3-on-32-bit.paste.md`.
  It was filed after this hand-off was written, as **#27931**
  (<https://gitlab.haskell.org/ghc/ghc/-/issues/27931>). Link it from the xxHash issue.

## The bug

- **Detection.** Both the include block (`xxhash.h:3870-3893`, the include at `:3879`) and the
  `XXH_VECTOR` auto-selection (`xxhash.h:4004-4013`) use

      (defined(__wasm_simd128__) && XXH_HAS_INCLUDE(<arm_neon.h>)) /* WASM SIMD128 via SIMDe */

  This came with `c9a7470` ("[WASM] Support SIMD128 via XXH_NEON (from EMSDK's SIMDe polyfill)",
  easyaspi314, 2023-03-14), PR #825, merged 2023-07-10 and first released in v0.8.2. The PR
  assumes that any `arm_neon.h` a wasm compiler finds is Emscripten's SIMDe polyfill.
- **Clang has its own.** Clang generates `arm_neon.h` into its resource directory whenever the
  ARM or AArch64 target is built (`clang/lib/Headers/CMakeLists.txt:452-454` at
  `llvmorg-21.1.8`). LLVM builds all targets by default (`llvm/CMakeLists.txt:557`), so most
  clangs have it: distribution clangs, nixpkgs' clang. It begins with
  `#if !defined(__arm__) && !defined(__aarch64__) && !defined(__arm64ec__)` /
  `#error "<arm_neon.h> is intended only for ARM and AArch64 targets"`. So on wasm32 with
  `-msimd128`, `__has_include` is true and the include fails.
- **The escape hatch doesn't work either.** The include block doesn't look at `XXH_VECTOR`, so
  the documented override `-DXXH_VECTOR=XXH_SCALAR` doesn't avoid the include. The constants
  `XXH_SCALAR`...`XXH_RVV` are defined at `xxhash.h:1112-1121`, before the include block.
- **Not affected:**
  - wasi-sdk: it builds LLVM with `-DLLVM_TARGETS_TO_BUILD=WebAssembly`, so it has no
    `arm_neon.h` and xxHash picks the scalar path.
  - Emscripten: its `system/include/compat/arm_neon.h` is an amalgamated SIMDe
    `simde/arm/neon.h` with `SIMDE_ARM_NEON_*_ENABLE_NATIVE_ALIASES`. Emscripten ships **no
    separate `simde/` include directory**, so `__has_include(<simde/arm/neon.h>)` can't replace
    the current check.
- **v0.8.4 has the same code.**
- **No upstream report yet.** Searched 2026-10-11 with `gh search issues --repo Cyan4973/xxHash
  --include-prs` for `arm_neon`, `wasm`, `wasi`, `simd128`, "intended only for ARM",
  `has_include` and `emscripten`. Related only: #824, #825, #960. **Redo the search right before
  filing.**

## Reproduced (2026-10-11, aarch64-darwin)

Compiler: nixpkgs' `pkgsCross.wasm32-wasip1` clang 21.1.8 with wasi-libc 32,
`/nix/store/rs8axglggar8lx30ayf1j2nvfyn6qgwz-wasm32-unknown-wasip1-clang-wrapper-21.1.8/bin/wasm32-unknown-wasip1-cc`.
Two other wrappers with the same name are in the store; they are Linux builds and fail with
`exec format error`. If the store path has been garbage-collected, ask before fetching a new one.

In `~/xxHash` at `680bf46`: `$CC -O2 <flags> -c xxhash.c -o /tmp/<dir>/x.o`. Write the outputs
outside the clone, so it stays clean.

| Flags | Result |
|---|---|
| `-msimd128` | 20 errors, starting with the `#error` (below) |
| `-msimd128 -DXXH_VECTOR=XXH_SCALAR` | 1 error, the same `#error` |
| `-msimd128 -DXXH_NO_XXH3` | compiles |
| (none) | compiles |

    In file included from xxhash.c:42:
    In file included from ./xxhash.h:3879:
    /nix/store/…-wasm32-unknown-wasip1-clang-wrapper-21.1.8/resource-root/include/arm_neon.h:28:2: error: "<arm_neon.h> is intended only for ARM and AArch64 targets"
       28 | #error "<arm_neon.h> is intended only for ARM and AArch64 targets"

## Who else hits it

- **GHC:** its wasm RTS is compiled with `-msimd128`, the flag ghc-wasm-meta recommends. GHC
  issue: see above.
- **haskell.nix** passes `-optc-DXXH_NO_XXH3` for wasm:
  <https://github.com/input-output-hk/haskell.nix/blob/1dde0b46d3daa5bf0ff3ea6332d579a1943b4a0c/compiler/ghc/default.nix#L437>
- **nixpkgs** carries the GHC patch as `ghc-wasm-rts-no-xxh3.patch`. It's on the user's branch
  `ghcwasmhacking`, public at github.com/mikatammi/nixpkgs.

## Fix options (settle with the user; the issue can ask the maintainer)

- **A. Auto-select the SIMDe path only under Emscripten.** Add `defined(__EMSCRIPTEN__)` to both
  conditions.
  - Smallest change. Emscripten and wasi-sdk behave as before.
  - Drawback: a non-Emscripten toolchain with SIMDe's `arm_neon.h` on its include path loses
    NEON. Even `-DXXH_VECTOR=XXH_NEON` wouldn't help, because the include block wouldn't include
    the header any more.
- **B. A, plus an explicit opt-in.** On wasm, the include block also includes `<arm_neon.h>` when
  the user sets `XXH_VECTOR` to `XXH_NEON`. Only the wasm branch changes; ARM's includes stay as
  they are.
  - Other SIMDe setups keep a way in, and `-DXXH_VECTOR=XXH_SCALAR` becomes a working escape
    hatch.
  - Mind `-Wundef`, which the Makefile uses, and `gcc-og-test` adds `-Werror`: write
    `defined(XXH_VECTOR) && XXH_VECTOR == XXH_NEON`.
  - **The previous session's recommendation.**
- **C. All intrinsic includes follow the selected `XXH_VECTOR`.** Cleanest in principle, but it
  touches every architecture's includes. `xxh_x86dispatch.c` includes `xxhash.h` too, though it
  doesn't set `XXH_VECTOR`. Too big for an outside PR unless the maintainer asks for it.

What B should do in each case:

| Setup | Before | After B |
|---|---|---|
| Emscripten, `-msimd128` (auto, or `XXH_VECTOR=XXH_NEON` as in CI) | NEON via SIMDe | unchanged |
| wasi-sdk (no `arm_neon.h`), `-msimd128` | scalar | unchanged |
| clang with ARM targets, `-msimd128` | **error** | scalar |
| clang with ARM targets, `-msimd128 -DXXH_VECTOR=XXH_SCALAR` | **error** | scalar |
| clang with ARM targets, `-msimd128 -DXXH_VECTOR=XXH_NEON`, no SIMDe | error | error (asked for NEON) |
| non-Emscripten with SIMDe's `arm_neon.h`, `-msimd128` | NEON | scalar, unless `XXH_VECTOR=XXH_NEON` |

## Testing

- The table above, before and after the change.
- Native: `make check` is quick. Maybe also `make noxxh3test` and `make gcc-og-test`, which uses
  `-Wundef -Werror` (gcc may not be on this Mac; then `make clangtest`).
- Emscripten: xxHash's CI job `ubuntu-wasm` (`.github/workflows/ci.yml:242-292`, emsdk 3.1.33)
  runs on the PR. It covers the scalar path, `-DXXH_VECTOR=XXH_NEON -msimd128` and asm.js.
  nixpkgs' emscripten would be a big download; ask first.
- Optional regression test: a CI step that compiles `xxhash.c` with Ubuntu's clang (all targets)
  and wasi-libc (`--target=wasm32-wasi --sysroot=/usr/share/wasi-sysroot -msimd128`). Only if
  the user wants it; keep the PR small.

## Upstream conventions (checked 2026-10-11)

- **Who and where:** PRs target `dev`; `release` is only for releases. The maintainer, Yann
  Collet (@Cyan4973), writes most commits and merges.
- **External PRs do get merged,** e.g. #1101 (2026-09-14), #1093, and #1092 "Fix building for
  ARM with GCC < 8" (@mstorsjo, 2026-02-26). #1092 is a similar small build fix and a good style
  reference.
- **Commit subjects** are short and imperative, without an area prefix: "Fix bench sign
  conversion", "Avoid cmp in version check".
- **`CHANGELOG`** is written by the maintainer at release time, crediting "by @user". Don't edit
  it in the PR.
- **No `CONTRIBUTING` file, no AI policy** (checked the README and `.github/`), and no issue or
  PR templates. Follow the user's own rules anyway (below).
- **cc:** maybe @easyaspi314, the author of #825. Ask the user.

## To do

1. **The issue.** Redo the duplicate check, then draft it. Keep it short:
   - disclosure line at the top;
   - what fails, with the repro table and the error;
   - the cause, with permalinks to `dev`'s lines, e.g.
     `https://github.com/Cyan4973/xxHash/blob/680bf46…/xxhash.h#L3877`;
   - the `XXH_VECTOR` escape hatch not working;
   - who hits it (GHC issue link, haskell.nix);
   - the proposed fix, offering to send a PR.

   Show the user the exact text and the exact `gh issue create -R Cyan4973/xxHash --title "…"
   --body-file …` command, and wait for an explicit OK.
2. **Settle the design** (A/B/C) with the user.
3. **Implement on a branch** from `dev` in `~/xxHash`, e.g. `wasm-simd128-neon-detection`. Test,
   then commit with `--no-gpg-sign`: a short subject, a 2-4 line body that ends with
   `Fixes #<issue>.`, and the trailer `Assisted-by: Claude Code (Claude Opus 5.5)`. Name the
   directory and branch when the commit is ready. The user signs it with
   `git commit --amend -s -S --no-edit`.
4. **Fork, push and open the PR,** each step only with the user's OK, after showing the exact
   text and commands: `gh pr create -R Cyan4973/xxHash --base dev --head mikatammi:<branch>
   --title "…" --body-file …`. Afterwards, check through the API that base, head and body are
   what the user approved.
5. **Report back.** Give the user the issue and PR numbers, so that the GHC MR can mention them.
   Ask whether to add an xxHash row to the "Upstream tracker" in `~/ghc-wasm-flake/README.md`.

## Ground rules (the user's standing preferences)

- **Never push, fork, comment or file anything** without the user's explicit go-ahead. First show
  the exact text and command, then wait for an explicit OK. Since 2026-10-11 the user has let
  Claude run `glab`/`gh` for this once they've approved.
- **GPG:** the user signs commits by hand and adds `Signed-off-by` themselves. Commit with
  `--no-gpg-sign` and remind them to sign before any push.
- **AI disclosure everywhere:** a line at the top of the issue and the PR, and an `Assisted-by`
  trailer on every commit. The review sentence in the disclosure ("I have reviewed and revised it
  and take responsibility for it") is the user's to make. Draft it, and remind them to review the
  texts before posting.
- **Small and short:**
  - the smallest correct change;
  - no explanatory multi-line comments: the user removed a 3-line source comment as "slop";
  - commit bodies of 2-4 lines;
  - short, factual prose.

  Put the long reasoning into the issue.
- **Every claim checkable:** cite commit hashes, `file:line` and output you actually produced.
  Say "not tested" where that's the case.
- **Ask before big downloads or long builds.** If the user mentions mobile data roaming: no big
  downloads, `nix … --offline`, and ask before `git fetch`.
- **Shell (zsh) pitfalls:**
  - an unquoted `$var` isn't word-split;
  - `$ref:r…` is read as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status (use `${pipestatus[1]}`);
  - a glob without matches aborts the whole command (quote it, or use `bash -c` with
    `shopt -s nullglob`);
  - `git cherry-pick` has no `-q`.
