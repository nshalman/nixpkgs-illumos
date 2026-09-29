# illumos as SmartOS builds it: illumos-joyent, built with SmartOS's proto.strap (../smartos-strap) the way
# smartos-live's tools/build_illumos builds it.
{
  lib,
  newScope,
  fetchFromGitHub,
}:

lib.makeScope newScope (self: {
  # illumos-joyent, SmartOS's illumos (smartos-live's projects/illumos), at a master commit of 2026-09-11 (an
  # illumos-gate merge). Pinned and bumped deliberately.
  src = fetchFromGitHub {
    owner = "TritonDataCenter";
    repo = "illumos-joyent";
    rev = "4012001854b4dd25a6190871dfe4d1cdda489ed9";
    sha256 = "0y4wkrbcv8xk0v7dvs1k0f2q0mnygshqscxyy8jyjc48a3jky0qy";
  };

  # A make to build make with: the gate's tools stage builds its own dmake with dmake.
  dmake-bootstrap = self.callPackage ./dmake-bootstrap.nix { };

  # a step of the build as tools/build_illumos runs it (bldenv illumos.sh)
  mkBldenvStep = self.callPackage ./bldenv.nix { };

  # the tools stage, with SmartOS's proto.strap from this repo
  tools = self.callPackage ./tools.nix { };
})
