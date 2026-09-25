# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/c13b4f18ed661fbf1d85abb520003144cb5db9c7.tar.gz";
  sha256 = "0f8dspp9gbf8lkw0cjv7as9fr4c53db20gnpraa0r321m9ibzgs6";
}
