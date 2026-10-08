# The generic package set, ../illumos.nix: what runs on any illumos distribution, with nothing of the SmartOS build
# (../smartos.nix, downstream of it) in it or needed by it:
#   independent: the set has no SmartOS attribute (smartos-*; the strap toolchain, gcc10-illumos and binutils-strap;
#                rust-bhyve, which builds against smartos-live's proto area), and the generic packages, the Nix
#                installer and the zone image's inputs evaluate without one (their .drv files are written).
#   nix-build tests/generic.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{ pkgs }:

let
  inherit (pkgs) lib;
  smartos = lib.filter (
    n:
    lib.hasPrefix "smartos" n
    || lib.elem n [
      "gcc10-illumos"
      "binutils-strap"
      "rust-bhyve"
    ]
  ) (lib.attrNames pkgs);
  generic = with pkgs; {
    inherit
      illumos-sysroot
      illumos-libc
      illumos-ld
      gcc-illumos
      tribblix-jdk-bin
      openjdk11-illumos
      nixInstallerTarball
      ;
    nix = nixVersions.nix_2_35;
    inherit (rust-illumos-bin) rustc cargo;
    zone-image = import ../zone/image.nix { inherit pkgs; };
  };
  # each one's .drv, evaluated here, without making the check depend on building it
  drvs = lib.mapAttrsToList (n: d: "${n} ${builtins.unsafeDiscardStringContext d.drvPath}") generic;
in
{
  independent = pkgs.runCommand "generic-independent" { } ''
    ${lib.optionalString (smartos != [ ]) ''
      echo "SmartOS attributes in the generic set: ${toString smartos}"
      exit 1
    ''}
    printf '%s\n' ${lib.escapeShellArgs drvs}
    echo "ok   ${toString (lib.length drvs)} generic packages evaluate, and no SmartOS attribute is in the set"
    touch $out
  '';
}
