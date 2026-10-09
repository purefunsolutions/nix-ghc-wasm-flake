# Draft: GHC merge request: accept `wasip1` in WASI target triples

Status: **draft, not submitted.** Patch: [`../upstream/ghc/0001-configure-accept-wasip1-as-the-OS-part-of-WASI-target-triples.patch`](../upstream/ghc/0001-configure-accept-wasip1-as-the-OS-part-of-WASI-target-triples.patch)
(against `master`; also applies to `ghc-9.12` (9.12.5-rc3) and `ghc-9.14` (9.14.1)).

Before submitting: check whether it still applies, and decide whether to open an issue first.
Possibly ask Cheng Shao (@TerrorJack) whether he'd prefer it framed differently.

---

**Title:** configure: accept `wasip1` as the OS part of WASI target triples

**Description:**

WASI preview 1 targets are nowadays commonly spelled `wasm32-*-wasip1`:
- LLVM uses that name; it warns about plain `wasm32-wasi` since LLVM 22 (llvm#165345).
- wasi-sdk uses it; plain `wasm32-wasi` targets were dropped in wasi-sdk 34 (wasi-sdk#637).
- Rust uses it.
- nixpkgs uses it (`pkgsCross.wasm32-wasip1`, config `wasm32-unknown-wasip1`).

`GHC_CONVERT_OS` only accepts `wasi`, so configuring a cross compiler with
`--target=wasm32-unknown-wasip1` fails with `Unknown OS wasip1`. ghc-toolchain's `parseOs`
has the same limitation (non-fatal, since configure only uses it as a cross-check).

This MR maps `wasip1` to `wasi` in both places. Everything after the conversion stays as it is:
- `TargetPlatform` becomes `wasm32-unknown-wasi`, so GHC's settings and Cabal's `os(wasi)` are
  unaffected.
- Only the program prefix (taken from the full target triple) keeps the user's spelling.

`wasip2` is deliberately not accepted: preview 2 is a different ABI that GHC doesn't target.

**Testing:** _(TODO: fill in from STATUS.md's result matrix before posting; claim only what
actually passed.)_
- nixpkgs builds wasm32-wasip1 cross compilers with this patch: versions/systems: TODO.
- Configure output for `--target=wasm32-unknown-wasi` is unchanged: TODO (verify).

_This patch and description were written with the help of an AI assistant (Claude Code). I
reviewed and tested them._
