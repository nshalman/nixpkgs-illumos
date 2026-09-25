# GNU binutils 2.34 as illumos-extra builds it for SmartOS's strap toolchain (illumos-extra binutils/): the
# assembler that smartos-live builds illumos with (it points GNU_ROOT at it) and that illumos-extra's gcc 10 is
# configured with. The tarball is byte-identical to the one illumos-extra carries, and the patches are
# illumos-extra's, unchanged (illumos-extra 5850d8e9, binutils/patches).
#
# Differences from illumos-extra's build, on purpose: a 64-bit build by this stdenv against the sysroot (theirs is
# a 32-bit one, i386-pc-solaris2.11, by the build host's gcc against its /usr/include), installed under $out
# without their `g` program prefix, so the assembler is bin/as.
{
  lib,
  stdenv,
  fetchurl,
  bison,
  flex,
}:

stdenv.mkDerivation {
  pname = "binutils-strap";
  version = "2.34";

  src = fetchurl {
    url = "https://ftp.gnu.org/gnu/binutils/binutils-2.34.tar.bz2";
    sha256 = "1rin1f5c7wm4n3piky6xilcrpf2s0n3dd5vqq8irrxkcic3i1w49";
  };

  patches = [
    ./binutiles_libfl.patch
    ./gas-25516.diff
    ./stdio-limit.patch
  ];

  nativeBuildInputs = [
    bison
    flex
  ];

  configureFlags = [ "--enable-64-bit-bfd" ];

  # as illumos-extra: no manuals
  makeFlags = [ "MAKEINFO=true" ];

  enableParallelBuilding = true;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/as" --version | grep -q "GNU assembler (GNU Binutils) 2.34"
    printf '\t.text\n\t.globl f\nf:\n\tmovq %%rsp, %%rax\n\tsysenter\n\tret\n' >ic.s
    "$out/bin/as" --64 -o ic.o ic.s
    test -s ic.o
    runHook postInstallCheck
  '';

  meta = {
    description = "GNU binutils 2.34 as SmartOS's illumos-extra builds it, for building illumos";
    homepage = "https://github.com/TritonDataCenter/illumos-extra";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.illumos;
  };
}
