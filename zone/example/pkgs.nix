# /etc/nixos/pkgs.nix of zone nixpkgs-native: the package set the zone is built from, ../illumos.nix
# evaluated with the bootstrap files and the Nix source this zone was bootstrapped with. The bootstrap URL
# and the nix-src mirror are this zone's own; a fresh zone gives the release it was made from.
import /work/nixpkgs-illumos/illumos.nix {
  nixpkgs = /work/nixpkgs;
  bootstrapUrl = "file:///nix/store/w1fw10cq694g76id1xn29m6wqi7l7qgg-build/on-server";
  bootstrapFiles = import /work/files-A4.nix {
    baseUrl = "file:///nix/store/w1fw10cq694g76id1xn29m6wqi7l7qgg-build/on-server";
  };
  nixSrc = builtins.fetchGit {
    url = "file:///work/nix-src.git";
    ref = "illumos-support-2.35";
    rev = "ff849c099603731091ef0df5d03baa2d39a70721";
  };
}
