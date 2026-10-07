#!/usr/bin/env bash
#
# ../pkgs/smartos-strap/normalize-zips.pl on archives the build's tools make: openjdk 11's jar and jmod, and zip (as
# openjdk's own build makes src.zip, with its extended timestamp and owner extra fields). The same files archived
# twice, with other modification times and owners, and the jar and the zip with their entries in another order (as
# jmod and jar take them from directories, in the order the file system gives), are different archives; once
# normalized (SOURCE_DATE_EPOCH given) they are the same file, the jar's manifest still first (where
# JarInputStream looks for it), which unzip tests whole, lists with that time and extracts to what was put in, and
# java reads (jar, a class from it; jmod, its contents). A file named .jar that is not an archive is left as it is,
# as is an archive outside the directory given; without SOURCE_DATE_EPOCH it refuses.
#
# usage: normalize-zips.sh PKGS-FILE   (as root, for chown; on illumos; perl and nix-build on PATH)

set -uo pipefail

pkgsFile=${1:?usage: $0 PKGS-FILE}
top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
# leave $tmp first, as illumos' rm does not remove the current directory
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

jdk=$(nix-build "$pkgsFile" -A openjdk11-illumos --no-out-link)/lib/openjdk/bin || { bad "no openjdk"; exit 1; }
zip=$(nix-build "$pkgsFile" -A zip --no-out-link)/bin/zip || { bad "no zip"; exit 1; }
unzip=$(nix-build "$pkgsFile" -A unzip --no-out-link)/bin/unzip || { bad "no unzip"; exit 1; }
norm="perl $top/pkgs/smartos-strap/normalize-zips.pl"

cd "$tmp"
mkdir -p src/t mod/t
printf 'package t;\npublic class Hello { public static void main(String[] a) { System.out.println("hello"); } }\n' >src/t/Hello.java
printf 'package t;\npublic class Two {}\n' >src/t/Two.java
printf 'module t { exports t; }\n' >src/module-info.java
"$jdk/javac" -d classes src/module-info.java src/t/Hello.java src/t/Two.java || { bad "cannot compile"; exit 1; }

# the same classes, archived as v at time T by owner O, the jar's and the zip's entries in order E
for v in a b; do
    mkdir -p $v/out
    cp -r classes $v/
done
find a/classes -exec touch -t 202001010000 {} +
find b/classes -exec touch -t 202602030405 {} +
chown -R 12345:54321 b/classes
order_a="module-info.class t/Hello.class t/Two.class" order_b="t/Two.class t/Hello.class module-info.class"
for v in a b; do
    eval "order=\$order_$v"
    (cd $v && "$jdk/jar" --create --file out/t.jar $(for e in $order; do echo "-C classes $e"; done) &&
        "$jdk/jmod" create --class-path classes out/t.jmod >/dev/null &&
        (cd classes && "$zip" -qr ../out/t.zip $order))
    # jmod dates its entries, and jar those it writes itself (META-INF/, directories), with the time it runs, to two
    # seconds (a DOS time): b's at least that much later
    sleep 2
done
echo 'not an archive' >a/out/text.jar
cp a/out/text.jar text.jar.orig
cp b/out/t.jar outside.jar

same() { cmp -s a/out/$1 b/out/$1; }
if ! same t.jar && ! same t.jmod && ! same t.zip; then
    ok "the jar, jmod and zip differ before normalizing"
else
    bad "a pair is the same before normalizing: the test shows nothing"; for f in t.jar t.jmod t.zip; do same $f && echo "    same: $f"; done
fi

if (unset SOURCE_DATE_EPOCH; ! $norm a 2>err) && grep -q SOURCE_DATE_EPOCH err; then
    ok "without SOURCE_DATE_EPOCH it refuses"
else
    bad "without SOURCE_DATE_EPOCH it does not refuse"
fi

export SOURCE_DATE_EPOCH=1757600000   # 2025-09-11 14:13:20 UTC
if $norm a && $norm b; then
    ok "normalize-zips.pl runs"
else
    bad "normalize-zips.pl fails"
fi

for f in t.jar t.jmod t.zip; do
    if same $f; then ok "$f: the same once normalized"; else bad "$f: still differs"; cmp -l a/out/$f b/out/$f | head -3; fi
done
if [ "$("$unzip" -Z1 a/out/t.jar | head -2 | tr '\n' ' ')" = "META-INF/ META-INF/MANIFEST.MF " ]; then
    ok "t.jar: META-INF/ and its MANIFEST.MF still first"
else
    bad "t.jar: the manifest is not first:"; "$unzip" -Z1 a/out/t.jar | head -3
fi

# unzip -t only for the zip: it rejects the empty extra field (0xCAFE) the jar tool gives META-INF/, in any jar
for f in t.jar t.zip; do
    if { [ $f = t.jar ] || "$unzip" -tq a/out/$f >/dev/null; } && [ "$("$unzip" -Z -T a/out/$f | grep -c ' 20250911\.1413[12][0-9] ')" -gt 0 ] &&
        [ "$("$unzip" -Z -T a/out/$f | grep -v ' 20250911\.1413[12][0-9] ' | grep -c '^[-d]')" = 0 ]; then
        ok "$f: unzip lists every entry at SOURCE_DATE_EPOCH (and tests t.zip whole)"
    else
        bad "$f: unzip's test or listing"; "$unzip" -Z -T a/out/$f | head -5
    fi
done
mkdir x && (cd x && "$unzip" -q ../a/out/t.zip)
if cmp -s x/t/Hello.class classes/t/Hello.class && cmp -s x/module-info.class classes/module-info.class; then
    ok "t.zip extracts to what was put in"
else
    bad "t.zip extracts to something else"
fi
if [ "$("$jdk/java" -cp a/out/t.jar t.Hello)" = hello ]; then
    ok "java runs a class from t.jar"
else
    bad "java cannot run a class from t.jar"
fi
if "$jdk/jmod" list a/out/t.jmod | grep -q 'classes/t/Hello.class'; then
    ok "jmod lists t.jmod"
else
    bad "jmod cannot list t.jmod"
fi

if cmp -s a/out/text.jar text.jar.orig && ! cmp -s outside.jar a/out/t.jar; then
    ok "a file named .jar that is not an archive, and an archive elsewhere, are left as they are"
else
    bad "a non-archive or an archive outside was changed"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
