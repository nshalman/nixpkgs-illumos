# pkgs/openjdk11-illumos: the times of its build, and its archives in use:
#   times: what it records of when it was built is the stdenv's SOURCE_DATE_EPOCH (1980-01-01 00:00 UTC): the VM's
#          "built on" (libjvm.so: __DATE__ __TIME__), and every entry of its jmods, jars, src.zip and ct.sym; and
#          their entries are in order of name, as the order the file system gives differs between hosts.
#   use:   what reads those archives still does: jlink makes a runtime of java.base from its jmods, which runs a
#          class; javac --release 8 compiles against ct.sym; jar lists jrt-fs.jar and src.zip.
#   nix-build tests/openjdk11-illumos.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{ pkgs }:

let
  jdk = pkgs.openjdk11-illumos;
in
{
  times = pkgs.runCommand "openjdk11-illumos-times" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    cd ${jdk}/lib/openjdk
    # the stdenv's SOURCE_DATE_EPOCH, 315532800
    grep -aoh 'built on [A-Z][a-z][a-z] [ 0-9][0-9] [0-9]* [0-9:]*' lib/server/libjvm.so | sort -u | tee $TMPDIR/built
    test "$(cat $TMPDIR/built)" = "built on Jan  1 1980 00:00:00"
    n=0
    for f in $(find . -name '*.jmod' -o -name '*.jar' -o -name '*.zip' -o -name '*.sym'); do
      n=$((n + 1))
      # unzip lists a jmod too, past its 4-byte header (and says so, exiting 1)
      unzip -Z -T "$f" >$TMPDIR/list 2>/dev/null || true
      grep -q '^[-dl]' $TMPDIR/list || { echo "unzip lists nothing of $f"; exit 1; }
      if grep '^[-dl]' $TMPDIR/list | grep -v ' 19800101\.000000 ' | grep -q .; then echo "not all at 1980-01-01 00:00: $f"; exit 1; fi
      # in order of name, META-INF/ and its MANIFEST.MF first (where there are)
      unzip -Z1 "$f" 2>/dev/null | grep -v -x -e META-INF/ -e META-INF/MANIFEST.MF >$TMPDIR/names || true
      LC_ALL=C sort $TMPDIR/names | cmp -s - $TMPDIR/names || { echo "not in order of name: $f"; exit 1; }
    done
    echo "$n archives, every entry at 1980-01-01 00:00, in order of name"
    test $n -gt 70
    echo ok >$out
  '';

  use = pkgs.runCommand "openjdk11-illumos-use" { } ''
    cd $TMPDIR
    ${jdk}/bin/jlink --module-path ${jdk}/lib/openjdk/jmods --add-modules java.base --output rt
    printf 'public class Hello { public static void main(String[] a) { System.out.println("hello"); } }\n' >Hello.java
    ${jdk}/bin/javac --release 8 Hello.java
    test "$(rt/bin/java -cp . Hello)" = hello
    ${jdk}/bin/jar tf ${jdk}/lib/openjdk/lib/jrt-fs.jar | grep -q '^jdk/internal/jrtfs/'
    ${jdk}/bin/jar tf ${jdk}/lib/openjdk/lib/src.zip | grep -q '^java.base/java/lang/Object.java$'
    echo ok >$out
  '';
}
