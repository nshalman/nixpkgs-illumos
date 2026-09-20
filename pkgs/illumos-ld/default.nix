# The illumos link-editor (ld, libld, liblddbg, and the libelf they use) built from a RECENT illumos-gate commit,
# but compiled and linked against the OLD sysroot. So it carries current bug fixes and still runs on any host at
# or above the floor.
#
# gate's own build system is not used: it needs Sun make (itself built by make), Makefile.master, cw, ...
# For this corner of the tree the makefiles reduce to five object lists, a second -D_ELF64 pass for the
# 64-bit ELF class, and sgsmsg invocations. See ./build.sh, which mirrors usr/src/cmd/sgs/*/Makefile.com.
{
  lib,
  stdenv,
  fetchFromGitHub,
  perl,
  gnum4,
  illumos-sysroot,
}:

stdenv.mkDerivation rec {
  pname = "illumos-ld";
  # Pinned per bootstrap-files release and bumped deliberately. Not master, not the sysroot's commit.
  gateRev = "7db575a44a2dd976e52d242cf394a2ba90efbe92";
  version = "0-unstable-2026-09-18";

  src = fetchFromGitHub {
    owner = "illumos";
    repo = "illumos-gate";
    rev = gateRev;
    sha256 = "00zx5xh8y3p4bxlazscllpx029i8wxx4qfky7l34jwh9zq1q0f70";
  };

  # The tree is >1 GB and only read from; build.sh uses $src in place.
  dontUnpack = true;
  dontConfigure = true;

  nativeBuildInputs = [
    perl
    gnum4
  ];

  # gate compiles these with its own flag set; nixpkgs hardening flags are not part of that.
  hardeningDisable = [ "all" ];

  sysroot = illumos-sysroot;

  buildPhase = ''
    runHook preBuild
    bash ${./build.sh}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib"
    cp build/out/bin/ld "$out/bin/"
    cp -P build/out/lib/* "$out/lib/"
    runHook postInstall
  '';

  # illumos ELF: leave it exactly as the link-editor wrote it. The RUNPATHs are $ORIGIN-relative on purpose.
  dontStrip = true;
  dontPatchELF = true;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/ld" -V
    echo 'int s4_answer(void) { return 42; }' > ic.c
    $CC -m64 -fPIC -c ic.c -o ic.o
    "$out/bin/ld" -G -o ic.so ic.o
    test -s ic.so
    # libld uses private libelf interfaces, so it must get the libelf built beside it, not the running system's.
    /usr/bin/ldd "$out/bin/ld" | grep "libelf\.so\.1" | grep -q "=>[[:space:]]*$out/" || { echo "ld does not load its own libelf"; /usr/bin/ldd "$out/bin/ld"; exit 1; }
    runHook postInstallCheck
  '';

  passthru = { inherit gateRev; };

  meta = {
    description = "illumos link-editor from a recent illumos-gate, linked against the sysroot ABI floor";
    homepage = "https://github.com/illumos/illumos-gate";
    license = lib.licenses.cddl;
    platforms = lib.platforms.illumos;
    mainProgram = "ld";
  };
}
