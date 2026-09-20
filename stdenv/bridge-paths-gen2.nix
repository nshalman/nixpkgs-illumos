# The bridge with the second-generation toolchain: what `nix-build bootstrap -A toolchain` produced when the bridge
# ran on ./bridge-paths.nix. The userland a bootstrap-files release ships must be linked against the gcc runtime
# libraries the release ships, so the release is built from this set, not from the first generation.
import ./bridge-paths.nix
// {
  illumos-libc = builtins.storePath /nix/store/i7x0ac2wbz7jck4lzp1fkimnzm94xdk3-illumos-libc-20210501-e0b4275f34-v0;
  illumos-ld = builtins.storePath /nix/store/yp2p6l36frnsimmm2wmjr1z1r5yw6gvm-illumos-ld-0-unstable-2026-09-18;
  gcc-illumos = {
    out = builtins.storePath /nix/store/bnmi761hz2nbc2nh0wck3dlkyiqmlb6y-gcc-illumos-14.2.0-il-1;
    lib = builtins.storePath /nix/store/lxlprqap0nb6akywlr9aqxjbis7llsfq-gcc-illumos-14.2.0-il-1-lib;
  };
}
