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

        # Closures in the order of `roots`, so that a later root's files win. Put the userland last: gcc's closure
        # holds the builds of bash, sed, binutils, ... it was built with, the userland holds the current ones.
        : > order
        for g in $(ls graph-* | sort -t- -k2 -n); do
          grep '^/nix/store/' $g | sort -u | while read -r f; do
            grep -qxF "$f" order || echo "$f" >> order
          done
        done

        # Two store paths of different names putting different files at the same place is a packaging error,
        # unless listed in allowedCollisions. Same name means two builds of one package; the later wins.
        : > files
        grep -vxF "$linkOnly" order | while read -r f; do
          name=''${f#/nix/store/*-}
          (cd $f && find . \( -type f -o -type l \) ! -path './nix-support/*') | sed "s|\$|\t$name\t$f|" >> files
        done
        awk -F'\t' '{ if (($1 in n) && n[$1] != $2) print $1 "\t" p[$1] "\t" $3; n[$1] = $2; p[$1] = $3 }' files > candidates
        : > bad
        while IFS="$(printf '\t')" read -r p one two; do
          # A symlink to the same place in another store path stands for the file the merge provides anyway.
          for x in "$one" "$two"; do
            if [ -L "$x/$p" ]; then case "$(readlink "$x/$p")" in /nix/store/*/"''${p#./}") continue 2 ;; esac; fi
          done
          cmp -s "$one/$p" "$two/$p" || echo "$p ($one, $two)" >> bad
        done < candidates
        grep -vE "^(${lib.concatStringsSep "|" allowedCollisions}) " bad > bad.unexpected || true
        if [ -s bad.unexpected ]; then echo "colliding files:"; cat bad.unexpected; exit 1; fi

        grep -vxF "$linkOnly" order | while read -r f; do
          (cd $f && find . \( -type f -o -type l \) ! -path './nix-support/*') | while read -r p; do
            if [ -L "$f/$p" ]; then case "$(readlink "$f/$p")" in /nix/store/*/"''${p#./}") continue ;; esac; fi
            mkdir -p "$base/$(dirname "$p")"
            rm -f "$base/$p"
            cp -a "$f/$p" "$base/$p"
          done
        done
        chmod -R u+w $base
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
        # Order matters, see pack-all: the userland last.
        [
          paths.illumos-ld
          paths.gcc-illumos.out
          paths.gcc-illumos.lib
        ]
        ++ bootstrap.userland
      )
      # binutils brings GNU ld; the link-editor of this platform is illumos-ld, put back below. Some scripts name the
      # interactive bash, which brings its own bin/bash; the stdenv shell is the non-interactive one, also put back.
      [
        "\\./bin/ld"
        "\\./bin/bash"
        "\\./bin/sh"
      ]
      ''
        # gcc looks for its tools in PREFIX/x86_64-pc-solaris2.11/bin before PATH, and binutils, now in the same
        # prefix, put GNU ld there.
        rm -f bin/ld bin/ld.bfd bin/ld.gold */bin/ld */bin/ld.bfd */bin/ld.gold
        cp -a ${paths.illumos-ld}/bin/ld bin/ld
        for d in */bin; do [ -e "$d/as" ] && ln -s ../../bin/ld "$d/ld"; done
        [ "$(readlink x86_64-pc-solaris2.11/bin/ld)" = ../../bin/ld ] || { echo "gcc's tool directory is not where expected"; exit 1; }

        rm -f bin/bash
        cp -a ${pkgs.bashNonInteractive}/bin/bash bin/bash

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
