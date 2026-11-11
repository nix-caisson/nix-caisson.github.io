# SPDX-License-Identifier: MIT
{ ... }:
{
  inputs,
  lib,
  ...
}:
let
  # The formatters, for `nix fmt` and for the formatting check alike.
  treefmt = {
    programs.nixfmt.enable = true;
  };
in
{

  imports = [ inputs.flake-parts.flakeModules.partitions ];

  # The website's package is the `default` entry of this flake's package
  # overlay registry (pkg-overlays/, registered on mkLib). The package
  # set applies it by default, and the flake exports its scope as the
  # `packages` output, so `nix build '.#site'` builds the website.
  caisson.nixpkgs = {
    packages.export.enabled = true;
  };

  partitionedAttrs.checks = "checks";
  partitionedAttrs.formatter = "formatter";

  partitions.formatter = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).dependencies;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem.treefmt = treefmt;
      };
  };

  partitions.checks = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).dependencies;
    module =
      { inputs, self, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem =
          { system, ... }:
          {
            # `checks.treefmt`, from the module: every Nix file
            # formatted.
            inherit treefmt;
            checks = {
              # mdBook fails the build on a broken SUMMARY.md, a
              # missing chapter or a template error.
              site = self.packages.${system}.site;
            };
          };
      };
  };

}
