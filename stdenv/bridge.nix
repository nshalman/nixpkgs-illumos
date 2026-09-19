# BRIDGE stdenv for x86_64-solaris on the illumos-26.05 nixpkgs branch. Not a bootstrap: every input of stage 0 is a store
# path that already exists on the builder, named in ./bridge-paths.nix.
#
#   - userland (bash, coreutils, make, ...): the illumos-recipe-v2 bootstrap closure, built against the HOST libc;
#   - toolchain: this repo's gcc-illumos, illumos-ld and illumos-sysroot.
#
# It exists to drive the real cc-wrapper / bintools-wrapper from nixpkgs over the sysroot toolchain, and to build
# the first generation of packages that replace the userland above. The shape follows
# pkgs/stdenv/illumos-recipe/bootstrap-files-stages.nix on the illumos-recipe-v2 branch.
#
# Use through ../bridge.nix, which hands this to nixpkgs as `stdenvStages`.
{ paths, nixpkgs }:
{
  lib,
  localSystem,
  crossSystem,
  config,
  overlays,
  crossOverlays ? [ ],
}:

assert crossSystem == localSystem;
assert localSystem.system == "x86_64-solaris";

let
  pkgsPath = nixpkgs;

  # The wrappers call lib.getVersion / lib.getExe on their inputs, which reject bare store-path strings.
  mkStoreDrv =
    {
      pname,
      version,
      outPath,
      extraOutputs ? { },
      extraAttrs ? { },
    }:
    {
      type = "derivation";
      outputs = [ "out" ] ++ lib.attrNames extraOutputs;
      inherit outPath pname version;
      name = "${pname}-${version}";
      out = {
        type = "derivation";
        outputs = [ "out" ];
        inherit outPath;
      };
    }
    // lib.mapAttrs (output: path: {
      type = "derivation";
      outputs = [ output ];
      outPath = path;
    }) extraOutputs
    // extraAttrs;

  gcc = mkStoreDrv {
    pname = "gcc-illumos";
    version = "14.2.0";
    outPath = paths.gcc-illumos.out;
    extraOutputs.lib = paths.gcc-illumos.lib;
    extraAttrs.isGNU = true;
  };

  # The libc is the sysroot with header backports (pkgs/illumos-libc). It is only linked against: its runtime
  # linker is the host's, so the ld wrapper keeps it out of RUNPATH.
  libc = mkStoreDrv {
    pname = "illumos-libc";
    version = "20210501";
    outPath = paths.illumos-libc;
    extraAttrs = {
      incdir = "/usr/include";
      libdir = "/usr/lib/amd64";
      dynamicLinker = "/usr/lib/amd64/ld.so.1";
    };
  };

  coreutils = mkStoreDrv {
    pname = "coreutils";
    version = "9.8";
    outPath = paths.coreutils;
  };

  expand-response-params = mkStoreDrv {
    pname = "expand-response-params";
    version = "0";
    outPath = paths.expand-response-params;
    extraAttrs.meta.mainProgram = "expand-response-params";
  };

  shell = "${paths.bash}/bin/bash";

  initialPath = with paths; [
    bash
    coreutils
    findutils
    gnutar
    gnused
    gnugrep
    gawk
    gnumake
    diffutils
    patch
    xz-bin
    gzip
    bzip2-bin
  ];

  preHook = ''
    export NIX_ENFORCE_PURITY=
    export NIX_ENFORCE_NO_NATIVE="''${NIX_ENFORCE_NO_NATIVE-1}"
    export PKG_CONFIG_LIBDIR=""
    # illumos utilities no package provides (isainfo, uname, ...). Host paths, so no store references.
    export PATH="$PATH:/usr/bin:/usr/sbin"
  '';

  makeStdenv =
    { cc, fetchurl }:
    import (pkgsPath + "/pkgs/stdenv/generic") {
      name = "illumos-bridge-stdenv";
      buildPlatform = localSystem;
      hostPlatform = localSystem;
      targetPlatform = localSystem;
      inherit
        preHook
        initialPath
        shell
        cc
        config
        ;
      fetchurlBoot = fetchurl;
    };
in
[
  (
    { }:
    rec {
      __raw = true;

      stdenv = makeStdenv {
        cc = null;
        fetchurl = null;
      };
      stdenvNoCC = stdenv;

      # binutils for everything except the link-editor, which is illumos ld.
      bintools-unwrapped = stdenvNoCC.mkDerivation {
        pname = "illumos-bintools";
        version = "2.44";
        dontUnpack = true;
        dontFixup = true;
        # Everything but ld is GNU binutils; the wrapper only wraps `strip` for bintools that say so.
        passthru.isGNU = true;
        installPhase = ''
          mkdir -p $out/bin
          for f in ${paths.binutils-unwrapped}/bin/*; do
            case "''${f##*/}" in
              ld | ld.*) ;;
              *) ln -s "$f" $out/bin/ ;;
            esac
          done
          ln -s ${paths.illumos-ld}/bin/ld $out/bin/ld
        '';
      };

      bintools = import (pkgsPath + "/pkgs/build-support/bintools-wrapper") {
        name = "bintools-illumos-bridge";
        inherit
          lib
          stdenvNoCC
          libc
          coreutils
          expand-response-params
          ;
        bintools = bintools-unwrapped;
        nativeTools = false;
        nativeLibc = false;
        runtimeShell = shell;
        gnugrep = paths.gnugrep;
      };

      cc = import (pkgsPath + "/pkgs/build-support/cc-wrapper") {
        name = "cc-illumos-bridge";
        inherit
          lib
          stdenvNoCC
          libc
          bintools
          coreutils
          expand-response-params
          ;
        cc = gcc;
        nativeTools = false;
        nativeLibc = false;
        runtimeShell = shell;
        gnugrep = paths.gnugrep;
        isGNU = true;
      };

      fetchurl = import (pkgsPath + "/pkgs/build-support/fetchurl") {
        inherit lib stdenvNoCC;
        curl = paths.curl.bin;
        inherit (config) hashedMirrors rewriteURL;
      };
    }
  )

  (prevStage: {
    inherit config overlays;
    stdenv =
      makeStdenv {
        inherit (prevStage) cc fetchurl;
      }
      // {
        inherit (prevStage) fetchurl;
        overrides = self: super: { inherit (prevStage) fetchurl; };
      };
  })

  # Stage 2 (final). Stage 1's packages are built by the first-generation tools and some bake a tool path in:
  # bison's and curl's scripts name the stdenv shell, gnum4 a shell, perl coreutils. That drags the old,
  # host-linked closure into anything depending on them (tests/audit-closure.sh shows it). So build the final
  # set with a stdenv made of stage 1's own tools, and re-wrap the toolchain with them.
  #
  # The basic tools below came out of stage 1 without any reference to the first generation, so the final set
  # reuses them instead of building a third copy.
  (
    prevStage:
    let
      cleanTools = {
        inherit (prevStage)
          bash
          bashNonInteractive
          coreutils
          findutils
          gnutar
          gnused
          gnugrep
          gawk
          gnumake
          diffutils
          patch
          xz
          gzip
          bzip2
          ;
      };
      cleanShell = "${prevStage.bashNonInteractive}/bin/bash";

      cleanBintoolsUnwrapped = prevStage.stdenvNoCC.mkDerivation {
        pname = "illumos-bintools";
        version = prevStage.binutils-unwrapped.version;
        dontUnpack = true;
        dontFixup = true;
        # Everything but ld is GNU binutils; the wrapper only wraps `strip` for bintools that say so.
        passthru.isGNU = true;
        installPhase = ''
          mkdir -p $out/bin
          for f in ${prevStage.binutils-unwrapped}/bin/*; do
            case "''${f##*/}" in
              ld | ld.*) ;;
              *) ln -s "$f" $out/bin/ ;;
            esac
          done
          ln -s ${paths.illumos-ld}/bin/ld $out/bin/ld
        '';
      };

      cleanBintools = prevStage.wrapBintoolsWith {
        bintools = cleanBintoolsUnwrapped;
        inherit libc;
        nativeTools = false;
        nativeLibc = false;
      };

      cleanCC = prevStage.wrapCCWith {
        cc = gcc;
        bintools = cleanBintools;
        inherit libc;
        nativeTools = false;
        nativeLibc = false;
        isGNU = true;
      };
    in
    {
      inherit config overlays;
      stdenv =
        import (pkgsPath + "/pkgs/stdenv/generic") {
          name = "illumos-bridge-stdenv-final";
          buildPlatform = localSystem;
          hostPlatform = localSystem;
          targetPlatform = localSystem;
          inherit preHook config;
          shell = cleanShell;
          cc = cleanCC;
          initialPath = with cleanTools; [
            bash
            coreutils
            findutils
            gnutar
            gnused
            gnugrep
            gawk
            gnumake
            diffutils
            patch
            xz.bin
            gzip
            bzip2.bin
          ];
          fetchurlBoot = prevStage.fetchurl;
          overrides = self: super: cleanTools // { inherit (prevStage) fetchurl; };
        }
        // {
          inherit (prevStage) fetchurl;
        };
    }
  )
]
