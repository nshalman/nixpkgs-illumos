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
# A gcc that is called directly, not through the wrappers, has neither -B nor an `ld` on the stdenv's PATH; it gets
# --with-ld through `linker` (gcc10-illumos).
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
  # Which gcc: version, source, the in-tree mpfr/gmp/mpc tarballs and the patches (./14.nix, ./10.nix).
  release ? import ./14.nix { inherit fetchurl; },
  # The assembler gcc is configured with.
  assembler ? "${binutils-unwrapped}/bin/as",
  # The link-editor gcc is configured with (--with-ld), or null to look it up at run time (see above).
  linker ? null,
}:

let
  target = "x86_64-pc-solaris2.11";
  withLd = lib.optionalString (linker != null) " --with-ld=${linker}";
  inherit (release) mpfr gmp mpc;
in
stdenv.mkDerivation {
  pname = "gcc-illumos";
  inherit (release) version src;

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

  inherit (release) patches;

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

    # GCC's bundled libtool takes the longest command line from `getconf ARG_MAX`, which is not on the build PATH,
    # and its fallback probe fails here, leaving 512 bytes. With that it links libraries from reloadable chunks
    # (`ld -r`), and where a chunk ends depends on the length of the build directory's path, which the reload
    # command names; the libraries' layout would change with the build directory. 786240 is what libtool computes
    # from illumos' ARG_MAX of 1048320. The configure runs of the target libraries, made by make, inherit it.
    export lt_cv_sys_max_cmd_len=786240

    # The runtime libraries are installed under $out and moved to $lib afterwards; until then the link spec's
    # $lib/lib/amd64 has to resolve.
    mkdir -p "$lib/lib" "$out/lib"
    ln -s "$out/lib/amd64" "$lib/lib/amd64"

    # The runtime libraries are compiled with -g, and the debug information would name the sysroot's include
    # directories. That is the only thing tying $lib, and so every C++ program's closure, to the sysroot.
    targetFlags="-g -O2 -ffile-prefix-map=${illumos-libc}=/illumos-libc"

    mkdir ../build && cd ../build
    LD_FOR_TARGET=${illumos-ld}/bin/ld \
    ../$sourceRoot/configure \
      --prefix="$out" \
      --enable-bootstrap \
      --build=${target} --host=${target} --target=${target} \
      --with-sysroot=${illumos-libc} \
      --without-gnu-ld${withLd} \
      --with-gnu-as --with-as=${assembler} \
      --enable-languages=c,c++ \
      --enable-shared \
      --disable-nls \
      --disable-multilib \
      CFLAGS="-g -O2 -m64" CXXFLAGS="-g -O2 -m64" \
      CFLAGS_FOR_TARGET="$targetFlags" CXXFLAGS_FOR_TARGET="$targetFlags" \
      LDFLAGS="-Wl,-R$lib/lib/amd64"
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cores=''${NIX_BUILD_CORES:-1}
    if [ ${toString coresCap} -gt 0 ] && [ "$cores" -gt ${toString coresCap} ]; then cores=${toString coresCap}; fi

    # Builds are not sandboxed on illumos and the build directory is named differently every time. The stdenv maps
    # it for what goes through the compiler wrapper; stages 2 and 3 and the runtime libraries are compiled by the
    # new compiler directly. The map is given to make and not to configure, which would record it, build
    # directory and all, in the compiler (`gcc -v`, "Configured with").
    buildDirMap="-ffile-prefix-map=$NIX_BUILD_TOP=/build"
    makeFlagsArray=(
      BOOT_CFLAGS="-g -O2 $buildDirMap"
      CFLAGS_FOR_TARGET="$targetFlags $buildDirMap"
      CXXFLAGS_FOR_TARGET="$targetFlags $buildDirMap"
    )
    make -j"$cores" "''${makeFlagsArray[@]}"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # The same variables as for the build, or make considers the flags changed.
    make install "''${makeFlagsArray[@]}"

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
