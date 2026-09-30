# rsync 3.5.0 as illumos-extra builds it for the platform (rsync/Makefile): 64 bits only, configure run with LD_OPTIONS
# naming the package's mapfile_noexstk (configure only), the included popt and no zstd, lz4, xxhash or OpenSSL;
# installed by rsync/install-sfw (the program stripped, the manuals through sunman-stability).
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-rsync";
  version = "3.5.0";
  dir = "rsync";
  ver = "rsync-3.5.0";
  bits = [ 64 ];
  # $(BASE)/mapfile_noexstk: the illumos-extra directory, one above the build directory
  configureEnv = ''LD_OPTIONS="-M $PWD/../mapfile_noexstk"'';
  configureFlags = [
    "--with-included-popt"
    "--enable-ipv6"
    "--disable-zstd"
    "--disable-lz4"
    "--disable-xxhash"
    "--disable-openssl"
  ];
  install = suffix: ''
    DESTDIR=$out VERDIR=rsync-3.5.0-64${suffix} bash -e ./install-sfw
  '';
}
