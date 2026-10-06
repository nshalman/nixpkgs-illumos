# pbzip2 1.1.6 as illumos-extra builds it for the platform (pbzip2/Makefile): 32 bits, one C++ compile by its own
# makefile.build under `env -`, given CC, CXX, CPPFLAGS (the proto area's headers) and LDFLAGS (its libraries and
# GENLDFLAGS) on make's command line; it links libbz2, from bzip2, installed before it in their proto area. The
# program and its manual installed.
{
  cleanEnv,
  lib,
  stdenv,
  strapBin,
  illumosExtraSrc,
  gcc,
  gxx,
  libDirFlags,
  illumosProto,
  bzip2,
}:

let
  # their DESTDIR: this package's output, bzip2, then the illumos proto area
  protoDirs = [
    "$out"
    "${bzip2}"
    illumosProto
  ];
in
stdenv.mkDerivation {
  pname = "smartos-extra-pbzip2";
  version = "1.1.6";

  src = illumosExtraSrc [ "pbzip2" ];

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in their build
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp -r $src/pbzip2 ie/pbzip2
    chmod -R u+w ie
    cd ie/pbzip2
    mkdir .unpack32
    tar xzf pbzip2-1.1.6.tar.gz -C .unpack32 --no-same-owner
    mv .unpack32/pbzip2-1.1.6 pbzip2-1.1.6-32
    rmdir .unpack32
    cp makefile.build pbzip2-1.1.6-32/Makefile
    runHook postUnpack
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    (cd pbzip2-1.1.6-32 && ${cleanEnv} PATH="$PATH" make -j$NIX_BUILD_CORES \
      CC="${gcc} -m32" CXX="${gxx} -m32" \
      CPPFLAGS="${lib.concatMapStringsSep " " (d: "-isystem ${d}/usr/include") protoDirs}" \
      LDFLAGS="${libDirFlags 32 "-L" protoDirs} -Wl,-zassert-deflib -Wl,-zfatal-warnings")
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/usr/bin $out/usr/share/man/man1
    cp pbzip2-1.1.6-32/pbzip2 $out/usr/bin
    cp pbzip2-1.1.6-32/pbzip2.1 $out/usr/share/man/man1
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
