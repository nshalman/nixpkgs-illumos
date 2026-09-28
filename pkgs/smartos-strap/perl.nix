# perl 5.12.3 as illumos-extra builds it for the strap (perl/Makefile), the perl the rest of the strap build runs
# (OpenSSL 1.0.2's build, among others): 32 bits with 64-bit integers; its four patches in the Makefile's order;
# Configure -des with illumos-extra's config.over, whose paths are the strap directory itself (@@THISPROTO@@: a strap
# perl is configured for, and installed straight into, <strap>/usr/perl5/5.12, without DESTDIR); DTrace probes, with
# perldtrace.h made by the platform's dtrace; then Config_heavy.pl replaced by illumos-extra's strap version, which
# points the modules built with it at the next proto (@@NEXTPROTO@@).
#
# Here the strap directory is this package's output, and so is the next proto: in a strap build NEXTPROTO is
# $(DESTDIR:.strap=), which leaves smartos-live's strap cache directory, the reference's, unchanged.
#
# The steps that do not run under `env -` (Configure, make) see what the top-level make exports; of that, STRAP,
# DESTDIR and PKG_CONFIG_LIBDIR are given here. The platform's /usr/sbin/dtrace is an input from the build host, as
# for illumos-extra.
{
  stdenv,
  strapBin,
  illumosExtra,
  gcc,
}:

let
  ver = "perl-5.12.3";
  basicCppflags = "-fno-strict-aliasing -pipe -fstack-protector";
  lfCppflags = "-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64";
  cppflags = "-isystem $out/usr/include ${basicCppflags} ${lfCppflags} -DPERL_USE_SAFE_PUTENV";
  nativeCppflags = "${basicCppflags} ${lfCppflags} -DPERL_USE_SAFE_PUTENV";
  ldflags = "-L$out/usr/lib -L$out/lib -lssp -fstack-protector";
  nativeLdflags = "-fstack-protector";
  cc = "${gcc} -m32";
  # XFORM.sh
  xform = ''
    sed -e "s;@@CC@@;${cc};g" \
        -e "s;@@CPPFLAGS@@;${cppflags};g" \
        -e "s;@@CFLAGS@@;;g" \
        -e "s;@@NATIVE_CPPFLAGS@@;${nativeCppflags};g" \
        -e "s;@@NATIVE_CFLAGS@@;;g" \
        -e "s;@@BASIC_CPPFLAGS@@;${basicCppflags};g" \
        -e "s;@@LF_CPPFLAGS@@;${lfCppflags};g" \
        -e "s;@@LDFLAGS@@;${ldflags};g" \
        -e "s;@@NATIVE_LDFLAGS@@;${nativeLdflags};g" \
        -e "s;@@LIBS@@;;g" \
        -e "s;@@GMAKE@@;gmake;g" \
        -e "s;@@THISPROTO@@;$out;g" \
        -e "s;@@NEXTPROTO@@;$out;g" \
        -e "s;@@NATIVE_SHARED_LDFLAGS@@;-G ${nativeLdflags};g" \
        -e "s;@@SHARED_LDFLAGS@@;-G ${ldflags};g"'';
  strapEnv = ''env -i PATH="$PATH" STRAP=strap DESTDIR=$out PKG_CONFIG_LIBDIR='';
in
stdenv.mkDerivation {
  pname = "smartos-strap-perl";
  version = "5.12.3";

  src = illumosExtra;

  unpackPhase = ''
    runHook preUnpack
    # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
    export PATH=${strapBin}/bin:$PATH
    mkdir -p ie
    cp $src/install.subr ie/
    cp -r $src/perl ie/perl
    chmod -R u+w ie
    cd ie/perl
    mkdir .unpack32
    tar xzf ${ver}.tar.gz -C .unpack32 --no-same-owner
    for p in CVE-2022-37434.patch dtrace.patch native.patch fix-gcc-errno.patch; do
      echo "Applying $p"
      patch -d .unpack32/${ver} -p1 <"$p"
    done
    mv .unpack32/${ver} ${ver}-32strap
    rmdir .unpack32
    chmod 755 ${ver}-32strap/Configure
    touch ${ver}-32strap/Configure
    runHook postUnpack
  '';

  configurePhase = ''
    runHook preConfigure
    ${xform} <config.over.in >${ver}-32strap/config.over
    (cd ${ver}-32strap && ${strapEnv} ./Configure -des -Dcc="${cc}" -Duse64bitint)
    (cd ${ver}-32strap && /usr/sbin/dtrace -h -s perldtrace.d -o perldtrace.h)
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    (cd ${ver}-32strap && ${strapEnv} LC_ALL=C make)
    ${xform} <Config_heavy.plstrap.in >Config_heavy.plstrap
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    (cd ${ver}-32strap && rm -f $out/usr/perl5/5.12/lib/i86pc-solaris-64int/.packlist &&
      ${strapEnv} make DESTDIR= install)
    rm -f $out/usr/perl5/5.12/lib/i86pc-solaris-64int/Config_heavy.pl
    cp Config_heavy.plstrap $out/usr/perl5/5.12/lib/i86pc-solaris-64int/Config_heavy.pl
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
