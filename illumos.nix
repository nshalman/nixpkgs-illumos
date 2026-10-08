# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on its own stdenv, pkgs/stdenv/illumos, given this repo's
# bootstrap files and toolchain packages: the generic package set, what runs on any illumos distribution. ./bridge.nix
# is how those bootstrap files were first made; ./smartos.nix builds SmartOS on it, through `overlays` and `config`,
# which add to its own.
#   nix-build illumos.nix -A hello
# Every input is pinned to where it is published (tests/pins.sh), nixpkgs and the Nix source in ./pins (bumped by
# pins/update.sh); a local checkout of illumos-26.05 can stand in:
#   nix-build illumos.nix --arg nixpkgs /path/to/illumos-26.05 -A hello
# bootstrapUrl is the directory of a release not hosted yet; see bootstrap/files.nix.
let
  pins = import ./pins;
in
{
  # the illumos-26.05 branch of github.com/nshalman/nixpkgs
  nixpkgs ? builtins.fetchTarball {
    url = pins.nixpkgs.archive;
    sha256 = pins.nixpkgs.hash;
  },
  bootstrapUrl ? null,
  bootstrapFiles ? import ./bootstrap/files.nix { baseUrl = bootstrapUrl; },
  # The Nix source to build: nixpkgs' `nixVersions.nix_2_35` packaging, with its source replaced by the
  # illumos branch of nix-src (upstream 2.35.2 plus the illumos series).
  nixSrc ? builtins.fetchTarball {
    # a GitHub archive of the illumos-support-2.35 commit: the tree a checkout has (nix-src has no export-ignore),
    # fetched without git
    url = pins.nix-src.archive;
    sha256 = pins.nix-src.hash;
  },
  # more overlays, after this repo's, and nixpkgs config
  overlays ? [ ],
  config ? { },
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
  inherit config;
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
      # setup hooks that make the archives (ar) and zip archives (jars, jmods) a package installs the same from one build
      # to the next
      normalizeArchives = final.callPackage ./pkgs/normalize-archives { };
      normalizeZips = final.callPackage ./pkgs/normalize-zips { };
      # a pre-built OpenJDK 11 to bootstrap OpenJDK from source
      tribblix-jdk-bin = final.callPackage ./pkgs/tribblix-jdk-bin { };
      # OpenJDK 11 built from source with the illumos port, headless (SmartOS builds illumos' Java parts with it)
      openjdk11-illumos = final.callPackage ./pkgs/openjdk11-illumos { };
      # rust-lang.org's Rust toolchain for illumos, and a rustPlatform that builds with it
      rust-illumos-bin = final.callPackage ./pkgs/rust-illumos-bin { };
    })
  ]
  ++ overlays;
}
