# /etc/nix/nix.conf for a zone that runs Nix from this repo, rendered from an attribute set of settings: a
# list becomes a space-separated value, a boolean true or false, anything else its string. zone/system.nix
# folds the result into the system profile at etc/nix/nix.conf, and the zone's /etc/nix/nix.conf is a symlink
# to it, so the file changes with the generation and the daemon reads it on the restart illumos-rebuild does.
{ pkgs, settings }:
let
  inherit (pkgs) lib;
  value =
    v:
    if lib.isBool v then
      lib.boolToString v
    else if lib.isList v then
      lib.concatStringsSep " " (map toString v)
    else
      toString v;
in
pkgs.writeTextDir "etc/nix/nix.conf" (
  ''
    # Rendered by zone/nix-conf.nix from the nixSettings of this zone's system configuration; edit those.
  ''
  + lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = ${value v}") settings)
  + "\n"
  # A zone's local additions outside the system configuration, read last; `!include` skips a missing file. The
  # zone image ships nix.local.conf.example, which turns on the nixpkgs-illumos binary cache.
  + ''
    !include /etc/nix/nix.local.conf
  ''
)
