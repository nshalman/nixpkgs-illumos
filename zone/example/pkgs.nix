# /etc/nixos/pkgs.nix of zone nixpkgs-native: the package set the zone is built from, ../illumos.nix
# evaluated with the repo's bootstrap files (bootstrap/files.nix) from the release hosted in this zone's
# store, and the Nix source of the local nix-src mirror. The bootstrap URL and the mirror are this zone's own.
import /work/nixpkgs-illumos/illumos.nix {
  nixpkgs = /work/nixpkgs;
  bootstrapUrl = "file:///nix/store/hrw8yb81z5kfjgjymhwz3fq97gxxw689-build/on-server";
  nixSrc = builtins.fetchGit {
    url = "file:///work/nix-src.git";
    ref = "illumos-support-2.35";
    rev = "ff849c099603731091ef0df5d03baa2d39a70721";
  };
}
