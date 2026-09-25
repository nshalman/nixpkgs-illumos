#!/usr/bin/env bash
#
# Test zone/smf-seed.nix, the seed SMF repository of a zone image:
#
#   1. It builds. The build itself compares `svccfg archive` of the
#      repository with zone/smf-seed-archive.xml and fails on any
#      difference, so a host svccfg that configures services differently
#      cannot slip through.
#   2. `svccfg archive` of the output is zone/smf-seed-archive.xml.
#   3. It holds exactly the services of the gate's non-global seed list
#      (usr/src/cmd/svc/seed/Makefile), less network/netcfg (not on
#      SmartOS), plus system/early-manifest-import and smartdc/mdata
#      (vmadm sets properties of its instances before the first boot),
#      and sendmail's network/smtp and network/sendmail-client.
#   4. Every manifest it records is under its installed path, not the
#      build directory or the store: /lib/svc/manifest, and for sendmail's
#      two, which the platform does not ship, /var/svc/manifest/network.
#      That is the path manifest-import compares on the zone's first boot.
#   5. The build's own check works: given an expected archive with one
#      service's enabled state flipped, the build fails.
#   6. What the first boot's early manifest-import does with the gate's
#      generic_limited_net.xml (the image's generic.xml) enables
#      smtp:sendmail, listening on the local host only, and
#      sendmail-client.
#
# Requires /usr/sbin/svccfg and /lib/svc/bin/svc.configd (any illumos
# zone) and a nix on PATH. Nothing touches the live SMF repository.
#
# usage: smf-seed.sh /etc/nixos/pkgs.nix   (a file evaluating to the package set)

set -uo pipefail

pkgsFile=${1:?usage: $0 /path/to/pkgs.nix}
top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

# svccfg against a scratch copy: svc.configd wants to write beside the repository
svccfg_on() {
	cp "$seed/repository.db" "$tmp/repository.db"
	chmod 600 "$tmp/repository.db"
	SVCCFG_REPOSITORY="$tmp/repository.db" SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd /usr/sbin/svccfg "$@"
}

# --- 1. build ---------------------------------------------------------------

if seed=$(nix-build --no-out-link -E "import $top/zone/smf-seed.nix { pkgs = import $pkgsFile; }" 2>"$tmp/build.log"); then
	ok "zone/smf-seed.nix builds ($seed)"
else
	bad "zone/smf-seed.nix does not build"
	tail -20 "$tmp/build.log"
	echo "$pass passed, $fail failed"
	exit 1
fi

# --- 2. the expected archive --------------------------------------------------

svccfg_on archive >"$tmp/archive.xml"
if cmp -s "$tmp/archive.xml" "$top/zone/smf-seed-archive.xml"; then
	ok "svccfg archive of the seed is zone/smf-seed-archive.xml"
else
	bad "svccfg archive of the seed differs from zone/smf-seed-archive.xml"
	diff "$top/zone/smf-seed-archive.xml" "$tmp/archive.xml" | head -20
fi

# --- 3. the services ----------------------------------------------------------

expected="milestone/devices
milestone/multi-user
milestone/multi-user-server
milestone/name-services
milestone/single-user
network/datalink-management
network/initial
network/ip-interface-management
network/iptun
network/loopback
network/physical
network/rpc/bind
network/sendmail-client
network/smtp
smartdc/mdata
system/boot-archive
system/console-login
system/device/local
system/early-manifest-import
system/filesystem/local
system/filesystem/minimal
system/filesystem/root
system/filesystem/usr
system/identity
system/install-discovery
system/manifest-import
system/svc/global
system/svc/restarter
system/utmp"
svccfg_on list | sort >"$tmp/services"
if [ "$(cat "$tmp/services")" = "$expected" ]; then
	ok "the seed holds the $(wc -l <"$tmp/services" | tr -d ' ') expected services"
else
	bad "the seed's services are not the expected ones"
	diff <(echo "$expected") "$tmp/services"
fi

# --- 4. recorded manifest paths ----------------------------------------------

: >"$tmp/paths"
while read -r svc; do
	svccfg_on -s "$svc" listprop manifestfiles | awk 'NF == 3 { print $3 }' >>"$tmp/paths"
done <"$tmp/services"
var="/var/svc/manifest/network/sendmail-client.xml
/var/svc/manifest/network/smtp-sendmail.xml"
if [ -s "$tmp/paths" ] && [ "$(grep -v '^/lib/svc/manifest/' "$tmp/paths" | sort -u)" = "$var" ]; then
	ok "all $(sort -u "$tmp/paths" | wc -l | tr -d ' ') recorded manifests are under /lib/svc/manifest, but sendmail's two under /var/svc/manifest/network"
else
	bad "recorded manifest paths other than /lib/svc/manifest and sendmail's two (or none recorded)"
	grep -v '^/lib/svc/manifest/' "$tmp/paths" | sort -u | head
fi

# --- 5. the build rejects a configuration it does not expect ----------------

# the first enabled='true' becomes enabled='false' (awk: illumos sed has no 0,/re/ address)
awk -v q="'" '
	BEGIN { t = "enabled=" q "true" q; f = "enabled=" q "false" q }
	!done && (i = index($0, t)) { $0 = substr($0, 1, i - 1) f substr($0, i + length(t)); done = 1 }
	{ print }
' "$top/zone/smf-seed-archive.xml" >"$tmp/wrong-archive.xml"
if cmp -s "$tmp/wrong-archive.xml" "$top/zone/smf-seed-archive.xml"; then
	bad "could not make a wrong expected archive (no enabled='true' in it)"
elif nix-build --no-out-link -E "(import $top/zone/smf-seed.nix { pkgs = import $pkgsFile; }).overrideAttrs { expectedArchive = $tmp/wrong-archive.xml; }" >"$tmp/wrong.log" 2>&1; then
	bad "the build accepted a wrong expected archive"
elif grep -q "differs from zone/smf-seed-archive.xml" "$tmp/wrong.log"; then
	ok "the build fails when the configuration differs from the expected archive"
else
	bad "the build with a wrong expected archive failed for another reason"
	tail -5 "$tmp/wrong.log"
fi

# --- 6. the first boot's profile enables sendmail --------------------------

gate=$(nix eval --raw --impure --expr "(import $pkgsFile).illumos-ld.src.outPath")
cp "$seed/repository.db" "$tmp/firstboot.db"
chmod 600 "$tmp/firstboot.db"
fb() { SVCCFG_REPOSITORY="$tmp/firstboot.db" SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd /usr/sbin/svccfg "$@"; }
# its include of /etc/svc/profile/name_service.xml pointed at the gate's ns_dns.xml, which the image links there
sed "s|file:/etc/svc/profile/name_service.xml|file:$gate/usr/src/cmd/svc/profile/ns_dns.xml|" \
	"$gate/usr/src/cmd/svc/profile/generic_limited_net.xml" >"$tmp/generic.xml"
fb apply "$tmp/generic.xml" >"$tmp/apply.log" 2>&1
got="$(fb -s network/smtp:sendmail listprop general/enabled | awk '{ print $3 }') \
$(fb -s network/smtp:sendmail listprop config/local_only | awk '{ print $3 }') \
$(fb -s network/sendmail-client:default listprop general/enabled | awk '{ print $3 }')"
if [ "$got" = "true true true" ]; then
	ok "generic_limited_net.xml, applied as at the first boot, enables smtp:sendmail (local only) and sendmail-client"
else
	bad "after generic_limited_net.xml: smtp:sendmail enabled, local_only, sendmail-client enabled = $got"
	tail -3 "$tmp/apply.log"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
