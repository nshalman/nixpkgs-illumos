#!/usr/bin/env bash
#
# boot-vm's parts that run without root and bhyve: boot-vm.exp driving tests/boot-vm-fake.sh, a stand-in for the VM's
# console (the console logged; a pattern found, not found in time, or bhyve exiting; logging in with the password
# file and running commands, their output on ours, a wrong password and a failing command told apart), the bhyve
# command boot-vm makes (--dry-run), its arguments, and vm-net's boot properties.
#
# usage: boot-vm.sh TOOLS-BIN EXPECT BOOT-VM-EXP FAKE-VM (TOOLS-BIN: builderTools' bin; EXPECT: an expect binary)

set -uo pipefail

tools=$1 expect=$2 exp=$3 fake=$4
tmp=$(mktemp -d)
trap 'cd / && rm -rf "$tmp"' EXIT
cd "$tmp"

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }
show() { for f in "$@"; do echo "    -- $f:"; sed 's/^/    /' "$f"; done; }

echo secret >password
export FAKE_PASSWORD=secret
# run NAME PATTERN TIMEOUT [COMMAND...]: boot-vm.exp on the fake VM, as boot-vm runs it, the commands (if any) after
# logging in; its status in NAME.rc, our output in NAME.out and NAME.err, the console in NAME.console
run() {
    local name=$1 pattern=$2 timeout=$3 rc=0
    shift 3
    local env=(BOOTVM_EXPECT="$pattern" BOOTVM_TIMEOUT="$timeout" BOOTVM_LOG="$tmp/$name.console")
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" >"$name.commands"
        env+=(BOOTVM_COMMANDS="$tmp/$name.commands" BOOTVM_PASSWORD_FILE="$tmp/password")
    fi
    env "${env[@]}" "$expect" -f "$exp" -- bash "$fake" >"$name.out" 2>"$name.err" || rc=$?
    echo $rc >"$name.rc"
}

run boot 'login: ' 30
if [ "$(cat boot.rc)" = 0 ] && grep -q '^fake console output' boot.console; then
    ok "a pattern on the console: exit 0, the console logged"
else
    bad "a pattern on the console (rc $(cat boot.rc))"; show boot.console boot.err
fi

run timeout 'never' 2
FAKE_HALT=1 run halt 'login: ' 30
if [ "$(cat timeout.rc)" = 1 ] && [ "$(cat halt.rc)" = 2 ]; then
    ok "no pattern in time: exit 1; bhyve exiting: exit 2"
else
    bad "timeout $(cat timeout.rc), halt $(cat halt.rc)"
fi

run commands 'login: ' 30 'echo hello' 'echo two; echo "lines"' 'uname -s >/dev/null'
printf '%s\n' hello two lines >commands.want
if [ "$(cat commands.rc)" = 0 ] && cmp -s commands.want commands.out; then
    ok "logging in and running commands: each one's output on ours, nothing else"
else
    bad "commands (rc $(cat commands.rc))"; show commands.out commands.err commands.console
fi

long=$(seq 1 3000 | tr '\n' ' ')
run long 'login: ' 30 'seq 1 3000 | tr "\n" " "; echo'
if [ "$(cat long.rc)" = 0 ] && [ "$(cat long.out)" = "$long" ]; then
    ok "a command's long output whole"
else
    bad "long output (rc $(cat long.rc), $(wc -c <long.out) bytes)"; show long.err
fi

run failing 'login: ' 30 'echo before' 'false' 'echo after'
if [ "$(cat failing.rc)" = 4 ] && [ "$(cat failing.out)" = before ] && grep -q "'false' exited 1" failing.err; then
    ok "a failing command: exit 4, the commands after it not run"
else
    bad "a failing command (rc $(cat failing.rc))"; show failing.out failing.err
fi

FAKE_PASSWORD=other run wrong 'login: ' 30 'echo hello'
if [ "$(cat wrong.rc)" = 3 ] && [ ! -s wrong.out ]; then
    ok "a wrong password: exit 3"
else
    bad "a wrong password (rc $(cat wrong.rc))"; show wrong.out wrong.err
fi

touch img.usb
if "$tools/boot-vm" --dry-run -n vm1 --nic vmnet0 --nic vmnet1 img.usb >dry.out 2>&1 &&
    grep -q -- "-s 4,ahci-hd,img.usb -s 5,virtio-net-viona,vmnet0 -s 6,virtio-net-viona,vmnet1 vm1$" dry.out; then
    ok "--dry-run: the bhyve command, with a virtio NIC on each --nic link"
else
    bad "--dry-run"; show dry.out
fi

if ! "$tools/boot-vm" --run 'echo hi' img.usb 2>norun.err && grep -q 'password-file' norun.err &&
    ! "$tools/boot-vm" --expect x --run 'echo hi' --password-file password img.usb 2>both.err && grep -q 'not both' both.err; then
    ok "--run wants --password-file, and not --expect"
else
    bad "--run's arguments"; show norun.err both.err
fi

if [ "$("$tools/vm-net" -i 3 args)" = "-B admin_nic=2:8:20:0:3:10 -B admin_ip=10.99.3.2 -B admin_netmask=255.255.255.0" ] &&
    [ "$("$tools/vm-net" args)" = "-B admin_nic=2:8:20:0:0:10 -B admin_ip=10.99.0.2 -B admin_netmask=255.255.255.0" ] &&
    ! "$tools/vm-net" -i 12 args 2>/dev/null && ! "$tools/vm-net" 2>/dev/null; then
    ok "vm-net args: the boot properties for network INDEX's VM; INDEX 0-9; a subcommand wanted"
else
    bad "vm-net args"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
