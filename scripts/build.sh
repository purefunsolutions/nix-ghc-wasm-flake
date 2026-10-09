#!/usr/bin/env bash
# Build one GHC version's wasm pipeline for one system: the wasm compiler, hello-pure,
# hello-wasm and hello-th, and their wasmtime checks. Logs to results/logs/<system>-<ghc>.log
# and appends "exit=<code>".
#
#   scripts/build.sh <system> <ghc> [extra nix args...]
#   scripts/build.sh aarch64-darwin ghc912
#   # with a local checkout of the nixpkgs branch instead of the GitHub one:
#   scripts/build.sh x86_64-linux ghc914 --override-input nixpkgs "git+file://$HOME/nixpkgs-ghcwasm.git?ref=ghcwasmhacking"
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

sys=${1:?system}
ghc=${2:?ghc attribute, e.g. ghc912}
shift 2

mkdir -p results/logs
log=results/logs/$sys-$ghc.log
targets=(
  ".#packages.$sys.wasm-$ghc"
  ".#packages.$sys.hello-pure-$ghc"
  ".#checks.$sys.hello-pure-$ghc"
  ".#packages.$sys.hello-$ghc"
  ".#checks.$sys.hello-$ghc"
  ".#packages.$sys.hello-th-$ghc"
  ".#checks.$sys.hello-th-$ghc"
)

nix build --no-link --keep-going -L "$@" "${targets[@]}" >"$log" 2>&1
rc=$?
echo "exit=$rc" >>"$log"
exit "$rc"
