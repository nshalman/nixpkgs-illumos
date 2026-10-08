# The same for zip archives (./normalize-zips.pl): the jars and jmods openjdk 11's tools write, which take no
# SOURCE_DATE_EPOCH.
{ makeSetupHook, perl }:

makeSetupHook {
  name = "normalize-zips-hook";
  substitutions = {
    perl = "${perl}/bin/perl";
    script = ./normalize-zips.pl;
  };
} ./normalize-zips-hook.sh
