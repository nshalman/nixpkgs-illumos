# The overlay's identity, for the platform's build stamp and gitstatus.json: its git checkout (src) as
# builtins.fetchGit sees it, which leaves untracked files out. kind is "clean" (src is its commit: rev, shortRev,
# date, the commit time), "release" (a clean commit that ../../release/cut.sh made: its time is the stamp in its
# release/release.json), "dirty" (the commit and changes to tracked files: rev <commit>-dirty) or "unknown" (src is
# not a git checkout, e.g. a copy of the overlay in the store). stamp, for a clean tree or a release, is the commit
# time as a SmartOS build stamp (YYYYMMDDTHHMMSSZ, UTC): the same commit, the same stamp. A dirty or unknown tree has
# none; the image step takes the time it runs. Either way the image step makes the stamp's last digit the flavor's
# (./stage-image.sh).
#
# release, for a clean tree or a release, is the last release's release/release.json (stamp, password, hash: the root
# password and its hash, chosen once when the release was cut), which the image step uses instead of a password of
# its own, so that every image of the commit has the same /etc/shadow; null before the first release, and for a dirty
# or unknown tree, whose images each make their own password.
{ src }:
let
  git = builtins.fetchGit src;
  # YYYYMMDDHHMMSS, UTC
  d = git.lastModifiedDate;
  stamp = "${builtins.substring 0 8 d}T${builtins.substring 8 6 d}Z";
  # the commit's own release/release.json, as fetchGit has it
  releaseFile = git.outPath + "/release/release.json";
  release = if builtins.pathExists releaseFile then builtins.fromJSON (builtins.readFile releaseFile) else null;
in
if !builtins.pathExists (src + "/.git") then
  {
    kind = "unknown";
    rev = null;
    shortRev = null;
    date = null;
    stamp = null;
    release = null;
  }
else if git ? dirtyRev then
  {
    kind = "dirty";
    rev = git.dirtyRev;
    shortRev = git.dirtyShortRev;
    date = git.lastModified;
    stamp = null;
    release = null;
  }
else
  {
    kind = if release != null && release.stamp == stamp then "release" else "clean";
    inherit (git) rev shortRev;
    date = git.lastModified;
    inherit stamp release;
  }
