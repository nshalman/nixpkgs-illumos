# gcc10-illumos, the compiler SmartOS builds illumos with, called directly the way illumos' build calls its compilers
# (not through the cc-wrapper):
#   programs:    it is gcc 10.4.0 configured with binutils-strap's gas; a C and a C++ (throw/catch) program build,
#                run, ask nothing newer of libc than the floor, and find libc on the running system and the C++
#                runtime in the store;
#   illumos-ld:  it builds real illumos-gate code: the link-editor (pkgs/illumos-ld, gate sources compiled with
#                the gate's own headers) with gcc 10 as $CC; that package's install check links a shared object
#                with the result.
#   nix-build tests/gcc10.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{
  pkgs,
  floor ? 38,
}:

let
  gcc10 = pkgs.gcc10-illumos;
in
{
  programs = pkgs.runCommand "gcc10-illumos-test" { } ''
    fail=0
    check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
    cc=${gcc10}/bin/gcc
    cxx=${gcc10}/bin/g++

    check "gcc reports 10.4.0" '$cc -dumpfullversion | grep -qx 10.4.0'
    check "configured with binutils-strap's gas" '$cc -v 2>&1 | grep -q -- "--with-as=${pkgs.binutils-strap}/bin/as"'
    check "the assembler it runs is gas 2.34" '$($cc -print-prog-name=as) --version | grep -q "GNU assembler (GNU Binutils) 2.34"'

    printf '#include <stdio.h>\nint main(void) { puts("hello from C"); return 0; }\n' >hello.c
    cat >hello.cc <<'CXX'
    #include <iostream>
    #include <stdexcept>
    int main() {
      try { throw std::runtime_error("throw and catch"); }
      catch (const std::exception &e) { std::cout << "hello from C++: " << e.what() << std::endl; return 0; }
      return 1;
    }
    CXX
    $cc -m64 -O2 -g hello.c -o hello-c 2>c.err || { cat c.err; exit 1; }
    $cxx -m64 -O2 -g hello.cc -o hello-cxx 2>cxx.err || { cat cxx.err; exit 1; }
    check "C compiles and links silently" '[ ! -s c.err ]'; cat c.err
    check "C++ compiles and links silently" '[ ! -s cxx.err ]'; cat cxx.err
    check "C runs" './hello-c | grep -q "hello from C"'
    check "C++ throw/catch runs" './hello-cxx | grep -q "throw and catch"'
    for p in hello-c hello-cxx; do
      echo "--- $p"; /usr/bin/elfdump -d $p | /usr/bin/egrep 'NEEDED|RUNPATH'
      check "$p: interpreter is the system runtime linker" '/usr/bin/elfdump -i $p | grep -q "/usr/lib/amd64/ld.so.1"'
      check "$p: no libc interface above ILLUMOS_0.${toString floor}" \
        '! /usr/bin/pvs -r $p | /usr/bin/egrep -o "ILLUMOS_0\.[0-9]+" | awk -F. "\$2 > ${toString floor}" | grep -q .'
      check "$p: libc resolves to the running system" '/usr/bin/ldd $p | grep "libc\.so\.1" | grep -q "=>[[:space:]]*/lib/"'
    done
    check "C++ runtime resolves inside gcc 10's lib output" \
      '/usr/bin/ldd hello-cxx | /usr/bin/egrep "libstdc|libgcc_s" | grep -q "${gcc10.lib}/"'
    [ $fail -eq 0 ]
    mkdir -p $out/bin; cp hello-c hello-cxx $out/bin/
  '';

  illumos-ld = pkgs.illumos-ld.overrideAttrs (old: {
    pname = "illumos-ld-built-by-gcc10";
    preBuild = (old.preBuild or "") + ''
      export CC=${gcc10}/bin/gcc
    '';
  });
}
