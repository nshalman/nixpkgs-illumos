#!/usr/bin/env bash
#
# Checks a zone after the Nix multi-user installer ran in it (`./install --daemon`): the daemon under SMF, the
# build users and group, the store, a login shell that finds Nix, a build by an unprivileged user through the
# daemon, and, given a cache and the stdenv's store path, that the stdenv comes from the cache without building.
# Runs as root on the zone; creates the users `nixtest` (home from /etc/skel) and `nixplain` (no startup files).
#
# usage: installed-zone.sh [CACHE-URL STDENV-PATH]

set -uo pipefail

cache=${1:-} stdenv=${2:-}
pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }
check() { if eval "$2" > /dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

profile=/nix/var/nix/profiles/default

check "nix-daemon is online under SMF" '[ "$(svcs -H -o state svc:/application/nix-daemon:default)" = online ]'
check "the daemon's process runs the default profile's nix" \
    'svcs -H -p svc:/application/nix-daemon:default | grep -q " nix$"'
check "the daemon socket exists" '[ -S /nix/var/nix/daemon-socket/socket ]'

check "group nixbld is gid 30000" '[ "$(getent group nixbld | cut -d: -f3)" = 30000 ]'
users_ok=0
for i in $(seq 1 32); do
    IFS=: read -r name _ uid gid comment home shell <<< "$(getent passwd nixbld$i)"
    if [ "$name" = nixbld$i ] && [ "$uid" = $((30000 + i)) ] && [ "$gid" = 30000 ] && [ "$home" = /var/empty ] \
        && [ "$shell" = /usr/bin/false ] && [ "$comment" = "Nix build user $i" ]; then
        users_ok=$((users_ok + 1))
    fi
done
[ $users_ok -eq 32 ] && ok "32 build users nixbld1..32: uid 30001.., gid 30000, /var/empty, /usr/bin/false" \
    || bad "only $users_ok of 32 build users as expected"
check "build users cannot log in (locked passwords)" \
    '[ "$(grep -c "^nixbld[0-9]*:\*LK\*:" /etc/shadow)" = 32 ]'

check "/nix/store is root:nixbld 1775" '[ "$(stat -c "%U:%G %a" /nix/store)" = "root:nixbld 1775" ]'
check "/etc/nix/nix.conf names the build group" 'grep -qx "build-users-group = nixbld" /etc/nix/nix.conf'
check "the store verifies" "$profile/bin/nix-store --verify --check-contents"

# Login shells (bash -l in a clean environment, as a login gives one; `su - USER -c` reads no startup files and
# takes PATH from /etc/default/su). /etc/profile, where the installer puts Nix, must give a user without startup
# files of their own Nix on PATH. A ~/.profile that sets PATH (the pkgsrc images' /etc/skel/.profile, and
# root's) discards it; the manual tells such users to add Nix's directories after that line.
login() { su "$1" -c "env -i HOME=$(getent passwd "$1" | cut -d: -f6) LOGNAME=$1 USER=$1 /usr/bin/bash -lc '$2'"; }
nixpath() { [ "$(readlink -f "$(login "$1" "command -v nix" 2>/dev/null)")" = "$(readlink -f $profile/bin/nix)" ]; }
id nixplain > /dev/null 2>&1 || { useradd -d /var/tmp/nixplain -s /usr/bin/bash nixplain && mkdir -p /var/tmp/nixplain && chown nixplain /var/tmp/nixplain; } > /dev/null 2>&1
nixpath nixplain && ok "a login shell of a user without startup files finds nix" || bad "a login shell of a user without startup files does not find nix"
id nixtest > /dev/null 2>&1 || useradd -m -d /home/nixtest -s /usr/bin/bash nixtest > /dev/null 2>&1
if grep -q "^PATH=" /home/nixtest/.profile 2>/dev/null; then
    nixpath nixtest && bad "nixtest's ~/.profile sets PATH, yet its login shell finds nix: the manual's note is wrong" \
        || ok "nixtest's ~/.profile sets PATH and its login shell does not find nix, as the manual says"
    cp -p /home/nixtest/.profile /tmp/nixtest.profile
    awk '{ print } /^PATH=/ { print "PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH" }' /tmp/nixtest.profile > /home/nixtest/.profile
    nixpath nixtest && ok "with the manual's line after PATH= in ~/.profile, the login shell finds nix" \
        || bad "the manual's line does not give the login shell nix"
    cp -p /tmp/nixtest.profile /home/nixtest/.profile
fi
check "nix talks to the daemon" "$profile/bin/nix-store --store daemon -q --hash $profile"

tag=$(date +%s)
cat > /tmp/nonroot-build.nix <<EOF
derivation {
  name = "installer-check-$tag";
  system = builtins.currentSystem;
  builder = "/usr/bin/sh";
  args = [ "-c" "/usr/bin/id > \$out" ];
}
EOF
chmod 644 /tmp/nonroot-build.nix
if out=$(su - nixtest -c "$profile/bin/nix-build --no-out-link /tmp/nonroot-build.nix" 2> /tmp/nonroot-build.err); then
    grep -q "^uid=3000[0-9]*(nixbld[0-9]*)" "$out" && ok "an unprivileged user builds through the daemon, as a build user: $(cat "$out")" \
        || bad "unprivileged build ran as: $(cat "$out")"
else
    bad "unprivileged build failed"; sed 's/^/    /' /tmp/nonroot-build.err
fi

if [ -n "$cache" ]; then
    if $profile/bin/nix-store -r "$stdenv" --option substituters "$cache?trusted=true" --option max-jobs 0 \
            > /tmp/stdenv-subst.log 2>&1; then
        ok "the stdenv substitutes from $cache without building"
    else
        bad "the stdenv did not substitute from $cache"; tail -5 /tmp/stdenv-subst.log | sed 's/^/    /'
    fi
fi

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
