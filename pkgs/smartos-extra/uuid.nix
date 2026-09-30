# OSSP uuid 1.6.2 as illumos-extra builds it for the platform (uuid/Makefile): 32 bits, --disable-shared, the uuid
# program and its manual installed.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-uuid";
  version = "1.6.2";
  dir = "uuid";
  ver = "uuid-1.6.2";
  configureFlags = [ "--disable-shared" ];
  install = suffix: ''
    mkdir -p $out/usr/bin $out/usr/share/man/man1
    install -m 0555 uuid-1.6.2-32${suffix}/uuid $out/usr/bin
    install -m 0444 uuid-1.6.2-32${suffix}/uuid.1 $out/usr/share/man/man1
  '';
}
