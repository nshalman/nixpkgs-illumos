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
