# The part of smartos-live's tree that tools/build_live runs from (it finds the tree by its own path): build_live and
# tools/lib/build_common.sh, the tools it runs at their places, and proto, from which it reads the build stamp and
# which its checks and DEBUG kernel test look at (the illumos build's proto area).
#
# What build_live makes in the mounted image without needing root is made by Nix here, and installed by the tools it
# runs for it, in place of theirs: tools/smf_import and tools/build_seeds install the SMF repository and the
# joyent-minimal seed (smfRepository, smfSeed: owned as their scripts leave them), tools/build_etcrelease prints
# gitstatus.json (-g) and etc/release (-v; versionFiles), which build_live writes in. Its whatis step, which runs the
# illumos tools' man -w itself, installs the whatis databases instead (./build-live-whatis.patch). tools/tzcheck is
# ./tzcheck-store.sh around theirs: the proto area is in the store, which keeps no hard links.
#
# build_live writes its log in the tree (log/), so it is run from a writable directory of links to this one.
{
  runCommand,
  smartosLive,
  illumosProto,
  liveTools,
  smfRepository,
  smfSeed,
  versionFiles,
  whatis,
  bootProto,
  pigz,
}:

runCommand "smartos-live-workspace" { } ''
  mkdir -p $out/tools/lib $out/tools/builder $out/tools/tzcheck $out/tools/ucodecheck
  cp ${smartosLive}/tools/build_live $out/tools/
  chmod u+w $out/tools/build_live
  patch $out/tools/build_live ${./build-live-whatis.patch}
  substituteInPlace $out/tools/build_live --subst-var-by whatis ${whatis}
  cp ${smartosLive}/tools/lib/build_common.sh $out/tools/lib/
  ln -s ${liveTools}/tools/builder/builder $out/tools/builder/builder
  ln -s ${liveTools}/tools/ucodecheck/ucodecheck $out/tools/ucodecheck/ucodecheck
  ln -s ${liveTools}/tools/cryptpass $out/tools/cryptpass
  substitute ${./tzcheck-store.sh} $out/tools/tzcheck/tzcheck --subst-var-by tzcheck ${liveTools}/tools/tzcheck/tzcheck
  chmod +x $out/tools/tzcheck/tzcheck

  # what tools/build_boot_image (`gmake usb`, build-usb) takes from the tree: its script, patched to take extra
  # loader variables and to compress with nixpkgs' pigz (./build-boot-image.patch), format_image and proto.boot
  cp ${smartosLive}/tools/build_boot_image $out/tools/
  chmod u+w $out/tools/build_boot_image
  patch $out/tools/build_boot_image ${./build-boot-image.patch}
  substituteInPlace $out/tools/build_boot_image --subst-var-by pigz ${pigz}/bin/pigz
  mkdir -p $out/tools/format_image
  ln -s ${liveTools}/tools/format_image/format_image $out/tools/format_image/format_image
  ln -s ${bootProto} $out/proto.boot

  cat >$out/tools/smf_import <<'EOF'
  #!/bin/bash
  # smf_import ROOT: the global zone's SMF repository, made by Nix (smartos-live smfRepository), as theirs leaves it
  set -euo pipefail
  cp ${smfRepository}/etc/svc/repository.db "$1/etc/svc/repository.db"
  chown root:root "$1/etc/svc/repository.db"
  chmod 600 "$1/etc/svc/repository.db"
  EOF
  cat >$out/tools/build_seeds <<'EOF'
  #!/bin/bash
  # build_seeds ROOT: joyent-minimal's seed repository, made by Nix (smartos-live smfSeed), as theirs leaves it
  set -euo pipefail
  r=usr/lib/brand/joyent-minimal/repository.db
  cp ${smfSeed}/$r "$1/$r"
  chmod 444 "$1/$r"
  chown root:root "$1/$r"
  EOF
  cat >$out/tools/build_etcrelease <<'EOF'
  #!/bin/bash
  # build_etcrelease -g | -v BUILDSTAMP: gitstatus.json and etc/release, made by Nix (smartos-live versionFiles)
  set -euo pipefail
  case "$*" in
    -g) cat ${versionFiles}/etc/versions/build ;;
    "-v $(head -1 ${versionFiles}/etc/release | awk '{ print $2 }')") cat ${versionFiles}/etc/release ;;
    *) echo "build_etcrelease: $* is not what was made (${versionFiles})" >&2; exit 1 ;;
  esac
  EOF
  chmod +x $out/tools/smf_import $out/tools/build_seeds $out/tools/build_etcrelease

  ln -s ${illumosProto} $out/proto
''
