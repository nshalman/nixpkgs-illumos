# Declarative SMF service list for a zone that runs Nix from this repo — the
# single source of truth for the services it ships, except nix-daemon: its
# manifest comes with Nix (lib/svc/manifest/site/nix-daemon.xml), which
# zone/system.nix also puts in the profile. Consumed by:
#
#   - zone/system.nix: `bundle` is folded into the system profile, so the
#     manifests are visible at
#     /nix/var/nix/profiles/default/lib/svc/manifest/site/, where
#     zone/illumos-rebuild imports them on every switch.
#
# To add a service: define it with smf-lib's mkSmfManifest (and
# mkSmfMethodScript if it needs tailscale-style start/stop logic), add
# it to `manifests`, rebuild. Test with ../tests/smf-lib.sh.
{ pkgs }:
let
  smf = import ./smf-lib.nix { inherit pkgs; };
in
rec {
  # Accounts from the zone's metadata (vmadm's customer_metadata), what a SmartOS base image's zoneinit does with
  # it, so a payload written for those images works here too:
  #   - root_authorized_keys becomes root's and admin's ~/.ssh/authorized_keys, for each whenever it has none: keys
  #     added by hand are never replaced. (admin getting them is this image's choice, Nahum's; the base images give
  #     them to root only. The platform's smartlogin plugin, libsmartsshd, asks a door only Triton's smartlogin
  #     agent serves; a standalone host has none.)
  #   - root_pw and admin_pw set those accounts' passwords, only while the zone is being provisioned
  #     (/var/svc/provisioning), as zoneinit's 91-passwords.sh does: a hash is taken as it is if it is a $2a$
  #     (bcrypt) one, anything else is hashed with the platform's /usr/lib/cryptpass. An account the image does not
  #     have is skipped. If a password was set, sshd's PasswordAuthentication is turned on
  #     (zoneinit's 92-sshd.sh). Without them passwords stay as the image ships them and password
  #     authentication stays off.
  # The service runs before mdata:execute, which ends the provisioning, and before ssh, which reads the
  # configuration. The optional second argument is a directory to act on instead of /, for testing.
  mdataAccountsMethod = smf.mkSmfMethodScript {
    name = "mdata-accounts";
    start = ''
      r=''${2:-}
      k=$(/usr/sbin/mdata-get root_authorized_keys 2>/dev/null) || k=
      [ -n "$k" ] || echo "no root_authorized_keys in the metadata"
      for u in root admin; do
          ent=$(grep "^$u:" "$r/etc/passwd") || continue
          home=$(echo "$ent" | cut -d: -f6)
          ids=$(echo "$ent" | cut -d: -f3,4)
          keys=$r$home/.ssh/authorized_keys
          if [ -e "$keys" ]; then
              echo "$keys exists; left as it is"
          elif [ -n "$k" ]; then
              (umask 077 && mkdir -p "$(dirname "$keys")" && printf '%s\n' "$k" >"$keys.new" &&
                  mv "$keys.new" "$keys" && chown -R "$ids" "$(dirname "$keys")") || exit "$SMF_EXIT_ERR_FATAL"
              echo "installed root_authorized_keys from the metadata into $keys"
          fi
      done

      if [ ! -f "$r/var/svc/provisioning" ]; then
          echo "not provisioning: passwords and sshd left as they are"
          exit "$SMF_EXIT_OK"
      fi
      allow=
      for u in admin root; do
          pw=$(/usr/sbin/mdata-get "''${u}_pw" 2>/dev/null) && [ -n "$pw" ] || continue
          if ! grep "^$u:" "$r/etc/shadow" >/dev/null; then
              echo "no account $u: ''${u}_pw ignored"
              continue
          fi
          case "$pw" in
          '$2a$'*) hash=$pw ;;
          *) hash=$(/usr/lib/cryptpass "$pw") || { echo "cryptpass failed for $u"; continue; } ;;
          esac
          day=$(( $(date +%s) / 86400 ))
          umask 077
          if awk -F: -v OFS=: -v u="$u" -v h="$hash" -v d="$day" '$1 == u { $2 = h; $3 = d } { print }' \
                  "$r/etc/shadow" >"$r/etc/shadow.new" &&
              chmod 0400 "$r/etc/shadow.new" && mv "$r/etc/shadow.new" "$r/etc/shadow"; then
              echo "set the password of $u from ''${u}_pw"
              allow=1
          else
              rm -f "$r/etc/shadow.new"
              echo "setting the password of $u failed"
          fi
      done
      if [ -n "$allow" ]; then
          sed 's/^PasswordAuthentication no$/PasswordAuthentication yes/' "$r/etc/ssh/sshd_config" \
              >"$r/etc/ssh/sshd_config.new" &&
              chmod 0644 "$r/etc/ssh/sshd_config.new" &&
              mv "$r/etc/ssh/sshd_config.new" "$r/etc/ssh/sshd_config" || exit "$SMF_EXIT_ERR_FATAL"
          echo "turned on PasswordAuthentication in $r/etc/ssh/sshd_config"
      fi
    '';
    stop = ":";
  };

  mdataAccounts = smf.mkSmfManifest {
    name = "mdata-accounts";
    description = "root's ssh keys and account passwords from the zone's metadata";
    dependencies = [
      {
        name = "filesystem-local";
        fmri = "svc:/system/filesystem/local";
      }
      {
        name = "mdata-fetch";
        fmri = "svc:/smartdc/mdata:fetch";
        grouping = "optional_all";
      }
    ];
    dependents = [
      {
        name = "before-mdata-execute";
        fmri = "svc:/smartdc/mdata:execute";
      }
      {
        name = "before-ssh";
        fmri = "svc:/network/ssh";
      }
    ];
    start.exec = "${mdataAccountsMethod} %m";
    stop.exec = ":true";
    duration = "transient";
  };

  # The zone's node name on the 127.0.0.1 line of /etc/inet/hosts, as a SmartOS base image's zoneinit puts it there
  # (12-network.sh) while the zone is being provisioned: the brand writes /etc/nodename, and nothing else makes the
  # name resolve. sendmail needs it too: a host name it cannot look up makes it sleep for a minute and retry, at
  # every start and every message ("My unqualified host name ... unknown; sleeping for retry"). Only while the zone
  # is being provisioned (/var/svc/provisioning), and once. The optional second argument is a directory to act on
  # instead of /, for testing.
  hostsNodenameMethod = smf.mkSmfMethodScript {
    name = "hosts-nodename";
    start = ''
      r=''${2:-}
      if [ ! -f "$r/var/svc/provisioning" ]; then
          echo "not provisioning: /etc/inet/hosts left as it is"
          exit "$SMF_EXIT_OK"
      fi
      name=$(cat "$r/etc/nodename" 2>/dev/null)
      if [ -z "$name" ]; then
          echo "no node name in /etc/nodename: /etc/inet/hosts left as it is"
          exit "$SMF_EXIT_OK"
      fi
      hosts=$r/etc/inet/hosts
      if awk -v n="$name" '$1 == "127.0.0.1" { for (i = 2; i <= NF; i++) if ($i == n) f = 1 } END { exit !f }' "$hosts"; then
          echo "$name is on the 127.0.0.1 line of /etc/inet/hosts already"
          exit "$SMF_EXIT_OK"
      fi
      sed "/^127\.0\.0\.1[ 	]/s/\$/ $name/" "$hosts" >"$hosts.new" && chmod 0644 "$hosts.new" &&
          mv "$hosts.new" "$hosts" || exit "$SMF_EXIT_ERR_FATAL"
      echo "added $name to the 127.0.0.1 line of /etc/inet/hosts"
    '';
    stop = ":";
  };

  hostsNodename = smf.mkSmfManifest {
    name = "hosts-nodename";
    description = "the zone's node name in /etc/inet/hosts, at provisioning";
    dependencies = [
      {
        name = "filesystem-local";
        fmri = "svc:/system/filesystem/local";
      }
    ];
    dependents = [
      {
        name = "hosts-nodename_mdata-execute";
        fmri = "svc:/smartdc/mdata:execute";
      }
      {
        name = "hosts-nodename_smtp";
        fmri = "svc:/network/smtp";
      }
      {
        name = "hosts-nodename_sendmail-client";
        fmri = "svc:/network/sendmail-client";
      }
    ];
    start.exec = "${hostsNodenameMethod} %m";
    stop.exec = ":true";
    duration = "transient";
  };

  manifests = [
    mdataAccounts
    hostsNodename
  ];

  bundle = smf.mkSmfManifestBundle { inherit manifests; };
}
