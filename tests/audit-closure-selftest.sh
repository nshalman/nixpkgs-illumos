#!/usr/bin/env bash
# Check that tests/audit-closure.sh catches what it claims to: build objects with known defects, add them to the
# store, and require the audit to FAIL with the matching check name. Needs a C compiler (CC, default gcc) that links
# with the illumos ld, and a writable store.
#
#   needed    a library without an SONAME, linked by relative path: the illumos ld records that path in NEEDED
#   resolve   the same object: nothing at run time will find "sub/libnosoname.so"
#   outside   an executable with a RUNPATH directory outside the store, as a build directory left in a RUNPATH would be
set -u
here=$(cd "$(dirname "$0")" && pwd); CC=${CC:-gcc}; NS=${NIX_STORE_CMD:-nix-store}
tmp=$(mktemp -d); trap 'cd /; rm -rf "$tmp"' EXIT
mkdir -p $tmp/fixture/bin $tmp/fixture/sub; cd $tmp/fixture || exit 2
echo 'int nosoname(void){return 1;}' > $tmp/lib.c
echo 'int nosoname(void); int main(void){return nosoname();}' > $tmp/main.c
$CC -shared -fPIC -o sub/libnosoname.so $tmp/lib.c || exit 2
$CC -o bin/uses-path $tmp/main.c sub/libnosoname.so || exit 2
$CC -o bin/runpath-outside -Wl,-R/var/tmp/not-the-store $tmp/main.c sub/libnosoname.so || exit 2
p=$($NS --add $tmp/fixture) || exit 2
out=$(bash $here/audit-closure.sh "$p" 2>&1); rc=$?
fail=0
expect() { if echo "$out" | grep -q "^FAIL $1:"; then echo "ok   audit reports $1"; else echo "FAIL audit did not report $1"; fail=1; fi; }
[ $rc -ne 0 ] && echo "ok   audit exits non-zero" || { echo "FAIL audit exited 0 on a defective closure"; fail=1; }
expect needed
expect resolve
expect outside
[ $fail -eq 0 ] && echo "SELFTEST: PASS" || { echo "$out" | sed 's/^/    /'; echo "SELFTEST: FAIL"; exit 1; }
