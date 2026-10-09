# The nixpkgs branch `ghcwasmhacking`

Repository: `~/nixpkgs-ghcwasm.git`. The branch was created 2026-10-09 on top of
`origin/haskell-updates` at `68594478077b`, following the Haskell team's advice to base Haskell
work there. Published at https://github.com/mikatammi/nixpkgs/tree/ghcwasmhacking and
force-pushed there after every change, so expect rewritten history. No PR yet. Commits 15–17
(Template Haskell) lived on a separate branch, `ghcwasmhacking-th`, until TH was green; they
were folded in on 2026-10-09.

Local reference branches with the original PRs: `pr/225000`, `pr/561449`, `pr/558928`.

## Commit stack

| # | Commit | Author | Where it should go upstream |
|---|---|---|---|
| 1 | `libffi-wasm: init at 20260905` | ilkecan (cherry-pick of #561449, unchanged) | #561449 (master). Its global `libffi` override for wasi is contested by sternenseemann; commit 4 makes GHC independent of it. |
| 2 | `wasilibc.tests: check compilations of trivial C(++) binaries` | sternenseemann (port of #225000 `9cc1d4d`) | small PR to master |
| 3 | `pkgsCross.wasm32-wasip1.haskell.compiler.*: new wasm backend` | sternenseemann (port of #225000 `646856e`) | haskell-updates |
| 4 | `haskell.compiler: use libffi-wasm for wasm targets` | Mika Tammi | haskell-updates (needs libffi-wasm to exist) |
| 5 | `haskell.compiler: accept wasm32-*-wasip1 target triples` | Mika Tammi | haskell-updates; the patch also goes to GHC (`upstream/ghc/0001-…`) |
| 6 | `haskell.compiler: link wasm targets with wasm-ld` | Mika Tammi | haskell-updates |
| 7 | `haskell.compiler: drop static-cross workarounds for wasm targets` | Mika Tammi | haskell-updates |
| 8 | `haskell.compiler: don't build profiled libraries for wasm targets` | Mika Tammi | haskell-updates |
| 9 | `haskell.compiler: use upstream's C and linker flags for wasm targets` | Mika Tammi | haskell-updates |
| 10 | `haskell.compiler: don't link the stage0 compiler against libffi-wasm` | Mika Tammi | haskell-updates; hadrian patch also for GHC (`upstream/ghc/0002-…`) |
| 11 | `haskell.compiler: fix the wasm RTS build against wasilibc 32` | Mika Tammi | haskell-updates; RTS patch also for GHC (`upstream/ghc/0003-…`) |
| 12 | `haskell.compiler: don't compile XXH3 into the wasm RTS` | Mika Tammi | haskell-updates; RTS patch also for GHC (`upstream/ghc/0004-…`) |
| 13 | `haskell.compiler: fix the darwin host config of wasm GHC >= 10` | Mika Tammi | haskell-updates; GHC issue: the host templates should use configure's results (`use-lib-rt`, otool, install_name_tool) |
| 14 | `haskell.compiler: no haddock docs for wasm GHC >= 10` | Mika Tammi | haskell-updates; hadrian issue: the haddock index step reads the stage0 package db in GHC 10 cross builds |
| 15 | `haskell: enable shared libraries for GHC's wasm interpreter` | ilkecan (cherry-pick of #558928, unchanged) | #558928 |
| 16 | `libffi-wasm: also build libffi.so` | Mika Tammi | suggest for #561449 (dyld.mjs loads `libffi.so`) |
| 17 | `haskell.compiler: set up GHC's wasm interpreter for Template Haskell` | Mika Tammi | haskell-updates. Contents: the node wrapper for `dyld.mjs`'s interpreter line, and the dyld library dir patch, which would ideally become a GHC option |
| 18 | `haskell.compiler.ghcHEAD: fix linking executables with libnuma/libdw` | Mika Tammi | haskell-updates, independent of wasm; GHC MR from `upstream/ghc/0005-…` |

The wasip1 commit (5) also carries the LLVM-target hunk; it was folded in with an autosquash
rebase.

## Invariants

- Every change is gated on `isWasm`/`isWasi`, so native derivations are unchanged. This is
  checked with `scripts/native-drvpaths.sh` against `results/native-drvpaths-base.txt`.
  Exception: commit 18 deliberately changes every GHC >= 10, including native `ghcHEAD`. It
  fixes a bug in stock nixpkgs.
- Formatted with nixpkgs' `nix fmt` (treefmt: nixfmt, nixf-diagnose, keep-sorted, …).
- Commits written or adapted with AI assistance carry an `Assisted-by:` trailer, per nixpkgs'
  Automation/AI policy. Ported commits keep their original author and date, with a note on what
  was changed.

## PR strategy

The user's decision (2026-10-09): **no PR from this branch**, probably ever. The branch shows
that the approach works and stays available on the fork. First, the prerequisite PRs (ilkecan's
#561449 and #558928, plus anything else this stack depends on) should be merged. After that,
either split the remaining commits into normal PRs as below, or open a *draft* PR as "this could
be one way to do it".

## Splitting into upstream PRs (later, after talking to the people involved)

1. Ask ilkecan whether to fold commits 4–9 into one PR with them or file them separately.
2. A PR to haskell-updates with commits 3–9 (+ fix-ups), depending on libffi-wasm landing on
   master first, or carrying it.
3. The wasilibc test to master.
4. The GHC MR for `wasip1`. Once merged, the nixpkgs patch gets a link and a version bound.
