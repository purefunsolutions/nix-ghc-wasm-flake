# Draft: test report for GHC !16790 (not posted)

For https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16790 ("compiler: ensure cross ghc --info
output target unid ids", fixes #27919), by Cheng Shao. Paste as a comment on the MR, or tell
Cheng in person. Written 2026-10-10 after the review threads with Teo Camarasu; it doesn't cover
the open `compiler/Setup.hs` question, and says so.

---

Independent confirmation from a different toolchain: I tested the MR at `95f24e6b` on a wasm
cross GHC that nixpkgs builds from source, with stock LLVM 21 and unmodified upstream wasi-libc
32 (target `wasm32-unknown-wasip1`), `--hash-unit-ids`, host aarch64-darwin. The MR is applied
on top of GHC master `556db2f3` (2026-08-10), which is what nixpkgs' `ghcHEAD` tracks. It applies
there with only line offsets.

Before: `ghc --info` and `ghc-pkg field <pkg> id` disagree on all three units (for example
`ghc-internal-10.100.0-169f` in `--info` against `ghc-internal-10.100.0-ddf4` in the package
db). cabal-install 3.18.1.0 then can't solve even a base-only executable, with
`active-repositories: :none`:

```
[__1] trying: base-4.23.0.0/installed-ffb7 (dependency of hello-pure)
[__2] next goal: ghc-internal (dependency of base)
[__2] rejecting: ghc-internal-10.100.0/installed-ddf4 (constraint from non-reinstallable package requires installed instance with unit id ghc-internal-10.100.0-169f)
```

After: `base`, `ghc-internal` and `ghc` agree between `--info` and `ghc-pkg`, `cabal build`
succeeds, and the resulting `.wasm` runs under wasmtime.

This only exercises the `ghc` + `ghc-pkg` + cabal-install path on an installed bindist-style
tree; it says nothing about the `compiler/Setup.hs` / cabal-reinstall question from the review.

(Tested with the help of Claude Code.)
