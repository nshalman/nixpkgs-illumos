{ callPackage }:

{
  illumos-sysroot = callPackage ./illumos-sysroot { };
  illumos-ld = callPackage ./illumos-ld { };
}
