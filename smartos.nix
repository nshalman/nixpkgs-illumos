# The SmartOS build (smartos-live's platform: pkgs/smartos-*) on the generic package set, ./illumos.nix: that set with
# an overlay of SmartOS's packages and the nixpkgs config they need, taking illumos.nix's arguments (overlays and
# config given here go after these).
#   nix-build smartos.nix -A smartos-live.builderTools
args:

import ./illumos.nix (
  args
  // {
    config = (args.config or { }) // {
      # SmartOS's strap node.js 0.10 (pkgs/smartos-strap/node.nix) is built with gyp, which needs python 2. Build time
      # only: nothing installed refers to it.
      permittedInsecurePackages = (args.config.permittedInsecurePackages or [ ]) ++ [ "python-2.7.18.12" ];
    };
    overlays = [
      (final: prev: {
        # The strap toolchain SmartOS builds illumos with (illumos-extra's binutils 2.34 and gcc 10), built here by
        # this stdenv against the sysroot. Not part of the bootstrap.
        binutils-strap = final.callPackage ./pkgs/binutils-strap { };
        gcc10-illumos = final.callPackage ./pkgs/gcc10-illumos { };
        # SmartOS's proto.strap: illumos-extra's strap packages built by that gcc 10.
        smartos-strap = final.callPackage ./pkgs/smartos-strap { };
        # illumos as SmartOS builds it (illumos-joyent), with that proto.strap.
        smartos-illumos = final.callPackage ./pkgs/smartos-illumos { };
        # what illumos-extra adds to SmartOS's proto area after illumos, built by the same gcc 10
        smartos-extra = final.callPackage ./pkgs/smartos-extra { };
        # smartos-live's own stages (src, man, ...), built against those
        smartos-live = final.callPackage ./pkgs/smartos-live { };
        # smartos-live's Jenkins "debug" build: the same, on a DEBUG nightly (stamp's last digit 8)
        smartos-illumos-debug = final.smartos-illumos.overrideScope (
          _: prev: { nightly = prev.nightly.override { debug = true; }; }
        );
        smartos-extra-debug = final.smartos-extra.override { smartos-illumos = final.smartos-illumos-debug; };
        smartos-live-debug = final.smartos-live.override {
          smartos-illumos = final.smartos-illumos-debug;
          smartos-extra = final.smartos-extra-debug;
          flavor = "debug";
        };
        # a bhyve VMM in Rust (rshyve, firehyve), built with rust-illumos-bin against smartos-live's proto area
        rust-bhyve = final.callPackage ./pkgs/rust-bhyve { };
      })
    ]
    ++ (args.overlays or [ ]);
  }
)
