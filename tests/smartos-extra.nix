# illumos-extra's platform packages (pkgs/smartos-extra), each against what SmartOS's own platform from the same
# illumos-extra commit ships of it (tests/strap-compare.sh with smartos-extra.platformReference as the reference,
# limited to the paths illumos-extra's manifest lists as files of the package; modes left out, since the platform
# takes them from the manifest), and used: a program built by the strap gcc against the package, run.
#   nix-build tests/smartos-extra.nix --arg pkgs 'import ./smartos.nix { }'
{ pkgs }:

let
  inherit (pkgs) lib;
  extra = pkgs.smartos-extra;
  inherit (pkgs.smartos-strap) gcc gcc10-illumos illumosExtra;

  # compare NAME PKG REGEX: PKG against the platform's files that illumos-extra's manifest lists and
  # REGEX matches. compareExpecting also takes the paths whose differences are expected (each caller says why);
  # compareWith takes more of strap-compare.sh's environment first.
  compareWith =
    env: name: pkg: regex: expected:
    pkgs.runCommand "smartos-extra-${name}-compare" { } ''
      # f entries only: smartos-live's builder copies those from the proto area and makes the manifest's symbolic
      # and hard links (s, h) itself (tools/builder/builder.c); $LIBSTDCXXVER is gcc 10's, as illumos-extra's
      # manifest target substitutes it
      sed 's/\$LIBSTDCXXVER/6.0.28/g' ${illumosExtra}/manifest | awk '$1 == "f" { print $2 }' |
        grep -E '${regex}' >list || true
      ${env} IGNORE_MODES=1 PATH_LIST=$PWD/list GCC_LIB=${gcc10-illumos.lib} GCC_OUT=${gcc10-illumos} \
        bash ${./strap-compare.sh} ${extra.platformReference} ${pkg} '${regex}' '${expected}' >report 2>&1 ||
        { cat report; exit 1; }
      cat report; cp report $out
    '';
  compareExpecting = compareWith "";
  compare = name: pkg: regex: compareExpecting name pkg regex "";

  # PROGRAM (C source) built against PKG and the illumos proto area for each word size in BITS with the given
  # libraries, run, and its output checked; a library it needs has to resolve into PKG.
  use =
    name: pkg: bits: libs: program: expect:
    pkgs.runCommand "smartos-extra-${name}-use" { } ''
      cat >t.c <<'C'
      ${program}
      C
      for bits in ${toString bits}; do
        if [ $bits = 32 ]; then l="-L${pkg}/usr/lib -R${pkg}/usr/lib"; else l="-L${pkg}/usr/lib/amd64 -R${pkg}/usr/lib/amd64"; fi
        ${gcc} -m$bits -I${pkg}/usr/include -isystem ${extra.illumosProto}/usr/include t.c -o t$bits $l ${libs}
        /usr/bin/ldd t$bits
        /usr/bin/ldd t$bits | grep "=>[[:space:]]*${pkg}/" >/dev/null ||
          { echo "FAIL $bits-bit: no library resolves into ${pkg}"; exit 1; }
        ./t$bits | tee out$bits
        grep -x '${expect}' out$bits >/dev/null || { echo "FAIL $bits-bit: expected '${expect}'"; exit 1; }
        echo "ok   $bits-bit program runs"
      done
      touch $out
    '';
in
{
  libz = compare "libz" extra.libz "^(usr/)?lib/(amd64/)?libz\\.";
  libz-use = use "libz" extra.libz [ 32 64 ] "-lz" ''
    #include <stdio.h>
    #include <string.h>
    #include <zlib.h>
    int main(void) {
      const char *in = "extra zlib extra zlib extra zlib";
      unsigned char z[128], back[128];
      uLongf zn = sizeof z, bn = sizeof back;
      if (compress(z, &zn, (const unsigned char *)in, strlen(in) + 1) != Z_OK) return 1;
      if (uncompress(back, &bn, z, zn) != Z_OK) return 2;
      printf("%s %s\n", zlibVersion(), strcmp((char *)back, in) == 0 ? "round trip" : "mismatch");
      return 0;
    }
  '' "1.3.1 round trip";

  # smartos-live's man/Makefile installs .so pages for the other names (its livesrc stage, after this one)
  bzip2 = compareExpecting "bzip2" extra.bzip2 "^usr/bin/(bz|bunzip2)|^usr/lib/(amd64/)?libbz2\\.|^usr/share/man/man1/bz"
    "^usr/share/man/man1/(bzcat|bzcmp|bzegrep|bzfgrep|bzip2recover|bzless)\\.1$";
  bzip2-use = pkgs.runCommand "smartos-extra-bzip2-run" { } ''
    b=${extra.bzip2}/usr/bin
    # the programs find libbz2 where the platform's do: not through a RUNPATH, on the system's library path
    seq 1 20000 >in
    LD_LIBRARY_PATH=${extra.bzip2}/usr/lib $b/bzip2 -c in >in.bz2
    LD_LIBRARY_PATH=${extra.bzip2}/usr/lib $b/bzcat in.bz2 | cmp - in
    echo "ok   bzip2 and bzcat round trip"
    touch $out
  '';

  libexpat = compare "libexpat" extra.libexpat "^usr/lib/(amd64/)?libexpat\\.";
  libexpat-use = use "libexpat" extra.libexpat [ 32 64 ] "-lexpat" ''
    #include <stdio.h>
    #include <expat.h>
    static int n;
    static void start(void *d, const XML_Char *el, const XML_Char **attr) { n++; }
    int main(void) {
      const char *doc = "<a><b/><c><d/></c></a>";
      XML_Parser p = XML_ParserCreate(NULL);
      XML_SetStartElementHandler(p, start);
      if (XML_Parse(p, doc, 22, 1) != XML_STATUS_OK) return 1;
      printf("%s %d elements\n", XML_ExpatVersion(), n);
      return 0;
    }
  '' "expat_2.8.2 4 elements";

  libidn = compare "libidn" extra.libidn "^usr/lib/libidn\\.";
  libidn-use = use "libidn" extra.libidn [ 32 ] "-lidn" ''
    #include <stdio.h>
    #include <stdlib.h>
    #include <idna.h>
    int main(void) {
      char *out;
      if (idna_to_ascii_8z("b\xc3\xbc" "cher.example", &out, 0) != IDNA_SUCCESS) return 1;
      printf("%s\n", out);
      free(out);
      return 0;
    }
  '' "xn--bcher-kva.example";

  xz = compare "xz" extra.xz "^usr/bin/xz$|^usr/lib/libjoy_lzma\\.|^usr/share/man/man1/xz\\.1$";
  xz-use = pkgs.runCommand "smartos-extra-xz-run" { } ''
    # libjoy_lzma.so.5, which xz needs, is a link the manifest makes
    mkdir lib && ln -s ${extra.xz}/usr/lib/libjoy_lzma.so.5.2.1 lib/libjoy_lzma.so.5
    seq 1 20000 >in
    LD_LIBRARY_PATH=$PWD/lib ${extra.xz}/usr/bin/xz -c in >in.xz
    LD_LIBRARY_PATH=$PWD/lib ${extra.xz}/usr/bin/xz -dc in.xz | cmp - in
    LD_LIBRARY_PATH=$PWD/lib /usr/bin/ldd ${extra.xz}/usr/bin/xz | grep "libjoy_lzma.so.5 =>.*$PWD/lib" >/dev/null
    echo "ok   xz round trip, with libjoy_lzma"
    touch $out
  '';

  libidn2 = compare "libidn2" extra.libidn2 "^usr/lib/libjoy_idn2\\.";
  libidn2-use = use "libidn2" extra.libidn2 [ 32 ] "-ljoy_idn2" ''
    #include <stdio.h>
    #include <idn2.h>
    int main(void) {
      char *out;
      if (idn2_to_ascii_8z("b\xc3\xbc" "cher.example", &out, 0) != IDN2_OK) return 1;
      printf("%s %s\n", idn2_check_version(NULL), out);
      idn2_free(out);
      return 0;
    }
  '' "2.3.4 xn--bcher-kva.example";

  openssl3 = compare "openssl3" extra.openssl3 "^lib/(amd64/)?lib(crypto|ssl)-smartos\\.|^usr/bin/openssl$|^etc/openssl/openssl\\.cnf$";
  openssl3-use = use "openssl3" extra.openssl3 [ 32 64 ] "-lcrypto-smartos" ''
    #include <stdio.h>
    #include <string.h>
    #include <openssl/evp.h>
    #include <openssl/crypto.h>
    int main(void) {
      unsigned char md[EVP_MAX_MD_SIZE];
      unsigned int n, i;
      if (!EVP_Digest("abc", 3, md, &n, EVP_sha256(), NULL)) return 1;
      printf("%s ", OpenSSL_version(OPENSSL_VERSION_STRING));
      for (i = 0; i < 4; i++) printf("%02x", md[i]);
      printf("\n");
      return 0;
    }
  '' "3.5.8 ba7816bf";

  bash = compare "bash" extra.bash "^usr/bin/bash$|^usr/share/man/man1/bash\\.1$";
  bash-use = pkgs.runCommand "smartos-extra-bash-run" { } ''
    ${extra.bash}/usr/bin/bash -c 'echo "$BASH_VERSION ''${BASH_VERSINFO[0]}"' | tee out
    grep -x '4.3.30(1)-release 4' out >/dev/null
    echo "ok   bash runs"
    touch $out
  '';

  less = compare "less" extra.less "^usr/bin/less(echo|key)?$|^usr/share/man/man1/less(echo|key)?\\.1$";
  less-use = pkgs.runCommand "smartos-extra-less-run" { } ''
    ${extra.less}/usr/bin/less --version | head -1 | tee out
    grep '^less 661 ' out >/dev/null
    seq 1 5 | ${extra.less}/usr/bin/less -F | tail -1 | grep -x 5 >/dev/null
    echo "ok   less runs"
    touch $out
  '';

  gtar = compare "gtar" extra.gtar "^usr/bin/gtar$";
  gtar-use = pkgs.runCommand "smartos-extra-gtar-run" { } ''
    mkdir d && echo gtar >d/f
    ${extra.gtar}/usr/bin/gtar cf t.tar d && rm -r d && ${extra.gtar}/usr/bin/gtar xf t.tar
    grep -x gtar d/f >/dev/null
    ${extra.gtar}/usr/bin/gtar --version | head -1 | grep -x 'tar (GNU tar) 1.23' >/dev/null
    echo "ok   gtar round trip"
    touch $out
  '';

  # smartos-live's man/Makefile installs .so pages for gzcat, gzcmp, gzegrep and gzfgrep (its livesrc stage)
  gzip = compareExpecting "gzip" extra.gzip "^usr/bin/(gz|gunzip)|^usr/share/man/man1/(gz|gunzip)"
    "^usr/share/man/man1/gz(cat|cmp|egrep|fgrep)\\.1$";
  gzip-use = pkgs.runCommand "smartos-extra-gzip-run" { } ''
    seq 1 20000 >in
    ${extra.gzip}/usr/bin/gunzip -c <in >/dev/null 2>&1 && exit 1
    # gzip and gzcat are hard links the manifest makes to gunzip, which picks its function from its name
    ln -s ${extra.gzip}/usr/bin/gunzip gzip
    ./gzip -c in >in.gz
    ${extra.gzip}/usr/bin/gunzip -c in.gz | cmp - in
    echo "ok   gzip round trip"
    touch $out
  '';

  coreutils = compare "coreutils" extra.coreutils "^usr/bin/(readlink|seq|stat)$|^usr/share/man/man1/(readlink|seq|stat)\\.1$";
  coreutils-use = pkgs.runCommand "smartos-extra-coreutils-run" { } ''
    b=${extra.coreutils}/usr/bin
    $b/seq 3 | tr '\n' ' ' | grep -x '1 2 3 ' >/dev/null
    ln -s target l && $b/readlink l | grep -x target >/dev/null
    $b/stat -c %s ${extra.coreutils}/usr/share/man/man1/seq.1 >/dev/null
    $b/seq --version | head -1 | grep -x 'seq (GNU coreutils) 9.7' >/dev/null
    echo "ok   readlink, seq and stat run"
    touch $out
  '';

  rsync = compare "rsync" extra.rsync "^usr/bin/rsync$|^usr/share/man/man1/rsync\\.1$";
  rsync-use = pkgs.runCommand "smartos-extra-rsync-run" { } ''
    mkdir a && seq 1 1000 >a/f
    ${extra.rsync}/usr/bin/rsync -a a/ b/
    cmp a/f b/f
    ${extra.rsync}/usr/bin/rsync --version | head -1 | grep '^rsync  version 3\.5\.0 ' >/dev/null
    echo "ok   rsync copies"
    touch $out
  '';

  uuid = compare "uuid" extra.uuid "^usr/bin/uuid$|^usr/share/man/man1/uuid\\.1$";
  uuid-use = pkgs.runCommand "smartos-extra-uuid-run" { } ''
    ${extra.uuid}/usr/bin/uuid -v4 | grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' >/dev/null
    echo "ok   uuid makes a version 4 UUID"
    touch $out
  '';

  socat = compare "socat" extra.socat "^usr/bin/socat$|^usr/share/man/man1/socat\\.1$";
  socat-use = pkgs.runCommand "smartos-extra-socat-run" { } ''
    echo socat | ${extra.socat}/usr/bin/socat - - | grep -x socat >/dev/null
    ${extra.socat}/usr/bin/socat -V | grep '^socat version 1\.7\.4\.1 ' >/dev/null
    echo "ok   socat copies stdin to stdout"
    touch $out
  '';

  gnupg = compare "gnupg" extra.gnupg "^usr/bin/gpg$|^usr/share/man/man1/gpg\\.1$";
  gnupg-use = pkgs.runCommand "smartos-extra-gnupg-run" { } ''
    export HOME=$PWD
    seq 1 2000 >in
    echo secret | ${extra.gnupg}/usr/bin/gpg --batch --passphrase-fd 0 -c -o in.gpg in
    echo secret | ${extra.gnupg}/usr/bin/gpg --batch --passphrase-fd 0 -d -o back in.gpg
    cmp in back
    ${extra.gnupg}/usr/bin/gpg --version | grep -x 'Compression: Uncompressed, ZIP, ZLIB, BZIP2' >/dev/null
    echo "ok   gpg encrypts and decrypts, with ZLIB and BZIP2"
    touch $out
  '';

  tun = compare "tun" extra.tun "^usr/kernel/drv/";
  # the drivers are loaded only on a platform; here, that they are kernel modules
  tun-use = pkgs.runCommand "smartos-extra-tun-check" { } ''
    for d in tun tap; do
      /usr/bin/elfdump -e ${extra.tun}/usr/kernel/drv/amd64/$d | grep 'e_type:.*ET_REL' >/dev/null
      /usr/bin/nm ${extra.tun}/usr/kernel/drv/amd64/$d | grep '_init$' >/dev/null
    done
    echo "ok   tun and tap are relocatable kernel modules with _init"
    touch $out
  '';

  screen = compare "screen" extra.screen "^usr/bin/screen$|^usr/share/man/man1/screen\\.1$";
  screen-use = pkgs.runCommand "smartos-extra-screen-run" { } ''
    ${extra.screen}/usr/bin/screen -v | grep '^Screen version 4\.09\.01 ' >/dev/null
    echo "ok   screen runs"
    touch $out
  '';

  dialog = compare "dialog" extra.dialog "^usr/bin/dialog$|^usr/share/man/man1/dialog\\.1$";
  dialog-use = pkgs.runCommand "smartos-extra-dialog-run" { } ''
    ${extra.dialog}/usr/bin/dialog --print-version 2>&1 | tee out
    grep 'Version: 1\.1-20111020' out >/dev/null
    echo "ok   dialog runs"
    touch $out
  '';

  # what the packages record of when they were built is the stdenv's SOURCE_DATE_EPOCH (1980-01-01): tun's version
  # string, gnupg's manuals' dates
  dates = pkgs.runCommand "smartos-extra-dates" { } ''
    for d in tun tap; do
      grep -aq 'TUN/TAP driver 1\.3\.0 01/01/1980' ${extra.tun}/usr/kernel/drv/amd64/$d ||
        { echo "FAIL $d: $(grep -ao 'TUN/TAP driver [^ ]* [^ ]*' ${extra.tun}/usr/kernel/drv/amd64/$d)"; exit 1; }
    done
    for m in gpg gpgv; do
      grep -q '^\.TH [A-Z]* 1 1980-01-01 ' ${extra.gnupg}/usr/share/man/man1/$m.1 ||
        { echo "FAIL $m.1: $(grep '^\.TH' ${extra.gnupg}/usr/share/man/man1/$m.1)"; exit 1; }
    done
    echo "ok   tun and tap 01/01/1980, gpg.1 and gpgv.1 1980-01-01"
    touch $out
  '';

  vim = compare "vim" extra.vim "^usr/bin/(vim|vimtutor|xxd)$|^usr/share/vim/|^usr/share/man/man1/(vim|vimdiff|vimtutor|xxd)\\.1$";
  vim-use = pkgs.runCommand "smartos-extra-vim-run" { } ''
    export HOME=$PWD
    printf 'one\ntwo\n' >f
    ${extra.vim}/usr/bin/vim -u NONE -es -c '%s/two/three/' -c 'wq' f
    grep -x three f >/dev/null
    ${extra.vim}/usr/bin/vim --version | head -1 | grep '^VIM - Vi IMproved 9\.2 ' >/dev/null
    echo abc | ${extra.vim}/usr/bin/xxd -p | grep -x 6162630a >/dev/null
    # its link line names no directory of the build host's (configure adds /usr/local/lib where the host has one:
    # only a host with one tells)
    if ${extra.vim}/usr/bin/vim --version | grep -e '-L/usr/local/lib'; then echo "FAIL vim links with the host's /usr/local/lib"; exit 1; fi
    # nor the build user (configure takes $USER for "Compiled by")
    if ${extra.vim}/usr/bin/vim --version | grep -i 'compiled by.*nixbld'; then echo "FAIL vim names its build user"; exit 1; fi
    echo "ok   vim edits, xxd dumps, links with nothing of the host's"
    touch $out
  '';

  pbzip2 = compare "pbzip2" extra.pbzip2 "^usr/bin/pbzip2$|^usr/share/man/man1/pbzip2\\.1$";
  pbzip2-use = pkgs.runCommand "smartos-extra-pbzip2-run" { } ''
    seq 1 50000 >in
    # libbz2 on the system's library path, as on the platform
    LD_LIBRARY_PATH=${extra.bzip2}/usr/lib ${extra.pbzip2}/usr/bin/pbzip2 -c <in >in.bz2
    LD_LIBRARY_PATH=${extra.bzip2}/usr/lib ${extra.bzip2}/usr/bin/bzcat in.bz2 | cmp - in
    echo "ok   pbzip2 compresses, bzcat decompresses"
    touch $out
  '';

  ncurses = compare "ncurses" extra.ncurses "^usr/bin/g(infocmp|tic|toe|tput|tset)$|^usr/gnu/";
  ncurses-use = pkgs.runCommand "smartos-extra-ncurses-run" { } ''
    n=${extra.ncurses}
    # RUNPATH /usr/gnu/lib names the build host's ncurses: this package's comes first on LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=$n/usr/gnu/lib TERMINFO=$n/usr/gnu/share/terminfo
    /usr/bin/ldd $n/usr/bin/gtput | grep "libncurses.so.5 =>.*$n/" >/dev/null
    test "$($n/usr/bin/gtput -T vt100 lines)" = 24
    $n/usr/bin/ginfocmp -V | grep '^ncurses 5\.7' >/dev/null
    echo "ok   gtput and ginfocmp run with this ncurses and its terminfo"
    touch $out
  '';

  libxml = compare "libxml" extra.libxml "^lib/(amd64/)?libxml2\\.|^usr/bin/xml(lint|catalog)$|^usr/share/man/man1/xml(lint|catalog)\\.1$";
  libxml-use = use "libxml" extra.libxml [ 32 64 ] "-I${extra.libxml}/usr/include/libxml2 -lxml2" ''
    #include <stdio.h>
    #include <libxml/parser.h>
    #include <libxml/tree.h>
    int main(void) {
      const char *doc = "<a><b>extra</b></a>";
      xmlDocPtr d = xmlReadMemory(doc, 19, "t.xml", NULL, 0);
      if (d == NULL) return 1;
      xmlChar *s = xmlNodeGetContent(xmlDocGetRootElement(d));
      printf("%s %s\n", LIBXML_DOTTED_VERSION, s);
      return 0;
    }
  '' "2.13.8 extra";

  cpp = compare "cpp" extra.cpp "^usr/lib/cpp$";
  cpp-use = pkgs.runCommand "smartos-extra-cpp-run" { } ''
    printf '#define X 42\nX\n' | ${extra.cpp}/usr/lib/cpp | grep -x 42 >/dev/null
    echo "ok   cpp expands a macro"
    touch $out
  '';

  # Their runtime libraries' RPATH is their build's proto.strap/usr/gcc/10/lib, ours RUNPATH and RPATH
  # /usr/gcc/10/lib (see pkgs/smartos-extra/gcc10.nix): search paths are left out of this comparison, and gcc10-use
  # states ours.
  gcc10 = compareWith "IGNORE_RUNPATHS=1" "gcc10" extra.gcc10 "^usr/lib/(amd64/)?lib(gcc_s|stdc\\+\\+|ssp)\\.so" "";
  gcc10-use = pkgs.runCommand "smartos-extra-gcc10-check" { } ''
    for f in ${extra.gcc10}/usr/lib/libstdc++.so.6.0.28 ${extra.gcc10}/usr/lib/amd64/libstdc++.so.6.0.28; do
      /usr/bin/elfdump -d $f | awk '$2 == "RUNPATH" || $2 == "RPATH" { print $2, $4 }' | tee paths
      case $f in
        */amd64/*) d=/usr/gcc/10/lib/amd64 ;;
        *) d=/usr/gcc/10/lib ;;
      esac
      test "$(cat paths)" = "RUNPATH $d
    RPATH $d"
    done
    echo "ok   libstdc++'s RUNPATH and RPATH are /usr/gcc/10/lib (amd64 for 64-bit)"
    touch $out
  '';

  openssl1x = compare "openssl1x" extra.openssl1x "^lib/(amd64/)?libsunw_(crypto|ssl)\\.so\\.1\\.0\\.0$";
  openssl1x-use = use "openssl1x" extra.openssl1x [ 32 64 ] "-I${extra.openssl1x}/opt/1x -lsunw1x_crypto" ''
    #include <stdio.h>
    #include <openssl/evp.h>
    #include <openssl/crypto.h>
    int main(void) {
      unsigned char md[EVP_MAX_MD_SIZE];
      unsigned int n, i;
      if (!EVP_Digest("abc", 3, md, &n, EVP_sha256(), NULL)) return 1;
      printf("%s ", SSLeay_version(SSLEAY_VERSION));
      for (i = 0; i < 4; i++) printf("%02x", md[i]);
      printf("\n");
      return 0;
    }
  '' "OpenSSL 1.0.2u  20 Dec 2019 ba7816bf";

  nss-nspr = compare "nss-nspr" extra.nss-nspr "^usr/lib/mps/|^usr/bin/certutil$|^usr/share/man/man1/certutil\\.1$";
  # certutil (32-bit, the one the platform ships) makes a new database and lists it: NSPR, NSS, softoken and sqlite
  # at work, from this package (its RUNPATH names the build host's /usr/lib/mps)
  nss-nspr-use = pkgs.runCommand "smartos-extra-nss-nspr-run" { } ''
    c=${extra.nss-nspr}/usr/bin/certutil
    export LD_LIBRARY_PATH=${extra.nss-nspr}/usr/lib/mps
    /usr/bin/ldd $c | tee ldd
    grep "libnss3.so =>.*${extra.nss-nspr}/" ldd >/dev/null
    mkdir db
    $c -N -d sql:db --empty-password
    $c -L -d sql:db | tee out
    grep "Certificate Nickname" out >/dev/null
    echo "ok   certutil makes and lists a database"
    touch $out
  '';

  # Expected: NTP/Util.pm is ntp's, installed into this tree by that later package; Config.pm records the compiler's
  # path, a build location (theirs their strap's usr/bin/gcc, ours gcc's store path mapped to /usr/gcc/10).
  perl = compareExpecting "perl" extra.perl "^usr/perl5/"
    "^usr/perl5/5\\.12/lib/NTP/Util\\.pm$|^usr/perl5/5\\.12/lib/i86pc-solaris-64int/Config\\.pm$";
  # Its @INC is the platform's /usr/perl5/5.12 (the build host has one too): this package's lib directories are put
  # first, and an XS module (POSIX) has to load from them
  perl-use = pkgs.runCommand "smartos-extra-perl-run" { } ''
    l=${extra.perl}/usr/perl5/5.12/lib
    ${extra.perl}/usr/perl5/5.12/bin/perl -I$l/i86pc-solaris-64int -I$l -MConfig -MPOSIX -e \
      'print join(" ", $Config{version}, $Config{installprefix}, $INC{"POSIX.pm"}, POSIX::floor(2.5)), "\n"' | tee out
    grep -x "5.12.3 /usr/perl5/5.12 $l/i86pc-solaris-64int/POSIX.pm 2" out >/dev/null
    echo "ok   perl 5.12.3, configured for /usr/perl5/5.12, loads POSIX from this package"
    touch $out
  '';

  node = compare "node" extra.node "^usr/node/";
  # node runs with this scope's OpenSSL 1.0.2 and zlib, found through LD_LIBRARY_PATH as the platform finds them in
  # /lib; python 2.7 was only for building it
  node-use = pkgs.runCommand "smartos-extra-node-run" { exportReferencesGraph = [ "closure" extra.node ]; } ''
    n=${extra.node}/usr/node/0.10/bin/node
    export LD_LIBRARY_PATH=${extra.openssl1x}/lib:${extra.libz}/lib
    /usr/bin/ldd $n | tee ldd
    grep "libsunw_crypto.so.1.0.0 =>.*${extra.openssl1x}/" ldd >/dev/null
    $n -e 'var h = require("crypto").createHash("sha256").update("abc").digest("hex").slice(0, 8);
      console.log([process.version, process.versions.openssl, process.versions.zlib, h].join(" "));' | tee out
    grep -x 'v0.10.26 1.0.2u 1.3.1 ba7816bf' out >/dev/null
    echo "ok   node 0.10.26 hashes with OpenSSL 1.0.2u and has zlib 1.3.1"
    if grep -e '-python-' closure; then echo "FAIL python is in node's closure"; exit 1; fi
    echo "ok   python is not in node's closure"
    touch $out
  '';

  curl = compare "curl" extra.curl "^usr/lib/libcurl\\.|^usr/bin/curl$|^usr/share/man/man1/curl\\.1$";
  # curl with this scope's libcurl, OpenSSL 3, zlib and libidn2 (on LD_LIBRARY_PATH, as the platform finds them in
  # /lib and /usr/lib): its version line names them, and it fetches a file: URL
  curl-use = pkgs.runCommand "smartos-extra-curl-run" { } ''
    export LD_LIBRARY_PATH=${extra.curl}/usr/lib:${extra.openssl3}/lib:${extra.libz}/lib:${extra.libidn2}/usr/lib
    c=${extra.curl}/usr/bin/curl
    /usr/bin/ldd $c | tee ldd
    grep "libcurl.so.4 =>.*${extra.curl}/" ldd >/dev/null
    $c --version | head -1 | tee out
    grep "^curl 8\\.22\\.0 .* OpenSSL/3\\.5\\.8 zlib/1\\.3\\.1 libidn2/2\\.3\\.4" out >/dev/null
    echo hello >f
    $c -s file://$PWD/f | grep -x hello >/dev/null
    echo "ok   curl 8.22.0 with OpenSSL 3.5.8, zlib and libidn2 fetches a file: URL"
    touch $out
  '';

  # wget.1 is made by pod2man: theirs Pod::Man 5.01 (pkgsrc's perl), ours v6.0.2 (nixpkgs' perl), which adds a groff
  # note and escapes hyphens
  wget = compareExpecting "wget" extra.wget "^usr/bin/wget$|^usr/share/man/man1/wget\\.1$"
    "^usr/share/man/man1/wget\\.1$";
  # wget with this scope's OpenSSL and zlib: its features, and CTF in the program, as the platform's has
  wget-use = pkgs.runCommand "smartos-extra-wget-run" { } ''
    w=${extra.wget}/usr/bin/wget
    export LD_LIBRARY_PATH=${extra.openssl3}/lib:${extra.libz}/lib
    /usr/bin/ldd $w | tee ldd
    grep "libssl-smartos.so.3 =>.*${extra.openssl3}/" ldd >/dev/null
    $w --version | head -3 | tee out
    grep "^GNU Wget 1\\.25\\.0 " out >/dev/null
    grep -- "+https" out >/dev/null
    /usr/bin/elfdump -c $w | grep "sh_name: \\.SUNW_ctf$" >/dev/null
    echo "ok   wget 1.25.0 with https, and CTF"
    touch $out
  '';

  bind = compare "bind" extra.bind "^usr/sbin/(dig|host|nslookup)$|^usr/share/man/man1/(dig|host|nslookup)\\.1$";
  bind-use = pkgs.runCommand "smartos-extra-bind-run" { } ''
    ${extra.bind}/usr/sbin/dig -v 2>&1 | tee out
    grep -x "DiG 9\\.10\\.1-P1" out >/dev/null
    echo "ok   dig 9.10.1-P1 runs"
    touch $out
  '';

  ipmitool = compare "ipmitool" extra.ipmitool "^usr/sbin/ipmitool$|^usr/share/man/man1/ipmitool\\.1$";
  # ipmitool with this scope's OpenSSL (lanplus): its version, and the libcrypto it links
  ipmitool-use = pkgs.runCommand "smartos-extra-ipmitool-run" { } ''
    i=${extra.ipmitool}/usr/sbin/ipmitool
    export LD_LIBRARY_PATH=${extra.openssl3}/lib
    /usr/bin/ldd $i | grep "libcrypto-smartos.so.3 =>.*${extra.openssl3}/" >/dev/null
    $i -V | tee out
    grep -x "ipmitool version 1\\.8\\.18" out >/dev/null
    echo "ok   ipmitool 1.8.18 runs, with libcrypto"
    touch $out
  '';

  rsyslog = compare "rsyslog" extra.rsyslog
    "^usr/sbin/rsyslogd$|^usr/lib/rsyslog/|^etc/rsyslog\\.conf$|^usr/share/man/man[58]/rsyslog";
  rsyslog-use = pkgs.runCommand "smartos-extra-rsyslog-run" { } ''
    ${extra.rsyslog}/usr/sbin/rsyslogd -v | head -1 | tee out
    grep "^rsyslogd 5\\.8\\.9" out >/dev/null
    echo "ok   rsyslogd 5.8.9 runs"
    touch $out
  '';

  openldap = compare "openldap" extra.openldap "^usr/openldap/|^etc/openldap/";
  openldap-use = pkgs.runCommand "smartos-extra-openldap-run" { } ''
    # RUNPATH /usr/openldap/lib names the build host's: this package's and OpenSSL's first
    export LD_LIBRARY_PATH=${extra.openldap}/usr/openldap/lib:${extra.openssl3}/lib
    ${extra.openldap}/usr/openldap/bin/ldapsearch -VV 2>&1 | tee out || true
    grep "ldapsearch 2\\.5\\.14" out >/dev/null
    echo "ok   ldapsearch 2.5.14 runs"
    touch $out
  '';

  openlldp = compare "openlldp" extra.openlldp "^usr/sbin/lldp|^lib/svc/manifest/network/lldpd\\.xml$";
  # the daemon needs datalinks; here, CTF in both programs, as the platform's have
  openlldp-use = pkgs.runCommand "smartos-extra-openlldp-check" { } ''
    for p in lldpd lldpneighbors; do
      /usr/bin/elfdump -c ${extra.openlldp}/usr/sbin/$p | grep "sh_name: \\.SUNW_ctf$" >/dev/null
    done
    echo "ok   lldpd and lldpneighbors have CTF"
    touch $out
  '';

  # NTP/Util.pm is listed under perl in the manifest; ntp installs it
  ntp = compare "ntp" extra.ntp
    "^usr/sbin/ntp|^lib/svc/(manifest/network/ntp\\.xml|method/ntp)$|^etc/security/(auth|prof)_attr\\.d/ntp$|^usr/share/man/man[18]/ntp|^usr/perl5/5\\.12/lib/NTP/";
  ntp-use = pkgs.runCommand "smartos-extra-ntp-run" { } ''
    export LD_LIBRARY_PATH=${extra.openssl3}/lib
    ${extra.ntp}/usr/sbin/ntpq --help >help 2>&1 || true
    head -1 help | tee out
    grep "Ver\\. 4\\.2\\.8p15$" out >/dev/null
    /usr/bin/elfdump -c ${extra.ntp}/usr/sbin/ntpd | grep "sh_name: \\.SUNW_ctf$" >/dev/null
    echo "ok   ntpq 4.2.8p15 runs; ntpd has CTF"
    touch $out
  '';

  # etc/ssh/sshd_config on the platform is smartos-live's own (src/etc/ssh/sshd_config, a later stage), installed over
  # openssh's
  openssh = compareExpecting "openssh" extra.openssh (
    "^usr/bin/(ssh|scp|sftp)|^usr/lib/ssh/|^usr/share/man/man[158]/(ssh|scp|sftp|moduli)|^usr/lib/dtrace/sftp\\.d$"
    + "|^etc/ssh/|^lib/svc/(method/sshd|manifest/network/ssh\\.xml)$|^usr/share/lib/ssh/moduli$"
  ) "^etc/ssh/sshd_config$";
  # ssh with this scope's OpenSSL and zlib: its version names both, and sshd has CTF
  openssh-use = pkgs.runCommand "smartos-extra-openssh-run" { } ''
    export LD_LIBRARY_PATH=${extra.openssl3}/lib:${extra.libz}/lib
    ${extra.openssh}/usr/bin/ssh -V 2>&1 | tee out
    grep "^OpenSSH_10\\.5p1, OpenSSL 3\\.5\\.8 " out >/dev/null
    /usr/bin/elfdump -c ${extra.openssh}/usr/lib/ssh/sshd | grep "sh_name: \\.SUNW_ctf$" >/dev/null
    echo "ok   ssh 10.5p1 with OpenSSL 3.5.8; sshd has CTF"
    touch $out
  '';

  mdb_v8 = compare "mdb_v8" extra.mdb_v8 "^usr/lib/mdb/proc/(amd64/)?v8\\.so$";
  # the dmods: CTF, mdb's module entry point, and the version tag the release target builds with git (theirs:
  # "release, from cbec173"), for both word sizes
  mdb_v8-use = pkgs.runCommand "smartos-extra-mdb_v8-check" { } ''
    for d in ${extra.mdb_v8}/usr/lib/mdb/proc/v8.so ${extra.mdb_v8}/usr/lib/mdb/proc/amd64/v8.so; do
      /usr/bin/elfdump -c $d | grep "sh_name: \\.SUNW_ctf$" >/dev/null
      /usr/bin/nm $d | grep "_mdb_init$" >/dev/null
      /usr/bin/strings -a $d | grep -x "release, from cbec173" >/dev/null
    done
    echo "ok   both v8.so have CTF, _mdb_init and the release tag"
    touch $out
  '';

  # No file the platform takes from a package (the manifest's f entries) names the store. In a text file (a script,
  # configuration) such a path would be dead on the platform. In a binary it is a build location, of the kind the
  # platform's binaries carry for their build too (debug information's include directories, vim's embedded compile
  # commands, the output file name the link-editor records); the scope maps those away (mapStorePaths in
  # pkgs/smartos-extra), and with that turned off this test fails on them.
  no-store-paths =
    let
      packages = lib.filter (d: lib.isDerivation d && lib.hasPrefix "smartos-extra-" d.name) (lib.attrValues extra);
    in
    pkgs.runCommand "smartos-extra-no-store-paths" { } ''
      sed 's/\$LIBSTDCXXVER/6.0.28/g' ${illumosExtra}/manifest | awk '$1 == "f" { print $2 }' >list
      found=0 binaries=0 checked=0
      for pkg in ${lib.concatMapStringsSep " " toString packages}; do
        while IFS= read -r p; do
          [ -f "$pkg/$p" ] || continue
          checked=$((checked + 1))
          grep -a ${builtins.storeDir}/ "$pkg/$p" >/dev/null || continue
          if grep -I -q . "$pkg/$p" 2>/dev/null; then
            echo "FAIL store path in a text file: $pkg/$p"; grep -o "${builtins.storeDir}/[a-z0-9]*-[^/ :]*" "$pkg/$p" | sort -u
            found=$((found + 1))
          else
            echo "FAIL store path in a binary: $pkg/$p"; /usr/bin/strings -a "$pkg/$p" | grep -o "${builtins.storeDir}/[a-z0-9]*-[^/ :]*" | sort -u
            binaries=$((binaries + 1))
          fi
        done <list
      done
      echo "$checked shipped files in ${toString (lib.length packages)} packages: $found text files and $binaries binaries naming the store"
      test $checked -gt 0
      test $found = 0
      test $binaries = 0
      touch $out
    '';
}
