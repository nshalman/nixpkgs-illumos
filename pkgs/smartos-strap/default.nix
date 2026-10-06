# SmartOS's proto.strap, the tree smartos-live builds illumos against, made the way illumos-extra's `install_strap`
# makes it: the same packages, from the tarballs, patches, mapfiles and install scripts of the pinned illumos-extra
# commit, each compiled by the strap gcc 10 (gcc10-illumos) with the flags its Makefile gives.
#
# One derivation per illumos-extra directory, restating that directory's Makefile (their Makefiles cannot run as
# they are: they assume one shared, writable proto directory and pkgsrc tools in /opt/local). Each output is laid
# out as that package's part of proto.strap, and tests/smartos-strap.nix compares it with SmartOS's own
# proto.strap built from the same commit (`reference`).
#
# What looks like a bug in illumos-extra's build is marked where it is restated, so `grep "illumos-extra bug"` lists
# them: "illumos-extra bug, reproduced:" where the package is built as theirs is anyway (bug-for-bug, to match their
# proto.strap), "illumos-extra bug, not reproduced:" where it is not, with the reason.
#
# illumos-extra bug, not reproduced: illumos-extra's install scripts are ksh93 scripts, most of them without
# errexit, so a failed copy goes unnoticed there; here they run under bash -e and fail the build.
#
# Where illumos-extra writes a RUNPATH into the strap directory (-R$(DESTDIR)/usr/lib -R$(DESTDIR)/lib), a package
# here names its own output and those of the strap packages it links against.
{
  lib,
  newScope,
  fetchurl,
  runCommand,
  makeSetupHook,
  gcc10-illumos,
  # nixpkgs' perl, for the builds that run perl (the build host's /usr/bin/perl there); inside the scope `perl` is the
  # strap perl 5.12, which the other packages do not use
  perl,
}:

lib.makeScope newScope (self: {
  # illumos-extra: the package sources (tarballs are committed in the repository, except gcc's), patches and
  # install scripts. smartos-live's strap cache is keyed by this commit. Fetched during evaluation (the GitHub
  # archive, the same tree fetchFromGitHub makes), so that illumosExtraSrc can take parts of it. Pinned in ../../pins.
  illumosExtra =
    let
      pin = (import ../../pins)."illumos-extra";
    in
    builtins.fetchTarball {
      url = pin.archive;
      sha256 = pin.hash;
    };

  # The part of illumos-extra a package's build reads: install.subr and the package's own directories (DIRS). A copy
  # in the store named by its contents, so that a package is rebuilt when those change and not whenever the pinned
  # commit moves.
  illumosExtraSrc =
    dirs:
    let
      root = toString self.illumosExtra;
      rel = p: lib.removePrefix "${root}/" (toString p);
    in
    builtins.path {
      path = self.illumosExtra;
      name = "illumos-extra-${lib.concatStringsSep "-" dirs}";
      filter =
        p: _: rel p == "install.subr" || lib.any (d: rel p == d || lib.hasPrefix "${d}/" (rel p)) dirs;
    };

  # The compilers as illumos-extra's Makefile.defs names them in a strap build (GCCBIN, GXXBIN): the strap gcc
  # with -fno-aggressive-loop-optimizations, "as we ship some rather downrev software".
  gcc = "${gcc10-illumos}/bin/gcc -fno-aggressive-loop-optimizations";
  gxx = "${gcc10-illumos}/bin/g++ -fno-aggressive-loop-optimizations";

  # The empty environment Makefile.defs runs configure, make and install in (`env -`), to which each build adds its
  # PATH and the variables illumos-extra gives it. It keeps the stdenv's SOURCE_DATE_EPOCH, the time the compilers
  # (__DATE__, __TIME__), OpenSSL's build information and other tools give for when they ran, so that what is built
  # does not depend on when (theirs carries the time of its build).
  cleanEnv = ''env -i SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH"'';
  inherit gcc10-illumos;

  # A setup hook that makes the archives a package installs the same from one build to the next
  # (./normalize-archives.pl: their member headers' times and owners, which the platform's ar takes from the files);
  # finishPackage gives it to each package of the strap.
  normalizeArchives = makeSetupHook {
    name = "normalize-archives-hook";
    substitutions = {
      perl = "${perl}/bin/perl";
      script = ./normalize-archives.pl;
    };
  } ./normalize-archives-hook.sh;
  finishPackage =
    pkg:
    pkg.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ self.normalizeArchives ];
    });

  # What a strap build finds first on PATH, $(STRAPPROTO)/usr/bin, holds the links gcc-strapfix makes as soon as the
  # primary compiler is installed: gcc, g++ and cpp. A build that runs plain `gcc` (OpenSSL's Configure) gets the
  # strap compiler, as there, and never the stdenv's.
  strapBin = runCommand "smartos-strap-usr-bin" { } ''
    mkdir -p $out/bin
    for f in gcc g++ cpp; do ln -s ${gcc10-illumos}/bin/$f $out/bin/$f; done
  '';

  # The platform's dtrace, which perl and node run at build time (dtrace -h, -G) as they do in illumos-extra: an
  # input from the build host, outside the store. It runs with ./dtrace-shim.c preloaded, so that the objects
  # dtrace -G writes name neither the build host nor its platform (the DOF's utsname: nodename "illumos", version
  # $DTRACE_SHIM_VERSION or "joyent") and do not depend on inode numbers (the $dtrace<key> aliases).
  platformDtrace = runCommand "smartos-strap-platform-dtrace" { } ''
    mkdir -p $out/bin $out/lib
    ${gcc10-illumos}/bin/gcc -m64 -shared -fPIC -O2 -o $out/lib/dtrace-shim.so ${./dtrace-shim.c}
    cat >$out/bin/dtrace <<EOF
    #!/bin/sh
    LD_PRELOAD_64=$out/lib/dtrace-shim.so exec /usr/sbin/dtrace "\$@"
    EOF
    chmod +x $out/bin/dtrace
  '';

  # -L and -R for the strap libraries a package links against (Makefile.defs' SYSLIBDIRS, /usr/lib and /lib, under
  # each), for 32 or 64 bits.
  libDirFlags =
    bits: flag: dirs:
    lib.concatMapStringsSep " " (
      d:
      "${flag}${d}/usr/lib${lib.optionalString (bits == 64) "/64"} ${flag}${d}/lib${
        lib.optionalString (bits == 64) "/64"
      }"
    ) dirs;

  # SmartOS's own proto.strap for the same illumos-extra commit, from smartos-live's strap cache
  # (tools/build_strap), with the illumos-adjunct tarball already extracted into it. For comparison only.
  reference =
    runCommand "smartos-proto-strap-reference-5850d8e9"
      {
        src = fetchurl {
          url = "https://us-central.manta.mnx.io/Joyent_Dev/public/builds/SmartOS/strap-cache/master/2024Q4/x86_64/5850d8e9f17443bbe42eb24739c8f3c2f268ae60/20260902T201307Z/proto.strap.tar.gz";
          sha256 = "6130339f6b5c7a414b4b93a41f50aee1e688e2788303d048b4eb130a43cc6be3";
        };
      }
      ''
        mkdir $out
        tar xzf $src -C $out --no-same-owner
      '';

  mkStrapAutoconf = self.callPackage ./autoconf.nix { };

  libz = self.finishPackage (self.callPackage ./libz.nix { });
  libexpat = self.finishPackage (self.callPackage ./libexpat.nix { });
  libidn = self.finishPackage (self.callPackage ./libidn.nix { inherit perl; });
  idnkit = self.finishPackage (self.callPackage ./idnkit.nix { });
  bzip2 = self.finishPackage (self.callPackage ./bzip2.nix { });
  cpp = self.finishPackage (self.callPackage ./cpp.nix { });
  libxml = self.finishPackage (self.callPackage ./libxml.nix { });
  openssl1x = self.finishPackage (self.callPackage ./openssl1x.nix { inherit perl; });
  openssl3 = self.finishPackage (self.callPackage ./openssl3.nix { inherit perl; });
  nss-nspr = self.finishPackage (self.callPackage ./nss-nspr.nix { inherit perl; });
  perl = self.finishPackage (self.callPackage ./perl.nix { });
  node = self.finishPackage (self.callPackage ./node.nix { });

  # the whole of proto.strap
  proto = self.callPackage ./proto.nix { };

  # The illumos-adjunct tarball smartos-live extracts into proto.strap after the strap build (tools/build_strap):
  # prebuilt libraries and headers (glib, dbus, net-snmp, trousers, python headers, ...) that illumos builds against.
  # Opaque binaries, taken as they are (smartos-live default.configure-build, ILLUMOS_ADJUNCT_TARBALL_URL).
  adjunct =
    runCommand "smartos-strap-adjunct-20240926"
      {
        src = fetchurl {
          url = "https://us-central.manta.mnx.io/Joyent_Dev/public/releng/adjuncts/illumos-adjunct.20240926.tgz";
          sha256 = "dfa097a9b4da12c25bf22995279223f6d1c8845c806d983d4f38b384fe7fb882";
        };
      }
      ''
        mkdir $out
        tar xzf $src -C $out --no-same-owner
      '';
})
