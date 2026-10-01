# rust-illumos-bin, rust-lang.org's Rust toolchain for illumos as nixpkgs' wrapper of its prebuilt toolchains installs
# it:
#   - rustc and cargo are 1.95.0, for x86_64-unknown-illumos;
#   - rustc, its driver library and cargo find every library they need: gcc's runtime (libgcc_s, libssp) in
#     gcc-illumos's lib output, not the running system's /usr/lib, and the system's (liblgrp, which the sysroot does
#     not have) on the running system;
#   - a program built by rustc (linked through the stdenv's cc) runs, and so does one cargo builds offline from a
#     package with a build script, through rust-illumos-bin.rustPlatform as packages build with it.
#   nix-build tests/rust-illumos-bin.nix --arg pkgs 'import /work/dev-pkgs.nix'
{ pkgs }:

let
  rust = pkgs.rust-illumos-bin;
  gccLib = pkgs.stdenv.cc.cc.lib;

  # a package with a build script that sets an environment variable the program prints
  hello = pkgs.runCommand "hello-rs-src" { } ''
    mkdir -p $out/src
    cat >$out/Cargo.toml <<'EOF'
    [package]
    name = "hello"
    version = "0.1.0"
    edition = "2021"
    EOF
    cat >$out/Cargo.lock <<'EOF'
    version = 4

    [[package]]
    name = "hello"
    version = "0.1.0"
    EOF
    cat >$out/build.rs <<'EOF'
    fn main() { println!("cargo:rustc-env=HELLO_FROM=build script"); }
    EOF
    cat >$out/src/main.rs <<'EOF'
    fn main() { println!("hello from cargo and the {}", env!("HELLO_FROM")); }
    EOF
  '';
  helloCargo = rust.rustPlatform.buildRustPackage {
    pname = "hello";
    version = "0.1.0";
    src = hello;
    cargoLock.lockFile = "${hello}/Cargo.lock";
    # see pkgs/rust-illumos-bin
    auditable = false;
  };
in
pkgs.runCommand "rust-illumos-bin-test" { nativeBuildInputs = [ pkgs.stdenv.cc ]; } ''
  fail=0
  check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

  check "rustc is 1.95.0" '${rust.rustc}/bin/rustc --version | grep "^rustc 1\.95\.0 " >/dev/null'
  check "for x86_64-unknown-illumos" '${rust.rustc}/bin/rustc -vV | grep -x "host: x86_64-unknown-illumos" >/dev/null'
  check "cargo is 1.95.0" '${rust.cargo}/bin/cargo --version | grep "^cargo 1\.95\.0 " >/dev/null'

  for o in ${rust.rustc-unwrapped}/bin/rustc ${rust.rustc-unwrapped}/lib/librustc_driver-*.so ${rust.cargo}/bin/.cargo-wrapped; do
    check "$(basename $o) finds every library it needs" '! /usr/bin/ldd $o | grep "not found" >/dev/null'
    check "$(basename $o) finds liblgrp on the running system" \
      '/usr/bin/ldd $o | grep -x "[[:space:]]*liblgrp.so.1 =>[[:space:]]*/usr/lib/64/liblgrp.so.1" >/dev/null'
    for l in libgcc_s.so.1 libssp.so.0; do
      check "$(basename $o) finds $l in gcc-illumos's lib" \
        '/usr/bin/ldd $o | grep -x "[[:space:]]*$l =>[[:space:]]*${gccLib}/lib/amd64/$l" >/dev/null'
    done
  done

  printf 'fn main() { println!("hello from rustc"); }\n' >hello.rs
  check "rustc builds a program" '${rust.rustc}/bin/rustc -O hello.rs -o hello'
  check "which runs" './hello | grep -x "hello from rustc" >/dev/null'
  check "a package cargo builds with a build script runs" \
    '${helloCargo}/bin/hello | grep -x "hello from cargo and the build script" >/dev/null'

  [ $fail -eq 0 ] && touch $out
''
