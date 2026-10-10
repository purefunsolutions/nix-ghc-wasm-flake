# Polish backlog (temporary)

**Remove this file, and the commits that touch it, before merging the `initial` branch.**

## nixpkgs branch `ghcwasmhacking`

1. **Structure for the upstream PRs.** Group the commits into the pieces that go upstream
   separately:
   - the wasilibc test (to master);
   - ilkecan's #561449 (libffi-wasm) and #558928 (shared libraries for TH);
   - the GHC wasm backend (to haskell-updates);
   - the `haskell.compiler.ghcHEAD` static library dirs fix (to haskell-updates, independent of
     wasm);
   - the `configuration-wasm.nix` overlay.

   No PR from the branch itself; wait for the prerequisites, or open a draft PR later (see
   [docs/nixpkgs-branch.md](docs/nixpkgs-branch.md)).
2. **Default wasm package set.** Make the plain package set the default for wasm, so `Setup.hs`
   doesn't need an uncached native-bignum native GHC. Waiting for approval.
3. ~~**The JS backend's GHC HEAD failure on Hydra.**~~ Done 2026-10-10: the same haddock bug.
   The workaround now covers all cross compilers. Verified: `pkgsCross.ghcjs.haskell.packages.ghcHEAD.hello`
   builds on x86_64-linux.

## GHC upstream (branches `wip/*` in `~/ghc`)

4. Build current master with patches 0001–0005 through nixpkgs: the native GHC on x86_64-linux
   (for 0005), and the wasm GHC with the hellos on darwin and Linux. Then write the MR texts.
   GPG-sign before pushing anything.
5. Issues for GHC 10's darwin host settings (librt, leading underscore, otool,
   install_name_tool; related: #26720) and the haddock index failure in GHC 10 cross builds.
   For the latter: master-only (not in `ghc-10.0`). **Bisected** to `23c9b6c392` "hadrian: Build
   stage 2 cross compilers" (parent `521e55bf69` good). Still to find out why GHC's own cross CI
   doesn't hit it (see `results/notes.md`).

## ghc-wasm-flake

6. A usage section in the README (the polished README has none yet). Maybe condense
   `results/notes.md` to final findings.
7. The NUC copy: move it from `~/ghcwasm` to `~/ghc-wasm-flake`?

## Developer tooling (asked at MuniHac)

9. **Haskell Language Server** for wasm projects: what works today, and what nixpkgs and this
   flake could provide. See `docs/tooling.md`.
10. **Debug tools** for wasm programs: GHCi and its debugger, RTS tracing and eventlog,
    profiling, and native-level debuggers. See `docs/tooling.md`.

## Coordination drafts

8. A status comment for nixpkgs #225000; notes for ilkecan (#558928 works as-is, and a
   suggestion to build `libffi.so` in #561449); a short list of open questions for Cheng Shao.

## Deliberately deferred

- Hackage packages on wasm: fix them when example packages are added to this flake, with the
  overrides they need in `configuration-wasm.nix`. When preparing the upstream PR, add a curated
  list of wasm Hydra jobs (e.g. the packages ghc-wasm-meta tests).
- A narrow `lld` variant with the wasm-ld patch (llvm#129007), only if large TH libraries hit
  V8's function size limit.
- `wasilibc` performance flags (SIMD string functions, `-O3`) as a separate nixpkgs change.
- The JS backend (`pkgsCross.ghcjs`) on aarch64-darwin and aarch64-linux: untested. Hydra skips
  aarch64-linux (output over 3 GB) and hasn't built darwin since 2024, so it's unknown whether the
  JS backend builds on macOS at all. Only x86_64-linux is checked, on the NUC.
