#!/usr/bin/env bash
#
# boot-vm's parts that run without root and bhyve: boot-vm.exp driving tests/boot-vm-fake.sh, a stand-in for the VM's
# console (the console logged; a pattern found, not found in time, or bhyve exiting).
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

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
