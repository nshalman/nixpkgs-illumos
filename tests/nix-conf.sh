#!/usr/bin/env bash
#
# The system profile carries /etc/nix/nix.conf: zone/system.nix renders it from the repo defaults and the
# zone's own `nixSettings`. Checks the rendered file and that nix parses it.
#
# usage: nix-conf.sh /etc/nixos/pkgs.nix

set -uo pipefail

pkgsFile=${1:?usage: $0 /path/to/pkgs.nix}
top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

cat > "$tmp/system.nix" <<NIX
import $top/zone/system.nix {
  pkgs = import $pkgsFile;
  nixSettings = { cores = 6; extra-platforms = [ "x86_64-illumos" "x86_64-sunos" ]; keep-outputs = true; };
}
NIX

if sys=$(nix-build --no-out-link "$tmp/system.nix" 2>"$tmp/build.err"); then
    ok "system profile with nixSettings builds"
else
    bad "system profile with nixSettings does not build"; sed 's/^/    /' "$tmp/build.err"; exit 1
fi

conf=$sys/etc/nix/nix.conf
[ -f "$conf" ] && ok "profile has etc/nix/nix.conf" || { bad "profile has no etc/nix/nix.conf"; exit 1; }

for line in "system = x86_64-solaris" "build-users-group = nixbld" "cores = 6" "keep-outputs = true" \
            "extra-platforms = x86_64-illumos x86_64-sunos" "experimental-features = nix-command flakes"; do
    grep -qx "$line" "$conf" && ok "nix.conf has '$line'" || { bad "nix.conf lacks '$line'"; }
done

# nix reads the file: NIX_CONF_DIR only, no store access
# the last line reads a zone's local additions, if it has any (the image ships nix.local.conf.example)
[ "$(tail -1 "$conf")" = "!include /etc/nix/nix.local.conf" ] && ok "nix.conf ends by including /etc/nix/nix.local.conf" \
    || bad "nix.conf does not end with '!include /etc/nix/nix.local.conf' (last line: $(tail -1 "$conf"))"

if NIX_CONF_DIR=$sys/etc/nix nix config show > "$tmp/show" 2>"$tmp/show.err"; then
    grep -qx "cores = 6" "$tmp/show" && grep -qx "system = x86_64-solaris" "$tmp/show" \
        && ok "nix config show reports the settings from the rendered file" \
        || { bad "nix config show does not report the settings"; grep -E "^(cores|system) " "$tmp/show" | sed 's/^/    /'; }
else
    bad "nix config show rejects the rendered file"; sed 's/^/    /' "$tmp/show.err"
fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
