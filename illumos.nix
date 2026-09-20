# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on its own stdenv, pkgs/stdenv/illumos, given this repo's
# bootstrap files and toolchain packages. ./bridge.nix is how those bootstrap files were first made.
#   nix-build illumos.nix --arg nixpkgs /path/to/illumos-26.05 --argstr bootstrapUrl file:///... -A hello
{
  nixpkgs ? <nixpkgs>,
  bootstrapUrl,
  bootstrapFiles ? import ./bootstrap/files.nix { baseUrl = bootstrapUrl; },
}:

import nixpkgs {
  # `system` is what Nix reports; `config` is the triple gcc-illumos is configured for.
  localSystem = {
    system = "x86_64-solaris";
    config = "x86_64-pc-solaris2.11";
  };
  stdenvStages =
    args:
    import (nixpkgs + "/pkgs/stdenv/illumos") (
      args
      // {
        inherit bootstrapFiles;
        illumosPackages = import ./pkgs;
      }
    );
  config = { };
  overlays = [ ];
}
