# The MuniHac 2026 slides as a JSFFI wasm32-wasi reactor module. Template
# Haskell embeds slides.md and the README's upstream tracker at compile time.
{
  mkDerivation,
  base,
  bytestring,
  ghc-experimental,
  template-haskell,
  lib,
}:
mkDerivation {
  pname = "munihac2026presentation";
  version = "0.1.0.0";
  # The web page doesn't affect the wasm module; leave it out so that styling
  # changes don't rebuild it.
  src = lib.fileset.toSource {
    root = ../munihac2026presentation;
    fileset = lib.fileset.difference ../munihac2026presentation ../munihac2026presentation/web;
  };
  postPatch = ''
    cp ${../README.md} README.md
  '';
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    base
    bytestring
    ghc-experimental
    template-haskell
  ];
  description = "MuniHac 2026 lightning talk slides, running on GHC's wasm backend";
  license = lib.licenses.mit;
  mainProgram = "munihac2026presentation.wasm";
}
