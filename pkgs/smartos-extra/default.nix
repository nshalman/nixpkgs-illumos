# What illumos-extra adds to SmartOS's proto area after the illumos build: smartos-live's 0-extra-stamp, `gmake
# install` in illumos-extra without STRAP (a non-strap build), with the same illumos-extra commit as the strap
# (../smartos-strap). Each package is compiled by the strap gcc 10 against the proto area of the illumos build
# (smartos-illumos.nightly), where theirs builds against smartos-live's proto, which by then also holds the
# illumos-extra packages installed before it.
#
# One derivation per illumos-extra directory, as for the strap; a package also built for the strap is that
# derivation with strap = false. Each output is laid out as that package's part of the proto area.
{
  lib,
  newScope,
  smartos-strap,
  smartos-illumos,
  # nixpkgs' perl, for the builds that run the build host's perl there; a `perl` of this scope's own (illumos-extra's
  # perl for the platform) would shadow it in callPackage
  perl,
}:

lib.makeScope newScope (self: {
  # the proto area the packages build against: their DESTDIR before illumos-extra installs into it
  illumosProto = "${smartos-illumos.nightly}/proto";

  # the strap scope's compilers, PATH entries and helpers
  inherit (smartos-strap)
    strapBin
    illumosExtraSrc
    gcc
    gxx
    libDirFlags
    ;

  # first, before the other packages (PRIMARY_COMPILER fixup)
  gcc10 = self.callPackage ./gcc10.nix { };

  libz = smartos-strap.libz.override {
    strap = false;
    inherit (self) illumosProto;
  };
  bzip2 = smartos-strap.bzip2.override { strap = false; };
  cpp = smartos-strap.cpp.override {
    strap = false;
    inherit (self) illumosProto;
  };

  # the strap's autoconf packages, built the non-strap way, against the illumos proto area or (mkAutoconfAgainst) a
  # view of it
  mkAutoconfAgainst =
    illumosProto:
    smartos-strap.callPackage ../smartos-strap/autoconf.nix {
      strap = false;
      inherit illumosProto;
    };
  mkAutoconf = self.mkAutoconfAgainst self.illumosProto;
  libexpat = smartos-strap.libexpat.override { mkStrapAutoconf = self.mkAutoconf; };
  libidn = smartos-strap.libidn.override { mkStrapAutoconf = self.mkAutoconf; };
  # before libz in their build (SUBDIRS order), so without it, as the platform's libxml2 is
  libxml = smartos-strap.libxml.override { mkStrapAutoconf = self.mkAutoconf; };

  openssl3 = smartos-strap.openssl3.override {
    strap = false;
    inherit (self) illumosProto;
  };
  libidn2 = self.callPackage ./libidn2.nix { };
  bash = self.callPackage ./bash.nix { };
  less = self.callPackage ./less.nix { };
  gtar = self.callPackage ./gtar.nix { };
  gzip = self.callPackage ./gzip.nix { };
  coreutils = self.callPackage ./coreutils.nix { inherit perl; };
  rsync = self.callPackage ./rsync.nix { };
  uuid = self.callPackage ./uuid.nix { };
  socat = self.callPackage ./socat.nix { };
  gnupg = self.callPackage ./gnupg.nix { };
  tun = self.callPackage ./tun.nix { };
  screen = self.callPackage ./screen.nix { };
  ncurses = self.callPackage ./ncurses.nix { };
  dialog = self.callPackage ./dialog.nix { };
  vim = self.callPackage ./vim.nix { };
  pbzip2 = self.callPackage ./pbzip2.nix { };
  xz = self.callPackage ./xz.nix { };
})
