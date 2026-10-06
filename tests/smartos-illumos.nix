# The SmartOS illumos build (pkgs/smartos-illumos) against what SmartOS itself ships:
#   runpath: no ELF object in the nightly's proto area names the store in its RUNPATH or RPATH, and gcc 10's
#            RUNPATH is illumos-extra's, /usr/gcc/10/lib (amd64 for 64-bit), as on the SmartOS platform (its
#            /usr/bin/ls).
#   idents:  every illumos ident (@(#)illumos joyent_<commit> <Month> <Year>, which the gate adds to each ELF file's
#            .comment) in the tools, msgcc and the nightly names the pinned commit's month (pins.json's date, as GNU
#            date gives it), not the month the build ran in.
#   log:     the nightly's logs, whose directory names carry the time of the build, are in its log output; its out
#            output, the one later stages use, has the proto area alone.
#   nix-build tests/smartos-illumos.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{ pkgs }:

let
  nightly = pkgs.smartos-illumos.nightly;
  pin = (import ../pins)."illumos-joyent";
in
{
  idents = pkgs.runCommand "smartos-illumos-idents" { } ''
    want="@(#)illumos joyent_${pin.rev} $(TZ=UTC LC_ALL=C date -d @${toString pin.date} '+%B %Y')"
    echo "want: $want"
    for p in ${pkgs.smartos-illumos.tools} ${pkgs.smartos-illumos.msgcc} ${nightly}; do
      grep -rhao '@(#)illumos joyent_[0-9a-z]* [A-Za-z]* [0-9]*' $p | sort | uniq -c | sed "s|^|$p: |"
    done >$TMPDIR/idents
    cat $TMPDIR/idents
    # each output has idents, and they are all the one wanted
    test "$(wc -l <$TMPDIR/idents)" = 3 || exit 1
    test "$(grep -cF " $want" $TMPDIR/idents)" = 3 || exit 1
    echo ok >$out
  '';

  log = pkgs.runCommand "smartos-illumos-nightly-log" { } ''
    ls -A ${nightly} >$TMPDIR/out
    cat $TMPDIR/out
    test "$(cat $TMPDIR/out)" = proto || exit 1
    test -s ${nightly.log or "no-log-output"}/latest/nightly.log || exit 1
    grep NIGHTLY_OPTIONS= ${nightly.log or "no-log-output"}/latest/nightly.log | head -1
    echo ok >$out
  '';

  runpath = pkgs.runCommand "smartos-illumos-nightly-runpath" { } ''
    cd ${nightly}/proto
    objects=0 store=0 gcc=0
    for f in $(find . -type f); do
      # ELF by its magic number: elfdump exits 0 on any file
      [ "$(od -An -tx1 -N4 "$f" | tr -d ' \n')" = 7f454c46 ] || continue
      /usr/bin/elfdump -d "$f" >$TMPDIR/dyn
      objects=$((objects + 1))
      rp=$(awk '$2 == "RUNPATH" { print $4 }' $TMPDIR/dyn)
      rpath=$(awk '$2 == "RPATH" { print $4 }' $TMPDIR/dyn)
      case "$rp $rpath" in
        *${builtins.storeDir}*) echo "store path in RUNPATH or RPATH: $f: $rp $rpath"; store=$((store + 1)) ;;
      esac
      case ":$rp:" in
        *:/usr/gcc/10/lib:*|*:/usr/gcc/10/lib/amd64:*) gcc=$((gcc + 1)) ;;
      esac
    done
    echo "$objects ELF objects, $gcc with gcc 10's RUNPATH, $store naming the store in RUNPATH or RPATH"
    test $objects -gt 0
    test $gcc -gt 0
    test $store = 0
    # the same RUNPATH as the platform's own ls
    test "$(/usr/bin/elfdump -d usr/bin/ls | awk '$2 == "RUNPATH" { print $4 }')" = /usr/gcc/10/lib
    echo ok >$out
  '';
}
