# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on its own stdenv, pkgs/stdenv/illumos, given this repo's
# bootstrap files and toolchain packages. ./bridge.nix is how those bootstrap files were first made.
#   nix-build illumos.nix -A hello
# Every input is pinned to where it is published (tests/pins.sh); a local checkout of illumos-26.05 can stand in:
#   nix-build illumos.nix --arg nixpkgs /path/to/illumos-26.05 -A hello
# bootstrapUrl is the directory of a release not hosted yet; see bootstrap/files.nix.
{
  nixpkgs ? builtins.fetchTarball {
    # the illumos-26.05 branch of github.com/nshalman/nixpkgs
    url = "https://github.com/nshalman/nixpkgs/archive/6acfce243e45950f1996d62a08f88db4ba21d27f.tar.gz";
    sha256 = "0r4rgwa98ng6vvv7k4gndrpxhqwfslb99qvxn4041lr0yag0a0yf";
  },
  bootstrapUrl ? null,
  bootstrapFiles ? import ./bootstrap/files.nix { baseUrl = bootstrapUrl; },
  # The Nix source to build: nixpkgs' `nixVersions.nix_2_35` packaging, with its source replaced by the
  # illumos branch of nix-src (upstream 2.35.2 plus the illumos series).
  nixSrc ? builtins.fetchTarball {
    # a GitHub archive of the illumos-support-2.35 commit: the tree a checkout has (nix-src has no export-ignore),
    # fetched without git
    url = "https://github.com/nshalman/nix-src/archive/ff849c099603731091ef0df5d03baa2d39a70721.tar.gz";
    sha256 = "1xxpcd4iw23wfjl3zvycmrj4q529cfnixxy6pv9v4ch5j3rc9lbq";
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
        # the packaging wants a name on the source, which may be a fetchGit result or a store path; a store-path
        # directory unpacks as "source"
        _: p: {
          nixComponents_2_35 = p.nixComponents_2_35.overrideSource {
            outPath = "${nixSrc}";
            name = "source";
          };
        }
      );
    })
  ];
}
