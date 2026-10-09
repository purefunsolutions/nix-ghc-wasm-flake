# Template Haskell hello world: the splices run in GHC's wasm interpreter.
{
  mkDerivation,
  base,
  template-haskell,
  lib,
}:
mkDerivation {
  pname = "hello-th";
  version = "0.1.0.0";
  # The Haskell project only: this file and the expected output don't
  # rebuild it.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./hello-th.cabal
      ./Main.hs
      ./Greeting.hs
    ];
  };
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    base
    template-haskell
  ];
  description = "Template Haskell hello world for GHC's wasm backend";
  license = lib.licenses.mit;
  mainProgram = "hello-th.wasm";
}
