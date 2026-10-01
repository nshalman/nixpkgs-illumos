#!/bin/bash
#
# build-usb [-c CONSOLE] [-B NAME=VALUE ...] [-f FILE=PATH ...] PLATFORM-DIR OUTPUT-DIR: a bootable USB image of a
# platform that build-image made (PLATFORM-DIR, e.g. OUTPUT/platform-20260911T185107Z), made as smartos-live's `gmake
# usb` makes it (tools/build_boot_image), into OUTPUT-DIR/PLATFORM.usb.gz. CONSOLE is the loader's and the system's
# console (text, ttya, ttyb, ...; default ttya, the serial port boot-vm shows); each -B adds a loader variable, which
# the system sees as a boot property (e.g. -B noimport=true: boot without importing a pool and without the setup
# questions); each -f puts FILE at PATH on the key's root file system (e.g. -f answers.json=private/answers.json: the
# setup questions' answers, which the setup then does not ask; see smartdc/lib/smartos_prompt_config.sh). Needs root,
# lofi and pcfs mounts.
#
# The tree build_boot_image runs from (@workspace@) has the loader's files (proto.boot), format_image and its
# script, patched to take extra loader variables and to compress with nixpkgs' pigz (theirs pkgsrc's).

set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/sbin

usage="usage: $0 [-c CONSOLE] [-B NAME=VALUE ...] [-f FILE=PATH ...] PLATFORM-DIR OUTPUT-DIR"
console=ttya
extra=
files=()
while getopts "c:B:f:" opt; do
    case $opt in
        c) console=$OPTARG ;;
        B) extra+="${OPTARG%%=*}=\"${OPTARG#*=}\""$'\n' ;;
        f) [ -f "${OPTARG%%=*}" ] && [ -n "${OPTARG#*=}" ] && [ "${OPTARG#*=}" != "$OPTARG" ] ||
               { echo "$0: -f $OPTARG: not FILE=PATH, FILE a file" >&2; exit 2; }
           files+=("$OPTARG") ;;
        *) echo "$usage" >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
platform=${1:?$usage}
out=${2:?$usage}
platform=$(cd "$platform" && pwd -P)
[ -f "$platform/i86pc/amd64/boot_archive" ] || { echo "$0: $platform is not a platform directory" >&2; exit 2; }

ws=$(mktemp -d -p /var/tmp)
trap 'rm -rf "$ws"' EXIT
for f in @workspace@/*; do
    ln -s "$f" "$ws/"
done
mkdir "$ws/output"
ln -s "$platform" "$ws/output/platform-latest"
# proto.boot is copied onto pcfs, where a directory without write permission is a read-only one: as theirs, its
# directories 0755 (the manifest's modes), not the store's 0555
rm "$ws/proto.boot"
cp -r @workspace@/proto.boot/ "$ws/proto.boot"
find "$ws/proto.boot" -type d -exec chmod u+w {} +
# the -f files: build_boot_image copies proto.boot onto the root file system
for f in ${files[@]+"${files[@]}"}; do
    mkdir -p "$(dirname "$ws/proto.boot/${f#*=}")"
    cp "${f%%=*}" "$ws/proto.boot/${f#*=}"
done

BI_LOADER_EXTRA=${extra%$'\n'} "$ws/tools/build_boot_image" -c "$console" -r "$ws"
mkdir -p "$out"
mv "$ws"/output-usb/*.usb.gz "$out/"
ls -l "$out"/"$(basename "$platform")".usb.gz
