# nixpkgs-illumos

illumos material for [nixpkgs](https://github.com/NixOS/nixpkgs) that is not (or not yet) suitable for
upstream. The goal is a **portable Nix userspace for illumos**: a bootstrapped toolchain and package set
whose outputs run on any reasonably recent illumos distribution or zone (OpenIndiana, OmniOS, SmartOS,
Tribblix), the way Nix on Darwin builds against a pinned SDK and runs against the host's libc.

This is not a distribution. Building illumos itself and a bootable, declaratively configured system is the
territory of [solnix](https://codeberg.org/gregburd/solnix); this repo aims to be reusable by it.

## How it fits together

| Where | What |
|---|---|
| `nshalman/nixpkgs`, branch `illumos-26.05` | Only commits fit to send upstream: `lib/systems`, the cc/bintools wrappers, the stdenv stage list, per-package `isSunOS` fixes. |
| **this repo** | Everything else: the pinned illumos sysroot, the link-editor built from illumos-gate, the compiler, bootstrap files and their tooling, zone images, the patch series for Nix itself. |

Design rules this repo follows:

- **Platform:** the existing `x86_64-solaris` double and plain `isSunOS`.
- **ABI floor:** packages compile and link against the published
  [illumos sysroot](https://github.com/illumos/sysroot) `20210501-e0b4275f34-v0`, never the build host's
  `/usr/include` or `/usr/lib`. illumos guarantees old binaries run on new systems, so the floor is what
  makes output portable.
- **Runtime:** libc and `ld.so.1` always come from the host. The sysroot's library directories are
  link-time only and must never appear in a `DT_RUNPATH`; it ships a full 2021 `libc.so.1`, and pairing
  that with a newer host `ld.so.1` is undefined behaviour.
- **Tools run at the floor too, but carry current fixes:** `ld` is built from a recent illumos-gate commit
  and linked against the sysroot.

## Status

Early. Until the `illumos-26.05` nixpkgs branch exists, the expressions here are built with the older
`illumos-recipe-v2` tree (system `x86_64-illumos`) as a bridge:

```bash
nix-build -I nixpkgs=/path/to/nixpkgs -A illumos-sysroot
```

| Attribute | State |
|---|---|
| `illumos-sysroot` | the pinned sysroot as a fixed-output fetch, unpacked untouched |
| `illumos-ld` | planned: `ld`, `libld`, `liblddbg` from illumos-gate against the sysroot |
| `patches/nix` | the one-line `sunos` to `solaris` system-string mapping for Nix |

A flake will be added once there is a nixpkgs branch worth pinning as its input.
