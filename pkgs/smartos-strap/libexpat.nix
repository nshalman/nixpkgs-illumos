# expat as illumos-extra builds it for the strap (libexpat/Makefile): 32 and 64 bits, installed by
# libexpat/install-sfw{,-64}: the library and the libexpat.so{,.0,.1} links in usr/lib and usr/lib/amd64, the two
# headers in usr/include. Makefile's CFLAGS (-g -fPIC) reach only the 32-bit build; CFLAGS.64 is empty. Left out:
# INSTALL="/usr/ucb/install -c", which only `make install` would use.
{ mkStrapAutoconf }:

mkStrapAutoconf {
  pname = "smartos-strap-libexpat";
  version = "2.8.2";
  dir = "libexpat";
  ver = "expat-2.8.2";
  bits = [
    32
    64
  ];
  cppflags = "-D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -D_HAVE_EXPAT_CONFIG_H";
  cflags = "-g -fPIC";
  install = ''
    DESTDIR=$out VERS=expat-2.8.2-32strap bash -e ./install-sfw
    DESTDIR=$out VERS=expat-2.8.2-64strap MACH64=amd64 bash -e ./install-sfw-64
  '';
}
