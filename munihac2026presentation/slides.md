@class title
@logo

# GHC's wasm backend, purely from nixpkgs

Mika Tammi, MuniHac 2026

This slide deck is itself a Haskell program. The wasm GHC this talk is about compiled it, in a pure Nix build (`nix build .#munihac2026presentation`), and your browser is running it right now.

JavaScript only loads it. Everything you'll see from here on is drawn by Haskell.

---

@class story

# How we got here

| When | |
|---|---|
| Before | Haskell in the browser used to mean GHCJS, a fork of GHC. Forks have to chase every release, and GHCJS never got past 8.10. It also produced enormous JavaScript: in my experience 40 MB and more, uncompressed, even for simple things. |
| Mar 2023 | GHC 9.6 brought WebAssembly and JavaScript backends into GHC itself, maintained with the rest of the compiler. Whether the JS backend's output got smaller I haven't checked; in 2024 a hello world was still a few megabytes before minification. |
| Apr 2023 | sternenseemann opened [nixpkgs#225000](https://github.com/NixOS/nixpkgs/pull/225000) to package the wasm backend. It needed a patched wasi-libc, a forked wasi-sdk and LLVM, patches to GHC and a custom libffi, and it stalled that summer. |
| 2024 | GHC's runtime stopped needing the patched libc. At MuniHac 2024, I started looking at whether a pure Nix build was possible at all; back then it looked like a great deal of work. |
| 2026 | ilkecan packaged libffi-wasm and the shared libraries Template Haskell needs. Of the four things that stopped #225000, two are gone and the LLVM fork is optional. This weekend, GHC 9.12, 9.14 and HEAD all built from source. |

@tracker-summary

After that comes the unglamorous part: Hydra jobs, a binary cache and Hackage packages, so the wasm backend becomes as ordinary in nixpkgs as native GHC, or as the JS backend, which Hydra already builds. Debugging tools need work too: GHC's wasm code generator emits no DWARF, so there's no source-level stepping in lldb or browser DevTools yet, and profiles record no time samples.

---

@class results

# Nine compilers, all green

Each of these is a wasm32-wasi GHC that nixpkgs built from source with the toolchain it already ships: LLVM 21 and the upstream wasi-libc 32. No bindists, no forks. If you've worked with Nix you know why that matters: a pure derivation can be cached and reproduced, while a toolchain assembled by hand in a devshell cannot. The aim is to make Haskell on WebAssembly as easy to pick up as any other GHC in nixpkgs.

| | aarch64-darwin | aarch64-linux | x86_64-linux |
|---|---|---|---|
| GHC 9.12 | ✓ | ✓ | ✓ |
| GHC 9.14 | ✓ | ✓ | ✓ |
| GHC HEAD | ✓ | ✓ | ✓ |

In every cell, three small programs compile and run under wasmtime: a pure hello world, one that calls into C, and one whose Template Haskell splices run in GHC's wasm interpreter. GHCi and profiling work too.

The first green build happened on Friday, right here. Much of what the tracker lists comes from one thing: GHC's own wasm toolchain ships forked LLVM and wasi-sdk, and GHC's CI tests only against those, so the differences surface the moment a distribution builds with its own, newer LLVM and wasi-libc.

---

@class upstream
@qr https://github.com/purefunsolutions/nix-ghc-wasm-flake/tree/initial

# Tracked in the README

[github.com/purefunsolutions/nix-ghc-wasm-flake](https://github.com/purefunsolutions/nix-ghc-wasm-flake/tree/initial) tracks how far GHC's WebAssembly support has got in nixpkgs, and gives you an experimental preview of it before it's merged.

@tracker

---

@class screenshot

# nix build, then wasmtime run

@image wasmtime-hello-runs.png Terminal: the pure, C FFI and Template Haskell hello programs built with nix build and run under wasmtime

---

# Live, right now, in your browser

@live

---

@class webgl
@webgl

# Live: WebGL, with Haskell driving every frame

- The lambda is a 3D model from a .glb file, parsed by Template Haskell when the slide deck was built.
- The four thousand stars come from a Haskell random number generator and are drawn as instanced quads.
- The floor is the scene rendered a second time, mirrored, into a texture, then read back through bumpy normals, which is why it only partly reflects.
- Every WebGL call is a JSFFI import, and every frame begins with a Haskell callback.

---

@class aside
@qr https://github.com/purefunsolutions/haskell-ghc-maintainer-skill

# Also out of this weekend

A side product of the weekend is **[haskell-ghc-maintainer-skill](https://github.com/purefunsolutions/haskell-ghc-maintainer-skill)**, an Agent Skill that teaches coding agents how GHC wants contributions done: check for an existing issue, file one first, keep the change small, follow GHC's LLM policy, fill in the merge request template honestly, and ask for labels and backports. It's a work in progress, and it came out of fixing [#27926](https://gitlab.haskell.org/ghc/ghc/-/issues/27926).

Claude Opus 5.5 and Claude Fable 5.1 have been working hard this weekend as well, and every commit says so in its Assisted-by trailer. Between them they set off thirty-six GHC builds on this laptop alone since Friday, plus the ones on the Linux machines, and a few are still running as I speak; the CPUs have been at 100 % the whole time, and the fans haven't stopped.

---

@class thanks
@qr https://github.com/purefunsolutions/nix-ghc-wasm-flake/tree/initial

# Thank you

Most of what you've seen is other people's work; the hard parts were done long before this weekend. I've mostly been integrating them, so that Haskell on WebAssembly is one flake input away for anyone who uses Nix.

- To the MuniHac organizers, for the weekend and the room.
- To the GHC maintainers, and to everyone building GHC's WebAssembly support, with a special mention to Cheng Shao.
- To the NixOS and nixpkgs Haskell maintainers, and in particular to ilkecan, sternenseemann and dmjio, whose work this builds on directly.

If you want to try it, this is all it takes, though with no binary cache yet it builds GHC from source:

```
nix build github:purefunsolutions/nix-ghc-wasm-flake/initial#munihac2026presentation
open result/index.html
```
