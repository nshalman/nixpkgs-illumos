# The bootstrap files pkgs/stdenv/illumos starts from, as built by ./make-bootstrap-tools.nix from that stdenv itself
# (the first ones came from the bridge; this is the fifth generation, and the release the previous one makes
# differs from it only in checksums computed over store paths). They are hosted at https://www.shalman.org/files
# under their store path names. baseUrl fetches them instead from a directory holding them under the names
# make-bootstrap-tools.nix gives them, such as its on-server output on the builder that made them:
#   baseUrl = "file:///nix/store/...-build/on-server"
{
  baseUrl ? null,
}:
let
  location =
    hosted: local:
    if baseUrl == null then "https://www.shalman.org/files/${hosted}" else "${baseUrl}/${local}";
in
{
  unpack = import <nix/fetchurl.nix> {
    url = location "42zkia7ysyali7qbsvfx2fwrv03nn6s5-unpack.nar.xz" "unpack.nar.xz";
    hash = "sha256:9f5f79c618355da4605885605544aaf1e8e4163818e6f33d983532068b7c4185";
    name = "unpack";
    unpack = true;
  };
  bootstrapTools = import <nix/fetchurl.nix> {
    url = location "46san2rv6nw7baw1dsm6m0jxffz9s5xb-bootstrap-tools.tar.xz" "bootstrap-tools.tar.xz";
    hash = "sha256:9db29a761d6bde6aa59d918f3d374d8dcfc4b1f9b1243b1978df370d6f1c4658";
    name = "bootstrap-tools.tar.xz";
  };
}
