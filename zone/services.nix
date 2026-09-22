# Declarative SMF service list for a zone that runs Nix from this repo — the
# single source of truth for the services it ships. Consumed by:
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
  # The nix-daemon socket server: exposes
  # /nix/var/nix/daemon-socket/socket and serves build requests from
  # clients (root or unprivileged) running NIX_REMOTE=daemon.
  nix-daemon = smf.mkSmfManifest {
    name = "nix-daemon";
    description = "Nix build daemon";
    documentation = {
      name = "nix-daemon manual";
      uri = "https://nix.dev/manual/nix/stable/command-ref/nix-daemon";
    };
    start = {
      exec = "/nix/var/nix/profiles/default/bin/nix-daemon";
      timeout = 60;
      user = "root";
      group = "root";
    };
    # 'child' so SMF tracks the long-running nix-daemon process
    # directly; the daemon does not double-fork. ignore_error so a
    # single crash doesn't fall into maintenance while we're still
    # shaking out illumos portability issues (peer-cred, etc.).
    duration = "child";
    ignoreError = "core,signal";
  };

  manifests = [ nix-daemon ];

  bundle = smf.mkSmfManifestBundle { inherit manifests; };
}
