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
#
# With strap = false, as illumos-extra builds it for the platform (pkgs/smartos-extra): configured for the platform's
# own /usr/perl5/5.12 (@@THISPROTO@@ is empty), installed with DESTDIR, given the non-strap Config_heavy.pl; CPPFLAGS
# and LDFLAGS name the proto area (illumosProto, after this package's output), LDFLAGS with GENLDFLAGS; Configure and
# make see an empty STRAP and their DESTDIR, the proto area; the build directory loses its suffix.
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
  ver = "perl-5.12.3";
  # the build directory's suffix (Makefile.defs VER.32), also STRAP's value
  suffix = lib.optionalString strap "strap";
  d = "${ver}-32${suffix}";
  # their DESTDIR: this package's output, then (non-strap) the illumos proto area
  protoDirs = [ "$out" ] ++ lib.optional (!strap) illumosProto;
  # @@THISPROTO@@ and @@NEXTPROTO@@: the strap directory, or nothing
  thisProto = lib.optionalString strap "$out";
  # the DESTDIR Configure and make see
  envDestdir = if strap then "$out" else illumosProto;
  # CONFIG_PL, and the DESTDIR of the install (INSTALL_DESTDIR: none for the strap)
  configPl = "Config_heavy.pl${suffix}";
  installDestdir = lib.optionalString (!strap) "$out";
  basicCppflags = "-fno-strict-aliasing -pipe -fstack-protector";
  lfCppflags = "-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64";
  includeFlags = lib.concatMapStringsSep " " (p: "-isystem ${p}/usr/include") protoDirs;
  cppflags = "${includeFlags} ${basicCppflags} ${lfCppflags} -DPERL_USE_SAFE_PUTENV";
  nativeCppflags = "${basicCppflags} ${lfCppflags} -DPERL_USE_SAFE_PUTENV";
  ldflags =
    libDirFlags 32 "-L" protoDirs
    + lib.optionalString (!strap) " -Wl,-zassert-deflib -Wl,-zfatal-warnings"
    + " -lssp -fstack-protector";
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
        -e "s;@@THISPROTO@@;${thisProto};g" \
        -e "s;@@NEXTPROTO@@;${thisProto};g" \
        -e "s;@@NATIVE_SHARED_LDFLAGS@@;-G ${nativeLdflags};g" \
        -e "s;@@SHARED_LDFLAGS@@;-G ${ldflags};g"'';
  strapEnv = ''${cleanEnv} PATH="$PATH" STRAP=${suffix} DESTDIR=${envDestdir} PKG_CONFIG_LIBDIR='';
in
stdenv.mkDerivation {
  pname = if strap then "smartos-strap-perl" else "smartos-extra-perl";
  version = "5.12.3";

  src = illumosExtraSrc [ "perl" ];

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
    mv .unpack32/${ver} ${d}
    rmdir .unpack32
    chmod 755 ${d}/Configure
    touch ${d}/Configure
    runHook postUnpack
  '';

  configurePhase = ''
    runHook preConfigure
    ${xform} <config.over.in >${d}/config.over
    (cd ${d} && ${strapEnv} ./Configure -des -Dcc="${cc}" -Duse64bitint)
    (cd ${d} && /usr/sbin/dtrace -h -s perldtrace.d -o perldtrace.h)
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    (cd ${d} && ${strapEnv} LC_ALL=C make)
    ${xform} <${configPl}.in >${configPl}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    (cd ${d} && rm -f $out/usr/perl5/5.12/lib/i86pc-solaris-64int/.packlist &&
      ${strapEnv} make DESTDIR=${installDestdir} install)
    rm -f $out/usr/perl5/5.12/lib/i86pc-solaris-64int/Config_heavy.pl
    cp ${configPl} $out/usr/perl5/5.12/lib/i86pc-solaris-64int/Config_heavy.pl
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
