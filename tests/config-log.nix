# Rebuilds a sample of autoconf packages with one extra step after configure: print every line of every config.log
# that names a host header or library directory. config.log records the compiler and linker command lines of each
# probe, which the build log does not show. autoconf's own default `oldincludedir=/usr/include` is not reported. Read the result with `nix-store --read-log`; lines start with CONFIGLOG.
#   nix-build tests/config-log.nix --arg pkgs 'import ../bridge.nix { nixpkgs = ...; }'
{
  pkgs,
  names ? [
    "coreutils"
    "gnutar"
    "bash"
    "curlMinimal"
    "gawk"
  ],
}:

map (
  n:
  pkgs.${n}.overrideAttrs (old: {
    doCheck = false;
    postConfigure = (old.postConfigure or "") + ''
      echo "CONFIGLOG files: $(find . -name config.log | wc -l)"
      echo "CONFIGLOG known-positive (lines naming the store, must not be 0): $(find . -name config.log -exec cat {} + | grep -c /nix/store/)"
      # Store paths are removed first: illumos-libc's own usr/include and usr/lib are what the probes should name.
      find . -name config.log | while read -r f; do
        sed -E "s|/nix/store/[^ :\"']*||g" "$f" \
          | grep -nE '/(usr/(include|lib|gnu|sfw|ccs)|opt/local|lib/(amd64|64))(/|[^[:alnum:]_.-]|$)' \
          | grep -vE '^[0-9]+:oldincludedir(_c)?=' \
          | sed "s|^|CONFIGLOG hit: $f:|"
      done || true
      echo "CONFIGLOG done"
    '';
  })
) names
