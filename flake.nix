{
  description = "Pure-Nix GHC wasm hello world, a testbed for GHC's wasm backend in nixpkgs";

  # nixpkgs with the work-in-progress wasm support, including Template
  # Haskell: branch ghcwasmhacking of github.com/mikatammi/nixpkgs, based on
  # haskell-updates. To try changes in a local checkout of it, add
  #   --override-input nixpkgs git+file:///path/to/nixpkgs?ref=ghcwasmhacking
  inputs.nixpkgs.url = "github:mikatammi/nixpkgs/ghcwasmhacking";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];

      # GHC versions to build, by nixpkgs attribute name.
      ghcs = [
        "ghc912"
        "ghc914"
        "ghcHEAD"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      wasmFor =
        pkgs:
        let
          wasm = pkgs.pkgsCross.wasm32-wasip1;
        in
        {
          inherit wasm;
          # The compilers run on `system` and produce wasm32-wasip1 code. They
          # use native bignum by default on the branch. (The `native-bignum`
          # package sets would also build native native-bignum GHCs for
          # Setup.hs, which no binary cache has.)
          compilers = lib.genAttrs ghcs (ghc: wasm.buildPackages.haskell.compiler.${ghc});
          hellos = lib.genAttrs ghcs (ghc: wasm.haskell.packages.${ghc}.callPackage ./nix/hello.nix { });
          hellosPure = lib.genAttrs ghcs (
            ghc: wasm.haskell.packages.${ghc}.callPackage ./nix/hello-pure.nix { }
          );
        };

      # Run a hello build under wasmtime and compare its output.
      runWasm =
        pkgs: name: drv: expected:
        pkgs.runCommand "run-${name}" { nativeBuildInputs = [ pkgs.wasmtime ]; } ''
          export HOME="$TMPDIR"
          wasmtime run ${lib.getExe drv} a b > output.txt
          diff -u ${expected} output.txt
          touch "$out"
        '';
      runHello =
        pkgs: name: hello:
        runWasm pkgs name hello ./hello/expected-output.txt;
      runHelloPure =
        pkgs: name: hello:
        runWasm pkgs "pure-${name}" hello (builtins.toFile "expected" "Hello, World!\n");
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          inherit (wasmFor pkgs)
            compilers
            hellos
            hellosPure
            ;
        in
        lib.mapAttrs' (ghc: drv: lib.nameValuePair "wasm-${ghc}" drv) compilers
        // lib.mapAttrs' (ghc: drv: lib.nameValuePair "hello-${ghc}" drv) hellos
        // lib.mapAttrs' (ghc: drv: lib.nameValuePair "hello-pure-${ghc}" drv) hellosPure
        // {
          default = hellos.ghc912;
        }
      );

      checks = forAllSystems (
        pkgs:
        let
          inherit (wasmFor pkgs)
            wasm
            hellos
            hellosPure
            ;
        in
        lib.mapAttrs' (ghc: drv: lib.nameValuePair "hello-${ghc}" (runHello pkgs ghc drv)) hellos
        // lib.mapAttrs' (
          ghc: drv: lib.nameValuePair "hello-pure-${ghc}" (runHelloPure pkgs ghc drv)
        ) hellosPure
        // {
          # Toolchain sanity checks from nixpkgs: C/C++ against wasilibc, and
          # libffi-wasm's own test suite.
          wasilibc = wasm.wasilibc.tests.simple-c-cxx-binaries;
          libffi-wasm = wasm.libffi-wasm.tests.upstream;
        }
      );

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "hello-wasm" ''
              exec ${lib.getExe pkgs.wasmtime} run ${
                lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default
              } "$@"
            ''
          );
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (wasmFor pkgs).compilers.ghc914
            pkgs.cabal-install
            pkgs.wasmtime
            pkgs.nodejs
          ];
        };
      });
    };
}
