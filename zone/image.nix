# What a SmartOS joyent-brand zone image is made of, for ./make-joyent-image to assemble on a ZFS dataset:
#
#   root.tar        ./root.nix: /etc, /var and the brand's mount points
#   system          the system profile (./system.nix with no zone-specific settings), which the image's
#                   /nix/var/nix/profiles/default is generation 1 of; /etc/nixos/system.nix evaluates to it
#   store-paths     the profile's closure, which the image ships in /nix/store
#   registration    its validity registration, for `nix-store --load-db`
#
# The store is copied from the building host's; it is not packed into a derivation, which would hold a second
# copy of it.
{ pkgs }:

let
  root = import ./root.nix { inherit pkgs; };
  system = import ./system.nix { inherit pkgs; };
  closure = pkgs.closureInfo { rootPaths = [ system ]; };
in
pkgs.runCommand "illumos-zone-image-inputs" { } ''
  mkdir -p "$out"
  ln -s ${root}/root.tar "$out/root.tar"
  ln -s ${root}/contents "$out/root-contents"
  ln -s ${system} "$out/system"
  cp ${closure}/store-paths ${closure}/registration "$out/"
''
