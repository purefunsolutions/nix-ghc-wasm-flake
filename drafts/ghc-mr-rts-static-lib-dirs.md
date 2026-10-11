# Draft: GHC issue and merge request: RTS static library dirs (patch 0005)

Status: **issue filed as #27926; MR not opened yet.** Branch `wip/rts-static-lib-dirs` in `~/ghc`:
commit `cfd9b9b6af` (signed, pushed to the fork) on master `e7cacf59b8`, only the one-line
deletion (the user removed the source comment). Its message still needs the short final version.
The patch is identical to the original
[`../upstream/ghc/0005-…patch`](../upstream/ghc/0005-rts-don-t-restrict-the-RTS-s-static-library-dirs-to-libffi-s.patch),
which nixpkgs carries. Tested; see below.

## GHC's LLM policy

[GHC Policy on LLM contributions](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)
covers tickets, MRs, commits and reviews. What it means here:

- **P4 (declare):** a disclosure at the top of the issue and the MR description, and an
  `Assisted-By: <tool>` line in the commit. GHC commits use both `Assisted-by: Claude Opus 5` and
  `Assisted-By: OpenAI Codex`; ours is `Assisted-by: Claude Code (Claude Opus 5.5)`.
- **P3 (authorship):** you must be able to explain every line and sentence. The facts and their
  sources are listed at the end.
- **R1 (write it yourself):** a strong recommendation, not a requirement. The one-line fix is the
  exception R1 itself names. For the texts (message, comment, issue, MR), GHC prefers that you
  write the final version. Treat the texts below as notes to rewrite from, or review every
  sentence before adopting it.
- **P1:** in review discussions, answer in your own words.

Likely reviewer: @maerwald (Julian Ospald), who wrote the regressing commits. He maintains GHCup,
which doesn't accept LLM-generated code. On ghc-devs (July 2026) he defended GHC's disclosure
rules as protecting both contributors and reviewers. A clear disclosure and your own wording will
count.

## Steps

Done: issue #27926 filed (`ghc-issue-rts-static-lib-dirs.paste.md`), commit `cfd9b9b6af` pushed.

1. Shorten the message (`ghc-mr-rts-static-lib-dirs.commit-msg.final.txt`: 47-character
   subject, four-line body, `Fixes #27926.`), re-sign and push. `-s` re-adds `Signed-off-by` after
   `Assisted-by`.

   ```sh
   cd ~/ghc   # on wip/rts-static-lib-dirs
   git commit --amend -s -S -F ~/ghc-wasm-flake/drafts/ghc-mr-rts-static-lib-dirs.commit-msg.final.txt
   git show -s --show-signature
   git push --force-with-lease mikatammi wip/rts-static-lib-dirs
   ```

2. Open the MR from `mikatammi/ghc` `wip/rts-static-lib-dirs` against **`ghc/ghc` `master`**. Use
   the title `rts: don't restrict static lib dirs to libffi's (#27926)` and paste the description
   from `ghc-mr-rts-static-lib-dirs.paste.md`. Keep "Allow commits from members who can merge"
   on, because marge-bot pushes its rebase to the fork.
3. Labels ~"no-changelog" and ~"backport needed:10.0": only project members can set them. The
   description's last line asks @triagers, and the issue asks for the 10.0.1 milestone. Without
   ~"no-changelog", the `lint-changelog` job fails.
4. GHC asks for at least 24 h between opening an MR and assigning it to marge-bot.

---

## Issue

**Title:** RTS's `library-dirs-static` lacks libnuma/libdw/libzstd dirs with `--with-ffi-libraries`

(Paste-ready description: `ghc-issue-rts-static-lib-dirs.paste.md`.)

**Description:**

_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this
report. I have carefully reviewed and revised it and take responsibility for it under (P3)._

## Summary

If GHC is configured with `--with-system-libffi --with-ffi-libraries=DIR`, the registered `rts`
package has `DIR` in `library-dirs-static`, but not the directories hadrian passes for libnuma,
libdw and libzstd: those end up only in `library-dirs`. GHC takes the `-L` flags for linking an
executable without `-dynamic` from `library-dirs-static`, so even hello world fails to link
unless these libraries are on the linker's default search path.

Cause: two changes from January 2026 combine.

- 1ac1a541 (!14935, #26434) made GHC take those `-L` flags from `library-dirs-static`
  instead of `library-dirs`.
- 0f53ccc6 ("Use libffi-clib", !14996) moved libffi's directory from hadrian's
  `--extra-lib-dirs` into `rts/rts.buildinfo.in`, including

  ```
  extra-lib-dirs-static: @FFILibDir@
  ```

  Cabal registers `extra-lib-dirs` as `library-dirs-static` only if no static library dirs are
  given (`extraLibDirsStaticOrFallback` in `Distribution.Simple.Register`). With
  `--with-ffi-libraries` the list isn't empty, so that fallback no longer happens.

This shows up with non-FHS layouts such as Nix, e.g. with nixpkgs' `haskell.compiler.ghcHEAD`.
It also shows up on macOS with the configure line from the
[wiki](https://gitlab.haskell.org/ghc/ghc/-/wikis/building/preparation/mac-osx)
(`--with-ffi-libraries=$sdk_path/usr/lib`) plus `--enable-ipe-data-compression`, if libzstd is
outside the linker's default search path. There, the GHC build itself fails (see below). GHC's CI
doesn't hit it: its only jobs with `--with-ffi-libraries` (FreeBSD 14) build an RTS without
libnuma, libdw or libzstd.

## Steps to reproduce

On x86_64-linux, configure master with libffi, libnuma and libdw outside the default search path,
here from the Nix store, then build. (Abbreviated: the run below also used nixpkgs' toolchain and
its other configure flags.)

```
./configure --with-system-libffi \
    --with-ffi-includes=/nix/store/…-libffi-3.8.0-dev/include \
    --with-ffi-libraries=/nix/store/…-libffi-3.8.0/lib \
    --enable-numa \
    --with-libnuma-includes=/nix/store/…-numactl-2.0.18-dev/include \
    --with-libnuma-libraries=/nix/store/…-numactl-2.0.18/lib \
    --enable-dwarf-unwind \
    --with-libdw-includes=/nix/store/…-elfutils-0.195-dev/include \
    --with-libdw-libraries=/nix/store/…-elfutils-0.195/lib
hadrian/build -j --flavour=quick+no_dynamic_libs+no_dynamic_ghc --docs=none
```

The registered RTS then has (`_build/stage1/lib/package.conf.d/rts-1.0.3.conf`, store hashes
shortened):

```
library-dirs:
    ${pkgroot}/../lib/x86_64-linux-ghc-10.1.20261010/rts-1.0.3
    /nix/store/…-libffi-3.8.0/lib
    /nix/store/…-elfutils-0.195/lib
    /nix/store/…-numactl-2.0.18/lib

library-dirs-static:
    ${pkgroot}/../lib/x86_64-linux-ghc-10.1.20261010/rts-1.0.3
    /nix/store/…-libffi-3.8.0/lib
```

and linking hello world from a clean environment (`env -i`, so nothing like Nix's `NIX_LDFLAGS`
adds the missing directories) fails, with or without `-threaded`:

```
$ _build/stage1/bin/ghc Hello.hs
[1 of 2] Compiling Main             ( Hello.hs, Hello.o )
[2 of 2] Linking Hello
/nix/store/…-binutils-2.46/bin/ld.gold: error: cannot find -lelf
/nix/store/…-binutils-2.46/bin/ld.gold: error: cannot find -ldw
/nix/store/…-binutils-2.46/bin/ld.gold: error: cannot find -lnuma
[35 undefined references to dwfl_*, numa_* and mbind]
collect2: error: ld returned 1 exit status
<no location info>: error:
    `cc' failed in phase `Linker'. (Exit code: 1)
```

Inside Nix builds, the build environment adds these directories, which hides the problem. In
nixpkgs, cross builds fail too: they link each package's `Setup.hs` with the native GHC HEAD,
without these directories.

On aarch64-darwin (macOS 26.7, Xcode 27.0's clang and ld), the wiki's configure line plus IPE
compression fails during the build itself:

```
./configure --with-system-libffi --with-intree-gmp \
    --with-ffi-libraries=$sdk_path/usr/lib --with-ffi-includes=$sdk_path/usr/include/ffi \
    --enable-ipe-data-compression \
    --with-libzstd-includes=/nix/store/…-zstd-1.5.7-dev/include \
    --with-libzstd-libraries=/nix/store/…-zstd-1.5.7/lib
```

(I also passed `--with-curses-*` for the stage0 `terminfo`, because my boot compiler came from
Nix.) The RTS then has `library-dirs-static: ${pkgroot}/…/rts-1.0.3 $sdk_path/usr/lib`, without
zstd's directory, and linking `_build/stage1/bin/hpc` fails:

```
| Run Ghc LinkHs Stage1: _build/stage1/utils/hpc/build/Main.o (and 17 more) => _build/stage1/bin/hpc
ld: library 'zstd' not found
clang: error: linker command failed with exit code 1 (use -v to see invocation)
`gcc' failed in phase `Linker'. (Exit code: 1)
```

## Expected behavior

`library-dirs-static` lists the same directories as `library-dirs`, as with GHC 9.14, and
executables link.

## Environment

* GHC version used: master (e7cacf59b8). ghc-10.0 is affected too, including 10.0.1-alpha1;
  9.14 and 9.12 aren't.
* Operating System: Linux (NixOS / nixpkgs); macOS 26.7 (Xcode 27.0: Apple clang 21, ld-27037)
* System Architecture: x86_64 (Linux), aarch64 (macOS). On aarch64-linux, where nixpkgs builds
  the RTS without libdw, only `-lnuma` is missing.

I'll open an MR with a fix (drop the field), and I'd like it backported to ghc-10.0.

Related: #26434 / !14935 (added the static fields), #20759.

cc @maerwald @alt-romes

/label ~"T::bug"
/label ~"needs triage"

---

## Merge request

**Title:** rts: don't restrict static lib dirs to libffi's (#27926)

**Description:**

_LLM assistance: Claude Code (Claude Opus 5.5) was used while preparing this contribution: for
the investigation, the testing, and drafts of the commit message, the source comment and this
description. I have carefully reviewed and revised the submitted material and take responsibility
for it under (P3)._

Fixes #27926.

Since 0f53ccc6 ("Use libffi-clib"), `rts/rts.buildinfo.in` sets `extra-lib-dirs-static:
@FFILibDir@`. With `--with-system-libffi --with-ffi-libraries`, this stops Cabal from falling back
to `extra-lib-dirs` for the RTS's `library-dirs-static`. The libnuma, libdw and libzstd dirs that
hadrian passes then go missing from it. Since 1ac1a541, GHC uses `library-dirs-static` when
linking without `-dynamic`, so linking executables fails unless those libraries are on the
default search path. On macOS, with the wiki's configure line plus IPE compression, even the GHC
build fails. See #27926 for details and reproducers.

This MR drops the field and leaves a comment in its place. The static library dirs then fall back
to `extra-lib-dirs` again, which still contains libffi's directory. `ghc-internal.buildinfo.in`
already relies on the same fallback. The only file changed is `rts/rts.buildinfo.in`.
`extra-lib-dirs: @FFILibDir@` has to stay: it's how libffi's directory gets into the RTS's
package entry at all, and dropping it as well gives `cannot find -lffi`. libffi's directory stays
in all three fields, so linking against a system libffi works as before, statically or not.

Library dirs differ from libraries here. Cabal registers `extra-libraries-static` exactly as
given, so the static libraries have to be spelled out, and `rts.cabal` does that. For library
dirs, Cabal falls back to `extra-lib-dirs` when no static dirs are given, and setting
`extra-lib-dirs-static` switches that fallback off.

An alternative would be for hadrian's `cabalExtraDirs` to pass `--extra-lib-dirs-static` as well.
But that makes the static list explicit for every package it serves (the compiler, ghci,
terminfo, ghc-internal and the RTS), which switches Cabal's fallback off for all of them. Each
`extra-lib-dirs` in their `.buildinfo` files would then have to be repeated as
`extra-lib-dirs-static`. Otherwise, for example, ghc-internal's iconv dirs would drop out of its
static list. `extra-lib-dirs-static` is for static archives that live in other directories than
the shared libraries. GHC's configure has only one directory per library, so the RTS has nothing
to put there, and leaving the field unset is the right encoding.

Nothing changes for GHC's CI. `FFILibDir` is empty in every job except FreeBSD 14
(`--with-ffi-libraries=/usr/local/lib`). There, the RTS has no other extra library dirs, so
`library-dirs-static` stays the RTS's own dir plus `/usr/local/lib`.

**Testing:** x86_64-linux, master e7cacf59b8, configured like nixpkgs' GHC HEAD
(`--with-system-libffi --with-ffi-libraries=…`, `--enable-numa`, `--enable-dwarf-unwind`, with
the libraries in the Nix store), `--flavour=quick+no_dynamic_libs+no_dynamic_ghc`. Each variant
was built in a fresh build root, and hello world was linked from a clean environment (`env -i`):

- Without the patch, `library-dirs-static` has only the RTS's own dir and libffi's, and linking
  fails as shown in #27926.
- With the patch, `library-dirs-static` equals `library-dirs` (the RTS's dir, libffi, elfutils,
  numactl) in both the installed and the in-place package DB. Hello world links and runs, with
  and without `-threaded`.

The same on aarch64-darwin (macOS 26.7, Xcode 27.0), configured with the wiki's
`--with-ffi-libraries=$sdk_path/usr/lib` plus `--enable-ipe-data-compression` and a libzstd
outside the default search path:

- Without the patch, the build fails when linking `_build/stage1/bin/hpc`, with
  `ld: library 'zstd' not found`.
- With the patch, the build completes, `library-dirs-static` equals `library-dirs` (the RTS's
  dir, the SDK's `usr/lib`, zstd), and hello world links and runs, with and without `-threaded`.

I've also used the patch in nixpkgs on top of GHC HEAD 10.1.20260810:

- The installed native compiler links and runs hello world from a clean environment as static,
  `-threaded`, `-dynamic` and `-dynamic -threaded` executables (x86_64-linux).
- With exactly this commit, the wasm cross pipeline passes on aarch64-linux and aarch64-darwin:
  the wasm compiler, plus a pure, a C-FFI and a Template Haskell hello world, each run under
  wasmtime. On aarch64-linux, these builds link each package's `Setup.hs` with the patched
  native compiler, which failed before with `cannot find -lnuma`. An earlier revision of the
  patch (the same change, without the comment) also passed the x86_64-linux wasm and JavaScript
  cross builds.

To test it yourself, use a fresh build root. In an existing build tree hadrian doesn't pick up
this change: it caches the RTS's package description and doesn't track the generated
`rts.buildinfo`, so `library-dirs-static` keeps its old value.

**Checklist notes:**

- No test: CI can't trigger this. Its only jobs with `--with-ffi-libraries` (FreeBSD 14) have no
  libnuma or libdw, so a test comparing the RTS's `library-dirs-static` with `library-dirs` would
  pass there with or without the fix. Happy to add one anyway if you'd like.
- No changelog entry (~no-changelog): no release has this bug, provided the fix reaches ghc-10.0
  before 10.0.1. If it doesn't, I'll add the entry below.
- Backport: ghc-10.0 has the same bug, and the patch applies cleanly there (~"backport
  needed:10.0"). 9.14 and 9.12 aren't affected.

---

## Changelog entry, only if a reviewer wants one

`changelog.d/rts-static-lib-dirs`:

```
section: packaging
synopsis: Fix linking executables when GHC is configured with
  ``--with-ffi-libraries`` and libnuma or libdw aren't on the linker's default
  search path. The RTS's ``library-dirs-static`` lacked their directories.
issues: #27926
mrs: !MMMMM
```

---

## Facts and where they come from (for P3)

- `0f53ccc6` "Use libffi-clib" (!14996, landed 2026-01-14) changed `rts/rts.buildinfo.in` to
  `extra-lib-dirs: @FFILibDir@` and `extra-lib-dirs-static: @FFILibDir@`. Before it, `1ac1a541`
  (!14935, #26434) had used the installed-package field names (`library-dirs-static` etc.),
  which aren't BuildInfo fields, so Cabal ignored them. Unchanged on master since.
- `FFILibDir` is set only with `--with-system-libffi --with-ffi-libraries=…`
  (`m4/fp_find_libffi.m4`).
- Cabal's fallback: `libraries/Cabal/Cabal/src/Distribution/Simple/Register.hs:578-587`
  (`extraLibDirsStaticOrFallback`), present since 2019 (Cabal 3.8 and later at least). Hadrian
  needs Cabal 3.13 to 3.16, which all have it. The `--extra-lib-dirs` flags are merged into the
  same BuildInfo: `Distribution/Simple/Configure.hs:1063-1070`.
- @maerwald's own design, from the public description of !14935 (the discussion threads need a
  login): "this patch assumes that 'library-dirs' is really just nothing but a fallback and always
  prefers the more specific variants if they exist and are non-empty", and "Conceptually, we
  should be ok with even just one search dirs variant. […] For system C libraries, the
  convention has been anyway to place static and dynamic libs next to each other". So a
  non-empty `library-dirs-static` has to be complete, which the fallback guarantees. !14996,
  which added the `extra-lib-dirs-static` line, has only the unedited MR template as its
  description, with no reason given for the line. It looks like a mechanical renaming of
  1ac1a541's field names (an inference). There's no comment from him on this bug: no issue or MR
  exists yet.
- From the full MR threads (pasted by the user, 2026-10-10):
  - The FFI dirs in `rts.buildinfo.in` come from the commit "Propagate ffi dirs from configure to
    package db". It first appeared in !14935's history and landed with !14996. It followed the
    darwin `-static-external` failure (`dyld: Symbol not found: _ffi_type_void`) and the darwin
    `ffi.h` hadrian error. @maerwald: "the right solution is that the rts.conf needs to have the
    system path to libffi in include-dirs". Rodrigo reproduced that with the wiki's macOS
    configure line, `--with-system-libffi --with-ffi-libraries=$sdk_path/usr/lib`. Nobody
    discussed `library-dirs-static` or Cabal's fallback.
  - !14935 added "Make sure 'extra-libraries-static' is consistently defined", duplicating every
    `extra-libraries`. That duplication is necessary, because Cabal registers
    `extra-libraries-static` as given (`Register.hs:535`, no fallback). @mpickering asked
    whether `extra-libraries` and `extra-libraries-static` should always be the same list; the
    answer is in a collapsed thread. Applying the same pattern to dirs, where Cabal does fall
    back (`:578-587`), is the most likely origin of the line. That's an inference.
  - People: @alt-romes (Rodrigo Mesquita) reviewed and approved !14935, is assigned #26434, and
    reproduced the macOS case. @mpickering approved !14996. Backports: @wz1000 (Zubin) refused
    the big !14935 for 9.12 as too risky, and @MangoIV (Magnus) helped with the 9.14 backport. A
    one-file, CI-neutral fix is the easy kind. @maerwald was very frustrated with hadrian and
    GHC CI in both MRs and closed the 9.14 backport ("I lost interest"). Don't count on quick
    replies from him, and keep the MR low-effort to review.
  - @maerwald also left an open question on `rts.cabal`'s `extra-libraries-static: zstd`
    indentation ("not quite sure if this is a bug"; @MangoIV: "It might be a bug"). It's in the
    same area, but a different matter.
- macOS (tested on this Mac, 2026-10-10): the wiki's configure line
  (`building/preparation/mac-osx`, line 20:
  `--with-system-libffi --with-intree-gmp --with-ffi-libraries=$sdk_path/usr/lib
  --with-ffi-includes=$sdk_path/usr/include/ffi`) plus `--enable-ipe-data-compression` with
  libzstd from the Nix store. The toolchain was Apple's (`/usr/bin/clang`, ld-27037, SDK
  MacOSX27.0). The tools (boot GHC 9.10.3, alex, happy, autoconf, automake, pkg-config) came
  from Nix on `PATH` only. Nix's ncurses was passed via `--with-curses-*`, only because the Nix
  boot compiler's C toolchain can't find curses for the stage0 terminfo. Unpatched, the RTS's
  `library-dirs-static` = own dir + SDK `usr/lib`, and the build fails linking
  `stage1/bin/hpc` (`ld: library 'zstd' not found`). Patched, the build completes in 14m41s,
  and hello world links and runs with and without `-threaded` from `env -i PATH=/usr/bin:/bin`.
  Configure needs `pkg-config` for the zstd version check. Logs are in
  `results/logs/patch-0005/macos/` (gitignored; the APFS-clone test tree was deleted 2026-10-10).
- What the static field is for: Cabal `bf32602db` (Niklas Hambüchen, 2019, "Add field to
  remember libs needed for fully static linking"), whose message has static `.a` files in a
  split output separate from the `.so`. The fallback's code comment: "If no static library dirs
  were given, the package likely makes no distinction between fully static linking and
  otherwise." Cabal's docs: "directories to search for libraries (when linking fully static
  executables)" (`doc/cabal-package-description-file.rst:1978`).
- Hadrian passes libdw, libnuma and libzstd dirs to the rts with `--extra-lib-dirs` only
  (`hadrian/src/Settings/Packages.hs:419-423`, `cabalExtraDirs` at `:451-464`).
- `cabalExtraDirs` also serves the compiler (libzstd, `:80`), ghci (libffi, `:161`), terminfo
  (curses, `:202`) and ghc-internal (gmp, `:261`). Of those, ghc-internal and terminfo add more
  dirs in their own `.buildinfo.in` (`@ICONV_LIB_DIRS@ @GMP_LIB_DIRS@`, `@TERMINFO_LIB_DIRS@`).
  Those would fall out of their static lists if `cabalExtraDirs` passed `--extra-lib-dirs-static`.
- GHC links non-dynamic executables with `library-dirs-static`: `libraryDirsForWay'`
  (`compiler/GHC/Unit/Info.hs:221-224`) via `collectLibraryDirs` in
  `compiler/GHC/Linker/Executable.hs:164`. This has been so since 1ac1a541; 9.14 used
  `library-dirs` there. GHC itself also falls back to `library-dirs` when
  `library-dirs-static` is empty (`mungeLibDirFields`, `compiler/GHC/Unit/External/Database.hs`).
- 9.14's hadrian passed libffi's dir to the rts with `--extra-lib-dirs`
  (`useSystemFfi ? cabalExtraDirs ffiIncludeDir ffiLibraryDir`). 0f53ccc6 removed that and put
  the dir into `rts.buildinfo.in` instead.
- `rts.buildinfo` is parsed with the `.cabal` lexer, which skips `--` comment lines
  (`parseHookedBuildInfo`; hadrian calls `readHookedBuildInfo`).
- Only `rts/rts.buildinfo.in` sets static library dirs in the tree. `ghc-internal.buildinfo.in`
  sets only `extra-lib-dirs`.
- CI: only the FreeBSD 14 jobs (validate, nightly, release) pass
  `--with-ffi-libraries=/usr/local/lib` (`.gitlab/generate-ci/gen_ci.hs:454`), with NUMA disabled
  and no libdw. The Debian 13 NUMA jobs don't pass `--with-ffi-libraries` (`.gitlab/jobs.yaml`).
- `ghc-9.14` and `ghc-9.12` have only `extra-libraries: @EXTRA_LIBS@` in the file. The 9.14
  backport of !14935 (!15692) was closed unmerged.
- No existing issue or MR (GitLab API search, 2026-10-10).
- Hadrian caches the RTS's package description. `resolveContextData`
  (`hadrian/src/Hadrian/Haskell/Cabal/Parse.hs:248`) is an `addOracleCache` that only `need`s
  `setup-config`, and reads the generated `rts.buildinfo` untracked. So an existing build tree
  keeps the old `library-dirs-static`, even after `rm -rf _build/stage1/rts`; we observed this on
  the NUC. Test in a fresh build root. This is a separate, small hadrian bug, a candidate for its
  own issue.
- `-static-external` (testsuite `driver/mostly-static`, run by hand outside Nix): unpatched it
  fails with `cannot find libelf.a`/`libdw.a`/`-lnuma`. Patched, the archives are found, but it
  then fails with 171 undefined references from `libdw.a`. They come from the `elf dw` order in
  `rts.cabal`'s `extra-libraries-static` (static libdw needs libelf after it), and from libdw's
  own static dependencies (zstd, lzma, bzip2, zlib), which nothing lists. That's pre-existing
  and separate; keep it out of the MR unless asked.
- GHC's `rts/Libdw.c` supports aarch64 since `b0fbd18120` (2024, in 9.12 and later). nixpkgs still
  enables libdw only on x86 and s390x, citing a 2022 comment, which is why aarch64-linux only
  misses `-lnuma`. That's a possible small nixpkgs follow-up, unrelated to this MR.

## Test runs (NUC and this Mac, 2026-10-10)

Tree `~/ghc-mr-test/ghc` on the NUC (deleted after the runs; a shallow clone of master `e7cacf59b8`), environment `nix-shell
~/nixpkgs-ghcwasm.git -A haskell.compiler.ghcHEAD` (nixpkgs' configure flags and toolchain),
hadrian built from the same tree, `--flavour=quick+no_dynamic_libs+no_dynamic_ghc --docs=none`.
Checks run from `env -i` outside the shell. Logs and scripts are on the NUC in
`~/ghcwasm/results/logs/patch-0005-nuc/` (gitignored).

| Build root | `rts.buildinfo.in` | `library-dirs-static` | hello world (`-threaded` too) |
|---|---|---|---|
| `_build` (clean) | master | RTS dir, libffi | `cannot find -lelf/-ldw/-lnuma` |
| `_build-patched` (clean) | the patch | RTS dir, libffi, elfutils, numactl (= `library-dirs`) | links and runs |
| `_build-cf` (clean) | the patch, minus `extra-lib-dirs` | RTS dir, elfutils, numactl (libffi gone everywhere) | `cannot find -lffi` |
| `_build`, rebuilt after `rm -rf _build/stage1/rts` | the patch | unchanged (stale, see the hadrian caching note) | still fails |
| macOS `_build-unpatched` (clean) | master | RTS dir, SDK `usr/lib` | the build fails: `ld: library 'zstd' not found` (linking `hpc`) |
| macOS `_build-patched` (clean) | the patch | RTS dir, SDK `usr/lib`, zstd (= `library-dirs`) | build completes; links and runs |

nixpkgs wasm GHC HEAD pipeline with exactly `0face25f69` in place of nixpkgs'
`ghc-10-rts-static-lib-dirs.patch`: a detached nixpkgs worktree (since removed) at the branch head
`a6b14f10857e`, built through ghc-wasm-flake with `--override-input nixpkgs path:…`. The 7 targets
of `scripts/build.sh` (wasm compiler, hello-pure, hello, hello-th, and the 3 wasmtime checks)
were built for each system. aarch64-linux: `exit=0` in 36 min (on the VM). aarch64-darwin: `exit=0`.
Logs are in `results/logs/patch-0005/wasm-pipeline/`. JS was deliberately skipped.

Also: `-static-external` (the `mostly-static` test by hand) in the NUC logs' `ms-unpatched/` and
`ms-patched/`, and nixpkgs' patched release-flavour GHC HEAD (static, `-threaded`, `-dynamic`,
`-dynamic -threaded`) in `hello-nixpkgs/`.
