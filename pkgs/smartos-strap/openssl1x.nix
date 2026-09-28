# OpenSSL 1.0.2u as illumos-extra builds it for the strap (openssl1x/Makefile), the library SmartOS keeps for its
# old node.js and kbmd: its patches (Configure overridden with smartos targets, the pkcs11 engine, every exported
# symbol prefixed sunw_, security fixes); the engine's sources copied in from openssl1x/engine_pkcs11; 32 and 64
# bits; checked with openssl1x/tools/checksyms.bash; installed by openssl1x/install-sfw{,-64}: libsunw_crypto and
# libsunw_ssl (.so.1.0.0, libsunw1x_* links) in lib with links in usr/lib, lib/64, the headers under opt/1x/openssl,
# and libcrypto.a as .build/libsunw1x_crypto.a.
#
# `configure` is the patched Configure with its @@ placeholders filled in by sed with the Makefile's values, so both
# word sizes get the Makefile's flags from there. make runs serially, as there (PARALLEL is empty).
#
# illumos-extra bug, reproduced but without effect here: as for openssl3, the Makefile empties AUTOCONF_ENV but not
# AUTOCONF_ENV.64, so the 64-bit configure also gets CC, CXX, CPPFLAGS, CFLAGS.64 (with the same \\" quoting),
# LDFLAGS.64 and LIBS.64 in its environment. OpenSSL 1.0.2's Configure reads no environment at all (patched or not),
# so they change nothing. The strap directory in the flags is this package's own output
# (see ./default.nix). Configure's perl is nixpkgs' (theirs: the build host's /usr/bin/perl).
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
  ver = "openssl-1.0.2u";
  cppflags = "-isystem $out/usr/include -DSOLARIS_OPENSSL -DNO_WINDOWS_BRAINDEATH -include openssl/sunw_prefix.h";
  # CFLAGS and CFLAGS.64, as the Makefile writes them: the \\" become \" in Configure's perl table
  cflags32 = ''-O3 -march=pentium -Wall -Werror -DPK11_LIB_LOCATION=\\"/usr/lib/libpkcs11.so.1\\" -Wno-stringop-truncation -Wno-stringop-overflow'';
  cflags64 = ''-O3 -Wall -Werror -DPK11_LIB_LOCATION=\\"/usr/lib/64/libpkcs11.so.1\\" -Wno-stringop-truncation -Wno-stringop-overflow'';
  ldflags32 = "${libDirFlags 32 "-L" [ "$out" ]} ${libDirFlags 32 "-R" [ "$out" ]}";
  ldflags64 = "${libDirFlags 64 "-L" [ "$out" ]} ${libDirFlags 64 "-R" [ "$out" ]}";
in
stdenv.mkDerivation {
  pname = "smartos-strap-openssl1x";
  version = "1.0.2u";

  src = illumosExtra;

  nativeBuildInputs = [ perl ];

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp $src/install.subr ie/
    cp -r $src/openssl1x ie/openssl1x
    chmod -R u+w ie
    cd ie/openssl1x
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
      cp engine_pkcs11/* $d/crypto/engine/
      cp sunw_prefix.h $d/sunw_prefix.h
      if [ $bits = 32 ]; then
        cc="${gcc} -m32" cflags='${cflags32}' ldflags="${ldflags32}"
      else
        cc="${gcc} -m64" cflags='${cflags64}' ldflags="${ldflags64}"
      fi
      sed -e "s#@@CC@@#$cc#g" \
          -e "s#@@CPPFLAGS@@#${cppflags}#g" \
          -e "s#@@CFLAGS@@#$cflags#g" \
          -e "s#@@MT_CPPFLAGS@@#-D_REENTRANT#g" \
          -e "s#@@LDFLAGS@@#$ldflags#g" \
          -e "s#@@LIBS@@#-lsocket -lnsl#g" \
          -e "s#@@SHARED_CFLAGS@@#-fPIC -DPIC#g" \
          -e "s#@@SHARED_LDFLAGS@@#-fPIC -shared#g" <$d/Configure >$d/configure
      chmod +x $d/configure
    done
    runHook postUnpack
  '';

  configurePhase = ''
    runHook preConfigure
    opts="--prefix=/usr --openssldir=/etc/openssl --install_prefix=$out no-rc3 no-rc5 no-mdc2 no-idea no-hw_4758_cca no-hw_aep no-hw_atalla no-hw_chil
      no-hw_gmp no-hw_ncipher no-hw_nuron no-hw_padlock no-hw_sureware no-hw_ubsec no-hw_cswift enable-md2 threads shared"
    (cd ${ver}-32strap && env -i PATH="$PATH" ./configure $opts smartos-x86-gcc)
    # AUTOCONF_ENV.64
    (cd ${ver}-64strap && env -i PATH="$PATH" PKG_CONFIG_LIBDIR="" CC="${gcc} -m64" CXX="${gxx} -m64" \
      CPPFLAGS="${cppflags}" \
      CFLAGS="-O3 -Wall -Werror -DPK11_LIB_LOCATION=\\"/usr/lib/64/libpkcs11.so.1\\" -Wno-stringop-truncation -Wno-stringop-overflow" \
      LDFLAGS="${ldflags64}" LIBS="" \
      ./configure $opts smartos64-x86_64-gcc)
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    for bits in 32 64; do
      (cd ${ver}-''${bits}strap && env -i PATH="$PATH" make V=1)
    done
    bash ./tools/checksyms.bash \
      ${ver}-32strap/libsunw_crypto.so.1.0.0 ${ver}-32strap/libsunw_ssl.so.1.0.0 \
      ${ver}-64strap/libsunw_crypto.so.1.0.0 ${ver}-64strap/libsunw_ssl.so.1.0.0
    runHook postBuild
  '';

  # The install scripts are ksh93 scripts using an extended glob, !(fips*|...); bash needs extglob for that.
  installPhase = ''
    runHook preInstall
    DESTDIR=$out VERDIR=${ver}-32strap LIBVER=1.0.0 bash -e -O extglob ./install-sfw
    DESTDIR=$out VERDIR=${ver}-64strap LIBVER=1.0.0 bash -e -O extglob ./install-sfw-64
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
