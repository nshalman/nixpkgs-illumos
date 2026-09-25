# gcc 10, the compiler SmartOS builds illumos with (illumos-extra gcc10, smartos-live's default PRIMARY_COMPILER;
# upstream illumos-gate's illumos.sh names gcc 10 primary as well). The source and the in-tree libraries are the ones
# illumos-extra builds: the GitHub archive of the tag has the same tree as illumos-extra's gcc-10.4.0-il-2.tar.gz
# (sha1 2378fec3…), and the mpfr, gmp and mpc tarballs match illumos-extra's sha1 files.
#
# Patches: illumos-extra's single gcc 10 patch is 1000-ld-flags.patch, of which ./ld-flags.patch is the Nix
# version (library paths under the store instead of /usr/gcc/10). The next three are this repo's gcc 14 patches,
# which apply unchanged. Left out:
#   - ./asm-debug-prefix-map.patch: it hands %(asm_debug) to the assembler for compiled code, and gcc 10's
#     ASM_DEBUG_SPEC (gcc/gcc.c) holds --gdwarf2 for any -g, so gas makes a line table of its own beside cc1's
#     .file/.loc directives ("Error: file number 1 already allocated", libstdc++'s eh_globals.cc in stage 1). What
#     the patch is for, DWARF 5 without a `.file 0`, does not arise: gcc 10 writes DWARF 4.
#   - nixpkgs' mangle-NIX_STORE-in-__FILE__.patch: no gcc 10 version, so this gcc is not suitable behind the
#     cc-wrapper.
{ fetchurl }:

{
  version = "10.4.0-il-2";
  src = fetchurl {
    url = "https://github.com/illumos/gcc/archive/refs/tags/gcc-10.4.0-il-2.tar.gz";
    sha256 = "07vw0jgyy73irw0lzx80321dcfcv8d00wmplviybqav048h2was2";
  };
  mpfr = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.0.tar.bz2";
    sha256 = "17crm8g5zcpaq867avgfngrchlia1x5iwna6q1hc8vz3g28v67b9";
  };
  gmp = fetchurl {
    url = "https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.bz2";
    sha256 = "0z2ddfiwgi0xbf65z4fg4hqqzlhv0cc6hdcswf3c6n21xdmk5sga";
  };
  mpc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz";
    sha256 = "1f2rqz0hdrrhx4y1i5f8pv6yv08a876k1dqcm9s2p26gyn928r5b";
  };
  patches = [
    ./ld-flags.patch
    ./madvise-decl.patch
    ./no-ccs-exec-prefix.patch
    ./ts-errno.patch
  ];
}
