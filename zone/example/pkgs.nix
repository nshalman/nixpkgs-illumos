# /etc/nixos/pkgs.nix of zone nixpkgs-native: the package set the zone is built from, illumos.nix of the published
# nixpkgs-illumos (./nixpkgs-illumos.nix) on its defaults: the nixpkgs, Nix source and bootstrap files it pins.
import (import ./nixpkgs-illumos.nix + "/illumos.nix") { }
