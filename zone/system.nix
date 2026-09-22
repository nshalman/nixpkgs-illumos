# The system profile of a zone that runs Nix from this repo: the packages merged under
# /nix/var/nix/profiles/default, which /etc/profile puts first on PATH, root's shell resolves through, and the
# SMF nix-daemon method execs from. A zone's own /etc/nixos/system.nix supplies `pkgs` (an ../illumos.nix
# evaluation with that zone's bootstrap arguments) and calls this; zone/illumos-rebuild builds and switches it.
{ pkgs }:
let
  services = import ./services.nix { inherit pkgs; };
in
pkgs.buildEnv {
  name = "nix-zone-system";
  paths = with pkgs; [
    # .out only: buildEnv would otherwise pull outputs such as `man` that the package does not build here
    nixVersions.nix_2_35.out
    bashInteractive
    coreutils
    rsync
    gitMinimal
    # Mozilla CA bundle at etc/ssl/certs/ca-bundle.crt; the zone image symlinks /etc/ssl/certs to it and
    # /etc/profile exports SSL_CERT_FILE and NIX_SSL_CERT_FILE there. Without it git, curl and nix lose TLS.
    cacert
    # the SMF manifests of ./services.nix, at lib/svc/manifest/site/ for illumos-rebuild to import
    services.bundle
  ];
  pathsToLink = [ "/bin" "/etc" "/lib" "/libexec" "/share" ];
  ignoreCollisions = true;
}
