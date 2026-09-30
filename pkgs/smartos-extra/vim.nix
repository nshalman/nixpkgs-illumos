# Vim 9.2 as illumos-extra builds it for the platform (vim/Makefile): 64 bits only, its two patches (one of them,
# Patches/defaults.vim, to runtime/defaults.vim), configure told STRIP=/usr/bin/strip, huge features, no GUI, X or
# NLS; installed by `make install`.
#
# The install writes the tools' #! lines from what `which.sh` finds on PATH (tools/efm_perl.pl: perl; tools/mve.awk:
# nawk, else gawk, else awk). It runs with their PATH order, the strap's usr/bin then the build host's /usr/bin, so
# the lines name /usr/bin/perl and /usr/bin/nawk, as the platform's do; with the build's PATH alone they would name
# no perl and nixpkgs' gawk, a store path. Only the paths are looked up; /usr/bin/perl has to exist on the build host.
{ mkAutoconf, strapBin }:

mkAutoconf {
  pname = "smartos-extra-vim";
  version = "9.2";
  dir = "vim";
  ver = "vim-9.2";
  tarball = "vim-9.2.tar.bz2";
  patches = "Patches/*";
  bits = [ 64 ];
  configureEnv = "STRIP=/usr/bin/strip";
  # the tarball also holds ._vim-9.2 and PaxHeader/vim-9.2 at its top
  unpackLeftovers = true;
  configureFlags = [
    "--disable-gui"
    "--disable-gtktest"
    "--disable-nls"
    "--with-features=huge"
    "--without-x"
  ];
  install = suffix: ''
    (cd vim-9.2-64${suffix} && env -i PATH="${strapBin}/bin:/usr/bin:$PATH" make V=1 DESTDIR=$out install)
  '';
}
