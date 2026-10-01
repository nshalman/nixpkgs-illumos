# smartos-live's src stage (0-livesrc-stamp): `gmake` then `gmake install` in src with NATIVEDIR (the strap) and
# DESTDIR (their proto area), then `gmake install` in man.
#
# Their DESTDIR is read as well as written: src/Makefile.defs compiles against -isystem $(DESTDIR)/usr/include, links
# against -L$(DESTDIR)/usr/lib and lib (with -zassert-deflib -zfatal-warnings), and builds the node add-ons against
# $(DESTDIR)/usr/node/0.10/include/node, while installing into $(DESTDIR). Of their proto area src reads the illumos
# build's headers and libraries, illumos-extra's libexpat (node-expat) and node.js's headers; here those are given
# for reading (READPROTO, NODE_PROTO, set into Makefile.defs), and DESTDIR is this package's output. The rest of
# their tree it reads is made as their build has it: build.env (configure's defaults) and proto/buildstamp (the
# nightly's).
#
# The node add-ons dtrace-provider, qlocker and zonename are built by the strap's npm (1.4.3, which ignores
# package-lock.json), and their build fetches at build time: nan ~2.14 from the npm registry (2.14.2, the newest
# 2.14.x, believed to be what theirs got; header-only, so not shipped), fs-ext from the node-0.10 branch of
# joyent/node-fs-ext (eafdf1e7, as the platform's installed copy records), and node's headers from nodejs.org. Here
# nan is a pinned input put into the add-ons' node_modules, npm is pointed at no registry, and node-gyp is given
# illumos-extra's node 0.10.26 source (nodedir). fs-ext npm still installs by its git flow (clone, rev-list of
# node-0.10, archive), which is what writes the _resolved and _from the platform's package.json has, from a local
# repository of the pinned commit put in place of github's by git's url.<base>.insteadOf.
#
# Differences, on purpose: PYTHON (theirs /opt/local/bin/python2.7) is nixpkgs' python 2.7; the man pages written
# from markdown are made by ronn.js under the strap's node (theirs /opt/local/bin/node); make, perl and the other
# tools on PATH are nixpkgs' (theirs /usr/bin, then pkgsrc's). The `node` on PATH, which dtrace-provider's build.sh asks
# which architecture to build libusdt for, is the strap's (theirs pkgsrc's; both 32-bit, as the add-ons are); the
# `node-gyp` it runs by name is the strap npm's own (bin/node-gyp-bin; theirs from pkgsrc). npm runs under the strap's
# node (NPM_EXEC): the strap's bin/npm names #!/usr/node/0.10/bin/node, the build host's platform node, which is
# believed to be what runs it in theirs (their strap is built by the same recipe); both are node 0.10.26.
#
# Workaround: nixpkgs' python 2.7 reports its version as 2.7.18.12, which the node-gyp of npm 1.4.3 rejects (it checks
# platform.python_version() as a semver, in an environment of TERM and PATH alone); PYTHON is a wrapper that puts a
# sitecustomize reporting the first three components (2.7.18, what theirs reports) on PYTHONPATH.
{
  stdenv,
  fetchurl,
  fetchgit,
  runCommand,
  gitMinimal,
  python27,
  smartosLive,
  buildEnv,
  illumosProto,
  strapProto,
  ctfconvert,
  smartos-strap,
  smartos-extra,
}:

let
  nan = fetchurl {
    url = "https://registry.npmjs.org/nan/-/nan-2.14.2.tgz";
    sha256 = "0092x43h4ysm9zsxrxhkba1m2m1ybmnsn7dq58ppfgmd02hi98m9";
  };
  # its tree and its commit object, from which buildPhase makes the repository npm clones: a .git itself is not stable
  # (nixpkgs' manual on leaveDotGit), these are
  fsExt = fetchgit rec {
    url = "https://github.com/joyent/node-fs-ext.git";
    rev = "eafdf1e7d4d025f8ac718a2cc800bead16cbe0bb";
    leaveDotGit = true;
    postFetch = ''
      git -C $out cat-file commit ${rev} >$TMPDIR/commit
      rm -rf $out/.git
      mkdir $TMPDIR/tree
      (shopt -s dotglob && mv $out/* $TMPDIR/tree/)
      mv $TMPDIR/tree $TMPDIR/commit $out/
    '';
    hash = "sha256-x9HC5+KGODkagU0GPo882hz1o6ZcMdm8L/cfk3TABBs=";
  };
  # node's source, for node-gyp's headers: illumos-extra's tarball of node 0.10.26
  nodeSource = "${smartos-strap.illumosExtraSrc [ "node.js" ]}/node.js/node-v0.10.26.tar.gz";
  # what src reads from their DESTDIR: this package's output first, then libexpat and the illumos proto area
  readProto = [
    "$out"
    "${smartos-extra.libexpat}"
    illumosProto
  ];
  ctfBin = builtins.dirOf ctfconvert;
  makeFlags = [
    "NATIVEDIR=${strapProto}"
    "DESTDIR=$out"
    ''READPROTO="${toString readProto}"''
    "NODE_PROTO=${smartos-extra.node}/usr/node/0.10"
    "CTFCONVERT=${ctfBin}/ctfconvert"
    "CTFMERGE=${ctfBin}/ctfmerge"
    ''NPM_EXEC="${strapProto}/usr/node/0.10/bin/node ${strapProto}/usr/node/0.10/bin/npm"''
    "MAKE=make"
    ''PATH="${strapProto}/usr/bin:${strapProto}/usr/node/0.10/bin:${strapProto}/usr/node/0.10/lib/node_modules/npm/bin/node-gyp-bin:$PATH:/usr/bin:/usr/sbin:/sbin"''
  ];
  # nixpkgs' python 2.7, reporting its version as 2.7.18 (see above)
  pythonForNodeGyp = runCommand "python-for-node-gyp" { } ''
    mkdir -p $out/bin $out/lib
    cat >$out/lib/sitecustomize.py <<EOF
    import platform
    _python_version = platform.python_version
    platform.python_version = lambda: ".".join(_python_version().split(".")[:3])
    EOF
    cat >$out/bin/python2.7 <<EOF
    #!/bin/sh
    PYTHONPATH=$out/lib\''${PYTHONPATH:+:\$PYTHONPATH} exec ${python27}/bin/python2.7 "\$@"
    EOF
    chmod +x $out/bin/python2.7
  '';
in
stdenv.mkDerivation {
  pname = "smartos-live-src";
  version = "0-unstable-2026-09-03";

  src = smartosLive;

  nativeBuildInputs = [
    python27
    gitMinimal
  ];

  postPatch = ''
    # what is read and what is written, apart
    substituteInPlace src/Makefile.defs \
      --replace-fail 'CPPFLAGS =	$(SYSINCDIRS:%=-isystem $(DESTDIR)/%)' \
        'CPPFLAGS =	$(foreach d,$(READPROTO),$(SYSINCDIRS:%=-isystem $(d)/%))' \
      --replace-fail 'LDFLAGS =	$(SYSLIBDIRS:%=-L$(DESTDIR)/%)' \
        'LDFLAGS =	$(foreach d,$(READPROTO),$(SYSLIBDIRS:%=-L$(d)/%))' \
      --replace-fail 'NODE_INCS =	-isystem $(PREFIX_NODE)/include/node -I.' \
        'NODE_INCS =	-isystem $(NODE_PROTO)/include/node -I.' \
      --replace-fail 'NODE_LIBDIR =	-L$(PREFIX_NODE)/lib' 'NODE_LIBDIR =	-L$(NODE_PROTO)/lib'
    substituteInPlace src/Makefile --replace-fail 'PYTHON="/opt/local/bin/python2.7"' 'PYTHON="${pythonForNodeGyp}/bin/python2.7"'

    # configure's build.env
    cp ${buildEnv} build.env
    # the nightly's build stamp, which src reads from proto/buildstamp (CTF labels)
    mkdir -p proto
    cp ${illumosProto}/buildstamp proto/buildstamp

    # nan, as npm would have fetched it from the registry; for qlocker, where fs-ext (which npm installs below it)
    # finds it
    for d in node-dtrace-provider node-zonename node-qlocker; do
      mkdir -p src/$d/node_modules/nan
      tar xzf ${nan} -C src/$d/node_modules/nan --strip-components=1
    done
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR/home npm_config_registry=http://127.0.0.1:9/ npm_config_nodedir=$TMPDIR/node-v0.10.26
    # npm's prefix as theirs has it (their node's /usr/node/0.10, not the strap's store path): npm makes
    # $DESTDIR$prefix, which make's DESTDIR reaches it as
    export npm_config_prefix=/usr/node/0.10
    mkdir -p $HOME
    tar xzf ${nodeSource} -C $TMPDIR
    # fs-ext's repository, which npm clones: the pinned commit, made again from its tree and commit object (shallow:
    # its parent is not there), with the node-0.10 branch at it
    g=$TMPDIR/node-fs-ext.git
    git init -q --bare $g
    tree=$(export GIT_DIR=$g GIT_WORK_TREE=${fsExt}/tree GIT_INDEX_FILE=$TMPDIR/fs-ext.index && git add -A && git write-tree)
    grep -qx "tree $tree" ${fsExt}/commit
    commit=$(git -C $g hash-object -t commit -w ${fsExt}/commit)
    [ "$commit" = ${fsExt.rev} ]
    echo $commit >$g/shallow
    git -C $g update-ref refs/heads/node-0.10 $commit
    git config --global url.file://$g.insteadOf https://github.com/joyent/node-fs-ext.git
    (cd src && make -j$NIX_BUILD_CORES ${toString makeFlags})
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # their installs copy into directories their proto area already has (illumos' among them): the directories
    # src's and man's manifests list, and those their files are in
    mkdir -p $out
    awk '$1 == "d" { print $2 } $1 ~ /^[fsh]$/ { sub("=.*", "", $2); if (sub("/[^/]*$", "", $2)) print $2 }' \
      src/manifest man/manifest | sort -u | (cd $out && xargs mkdir -p)
    (cd src && make ${toString makeFlags} install)
    # as theirs, from man: its Makefile finds the tree by $(PWD). ronn.js dates its pages with the month it runs in
    # unless given one: here smartos-live's commit date, the month of theirs (built 2026-09-03)
    (cd man && make DESTDIR=$out install \
      RONNJS="${strapProto}/usr/node/0.10/bin/node $PWD/../tools/ronnjs/bin/ronn.js --date 2026-09-02")
    runHook postInstall
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;
}
