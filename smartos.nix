# The SmartOS build (smartos-live's platform: pkgs/smartos-*) with the package set it builds on, ./illumos.nix,
# taking the same arguments.
#   nix-build smartos.nix -A smartos-live.builderTools
args: import ./illumos.nix args
