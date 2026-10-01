# smartos-live's manifest: `gmake manifest` at the top of their tree, which collects illumos', live's (src's, with the
# tests and examples its manifest target lists with git ls-files), man's, illumos-extra's (gcc 10's libstdc++ version
# put in) and each local project's manifest in manifest.d, then merges them (tools/build_manifest) and sorts them
# (tools/sorter, which warns of paths more than one lists; the later manifest, by name, wins) into manifest.gen and,
# from illumos' boot.manifest, boot.manifest.gen. Its targets only copy and read files: run as they are, in a tree laid
# out as theirs, with illumos-extra's stage taken as done (-o 0-extra-stamp: it only orders the targets).
#
# The tree: smartos-live as a git repository of its files (their targets run git ls-files; the Makefile's own
# `git submodule update --init deps/eng`, for engineering tools, fails as there is no such submodule and is not needed),
# build.env, projects/illumos (the nightly's illumos-joyent), and illumos-extra and the local projects as directories
# of links to their sources (their Makefiles find build.env by their own directory). Their Makefile sets PATH to
# /usr/bin:/usr/sbin:/sbin:/opt/local/bin, and they find git, gmake and python2.7 (sorter) in /opt/local/bin; here
# PATH is given on make's command line, with nixpkgs' git, make (as gmake) and python 2.7, then the host's /usr/bin
# (tools/build_manifest is #!/usr/bin/bash), /usr/sbin and /sbin.
{
  lib,
  stdenv,
  runCommand,
  gitMinimal,
  gnumake,
  python27,
  smartosLive,
  buildEnv,
  localSrc,
  smartos-illumos,
  smartos-strap,
}:

let
  gmake = runCommand "gmake" { } ''
    mkdir -p $out/bin
    ln -s ${gnumake}/bin/make $out/bin/gmake
  '';
  path = lib.makeBinPath [
    gmake
    gitMinimal
    python27
  ];
in
stdenv.mkDerivation {
  pname = "smartos-live-manifest";
  version = "0-unstable-2026-09-03";

  src = smartosLive;

  nativeBuildInputs = [
    gitMinimal
    gnumake
  ];

  # links to the files of directory SRC in a new directory DIR
  postPatch = ''
    linkFarm() {
      mkdir -p "$2"
      for f in "$1"/* "$1"/.[!.]*; do
        [ ! -e "$f" ] || ln -s "$f" "$2"/
      done
    }
    git init -q .
    git add -A -f .
    cp ${buildEnv} build.env
    ln -s ${smartos-illumos.src} projects/illumos
    linkFarm ${smartos-strap.illumosExtra} projects/illumos-extra
    ${lib.concatStrings (
      lib.mapAttrsToList (n: src: ''
        linkFarm ${src} projects/local/${n}
      '') localSrc
    )}
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    make PATH=${path}:/usr/bin:/usr/sbin:/sbin -o 0-extra-stamp manifest
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp manifest.gen boot.manifest.gen $out/
    runHook postInstall
  '';
}
