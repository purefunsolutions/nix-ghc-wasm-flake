# Test report for GHC !16790 (posted 2026-10-10)

For https://gitlab.haskell.org/ghc/ghc/-/merge_requests/16790, by Cheng Shao. Mika posted the
text below as a comment on the MR.

---

I tested this MR (`95f24e6b`) on a different toolchain: a wasm cross GHC that nixpkgs builds
from source with stock LLVM 21 and upstream wasi-libc 32, with `--hash-unit-ids`, on
aarch64-darwin. The MR is applied on top of master `556db2f3`, the commit nixpkgs' `ghcHEAD`
currently uses.

Without the MR, I get the bug from #27919: `ghc --info` and `ghc-pkg` report different unit ids
for `base`, `ghc-internal` and `ghc`, and cabal-install 3.18.1.0 can't build even a base-only
executable (`Cabal-7107`, "requires installed instance with unit id ghc-internal-10.100.0-169f").

With the MR, all three unit ids match, `cabal build` succeeds, and the resulting `.wasm` runs
under wasmtime.

I only tested the installed compiler with cabal-install; this doesn't say anything about the
`compiler/Setup.hs` question from the review.
