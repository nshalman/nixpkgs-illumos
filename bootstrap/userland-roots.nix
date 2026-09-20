# The store paths a release is packed from, for tests/audit-closure.sh:
#   nix-build bootstrap/userland-roots.nix --arg pkgs 'import ./illumos.nix { ... }' --no-out-link
{ pkgs }:
import ./userland.nix pkgs
++ [
  pkgs.illumos-ld
  pkgs.gcc-illumos.out
  pkgs.gcc-illumos.lib
]
