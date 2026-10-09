{
  description = "Pure-Nix GHC wasm hello world, a testbed for GHC's wasm backend in nixpkgs";

  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # nixpkgs with the work-in-progress wasm support, including Template
    # Haskell: github.com/mikatammi/nixpkgs, whose branch ghcwasmhacking is
    # based on haskell-updates and rebased now and then. Every update also
    # gets a dated branch that never moves, ghc-wasm-flake-<date>; this
    # points at the newest one, so older revisions of this flake keep
    # working. To try changes in a local checkout of the branch, add
    #   --override-input nixpkgs git+file:///path/to/nixpkgs?ref=ghcwasmhacking
    nixpkgs.url = "github:mikatammi/nixpkgs/ghc-wasm-flake-20261028b";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ./nix ];
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
}
