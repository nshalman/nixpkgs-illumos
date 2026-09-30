# socat 1.7.4.1 as illumos-extra builds it for the platform (socat/Makefile): 32 bits, its two patches, no interface
# or readline support, installed by `make install`.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-socat";
  version = "1.7.4.1";
  dir = "socat";
  ver = "socat-1.7.4.1";
  patches = "Patches/*";
  configureFlags = [
    "--disable-interface"
    "--disable-readline"
  ];
}
