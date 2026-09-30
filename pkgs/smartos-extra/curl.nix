# curl 8.22.0 as illumos-extra builds it for the platform (curl/Makefile): 32 bits, its four patches (libidn2 as
# libjoy_idn2, the platform's OpenSSL names, illumos' old LDAP), against OpenSSL in their proto area
# (--with-openssl=$(DESTDIR)/usr: here openssl3's output), without libpsl; installed by `make install`. The top
# Makefile makes it wait for libz, openssl3 and libidn2, and the platform's curl links all three. Its manuals are made
# by scripts run through `/usr/bin/env perl`, found on PATH (the scope puts perl there, finishPackage).
{
  mkAutoconf,
  libz,
  openssl3,
  libidn2,
}:

mkAutoconf {
  pname = "smartos-extra-curl";
  version = "8.22.0";
  dir = "curl";
  ver = "curl-8.22.0";
  tarball = "curl-8.22.0.tar.bz2";
  patches = "Patches/*";
  deps = [
    libz
    openssl3
    libidn2
  ];
  configureFlags = [
    "--with-openssl=${openssl3}/usr"
    "--without-libpsl"
  ];
}
