# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/1014953bf9370c90593e6032fc8e1027357caf61.tar.gz";
  sha256 = "19sczpgbmvmqvbslfq3f7b9y1kfr2hpg3ch72xak0vhw2f447wqp";
}
