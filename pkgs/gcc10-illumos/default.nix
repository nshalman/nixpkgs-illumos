# gcc 10 configured as illumos-extra configures it for SmartOS's strap toolchain (--with-gnu-as and binutils 2.34's
# gas), otherwise the same recipe as gcc-illumos: built by this stdenv, against the sysroot. It is meant to be
# called directly, the way illumos' build calls its compilers, not through the cc-wrapper (see ../gcc-illumos/10.nix).
#
# Called directly, it has no wrapper to hand it a link-editor, so like illumos-extra's it is configured --with-ld:
# illumos-ld, the link-editor built from the pinned illumos-gate commit, where illumos-extra names the build host's
# /usr/bin/ld. Both honour LD_ALTEXEC.
#
# Differences from illumos-extra's gcc 10 (Makefile.gcc): --with-sysroot, --with-ld naming illumos-ld, prefix in the
# store instead of /usr/gcc/10, --disable-multilib.
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
}
