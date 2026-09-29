# A pre-built OpenJDK 11 for illumos, to bootstrap building OpenJDK from source (jdk11u takes a boot JDK of version 10
# or 11). Peter Tribble's build for Tribblix, from his illumos patch set (github.com/ptribble/jdk-sunos-patches, the
# one OmniOS and OpenIndiana build from), published as a tarball "for bootstrapping in other distributions". Old
# versions are removed from that site, so pin one that is mirrored.
#
# The binaries find the illumos system libraries on the default path (libc, libz, ...) and the gcc runtime
# (libstdc++, libgcc_s) there too, which on SmartOS is the platform's /usr/lib/64 and elsewhere may be missing
# (Tribblix's page has OpenIndiana set LD_LIBRARY_PATH). Here the objects that need the gcc runtime get the stdenv
# compiler's runtime on their RUNPATH, with elfedit: the link-editor left room for it (DT_SUNW_STRPAD, spare DT_NULLs).
#
# It is run headless: the X11 libraries libawt_xawt, libjawt and libsplashscreen need, and libfontmanager's freetype,
# are not provided, whatever gtkSupport (nixpkgs' OpenJDK asks its boot JDK for that) says. libsplashscreen also wants
# a newer libz than SmartOS's (version SUNW_1.3).
{
  lib,
  stdenv,
  fetchurl,
  gtkSupport ? false,
}:

let
  gccRuntime = "${lib.getLib stdenv.cc.cc}/lib/amd64";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "tribblix-jdk-bin";
  version = "11.0.30";

  src = fetchurl {
    url = "https://pkgs.tribblix.org/openjdk/jdk11u-jdk-${finalAttrs.version}-ga.tar.gz";
    # as published on https://pkgs.tribblix.org/openjdk/
    sha256 = "725d35c1168dcd0210f9209d62d65262e84aecbbf9d5a0893653258f3125e453";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    pushd $out >/dev/null
    for f in $(find bin lib -type f); do
      /usr/bin/elfdump -d "$f" >$TMPDIR/dyn 2>/dev/null || continue
      grep -E 'NEEDED +[^ ]+ +(libstdc\+\+\.so\.6|libgcc_s\.so\.1)$' $TMPDIR/dyn >/dev/null || continue
      old=$(awk '$2 == "RUNPATH" { print $4 }' $TMPDIR/dyn)
      chmod u+w "$f"
      /usr/bin/elfedit -e "dyn:runpath ''${old:+$old:}${gccRuntime}" "$f"
    done
    popd >/dev/null
    runHook postInstall
  '';

  # the binaries as Tribblix built them, but for the RUNPATHs above
  dontFixup = true;

  # It runs as a JDK: java reports the version and javac compiles a program java runs. Every object resolves its
  # libraries (the gcc runtime from the stdenv compiler's) but for the ones above and libjvm.so, which the launcher
  # loads first.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/java -version 2>&1 | grep '"${finalAttrs.version}-internal"' >/dev/null
    mkdir ic && cd ic
    printf '%s\n' 'public class Hello { public static void main(String[] a) { System.out.println("hello " + (6 * 7)); } }' >Hello.java
    $out/bin/javac Hello.java
    $out/bin/java -cp . Hello | grep -x 'hello 42' >/dev/null
    bad=0
    for f in $(find $out/bin $out/lib -type f); do
      /usr/bin/elfdump -d "$f" >/dev/null 2>&1 || continue
      /usr/bin/ldd "$f" >ldd.out 2>&1 || true
      if [ "$f" = $out/lib/libsplashscreen.so ]; then
        sed -i '/^\s*libz\.so\.1 (SUNW_1\.3) =>\s*(version not found)$/d' ldd.out
      fi
      if grep 'not found' ldd.out | grep -vE '^\s*(libjvm\.so|libX[A-Za-z0-9]*\.so\.[0-9]+|libfreetype\.so\.6) ' >&2; then
        echo "unresolved in $f" >&2; bad=1
      fi
      if grep -E '(libstdc\+\+\.so\.6|libgcc_s\.so\.1) =>' ldd.out | grep -v '${gccRuntime}/' >&2; then
        echo "gcc runtime from outside the store in $f" >&2; bad=1
      fi
    done
    test $bad = 0
    runHook postInstallCheck
  '';

  passthru.home = finalAttrs.finalPackage;

  meta = {
    description = "OpenJDK 11 for illumos built by Tribblix, as a boot JDK";
    homepage = "https://pkgs.tribblix.org/openjdk/";
    license = with lib.licenses; [
      gpl2
      classpathException20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.platforms.illumos;
  };
})
