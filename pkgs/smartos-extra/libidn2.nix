# GNU libidn2 2.3.4 as illumos-extra builds it for the platform (libidn2/Makefile): 32 bits, installed by
# libidn2/install-sfw: the library copied under a private name by elfedit (SONAME libjoy_idn2.so.0), links to it, and
# idn2.h. Left out: INSTALL="/usr/ucb/install -c", which only `make install` would use.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-libidn2";
  version = "2.3.4";
  dir = "libidn2";
  ver = "libidn2-2.3.4";
  cppflags = "-D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE";
  cflags = "-g";
  install = suffix: ''
    DESTDIR=$out VERS=libidn2-2.3.4-32${suffix} bash -e ./install-sfw
  '';
}
