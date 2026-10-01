#!/bin/bash
#
# boot-vm [-n NAME] [-m MEMORY] [-c CPUS] [--expect PATTERN [--timeout SECONDS]] IMAGE: boots IMAGE (a USB image
# from build-usb, gzipped or not) in a bhyve VM with UEFI firmware (the platform's), its first serial port (ttya) on
# this terminal: the console of an image made with build-usb's default -c ttya. Needs root and bhyve (a builder- or
# bhyve-brand zone, or the global zone). The VM is destroyed when bhyve exits, or when this script does.
#
# With --expect, the VM runs under expect, its console logged (NAME.console, in the current directory) instead,
# until PATTERN (a regular expression) appears on it (exit 0), SECONDS pass (default 600; exit 1) or bhyve exits
# (exit 2), then is destroyed: a boot test, e.g. --expect 'login:' for an image made with -B noimport=true.

set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/sbin

name=boot-vm-$$ memory=4G cpus=2 expect= timeout=600
usage() {
    echo "usage: $0 [-n NAME] [-m MEMORY] [-c CPUS] [--expect PATTERN [--timeout SECONDS]] IMAGE" >&2
    exit 2
}
while [ $# -gt 1 ]; do
    case $1 in
        -n) name=$2; shift 2 ;;
        -m) memory=$2; shift 2 ;;
        -c) cpus=$2; shift 2 ;;
        --expect) expect=$2; shift 2 ;;
        --timeout) timeout=$2; shift 2 ;;
        *) usage ;;
    esac
done
image=${1:-}
[ -f "$image" ] || usage

disk=$image
case $image in
    *.gz)
        disk=$(mktemp -p /var/tmp boot-vm.XXXXXX)
        @pigz@ -dc "$image" >"$disk"
        ;;
esac

cleanup() {
    bhyvectl --vm="$name" --destroy >/dev/null 2>&1 || true
    [ "$disk" = "$image" ] || rm -f "$disk"
}
trap cleanup EXIT

vm=(bhyve -H -w -c "$cpus" -m "$memory"
    -s 0,hostbridge -s 31,lpc
    -l bootrom,/usr/share/bhyve/uefi-rom.bin
    -l com1,stdio
    -s 4,ahci-hd,"$disk"
    "$name")


if [ -z "$expect" ]; then
    echo "boot-vm: $name, console here (ttya); the VM is destroyed when it halts or this script ends" >&2
    "${vm[@]}"
    exit
fi

# under expect, on a pseudo-terminal (./boot-vm.exp)
log=$PWD/$name.console
start=$SECONDS
rc=0
BOOTVM_EXPECT=$expect BOOTVM_TIMEOUT=$timeout BOOTVM_LOG=$log @expect@ -f @bootVmExp@ -- "${vm[@]}" || rc=$?
case $rc in
    0) echo "boot-vm: '$expect' on $name's console after $((SECONDS - start))s (log: $log)" ;;
    1) echo "boot-vm: no '$expect' on $name's console in ${timeout}s (log: $log)" >&2 ;;
    2) echo "boot-vm: $name's bhyve exited (log: $log)" >&2 ;;
    *) echo "boot-vm: expect failed ($rc)" >&2 ;;
esac
exit $rc
