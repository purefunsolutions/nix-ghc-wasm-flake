// Starts the slides: a Haskell program compiled by GHC's wasm backend. The
// JSFFI glue comes from GHC's post-linker, and esbuild bundles everything,
// the wasm module included, into one classic script that works from file://.
import { ConsoleStdout, File, OpenFile, WASI } from "@bjorn3/browser_wasi_shim";
import ghc_wasm_jsffi from "./ghc_wasm_jsffi.js";
import wasm from "./munihac2026presentation.wasm";

(async () => {
  try {
    const wasi = new WASI(
      [],
      [],
      [
        new OpenFile(new File([])),
        ConsoleStdout.lineBuffered((line) => console.log(`[haskell] ${line}`)),
        ConsoleStdout.lineBuffered((line) => console.warn(`[haskell] ${line}`)),
      ],
      { debug: false },
    );
    globalThis.presentationWasmBytes = wasm.byteLength;
    const exports = {};
    const { instance } = await WebAssembly.instantiate(wasm, {
      wasi_snapshot_preview1: wasi.wasiImport,
      ghc_wasm_jsffi: ghc_wasm_jsffi(exports),
    });
    Object.assign(exports, instance.exports);
    wasi.initialize(instance);
    await instance.exports.hs_start();
  } catch (err) {
    console.error(err);
    const message = document.createElement("pre");
    message.className = "error";
    message.textContent = `The Haskell program failed to start:\n${err}`;
    document.getElementById("slide").replaceChildren(message);
  }
})();
