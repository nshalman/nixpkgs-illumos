#!/usr/bin/env bash
#
# pins/seed.sh against a local repository standing in for GitHub (PINS_URL_PREFIX), with its own sources.json and
# pins.json (PINS_DIR): it puts the pinned commit's tree into the store at the path fetchFromGitHub's fixed output
# has (named source, the recursive sha256 the pin's hash is), and refuses a pin whose hash the commit's tree does not
# have, adding nothing. (Copying to another host, seed.sh's second argument, is nix-copy-closure's and not tested.)
#
# usage: pins-seed.sh (needs git, nix and a tar that reads standard input by default on PATH)

set -uo pipefail

top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
nix() { command nix --extra-experimental-features nix-command "$@"; }

# the repository: acme/widget, a commit with a file whose content is this run's, so its path is new to the store
git init -q --bare "$tmp/gh/acme/widget.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
echo "widget $tmp" >README
printf '#!/bin/sh\necho run\n' >run.sh && chmod +x run.sh
git add -A && git commit -q -m A
rev=$(git rev-parse HEAD)
git push -q "$tmp/gh/acme/widget.git" main
mkdir "$tmp/tree" && cp -a README run.sh "$tmp/tree/"
hash=$(nix hash path --type sha256 "$tmp/tree")
want=$(nix-store --print-fixed-path --recursive sha256 "$(nix hash convert --hash-algo sha256 --to nix32 "$hash")" source)

mkdir "$tmp/pins"
cp "$top/pins/seed.sh" "$top/pins/default.nix" "$tmp/pins/"
echo '{ "widget": { "owner": "acme", "repo": "widget", "branch": "main" } }' >"$tmp/pins/sources.json"
pins() { printf '{ "widget": { "rev": "%s", "hash": "%s", "date": 0 } }\n' "$rev" "$1" >"$tmp/pins/pins.json"; }
run() { PINS_DIR="$tmp/pins" PINS_URL_PREFIX="file://$tmp/gh" bash "$tmp/pins/seed.sh" "$@"; }

pins "$hash"
if [ ! -e "$want" ] && run widget >"$tmp/out1" 2>&1 && [ "$(tail -1 "$tmp/out1")" = "$want" ] && [ -e "$want" ] &&
    diff -r "$tmp/tree" "$want" >/dev/null; then
    ok "the pinned commit's tree is put in the store at fetchFromGitHub's path"
else
    bad "seeding"; echo "    want $want"; sed 's/^/    /' "$tmp/out1"
fi

# a pin whose hash is not the commit's tree's: another tree's
echo other >"$tmp/other"
other=$(nix hash path --type sha256 "$tmp/other")
otherPath=$(nix-store --print-fixed-path --recursive sha256 "$(nix hash convert --hash-algo sha256 --to nix32 "$other")" source)
pins "$other"
if ! run widget >"$tmp/out2" 2>&1 && grep "widget" "$tmp/out2" >/dev/null && [ ! -e "$otherPath" ]; then
    ok "a commit whose tree is not the pin's hash is refused, and nothing is added"
else
    bad "a wrong hash"; sed 's/^/    /' "$tmp/out2"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
