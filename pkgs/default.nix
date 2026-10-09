# This flake's packages: pkgs/<name>/default.nix. The wasm programs are
# built with every GHC version in `ghcs`, as `<name>-<ghc>`; their checks
# run them under wasmtime and compare the output.
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      wasm,
      ghcs,
      ...
    }:
    let
      # A package for every GHC version, named <name>-<ghc>.
      forGhcs =
        name: f:
        lib.listToAttrs (
          map (ghc: lib.nameValuePair "${name}-${ghc}" (f wasm.haskell.packages.${ghc})) ghcs
        );

      hellos = forGhcs "hello" (hp: hp.callPackage ./hello { });
      hellosPure = forGhcs "hello-pure" (hp: hp.callPackage ./hello-pure { });

      # Runs each program under wasmtime with the arguments "a b" and
      # compares its output.
      runEach =
        expected:
        lib.mapAttrs (
          name: drv:
          pkgs.runCommand "run-${name}" { nativeBuildInputs = [ pkgs.wasmtime ]; } ''
            export HOME="$TMPDIR"
            wasmtime run ${lib.getExe drv} a b > output.txt
            diff -u ${expected} output.txt
            touch "$out"
          ''
        );
    in
    {
      packages =
        hellos
        // hellosPure
        // {
          default = hellos.hello-ghc912;
        };

      checks =
        runEach ./hello/expected-output.txt hellos
        // runEach (builtins.toFile "expected" "Hello, World!\n") hellosPure;

      apps = {
        default = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "hello-wasm" ''
              exec ${lib.getExe pkgs.wasmtime} run ${lib.getExe config.packages.default} "$@"
            ''
          );
        };
      };
    };
}
