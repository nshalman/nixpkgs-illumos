# smartos-live's own parts of SmartOS (src, man, later the local projects and the image), built from its pinned tree
# against the illumos build (smartos-illumos) and illumos-extra's packages (smartos-extra), each stage its own
# derivation rather than one step installing into a shared proto area.
{
  lib,
  newScope,
  fetchFromGitHub,
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

  inherit (smartos-extra) illumosProto ctfconvert;
  # smartos-live's NATIVEDIR, the strap it builds with (gcc, g++, node, npm)
  strapProto = smartos-strap.proto;

  # the src stage (0-livesrc-stamp): src and man
  livesrc = smartos-extra.finishPackage (self.callPackage ./livesrc.nix { });

  # the devpro stage (0-devpro-stamp): the C++ runtime libraries kept prebuilt in the tree
  devpro = self.callPackage ./devpro.nix { };

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
