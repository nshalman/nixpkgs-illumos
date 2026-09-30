# dialog 1.1-20111020 as illumos-extra builds it for the platform (dialog/Makefile): 32 bits, its patch, without
# Xdialog or the rpath hack, installed by `make install`. The top Makefile makes it wait for ncurses, but it links the
# proto area's curses (libcurses.so.1), as the platform's does.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-dialog";
  version = "1.1-20111020";
  dir = "dialog";
  ver = "dialog-1.1-20111020";
  patches = "Patches/*";
  configureFlags = [
    "--mandir=/usr/share/man"
    "--disable-Xdialog"
    "--disable-rpath-hack"
  ];
}
