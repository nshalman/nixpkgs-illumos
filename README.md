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

Early. There are two generations of tools and they are built differently.

**Toolchain packages** (`illumos-sysroot`, `illumos-libc`, `illumos-ld`, `gcc-illumos`) are built with the older
`illumos-recipe-v2` nixpkgs tree (system `x86_64-illumos`) until they can build themselves:

```bash
nix-build -I nixpkgs=/path/to/illumos-recipe-v2 -A gcc-illumos
```

**Everything after that** is built by the `illumos-26.05` nixpkgs branch for `x86_64-solaris`, through the
bridge stdenv:

```bash
nix-build bridge.nix --arg nixpkgs /path/to/illumos-26.05 -A hello
nix-build tests/toolchain.nix --arg pkgs 'import ./bridge.nix { nixpkgs = /path/to/illumos-26.05; }'
```

The bridge (`stdenv/bridge.nix`) is **not a bootstrap**. It is handed to nixpkgs as `stdenvStages` and is made
of store paths that must already exist on the builder (`stdenv/bridge-paths.nix`): the toolchain above, plus
the `illumos-recipe-v2` bootstrap closure as userland. That userland is still linked against the build
host's libc; replacing it with packages built here is the next step. Nix must report `x86_64-solaris`
(`patches/nix`) and accept `x86_64-illumos` as an extra platform.

| Attribute | State |
|---|---|
| `illumos-sysroot` | the pinned sysroot as a fixed-output fetch, unpacked untouched |
| `illumos-libc` | `illumos-sysroot` plus the header hunks of upstream illumos-gate commits, applied verbatim; what the compiler wrappers use as libc (passed as `--sysroot`, so no gcc rebuild). Currently illumos 16344: handler types `void (*)()` become `void (*)(int)`, without which anything compiled as C23 that touches signals fails. Two files differ from the sysroot. |
| `illumos-ld` | `ld`, `libld.so.4`, `liblddbg.so.4` from illumos-gate `7db575a44a`, linked against the sysroot. Needs only libc `ILLUMOS_0.26`, has no store references, and links byte-for-byte like the platform `ld` apart from its version string. |
| `gcc-illumos` | illumos/gcc 14.2.0-il-1, three-stage bootstrap, `--with-sysroot`. Searches no host header or library directory; the compiler, `libstdc++` and `libgcc_s` themselves need only libc `ILLUMOS_0.26`; finds `ld` on `PATH` so the nixpkgs wrappers apply. Still hard-codes GNU `as` from the older tree's binutils. |
| `tests/toolchain.nix` | C and C++ (throw/catch) programs built by a stdenv's wrapped toolchain; asserts the interpreter, RUNPATH, libc floor and which `ld` linked them |
| `patches/nix` | the one-line `sunos` to `solaris` system-string mapping for Nix |

Known costs of the 2021 floor:

- Its `<sys/mman.h>` hides `madvise()` from C++ (`_XOPEN_SOURCE`), so C++ code calling it does not compile
  against the sysroot. `gcc-illumos` carries a patch for its own use of it.
- Its headers predate C23. Fixed for signals by the backport in `illumos-libc`; the matching upstream clean-up
  of `rpc/*.h` (illumos 18214) is not backported because nothing has needed it.

Verified so far, on one SmartOS host: `tests/toolchain.nix` passes, and nixpkgs `hello` builds and runs from the
bridge, together with the xz, gnum4, zlib, gmp, perl, libxcrypt and coreutils it depends on.

A flake will be added once the nixpkgs branch is published.
