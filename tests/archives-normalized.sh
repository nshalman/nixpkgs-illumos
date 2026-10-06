#!/usr/bin/env bash
#
# Whether the archives the packages install are the same from one build to the next: for each attribute, every
# member of every archive (*.a) in its outputs is dated the stdenv's epoch (SOURCE_DATE_EPOCH's default, 1980-01-01)
# and owned by 0/0 (pkgs/smartos-strap/normalize-archives.pl), as the platform's ar lists them. An attribute without
# archives passes, and is said to.
#
# usage: archives-normalized.sh PKGS-FILE ATTR...   e.g. archives-normalized.sh /work/dev-pkgs.nix smartos-strap.perl

set -uo pipefail

pkgsFile=${1:?usage: $0 PKGS-FILE ATTR...}
shift
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

for attr in "$@"; do
    if ! outs=$(nix-build "$pkgsFile" -A "$attr" --no-out-link 2>"$tmp/build.log"); then
        bad "$attr does not build"; tail -5 "$tmp/build.log" | sed 's/^/    /'
        continue
    fi
    archives=0 members=0 others=0
    for out in $outs; do
        while IFS= read -r a; do
            [ "$(head -c 8 "$a")" = '!<arch>' ] || continue
            archives=$((archives + 1))
            /usr/bin/ar -tv "$a" >"$tmp/tv" 2>&1 || { others=$((others + 1)); echo "    ar cannot list $a"; continue; }
            members=$((members + $(wc -l <"$tmp/tv")))
            n=$(grep -vc ' 0/ *0 .* Jan  1 00:00 1980 ' "$tmp/tv")
            if [ "$n" -gt 0 ]; then
                others=$((others + n))
                grep -v ' 0/ *0 .* Jan  1 00:00 1980 ' "$tmp/tv" | head -2 | sed "s|^|    $a: |"
            fi
        done < <(find "$out" -name '*.a' -type f)
    done
    if [ "$archives" = 0 ]; then
        ok "$attr has no archives"
    elif [ "$others" = 0 ]; then
        ok "$attr: $archives archives, all $members members dated the epoch and owned by 0/0"
    else
        bad "$attr: $others of $members members in $archives archives are not"
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
