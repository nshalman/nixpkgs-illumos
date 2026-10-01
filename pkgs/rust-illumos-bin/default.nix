# The Rust toolchain rust-lang.org builds for illumos (rust-VERSION-x86_64-unknown-illumos.tar.gz, what rustup
# installs), installed by nixpkgs' expression for its prebuilt toolchains (rust/binary.nix, which its rust builds
# bootstrap from), with a rustPlatform that builds with it. nixpkgs' rust has no hash for this platform's tarball, and
# the gcc it takes gcc's runtime from (top-level gcc) is not this stdenv's: here gcc-illumos's.
#
# binary.nix fixes up the programs with autoPatchelfHook, here one for illumos:
#   - the toolchain needs gcc's libgcc_s and libssp, which gcc-illumos's lib output has in lib/amd64, the illumos
#     place for 64-bit libraries; autoPatchelfHook looks only in each input's lib, so here also in lib/amd64;
#   - it takes the system's libraries from the running system, as it should, when the libc it is given (the stdenv's
#     sysroot) has them; liblgrp, which every illumos has, is not in the sysroot;
#   - nixpkgs' autoPatchelfHook brings top-level bintools, which is not this stdenv's either: here the same hook
#     (auto-patchelf.sh) with the stdenv's.
#
# Packages built with rustPlatform need `auditable = false`: buildRustPackage builds with cargo-auditable by default,
# which nixpkgs builds with its own rust and vendors with fetchCargoVendor, whose helper's script checks run under
# dash, which does not build on illumos yet (it uses struct dirent's d_type and BSD getopt's optreset).
{
  stdenv,
  stdenvAdapters,
  path,
  callPackage,
  fetchurl,
  makeSetupHook,
  writeShellScript,
  auto-patchelf,
  makeRustPlatform,
}:

let
  version = "1.95.0";
  platform = stdenv.hostPlatform.rust.rustcTarget;
  # from https://static.rust-lang.org/dist/rust-${version}-${platform}.tar.gz.sha256
  sha256 = "8ffcdf78641c2ebc2ab6de3e47461d0a5a3429553a37b950247bd04ade505f0d";

  autoPatchelfHook = makeSetupHook {
    name = "auto-patchelf-hook";
    propagatedBuildInputs = [
      auto-patchelf
      stdenv.cc.bintools
    ];
    substitutions = {
      hostPlatform = stdenv.hostPlatform.config;
    };
  } (path + "/pkgs/build-support/setup-hooks/auto-patchelf.sh");
  autoPatchelfHookIllumos =
    makeSetupHook
      {
        name = "auto-patchelf-hook-illumos";
        propagatedBuildInputs = [ autoPatchelfHook ];
      }
      (
        writeShellScript "auto-patchelf-illumos.sh" ''
          gatherLibrariesAmd64() {
              if [ -d "$1/lib/amd64" ]; then autoPatchelfLibs+=("$1/lib/amd64"); fi
          }
          addEnvHooks "$targetOffset" gatherLibrariesAmd64
          autoPatchelfIgnoreMissingDeps+=" liblgrp.so.1"
        ''
      );

  toolchain = callPackage (path + "/pkgs/development/compilers/rust/binary.nix") {
    inherit version platform;
    versionType = "prebuilt";
    gcc = stdenv.cc;
    autoPatchelfHook = autoPatchelfHookIllumos;
    src = fetchurl {
      url = "https://static.rust-lang.org/dist/rust-${version}-${platform}.tar.gz";
      inherit sha256;
    };
  };
  # rustc keeps a crate's metadata in a .rustc section nothing refers to, which it reads back from proc-macros (shared
  # objects) when it uses them; it links with -z ignore (the illumos link-editor discards unreferenced sections of the
  # objects after it) after its own objects, so that section stays. The ld wrapper puts -z ignore before everything,
  # which discards it ("no .rustc section"). The packages rustPlatform builds turn it back off, -z record (the
  # link-editor's default), after the wrapper's -z ignore and before the objects.
  stdenvRust = stdenvAdapters.addAttrsToDerivation { NIX_LDFLAGS_BEFORE = "-z record"; } stdenv;
in
toolchain
// {
  rustPlatform = makeRustPlatform {
    inherit (toolchain) rustc cargo;
    stdenv = stdenvRust;
  };
}
