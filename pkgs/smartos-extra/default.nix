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
  fetchurl,
  requireFile,
  smartos-strap,
  smartos-illumos,
  # nixpkgs' perl, for the builds that run the build host's perl there; a `perl` of this scope's own (illumos-extra's
  # perl for the platform) would shadow it in callPackage
  perl,
}:

lib.makeScope newScope (self: {
  # the proto area the packages build against: their DESTDIR before illumos-extra installs into it
  illumosProto = "${smartos-illumos.nightly}/proto";

  # SmartOS's own platform from the same illumos-extra commit, for comparison only: release-20260903
  # (20260903T001557Z), whose gitstatus.json names illumos-extra 5850d8e9 (its illumos-joyent is the release branch's
  # feb8a55d, not the nightly's 40120018). platformReference is the files a running platform shows, the boot archive's
  # root with /usr from usr.lgz; making it takes root and lofi (tests/smartos-platform-reference.sh), so it is added
  # to the store by hand.
  platformTarball = fetchurl {
    url = "https://us-central.manta.mnx.io/Joyent_Dev/public/SmartOS/20260903T001557Z/platform-release-20260903-20260903T001557Z.tgz";
    sha256 = "fe0db94859cff38186b3c99b3d51dc6f6f4d98c10a1b6a66ce04f2cc18d1c2da";
  };
  platformReference = requireFile {
    name = "smartos-platform-20260903T001557Z";
    hashMode = "recursive";
    sha256 = "1kqxvmkpgbg97jxl0lwhpiwvc3h09djn1mnklhhskz56dljxjx2v";
    message = ''
      The unpacked SmartOS platform release-20260903 is made from its published tarball by a script that needs root
      and lofi (a zone with /dev/lofictl will do):
        tests/smartos-platform-reference.sh PLATFORM-TGZ /var/tmp/ref/smartos-platform-20260903T001557Z
        nix-store --add-fixed --recursive sha256 /var/tmp/ref/smartos-platform-20260903T001557Z
      where PLATFORM-TGZ is smartos-extra.platformTarball.
    '';
  };

  # the strap scope's compilers, PATH entries and helpers
  inherit (smartos-strap)
    strapBin
    illumosExtraSrc
    gcc
    gxx
    libDirFlags
    ;

  # the strap's autoconf packages, built the non-strap way, against the illumos proto area or (mkAutoconfAgainst) a
  # view of it
  mkAutoconfAgainst =
    illumosProto:
    smartos-strap.callPackage ../smartos-strap/autoconf.nix {
      strap = false;
      inherit illumosProto;
    };
  mkAutoconf = self.mkAutoconfAgainst self.illumosProto;

  # Store paths in what a package installs are build locations: the proto area's and the compiler's directories in
  # debug information, compile commands a program embeds, the output file name the link-editor records. The platform's
  # binaries carry their own build's in the same places. finishPackage maps them away after the install
  # (./map-store-paths.pl: each to the place it stands for, padded with slashes to the same length, so binaries keep
  # their layout) and recomputes the DT_CHECKSUM of the ELF files it changed. With mapStorePaths = false the store
  # paths are left in and leak into the platform's files (tests/smartos-extra.nix no-store-paths then fails on them).
  mapStorePaths = true;

  # what is done to each package below once it is built
  finishPackage =
    pkg:
    if !self.mapStorePaths then
      pkg
    else
      pkg.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          ${perl}/bin/perl ${./map-store-paths.pl} $out | while IFS= read -r f; do
            if /usr/bin/elfdump -d "$f" 2>/dev/null | grep ' CHECKSUM ' >/dev/null; then
              mode=$(stat -c %a "$f")
              chmod u+w "$f"
              /usr/bin/elfedit -e dyn:checksum "$f"
              chmod "$mode" "$f"
            fi
          done
        '';
      });

  # first, before the other packages (PRIMARY_COMPILER fixup)
  gcc10 = self.callPackage ./gcc10.nix { };
}
// lib.mapAttrs (_: self.finishPackage) {
  libz = smartos-strap.libz.override {
    strap = false;
    inherit (self) illumosProto;
  };
  bzip2 = smartos-strap.bzip2.override { strap = false; };
  cpp = smartos-strap.cpp.override {
    strap = false;
    inherit (self) illumosProto;
  };

  libexpat = smartos-strap.libexpat.override { mkStrapAutoconf = self.mkAutoconf; };
  libidn = smartos-strap.libidn.override { mkStrapAutoconf = self.mkAutoconf; };
  # before libz in their build (SUBDIRS order), so without it, as the platform's libxml2 is
  libxml = smartos-strap.libxml.override { mkStrapAutoconf = self.mkAutoconf; };

  perl = smartos-strap.perl.override {
    strap = false;
    inherit (self) illumosProto;
  };
  nss-nspr = smartos-strap.nss-nspr.override {
    strap = false;
    inherit (self) illumosProto;
  };
  openssl1x = smartos-strap.openssl1x.override {
    strap = false;
    inherit (self) illumosProto;
  };
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
