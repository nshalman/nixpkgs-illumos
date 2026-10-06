# NSS 3.25 with NSPR 4.12 as illumos-extra builds them for the strap (nss-nspr/Makefile): its patches; NSS's own
# build (nss_build_all, which configures and builds NSPR too), serially, once per word size with the strap gcc as
# CC and AS; installed by nss-nspr/install-nss{,-64}: the libraries and their .chk signatures in usr/lib/mps and
# usr/lib/mps/amd64 (with a 64 link), certutil for both word sizes, the headers in usr/include/mps.
#
# NSS's make is not run under `env -`, so it sees what the top-level make exports; of that, STRAP, DESTDIR and
# PKG_CONFIG_LIBDIR are given here (STRAP=strap keeps the patched shlibsign from adding the strap directory to
# LD_LIBRARY_PATH). The strap directory in the flags is this package's own output (see ./default.nix).
#
# illumos-extra bug, reproduced: NSPR_CONFIGURE_ENV names $(CXX.32) (and $(CXX.64)), variables the Makefile never
# sets (presumably GXX.32 and GXX.64 were meant), so NSPR is configured with an empty CXX.
#
# With strap = false, as illumos-extra builds it for the platform (pkgs/smartos-extra): STRAP is empty and DESTDIR is
# the proto area (illumosProto), so the patched shlibsign signs with the proto area's libraries on LD_LIBRARY_PATH,
# as theirs does with their proto; CPPFLAGS and LDFLAGS name it after this package's output, LDFLAGS with GENLDFLAGS
# (-zassert-deflib -zfatal-warnings); the build directories lose their suffix.
{
  cleanEnv,
  lib,
  stdenv,
  strapBin,
  illumosExtraSrc,
  gcc,
  gxx,
  libDirFlags,
  perl,
  strap ? true,
  illumosProto ? null,
}:

let
  ver = "nss-3.25";
  # the build directories' suffix (Makefile.defs VER.32, VER.64), also STRAP's value
  suffix = lib.optionalString strap "strap";
  # their DESTDIR: this package's output, then (non-strap) the illumos proto area
  protoDirs = [ "$out" ] ++ lib.optional (!strap) illumosProto;
  # the DESTDIR NSS's make sees (shlibsign's LD_LIBRARY_PATH, non-strap)
  makeDestdir = if strap then "$out" else illumosProto;
  includeFlags = lib.concatMapStringsSep " " (d: "-isystem ${d}/usr/include") protoDirs;
  # Makefile.defs LDFLAGS: the library directories, then (non-strap) GENLDFLAGS
  ldflags =
    bits: libDirFlags bits "-L" protoDirs + lib.optionalString (!strap) " -Wl,-zassert-deflib -Wl,-zfatal-warnings";
  xcflags = "-Wno-unused -Wno-int-in-bool-context -Wno-stringop-truncation";
in
stdenv.mkDerivation {
  pname = if strap then "smartos-strap-nss-nspr" else "smartos-extra-nss-nspr";
  version = "3.25";

  src = illumosExtraSrc [ "nss-nspr" ];

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
      mv .unpack$bits/${ver} ${ver}-''${bits}${suffix}
      rmdir .unpack$bits
    done
    runHook postUnpack
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    # NSPR's build time (_BUILD_STRING, _BUILD_TIME in microseconds), which pr/src/Makefile takes from date and
    # config/now (time()), as SOURCE_DATE_EPOCH gives it
    nsprDate=$(TZ=UTC date -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d %T')
    nsprNow=''${SOURCE_DATE_EPOCH}000000
    (cd ${ver}-32${suffix}/nss && ${cleanEnv} PATH="$PATH" STRAP=${suffix} DESTDIR=${makeDestdir} PKG_CONFIG_LIBDIR= \
      make BUILD_OPT=1 BUILD_SUN_PKG=1 NS_USE_GCC=1 NO_MDUPDATE=1 \
      NSPR_CONFIGURE_ENV="CC=\"${gcc} -m32\" CXX=\"\"" \
      CC="${gcc} -m32" CXX="${gxx} -m32" AS="${gcc} -m32" \
      CPPFLAGS="${includeFlags}" XCFLAGS="${xcflags}" LDFLAGS="${ldflags 32}" \
      SH_DATE="$nsprDate" SH_NOW="$nsprNow" NSS_DISABLE_GTESTS=1 nss_build_all)
    (cd ${ver}-64${suffix}/nss && ${cleanEnv} PATH="$PATH" STRAP=${suffix} DESTDIR=${makeDestdir} PKG_CONFIG_LIBDIR= \
      make USE_64=1 BUILD_OPT=1 BUILD_SUN_PKG=1 NS_USE_GCC=1 \
      NSPR_CONFIGURE_ENV="CC=\"${gcc} -m64\" CXX=\"\"" \
      CC="${gcc} -m64" CXX="${gxx} -m64" AS="${gcc} -m64" \
      CPPFLAGS="${includeFlags}" XCFLAGS="${xcflags}" LDFLAGS="${ldflags 64}" \
      SH_DATE="$nsprDate" SH_NOW="$nsprNow" NSS_DISABLE_GTESTS=1 NO_MDUPDATE=1 nss_build_all)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    DESTDIR=$out bash -e ./install-nss ${ver}-32${suffix}
    DESTDIR=$out MACH64=amd64 bash -e ./install-nss-64 ${ver}-64${suffix}
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
