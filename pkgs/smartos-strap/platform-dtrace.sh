#!/bin/sh
# smartos-strap.platformDtrace (./default.nix): the build host's dtrace, with ./dtrace-shim.c preloaded (which also
# zeroes the dofa_uargs in each object dtrace -G writes) and without address space layout randomization.
LD_PRELOAD_64=@out@/lib/dtrace-shim.so exec /usr/bin/psecflags -s current,-aslr -e /usr/sbin/dtrace "$@"
