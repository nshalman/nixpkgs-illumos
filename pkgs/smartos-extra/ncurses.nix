# ncurses 5.7 as illumos-extra builds it for the platform (ncurses/Makefile): 32 and 64 bits under /usr/gnu, its three
# patches, shared libraries only, no C++ binding, configure with a cache (-C) and CONFIG_SHELL=/bin/bash, RUNPATH
# /usr/gnu/lib (amd64 for 64-bit); installed by `make install`, 64-bit first, with /usr/bin first on PATH, then
# infocmp, tic, toe, tput and tset moved to usr/bin as g<name>, the headers to usr/include/ncurses, and the README to
# usr/gnu/share/doc/ncurses.
#
# Their build first moves the illumos proto area's libform.so, libmenu.so and libpanel.so links aside (hack-curses) and
# puts them back before installing (unhack-curses), so that nothing finds illumos' form, menu and panel libraries by
# those names while ncurses' own are built. The proto area here is read-only: the build is given a view of it without
# those links instead.
{
  cleanEnv,
  lib,
  runCommand,
  mkAutoconfAgainst,
  illumosProto,
}:

let
  hidden = [
    "libform.so"
    "libmenu.so"
    "libpanel.so"
  ];
  # illumosProto, as links, without the hidden names in usr/lib and usr/lib/amd64 (usr/lib/64 is a link to amd64)
  protoView = runCommand "illumos-proto-without-curses-links" { } ''
    link_except() {
      local src=$1 dst=$2 e n
      for e in "$src"/*; do
        n=''${e##*/}
        case " ${lib.concatStringsSep " " hidden} amd64 64 " in *" $n "*) continue ;; esac
        ln -s "$e" "$dst/$n"
      done
    }
    mkdir -p $out/usr/lib/amd64
    for e in ${illumosProto}/*; do [ "''${e##*/}" = usr ] || ln -s "$e" $out/; done
    for e in ${illumosProto}/usr/*; do [ "''${e##*/}" = lib ] || ln -s "$e" $out/usr/; done
    link_except ${illumosProto}/usr/lib $out/usr/lib
    link_except ${illumosProto}/usr/lib/amd64 $out/usr/lib/amd64
    ln -s amd64 $out/usr/lib/64
    for n in ${lib.concatStringsSep " " hidden}; do
      test ! -e $out/usr/lib/$n && test ! -e $out/usr/lib/64/$n
    done
  '';
in
(mkAutoconfAgainst protoView) {
  pname = "smartos-extra-ncurses";
  version = "5.7";
  dir = "ncurses";
  ver = "ncurses-5.7";
  patches = "Patches/*";
  bits = [
    32
    64
  ];
  prefix = "/usr/gnu";
  configureEnv = "CONFIG_SHELL=/bin/bash";
  configureFlags = [
    "-C"
    "--with-shared"
    "--without-cxx-binding"
    "--without-normal"
  ];
  configureFlags64 = [ "--libdir=/usr/gnu/lib/amd64" ];
  ldflags = "-R/usr/gnu/lib";
  ldflags64 = "-R/usr/gnu/lib/amd64";
  install = suffix: ''
    (cd ncurses-5.7-64${suffix} && ${cleanEnv} PATH=/usr/bin:$PATH make DESTDIR=$out install)
    (cd ncurses-5.7-32${suffix} && ${cleanEnv} PATH=/usr/bin:$PATH make DESTDIR=$out install)
    mkdir -p $out/usr/bin $out/usr/include
    for p in infocmp tic toe tput tset; do mv $out/usr/gnu/bin/$p $out/usr/bin/g$p; done
    rm -rf $out/usr/include/ncurses
    mv $out/usr/gnu/include/ncurses $out/usr/include
    mkdir -p $out/usr/gnu/share/doc/ncurses
    cp ncurses-5.7-32${suffix}/README $out/usr/gnu/share/doc/ncurses
  '';
}
