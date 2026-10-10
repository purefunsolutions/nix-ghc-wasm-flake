# Developer tooling for GHC's wasm backend: HLS and debugging

Asked at MuniHac 2026: does this work support the Haskell Language Server and debug tools?
Analysed 2026-10-10. The hands-on results are from nixpkgs' wasm GHC 9.14 (branch
`ghcwasmhacking`) on aarch64-darwin.

## Summary

| Tool | Status with our nixpkgs wasm GHC |
| -- | -- |
| GHCi, including the GHCi debugger | **works** (tested) |
| GHCi browser mode (`-fghci-browser`) | upstream feature; needs extra node packages, not tried |
| Debug RTS, `+RTS -D…` tracing | available (RTS ways `v debug debug_dyn dyn`) |
| Eventlog, heap profile by closure type | **works** (tested) |
| Cost-centre profiling (`-prof`, `+RTS -p`, `-xc`, `-hc`) | **works** (tested); time samples are always 0 on wasm |
| Source-level debugging in lldb or browser DevTools | **not possible**: GHC's wasm code generator emits no DWARF |
| Haskell Language Server on wasm-specific code | **not supported** upstream, no roadmap |
| HLS with a native GHC of the same version | works today, with limits (see below) |

## Debugging

### GHCi and its debugger: works

GHC's user's guide (`docs/users_guide/wasm.rst`) says "All existing GHCi features work with
wasm, including the GHCi debugger". GHCi runs through the same node-based interpreter
(`dyld.mjs`) as Template Haskell, which nixpkgs sets up. Tested with
`wasm32-unknown-wasip1-ghc --interactive`:

```
Breakpoint 1 activated at Fact.hs:5:10-25
Stopped in Main.fact, Fact.hs:5:10-25
n :: Integer = 20
5  fact n = n * fact (n - 1)
```

So breakpoints, `:step`, `:list` and inspecting bindings all work.

GHC 9.14+ also has a **browser mode** (`-fghci-browser`): GHCi drives a page in a real browser,
for live-coding frontends. It needs the `ws` node package, and optionally puppeteer or
playwright. nixpkgs doesn't provide those to GHC yet, so this is untested.

### RTS tools: work, except cost-centre profiling

- **Debug RTS:** our wasm GHC ships the `debug` RTS way, so `-debug` and `+RTS -D…` tracing are
  available.
- **Eventlog and heap profiles by closure type:** these need a directory the program can write
  to (`wasmtime run --dir .`). Tested: `+RTS -l -hT` wrote `fact.wasm.eventlog` and `fact.hp`.
- **Cost-centre profiling** (`-prof`, `+RTS -p`, `-xc`, `-hc`) works. The nixpkgs branch
  first disabled profiled libraries for wasm. Since 2026-10-11 they're built like for native and
  JS GHCs (RTS ways `v debug debug_p debug_p_dyn debug_dyn p p_dyn dyn`). Tested with 9.14:
  `+RTS -xc` prints full cost-centre stacks, and `+RTS -p` writes a complete allocation profile.
  The time columns always show 0 ticks: WASI has no timer signals, so the RTS can't sample
  time.

### Native debuggers: wasm level only

`-g` produces no DWARF. Tested: no `.debug_*` sections in the object file or the linked `.wasm`.
GHC's wasm code generator doesn't emit debug info for Haskell code, and the link flags also strip
it (`--strip-debug`). Tools like wasmtime + lldb or Chrome DevTools can still step through the
wasm code with function names, which is rarely useful for Haskell code. This is an upstream GHC
limitation; nixpkgs can't fix it.

For frontend apps, the usual tools are the browser console, JS stack traces, `Debug.Trace` and
GHCi browser mode.

## Haskell Language Server

### Why HLS can't simply target wasm

HLS is an alternative frontend to GHC: it links the GHC API and loads the project's dependency
interface files (`.hi`). Those must come from _exactly_ the same compiler. For a wasm project
they're produced by the wasm cross compiler, for a 32-bit target. A native HLS can't load them,
and an HLS built "for wasm" would itself run in wasm.

A real wasm-aware HLS would need three things:

- a native build of the cross compiler's GHC API, configured for the wasm target (cross
  compilers don't install one today);
- HLS built against it;
- Template Haskell evaluated through the wasm interpreter.

The HLS maintainers said in January 2025 that HLS doesn't support ghc-wasm and that they have no
roadmap for it
([haskell-language-server#4486](https://github.com/haskell/haskell-language-server/issues/4486)).
This is upstream work in GHC and HLS, not something nixpkgs can package. GHC 10's restructuring
of cross compilers (the "stage 2 cross compilers" work) may change what a cross compiler can
ship, but nobody has announced plans for HLS on top of it.

### What works today: native HLS of the same GHC version

nixpkgs builds the wasm GHC and the native GHC from the same source and version, and has native
HLS 2.15.0.0 for 9.12, 9.14 and HEAD. So a project can use:

- the **native** GHC, its dependencies from the native `haskellPackages`, and HLS, for the
  editor;
- the **wasm** GHC for the actual build (`pkgsCross.wasm32-wasip1.haskell.packages.<ghc>`).

Nix makes this easier than in most setups, because both package sets come from the same
definitions.

The limit is wasm-specific code: JavaScript FFI imports (`foreign import javascript`),
`GHC.Wasm.Prim` and `#if defined(wasm32_HOST_ARCH)` branches don't typecheck natively, or show
the native branch. The usual answer, also suggested in HLS#4486: keep most of the app in a
platform-independent library, with a thin wasm entry point.

## Possible next steps

1. **ghc-wasm-flake devShell:** add native HLS for the same GHC version, plus native
   dependencies via `shellFor`, next to the wasm GHC and cabal. Also add a `hie.yaml` example
   and document the library + thin entry point layout.
1. **A GHCi check in the flake:** run a scripted GHCi session with a breakpoint, so the debugger
   stays tested on every lock bump.
1. ~~**Profiling in nixpkgs**~~: done, profiled libraries are back on for wasm. All three GHCs
   build and pass their checks with them on all three systems.
1. **GHCi browser mode in nixpkgs:** provide the node packages it needs (`ws`, optionally
   playwright) and test it.
1. Nothing for DWARF or a wasm-aware HLS; those need GHC and HLS work upstream.
