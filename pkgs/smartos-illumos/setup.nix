# The start of illumos-joyent's build as smartos-live's tools/build_illumos runs it before the nightly: under
# bldenv, `dmake setup && cd tools && dmake install` in usr/src. setup is closedbins, bldtools (the tools stage,
# as ./tools.nix builds it), sgs (the proto area's directories and the headers: system, user, library, ucb and
# command headers) and mapfiles (the link-editor mapfiles). The output holds the proto area ROOT (proto) and the tools
# proto (tools, whose opt/onbld is ./tools.nix's).
#
# closedbins copies illumos' closed binaries into the proto area and strips their CTF. smartos-live's configure
# (fetch_closed) downloads both tarballs, debug and non-debug, and extracts them into the tree as closed/root_i386
# and closed/root_i386-nd; bldenv's non-DEBUG build takes the -nd one. Opaque binaries, taken as they are
# (smartos-live default.configure-build, ON_CLOSED_BINS_URL and ON_CLOSED_BINS_ND_URL).
{
  mkBldenvStep,
  fetchurl,
  src,
}:

let
  closedBins = fetchurl {
    url = "https://us-central.manta.mnx.io/Joyent_Dev/public/releng/illumos/on-closed-bins.i386.tar.bz2";
    sha256 = "0dc5x63j2jsdks99jds484xwckxlyvvxyjvfb1icl7a8x2n2ps0q";
  };
  closedBinsNd = fetchurl {
    url = "https://us-central.manta.mnx.io/Joyent_Dev/public/releng/illumos/on-closed-bins-nd.i386.tar.bz2";
    sha256 = "0mpzsaqhih96w2zk8ly4gknqjmx4726ms9k926hacawp4kma2g6s";
  };
in
mkBldenvStep {
  pname = "smartos-illumos-setup";
  description = "illumos-joyent's proto area after `dmake setup` (closed binaries, headers, mapfiles) and its tools";
  dir = "usr/src";
  command = "dmake setup && cd tools && dmake install";

  # configure's fetch_closed
  extra.postUnpack = ''
    (cd illumos && tar xpjf ${closedBins} && tar xpjf ${closedBinsNd})
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/tools
    cp -r proto $out/proto
    cp -r illumos/usr/src/tools/proto/root_*-nd/. $out/tools/
    runHook postInstall
  '';

  # What setup leaves in the proto area: headers from each of sgs's groups, the link-editor mapfiles, every non-debug
  # closed kernel driver with its CTF stripped, closedbins' intel_nhmex.conf fix; and the tools.
  installCheckPhase = ''
    runHook preInstallCheck
    p=$out/proto
    for f in usr/include/sys/types.h usr/include/stdio.h usr/include/libscf.h usr/ucbinclude/sys/types.h \
             usr/include/sys/mdb_modapi.h usr/lib/ld/map.noexstk; do
      test -f $p/$f || { echo "missing $p/$f"; exit 1; }
    done
    # closedbins copies all but what exception_lists/closed-bins names
    drivers=$(tar tjf ${closedBinsNd} | grep '^closed/root_i386-nd/kernel/drv/amd64/.' | sed 's#^closed/root_i386-nd/##')
    excluded=$(sed -n 's#^\./##p' ${src}/exception_lists/closed-bins)
    copied=0
    for f in $drivers; do
      if printf '%s\n' "$excluded" | grep -x "$f" >/dev/null; then
        test ! -e $p/$f || { echo "excluded closed binary copied: $p/$f"; exit 1; }
        continue
      fi
      test -f $p/$f || { echo "missing closed binary $p/$f"; exit 1; }
      if /usr/bin/elfdump -c $p/$f | grep SUNW_ctf >/dev/null; then echo "CTF left in $p/$f"; exit 1; fi
      copied=$((copied + 1))
    done
    test $copied -gt 0
    grep -x 'no-smbios=1;' $p/kernel/drv/intel_nhmex.conf >/dev/null
    test -x $out/tools/opt/onbld/bin/i386/cw
    runHook postInstallCheck
  '';
}
