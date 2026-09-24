#!/usr/bin/env bash
#
# Test zone/illumos-rebuild against scratch state on a live illumos zone: a
# scratch profile under $TMPDIR-like /work, the real svccfg pointed at a
# scratch repository (SVCCFG_REPOSITORY), an svcadm stub that records
# its calls and an svcs stub that reports the states in $SVCS_STATES
# (online unless listed). Nothing touches the live SMF repository or the
# system profile.
#
# usage: illumos-rebuild.sh /etc/nixos/pkgs.nix
#
# Two generations are built: A declares services site/rebuild-test-a and
# site/rebuild-test-b, B declares rebuild-test-a only, with a new description.

set -uo pipefail

pkgsFile=${1:?usage: $0 /path/to/pkgs.nix}
top="$(cd "$(dirname "$0")/.." && pwd)"
rebuild="$top/zone/illumos-rebuild"
tmp=$(mktemp -d /work/rebuild-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

profile=$tmp/profiles/test
mkdir -p "$tmp/profiles"
export SVCCFG_REPOSITORY=$tmp/repo.db
export SVCADM=$tmp/svcadm-stub
export SVCADM_LOG=$tmp/svcadm.log
cat > "$SVCADM" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$SVCADM_LOG"
STUB
chmod +x "$SVCADM"
export SVCS=$tmp/svcs-stub
export SVCS_STATES=$tmp/svcs-states
: > "$SVCS_STATES"
cat > "$SVCS" <<'STUB'
#!/usr/bin/env bash
# `svcs -H -o state FMRI`: the state listed for FMRI in $SVCS_STATES ("FMRI STATE" lines), else online
fmri=${!#}
state=$(awk -v f="$fmri" '$1 == f { print $2 }' "$SVCS_STATES")
echo "${state:-online}"
STUB
chmod +x "$SVCS"

# a system: the manifests of the given services under lib/svc/manifest/site/
gen() { # <name> <description> <service>... -> writes $tmp/<name>.nix
    local name=$1 desc=$2; shift 2
    local svcs=""
    for s in "$@"; do
        svcs="$svcs (smf.mkSmfManifest { name = \"$s\"; category = \"site\"; description = \"$desc\"; start = { exec = \"/usr/bin/true\"; }; duration = \"transient\"; })"
    done
    cat > "$tmp/$name.nix" <<NIX
let
  pkgs = import $pkgsFile;
  smf = import $top/zone/smf-lib.nix { inherit pkgs; };
in
smf.mkSmfManifestBundle { name = "rebuild-test-$name"; manifests = [ $svcs ]; }
NIX
}
gen a "generation A" rebuild-test-a rebuild-test-b
gen b "generation B" rebuild-test-a

current() { (cd -P "$profile" 2>/dev/null && pwd -P); }
# svcadm restart returns before the instance is back; illumos-rebuild disables and enables it, temporarily and
# waiting for each (-s)
restarted() { diff <(grep " $1\$" "$SVCADM_LOG") <(printf 'disable -s -t %s\nenable -s -t %s\n' "$1" "$1") > /dev/null; }
exported() { "$SVCCFG_BIN" export "$1" >/dev/null 2>&1; }
SVCCFG_BIN=/usr/sbin/svccfg

# --- 1. first switch: profile set, services imported, nothing restarted -----

pathA=$(nix-build --no-out-link "$tmp/a.nix" 2>"$tmp/build.err") || { bad "generation A builds"; sed 's/^/    /' "$tmp/build.err"; exit 1; }
pathB=$(nix-build --no-out-link "$tmp/b.nix" 2>"$tmp/build.err") || { bad "generation B builds"; sed 's/^/    /' "$tmp/build.err"; exit 1; }
ok "both test generations build"

if "$rebuild" switch --config "$tmp/a.nix" --profile "$profile" >"$tmp/switch1.out" 2>&1; then
    ok "switch to A exits 0"
else
    bad "switch to A fails"; sed 's/^/    /' "$tmp/switch1.out"
fi
[ "$(current)" = "$pathA" ] && ok "profile points at A" || bad "profile is '$(current)', not $pathA"
exported site/rebuild-test-a && exported site/rebuild-test-b && ok "both services imported" || bad "services not imported"
[ ! -s "$SVCADM_LOG" ] && ok "first switch restarts nothing" || { bad "first switch called svcadm"; sed 's/^/    /' "$SVCADM_LOG"; }

# --- 2. switch to B: restart the kept service, remove the dropped one ------

: > "$SVCADM_LOG"
"$rebuild" switch --config "$tmp/b.nix" --profile "$profile" >"$tmp/switch2.out" 2>&1 || { bad "switch to B fails"; sed 's/^/    /' "$tmp/switch2.out"; }
[ "$(current)" = "$pathB" ] && ok "profile points at B" || bad "profile is '$(current)', not $pathB"
restarted svc:/site/rebuild-test-a:default && ok "kept service restarted, waiting for it" || { bad "kept service not restarted synchronously"; sed 's/^/    /' "$SVCADM_LOG"; }
grep -qx 'disable -s svc:/site/rebuild-test-b:default' "$SVCADM_LOG" && ok "dropped service disabled" || bad "dropped service not disabled"
! exported site/rebuild-test-b && ok "dropped service deleted from the repository" || bad "dropped service still in the repository"
exported site/rebuild-test-a && ok "kept service still in the repository" || bad "kept service missing"
grep -q 'generation B' <("$SVCCFG_BIN" export site/rebuild-test-a) && ok "kept service carries B's manifest" || bad "kept service still has A's manifest"

# --- 3. switch to the same generation: no restart ---------------------------

: > "$SVCADM_LOG"
"$rebuild" switch --config "$tmp/b.nix" --profile "$profile" >"$tmp/switch3.out" 2>&1 || bad "repeated switch fails"
[ ! -s "$SVCADM_LOG" ] && ok "unchanged switch restarts nothing" || { bad "unchanged switch called svcadm"; sed 's/^/    /' "$SVCADM_LOG"; }

# --- 4. rollback: back to A, restart, re-import the dropped service -------

: > "$SVCADM_LOG"
"$rebuild" rollback --profile "$profile" >"$tmp/rollback.out" 2>&1 || { bad "rollback fails"; sed 's/^/    /' "$tmp/rollback.out"; }
[ "$(current)" = "$pathA" ] && ok "rollback points the profile at A" || bad "after rollback profile is '$(current)'"
restarted svc:/site/rebuild-test-a:default && ok "rollback restarts the kept service" || bad "rollback did not restart"
exported site/rebuild-test-b && ok "rollback re-imports the dropped service" || bad "dropped service not back after rollback"

# --- 4b. a kept service that is not online is left alone -------------------

echo "svc:/site/rebuild-test-a:default disabled" > "$SVCS_STATES"
: > "$SVCADM_LOG"
"$rebuild" switch --config "$tmp/b.nix" --profile "$profile" >"$tmp/switch4.out" 2>&1 || { bad "switch to B fails"; sed 's/^/    /' "$tmp/switch4.out"; }
! grep -q 'svc:/site/rebuild-test-a:default' "$SVCADM_LOG" && ok "a kept service that is not online is not restarted" \
    || { bad "a disabled kept service was touched"; sed 's/^/    /' "$SVCADM_LOG"; }
: > "$SVCS_STATES"

# --- 5. list-generations ------------------------------------------------------

"$rebuild" list-generations --profile "$profile" >"$tmp/list.out" 2>&1
grep -qE '^ +1 ' "$tmp/list.out" && grep -qE '^ +2 ' "$tmp/list.out" && ok "list-generations shows generations 1 and 2" || { bad "list-generations output"; sed 's/^/    /' "$tmp/list.out"; }

# --- 6. a manifest svccfg rejects makes switch fail -------------------------

cat > "$tmp/bad.nix" <<NIX
let pkgs = import $pkgsFile; in
pkgs.runCommand "rebuild-test-bad" { } ''
  mkdir -p \$out/lib/svc/manifest/site
  echo '<service_bundle>' > \$out/lib/svc/manifest/site/broken.xml
''
NIX
if "$rebuild" switch --config "$tmp/bad.nix" --profile "$profile" >"$tmp/bad.out" 2>&1; then
    bad "switch exits 0 although svccfg rejected a manifest"
elif grep -q 'broken.xml' "$tmp/bad.out"; then
    ok "switch fails when svccfg rejects a manifest, naming it"
else
    bad "switch fails without naming the rejected manifest"; sed 's/^/    /' "$tmp/bad.out"
fi

# --- 7. build only ----------------------------------------------------------

out=$("$rebuild" build --config "$tmp/b.nix" 2>/dev/null)
[ "$out" = "$pathB" ] && ok "build prints the store path" || bad "build printed '$out'"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
