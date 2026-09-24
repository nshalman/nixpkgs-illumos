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
| `/etc/svc/repository.db` | the services imported at image time; `illumos-rebuild` keeps it current afterwards | the zone image |

The zone image builder is still the one on the `illumos-recipe-v2` branch of nixpkgs
(`pkgs/stdenv/illumos-recipe/zone-root/builder.sh`, `make-zone-root.nix`, `make-zone-image.nix`,
`make-joyent-image.nix`); porting it here is open.

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

`tests/installed-zone.sh [CACHE-URL STDENV-PATH]` checks a zone after the installer ran in it: the daemon, the
build users, the store, login shells, an unprivileged build and, given them, substitution of the stdenv from a
cache. It runs as root on that zone and creates two test users there.
