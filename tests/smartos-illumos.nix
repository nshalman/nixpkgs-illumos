# The SmartOS illumos build (pkgs/smartos-illumos) against what SmartOS itself ships:
#   runpath: no ELF object in the nightly's proto area names the store in its RUNPATH or RPATH, and gcc 10's
#            RUNPATH is illumos-extra's, /usr/gcc/10/lib (amd64 for 64-bit), as on the SmartOS platform (its
#            /usr/bin/ls).
#   idents:  every illumos ident (@(#)illumos joyent_<commit> <Month> <Year>, which the gate adds to each ELF file's
#            .comment) in the tools, msgcc and the nightly names the pinned commit's month (pins.json's date, as GNU
#            date gives it), not the month the build ran in.
#   log:     the nightly's logs, whose directory names carry the time of the build, are in its log output; its out
#            output, the one later stages use, has the proto area alone.
#   times:   what the build writes of when it ran is the pinned commit's time (SOURCE_DATE_EPOCH): .pyc files are checked
#            by their sources' hashes, not times; __TIME__ (libzdoor) is the commit's; every jar entry is dated then.
#   dofUarg: the nightly's libdtrace writes the same object for a D program each time dtrace -G runs, with address
#            space layout randomization on (pkgs/smartos-illumos/libdtrace-dof-uarg.patch): the build host's dtrace,
#            run five times on a ustack helper with that library in place of its own.
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

  dofUarg = pkgs.runCommand "smartos-illumos-dof-uarg" { } ''
    mkdir lib
    ln -s ${nightly}/proto/usr/lib/amd64/libdtrace.so.1 lib/libdtrace.so.1
    # the library loaded is the nightly's (/usr/sbin/dtrace is 64-bit)
    loaded=$(LD_LIBRARY_PATH_64=$PWD/lib /usr/bin/ldd /usr/sbin/dtrace | awk '$1 == "libdtrace.so.1" { print $3 }')
    echo "libdtrace.so.1 => $loaded"
    test "$loaded" = $PWD/lib/libdtrace.so.1
    printf 'dtrace:helper:ustack:\n{\n\t"@helped"\n}\n' >h.d
    for i in 1 2 3 4 5; do
      LD_LIBRARY_PATH_64=$PWD/lib /usr/bin/psecflags -s current,aslr -e /usr/sbin/dtrace -G -s h.d -o h.o
      cksum <h.o
    done >sums
    cat sums
    test "$(sort -u sums | wc -l)" = 1
    echo ok >$out
  '';

  times = pkgs.runCommand "smartos-illumos-times" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    # .pyc files: checked by a hash of their source (flags, bytes 4-7, not 0), not by its time
    n=0 bytime=0
    for f in $(find ${pkgs.smartos-illumos.tools} ${nightly}/proto -name '*.pyc'); do
      n=$((n + 1))
      if [ "$(od -An -tu4 -j4 -N4 "$f" | tr -d ' ')" = 0 ]; then echo "by its source's time: $f"; bytime=$((bytime + 1)); fi
    done
    echo "$n .pyc files, $bytime checked by their sources' times"
    test $n -gt 0
    test $bytime = 0
    # __TIME__ (libzdoor's messages): the commit's
    want=$(TZ=UTC date -d @${toString pin.date} +%T)
    grep -qaF "$want" ${nightly}/proto/lib/amd64/libzdoor.so.1 || { echo "libzdoor: no $want"; exit 1; }
    echo "libzdoor: $want"
    # jars: every entry at the commit's time (a DOS time: to 2 seconds)
    dos=$(TZ=UTC date -d @$(( ${toString pin.date} / 2 * 2 )) +%Y%m%d.%H%M%S)
    j=0
    for f in $(find ${nightly}/proto -name '*.jar'); do
      j=$((j + 1))
      if unzip -Z -T "$f" | grep '^[-dl]' | grep -v " $dos " | grep -q .; then echo "not all at $dos: $f"; exit 1; fi
    done
    echo "$j jars, every entry at $dos"
    test $j -gt 0
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
