# Patches for Nix itself

Each file here is meant to become an upstream pull request against NixOS/nix.

| Patch | Why |
|---|---|
| `0001-libstore-report-solaris-not-sunos.patch` | On illumos, meson's `host_machine.system()` is `sunos`, so Nix reports `x86_64-sunos`, which nixpkgs cannot parse ("Unknown kernel: sunos"). nixpkgs' double is `x86_64-solaris`. Verified on Nix 2.33.6: with the patch a bare-config `nix` reports `x86_64-solaris` and builds for it; `extra-platforms = x86_64-illumos` keeps an older store usable. |

The rest of the illumos series (flock unlock, build users, `getpeerucred`, GC runtime roots, pty handling)
still lives in the `illumos-recipe-v2` nixpkgs branch and will move here as it is reworked.
