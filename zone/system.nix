# The system profile of a zone that runs Nix from this repo: the packages merged under
# /nix/var/nix/profiles/default, which /etc/profile puts first on PATH, root's shell resolves through, and the
# SMF nix-daemon method execs from. A zone's own /etc/nixos/system.nix supplies `pkgs` (an ../illumos.nix
# evaluation with that zone's bootstrap arguments) and its `nixSettings`, then calls this; zone/illumos-rebuild
# builds and switches it. See README.md for the files a zone keeps outside the profile.
{
  pkgs,
  # merged over the defaults below into etc/nix/nix.conf (./nix-conf.nix)
  nixSettings ? { },
}:
let
  services = import ./services.nix { inherit pkgs; };
  # ./illumos-rebuild on the profile's PATH, so a zone can rebuild and switch itself from /etc/nixos/system.nix
  illumosRebuild = pkgs.runCommand "illumos-rebuild" { } ''
    install -D -m 0555 ${./illumos-rebuild} $out/bin/illumos-rebuild
  '';
  # The programs to run setuid root, which the store cannot hold: the zone image and illumos-rebuild copy each into
  # /opt/nix/bin, setuid root, and /etc/profile puts that directory ahead of the profile
  setuidPrograms = pkgs.writeTextDir "etc/setuid-programs" ''
    bin/sudo
  '';
  nixConf = import ./nix-conf.nix {
    inherit pkgs;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # multi-user mode; the nixbld group and the users nixbld1..32 come with the zone image
      build-users-group = "nixbld";
      trusted-users = [ "root" ];
      # what Nix from the illumos series reports, and what ../illumos.nix builds for
      system = "x86_64-solaris";
    }
    // nixSettings;
  };
in
pkgs.buildEnv {
  name = "nix-zone-system";
  paths = with pkgs; [
    # .out only: buildEnv would otherwise pull outputs such as `man` that the package does not build here.
    # It carries nix-daemon's SMF manifest at lib/svc/manifest/site/, for illumos-rebuild to import.
    nixVersions.nix_2_35.out
    bashInteractive
    coreutils
    rsync
    gitMinimal
    gnugrep
    gawk
    # Mozilla CA bundle at etc/ssl/certs/ca-bundle.crt; the zone image symlinks /etc/ssl/certs to it and
    # /etc/profile exports SSL_CERT_FILE and NIX_SSL_CERT_FILE there. Without it git, curl and nix lose TLS.
    cacert
    # the SMF manifests of ./services.nix, at lib/svc/manifest/site/ for illumos-rebuild to import
    services.bundle
    # etc/nix/nix.conf, which the zone's /etc/nix/nix.conf points at
    nixConf
    illumosRebuild
    # programmable completion in interactive bash (/etc/bashrc loads its etc/profile.d/bash_completion.sh), which
    # NixOS enables by default; a command's completions are found beside it, under the profile's share/
    bash-completion
    # sudo, as the SmartOS base images have it (the zone image's /etc/sudoers); it runs from its setuid copy
    sudo
    setuidPrograms
  ];
  pathsToLink = [ "/bin" "/etc" "/lib" "/libexec" "/share" ];
  ignoreCollisions = true;
}
