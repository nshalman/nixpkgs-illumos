# smartos-live's local stage (0-local-stamp): for each of projects/local/NAME, 0-subdir-NAME-stamp runs, in that
# directory, `gmake [-f Makefile.joyent] CTFMERGE=… CTFCONVERT=… MAX_JOBS=… DESTDIR=$(PROTO) world install` (with
# Makefile.joyent when the project has one).
#
# The projects' Makefiles find the rest of their tree by $(PWD): ../../../build.env, ../../../proto (the proto area,
# which they read headers and libraries from), ../../../proto.strap (the strap: CC), ../../illumos (illumos-joyent's
# source: kernel headers, mdb's, mapfiles). Here that tree is laid out around a writable copy of the project: build.env
# is the scope's, proto the illumos build's proto area (read only: DESTDIR, which they install into, is this
# package's output), proto.strap the strap, projects/illumos the nightly's illumos-joyent source.
{
  stdenv,
  buildEnv,
  illumosProto,
  strapProto,
  ctfconvert,
  smartos-illumos,
}:

{
  name,
  src,
  version,
  # more make variables, on the command line
  makeFlags ? [ ],
  ...
}@args:

let
  ctfBin = builtins.dirOf ctfconvert;
in
stdenv.mkDerivation (
  removeAttrs args [
    "name"
    "makeFlags"
  ]
  // {
    pname = "smartos-live-local-${name}";
    inherit version src;

    unpackPhase = ''
      runHook preUnpack
      mkdir -p live/projects/local
      cp -r ${src} live/projects/local/${name}
      chmod -R u+w live/projects/local/${name}
      cp ${buildEnv} live/build.env
      ln -s ${illumosProto} live/proto
      ln -s ${strapProto} live/proto.strap
      ln -s ${smartos-illumos.src} live/projects/illumos
      cd live/projects/local/${name}
      runHook postUnpack
    '';

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      f=Makefile
      [ ! -f Makefile.joyent ] || f=Makefile.joyent
      make -f $f CTFMERGE=${ctfBin}/ctfmerge CTFCONVERT=${ctfBin}/ctfconvert MAX_JOBS=$NIX_BUILD_CORES \
        DESTDIR=$out ${toString makeFlags} world install
      runHook postInstall
    '';

    # illumos ELF: leave it as the link-editor wrote it.
    dontFixup = true;
  }
)
