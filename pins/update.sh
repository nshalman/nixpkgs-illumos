#!/usr/bin/env bash
#
# Pins each source named (all of sources.json's when none are) at the commit its branch is at now, in pins.json:
# rev, date (the commit's time) and hash (the NAR hash of the commit's tree as `git archive` gives it, which is what
# GitHub's archive of it unpacks to and fetchFromGitHub checks), and submodules, which archives leave out: by path,
# the url (.gitmodules'), rev (the commit's gitlink) and hash (of that commit's tree, likewise). A source whose branch
# has not moved is left as it is. Nothing else is changed; sources.json says where each comes from and which branch
# it follows.
#
# usage: update.sh [NAME...]   (needs git, nix, python3 and a tar that reads standard input by default on PATH)
#
# PINS_DIR is the directory of sources.json and pins.json (default: this script's), PINS_URL_PREFIX where the
# repositories are (default https://github.com: PREFIX/owner/repo.git).

set -euo pipefail

dir=${PINS_DIR:-$(cd "$(dirname "$0")" && pwd)}
prefix=${PINS_URL_PREFIX:-https://github.com}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

json() { python3 -c "import json, sys; $1" "$dir/sources.json" "$dir/pins.json" "${@:2}"; }

if [ $# -eq 0 ]; then
    set -- $(json 'print(" ".join(sorted(json.load(open(sys.argv[1])))))')
fi

for name in "$@"; do
    if ! read -r owner repo branch < <(json 's = json.load(open(sys.argv[1]))[sys.argv[3]]; print(s["owner"], s["repo"], s["branch"])' "$name" 2>/dev/null); then
        echo "$name: not in $dir/sources.json" >&2
        exit 1
    fi
    url="$prefix/$owner/$repo.git"
    pinned=$(json 'print(json.load(open(sys.argv[2])).get(sys.argv[3], {}).get("rev", ""))' "$name")

    head=$(git ls-remote "$url" "refs/heads/$branch" | cut -f1)
    if [ -z "$head" ]; then
        echo "$name: no branch $branch at $url" >&2
        exit 1
    fi
    if [ "$head" = "$pinned" ]; then
        echo "$name: $branch at $head, as pinned"
        continue
    fi

    # the branch's commit, its time and its archive's tree
    git init -q --bare "$tmp/$name.git"
    git -C "$tmp/$name.git" fetch -q --depth 1 "$url" "refs/heads/$branch"
    rev=$(git -C "$tmp/$name.git" rev-parse FETCH_HEAD)
    date=$(git -C "$tmp/$name.git" log -1 --format=%ct FETCH_HEAD)
    mkdir "$tmp/$name"
    git -C "$tmp/$name.git" archive FETCH_HEAD | tar -x -C "$tmp/$name"
    hash=$(nix --extra-experimental-features nix-command hash path --type sha256 "$tmp/$name")

    # its submodules, which the archive leaves out: each at the commit its gitlink names, from the url .gitmodules
    # gives it, with the hash of that commit's archive (lines of path, url, rev, hash)
    : >"$tmp/$name.submodules"
    git -C "$tmp/$name.git" ls-tree -r FETCH_HEAD | while IFS=$'\t' read -r entry path; do
        read -r _ type subrev <<<"$entry"
        [ "$type" = commit ] || continue
        subname=$(git -C "$tmp/$name.git" config --blob FETCH_HEAD:.gitmodules --get-regexp '^submodule\..*\.path$' |
            awk -v p="$path" '$2 == p { sub(/^submodule\./, "", $1); sub(/\.path$/, "", $1); print $1 }')
        suburl=$(git -C "$tmp/$name.git" config --blob FETCH_HEAD:.gitmodules "submodule.$subname.url")
        case $suburl in
            ./* | ../*) echo "$name: submodule $path has a relative url ($suburl), which is not supported" >&2; exit 1 ;;
        esac
        sub=$tmp/$name.sub
        rm -rf "$sub.git" "$sub"
        git init -q --bare "$sub.git"
        git -C "$sub.git" fetch -q --depth 1 "$suburl" "$subrev"
        mkdir "$sub"
        git -C "$sub.git" archive "$subrev" | tar -x -C "$sub"
        subhash=$(nix --extra-experimental-features nix-command hash path --type sha256 "$sub")
        printf '%s\t%s\t%s\t%s\n' "$path" "$suburl" "$subrev" "$subhash" >>"$tmp/$name.submodules"
    done

    json '
p = json.load(open(sys.argv[2]))
p[sys.argv[3]] = {"rev": sys.argv[4], "hash": sys.argv[5], "date": int(sys.argv[6])}
subs = [l.rstrip("\n").split("\t") for l in open(sys.argv[7])]
if subs:
    p[sys.argv[3]]["submodules"] = {path: {"url": url, "rev": rev, "hash": hash} for path, url, rev, hash in subs}
with open(sys.argv[2], "w") as f:
    json.dump(p, f, indent=2, sort_keys=True)
    f.write("\n")' "$name" "$rev" "$hash" "$date" "$tmp/$name.submodules"
    echo "$name: $branch moved to $rev${pinned:+ (from $pinned)}"
done
