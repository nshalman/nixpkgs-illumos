# The overlay's identity, for the platform's build stamp and gitstatus.json: its git checkout (src) as
# builtins.fetchGit sees it, which leaves untracked files out. kind is "clean" (src is its commit: rev, shortRev,
# date, the commit time), "dirty" (the commit and changes to tracked files: rev <commit>-dirty) or "unknown" (src is
# not a git checkout, e.g. a copy of the overlay in the store). stamp, for a clean tree only, is the commit time as a
# SmartOS build stamp (YYYYMMDDTHHMMSSZ, UTC): the same commit, the same stamp. A dirty or unknown tree has none; the
# image step takes the time it runs. Either way the image step makes the stamp's last digit the flavor's
# (./stage-image.sh).
{ src }:
let
  git = builtins.fetchGit src;
  # YYYYMMDDHHMMSS, UTC
  d = git.lastModifiedDate;
in
if !builtins.pathExists (src + "/.git") then
  {
    kind = "unknown";
    rev = null;
    shortRev = null;
    date = null;
    stamp = null;
  }
else if git ? dirtyRev then
  {
    kind = "dirty";
    rev = git.dirtyRev;
    shortRev = git.dirtyShortRev;
    date = git.lastModified;
    stamp = null;
  }
else
  {
    kind = "clean";
    inherit (git) rev shortRev;
    date = git.lastModified;
    stamp = "${builtins.substring 0 8 d}T${builtins.substring 8 6 d}Z";
  }
