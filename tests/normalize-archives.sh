#!/usr/bin/env bash
#
# ../pkgs/smartos-strap/normalize-archives.pl on archives the platform's ar makes: the same two objects (one with a
# name too long for the member header, which goes to the long-name table) archived twice, with other modification
# times and owners, are different archives; once normalized (SOURCE_DATE_EPOCH given) they are the same file, whose
# members ar lists with that date and owner 0/0, extract to what was put in, and still link. A file named .a that is
# not an archive is left as it is, as is an archive outside the directory given.
#
# usage: normalize-archives.sh   (as root, for chown; on illumos, for /usr/bin/ar; perl on PATH; CC, default gcc)

set -uo pipefail

top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
# leave $tmp first, as illumos' rm does not remove the current directory
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

cc=${CC:-gcc}
cd "$tmp"
echo 'int one(void) { return 1; }' >one.c
echo 'int a_member_with_a_long_name(void) { return 2; }' >a_member_with_a_long_name.c
echo 'int one(void); int a_member_with_a_long_name(void); int main(void) { return one() + a_member_with_a_long_name() - 3; }' >main.c
"$cc" -c one.c a_member_with_a_long_name.c main.c || { bad "cannot compile"; exit 1; }

for v in a b; do
    mkdir -p $v/lib
    cp one.o a_member_with_a_long_name.o $v/
done
touch -t 202001010000 a/*.o
touch -t 202602030405 b/*.o
chown 12345:54321 b/*.o
(cd a && /usr/bin/ar -cr lib/libt.a one.o a_member_with_a_long_name.o)
sleep 1
(cd b && /usr/bin/ar -cr lib/libt.a one.o a_member_with_a_long_name.o)
echo 'not an archive' >a/lib/text.a
cp a/lib/text.a text.a.orig
cp b/lib/libt.a outside.a

if cmp -s a/lib/libt.a b/lib/libt.a; then
    bad "the two archives are the same before normalizing: the test shows nothing"
else
    ok "the two archives differ before normalizing"
fi

export SOURCE_DATE_EPOCH=315532800
if perl "$top/pkgs/smartos-strap/normalize-archives.pl" a && perl "$top/pkgs/smartos-strap/normalize-archives.pl" b; then
    ok "normalize-archives.pl runs"
else
    bad "normalize-archives.pl fails"
fi

if cmp -s a/lib/libt.a b/lib/libt.a; then
    ok "the same archive once normalized"
else
    bad "the archives still differ"; cmp -l a/lib/libt.a b/lib/libt.a | head -5 | sed 's/^/    /'
fi

/usr/bin/ar -tv a/lib/libt.a >tv 2>&1
if [ "$(/usr/bin/ar -t a/lib/libt.a)" = "one.o
a_member_with_a_long_name.o" ] && [ "$(grep -c ' 0/ *0 .*Jan  1 00:00 1980 ' tv)" = 2 ]; then
    ok "ar lists both members, dated the epoch, owned by 0/0"
else
    bad "ar's listing"; sed 's/^/    /' tv
fi

mkdir x && (cd x && /usr/bin/ar -x ../a/lib/libt.a)
if cmp -s x/one.o one.o && cmp -s x/a_member_with_a_long_name.o a_member_with_a_long_name.o; then
    ok "the members extract to what was put in"
else
    bad "the members extracted differ"
fi

if "$cc" -o main main.c -La/lib -lt && ./main; then
    ok "a program links against it"
else
    bad "a program does not link against it"
fi

if cmp -s a/lib/text.a text.a.orig && ! cmp -s outside.a a/lib/libt.a; then
    ok "a file named .a that is not an archive, and an archive elsewhere, are left as they are"
else
    bad "a non-archive or an archive outside was changed"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
