# less 661 as illumos-extra builds it for the platform (less/Makefile): 64 bits only, installed by `make install`.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-less";
  version = "661";
  dir = "less";
  ver = "less-661";
  bits = [ 64 ];
}
