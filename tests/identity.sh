#!/usr/bin/env bash
#
# pkgs/smartos-live/identity.nix on a throwaway git repository standing in for the overlay's checkout: a clean tree
# (its commit, and the commit time as a build stamp), an untracked file (still clean: fetchGit
# leaves untracked files out), a changed tracked file (dirty: <commit>-dirty, no stamp), and a directory that is not a
# git checkout (unknown).
#
# usage: identity.sh (needs git and nix on PATH)

set -uo pipefail

top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
# leave $tmp first, as illumos' rm does not remove the current directory
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# identity DIR FIELD: identity.nix's FIELD for DIR, as JSON (a string quoted, null as null)
identity() {
    nix-instantiate --eval --strict --json \
        -E "(import $top/pkgs/smartos-live/identity.nix { src = $1; }).$2" 2>/dev/null
}

git init -q -b main "$tmp/repo"
cd "$tmp/repo"
echo a >file
git add -A
# 2023-11-14T22:13:20Z
GIT_COMMITTER_DATE=@1700000000 git commit -q -m one
rev=$(git rev-parse HEAD)

if [ "$(identity "$tmp/repo" kind)" = '"clean"' ] && [ "$(identity "$tmp/repo" rev)" = "\"$rev\"" ] &&
    [ "$(identity "$tmp/repo" shortRev)" = "\"${rev:0:7}\"" ] && [ "$(identity "$tmp/repo" date)" = 1700000000 ] &&
    [ "$(identity "$tmp/repo" stamp)" = '"20231114T221320Z"' ]; then
    ok "a clean tree: its commit, and the commit time as a build stamp"
else
    bad "a clean tree"; identity "$tmp/repo" ""
fi

echo b >untracked
if [ "$(identity "$tmp/repo" kind)" = '"clean"' ] && [ "$(identity "$tmp/repo" stamp)" = '"20231114T221320Z"' ]; then
    ok "an untracked file: still clean (fetchGit leaves it out)"
else
    bad "an untracked file: $(identity "$tmp/repo" kind)"
fi
rm untracked

echo c >>file
if [ "$(identity "$tmp/repo" kind)" = '"dirty"' ] && [ "$(identity "$tmp/repo" rev)" = "\"$rev-dirty\"" ] &&
    [ "$(identity "$tmp/repo" shortRev)" = "\"${rev:0:7}-dirty\"" ] && [ "$(identity "$tmp/repo" stamp)" = null ]; then
    ok "a changed tracked file: dirty, <commit>-dirty, no stamp"
else
    bad "a changed tracked file: $(identity "$tmp/repo" kind) $(identity "$tmp/repo" rev) $(identity "$tmp/repo" stamp)"
fi

mkdir "$tmp/plain" && echo a >"$tmp/plain/file"
if [ "$(identity "$tmp/plain" kind)" = '"unknown"' ] && [ "$(identity "$tmp/plain" rev)" = null ] &&
    [ "$(identity "$tmp/plain" stamp)" = null ]; then
    ok "not a git checkout: unknown, no commit, no stamp"
else
    bad "not a git checkout: $(identity "$tmp/plain" kind)"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
