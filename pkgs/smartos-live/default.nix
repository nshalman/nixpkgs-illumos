# smartos-live's own parts of SmartOS (src, man, later the local projects and the image), built from its pinned tree
# against the illumos build (smartos-illumos) and illumos-extra's packages (smartos-extra), each stage its own
# derivation rather than one step installing into a shared proto area.
{
  lib,
  newScope,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  runCommand,
  coreutils,
  gnumake,
  writeText,
  smartos-illumos,
  smartos-strap,
  smartos-extra,
}:

lib.makeScope newScope (self: {
  # smartos-live at the commit SmartOS release-20260903 was built from (its gitstatus.json), the release
  # smartos-extra.platformReference is, so that what is built here can be compared with it
  smartosLive = fetchFromGitHub {
    owner = "TritonDataCenter";
    repo = "smartos-live";
    rev = "148c3689faede56d529a44469fdb989d24b29aa1";
    sha256 = "1zcrk6pgg12glq6a048k5qg72149vg567jf4a0wc1skqzx8g5fka";
  };

  # the build.env configure writes, with its defaults, which the stages read
  buildEnv = writeText "build.env" ''
    FORCE_STRAP_REBUILD=no
    ILLUMOS_CLOBBER=no
    ILLUMOS_ENABLE_DEBUG=no
    PRIMARY_COMPILER=gcc10
    PRIMARY_COMPILER_VER=10
    SHADOW_COMPILERS=
    ENABLE_SMATCH=yes
  '';

  # Shell for an installPhase: their installs copy into directories their proto area already has (illumos' among
  # them); this makes in $out the directories MANIFESTS (paths from the build directory) list, and those their files
  # are in.
  manifestDirs = manifests: ''
    mkdir -p $out
    awk '$1 == "d" { print $2 } $1 ~ /^[fsh]$/ { sub("=.*", "", $2); if (sub("/[^/]*$", "", $2)) print $2 }' \
      ${toString manifests} | sort -u | (cd $out && xargs mkdir -p)
  '';

  inherit (smartos-extra) illumosProto ctfconvert;
  # smartos-live's NATIVEDIR, the strap it builds with (gcc, g++, node, npm)
  strapProto = smartos-strap.proto;

  # the src stage (0-livesrc-stamp): src and man
  livesrc = smartos-extra.finishPackage (self.callPackage ./livesrc.nix { });

  # the devpro stage (0-devpro-stamp): the C++ runtime libraries kept prebuilt in the tree
  devpro = self.callPackage ./devpro.nix { };

  # the platform's manifest (manifest.gen, boot.manifest.gen), from the stages' manifests
  manifest = self.callPackage ./manifest.nix { };

  # tools/mancf, which writes man.cf from the manifest: a tool for the build host, which their Makefile builds with
  # NATIVE_CC (the build zone's pkgsrc gcc) against the host's libraries; here with this stdenv's compiler
  mancf = stdenv.mkDerivation {
    pname = "smartos-live-mancf";
    version = "0-unstable-2026-09-03";
    src = self.smartosLive;
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      (cd tools/mancf && make mancf CC=$CC CTFCONVERT=${builtins.dirOf self.ctfconvert}/ctfconvert)
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -D tools/mancf/mancf $out/bin/mancf
      runHook postInstall
    '';
  };

  # usr/share/man/man.cf, the man page sections the platform's pages are in: `mancf -t -f manifest.gen`
  man-cf = runCommand "smartos-live-man-cf" { } ''
    mkdir -p $out/usr/share/man
    ${self.mancf}/bin/mancf -t -f ${self.manifest}/manifest.gen >$out/usr/share/man/man.cf
  '';

  # The local stage (0-local-stamp): smartos-live's projects/local, the repositories its configure-projects names, at
  # the commits release-20260903 was built from (its boot_archive.gitstatus).
  localSrc =
    let
      f =
        repo: rev: hash:
        fetchFromGitHub {
          owner = "TritonDataCenter";
          inherit repo rev hash;
        };
    in
    {
      kbmd =
        f "kbmd" "726dfaa6f72e7b8ce6b0cce88ff26b93feb0f574"
          "sha256-MTVoxI5cIDw57AP1L1b5G0RSE4yqnYklV16ukgTUETg=";
      kvm =
        f "illumos-kvm" "a7f088a6252631a8fd3d86f413fe0c7809ac50c3"
          "sha256-DFIJSRCI/9+nU+36JeQwZOWRnemN5dkxSS2QsqRciG4=";
      kvm-cmd =
        f "illumos-kvm-cmd" "1c9b441da90fe179451abab9aa8a4b926912d518"
          "sha256-L5fxkfI5rqR4U0FTxL0o0a3Af6QiwaGHluM9HimA18k=";
      mdata-client =
        f "mdata-client" "b5f9dc8437c2be3824bd7f86cb2ca0edc70aea4e"
          "sha256-tLZxsW84JskhioRhZ519DORlsCKnDPSOoMy+X7j0Ehc=";
      ur-agent =
        f "sdc-ur-agent" "cc3cc3bfca21c77cf3b4541fcafde7c0fa3d30f1"
          "sha256-v8M+bGepmKKtrplEG+1842eKPzUt2pKd0o9XnAi1VIM=";
    };
  # a local project, as 0-subdir-NAME-stamp builds it
  mkLocal = self.callPackage ./local.nix { };

  # mdata-client's Makefile compiles with the `gcc` on PATH and no include or library directories: theirs is the build
  # zone's pkgsrc gcc 13 (/opt/local/bin, last on smartos-live's PATH), 64-bit, against the build host's headers and
  # libraries. Here, as for the other projects, it is the strap's gcc 10, made 64-bit, against the illumos build's
  # proto area (pkgsrc is no part of this toolchain); so its RUNPATH is gcc 10's, where theirs is pkgsrc's.
  mdata-client = smartos-extra.finishPackage (
    self.mkLocal {
      name = "mdata-client";
      version = "0-unstable-2025-04-22";
      src = self.localSrc.mdata-client;
      makeFlags = [
        ''CC="${self.strapProto}/usr/bin/gcc -m64 -isystem ${self.illumosProto}/usr/include -L${self.illumosProto}/lib/amd64 -L${self.illumosProto}/usr/lib/amd64"''
      ];
    }
  );

  # illumos-kvm: the kvm driver, its mdb module and its devfsadm link module. Its Makefile links the driver with
  # /usr/bin/ld, the build host's link-editor; here it is the one the strap's gcc links with (the gate's, illumos-ld).
  kvm = smartos-extra.finishPackage (
    self.mkLocal {
      name = "kvm";
      version = "0-unstable-2025-09-24";
      src = self.localSrc.kvm;
      makeFlags = [ "LD=$(${self.strapProto}/usr/bin/gcc -print-prog-name=ld)" ];
    }
  );

  # kbmd, the key backup and management daemon, with pivy's pivy-tool and pivy-box. pivy is a git submodule, which
  # its Makefile checks out with `git submodule update`; here the commit kbmd records (Nahum approved the download)
  # is put in place and that command left out. Its Makefile compiles and links against $DESTDIR, their proto area,
  # and passes it to pivy's: what it reads there, the illumos build's headers and libraries, illumos-extra's libz,
  # and illumos-extra's OpenSSL 1.x (opt/1x and its static libcrypto in .build), is given for reading, and DESTDIR is
  # this package's output.
  kbmd =
    let
      pivy = fetchFromGitHub {
        owner = "arekinath";
        repo = "pivy";
        rev = "deebdab681be3d37dd207da2c30b16d0db3baf44";
        hash = "sha256-b5ivtmXYbfSO24Pxyjj6ibGQ+WQrw6rSBDIgdhKIiig=";
      };
      inherit (smartos-extra) libz openssl1x;
    in
    smartos-extra.finishPackage (
      self.mkLocal {
        name = "kbmd";
        version = "0-unstable-2025-04-22";
        src = self.localSrc.kbmd;
        postPatch = ''
          cp -r ${pivy}/. pivy/
          chmod -R u+w pivy
          substituteInPlace Makefile \
            --replace-fail 'git submodule update --init' ': git submodule update --init' \
            --replace-fail '$(DESTDIR)/.build/' '${openssl1x}/.build/' \
            --replace-fail '$(DESTDIR)/opt/1x' '${openssl1x}/opt/1x' \
            --replace-fail '-I''${DESTDIR}/opt/1x' '-I${openssl1x}/opt/1x' \
            --replace-fail '$(DESTDIR)/usr/include' '${self.illumosProto}/usr/include -I${libz}/usr/include' \
            --replace-fail '-L$(DESTDIR)/lib/amd64' '-L${self.illumosProto}/lib/amd64 -L${libz}/lib/amd64' \
            --replace-fail '-L$(DESTDIR)/usr/lib/amd64' '-L${self.illumosProto}/usr/lib/amd64 -L${libz}/usr/lib/amd64' \
            --replace-fail 'PROTO_AREA="$(DESTDIR)"' \
              'PROTO_AREA="${self.illumosProto}" ZLIB_CFLAGS="-isystem ${libz}/usr/include"'
        '';
      }
    );

  # illumos-kvm-cmd: QEMU 0.14.1 for KVM, and its mdb module. Its build.sh, which configure runs, downloads libpng
  # 1.5.4 from Manta unless it is there already, and builds it; it is a pinned input here (Nahum approved the
  # download), unpacked where build.sh looks. build.sh compiles and links against $DESTDIR, their proto area; what it
  # reads there, the illumos build's headers and libraries and illumos-extra's libz, is given for reading, and DESTDIR
  # is this package's output. QEMU's kernel directory is ../kvm, illumos-kvm's source. Its trace backend is dtrace,
  # which the build runs (dtrace -h, -G): the build host's, as for perl and node.
  kvm-cmd =
    let
      libpng = fetchurl {
        url = "https://us-central.manta.mnx.io/Joyent_Dev/public/releng/kvm-cmd/libpng-1.5.4.tar.gz";
        sha256 = "1azaiz451p2kgx4pz6m1yg1px6clrgmimansj058vd3j1jvxpk55";
      };
      readProto = [
        self.illumosProto
        "${smartos-extra.libz}"
      ];
      includes = toString (map (d: "-isystem ${d}/usr/include") readProto);
      libDirs = toString (map (d: "-L${d}/usr/lib/amd64 -L${d}/lib/amd64") readProto);
      # what the build takes from their PATH: gmake, which Makefile.joyent runs, and ginstall, which QEMU's configure
      # asks for on SunOS (theirs pkgsrc's; here nixpkgs' make and coreutils), and isainfo (the host's). configure
      # also names gld, for a config-host.ld nothing reads; not given.
      pathTools = runCommand "kvm-cmd-path-tools" { } ''
        mkdir -p $out/bin
        ln -s ${gnumake}/bin/make $out/bin/gmake
        ln -s ${coreutils}/bin/install $out/bin/ginstall
        ln -s /usr/bin/isainfo $out/bin/isainfo
      '';
    in
    smartos-extra.finishPackage (
      self.mkLocal {
        name = "kvm-cmd";
        version = "0-unstable-2025-08-28";
        src = self.localSrc.kvm-cmd;
        withLocal = [ "kvm" ];
        nativeBuildInputs = [
          smartos-strap.platformDtrace
          pathTools
        ];
        postPatch = ''
          tar xzf ${libpng}
          substituteInPlace build.sh \
            --replace-fail '-isystem ''${DESTDIR}/usr/include' '${includes}' \
            --replace-fail '-L''${DESTDIR}/usr/lib/amd64 -L''${DESTDIR}/lib/amd64' '${libDirs}'
        '';
        # build.sh runs libpng's and QEMU's configure as ./configure, under /bin/sh (ksh93). stdenv exports
        # CONFIG_SHELL (bash), which their config.status then runs under: libpng's libtool 2.4 chose `print -r --`
        # for echo under ksh93, and bash has no print, so the libtool it wrote was broken. Their build has no
        # CONFIG_SHELL.
        preInstall = ''
          unset CONFIG_SHELL
        '';
      }
    );

  # sdc-ur-agent: node programs and modules committed in the repository. Its world target is `git submodule update`,
  # for jsstyle, javascriptlint and restdown, which only `make check` uses; it is taken as done (-o).
  ur-agent = smartos-extra.finishPackage (
    self.mkLocal {
      name = "ur-agent";
      version = "0-unstable-2025-04-22";
      src = self.localSrc.ur-agent;
      makeFlags = [
        "-o"
        "submodules"
      ];
    }
  );
})
