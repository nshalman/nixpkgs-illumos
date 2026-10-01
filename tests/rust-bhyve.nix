# rust-bhyve as pkgs/rust-bhyve builds it (its own test suite runs in its check phase):
#   - rshyve, firehyve and fhrun are installed, and rshyve says it is the pinned commit;
#   - each finds every library it needs; rshyve's libcrypto (the vTPM's libtpms links it) is nixpkgs' openssl's, not
#     the build host's platform libcrypto-smartos, whatever platform the build host runs;
#   - built against the illumos proto area as a platform binary is: every other library, libc and libdladm included,
#     comes from the running system: RUNPATH has nixpkgs' openssl's lib and gcc's runtime (its link spec's), and the
#     libgcc_s versions it needs are all the running platform's (so the platform's gcc runtime does in an image);
#   - rshyve has RDP (its default rdp feature, the branch's vmm_rdp).
#   nix-build tests/rust-bhyve.nix --arg pkgs 'import /work/dev-pkgs.nix'
{ pkgs }:

let
  rb = pkgs.rust-bhyve;
  pin = (import ../pins).rust-bhyve;
in
pkgs.runCommand "rust-bhyve-test" { } ''
  fail=0
  check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

  for b in rshyve firehyve fhrun; do
    check "$b is installed" '[ -x ${rb}/bin/$b ]'
    check "$b finds every library it needs" '! /usr/bin/ldd ${rb}/bin/$b | grep "not found" >/dev/null'
  done
  check "rshyve --version is 0.1.0 at the pinned commit" \
    '${rb}/bin/rshyve --version | grep -x "rshyve 0\.1\.0 (${pin.rev})" >/dev/null'
  check "rshyve's libcrypto is nixpkgs' openssl's" \
    '/usr/bin/ldd ${rb}/bin/rshyve | grep -x "[[:space:]]*libcrypto.so.3 =>[[:space:]]*${pkgs.lib.getLib pkgs.openssl}/lib/libcrypto.so.3" >/dev/null'
  check "and not the platform's" '! /usr/bin/ldd ${rb}/bin/rshyve | grep libcrypto-smartos >/dev/null'
  for b in rshyve firehyve fhrun; do
    # RUNPATH entries, one per line: each is nixpkgs' openssl's lib or gcc-illumos's runtime (its own link spec's -R),
    # none the proto's, illumos-extra's or the sysroot's
    /usr/bin/elfdump -d ${rb}/bin/$b | /usr/bin/awk '$2 == "RUNPATH" { print $4 }' | tr : '\n' >runpath-$b
    check "$b's RUNPATH has only nixpkgs' openssl's lib and gcc's runtime" \
      '! grep -v -x -e "${pkgs.lib.getLib pkgs.openssl}/lib" -e "${pkgs.stdenv.cc.cc.lib}/lib/amd64" runpath-$b >/dev/null'
    # in a platform image gcc's runtime is the platform's: every libgcc_s version it needs is one that has
    check "$b needs no libgcc_s version the running platform's lacks" \
      '/usr/bin/pvs -r ${rb}/bin/$b | /usr/bin/awk "/libgcc_s/ { gsub(/[(),;]/, \"\"); for (i = 2; i <= NF; i++) print \$i }" >need-$b &&
       [ -s need-$b ] && /usr/bin/pvs -d /usr/lib/64/libgcc_s.so.1 | tr -d " \t;" >have &&
       ! grep -v -x -F -f have need-$b >/dev/null'
  done
  check "rshyve takes libc and libdladm from the running system" \
    '/usr/bin/ldd ${rb}/bin/rshyve | grep -x "[[:space:]]*libdladm.so.1 =>[[:space:]]*/lib/64/libdladm.so.1" >/dev/null &&
     /usr/bin/ldd ${rb}/bin/rshyve | grep -x "[[:space:]]*libc.so.1 =>[[:space:]]*/lib/64/libc.so.1" >/dev/null'
  check "rshyve has RDP (vmm_rdp)" '/usr/bin/nm ${rb}/bin/rshyve | grep vmm_rdp >/dev/null'

  [ $fail -eq 0 ] && touch $out
''
