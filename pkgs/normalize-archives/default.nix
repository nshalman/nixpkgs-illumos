# A setup hook that makes the archives a package installs the same from one build to the next
# (./normalize-archives.pl: their member headers' times and owners, which the platform's ar takes from the files).
{ makeSetupHook, perl }:

makeSetupHook {
  name = "normalize-archives-hook";
  substitutions = {
    perl = "${perl}/bin/perl";
    script = ./normalize-archives.pl;
  };
} ./normalize-archives-hook.sh
