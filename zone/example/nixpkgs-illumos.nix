# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/5ae3271fbdef545bdb6e04eb0ca8cafaef707fc7.tar.gz";
  sha256 = "0p32dm3jagv6n0xsw1dk0qylx5b742xy228bxzlgdp75zz8xwv14";
}
