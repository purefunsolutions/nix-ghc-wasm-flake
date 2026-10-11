# Hand-off: upstream GHC patch 0003 (`<wasi/api.h>` in wasm JSFFI.c)

Written 2026-10-11 for a new Claude session in `~/ghc`. That session won't see the previous
sessions' memory, so this file is meant to be self-contained. The sibling hand-off for patch 0005
(now GHC !16791) is `handoff-ghc-patch-0005.md`.

## Goal

Turn patch 0003, "rts: include <wasi/api.h> in wasm JSFFI.c", into a GHC merge request against
master, with backports to `ghc-10.0`, `ghc-9.14` and `ghc-9.12`. Prepare everything locally. **The
user pushes and opens the MR, after GPG-signing the commit by hand.**

## Where things are

- `~/ghc`: full GHC clone with submodules. Branch **`wip/rts-wasm-jsffi-wasi-api`** is
  `origin/master` (`e7cacf59b8`, 2026-10-09) plus one commit, `acc7b6277f`. That commit still has
  the long draft message and the old trailer; it needs the polish below.
- **Don't touch the other `wip/*` branches.** `wip/rts-static-lib-dirs` is the user's open
  !16791. If another Claude session is still working in `~/ghc`, do this in a separate worktree
  (`git -C ~/ghc worktree add ~/ghc-0003 wip/rts-wasm-jsffi-wasi-api`) so the two sessions don't
  switch branches under each other.
- The same patch as a file: `~/ghc-wasm-flake/upstream/ghc/0003-rts-include-wasi-api.h-in-wasm-JSFFI.c.patch`.
  nixpkgs carries it as `pkgs/development/compilers/ghc/ghc-wasm-rts-include-wasi-api.patch` in
  `~/nixpkgs-ghcwasm.git`, branch `ghcwasmhacking` (public at github.com/mikatammi/nixpkgs),
  applied for every wasi target.
- Project docs: `~/ghc-wasm-flake` (branch `initial`). Drafts go in `~/ghc-wasm-flake/drafts/`.

## The change

One added line in `rts/wasm/JSFFI.c`:

```c
#include <wasi/api.h>
```

## Root cause and evidence

- `rts/wasm/JSFFI.c` calls `__wasi_args_sizes_get()` and `__wasi_args_get()` and uses
  `__wasi_errno_t`, without including `<wasi/api.h>`. It relied on other libc headers pulling
  that in.
- wasi-libc 32 (wasi-sdk 32) moved the WASI preview 1 API into `<wasi/wasip1.h>`, which
  `<wasi/api.h>` selects. Only `<sys/socket.h>` still includes it transitively, so with stock
  wasi-libc 32 the RTS doesn't compile:

  ```
  rts/wasm/JSFFI.c:100:3: error: use of undeclared identifier '__wasi_errno_t'
  ```

- `JSFFI.c` is the only GHC source file that uses the WASI API directly (checked in 9.12.5-rc3,
  9.14.1 and the 10.1 snapshot).
- **Why GHC's CI doesn't see it:** its wasm jobs use ghc-wasm-meta's toolchain, a fork based on
  wasi-sdk 29, whose libc still includes the header more widely. GHC hits this as soon as it moves
  to a newer wasi-libc. The include is harmless with older ones.
- **Verified:** nixpkgs builds wasm GHC 9.12, 9.14 and HEAD with this patch, using stock LLVM 21
  and wasi-libc 32, on aarch64-darwin, aarch64-linux and x86_64-linux. All of them build and run
  their tests under wasmtime.
- **Scope:** `master`, `ghc-10.0`, `ghc-9.14` and `ghc-9.12` all lack the include, and the patch
  applies to all four (to the release branches with small line offsets).
- **No existing issue or MR.** Searched GitLab on 2026-10-10 for `wasi/api.h`,
  `__wasi_errno_t` and `JSFFI.c`.

## To do

1. **Check master.** `rts/wasm/JSFFI.c` may have changed since 2026-10-09. The user is on mobile
   data roaming, so **ask before `git fetch`** (a day of GHC commits is small, but ask anyway).
2. **Decide with the user** whether to file a GHC issue first. !16791 had one (#27926). For a
   one-line build fix the MR alone may be enough, but GHC often prefers "Fixes #NNNN".
3. **Polish the commit to match !16791:** a compact message, then the trailers
   `Assisted-by: Claude Code (Claude Opus 5.5)` and
   `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`. For example:

   ```
   rts: include <wasi/api.h> in wasm JSFFI.c

   JSFFI.c uses the WASI preview 1 API (__wasi_errno_t, __wasi_args_get)
   without including <wasi/api.h>. wasi-libc >= 32 no longer pulls it in
   through other headers, so the wasm RTS fails to compile:

       rts/wasm/JSFFI.c:100:3: error: use of undeclared identifier '__wasi_errno_t'
   ```

4. **Test without big downloads.** A minimal C reproducer with nixpkgs' wasm compiler (already in
   the local store) shows the cause directly:

   ```sh
   cc=$(nix build --no-link --print-out-paths \
     "git+file:///Users/mika/nixpkgs-ghcwasm.git?ref=ghcwasmhacking#pkgsCross.wasm32-wasip1.stdenv.cc")/bin/wasm32-unknown-wasip1-cc
   printf '#include <stdlib.h>\n__wasi_errno_t f(void) { return 0; }\n' > t.c && $cc -c t.c           # fails
   printf '#include <wasi/api.h>\n__wasi_errno_t f(void) { return 0; }\n' > t.c && $cc -c t.c         # works
   ```

   A full wasm GHC build from this branch isn't needed: the nixpkgs builds above already cover
   the patch.
5. **Changelog:** read `.gitlab/merge_request_templates/Default.md` (a `changelog.d/` entry for
   user-facing changes, otherwise the `no-changelog` label). !16791 had no entry. A wasm build fix
   is probably `no-changelog`; ask the user.
6. **Draft the MR description** into `~/ghc-wasm-flake/drafts/`. Follow !16791's shape: start
   with the P3 disclosure line, then the template's "Changes contained in this patch" section.
   The !16791 disclosure:

   > _LLM assistance: Claude Code (Claude Opus 5.5) was used while preparing this contribution:
   > for the investigation, the testing, and drafts of the commit message and this description. I
   > have carefully reviewed and revised the submitted material and take responsibility for it
   > under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

   Mention the backport wish (10.0, 9.14, 9.12) and suggest the `wasm` label, so the wasm CI jobs
   run.
7. **Stop before pushing.** Remind the user to GPG-sign; they push to their fork on
   gitlab.haskell.org and open the MR.
8. **After the MR exists**, add it to the "Upstream tracker" table in `~/ghc-wasm-flake/README.md`,
   replacing the "not submitted yet" row. Commit there with that repo's trailers
   (`Assisted-by: Claude Code (Claude Opus 5.5)` and `Signed-off-by: Mika Tammi <mikatammi@gmail.com>`).

## Ground rules (the user's standing preferences)

- **Never push or post anything** (GitLab, GitHub, Matrix) without the user's explicit go-ahead.
- **GPG:** the user signs commits by hand. Always remind them before any push or MR.
- **GHC's AI policy** (wiki: contributing/AI): an `Assisted-by` line on every commit, a disclosure
  at the top of every issue and MR, and GHC recommends that people write the final texts
  themselves. So draft for the user to review and rework, rather than presenting final prose.
- **Roaming:** no big downloads, and ask before fetching.
- **Commit messages:** compact, in nixpkgs style.
- **Shell (zsh) pitfalls:**
  - an unquoted `$var` isn't word-split;
  - `$ref:r…` is read as a modifier (use `${ref}`);
  - `cmd | tail` hides `cmd`'s exit status;
  - `git cherry-pick` has no `-q`.
