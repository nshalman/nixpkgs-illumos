# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/d844029f01eb713b312119f77270a59b289f4ffd.tar.gz";
  sha256 = "173w12a1qmi6ilg6p39pj41mgyyqxvqjh9avhx60n56ywy8zs8pk";
}
