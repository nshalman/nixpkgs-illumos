# GNU bash 4.3.30 as illumos-extra builds it for the platform (bash/Makefile): 32 bits, its two patches, make without
# -j (PARALLEL is empty), installed by `make install`.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-bash";
  version = "4.3.30";
  dir = "bash";
  ver = "bash-4.3.30";
  patches = "Patches/*";
  parallel = false;
}
