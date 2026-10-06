# /etc/nixos/nixpkgs-illumos.nix of zone nixpkgs-native: the published commit of this repo the zone is built from,
# pinned in ../../pins (nixpkgs-illumos, bumped by pins/update.sh). ./pkgs.nix and ./system.nix both take it from
# here. A zone's own copy stands alone, the pin written out (../root.nix writes the image's); moving such a zone to
# another commit means changing url and sha256 in it (`nix-prefetch-url --unpack URL`), then `illumos-rebuild switch`.
let
  pin = (import ../../pins)."nixpkgs-illumos";
in
builtins.fetchTarball {
  url = pin.archive;
  sha256 = pin.hash;
}
