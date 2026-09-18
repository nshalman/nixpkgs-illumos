# The published illumos sysroot: headers, crt objects and link-time libraries from a pinned, old
# illumos-gate build. It is this platform's `libc` for building, in the way apple-sdk is on Darwin.
#
# The tarball ships FULL runtime libraries (a 2 MB libc.so.1, ld.so.1, ...), not stubs; only the gcc
# runtime pieces (libgcc_s, libssp) are mapfile stubs. So:
#   * nothing in here may be patched, stripped or otherwise rewritten, and
#   * $out/lib and $out/usr/lib are link-time only. They must never reach a DT_RUNPATH. At run time libc
#     and the ELF interpreter come from the host, which is what `dynamicLinker` says.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "illumos-sysroot";
  # <date of the illumos-gate commit>-<commit>-<sysroot revision>, as upstream tags it.
  version = "20210501-e0b4275f34-v0";

  src = fetchurl {
    url = "https://github.com/illumos/sysroot/releases/download/${version}/illumos-sysroot-i386-${version}.tar.gz";
    sha256 = "28d8f4f6d84331ff1e99ac3d68b917cf8174897a5c00171c5e493253eb1587f6";
  };

  # The archive has no top-level directory: it unpacks to lib/ and usr/.
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R lib usr "$out/"
    runHook postInstall
  '';

  passthru = {
    # Consumed the way cc-wrapper consumes any libc: $out + incdir, $out + libdir.
    incdir = "/usr/include";
    libdir = "/usr/lib/amd64";
    # Deliberately a HOST path, not a store path.
    dynamicLinker = "/usr/lib/amd64/ld.so.1";
    # Highest symbol version in this sysroot's libc.so.1; binaries linked against it need nothing newer.
    libcFloor = "ILLUMOS_0.38";
  };

  meta = {
    description = "Headers and link-time libraries from a pinned illumos-gate build (the ABI floor)";
    homepage = "https://github.com/illumos/sysroot";
    license = lib.licenses.cddl;
    platforms = lib.platforms.all; # unpack-only; the contents are only useful when targeting illumos
  };
}
