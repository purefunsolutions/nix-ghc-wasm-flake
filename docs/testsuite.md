# GHC's testsuite and our wasm builds

Asked at MuniHac 2026: have we run GHC's testsuite? Investigated 2026-10-12; nothing was run
for this.

## Short answers

- **We haven't run it.** Our checks are the hello worlds (C FFI, a libffi `"wrapper"` callback,
  native bignum), Template Haskell, the GHCi debugger and profiling: GHC 9.12, 9.14 and HEAD on
  three systems.
- **nixpkgs never runs it**, for any GHC: `common-hadrian.nix` has no `checkPhase` or `doCheck`.
  The test suites of Haskell packages are off for cross builds too (`doCheck ? !isCross` in
  `generic-builder.nix`).
- **GHC's CI runs it for wasm.** The master job of 2026-10-11 (job 2671530) ran 11,394 tests in
  46,612 test cases. Of those, 36,626 were skipped. The rest gave 9,868 expected passes, 88
  expected failures, 30 fragile tests and no unexpected results.
- **Our !16795 got the same run.** sheaf added ~wasm, and the pipeline after it (job 2671164 in
  `mikatammi/ghc`) gave 9,865 expected passes, 88 expected failures, 30 fragile tests and no
  unexpected results.
  - Caveat: CI uses the forked toolchain and `--target=wasm32-wasi`. So this shows the patch
    doesn't break the existing path. Only our nixpkgs builds exercise `wasm32-unknown-wasip1`.

## What the testsuite is

- `testsuite/` in the GHC tree, run by a Python driver (`testsuite/driver/runtests.py`). On master,
  686 `.T` files declare about 11,000 tests.
- Each test runs in one or more _ways_: normal, optasm, threaded, profiled, ghci, …. That gives
  46,600 test cases for wasm, most of which wasm skips.
- A test compiles and/or runs a program and checks the exit code, stdout and stderr against
  expected files. Performance tests also check metrics.
- **How to run it:**
  - `hadrian/build test` in a build tree, or against an installed compiler with
    `--test-compiler=<ghc>`;
  - narrow it with `--only=`, `--test-way=` and `--test-speed=fast|normal|slow`.
- **Cross compilers** run their test programs through a _target wrapper_. Hadrian passes
  `$CROSS_EMULATOR` as `--target-wrapper` (`hadrian/src/Settings/Builders/RunTest.hs:241,314`).

## How GHC's CI runs it for wasm

- **The job:** `x86_64-linux-alpine3_23-wasm-cross_wasm32-wasi-release+host_fully_static+text_simdutf`.
  It builds and installs a bindist, then runs `hadrian test --test-compiler=<installed wasm32-wasi-ghc>` (`test_hadrian` in `.gitlab/ci.sh`).

- **The target wrapper** is ghc-wasm-meta's `wasm-run.mjs`. It runs each module with node's WASI
  (`node:wasi`) and stubs missing imports. ghc-wasm-meta's `setup.sh` writes
  `CROSS_EMULATOR=…/wasm-run.mjs` into the env file that `ci.sh` sources. ghc-wasm-meta also
  ships a `wasmtime.sh` wrapper.

- **Settings and time:** normal speed (`config.speed=1`) on 4 threads. The tests take about 16
  minutes; the whole job takes about 2 hours.

- **When it runs:**

  - on every master push and in the nightly pipeline (the native-bignum and unregisterised variants
    run nightly or by hand);
  - in an MR pipeline when the MR has a label matching `/.*wasm.*/` (e.g. ~wasm) or ~"full-ci"
    (`.gitlab/generate-ci/gen_ci.hs:576`, `683-685`, `762-772`, `1367`);
  - in Marge's batch merges, which count as full-ci, so it always runs before a merge.

  GitLab reads the labels when it creates a pipeline. After a label is added, a new pipeline is
  needed.

## Running it without nixpkgs

1. **GHC's CI through our MRs.** No cost to us: ask `@triagers` for ~wasm. It tests the forked
   toolchain with `wasm32-wasi`.

1. **Upstream wasi-sdk, outside Nix**, for example on x86_64-linux:

   - build master plus !16795 and !16794 with upstream wasi-sdk 34 (`--target=wasm32-wasip1`),
     libffi-wasm (its prebuilt artifact, or built with its Haskell generator) and node;
   - then run `hadrian test` with a wasm runner;
   - about 1–1.5 hours to build plus 20–30 minutes of tests, and a few hundred MB of downloads.

   This is the cleanest answer to "do the patches work without nixpkgs".

1. **GHC's testsuite against a nixpkgs compiler:**

   - check out the GHC source that matches a nixpkgs wasm GHC (e.g. `ghc-9.14.1-release`) and
     build hadrian with a native GHC;
   - run `hadrian test --test-compiler=<nixpkgs wasm ghc>` with a runner;
   - there's no GHC rebuild, and it tests the stock-toolchain build directly;
   - without `--test-have-intree-files`, tests that need the build tree are skipped.

## What it would take in nixpkgs

- **A separate derivation**, e.g. `passthru.tests.testsuite`, not `checkPhase`. The run is long,
  needs a list of known failures, and shouldn't force a rebuild of the compiler.

- **What already exists:**

  - `ghcSrc`, which contains `testsuite/`;
  - `passthru.hadrian` (`common-hadrian.nix:1090`);
  - the installed compiler, python3, and node (already used for TH).

  The run itself would be `hadrian test --test-compiler=${ghc}/bin/wasm32-unknown-wasip1-ghc`
  with `CROSS_EMULATOR` set.

- **A runner:** nixpkgs' emulator for WASI is plain `wasmtime` (`lib/systems/default.nix:118-119`),
  which can't see the test's directory without `--dir`. That needs a small wrapper: wasmtime with
  `--dir .` and the environment passed through, or node like `wasm-run.mjs`.

- **Known failures:**

  - the first run will show tests that fail for environment reasons (the sandbox, store paths, the
    toolchain differences in `toolchain-vs-forks.md`); they go into a `--broken-test` list;
  - perf tests need `--skip-perf-tests`, since their metrics depend on the machine.

- **Cost:** 20–30 minutes per GHC version and platform, on top of the compiler. A flake check in
  this repository is the easier place to start; nixpkgs can come later.

- **Package test suites** are a separate matter. generic-builder could run Cabal `test-suite`s for
  wasm through `Setup test --test-wrapper` (Cabal's `Distribution/Simple/Setup/Test.hs:228`) with
  a wasmtime wrapper, instead of `doCheck = false`.
