# The libc the compiler wrappers use: the published illumos sysroot plus header fixes backported from
# illumos-gate. illumos-sysroot itself stays exactly as published and is this derivation's only input.
#
# Why headers need fixing at all: the sysroot pins 2021 headers, and compilers move on. Each patch is the header
# part of one upstream illumos commit, so a newer sysroot simply makes it unnecessary. Only libraries' *headers*
# change here; the link libraries are the sysroot's, and at run time libc is always the running system's.
#
# This is cheap to rebuild, unlike gcc, which is why the fixes live here and not in gcc's include-fixed.
{
  lib,
  stdenvNoCC,
  illumos-sysroot,
}:

stdenvNoCC.mkDerivation {
  pname = "illumos-libc";
  inherit (illumos-sysroot) version;

  src = illumos-sysroot;

  patches = [
    # C23 reads `void (*)()` as "no arguments", and gcc 14 rejects mixing that with `void (*)(int)` handlers.
    # The 2021 headers use it for SIG_DFL, SIG_IGN, SIG_ERR, SIG_HOLD and, for C, sigaction's sa_handler.
    # configure scripts from autoconf 2.73 select -std=gnu23 by themselves, so this breaks xz, and through
    # gnulib nearly every GNU package.
    ./16344-signal-constants.patch
  ];

  dontConfigure = true;
  dontBuild = true;
  # Real illumos libraries: leave them exactly as they are.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R lib usr $out/
    runHook postInstall
  '';

  passthru = {
    inherit (illumos-sysroot)
      incdir
      libdir
      dynamicLinker
      libcFloor
      ;
    pristine = illumos-sysroot;
  };

  meta = illumos-sysroot.meta // {
    description = "illumos sysroot with header fixes backported from illumos-gate, for use as the wrappers' libc";
  };
}
