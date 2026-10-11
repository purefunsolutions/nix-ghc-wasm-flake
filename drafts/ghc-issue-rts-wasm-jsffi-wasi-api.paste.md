_LLM assistance: Claude Code (Claude Opus 5.5) was used to investigate this and to draft this report. I have carefully reviewed and revised it and take responsibility for it under [P3](https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI)._

## Summary

Since bdc9d130 (!14895), `rts/wasm/JSFFI.c` uses the WASI preview 1 API (`__wasi_errno_t`, `__wasi_args_sizes_get()`, `__wasi_args_get()`) without including `<wasi/api.h>`. It relies on other libc headers to include it. In wasi-libc 32 (wasi-sdk 32), only the socket headers still do, and `JSFFI.c` doesn't include any of them, so the wasm RTS doesn't compile.

GHC's CI doesn't hit this: its wasm jobs use ghc-wasm-meta's wasi-sdk, whose libc still includes `<wasi/api.h>` indirectly.

## Steps to reproduce

Compile `rts/wasm/JSFFI.c` from master with clang 21.1.8 and wasi-libc 32 (here nixpkgs' `pkgsCross.wasm32-wasip1` toolchain), with the RTS's include paths and `-DCOMPILING_RTS`:

```
rts/wasm/JSFFI.c:100:3: error: use of undeclared identifier '__wasi_errno_t'
rts/wasm/JSFFI.c:105:9: error: call to undeclared function '__wasi_args_sizes_get'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
rts/wasm/JSFFI.c:133:9: error: call to undeclared function '__wasi_args_get'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
[6 more errors about err and __WASI_ERRNO_SUCCESS]
9 errors generated.
```

The libc change on its own:

```
$ cat t.c
#include <stdlib.h>
__wasi_errno_t e;
$ wasm32-unknown-wasip1-cc -fsyntax-only t.c
t.c:2:1: error: unknown type name '__wasi_errno_t'
```

With `#include <wasi/api.h>` instead of `<stdlib.h>`, `t.c` compiles.

## Expected behavior

The wasm RTS compiles with wasi-libc 32.

## Environment

* GHC version used: master (e7cacf59b8). ghc-10.0, ghc-9.14 and ghc-9.12 have the same code.
* Operating System: macOS 26.7.1 host, wasm32-wasi target. The error comes from the target's libc headers, so the host doesn't matter.
* System Architecture: aarch64 host

I'll open an MR that includes `<wasi/api.h>` in `JSFFI.c`. Since ghc-10.0, ghc-9.14 and ghc-9.12 have the same code, I'd like it backported to all three.

cc @TerrorJack

/label ~"T::bug"
/label ~"needs triage"
/label ~wasm
