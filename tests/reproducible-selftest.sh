#!/usr/bin/env bash
#
# tests/reproducible.sh on derivations with two outputs (out and log, as the illumos nightly has), built here:
#   steady:  both outputs the same in every build: it passes;
#   varying: both outputs hold the time of the build: it fails, and says which output it could not compare, as
#            nix-build --check stops at the first output that differs and compares none after it.
# Each run leaves the varying derivation's <output>.check beside its output (reproducible.sh's --keep-failed).
#
# usage: reproducible-selftest.sh PKGS-FILE   (on illumos; nix-build on PATH)

set -uo pipefail

pkgsFile=${1:?usage: $0 PKGS-FILE}
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

cat >"$tmp/selftest.nix" <<EOF
let
  pkgs = import $pkgsFile;
in
{
  steady = pkgs.runCommand "reproducible-selftest-steady" { outputs = [ "out" "log" ]; } ''
    echo out >\$out
    echo log >\$log
  '';
  varying = pkgs.runCommand "reproducible-selftest-varying" { outputs = [ "out" "log" ]; } ''
    date +%s%N >\$out
    date +%s%N >\$log
  '';
}
EOF

if bash "$here/reproducible.sh" "$tmp/selftest.nix" steady >"$tmp/steady" 2>&1 &&
    grep -q '^PASS: steady builds the same again$' "$tmp/steady" &&
    [ "$(grep -c '^PASS: steady: .*-reproducible-selftest-steady-log names no' "$tmp/steady")" = 3 ]; then
    ok "steady: passes, both outputs searched"
else
    bad "steady: does not pass, or its log output is not searched"; sed 's/^/    /' "$tmp/steady"
fi

if bash "$here/reproducible.sh" "$tmp/selftest.nix" varying >"$tmp/varying" 2>&1; then
    bad "varying: passes"; sed 's/^/    /' "$tmp/varying"
elif grep -q '^FAIL: varying.*not compared' "$tmp/varying"; then
    ok "varying: fails, and names the output --check did not compare"
else
    bad "varying: fails, but does not name the output --check did not compare"; sed 's/^/    /' "$tmp/varying"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
