# illumos-joyent's tools stage (usr/src/tools: cw, the ctf tools, dmake, onbld's scripts, sgs, the svc tools, ...),
# built the way smartos-live's tools/build_illumos starts the illumos build: `bldenv illumos.sh` with MAKE naming a
# dmake from the build host, then `dmake install` in usr/src/tools (the Makefile's bldtools target). The output is
# the tools proto, $SRC/tools/proto/root_i386-nd, whose opt/onbld the nightly then builds with.
#
# The step itself (illumos.sh, bldenv, what comes from the build host) is ./bldenv.nix.
#
# Not done here: the rest of `dmake setup` (closed binaries, headers into the proto area), which belongs to the
# nightly.
{
  mkBldenvStep,
  smartos-strap,
}:

let
  proto = smartos-strap.proto;
in
mkBldenvStep {
  pname = "smartos-illumos-tools";
  description = "illumos-joyent's build tools (opt/onbld), built with SmartOS's proto.strap from this repo";
  dir = "usr/src/tools";
  command = "dmake install";

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r illumos/usr/src/tools/proto/root_*-nd/. $out/
    runHook postInstall
  '';

  # The tools the nightly uses are there and work: the dmake built here runs a makefile; cw compiles through the
  # strap gcc 10 (translating Sun-style flags); ctfconvert turns the object's DWARF into CTF, ctfdump shows the types,
  # and ctfmerge merges it into an object.
  installCheckPhase = ''
    runHook preInstallCheck
    b=$out/opt/onbld/bin
    for t in i386/cw i386/ctfconvert i386/ctfmerge i386/ctfdump i386/dmake i386/ndrgen nightly bldenv; do
      test -x $b/$t || { echo "missing $b/$t"; exit 1; }
    done
    mkdir ic && cd ic
    printf '%s\n' 'all := T = ok' 'all:' '	@echo $(T)' >Makefile
    $b/i386/dmake all | grep -x ok >/dev/null

    primary="gcc10,${proto}/usr/gcc/10/bin/gcc,gnu"
    $b/i386/cw --versions --primary $primary -- | grep "gcc (GCC) 10.4.0" >/dev/null
    printf 'struct strap_s { int a; long b; };\nstruct strap_s strap_v;\nint strap_f(struct strap_s *p) { return p->a; }\n' >t.c
    $b/i386/cw --primary $primary -- -std=gnu99 -m64 -xO2 -g -c t.c -o t.o
    $b/i386/ctfconvert -l test -o t.ctf.o t.o
    $b/i386/ctfdump t.ctf.o | tee ctf.txt | grep "struct strap_s (16 bytes)" >/dev/null
    grep "strap_f" ctf.txt >/dev/null
    cp t.ctf.o merged.o
    $b/i386/ctfmerge -l test -o merged.o t.ctf.o
    $b/i386/ctfdump merged.o | grep "struct strap_s (16 bytes)" >/dev/null
    runHook postInstallCheck
  '';
}
