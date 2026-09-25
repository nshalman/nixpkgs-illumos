#!/usr/bin/env bash
#
# Build a zone image with zone/image.nix and zone/make-joyent-image, receive its stream into a scratch dataset and
# check what a zone booted from it would find, without booting one:
#
#   1. The inputs build, the script makes a stream and a manifest whose sha1 and size match the stream, and the
#      stream receives.
#   2. Modes: /etc/shadow 0400, /etc/svc/repository.db 0600, /tmp and /var/tmp 1777, /nix/store 1775 group 30000.
#      vmadm will provision a joyent-brand zone from it: /var/zoneinit/zoneinit.json declares
#      features.var_svc_provisioning (checkDatasetProvisionable in /usr/vm/node_modules/VM.js; without it,
#      "provisioning dataset ... with brand joyent is not supported").
#   3. In a chroot of the received root, with /usr, /lib, /sbin, /dev and /proc lofs-mounted from this zone as the
#      brand mounts them from the global zone:
#      - root's shell is the system profile's bash, and nixbld has the 32 build users as members;
#      - a login shell finds nix through /etc/profile;
#      - Nix's database knows the whole closure (`nix-store --verify`, the profile's requisites);
#      - the SMF repository is the seed (26 services);
#      - sshd accepts /etc/ssh/sshd_config (`sshd -t`, with host keys made in the copy);
#      - every symbolic link under /etc and /var resolves.
#   4. /etc/nixos/system.nix evaluates to the system profile the image ships, so a first `illumos-rebuild switch`
#      changes nothing. It fetches what /etc/nixos/nixpkgs-illumos.nix names, so this holds only while that
#      published commit's system is the same as this checkout's.
#
# Runs as root on a zone with a delegated dataset; creates and destroys children of PARENT-DATASET only.
#
# usage: zone-image.sh PKGS-FILE PARENT-DATASET

set -uo pipefail

pkgsFile=${1:?usage: $0 PKGS-FILE PARENT-DATASET}
parent=${2:?usage: $0 PKGS-FILE PARENT-DATASET}
top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
recv=""
mounts=()

cleanup() {
	local i
	for ((i = ${#mounts[@]} - 1; i >= 0; i--)); do umount "${mounts[i]}" 2>/dev/null; done
	[ -n "$recv" ] && zfs destroy -r "$recv" 2>/dev/null
	rm -rf "$tmp"
}
trap cleanup EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }
finish() { echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit; }

# --- 1. build, stream, manifest, receive -------------------------------------------------------------------

if inputs=$(nix-build --no-out-link -E "import $top/zone/image.nix { pkgs = import $pkgsFile; }" 2>"$tmp/build.log"); then
	ok "zone/image.nix builds ($inputs)"
else
	bad "zone/image.nix does not build"; tail -20 "$tmp/build.log"; finish
fi

if "$top/zone/make-joyent-image" --parent-dataset "$parent" --inputs "$inputs" --name nix-zone-test \
	--version 0.0.0 --out-dir "$tmp/out" >"$tmp/make.log" 2>&1; then
	ok "make-joyent-image made an image"
else
	bad "make-joyent-image failed"; tail -20 "$tmp/make.log"; finish
fi
stream=$(ls "$tmp"/out/*.zfs.gz) manifest=$(ls "$tmp"/out/*.imgmanifest)
msha1=$(nix eval --raw --impure --expr "(builtins.head (builtins.fromJSON (builtins.readFile $manifest)).files).sha1")
msize=$(nix eval --raw --impure --expr "toString (builtins.head (builtins.fromJSON (builtins.readFile $manifest)).files).size")
if [ "$msha1" = "$(digest -a sha1 "$stream")" ] && [ "$msize" = "$(wc -c <"$stream" | tr -d ' ')" ]; then
	ok "the manifest's sha1 and size are the stream's ($msize bytes)"
else
	bad "manifest sha1/size ($msha1, $msize) do not match the stream"
fi

recv="$parent/zone-image-test-$$"
if gzip -dc "$stream" | zfs receive "$recv" 2>"$tmp/recv.log"; then
	ok "the stream receives into $recv"
else
	bad "zfs receive failed"; cat "$tmp/recv.log"; recv=""; finish
fi
R="$(zfs get -H -o value mountpoint "$recv")/root"

# --- 2. modes, and what vmadm checks -------------------------------------------------------------------------

zi="$R/var/zoneinit/zoneinit.json"
if [ -f "$zi" ] && [ "$(nix eval --impure --expr "(builtins.fromJSON (builtins.readFile $zi)).features.var_svc_provisioning or false" 2>/dev/null)" = true ]; then
	ok "zoneinit.json declares features.var_svc_provisioning, as vmadm requires of a joyent-brand image"
else
	bad "no /var/zoneinit/zoneinit.json with features.var_svc_provisioning: vmadm will not provision from the image"
fi

mode() { stat -c '%a %g' "$R/$1"; }
for check in "etc/shadow 400 0" "etc/svc/repository.db 600 0" "tmp 1777 0" "var/tmp 1777 0" "nix/store 1775 30000"; do
	set -- $check
	if [ "$(mode "$1")" = "$2 $3" ]; then ok "/$1 is mode $2, group $3"; else bad "/$1 is $(mode "$1"), want $2 $3"; fi
done

# --- 3. in a chroot ----------------------------------------------------------------------------------------

for m in usr lib sbin dev proc; do
	if mount -F lofs -o ro "/$m" "$R/$m" 2>"$tmp/mount.log"; then mounts+=("$R/$m"); else bad "lofs /$m"; cat "$tmp/mount.log"; finish; fi
done
in_root() { chroot "$R" /usr/bin/env -i PATH=/usr/bin:/usr/sbin HOME=/root "$@"; }

if [ "$(in_root /usr/bin/getent passwd root | cut -d: -f7)" = /nix/var/nix/profiles/default/bin/bash ] &&
	in_root /nix/var/nix/profiles/default/bin/bash -c true; then
	ok "root's shell is the profile's bash, and it runs"
else
	bad "root's shell: $(in_root /usr/bin/getent passwd root)"
fi
n=$(in_root /usr/bin/getent group nixbld | cut -d: -f4 | tr ',' '\n' | grep -c '^nixbld')
if [ "$n" = 32 ]; then ok "nixbld lists 32 members"; else bad "nixbld lists $n members"; fi

if out=$(in_root /nix/var/nix/profiles/default/bin/bash -lc 'command -v nix && nix --version' 2>&1) &&
	echo "$out" | grep -q '^nix (Nix) '; then
	ok "a login shell finds nix ($(echo "$out" | tail -1))"
else
	bad "a login shell does not find nix: $out"
fi

if in_root /nix/var/nix/profiles/default/bin/nix-store --verify >"$tmp/verify.log" 2>&1; then
	ok "nix-store --verify"
else
	bad "nix-store --verify"; tail -5 "$tmp/verify.log"
fi
system=$(readlink "$inputs/system")
nreq=$(in_root /nix/var/nix/profiles/default/bin/nix-store -q --requisites "$system" 2>/dev/null | wc -l | tr -d ' ')
if [ "$nreq" = "$(wc -l <"$inputs/store-paths" | tr -d ' ')" ]; then
	ok "the database knows the profile's $nreq requisites"
else
	bad "the database knows $nreq requisites of the profile, the closure has $(wc -l <"$inputs/store-paths")"
fi

cp "$R/etc/svc/repository.db" "$tmp/repo.db"
nsvc=$(SVCCFG_REPOSITORY="$tmp/repo.db" SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd /usr/sbin/svccfg list | wc -l | tr -d ' ')
if [ "$nsvc" = 26 ]; then ok "the SMF repository is the seed (26 services)"; else bad "the SMF repository has $nsvc services"; fi

for t in rsa ecdsa ed25519; do
	in_root /usr/bin/ssh-keygen -q -t $t -N '' -f /var/ssh/ssh_host_${t}_key >/dev/null 2>&1
done
if in_root /usr/lib/ssh/sshd -t -f /etc/ssh/sshd_config >"$tmp/sshd.log" 2>&1; then
	ok "sshd -t accepts /etc/ssh/sshd_config$( [ -s "$tmp/sshd.log" ] && echo " (said: $(head -1 "$tmp/sshd.log"))")"
else
	bad "sshd -t"; cat "$tmp/sshd.log"
fi

broken=$(in_root /usr/bin/find /etc /var -type l ! -exec /usr/bin/test -e {} \; -print 2>/dev/null)
if [ -z "$broken" ]; then ok "every link under /etc and /var resolves"; else bad "links that do not resolve: $broken"; fi

# --- 4. /etc/nixos evaluates to the shipped system ------------------------------------------------------------

want=$(nix-store -q --deriver "$system")
got=$(cd "$R/etc/nixos" && nix-instantiate ./system.nix 2>"$tmp/eval.log")
if [ "$got" = "$want" ]; then
	ok "/etc/nixos/system.nix evaluates to the shipped system"
else
	bad "/etc/nixos/system.nix evaluates to ${got:-nothing}, the image ships $want's output"; tail -3 "$tmp/eval.log"
fi

finish
