# mdb_v8 1.4.4 as illumos-extra builds it for the platform (mdb_v8/Makefile): its own GNUmakefile's release target,
# which builds the dmod for both word sizes, run under `env -` with AUTOCONF_ENV (CC and CXX the strap compilers
# without -m, CPPFLAGS the proto area's headers, CFLAGS -gdwarf-2, LDFLAGS with GENLDFLAGS), CFLAGS_ARCH and PATH, and
# make given V=1; installed by ctfconvert, which writes each dmod with CTF from its DWARF into usr/lib/mdb/proc (their
# proto area has the directories; they are made here).
#
# Its makefile checks out the illumos-libavl submodule with `git submodule update` (deps/%/.git in Makefile.targ);
# the tarball has an empty deps/illumos-libavl and no submodule objects, so their build clones it from GitHub. Here
# the commit mdb_v8 1.4.4 records (60a0c8a3) is a pinned input, put in place, and make is told to take
# deps/illumos-libavl/.git as there (-o), so that the rule is not run; git then sees the submodule as not
# initialised, which `git describe --dirty` does not count as a change. git is on PATH, as on their build host, for the release target's version tag (`git describe` of the
# tarball's own .git: "release, from cbec173" in theirs).
{
  lib,
  stdenv,
  fetchFromGitHub,
  gitMinimal,
  strapBin,
  illumosExtraSrc,
  gcc,
  gxx,
  libDirFlags,
  illumosProto,
  ctfconvert,
}:

let
  ver = "mdb_v8-1.4.4";
  # deps/illumos-libavl, the submodule commit in mdb_v8 1.4.4's tree
  libavl = fetchFromGitHub {
    owner = "joyent";
    repo = "illumos-libavl";
    rev = "60a0c8a31038ec1d6096c9bbcb089326659fc9c8";
    sha256 = "0kyh2asb2ivlp97i516liwjfdr28f7lh89zmbz17w4qqpnhm4nxz";
  };
  # their DESTDIR: this package's output, then the illumos proto area
  protoDirs = [
    "$out"
    illumosProto
  ];
in
stdenv.mkDerivation {
  pname = "smartos-extra-mdb_v8";
  version = "1.4.4";

  src = illumosExtraSrc [ "mdb_v8" ];

  nativeBuildInputs = [ gitMinimal ];

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in their build
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp -r $src/mdb_v8 ie/mdb_v8
    chmod -R u+w ie
    cd ie/mdb_v8
    mkdir .unpack
    tar xzf ${ver}.tar.gz -C .unpack --no-same-owner
    mv .unpack/${ver} ${ver}
    rmdir .unpack
    rmdir ${ver}/deps/illumos-libavl
    cp -r ${libavl} ${ver}/deps/illumos-libavl
    chmod -R u+w ${ver}/deps/illumos-libavl
    runHook postUnpack
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    (cd ${ver} && env -i PKG_CONFIG_LIBDIR= CC="${gcc}" CXX="${gxx}" \
      CPPFLAGS="${lib.concatMapStringsSep " " (d: "-isystem ${d}/usr/include") protoDirs}" CFLAGS="-gdwarf-2" \
      LDFLAGS="${libDirFlags 32 "-L" protoDirs} -Wl,-zassert-deflib -Wl,-zfatal-warnings" LIBS="" \
      CFLAGS_ARCH=-gdwarf-2 PATH="$PATH" make -o deps/illumos-libavl/.git V=1 release)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/usr/lib/mdb/proc/amd64
    ${ctfconvert} -l ${ver} -o $out/usr/lib/mdb/proc/v8.so ${ver}/build/ia32/mdb_v8.so
    ${ctfconvert} -l ${ver} -o $out/usr/lib/mdb/proc/amd64/v8.so ${ver}/build/amd64/mdb_v8.so
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
