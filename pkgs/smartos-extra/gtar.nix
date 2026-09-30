# GNU tar 1.23 as illumos-extra builds it for the platform (gtar/Makefile): 32 bits, its patch, configure run with
# LD_OPTIONS naming the package's mapfile_noexstk (configure only: make runs under `env -`), --program-prefix=g, and
# the tar program installed as usr/bin/gtar.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-gtar";
  version = "1.23";
  dir = "gtar";
  ver = "tar-1.23";
  tarball = "tar-1.23.tar.bz2";
  patches = "Patches/*";
  # $(BASE)/mapfile_noexstk: the illumos-extra directory, one above the build directory
  configureEnv = ''LD_OPTIONS="-M $PWD/../mapfile_noexstk"'';
  configureFlags = [
    "--with-rmt=/usr/sbin/rmt"
    "--libexecdir=/usr/sbin"
    "--program-prefix=g"
  ];
  install = suffix: ''
    mkdir -p $out/usr/bin
    install -m 0555 tar-1.23-32${suffix}/src/tar $out/usr/bin/gtar
  '';
}
