#!/usr/bin/env bash
# usage: tests/compare-releases.sh TOOLS-A.tar.xz TOOLS-B.tar.xz
# Compares two bootstrap-tools tarballs file by file with store path hashes blanked. Two releases made by the same
# recipe from different bootstrap files cannot be bit-identical, their store paths differ; everything else should be.
set -u
t=$(mktemp -d); trap 'cd /; chmod -R u+w "$t"; rm -rf "$t"' EXIT
for s in a b; do mkdir $t/$s; done
xz -dc "$1" | tar -xf - -C $t/a; xz -dc "$2" | tar -xf - -C $t/b
(cd $t/a && find . | sort) > $t/list.a; (cd $t/b && find . | sort) > $t/list.b
echo "entries: $(wc -l < $t/list.a) and $(wc -l < $t/list.b); only in one: $(comm -3 $t/list.a $t/list.b | wc -l)"
comm -3 $t/list.a $t/list.b | head -10
same=0; diff=0; : > $t/differ
while read -r f; do
  [ -f "$t/a/$f" ] && [ ! -L "$t/a/$f" ] && [ -f "$t/b/$f" ] || continue
  if cmp -s "$t/a/$f" "$t/b/$f"; then same=$((same + 1)); continue; fi
  ha=$(sed -e 's|/nix/store/[a-z0-9]\{32\}|/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee|g' "$t/a/$f" | sha256sum)
  hb=$(sed -e 's|/nix/store/[a-z0-9]\{32\}|/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee|g' "$t/b/$f" | sha256sum)
  if [ "$ha" = "$hb" ]; then same=$((same + 1)); else diff=$((diff + 1)); echo "$f" >> $t/differ; fi
done < <(comm -12 $t/list.a $t/list.b)
echo "regular files identical once store hashes are blanked: $same; different: $diff"
sed 's|/[^/]*$||' $t/differ | sort | uniq -c | sort -rn | head -15
echo "examples:"; head -15 $t/differ
