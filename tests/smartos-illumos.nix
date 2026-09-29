# The SmartOS illumos build (pkgs/smartos-illumos) against what SmartOS itself ships:
#   runpath: no ELF object in the nightly's proto area names the store in its RUNPATH, and gcc 10's RUNPATH is
#            illumos-extra's, /usr/gcc/10/lib (amd64 for 64-bit), as on the SmartOS platform (its /usr/bin/ls).
#   nix-build tests/smartos-illumos.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{ pkgs }:

let
  nightly = pkgs.smartos-illumos.nightly;
in
{
  runpath = pkgs.runCommand "smartos-illumos-nightly-runpath" { } ''
    cd ${nightly}/proto
    objects=0 store=0 gcc=0
    for f in $(find . -type f); do
      # ELF by its magic number: elfdump exits 0 on any file
      [ "$(od -An -tx1 -N4 "$f" | tr -d ' \n')" = 7f454c46 ] || continue
      /usr/bin/elfdump -d "$f" >$TMPDIR/dyn
      objects=$((objects + 1))
      rp=$(awk '$2 == "RUNPATH" { print $4 }' $TMPDIR/dyn)
      case "$rp" in
        *${builtins.storeDir}*) echo "store path in RUNPATH: $f: $rp"; store=$((store + 1)) ;;
      esac
      case ":$rp:" in
        *:/usr/gcc/10/lib:*|*:/usr/gcc/10/lib/amd64:*) gcc=$((gcc + 1)) ;;
      esac
    done
    echo "$objects ELF objects, $gcc with gcc 10's RUNPATH, $store naming the store"
    test $objects -gt 0
    test $gcc -gt 0
    test $store = 0
    # the same RUNPATH as the platform's own ls
    test "$(/usr/bin/elfdump -d usr/bin/ls | awk '$2 == "RUNPATH" { print $4 }')" = /usr/gcc/10/lib
    echo ok >$out
  '';
}
