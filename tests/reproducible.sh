#!/usr/bin/env bash
#
# Whether packages build the same again on this host, and name neither the host nor a build user: for each
# attribute, (1) `nix-build --check` builds it again (at another time, perhaps as another build user) and Nix compares
# the result with the output it has; (2) no file of the output contains this host's node name (uname -n), its
# platform (uname -v, in any case: perl lowercases it) or a build user's name (nixbld<N>: any "nixbld"), which a
# build on another host or as another user would give differently. A
# difference --check finds is kept beside the output (<output>.check) for comparison. Without a sandbox --check builds
# into a scratch output path and writes the real one back afterwards, which a checksum over a file naming its own
# output (an ELF DT_CHECKSUM over its RUNPATH) does not survive: files that are the same once their DT_CHECKSUMs are
# computed again pass, and are said to. Every output of a derivation is checked and searched, not only the one
# nix-build names (out); as --check stops at the first output that differs, an output it did not keep as a .check
# may not have been compared at all, and fails as "not compared" (tests/reproducible-selftest.sh).
#
# usage: reproducible.sh PKGS-FILE ATTR...   e.g. reproducible.sh /work/dev-pkgs.nix smartos-extra.ntp

set -uo pipefail

pkgsFile=${1:?usage: $0 PKGS-FILE ATTR...}
shift
host=$(uname -n) platform=$(uname -v)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

for attr in "$@"; do
    if ! nix-build "$pkgsFile" -A "$attr" --no-out-link >/dev/null 2>"$tmp/build.log"; then
        bad "$attr does not build"; tail -5 "$tmp/build.log" | sed 's/^/    /'
        continue
    fi
    # every output of the derivation (nix-build names only those it was asked for: out, of the nightly)
    outs=$(nix-store -q --outputs "$(nix-instantiate "$pkgsFile" -A "$attr" 2>/dev/null)")
    # the inode of each <output>.check left from an earlier run: a .check of this one replaces it
    declare -A before=()
    for out in $outs; do
        before[$out]=$(ls -di "$out.check" 2>/dev/null | awk '{ print $1 }')
    done
    if nix-build "$pkgsFile" -A "$attr" --no-out-link --check --keep-failed >/dev/null 2>"$tmp/check.log"; then
        ok "$attr builds the same again"
    elif ! grep -q 'may not be deterministic' "$tmp/check.log"; then
        bad "$attr does not build again"; grep '^error' "$tmp/check.log" | head -3 | sed 's/^/    /'
    else
        # Without a sandbox, --check builds into a scratch output path and then writes the output's own path back
        # in place of it; a checksum over a file naming its own output (an ELF DT_CHECKSUM over a RUNPATH) keeps
        # the scratch path's. Such a file is the same once both checksums are computed again over what is there.
        # --check keeps the first output that differs as <output>.check and compares none after it: an output with
        # no .check of this run was the same, or not compared at all, which cannot be told apart
        differ=() uncompared=()
        for out in $outs; do
            if [ ! -d "$out.check" ] || [ "$(ls -di "$out.check" | awk '{ print $1 }')" = "${before[$out]}" ]; then
                uncompared+=("$out")
                continue
            fi
            if [ "$(cd "$out" && find . | sort)" != "$(cd "$out.check" && find . | sort)" ]; then
                differ+=("$out: not the same files")
                continue
            fi
            while IFS= read -r f; do
                cmp -s "$out/$f" "$out.check/$f" && continue
                cp "$out/$f" "$tmp/a" && cp "$out.check/$f" "$tmp/b" && chmod u+w "$tmp/a" "$tmp/b"
                /usr/bin/elfedit -e dyn:checksum "$tmp/a" 2>/dev/null && /usr/bin/elfedit -e dyn:checksum "$tmp/b" 2>/dev/null &&
                    cmp -s "$tmp/a" "$tmp/b" && continue
                differ+=("$out/$f")
            done < <(cd "$out" && find . -type f)
        done
        if [ ${#differ[@]} -gt 0 ]; then
            bad "$attr builds differently again: ${#differ[@]} files, e.g. ${differ[0]}"
        elif [ ${#uncompared[@]} -eq 0 ]; then
            ok "$attr builds the same again, but for DT_CHECKSUMs over --check's scratch output path"
        fi
        if [ ${#uncompared[@]} -gt 0 ]; then
            bad "$attr: ${#uncompared[@]} outputs not compared (--check stops at the first output that differs), e.g. ${uncompared[0]}"
        fi
    fi
    for out in $outs; do
        for pat in "$host" "$platform" nixbld; do
            if grep -rliF "$pat" "$out" >"$tmp/named" 2>/dev/null; then
                bad "$attr: $(wc -l <"$tmp/named") files of $out name $pat, e.g. $(head -1 "$tmp/named")"
            else
                ok "$attr: $out names no $pat"
            fi
        done
    done
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
