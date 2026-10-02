#!/bin/bash
#
# stage-image IDENTITY DIR DIGIT: the platform's build stamp, printed, and what build-image gives build_live for it
# besides what Nix built: DIR/proto, the illumos build's proto area (@illumosProto@) by links, with that stamp as the
# buildstamp build_live reads (it names the platform, etc/release and etc/version/platform by it); and DIR/stamped,
# files with the stamp in, ahead of builder's search directories: the kernel, its uname -v joyent_STAMP (as
# smartos-live's build_illumos makes GATE; ./uname-version.sh), and etc/motd and etc/issue, the illumos build's with
# its stamp replaced.
#
# IDENTITY is the overlay's (smartos-live identityFile, ./identity.nix: kind, rev, stamp, one KEY=VALUE a line): a
# clean tree or a release has its commit's time (a release's, the stamp it was cut at), the same on every build of
# it; a dirty or unknown tree's is the time now (UTC), so each build of it is newer than the last. DIGIT, the
# flavor's, is the stamp's last, as smartos-live's Jenkins builds stamp theirs (tools/build_jenkins: 7 the default
# build, 8 debug, 9 gcc14), so that flavors of one build differ.

set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/sbin

usage() {
    echo "usage: $0 IDENTITY DIR DIGIT" >&2
    exit 2
}
[ $# = 3 ] && [ -f "$1" ] && [[ $3 =~ ^[0-9]$ ]] || usage
identity=$1 dir=$2 digit=$3
proto=@illumosProto@

kind= stamp=
while IFS='=' read -r key value; do
    case $key in
        kind) kind=$value ;;
        stamp) stamp=$value ;;
    esac
done <"$identity"
case $kind in
    clean | release | dirty | unknown) ;;
    *) echo "$0: $identity: kind '$kind' is not clean, release, dirty or unknown" >&2; exit 1 ;;
esac
if [ -z "$stamp" ]; then
    stamp=$(TZ=UTC date +%Y%m%dT%H%M%SZ)
fi
[[ $stamp =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { echo "$0: $identity: '$stamp' is not a build stamp" >&2; exit 1; }
stamp=${stamp:0:14}${digit}Z

mkdir -p "$dir/proto"
for f in "$proto"/*; do
    [ "${f##*/}" = buildstamp ] || ln -s "$f" "$dir/proto/"
done
echo "$stamp" >"$dir/proto/buildstamp"

kernel=$dir/stamped/platform/i86pc/kernel/amd64
mkdir -p "$kernel" "$dir/stamped/etc"
cp "$proto/platform/i86pc/kernel/amd64/unix" "$kernel/unix"
chmod u+w "$kernel/unix"
"$(dirname "$0")/uname-version" "$kernel/unix" "joyent_$stamp" >&2
old=$(cat "$proto/buildstamp")
for f in motd issue; do
    sed "s/$old/$stamp/g" "$proto/etc/$f" >"$dir/stamped/etc/$f"
done

echo "$stamp"
