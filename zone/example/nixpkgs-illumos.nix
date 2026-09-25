# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/3c438104c45efc3a47b1984de0fa3c633dadddf2.tar.gz";
  sha256 = "0nc3bfmygf1h7chyaql7cbwz0aj9biz2akcsrw7fh2xqp1mlxcpv";
}
