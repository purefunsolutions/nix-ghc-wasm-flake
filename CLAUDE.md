# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project overview

GHC's wasm backend built purely from source in nixpkgs, with stock LLVM
and wasi-libc. The nixpkgs side lives on the branch `ghcwasmhacking` of
github.com/mikatammi/nixpkgs, whose newest dated copy is this flake's
`nixpkgs` input. This repository has the flake that builds and tests it,
the GHC patches prepared for upstream, and the documentation: research,
results and the upstream tracker.

## Commands

```sh
nix fmt
nix flake check --no-build --all-systems --no-update-lock-file
scripts/build.sh <system> <ghc>
```

`nix fmt` formats every file. The check evaluates every system.
`scripts/build.sh` builds one GHC version's wasm compiler, hello worlds and
their wasmtime checks for one system, with a log in `results/logs/`.
Extra arguments go to `nix build`, e.g.
`--override-input nixpkgs 'git+file://<checkout>?ref=ghcwasmhacking'` to
test a local nixpkgs change. A wasm GHC takes about an hour per version
and system, so build one system at a time.

## Layout

- `flake.nix`: flake-parts for aarch64-darwin, x86_64-linux and
  aarch64-linux. Its inputs are flake-parts, nixpkgs and treefmt-nix.
- `nix/`: flake-parts modules. `wasm.nix` has the compilers as
  `wasm-<ghc>` for each of `ghc912`, `ghc914` and `ghcHEAD`, nixpkgs'
  wasilibc and libffi-wasm tests as checks, and the `wasm` package set and
  `ghcs` list as module arguments. `devshell.nix` is `nix develop`, and
  `treefmt.nix` is `nix fmt` and `checks.treefmt`.
- `pkgs/`: `default.nix` builds each program in `pkgs/<name>/` with every
  GHC, as `<name>-<ghc>`, and checks it under wasmtime against its
  expected output: `hello` (native bignum, C FFI and a libffi callback),
  `hello-pure` and `hello-th`. `munihac2026presentation` is the MuniHac
  2026 talk, a GHC 9.14 JSFFI program and its web page, also an app.
- `upstream/ghc/`: the GHC patch without a merge request yet.
  `docs/upstream-check.md` has the upstream status of every GHC change.
- `docs/`: research and plan, the nixpkgs branch's commits, tooling (HLS
  and debugging), the toolchain compared with GHC's forks, and GHC's
  testsuite.
- `STATUS.md`: the result matrix. `results/notes.md`: the log of
  findings.
- `README.md`: the overview and the upstream tracker.
- `.gitlab-ci.yml`: GitLab CI. `checks` evaluates the flake for every
  system and builds nothing. `publish-github`, on master once that
  passed, pushes master to github.com/purefunsolutions/nix-ghc-wasm-flake
  with the deploy key in the masked, protected CI variable
  `GITHUB_DEPLOY_KEY_B64`.

## Conventions

- Every file type has a formatter in `nix/treefmt.nix`, enabled in the
  commit that adds the first file of that type. Patches, binary files and
  test fixtures are excluded there.
- Nothing host-specific in the repository: no hostnames, IP addresses or
  absolute paths of anyone's machine.
- The `nixpkgs` input is the fork's newest `ghc-wasm-flake-<date>` branch.
  Those branches never move, so older revisions of this flake keep
  working: an update of `ghcwasmhacking` gets a new dated branch, and the
  input points at it.

## Git workflow

- One commit per reasonably sized feature. Docs change in the same commit
  as the feature they describe.
- Subjects in nixpkgs style, `<area>: <summary>`, e.g. `hello-th: init` or
  `docs: compare the stock toolchain with GHC's wasm forks`. Short bodies:
  why, and facts that aren't obvious from the diff.
- Trailers: `Assisted-by: Claude Code (<model>)` when Claude helped, then
  `Signed-off-by: Mika Tammi <mikatammi@gmail.com>` (`git commit -s`).
- `flake.lock` changes in its own commit (`flake.lock: update nixpkgs`) or
  together with the input change that needs it.
- Every commit is formatted (`nix fmt`) and passes
  `nix flake check --no-build --all-systems --no-update-lock-file`.
- Corrections to earlier commits go in as `git commit --fixup=<commit>`
  and are autosquashed before the merge request is merged.
- Keep the upstream tracker in `README.md` current; ✅ marks merged
  changes.

## Never commit

- `drafts/`: texts for upstream issues, merge requests and comments until
  they are posted, and hand-offs between sessions. Delete a draft once
  it's posted or no longer relevant.
- `TODO.md`: the working backlog.

`.gitignore` excludes both.
