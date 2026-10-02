#!/bin/bash
#
# uname-version UNIX VERSION: makes VERSION the version `uname -v` reports (and so sysinfo's Live Image, what follows
# its last "_") on a system booted from UNIX, a copy of the illumos kernel (platform/i86pc/kernel/amd64/unix),
# changed in place. The kernel's utsname (uts/common/os/vers.c) is initialised data: five fields of SYS_NMLN (257)
# bytes, sysname ("SunOS") first and version, the illumos build's VERSION (its GATE), fourth. VERSION, of 1 to 256
# bytes, replaces that field, zero-filled; nothing else in the file changes. Fails, the file unchanged, when UNIX has
# no such utsname.
#
# The image step sets the platform's version this way (as joyent_STAMP, smartos-live's build_illumos's GATE), so that
# a new build stamp does not rebuild illumos.

set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/sbin LC_ALL=C

nmln=257
usage() {
    echo "usage: $0 UNIX VERSION" >&2
    exit 2
}
[ $# = 2 ] && [ -f "$1" ] || usage
unix=$1 version=$2
if [ ${#version} -lt 1 ] || [ ${#version} -ge $nmln ]; then
    echo "$0: VERSION must be 1 to $((nmln - 1)) bytes" >&2
    exit 2
fi
fail() {
    echo "$0: $unix: $*" >&2
    exit 1
}

# utsname's address and size, from the symbol table
sym=$(elfdump -s -N .symtab "$unix" 2>/dev/null | awk '$NF == "utsname" && $4 == "OBJT" { print $2, $3 }')
[ "$(echo "$sym" | grep -c .)" = 1 ] || fail "no utsname"
read -r addr size <<<"$sym"
[ $((size)) = $((5 * nmln)) ] || fail "utsname is $((size)) bytes, not $((5 * nmln))"

# its offset in the file, from the section that holds its address (a kernel has more than one called .data, so by
# address, not by name); each section's address, size, offset and type
offset=
while read -r saddr ssize soffset stype; do
    if [ "$stype" = SHT_PROGBITS ] && [ $((addr)) -ge $((saddr)) ] && [ $((addr)) -lt $((saddr + ssize)) ]; then
        offset=$((soffset + addr - saddr))
    fi
done < <(elfdump -c "$unix" | awk '
    /sh_addr:/ { a = $2 }
    /sh_size:/ { s = $2; t = $5 }
    /sh_offset:/ { print a, s, $2, t }')
[ -n "$offset" ] || fail "no section holds utsname"

field() {
    dd if="$unix" bs=1 skip=$((offset + $1 * nmln)) count=$nmln 2>/dev/null | tr -d '\0'
}
[ "$(field 0)" = SunOS ] || fail "no utsname: its sysname is not SunOS"
old=$(field 3)

{
    printf '%s' "$version"
    dd if=/dev/zero bs=1 count=$((nmln - ${#version})) 2>/dev/null
} | dd of="$unix" bs=1 seek=$((offset + 3 * nmln)) conv=notrunc 2>/dev/null
[ "$(field 3)" = "$version" ] || fail "the version field reads '$(field 3)', not '$version'"
echo "uname-version: $unix: $old -> $version"
