#!/usr/bin/env bash
# Unpack a SmartOS platform tarball into the files a running platform shows: its boot archive's root file system with
# /usr from usr.lgz, the compressed image the platform mounts there. For comparing what this repository builds with
# what SmartOS ships (pkgs/smartos-extra: platformReference).
#
#   tests/smartos-platform-reference.sh PLATFORM-TGZ OUT-DIR
#   nix-store --add-fixed --recursive sha256 OUT-DIR
#
# Both images are UFS. A zone can attach them read-only with lofi but cannot mount them; ufsdump reads the raw lofi
# device and ufsrestore writes the files, so no mount is needed. Run as root, in a zone that has /dev/lofictl, or in
# the global zone. The lofi devices are detached again, also on failure.
#
# Left out of OUT-DIR: usr.lgz itself (its contents are usr/), the boot archive's own usr/ (hidden under usr.lgz on a
# running platform), and ufsrestore's restoresymtable files. Neither image holds device nodes, FIFOs or sockets (the
# store could not take them); the script fails if one does.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 PLATFORM-TGZ OUT-DIR" >&2
  exit 2
fi
tgz=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
out=$2
if [ -e "$out" ]; then
  echo "$0: $out exists" >&2
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/var/tmp}/platform-ref.XXXXXX")
devs=()
cleanup() {
  local d
  for d in "${devs[@]}"; do [ -z "$d" ] || lofiadm -d "$d" || true; done
  rm -rf "$work"
}
trap cleanup EXIT

# restore IMAGE DIR: the UFS file system in IMAGE into DIR, through a read-only lofi device
restore() {
  local image=$1 dir=$2 dev
  dev=$(lofiadm -r -a "$image")
  devs+=("$dev")
  mkdir -p "$dir"
  (cd "$dir" && ufsdump 0f - "${dev/\/lofi\//\/rlofi\/}" | ufsrestore rf -)
  lofiadm -d "$dev"
  devs=("${devs[@]/$dev/}")
  rm -f "$dir/restoresymtable"
}

tar xzf "$tgz" -C "$work"
archive=$(echo "$work"/platform-*/i86pc/amd64/boot_archive)
restore "$archive" "$work/root"
restore "$work/root/usr.lgz" "$work/usr"
rm -rf "$work/root/usr" "$work/root/usr.lgz"
mv "$work/usr" "$work/root/usr"

special=$(find "$work/root" \( -type b -o -type c -o -type p -o -type s -o -type D \) | head -5)
if [ -n "$special" ]; then
  echo "$0: special files the store cannot hold:" >&2
  echo "$special" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"
mv "$work/root" "$out"
echo "$out"
