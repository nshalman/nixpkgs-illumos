# Declarative SMF service list for a zone that runs Nix from this repo — the
# single source of truth for the services it ships, except nix-daemon: its
# manifest comes with Nix (lib/svc/manifest/site/nix-daemon.xml), which
# zone/system.nix also puts in the profile. Consumed by:
#
#   - zone/system.nix: `bundle` is folded into the system profile, so the
#     manifests are visible at
#     /nix/var/nix/profiles/default/lib/svc/manifest/site/, where
#     zone/illumos-rebuild imports them on every switch.
#
# To add a service: define it with smf-lib's mkSmfManifest (and
# mkSmfMethodScript if it needs tailscale-style start/stop logic), add
# it to `manifests`, rebuild. Test with ../tests/smf-lib.sh.
{ pkgs }:
let
  smf = import ./smf-lib.nix { inherit pkgs; };
in
rec {
  manifests = [ ];

  bundle = smf.mkSmfManifestBundle { inherit manifests; };
}
