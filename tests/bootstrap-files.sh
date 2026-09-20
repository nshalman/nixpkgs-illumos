#!/usr/bin/env bash
# usage: tests/bootstrap-files.sh ON-SERVER-DIR ILLUMOS-LIBC-STORE-PATH [nix-build options]
# Runs tests/bootstrap-files.nix on the two files in ON-SERVER-DIR. NIX_BUILD_CMD overrides `nix-build`.
set -eu
here=$(cd "$(dirname "$0")" && pwd); dir=$(cd "$1" && pwd -P); libc=$2; shift 2
nar=$(readlink -f "$dir/unpack.nar.xz"); tools=$(readlink -f "$dir/bootstrap-tools.tar.xz")
hash=$(xz -dc "$nar" | sha256sum | cut -d' ' -f1)
thash=$(sha256sum "$tools" | cut -d" " -f1)
exec ${NIX_BUILD_CMD:-nix-build} "$here/bootstrap-files.nix" --no-out-link \
  --argstr unpackUrl "file://$nar" --argstr unpackHash "sha256:$hash" --argstr toolsUrl "file://$tools" --argstr toolsHash "sha256:$thash" --argstr illumos-libc "$libc" "$@"
