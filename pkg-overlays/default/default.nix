# SPDX-License-Identifier: MIT
#
# The default package overlay: the built website under
# `pkgs.nix-caisson-site` (packages/default.nix lists it). The scope
# name is bound here and matches the name declared on mkLib, which is
# the scope the flake's `packages` output publishes.
{ closure-lib, ... }:
{
  overlay = closure-lib.caisson.nixpkgs.mkPackagesOverlay (
    { callPackage, ... }: import ./packages { inherit callPackage; }
  ) "nix-caisson-site";
}
