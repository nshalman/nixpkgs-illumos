# GNU libidn 1.11 as illumos-extra builds it for the strap (libidn/Makefile): 32 bits only, with its two patches,
# installed by libidn/install-sfw: the library and links in usr/lib, seven headers in usr/include. Left out:
# INSTALL="/usr/ucb/install -c", which only `make install` would use.
#
# The patches touch sources the manual's texinfo pages are generated from, so make regenerates them with perl,
# found on the build host's PATH there and given here.
{ mkStrapAutoconf, perl }:

mkStrapAutoconf {
  pname = "smartos-strap-libidn";
  version = "1.11";
  dir = "libidn";
  ver = "libidn-1.11";
  patches = "Patches/*";
  nativeBuildInputs = [ perl ];
  cppflags = "-D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE";
  cflags = "-g";
  install = suffix: ''
    DESTDIR=$out VERS=libidn-1.11-32${suffix} bash -e ./install-sfw
  '';
}
