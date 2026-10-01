# smartos-live's own parts of SmartOS (src, man, later the local projects and the image), built from its pinned tree
# against the illumos build (smartos-illumos) and illumos-extra's packages (smartos-extra), each stage its own
# derivation rather than one step installing into a shared proto area.
{
  lib,
  newScope,
  fetchFromGitHub,
  smartos-illumos,
  smartos-strap,
  smartos-extra,
}:

lib.makeScope newScope (self: {
  # smartos-live at the commit SmartOS release-20260903 was built from (its gitstatus.json), the release
  # smartos-extra.platformReference is, so that what is built here can be compared with it
  smartosLive = fetchFromGitHub {
    owner = "TritonDataCenter";
    repo = "smartos-live";
    rev = "148c3689faede56d529a44469fdb989d24b29aa1";
    sha256 = "1zcrk6pgg12glq6a048k5qg72149vg567jf4a0wc1skqzx8g5fka";
  };

  inherit (smartos-extra) illumosProto ctfconvert;
  # smartos-live's NATIVEDIR, the strap it builds with (gcc, g++, node, npm)
  strapProto = smartos-strap.proto;

  # the src stage (0-livesrc-stamp): src and man
  livesrc = smartos-extra.finishPackage (self.callPackage ./livesrc.nix { });

  # the devpro stage (0-devpro-stamp): the C++ runtime libraries kept prebuilt in the tree
  devpro = self.callPackage ./devpro.nix { };
})
