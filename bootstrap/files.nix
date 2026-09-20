# The bootstrap files pkgs/stdenv/illumos starts from, as built by ./make-bootstrap-tools.nix from that stdenv itself
# (the first ones came from the bridge and had hashes 002cad0c... and 82dc6fb9...). They are not hosted
# anywhere yet, so the location is an argument; on the builder that made them:
#   baseUrl = "file:///nix/store/...-build/on-server"
{ baseUrl }:
{
  unpack = import <nix/fetchurl.nix> {
    url = "${baseUrl}/unpack.nar.xz";
    hash = "sha256:c0b1d537e289a6475a1fb4de6727fee6c4970bc8fb519a8b69dc8b8c03b265d9";
    name = "unpack";
    unpack = true;
  };
  bootstrapTools = import <nix/fetchurl.nix> {
    url = "${baseUrl}/bootstrap-tools.tar.xz";
    hash = "sha256:89c3187989c45fece678cf0c43eb3c786998931f6cf20139d4d73e557122f503";
  };
}
