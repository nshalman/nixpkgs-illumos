# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on its own stdenv, pkgs/stdenv/illumos, given this repo's
# bootstrap files and toolchain packages. ./bridge.nix is how those bootstrap files were first made.
#   nix-build illumos.nix -A hello
# Every input is pinned to where it is published (tests/pins.sh); a local checkout of illumos-26.05 can stand in:
#   nix-build illumos.nix --arg nixpkgs /path/to/illumos-26.05 -A hello
# bootstrapUrl is the directory of a release not hosted yet; see bootstrap/files.nix.
{
  nixpkgs ? builtins.fetchTarball {
    # the illumos-26.05 branch of github.com/nshalman/nixpkgs
    url = "https://github.com/nshalman/nixpkgs/archive/4eee97ee70a159d8d78a47df7b1a8500c38e2652.tar.gz";
    sha256 = "1is5fz8ym2z68vyk1ywh9ilipa3y9fw49b8dci539q84wx76d7m7";
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
  config = {
    # SmartOS's strap node.js 0.10 (pkgs/smartos-strap/node.nix) is built with gyp, which needs python 2. Build time
    # only: nothing installed refers to it.
    permittedInsecurePackages = [ "python-2.7.18.12" ];
  };
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
      # The strap toolchain SmartOS builds illumos with (illumos-extra's binutils 2.34 and gcc 10), built here by
      # this stdenv against the sysroot. Not part of the bootstrap.
      binutils-strap = final.callPackage ./pkgs/binutils-strap { };
      gcc10-illumos = final.callPackage ./pkgs/gcc10-illumos { };
      # SmartOS's proto.strap: illumos-extra's strap packages built by that gcc 10.
      smartos-strap = final.callPackage ./pkgs/smartos-strap { };
      # illumos as SmartOS builds it (illumos-joyent), with that proto.strap.
      smartos-illumos = final.callPackage ./pkgs/smartos-illumos { };
      # what illumos-extra adds to SmartOS's proto area after illumos, built by the same gcc 10
      smartos-extra = final.callPackage ./pkgs/smartos-extra { };
      # a pre-built OpenJDK 11 to bootstrap OpenJDK from source
      tribblix-jdk-bin = final.callPackage ./pkgs/tribblix-jdk-bin { };
      # OpenJDK 11 built from source with the illumos port, headless; SmartOS builds illumos' Java parts with JDK 11
      openjdk11-illumos = final.callPackage ./pkgs/openjdk11-illumos { };
    })
  ];
}
