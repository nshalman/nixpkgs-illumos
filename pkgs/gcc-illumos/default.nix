# GCC for illumos, configured against the sysroot.
#
# Source and recipe follow SmartOS/OmniOS: github.com/illumos/gcc, mpfr/gmp/mpc built in-tree, and one patch to
# gcc/config/sol2.h so that programs find this gcc's runtime libraries (./ld-flags.patch).
#
# --with-sysroot makes the sysroot, not the build host, the source of:
#   - the headers gcc searches by default and the ones fixincludes copies into include-fixed,
#   - the crt objects and link libraries (the link spec's `-Y P,%R/lib/amd64:%R/usr/lib/amd64`),
#   - everything gcc's own target libraries (libgcc_s, libstdc++, ...) are compiled and linked against.
# So both the compiler (stages 2 and 3 are built by gcc itself) and its output need nothing newer than the
# sysroot's libc.
#
# The sysroot is illumos-libc, the published sysroot plus header backports, not the pristine one. fixincludes keeps
# its own copy of several headers (sys/feature_tests.h among them) and that copy is found before the sysroot's, so
# a gcc configured against the pristine sysroot hides header fixes made later. The price: a backport that touches
# a header fixincludes copies needs a gcc rebuild. Others do not, because the cc-wrapper passes --sysroot itself.
#
# No --with-ld: gcc looks `ld` up at run time, through -B and PATH, so the nixpkgs bintools wrapper can stand
# in front of the link-editor. configure still has to know it is the Solaris one, hence LD_FOR_TARGET.
{
  lib,
  stdenv,
  fetchurl,
  flex,
  bison,
  gnum4,
  perl,
  binutils-unwrapped,
  illumos-libc,
  illumos-ld,
  # Cap on `make -j`; 0 means NIX_BUILD_CORES. The stage 3 links of cc1, cc1plus and lto1 run together and each
  # holds several GB.
  coresCap ? 0,
}:

let
  target = "x86_64-pc-solaris2.11";
  mpfr = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.bz2";
    sha256 = "183acv9b1ji6kzawzwcxnahlij2a1i11jfv256f0ir10bdir7pxr";
  };
  gmp = fetchurl {
    url = "https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.bz2";
    sha256 = "1jr03h6h0yz4w9pwyh7p6ijfk3vcsrc6139c5sp9nq7vghd22a5c";
  };
  mpc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz";
    sha256 = "1f2rqz0hdrrhx4y1i5f8pv6yv08a876k1dqcm9s2p26gyn928r5b";
  };
in
stdenv.mkDerivation rec {
  pname = "gcc-illumos";
  version = "14.2.0-il-1";

  src = fetchurl {
    url = "https://github.com/illumos/gcc/archive/refs/tags/gcc-${version}.tar.gz";
    sha256 = "18lfswx45lkizs0ygdhhwp5qswb66jqssihwb9wnx6gpw986mgzq";
  };

  # `out` is the compiler; `lib` the runtime libraries its output links to, so that programs do not keep the
  # whole compiler alive.
  outputs = [
    "out"
    "lib"
  ];

  nativeBuildInputs = [
    flex
    bison
    gnum4
    perl
  ];

  patches = [
    ./ld-flags.patch
    ./madvise-decl.patch
    ./no-ccs-exec-prefix.patch
    ./ts-errno.patch
    ./asm-debug-prefix-map.patch
  ];

  # GCC's build sets its own flags for each stage; the wrapper's would only reach stage 1.
  hardeningDisable = [ "all" ];

  postPatch = ''
    substituteInPlace gcc/config/sol2.h --replace-fail @NIX_GCC_PREFIX@ "$lib"

    # GCC's configure picks these up as in-tree dependencies.
    mkdir mpfr gmp mpc
    tar xf ${mpfr} -C mpfr --strip-components=1
    tar xf ${gmp} -C gmp --strip-components=1
    tar xf ${mpc} -C mpc --strip-components=1

    # On illumos $(libgomp_la_LIBADD) is `-ldl`, which make takes for a prerequisite file of libgomp.ver-sun
    # ("no rule to make target '-ldl'"). The recipe still reads it.
    sed -i \
      -e '/^\(@LIBGOMP_BUILD_VERSIONED_SHLIB[^@]*@\)\+libgomp\.ver-sun *:/,/^[^@\t ]/{ s/\$(libgomp_la_OBJECTS) \$(libgomp_la_LIBADD)/$(libgomp_la_OBJECTS)/; }' \
      libgomp/Makefile.in
  '';

  # The stage 1 compiler is the wrapped one. Nothing here links against store libraries, so keep the stdenv's
  # automatic RUNPATH entries out.
  NIX_LDFLAGS = "";

  configurePhase = ''
    runHook preConfigure
    # libtool in the subdirectories decides between GNU and Solaris ld by looking `ld` up on PATH, where the
    # stdenv puts binutils' first. Guessing GNU, it hands the real link-editor a GNU linker script.
    export PATH=${illumos-ld}/bin:$PATH

    # The runtime libraries are installed under $out and moved to $lib afterwards; until then the link spec's
    # $lib/lib/amd64 has to resolve.
    mkdir -p "$lib/lib" "$out/lib"
    ln -s "$out/lib/amd64" "$lib/lib/amd64"

    # The runtime libraries are compiled with -g, and the debug information would name the sysroot's include
    # directories. That is the only thing tying $lib, and so every C++ program's closure, to the sysroot.
    #
    # Builds are not sandboxed on illumos and the build directory is named differently every time. The stdenv maps
    # it for what goes through the compiler wrapper; stages 2 and 3 and the runtime libraries are compiled by the
    # new compiler directly.
    buildDirMap="-ffile-prefix-map=$NIX_BUILD_TOP=/build"
    targetFlags="-g -O2 -ffile-prefix-map=${illumos-libc}=/illumos-libc $buildDirMap"

    mkdir ../build && cd ../build
    LD_FOR_TARGET=${illumos-ld}/bin/ld \
    ../$sourceRoot/configure \
      --prefix="$out" \
      --enable-bootstrap \
      --build=${target} --host=${target} --target=${target} \
      --with-sysroot=${illumos-libc} \
      --without-gnu-ld \
      --with-gnu-as --with-as=${binutils-unwrapped}/bin/as \
      --enable-languages=c,c++ \
      --enable-shared \
      --disable-nls \
      --disable-multilib \
      CFLAGS="-g -O2 -m64" CXXFLAGS="-g -O2 -m64" \
      BOOT_CFLAGS="-g -O2 $buildDirMap" \
      CFLAGS_FOR_TARGET="$targetFlags" CXXFLAGS_FOR_TARGET="$targetFlags" \
      LDFLAGS="-Wl,-R$lib/lib/amd64"
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cores=''${NIX_BUILD_CORES:-1}
    if [ ${toString coresCap} -gt 0 ] && [ "$cores" -gt ${toString coresCap} ]; then cores=${toString coresCap}; fi
    make -j"$cores"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install

    rm "$lib/lib/amd64"
    mv "$out/lib/amd64" "$lib/lib/amd64"

    # Keep $lib free of references to $out: libtool archives and gdb pretty-printers name $out's libdir, the
    # sanitizer libraries get a second RUNPATH into it, and libcc1 (the plugin interface) is linked by the
    # stage 1 host compiler.
    find "$lib/lib/amd64" -name '*.la' -delete
    mkdir -p "$out/lib/amd64"
    for f in "$lib"/lib/amd64/*-gdb.py "$lib"/lib/amd64/libasan.* "$lib"/lib/amd64/libubsan.* \
             "$lib"/lib/amd64/libtsan.* "$lib"/lib/amd64/liblsan.* "$lib"/lib/amd64/libsanitizer.spec \
             "$lib"/lib/amd64/libcc1.*; do
      if [ -e "$f" ]; then mv "$f" "$out/lib/amd64/"; fi
    done
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontStrip = true;
  dontPatchELF = true;
  dontFixup = true;

  passthru = {
    inherit target;
    isGNU = true;
    sysroot = illumos-libc;
  };

  meta = {
    description = "GCC from the illumos fork, configured against the illumos sysroot";
    homepage = "https://github.com/illumos/gcc";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.illumos;
  };
}
