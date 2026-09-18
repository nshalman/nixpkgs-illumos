# Builds a C and a C++ program with the stdenv's wrapped toolchain, runs them, and checks what the link-editor
# wrote. The properties checked are the ones the sysroot design promises:
#   - nothing newer than the sysroot's libc is required (floor ILLUMOS_0.38),
#   - the sysroot never appears in RUNPATH, so libc comes from the running system,
#   - the interpreter is the running system's runtime linker.
#   nix-build tests/toolchain.nix --arg pkgs 'import ../bridge.nix { nixpkgs = ...; }'
{
  pkgs,
  floor ? 38,
}:

pkgs.stdenv.mkDerivation {
  name = "illumos-toolchain-test";
  dontUnpack = true;
  dontFixup = true;

  buildPhase = ''
    cat > hello.c <<'C'
    #include <stdio.h>
    #include <string.h>
    int main(void) { puts("hello from C"); return 0; }
    C
    cat > hello.cc <<'CXX'
    #include <iostream>
    #include <stdexcept>
    #include <string>
    #include <vector>
    int main() {
      std::vector<std::string> v{"throw", "and", "catch"};
      try { throw std::runtime_error(v.at(0) + " " + v.at(1) + " " + v.at(2)); }
      catch (const std::exception &e) { std::cout << "hello from C++: " << e.what() << std::endl; return 0; }
      return 1;
    }
    CXX
    $CC hello.c -o hello-c 2> c.err || { cat c.err; exit 1; }
    $CXX hello.cc -o hello-cxx 2> cxx.err || { cat cxx.err; exit 1; }
  '';

  doCheck = true;
  checkPhase = ''
    fail=0
    check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
    check "C compiles and links silently" '[ ! -s c.err ]'; cat c.err
    check "C++ compiles and links silently" '[ ! -s cxx.err ]'; cat cxx.err
    check "C runs" './hello-c | grep -q "hello from C"'
    check "C++ throw/catch runs" './hello-cxx | grep -q "throw and catch"'
    # The link-editor stamps its revision into .comment. It must be the stdenv's ld, reached through the wrappers,
    # and not one the compiler driver found on the build host.
    # `ld -V` prints its revision and then fails for want of input files.
    rev() { { "$@" -V 2>&1 || true; } | /usr/bin/egrep -o '5\.11-1\.[0-9]+' | head -1; }
    ldrev=$(rev ld)
    echo "stdenv ld revision: $ldrev; host /usr/bin/ld: $(rev /usr/bin/ld)"
    for p in hello-c hello-cxx; do
      echo "--- $p"; /usr/bin/elfdump -d $p | /usr/bin/egrep 'NEEDED|RUNPATH'; /usr/bin/pvs -r $p | sed 's/^/    /'
      check "$p: interpreter is the system runtime linker" '/usr/bin/elfdump -i $p | grep -q "/usr/lib/amd64/ld.so.1"'
      check "$p: linked by the stdenv's ld ($ldrev)" '/usr/bin/mcs -p $p | grep -q "$ldrev"'
      check "$p: no sysroot in RUNPATH" '! /usr/bin/elfdump -d $p | /usr/bin/egrep "RUNPATH|RPATH" | grep -q illumos-sysroot'
      check "$p: no libc interface above ILLUMOS_0.${toString floor}" \
        '! /usr/bin/pvs -r $p | /usr/bin/egrep -o "ILLUMOS_0\.[0-9]+" | awk -F. "\$2 > ${toString floor}" | grep -q .'
      check "$p: libc resolves to the running system" '/usr/bin/ldd $p | grep "libc\.so\.1" | grep -q "=>[[:space:]]*/lib/"'
    done
    check "C++ runtime resolves inside the store" '! /usr/bin/ldd hello-cxx | /usr/bin/egrep "libstdc|libgcc_s" | grep -v /nix/store/ | grep -q .'
    [ $fail -eq 0 ]
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp hello-c hello-cxx $out/bin/
  '';
}
