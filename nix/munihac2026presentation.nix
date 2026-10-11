# The MuniHac 2026 lightning talk as a static web page. Everything is inlined
# into index.html, so result/index.html opens without a web server.
{
  lib,
  stdenvNoCC,
  fetchurl,
  esbuild,
  nodejs,
  qrencode,
  # The wasm GHC that built presentation-wasm, for its post-linker.
  ghc,
  presentation-wasm,
}:
let
  browser-wasi-shim = fetchurl {
    url = "https://registry.npmjs.org/@bjorn3/browser_wasi_shim/-/browser_wasi_shim-0.4.2.tgz";
    hash = "sha512-/iHkCVUG3VbcbmEHn5iIUpIrh7a7WPiwZ3sHy4HZKZzBdSadwdddYDZAII2zBvQYV0Lfi8naZngPCN7WPHI/hA==";
  };
in
stdenvNoCC.mkDerivation {
  pname = "munihac2026presentation";
  version = "0.1.0.0";
  src = ../munihac2026presentation/web;

  nativeBuildInputs = [
    esbuild
    nodejs
    qrencode
  ];

  buildPhase = ''
    runHook preBuild

    cp ${lib.getExe presentation-wasm} munihac2026presentation.wasm
    # The installed post-link.mjs has a broken shebang, so run it with node.
    node "$(${lib.getExe' ghc "${ghc.targetPrefix}ghc"} --print-libdir)/post-link.mjs" \
      -i munihac2026presentation.wasm -o ghc_wasm_jsffi.js

    mkdir -p node_modules/@bjorn3/browser_wasi_shim
    tar -xzf ${browser-wasi-shim} --strip-components=1 -C node_modules/@bjorn3/browser_wasi_shim

    # One module with the wasm inlined, itself inlined into index.html:
    # browsers refuse to fetch() or import modules from file:// URLs. (It must
    # be a module: the JSFFI glue uses top-level await.)
    esbuild main.js --bundle --format=esm --loader:.wasm=binary \
      --log-level=warning --outfile=presentation.js
    node -e '
      const fs = require("fs");
      const html = fs.readFileSync("index.html", "utf8");
      const js = fs.readFileSync("presentation.js", "utf8");
      fs.writeFileSync("index.html", html.replace(
        "<!-- presentation.js: inlined here by the build -->",
        () => "<script type=\"module\">\n" + js + "</script>"));
    '

    # A QR code for every "@qr <url>" line, named the way Main.qr expects.
    grep '^@qr ' ${../munihac2026presentation/slides.md} | while read -r _ url; do
      qrencode -t SVG -m 2 -o "qr-$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_').svg" "$url"
    done

    # What the browser downloads, uncompressed: the page with the inlined
    # module, the stylesheet and the images. Shown on the live slide.
    total=$(cat index.html style.css qr-*.svg *.png | wc -c | tr -d ' ')
    sed -i "s|<main id=\"stage\">|<main id=\"stage\" data-bytes=\"$total\">|" index.html

    runHook postBuild
  '';

  # Nothing to patch or strip in a web page.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out index.html style.css qr-*.svg *.png \
      munihac2026presentation.wasm ghc_wasm_jsffi.js
    runHook postInstall
  '';

  meta = {
    description = "MuniHac 2026 lightning talk about GHC's wasm backend in nixpkgs";
    license = lib.licenses.mit;
  };
}
