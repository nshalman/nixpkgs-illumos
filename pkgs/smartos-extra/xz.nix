# xz 5.2.1 as illumos-extra builds it for the platform (xz/Makefile): 32 bits, --disable-rpath, then its install
# target: liblzma copied under a private name by elfedit, its SONAME libjoy_lzma.so.5, and the xz program's first
# NEEDED entry (checked to be liblzma.so.5) renamed to match, so that nothing else on the platform links it by the
# usual name; and the manual. The platform's libjoy_lzma.so.5 and xzcat links are the manifest's.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-xz";
  version = "5.2.1";
  dir = "xz";
  ver = "xz-5.2.1";
  configureFlags = [ "--disable-rpath" ];
  install = suffix: ''
    mkdir -p $out/usr/bin $out/usr/lib $out/usr/share/man/man1
    /usr/bin/elfedit -e 'dyn:value -s SONAME libjoy_lzma.so.5' \
      xz-5.2.1-32${suffix}/src/liblzma/.libs/liblzma.so.5.2.1 $out/usr/lib/libjoy_lzma.so.5.2.1
    chmod 0555 $out/usr/lib/libjoy_lzma.so.5.2.1
    /usr/bin/elfedit -e 'dyn:value -dynndx 0' xz-5.2.1-32${suffix}/src/xz/.libs/xz | /usr/bin/grep liblzma.so.5 >/dev/null
    /usr/bin/elfedit -e 'dyn:value -s -dynndx 0 libjoy_lzma.so.5' xz-5.2.1-32${suffix}/src/xz/.libs/xz $out/usr/bin/xz
    install -m 0555 xz-5.2.1-32${suffix}/src/xz/xz.1 $out/usr/share/man/man1
  '';
}
