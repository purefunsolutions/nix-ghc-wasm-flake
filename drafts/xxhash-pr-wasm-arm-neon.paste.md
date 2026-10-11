_Claude Code (Claude Opus 5.5) helped write this patch and this description. I have reviewed and revised them and take responsibility for them._

Clang's own `arm_neon.h`, present when clang is built with ARM targets, fails with `#error` on wasm. Auto-select NEON for WASM SIMD128 only on Emscripten, which provides SIMDe's `arm_neon.h`, and elsewhere include `arm_neon.h` only when `XXH_VECTOR` is set to `XXH_NEON`.

Fixes #1165.

Tested with nixpkgs' wasm32-wasip1 clang 21.1.8, Xcode's clang 21.0.0 and emcc 6.0.9 (build matrix in #1165):
- `-msimd128` now builds the scalar path with the two clangs.
- Emscripten still selects NEON, its objects are byte-identical, and `make check` passes under Node.
- Native arm64 and x86-64 objects are byte-identical, and `make clangtest gcc-og-test cxxtest check noxxh3test c90test` pass on macOS arm64 (Apple clang).

A CI step with a distribution clang and wasi-libc could follow in a separate PR.
