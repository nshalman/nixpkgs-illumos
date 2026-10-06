# nixpkgs (the illumos-26.05 branch) for x86_64-solaris on its own stdenv, pkgs/stdenv/illumos, given this repo's
# bootstrap files and toolchain packages. ./bridge.nix is how those bootstrap files were first made.
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
      # smartos-live's own stages (src, man, ...), built against those
      smartos-live = final.callPackage ./pkgs/smartos-live { };
      # smartos-live's Jenkins "debug" build: the same, on a DEBUG nightly (stamp's last digit 8)
      smartos-illumos-debug = final.smartos-illumos.overrideScope (
        _: prev: { nightly = prev.nightly.override { debug = true; }; }
      );
      smartos-extra-debug = final.smartos-extra.override { smartos-illumos = final.smartos-illumos-debug; };
      smartos-live-debug = final.smartos-live.override {
        smartos-illumos = final.smartos-illumos-debug;
        smartos-extra = final.smartos-extra-debug;
        flavor = "debug";
      };
      # a pre-built OpenJDK 11 to bootstrap OpenJDK from source
      tribblix-jdk-bin = final.callPackage ./pkgs/tribblix-jdk-bin { };
      # OpenJDK 11 built from source with the illumos port, headless; SmartOS builds illumos' Java parts with JDK 11
      openjdk11-illumos = final.callPackage ./pkgs/openjdk11-illumos { };
      # rust-lang.org's Rust toolchain for illumos, and a rustPlatform that builds with it
      rust-illumos-bin = final.callPackage ./pkgs/rust-illumos-bin { };
      # a bhyve VMM in Rust (rshyve, firehyve), built with it
      rust-bhyve = final.callPackage ./pkgs/rust-bhyve { };
    })
  ];
}
