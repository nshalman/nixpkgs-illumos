# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/b6a6a75babac37ebae9b4dc52c28f8c42f0b2bd6.tar.gz";
  sha256 = "04bpk99m1jh2i9fv4sdhx81zxaa0skm4kk49ccj80w8qwz1g1492";
}
