# What nixpkgs' fixup phase does to ELF files depends on patchelf being in the stdenv: RUNPATH shrinking, and the
# check for a build directory left in a RUNPATH (audit-tmpdir.sh), which fails open when patchelf is missing.
# Links a program with one RUNPATH entry it needs and one it does not, lets the default fixup run, then checks
# that the unneeded entry is gone and that the rewritten program still runs.
#   nix-build tests/fixup.nix --arg pkgs 'import ../bridge.nix { nixpkgs = ...; }'
{ pkgs }:

pkgs.stdenv.mkDerivation {
  name = "illumos-fixup-test";
  dontUnpack = true;
  buildInputs = [ pkgs.zlib ];

  buildPhase = ''
    cat > z.c <<'C'
    #include <stdio.h>
    #include <zlib.h>
    int main(void) { printf("zlib %s\n", zlibVersion()); return 0; }
    C
    $CC -o uses-zlib z.c -lz -Wl,-rpath,${pkgs.bzip2.out}/lib
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp uses-zlib $out/bin/
    /usr/bin/elfdump -d $out/bin/uses-zlib | grep -q '${pkgs.bzip2.out}/lib' || { echo "test is void: the extra RUNPATH entry was never there"; exit 1; }
  '';

  postFixup = ''
    fail=0
    check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
    check "patchelf is on PATH during fixup" 'command -v patchelf > /dev/null'
    check "unneeded RUNPATH entry removed" '! /usr/bin/elfdump -d $out/bin/uses-zlib | grep -q "${pkgs.bzip2.out}/lib"'
    check "needed RUNPATH entry kept" '/usr/bin/elfdump -d $out/bin/uses-zlib | grep RUNPATH | grep -q "${pkgs.zlib.out}/lib"'
    check "program still runs" '$out/bin/uses-zlib | grep -q "^zlib [0-9]"'
    check "elfdump still reads it without complaint" '[ -z "$(/usr/bin/elfdump -d -c $out/bin/uses-zlib 2>&1 > /dev/null)" ]'
    [ $fail -eq 0 ]
  '';
}
