#!/usr/bin/env bash
#
# ../illumos.nix pins what it builds from: nixpkgs, the Nix source and the bootstrap files are fetched from where
# they are published, so a zone needs only this repo (or a fetch of it) to evaluate the same package set as the
# builder that filled the binary cache. Checks that the defaults evaluate with no NIX_PATH and no local files
# outside this repo, and that the zone system they give is the one the reference package set gives.
#
# usage: pins.sh /etc/nixos/pkgs.nix

set -uo pipefail

refFile=${1:?usage: $0 /path/to/reference-pkgs.nix}
top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

system() { echo "(import $top/zone/system.nix { pkgs = $1; }).outPath"; }

# restrict-eval: files outside this repo, and URLs outside GitHub, are refused (the bootstrap files are fetched at
# build time, not here). No global git config: one rewriting https URLs (url.<base>.insteadOf) would change how
# the Nix source is fetched.
if pinned=$(NIX_PATH= GIT_CONFIG_GLOBAL=/dev/null nix-instantiate --eval --read-write-mode \
        --option restrict-eval true -I "$top" \
        --option allowed-uris "https://github.com/ git+https://github.com/" \
        --expr "$(system "import $top/illumos.nix { }")" 2>"$tmp/pinned.err"); then
    ok "illumos.nix evaluates on its defaults alone"
else
    bad "illumos.nix does not evaluate on its defaults alone"; sed 's/^/    /' "$tmp/pinned.err"
fi

if ref=$(nix-instantiate --eval --read-write-mode --expr "$(system "import $refFile")" 2>"$tmp/ref.err"); then
    ok "reference $refFile evaluates"
else
    bad "reference $refFile does not evaluate"; sed 's/^/    /' "$tmp/ref.err"
fi

if [ "$fail" -eq 0 ]; then
    if [ "$pinned" = "$ref" ]; then
        ok "same zone system: $pinned"
    else
        bad "different zone systems: pinned $pinned, reference $ref"
    fi
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
