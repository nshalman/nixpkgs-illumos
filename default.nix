# Package set for this repo. Until the illumos-26.05 nixpkgs branch exists, pass the bridge tree:
#   nix-build -I nixpkgs=/path/to/nixpkgs -A illumos-sysroot
{
  pkgs ? import <nixpkgs> { },
}:

let
  callPackage = pkgs.lib.callPackageWith (pkgs // self);
  self = import ./pkgs { inherit callPackage; };
in
self
