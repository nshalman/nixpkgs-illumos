# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/37115573b7a36ffc115f7c8c7d47b6e3d2aa8be6.tar.gz";
  sha256 = "1711wjqcq2qv98hly4hvjgz76ilxsy8brqp356zyipzqv6a2gv0z";
}
