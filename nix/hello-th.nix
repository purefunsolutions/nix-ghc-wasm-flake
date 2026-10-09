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
  src = ../hello-th;
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
