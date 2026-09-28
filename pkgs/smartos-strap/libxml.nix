# libxml2 2.13.8 as illumos-extra builds it for the strap (libxml/Makefile): the GNOME git tag's tarball, which has
# no configure, regenerated with `autoreconf -fi` (FROB_SENTINEL); 32 and 64 bits, CPPFLAGS in CC as well, no CFLAGS
# or LDFLAGS given to configure (AUTOCONF_CFLAGS and AUTOCONF_LDFLAGS are empty), LIBS="-lpthread -lc" for the
# 32-bit build only (LIBS.64 is empty); installed by libxml/install-libxml2{,-64}: the library in lib with links in
# usr/lib, the headers, libxml.m4 and two manuals, and the 64-bit xmllint and xmlcatalog, stripped.
#
# illumos-extra bug, reproduced: the Makefile's LIBXML2_LDFLAGS (-zdefs, -ztext, -zcombreloc and its mapfile) is
# added to LDFLAGS, which neither configure nor make is given (AUTOCONF_LDFLAGS is empty), so the library is linked
# without them: no mapfile, no symbol versioning from it.
#
# illumos-extra bug, reproduced: LIBS (-lpthread -lc) is set for the 32-bit build only; LIBS.64 stays empty.
#
# autoreconf is nixpkgs' autoconf, automake and libtool (theirs: pkgsrc's). nixpkgs' aclocal finds macros
# through ACLOCAL_PATH, which is kept through `env -`.
{
  mkStrapAutoconf,
  autoconf,
  automake,
  libtool,
  pkg-config,
}:

mkStrapAutoconf {
  pname = "smartos-strap-libxml2";
  version = "2.13.8";
  dir = "libxml";
  ver = "libxml2-v2.13.8";
  bits = [
    32
    64
  ];
  nativeBuildInputs = [
    autoconf
    automake
    libtool
    pkg-config
  ];
  frob = ''(cd $d && env -i PATH="$PATH" ACLOCAL_PATH="$ACLOCAL_PATH" autoreconf -fi)'';
  cppInCC = true;
  passCflags = false;
  passLdflags = false;
  cppflags = "-D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE";
  libs = "-lpthread -lc";
  configureFlags = [
    "--with-threads"
    "--without-python"
    "--with-legacy"
    "--with-aix-soname=svr4"
  ];
  install = ''
    DESTDIR=$out bash -e ./install-libxml2 libxml2-v2.13.8-32strap
    DESTDIR=$out bash -e ./install-libxml2-64 libxml2-v2.13.8-64strap
  '';
}
