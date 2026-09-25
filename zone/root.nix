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
{ pkgs }:

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
    etc/default/utmpd                    0644 cmd/utmpd/utmpd.dfl
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

  # /etc/nixos/system.nix of a zone from this image: ./example/system.nix without that zone's host-specific
  # settings, so it evaluates to the system profile ./image.nix ships
  nixosSystem = pkgs.writeText "system.nix" ''
    # /etc/nixos/system.nix of a zone made from the nixpkgs-illumos zone image. Rebuild and switch with
    # illumos-rebuild; nixSettings are merged into /etc/nix/nix.conf (zone/nix-conf.nix of nixpkgs-illumos).
    import (import ./nixpkgs-illumos.nix + "/zone/system.nix") {
      pkgs = import ./pkgs.nix;
      nixSettings = { };
    }
  '';
in
pkgs.runCommand "illumos-zone-root"
  {
    inherit gate gateFileList sshdConfig nixosSystem;
    seedDb = "${seed}/repository.db";
    siteProfile = ./site.xml;
    etcProfile = ./profile;
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
    chmod 0400 "$r/etc/shadow"

    # --- sshd -------------------------------------------------------------------------------------------------
    # the platform's sshd with smartos-live's configuration; the method makes host keys in /var/ssh at first start
    f 0644 "$sshdConfig" etc/ssh/sshd_config

    # --- SMF ------------------------------------------------------------------------------------------------
    f 0600 "$seedDb" etc/svc/repository.db
    f 0444 "$siteProfile" etc/svc/profile/site.xml
    l ${profileLink}/lib/svc/manifest/site/nix-daemon.xml var/svc/manifest/site/nix-daemon.xml

    # --- Nix --------------------------------------------------------------------------------------------------
    f 0644 "$etcProfile" etc/profile
    l ${profileLink}/etc/nix/nix.conf etc/nix/nix.conf
    l ${profileLink}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-bundle.crt
    l ca-bundle.crt etc/ssl/certs/ca-certificates.crt
    for n in nixpkgs-illumos.nix pkgs.nix; do f 0644 "$nixosExample/$n" "etc/nixos/$n"; done
    f 0644 "$nixosSystem" etc/nixos/system.nix

    mkdir -p "$out"
    tar -C "$r" -cf "$out/root.tar" --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 .
    (cd "$r" && find . | sort) >"$out/contents"
  ''
