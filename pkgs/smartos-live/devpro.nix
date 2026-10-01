# smartos-live's devpro stage (0-devpro-stamp): `gmake install` in projects/devpro, which installs the Sun C++ runtime
# libraries (libC, libCrun, libCstd, libiostream, libdemangle) kept prebuilt in smartos-live's tree (OpenSolaris b147's,
# its Readme says), with the illumos install(8) its Makefile puts on PATH, as theirs does. Nothing is built.
{
  stdenv,
  smartosLive,
}:

stdenv.mkDerivation {
  pname = "smartos-live-devpro";
  version = "0-unstable-2026-09-03";

  src = smartosLive;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    # install -f copies into directories their proto area already has
    mkdir -p $out/usr/include $out/usr/lib/amd64
    (cd projects/devpro && make DESTDIR=$out install)
    runHook postInstall
  '';

  # illumos ELF, prebuilt: leave it as it is.
  dontFixup = true;
}
