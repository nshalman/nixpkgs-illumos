#!/bin/bash
#
# boot-vm [--vmm bhyve|rshyve] [-n NAME] [-m MEMORY] [-c CPUS] [--nic LINK ...] [--disk FILE ...]
#         [--expect PATTERN | --run COMMAND ... --password-file FILE] [--timeout SECONDS] [--dry-run] IMAGE:
# boots IMAGE (a USB image from build-usb, gzipped or not) in a bhyve VM with UEFI firmware (the platform's), its first
# serial port (ttya) on this terminal: the console of an image made with build-usb's default -c ttya. Each --nic is a
# virtio NIC on LINK (a VNIC of this zone, e.g. vm-net's vmnet0); each --disk a virtio disk on FILE (e.g. one from
# `mkfile -n 20g`, for a zones pool), kept as the VM leaves it. Needs root and bhyve (a builder- or bhyve-brand
# zone, or the global zone). The VM is destroyed when bhyve exits, or when this script does. --dry-run prints the bhyve
# command instead.
#
# --vmm rshyve runs it under rshyve (rust-bhyve, the overlay's rust-bhyve package), found on the caller's PATH, in
# place of the platform's bhyve: its disks on NVMe and its COM2 on nothing (see make_vm).
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
callerPath=$PATH
export PATH=/usr/bin:/usr/sbin:/sbin

name=boot-vm-$$ memory=4G cpus=2 expect= timeout=600 password= dry= vmm=bhyve
nics=() disks=() commands=()
usage() {
    echo "usage: $0 [--vmm bhyve|rshyve] [-n NAME] [-m MEMORY] [-c CPUS] [--nic LINK ...] [--disk FILE ...]" \
        "[--expect PATTERN | --run COMMAND ... --password-file FILE] [--timeout SECONDS] [--dry-run] IMAGE" >&2
    exit 2
}
while [ $# -gt 1 ]; do
    case $1 in
        --vmm) vmm=$2; shift 2 ;;
        -n) name=$2; shift 2 ;;
        -m) memory=$2; shift 2 ;;
        -c) cpus=$2; shift 2 ;;
        --nic) nics+=("$2"); shift 2 ;;
        --disk) disks+=("$2"); shift 2 ;;
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
case $vmm in
    bhyve) ;;
    rshyve)
        rshyve=$(PATH=$callerPath; command -v rshyve) ||
            { echo "$0: --vmm rshyve: no rshyve on PATH ($callerPath)" >&2; exit 2; } ;;
    *) usage ;;
esac
for d in ${disks[@]+"${disks[@]}"}; do
    [ -f "$d" ] || { echo "$0: --disk $d: no such file" >&2; exit 2; }
done
if [ ${#commands[@]} -gt 0 ]; then
    [ -z "$expect" ] || { echo "$0: --expect or --run, not both" >&2; exit 2; }
    [ -f "$password" ] || { echo "$0: --run wants --password-file FILE, root's password" >&2; exit 2; }
fi

# make_vm DISK: the bhyve (or rshyve) command, in vm
make_vm() {
    # bhyve gives a disk on a file the file system's block size (st_blksize; ZFS's recordsize, 128K) for its physical
    # sector size, too big for a pool's ashift ("one or more vdevs require an invalid ashift"): 4K, as a disk's
    local disk=$1 slot=5 nic d dev=virtio-blk opts=,sectorsize=512/4096
    case $vmm in
        bhyve) vm=(bhyve -H -w) ;;
        rshyve) vm=("$rshyve" -H) ;;
    esac
    vm+=(-c "$cpus" -m "$memory"
        -s 0,hostbridge -s 31,lpc
        -l bootrom,/usr/share/bhyve/uefi-rom.bin
        -l com1,stdio)
    case $vmm in
        bhyve) vm+=(-s 4,ahci-hd,"$disk") ;;
        # rshyve has no AHCI disk, and its COM2 is a metadata agent unless one is named: the image's loader writes its
        # console to COM2 too (ttyb), and would take the agent's answers ("invalid command") for keys
        rshyve) vm+=(-l com2,/dev/null -s 4,nvme,"$disk"); dev=nvme opts= ;;
    esac
    for nic in ${nics[@]+"${nics[@]}"}; do
        vm+=(-s $slot,virtio-net-viona,"$nic")
        slot=$((slot + 1))
    done
    # the --disk disks from slot 10, after the NICs
    slot=10
    for d in ${disks[@]+"${disks[@]}"}; do
        vm+=(-s $slot,$dev,"$d$opts")
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
    [ -z "${tty:-}" ] || stty "$tty"
}
trap cleanup EXIT

make_vm "$disk"
# bhyve makes the terminal its console is on raw; rshyve leaves it as it finds it, and a cooked one echoes what is
# typed, takes ^C for itself and turns the guest's \r\n into \r\r\n (which --run's prompts do not match). Make it raw
# for rshyve, and put ours back afterwards.
if [ "$vmm" = rshyve ]; then
    vm=(sh -c 'stty raw -echo && exec "$@"' rshyve "${vm[@]}")
    if [ -t 0 ]; then
        tty=$(stty -g)
    fi
fi

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
    2) echo "boot-vm: $name's $vmm exited (log: $log)" >&2 ;;
    3|4) echo "boot-vm: log: $log" >&2 ;;
    *) echo "boot-vm: expect failed ($rc)" >&2 ;;
esac
exit $rc
