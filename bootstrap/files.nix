# The bootstrap files pkgs/stdenv/illumos starts from, as built by ./make-bootstrap-tools.nix. They are not hosted
# anywhere yet, so the location is an argument; on the builder that made them:
#   baseUrl = "file:///nix/store/...-build/on-server"
{ baseUrl }:
{
  unpack = import <nix/fetchurl.nix> {
    url = "${baseUrl}/unpack.nar.xz";
    hash = "sha256:002cad0c99598621b1bffbf4c29f716236108d2e4005596419aabfa129664a4c";
    name = "unpack";
    unpack = true;
  };
  bootstrapTools = import <nix/fetchurl.nix> {
    url = "${baseUrl}/bootstrap-tools.tar.xz";
    hash = "sha256:82dc6fb913fdc90c06b73746657a2a9a763f0c4eda2ceee155060c26c8122a89";
  };
}
