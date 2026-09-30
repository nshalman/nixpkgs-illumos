# illumos-extra's platform packages (pkgs/smartos-extra), each against what the SmartOS platform the builder runs
# ships of it (tests/strap-compare.sh with the build host's root as the reference, limited to the paths
# illumos-extra's manifest lists as files of the package; modes left out, since the platform takes them from the
# manifest), and used: a program built by the strap gcc against the package, run.
#
# The reference is the running platform, an input from outside the store: its illumos-extra commit is not
# necessarily the pinned one, and a result is not rebuilt when the platform changes.
#   nix-build tests/smartos-extra.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{ pkgs }:

let
  extra = pkgs.smartos-extra;
  inherit (pkgs.smartos-strap) gcc gcc10-illumos illumosExtra;

  # compare NAME PKG REGEX: PKG against the platform's files that illumos-extra's manifest lists and
  # REGEX matches. compareExpecting also takes the paths whose differences are expected (each caller says why).
  compareExpecting =
    name: pkg: regex: expected:
    pkgs.runCommand "smartos-extra-${name}-compare" { } ''
      # f entries only: smartos-live's builder copies those from the proto area and makes the manifest's symbolic
      # and hard links (s, h) itself (tools/builder/builder.c)
      awk '$1 == "f" { print $2 }' ${illumosExtra}/manifest |
        grep -E '${regex}' >list || true
      IGNORE_MODES=1 PATH_LIST=$PWD/list GCC_LIB=${gcc10-illumos.lib} GCC_OUT=${gcc10-illumos} \
        bash ${./strap-compare.sh} / ${pkg} '${regex}' '${expected}' >report 2>&1 || { cat report; exit 1; }
      cat report; cp report $out
    '';
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

  # The builder's platform (joyent_20260723T000757Z) ships OpenSSL 3.0.21, the pinned illumos-extra 3.5.8: newer
  # symbol versions (OPENSSL_SMARTOS_3.1.0 and on), a newer openssl.cnf, and openssl as a 64-bit command only
  # (install-sfw-64, "64-bit commands only, now"), where the platform's is 32-bit.
  openssl3 = compareExpecting "openssl3" extra.openssl3 "^lib/(amd64/)?lib(crypto|ssl)-smartos\\.|^usr/bin/openssl$|^etc/openssl/openssl\\.cnf$"
    "^lib/(amd64/)?lib(crypto|ssl)-smartos\\.so\\.3$|^usr/bin/openssl$|^etc/openssl/openssl\\.cnf$";
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
}
