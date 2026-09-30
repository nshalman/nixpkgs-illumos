# OpenLDAP 2.5.14's client side as illumos-extra builds it for the platform (openldap/Makefile): 32 bits under
# /usr/openldap, its two patches (OpenSSL's platform names), no slapd or SASL, TLS through OpenSSL, RUNPATH
# /usr/openldap/lib added; installed by `make install`. The top Makefile makes it wait for openssl3, and the
# platform's programs link it.
{
  mkAutoconf,
  openssl3,
  hostTools,
}:

mkAutoconf {
  pname = "smartos-extra-openldap";
  version = "2.5.14";
  dir = "openldap";
  ver = "openldap-2.5.14";
  tarball = "openldap-2.5.14.tgz";
  patches = "Patches/*";
  prefix = "/usr/openldap";
  deps = [ openssl3 ];
  # its manuals are run through soelim, the platform's /usr/bin/soelim on their build host (hostTools)
  nativeBuildInputs = [ hostTools ];
  ldflags = "-Wl,-R/usr/openldap/lib";
  configureFlags = [
    "--disable-slapd"
    "--without-cyrus-sasl"
    "--sysconfdir=/etc"
    "--localstatedir=/var/dp/openldap"
    "--with-tls=openssl"
  ];
}
