#!/usr/bin/env bash
#
# Test zone/smf-lib.nix end-to-end on a live illumos zone:
#
#   1. zone/services.nix evaluates and the generated nix-daemon
#      manifest + bundle build.
#   2. `svccfg validate` accepts every generated manifest.
#   3. Golden parity: the hand-written nix-daemon-golden.xml and the
#      generated replacement are imported into separate scratch
#      repositories (SVCCFG_REPOSITORY creates the db on demand);
#      `svccfg export` of both must be byte-identical.
#   4. mkSmfMethodScript: a tailscale-style %m-dispatch script builds,
#      a manifest wired to it validates, and an invalid-arg invocation
#      of the script fails with a usage message.
#
# Requires /usr/sbin/svccfg (present in any illumos zone via the GZ
# /usr mount) and a nix on PATH. Safe to run as any user that can
# nix-build; nothing touches the live SMF repository.
#
# usage: smf-lib.sh /etc/nixos/pkgs.nix   (a file evaluating to the package set)

set -uo pipefail

pkgsFile=${1:?usage: $0 /path/to/pkgs.nix}
top="$(cd "$(dirname "$0")/.." && pwd)"
svccfg=/usr/sbin/svccfg
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

# --- 1. services.nix builds --------------------------------------------------

if gen_daemon=$(nix-build --no-out-link "$top/zone/services.nix" --arg pkgs "import $pkgsFile" -A nix-daemon 2>"$tmp/build.err"); then
    ok "services.nix -A nix-daemon builds"
else
    bad "services.nix -A nix-daemon does not build"
    sed 's/^/    /' "$tmp/build.err"
    echo "cannot continue without the generated manifest"
    exit 1
fi

if bundle=$(nix-build --no-out-link "$top/zone/services.nix" --arg pkgs "import $pkgsFile" -A bundle 2>"$tmp/build.err"); then
    ok "services.nix -A bundle builds"
else
    bad "services.nix -A bundle does not build"
    sed 's/^/    /' "$tmp/build.err"
    bundle=""
fi

# --- 2. svccfg validate ------------------------------------------------------

if "$svccfg" validate "$gen_daemon" 2>"$tmp/validate.err"; then
    ok "svccfg validate accepts generated nix-daemon manifest"
else
    bad "svccfg validate rejects generated nix-daemon manifest"
    sed 's/^/    /' "$tmp/validate.err"
fi

if [ -n "$bundle" ]; then
    found=0
    for m in "$bundle"/lib/svc/manifest/site/*.xml; do
        [ -e "$m" ] || continue
        found=$((found+1))
        if ! "$svccfg" validate "$m" 2>"$tmp/validate.err"; then
            bad "svccfg validate rejects bundle manifest $m"
            sed 's/^/    /' "$tmp/validate.err"
        fi
    done
    if [ "$found" -gt 0 ]; then
        ok "bundle ships $found manifest(s) under lib/svc/manifest/site/, all valid"
    else
        bad "bundle has no manifests under lib/svc/manifest/site/"
    fi
fi

# --- 3. golden parity with hand-written nix-daemon.xml -----------------------

export_one() { # <manifest.xml> <repo.db> -> export on stdout
    SVCCFG_REPOSITORY="$2" "$svccfg" import "$1" >&2 &&
    SVCCFG_REPOSITORY="$2" "$svccfg" export application/nix-daemon
}

if export_one "$top/tests/nix-daemon-golden.xml" "$tmp/golden.db" >"$tmp/golden.export" \
   && export_one "$gen_daemon" "$tmp/gen.db" >"$tmp/gen.export"; then
    if diff -u "$tmp/golden.export" "$tmp/gen.export" >"$tmp/export.diff"; then
        ok "generated nix-daemon is svccfg-export-identical to hand-written XML"
    else
        bad "generated nix-daemon diverges from hand-written XML"
        sed 's/^/    /' "$tmp/export.diff"
    fi
else
    bad "scratch-repo import/export round-trip failed"
fi

# --- 4. mkSmfMethodScript ----------------------------------------------------

cat >"$tmp/example.nix" <<NIX
let
  pkgs = import $pkgsFile;
  smf = import $top/zone/smf-lib.nix { inherit pkgs; };
  script = smf.mkSmfMethodScript {
    name = "example";
    start = ''
      smf_clear_env
      /usr/bin/true &
    '';
    stop = ''
      smf_kill_contract "\$2" TERM 60
      /usr/bin/true
    '';
  };
  manifest = smf.mkSmfManifest {
    name = "example";
    category = "site";
    description = "Example daemon";
    dependencies = [
      {
        name = "network";
        fmri = "svc:/milestone/network:default";
        restartOn = "error";
      }
    ];
    start = {
      exec = "\${script} %m";
      timeout = 5;
      user = "root";
      group = "root";
      environment.EXAMPLE_FLAVOR = "bar baz";
    };
    stop = {
      exec = "\${script} %m %{restarter/contract}";
      timeout = 60;
    };
    duration = "contract";
    application.binary = "/usr/bin/true";
  };
in
{ inherit script manifest; }
NIX

if script=$(nix-build --no-out-link "$tmp/example.nix" -A script 2>"$tmp/build.err"); then
    ok "mkSmfMethodScript builds"
    if out=$("$script" bogus 2>&1); then
        bad "method script exits 0 on invalid argument"
    elif echo "$out" | grep -q 'Usage:'; then
        ok "method script rejects invalid argument with usage"
    else
        bad "method script fails on invalid argument but prints no usage: $out"
    fi
else
    bad "mkSmfMethodScript does not build"
    sed 's/^/    /' "$tmp/build.err"
fi

if manifest=$(nix-build --no-out-link "$tmp/example.nix" -A manifest 2>"$tmp/build.err"); then
    if "$svccfg" validate "$manifest" 2>"$tmp/validate.err"; then
        ok "svccfg validate accepts method-script example manifest"
    else
        bad "svccfg validate rejects method-script example manifest"
        sed 's/^/    /' "$tmp/validate.err"
    fi
    if rm -f "$tmp/example.db" \
       && SVCCFG_REPOSITORY="$tmp/example.db" "$svccfg" import "$manifest" \
       && SVCCFG_REPOSITORY="$tmp/example.db" "$svccfg" export site/example >"$tmp/example.export"; then
        ok "method-script example imports + exports from a scratch repo"
    else
        bad "method-script example fails scratch-repo import/export"
    fi
else
    bad "method-script example manifest does not build"
    sed 's/^/    /' "$tmp/build.err"
fi

# --- summary -----------------------------------------------------------------

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
