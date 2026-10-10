# Draft: test report for GHC !16790 (not posted)

For https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16790 ("compiler: ensure cross ghc --info
output target unit ids", fixes #27919), by Cheng Shao. Paste as a comment on the MR, or tell
Cheng in person.

---

I tested this MR (head `95f24e6b`) with a wasm GHC built from source by nixpkgs: stock LLVM 21,
upstream wasi-libc 32, target `wasm32-unknown-wasip1`, built with `--hash-unit-ids`, host
aarch64-darwin. It's applied on top of GHC master `556db2f3` (2026-08-10), which nixpkgs'
`ghcHEAD` currently uses. The diff applies cleanly there, with only line offsets.

Without the MR, `ghc --info` and `ghc-pkg field <pkg> id` disagree for all three units, e.g.
`ghc-internal-10.100.0-169f` against `ghc-internal-10.100.0-ddf4`. cabal-install 3.18.1.0 then
fails even on a base-only package (with `active-repositories: :none`):

```
[__1] trying: base-4.23.0.0/installed-ffb7 (dependency of hello-pure)
[__2] next goal: ghc-internal (dependency of base)
[__2] rejecting: ghc-internal-10.100.0/installed-ddf4 (constraint from non-reinstallable package requires installed instance with unit id ghc-internal-10.100.0-169f)
```

With the MR, `base`, `ghc-internal` and `ghc` all match, `cabal build` succeeds, and the
resulting `.wasm` runs under wasmtime.

(Tested with the help of Claude Code.)
