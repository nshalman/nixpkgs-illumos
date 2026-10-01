# rust-bhyve (TritonDataCenter/rust-bhyve): a bhyve VMM in Rust, rshyve (bhyve's flags, for the bhyve brand), the
# firehyve microVM and fhrun. Pinned in ../../pins, at the branch sources.json follows (wip/virtio-gpu: virtio-gpu,
# virtio-snd and RDP); built with rust-lang.org's toolchain (rust-illumos-bin), its test suite run.
#
# The repository is private: GitHub serves its archive only to those with access, so a builder without access does
# not fetch it. From a machine with access, `pins/seed.sh rust-bhyve BUILDER` puts the pinned tree into the builder's
# store at the path fetchFromGitHub makes. pins/update.sh needs that access too.
#
# Its submodule libtpms, which the archive leaves out, is pinned with it and put in place. vmm-tpm-sys builds it
# (autoreconf, configure, make) and links it with OpenSSL. On a SmartOS build host its build script takes the running
# platform's libcrypto-smartos (as for a platform image), found at /lib/amd64 outside Nix's view, so what is built
# would depend on the platform the builder boots (20260723's is OpenSSL 3.0.21, release-20260903's 3.5.8). Here it
# takes nixpkgs' openssl through pkg-config, as it does on any other host (./pkg-config-crypto.patch, asked for with
# VMM_TPM_SYS_PKG_CONFIG_CRYPTO). The platform's is private to it: its symbols are renamed (sunw_ prefix) so that no
# other OpenSSL in a process meets them.
#
# It is built as a platform binary is, so that it can go into a platform image: against the illumos build's proto
# area (smartos-live's illumosProto, release-20260903's headers and libraries: libtpms needs dprintf, which the
# stdenv's 2021 sysroot does not have, and the sysroot's libdladm needs libpool, which it lacks), and the platform's
# libraries from illumos-extra (smartos-live's extraJoin: libpool needs libxml2), searched as smartos-live's builder
# searches them, with every library but nixpkgs' openssl found on the running system: the ld wrapper's RUNPATH (each
# store directory that supplied a library, the proto's too) is off, and RUNPATH is openssl's lib alone.
{
  lib,
  rust-illumos-bin,
  fetchFromGitHub,
  fetchzip,
  autoconf,
  automake,
  libtool,
  pkg-config,
  openssl,
  perl,
  smartos-live,
}:

let
  pin = (import ../../pins).rust-bhyve;
  libtpms = pin.submodules."third_party/libtpms";
  proto = smartos-live.illumosProto;
  extra = smartos-live.extraJoin;
in
rust-illumos-bin.rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rust-bhyve";
  version = "0.1.0-unstable-${builtins.substring 0 8 pin.rev}";

  src = fetchFromGitHub {
    inherit (pin)
      owner
      repo
      rev
      hash
      ;
  };
  libtpmsSrc = fetchzip {
    inherit (libtpms) hash;
    url = libtpms.archive;
  };
  postUnpack = ''
    rmdir $sourceRoot/third_party/libtpms
    cp -r ${finalAttrs.libtpmsSrc} $sourceRoot/third_party/libtpms
    chmod -R u+w $sourceRoot/third_party/libtpms
  '';
  patches = [ ./pkg-config-crypto.patch ];

  cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";
  # see pkgs/rust-illumos-bin
  auditable = false;

  nativeBuildInputs = [
    autoconf
    automake
    libtool
    # libtpms makes its man pages with pod2man
    perl
    pkg-config
  ];
  buildInputs = [ openssl ];

  env = {
    # stamped into rshyve --version (crates/vmm-machine/src/build_rev.rs)
    TRITON_BUILD_REV = pin.rev;
    # libtpms with nixpkgs' openssl (see above)
    VMM_TPM_SYS_PKG_CONFIG_CRYPTO = "1";
    # the proto area's headers, and the platform's libraries (illumos-extra's, then the proto's), ahead of the
    # sysroot's (see above)
    NIX_CFLAGS_COMPILE = "-isystem ${proto}/usr/include";
    NIX_LDFLAGS = lib.concatStringsSep " " [
      "-L${extra}/lib/amd64"
      "-L${extra}/usr/lib/amd64"
      "-L${proto}/lib/amd64"
      "-L${proto}/usr/lib/amd64"
      "-rpath ${lib.getLib openssl}/lib"
    ];
    NIX_DONT_SET_RPATH = "1";
  };

  # Its tests bind Unix sockets under TMPDIR, whose paths must fit in sun_path (108 bytes); the build directory's do
  # not ("path must be shorter than SUN_LEN").
  preCheck = ''
    buildTmp=$TMPDIR
    checkTmp=$(mktemp -d /tmp/rust-bhyve-check.XXXXXX)
    export TMPDIR=$checkTmp
  '';
  postCheck = ''
    export TMPDIR=$buildTmp
    rm -rf "$checkTmp"
  '';
  # upstream runs the suite as a debug build (`cargo test`), with --no-fail-fast, so that one failing crate does not
  # hide the rest. Its tests rely on the debug build: slog leaves out debug! lines from a release build, and rshyve's
  # mdata tests look for them.
  checkType = "debug";
  cargoTestFlags = [
    "--workspace"
    "--no-fail-fast"
  ];
  checkFlags = [
    # create a VM through /dev/vmmctl, which a build has not (upstream: "These tests need illumos and the privilege
    # to create a VM")
    "--skip=armed_autodestruct_reclaims_the_instance_on_close"
    "--skip=disarmed_autodestruct_keeps_the_instance"
    # passes as root, fails as the unprivileged build user (EACCES): the passthrough reopens the file it holds
    # read-only through /proc/self/fd for writing
    "--skip=o_trunc_still_works_on_a_writable_share"
  ];

  meta = {
    description = "bhyve VMM in Rust: rshyve, the firehyve microVM and fhrun";
    homepage = "https://github.com/TritonDataCenter/rust-bhyve";
    license = lib.licenses.mpl20;
    platforms = lib.platforms.illumos;
    mainProgram = "rshyve";
  };
})
