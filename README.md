# ghc-wasm-flake Flake

This flake makes it possible to build projects that use GHC's WebAssembly
backend as pure Nix derivations, so building them works the same way as with
any other GHC in nixpkgs instead of assembling the toolchain imperatively in a
devshell. This repository also tracks the upstream pull requests in nixpkgs
and GHC needed to make this work, and aims to support upstream development of
the GHC WASM backend.

## Conventions

This repository broadly follows the
[nixpkgs contributing conventions](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md),
though not necessarily in every detail. In particular, commits follow the
nixpkgs automation/AI policy: any non-trivial use of AI tooling is disclosed
with an `Assisted-by:` commit trailer naming the tool and model used.
