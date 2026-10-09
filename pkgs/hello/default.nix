# Hand-written in the style of cabal2nix, so building needs no IFD.
{
  mkDerivation,
  base,
  lib,
}:
mkDerivation {
  pname = "hello-wasm";
  version = "0.1.0.0";
  # The Haskell project only: this file and the expected output don't
  # rebuild it.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./hello-wasm.cabal
      ./app
      ./cbits
    ];
  };
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [ base ];
  description = "Hello world for GHC's wasm backend, built purely with Nix";
  license = lib.licenses.mit;
  # Cabal gives wasm executables a .wasm extension.
  mainProgram = "hello-wasm.wasm";
}
