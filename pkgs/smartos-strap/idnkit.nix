# idnkit 2.3 as illumos-extra builds it, only in the strap (idnkit/Makefile, STRAP_ONLY): 32 bits, no CFLAGS at all
# (the Makefile sets none), installed by its own `make install`.
{ mkStrapAutoconf }:

mkStrapAutoconf {
  pname = "smartos-strap-idnkit";
  version = "2.3";
  dir = "idnkit";
  ver = "idnkit-2.3";
  tarball = "idnkit-2.3.tar.bz2";
  install = ''
    (cd idnkit-2.3-32strap && env -i PATH="$PATH" make V=1 DESTDIR=$out install)
  '';
}
