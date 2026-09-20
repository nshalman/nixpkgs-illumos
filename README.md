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

Early, and not yet a bootstrap: there is no `pkgs/stdenv/illumos` in nixpkgs. What exists is two generations of
tools and a bridge between them.

**First generation.** The toolchain packages (`illumos-sysroot`, `illumos-libc`, `illumos-ld`, `gcc-illumos`) were
first built with the older `illumos-recipe-v2` nixpkgs tree (system `x86_64-illumos`), whose userland is linked
against the build host's libc:

```bash
nix-build -I nixpkgs=/path/to/illumos-recipe-v2 -A gcc-illumos
```

**The bridge** (`stdenv/bridge.nix`, used through `bridge.nix`) hands the `illumos-26.05` nixpkgs branch a stdenv
for `x86_64-solaris` as `stdenvStages`. It is made of store paths that must already exist on the builder
(`stdenv/bridge-paths.nix`). Three stages: the wrapped first-generation toolchain; a package set built by the old
userland; and a final package set built by that second set's own tools, because packages built by the old
userland bake paths to it into their scripts. Nix must report `x86_64-solaris` (`patches/nix`) and accept
`x86_64-illumos` as an extra platform.

**Second generation** (`bootstrap/`): everything a bootstrap-files release is made of, built by the bridge, so by
the sysroot toolchain and against `illumos-libc`:

```bash
nix-build bootstrap --arg nixpkgs /path/to/illumos-26.05 -A userland --keep-going
nix-build bootstrap --arg nixpkgs /path/to/illumos-26.05 -A toolchain
```

| Attribute | State |
|---|---|
| `illumos-sysroot` | the pinned sysroot as a fixed-output fetch, unpacked untouched |
| `illumos-libc` | `illumos-sysroot` plus the header hunks of upstream illumos-gate commits, applied verbatim, minus the sysroot's curses/termcap link names and headers (packages must find ncurses, not the system curses). What the compiler wrappers use as libc, and what gcc is configured against. Backports: illumos 16344 (handler types `void (*)()` become `void (*)(int)`, needed by anything compiled as C23 that touches signals) and 14418 (`madvise()` visible under `_XOPEN_SOURCE`, needed by C++). Link-only: nothing may load its libraries at run time. |
| `illumos-ld` | `ld`, `libld.so.4`, `liblddbg.so.4` from a recent illumos-gate commit, linked against the sysroot. Links byte-for-byte like the platform `ld` apart from its version string. |
| `gcc-illumos` | illumos/gcc 14.2.0-il-1, three-stage bootstrap, `--with-sysroot=illumos-libc`. Searches no host header or library directory; finds `ld` on `PATH` so the nixpkgs wrappers apply; defines `_TS_ERRNO` by default, because on illumos code compiled without it reads and writes the main thread's `errno` from every thread. |
| `bootstrap/` | `userland` (coreutils, bash, tar, make, sed, grep, awk, compression, binutils, patchelf, curl, m4, flex, bison, perl) and `toolchain`, built by the bridge |

Tests, all run on an illumos host:

| Test | What it establishes |
|---|---|
| `tests/toolchain.nix` | C and C++ (throw/catch) programs built by a stdenv's wrapped toolchain: interpreter, RUNPATH, libc floor, which `ld` linked them, thread-safe errno |
| `tests/fixup.nix` | nixpkgs' fixup phase has patchelf: unneeded RUNPATH entries go, the rewritten program still runs |
| `tests/audit-closure.sh` | for every ELF object in a runtime closure: libc floor, no sysroot in RUNPATH, system runtime linker, no plain `errno` import, no directory in a NEEDED entry, every dependency resolves, every RUNPATH directory is in the store; no store path of the previous generation; lists the system libraries relied on. `-x` leaves the link-only libc unexamined |
| `tests/audit-closure-selftest.sh` | the audit fails on objects built with those defects |
| `tests/bash-heredoc-path.sh` | a bash sends a large here-document to a temporary file, not to a pipe it can block on forever (bash has no `F_GETPIPE_SZ` on illumos; nixpkgs sets `HEREDOC_PIPESIZE`) |

Known costs of the 2021 floor:

- Its headers predate C23 and hide some interfaces from C++. Fixed where needed by the backports in
  `illumos-libc`; the matching upstream clean-up of `rpc/*.h` (illumos 18214) is not backported because nothing
  has needed it.
- `SO_REUSEPORT` does not exist at the floor, so e.g. nghttp2's applications are not built.

Known host dependencies of the output: the illumos libraries listed by the audit (libc, libm, libsocket, libnsl,
... and, through gettext's link flags, libuutil, libavl, libidmap, libsec, libnvpair, which are not public
interfaces); `/usr/xpg4/bin/sh` in xz's scripts.

Verified so far, on one SmartOS host only: both `bootstrap` attributes build and their closures pass the audit;
`tests/toolchain.nix` and `tests/fixup.nix` pass; the second-generation gcc passes the 22 compiler checks used for
the first. Not done: packaging as bootstrap files, the real nixpkgs stdenv, a second host, 32-bit,
`separateDebugInfo` (`--build-id`).

A flake will be added once the nixpkgs branch is published.
