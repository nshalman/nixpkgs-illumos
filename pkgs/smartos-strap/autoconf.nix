# An illumos-extra autoconf package in a strap build, as Makefile.defs and Makefile.targ build it:
#   - the tarball unpacked once per word size into <ver>-32strap / <ver>-64strap, the directory's patches applied
#     with -p1 in name order (PATCHES = Patches/*), configure made executable (FROB_SENTINEL);
#   - configure run in that directory under `env -` (PATH alone) with AUTOCONF_ENV: PKG_CONFIG_LIBDIR empty,
#     CC/CXX the strap compilers with -m32 or -m64, CPPFLAGS (-isystem <strap>/usr/include plus the package's),
#     CFLAGS (the package's; the 64-bit build takes CFLAGS.64, usually empty), LDFLAGS (-L<strap>/usr/lib
#     -L<strap>/lib, /64 for 64 bits, plus the package's), LIBS; and --prefix=/usr;
#   - make -j under `env -` with V=1 (OVERRIDES), then the package's install step.
# <strap> is the proto.strap directory there. Here it is this package's own output followed by those of the strap
# packages it depends on (`deps`), so that RUNPATHs and libtool archives name the same places.
#
# With strap = false, a non-strap build (pkgs/smartos-extra): the directories are <ver>-32 / <ver>-64, <strap> in
# CPPFLAGS and LDFLAGS is their DESTDIR, smartos-live's proto area (here: this package's output, the packages it
# depends on, then illumosProto, the illumos build's proto area), and LDFLAGS carries GENLDFLAGS (-zassert-deflib
# -zfatal-warnings) after the library directories. A package's pname "smartos-strap-X" becomes "smartos-extra-X"
# (other names are kept), and its `install` may be a function of the directories' suffix ("strap" or "").
{
  lib,
  stdenv,
  strapBin,
  illumosExtra,
  gcc,
  gxx,
  strap ? true,
  illumosProto ? null,
}:

{
  pname,
  version,
  # the illumos-extra directory, e.g. "libexpat"
  dir,
  # the unpacked tarball's top directory (VER)
  ver,
  tarball ? "${ver}.tar.gz",
  # glob of the patches, relative to `dir`, applied in name order; null for none
  patches ? null,
  bits ? [ 32 ],
  deps ? [ ],
  cppflags ? "",
  cflags ? "",
  cflags64 ? "",
  ldflags ? "",
  ldflags64 ? "",
  libs ? "",
  libs64 ? "",
  configureFlags ? [ ],
  # FROB_SENTINEL, run in the unpacked source ($d is its directory); null: make configure executable
  frob ? null,
  # AUTOCONF_CC is CC="$(GCC.32) $(CPPFLAGS)": CPPFLAGS in CC as well
  cppInCC ? false,
  # AUTOCONF_CFLAGS / AUTOCONF_LDFLAGS set empty: CFLAGS / LDFLAGS not given to configure at all
  passCflags ? true,
  passLdflags ? true,
  # the install step, run in the copy of the illumos-extra directory with $out as DESTDIR; a string, or a function
  # of the build directories' suffix
  install,
  nativeBuildInputs ? [ ],
  # other derivation attributes (preConfigure hooks, meta, ...)
  extra ? { },
}:

let
  suffix = lib.optionalString strap "strap";
  strapDirs = [ "$out" ] ++ map toString deps ++ lib.optional (!strap) illumosProto;
  # Makefile.defs GENLDFLAGS
  genLdFlags = lib.optionalString (!strap) " -Wl,-zassert-deflib -Wl,-zfatal-warnings";
  cppFlags = lib.concatMapStringsSep " " (d: "-isystem ${d}/usr/include") strapDirs + " ${cppflags}";
  libDirs =
    b: lib.concatMapStringsSep " " (d: if b == 64 then "-L${d}/usr/lib/64 -L${d}/lib/64" else "-L${d}/usr/lib -L${d}/lib") strapDirs;
  flagsFor = b: {
    cc = "${gcc} -m${toString b}";
    cxx = "${gxx} -m${toString b}";
    cflags = if b == 64 then cflags64 else cflags;
    ldflags = "${libDirs b}${genLdFlags} ${if b == 64 then ldflags64 else ldflags}";
    libs = if b == 64 then libs64 else libs;
  };
  forBits = f: lib.concatMapStrings (b: f b (flagsFor b)) bits;
in
stdenv.mkDerivation (
  {
    pname =
      if strap || !lib.hasPrefix "smartos-strap-" pname then
        pname
      else
        "smartos-extra-" + lib.removePrefix "smartos-strap-" pname;
    inherit version nativeBuildInputs;
    src = illumosExtra;

    unpackPhase = ''
      runHook preUnpack
      # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
      export PATH=${strapBin}/bin:$PATH
      mkdir -p ie
      cp $src/install.subr ie/
      cp -r $src/${dir} ie/${dir}
      chmod -R u+w ie
      cd ie/${dir}
    ''
    + forBits (
      b: _: ''
        mkdir .unpack${toString b}
        tar xf ${tarball} -C .unpack${toString b} --no-same-owner
        ${lib.optionalString (patches != null) ''
          for p in ${patches}; do
            echo "Applying $p"
            patch -d .unpack${toString b}/${ver} -p1 <"$p"
          done
        ''}
        mv .unpack${toString b}/${ver} ${ver}-${toString b}${suffix}
        rmdir .unpack${toString b}
        d=${ver}-${toString b}${suffix}
        ${if frob == null then "chmod 755 $d/configure" else frob}
        touch ${ver}-${toString b}${suffix}/configure
      ''
    )
    + ''
      runHook postUnpack
    '';

    configurePhase = ''
      runHook preConfigure
    ''
    + forBits (
      b: f: ''
        (cd ${ver}-${toString b}${suffix} && env -i PATH="$PATH" PKG_CONFIG_LIBDIR= \
          CC="${f.cc}${lib.optionalString cppInCC " ${cppFlags}"}" CPPFLAGS="${cppFlags}" CXX="${f.cxx}" \
          ${lib.optionalString passCflags "CFLAGS=\"${f.cflags}\""} ${lib.optionalString passLdflags "LDFLAGS=\"${f.ldflags}\""} \
          LIBS="${f.libs}" ./configure --prefix=/usr ${lib.escapeShellArgs configureFlags})
      ''
    )
    + ''
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
    ''
    + forBits (
      b: _: ''
        (cd ${ver}-${toString b}${suffix} && env -i PATH="$PATH" make -j$NIX_BUILD_CORES V=1)
      ''
    )
    + ''
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      ${if lib.isFunction install then install suffix else install}
      runHook postInstall
    '';

    # illumos ELF: leave it as the link-editor wrote it.
    dontFixup = true;
  }
  // extra
)
