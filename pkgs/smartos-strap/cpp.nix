# illumos-extra's cpp (cpp/: cpp.c and the cpy.y grammar, which includes yylex.c), the C preprocessor the illumos
# build runs as /usr/lib/cpp, built for the strap as cpp/Makefile builds it: 32-bit, -O2, by the strap gcc, then
# installed as usr/lib/cpp.
#
# Their YACC is pkgsrc's /opt/local/bin/yacc; here it is byacc. Believed, not checked: that pkgsrc's `yacc` is
# byacc as well.
{
  stdenv,
  strapBin,
  illumosExtra,
  gcc,
  byacc,
}:

stdenv.mkDerivation {
  pname = "smartos-strap-cpp";
  version = "0-unstable-illumos-extra-5850d8e9";

  src = illumosExtra;
  sourceRoot = "source/cpp";

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
    $cc -isystem $out/usr/include -O2 -c cpp.c -o cpp.ostrap
    $cc -isystem $out/usr/include -O2 -c y.tab.c -o y.tab.ostrap
    $cc -L$out/usr/lib -L$out/lib -o cppstrap cpp.ostrap y.tab.ostrap
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/usr/lib
    install -m 0755 cppstrap $out/usr/lib/cpp
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
