# SPDX-License-Identifier: MIT
#
# The website as GitHub Pages serves it: the landing page and the other
# files of site/, the book that mdBook builds from docs/ into
# site/docs/, and the brand sources of assets/brand/ under
# site/assets/brand/, so other repositories can reference them by URL.
# The output is the directory that .github/workflows/pages.yml uploads.
{
  lib,
  stdenvNoCC,
  mdbook,
}:
let
  root = ../../../..;
in
stdenvNoCC.mkDerivation {
  name = "nix-caisson-site";

  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/book.toml")
      (root + "/docs")
      (root + "/theme")
      (root + "/site")
      (root + "/assets/brand")
    ];
  };

  nativeBuildInputs = [ mdbook ];

  buildPhase = ''
    runHook preBuild
    mdbook build
    cp -r assets/brand site/assets/brand
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r site "$out"
    runHook postInstall
  '';
}
