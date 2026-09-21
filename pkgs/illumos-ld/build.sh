# Build sgsmsg (a build tool), libconv.a, liblddbg.so.4, libelf.so.1, libld.so.4 and ld.
# Expects: $src (illumos-gate), $sysroot, $CC, NIX_BUILD_CORES. Mirrors usr/src/cmd/sgs/*/Makefile.com.
set -eu
SRC=$src/usr/src; SGS=$SRC/cmd/sgs
W=$PWD/build; OUT=$W/out; mkdir -p "$OUT/bin" "$OUT/lib"
JOBS=${NIX_BUILD_CORES:-4}; [ "$JOBS" -gt 0 ] 2>/dev/null || JOBS=4

cc="$CC -m64 --sysroot=$sysroot"
# -YP, names ld's default library search path outright. It keeps the link inside the sysroot and also
# suppresses the gcc spec block that would add the compiler's own lib dir to RUNPATH; none of these objects
# need libgcc_s or libstdc++ at run time.
LINK="-YP,$sysroot/lib/amd64:$sysroot/usr/lib/amd64"
# Current gate source needs gate's own headers at COMPILE time (first casualty without them:
# __maybe_unused, from a sys/ccompile.h newer than the sysroot's). Libraries come only from the sysroot,
# so a call to anything newer than the floor fails at link time.
# libdemangle-sys is absent from the sysroot; libconv only dlopen()s it, so its header is enough.
INC="-I. -I$SGS/include -I$SGS/include/i386 -I$SRC/common/elfcap -I$SRC/lib/libc/inc \
  -I$SRC/common/sgsrtcid -I$SRC/uts/common -I$SRC/lib/libdemangle/common"
# -ffile-prefix-map: assertions embed __FILE__. Without the map every binary names $src, and the output would
# hold a runtime reference to the whole >1 GB gate tree.
CF="-std=gnu99 -O2 -fPIC -DPIC -D_REENTRANT -D_TS_ERRNO -Wno-unused-value -Wno-parentheses -Wno-switch \
  -ffile-prefix-map=$src=/illumos-gate"
IDENT="-i $SGS/messages/sgs.ident"
export MACH=i386

# The stdenv's auto-rpath hook puts an -rpath in NIX_LDFLAGS for every build input that ships shared
# libraries (here: libxcrypt, propagated by perl) and for $out/lib. Nothing built here links against a store
# library; the only RUNPATH entries wanted are the $ORIGIN ones given explicitly below.
export NIX_LDFLAGS=""

FAILED=$W/failed; : > "$FAILED"
cc1() { # out.o src.c [flags...]   -- runs in the background, at most $JOBS at once
  local o=$1 s=$2; shift 2
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n || true; done
  { $cc $CF $INC "$@" -c "$s" -o "$o" || echo "$s" >> "$FAILED"; } &
}
settle() { wait; if [ -s "$FAILED" ]; then echo "compile failures in stage '$1':"; cat "$FAILED"; exit 1; fi; echo "stage $1: $(ls *.o | wc -l) objects"; }

mkdir -p "$W/sgsmsg" && cd "$W/sgsmsg"
for f in $SRC/tools/sgs/sgsmsg/sgsmsg.c $SGS/common/string_table.c $SGS/common/findprime.c \
         $SGS/common/assfail.c $SRC/common/avl/avl.c; do
  cc1 "$(basename "${f%.c}").o" "$f" -DNATIVE_BUILD
done
settle sgsmsg
$cc -o sgsmsg *.o $LINK
SGSMSG=$W/sgsmsg/sgsmsg

mkdir -p "$W/libconv" && cd "$W/libconv"
C=$SGS/libconv/common
perl $SGS/tools/libconv_mk_report_bufsize.pl 8000
for m in $C/*.msg; do b=$(basename "$m" .msg); $SGSMSG $IDENT -h ${b}_msg.h -d ${b}_msg.c -n sgs_msg_libconv_$b "$m"; done
for b in arch audit c_literal cap config corenote data deftag demangle dl dwarf dwarf_ehe dynamic elf \
         entry globals group lddstub map phdr relocate relocate_i386 relocate_amd64 relocate_sparc \
         sections segments strproc symbols syminfo tokens time version; do cc1 $b.o $C/$b.c -I$C; done
for b in cap dynamic globals sections symbols symbols_sparc; do
  cc1 ${b}_machelf32.o $C/${b}_machelf.c -I$C; cc1 ${b}_machelf64.o $C/${b}_machelf.c -I$C -D_ELF64
done
cc1 elfcap.o $SRC/common/elfcap/elfcap.c -I$C
for m in *_msg.c; do cc1 "${m%.c}.o" "$m" -I$C; done
# The link-editor's version note. gate derives the revision from the SUNWonld README the same way.
REV=$(perl $SGS/tools/readme_revision $SGS/tools/SUNWonld-README)
bash $C/bld_vernote.ksh -R "$REV" -r "5.11" -o vernote.s
cc1 vernote.o vernote.s -D_ASM
settle libconv
ar cr libconv.a *.o

mkdir -p "$W/liblddbg" && cd "$W/liblddbg"
C=$SGS/liblddbg/common
$SGSMSG $IDENT -h msg.h -d msg.c -m liblddbg.cat -n liblddbg_msg $C/liblddbg.msg
for b in args audit basic debug syminfo tls; do cc1 $b.o $C/$b.c -I$C; done
for b in bindings cap dlfcns dynamic elf entry files got libs map move phdr relocate sections segments \
         shdr statistics support syms unused util version; do
  cc1 ${b}32.o $C/$b.c -I$C; cc1 ${b}64.o $C/$b.c -I$C -D_ELF64
done
cc1 alist.o $SGS/common/alist.c -I$C; cc1 msg.o msg.c -I$C
settle liblddbg
# The illumos link-editor records the name it was given for its output in the object (a FILE symbol). Every
# build directory ($W) is reached from one level below it, so the outputs are named relative to that, or the build
# directory, which Nix names differently for every build on illumos, ends up in ld and its libraries.
$cc -shared -o ../out/lib/liblddbg.so.4 -Wl,-h,liblddbg.so.4 -Wl,-M,$C/mapfile-vers '-Wl,-R,$ORIGIN' \
  *.o -L"$W/libconv" -lconv -lc $LINK
ln -s liblddbg.so.4 "$OUT/lib/liblddbg.so"

# libelf, 64-bit only. libld binds private libelf interfaces (_elf_*), which gate may change together with libld,
# so ld gets the libelf of its own commit instead of whatever the running system has.
mkdir -p "$W/libelf" && cd "$W/libelf"
C=$SGS/libelf/common
$SGSMSG $IDENT -h msg.h -d msg.c -n libelf_msg $C/libelf.msg
m4 < $C/xlate.m4 > xlate.c
m4 < $C/xlate64.m4 > xlate64.c
for b in ar begin cntl cook data end fill flag getarhdr getarsym getbase getdata getehdr getident getphdr getscn \
         getshdr getphnum getshnum getshstrndx hash input kind ndxscn newdata newehdr newphdr newscn next \
         nextscn output rand rawdata rawfile rawput strptr update error gelf clscook checksum; do
  cc1 $b.o $C/$b.c -I$C
done
for b in clscook newehdr newphdr update checksum; do cc1 ${b}64.o $C/$b.c -I$C -D_ELF64; done
for b in msg xlate xlate64; do cc1 $b.o $b.c -I$C; done
cc1 nlist.o $SGS/libelf/misc/nlist.c -I$C -DELF
settle libelf
$cc -shared -o ../out/lib/libelf.so.1 -Wl,-h,libelf.so.1 -Wl,-M,$C/mapfile-vers '-Wl,-R,$ORIGIN' \
  *.o -L"$W/libconv" -lconv -lc $LINK
ln -s libelf.so.1 "$OUT/lib/libelf.so"

mkdir -p "$W/libld" && cd "$W/libld"
C=$SGS/libld/common
LI="-I$C -DUSE_LIBLD_MALLOC -I$SRC/uts/common/krtld -I$SRC/uts/sparc"
$SGSMSG $IDENT -h msg.h -d msg.c -n libld_msg $C/libld.msg $C/libld.sparc.msg $C/libld.intel.msg
for b in debug globals util; do cc1 $b.o $C/$b.c $LI; done
for b in args entry exit groups ldentry ldlibs ldmachdep ldmain libs files map map_core map_support \
         map_v2 order outfile place relocate resolve sections sunwmove support syms update unwind \
         version wrap; do
  cc1 ${b}32.o $C/$b.c $LI; cc1 ${b}64.o $C/$b.c $LI -D_ELF64
done
for b in alist assfail findprime string_table strhash leb128; do cc1 $b.o $SGS/common/$b.c $LI; done
cc1 avl.o $SRC/common/avl/avl.c $LI; cc1 elfcap.o $SRC/common/elfcap/elfcap.c $LI; cc1 msg.o msg.c $LI
cc1 doreloc_x86_32.o   $SRC/uts/intel/ia32/krtld/doreloc.c  $LI -DDO_RELOC_LIBLD
cc1 doreloc_x86_64.o   $SRC/uts/intel/amd64/krtld/doreloc.c $LI -DDO_RELOC_LIBLD -D_ELF64
cc1 doreloc_sparc_32.o $SRC/uts/sparc/krtld/doreloc.c       $LI -DDO_RELOC_LIBLD
cc1 doreloc_sparc_64.o $SRC/uts/sparc/krtld/doreloc.c       $LI -DDO_RELOC_LIBLD -D_ELF64
cc1 machrel.intel32.o $C/machrel.intel.c $LI; cc1 machrel.amd64.o $C/machrel.amd.c $LI -D_ELF64
for b in machrel.sparc machsym.sparc; do cc1 ${b}32.o $C/$b.c $LI; cc1 ${b}64.o $C/$b.c $LI -D_ELF64; done
settle libld
$cc -shared -o ../out/lib/libld.so.4 -Wl,-h,libld.so.4 -Wl,-M,$C/mapfile-vers '-Wl,-R,$ORIGIN' \
  *.o -L"$W/libconv" -lconv -L"$OUT/lib" -llddbg -lelf -ldl -lc $LINK
ln -s libld.so.4 "$OUT/lib/libld.so"

mkdir -p "$W/ld" && cd "$W/ld"
C=$SGS/ld/common
$SGSMSG $IDENT -h msg.h -d msg.c -m ld.cat -n ld_msg $C/ld.msg
cc1 ld.o $C/ld.c -I$C; cc1 msg.o msg.c -I$C
settle ld
$cc -o ../out/bin/ld ld.o msg.o -Wl,-M,$C/mapfile-intf '-Wl,-R,$ORIGIN/../lib' \
  -lumem -L"$OUT/lib" -lld -lelf -llddbg -L"$W/libconv" -lconv $LINK
