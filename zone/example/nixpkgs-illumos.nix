# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/b8b17876e68d7b476e15d90f7dd2d9bb9b07f252.tar.gz";
  sha256 = "01lxq0vx6b2ld9k5i2yigpp09444b9i7l6ba4ny14pzr15blllnd";
}
