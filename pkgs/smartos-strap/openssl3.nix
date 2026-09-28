# OpenSSL 3.5.8 as illumos-extra builds it for the strap (openssl3/Makefile): its one patch, which adds the
# smartos-x86-gcc and smartos64-x86_64-gcc targets (library names with a -smartos suffix, every exported symbol
# prefixed sunw_ through sunw_prefix.h and the perlasm changes); 32 and 64 bits; checked with
# openssl3/tools/checksyms.bash (no unprefixed symbol exported); installed by openssl3/install-sfw{,-64}: the
# libraries in lib with libsunw_{crypto,ssl}.so links and links in usr/lib, lib/64, the headers, openssl.cnf, the
# 64-bit openssl and CA.pl, and libcrypto.a as .build/libsunw_crypto.a.
#
# Its `configure` is Configure with @@CC@@, @@CFLAGS@@ and the other placeholders replaced, but OpenSSL 3's Configure
# has none (checked below), so the Makefile's flags reach configure only through its environment.
#
# illumos-extra bug, reproduced: the Makefile empties AUTOCONF_ENV but not AUTOCONF_ENV.64. The 32-bit build gets no
# environment (the compiler is the target's plain `gcc`, found first on PATH in the strap's usr/bin, without
# -fno-aggressive-loop-optimizations, with the target's own flags and no strap RUNPATH); the 64-bit one gets CC,
# CXX, CPPFLAGS, CFLAGS.64 (-Werror included), LDFLAGS.64 (with the strap RUNPATH) and LIBS.64, which Configure
# takes. The comparison with their proto.strap shows it: only their 64-bit binaries carry the strap RUNPATH.
#
# illumos-extra bug, reproduced: CFLAGS.64 is written as their recipe writes it, with -DPK11_LIB_LOCATION=\\"...\\"
# inside a double-quoted shell word; the shell leaves -DPK11_LIB_LOCATION=\/usr/lib/64/libpkcs11.so.1\ and the
# -Wno-stringop-truncation after it as one word, so that warning stays on (and -Werror applies to it).
#
# Differences, on purpose: Configure's perl is nixpkgs' (theirs: the build host's /usr/bin/perl), and make runs
# with -j (theirs: PARALLEL is empty).
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
  ver = "openssl-3.5.8";
  targets = {
    "32" = "smartos-x86-gcc";
    "64" = "smartos64-x86_64-gcc";
  };
in
stdenv.mkDerivation {
  pname = "smartos-strap-openssl3";
  version = "3.5.8";

  src = illumosExtra;

  nativeBuildInputs = [ perl ];

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp $src/install.subr ie/
    cp -r $src/openssl3 ie/openssl3
    chmod -R u+w ie
    cd ie/openssl3
    for bits in 32 64; do
      d=${ver}-''${bits}strap
      mkdir .unpack$bits
      tar xzf ${ver}.tar.gz -C .unpack$bits --no-same-owner
      for p in Patches/*; do
        echo "Applying $p"
        patch -d .unpack$bits/${ver} -p1 <"$p"
      done
      mv .unpack$bits/${ver} $d
      rmdir .unpack$bits
      chmod 755 $d/Configure
      cp sunw_prefix.h $d/sunw_prefix.h
      cp sunw_prefix.h $d/include/openssl/sunw_prefix.h
      if grep -q @@ $d/Configure; then
        echo "Configure has @@ placeholders now: the Makefile's flags would apply" >&2
        exit 1
      fi
      cp $d/Configure $d/configure
      chmod +x $d/configure
    done
    runHook postUnpack
  '';

  configurePhase = ''
    runHook preConfigure
    opts="--prefix=/usr --api=1.1.1 --openssldir=/etc/openssl no-rc5 no-mdc2 no-idea enable-md2 threads shared"
    (cd ${ver}-32strap && env -i PATH="$PATH" ./configure $opts ${targets."32"})
    # AUTOCONF_ENV.64
    (cd ${ver}-64strap && env -i PATH="$PATH" PKG_CONFIG_LIBDIR="" CC="${gcc} -m64" CXX="${gxx} -m64" \
      CPPFLAGS="-isystem $out/usr/include -DSOLARIS_OPENSSL -DNO_WINDOWS_BRAINDEATH" \
      CFLAGS="-O3 -Wall -Werror -DPK11_LIB_LOCATION=\\"/usr/lib/64/libpkcs11.so.1\\" -Wno-stringop-truncation -Wno-stringop-overflow" \
      LDFLAGS="${libDirFlags 64 "-L" [ "$out" ]} ${libDirFlags 64 "-R" [ "$out" ]}" LIBS="" \
      ./configure $opts ${targets."64"})
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    for bits in 32 64; do
      (cd ${ver}-''${bits}strap && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1)
    done
    bash ./tools/checksyms.bash \
      ${ver}-32strap/libcrypto-smartos.so.3 ${ver}-32strap/libssl-smartos.so.3 \
      ${ver}-64strap/libcrypto-smartos.so.3 ${ver}-64strap/libssl-smartos.so.3
    runHook postBuild
  '';

  # The install scripts are ksh93 scripts using an extended glob, !(fips*|...); bash needs extglob for that.
  installPhase = ''
    runHook preInstall
    DESTDIR=$out VERDIR=${ver}-32strap LIBVER=3 bash -e -O extglob ./install-sfw
    DESTDIR=$out VERDIR=${ver}-64strap LIBVER=3 bash -e -O extglob ./install-sfw-64
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
