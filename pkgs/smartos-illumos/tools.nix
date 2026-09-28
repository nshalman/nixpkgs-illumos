# illumos-joyent's tools stage (usr/src/tools: cw, the ctf tools, dmake, onbld's scripts, sgs, the svc tools, ...),
# built the way smartos-live's tools/build_illumos starts the illumos build: `bldenv illumos.sh` with MAKE naming a
# dmake from the build host, then `dmake install` in usr/src/tools (the Makefile's bldtools target). The output is
# the tools proto, $SRC/tools/proto/root_i386-nd, whose opt/onbld the nightly then builds with.
#
# illumos.sh is written as smartos-live's configure writes it (generate_env), with this repo's pieces in place of
# its directories: proto.strap is smartos-strap.proto (ADJUNCT_PROTO, GNU_ROOT, GNUC_ROOT), the pkgsrc tools it
# names under /opt/local are nixpkgs' (FLEX, BISON, GM4, GNUXGETTEXT, PERL, PYTHON3 3.12), and NATIVE_ADJUNCT, the
# prefix native tools build against (/opt/local there), joins the nixpkgs libraries they use: libxml2 (svccfg) and
# sqlite (smatch), and zlib's header alone (the ctf tools' libctf includes zlib.h but dlopen()s the platform's
# /usr/lib/libz.so.1; the platform's /usr/include has no zlib.h, and zlib's library is 64-bit where these tools are
# 32).
#
# From the build host, as for any illumos build: bldenv's ksh93, its PATH of /usr/bin, /usr/sbin and friends, the
# ELF tools illumos.sh names (/usr/bin/elfdump, nm, strip, ...), and the native tools' -I/usr/include.
#
# bldenv prints two messages that do no harm: "-L: unknown option" (smartos-live's NIGHTLY_OPTIONS has an L that
# bldenv's getopts does not know; it only acts on t and F) and newtask's refusal to move the build user into root's
# project.
#
# Not done here: the rest of `dmake setup` (closed binaries, headers into the proto area), which belongs to the
# nightly.
{
  lib,
  stdenv,
  symlinkJoin,
  src,
  dmake-bootstrap,
  smartos-strap,
  flex,
  bison,
  gnum4,
  gettext,
  perl,
  python312,
  libxml2,
  sqlite,
  zlib,
}:

let
  proto = smartos-strap.proto;
  nativeAdjunct = symlinkJoin {
    name = "smartos-illumos-native-adjunct";
    paths = map lib.getDev [
      libxml2
      sqlite
      zlib
    ] ++ map lib.getLib [
      libxml2
      sqlite
    ];
  };
in
stdenv.mkDerivation {
  pname = "smartos-illumos-tools";
  version = "0-unstable-2026-09-11";

  inherit src;

  # The tools build in the tree itself.
  unpackPhase = ''
    runHook preUnpack
    cp -r $src illumos
    chmod -R u+w illumos
    runHook postUnpack
  '';

  dontConfigure = true;

  # the gate compiles with its own flag set, through cw; nixpkgs' hardening flags are not part of that
  hardeningDisable = [ "all" ];

  buildPhase = ''
    runHook preBuild
    ws=$PWD/illumos
    mkdir -p proto

    # smartos-live configure's generate_env, as illumos.sh; GATE as build_illumos sets it, from the illumos-joyent
    # commit here rather than a build time
    cat >illumos/illumos.sh <<EOF
    NIGHTLY_OPTIONS="-CiLmMNnt";			export NIGHTLY_OPTIONS
    GATE="joyent_${src.rev or "unknown"}";		export GATE
    CODEMGR_WS="$ws";				export CODEMGR_WS
    MAX_JOBS=''${NIX_BUILD_CORES:-1};		export MAX_JOBS
    DMAKE_MAX_JOBS=''${NIX_BUILD_CORES:-1};		export DMAKE_MAX_JOBS
    PARENT_WS="";					export PARENT_WS
    STAFFER="nobody";				export STAFFER
    BUILD_PROJECT="";				export BUILD_PROJECT
    LOCKNAME="nix_nightly.lock";			export LOCKNAME
    ATLOG="\$CODEMGR_WS/log";			export ATLOG
    LOGFILE="\$ATLOG/nightly.log";			export LOGFILE
    MACH=\`uname -p\`;				export MACH
    ON_CLOSED_BINS="\$CODEMGR_WS/closed";		export ON_CLOSED_BINS
    ROOT="$PWD/proto";				export ROOT
    ADJUNCT_PROTO="${proto}";			export ADJUNCT_PROTO
    NATIVE_ADJUNCT="${nativeAdjunct}";		export NATIVE_ADJUNCT
    SRC="\$CODEMGR_WS/usr/src";			export SRC
    VERSION="\$GATE";				export VERSION
    PARENT_ROOT="$PWD/proto";			export PARENT_ROOT
    MAKEFLAGS=ek;					export MAKEFLAGS
    UT_NO_USAGE_TRACKING="1";			export UT_NO_USAGE_TRACKING
    MULTI_PROTO="no";				export MULTI_PROTO
    BUILD_TOOLS="\$SRC/tools/proto/root_\''${MACH}-nd/opt";	export BUILD_TOOLS
    SPRO_ROOT=/opt/SUNWspro;			export SPRO_ROOT
    SPRO_VROOT=\$SPRO_ROOT;				export SPRO_VROOT
    GNU_ROOT="${proto}/usr/gnu";			export GNU_ROOT
    __GNUC="";					export __GNUC
    GNUC_ROOT="${proto}/usr/gcc/10";		export GNUC_ROOT
    PRIMARY_CC="gcc10,${proto}/usr/gcc/10/bin/gcc,gnu";	export PRIMARY_CC
    PRIMARY_CCC="gcc10,${proto}/usr/gcc/10/bin/g++,gnu";	export PRIMARY_CCC
    SHADOW_CCS=" smatch,\$BUILD_TOOLS/onbld/bin/\$MACH/smatch,smatch";	export SHADOW_CCS
    SHADOW_CCCS="";					export SHADOW_CCCS
    FLEX=${flex}/bin/flex;				export FLEX
    GNUXGETTEXT=${gettext}/bin/xgettext;		export GNUXGETTEXT
    PYTHON3=${python312}/bin/python3.12;		export PYTHON3
    PYTHON3_VERSION=3.12;				export PYTHON3_VERSION
    PYTHON3_PKGVERS=-312;				export PYTHON3_PKGVERS
    PYTHON3_SUFFIX="";				export PYTHON3_SUFFIX
    BLD_JAVA_11="";					export BLD_JAVA_11
    export BUILDPERL64='#'
    PERL=${perl}/bin/perl;				export PERL
    ELFDUMP=/usr/bin/elfdump;			export ELFDUMP
    LORDER=/usr/bin/lorder;				export LORDER
    MCS=/usr/bin/mcs;				export MCS
    NM=/usr/bin/nm;					export NM
    STRIP=/usr/bin/strip;				export STRIP
    TSORT=/usr/bin/tsort;				export TSORT
    AR=/usr/bin/ar;					export AR
    BISON=${bison}/bin/bison;			export BISON
    GM4=${gnum4}/bin/m4;				export GM4
    LD_TOXIC_PATH="\$ROOT/lib:\$ROOT/usr/lib";	export LD_TOXIC_PATH
    EOF

    # build_illumos: MAKE names the build host's dmake; the command runs with /opt/local/bin (here: nixpkgs' tools)
    # appended to bldenv's PATH. It runs from a user's shell with CC and CXX unset; here it gets no environment
    # beyond what that shell would have, because illumos.sh's MAKEFLAGS=ek lets the environment override the
    # makefiles' macros, and the stdenv exports CC=gcc, AR, NM, STRIP and more.
    cd illumos
    env -i HOME="$HOME" PATH=/usr/bin:/usr/sbin SHELL=/usr/bin/bash MAKE=${dmake-bootstrap}/bin/dmake \
    /usr/bin/ksh93 ./usr/src/tools/scripts/bldenv illumos.sh \
      "cd \$CODEMGR_WS/usr/src/tools && export PATH=\"\$PATH:${
        lib.makeBinPath [
          flex
          bison
          gnum4
          gettext
          perl
          python312
        ]
      }\" && dmake install"
    cd ..
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r illumos/usr/src/tools/proto/root_*-nd/. $out/
    runHook postInstall
  '';

  # The tools the nightly uses are there and work: the dmake built here runs a makefile; cw compiles through the
  # strap gcc 10 (translating Sun-style flags); ctfconvert turns the object's DWARF into CTF, ctfdump shows the types,
  # and ctfmerge merges it into an object.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    b=$out/opt/onbld/bin
    for t in i386/cw i386/ctfconvert i386/ctfmerge i386/ctfdump i386/dmake i386/ndrgen nightly bldenv; do
      test -x $b/$t || { echo "missing $b/$t"; exit 1; }
    done
    mkdir ic && cd ic
    printf '%s\n' 'all := T = ok' 'all:' '	@echo $(T)' >Makefile
    $b/i386/dmake all | grep -x ok >/dev/null

    primary="gcc10,${proto}/usr/gcc/10/bin/gcc,gnu"
    $b/i386/cw --versions --primary $primary -- | grep "gcc (GCC) 10.4.0" >/dev/null
    printf 'struct strap_s { int a; long b; };\nstruct strap_s strap_v;\nint strap_f(struct strap_s *p) { return p->a; }\n' >t.c
    $b/i386/cw --primary $primary -- -std=gnu99 -m64 -xO2 -g -c t.c -o t.o
    $b/i386/ctfconvert -l test -o t.ctf.o t.o
    $b/i386/ctfdump t.ctf.o | tee ctf.txt | grep "struct strap_s (16 bytes)" >/dev/null
    grep "strap_f" ctf.txt >/dev/null
    cp t.ctf.o merged.o
    $b/i386/ctfmerge -l test -o merged.o t.ctf.o
    $b/i386/ctfdump merged.o | grep "struct strap_s (16 bytes)" >/dev/null
    runHook postInstallCheck
  '';

  # illumos ELF: leave it as the link-editor wrote it.
  dontFixup = true;

  passthru = { inherit nativeAdjunct; };

  meta = {
    description = "illumos-joyent's build tools (opt/onbld), built with SmartOS's proto.strap from this repo";
    homepage = "https://github.com/TritonDataCenter/illumos-joyent";
    license = lib.licenses.cddl;
    platforms = lib.platforms.illumos;
  };
}
