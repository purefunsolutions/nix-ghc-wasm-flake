# GHC's wasm backend from the nixpkgs branch: the compilers as packages,
# nixpkgs' toolchain tests as checks, and for the other modules the wasm
# package set and the GHC versions to build with.
{
  perSystem =
    { pkgs, lib, ... }:
    let
      wasm = pkgs.pkgsCross.wasm32-wasip1;
      # GHC versions to build, by nixpkgs attribute name.
      ghcs = [
        "ghc912"
        "ghc914"
        "ghcHEAD"
      ];
    in
    {
      _module.args = { inherit wasm ghcs; };

      # The compilers run on `system` and produce wasm32-wasip1 code. They
      # use native bignum by default on the branch. (The `native-bignum`
      # package sets would also build native native-bignum GHCs for
      # Setup.hs, which no binary cache has.)
      packages = lib.listToAttrs (
        map (ghc: lib.nameValuePair "wasm-${ghc}" wasm.buildPackages.haskell.compiler.${ghc}) ghcs
      );

      # Toolchain sanity checks from nixpkgs: C/C++ against wasilibc, and
      # libffi-wasm's own test suite.
      checks = {
        wasilibc = wasm.wasilibc.tests.simple-c-cxx-binaries;
        libffi-wasm = wasm.libffi-wasm.tests.upstream;
      };
    };
}
