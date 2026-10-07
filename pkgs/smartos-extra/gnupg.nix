# GnuPG 1.4.23 as illumos-extra builds it for the platform (gnupg/Makefile): 32 bits, its three patches, installed by
# `make install`. Its configure uses zlib and bzip2 where it finds them in the proto area and falls back to its own
# copies otherwise; the Makefile declares neither, but the platform's gpg links both (libz.so.1, libbz2.so.1), so they
# were installed before it there, as they are given here.
#
# illumos-extra bug, not reproduced: the manuals are dated the day of the build (doc/yat2m.c, time (NULL)); here
# SOURCE_DATE_EPOCH, as later yat2m versions take it.
{
  mkAutoconf,
  libz,
  bzip2,
}:

mkAutoconf {
  pname = "smartos-extra-gnupg";
  version = "1.4.23";
  dir = "gnupg";
  ver = "gnupg-1.4.23";
  tarball = "gnupg-1.4.23.tar.bz2";
  patches = "Patches/*";
  frob = ''
    chmod 755 $d/configure
    substituteInPlace $d/doc/yat2m.c --replace-fail 'time_t atime = time (NULL);' \
      'time_t atime = getenv ("SOURCE_DATE_EPOCH") ? (time_t) strtoll (getenv ("SOURCE_DATE_EPOCH"), NULL, 10) : time (NULL);'
  '';
  deps = [
    libz
    bzip2
  ];
}
