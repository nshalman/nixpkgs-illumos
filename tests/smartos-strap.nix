# The strap packages (pkgs/smartos-strap), each against SmartOS's own proto.strap from the same illumos-extra commit
# (tests/strap-compare.sh: the same files and links, ELF classes, SONAMEs, NEEDED entries, RUNPATHs up to where
# they point, version definitions and exported symbols, and identical other files), and used the way the gate uses
# them: a program built by the strap gcc against the package, 32- and 64-bit, run.
#   nix-build tests/smartos-strap.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{ pkgs }:

let
  strap = pkgs.smartos-strap;
  inherit (strap) gcc gcc10-illumos reference;

  # compare NAME PKG REGEX: PKG against the reference's paths matching REGEX. compareExpecting also takes the paths
  # whose differences are expected (each caller says why).
  compareExpecting =
    name: pkg: regex: expected:
    pkgs.runCommand "smartos-strap-${name}-compare" { } ''
      GCC_LIB=${gcc10-illumos.lib} GCC_OUT=${gcc10-illumos} bash ${./strap-compare.sh} ${reference} ${pkg} \
        '${regex}' '${expected}' >report 2>&1 || { cat report; exit 1; }
      cat report; cp report $out
    '';
  compare = name: pkg: regex: compareExpecting name pkg regex "";

  # PROGRAM (C source) built against PKG for each word size in BITS with the given libraries, run, and its output
  # checked; a library it needs has to resolve into PKG.
  use =
    name: pkg: bits: libs: program: expect:
    pkgs.runCommand "smartos-strap-${name}-use" { } ''
      cat >t.c <<'C'
      ${program}
      C
      for bits in ${toString bits}; do
        if [ $bits = 32 ]; then l="-L${pkg}/usr/lib -R${pkg}/usr/lib"; else l="-L${pkg}/usr/lib/amd64 -R${pkg}/usr/lib/amd64"; fi
        ${gcc} -m$bits -I${pkg}/usr/include t.c -o t$bits $l ${libs}
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
  libz = compare "libz" strap.libz "^(usr/)?lib/(amd64/)?libz\\.|^usr/include/z(lib|conf)\\.h$";
  libz-use = use "libz" strap.libz [ 32 64 ] "-lz" ''
    #include <stdio.h>
    #include <string.h>
    #include <zlib.h>
    int main(void) {
      const char *in = "strap zlib strap zlib strap zlib";
      unsigned char z[128], back[128];
      uLongf zn = sizeof z, bn = sizeof back;
      if (compress(z, &zn, (const unsigned char *)in, strlen(in) + 1) != Z_OK) return 1;
      if (uncompress(back, &bn, z, zn) != Z_OK) return 2;
      printf("%s %s\n", zlibVersion(), strcmp((char *)back, in) == 0 ? "round trip" : "mismatch");
      return 0;
    }
  '' "1.3.1 round trip";

  libexpat = compare "libexpat" strap.libexpat "^usr/lib/(amd64/)?libexpat\\.|^usr/include/expat(_external)?\\.h$";
  libexpat-use = use "libexpat" strap.libexpat [ 32 64 ] "-lexpat" ''
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

  libidn = compare "libidn" strap.libidn "^usr/lib/libidn\\.|^usr/include/(stringprep|idna|punycode|idn-free|pr29|tld|idn-int)\\.h$";
  libidn-use = use "libidn" strap.libidn [ 32 ] "-lidn" ''
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

  idnkit = compare "idnkit" strap.idnkit "^usr/bin/idn|^usr/etc/idn|^usr/include/idn/|^usr/lib/libidnkit|^usr/share/idnkit/|^usr/share/man/man[135]/(idn|libidnkit)";

  bzip2 = compare "bzip2" strap.bzip2 "^usr/bin/(bz|bunzip2)|^usr/lib/(amd64/)?libbz2\\.|^usr/include/bzlib\\.h$|^usr/share/man/man1/bz";
  bzip2-use = pkgs.runCommand "smartos-strap-bzip2-run" { } ''
    b=${strap.bzip2}/usr/bin
    # the programs find libbz2 where illumos-extra's do: not through a RUNPATH, on the system's library path
    seq 1 20000 >in
    LD_LIBRARY_PATH=${strap.bzip2}/usr/lib $b/bzip2 -c in >in.bz2
    LD_LIBRARY_PATH=${strap.bzip2}/usr/lib $b/bzcat in.bz2 | cmp - in
    echo "ok   bzip2 and bzcat round trip"
    touch $out
  '';

  libxml = compare "libxml" strap.libxml "^(usr/)?lib/(amd64/)?libxml2\\.|^usr/include/libxml2/|^usr/share/aclocal/libxml\\.m4$|^usr/share/man/man1/xml|^usr/bin/xml";
  libxml-use = use "libxml" strap.libxml [ 32 64 ] "-I${strap.libxml}/usr/include/libxml2 -lxml2" ''
    #include <stdio.h>
    #include <libxml/parser.h>
    #include <libxml/tree.h>
    int main(void) {
      const char *doc = "<a><b>strap</b></a>";
      xmlDocPtr d = xmlReadMemory(doc, 19, "t.xml", NULL, 0);
      if (d == NULL) return 1;
      xmlChar *s = xmlNodeGetContent(xmlDocGetRootElement(d));
      printf("%s %s\n", LIBXML_DOTTED_VERSION, s);
      return 0;
    }
  '' "2.13.8 strap";

  # lib/libsunw_{crypto,ssl}.so are openssl3's in the reference (it installs after this); lib/64 and etc/sfw/openssl
  # are the same links from both.
  openssl1x = compare "openssl1x" strap.openssl1x "^(usr/)?lib/(amd64/)?(libsunw_(crypto|ssl)\\.so\\.1\\.0\\.0|libsunw1x_(crypto|ssl)\\.so)$|^lib/64$|^etc/sfw/openssl$|^opt/1x/|^\\.build/libsunw1x_crypto\\.a$";
  openssl1x-use = use "openssl1x" strap.openssl1x [ 32 64 ] "-I${strap.openssl1x}/opt/1x -lsunw1x_crypto" ''
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

  # openssl1x installs libsunw_{crypto,ssl}.so too; openssl3's links are the ones in the reference, and only its
  # headers are in usr/include/openssl (1.0.2's are under opt/1x).
  openssl3 = compare "openssl3" strap.openssl3 "^(usr/)?lib/(amd64/)?(lib(crypto|ssl)-smartos\\.|libsunw_(crypto|ssl)\\.so$)|^lib/64$|^etc/openssl/openssl\\.cnf$|^etc/sfw/openssl$|^usr/include/openssl/|^usr/(sfw/)?bin/(openssl|CA\\.pl)$|^\\.build/libsunw_crypto\\.a$";
  openssl3-use = use "openssl3" strap.openssl3 [ 32 64 ] "-lcrypto-smartos" ''
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

  nss-nspr = compare "nss-nspr" strap.nss-nspr "^usr/lib/mps/|^usr/include/mps/|^usr/bin/(amd64/)?certutil$|^usr/share/man/man1/certutil\\.1$";
  # certutil makes a new database and lists it: NSPR, NSS, softoken and sqlite at work
  nss-nspr-use = pkgs.runCommand "smartos-strap-nss-nspr-run" { } ''
    for c in ${strap.nss-nspr}/usr/bin/certutil ${strap.nss-nspr}/usr/bin/amd64/certutil; do
      /usr/bin/ldd $c
      rm -rf db; mkdir db
      $c -N -d sql:db --empty-password
      $c -L -d sql:db | tee out
      grep "Certificate Nickname" out >/dev/null
      echo "ok   $c makes and lists a database"
    done
    touch $out
  '';

  # CORE/config.h records the build: the host's uname, and the signals of the headers perl was configured against
  # (SIG_NAME, SIG_NUM, SIG_SIZE: their platform's, one more than in the 2021 sysroot's)
  perl = compareExpecting "perl" strap.perl "^usr/perl5/" "^usr/perl5/5\\.12/lib/i86pc-solaris-64int/CORE/config\\.h$";
  # the strap perl runs, loads an XS module and reports its strap configuration
  perl-use = pkgs.runCommand "smartos-strap-perl-run" { } ''
    p=${strap.perl}/usr/perl5/5.12/bin/perl
    /usr/bin/elfdump -e $p | grep ELFCLASS32 >/dev/null
    $p -MConfig -MDigest::MD5=md5_hex -e 'print "$Config{version} $Config{use64bitint} $Config{usedtrace} ", md5_hex("abc"), "\n"' | tee out
    grep -x '5.12.3 define define 900150983cd24fb0d6963f7d28e17f72' out >/dev/null
    echo "ok   perl 5.12.3 runs an XS module"
    touch $out
  '';

  # config.gypi records the python gyp ran with: pkgsrc's there, nixpkgs' (its store path removed) here
  node = compareExpecting "node" strap.node "^usr/node/" "^usr/node/0\\.10/include/node/config\\.gypi$";
  # the strap node runs, with its OpenSSL and zlib bindings; python 2.7 was only for building it
  node-use = pkgs.runCommand "smartos-strap-node-run" { exportReferencesGraph = [ "closure" strap.node ]; } ''
    n=${strap.node}/usr/node/0.10/bin/node
    /usr/bin/ldd $n
    $n -e 'var h = require("crypto").createHash("sha256").update("abc").digest("hex").slice(0, 8);
      console.log([process.version, process.versions.openssl, process.versions.zlib, h].join(" "));' | tee out
    grep -x 'v0.10.26 1.0.2u 1.3.1 ba7816bf' out >/dev/null
    echo "ok   node 0.10.26 hashes with OpenSSL 1.0.2u and has zlib 1.3.1"
    if grep -e '-python-' closure; then echo "FAIL python is in node's closure"; exit 1; fi
    echo "ok   python is not in node's closure"
    touch $out
  '';

  # the adjunct is extracted last, so every file of it is in the reference as it is
  adjunct = pkgs.runCommand "smartos-strap-adjunct-compare" { } ''
    regex=$(cd ${strap.adjunct} && find . \( -type f -o -type l \) | sed -e 's#^\./##' -e 's/[][\.*^$+?(){}|]/\\&/g' \
      -e 's/^/^/' -e 's/$/$/' | paste -sd'|')
    GCC_LIB=${gcc10-illumos.lib} GCC_OUT=${gcc10-illumos} bash ${./strap-compare.sh} ${reference} ${strap.adjunct} "$regex" >report 2>&1 || {
      cat report; exit 1; }
    cat report; cp report $out
  '';

  cpp = compare "cpp" strap.cpp "^usr/lib/cpp$";
  cpp-use = pkgs.runCommand "smartos-strap-cpp-run" { } ''
    printf '#define GREETING(x) hello x\n#if defined(GREETING)\nGREETING(strap)\n#endif\n' >t.c
    ${strap.cpp}/usr/lib/cpp t.c | tee out
    # like the traditional illumos cpp, it keeps the space before the expansion
    grep -x ' *hello strap' out >/dev/null
    echo "ok   cpp expands a macro"
    touch $out
  '';
}
