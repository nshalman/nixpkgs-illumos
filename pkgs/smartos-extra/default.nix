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
}:

lib.makeScope newScope (self: {
  # the proto area the packages build against: their DESTDIR before illumos-extra installs into it
  illumosProto = "${smartos-illumos.nightly}/proto";

  libz = smartos-strap.libz.override {
    strap = false;
    inherit (self) illumosProto;
  };
  bzip2 = smartos-strap.bzip2.override { strap = false; };

  # the strap's autoconf packages, built the non-strap way
  mkAutoconf = smartos-strap.callPackage ../smartos-strap/autoconf.nix {
    strap = false;
    inherit (self) illumosProto;
  };
  libexpat = smartos-strap.libexpat.override { mkStrapAutoconf = self.mkAutoconf; };
  libidn = smartos-strap.libidn.override { mkStrapAutoconf = self.mkAutoconf; };
})
