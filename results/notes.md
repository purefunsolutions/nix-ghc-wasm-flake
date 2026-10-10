# Build notes (chronological)

Findings while building. Raw logs are in `results/logs/` (not committed).

## 2026-10-09

- **Cache coverage on haskell-updates.**
  - Hydra's haskell-updates jobset last evaluated `4e9d3032` (2026-09-30).
  - Even there, only x86_64-linux Haskell outputs are in cache.nixos.org. On aarch64-darwin and
    aarch64-linux, the bootstrap GHC 9.10.3, the default GHC 9.12.5 (needed for libffi-wasm's
    code generator) and per-version build GHCs (for `Setup.hs`) all have to be built locally.
  - The wasm C toolchain (wasilibc 32, compiler-rt), wasmtime and node are cached everywhere.
- **wasilibc C/C++ test** (`pkgsCross.wasm32-wasip1.wasilibc.tests.simple-c-cxx-binaries`)
  passes on aarch64-darwin.
- **darwin libiconv leak.** On a darwin host, the unspliced darwin `libiconv`
  (`libiconv-115.100.1`, host `arm64-apple-darwin`) ended up in the wasm GHC's `depsTargetTarget`.
  On x86_64-linux the splice works and gives `wasilibc-iconv-32`. Fixed by excluding libiconv
  from the wasm target's `libDeps`, as #225000 originally did.
- **lld flavour.** `wasm32-unknown-wasip1-ld --version` prints "LLD 21.1.8 (compatible with GNU
  linkers)" (ELF), whereas `wasm32-unknown-wasip1-wasm-ld` is the wasm linker. Hence commit
  "link wasm targets with wasm-ld".
- **Flake package-set choice.** The `native-bignum` package sets use native *native-bignum* GHCs
  as `buildHaskellPackages` (to compile `Setup.hs`); no cache has those. The plain sets give the
  same wasm compiler (native bignum is the wasm default on the branch, same drvPath) with regular
  build GHCs.
- **Two pilots hung, cause unknown. It was _not_ the eval cache.**
  - The restarted x86_64-linux and aarch64-darwin pilots printed nothing for ~5 min and ignored
    SIGTERM/SIGINT, so they were killed and restarted (with `--no-eval-cache`).
  - I first blamed the eval cache, but a test against the still-running pilot's flake revision
    showed a busy eval cache is just reported (`error (ignored): SQLite database '…eval-cache-v6/…'
    is busy`). Nix falls back to evaluating without the cache immediately (1 s).
  - So `--no-eval-cache` isn't needed for concurrent builds; don't use it in future runs.
  - The real cause of the hang wasn't identified.
- **GHC #26021 on darwin is not triggered by nixpkgs' cc-wrapper.**
  - GHC's probe `$CC_STAGE0 --target=$LlvmTarget -Werror -c conftest.c` fails, because the darwin
    wrapper always adds `-mmacos-version-min=14.0`, which is unused for wasm (`-Werror`).
  - So `--target=wasm32-…` never reaches the stage0 flags.
  - Accidental protection: the GHC bug (the probe uses the target triple for stage0) is still
    real and fragile.
- **First configure success:** wasm GHC 9.14.1 on x86_64-linux got past `./configure` and
  started hadrian with flavour `release+no_dynamic_libs+no_dynamic_ghc+no_profiled_libs+split_sections`.
- **First hadrian failure (x86_64-linux, 9.14.1): stage0 picked up libffi-wasm.**
  - Linking the stage1 compiler with the bootstrap GHC failed:
    `ld.gold: error: ffi: plugin failed to claim member ffi.o`, then undefined `ffi_call` /
    `ffi_type_*` from the bootstrap RTS.
  - Cause: hadrian (`Settings/Packages.hs`) passes configure's `--with-ffi-*` dirs, i.e. the
    target's libffi, to the stage0 `ghc` library too, so `-L<libffi-wasm>/lib` ends up on the
    host link line.
  - ELF cross targets survive because the linker skips incompatible archives; wasm archives make
    gold's plugin fail instead.
  - Fixed with a hadrian patch (only pass the dirs outside stage0 of a cross compiler); see
    `upstream/ghc/0002-…`. Hadrian with the patch compiles (9.14.1).
  - haskell.nix avoids the same problem by not passing `--with-ffi-*` for wasm at all, which
    would leave the installed rts without libffi's library dir.
- **Second hadrian failure (x86_64-linux, 9.14.1): the wasm RTS's configure, "C compiler cannot
  create executables".**
  - The stage1 compiler now builds (`Successfully built program 'ghc-bin' … wasm32-unknown-wasip1-ghc`).
  - Cause: configure's `FP_CC_SUPPORTS_TARGET` adds `--target=$LlvmTarget` to the target C flags,
    and `GHC_LLVM_TARGET` built `$LlvmTarget` from the *converted* OS, giving
    `wasm32-unknown-wasi`.
  - With that `--target`, clang looks for `…/resource-root/lib/wasm32-unknown-wasi/libclang_rt.builtins.a`,
    but nixpkgs' compiler-rt lives under `wasm32-unknown-wasip1`. Reproduced locally with the
    darwin-hosted wasm cc-wrapper; the default target and upstream's CONF flags link fine.
  - Fixed by extending the wasip1 patch: `GHC_LLVM_TARGET` keeps `wasip1`, like it already does
    for `*-android*`/`*-gnueabi*`. Folded into the wasip1 commit; `upstream/ghc/0001-…` updated.
- **Pre-fix builds.** Four clients started before the fixes (old pilots and pilot2) are watched by
  `scripts/stop-when-building.sh`. Each is stopped only once it starts building its doomed wasm
  GHC derivation, so the shared native work it did up to then is kept. The fixed builds are
  pilot3 (`results/logs/pilot3-*`).
- **Third failure (x86_64-linux, 9.14.1): the RTS doesn't compile against wasilibc 32.**
  - The wasm RTS configure now passes, but compiling it fails with
    `rts/wasm/JSFFI.c:100:3: error: use of undeclared identifier '__wasi_errno_t'`.
  - JSFFI.c uses the WASI preview 1 API without including `<wasi/api.h>`. wasilibc 32 moved that
    API to `<wasi/wasip1.h>` (selected by `<wasi/api.h>`), and only `<sys/socket.h>` still
    includes it transitively. The fork's wasi-sdk 29 libc included it more widely.
  - Reproduced with nixpkgs' wasm cc. JSFFI.c is the only GHC file using the WASI API directly
    (9.12.5-rc3, 9.14.1, HEAD). GHC master has the same code.
  - Fixed with `upstream/ghc/0003-…` (explicit include). This is the first real "stock
    wasi-libc vs GHC's toolchain" difference.
- **Rescheduling (user's request).** Darwin first and kept busy: the 9.12 wasm pipeline plus the
  native 9.14.1/HEAD GHCs that the 9.14/HEAD `Setup.hs` builds need. Linux one architecture at
  a time on the shared VM (aarch64-linux 9.14, then x86_64-linux). pilot2/pilot3 were stopped
  (their locks predate the fixes).
- **Darwin builds were throttled to the efficiency cores by the nix-daemon's launchd process
  type.**
  - htop showed CPUs 0–3 (the M3 Max's E-cores) at ~85% and the P-cores mostly idle.
  - A 16-way CPU-bound `/bin/sh` loop took 6 s as the user but 42 s inside a nix build, with
    `NIX_BUILD_CORES=16`. So neither Nix nor GHC/hadrian (which runs with `-j16`) limited cores.
  - Cause: nix-darwin's default `nix.daemonProcessType = "Standard"`, whose docs say it "will
    apply light resource limits, throttling its CPU usage". It was changed from `Interactive`
    in 2022 (nix-darwin 08edc0e19a, PR #490).
  - Fix: `daemonProcessType = "Interactive"` in purefun-infra's IsoOmenaM3 config (the user
    rebuilt). After that, the same test took 6 s inside a build.
  - Builds running during the switch keep their old daemon workers and therefore the throttle,
    so the darwin builds were restarted (pilot5). The aarch64-linux build runs in the VM, wasn't
    affected, and was left running.
  - Draft upstream issue: `drafts/nix-darwin-daemon-process-type.md`.
- **Fourth failure (aarch64-linux, 9.12.5): xxhash includes `<arm_neon.h>` for wasm.**
  - `rts/Hash.c` includes GHC's bundled xxhash 0.8.3. With `-msimd128` (upstream's flag),
    `__wasm_simd128__` is set, and xxhash includes `<arm_neon.h>` whenever `__has_include` finds
    it, for SIMDe's NEON emulation.
  - nixpkgs' clang (built with ARM targets) ships an `arm_neon.h` that `#error`s for wasm.
    wasi-sdk's wasm-only clang most likely doesn't ship one, so upstream doesn't hit this.
  - Reproduced on the Mac too. Same `xxhash.h` in 9.12.5-rc3/9.14.1/HEAD.
  - XXH3 is only used on 64-bit, so the fix is `upstream/ghc/0004-…`: `#define XXH_NO_XXH3` in
    Hash.c when the word size isn't 64. haskell.nix passes `-DXXH_NO_XXH3` globally instead.
- **x86_64-linux moved to the NUC (10.1.0.17, native x86_64, 8 cores).**
  - The branch was pushed there with `git push` rather than rsync, because the NUC repo has
    branches that exist nowhere else (`fix_liquid_haskell*`, `dusk-pre-rebase-2026-09-24`, …).
  - `~/ghcwasm` was rsynced over. Builds run detached with
    `scripts/build.sh x86_64-linux <ghc> --override-input nixpkgs git+file:///home/mika/nixpkgs-ghcwasm.git?…&rev=…`.
- **First full success: aarch64-linux, GHC 9.12.5-rc3** (nixpkgs `404cf810318c`, VM).
  - Wasm compiler ✓, hello-wasm ✓, wasmtime check ✓.
  - The aarch64-linux-built `hello-wasm.wasm` (5.6 MB) also runs under wasmtime on the Mac.
  - Installed settings: `target platform string = wasm32-unknown-wasi`, `target os = OSWasi`,
    C flags `--target=wasm32-unknown-wasip1 -Wno-error=int-conversion -O3 -mcpu=lime1
    -mreference-types -msimd128`, merge-objects `wasm32-unknown-wasip1-wasm-ld`, link flags
    with `--keep-section=ghc_wasm_jsffi`.
- **darwin HEAD (10.1) failure: `Missing (or bad) C library: rt`.**
  - GHC ≥ 10 builds an RTS for the host too. Hadrian passes it the `librt` Cabal flag that
    configure determined with the target's C compiler: wasilibc's `librt.a` is an empty 8-byte
    stub, so `AC_CHECK_LIB([rt], [clock_gettime])` succeeds.
  - macOS has no librt; Linux hosts do, so they're unaffected.
  - First attempt (`ac_cv_lib_rt_clock_gettime=no`) didn't help. The real cause:
    `hadrian/cfg/system.config.host.in` hardcodes `use-lib-rt = YES`, and stages 0 and 1 read
    the host config (`lookupHostBuildConfig`). Only the target config uses configure's
    `@UseLibrt@`.
  - Workaround: patch that template line to `NO` (wasm + darwin host + GHC ≥ 9.15, drvPaths of
    the other builds unchanged). Upstream fix: compute `use-lib-rt` for the host in configure.
  - Probably affects every darwin-hosted cross build of GHC 10.
- **Editing a running script.** I rewrote `scripts/build.sh` in place while runs of it were still
  waiting in `nix build`. When the builds finished, bash continued reading at the old offset and
  hit a syntax error, so no `exit=` line and garbled task output. The builds themselves were fine.
  Scripts must be replaced atomically (temp file + `mv`). rsync already does that, which is why
  the NUC runs were unaffected.
- **aarch64-linux HEAD (10.1) failure: haddock's index step can't read the stage0 package db.**
  - `Run Haddock BuildIndex` ran `_build/stage1/bin/wasm32-unknown-wasip1-haddock` and failed with
    `_build/stage1/lib/../../stage0/lib/package.conf.d/package.cache:
    GHC.Unit.Database.readPackageDb: inappropriate type (not enough bytes)`.
  - With GHC 10's new staging, the stage1 haddock is pointed at the stage0 (in-tree host compiler)
    package db, whose cache it can't parse. This is a hadrian problem for cross builds of GHC 10.
  - Workaround: `--docs=no-haddocks` for wasm GHC ≥ 9.15 (nixpkgs `2a20c9b7ca10`). Upstream
    issue still to write.
- **darwin HEAD `ghc: otool: could not execute:`: my first fix was wrong.**
  - Putting cctools' `otool`/`install_name_tool` on PATH changed nothing; the error repeated in
    attempt 4. The message ends after the colon because GHC tried to run an *empty* program
    name, not `otool` from PATH.
  - Real cause: `hadrian/cfg/default.host.target.in` (hadrian's `buildTargetFile`,
    `hadrian/src/Base.hs:94`) hardcodes `tgtOtool = Nothing` and `tgtInstallNameTool = Nothing`,
    so the in-tree host compiler's settings have empty otool/install_name_tool commands. GHC
    needs both to link programs for darwin, here `utils/unlit` for the host.
  - Fix: substitute `Just (Program {prgPath = "<cctools>/bin/otool", prgFlags = []})` (and the
    same for install_name_tool) into the template, using the syntax configure's
    `PREP_MAYBE_PROGRAM` produces for the target template. This was folded together with the
    librt workaround into one commit, "fix the darwin host config of wasm GHC >= 10"
    (`c728f4ab9fb6`); `darwinHostTools` is gone. Native and Linux drvPaths are unchanged.
- **x86_64-linux 9.14: the pure hello is green too**, so 9.12 and 9.14 are fully green on all
  three systems.
- **Template Haskell, first build (x86_64-linux 9.12, NUC).**
  - The TH compiler (`wasm-th-ghc912`, with shared libraries) built. `hello-th` then failed:
    `node: bad option: --wasm-lazy-val` / `External interpreter terminated (9)`.
  - GHC starts its wasm interpreter, `dyld.mjs`, through the file's interpreter line. After
    pinning coreutils' `env` and node by store path, that line was 262 characters. Linux reads
    only the first 256 bytes of it (`BINPRM_BUF_SIZE`), so the last flag got cut off; macOS reads
    512, so darwin would have worked.
  - The node flags differ per version, so they can't be hardcoded:
    - 9.12: `--disable-warning=ExperimentalWarning --experimental-wasm-type-reflection
      --no-turbo-fast-api-calls --wasm-lazy-validation`
    - 9.14: `--disable-warning=ExperimentalWarning --max-old-space-size=65536
      --no-turbo-fast-api-calls --wasm-lazy-validation`
    - HEAD: `--disable-warning=ExperimentalWarning --max-old-space-size=65536
      --wasm-lazy-validation`
  - **TH works at runtime.** Using the already-built compiler with only the interpreter line
    swapped (a symlink farm of its output plus `-B`; `/tmp/th-test.*` on the NUC), `hello-th`
    compiles: the splices run in the wasm interpreter, including one imported from another
    module. It links and prints the expected 3 lines under wasmtime. This took 1.8 s for 3
    modules.
  - Fix (TH branch, `7012299d6f89`): a tiny per-GHC derivation builds a *binary* node wrapper
    (`makeBinaryWrapper`; macOS doesn't accept scripts as interpreters) that adds the flags
    parsed from the source's own interpreter line. `dyld.mjs` points at it, and the wrapper
    derivation fails if the line ever changes shape. All three wrappers build and pass the right
    flags on darwin.
  - The TH branch was rebased so that TH = main + 3 commits: ilkecan's #558928, `libffi.so`, and
    the interpreter setup. Native drvPaths are unchanged on both branches.
- **Remote process handling.** `ssh nuc 'pkill -f "scripts/build.sh x86_64-linux ghcHEAD"; …'`
  killed the remote shell itself (its own command line contains the pattern), so ssh exited
  255 and the restart never ran. Use explicit PIDs, or the `[s]cripts` bracket trick.
- **aarch64-linux HEAD: the wasm compiler builds** (the haddock workaround works), but both
  hellos fail before any wasm is involved.
  - The cross build compiles each package's `Setup.hs` with nixpkgs' *native* GHC HEAD
    (10.1.20260810; we built it ourselves, cache.nixos.org doesn't have it). Linking `Setup`
    fails with `ld.gold: error: cannot find -lnuma`, plus undefined `numa_*` references from the
    threaded RTS.
  - The native compiler's `rts-1.0.3.conf` lists `numa` in `extra-libraries-static`, but
    numactl's lib dir only appears in `library-dirs`, not in `library-dirs-static`. libffi's dir
    is in both. GHC 10 apparently links executables with the static fields.
  - Hadrian passes libnuma's dir with `cabalExtraDirs`, which emits only `--extra-lib-dirs`
    (`hadrian/src/Settings/Packages.hs:424`, `:459`).
  - Not wasm-specific: presumably any program linked by native GHC HEAD on Linux, so x86_64-linux
    HEAD will hit it too. Next: check whether haskell-updates or GHC master already fix it. If
    not, fix it either in nixpkgs (this changes the native ghcHEAD, so it gets its own commit) or
    in hadrian (also emit `--extra-lib-dirs-static`).
- **darwin HEAD attempt 5: the otool fix worked; the next failure is symbol names.**
  - The link of host programs by the in-tree host compiler found no symbols at all:
    `"user_era", referenced from: … (maybe you meant: _user_era)`.
  - Same root cause: `default.host.target.in` hardcodes
    `tgtSymbolsHaveLeadingUnderscore = False`, but Mach-O symbols carry a leading underscore.
    GHC master's template is identical to the 10.1.20260810 snapshot (checked 2026-10-09).
  - Added to the host-config commit (`be8d6ea841b4`): set it to `True` on darwin hosts. The
    other hardcoded fields look harmless for darwin; Linux uses the same `arNeedsRanlib = True`
    / `tgtRanlib = Nothing`, `GnuNonexecStack = False` is correct for Mach-O, and subsections via
    symbols are just off.
  - The GHC issue should list all four darwin problems (librt, leading underscore, otool,
    install_name_tool) and suggest filling the host template from configure, like the target's.
  - The darwin TH HEAD build was started before this fix and will fail the same way; it gets
    rerun once it does (the user asked not to stop builds).
- **Shell pitfall.** `git cherry-pick … 2>&1 | tail -1 && git branch -f …`: the pipe's status is
  `tail`'s, so a conflicted cherry-pick still moved the TH branch (it was repaired right away).
  Don't put `| tail` in `&&` chains.
- **Native GHC HEAD (10.1.20260810) can't link any executable on Linux, not even hello world.**
  - Tested on the NUC outside nix builds: `ghc Main.hs` (threaded or not) fails with
    `cannot find -lelf`, `-ldw`, `-lnuma` on x86_64-linux. On aarch64-linux, where the RTS has
    no libdw support, only `-lnuma` is missing.
  - With `-L<numactl>/lib` the numa error goes away, and elf/dw remain. So the cause is the
    missing directories: the RTS conf lists these libraries in `extra-libraries-static`, but
    their store paths only in `library-dirs`, not `library-dirs-static`.
  - On FHS distros these libraries are on the linker's default path, which is presumably why
    upstream doesn't notice.
  - Proposed fix: hadrian's `cabalExtraDirs` also passes `--extra-lib-dirs-static` (Cabal 3.16
    has the flag). This changes the native ghcHEAD, so it needs its own nixpkgs commit and a GHC
    MR. Waiting for the user's go-ahead.
  - **Follow-up: it's in stock nixpkgs, and it's a GHC 10 regression.**
    - The tested compiler is exactly stock haskell-updates' `haskell.compiler.ghcHEAD`: same out
      paths at base `68594478077b`, and no GHC builder commits since. Hydra built the x86_64 one
      (it's on cache.nixos.org); aarch64-linux isn't cached.
    - Native *package builds* work: on stock haskell-updates,
      `haskell.packages.ghcHEAD.hello` builds on x86_64-linux, and `Setup` links. The nix build
      environment supplies the library paths, most likely via the compiler's propagated
      libraries (not verified). So package builds, including Hydra's, don't show the problem.
      Using the compiler directly does.
    - In cross builds, `Setup.hs` is linked by the native compiler for the *build* platform,
      where those paths aren't supplied. So presumably every cross target with GHC HEAD is
      affected; only wasm has been verified.
    - GHC 9.14.1's RTS conf does list elfutils and numactl in `library-dirs-static`, and 9.14.1
      links a hello world fine outside nix builds. So GHC 10 regressed.
- **Formatting check (the user's request), both branches.** `nix fmt -- --no-cache
  --fail-on-change` (nixpkgs' treefmt: nixfmt, nixf-diagnose, keep-sorted,
  editorconfig-checker) on every file changed since base `68594478077b` passes with 0 changes:
  main `b85034bdbe51` (13 files) and TH `6cff689fec63` (14 files). The `.patch` files have no
  formatter. Gotcha: in zsh an unquoted `$files` isn't word-split; use `$(git diff …)` directly.
- **darwin HEAD attempt 6: green.** The wasm GHC 10.1 compiler builds on aarch64-darwin, and
  hello-wasm and hello-pure pass their wasmtime checks (nixpkgs `b85034bdbe51`). The darwin host
  template fixes (librt, otool/install_name_tool, leading underscore) are all it needed. The
  native GHC HEAD link bug doesn't apply on darwin, which has no libnuma or elfutils.
- **darwin TH HEAD (attempt 2): green.** The TH compiler for GHC 10.1, `hello-th` and its
  wasmtime check pass (TH branch `6cff689fec63`). aarch64-darwin is now fully green: 9.12, 9.14
  and HEAD, each with hello, hello-pure and hello-th. Everything left on Linux is blocked by the
  native GHC HEAD link bug.
- **TH folded into `ghcwasmhacking`; GHC 10 static library dirs fixed (nixpkgs `93f4824cc1ee`).**
  - The user approved both. The TH branch was main + 3 commits, so main was fast-forwarded and
    the TH branch and worktree were deleted (locally and on the NUC). The flake lost its
    `nixpkgs-th` input. The 9.12/9.14 `hello-th` derivations are identical to the ones tested
    before.
  - Root cause of the native GHC HEAD link failure: GHC commit `0f53ccc6` ("Use libffi-clib",
    2026-01) left `extra-lib-dirs-static: @FFILibDir@` in `rts/rts.buildinfo.in`, rewriting
    fields that `1ac1a541` (static linking, #26434) had added. A non-empty static list disables
    Cabal's `extraLibDirsStaticOrFallback`. The fix drops the line (`upstream/ghc/0005-…`, same on
    GHC master); nixpkgs applies it to GHC ≥ 9.15.
  - Only `haskell.compiler.ghcHEAD` changes among the native drvPaths (all three systems).
  - Force-pushed to github.com/mikatammi/nixpkgs (`b85034b..93f4824`).
  - x86_64-linux 9.12 and 9.14 after the fold: green (the hellos rebuilt with shared libraries
    enabled; TH cached).
- **The static library dirs fix works (x86_64-linux, NUC).**
  - With `93f4824cc1ee`, the full HEAD pipeline is green: native ghcHEAD (rebuilt), the wasm GHC
    10.1, hello-pure, hello-wasm and hello-th, and all three wasmtime checks.
  - The rebuilt native ghcHEAD's `rts-1.0.3.conf` now lists the libffi, elfutils and numactl
    dirs in `library-dirs-static`, as 9.14 does. Outside nix, `ghc Main.hs` links and runs hello
    world, with and without `-threaded`.
- **aarch64-linux after the fold and fix: 9.12, 9.14 and HEAD all green.** HEAD built the
  patched native ghcHEAD and the wasm GHC 10.1, then hello-pure, hello-wasm and hello-th, and all
  three wasmtime checks pass (17 derivations, about 40 min on the VM).
- **The JS backend's GHC HEAD fails on Hydra with the same haddock bug.**
  - Hydra build 347803739 (`pkgsCross.ghcjs.haskell.packages.ghcHEAD.ghc`, x86_64-linux) builds
    for 1h01m and then dies in `Run Haddock BuildIndex` with the same
    `…/stage0/lib/package.conf.d/package.cache: GHC.Unit.Database.readPackageDb: inappropriate type
    (not enough bytes)` as our wasm build. The full log is at
    `https://hydra.nixos.org/build/<id>/log/raw`; failed builds' logs aren't in cache.nixos.org.
  - So it's a GHC 10 problem in every cross build. The workaround now applies to all cross
    compilers (`targetPlatform != hostPlatform`), rewritten into the same nixpkgs commit (now
    "no haddock docs for cross GHC >= 10"). Only the JS GHC HEAD derivation changes; wasm and
    native derivations are identical.
  - A verification build of `pkgsCross.ghcjs.haskell.packages.ghcHEAD.hello` is running on the
    NUC.
- **The haddock bug's history (2026-10-10).**
  - No GHC issue and no nixpkgs issue mentions it. Searched GitLab for `readPackageDb`,
    "inappropriate type", haddock + cross; GitHub nixpkgs for `readPackageDb` and "not enough
    bytes".
  - Hydra's `pkgsCross.ghcjs.haskell.packages.ghcHEAD.ghc` (x86_64-linux) built fine on every GHC
    master snapshot from early 2025 up to **10.1.20260513** (GHC `38b76b2f`). It has failed on
    every build since nixpkgs moved to **10.1.20260810** (GHC `556db2f3`) on 2026-08-15. So it's a
    GHC master regression from between those two snapshots, not present in 9.x.
  - Prime suspect: `23c9b6c392` "hadrian: Build stage 2 cross compilers" (written 2023, merged
    2026-06-20). It restructures how cross compilers are staged and adds a `binary-dist-dir-cross`
    target, and the failing step reads `_build/stage1/lib/../../stage0/lib/package.conf.d`. It is
    **not** in `ghc-10.0`, so 10.0 is probably unaffected; it's master/10.2 only. That's the
    opposite of patch 0005, which is in 10.0. Not bisected.
  - Open question for the issue: GHC's own cross CI jobs (`binary-dist`, with haddocks) seem
    unaffected. nixpkgs uses `binary-dist-dir`, which picks the cross configuration implicitly,
    so the target alone doesn't explain it. Possibly the bootstrap compiler writing stage0's
    package database: its binary format changed with `1ac1a541`.
- **JS backend GHC HEAD on x86_64-linux (NUC): green.** `pkgsCross.ghcjs.haskell.packages.ghcHEAD.hello`
  builds with the nixpkgs branch (`a6b14f10857e`): the JS GHC 10.1.20260810 compiler, which uses
  the haddock workaround, and `hello`, whose `Setup.hs` links thanks to patch 0005. Both fixes
  are confirmed for JS too.
- **Bisecting the haddock bug** (in a separate worktree, `~/ghc-bisect`, so `~/ghc` stays free for
  the patch-0005 session). The builds run on the NUC from `~/bisect-haddock/bisect.nix`: nixpkgs'
  JS GHC HEAD with `ghcSrc` replaced by any GHC commit (`builtins.fetchGit` with submodules) and
  `--docs=no-haddocks` removed. First test: suspect `23c9b6c392` against its parent `521e55bf69`.
- **Cheng Shao's GHC !16790 tested (cross `ghc --info` unit ids, #27919).**
  - Our wasm GHCs are affected: they're built with `--hash-unit-ids`, and nixpkgs has
    cabal-install 3.18.1.0. `--info` against `ghc-pkg` mismatches for `ghc-internal` and `ghc` on
    9.14, and for `base`, `ghc-internal` and `ghc` on HEAD. 9.12 doesn't report base/ghc-internal
    in `--info`. Nix builds through the generic builder aren't affected (`Setup.hs` doesn't use
    the solver), but cabal-install in a shell is, e.g. the flake's devShell.
  - A/B test on aarch64-darwin, with the MR (head `95f24e6b`) applied to our wasm GHC HEAD
    (`556db2f3`): unpatched, cabal fails with `Cabal-7107` exactly as in #27919; patched, all
    three ids match, `cabal build` of hello-pure succeeds and the `.wasm` runs under wasmtime.
    Scratch setup in `/tmp/ghcwasm-scratch/mr16790/`. Report draft:
    `drafts/ghc-mr16790-test-report.md`.
  - **Pitfall:** to test a GHC patch that touches hadrian through nixpkgs, put it in `ghcSrc`
    (`.override { ghcSrc = srcOnly { …; patches = old ++ [ diff ]; }; }`). Hadrian is a separate
    derivation built from `ghcSrc`. Adding the patch with `overrideAttrs` patches only the
    compiler and gives `No entry for "ghc unit-id" in …/stage0/lib/settings`.
