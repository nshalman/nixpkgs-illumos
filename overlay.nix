# The same package set as ./default.nix, as a nixpkgs overlay.
final: _prev: import ./pkgs { inherit (final) callPackage; }
