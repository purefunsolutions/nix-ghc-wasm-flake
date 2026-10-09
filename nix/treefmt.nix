# `nix fmt` and `checks.treefmt`. Every file type in the repository gets a
# formatter here in the same commit that adds the first file of that type.
{ inputs, lib, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ];

  perSystem = {
    treefmt = {
      projectRootFile = "flake.nix";

      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
        yamlfmt.enable = true;
        mdformat = {
          enable = true;
          # GitHub-flavoured Markdown: plain mdformat would mangle tables.
          plugins = ps: [ ps.mdformat-gfm ];
        };
        ormolu.enable = true;
        cabal-fmt.enable = true;
        clang-format.enable = true;
        prettier.enable = true;
        shellcheck.enable = true;
        shfmt.enable = true;
      };

      # Tables as they are written, without padding every column to the
      # width of its longest cell.
      settings.formatter.mdformat.options = [ "--compact-tables" ];

      # Prettier would take Markdown and YAML too, which have their own
      # formatters: replace its list instead of adding to it.
      settings.formatter.prettier.includes = lib.mkForce [
        "*.css"
        "*.html"
        "*.js"
      ];

      # Files without a formatter, and test fixtures that must stay byte for
      # byte as they are. slides.md is the presentation's own syntax, which
      # only looks like Markdown.
      settings.global.excludes = [
        "*.glb"
        "*.png"
        "*.txt"
        ".gitignore"
        "flake.lock"
        "pkgs/munihac2026presentation/slides.md"
      ];
    };
  };
}
