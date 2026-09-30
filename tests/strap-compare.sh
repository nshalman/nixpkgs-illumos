#!/usr/bin/env bash
# Compare a strap package built here with its part of SmartOS's own proto.strap, made by illumos-extra's
# install_strap at the same commit.
#
#   tests/strap-compare.sh REFERENCE-DIR OURS-DIR PATH-REGEX [EXPECTED-REGEX]
#
# REFERENCE-DIR is the unpacked proto.strap (pkgs/smartos-strap: reference), OURS-DIR a package's output laid out as
# its slice of proto.strap, and PATH-REGEX (grep -E, anchored by the caller) selects that slice of the reference
# by relative path. Every file and symbolic link in the slice and in OURS-DIR is described on one line, and the two
# descriptions have to be equal, except for the paths EXPECTED-REGEX matches, whose differences are shown and
# accepted (the caller says why):
#   symbolic link   its target, as written, with the strap and gcc directories named as for RUNPATH; with
#                   FOLLOW_STORE_LINKS set, a link into another store path is described as the file it points at
#   ELF file        whether executable, class, type, SONAME, NEEDED entries in order, RUNPATH and RPATH, the version
#                   definitions and the symbols each one exports
#   static library  whether executable, its members and the global symbols they define
#   text file       whether executable, sha256, after naming the strap and gcc directories as for RUNPATH
#                   (libtool archives name them) and replacing build dates (theirs have their build's) by <date>
#   *.chk           whether executable only (NSS's signatures of its libraries)
#   any other file  whether executable, sha256
# Modes are reduced to the executable bit: the store keeps no more than that. With IGNORE_MODES set they are not
# compared at all (shown as .): a platform takes its modes from its manifest, not from the proto area.
# With IGNORE_RUNPATHS set, RUNPATH and RPATH are left out of ELF descriptions (for files whose search paths are known
# to differ, the caller says why).
# Directories are left out: proto.strap's are shared by every package.
#
# With PATH_LIST set (a file of relative paths, one per line), the files and links compared, on both sides, are the
# ones it lists rather than all of them (PATH-REGEX still applies to the reference's): for a reference too large to
# walk, such as a whole platform's root, and a package whose output holds more than ships (headers in a proto area
# that the platform leaves out). A listed path one side lacks is described as missing.
#
# Not compared, because they cannot match: the code itself (another build of the same compiler and sources, linked
# against another libc), the .comment section, and where RUNPATH and RPATH entries point. They are compared after naming
# the strap directory <strap>/ (theirs: the build cache directory; ours: any smartos-strap package in the store)
# and gcc 10's runtime libraries <gcc>/ (theirs: /usr/gcc/10; ours: GCC_LIB, gcc10-illumos's lib output); the
# compiler itself (GCC_OUT, gcc10-illumos) is <strap>/usr/gcc/10, where theirs is.
set -euo pipefail

if [ $# -ne 3 ] && [ $# -ne 4 ]; then
  echo "usage: $0 REFERENCE-DIR OURS-DIR PATH-REGEX [EXPECTED-REGEX]" >&2
  exit 2
fi
ref=$1 ours=$2 regex=$3 expected=${4:-}
# a whole root is never walked: it has to come with PATH_LIST
if [ "$(cd "$ref" && pwd -P)" = / ] && [ -z "${PATH_LIST:-}" ]; then
  echo "$0: the reference is / and PATH_LIST is not set" >&2
  exit 2
fi
oursReal=$(cd "$ours" && pwd -P)
gccLib=${GCC_LIB:-/nonexistent}
gccOut=${GCC_OUT:-/nonexistent}

runpath() {
  sed -E \
    -e 's#/opt/SmartOS/build-cache/[^/]+/[^/]+/[0-9a-f]{40}/+#<strap>/#g' \
    -e 's#/root/data/jenkins/workspace/[^/]+/proto\.strap/+#<strap>/#g' \
    -e 's#/nix/store/[a-z0-9]{32}-smartos-strap-[^/:]*/+#<strap>/#g' \
    -e "s#${gccOut}/#<strap>/usr/gcc/10/#g" \
    -e 's#/usr/gcc/10/#<gcc>/#g' \
    -e "s#${gccLib}/#<gcc>/#g"
}

# Build stamps, which theirs have from their build: dates (a manual's .TH line, the date quoted or not; `date` output)
# become <date>
stamps() {
  sed -E \
    -e 's#^(\.TH .*)"[0-9]{4}-[0-9]{2}-[0-9]{2}"#\1"<date>"#' \
    -e 's#^(\.TH [^ ]+ [^ ]+ )[0-9]{4}-[0-9]{2}-[0-9]{2}( |$)#\1<date>\2#' \
    -e 's#[A-Z][a-z]{2} [A-Z][a-z]{2} [ 0-9][0-9] [0-9]{2}:[0-9]{2}:[0-9]{2}( [A-Z]{3,4})? [0-9]{4}#<date>#g'
}

# A package here has several strap directories (its own and its dependencies'), which all become <strap>/; keep the
# first of each repeated RUNPATH and RPATH entry.
dedup_runpath() {
  awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^(RUNPATH|RPATH)=/) {
        tag = substr($i, 1, index($i, "=") - 1)
        n = split(substr($i, length(tag) + 2), e, ":"); out = ""; delete seen
        for (j = 1; j <= n; j++) if (!(e[j] in seen)) { seen[e[j]] = 1; out = out (out == "" ? "" : ":") e[j] }
        $i = tag "=" out
      }
    }
    print
  }'
}

describe() {
  local f=$1 mode
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then
    printf 'missing\n'
    return
  fi
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
  if [ -n "${IGNORE_MODES:-}" ]; then mode=.; fi
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
      awk -v paths="${IGNORE_RUNPATHS:+no}" '$2 == "SONAME" || $2 == "NEEDED" ||
        (paths != "no" && ($2 == "RUNPATH" || $2 == "RPATH")) { printf "%s=%s ", $2, $4 }' | runpath | dedup_runpath)
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
    printf 'text %s %s\n' "$mode" "$(runpath <"$f" | stamps | sha256sum | cut -d' ' -f1)"
  else
    printf 'file %s %s\n' "$mode" "$(sha256sum <"$f" | cut -d' ' -f1)"
  fi
}

manifest() {
  local dir=$1 filter=$2 list=${3:-} p
  { if [ -n "$list" ]; then cat "$list"; else (cd "$dir" && find . \( -type f -o -type l \) | sed 's#^\./##'); fi } |
    LC_ALL=C sort |
    { if [ -n "$filter" ]; then grep -E "$filter" || true; else cat; fi } |
    while IFS= read -r p; do
      printf '%s\t%s\n' "$p" "$(describe "$dir/$p")"
    done
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
manifest "$ref" "$regex" "${PATH_LIST:-}" >"$tmp/reference"
manifest "$ours" "" "${PATH_LIST:-}" >"$tmp/ours"

if [ ! -s "$tmp/reference" ]; then
  echo "FAIL the reference has nothing matching $regex" >&2
  exit 1
fi
if diff -u "$tmp/reference" "$tmp/ours" >"$tmp/diff"; then
  echo "ok   $(wc -l <"$tmp/ours") files and links match the reference"
  exit 0
fi
cat "$tmp/diff"
# the paths that differ, and those of them not expected to
sed -n '/^[-+][^-+]/{ s/^[-+]//; s/\t.*//; p; }' "$tmp/diff" | sort -u >"$tmp/differ"
if [ -n "$expected" ]; then grep -Ev "$expected" "$tmp/differ" >"$tmp/unexpected" || true; else cp "$tmp/differ" "$tmp/unexpected"; fi
if [ -s "$tmp/unexpected" ]; then
  echo "FAIL differences from the reference (- theirs, + ours) in:"
  sed 's/^/       /' "$tmp/unexpected"
  exit 1
fi
echo "ok   $(wc -l <"$tmp/ours") files and links match the reference, except the expected differences above in:"
sed 's/^/       /' "$tmp/differ"
