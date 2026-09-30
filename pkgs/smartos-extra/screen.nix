# GNU screen 4.9.1 as illumos-extra builds it for the platform (screen/Makefile): 32 bits, its six patches, configure
# given its own CFLAGS (after AUTOCONF_ENV's, so they replace them) and the proto area's usr/lib as LD_LIBRARY_PATH
# for the programs it runs; the screen program and its manual installed.
{ mkAutoconf, illumosProto }:

mkAutoconf {
  pname = "smartos-extra-screen";
  version = "4.9.1";
  dir = "screen";
  ver = "screen-4.9.1";
  patches = "Patches/*";
  configureEnv = ''CFLAGS="-std=c99 -D_XOPEN_SOURCE=700 -D__EXTENSIONS__=1" LD_LIBRARY_PATH=${illumosProto}/usr/lib'';
  configureFlags = [
    "--enable-colors256"
    "--with-sys-screenrc=/etc/screenrc"
  ];
  install = suffix: ''
    mkdir -p $out/usr/bin $out/usr/share/man/man1
    install -m 0555 screen-4.9.1-32${suffix}/screen $out/usr/bin/screen
    install -m 0444 screen-4.9.1-32${suffix}/doc/screen.1 $out/usr/share/man/man1/screen.1
  '';
}
