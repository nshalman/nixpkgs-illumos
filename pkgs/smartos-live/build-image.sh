#!/bin/bash
#
# build-image OUTPUT-DIR [ROOT-PASSWORD]: SmartOS's platform image, made as smartos-live's `gmake live` makes it
# (tools/build_live), from what Nix built: the manifest (@manifest@), the stages' outputs as builder's search
# directories (@searchDirs@) and the workspace build_live runs from (@workspace@). Needs root, lofi and UFS mounts:
# a zone with the builder brand (its lofi devices) and fs_allowed including ufs, or the global zone.
#
# The root password is ROOT-PASSWORD, or one made here (theirs by pkgsrc's pwgen -B -c -n 16); build_live writes it
# beside the image (root.password). PATH is theirs (/usr/bin, /usr/sbin, /sbin, then what they take from pkgsrc:
# md5sum and gtar, here nixpkgs' coreutils and GNU tar).

set -euo pipefail

export PATH=/usr/bin:/usr/sbin:/sbin:@extraPath@

out=${1:?usage: $0 OUTPUT-DIR [ROOT-PASSWORD]}
password=${2:-}
if [ -z "$password" ]; then
    # 16 letters and digits, none easily mistaken for another
    password=$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789')
    password=${password:0:16}
    [ ${#password} = 16 ]
fi

# build_live finds its tree by its own path and writes its log in log/ there: a directory of links to the workspace,
# with log/ in OUTPUT-DIR
ws=$(mktemp -d)
trap 'rm -rf "$ws"' EXIT
for f in @workspace@/*; do
    ln -s "$f" "$ws/"
done
mkdir -p "$out/log"
ln -s "$(cd "$out" && pwd)/log" "$ws/log"

# The kernel, its uname -v the platform's version, joyent_ and the build stamp build_live gives the image (as
# smartos-live's build_illumos makes it), rather than the illumos build's (./uname-version.sh): in a search directory
# of its own, ahead of the others, as builder takes each file from the first that has it
stamped=$ws/stamped/platform/i86pc/kernel/amd64
mkdir -p "$stamped"
cp @unix@ "$stamped/unix"
chmod u+w "$stamped/unix"
uname-version "$stamped/unix" "joyent_$(cat @workspace@/proto/buildstamp)"

"$ws/tools/build_live" -m @manifest@ -o "$out" -p "$password" "$ws/stamped" @searchDirs@
