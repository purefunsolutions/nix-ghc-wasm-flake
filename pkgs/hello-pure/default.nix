# Minimal pure-Haskell hello world (no C code, no FFI).
{
  mkDerivation,
  base,
  lib,
}:
mkDerivation {
  pname = "hello-pure";
  version = "0.1.0.0";
  # The Haskell project only: this file and the expected output don't
  # rebuild it.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./hello-pure.cabal
      ./Main.hs
    ];
  };
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [ base ];
  description = "Minimal pure-Haskell hello world for GHC's wasm backend";
  license = lib.licenses.mit;
  mainProgram = "hello-pure.wasm";
}
