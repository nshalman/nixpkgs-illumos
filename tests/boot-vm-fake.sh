#!/bin/bash
#
# A stand-in for a SmartOS VM's console, for tests/boot-vm.sh: boot messages, a login prompt, a password prompt
# (FAKE_PASSWORD's the right one; a wrong one gets "Login incorrect"), then a root shell's prompt, running each line it
# reads. With FAKE_HALT it halts after the boot messages instead (bhyve exiting).

echo "SunOS Release 5.11 Version fake 64-bit"
echo "fake console output"
[ -n "${FAKE_HALT:-}" ] && exit 0
printf 'fake ttya login: '
read -r user
printf 'Password: '
read -r password
if [ "$user" != root ] || [ "$password" != "$FAKE_PASSWORD" ]; then
    echo "Login incorrect"
    sleep 60
    exit 1
fi
while printf '[root@fake ~]# ' && read -r line; do
    eval "$line"
done
