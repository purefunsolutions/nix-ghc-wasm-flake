# Plan: GHC wasm backend in nixpkgs — rebased #225000 + pure-Nix hello world

## Context

MuniHac 2026 goal: nixpkgs builds a wasm-targeting GHC **purely from source with its own stock
toolchain** (LLVM 21 + upstream wasilibc 32; no bindists, no haskell-wasm forks), proven by a
hello-world flake in `~/ghcwasm` whose nixpkgs input is `~/nixpkgs-ghcwasm.git`.
sternenseemann's 2023 PR NixOS/nixpkgs#225000 stalled on GHC-specific wasi-libc patches, GHC's
forked wasi-sdk/LLVM, GHC patches applied in CI, and the custom libffi. On 2026-10-05 he restated
on #561449 that GHC "requires a fork of LLVM … since GHC's assumptions about memory have to be
accommodated". Research shows that has not been true since mid-2024, but **nobody has tested a
source build on stock nixpkgs** (ilkecan's `ghc-wasm-nix` = bindist; haskell.nix = from source
but with the forked wasi-libc + an LLVM patch, pinned before the wasip1 rename). A green static
hello world on stock nixpkgs is the evidence that unblocks review.

User decisions (2026-10-09):
- Re-point `ghcwasmhacking` to **`origin/haskell-updates`** (Haskell team guidance; #225000 also
  targeted it; shares cache with master). The branch has no own commits (== master), so this
  loses nothing.
- **Integrate ilkecan's open PRs** (#561449 libffi-wasm, #558928 wasm shared libs); drop #225000's
  2023 `libffi-wasm-ghc`; ported #225000 commits keep sternenseemann as author.
- GHC targets, native bignum, via aliases that follow the branch: `ghc912` (→ 9.12.5; default
  wasm `haskellPackages`), `ghc914` (→ 9.14.1; `ghc9142` also exists), `ghcHEAD` (→ 10.1.20260810).
- Scope: hello world builds + runs under wasmtime on **aarch64-darwin (native), x86_64-linux,
  aarch64-linux** (Linux via this Mac's remote builders). All project docs, drafts, patches and
  results live in `~/ghcwasm` (Part 2). TH/JSFFI next.
- Nothing is pushed or posted (GitHub/GitLab/Matrix) without explicit approval; drafts only.
- nixpkgs `CONTRIBUTING.md` "Automation/AI policy" (`:896-930`): every commit I create or adapt
  gets `Assisted-by: Claude Code (claude-opus-5-5)` (`Co-authored-by` doesn't satisfy it); you
  stay the accountable reviewer; drafted PR/issue/MR texts carry their own disclosure. ilkecan's
  cherry-picks stay untouched.
- GHC has no in-repo AI policy, but its wiki has one:
  [contributing/AI](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI). Every commit gets
  an `Assisted-By:` line. Every issue and MR starts with a disclosure that also says the author
  reviewed the material and takes responsibility for it (P3/P4). GHC strongly recommends writing
  the final texts yourself (R1).

## Research summary (2026-10-09)

| 2023 blocker | Now | Evidence |
|---|---|---|
| RTS needs patched wasi-libc (OSMem.c) | **Resolved** (9.10.2+, 9.12, 9.14, 10.x): page-sized megablocks, RTS calls stock `sbrk` directly | GHC `558353f4` (2024-06-12); relies on wasi-libc#334 + `__heap_end`, both upstream. GHC CI still only tests the fork. |
| Forked wasi-sdk/LLVM (mimalloc…) | **Mostly optional**: forks persist (wasi-sdk-29 + LLVM 21.1.8+4 + wasi-libc +9 patches). The only correctness patch, wasm-ld splitting `__wasm_apply_data_relocs`, matters only for huge TH `.so`s. mimalloc only speeds up the fork's CI. | Fork `a4a2f322`, llvm#129007 open. The README line "Upstream wasi-sdk won't work yet" dates from 2022. |
| GHC patches in CI | **Resolved** | hsc2hs#68, process#270 (Jan 2023); current CI applies none |
| libffi-wasm | **Still required** (`LibffiAdjustor.c`; upstream libffi's wasm port is emscripten-only). Now MIT (tag 20260905), and its own CI builds with stock wasi-sdk-34 | nixpkgs #561449 (open; sternenseemann objects to a global `libffi` override); GHC #22590 |
| new: triple | GHC accepts OS `wasi` only; nixpkgs is `wasm32-unknown-wasip1` → configure fails "Unknown OS wasip1" | `m4/ghc_convert_os.m4`, ghc-toolchain `ParseTriple.hs:82`; no GHC issue |
| new: macOS host | GHC #26021 (open): hadrian passes the target `--target` to the stage0 clang; regression `9995c2b7` is in 9.14.x/10.x/master, **not 9.12** | Expect 9.14/HEAD on darwin to fail at `_build/stage0/utils/unlit/build/c/fs.o` |
| new: TH (later) | GHC 9.12.1+ (!12555). Needs node ≥22.18, `.so` libs (nixpkgs wasilibc already ships `libc.so`, `libdl.so`, `libsetjmp.so`; #561449 has no `libffi.so`) and the dyld lib dir (taken from `$CC --print-search-dirs`, which needs a patch with cc-wrapper) | haskell.nix patches `compiler/GHC.hs` |

Upstream flags (ghc-wasm-meta `pkgs/wasi-sdk-setup-hook.sh`), STAGE1 = STAGE2:
`CONF_CC_OPTS_STAGE2="-Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128"`,
`CONF_CXX_OPTS_STAGE2` = same + `-fno-exceptions`,
`CONF_GCC_LINKER_OPTS_STAGE2="-Wl,--error-limit=0,--keep-section=ghc_wasm_jsffi,--keep-section=target_features,--stack-first,--strip-debug"`,
`--with-system-libffi`, flavour `release` (no `+no_dynamic_libs` if TH is wanted). `-mcpu=lime1`
needs LLVM ≥ 20 (nixpkgs: 21.1.8). GHC 9.16 was renamed 10.0 (alpha1 2026-09-17). ghc-wasm-meta's
default 9.14 is a fork branch (upstream + 107 backports); haskell.nix builds upstream 9.12.4/9.14.1.

nixpkgs, already merged: wasilibc 32 CMake (#537425), wasip1 rename (#537429), LLVM 21 wasm
toolchain, generic-builder wasm interpreter support (#553410), cross Haddock (#553415),
`CC/LD/AR_STAGE0` + `depsBuildBuild` (= #225000's last commit), `dontStrip` for wasm,
native-bignum `haskellPackages` for static (incl. wasm) hosts.

Fate of #225000's hunks: emscripten `isLLVM`, strip-via-wrapper, LLVM-16 libcxx/libcxxabi,
wasilibc 20/threads, LLVM min-version, haskell-packages libffi/LLVM overrides → obsolete.
`CC_STAGE0`, `depsBuildBuild`, `enableShared = false`, `haskellPackages` choice → already in the tree.
`libffiAttr` and libffi-wasm-ghc → superseded by #561449 + commit 4 below. wasilibc test, NCG for
wasm, native bignum, no terminfo, release jobs → still needed.

Other in-tree problems (verified):
- `useLLVM` is true for wasm today: the eval shows flavour `release+llvm+…`.
- `LD` and merge-objs use `${prefix}ld`. lld picks its flavour from the program name: LLVM 21
  `DriverDispatcher.cpp` `parseProgname` turns `…-ld` into ELF. `${prefix}wasm-ld` exists and
  resolves to Wasm.
- `-fPIC -fexternal-dynamic-refs` and `--flags=-dynamic-system-linker` (applied to every
  `isStatic` host) also hit wasm.
- `targetPackages.libffi` on wasi is upstream libffi 3.8, which is broken there.
- The gmp variant needs gmp-static, which fails on wasi.

## Part 1 — nixpkgs branch `ghcwasmhacking` (`/Users/mika/nixpkgs-ghcwasm.git`)

Step 0: `git fetch origin haskell-updates pull/225000/head:pr/225000 pull/561449/head:pr/561449
pull/558928/head:pr/558928`, then `git switch -C ghcwasmhacking origin/haskell-updates`
(untracked files untouched).

Commit stack. Every change is gated on `isWasm`/`isWasi`, so native GHC drvPaths stay
identical and haskell-updates sees no mass rebuild. Line numbers are from master; on
haskell-updates the code sits ~10-20 lines earlier.

1. `libffi-wasm: init at 20260905`: cherry-pick #561449 as-is (author ilkecan).
2. `wasilibc: add C/C++ hello-world tests`: port of #225000 `9cc1d4d` (author sternenseemann).
   Add a `test.nix` in `pkgs/by-name/wa/wasilibc/`, wired into `passthru.tests` and modeled on
   #561449's `test.nix`: compile with the wasm `stdenv.cc`, run with wasmtime, link `-lc++` only.
3. `pkgsCross.wasm32-wasip1.haskell.compiler.*: new wasm backend`: port of #225000 `646856e`.
   It contains only what that commit did (author sternenseemann + `Co-authored-by: Mika Tammi`;
   the message lists the adaptations):
   - `common-have-ncg.nix`: add `|| (lib.versionAtLeast version "9.6" && stdenv.targetPlatform.isWasm)`.
   - `common-hadrian.nix`: add `isWasm` to `enableNativeBignum` (`:52-55`) and `enableTerminfo`
     (`:71-84`, which matters for HEAD).
   - `release-cross.nix` `wasiCommon` (`:120-131`): add `haskellPackages.hello`.
   - `release-haskell.nix` `pkgsCross`: add a `wasm32-wasip1` block mirroring the `ghcjs` block
     (haskell-updates `:424-457`): `haskellPackages`, `haskell.packages.{ghc914,ghcHEAD}` →
     `{ ghc hello microlens }`.

New commits by Mika Tammi, one concern each (in `common-hadrian.nix` unless noted):

4. `…: use libffi-wasm for wasm targets`: `targetLibs.libffi` (`:549-557`) and `libDeps`
   (`:435-448`) take `targetPackages.libffi-wasm`. This works with or without #561449's global
   override, which answers sternenseemann's objection.
5. `…: accept wasm32-*-wasip1 target triples`: new `ghc-wasm-accept-wasip1-triple.patch` (m4
   `wasi*)`, ParseTriple `wasip1`/`wasip2`), wasi-only in the `ghcSrc` patch list (`:184-363`).
6. `…: link wasm targets with wasm-ld`: add `"wasm-ld" = cc.bintools.bintools` to `toolPath`
   (`:474-512`), plus a `linkerTool` used for `LD` (`:598`) and the "ld command" / "Merge
   objects command" settings (`:904-905`).
7. `…: no -fexternal-dynamic-refs / -dynamic-system-linker for wasm`: add `&& !isWasm` to
   `enableRelocatedStaticLibs` (`:59-60`, as haskell.nix does) and to `-dynamic-system-linker`
   (`:429-432`).
8. `…: don't build profiled libs for wasm targets`: `enableProfiledLibs` (`:64`). generic-builder
   never uses them on wasm, so this roughly halves each of the 9 GHC builds.
9. `…: use upstream's wasm C/linker flags`: the `CONF_*_STAGE1/2` values above, added to
   `configureFlags` for wasm.
10. Fix-ups found while building, one commit each, explained. Expected: a #26021 workaround for
    darwin 9.14/HEAD (keep the target `--target` out of stage0 CC flags), plus per-version
    patches. Each also gets an upstream issue or MR draft in `~/ghcwasm/drafts/`, with the
    patch in `~/ghcwasm/upstream/ghc/`.
11. `haskell: enable shared libraries for GHC's wasm interpreter`: cherry-pick #558928 **last**
    (author ilkecan). Rebuild ghc914 on all systems. If the dynamic way fails, add a follow-up
    fix or gate it, and note the finding for ilkecan.

Pilot order:
- First, in parallel: `ghc912` on aarch64-darwin (no #26021) and `ghc914` on aarch64-linux.
- Then darwin ghc914/ghcHEAD with the #26021 fix.
- Then x86_64-linux (Rosetta, slowest).

## Part 2 — `~/ghcwasm`: the project home (`/Users/mika/ghcwasm`)

Everything about this project that isn't a nixpkgs change lives here: the hello-world flake,
status, research notes, drafts, upstream patches and build results. The only thing that lives
in `nixpkgs-ghcwasm.git` is the commit stack itself.

```
~/ghcwasm/
  README.md          what this is, how to build/run/iterate
  STATUS.md          living status: result matrix, blockers, coordination, open questions
  flake.nix  flake.lock  .gitignore
  hello/             hello-wasm.cabal, app/Main.hs, cbits/hello.c
  nix/hello.nix      hand-written mkDerivation (no IFD)
  docs/
    plan.md          this plan, kept up to date
    research.md      full findings with links (upstream toolchain, nixpkgs per-hunk map,
                     community efforts, haskell.nix recipe, GHC issues)
    nixpkgs-branch.md  commit stack ↔ upstream PRs, authorship, how to split into PRs
  drafts/            texts to post later, each with AI disclosure: GHC wasip1 MR, GHC #26021,
                     status comment for nixpkgs #220835/#225000, notes for ilkecan
                     (#558928/#561449), nixpkgs data point for GHC #25917
  upstream/ghc/      GHC patches prepared against GHC master for MRs (wasip1; #26021 if found)
  results/           per-GHC × system build outcomes and trimmed failure excerpts
```

`flake.nix`:
- `inputs.nixpkgs.url = "git+file:///Users/mika/nixpkgs-ghcwasm.git?ref=ghcwasmhacking"`.
- Systems: aarch64-darwin, x86_64-linux, aarch64-linux. `wasm = pkgs.pkgsCross.wasm32-wasip1`.
- `packages.<sys>`:
  - `wasm-{ghc912,ghc914,ghcHEAD}` = `wasm.buildPackages.haskell.compiler.native-bignum.<v>`.
  - `hello-{…}` = `wasm.haskell.packages.native-bignum.<v>.callPackage ./nix/hello.nix { }`. The
    explicit `native-bignum` keeps before/after repros against unpatched nixpkgs working.
  - `wasi-c-hello`: C built with `wasm.stdenv`, as a toolchain sanity check.
  - `default` = `hello-ghc912`.
- `checks.<sys>`: run each `hello-*/bin/hello-wasm.wasm a b` under `pkgs.wasmtime` and diff it
  against the expected output; also run `wasi-c-hello` and `wasm.libffi-wasm.tests.upstream`.
- `apps.<sys>.default`: a wasmtime wrapper.
- `devShells.<sys>.default`: the ghc914 wasm GHC, cabal-install, wasmtime and nodejs.

`hello/hello-wasm.cabal` (exe `hello-wasm`, base only, `c-sources: cbits/hello.c`), with
`app/Main.hs` and `cbits/hello.c` (`hello_add`, `hello_apply(fnptr,a,b)`). Running it with
arguments `a b` must print the lines below. Each line exercises one layer; Cabal names wasm
executables `<name>.wasm`.
```
Hello from GHC's wasm backend, built purely with Nix!
265252859812191058636308480000000        -- product [1..30 :: Integer]: native bignum
args: a b                                -- WASI argv
C FFI: 40 + 2 = 42                       -- C toolchain + linking
FFI wrapper (libffi-wasm): 6 * 7 = 42    -- foreign import ccall "wrapper"
```

Other files:
- `nix/hello.nix`: hand-written cabal2nix-style `mkDerivation`, so no IFD.
- `.gitignore`: `result*`.
- `flake.lock`: committed. Commits stay local on `master` (the repo has no remote).
- `README.md`: usage, how to iterate on uncommitted nixpkgs edits with
  `--override-input nixpkgs git+file:///Users/mika/nixpkgs-ghcwasm.git`, and the before/after
  repro pattern reviewers want.
- `STATUS.md`: the research table (short form; details in `docs/research.md`), the per-GHC ×
  system result matrix, the coordination map below, and open questions for upstream. The
  questions cover only what the builds leave unresolved, written after implementing.
- Commit to `~/ghcwasm` as work progresses: docs/research first, then the flake, then results.

## Coordination map (goes into STATUS.md)

- **GHC upstream** (Cheng Shao/@TerrorJack is the sole wasm maintainer, and is at MuniHac; after
  implementing, list in STATUS.md only the questions the builds left open, if any; `wasm` label;
  `#haskell.wasm:matrix.org`):
  - MRs: accept `wasip1`; fix #26021; make the dyld library dir configurable (for TH).
  - Input to #25917 (high priority: "toolchain requirements checked at configure time") and
    #26812.
- **haskell-wasm forks / ghc-wasm-meta#19** ("make a proper nixpkgs package"): report the
  stock-toolchain results and ask whether the remaining fork patches can go upstream (wasm-ld
  llvm#129007).
- **nixpkgs Haskell team** (`#haskell:nixos.org`; sternenseemann, maralorn, wolfgangwalther,
  cdepillabout):
  - GHC builder PRs go to `haskell-updates`.
  - sternenseemann decides on libffi placement.
  - wolfgangwalther wants before/after repros.
  - Correct the "memory needs a fork" premise with GHC `558353f4`.
- **ilkecan**: talk first. Test and review #558928/#561449 with our results, and offer the
  GHC-only libffi wiring.
- **wasilibc** (rvolosatovs, wucke13, sepointon): the test commit goes to `master`.
- **Ericson2314** (cross-compilation design, requested on #561449).
- **haskell.nix** (hamishmack, angerman, ncaq): reference recipe.

## Risks / decision points

- If the stock toolchain fails at runtime in a way that needs a fork patch, stop and ask. The
  choice would be a GHC-scoped wasilibc variant vs. upstreaming the patch. Document the
  evidence either way.
- HEAD (10.1 snapshot) may need extra fixes. It can stay red, with documentation, without
  blocking 9.12/9.14.
- Upstream 9.12.5/9.14.1 lack the fork's backports, so wasm bugs fixed only in the fork may show
  up. Record them; prefer `ghc9142` if 9.14.1 breaks.
- 9 GHC builds, x86_64-linux under Rosetta. Pilot first, run long builds in the background with
  `-L --keep-going`, and monitor the logs.

## Verification

1. **Hygiene:**
   - `nix eval --raw -f . haskell.compiler.ghc914.drvPath` and `haskellPackages.hello.drvPath`
     must be unchanged vs `origin/haskell-updates`.
   - `nix fmt -- <changed files>` (treefmt/nixfmt, as CI does).
   - `nix-instantiate --eval` of the new release attrs.
2. **Toolchain:** `nix build -f . pkgsCross.wasm32-wasip1.wasilibc.tests` and
   `pkgsCross.wasm32-wasip1.libffi-wasm.tests`.
3. **Compilers** (from `~/ghcwasm`, following the pilot order): build
   `.#packages.<sys>.wasm-{ghc912,ghc914,ghcHEAD}` for all 3 systems. On the first success, check
   `wasm32-unknown-wasip1-ghc --info`: target platform `wasm32-unknown-wasi`, and wasm-ld in
   settings.
4. **Hello world:** `nix flake check -L --all-systems`, plus `nix run .#default -- a b`.
5. **After #558928:** repeat 3–4 for ghc914 on all systems.
6. **Report:** fill the STATUS.md result matrix and the remaining blockers, keep
   `~/ghcwasm/results/` and `docs/plan.md` current, and commit to `~/ghcwasm`.
