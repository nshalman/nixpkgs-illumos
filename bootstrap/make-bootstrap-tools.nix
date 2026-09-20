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
  paths ? import ../stdenv/bridge-paths-gen2.nix,
}:

let
  bootstrap = import ./default.nix { inherit nixpkgs paths; };
  inherit (bootstrap) pkgs;
  inherit (pkgs) lib runCommand;

  pack-all =
    packCmd: name: roots: allowedCollisions: fixups:
    runCommand name
      {
        nativeBuildInputs = [ pkgs.dumpnar ];
        exportReferencesGraph = lib.concatLists (
          lib.imap0 (i: r: [
            "graph-${toString i}"
            r
          ]) roots
        );
        linkOnly = "${paths.illumos-libc}";
      }
      ''
        base=$PWD/root
        mkdir $base
        for f in $(cat graph-* | grep '^/nix/store/' | sort -u); do
          [ "$f" = "$linkOnly" ] && continue
          # Two closures putting different files at the same place would make the result depend on copy order.
          (cd $f && find . \( -type f -o -type l \) ! -path './nix-support/*') | while read -r p; do
            if [ -e "$base/$p" ] || [ -L "$base/$p" ]; then
              cmp -s "$f/$p" "$base/$p" || echo "$p ($f)" >> $NIX_BUILD_TOP/collisions
            fi
          done
          cp -a $f/. $base/
          chmod -R u+w $base
        done
        if [ -s $NIX_BUILD_TOP/collisions ]; then
          grep -vE "^(${lib.concatStringsSep "|" allowedCollisions}) " $NIX_BUILD_TOP/collisions > $NIX_BUILD_TOP/bad || true
          if [ -s $NIX_BUILD_TOP/bad ]; then echo "colliding files:"; cat $NIX_BUILD_TOP/bad; exit 1; fi
        fi
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
      [ ]
      ''
        rm -rf include lib/*.a lib/bash lib/pkgconfig share libexec
      '';

  # The toolchain is the one the bridge ran on (`paths`), not one built by it: the userland is linked against that
  # gcc's runtime libraries, and a release must ship the libraries its programs were linked against.
  bootstrap-tools =
    tar-all "bootstrap-tools.tar.xz"
      (
        bootstrap.userland
        ++ [
          paths.illumos-ld
          paths.gcc-illumos.out
          paths.gcc-illumos.lib
        ]
      )
      # binutils brings GNU ld; the link-editor of this platform is illumos-ld, put back below.
      [ "\\./bin/ld" ]
      ''
        # gcc looks for its tools in PREFIX/x86_64-pc-solaris2.11/bin before PATH, and binutils, now in the same
        # prefix, put GNU ld there.
        rm -f bin/ld bin/ld.bfd bin/ld.gold */bin/ld */bin/ld.bfd */bin/ld.gold
        cp -a ${paths.illumos-ld}/bin/ld bin/ld
        for d in */bin; do [ -e "$d/as" ] && ln -s ../../bin/ld "$d/ld"; done
        [ "$(readlink x86_64-pc-solaris2.11/bin/ld)" = ../../bin/ld ] || { echo "gcc's tool directory is not where expected"; exit 1; }

        # gettext's spit is a python script.
        rm -f bin/spit
        rm -rf share/doc share/info share/man share/locale share/gtk-doc
      '';

  build = runCommand "build" { } ''
    mkdir -p $out/on-server
    ln -s ${unpack} $out/on-server/unpack.nar.xz
    ln -s ${bootstrap-tools} $out/on-server/bootstrap-tools.tar.xz
  '';
}
