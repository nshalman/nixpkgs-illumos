# gcc 10's runtime libraries in the platform's usr/lib, as illumos-extra's non-strap build puts them there before the
# other packages (the primary compiler's `fixup` target, Makefile.gcc): gcc-strapfix's gcclibs.tar.gz from the strap,
# extracted into usr/lib. Nothing is built.
#
# Theirs carry the RPATH gcc-strapfix leaves on them, their build's own proto.strap/usr/gcc/10/lib: a strap build runs
# gcc-strapfix twice (after gcc's install, and again as fixup_strap), and the second run packs gcclibs.tar.gz from
# libraries the first had edited (RUNPATH deleted, the remaining RPATH set to that directory). Ours are as gcc10-illumos
# built them, RUNPATH and RPATH /usr/gcc/10/lib (../gcc10-illumos). Neither directory exists on the platform.
{ runCommand, smartos-strap }:

runCommand "smartos-extra-gcc10-runtime" { } ''
  mkdir -p $out/usr/lib
  cd $out/usr/lib
  tar xzf ${smartos-strap.proto}/gcclibs.tar.gz
''
