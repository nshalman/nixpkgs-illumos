# gzip 1.3.5 as illumos-extra builds it for the platform (gzip/Makefile): 32 bits, its four patches, installed by
# `make install` with the z* scripts and their manuals renamed gz*.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-gzip";
  version = "1.3.5";
  dir = "gzip";
  ver = "gzip-1.3.5";
  patches = "Patches/*";
  configureFlags = [ "--mandir=/usr/share/man" ];
  install = suffix: ''
    mkdir -p $out/usr/bin $out/usr/share/man/man1
    (cd gzip-1.3.5-32${suffix} && make -j$NIX_BUILD_CORES DESTDIR=$out install)
    for f in zcmp zdiff zegrep zfgrep zforce zgrep zless zmore znew; do mv $out/usr/bin/$f $out/usr/bin/g$f; done
    for f in zdiff zforce zgrep zless zmore znew; do mv $out/usr/share/man/man1/$f.1 $out/usr/share/man/man1/g$f.1; done
  '';
}
