# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on its own stdenv, pkgs/stdenv/illumos, given this repo's
# bootstrap files and toolchain packages. ./bridge.nix is how those bootstrap files were first made.
#   nix-build illumos.nix -A hello
# Every input is pinned to where it is published (tests/pins.sh); a local checkout of illumos-26.05 can stand in:
#   nix-build illumos.nix --arg nixpkgs /path/to/illumos-26.05 -A hello
# bootstrapUrl is the directory of a release not hosted yet; see bootstrap/files.nix.
{
  nixpkgs ? builtins.fetchTarball {
    # the illumos-26.05 branch of github.com/nshalman/nixpkgs
    url = "https://github.com/nshalman/nixpkgs/archive/e4adcd79594ccb4a8a57c394bcbb053d49301775.tar.gz";
    sha256 = "0r5ckd3ljrrwq9jnj5wwcxrdkfafdh6qqhnznp02xkwlld5krhlx";
  },
  bootstrapUrl ? null,
  bootstrapFiles ? import ./bootstrap/files.nix { baseUrl = bootstrapUrl; },
  # The Nix source to build: nixpkgs' `nixVersions.nix_2_35` packaging, with its source replaced by the
  # illumos branch of nix-src (upstream 2.35.2 plus the illumos series).
  nixSrc ? builtins.fetchGit {
    url = "https://github.com/nshalman/nix-src";
    ref = "illumos-support-2.35";
    rev = "ff849c099603731091ef0df5d03baa2d39a70721";
  },
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
  overlays = [
    (final: prev: {
      nixVersions = prev.nixVersions.extend (
        # the packaging wants a name on the source; a store-path directory unpacks as "source"
        _: p: { nixComponents_2_35 = p.nixComponents_2_35.overrideSource (nixSrc // { name = "source"; }); }
      );
    })
  ];
}
