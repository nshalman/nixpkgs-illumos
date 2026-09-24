# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on its own stdenv, pkgs/stdenv/illumos, given this repo's
# bootstrap files and toolchain packages. ./bridge.nix is how those bootstrap files were first made.
#   nix-build illumos.nix -A hello
# Every input is pinned to where it is published (tests/pins.sh); a local checkout of illumos-26.05 can stand in:
#   nix-build illumos.nix --arg nixpkgs /path/to/illumos-26.05 -A hello
# bootstrapUrl is the directory of a release not hosted yet; see bootstrap/files.nix.
{
  nixpkgs ? builtins.fetchTarball {
    # the illumos-26.05 branch of github.com/nshalman/nixpkgs
    url = "https://github.com/nshalman/nixpkgs/archive/a2b70636aef341b5b4e1cbcf80657f31e4199d1a.tar.gz";
    sha256 = "0fkb3qfsqh1x9msw046pdgnjzzb90amzdlia9l1dfg6j7594h1yr";
  },
  bootstrapUrl ? null,
  bootstrapFiles ? import ./bootstrap/files.nix { baseUrl = bootstrapUrl; },
  # The Nix source to build: nixpkgs' `nixVersions.nix_2_35` packaging, with its source replaced by the
  # illumos branch of nix-src (upstream 2.35.2 plus the illumos series).
  nixSrc ? builtins.fetchTarball {
    # a GitHub archive of the illumos-support-2.35 commit: the tree a checkout has (nix-src has no export-ignore),
    # fetched without git
    url = "https://github.com/nshalman/nix-src/archive/55b532f45b2ba5f4a0e66037f062a72d5c4a2faa.tar.gz";
    sha256 = "0rnf0665i24m7rvixv6dgqhw0bsl0jsarij13jjb1f3kpm0h8fy6";
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
      # The binary tarball and installer of that Nix, made by nix-src's own packaging from the same source. The
      # manual does not evaluate for illumos.
      nixInstallerTarball = final.callPackage "${nixSrc}/packaging/binary-tarball.nix" {
        nix = final.nixVersions.nix_2_35;
        nixComponents2 = final.nixVersions.nixComponents_2_35;
        withManual = false;
      };
    })
  ];
}
