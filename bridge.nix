# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on top of the BRIDGE stdenv; see ./stdenv/bridge.nix.
#   nix-build bridge.nix -I nixpkgs=/path/to/illumos-26.05 -A hello
{
  nixpkgs ? <nixpkgs>,
  paths ? import ./stdenv/bridge-paths.nix,
}:

import nixpkgs {
  # `system` is what Nix reports; `config` is the triple gcc-illumos is configured for.
  localSystem = {
    system = "x86_64-solaris";
    config = "x86_64-pc-solaris2.11";
  };
  stdenvStages = import ./stdenv/bridge.nix { inherit paths nixpkgs; };
  config = { };
  overlays = [ ];
}
