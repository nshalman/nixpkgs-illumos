# What illumos-extra adds to SmartOS's proto area after the illumos build: smartos-live's 0-extra-stamp, `gmake
# install` in illumos-extra without STRAP (a non-strap build), with the same illumos-extra commit as the strap
# (../smartos-strap). Each package is compiled by the strap gcc 10 against the proto area of the illumos build
# (smartos-illumos.nightly), where theirs builds against smartos-live's proto, which by then also holds the
# illumos-extra packages installed before it.
#
# One derivation per illumos-extra directory, as for the strap; a package also built for the strap is that
# derivation with strap = false. Each output is laid out as that package's part of the proto area.
{
  lib,
  newScope,
  fetchurl,
  requireFile,
  runCommand,
  binutils-strap,
  smartos-strap,
  smartos-illumos,
  # nixpkgs' perl, for the builds that run the build host's perl there; a `perl` of this scope's own (illumos-extra's
  # perl for the platform) would shadow it in callPackage
  perl,
}:

lib.makeScope newScope (self: {
  # the proto area the packages build against: their DESTDIR before illumos-extra installs into it
  illumosProto = "${smartos-illumos.nightly}/proto";

  # SmartOS's own platform from the same illumos-extra commit, for comparison only: release-20260903
  # (20260903T001557Z), whose gitstatus.json names illumos-extra 5850d8e9 (its illumos-joyent is the release branch's
  # feb8a55d, not the nightly's 40120018). platformReference is the files a running platform shows, the boot archive's
  # root with /usr from usr.lgz; making it takes root and lofi (tests/smartos-platform-reference.sh), so it is added
  # to the store by hand.
  platformTarball = fetchurl {
    url = "https://us-central.manta.mnx.io/Joyent_Dev/public/SmartOS/20260903T001557Z/platform-release-20260903-20260903T001557Z.tgz";
    sha256 = "fe0db94859cff38186b3c99b3d51dc6f6f4d98c10a1b6a66ce04f2cc18d1c2da";
  };
  platformReference = requireFile {
    name = "smartos-platform-20260903T001557Z";
    hashMode = "recursive";
    sha256 = "1kqxvmkpgbg97jxl0lwhpiwvc3h09djn1mnklhhskz56dljxjx2v";
    message = ''
      The unpacked SmartOS platform release-20260903 is made from its published tarball by a script that needs root
      and lofi (a zone with /dev/lofictl will do):
        tests/smartos-platform-reference.sh PLATFORM-TGZ /var/tmp/ref/smartos-platform-20260903T001557Z
        nix-store --add-fixed --recursive sha256 /var/tmp/ref/smartos-platform-20260903T001557Z
      where PLATFORM-TGZ is smartos-extra.platformTarball.
    '';
  };

  # the illumos build's ctfconvert, which illumos-extra's make-ctf is given (smartos-live: CTFBINDIR, the tools
  # stage's opt/onbld/bin/i386)
  ctfconvert = "${smartos-illumos.tools}/opt/onbld/bin/i386/ctfconvert";

  # Tools from their build host's PATH that a package names or runs: GNU ar and ld as gar and gld (pkgsrc's names in
  # /opt/local/bin, which ipmitool's configure sets outright), here the strap's binutils 2.34; and programs of the
  # platform's /usr/bin that packages look for on PATH (soelim for openldap's manuals; nroff and mandoc, which decide
  # openssh's manual format), inputs from the build host, as the platform's dtrace is.
  gnuGTools = runCommand "gnu-ar-ld-g-names" { } ''
    mkdir -p $out/bin
    for t in ar ld; do ln -s ${binutils-strap}/bin/$t $out/bin/g$t; done
  '';
  hostTools = runCommand "host-usr-bin-tools" { } ''
    mkdir -p $out/bin
    for t in soelim nroff mandoc; do ln -s /usr/bin/$t $out/bin/$t; done
  '';

  # the strap scope's compilers, PATH entries and helpers
  inherit (smartos-strap)
    strapBin
    platformDtrace
    illumosExtraSrc
    gcc
    gxx
    libDirFlags
    cleanEnv
    ;

  # the strap's autoconf packages, built the non-strap way, against the illumos proto area or (mkAutoconfAgainst) a
  # view of it
  mkAutoconfAgainst =
    illumosProto:
    smartos-strap.callPackage ../smartos-strap/autoconf.nix {
      strap = false;
      inherit illumosProto;
    };
  mkAutoconf = self.mkAutoconfAgainst self.illumosProto;

  # Store paths in what a package installs are build locations: the proto area's and the compiler's directories in
  # debug information, compile commands a program embeds, the output file name the link-editor records. The platform's
  # binaries carry their own build's in the same places. finishPackage maps them away after the install
  # (./map-store-paths.pl: each to the place it stands for, padded with slashes to the same length, so binaries keep
  # their layout) and recomputes the DT_CHECKSUM of the ELF files it changed. With mapStorePaths = false the store
  # paths are left in and leak into the platform's files (tests/smartos-extra.nix no-store-paths then fails on them).
  mapStorePaths = true;

  # What is done to each package below: perl on PATH, as their build host has /usr/bin/perl on PATH for every package
  # (configure scripts check for it, manuals are made with it: bind, coreutils, curl, wget); then, with
  # mapStorePaths, the store paths mapped away after the install; then its archives made the same from one build to
  # the next (smartos-strap.normalizeArchives).
  finishPackage =
    pkg:
    pkg.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
        perl
        smartos-strap.normalizeArchives
      ];
      postInstall =
        (old.postInstall or "")
        + lib.optionalString self.mapStorePaths ''
          ${perl}/bin/perl ${./map-store-paths.pl} $out | while IFS= read -r f; do
            # a library NSS has signed (its .chk beside it) no longer matches its signature once mapped, and only FIPS
            # mode would notice: fail instead
            case "$f" in
              *.so)
                if [ -e "''${f%.so}.chk" ]; then
                  echo "$f is signed (''${f%.so}.chk) and was changed" >&2
                  exit 1
                fi
                ;;
            esac
            if /usr/bin/elfdump -d "$f" 2>/dev/null | grep ' CHECKSUM ' >/dev/null; then
              mode=$(stat -c %a "$f")
              chmod u+w "$f"
              /usr/bin/elfedit -e dyn:checksum "$f"
              chmod "$mode" "$f"
            fi
          done
        '';
    });

  # first, before the other packages (PRIMARY_COMPILER fixup)
  gcc10 = self.callPackage ./gcc10.nix { };
}
// lib.mapAttrs (_: self.finishPackage) {
  libz = smartos-strap.libz.override {
    strap = false;
    inherit (self) illumosProto;
  };
  bzip2 = smartos-strap.bzip2.override { strap = false; };
  cpp = smartos-strap.cpp.override {
    strap = false;
    inherit (self) illumosProto;
  };

  libexpat = smartos-strap.libexpat.override { mkStrapAutoconf = self.mkAutoconf; };
  libidn = smartos-strap.libidn.override { mkStrapAutoconf = self.mkAutoconf; };
  # before libz in their build (SUBDIRS order), so without it, as the platform's libxml2 is
  libxml = smartos-strap.libxml.override { mkStrapAutoconf = self.mkAutoconf; };

  node = smartos-strap.node.override {
    strap = false;
    inherit (self) illumosProto libz openssl1x;
  };
  perl = smartos-strap.perl.override {
    strap = false;
    inherit (self) illumosProto;
  };
  nss-nspr = smartos-strap.nss-nspr.override {
    strap = false;
    inherit (self) illumosProto;
  };
  openssl1x = smartos-strap.openssl1x.override {
    strap = false;
    inherit (self) illumosProto;
  };
  openssl3 = smartos-strap.openssl3.override {
    strap = false;
    inherit (self) illumosProto;
  };
  libidn2 = self.callPackage ./libidn2.nix { };
  curl = self.callPackage ./curl.nix { };
  wget = self.callPackage ./wget.nix { inherit perl; };
  bind = self.callPackage ./bind.nix { };
  ipmitool = self.callPackage ./ipmitool.nix { };
  rsyslog = self.callPackage ./rsyslog.nix { };
  openldap = self.callPackage ./openldap.nix { };
  openlldp = self.callPackage ./openlldp.nix { };
  ntp = self.callPackage ./ntp.nix { };
  openssh = self.callPackage ./openssh.nix { };
  mdb_v8 = self.callPackage ./mdb_v8.nix { };
  bash = self.callPackage ./bash.nix { };
  less = self.callPackage ./less.nix { };
  gtar = self.callPackage ./gtar.nix { };
  gzip = self.callPackage ./gzip.nix { };
  coreutils = self.callPackage ./coreutils.nix { };
  rsync = self.callPackage ./rsync.nix { };
  uuid = self.callPackage ./uuid.nix { };
  socat = self.callPackage ./socat.nix { };
  gnupg = self.callPackage ./gnupg.nix { };
  tun = self.callPackage ./tun.nix { };
  screen = self.callPackage ./screen.nix { };
  ncurses = self.callPackage ./ncurses.nix { };
  dialog = self.callPackage ./dialog.nix { };
  vim = self.callPackage ./vim.nix { };
  pbzip2 = self.callPackage ./pbzip2.nix { };
  xz = self.callPackage ./xz.nix { };
})
