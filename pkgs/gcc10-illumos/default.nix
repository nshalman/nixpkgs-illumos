# gcc 10 configured as illumos-extra configures it for SmartOS's strap toolchain (--with-gnu-as and binutils 2.34's
# gas), otherwise the same recipe as gcc-illumos: built by this stdenv, against the sysroot. It is meant to be
# called directly, the way illumos' build calls its compilers, not through the cc-wrapper (see ../gcc-illumos/10.nix).
#
# Called directly, it has no wrapper to hand it a link-editor, so like illumos-extra's it is configured --with-ld:
# illumos-ld, the link-editor built from the pinned illumos-gate commit, where illumos-extra names the build host's
# /usr/bin/ld. Both honour LD_ALTEXEC.
#
# Like illumos-extra's gcc 10, what it compiles uses the build host's headers and libc (runtimeSysroot "/"), and its
# include-fixed is made from the build host's headers; what it links gets their RUNPATH, /usr/gcc/10/lib (amd64 for
# 64-bit), so illumos built with it records no store path, and finds the C++ runtime SmartOS ships in /usr/lib; and
# it is multilib: 64-bit runtime libraries in lib/amd64, 32-bit ones in lib. Differences from theirs (Makefile.gcc): gcc itself and its runtime libraries are built against
# the sysroot (--with-build-sysroot), --with-ld names illumos-ld, prefix in the store instead of /usr/gcc/10.
{
  callPackage,
  fetchurl,
  binutils-strap,
  illumos-ld,
}:

callPackage ../gcc-illumos {
  release = import ../gcc-illumos/10.nix { inherit fetchurl; };
  assembler = "${binutils-strap}/bin/as";
  linker = "${illumos-ld}/bin/ld";
  multilib = true;
  runtimeSysroot = "/";
  runpath = "/usr/gcc/10/lib";
}
