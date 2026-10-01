#!/usr/bin/env bash
#
# smartos-live's tzcheck (@tzcheck@), for a proto area in the Nix store, with tzcheck's arguments (-f MANIFEST
# -p PROTO). tzcheck also checks that the zoneinfo files the manifest makes hard links of are hard links in the proto
# area; the store keeps no hard links, so there each such pair is to be the same contents instead (the image's hard
# links are builder's, from the manifest). Any other error tzcheck reports is one here.

set -euo pipefail

proto=
args=("$@")
while getopts "f:p:v" opt; do
    case $opt in
        p) proto=$OPTARG ;;
        *) ;;
    esac
done
[ -n "$proto" ] || { echo "$0: no -p PROTO" >&2; exit 2; }

out=$(mktemp)
trap 'rm -f "$out"' EXIT
rc=0
@tzcheck@ "${args[@]}" >"$out" || rc=$?
[ $rc = 0 ] || [ $rc = 60 ] || { cat "$out"; exit $rc; }

# "hardlink mismatch: NAME", "manifest: TARGET", "proto: check manually"; anything else but the count is an error
n=0
while read -r what name target; do
    if [ "$what" != link ]; then
        echo "tzcheck: $name $target"
        exit 1
    fi
    cmp -s "$proto/usr/share/lib/zoneinfo/$name" "$proto/usr/share/lib/zoneinfo/$target" ||
        { echo "tzcheck: $name and $target differ (the manifest makes them one file)"; exit 1; }
    n=$((n + 1))
done < <(awk '/^hardlink mismatch: / { name = $3; getline; target = $2; getline; print "link", name, target; next }
    /^$/ || /^time zone errors found: / || /^ok: / { next } { print "other", $0 }' "$out")
echo "tzcheck: no errors; $n hard links, each the same contents in $proto"
