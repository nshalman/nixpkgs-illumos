# bzip2 1.0.6 as illumos-extra builds it for the strap (bzip2/Makefile): its patch applied, then bzip2's sources
# built twice by illumos-extra's own makefile (makefile.build and Makefile.com, copied into i386/ and amd64/) with
# the strap gcc as CC: libbz2.so.1 with illumos-extra's mapfile for both word sizes, the programs 32-bit only;
# installed by bzip2/install-bzip2 (programs stripped, bzgrep run by ksh, hard links for bunzip2, bzcat, bzegrep,
# bzfgrep, bzless, bzcmp).
#
# illumos-extra bug, not reproduced: Makefile.com adds -L$(DESTDIR)/usr/lib -L$(DESTDIR)/lib, but the makefile runs
# under `env -`, so DESTDIR is empty there and those name the build host's /usr/lib and /lib. Against the sysroot
# that would link the host's libraries, so they are left out. Nothing else is linked: only libbz2 (-L.) and libc.
#
# With strap = false, as illumos-extra builds it for the platform (pkgs/smartos-extra): the same build, in a directory
# without the strap suffix. Makefile.com's non-strap additions (GENLDFLAGS) do not take effect there either: under
# `env -` STRAP is empty, so its `ifneq ($(STRAP),strap)` holds in both builds, and GENLDFLAGS, set only in
# Makefile.defs, is empty. Nor does the build name the proto area: it compiles against the compiler's own headers.
{
  lib,
  stdenv,
  strapBin,
  illumosExtra,
  gcc,
  strap ? true,
}:

let
  # the build directory (bzip2/Makefile VER)
  dir = "bzip2-1.0.6${lib.optionalString strap "strap"}";
in
stdenv.mkDerivation {
  pname = if strap then "smartos-strap-bzip2" else "smartos-extra-bzip2";
  version = "1.0.6";

  src = illumosExtra;

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp $src/install.subr ie/
    cp -r $src/bzip2 ie/bzip2
    chmod -R u+w ie
    cd ie/bzip2
    mkdir .unpack
    tar xzf bzip2-1.0.6.tar.gz -C .unpack --no-same-owner
    mv .unpack/bzip2-1.0.6 ${dir}
    rmdir .unpack
    (cd ${dir} && patch -p1 <../bzip2.patch)
    cp ${dir}/Makefile ${dir}/Makefile.dist
    for m in i386 amd64; do
      mkdir ${dir}/$m
      cp makefile.build ${dir}/$m/Makefile
    done
    runHook postUnpack
  '';

  postPatch = ''
    sed -i '/^LDFLAGS += -L\. -L\$(DESTDIR)\/usr\/lib -L\$(DESTDIR)\/lib$/s/ -L\$(DESTDIR)\/usr\/lib -L\$(DESTDIR)\/lib//' Makefile.com
    grep -q '^LDFLAGS += -L\.$' Makefile.com
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    (cd ${dir}/i386 && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1 CC="${gcc} -m32")
    (cd ${dir}/amd64 && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1 CC="${gcc} -m64")
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    DESTDIR=$out bash -e ./install-bzip2 $PWD/${dir}
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
