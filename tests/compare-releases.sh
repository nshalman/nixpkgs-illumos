#!/usr/bin/env bash
# usage: tests/compare-releases.sh TOOLS-A.tar.xz TOOLS-B.tar.xz
# Compares two bootstrap-tools tarballs file by file with store path hashes blanked. Two releases made by the same
# recipe from different bootstrap files cannot be bit-identical, their store paths differ; everything else should be.
# One difference follows from the store paths and is counted apart: the illumos ld writes a checksum of an object's
# contents into its dynamic section (DT_CHECKSUM, tag 0x6ffffdf8). Exit status 0 if nothing else differs.
set -u
t=$(mktemp -d); trap 'cd /; chmod -R u+w "$t"; rm -rf "$t"' EXIT
mkdir $t/a $t/b
xz -dc "$1" | tar -xf - -C $t/a; xz -dc "$2" | tar -xf - -C $t/b
(cd $t/a && find . | sort) > $t/list.a; (cd $t/b && find . | sort) > $t/list.b
echo "entries: $(wc -l < $t/list.a) and $(wc -l < $t/list.b); only in one: $(comm -3 $t/list.a $t/list.b | wc -l)"
comm -3 $t/list.a $t/list.b | head -10
blank='s|/nix/store/[a-z0-9]\{32\}|/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee|g'
same=0; cksum=0; : > $t/differ
while read -r f; do
  [ -f "$t/a/$f" ] && [ ! -L "$t/a/$f" ] && [ -f "$t/b/$f" ] || continue
  if cmp -s "$t/a/$f" "$t/b/$f"; then same=$((same + 1)); continue; fi
  sed -e "$blank" "$t/a/$f" > $t/x.a; sed -e "$blank" "$t/b/$f" > $t/x.b
  if cmp -s $t/x.a $t/x.b; then same=$((same + 1)); continue; fi
  n=$(cmp -l $t/x.a $t/x.b 2> /dev/null | wc -l)
  if [ "$(wc -c < $t/x.a)" = "$(wc -c < $t/x.b)" ] && [ "$n" -le 2 ]; then
    o=$(cmp -l $t/x.a $t/x.b | awk 'NR==1 {print $1}')
    tag=$(od -A n -t x1 -j $(((o - 1) - ((o - 1) % 8) - 8)) -N 8 $t/x.a | tr -d ' \n')
    if [ "$tag" = f8fdff6f00000000 ]; then cksum=$((cksum + 1)); continue; fi
  fi
  echo "$n $f" >> $t/differ
done < <(comm -12 $t/list.a $t/list.b)
other=$(wc -l < $t/differ | tr -d ' ')
echo "regular files identical once store hashes are blanked: $same"
echo "differing only in DT_CHECKSUM: $cksum"
echo "differing otherwise: $other"
sort -rn $t/differ | head -20
[ "$other" -eq 0 ] && [ "$(comm -3 $t/list.a $t/list.b | wc -l)" -eq 0 ]
