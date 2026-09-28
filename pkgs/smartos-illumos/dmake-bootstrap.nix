# The illumos make (make, and dmake: the same program, parallel when called as dmake) built from illumos-joyent's
# usr/src/cmd/make without the gate's build system, only to run the gate's tools stage, which builds the real one
# with it (smartos-live takes this from pkgsrc's smartos-build-tools, itself packaged from a SmartOS build).
#
# usr/src/cmd/make's makefiles reduce to five object lists: libbsd, libmksh and libvroot (static) and make's own
# objects, linked with -lnsl -lumem; and libmakestate.so.1, the link-editor support library through which ld reports
# a link's inputs to .make.state. make names it to ld in SGS_SUPPORT_32/SGS_SUPPORT_64 wherever a makefile has
# .KEEP_STATE, looking for it in lib and lib/64 beside its bin directory. The default rules (make.rules,
# svr4.make.rules) go to share/lib/make, where make looks for them beside its bin directory.
#
# Built by this stdenv's compilers against the sysroot, 64-bit (the gate builds make 32-bit and libmakestate for
# both word sizes). libmakestate is 64-bit only, for 64-bit link-editors such as illumos-ld; a 32-bit ld would find
# none.
{
  lib,
  stdenv,
  src,
}:

stdenv.mkDerivation {
  pname = "illumos-dmake-bootstrap";
  version = "0-unstable-2026-09-11";

  inherit src;
  # only usr/src/cmd/make, not the whole tree
  unpackPhase = ''
    runHook preUnpack
    cp -r $src/usr/src/cmd/make make
    chmod -R u+w make
    cd make
    runHook postUnpack
  '';

  dontConfigure = true;

  # the gate compiles these with its own flag set; nixpkgs' hardening flags are not part of that
  # (-Werror=format-security stops lib/vroot/report.cc)
  hardeningDisable = [ "all" ];

  buildPhase = ''
    runHook preBuild
    # CPPFLAGS as the makefiles give them: -I$(SRC)/cmd/make/include, -D_FILE_OFFSET_BITS=64
    cxx() { $CXX -O2 -D_FILE_OFFSET_BITS=64 -Iinclude -c "$@"; }
    mkdir -p obj/bsd obj/mksh obj/vroot obj/bin
    for o in bsd; do cxx lib/bsd/$o.cc -o obj/bsd/$o.o; done
    for o in dosys globals i18n macro misc mksh read; do cxx lib/mksh/$o.cc -o obj/mksh/$o.o; done
    for o in access args chdir chmod chown chroot creat execve lock lstat mkdir mount open readlink report \
             rmdir stat truncate unlink utimes vroot setenv; do
      cxx lib/vroot/$o.cc -o obj/vroot/$o.o
    done
    for o in ar depvar doname dosys files globals implicit macro main misc nse_printdep parallel pmake read \
             read2 rep state; do
      cxx bin/$o.cc -o obj/bin/$o.o
    done
    ar rcs libbsd.a obj/bsd/*.o
    ar rcs libmksh.a obj/mksh/*.o
    ar rcs libvroot.a obj/vroot/*.o
    $CXX -o make obj/bin/*.o libmksh.a libvroot.a libbsd.a -lc -lnsl -lumem

    # libmakestate (lib/makestate/Makefile.com): its mapfile, -lc
    for o in ld_file lock; do $CC -O2 -fPIC -c lib/makestate/$o.c -o obj/$o.o; done
    $CC -shared -Wl,-h,libmakestate.so.1 -Wl,-M,lib/makestate/mapfile-vers -o libmakestate.so.1 \
      obj/ld_file.o obj/lock.o -lc
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/lib/make
    cp make $out/bin/make
    ln -s make $out/bin/dmake
    mkdir -p $out/lib/64
    cp libmakestate.so.1 $out/lib/64/
    cp bin/make.rules.file $out/share/lib/make/make.rules
    cp bin/svr4.make.rules.file $out/share/lib/make/svr4.make.rules
    runHook postInstall
  '';

  # What the gate's makefiles use: conditional macros (all := TARGET = ...), pattern substitution, .KEEP_STATE (with a
  # link, which the link-editor reports to .make.state through libmakestate), the default rules from make.rules
  # (.c.o through COMPILE.c), and dmake's parallel mode.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    mkdir ic && cd ic
    printf 'int one(void) { return 1; }\n' >one.c
    printf 'int two(void) { return 2; }\n' >two.c
    printf 'int one(void), two(void);\nint main(void) { return one() + two() - 3; }\n' >main.c
    printf '%s\n' \
      'OBJS = one.o two.o main.o' \
      'SRCS = $(OBJS:%.o=%.c)' \
      'all := TARGET = built' \
      '.KEEP_STATE:' \
      'all: prog' \
      '	@echo "$(TARGET) from $(SRCS)"' \
      'prog: $(OBJS)' \
      '	$(LINK.c) -o $@ $(OBJS)' >Makefile
    $out/bin/dmake -j 2 CC=$CC all | tee out
    grep -x 'built from one.c two.c main.c' out >/dev/null
    ./prog
    # the link-editor recorded the link in .make.state through libmakestate (SGS_SUPPORT)
    test -f .make.state
    grep "^prog:" .make.state
    $out/bin/make CC=$CC all | grep -x 'built from one.c two.c main.c' >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "illumos make/dmake, built without the gate's build system to bootstrap its tools stage";
    homepage = "https://github.com/TritonDataCenter/illumos-joyent";
    license = lib.licenses.cddl;
    platforms = lib.platforms.illumos;
  };
}
