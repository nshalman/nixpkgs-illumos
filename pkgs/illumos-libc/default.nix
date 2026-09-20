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

    # The 2021 <sys/mman.h> declares the mmap family twice, the second time with caddr_t, and hides madvise()
    # whenever _XOPEN_SOURCE is defined, which g++ always does. gcc 14 rejects the caddr_t prototypes ("passing
    # argument 1 of 'munmap' from incompatible pointer type", binutils) and C++ cannot see madvise() at all.
    #
    # It also adds _STRICT_POSIX to <sys/feature_tests.h>. gcc-illumos keeps a fixincludes copy of that header,
    # made from the pristine sysroot, which is found first; until gcc is rebuilt against this derivation
    # _STRICT_POSIX is never defined and <sys/mman.h> shows its extensions in strict POSIX mode too.
    ./14418-mman-visibility.patch
  ];

  # Parts of the sysroot that are not "the platform" for our purposes: nixpkgs has its own implementation with a
  # different API, and a configure script that finds these uses them without the package having declared
  # anything. Seen: gettext linked the system libcurses, and texinfo then failed against its SVR4 <curses.h>
  # (tputs takes an `int (*)(char)`); so did its <termcap.h>, found without any library to go with it. Packages that
  # want curses get ncurses from nixpkgs. usr/xpg4 is left alone:
  # nothing searches it by default.
  prune = [
    "usr/include/curses.h"
    "usr/include/term.h"
    "usr/include/termcap.h"
    "usr/include/unctrl.h"
    "lib/libcurses.so"
    "lib/libtermcap.so"
    "lib/libtermlib.so"
    "lib/amd64/libcurses.so"
    "lib/amd64/libtermcap.so"
    "lib/amd64/libtermlib.so"
    "usr/lib/libcurses.so"
    "usr/lib/libtermcap.so"
    "usr/lib/libtermlib.so"
    "usr/lib/amd64/libcurses.so"
    "usr/lib/amd64/libtermcap.so"
    "usr/lib/amd64/libtermlib.so"
  ];

  dontConfigure = true;
  dontBuild = true;
  # Real illumos libraries: leave them exactly as they are.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    for f in $prune; do
      # Only the link-time names go; the versioned libraries stay so that nothing else in the sysroot dangles.
      if [ -e "$f" ] || [ -L "$f" ]; then rm "$f"; else echo "prune: $f is not in the sysroot" >&2; exit 1; fi
    done
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
