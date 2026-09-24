# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/bd8cbc417af334ceddadcca26ee69e1428df881d.tar.gz";
  sha256 = "1fvai5adq613akmvbhn0l8gdlrhb15ki3czkwxxj5bcxgpkbwq28";
}
