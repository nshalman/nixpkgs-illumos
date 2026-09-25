# gcc 14, the toolchain's compiler: github.com/illumos/gcc, with the in-tree libraries illumos-extra's gcc14 uses.
{ fetchurl }:

{
  version = "14.2.0-il-1";
  src = fetchurl {
    url = "https://github.com/illumos/gcc/archive/refs/tags/gcc-14.2.0-il-1.tar.gz";
    sha256 = "18lfswx45lkizs0ygdhhwp5qswb66jqssihwb9wnx6gpw986mgzq";
  };
  mpfr = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.bz2";
    sha256 = "183acv9b1ji6kzawzwcxnahlij2a1i11jfv256f0ir10bdir7pxr";
  };
  gmp = fetchurl {
    url = "https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.bz2";
    sha256 = "1jr03h6h0yz4w9pwyh7p6ijfk3vcsrc6139c5sp9nq7vghd22a5c";
  };
  mpc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz";
    sha256 = "1f2rqz0hdrrhx4y1i5f8pv6yv08a876k1dqcm9s2p26gyn928r5b";
  };
  patches = [
    ./ld-flags.patch
    ./madvise-decl.patch
    ./no-ccs-exec-prefix.patch
    ./ts-errno.patch
    ./asm-debug-prefix-map.patch
    # nixpkgs' gcc patch (pkgs/development/compilers/gcc/patches/13/, applied to gcc 13 to 16): __FILE__ of a file
    # in the store gets its hash in upper case, so that a header's __FILE__ does not make its store path, often a
    # -dev output, a runtime dependency. The cc-wrapper counts on it for a GNU compiler (`useMacroPrefixMap =
    # !isGNU`).
    ./mangle-NIX_STORE-in-__FILE__.patch
  ];
}
