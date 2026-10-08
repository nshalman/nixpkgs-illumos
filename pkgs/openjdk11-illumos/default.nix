# OpenJDK 11 for illumos, built from source: nixpkgs' OpenJDK 11 recipe (generic.nix, which nixpkgs uses on Linux
# only, taking Azul's Zulu elsewhere; the same jdk11u tag and nixpkgs' own patches), with
# the illumos port that every illumos distribution builds it with, Peter Tribble's patch set
# (github.com/ptribble/jdk-sunos-patches: the Solaris port OpenJDK removed in JDK 15, kept building with gcc on
# illumos), applied in the order of its .pls list. jdk11u needs a boot JDK of version 10 or 11: Tribblix's build of it
# (../tribblix-jdk-bin).
#
# Headless (the nightly builds its Java components with javac and jar), like OmniOS's openjdk11, and with the font
# and image libraries jdk11u carries (freetype, harfbuzz, libjpeg, giflib, libpng, lcms) rather than nixpkgs' (whose
# harfbuzz alone brings glib, cairo and sphinx), as OmniOS builds it: zlib is the system's. Headless still takes:
# - X11: jdk11u's configure requires it on all but Windows and macOS ("libawt still needs X11 headers"), and on
#   Solaris libjawt links libXrender; nixpkgs' X11 libraries, as in nixpkgs' recipe;
# - CUPS and fontconfig headers: the JDK dlopen()s the libraries at run time (sun.print's CUPSfuncs.c, the font
#   manager's fontpath.c), so only their headers, from the sources of nixpkgs' versions (its cups does not evaluate for
#   illumos; its fontconfig brings a hundred derivations, the default fonts built with fontforge). fontconfig.h is
#   made from fontconfig.h.in as its configure does, with configure.ac's CACHE_VERSION.
# Where nixpkgs' recipe assumes Linux or gcc 15, it is changed here:
# - configure: Tribblix's build.sh (the gcc toolchain; no dtrace probes, whose generation this build does not set up;
#   no gtest), without --with-jvm-features=zgc (ZGC has no Solaris port in 11), and no debug symbols, since
#   nixpkgs' separate debug output is made with Linux tools;
# - NIX_CFLAGS_COMPILE without -std=gnu17, nixpkgs' fix for gcc 15 (whose C default is newer; gcc 14's is gnu17):
#   the wrapper passes it to C++ too, where g++ rejects it under -Werror, so every C++ flag configure probes fails
#   and hotspot loses -std=gnu++98, -fno-lifetime-dse and -fno-delete-null-pointer-checks;
# - jni_md.h is in include/solaris;
# - no autoPatchelf: the illumos link-editor records the RUNPATHs itself;
# - the launcher's Solaris -R$(OPENWIN_HOME)/lib/amd64, which with Tribblix's patches (no /usr/openwin) is
#   -R/lib/amd64, a directory the runtime linker searches anyway and nixpkgs' linker wrapper rejects as impure.
# And the stdenv compiler's sysroot (illumos 2021) has no audio headers, which libjsound includes (OmniOS builds with
# its system/header/header-audio): sys/audio.h, sys/audioio.h and sys/mixer.h from the illumos-gate commit ../illumos-ld
# is built from.
# What it records of when it was built is the stdenv's SOURCE_DATE_EPOCH: jdk11u's --with-source-date for what its
# makefiles date, and its jmods', jars' and zips' entries made so afterwards (normalizeZips, ../normalize-zips), as its
# jar and jmod tools take no time. The sources it generates (CharacterData) carry no date.
{
  lib,
  path,
  callPackage,
  fetchFromGitHub,
  fetchurl,
  tribblix-jdk-bin,
  runCommand,
  cpio,
  file,
  zlib,
  libx11,
  libxext,
  libxrender,
  libxtst,
  libxt,
  libxi,
  libxrandr,
  cups,
  fontconfig,
  illumos-ld,
  normalizeZips,
}:

let
  tribblixPatches = fetchFromGitHub {
    owner = "ptribble";
    repo = "jdk-sunos-patches";
    rev = "f7577be7e901958e4a0543d7c5706eaa3a41f45b";
    sha256 = "0lksn6bayli0ka740lb3kfyf4n6b2947dj0yzhczffp6zs1w5k51";
  };
  # the patch set for this jdk11u tag (jdk-11.0.32.1+1 is the commit of jdk-11.0.32.1-ga)
  patchSet = "jdk11u-jdk-11.0.32.1-ga";
  dlopenedHeaders = runCommand "openjdk-cups-fontconfig-headers" { } ''
    mkdir -p $out/include/cups $out/include/fontconfig
    tar xf ${cups.src}
    cp cups-*/cups/*.h $out/include/cups/
    tar xf ${fontconfig.src}
    cp fontconfig-*/fontconfig/*.h $out/include/fontconfig/
    v=$(sed -n 's/^CACHE_VERSION=//p' fontconfig-*/configure.ac)
    test -n "$v"
    sed "s/@CACHE_VERSION@/$v/" fontconfig-*/fontconfig/fontconfig.h.in >$out/include/fontconfig/fontconfig.h
    if grep @ $out/include/fontconfig/fontconfig.h; then exit 1; fi
  '';
  # OmniOS's patch for a headless-only build on illumos: libjawt links libawt_headless, and jdk11u stubs out its
  # calls into the X11 AWT (-DHEADLESS) on Linux only
  omniosHeadless = fetchurl {
    url = "https://raw.githubusercontent.com/omniosorg/omnios-build/89428e6eea3eb432cc8ec4d0fe88adc3fbc025f7/build/openjdk11/patches/omnios-headless.patch";
    sha256 = "10h9amifpbwgwq9kdx90y2c6fnnh4hylvkrn4nhvxf12wl90jxbr";
  };
  audioHeaders = runCommand "openjdk-illumos-audio-headers" { } ''
    mkdir -p $out/include/sys
    for h in audio audioio mixer; do
      cp ${illumos-ld.src}/usr/src/uts/common/sys/$h.h $out/include/sys/
    done
  '';
in
(callPackage "${path}/pkgs/development/compilers/openjdk/generic.nix" {
  featureVersion = "11";
  headless = true;
  jdk-bootstrap = tribblix-jdk-bin;
}).overrideAttrs
  (old: {
    pname = "openjdk-illumos-headless";

    postPatch = ''
      while read -r level patch; do
        echo "applying Tribblix's $patch"
        patch $level <${tribblixPatches}/jdk11/$patch
      done <${tribblixPatches}/jdk11/${patchSet}.pls
      patch -p1 <${omniosHeadless}
      substituteInPlace make/launcher/Launcher-java.base.gmk \
        --replace-fail 'LDFLAGS_solaris := -R$(OPENWIN_HOME)/lib$(OPENJDK_TARGET_CPU_ISADIR), \' \
                       'LDFLAGS_solaris := , \'
      # the sources the build generates (java.lang.CharacterData*) without the time they were generated, which goes
      # into src.zip
      substituteInPlace make/jdk/src/classes/build/tools/generatecharacter/GenerateCharacter.java \
        --replace-fail 'new java.util.Date() + commentEnd' 'commentEnd'
    ''
    + old.postPatch;

    # configure wants the file and cpio programs, which nixpkgs' recipe lists as buildInputs (file there for its
    # headful -lmagic)
    nativeBuildInputs = lib.filter (p: (p.name or "") != "auto-patchelf-hook") old.nativeBuildInputs ++ [
      cpio
      file
      normalizeZips
    ];

    buildInputs = [
      audioHeaders
      zlib
      libx11
      libxext
      libxrender
      libxtst
      libxt
      libxi
      libxrandr
    ];

    env = old.env // {
      NIX_CFLAGS_COMPILE = "-Wformat";
    };

    # the C++ flags configure probes reached the build's flags
    postConfigure = ''
      for f in -std=gnu++98 -fno-lifetime-dse -fno-delete-null-pointer-checks; do
        grep -e "$f" build/*/spec.gmk >/dev/null || { echo "configure dropped $f"; exit 1; }
      done
    '';

    # jdk11u's reproducible build: its makefiles take the time of the build from --with-source-date, here the
    # stdenv's SOURCE_DATE_EPOCH, where without it they export the time they run at (libjvm's "built on")
    preConfigure = old.preConfigure + ''
      configureFlags+=("--with-source-date=$SOURCE_DATE_EPOCH")
    '';

    configureFlags =
      lib.subtractLists [
        "--with-jvm-features=zgc"
        "--with-native-debug-symbols=internal"
        "--with-giflib=system"
        "--with-freetype=system"
        "--with-harfbuzz=system"
        "--with-libjpeg=system"
        "--with-libpng=system"
        "--with-lcms=system"
      ] old.configureFlags
      ++ [
        # the others' default is jdk11u's own copy; freetype's is the system's
        "--with-freetype=bundled"
        "--with-cups-include=${dlopenedHeaders}/include"
        "--with-fontconfig-include=${dlopenedHeaders}/include"
        "--with-native-debug-symbols=none"
        "--with-toolchain-type=gcc"
        "--disable-dtrace"
        "--disable-hotspot-gtest"
      ];

    separateDebugInfo = false;

    # nixpkgs' format hardening makes -Wformat-security an error, and the Solaris port has calls it rejects
    # (os_solaris.cpp: fatal(dlerror())); Tribblix builds it without that hardening
    hardeningDisable = (old.hardeningDisable or [ ]) ++ [ "format" ];

    # nixpkgs' installPhase runs no postInstall hooks, which normalizeZips is
    installPhase =
      lib.replaceStrings [ "$out/include/linux/" ] [ "$out/include/solaris/" ] old.installPhase
      + ''
        runHook postInstall
      '';

    postFixup = "";

    # It works as the nightly uses it: java reports this version, javac compiles a program java runs from the jar
    # made of it, and a JNI source compiles against include/ (jni.h includes jni_md.h).
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      $out/bin/java -version 2>&1 | grep '"${lib.head (lib.splitString "+" old.version)}"' >/dev/null
      mkdir ic && cd ic
      printf '%s\n' 'public class Hello { public static void main(String[] a) { System.out.println("hello " + (6 * 7)); } }' >Hello.java
      $out/bin/javac Hello.java
      $out/bin/jar cf hello.jar Hello.class
      $out/bin/java -cp hello.jar Hello | grep -x 'hello 42' >/dev/null
      printf '#include <jni.h>\nJNIEXPORT jint JNICALL f(JNIEnv *e) { return JNI_VERSION_10; }\n' >n.c
      $CC -I$out/include -c n.c
      runHook postInstallCheck
    '';

    meta = old.meta // {
      platforms = lib.platforms.illumos;
    };
  })
