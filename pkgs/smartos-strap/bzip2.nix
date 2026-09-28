# bzip2 1.0.6 as illumos-extra builds it for the strap (bzip2/Makefile): its patch applied, then bzip2's sources
# built twice by illumos-extra's own makefile (makefile.build and Makefile.com, copied into i386/ and amd64/) with
# the strap gcc as CC: libbz2.so.1 with illumos-extra's mapfile for both word sizes, the programs 32-bit only;
# installed by bzip2/install-bzip2 (programs stripped, bzgrep run by ksh, hard links for bunzip2, bzcat, bzegrep,
# bzfgrep, bzless, bzcmp).
#
# illumos-extra bug, not reproduced: Makefile.com adds -L$(DESTDIR)/usr/lib -L$(DESTDIR)/lib, but the makefile runs
# under `env -`, so DESTDIR is empty there and those name the build host's /usr/lib and /lib. Against the sysroot
# that would link the host's libraries, so they are left out. Nothing else is linked: only libbz2 (-L.) and libc.
{
  stdenv,
  strapBin,
  illumosExtra,
  gcc,
}:

stdenv.mkDerivation {
  pname = "smartos-strap-bzip2";
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
    mv .unpack/bzip2-1.0.6 bzip2-1.0.6strap
    rmdir .unpack
    (cd bzip2-1.0.6strap && patch -p1 <../bzip2.patch)
    cp bzip2-1.0.6strap/Makefile bzip2-1.0.6strap/Makefile.dist
    for m in i386 amd64; do
      mkdir bzip2-1.0.6strap/$m
      cp makefile.build bzip2-1.0.6strap/$m/Makefile
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
    (cd bzip2-1.0.6strap/i386 && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1 CC="${gcc} -m32")
    (cd bzip2-1.0.6strap/amd64 && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1 CC="${gcc} -m64")
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    DESTDIR=$out bash -e ./install-bzip2 $PWD/bzip2-1.0.6strap
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
