# What a bootstrap-files release holds besides the toolchain. The list follows
# pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix on the illumos-recipe-v2 branch.
pkgs: with pkgs; [
  coreutils
  bashNonInteractive
  gnutar
  findutils
  gnumake
  gnused
  gnugrep
  gawk
  diffutils
  patch

  xz
  xz.dev
  gzip
  bzip2
  bzip2.dev
  zlib
  zlib.dev

  # gas and the rest of GNU binutils; the link-editor is illumos-ld.
  binutils-unwrapped
  expand-response-params
  patchelf

  curlMinimal.out
  curlMinimal.bin

  gnum4
  flex
  bison
  perl
]
