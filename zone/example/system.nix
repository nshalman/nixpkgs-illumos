# /etc/nixos/system.nix of zone nixpkgs-native. Rebuild and switch with zone/illumos-rebuild.
import (import ./nixpkgs-illumos.nix + "/zone/system.nix") {
  pkgs = import ./pkgs.nix;
  nixSettings = {
    # the store also holds outputs the earlier Nix built as x86_64-illumos and x86_64-sunos
    extra-platforms = [ "x86_64-illumos" "x86_64-sunos" ];
    # zone.cpu-cap is 600 (6 CPUs) while all 16 processors of the host are visible
    cores = 6;
    # keep the build-time dependencies of rooted paths (the stdenv chain, meson, python) across collections
    keep-outputs = true;
  };
}
