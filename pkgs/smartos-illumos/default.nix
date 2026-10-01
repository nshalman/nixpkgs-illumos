# illumos as SmartOS builds it: illumos-joyent, built with SmartOS's proto.strap (../smartos-strap) the way
# smartos-live's tools/build_illumos builds it.
{
  lib,
  newScope,
  fetchFromGitHub,
}:

lib.makeScope newScope (self: {
  # illumos-joyent, SmartOS's illumos (smartos-live's projects/illumos), at a master commit of 2026-09-11 (an
  # illumos-gate merge). Pinned in ../../pins, and bumped deliberately.
  src =
    let
      pin = (import ../../pins)."illumos-joyent";
    in
    fetchFromGitHub {
      inherit (pin)
        owner
        repo
        rev
        hash
        ;
    };

  # A make to build make with: the gate's tools stage builds its own dmake with dmake.
  dmake-bootstrap = self.callPackage ./dmake-bootstrap.nix { };

  # a step of the build as tools/build_illumos runs it (bldenv illumos.sh)
  mkBldenvStep = self.callPackage ./bldenv.nix { };

  # the tools stage, with SmartOS's proto.strap from this repo
  tools = self.callPackage ./tools.nix { };

  # the rest of `dmake setup`: closed binaries, headers and mapfiles into the proto area
  setup = self.callPackage ./setup.nix { };

  # the AST message tools the nightly builds the AST libraries' message catalogs with
  msgcc = self.callPackage ./msgcc.nix { };

  # the nightly build: the proto area
  nightly = self.callPackage ./nightly.nix { };
})
