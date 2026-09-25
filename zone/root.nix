# The root file system of a SmartOS joyent-brand zone image, except /nix: a tar of /etc, /var and the empty
# directories the brand mounts over (/usr, /lib, /sbin, /system/*, /proc, /dev come from the global zone).
#
# It holds what the zone's enabled services, logins and Nix need, not what a proto area has. The SMF repository is
# ./smf-seed.nix; at first boot manifest-import loads the platform's manifests from /lib/svc/manifest and ours from
# /var/svc/manifest/site, then applies /etc/svc/profile/generic.xml and ./site.xml. Text files come from the
# illumos-gate commit illumos-ld pins, except sshd_config: the platform's sshd is SmartOS's (illumos-extra), and its
# configuration is smartos-live's. Every file below says why it is here; a first cut, to be checked against a zone
# booted from it (etc-reads.d traces of lookups that fail).
#
# Tar entries are owned by root (0:0), with the modes set here.
{
  pkgs,
  # the system profile the image ships (./image.nix), whose SMF manifests the first boot must import
  system ? import ./system.nix { inherit pkgs; },
}:

let
  inherit (pkgs) lib;
  gate = pkgs.illumos-ld.src;
  seed = import ./smf-seed.nix { inherit pkgs; };
  smartosLiveRev = "547013319fd06675b9d60eaee0d8dba42e58637d";
  sshdConfig = pkgs.fetchurl {
    name = "sshd_config";
    url = "https://raw.githubusercontent.com/TritonDataCenter/smartos-live/${smartosLiveRev}/src/etc/ssh/sshd_config";
    sha256 = "19h9101rlbl5pkdfl39r22wbyhzp7rl2v97wj6gd643n5gg0bws5";
  };
  profileLink = "/nix/var/nix/profiles/default";

  # installed path, mode, source under the gate's usr/src; one line each
  gateFiles = ''
    # init(8) and SMF's start: run levels, svc.startd
    etc/inittab                          0644 cmd/initpkg/inittab
    # fs-minimal and fs-local mount what the zone may mount from here
    # (vfstab is generated below, as the gate's vfstab.sh does)
    # defaults read by init, login, passwd, su, cron, name services, syslogd, network start-up, the DHCP agent, utmpd
    etc/default/login                    0644 cmd/login/login.dfl
    etc/default/passwd                   0644 cmd/passwd/passwd.dfl
    etc/default/su                       0644 cmd/su/su.dfl
    etc/default/cron                     0644 cmd/cron/cron.dfl
    etc/default/nss                      0644 cmd/netfiles/nss.dfl
    etc/default/syslogd                  0644 cmd/syslogd/syslogd.dfl
    etc/default/inetinit                 0644 cmd/cmd-inet/etc/default/inetinit.dfl
    etc/default/dhcpagent                0644 cmd/cmd-inet/sbin/dhcpagent/dhcpagent.dfl
    # the DHCP option tables dhcpagent and dhcpinfo read, for a NIC configured by DHCP
    etc/dhcp/inittab                     0644 cmd/cmd-inet/etc/dhcp/inittab
    etc/dhcp/inittab6                    0644 cmd/cmd-inet/etc/dhcp/inittab6
    etc/default/utmpd                    0644 cmd/utmpd/utmpd.dfl
    # useradd's defaults (with the empty /etc/skel below, `useradd -m` works)
    etc/default/useradd                  0644 cmd/oamuser/user/useradd.dfl
    # PAM for login, su, sshd, cron
    etc/pam.conf                         0644 lib/libpam/pam.conf
    # name services: the switch (the gate's DNS variant, as SmartOS installs), nscd, TLI transports
    etc/nsswitch.conf                    0644 cmd/netfiles/nsswitch.dns
    etc/nscd.conf                        0644 cmd/initpkg/nscd.conf
    etc/netconfig                        0644 cmd/netfiles/netconfig
    etc/net/ticlts/hosts                 0644 cmd/netfiles/hosts
    etc/net/ticlts/services              0644 cmd/netfiles/services
    etc/net/ticots/hosts                 0644 cmd/netfiles/hosts
    etc/net/ticots/services              0644 cmd/netfiles/services
    etc/net/ticotsord/hosts              0644 cmd/netfiles/hosts
    etc/net/ticotsord/services           0644 cmd/netfiles/services
    # network files: hosts, services and friends; address selection (network/initial)
    etc/inet/hosts                       0644 cmd/cmd-inet/etc/hosts
    etc/inet/services                    0644 cmd/cmd-inet/etc/services
    etc/inet/protocols                   0644 cmd/cmd-inet/etc/protocols
    etc/inet/networks                    0644 cmd/cmd-inet/etc/networks
    etc/inet/netmasks                    0644 cmd/cmd-inet/etc/netmasks
    etc/inet/ipaddrsel.conf              0644 cmd/cmd-inet/etc/ipaddrsel.conf
    # the zone's datalink and IP interface stores (dlmgmtd, ipmgmtd)
    etc/dladm/datalink.conf              0644 cmd/dlmgmtd/datalink.conf
    etc/dladm/secobj.conf                0600 cmd/dladm/secobj.conf
    etc/dladm/flowadm.conf               0644 cmd/flowadm/flowadm.conf
    etc/dladm/flowprop.conf              0644 cmd/flowadm/flowprop.conf
    etc/ipadm/ipadm.conf                 0644 cmd/cmd-inet/lib/ipmgmtd/ipadm.conf
    # socket types
    etc/sock2path.d/system%2Fkernel      0644 cmd/cmd-inet/etc/sock2path.d/system%2Fkernel
    # the kernel crypto framework (system/cryptosvc) and libpkcs11
    etc/crypto/kcf.conf                  0644 cmd/cmd-crypto/etc/kcf.conf
    etc/crypto/pkcs11.conf               0644 cmd/cmd-crypto/etc/pkcs11.conf
    # RBAC (system/rbac, pfexec), password hashing, the default project
    etc/security/auth_attr               0644 lib/libsecdb/auth_attr.txt
    etc/security/exec_attr               0644 lib/libsecdb/exec_attr.txt
    etc/security/prof_attr               0644 lib/libsecdb/prof_attr.txt
    etc/security/policy.conf             0644 lib/libsecdb/policy.conf
    etc/security/crypt.conf              0644 cmd/initpkg/security/crypt.conf
    etc/user_attr                        0644 lib/libsecdb/user_attr.txt
    # the audit classes and events sshd and login look up when they record a session (libbsm); read by sshd-session
    # in a trace of an ssh login on nixpkgs-native
    etc/security/audit_class             0644 lib/libbsm/audit_class.txt
    etc/security/audit_event             0644 lib/libbsm/audit_event.txt
    etc/project                          0644 cmd/Adm/project
    # system-log and log rotation (logadm-upgrade, root's crontab)
    etc/syslog.conf                      0644 cmd/syslogd/syslog.conf
    etc/logadm.conf                      0644 cmd/logadm/logadm.conf
    # cron
    etc/cron.d/at.deny                   0644 cmd/Adm/at.deny
    etc/cron.d/cron.deny                 0644 cmd/Adm/cron.deny
    etc/cron.d/queuedefs                 0644 cmd/Adm/queuedefs
    var/spool/cron/crontabs/root         0600 cmd/Adm/root
    # SMF profiles manifest-import applies at first boot (generic.xml is a link to generic_limited_net.xml below;
    # platform.xml is made at first boot)
    etc/svc/profile/generic_limited_net.xml 0444 cmd/svc/profile/generic_limited_net.xml
    etc/svc/profile/generic_open.xml     0444 cmd/svc/profile/generic_open.xml
    etc/svc/profile/platform_none.xml    0444 cmd/svc/profile/platform_none.xml
  '';

  gateFileList = pkgs.writeText "zone-root-gate-files" gateFiles;

  # vmadm (checkDatasetProvisionable in the platform's /usr/vm/node_modules/VM.js) provisions a joyent-brand zone
  # only from an image whose /var/zoneinit/zoneinit.json declares features.var_svc_provisioning, the promise that
  # the zone turns /var/svc/provisioning into provision_success itself. Here the platform's mdata-fetch enables
  # mdata:execute, which does that (/lib/svc/method/mdata-execute). Without the file vmadm says "provisioning
  # dataset <image> with brand joyent is not supported". The same declaration the recipe-v2 image carried.
  zoneinitJson = pkgs.writeText "zoneinit.json" ''
    {
      "version": "1.5.1",
      "features": {
        "var_svc_provisioning": true,
        "reboot": true
      }
    }
  '';

  # /etc/nixos/system.nix of a zone from this image: ./example/system.nix without that zone's host-specific
  # settings, so it evaluates to the system profile ./image.nix ships
  nixosSystem = pkgs.writeText "system.nix" ''
    # /etc/nixos/system.nix of a zone made from the nixpkgs-illumos zone image. Rebuild and switch with
    # illumos-rebuild; nixSettings are merged into /etc/nix/nix.conf (zone/nix-conf.nix of nixpkgs-illumos).
    import (import ./nixpkgs-illumos.nix + "/zone/system.nix") {
      pkgs = import ./pkgs.nix;
      nixSettings = {
        # The nixpkgs-illumos binary cache (unsigned for now, hence trusted=true); or, without a rebuild, see
        # /etc/nix/nix.local.conf.example.
        # extra-substituters = [ "${cacheUrl}" ];
      };
    }
  '';

  # The nixpkgs-illumos binary cache, off until a zone turns it on
  cacheUrl = "https://www.shalman.org/files/cache/?trusted=true";
  nixLocalConfExample = pkgs.writeText "nix.local.conf.example" ''
    # Local additions to /etc/nix/nix.conf, which includes /etc/nix/nix.local.conf last (and skips it if it is
    # missing). To use the nixpkgs-illumos binary cache:
    #   cp /etc/nix/nix.local.conf.example /etc/nix/nix.local.conf && svcadm restart nix-daemon
    # The cache is not signed yet, hence trusted=true.
    extra-substituters = ${cacheUrl}
  '';

  # sudo as the SmartOS base images configure it (pkgsrc's /opt/local/etc/sudoers and sudoers.d/admin), with this
  # zone's paths: the setuid copies and the system profile on the secure path
  sudoers = pkgs.writeText "sudoers" ''
    Defaults!${profileLink}/bin/visudo env_keep += "SUDO_EDITOR EDITOR VISUAL"
    Defaults secure_path="/opt/nix/bin:${profileLink}/bin:/usr/sbin:/usr/bin:/sbin"
    root ALL=(ALL:ALL) ALL
    @includedir /etc/sudoers.d
  '';
  sudoersAdmin = pkgs.writeText "sudoers-admin" ''
    admin ALL=(root) NOPASSWD: SETENV: ALL
  '';

  motd = pkgs.writeText "motd" ''

      nixpkgs-illumos zone: Nix ${pkgs.nixVersions.nix_2_35.version} in a SmartOS zone
      https://github.com/nshalman/nixpkgs-illumos

      system profile  /nix/var/nix/profiles/default, from /etc/nixos/system.nix
      nix settings    /etc/nix/nix.conf, then /etc/nix/nix.local.conf if present
      binary cache    cp /etc/nix/nix.local.conf.example /etc/nix/nix.local.conf
                      svcadm restart nix-daemon

  '';
in
pkgs.runCommand "illumos-zone-root"
  {
    inherit gate gateFileList sshdConfig nixosSystem zoneinitJson nixLocalConfExample motd sudoers sudoersAdmin;
    seedDb = "${seed}/repository.db";
    siteProfile = ./site.xml;
    etcProfile = ./profile;
    etcBashrc = ./bashrc;
    nixosExample = ./example;
    nativeBuildInputs = [ pkgs.gnutar ];
  }
  ''
    r=$PWD/root
    mkdir -m 0755 "$r"

    d() { mkdir -p "$r/$2"; chmod "$1" "$r/$2"; }   # d MODE DIR
    f() { mkdir -p "$(dirname "$r/$3")"; cp "$2" "$r/$3"; chmod "$1" "$r/$3"; }   # f MODE SOURCE PATH
    e() { mkdir -p "$(dirname "$r/$2")"; : >"$r/$2"; chmod "$1" "$r/$2"; }   # e MODE PATH: an empty file
    l() { mkdir -p "$(dirname "$r/$2")"; ln -s "$1" "$r/$2"; }   # l TARGET PATH

    # --- directories -----------------------------------------------------------------------------------------
    # mount points the brand lofs-mounts or mounts file systems on
    for p in dev etc home lib proc sbin system system/contract system/object usr .zonecontrol; do d 0755 "$p"; done
    d 1777 tmp
    l ./usr/bin bin
    # root's home; /var/empty is the build users' home
    d 0700 root
    # root's non-login bash (a command run over ssh, an interactive subshell) reads ~/.bashrc and not /etc/profile;
    # this puts the system profile on its PATH too, as the recipe-v2 image did (it also linked ~/.bash_profile,
    # which a login shell would read after /etc/profile, sourcing it twice)
    l /etc/profile root/.bashrc
    # useradd -m copies /etc/skel into a new home and fails without it. Empty: the gate's skeleton files
    # (cmd/nsadmin dot-profile.sh, dot-kshrc.sh) set nothing, and SmartOS's and the pkgsrc images' .profile set
    # PATH outright, which drops the system profile /etc/profile added.
    d 0755 etc/skel
    for p in var var/cron var/empty var/log var/logadm var/run var/spool var/spool/cron var/spool/cron/crontabs \
             var/ssh var/svc var/svc/log var/svc/manifest var/svc/manifest/site var/svc/profile var/ld var/ld/amd64; do
      d 0755 "$p"
    done
    d 0775 var/adm
    d 1777 var/tmp
    l . var/ld/32
    l amd64 var/ld/64
    for p in etc/svc etc/svc/profile etc/svc/volatile etc/dfs etc/rc0.d etc/rc1.d etc/rc2.d etc/rc3.d etc/rcS.d \
             etc/security etc/cron.d; do
      d 0755 "$p"
    done

    # --- files from the gate -----------------------------------------------------------------------------------
    grep -v '^[[:space:]]*#' "$gateFileList" | while read -r path mode src; do
      [ -n "$path" ] || continue
      f "$mode" "$gate/usr/src/$src" "$path"
    done
    # the gate's /etc/default/init, with the time zone SmartOS zones use instead of PST8PDT
    f 0644 "$gate/usr/src/cmd/init/init.dfl" etc/default/init
    sed -i 's/^TZ=.*/TZ=UTC/' "$r/etc/default/init"
    grep -q '^TZ=UTC$' "$r/etc/default/init"
    # /etc/logindevperm, which login reads for console device permissions, made as the gate's build makes it
    MACH=i386 sh "$gate/usr/src/cmd/login/logindevperm.sh" >"$r/etc/logindevperm"
    chmod 0644 "$r/etc/logindevperm"
    # /etc/vfstab, made as the gate's build makes it
    (cd "$r/etc" && sh "$gate/usr/src/cmd/initpkg/vfstab.sh")
    chmod 0644 "$r/etc/vfstab"

    # the links the gate's packages install
    l ./inet/hosts etc/hosts
    l ./hosts etc/inet/ipnodes
    l ./inet/services etc/services
    l ./inet/protocols etc/protocols
    l ./inet/networks etc/networks
    l ./inet/netmasks etc/netmasks
    l ./default/init etc/TIMEZONE
    l ../var/adm/utmpx etc/utmpx
    l ../var/adm/wtmpx etc/wtmpx
    l generic_limited_net.xml etc/svc/profile/generic.xml

    # mount points that are files: mntfs on /etc/mnttab, sharefs on /etc/dfs/sharetab
    e 0444 etc/mnttab
    e 0444 etc/dfs/sharetab
    # syslog.conf's files; syslogd does not create them
    e 0644 var/adm/messages
    e 0644 var/log/syslog
    # the login accounting files the gate's SUNWcs package ships (there wtmpx belongs to adm:adm; here, as every
    # entry of the tar, to root)
    e 0644 var/adm/utmpx
    e 0644 var/adm/wtmpx

    # --- accounts ---------------------------------------------------------------------------------------------
    # the gate's system accounts; root's shell is the system profile's bash and root has no password (NP: key or
    # zlogin only), as the earlier image had; build users nixbld1..32 (uid 30001.., gid 30000), locked, no login,
    # listed as members of nixbld, which Nix requires
    f 0644 "$gate/usr/src/cmd/Adm/sun/passwd" etc/passwd
    f 0400 "$gate/usr/src/cmd/Adm/sun/shadow" etc/shadow
    f 0644 "$gate/usr/src/cmd/Adm/group" etc/group
    chmod u+w "$r/etc/shadow"
    sed -i 's|^root:x:0:0:Super-User:/root:.*|root:x:0:0:Super-User:/root:${profileLink}/bin/bash|' "$r/etc/passwd"
    sed -i 's|^root:[^:]*:|root:NP:|' "$r/etc/shadow"
    grep -q '^root:x:0:0:Super-User:/root:${profileLink}/bin/bash$' "$r/etc/passwd"
    grep -q '^root:NP:' "$r/etc/shadow"
    members=
    for i in $(seq 1 32); do
      echo "nixbld$i:x:$((30000 + i)):30000:Nix build user $i:/var/empty:/usr/bin/false" >>"$r/etc/passwd"
      echo "nixbld$i:*LK*:::::::" >>"$r/etc/shadow"
      members=''${members:+$members,}nixbld$i
    done
    echo "nixbld::30000:$members" >>"$r/etc/group"
    # admin, as the SmartOS base images have it (uid 100, group staff, no password until admin_pw sets one at
    # provisioning, the Service Management and Software Installation RBAC profiles), so payloads that set admin_pw
    # work here too, but with the system profile's bash as root has. Its home belongs to it, see the tar below.
    # Those images also give it sudo without a password, as does this one (see sudo below).
    echo "admin:x:100:10::/home/admin:${profileLink}/bin/bash" >>"$r/etc/passwd"
    echo "admin:NP:::::::" >>"$r/etc/shadow"
    echo "admin::::type=normal;profiles=Service Management,Software Installation" >>"$r/etc/user_attr"
    d 0755 home/admin
    chmod 0400 "$r/etc/shadow"

    # --- sudo -------------------------------------------------------------------------------------------------
    # the setuid copies illumos-rebuild keeps up to date (./illumos-rebuild, installSetuid), as it would make them
    # for the shipped system
    while read -r p; do
      [ -n "$p" ] || continue
      f 4511 "${system}/$p" "opt/nix/bin/$(basename "$p")"
    done <${system}/etc/setuid-programs
    f 0440 "$sudoers" etc/sudoers
    d 0755 etc/sudoers.d
    f 0440 "$sudoersAdmin" etc/sudoers.d/admin

    # --- sshd -------------------------------------------------------------------------------------------------
    # the platform's sshd with smartos-live's configuration; the method makes host keys in /var/ssh at first start
    f 0644 "$sshdConfig" etc/ssh/sshd_config
    # ... with passwords off, as the SmartOS zone images (pkgsrc base) ship it: no password or keyboard-interactive
    # (PAM) logins, and root by key only. The mdata-accounts service (./services.nix) turns PasswordAuthentication
    # on when the metadata sets root_pw or admin_pw at provisioning, as those images' zoneinit does.
    sed -i -e 's/^PasswordAuthentication yes$/PasswordAuthentication no/' \
      -e 's/^PermitRootLogin yes$/PermitRootLogin prohibit-password/' "$r/etc/ssh/sshd_config"
    echo "KbdInteractiveAuthentication no" >>"$r/etc/ssh/sshd_config"
    grep -q '^PasswordAuthentication no$' "$r/etc/ssh/sshd_config"
    grep -q '^PermitRootLogin prohibit-password$' "$r/etc/ssh/sshd_config"

    # --- SMF ------------------------------------------------------------------------------------------------
    f 0600 "$seedDb" etc/svc/repository.db
    f 0444 "$siteProfile" etc/svc/profile/site.xml
    # The first boot's manifest-import reads /lib/svc/manifest and /var/svc/manifest, not the profile (where
    # illumos-rebuild imports from later): a link here for every service of the profile, nix-daemon and ./services.nix.
    for m in ${system}/lib/svc/manifest/site/*.xml; do
      l ${profileLink}/lib/svc/manifest/site/$(basename "$m") var/svc/manifest/site/$(basename "$m")
    done
    # what vmadm reads from the image before it provisions a zone (see zoneinitJson)
    f 0644 "$zoneinitJson" var/zoneinit/zoneinit.json

    # --- Nix --------------------------------------------------------------------------------------------------
    f 0644 "$etcProfile" etc/profile
    f 0644 "$etcBashrc" etc/bashrc
    f 0644 "$motd" etc/motd
    f 0644 "$nixLocalConfExample" etc/nix/nix.local.conf.example
    l ${profileLink}/etc/nix/nix.conf etc/nix/nix.conf
    l ${profileLink}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-bundle.crt
    l ca-bundle.crt etc/ssl/certs/ca-certificates.crt
    for n in nixpkgs-illumos.nix pkgs.nix; do f 0644 "$nixosExample/$n" "etc/nixos/$n"; done
    f 0644 "$nixosSystem" etc/nixos/system.nix

    mkdir -p "$out"
    tar -C "$r" -cf "$out/root.tar" --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 \
      --exclude=./home/admin .
    # admin's home is admin's (100:10)
    tar -C "$r" -rf "$out/root.tar" --numeric-owner --owner=100 --group=10 --mtime=@1 ./home/admin
    (cd "$r" && find . | sort) >"$out/contents"
  ''
