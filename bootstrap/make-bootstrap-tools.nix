# The two bootstrap files of a release, in the shape pkgs/stdenv/freebsd uses:
#
#   unpack.nar.xz           bash, coreutils, tar, xz: enough to unpack the other one. Fetched unpacked.
#   bootstrap-tools.tar.xz  the userland and the toolchain, every closure merged into one prefix
#
#   nix-build bootstrap/make-bootstrap-tools.nix --arg nixpkgs /path/to/illumos-26.05 -A build
#
# illumos-libc is left out on purpose. It is link-only: nothing may load its 2021 libc.so.1, and merged into the
# prefix it would share lib/amd64 with gcc's runtime libraries, a directory that is on RUNPATHs. It is also not a
# build product but the upstream sysroot plus header patches, which the first stdenv stage can make itself.
{
  nixpkgs ? <nixpkgs>,
}:

let
  bootstrap = import ./default.nix { inherit nixpkgs; };
  inherit (bootstrap) pkgs own;
  inherit (pkgs) lib runCommand;

  pack-all =
    packCmd: name: roots: fixups:
    runCommand name
      {
        nativeBuildInputs = [ pkgs.dumpnar ];
        exportReferencesGraph = lib.concatLists (lib.imap0 (i: r: [ "graph-${toString i}" r ]) roots);
        linkOnly = "${own.illumos-libc}";
      }
      ''
        base=$PWD/root
        mkdir $base
        for f in $(cat graph-* | grep '^/nix/store/' | sort -u); do
          [ "$f" = "$linkOnly" ] && continue
          cp -a $f/. $base/
          chmod -R u+w $base
        done
        cd $base
        rm -rf nix-support

        # A symlink into another store path would dangle once unpacked elsewhere; everything is in this prefix now.
        find . -type l | while read -r l; do
          t=$(readlink "$l")
          case "$t" in
            /nix/store/*)
              rest=''${t#/nix/store/*/}
              [ -e "$base/$rest" ] || { echo "dangling after merge: $l -> $t"; exit 1; }
              ln -sfn "$(realpath --relative-to="$(dirname "$l")" "$base/$rest")" "$l"
              ;;
          esac
        done

        ${fixups}

        ${packCmd}
      '';

  nar-all = pack-all "dumpnar . | xz -9 -e -T $NIX_BUILD_CORES > $out";
  tar-all = pack-all ''XZ_OPT="-9 -e -T $NIX_BUILD_CORES" tar cJf $out --hard-dereference --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 .'';
in
rec {
  unpack =
    nar-all "unpack.nar.xz"
      (with pkgs; [
        bashNonInteractive
        coreutils
        xz.bin
        gnutar
      ])
      ''
        rm -rf include lib/*.a lib/bash lib/pkgconfig share libexec
      '';

  bootstrap-tools = tar-all "bootstrap-tools.tar.xz" (
    bootstrap.userland
    ++ [
      own.illumos-ld
      own.gcc-illumos.out
      own.gcc-illumos.lib
    ]
  ) "rm -rf share/doc share/info share/man share/locale share/gtk-doc";

  build = runCommand "build" { } ''
    mkdir -p $out/on-server
    ln -s ${unpack} $out/on-server/unpack.nar.xz
    ln -s ${bootstrap-tools} $out/on-server/bootstrap-tools.tar.xz
  '';
}
