# gcc10-illumos, the compiler SmartOS builds illumos with, called directly the way illumos' build calls its compilers
# (not through the cc-wrapper):
#   programs:    it is gcc 10.4.0 configured with binutils-strap's gas, predefining the macros illumos-extra's gcc 10
#                predefines (compared with the reference proto.strap's); like illumos-extra's, what it compiles uses
#                the build host's headers and libc (a program using a libc function newer than the 2021 sysroot
#                builds and runs), while gcc 10 itself and its runtime libraries ask nothing newer of libc than the
#                floor; a C and a C++ (throw/catch) program build as 64-bit and as 32-bit programs, run, and find
#                libc on the running system and the C++ runtime in the store;
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

    # It predefines what illumos-extra's gcc 10 predefines, for 32- and 64-bit code. (The gate's standalone code
    # links without libc: libumem's standalone build fails on ___errno under -D_TS_ERRNO.)
    for m in -m32 -m64; do
      $cc $m -dM -E - </dev/null | sort >ours$m
      ${pkgs.smartos-strap.reference}/usr/gcc/10/bin/gcc $m -dM -E - </dev/null | sort >ref$m
      check "predefined macros ($m) are illumos-extra's gcc 10's" 'diff ref$m ours$m'
    done

    # What it compiles uses the build host's headers and libc, as illumos-extra's gcc 10 does: dprintf is declared
    # in the host's stdio.h and is in its libc (ILLUMOS_0.55), neither of which the 2021 sysroot has.
    printf '#include <stdio.h>\nint main(void) { dprintf(1, "hello from the host libc\\n"); return 0; }\n' >host.c
    check "a program using the build host's libc builds (dprintf)" '$cc -m64 -O2 -Werror=implicit-function-declaration host.c -o host 2>host.err || { cat host.err; false; }'
    check "and runs" './host | grep -x "hello from the host libc" >/dev/null'
    check "and asks the host's libc for ILLUMOS_0.55" '/usr/bin/pvs -r host | grep "ILLUMOS_0.55" >/dev/null'
    # gcc 10 itself is built against the sysroot: its runtime libraries and its compiler proper ask nothing newer of
    # libc than the floor
    for o in ${gcc10.lib}/lib/amd64/libstdc++.so.6 ${gcc10.lib}/lib/libstdc++.so.6 ${gcc10.lib}/lib/amd64/libgcc_s.so.1 \
             ${gcc10.lib}/lib/libgcc_s.so.1 $($cc -print-prog-name=cc1) $($cc -print-prog-name=cc1plus) $cc; do
      check "$(basename $o): no libc interface above ILLUMOS_0.${toString floor}" \
        '! /usr/bin/pvs -r $o | /usr/bin/egrep -o "ILLUMOS_0\.[0-9]+" | awk -F. "\$2 > ${toString floor}" | grep . >/dev/null'
    done

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
    # Both ABIs, as illumos-extra's gcc 10 builds for both (multilib: 32-bit runtime libraries in lib, 64-bit in
    # lib/amd64) and the strap libraries are built with -m32 and -m64.
    for bits in 64 32; do
      if [ $bits = 64 ]; then rtld=/usr/lib/amd64/ld.so.1 class=ELFCLASS64 libc=/lib/64/ rt=${gcc10.lib}/lib/amd64/
      else rtld=/usr/lib/ld.so.1 class=ELFCLASS32 libc=/lib/ rt=${gcc10.lib}/lib/; fi
      pc=hello-c$bits pcxx=hello-cxx$bits
      $cc -m$bits -O2 -g hello.c -o $pc 2>$pc.err || { cat $pc.err; fail=1; echo "FAIL $pc builds"; continue; }
      $cxx -m$bits -O2 -g hello.cc -o $pcxx 2>$pcxx.err || { cat $pcxx.err; fail=1; echo "FAIL $pcxx builds"; continue; }
      check "$pc compiles and links silently" '[ ! -s $pc.err ]'; cat $pc.err
      check "$pcxx compiles and links silently" '[ ! -s $pcxx.err ]'; cat $pcxx.err
      check "$pc runs" './$pc | grep >/dev/null "hello from C"'
      check "$pcxx throw/catch runs" './$pcxx | grep >/dev/null "throw and catch"'
      for p in $pc $pcxx; do
        echo "--- $p"; /usr/bin/elfdump -d $p | /usr/bin/egrep 'NEEDED|RUNPATH'; /usr/bin/ldd $p
        check "$p: $class" '/usr/bin/elfdump -e $p | grep >/dev/null "$class"'
        check "$p: interpreter is the system runtime linker" '/usr/bin/elfdump -i $p | grep >/dev/null "$rtld"'
        check "$p: no libc interface above ILLUMOS_0.${toString floor}" \
          '! /usr/bin/pvs -r $p | /usr/bin/egrep -o "ILLUMOS_0\.[0-9]+" | awk -F. "\$2 > ${toString floor}" | grep >/dev/null .'
        check "$p: libc resolves to the running system" \
          '/usr/bin/ldd $p | grep "libc\.so\.1" | grep >/dev/null "=>[[:space:]]*$libc"'
      done
      check "$pcxx: C++ runtime resolves inside gcc 10's lib output" \
        '[ "$(/usr/bin/ldd $pcxx | /usr/bin/egrep "libstdc\+\+\.so|libgcc_s\.so" | grep -c "=>[[:space:]]*$rt[^/]*$")" = 2 ]'
    done
    [ $fail -eq 0 ]
    mkdir -p $out/bin; cp hello-c64 hello-cxx64 hello-c32 hello-cxx32 $out/bin/
  '';

  illumos-ld = pkgs.illumos-ld.overrideAttrs (old: {
    pname = "illumos-ld-built-by-gcc10";
    preBuild = (old.preBuild or "") + ''
      export CC=${gcc10}/bin/gcc
    '';
  });
}
