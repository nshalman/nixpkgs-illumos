# illumos-extra's cpp (cpp/: cpp.c and the cpy.y grammar, which includes yylex.c), the C preprocessor the illumos
# build runs as /usr/lib/cpp, built for the strap as cpp/Makefile builds it: 32-bit, -O2, by the strap gcc, then
# installed as usr/lib/cpp.
#
# Their YACC is pkgsrc's /opt/local/bin/yacc; here it is byacc. Believed, not checked: that pkgsrc's `yacc` is
# byacc as well.
#
# With strap = false, as illumos-extra builds it for the platform (pkgs/smartos-extra): cpp itself rather than cppstrap,
# compiled against the proto area (illumosProto) and linked with GENLDFLAGS (-zassert-deflib -zfatal-warnings).
{
  lib,
  stdenv,
  strapBin,
  illumosExtraSrc,
  gcc,
  byacc,
  libDirFlags,
  strap ? true,
  illumosProto ? null,
}:

let
  # the suffix of the program and object names (cpp/Makefile PROG, OBJS)
  s = lib.optionalString strap "strap";
  # their DESTDIR: this package's output, then (non-strap) the illumos proto area
  protoDirs = [ "$out" ] ++ lib.optional (!strap) illumosProto;
  includeFlags = lib.concatMapStringsSep " " (d: "-isystem ${d}/usr/include") protoDirs;
  genLdFlags = lib.optionalString (!strap) " -Wl,-zassert-deflib -Wl,-zfatal-warnings";
in

stdenv.mkDerivation {
  pname = if strap then "smartos-strap-cpp" else "smartos-extra-cpp";
  version = "0-unstable-illumos-extra-5850d8e9";

  src = illumosExtraSrc [ "cpp" ];
  sourceRoot = "illumos-extra-cpp/cpp";

  nativeBuildInputs = [ byacc ];

  dontConfigure = true;

  # $(STRAPPROTO)/usr/bin first, as in a strap build (see ./default.nix)
  preBuild = ''
    export PATH=${strapBin}/bin:$PATH
  '';

  # COMPILE.c = $(GCC.32) $(CPPFLAGS) $(CFLAGS) -c; LINK.prog = $(GCC.32) $(LDFLAGS) -o $@ $(OBJS); the strap
  # directory in CPPFLAGS and LDFLAGS is this package's own output (see ./default.nix).
  buildPhase = ''
    runHook preBuild
    yacc cpy.y
    cc="${gcc} -m32"
    $cc ${includeFlags} -O2 -c cpp.c -o cpp.o${s}
    $cc ${includeFlags} -O2 -c y.tab.c -o y.tab.o${s}
    $cc ${libDirFlags 32 "-L" protoDirs}${genLdFlags} -o cpp${s} cpp.o${s} y.tab.o${s}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/usr/lib
    install -m 0755 cpp${s} $out/usr/lib/cpp
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
