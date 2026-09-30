# node.js 0.10.26 as illumos-extra builds it for the strap (node.js/Makefile), the node SmartOS's build tools run:
# 32 bits, its patches (in name order), with DTrace probes, without a snapshot, against the strap's OpenSSL 1.0.2
# (libsunw_crypto/libsunw_ssl) and zlib; host tools built by a separate host toolset through node.js/wrapper.c
# (which turns -lsunw_crypto/-lsunw_ssl into -lcrypto/-lssl for the host); installed by its own `make install` into
# <strap>/usr/node/0.10, plus node_modules/platform_node_version.js from node.js/genversionjs.c and the manuals moved
# up from share/man.
#
# Makefile.targ's flow: configure and make under `env -`, configure given AUTOCONF_ENV and make the same variables
# on its command line (OVERRIDES). The strap directories are this package's output and the libz and openssl1x
# packages (see ./default.nix); --shared-openssl-* name openssl1x's, --shared-zlib-* libz's. The Makefile's
# -R'$$\$$'ORIGIN/... reaches the environment as -R'$$'ORIGIN/..., which node's own make and shell turn into a literal
# $ORIGIN in the binary's RUNPATH; that string is given here as it is.
#
# Differences, on purpose: the host compiler ($(GCC.host.32), pkgsrc's gcc -m32 there) is the strap gcc -m32; python
# is nixpkgs' python 2.7, permitted for this build though marked insecure (illumos.nix). node records the python
# gyp ran with (config.gypi, and process.config in the binary), as theirs records pkgsrc's; the reference to the store
# path is removed, so python 2.7 stays a build-time input. The platform's /usr/sbin/dtrace is an input from the
# build host, as for illumos-extra.
{
  stdenv,
  strapBin,
  platformDtrace,
  illumosExtraSrc,
  gcc,
  gxx,
  gcc10-illumos,
  libz,
  openssl1x,
  python27,
  removeReferencesTo,
}:

let
  ver = "node-v0.10.26";
  strapDirs = [
    "$out"
    "${libz}"
    "${openssl1x}"
  ];
  concatDirs = f: builtins.concatStringsSep " " (map f strapDirs);
  cppflags = "${concatDirs (d: "-isystem ${d}/usr/include")} -I${openssl1x}/opt/1x";
  cxxflags = "-fpermissive -fno-delete-null-pointer-checks -Wno-cast-function-type -fno-zero-initialized-in-bss";
  hostCC = "${gcc10-illumos}/bin/gcc -m32";
  hostCXX = "${gcc10-illumos}/bin/g++ -m32";
in
stdenv.mkDerivation {
  pname = "smartos-strap-node";
  version = "0.10.26";

  src = illumosExtraSrc [ "node.js" ];

  nativeBuildInputs = [
    python27
    removeReferencesTo
  ];

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix), and the platform's dtrace
    export PATH=${strapBin}/bin:${platformDtrace}/bin:$PATH
    mkdir -p ie
    cp $src/install.subr ie/
    cp -r $src/node.js ie/node.js
    chmod -R u+w ie
    cd ie/node.js
    mkdir .unpack32
    tar xzf ${ver}.tar.gz -C .unpack32 --no-same-owner
    for p in Patches/*; do
      echo "Applying $p"
      patch -d .unpack32/${ver} -p1 <"$p"
    done
    mv .unpack32/${ver} ${ver}-32strap
    rmdir .unpack32
    chmod 755 ${ver}-32strap/configure
    touch ${ver}-32strap/configure
    runHook postUnpack
  '';

  # AUTOCONF_ENV, as the words handed to `env` (configure) and to make (OVERRIDES)
  preConfigure = ''
    ldflags="${concatDirs (d: "-L${d}/usr/lib -L${d}/lib")} -lumem ${concatDirs (d: "-R${d}/usr/lib -R${d}/lib")} -R'\$\$'ORIGIN/../../../../usr/gcc/10/lib"
    vars=(
      "PKG_CONFIG_LIBDIR="
      "CC=${gcc} -m32"
      "CXX=${gxx} -m32"
      "CPPFLAGS=${cppflags}"
      "CFLAGS=${cppflags} "
      "LDFLAGS=$ldflags"
      "CXXFLAGS=${cppflags}  ${cxxflags}"
      "CXXFLAGS.host=${cppflags}  ${cxxflags}"
      "LDFLAGS.host=-Wl,-i"
      "CXX.host=$PWD/wrapper ${hostCXX}"
      "CC.host=$PWD/wrapper ${hostCC}"
      "CXX_host=$PWD/wrapper ${hostCXX}"
      "CC_host=$PWD/wrapper ${hostCC}"
      "LINK.host=$PWD/wrapper ${hostCXX}"
    )
  '';

  configurePhase = ''
    runHook preConfigure
    ${hostCC} -Wall -Wextra -Werror -O2 -o wrapper wrapper.c
    (cd ${ver}-32strap && env -i PATH="$PATH" "''${vars[@]}" ./configure --prefix=/usr --with-dtrace \
      --without-snapshot --shared-openssl --shared-openssl-includes=${openssl1x}/opt/1x \
      --shared-openssl-libpath=${openssl1x}/lib --shared-openssl-libname=sunw1x_crypto,sunw1x_ssl --shared-zlib \
      --shared-zlib-libpath=${libz}/lib --shared-zlib-includes=${libz}/usr/include --prefix=/usr/node/0.10)
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    (cd ${ver}-32strap && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1 "''${vars[@]}")
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    (cd ${ver}-32strap && env -i PATH="$PATH" make V=1 "''${vars[@]}" DESTDIR=$out install)
    nodeRoot=$out/usr/node/0.10
    ${hostCC} -o genversionjs -include $nodeRoot/include/node/node_version.h genversionjs.c
    mkdir -p $nodeRoot/node_modules
    ./genversionjs >$nodeRoot/node_modules/platform_node_version.js
    rm -rf $nodeRoot/man
    mv $nodeRoot/share/man $nodeRoot/
    remove-references-to -t ${python27} $nodeRoot/include/node/config.gypi $nodeRoot/bin/node
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
