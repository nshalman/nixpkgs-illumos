# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from.
# ./pkgs.nix and ./system.nix both take it from here; moving the zone to another commit means changing url and
# sha256 (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
builtins.fetchTarball {
  url = "https://github.com/nshalman/nixpkgs-illumos/archive/ba6106e65893778ed2aa5d4a2d0235816295d37e.tar.gz";
  sha256 = "1m15jz7kzb9lg79v5ymav1wsdgfigs67m1yhxlcrs97v9ay0nh1y";
}
