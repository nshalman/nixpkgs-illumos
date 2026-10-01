#!/usr/bin/env bash
#
# Puts a pinned source into the Nix store as fetchFromGitHub makes it (the commit's tree as `git archive` gives it,
# named source, at the fixed-output path of the pin's hash), from a git fetch of the pinned commit with whatever
# access git has here, and checks the tree against the pin's hash first. With HOST, copies it into HOST's store too
# (nix-copy-closure). A build of the pin there then finds its source in the store and does not fetch it: for a private
# repository, whose archive GitHub serves only with credentials a builder need not have.
#
# usage: seed.sh NAME [HOST]   (needs git, nix and a tar that reads standard input by default on PATH)
#
# PINS_DIR is the directory of sources.json and pins.json (default: this script's), PINS_URL_PREFIX where the
# repositories are (default https://github.com: PREFIX/owner/repo.git).

set -euo pipefail

dir=${PINS_DIR:-$(cd "$(dirname "$0")" && pwd)}
prefix=${PINS_URL_PREFIX:-https://github.com}
name=${1:?usage: $0 NAME [HOST]}
host=${2:-}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

nix() { command nix --extra-experimental-features nix-command "$@"; }
pin() { nix eval --raw --file "$dir/default.nix" "\"$name\".$1"; }

rev=$(pin rev)
hash=$(pin hash)
url="$prefix/$(pin owner)/$(pin repo).git"

git init -q --bare "$tmp/git"
git -C "$tmp/git" fetch -q --depth 1 "$url" "$rev"
mkdir "$tmp/source"
git -C "$tmp/git" archive "$rev" | tar -x -C "$tmp/source"
got=$(nix hash path --type sha256 "$tmp/source")
if [ "$got" != "$hash" ]; then
    echo "$name: the tree of $rev at $url is $got, not the pin's $hash" >&2
    exit 1
fi

path=$(nix-store --add-fixed --recursive sha256 "$tmp/source")
if [ -n "$host" ]; then
    nix-copy-closure --to "$host" "$path"
fi
echo "$path"
