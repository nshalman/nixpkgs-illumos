#!/usr/bin/env bash
#
# Build a zone image with zone/image.nix and zone/make-joyent-image, receive its stream into a scratch dataset and
# check what a zone booted from it would find, without booting one:
#
#   1. The inputs build, the script makes a stream and a manifest whose sha1 and size match the stream, and the
#      stream receives.
#   2. Modes: /etc/shadow 0400, /etc/svc/repository.db 0600, /tmp and /var/tmp 1777, /nix/store 1775 group 30000,
#      /opt/nix/bin/sudo and sudoedit 4511 (setuid root), /etc/sudoers and /etc/sudoers.d/admin 0440; the mail spools
#      as the gate's packages make them (/var/spool/clientmqueue smmsp 0770, /var/spool/mqueue 0750 group bin,
#      /var/mail 1777 and /var/mail/:saved 0775 group mail).
#      vmadm will provision a joyent-brand zone from it: /var/zoneinit/zoneinit.json declares
#      features.var_svc_provisioning (checkDatasetProvisionable in /usr/vm/node_modules/VM.js; without it,
#      "provisioning dataset ... with brand joyent is not supported").
#   3. In a chroot of the received root, with /usr, /lib, /sbin, /dev and /proc lofs-mounted from this zone as the
#      brand mounts them from the global zone:
#      - root's shell is the system profile's bash, and nixbld has the 32 build users as members;
#      - the admin account is the SmartOS base images' (uid 100, staff, /home/admin its own, no password until
#        admin_pw, the Service Management and Software Installation profiles), but with the system profile's bash as
#        shell, and its login shell finds nix;
#      - a login shell finds nix through /etc/profile;
#      - Nix's database knows the whole closure (`nix-store --verify`, the profile's requisites), and a GC root
#        keeps the system the setuid copies came from;
#      - the SMF repository is the seed (27 services), and vmadm's pre-boot svccfg calls on mdata succeed;
#      - sshd accepts /etc/ssh/sshd_config (`sshd -t`, with host keys made in the copy), and its effective
#        settings (`sshd -T`) allow no password or keyboard-interactive logins and root by key only;
#      - importing /var/svc/manifest/site, as the first boot does, adds the profile's services (nix-daemon,
#        mdata-accounts, which runs before mdata:execute and ssh, hosts-nodename, before mdata:execute and smtp);
#      - hosts-nodename puts the node name on the 127.0.0.1 line of /etc/inet/hosts at provisioning only, once;
#      - the first boot's early manifest-import, replayed (the platform's manifests, then generic.xml, the platform
#        profile and site.xml), applies every profile and leaves the services a zone should not run off;
#      - every symbolic link under /etc and /var resolves;
#      - /etc/logindevperm exists (login reads it; without it zlogin prints "error processing /etc/logindevperm");
#      - `useradd -m` makes a user with a home (it needs /etc/skel and reads /etc/default/useradd);
#      - sudo as the base images have it: visudo accepts /etc/sudoers, admin's login shell finds the setuid copy
#        and runs a command as root without a password, sudoedit runs, its mailer is the platform's sendmail, and a
#        user sudoers does not name gets nothing;
#      - mail: the gate's smmsp account; a message to root, through the image's sendmail.cf and the platform's
#        mail.local, lands in /var/mail/root and mailx reads it; submit.cf hands mail to 127.0.0.1; mailer.conf;
#      - a command run over ssh (bash, not a login shell, SSH_CLIENT set) finds nix, through root's ~/.bashrc;
#      - /etc/motd says what the zone is; an interactive login shell has NixOS's aliases and prompt (/etc/bashrc)
#        and bash-completion, and finds illumos-rebuild;
#      - the nixpkgs-illumos binary cache is off, and on once /etc/nix/nix.local.conf.example is copied into place.
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
for check in "etc/shadow 400 0" "etc/svc/repository.db 600 0" "tmp 1777 0" "var/tmp 1777 0" "nix/store 1775 30000" \
	"opt/nix/bin/sudo 4511 0" "opt/nix/bin/sudoedit 4511 0" "etc/sudoers 440 0" "etc/sudoers.d/admin 440 0" \
	"var/spool/clientmqueue 770 25" "var/spool/mqueue 750 2" "var/mail 1777 6" "var/mail/:saved 775 6"; do
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

a_pw=$(in_root /usr/bin/getent passwd admin)
a_home=$(stat -c '%u %g %a' "$R/home/admin" 2>/dev/null)
if [ "$a_pw" = "admin:x:100:10::/home/admin:/nix/var/nix/profiles/default/bin/bash" ] && [ "$a_home" = "100 10 755" ] &&
	grep '^admin:NP:' "$R/etc/shadow" >/dev/null &&
	grep -x 'admin::::type=normal;profiles=Service Management,Software Installation' "$R/etc/user_attr" >/dev/null; then
	ok "the admin account is the base images' (uid 100, staff, own home, NP, two RBAC profiles)"
else
	bad "admin account: passwd '$a_pw', home '$a_home'"
fi
# `su - admin -c` on illumos reads no startup files; a login shell of admin's own is what an ssh login gets
if out=$(in_root /usr/bin/su admin -c "/usr/bin/env -i HOME=/home/admin LOGNAME=admin USER=admin \
	/usr/bin/bash -lc 'command -v nix'" 2>&1) && [ -n "$out" ]; then
	ok "admin's login shell finds nix ($out)"
else
	bad "admin's login shell does not find nix: $out"
fi

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
# the GC root illumos-rebuild keeps on the system the setuid copies came from (zone/illumos-rebuild, installSetuid).
# Asked with the image's state directory from outside the chroot: in it, the search for the roots of running
# processes reads this zone's /proc, and fails there ("reading symlink '/proc/<pid>/path/root': Not owner").
NIX_STATE_DIR="$R/nix/var/nix" "$system/bin/nix-store" -q --roots "$system" >"$tmp/roots" 2>&1
if grep -x "$R/nix/var/nix/gcroots/setuid-programs -> $system" "$tmp/roots" >/dev/null; then
	ok "the shipped system is a GC root for the setuid copies"
else
	bad "no GC root /nix/var/nix/gcroots/setuid-programs on the shipped system (link: $(readlink "$R/nix/var/nix/gcroots/setuid-programs" 2>&1)); nix-store -q --roots said:"
	grep -v '^/proc/' "$tmp/roots" | tail -5
fi

cp "$R/etc/svc/repository.db" "$tmp/repo.db"
repo() { SVCCFG_REPOSITORY="$tmp/repo.db" SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd /usr/sbin/svccfg "$@"; }
nsvc=$(repo list | wc -l | tr -d ' ')
if [ "$nsvc" = 27 ]; then ok "the SMF repository is the seed (27 services)"; else bad "the SMF repository has $nsvc services"; fi
# what vmadm does to a joyent-brand zone's repository before its first boot (VM.js: the mdata:execute timeout,
# feature update_mdata_exec_timeout; fixMdataFetchStart, features cleanup_dataset and zoneinit)
if repo -s svc:/smartdc/mdata:execute setprop start/timeout_seconds = count: 300 2>"$tmp/vmadm.err" &&
	repo -s svc:/smartdc/mdata:fetch setprop start/exec = /lib/svc/method/mdata-fetch 2>>"$tmp/vmadm.err"; then
	ok "vmadm's pre-boot svccfg calls on mdata:execute and mdata:fetch succeed"
else
	bad "vmadm's pre-boot svccfg calls fail: $(cat "$tmp/vmadm.err")"
fi

for t in rsa ecdsa ed25519; do
	in_root /usr/bin/ssh-keygen -q -t $t -N '' -f /var/ssh/ssh_host_${t}_key >/dev/null 2>&1
done
if in_root /usr/lib/ssh/sshd -t -f /etc/ssh/sshd_config >"$tmp/sshd.log" 2>&1; then
	ok "sshd -t accepts /etc/ssh/sshd_config$( [ -s "$tmp/sshd.log" ] && echo " (said: $(head -1 "$tmp/sshd.log"))")"
else
	bad "sshd -t"; cat "$tmp/sshd.log"
fi
# SmartOS's sshd prints some keys in CamelCase (PermitRootLogin), and without-password is prohibit-password's old name
settings=$(in_root /usr/lib/ssh/sshd -T -f /etc/ssh/sshd_config 2>"$tmp/sshdT.err" |
	grep -i -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) ' |
	tr 'A-Z' 'a-z' | sed 's/without-password/prohibit-password/' | sort | tr '\n' ' ')
if [ "$settings" = "kbdinteractiveauthentication no passwordauthentication no permitrootlogin prohibit-password " ]; then
	ok "sshd allows no password or keyboard-interactive logins, and root by key only"
else
	bad "sshd's effective settings: $settings"; tail -3 "$tmp/sshdT.err"
fi

# what the first boot's manifest-import does with /var/svc/manifest/site: the profile's services must be there
cp "$R/etc/svc/repository.db" "$R/tmp/firstboot.db"
in_root /usr/bin/env SVCCFG_REPOSITORY=/tmp/firstboot.db SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd \
	/usr/sbin/svccfg import /var/svc/manifest/site >"$tmp/firstboot.log" 2>&1
fb() { in_root /usr/bin/env SVCCFG_REPOSITORY=/tmp/firstboot.db SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd /usr/sbin/svccfg "$@"; }
missing=
for s in application/nix-daemon application/mdata-accounts application/hosts-nodename; do
	fb list | grep -qx "$s" || missing="$missing $s"
done
if [ -z "$missing" ] &&
	fb export application/mdata-accounts | grep "<service_fmri value='svc:/smartdc/mdata:execute'/>" >/dev/null &&
	fb export application/mdata-accounts | grep "<service_fmri value='svc:/network/ssh'/>" >/dev/null &&
	fb export application/hosts-nodename | grep "<service_fmri value='svc:/smartdc/mdata:execute'/>" >/dev/null &&
	fb export application/hosts-nodename | grep "<service_fmri value='svc:/network/smtp'/>" >/dev/null; then
	ok "importing /var/svc/manifest/site, as the first boot does, adds nix-daemon, mdata-accounts (before mdata:execute and ssh) and hosts-nodename (before mdata:execute and smtp)"
else
	bad "importing /var/svc/manifest/site does not add:${missing:- the dependents of mdata-accounts}"; tail -3 "$tmp/firstboot.log"
fi

# the hosts-nodename method (zone/services.nix), as the first boot runs it: with /var/svc/provisioning present it
# puts the node name the brand wrote to /etc/nodename on the 127.0.0.1 line of /etc/inet/hosts, once; otherwise it
# leaves the file alone. The name is this zone's own, which the chroot's sendmail below looks up.
hn=$(nix-build --no-out-link -E "(import $top/zone/services.nix { pkgs = import $pkgsFile; }).hostsNodenameMethod" 2>"$tmp/hn.log")
node=$(uname -n)
echo "$node" >"$R/etc/nodename"
before=$(cat "$R/etc/inet/hosts")
"$hn" start "$R" >"$tmp/hn1.log" 2>&1
unchanged=$([ "$(cat "$R/etc/inet/hosts")" = "$before" ] && echo yes)
touch "$R/var/svc/provisioning"
"$hn" start "$R" >"$tmp/hn2.log" 2>&1 && "$hn" start "$R" >"$tmp/hn3.log" 2>&1
rm -f "$R/var/svc/provisioning"
line=$(grep '^127\.0\.0\.1' "$R/etc/inet/hosts")
if [ -n "$hn" ] && [ "$unchanged" = yes ] && [ "$line" = "127.0.0.1	localhost localhost.local loghost $node" ] &&
	[ "$(in_root /usr/bin/getent hosts "$node" | awk '{ print $1 }')" = 127.0.0.1 ]; then
	ok "at provisioning, hosts-nodename puts the node name on the 127.0.0.1 line of /etc/inet/hosts, once"
else
	bad "hosts-nodename: not provisioning left the file alone: ${unchanged:-no}; 127.0.0.1 line: '$line'"
	cat "$tmp/hn.log" "$tmp/hn1.log" "$tmp/hn2.log" "$tmp/hn3.log" 2>/dev/null | tail -5
fi

# what the first boot's early manifest-import does (/lib/svc/method/manifest-import): import the platform's
# /lib/svc/manifest into the seed, then apply generic.xml, the platform profile and site.xml. generic.xml, the gate's
# generic_limited_net.xml, must apply (it includes /etc/svc/profile/name_service.xml); site.xml then leaves off what
# a zone should not run, as SmartOS's own generic.xml does.
cp "$R/etc/svc/repository.db" "$R/tmp/early.db"
em() { in_root /usr/bin/env SVCCFG_REPOSITORY=/tmp/early.db SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd /usr/sbin/svccfg "$@"; }
em import /lib/svc/manifest >"$tmp/early.log" 2>&1
for p in generic.xml platform_none.xml site.xml; do
	em apply /etc/svc/profile/$p >>"$tmp/early.log" 2>&1 || echo "apply $p: exit $?" >>"$tmp/early.log"
done
states=
for s in system/filesystem/autofs:default system/sac:default network/inetd:default network/rpc/bind:default \
	system/identity:domain network/dns/client:default; do
	states="$states $s=$(em -s "$s" listprop general/enabled 2>/dev/null | awk '{ print $3 }')"
done
want=" system/filesystem/autofs:default=false system/sac:default=false network/inetd:default=false"
want="$want network/rpc/bind:default=false system/identity:domain=true network/dns/client:default=true"
if ! grep -i -E 'failed|error' "$tmp/early.log" >/dev/null && [ "$states" = "$want" ]; then
	ok "the first boot's profiles apply (generic.xml, platform, site.xml), and leave autofs, sac, inetd and rpcbind off"
else
	bad "the first boot's profiles:$states"; grep -i -E 'failed|error' "$tmp/early.log" | head -5
fi

broken=$(in_root /usr/bin/find /etc /var -type l ! -exec /usr/bin/test -e {} \; -print 2>/dev/null)
if [ -z "$broken" ]; then ok "every link under /etc and /var resolves"; else bad "links that do not resolve: $broken"; fi

if [ -s "$R/etc/logindevperm" ]; then ok "/etc/logindevperm exists"; else bad "no /etc/logindevperm"; fi

if in_root /usr/sbin/useradd -m -d /home/imgtest -s /usr/bin/bash imgtest >"$tmp/useradd.log" 2>&1 &&
	[ -d "$R/home/imgtest" ]; then
	ok "useradd -m makes a user with a home"
else
	bad "useradd -m: $(cat "$tmp/useradd.log")"
fi

if out=$(in_root /nix/var/nix/profiles/default/bin/visudo -c 2>&1); then
	ok "visudo accepts the sudoers files ($(echo $out))"
else
	bad "visudo -c: $out"
fi
if out=$(in_root /usr/bin/su admin -c "/usr/bin/env -i HOME=/home/admin LOGNAME=admin USER=admin \
	/usr/bin/bash -lc 'command -v sudo && sudo -n /usr/bin/id -u'" 2>&1) &&
	[ "$out" = "$(printf '/opt/nix/bin/sudo\n0')" ]; then
	ok "admin's login shell finds the setuid sudo, which runs a command as root without a password"
else
	bad "admin and sudo: $out"
fi
# the mailer sudo runs to report a user sudoers does not name is the platform's, as the base images' sudo has it
if out=$(in_root /opt/nix/bin/sudo -V 2>&1) && echo "$out" | grep -x 'Path to mail program: /usr/sbin/sendmail' >/dev/null; then
	ok "sudo's mailer is /usr/sbin/sendmail"
else
	bad "sudo's mailer: $(echo "$out" | grep -i 'mail program')"
fi
# sudoedit is sudo under another name (sudo -e): admin's editor, here one that changes nothing, runs on a copy
if out=$(in_root /usr/bin/su admin -c "/usr/bin/env -i HOME=/home/admin LOGNAME=admin USER=admin \
	/usr/bin/bash -lc 'command -v sudoedit && SUDO_EDITOR=/usr/bin/true sudoedit -n /etc/motd'" 2>&1) &&
	echo "$out" | head -1 | grep -x /opt/nix/bin/sudoedit >/dev/null; then
	ok "admin's login shell finds the setuid sudoedit, which edits a root-owned file ($(echo $out | cut -d' ' -f2-))"
else
	bad "admin and sudoedit: $out"
fi
if out=$(in_root /usr/bin/su imgtest -c "/opt/nix/bin/sudo -n /usr/bin/id -u" 2>&1); then
	bad "sudo ran a command as root for imgtest, whom sudoers does not name: $out"
else
	ok "sudo refuses a user sudoers does not name ($out)"
fi

# Mail for root, as smtp:sendmail delivers it: the platform's sendmail with the image's /etc/mail/sendmail.cf (-Am,
# delivering at once, -odi, since no daemon runs here) hands it to the platform's mail.local, into /var/mail/root,
# where mailx reads it. The aliases database is made first, as the smtp-sendmail method does at its start.
if [ "$(in_root /usr/bin/getent passwd smmsp)" = "smmsp:x:25:25:SendMail Message Submission Program:/:" ] &&
	[ "$(in_root /usr/bin/getent group smmsp)" = "smmsp::25:" ] && grep '^smmsp:NP:' "$R/etc/shadow" >/dev/null; then
	ok "the smmsp account is the gate's (uid and gid 25, no password)"
else
	bad "smmsp: $(in_root /usr/bin/getent passwd smmsp) / $(in_root /usr/bin/getent group smmsp)"
fi
in_root /usr/lib/sendmail -bi >"$tmp/mail.log" 2>&1
printf 'Subject: zone-image mail test\n\nhello root\n' |
	in_root /usr/lib/sendmail -Am -odi -oi root >>"$tmp/mail.log" 2>&1
if out=$(in_root /usr/bin/env TERM=dumb /usr/bin/mailx -H -f /var/mail/root 2>&1) &&
	echo "$out" | grep 'zone-image mail test' >/dev/null; then
	ok "mail to root is delivered to /var/mail/root and mailx reads it"
else
	bad "mail to root: mailx -H said: $out"; tail -5 "$tmp/mail.log"
fi
# the submission program's configuration, submit.cf, hands mail to the local host's daemon, at once: a host name it
# cannot qualify makes sendmail sleep a minute first ("My unqualified host name (localhost) unknown; sleeping for
# retry"), at every message; localhost.local on the 127.0.0.1 line qualifies it
t0=$(date +%s)
out=$(in_root /usr/lib/sendmail -Ac -bv root 2>&1)
took=$(($(date +%s) - t0))
if echo "$out" | grep 'mailer relay, host \[127.0.0.1\], user root@localhost.local' >/dev/null && [ "$took" -lt 30 ]; then
	ok "submitted mail goes to the daemon on 127.0.0.1 (submit.cf), for root@localhost.local, without waiting (${took}s)"
else
	bad "submit.cf, after ${took}s: $out"
fi
if grep -E '^sendmail[[:space:]]+/usr/lib/smtp/sendmail/sendmail$' "$R/etc/mailer.conf" >/dev/null 2>&1; then
	ok "/etc/mailer.conf points mailwrapper at the platform's sendmail"
else
	bad "/etc/mailer.conf: $(cat "$R/etc/mailer.conf" 2>&1 | grep -v '^#' | head -3)"
fi

if out=$(chroot "$R" /usr/bin/env -i PATH=/usr/bin:/usr/sbin HOME=/root SSH_CLIENT="192.0.2.1 50000 22" \
	/nix/var/nix/profiles/default/bin/bash -c 'command -v nix' 2>&1) && [ -n "$out" ]; then
	ok "a command run over ssh finds nix ($out)"
else
	bad "a command run over ssh does not find nix: $out"
fi

if grep 'nixpkgs-illumos' "$R/etc/motd" >/dev/null; then ok "/etc/motd names the image"; else bad "/etc/motd: $(head -3 "$R/etc/motd")"; fi

if out=$(in_root /usr/bin/env TERM=xterm /nix/var/nix/profiles/default/bin/bash -lic 'alias ll; echo "$PS1"' 2>/dev/null) &&
	echo "$out" | grep -x "alias ll='ls -l'" >/dev/null && echo "$out" | grep 'u@\\h:\\w' >/dev/null; then
	ok "an interactive login shell has NixOS's aliases and prompt"
else
	bad "an interactive login shell lacks the aliases or prompt: $out"
fi

if out=$(in_root /usr/bin/env TERM=xterm /nix/var/nix/profiles/default/bin/bash -lic \
	'command -v illumos-rebuild; type -t _comp_initialize || type -t _init_completion' 2>/dev/null) &&
	echo "$out" | grep -x /nix/var/nix/profiles/default/bin/illumos-rebuild >/dev/null &&
	echo "$out" | grep -x function >/dev/null; then
	ok "an interactive login shell has bash-completion and finds illumos-rebuild"
else
	bad "an interactive login shell lacks bash-completion or illumos-rebuild: $out"
fi

cache=https://www.shalman.org/files/cache
subst() { in_root /usr/bin/env HOME=/root /nix/var/nix/profiles/default/bin/nix config show substituters 2>/dev/null; }
if ! subst | grep "$cache" >/dev/null && [ -f "$R/etc/nix/nix.local.conf.example" ] &&
	cp "$R/etc/nix/nix.local.conf.example" "$R/etc/nix/nix.local.conf" && subst | grep "$cache" >/dev/null; then
	ok "the binary cache is off, and on once nix.local.conf.example is copied into place"
else
	bad "binary cache: off by default or on with nix.local.conf does not hold (substituters now: $(subst))"
fi
rm -f "$R/etc/nix/nix.local.conf"

# --- 4. /etc/nixos evaluates to the shipped system ------------------------------------------------------------

want=$(nix-store -q --deriver "$system")
got=$(cd "$R/etc/nixos" && nix-instantiate ./system.nix 2>"$tmp/eval.log")
if [ "$got" = "$want" ]; then
	ok "/etc/nixos/system.nix evaluates to the shipped system"
else
	bad "/etc/nixos/system.nix evaluates to ${got:-nothing}, the image ships $want's output"; tail -3 "$tmp/eval.log"
fi

finish
