# `nix develop`: the wasm GHC 9.14 with cabal-install, wasmtime and node.
{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.packages.wasm-ghc914
          pkgs.cabal-install
          pkgs.wasmtime
          pkgs.nodejs
        ];
      };
    };
}
