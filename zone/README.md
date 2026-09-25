# A zone that runs Nix from this repo

The zone's state is the system profile, `/nix/var/nix/profiles/default`, built from `system.nix` and switched
with `illumos-rebuild`; everything else is a few files outside the store.

## In the profile (this directory)

| file | what |
|---|---|
| `system.nix` | the profile: Nix, bash, coreutils, rsync, git, grep, awk, the CA bundle, the SMF manifests, `etc/nix/nix.conf` |
| `nix-conf.nix` | renders `etc/nix/nix.conf` from the defaults in `system.nix` merged with the zone's `nixSettings` |
| `smf-lib.nix`, `services.nix` | SMF manifest generators and the services declared: `nix-daemon` |
| `illumos-rebuild` | `build`, `switch`, `rollback`, `list-generations`: `nix-env --set` generations, `svccfg import` of the manifests, deletion of services no longer declared, `svcadm restart` of the services both generations declare when the system path changed |

## Outside the profile, per zone

| path | content | comes from |
|---|---|---|
| `/etc/nixos/nixpkgs-illumos.nix` | the published commit of this repo the zone is built from, fetched as a tarball | `example/nixpkgs-illumos.nix` |
| `/etc/nixos/pkgs.nix` | the package set: that commit's `illumos.nix` on its defaults | `example/pkgs.nix` |
| `/etc/nixos/system.nix` | that commit's `system.nix` applied to the package set and the zone's `nixSettings` | `example/system.nix` |
| `/etc/nix/nix.conf` | symlink to `/nix/var/nix/profiles/default/etc/nix/nix.conf` | made once by hand or by the image |
| `/etc/profile` | puts the profile on PATH and MANPATH, exports the CA bundle | `profile` |
| `/etc/ssl/certs/ca-bundle.crt`, `ca-certificates.crt` | symlinks to the profile's `etc/ssl/certs/ca-bundle.crt` | the zone image |
| `/etc/passwd`, `shadow`, `group` | root's shell is the profile's bash; group `nixbld` with members `nixbld1..32` (uids 30001..30032, gid 30000, home `/var/empty`, no login), which `build-users-group` names | the zone image |
| `/etc/svc/repository.db` | from this directory's image, the seed (`smf-seed.nix`), which manifest-import fills from the platform's manifests on first boot; `illumos-rebuild` imports the profile's manifests afterwards | the zone image |

## The zone image

`nix-build image.nix` (with `pkgs`) makes the inputs, then, as root on a zone with a delegated dataset,
`make-joyent-image --parent-dataset <dataset> --inputs <result> --name nix-zone --version <v> --out-dir <dir>`
makes `<uuid>.zfs.gz` and `<uuid>.imgmanifest` for `imgadm install`. It ships the Nix store: the system profile's
closure is copied from the building host's store, and the database is loaded.

| file | what |
|---|---|
| `image.nix` | the inputs: `root.tar`, the system profile (`system.nix` with no zone-specific settings), its closure and registration |
| `root.nix` | `/etc`, `/var` and the brand's mount points: what the enabled services, logins and Nix need, from the illumos-gate commit `illumos-ld` pins (sshd's configuration from smartos-live); accounts with the build users; each file with the reason it is there. A first cut, not yet booted |
| `site.xml` | the site profile: turns on the zone console, turns off what a zone should not run (mDNS, rpcbind, rcap, shares, inetd, IPsec, IP tunnels). SMF applies a profile once, on the first boot |
| `smf-seed.nix`, `smf-seed-archive.xml` | a seed `/etc/svc/repository.db` from upstream illumos-gate manifests: the gate's non-global seed services, just enough for early manifest import to load the platform's manifests from `/lib/svc/manifest` on first boot, before any service starts. The build checks `svccfg archive` of the result against `smf-seed-archive.xml` |
| `make-joyent-image` | the root-run step: a dataset, the root file system, the store, the database, a snapshot, `zfs send`, the manifest (adapted from `make-joyent-image.sh` on nixpkgs' `illumos-recipe-v2` branch) |

## Installing Nix in an existing zone

`nix-build ../illumos.nix -A nixInstallerTarball` makes `nix-<version>-x86_64-solaris.tar.xz`, Nix's binary
tarball with its multi-user installer; the illumos section of the Nix manual's "Installing a Binary Distribution"
says how to install from it. The result is an ordinary multi-user Nix installation (nix.conf a plain file, Nix in
root's default profile), not the system profile above.

## Tests

Each takes the path of a file evaluating to the package set, e.g. `/etc/nixos/pkgs.nix`, and runs on a live
zone without touching its profile or SMF repository:

    tests/smf-lib.sh /etc/nixos/pkgs.nix          # manifests validate and match the golden export
    tests/illumos-rebuild.sh /etc/nixos/pkgs.nix  # switch, removal, restart, rollback on scratch state
    tests/nix-conf.sh /etc/nixos/pkgs.nix         # the rendered nix.conf, and that nix parses it
    tests/smf-seed.sh /etc/nixos/pkgs.nix         # the seed: its services, configuration, recorded manifest paths

`tests/zone-image.sh PKGS-FILE PARENT-DATASET` (root, a delegated dataset) makes an image, receives its stream
and checks the received root in a chroot: modes, accounts, a login shell finding nix, Nix's database, the seed,
`sshd -t`, that every link resolves, and that `/etc/nixos/system.nix` evaluates to the shipped system.

`tests/installed-zone.sh [CACHE-URL STDENV-PATH]` checks a zone after the installer ran in it: the daemon, the
build users, the store, login shells, an unprivileged build and, given them, substitution of the stdenv from a
cache. It runs as root on that zone and creates two test users there.
