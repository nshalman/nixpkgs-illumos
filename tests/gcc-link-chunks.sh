#!/usr/bin/env bash
# usage: tests/gcc-link-chunks.sh GCC-ILLUMOS-DRV
# Reads the build log of a gcc-illumos derivation and fails if libtool linked any library from reloadable chunks
# (`ld -r -o .libs/<name>.la-N.o`). Chunks appear when libtool's idea of the longest command line is too short, and
# their boundaries depend on the length of the build directory's path, so the libraries' layout would too.
set -u
log=$(nix-store --read-log "$1") || { echo "no build log for $1" >&2; exit 2; }
lens=$(printf '%s\n' "$log" | grep -oE 'maximum length of command line arguments\.\.\. (\(cached\) )?-?[0-9]+' \
  | sed 's/.*\.\.\. //' | sort | uniq -c | tr -s ' \n' ' ')
echo "command line lengths configure settled on (count value):$lens"
chunks=$(printf '%s\n' "$log" | grep -o ' -r -o \.libs/[^ ]*\.la-[0-9]*\.o' | sed 's|.*\.libs/||; s|\.la-[0-9]*\.o||' | sort | uniq -c)
if [ -n "$chunks" ]; then
  echo "FAIL: libraries linked from reloadable chunks (count name):"
  echo "$chunks"
  exit 1
fi
echo "PASS: no library linked from reloadable chunks"
