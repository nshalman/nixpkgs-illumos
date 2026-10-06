#!/bin/sh
# smartos-strap.platformDtrace (./default.nix): the build host's dtrace, with ./dtrace-shim.c preloaded and without
# address space layout randomization; and for dtrace -G, the objects it writes with their actions' dofa_uargs
# zeroed (./dof-zero-uarg.c).
#
# The objects dtrace -G writes, as dtrace.c's link_prog() names them: with -o and one program, the -o file; else for
# each program, a script X.d's basename(X).o (in the current directory), or d.out; and with several programs and -o,
# the -o file too, which joins them. Programs other than scripts (-n, -P, -m, -f, -i) and d.out are refused.
#
# The options are read as dtrace's getopt() reads them (DTRACE_OPTSTR "3:6:aAb:Bc:CD:ef:FGhHi:I:lL:m:n:o:p:P:qs:SU:
# vVwx:X:Z": -32 and -64 are -3 and -6 with a value), up to the first operand.
obj= link= other= scripts= n=0 want=
take() {
	case $1 in
	o) obj=$2 ;;
	s) n=$((n + 1)); scripts="$scripts$2
" ;;
	[nPmfi]) n=$((n + 1)); other=1 ;;
	esac
}
for a in "$@"; do
	if [ -n "$want" ]; then take "$want" "$a"; want=; continue; fi
	case $a in
	--) break ;;
	-?*) ;;
	*) break ;;
	esac
	cl=${a#-}
	while [ -n "$cl" ]; do
		c=${cl%"${cl#?}"} cl=${cl#?}
		case $c in
		[36bcDfiILmnopPsUxX])
			if [ -n "$cl" ]; then take "$c" "$cl"; else want=$c; fi
			cl= ;;
		G) link=1 ;;
		esac
	done
done

objs=
if [ -n "$link" ]; then
	refuse() {
		echo "@out@/bin/dtrace: dtrace -G: $1: its objects cannot be zeroed; name them with -o and -s X.d" >&2
		exit 2
	}
	[ -z "$other" ] || refuse "a program not from a script (-n, -P, -m, -f, -i)"
	if [ "$n" = 1 ] && [ -n "$obj" ]; then
		objs=$obj
	else
		objs=$(printf '%s' "$scripts" | while IFS= read -r s; do
			case $s in
			*.d) b=${s%.d}; echo "${b##*/}.o" ;;
			*) echo "d.out" ;;
			esac
		done)
		case "
$objs
" in *"
d.out
"*) refuse "a script not named X.d (its object would be d.out)" ;; esac
		[ "$n" -gt 1 ] && [ -n "$obj" ] && objs="$objs
$obj"
	fi
fi

LD_PRELOAD_64=@out@/lib/dtrace-shim.so /usr/bin/psecflags -s current,-aslr -e /usr/sbin/dtrace "$@" || exit
[ -n "$objs" ] || exit 0
printf '%s\n' "$objs" | while IFS= read -r f; do
	@out@/libexec/dof-zero-uarg "$f" || exit
done
