#!/bin/bash
#
# vm-net [-i INDEX] up|down|args: a network of its own for a boot-vm VM, in this zone. up makes it (as far as it is not
# there yet), of temporary links, gone when the zone reboots: an etherstub, vmstubINDEX; this zone's VNIC on it,
# vmhostINDEX, at 10.99.INDEX.1/24; and the VM's VNIC, vmnetINDEX, MAC 2:8:20:0:INDEX:10, for boot-vm --nic. down
# removes them. args prints the boot properties for build-usb that give the VM the address 10.99.INDEX.2 on it, e.g.
#   vm-net up && build-usb -B noimport=true $(vm-net args) PLATFORM-DIR usb &&
#     boot-vm --nic vmnet0 --run 'ping 10.99.0.1' --password-file PLATFORM-DIR/root.password usb/*.usb.gz
# INDEX (0-9, default 0) keeps the networks of VMs run side by side apart. Nothing leaves the zone: no gateway, no
# NAT. up and down need root and the zone's sys_dl_config privilege (a builder zone's limit_priv
# default,sys_dl_config).

set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/sbin

usage() {
    echo "usage: $0 [-i INDEX] up|down|args" >&2
    exit 2
}
i=0
while getopts "i:" opt; do
    case $opt in
        i) i=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[[ $i =~ ^[0-9]$ ]] || usage
[ $# = 1 ] || usage

stub=vmstub$i host=vmhost$i guest=vmnet$i
mac=2:8:20:0:$i:10
exists() { dladm show-link "$1" >/dev/null 2>&1; }

case $1 in
    args)
        echo "-B admin_nic=$mac -B admin_ip=10.99.$i.2 -B admin_netmask=255.255.255.0"
        ;;
    up)
        exists $stub || dladm create-etherstub -t $stub
        exists $host || dladm create-vnic -t -l $stub -m 2:8:20:0:$i:1 $host
        ipadm show-addr $host/v4 >/dev/null 2>&1 || ipadm create-addr -t -T static -a 10.99.$i.1/24 $host/v4
        exists $guest || dladm create-vnic -t -l $stub -m $mac $guest
        echo "vm-net: $guest (MAC $mac) for the VM, on $stub with $host at 10.99.$i.1/24"
        ;;
    down)
        ! ipadm show-if $host >/dev/null 2>&1 || ipadm delete-ip $host
        ! exists $guest || dladm delete-vnic -t $guest
        ! exists $host || dladm delete-vnic -t $host
        ! exists $stub || dladm delete-etherstub -t $stub
        ;;
    *) usage ;;
esac
