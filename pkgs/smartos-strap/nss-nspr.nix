# NSS 3.25 with NSPR 4.12 as illumos-extra builds them for the strap (nss-nspr/Makefile): its patches; NSS's own
# build (nss_build_all, which configures and builds NSPR too), serially, once per word size with the strap gcc as
# CC and AS; installed by nss-nspr/install-nss{,-64}: the libraries and their .chk signatures in usr/lib/mps and
# usr/lib/mps/amd64 (with a 64 link), certutil for both word sizes, the headers in usr/include/mps.
#
# NSS's make is not run under `env -`, so it sees what the top-level make exports; of that, STRAP, DESTDIR and
# PKG_CONFIG_LIBDIR are given here (STRAP=strap keeps the patched shlibsign from adding the strap directory to
# LD_LIBRARY_PATH). NSPR_CONFIGURE_ENV names $(CXX.32), a variable the Makefile never sets, so NSPR is configured
# with an empty CXX, as there. The strap directory in the flags is this package's own output (see ./default.nix).
{
  stdenv,
  strapBin,
  illumosExtra,
  gcc,
  gxx,
  libDirFlags,
  perl,
}:

let
  ver = "nss-3.25";
  xcflags = "-Wno-unused -Wno-int-in-bool-context -Wno-stringop-truncation";
in
stdenv.mkDerivation {
  pname = "smartos-strap-nss-nspr";
  version = "3.25";

  src = illumosExtra;

  nativeBuildInputs = [ perl ];

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp $src/install.subr ie/
    cp -r $src/nss-nspr ie/nss-nspr
    chmod -R u+w ie
    cd ie/nss-nspr
    for bits in 32 64; do
      mkdir .unpack$bits
      tar xzf ${ver}-with-nspr-4.12.tar.gz -C .unpack$bits --no-same-owner
      for p in Patches/*; do
        echo "Applying $p"
        patch -d .unpack$bits/${ver} -p1 <"$p"
      done
      mv .unpack$bits/${ver} ${ver}-''${bits}strap
      rmdir .unpack$bits
    done
    runHook postUnpack
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    (cd ${ver}-32strap/nss && env -i PATH="$PATH" STRAP=strap DESTDIR=$out PKG_CONFIG_LIBDIR= \
      make BUILD_OPT=1 BUILD_SUN_PKG=1 NS_USE_GCC=1 NO_MDUPDATE=1 \
      NSPR_CONFIGURE_ENV="CC=\"${gcc} -m32\" CXX=\"\"" \
      CC="${gcc} -m32" CXX="${gxx} -m32" AS="${gcc} -m32" \
      CPPFLAGS="-isystem $out/usr/include" XCFLAGS="${xcflags}" LDFLAGS="${libDirFlags 32 "-L" [ "$out" ]}" \
      NSS_DISABLE_GTESTS=1 nss_build_all)
    (cd ${ver}-64strap/nss && env -i PATH="$PATH" STRAP=strap DESTDIR=$out PKG_CONFIG_LIBDIR= \
      make USE_64=1 BUILD_OPT=1 BUILD_SUN_PKG=1 NS_USE_GCC=1 \
      NSPR_CONFIGURE_ENV="CC=\"${gcc} -m64\" CXX=\"\"" \
      CC="${gcc} -m64" CXX="${gxx} -m64" AS="${gcc} -m64" \
      CPPFLAGS="-isystem $out/usr/include" XCFLAGS="${xcflags}" LDFLAGS="${libDirFlags 64 "-L" [ "$out" ]}" \
      NSS_DISABLE_GTESTS=1 NO_MDUPDATE=1 nss_build_all)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    DESTDIR=$out bash -e ./install-nss ${ver}-32strap
    DESTDIR=$out MACH64=amd64 bash -e ./install-nss-64 ${ver}-64strap
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
