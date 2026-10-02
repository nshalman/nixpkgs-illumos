# illumos-joyent built as smartos-live's tools/build_illumos builds it: `dmake setup` and the tools under bldenv (as
# ./setup.nix), then `nightly illumos.sh` in the same tree, with NIGHTLY_OPTIONS -CiLmMNnt (an incremental,
# non-DEBUG build that builds and uses its own tools). The output is the proto area ROOT (proto) and nightly's logs
# (log).
#
# illumos.sh has what smartos-live's configure adds for the nightly beyond the earlier steps': JAVA_ROOT, the JDK 11
# that builds illumos' Java components (../openjdk11-illumos, where smartos-live has pkgsrc's openjdk11); ASTBINDIR,
# the AST message tools the _msg pass builds libast's catalogs with (./msgcc.nix, where smartos-live has pkgsrc's
# smartos-build-tools); and the default MAKE, the tools proto's dmake, which nightly runs since build_illumos
# unexports MAKE before it. Not set: BUILDVERSION_EXEC (smartos-live's build_etcrelease, for the buildversion
# module; unset, cmd/nsadmin skips it). BANNER_YEAR, which build_illumos takes from the clock, is the year of the
# pinned illumos-joyent commit.
#
# BUILDSTAMP: smartos-live's Makefile writes the platform's build stamp to proto/buildstamp before the illumos build
# ($BUILDSTAMP, or the time), and cmd/Adm/sun builds /etc/motd and /etc/issue from it. Here it is the pinned
# illumos-joyent commit's time (UTC), so the build does not depend on when it runs. build_illumos also makes GATE
# joyent_$BUILDSTAMP; GATE here is joyent_<commit> (./bldenv.nix).
{
  lib,
  mkBldenvStep,
  setup,
  msgcc,
  openjdk11-illumos,
  buildstamp ? "20260911T185107Z",
  # a DEBUG build only, as smartos-live's configure -d (ILLUMOS_ENABLE_DEBUG=exclusive) makes it: NIGHTLY_OPTIONS
  # with D (DEBUG) and F (no non-DEBUG build); the proto area is the same one (MULTI_PROTO no)
  debug ? false,
}:

mkBldenvStep {
  pname = "smartos-illumos-nightly" + lib.optionalString debug "-debug";
  description = "illumos-joyent's proto area from a SmartOS nightly build" + lib.optionalString debug " (DEBUG)";
  dir = "usr/src";
  inherit (setup) command;

  extraEnv = ''
    JAVA_ROOT=${openjdk11-illumos.home};		export JAVA_ROOT
    if [[ -z "\$MAKE" ]]; then
    MAKE="\$SRC/tools/proto/root_i386-nd/opt/onbld/bin/i386/dmake";	export MAKE
    fi
    ASTBINDIR=${msgcc}/usr/ast/bin;		export ASTBINDIR
  ''
  + lib.optionalString debug ''
    NIGHTLY_OPTIONS="-CiLmMNntDF";			export NIGHTLY_OPTIONS
  '';

  afterBldenv = "BANNER_YEAR=2026 ./usr/src/tools/scripts/nightly illumos.sh";

  extra.postUnpack = setup.postUnpack;

  # The build host's /usr/bin/perl: nightly sets its own PATH (onbld, /usr/ccs/bin, /usr/bin, ...) and the build runs
  # perl from it, and runs its perl generators by their #!/usr/bin/perl (sbdgenerr, ao_gendisp, fm's topology maps,
  # ...). On the SmartOS platform /usr/bin/perl is a link to /opt/local/bin/perl (illumos-joyent's manifest), pkgsrc's
  # perl in smartos-live's build zone; on a SmartOS builder without pkgsrc it dangles, and needs a perl there, e.g.
  #   nix-build illumos.nix -A smartos-illumos.setup.perlXml -o /work/opt-local-perl
  #   mkdir -p /opt/local/bin && ln -s /work/opt-local-perl/bin/perl /opt/local/bin/perl
  extra.preBuild = ''
    /usr/bin/perl -e 1 || {
      echo "the build host's /usr/bin/perl does not run; see pkgs/smartos-illumos/nightly.nix"
      exit 1
    }
    mkdir -p proto
    echo ${buildstamp} >proto/buildstamp
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r proto $out/proto
    cp -r illumos/log $out/log
    runHook postInstall
  '';

  # The proto area has the kernel, libc (32- and 64-bit) and commands; the Java component the JDK built (the DTrace
  # API's jar, with its consumer class); libast's message catalog, built by msgcc (a build without it leaves an
  # empty file); and /etc/motd with the build stamp.
  installCheckPhase = ''
    runHook preInstallCheck
    p=$out/proto
    for f in platform/i86pc/kernel/amd64/unix lib/libc.so.1 lib/amd64/libc.so.1 usr/bin/ls \
             usr/share/lib/java/dtrace.jar; do
      test -f $p/$f || { echo "missing $p/$f"; exit 1; }
    done
    ${openjdk11-illumos}/bin/jar tf $p/usr/share/lib/java/dtrace.jar | grep -x 'org/opensolaris/os/dtrace/Consumer.class' >/dev/null
    test -s $p/usr/lib/locale/C/LC_MESSAGES/libast || { echo "libast's catalog is empty"; exit 1; }
    grep -x 'SmartOS (build: ${buildstamp})' $p/etc/motd >/dev/null
    runHook postInstallCheck
  '';
}
