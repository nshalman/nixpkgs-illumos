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

let
  # a header in the store whose inline function expands __FILE__, as Boost's and Nix's own headers do
  storeHeader = pkgs.writeTextDir "include/where-header.h" ''
    static inline const char *where_header(void) { return __FILE__; }
  '';
in
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
    cat > sig.c <<'C'
    #include <signal.h>
    #include <string.h>
    static void handler(int s) { (void)s; }
    int main(void) {
      struct sigaction sa;
      memset(&sa, 0, sizeof sa);
      sa.sa_handler = handler;
      if (sigaction(SIGUSR1, &sa, 0)) return 1;
      sa.sa_handler = SIG_IGN;
      if (sigaction(SIGUSR2, &sa, 0)) return 2;
      return signal(SIGPIPE, SIG_DFL) == SIG_ERR;
    }
    C
    # Both dialects: autoconf 2.73 configure scripts pick gnu23 by themselves.
    $CC -std=gnu17 sig.c -o sig-gnu17 2> sig17.err || { cat sig17.err; exit 1; }
    $CC -std=gnu23 sig.c -o sig-gnu23 2> sig23.err || { cat sig23.err; exit 1; }
    # Deliberately built without -pthread: that is how most libraries are built.
    printf '#include <errno.h>\nint set_errno(int v) { errno = v; return errno; }\n' > e.c
    $CC -shared -fPIC e.c -o libe.so 2> e.err || { cat e.err; exit 1; }
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
    # Builds are not sandboxed on illumos, so the build directory has a different name every time
    # (/nix/var/nix/builds/nix-PID-RANDOM). The stdenv maps it to a constant or no output is reproducible.
    printf 'const char *where(void) { return __FILE__; }\n' > $PWD/where.c
    $CC -g -c $PWD/where.c -o where.o
    check "neither __FILE__ nor debug info names the build directory" '! strings -a where.o | grep -q "$NIX_BUILD_TOP"'
    # __FILE__ of a header in the store would make that store path (often a -dev output) a runtime dependency of
    # whatever uses it. gcc mangles the hash to upper case, as nixpkgs' gcc does (mangle-NIX_STORE-in-__FILE__):
    # the cc-wrapper counts on that for GNU compilers.
    printf '#include <where-header.h>\nconst char *h(void) { return where_header(); }\n' > h.c
    $CC -I${storeHeader}/include -c h.c -o h.o
    hash=$(basename ${storeHeader} | cut -c1-32)
    check "__FILE__ of a store header does not name its store path" '! strings -a h.o | grep -q "$hash"'
    check "__FILE__ of a store header names it with the hash in upper case" \
      'strings -a h.o | grep -q "$(echo "$hash" | tr a-z A-Z)-where-header.h/include/where-header.h"'
    check "signal handlers and SIG_ constants work under gnu17 and gnu23" './sig-gnu17 && ./sig-gnu23 && [ ! -s sig17.err ] && [ ! -s sig23.err ]'
    # illumos only hands out the thread-safe errno under _REENTRANT, _TS_ERRNO or a POSIX feature macro. A library
    # that imports the plain `errno` object overwrites the main thread's errno from any thread.
    echo "libe.so imports: $(/usr/bin/elfdump -s -N .dynsym libe.so | awk '$NF=="errno" || $NF=="___errno" {print $NF}' | tr '\n' ' ')"
    check "a library built without -pthread uses the thread-safe errno" \
      '/usr/bin/elfdump -s -N .dynsym libe.so | awk "\$NF==\"___errno\"" | grep -q . && ! /usr/bin/elfdump -s -N .dynsym libe.so | awk "\$NF==\"errno\"" | grep -q .'
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
      check "$p: no sysroot or libc directory in RUNPATH" '! /usr/bin/elfdump -d $p | /usr/bin/egrep "RUNPATH|RPATH" | /usr/bin/egrep -q "illumos-(sysroot|libc)"'
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
