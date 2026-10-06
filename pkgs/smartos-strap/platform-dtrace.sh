#!/bin/sh
# smartos-strap.platformDtrace (./default.nix): the build host's dtrace, with ./dtrace-shim.c preloaded and without
# address space layout randomization; and for dtrace -G, the object it writes (-o) with its actions' dofa_uargs
# zeroed (./dof-zero-uarg.c).
obj= link= prev=
for a in "$@"; do
	[ "$prev" = -o ] && obj=$a
	case $a in
	-o) ;;
	-o*) obj=${a#-o} ;;
	# an option that takes a value, with it (dtrace.c's DTRACE_OPTSTR, "3:6:aAb:Bc:CD:ef:FGhHi:I:lL:m:n:o:p:P:qs:SU:
	# vVwx:X:Z": -32 and -64 are -3 and -6 with a value)
	-[36bcDfiILmnpPsUxX]*) ;;
	# flags, -G among them
	-*G*) link=1 ;;
	esac
	prev=$a
done
if [ -n "$link" ] && [ -z "$obj" ]; then
	echo "@out@/bin/dtrace: dtrace -G without -o: name the object it writes with -o, so that it can be zeroed" >&2
	exit 2
fi
LD_PRELOAD_64=@out@/lib/dtrace-shim.so /usr/bin/psecflags -s current,-aslr -e /usr/sbin/dtrace "$@" || exit
[ -z "$link" ] || exec @out@/libexec/dof-zero-uarg "$obj"
