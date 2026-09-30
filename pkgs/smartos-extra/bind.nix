# BIND 9.10.1-P1's DNS tools as illumos-extra builds them for the platform (bind/Makefile): 32 bits, its three
# patches, no libxml2, JSON or OpenSSL, CFLAGS -g plus CPPFLAGS, make without -j (PARALLEL is empty); only dig, host
# and nslookup and their manuals installed (bind/install-joyent). Left out: INSTALL="/usr/ucb/install -c", which
# only `make install` would use.
#
# install-joyent copies the manuals into usr/share/man/man1 without making it, which their proto area already has;
# it is made here first.
{ mkAutoconf, illumosProto }:

mkAutoconf {
  pname = "smartos-extra-bind";
  version = "9.10.1-P1";
  dir = "bind";
  ver = "bind-9.10.1-P1";
  patches = "Patches/*";
  parallel = false;
  configureFlags = [
    "--with-libxml2=no"
    "--with-libjson=no"
    "--without-openssl"
  ];
  install = suffix: ''
    mkdir -p $out/usr/share/man/man1
    DESTDIR=$out VERS=bind-9.10.1-P1-32${suffix} bash ./install-joyent
  '';
  # CFLAGS += -g $(CPPFLAGS): CPPFLAGS is their proto area's headers alone, here this package's output's and the
  # illumos proto area's, as the helper gives CPPFLAGS
  cflags = "-g -isystem $out/usr/include -isystem ${illumosProto}/usr/include";
}
