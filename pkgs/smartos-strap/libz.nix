# zlib as illumos-extra builds it for the strap (libz/Makefile): 32 and 64 bits, zlib's own configure with
# --shared, the shared library linked by the strap gcc with illumos-extra's mapfile (the SUNW_1.x and SMARTOS_0.1
# symbol versions), then installed by libz/install-zlib{,-64}: the library in lib, links to it in usr/lib, the two
# headers in usr/include. No dependencies, so no include or library directories beyond the compiler's own.
{
  stdenv,
  strapBin,
  illumosExtra,
  gcc,
  libDirFlags,
}:

stdenv.mkDerivation {
  pname = "smartos-strap-libz";
  version = "1.3.1";

  src = illumosExtra;

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
      mv .unpack/zlib-1.3.1 zlib-1.3.1-''${bits}strap
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
      (cd zlib-1.3.1-''${bits}strap && env -i PATH="$PATH" CC="${gcc} -m$bits -isystem $out/usr/include" ./configure --prefix=/usr --shared)
    done
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    for bits in 32 64; do
      if [ $bits = 32 ]; then libs="${libDirFlags 32 "-L" [ "$out" ]}"; runpath="${libDirFlags 32 "-R" [ "$out" ]}"
      else libs="${libDirFlags 64 "-L" [ "$out" ]}"; runpath="${libDirFlags 64 "-R" [ "$out" ]}"; fi
      (cd zlib-1.3.1-''${bits}strap && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1 \
        LDSHARED="${gcc} -m$bits -shared -Wl,-h,libz.so.1 -Wl,-zdefs -Wl,-ztext -Wl,-zcombreloc -Wl,-M,../mapfile $libs $runpath -lc" \
        LDFLAGS="$libs -L. -lc")
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    DESTDIR=$out VERS=zlib-1.3.1-32strap bash -e ./install-zlib
    DESTDIR=$out VERS=zlib-1.3.1-64strap MACH64=amd64 bash -e ./install-zlib-64
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
