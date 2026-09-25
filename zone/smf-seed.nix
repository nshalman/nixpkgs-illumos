# The seed SMF repository of a zone image: just enough for svc.startd to run early manifest import, which then
# loads every manifest the platform has under /lib/svc/manifest (and ours under /var/svc/manifest/site) before any
# service starts. The seed's own service definitions are therefore replaced by the platform's on first boot;
# they only have to get that far.
#
# The services are the gate's non-global seed list (usr/src/cmd/svc/seed/Makefile), less network-netcfg.xml
# (SmartOS has no network/netcfg), plus early-manifest-import.xml (a separate manifest on SmartOS). The
# manifests are the upstream ones from the illumos-gate commit illumos-ld pins, installed under a scratch root
# and imported with PKG_INSTALL_ROOT, as the gate does, so the repository records their installed
# /lib/svc/manifest paths.
#
# svccfg and svc.configd are the build host's. The repository file is not reproducible byte for byte (sqlite 2),
# so the build checks the configuration instead: `svccfg archive` of the result must equal ./smf-seed-archive.xml.
# A host svccfg that configures the same services passes; one that does not fails here, with the difference.
#
# Test: ../tests/smf-seed.sh
{ pkgs }:

let
  # installed path under /lib/svc/manifest -> source in the gate tree
  manifests = {
    "milestone/multi-user.xml" = "cmd/svc/milestone/multi-user.xml";
    "milestone/multi-user-server.xml" = "cmd/svc/milestone/multi-user-server.xml";
    "milestone/name-services.xml" = "cmd/svc/milestone/name-services.xml";
    "milestone/single-user.xml" = "cmd/svc/milestone/single-user.xml";
    "network/dlmgmt.xml" = "cmd/dlmgmtd/dlmgmt.xml";
    "network/network-initial.xml" = "cmd/svc/milestone/network-initial.xml";
    "network/network-ipmgmt.xml" = "cmd/cmd-inet/lib/ipmgmtd/network-ipmgmt.xml";
    "network/network-loopback.xml" = "cmd/svc/milestone/network-loopback.xml";
    "network/network-physical.xml" = "cmd/svc/milestone/network-physical.xml";
    "network/rpc/bind.xml" = "cmd/rpcbind/bind.xml";
    "system/boot-archive.xml" = "cmd/svc/milestone/boot-archive.xml";
    "system/device/devices-local.xml" = "cmd/svc/milestone/devices-local.xml";
    "system/early-manifest-import.xml" = "cmd/svc/milestone/early-manifest-import.xml";
    "system/filesystem/local-fs.xml" = "cmd/svc/milestone/local-fs.xml";
    "system/filesystem/minimal-fs.xml" = "cmd/svc/milestone/minimal-fs.xml";
    "system/filesystem/root-fs.xml" = "cmd/svc/milestone/root-fs.xml";
    "system/filesystem/usr-fs.xml" = "cmd/svc/milestone/usr-fs.xml";
    "system/identity.xml" = "cmd/svc/milestone/identity.xml";
    "system/manifest-import.xml" = "cmd/svc/milestone/manifest-import.xml";
    "system/svc/global.xml" = "cmd/svc/milestone/global.xml";
    "system/svc/restarter.xml" = "cmd/svc/milestone/restarter.xml";
    "system/utmp.xml" = "cmd/utmpd/utmp.xml";
    # system/console-login.xml is generated, as the gate's milestone Makefile does
  };
in
pkgs.runCommand "illumos-smf-seed"
  {
    gate = pkgs.illumos-ld.src;
    inherit (pkgs.illumos-ld) gateRev;
    expectedArchive = ./smf-seed-archive.xml;
    # one "installed source" line per manifest, each ending in a newline (`read` drops an unterminated last line)
    manifestList = pkgs.lib.concatMapAttrsStringSep "" (
      installed: source: "${installed} ${source}\n"
    ) manifests;
    passAsFile = [ "manifestList" ];
  }
  ''
    root=$PWD/root
    mkdir -p "$root/lib/svc/manifest/system"
    while read -r installed source; do
      mkdir -p "$root/lib/svc/manifest/$(dirname "$installed")"
      cp "$gate/usr/src/$source" "$root/lib/svc/manifest/$installed"
    done <"$manifestListPath"
    (cd "$root/lib/svc/manifest/system" && sh "$gate/usr/src/cmd/svc/milestone/make-console-login-xml")

    mkdir -p "$out/nix-support"
    export PKG_INSTALL_ROOT=$root
    export SVCCFG_DTD=$gate/usr/src/cmd/svc/dtd/service_bundle.dtd.1
    export SVCCFG_REPOSITORY=$out/repository.db
    export SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd
    # One import command per manifest, in sorted order, from a command file. Not all the paths as arguments:
    # svccfg joins its arguments into one 2048-byte command (MAX_CMD_LINE_SZ, svccfg_main.c) and silently cuts the
    # rest, and 23 paths under the build directory exceed it. Not the directory either: services enter the
    # repository in the order they are imported, and a directory is imported in the file system's order.
    find "$root/lib/svc/manifest" -name '*.xml' | sort | sed 's/^/import /' >import.cmds
    /usr/sbin/svccfg -f import.cmds

    /usr/sbin/svccfg archive >"$out/archive.xml"
    if ! cmp -s "$out/archive.xml" "$expectedArchive"; then
      echo "svccfg archive of the seed differs from zone/smf-seed-archive.xml:" >&2
      diff "$expectedArchive" "$out/archive.xml" >&2 || true
      exit 1
    fi
    rm -f "$out"/repository.db-journal

    # which host tools made it: the build does not depend on them, the configuration check above does
    {
      echo "gate $gateRev"
      echo "platform $(uname -v)"
      echo "svccfg $(sha256sum /usr/sbin/svccfg | cut -d' ' -f1)"
      echo "svc.configd $(sha256sum /lib/svc/bin/svc.configd | cut -d' ' -f1)"
    } >"$out/nix-support/build-host"
  ''
