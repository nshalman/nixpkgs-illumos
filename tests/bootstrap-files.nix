# Unpacks the two bootstrap files the way the stdenv will, at a store path of their own, and checks the result
# using nothing but the archive itself (raw derivations, no stdenv):
#   - every program starts,
#   - the relocated gcc compiles, links and runs C and C++ against illumos-libc,
#   - no file names a store path other than the archive, apart from what nix-support/unpatched admits to.
# Run through tests/bootstrap-files.sh, which computes the hashes.
{
  unpackUrl,
  unpackHash,
  toolsUrl,
  toolsHash,
  illumos-libc,
}:

let
  system = "x86_64-solaris";
  unpack = import <nix/fetchurl.nix> {
    url = unpackUrl;
    hash = unpackHash;
    name = "unpack";
    unpack = true;
  };
  bootstrapTools = import <nix/fetchurl.nix> {
    url = toolsUrl;
    hash = toolsHash;
  };
  archive = derivation {
    inherit system bootstrapTools;
    # Short, because store paths inside binaries are replaced by this one padded to their length.
    name = "boot";
    builder = "${unpack}/bin/bash";
    args = [ ../bootstrap/unpack-bootstrap-files.sh ];
    LD_LIBRARY_PATH_64 = "${unpack}/lib";
    src = unpack;
  };
in
derivation {
  inherit system archive;
  name = "bootstrap-archive-test";
  builder = "${archive}/bin/bash";
  libc = builtins.storePath illumos-libc;
  PATH = "${archive}/bin";
  args = [
    "-c"
    ''
      fail=0
      check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
      cd $NIX_BUILD_TOP

      n=0; bad=
      for b in $archive/bin/*; do
        [ -f "$b" ] && [ -x "$b" ] || continue
        n=$((n + 1))
        msg=$( ( "$b" --version < /dev/null || "$b" --help < /dev/null ) 2>&1 | head -3 )
        case "$msg" in *ld.so.1:*|*"Exec format"*|*"cannot execute"*|*"bad interpreter"*|*"env: "*) bad="$bad ''${b##*/}" ;; esac
      done
      check "all $n programs in bin/ start (failed:$bad)" '[ -z "$bad" ]'

      printf '#include <stdio.h>\nint main(void){puts("C ok");return 0;}\n' > h.c
      printf '#include <iostream>\n#include <stdexcept>\nint main(){try{throw std::runtime_error("C++ ok");}catch(const std::exception&e){std::cout<<e.what()<<std::endl;return 0;}return 1;}\n' > h.cc
      check "gcc compiles and links C"   'gcc --sysroot=$libc -o h-c h.c'
      check "C program runs"             '[ "$(./h-c)" = "C ok" ]'
      check "g++ compiles and links C++" 'g++ --sysroot=$libc -o h-cxx h.cc'
      check "C++ program runs (libstdc++ found through the rewritten spec)" '[ "$(./h-cxx)" = "C++ ok" ]'
      check "the link-editor gcc runs is the illumos one" '$(gcc -print-prog-name=ld) -V 2>&1 | grep -q "Solaris Link Editors"'
      check "so is ld on PATH" 'ld -V 2>&1 | grep -q "Solaris Link Editors"'

      foreign=$(find $archive -type f -exec grep -l -a '/nix/store/[a-z0-9]\{32\}-' {} + | while read -r f; do
        strings "$f" | grep -o '/nix/store/[a-z0-9]\{32\}-[^/ ":]*' | grep -vx "$archive" | grep -vxF -f $archive/nix-support/unpatched | sed "s|^|$f: |"; done | sort -u)
      echo "$foreign" | head -20
      check "no unadmitted foreign store path in any file" '[ -z "$foreign" ]'
      echo "admitted leftovers (too short to pad): $(sort -u $archive/nix-support/unpatched | wc -l)"
      sort -u $archive/nix-support/unpatched

      [ $fail -eq 0 ] && mkdir $out
    ''
  ];
}
