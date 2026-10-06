# zlib as illumos-extra builds it for the strap (libz/Makefile): 32 and 64 bits, zlib's own configure with
# --shared, the shared library linked by the strap gcc with illumos-extra's mapfile (the SUNW_1.x and SMARTOS_0.1
# symbol versions), then installed by libz/install-zlib{,-64}: the library in lib, links to it in usr/lib, the two
# headers in usr/include. No dependencies, so no include or library directories beyond the compiler's own.
#
# With strap = false, as illumos-extra builds it for the platform (a non-strap build, pkgs/smartos-extra): against
# illumosProto, the proto area of the illumos build, where theirs has smartos-live's proto, with GENLDFLAGS
# (-zassert-deflib -zfatal-warnings: nothing may come from the build host's /lib or /usr/lib) and no RUNPATH.
{
  cleanEnv,
  lib,
  stdenv,
  strapBin,
  illumosExtraSrc,
  gcc,
  libDirFlags,
  strap ? true,
  illumosProto ? null,
}:

let
  # the build directories' suffix (Makefile.defs VER.32, VER.64)
  suffix = lib.optionalString strap "strap";
  # Makefile.defs GENLDFLAGS
  genLdFlags = lib.optionalString (!strap) " -Wl,-zassert-deflib -Wl,-zfatal-warnings";
  # the directories that stand for their DESTDIR: this package's output, then (non-strap) the illumos proto area
  protoDirs = [ "$out" ] ++ lib.optional (!strap) illumosProto;
  includeFlags = lib.concatMapStringsSep " " (d: "-isystem ${d}/usr/include") protoDirs;
in
stdenv.mkDerivation {
  pname = if strap then "smartos-strap-libz" else "smartos-extra-libz";
  version = "1.3.1";

  src = illumosExtraSrc [ "libz" ];

  # The build runs in a copy of illumos-extra's libz directory, as there: the mapfile is ../mapfile from the build
  # directories, and the install scripts read ../install.subr.
  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp $src/install.subr ie/
    cp -r $src/libz ie/libz
    chmod -R u+w ie
    cd ie/libz
    for bits in 32 64; do
      mkdir .unpack
      tar xzf zlib-1.3.1.tar.gz -C .unpack --no-same-owner
      mv .unpack/zlib-1.3.1 zlib-1.3.1-''${bits}${suffix}
      rmdir .unpack
    done
    runHook postUnpack
  '';

  # Makefile.targ runs configure and make under `env -` with PATH alone; CFLAGS and LDFLAGS are left to zlib's
  # configure (AUTOCONF_CFLAGS and AUTOCONF_LDFLAGS are empty), CC carries CPPFLAGS, and make gets LDSHARED and
  # LDFLAGS (OVERRIDES).
  # The strap directory in those flags is this package's own output (see ./default.nix).
  configurePhase = ''
    runHook preConfigure
    for bits in 32 64; do
      (cd zlib-1.3.1-''${bits}${suffix} && ${cleanEnv} PATH="$PATH" CC="${gcc} -m$bits ${includeFlags}" ./configure --prefix=/usr --shared)
    done
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    for bits in 32 64; do
      if [ $bits = 32 ]; then libs="${libDirFlags 32 "-L" protoDirs}"; runpath="${lib.optionalString strap (libDirFlags 32 "-R" protoDirs)}"
      else libs="${libDirFlags 64 "-L" protoDirs}"; runpath="${lib.optionalString strap (libDirFlags 64 "-R" protoDirs)}"; fi
      (cd zlib-1.3.1-''${bits}${suffix} && ${cleanEnv} PATH="$PATH" make -j$NIX_BUILD_CORES V=1 \
        LDSHARED="${gcc} -m$bits -shared -Wl,-h,libz.so.1 -Wl,-zdefs -Wl,-ztext -Wl,-zcombreloc -Wl,-M,../mapfile${genLdFlags} $libs $runpath -lc" \
        LDFLAGS="$libs${genLdFlags} -L. -lc")
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    DESTDIR=$out VERS=zlib-1.3.1-32${suffix} bash -e ./install-zlib
    DESTDIR=$out VERS=zlib-1.3.1-64${suffix} MACH64=amd64 bash -e ./install-zlib-64
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
