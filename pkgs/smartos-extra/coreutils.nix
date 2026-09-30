# GNU coreutils 9.7 as illumos-extra builds it for the platform (coreutils/Makefile): 64 bits only, its two patches,
# FORCE_UNSAFE_CONFIGURE=1 for configure and make; only readlink, seq and stat and their manuals installed.
#
# perl, on the build host's PATH there (/usr/bin/perl), makes configure choose help2man, which regenerates the
# manuals from the programs' --help; without it, man/dummy-man keeps the tarball's (stat.1 then lists %C, from a
# SELinux build, in the --terse format). The scope puts perl on PATH for every package (finishPackage).
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-coreutils";
  version = "9.7";
  dir = "coreutils";
  ver = "coreutils-9.7";
  patches = "Patches/*";
  bits = [ 64 ];
  configureEnv = "FORCE_UNSAFE_CONFIGURE=1";
  makeFlags = "FORCE_UNSAFE_CONFIGURE=1";
  install = suffix: ''
    mkdir -p $out/usr/bin $out/usr/share/man/man1
    for f in readlink seq stat; do
      cp coreutils-9.7-64${suffix}/src/$f $out/usr/bin
      cp -f coreutils-9.7-64${suffix}/man/$f.1 $out/usr/share/man/man1
    done
  '';
}
