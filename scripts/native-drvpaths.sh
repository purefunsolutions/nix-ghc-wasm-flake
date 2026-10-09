#!/usr/bin/env bash
# Print drvPaths of native (non-wasm) Haskell derivations for a nixpkgs checkout.
# Used to prove that wasm-only changes to the GHC builder cause no native rebuilds:
#
#   scripts/native-drvpaths.sh ~/nixpkgs-ghcwasm.git > before.txt   # on the base commit
#   scripts/native-drvpaths.sh ~/nixpkgs-ghcwasm.git > after.txt    # with the changes
#   diff before.txt after.txt                                       # must be empty
set -euo pipefail

nixpkgs=${1:?usage: $0 <path-to-nixpkgs>}
systems=(aarch64-darwin x86_64-linux aarch64-linux)
attrs=(
  haskell.compiler.ghc9103
  haskell.compiler.ghc912
  haskell.compiler.ghc914
  haskell.compiler.ghcHEAD
  haskell.compiler.native-bignum.ghc914
  haskellPackages.hello
  haskellPackages.pandoc
  pkgsStatic.haskellPackages.hello
  pkgsCross.aarch64-multiplatform.haskellPackages.hello
  pkgsCross.ghcjs.haskellPackages.hello
)

for sys in "${systems[@]}"; do
  for attr in "${attrs[@]}"; do
    drv=$(nix eval --read-only --impure --raw \
      --expr "(import $nixpkgs { system = \"$sys\"; }).$attr.drvPath" 2>/dev/null || echo "EVAL-ERROR")
    printf '%s %s %s\n' "$sys" "$attr" "$drv"
  done
done
