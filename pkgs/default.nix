{ callPackage }:

{
  illumos-sysroot = callPackage ./illumos-sysroot { };
  illumos-libc = callPackage ./illumos-libc { };
  illumos-ld = callPackage ./illumos-ld { };
  gcc-illumos = callPackage ./gcc-illumos { };
}
