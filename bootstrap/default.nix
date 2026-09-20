# The second generation: everything a bootstrap-files release is made of, built by the bridge stdenv, so by the
# sysroot toolchain and against illumos-libc. Nothing in here may be linked against the build host's libc.
#
#   nix-build bootstrap --arg nixpkgs /path/to/illumos-26.05 -A userland --keep-going
#
# The list follows pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix on the illumos-recipe-v2 branch.
{
  nixpkgs ? <nixpkgs>,
  paths ? import ../stdenv/bridge-paths.nix,
}:

let
  pkgs = import ../bridge.nix { inherit nixpkgs paths; };
  # This repo's packages, built by the bridge stdenv instead of the illumos-recipe-v2 one.
  own = import ../pkgs { callPackage = pkgs.lib.callPackageWith (pkgs // own); };
in
rec {
  inherit pkgs own paths;

  userland = import ./userland.nix pkgs;

  toolchain = [
    own.illumos-libc
    own.illumos-ld
    own.gcc-illumos.out
    own.gcc-illumos.lib
  ];
}
