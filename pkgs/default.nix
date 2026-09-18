{ callPackage }:

{
  illumos-sysroot = callPackage ./illumos-sysroot { };
  illumos-ld = callPackage ./illumos-ld { };
  gcc-illumos = callPackage ./gcc-illumos { };
}
