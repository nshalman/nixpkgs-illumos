# Declarative SMF manifests from Nix — the illumos analogue of NixOS's
# systemd unit generators (nixos/lib/systemd-lib.nix). Function-style:
# an attrset describing a service becomes a manifest XML derivation
# that `svccfg import` accepts. If/when an evalModules front-end
# (smf.services.<name> options) is layered on later, it feeds the same
# attrset shape into these generators — they are the keepable core.
#
# Vocabulary borrows from systemd's serviceConfig where the mapping is
# clean:
#
#   systemd                      SMF
#   -------                      ---
#   ExecStart                    start.exec (exec_method start)
#   ExecStop                     stop.exec  (exec_method stop, default :kill)
#   User / Group                 start.user / start.group (method_credential)
#   Environment                  start.environment (method_environment)
#   After / Requires             dependencies (grouping require_all)
#   Type=simple                  duration = "child"
#   Type=forking                 duration = "contract"
#   Type=oneshot                 duration = "transient"
#
# Two idioms are supported for exec:
#   - direct exec of a long-running binary (see nix-daemon in
#     zone/services.nix);
#   - a method script dispatched on %m, tailscale-style, built with
#     mkSmfMethodScript: exec = "${script} %m" for start and
#     "${script} %m %{restarter/contract}" for stop, so the stop arm
#     can smf_kill_contract the whole contract and run cleanup.
#
# Test: ../tests/smf-lib.sh (svccfg validate + scratch-repo import/export
# golden diff; runs on any illumos zone).
{ pkgs }:
let
  inherit (pkgs) lib writeText writeScript runCommand;
  esc = lib.strings.escapeXML;
in
rec {
  # A %m-dispatch method script following the pattern of
  # /lib/svc/share/README and the illumos-shipped method scripts:
  # sources smf_include.sh, cases on $1 (start|stop), exits
  # $SMF_EXIT_OK. `start` and `stop` are shell fragments; in the stop
  # arm $2 is the restarter contract id when the manifest passes
  # %{restarter/contract}.
  mkSmfMethodScript =
    {
      name,
      start,
      stop ? ''smf_kill_contract "$2" TERM 60'',
    }:
    writeScript "${name}-method" ''
      #!/sbin/sh
      # SMF method script for ${name}. Dispatched on %m by the manifest.

      . /lib/svc/share/smf_include.sh

      case "$1" in
      start)
          ${start}
          ;;
      stop)
          ${stop}
          ;;
      *)
          echo "Usage: $0 {start|stop}" >&2
          exit 1
          ;;
      esac

      exit "$SMF_EXIT_OK"
    '';

  # An SMF manifest XML derivation. The generated XML round-trips
  # through `svccfg import` + `svccfg export` identically to a
  # hand-written manifest of the same shape (test-smf-lib.sh asserts
  # this against the pre-smf-lib nix-daemon.xml).
  mkSmfManifest =
    {
      # FMRI = svc:/<category>/<name>; instance is the default instance.
      name,
      category ? "application",
      # template/common_name loctext.
      description,
      # Optional { name, uri } -> template/documentation doc_link.
      documentation ? null,
      enabled ? true,
      singleInstance ? true,
      # List of { name, fmri, grouping ? "require_all", restartOn ? "none" }.
      # The default set is right for typical daemons in a zone: local
      # filesystems mounted, multi-user milestone reached.
      dependencies ? [
        {
          name = "filesystem-local";
          fmri = "svc:/system/filesystem/local";
        }
        {
          name = "multi-user-server";
          fmri = "svc:/milestone/multi-user-server";
        }
      ],
      # List of { name, fmri, grouping ? "optional_all", restartOn ? "none" }: services that wait for this one
      # (SMF dependents), such as a platform service whose manifest we cannot change.
      dependents ? [ ],
      # { exec, timeout ? 60, user ? null, group ? null, environment ? {} }
      start,
      # Same shape; defaults to SMF's builtin contract kill.
      stop ? { },
      # startd/duration: "child" (SMF tracks the non-forking daemon
      # directly), "contract" (default SMF model, daemon may fork),
      # "transient" (oneshot), or null to omit the property group and
      # take SMF's default (contract).
      duration ? null,
      # startd/ignore_error, e.g. "core,signal" to avoid maintenance
      # state on crash.
      ignoreError ? null,
      # astring propvals under an `application` property group —
      # config the method script reads back via
      # `svcprop -c -p application/<key> $SMF_FMRI` (see the tailscale
      # binary/tun_driver pattern).
      application ? { },
      stability ? "Unstable",
    }:
    let
      start' = {
        timeout = 60;
      }
      // start;
      stop' = {
        exec = ":kill";
        timeout = 30;
      }
      // stop;

      renderDependency = d: [
        "    <dependency name='${esc d.name}'"
        "                grouping='${esc (d.grouping or "require_all")}'"
        "                restart_on='${esc (d.restartOn or "none")}'"
        "                type='service'>"
        "        <service_fmri value='${esc d.fmri}' />"
        "    </dependency>"
      ];

      renderDependent = d: [
        "    <dependent name='${esc d.name}'"
        "               grouping='${esc (d.grouping or "optional_all")}'"
        "               restart_on='${esc (d.restartOn or "none")}'>"
        "        <service_fmri value='${esc d.fmri}' />"
        "    </dependent>"
      ];

      renderMethod =
        mname: m:
        let
          user = m.user or null;
          group = m.group or null;
          env = m.environment or { };
          hasCred = user != null || group != null;
          hasCtx = hasCred || env != { };
        in
        [
          "    <exec_method type='method' name='${mname}'"
          "                 exec='${esc m.exec}'"
          "                 timeout_seconds='${toString m.timeout}'${if hasCtx then ">" else " />"}"
        ]
        ++ lib.optionals hasCtx (
          [ "        <method_context>" ]
          ++ lib.optional hasCred (
            "            <method_credential"
            + lib.optionalString (user != null) " user='${esc user}'"
            + lib.optionalString (group != null) " group='${esc group}'"
            + " />"
          )
          ++ lib.optionals (env != { }) (
            [ "            <method_environment>" ]
            ++ lib.mapAttrsToList (n: v: "                <envvar name='${esc n}' value='${esc v}' />") env
            ++ [ "            </method_environment>" ]
          )
          ++ [
            "        </method_context>"
            "    </exec_method>"
          ]
        );

      renderPropvals = lib.mapAttrsToList (
        n: v: "        <propval name='${esc n}' type='astring' value='${esc v}' />"
      );

      lines =
        [
          "<?xml version='1.0'?>"
          "<!DOCTYPE service_bundle SYSTEM '/usr/share/lib/xml/dtd/service_bundle.dtd.1'>"
          "<!-- Generated by smf-lib.nix from the service definition in"
          "     zone/services.nix. Do not edit the XML; edit the nix. -->"
          "<service_bundle type='manifest' name='nix:${esc name}'>"
          ""
          "<service name='${esc category}/${esc name}' type='service' version='1'>"
          ""
          "    <create_default_instance enabled='${lib.boolToString enabled}' />"
        ]
        ++ lib.optional singleInstance "    <single_instance />"
        ++ lib.concatMap renderDependency dependencies
        ++ lib.concatMap renderDependent dependents
        ++ renderMethod "start" start'
        ++ renderMethod "stop" stop'
        ++ lib.optionals (duration != null || ignoreError != null) (
          [ "    <property_group name='startd' type='framework'>" ]
          ++ lib.optional (
            duration != null
          ) "        <propval name='duration' type='astring' value='${esc duration}' />"
          ++ lib.optional (
            ignoreError != null
          ) "        <propval name='ignore_error' type='astring' value='${esc ignoreError}' />"
          ++ [ "    </property_group>" ]
        )
        ++ lib.optionals (application != { }) (
          [ "    <property_group name='application' type='application'>" ]
          ++ renderPropvals application
          ++ [ "    </property_group>" ]
        )
        ++ [
          "    <stability value='${esc stability}' />"
          ""
          "    <template>"
          "        <common_name>"
          "            <loctext xml:lang='C'>${esc description}</loctext>"
          "        </common_name>"
        ]
        ++ lib.optionals (documentation != null) [
          "        <documentation>"
          "            <doc_link name='${esc documentation.name}'"
          "                      uri='${esc documentation.uri}' />"
          "        </documentation>"
        ]
        ++ [
          "    </template>"
          ""
          "</service>"
          ""
          "</service_bundle>"
        ];
    in
    writeText "${name}.xml" (lib.concatStringsSep "\n" lines + "\n");

  # Collect manifests under lib/svc/manifest/site/ so the result can be
  # a buildEnv path (the system profile exposes them at
  # /nix/var/nix/profiles/default/lib/svc/manifest/site/) and
  # illumos-rebuild can import everything in one directory glob.
  mkSmfManifestBundle =
    {
      name ? "smf-manifests",
      manifests,
    }:
    runCommand name { } ''
      mkdir -p $out/lib/svc/manifest/site
      ${lib.concatMapStringsSep "\n" (m: "cp ${m} $out/lib/svc/manifest/site/${m.name}") manifests}
    '';
}
