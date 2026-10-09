# The nixpkgs branch `ghcwasmhacking`

Repository: github.com/mikatammi/nixpkgs. The branch was created 2026-10-09 on top of
`origin/haskell-updates` at `68594478077b`, following the Haskell team's advice to base Haskell
work there, and rebased onto `a7dd47562121` on 2026-10-28. Published at https://github.com/mikatammi/nixpkgs/tree/ghcwasmhacking and
force-pushed there after every change, so expect rewritten history. Each update also gets a
dated branch that never moves, `ghc-wasm-flake-<date>`, which this flake pins. Commits 14–16
(Template Haskell) lived on a separate branch, `ghcwasmhacking-th`, until TH was green; they
were folded in on 2026-10-09.

Local reference branches with the original PRs: `pr/225000`, `pr/561449`, `pr/558928`.

## Commit stack

| # | Commit | Author | Where it should go upstream |
| -- | -- | -- | -- |
| 1 | `libffi-wasm: init at 20260905` | ilkecan (cherry-pick of #561449, unchanged) | #561449 (master). Its global `libffi` override for wasi is contested by sternenseemann; commit 4 makes GHC independent of it. |
| 2 | `wasilibc.tests: check compilations of trivial C(++) binaries` | sternenseemann (port of #225000 `9cc1d4d`) | small PR to master |
| 3 | `pkgsCross.wasm32-wasip1.haskell.compiler.*: new wasm backend` | sternenseemann (port of #225000 `646856e`) | haskell-updates |
| 4 | `haskell.compiler: use libffi-wasm for wasm targets` | Mika Tammi | haskell-updates (needs libffi-wasm to exist) |
| 5 | `haskell.compiler: accept wasm32-*-wasip1 target triples` | Mika Tammi | haskell-updates; the patch is GHC !16795, fetched with `fetchpatch2` |
| 6 | `haskell.compiler: link wasm targets with wasm-ld` | Mika Tammi | haskell-updates |
| 7 | `haskell.compiler: drop static-cross workarounds for wasm targets` | Mika Tammi | haskell-updates |
| 8 | `haskell.compiler: use upstream's C and linker flags for wasm targets` | Mika Tammi | haskell-updates |
| 9 | `haskell.compiler: don't link the stage0 compiler against libffi-wasm` | Mika Tammi | haskell-updates; the hadrian patch (`upstream/ghc/0002-…`) has GHC issue #28053 but no MR yet: GHC master no longer needs it, only the release branches do |
| 10 | `haskell.compiler: fix the wasm RTS build against wasilibc 32` | Mika Tammi | haskell-updates; the patch is GHC !16794, fetched with `fetchpatch2` |
| 11 | `haskell.compiler: update xxHash in the wasm RTS` | Mika Tammi | haskell-updates; GHC's xxHash bumps !16708 (0.8.4) and !16879 (xxHash's dev branch, until 0.8.5), fetched with `fetchpatch2` |
| 12 | `haskell.compiler: fix the darwin host config of wasm GHC >= 10` | Mika Tammi | haskell-updates; GHC issue #28054: the host templates should use configure's results (`use-lib-rt`, otool, install_name_tool) |
| 13 | `haskell.compiler: no haddock docs for cross GHC >= 10` | Mika Tammi | haskell-updates, independent of wasm: it also fixes the JS backend's GHC HEAD on Hydra. GHC issue #28055: the haddock index step reads the stage0 package db in GHC 10 cross builds |
| 14 | `haskell: enable shared libraries for GHC's wasm interpreter` | ilkecan (cherry-pick of #558928, unchanged) | #558928 |
| 15 | `libffi-wasm: also build libffi.so` | Mika Tammi | suggest for #561449 (dyld.mjs loads `libffi.so`) |
| 16 | `haskell.compiler: set up GHC's wasm interpreter for Template Haskell` | Mika Tammi | haskell-updates. Contents: the node wrapper for `dyld.mjs`'s interpreter line (node from `pkgsHostHost`, so darwin gets Hydra's), and the dyld library dir patch, which would ideally become a GHC option |
| 17 | `haskell.compiler.ghcHEAD: fix linking executables with libnuma/libdw` | Mika Tammi | haskell-updates, independent of wasm; the patch is GHC !16791, fetched with `fetchpatch2` |
| 18 | `haskellPackages: add configuration overlay for wasm` | Mika Tammi | haskell-updates; like `configuration-ghcjs-9.x.nix`, a place for overrides that only apply to wasm hosts |
| 19 | `haskellPackages.mkDerivation: take nodejs from pkgsBuildBuild` | Mika Tammi | haskell-updates, independent of wasm: `buildPackages`' nodejs has the target platform, which on darwin is a variant Hydra doesn't build. Changes only darwin's wasm and GHCJS package sets |

The wasip1 commit (5) also carries the LLVM-target hunk; it was folded in with an autosquash
rebase.

## Invariants

- Every change is gated on `isWasm`/`isWasi`, so native derivations are unchanged. This is
  checked with `scripts/native-drvpaths.sh` against `results/native-drvpaths-base.txt`.
  Exception: commit 17 deliberately changes every GHC >= 10, including native `ghcHEAD`. It
  fixes a bug in stock nixpkgs.
- Formatted with nixpkgs' `nix fmt` (treefmt: nixfmt, nixf-diagnose, keep-sorted, …).
- Commits written or adapted with AI assistance carry an `Assisted-by:` trailer, per nixpkgs'
  Automation/AI policy. Ported commits keep their original author and date, with a note on what
  was changed.

## PR strategy

The branch itself never becomes a nixpkgs PR as it is. It shows that the approach works and
stays available on the fork. Its commits go upstream individually instead, as separate PRs, once
the prerequisite PRs (ilkecan's #561449 and #558928, plus anything else this stack depends on)
are merged.

## Splitting into upstream PRs (later, after talking to the people involved)

1. Ask ilkecan whether to fold commits 4–9 into one PR with them or file them separately.
1. A PR to haskell-updates with commits 3–9 (+ fix-ups), depending on libffi-wasm landing on
   master first, or carrying it.
1. The wasilibc test to master.
1. The GHC patches are fetched from their merge requests. Once those are merged, switch to the
   merged commits and add version bounds.
