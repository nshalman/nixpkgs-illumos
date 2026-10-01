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
  # the sources pinned by data (../../pins), by name
  pins = import ../../pins;
  # a pinned GitHub source
  fetchPin =
    name:
    fetchFromGitHub {
      inherit (self.pins.${name})
        owner
        repo
        rev
        hash
        ;
    };

  # smartos-live at the commit SmartOS release-20260903 was built from (its gitstatus.json), the release
  # smartos-extra.platformReference is, so that what is built here can be compared with it
  smartosLive = self.fetchPin "smartos-live";

  # gitstatus.json, which build_live writes into the platform (etc/versions/build, the boot archive's .gitstatus) as
  # tools/build_etcrelease -g gives it: each repository's branch, commit time, commit and URL, in the order smartos-live,
  # illumos-joyent, illumos-extra, the local projects; here from the pins, not from checkouts. gitstatusText writes
  # entries (repo, branch, commit_date, rev, url) as build_etcrelease does (json -o json-4).
  gitstatusText =
    entries:
    let
      entry = e: ''
        {
                "repo": "${e.repo}",
                "branch": "${e.branch}",
                "commit_date": "${e.commit_date}",
                "rev": "${e.rev}",
                "url": "${e.url}"
            }'';
    in
    "[\n    " + lib.concatMapStringsSep ",\n    " entry entries + "\n]\n";
  gitstatus = writeText "gitstatus.json" (
    self.gitstatusText (
      map
        (name: {
          repo = name;
          inherit (self.pins.${name}) branch rev url;
          commit_date = toString self.pins.${name}.date;
        })
        (
          [
            "smartos-live"
            "illumos-joyent"
            "illumos-extra"
          ]
          ++ lib.attrNames self.localSrc
        )
    )
  );

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

  # The build-host tools build_live runs, at their places in the tree (tools/...), built as their Makefile does
  # (0-tools-stamp, TOOLS_TARGETS) with NATIVE_CC, the build zone's pkgsrc gcc there and this stdenv's compiler here:
  # builder, which copies the manifest's files into the image and owns them as it says, by the names in a proto
  # area's etc/passwd and etc/group (users.c; the illumos build's here), and the checks tzcheck and ucodecheck, and
  # cryptpass, which hashes the root password. builder is patched to run without root when BUILDER_UNOWNED is set,
  # owning nothing (./builder-unowned.patch), for the parts of the image made without root; as root, unset, it is
  # theirs.
  liveTools = stdenv.mkDerivation {
    pname = "smartos-live-tools";
    version = "0-unstable-2026-09-03";
    src = self.smartosLive;
    patches = [ ./builder-unowned.patch ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      ctf=CTFCONVERT=${builtins.dirOf self.ctfconvert}/ctfconvert
      (cd tools/builder && bash ./build_users_c.sh ${self.illumosProto}/ >users.c && make builder CC=$CC)
      (cd tools/tzcheck && make tzcheck CC=$CC $ctf)
      (cd tools/ucodecheck && make ucodecheck CC=$CC $ctf)
      $CC -Wall -W -O2 -o tools/cryptpass src/cryptpass.c
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      for t in builder/builder tzcheck/tzcheck ucodecheck/ucodecheck cryptpass; do
        install -D tools/$t $out/tools/$t
      done
      runHook postInstall
    '';
  };

  # The directories builder takes the platform's files from (build_live's input directories), first match first.
  # Theirs is the one proto area every stage installed into, a later stage's file over an earlier one's; here the
  # stages' outputs, later stages first: of the files the manifest lists, livesrc's sshd_config is also openssh's
  # (illumos-extra), and illumos-extra's zcat (gzip) also illumos'; no others are in two. Stages with none in
  # common are joined into one directory of links to the files of theirs the manifest lists (what builder reads; it
  # copies the files linked to), which fails if two of them have the same one. livesrc, the joined local stages, the
  # joined illumos-extra, illumos.
  join =
    name: paths:
    runCommand name { } ''
      mkdir $out
      awk '$1 == "f" { print $2 }' ${self.manifest}/manifest.gen >files
      for p in ${toString paths}; do
        while read -r f; do
          [ -e "$p/$f" ] || continue
          if [ -e "$out/$f" ] || [ -L "$out/$f" ]; then
            echo "$f is in more than one of ${toString paths}" >&2
            exit 1
          fi
          mkdir -p "$out/$(dirname "$f")"
          ln -s "$p/$f" "$out/$f"
        done <files
      done
    '';
  localJoin = self.join "smartos-live-local-join" (
    [
      self.devpro
      self.man-cf
    ]
    ++ map (n: self.${n}) (lib.attrNames self.localSrc)
  );
  # what illumos-extra installs into the platform's proto area: its 38 packages and gcc 10's runtime libraries
  extraPackages = map (n: smartos-extra.${n}) [
    "bash"
    "bind"
    "bzip2"
    "coreutils"
    "cpp"
    "curl"
    "dialog"
    "gcc10"
    "gnupg"
    "gtar"
    "gzip"
    "ipmitool"
    "less"
    "libexpat"
    "libidn"
    "libidn2"
    "libxml"
    "libz"
    "mdb_v8"
    "ncurses"
    "node"
    "nss-nspr"
    "ntp"
    "openldap"
    "openlldp"
    "openssh"
    "openssl1x"
    "openssl3"
    "pbzip2"
    "perl"
    "rsync"
    "rsyslog"
    "screen"
    "socat"
    "tun"
    "uuid"
    "vim"
    "wget"
    "xz"
  ];
  extraJoin = self.join "smartos-extra-join" self.extraPackages;
  searchDirs = [
    self.livesrc
    self.localJoin
    self.extraJoin
    self.illumosProto
  ];

  # The image's entries under PREFIXES (and the directories down to them), laid out by builder from searchDirs as
  # build_live lays out the whole image, but without root (BUILDER_UNOWNED, owning nothing): for what build_live
  # makes in the mounted image from its files that needs no root, made here instead.
  imagePart =
    name: prefixes:
    runCommand "smartos-live-image-${name}" { } ''
      awk -v prefixes='${toString prefixes}' '
        BEGIN { n = split(prefixes, p, " ") }
        {
          path = $2
          sub("=.*", "", path)
          for (i = 1; i <= n; i++)
            if (path == p[i] || index(path, p[i] "/") == 1 || ($1 == "d" && index(p[i], path "/") == 1)) {
              print
              next
            }
        }' ${self.manifest}/manifest.gen >manifest
      mkdir $out
      BUILDER_UNOWNED=1 ${self.liveTools}/tools/builder/builder $PWD/manifest $out ${toString self.searchDirs} >log ||
        { grep -v ' OK' log; exit 1; }
    '';

  # The whatis databases of the image's manual pages, as build_live makes them (bi_gen_whatis): the illumos tools'
  # man -w over usr/share/man and smartdc/man, with the directories some of their pages are links into (usr/has/man,
  # usr/node/0.10/man).
  whatis =
    let
      part = self.imagePart "man" [
        "usr/share/man"
        "smartdc/man"
        "usr/has/man"
        "usr/node/0.10/man"
      ];
    in
    runCommand "smartos-live-whatis" { } ''
      cp -r ${part} root
      chmod -R u+w root
      ${smartos-illumos.tools}/opt/onbld/bin/i386/man -M $PWD/root/usr/share/man:$PWD/root/smartdc/man -w
      for d in usr/share/man smartdc/man; do
        install -D -m 444 root/$d/whatis $out/$d/whatis
      done
    '';

  # usr/share/man/man.cf, the man page sections the platform's pages are in: `mancf -t -f manifest.gen`
  man-cf = runCommand "smartos-live-man-cf" { } ''
    mkdir -p $out/usr/share/man
    ${self.mancf}/bin/mancf -t -f ${self.manifest}/manifest.gen >$out/usr/share/man/man.cf
  '';

  # The local stage (0-local-stamp): smartos-live's projects/local, the repositories its configure-projects names, at
  # the commits release-20260903 was built from (its boot_archive.gitstatus), pinned in ../../pins.
  localSrc = lib.genAttrs [
    "kbmd"
    "kvm"
    "kvm-cmd"
    "mdata-client"
    "ur-agent"
  ] self.fetchPin;
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
