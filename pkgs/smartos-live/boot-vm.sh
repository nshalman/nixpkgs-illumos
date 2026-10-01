#!/bin/bash
#
# boot-vm [-n NAME] [-m MEMORY] [-c CPUS] [--nic LINK ...] [--expect PATTERN | --run COMMAND ... --password-file FILE]
#         [--timeout SECONDS] [--dry-run] IMAGE:
# boots IMAGE (a USB image from build-usb, gzipped or not) in a bhyve VM with UEFI firmware (the platform's), its first
# serial port (ttya) on this terminal: the console of an image made with build-usb's default -c ttya. Each --nic is a
# virtio NIC on LINK (a VNIC of this zone, e.g. vm-net's vmnet0). Needs root and bhyve (a builder- or bhyve-brand
# zone, or the global zone). The VM is destroyed when bhyve exits, or when this script does. --dry-run prints the bhyve
# command instead.
#
# With --expect, the VM runs under expect, its console logged (NAME.console, in the current directory) instead,
# until PATTERN (a regular expression) appears on it (exit 0), SECONDS pass (default 600; exit 1) or bhyve exits
# (exit 2), then is destroyed: a boot test, e.g. --expect 'login:' for an image made with -B noimport=true.
#
# With --run, likewise until the login prompt, then logs in as root with the password in FILE (build-image's
# OUTPUT/platform-*/root.password; exit 3 if refused) and runs each COMMAND (a command line for root's shell) in turn,
# their output on ours, until one fails (exit 4); SECONDS is then each step's. Messages the system writes to its
# console while a command runs come with the command's output.

set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/sbin

name=boot-vm-$$ memory=4G cpus=2 expect= timeout=600 password= dry=
nics=() commands=()
usage() {
    echo "usage: $0 [-n NAME] [-m MEMORY] [-c CPUS] [--nic LINK ...]" \
        "[--expect PATTERN | --run COMMAND ... --password-file FILE] [--timeout SECONDS] [--dry-run] IMAGE" >&2
    exit 2
}
while [ $# -gt 1 ]; do
    case $1 in
        -n) name=$2; shift 2 ;;
        -m) memory=$2; shift 2 ;;
        -c) cpus=$2; shift 2 ;;
        --nic) nics+=("$2"); shift 2 ;;
        --expect) expect=$2; shift 2 ;;
        --run) commands+=("$2"); shift 2 ;;
        --password-file) password=$2; shift 2 ;;
        --timeout) timeout=$2; shift 2 ;;
        --dry-run) dry=1; shift ;;
        *) usage ;;
    esac
done
image=${1:-}
[ -f "$image" ] || usage
if [ ${#commands[@]} -gt 0 ]; then
    [ -z "$expect" ] || { echo "$0: --expect or --run, not both" >&2; exit 2; }
    [ -f "$password" ] || { echo "$0: --run wants --password-file FILE, root's password" >&2; exit 2; }
fi

# make_vm DISK: the bhyve command, in vm
make_vm() {
    local disk=$1 slot=5 nic
    vm=(bhyve -H -w -c "$cpus" -m "$memory"
        -s 0,hostbridge -s 31,lpc
        -l bootrom,/usr/share/bhyve/uefi-rom.bin
        -l com1,stdio
        -s 4,ahci-hd,"$disk")
    for nic in ${nics[@]+"${nics[@]}"}; do
        vm+=(-s $slot,virtio-net-viona,"$nic")
        slot=$((slot + 1))
    done
    vm+=("$name")
}

if [ -n "$dry" ]; then
    make_vm "$image"
    echo "${vm[@]}"
    exit
fi

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
    [ -z "${list:-}" ] || rm -f "$list"
}
trap cleanup EXIT

make_vm "$disk"

if [ -z "$expect" ] && [ ${#commands[@]} = 0 ]; then
    echo "boot-vm: $name, console here (ttya); the VM is destroyed when it halts or this script ends" >&2
    "${vm[@]}"
    exit
fi

# under expect, on a pseudo-terminal (./boot-vm.exp)
log=$PWD/$name.console
env=(BOOTVM_EXPECT="${expect:-login: }" BOOTVM_TIMEOUT="$timeout" BOOTVM_LOG="$log")
if [ ${#commands[@]} -gt 0 ]; then
    list=$(mktemp)
    printf '%s\n' "${commands[@]}" >"$list"
    env+=(BOOTVM_COMMANDS="$list" BOOTVM_PASSWORD_FILE="$password")
fi
start=$SECONDS
rc=0
env "${env[@]}" @expect@ -f @bootVmExp@ -- "${vm[@]}" || rc=$?
case $rc in
    0) if [ -n "$expect" ]; then
           echo "boot-vm: '$expect' on $name's console after $((SECONDS - start))s (log: $log)" >&2
       else
           echo "boot-vm: ${#commands[@]} commands ran on $name in $((SECONDS - start))s (log: $log)" >&2
       fi ;;
    1) echo "boot-vm: $name's console: nothing expected in ${timeout}s (log: $log)" >&2 ;;
    2) echo "boot-vm: $name's bhyve exited (log: $log)" >&2 ;;
    3|4) echo "boot-vm: log: $log" >&2 ;;
    *) echo "boot-vm: expect failed ($rc)" >&2 ;;
esac
exit $rc
