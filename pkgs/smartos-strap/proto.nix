# proto.strap: the directory smartos-live builds illumos and illumos-extra against (ADJUNCT_PROTO, GNU_ROOT=usr/gnu,
# GNUC_ROOT=usr/gcc/10), put together in illumos-extra's install_strap order: binutils, the primary compiler with
# gcc-strapfix's additions, the strap packages in SUBDIRS order (a later one's file replaces an earlier one's:
# openssl3's libsunw_{crypto,ssl}.so links win over openssl1x's), then the adjunct, extracted last by smartos-live's
# tools/build_strap.
#
# A tree of symbolic links into the packages rather than a copy: real directories, each file a link to the file in
# its package, each package's own links kept as they are (relative, so they resolve inside this tree).
#
# Differences from theirs, on purpose:
#   - binutils: binutils-strap is 64-bit and installed without a program prefix, so usr/gnu/bin/g<tool> are links to
#     its bin/<tool>, and its tool directory is x86_64-pc-solaris2.11 (theirs: 32-bit, i386-pc-solaris2.11);
#   - gcc: usr/gcc/10 joins gcc10-illumos's two outputs (the compiler, and its runtime libraries in lib and
#     lib/amd64). gcc-strapfix's edits of the runtime libraries' RUNPATHs do not apply: those libraries are in the
#     store and already name their own directory. gcclibs.tar.gz holds them as they are;
#   - usr/bin/{gcc,g++,cpp} point at this tree's usr/gcc/10/bin, as gcc-strapfix's do at theirs;
#   - usr/gcc/10/bin/{gcc,g++} link with the pinned start files (./default.nix, startFiles), not the build host's.
{
  runCommand,
  binutils-strap,
  gcc10-illumos,
  startFiles,
  adjunct,
  cpp,
  bzip2,
  libexpat,
  libidn,
  libxml,
  libz,
  node,
  nss-nspr,
  openssl1x,
  openssl3,
  perl,
  idnkit,
}:

runCommand "smartos-strap-proto"
  {
    # illumos-extra's SUBDIRS in a strap build, then the adjunct
    packages = [
      cpp
      bzip2
      libexpat
      libidn
      libxml
      libz
      node
      nss-nspr
      openssl1x
      openssl3
      perl
      idnkit
      adjunct
    ];
  }
  ''
    # link_tree SRC DST: directories made, files linked, links copied; what is there already is replaced
    link_tree() {
      local src=$1 dst=$2 rel
      (cd "$src" && find . -mindepth 1 | sed 's#^\./##') | while IFS= read -r rel; do
        if [ -L "$src/$rel" ]; then
          rm -rf "$dst/$rel"; cp -P "$src/$rel" "$dst/$rel"
        elif [ -d "$src/$rel" ]; then
          [ -L "$dst/$rel" ] && rm -f "$dst/$rel"
          mkdir -p "$dst/$rel"
        else
          rm -rf "$dst/$rel"; ln -s "$src/$rel" "$dst/$rel"
        fi
      done
    }

    mkdir -p $out

    # binutils (GNU_ROOT)
    g=$out/usr/gnu
    mkdir -p $g/bin
    for d in include lib share x86_64-pc-solaris2.11; do
      if [ -d ${binutils-strap}/$d ]; then mkdir -p $g/$d; link_tree ${binutils-strap}/$d $g/$d; fi
    done
    for f in ${binutils-strap}/bin/*; do ln -s $f $g/bin/g''${f##*/}; done

    # the primary compiler (GNUC_ROOT) and gcc-strapfix
    c=$out/usr/gcc/10
    mkdir -p $c
    link_tree ${gcc10-illumos} $c
    link_tree ${gcc10-illumos.lib} $c
    find $c/lib -name 'libstdc++.so*-gdb.py' -delete
    [ -L $c/lib/64 ] || ln -s amd64 $c/lib/64
    # gcc and g++ link with the pinned start files (startFiles), as the scope's compilers do: the illumos build's
    # cw runs them (PRIMARY_CC), and links the shared objects it builds without -nostdlib (rcm modules, perl
    # extensions) with them; the smartos-live projects compile with usr/bin/gcc
    for f in gcc g++; do
      rm $c/bin/$f
      printf '#!/bin/sh\nexec %s -B%s/ "$@"\n' ${gcc10-illumos}/bin/$f ${startFiles} >$c/bin/$f
      chmod +x $c/bin/$f
    done
    mkdir -p $out/usr/bin
    for f in gcc g++ cpp; do ln -sf $c/bin/$f $out/usr/bin/$f; done
    (cd ${gcc10-illumos.lib}/lib && tar -czf $out/gcclibs.tar.gz lib{ssp,gcc_s,stdc++}.so* amd64/lib{ssp,gcc_s,stdc++}.so*)

    for p in $packages; do
      echo "adding $p"
      link_tree $p $out
    done
  ''
