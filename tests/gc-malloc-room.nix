# A program using the Boehm GC must still be able to malloc more than 1 GiB. illumos libc's malloc grows its heap
# only with brk, upwards from just above the program, so the GC's own heap (mapped with mmap) must not be placed in
# its way; bdwgc's Solaris default put it at 0x40000000 and left malloc about 940 MiB. Starts the GC as Nix does,
# with an initial heap, then mallocs 2 GiB in blocks the size of an xz encoder's.
#   nix-build tests/gc-malloc-room.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{
  pkgs,
  # the GC Nix links
  gc ? pkgs.nixDependencies.boehmgc,
}:

pkgs.stdenv.mkDerivation {
  name = "illumos-gc-malloc-room-test";
  dontUnpack = true;
  buildInputs = [ gc ];

  buildPhase = ''
    cat > room.c <<'C'
    #include <gc/gc.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    int main(void)
    {
        GC_INIT();
        GC_expand_hp(384UL << 20);
        void *collected = GC_MALLOC(1 << 20);
        size_t chunk = 94UL << 20, total = 0;
        while (total < (2UL << 30)) {
            void *p = malloc(chunk);
            if (p == NULL) {
                printf("malloc failed after %zu MiB; GC heap object at %p\n", total >> 20, collected);
                return 1;
            }
            memset(p, 1, 4096);
            total += chunk;
        }
        printf("malloc'd %zu MiB; GC heap object at %p\n", total >> 20, collected);
        return 0;
    }
    C
    $CC -o room room.c -lgc
  '';

  installPhase = ''
    ./room
    mkdir -p $out
    ./room > $out/result
  '';
}
