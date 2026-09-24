#!/usr/bin/env bash
# Audit the runtime closure of one or more store paths on an illumos host.
#
#   tests/audit-closure.sh [-f FLOOR] [-o OLD-PATHS-FILE] [-x LINK-ONLY-REGEX] [-p LIB,LIB] STORE-PATH...
#
# For every ELF object in the closure:
#   floor     no libc interface newer than ILLUMOS_0.FLOOR (default 38, the 2021 sysroot)
#   runpath   no illumos-sysroot / illumos-libc directory in RUNPATH or RPATH: libc must come from the running system
#   interp    executables use the system runtime linker, not one from the store
#   errno     no import of the plain `errno` object: on illumos that is the MAIN thread's errno, whatever thread
#             the code runs on; `___errno` is the thread-safe accessor
#   needed    no NEEDED entry with a directory in it. The illumos ld records an input library that has no SONAME
#             under the path it was given on the command line; the runtime linker then looks for exactly that path
#   resolve   ldd finds every dependency
#   outside   every RUNPATH/RPATH directory is in the store. nixpkgs checks for a build directory left in a RUNPATH
#             with patchelf at fixup time; a stdenv without patchelf on PATH skips that check without failing
#   platform  the system libraries an object names itself (NEEDED entries that resolve outside the store) are on the
#             allow-list: illumos-gate libraries with public, committed interfaces. -p LIB,LIB adds to the list.
#             What those libraries need in turn is the running system's own business and is only reported.
# And for the closure as a whole:
#   dev       no -dev output (headers, pkg-config files): nothing needs one at run time, and one gets in when a
#             header's __FILE__ names its store path, which gcc-illumos prevents by mangling the hash
#   old       no store path named in OLD-PATHS-FILE, any text file with the previous generation's store paths in it,
#             e.g. illumos-recipe-v2's bootstrap-files/x86_64-illumos-paths.nix. NOT stdenv/bridge-paths.nix: that also
#             names the current toolchain.
#   (report)  every library resolved from outside the store, directly or not, with the number of objects using it
#             and every library from which a private-versioned symbol is bound. Most of those are what the system
#             headers turn assert(), TLS and XPG5 calls into; a library of ours using another one's internals
#             (illumos ld and libelf) shows up here too
#
# -x names store paths whose ELF objects are not examined because nothing loads them: the link-only libc, which is the
# 2021 sysroot's own libraries. The runpath check is what guarantees they are never loaded.
#
# Uses the host's elfdump/pvs/ldd, so it runs outside Nix. NIX_STORE_CMD overrides `nix-store`.
set -u
floor=38; old=; linkonly=
# libintl.so.1 is a filter on libc (libiconv cannot use gettext, which needs libiconv); libkstat is what gcc uses to
# size its memory pools.
allowed="libc.so.1 libm.so.2 libsocket.so.1 libnsl.so.1 libdl.so.1 libpthread.so.1 libsec.so.1 librt.so.1 libresolv.so.2 libnvpair.so.1 libintl.so.1 libkstat.so.1"
while getopts f:o:x:p: c; do case $c in p) allowed="$allowed $(echo $OPTARG | tr , " ")" ;; f) floor=$OPTARG ;; o) old=$OPTARG ;; x) linkonly=$OPTARG ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1)); [ $# -gt 0 ] || { echo "usage: $0 [-f floor] [-o old-paths] [-x link-only-regex] [-p lib,lib] store-path..." >&2; exit 2; }
NS=${NIX_STORE_CMD:-nix-store}; E=/usr/bin/egrep
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
$NS -qR "$@" | sort -u > $tmp/closure
echo "closure: $(wc -l < $tmp/closure | tr -d ' ') store paths"
if [ -n "$linkonly" ]; then $E -v -- "$linkonly" $tmp/closure > $tmp/examined; echo "link-only, not examined: $($E -c -- "$linkonly" $tmp/closure) store path(s) matching $linkonly"; else cp $tmp/closure $tmp/examined; fi
: > $tmp/floor; : > $tmp/runpath; : > $tmp/interp; : > $tmp/errno; : > $tmp/needed; : > $tmp/resolve; : > $tmp/outside; : > $tmp/notallowed; : > $tmp/private; : > $tmp/platform; n=0
while read -r p; do
  find "$p" -type f \( -perm -u+x -o -name '*.so' -o -name '*.so.*' \) 2>/dev/null
done < $tmp/examined | while read -r f; do
  [ "$(head -c 4 "$f" 2>/dev/null | od -An -c | tr -d ' ')" = '177ELF' ] || continue
  echo "$f" >> $tmp/elf
  v=$(/usr/bin/pvs -r "$f" 2>/dev/null | $E -o 'ILLUMOS_0\.[0-9]+' | awk -F. '{print $2}' | sort -n | tail -1)
  [ "${v:-0}" -le "$floor" ] || echo "ILLUMOS_0.$v $f" >> $tmp/floor
  d=$(/usr/bin/elfdump -d "$f" 2>/dev/null)
  echo "$d" | $E 'RUNPATH|RPATH' | $E -q 'illumos-(sysroot|libc)' && echo "$f" >> $tmp/runpath
  i=$(/usr/bin/elfdump -i "$f" 2>/dev/null | awk 'NF && !/Interpreter Section/ {print $NF}' | tail -1)
  case "${i:-}" in ''|/usr/lib/amd64/ld.so.1|/usr/lib/ld.so.1|/lib/ld.so.1|/lib/amd64/ld.so.1) ;; *) echo "$i $f" >> $tmp/interp ;; esac
  /usr/bin/elfdump -s -N .dynsym "$f" 2>/dev/null | awk '$NF=="errno" && /UNDEF/' | grep -q . && echo "$f" >> $tmp/errno
  echo "$d" | awk -v f="$f" '$2=="RUNPATH" || $2=="RPATH" {n=split($4, a, ":"); for (i=1; i<=n; i++) if (a[i] != "" && a[i] !~ /^\/nix\/store\// && a[i] !~ /^\$ORIGIN/) print a[i], f}' | sort -u >> $tmp/outside
  echo "$d" | awk -v f="$f" '$2=="NEEDED" && $4 ~ /\// {print $4, f}' >> $tmp/needed
  /usr/bin/pvs -r "$f" 2>/dev/null | tr -d "\t;" | awk "/private/ {print \$1}" >> $tmp/private
  l=$( (cd / && /usr/bin/ldd "$f" 2>/dev/null) )
  for n in $(echo "$d" | awk '$2=="NEEDED" {print $4}'); do
    case "$(echo "$l" | awk -v n="$n" '$1==n && $2=="=>" {print $3; exit}')" in
      /nix/store/*|'') ;;
      *) case " $allowed " in *" $n "*) ;; *) echo "$n $f" >> $tmp/notallowed ;; esac ;;
    esac
  done
  (cd / && /usr/bin/ldd "$f" 2>/dev/null) | awk -v f="$f" '/file not found/ {print $1, f}' >> $tmp/resolve
  (cd / && /usr/bin/ldd "$f" 2>/dev/null) | awk '$2=="=>" && $3 !~ /^\/nix\/store\// && $3 != "(file" {print $1}' >> $tmp/platform
done
fail=0
report() { local name=$1 file=$2 what=$3; local c; c=$(wc -l < "$file" | tr -d ' ')
  if [ "$c" -eq 0 ]; then echo "ok   $name: $what"; else echo "FAIL $name: $c object(s): $what"; sed 's/^/       /' "$file" | head -15; fail=1; fi; }
echo "ELF objects examined: $(wc -l < $tmp/elf 2>/dev/null | tr -d ' ')"
report floor   $tmp/floor   "nothing needs a libc interface above ILLUMOS_0.$floor"
report runpath $tmp/runpath "no sysroot or libc directory in any RUNPATH"
report interp  $tmp/interp  "every executable uses the system runtime linker"
report errno   $tmp/errno   "nothing imports the plain errno object"
report needed  $tmp/needed  "no NEEDED entry names a directory"
report resolve $tmp/resolve "ldd finds every dependency"
report outside $tmp/outside "every RUNPATH directory is in the store"
report platform $tmp/notallowed "every system library an object names is on the allow-list"
$E -- '-dev$' $tmp/closure > $tmp/dev
report dev     $tmp/dev     "no -dev output in the closure"
if [ -n "$old" ]; then
  $E -o '/nix/store/[a-z0-9]{32}-[^;" ]+' "$old" | sort -u > $tmp/oldpaths; comm -12 $tmp/closure $tmp/oldpaths > $tmp/oldhits
  report old $tmp/oldhits "no path of the previous generation in the closure"
fi
echo "platform libraries resolved from the running system (count of objects using each):"
sort $tmp/platform | uniq -c | sort -rn | awk '{printf "   %5d  %s\n", $1, $2}'
echo "libraries from which private-versioned symbols are bound (count of objects):"
sort $tmp/private | uniq -c | sort -rn | awk '{printf "   %5d  %s\n", $1, $2}'
[ $fail -eq 0 ] && echo "AUDIT: PASS" || { echo "AUDIT: FAIL"; exit 1; }
