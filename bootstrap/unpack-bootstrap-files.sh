# Builder of the bootstrap archive: unpack bootstrap-tools.tar.xz with the tools in $src (unpack.nar.xz), then make
# the result independent of the store paths it was packed from. Follows pkgs/stdenv/freebsd/unpack-bootstrap-files.sh.
# The runtime linker and libc are the running system's, so unlike there no tool is started through a loader.
#
# $src's programs still carry the RUNPATHs of where they were built. LD_LIBRARY_PATH_64 is searched first.
export LD_LIBRARY_PATH_64=$src/lib
$src/bin/mkdir $out
$src/bin/tar -I $src/bin/xz -C $out -xf $bootstrapTools || exit 1

export PATH=$out/bin

# Until the rewrite below is done the programs in $out find their libraries through LD_LIBRARY_PATH_64.
export LD_LIBRARY_PATH_64=$out/lib:$out/lib/amd64

# RUNPATHs are not set with patchelf as on FreeBSD: patchelf 0.15 can shrink a RUNPATH on illumos objects but not
# grow one ("cannot find section '.gnu.version_r'"). They do not need to be. Every closure was merged into this
# one prefix, so each old RUNPATH directory STORE-PATH/lib is now $out/lib, and a RUNPATH is a string like any other.

# Replace every other store path by this one. In text files (scripts, .pc, .la, perl's Config) freely; in binaries
# padded with leading slashes to the same length so that they stay valid: RUNPATHs and paths compiled in as
# strings. A name shorter than this archive's cannot be padded, which is why the archive's name is short; such
# leftovers are listed in nix-support/unpatched instead of being passed over silently.
mkdir -p $out/nix-support
: > $out/nix-support/unpatched
pat='/nix/store/[a-z0-9]\{32\}-[^/ ":]*'
for f in $(find $out -type f); do
  if grep -qI . "$f"; then
    grep -q "$pat" "$f" && sed -i -e "s@$pat@$out@g" "$f"
    continue
  fi
  tries=0
  while [ $tries -lt 50 ]; do
    tries=$((tries + 1))
    old=$(strings "$f" | grep -o "$pat" | grep -vx "$out" | grep -vxF -f $out/nix-support/unpatched | head -n1)
    [ -n "$old" ] || break
    new=$out
    if [ ${#new} -gt ${#old} ]; then echo "$old $f" >> $out/nix-support/unpatched.files; echo "$old" >> $out/nix-support/unpatched; continue; fi
    while [ ${#new} -lt ${#old} ]; do new="/$new"; done
    sed -i -e "s@$old@$new@g" "$f" || { echo "$old $f (sed failed)" >> $out/nix-support/unpatched.files; break; }
  done
done
unset LD_LIBRARY_PATH_64
true || exit 1
echo "unpatched store paths: $(sort -u $out/nix-support/unpatched | wc -l)"
echo $out
