#!/usr/bin/env bash
#
# Pins each source named (all of sources.json's when none are) at the commit its branch is at now, in pins.json:
# rev, date (the commit's time) and hash (the NAR hash of the commit's tree as `git archive` gives it, which is what
# GitHub's archive of it unpacks to and fetchFromGitHub checks). A source whose branch has not moved is left as it is.
# Nothing else is changed; sources.json says where each comes from and which branch it follows.
#
# usage: update.sh [NAME...]   (needs git, nix and python3 on PATH)
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

    json '
p = json.load(open(sys.argv[2]))
p[sys.argv[3]] = {"rev": sys.argv[4], "hash": sys.argv[5], "date": int(sys.argv[6])}
with open(sys.argv[2], "w") as f:
    json.dump(p, f, indent=2, sort_keys=True)
    f.write("\n")' "$name" "$rev" "$hash" "$date"
    echo "$name: $branch moved to $rev${pinned:+ (from $pinned)}"
done
