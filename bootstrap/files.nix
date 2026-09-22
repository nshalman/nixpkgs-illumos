# The bootstrap files pkgs/stdenv/illumos starts from, as built by ./make-bootstrap-tools.nix from that stdenv itself
# (the first ones came from the bridge; this is the fifth generation, and the release the previous one makes
# differs from it only in checksums computed over store paths). They are not hosted
# anywhere yet, so the location is an argument; on the builder that made them:
#   baseUrl = "file:///nix/store/...-build/on-server"
{ baseUrl }:
{
  unpack = import <nix/fetchurl.nix> {
    url = "${baseUrl}/unpack.nar.xz";
    hash = "sha256:9f5f79c618355da4605885605544aaf1e8e4163818e6f33d983532068b7c4185";
    name = "unpack";
    unpack = true;
  };
  bootstrapTools = import <nix/fetchurl.nix> {
    url = "${baseUrl}/bootstrap-tools.tar.xz";
    hash = "sha256:9db29a761d6bde6aa59d918f3d374d8dcfc4b1f9b1243b1978df370d6f1c4658";
  };
}
