#!/usr/bin/env bash
# Compare a strap package built here with its part of SmartOS's own proto.strap, made by illumos-extra's
# install_strap at the same commit.
#
#   tests/strap-compare.sh REFERENCE-DIR OURS-DIR PATH-REGEX
#
# REFERENCE-DIR is the unpacked proto.strap (pkgs/smartos-strap: reference), OURS-DIR a package's output laid out as
# its slice of proto.strap, and PATH-REGEX (grep -E, anchored by the caller) selects that slice of the reference
# by relative path. Every file and symbolic link in the slice and in OURS-DIR is described on one line, and the two
# descriptions have to be equal:
#   symbolic link   its target, as written, with the strap and gcc directories named as for RUNPATH; with
#                   FOLLOW_STORE_LINKS set, a link into another store path is described as the file it points at
#   ELF file        whether executable, class, type, SONAME, NEEDED entries in order, RUNPATH, the version
#                   definitions and the symbols each one exports
#   static library  whether executable, its members and the global symbols they define
#   text file       whether executable, sha256, after naming the strap and gcc directories as for RUNPATH
#                   (libtool archives name them)
#   *.chk           whether executable only (NSS's signatures of its libraries)
#   any other file  whether executable, sha256
# Modes are reduced to the executable bit: the store keeps no more than that.
# Directories are left out: proto.strap's are shared by every package.
#
# Not compared, because they cannot match: the code itself (another build of the same compiler and sources, linked
# against another libc), the .comment section, and where RUNPATH entries point. RUNPATH is compared after naming
# the strap directory <strap>/ (theirs: the build cache directory; ours: any smartos-strap package in the store)
# and gcc 10's runtime libraries <gcc>/ (theirs: /usr/gcc/10; ours: GCC_LIB, gcc10-illumos's lib output).
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 REFERENCE-DIR OURS-DIR PATH-REGEX" >&2
  exit 2
fi
ref=$1 ours=$2 regex=$3
oursReal=$(cd "$ours" && pwd -P)
gccLib=${GCC_LIB:-/nonexistent}

runpath() {
  sed -E \
    -e 's#/opt/SmartOS/build-cache/[^/]+/[^/]+/[0-9a-f]{40}/+#<strap>/#g' \
    -e 's#/nix/store/[a-z0-9]{32}-smartos-strap-[^/:]*/+#<strap>/#g' \
    -e 's#/usr/gcc/10/#<gcc>/#g' \
    -e "s#${gccLib}/#<gcc>/#g"
}

# A package here has several strap directories (its own and its dependencies'), which all become <strap>/; keep the
# first of each repeated RUNPATH entry.
dedup_runpath() {
  awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^RUNPATH=/) {
        n = split(substr($i, 9), e, ":"); out = ""; delete seen
        for (j = 1; j <= n; j++) if (!(e[j] in seen)) { seen[e[j]] = 1; out = out (out == "" ? "" : ":") e[j] }
        $i = "RUNPATH=" out
      }
    }
    print
  }'
}

describe() {
  local f=$1 mode
  if [ -L "$f" ]; then
    local t
    t=$(readlink "$f")
    # FOLLOW_STORE_LINKS (a tree of links such as the whole proto.strap): a link into another store path stands
    # for the file it points at
    if [ -n "${FOLLOW_STORE_LINKS:-}" ] && [ "${t#/nix/store/}" != "$t" ] && [ "${t#"$oursReal"/}" = "$t" ]; then
      describe "$t"
      return
    fi
    printf 'link -> %s\n' "$(printf %s "$t" | runpath)"
    return
  fi
  # the store keeps only whether a file is executable (555 or 444)
  if [ $((8#$(stat -L -c %a "$f") & 8#111)) -ne 0 ]; then mode=x; else mode=-; fi
  case $f in
    *.chk)
      # NSS's shlibsign signature of the library beside it: it cannot match
      printf 'chk %s\n' "$mode"
      return
      ;;
  esac
  # elfdump -e exits 0 on any file, so look at the magic number
  if [ "$(od -An -N4 -tx1 "$f" | tr -d " \n")" = 7f454c46 ]; then
    local class type dyn
    class=$(/usr/bin/elfdump -e "$f" | awk '/ei_class:/ { print $2; exit }')
    type=$(/usr/bin/elfdump -e "$f" | awk '/e_type:/ { print $2; exit }')
    dyn=$(/usr/bin/elfdump -d "$f" 2>/dev/null |
      awk '$2 == "SONAME" || $2 == "NEEDED" || $2 == "RUNPATH" { printf "%s=%s ", $2, $4 }' | runpath | dedup_runpath)
    printf 'elf %s %s %s %s' "$mode" "$class" "$type" "$dyn"
    # pvs -ds: a version definition is indented by one tab and ends in ':' or ';'; its symbols follow, indented by two
    # tabs, each ending in ';'
    /usr/bin/pvs -ds "$f" 2>/dev/null | awk '
      /^\t[^\t]/ { v = $1; sub(/[:;]$/, "", v); print "def:" v; next }
      { s = $1; sub(/;$/, "", s); if (s != "") print "sym:" v ":" s }' | sort | tr '\n' ' '
    printf '\n'
  elif [ "$(od -An -N7 -tx1 "$f" | tr -d " \n")" = 213c617263683e ]; then
    # a static library: its members and the global symbols they define
    printf 'ar %s %s %s\n' "$mode" "$(/usr/bin/ar t "$f" | LC_ALL=C sort | tr '\n' ' ')" \
      "$(/usr/bin/nm -Pg "$f" 2>/dev/null | awk '$2 ~ /^[A-Z]$/ && $2 != "U" { print $1 }' | LC_ALL=C sort -u | tr '\n' ' ')"
  elif grep -Iq . "$f" 2>/dev/null || [ ! -s "$f" ]; then
    # text, e.g. a libtool archive: compared with the strap and gcc directories named as for RUNPATH
    printf 'text %s %s\n' "$mode" "$(runpath <"$f" | sha256sum | cut -d' ' -f1)"
  else
    printf 'file %s %s\n' "$mode" "$(sha256sum <"$f" | cut -d' ' -f1)"
  fi
}

manifest() {
  local dir=$1 filter=$2 p
  (cd "$dir" && find . \( -type f -o -type l \) | sed 's#^\./##' | LC_ALL=C sort) |
    { if [ -n "$filter" ]; then grep -E "$filter" || true; else cat; fi } |
    while IFS= read -r p; do
      printf '%s\t%s\n' "$p" "$(describe "$dir/$p")"
    done
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
manifest "$ref" "$regex" >"$tmp/reference"
manifest "$ours" "" >"$tmp/ours"

if [ ! -s "$tmp/reference" ]; then
  echo "FAIL the reference has nothing matching $regex" >&2
  exit 1
fi
if diff -u "$tmp/reference" "$tmp/ours"; then
  echo "ok   $(wc -l <"$tmp/ours") files and links match the reference"
else
  echo "FAIL differences from the reference (- theirs, + ours)"
  exit 1
fi
