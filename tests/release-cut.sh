#!/usr/bin/env bash
#
# release/cut.sh on a throwaway repository standing in for the overlay (release/cut.sh, pins/update.sh and
# pkgs/smartos-live/identity.nix copied in, one source pinned from a local repository standing in for GitHub, as
# tests/pins-update.sh does): a release at a given date (one commit at the stamp's time with the pins moved, a root
# password and its hash in release/release.json, which identity.nix calls a release), then the cuts refused, each
# leaving HEAD as it was (the same date again, a future one, one before HEAD's commit, a changed tracked file, a stamp
# not a stamp), and one with the default stamp (now) that keeps the pins.
#
# usage: release-cut.sh CRYPTPASS (smartos-live's cryptpass; needs git, nix, python3 and perl on PATH)

set -uo pipefail

cryptpass=$1
top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
# leave $tmp first, as illumos' rm does not remove the current directory
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export PINS_URL_PREFIX="file://$tmp/gh" CRYPTPASS=$cryptpass
epoch() { python3 -c 'import calendar, sys, time; print(calendar.timegm(time.strptime(sys.argv[1], "%Y%m%dT%H%M%SZ")))' "$1"; }
field() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$tmp/repo/$1" "$2"; }
identity() {
    nix-instantiate --eval --strict --json \
        -E "(import $tmp/repo/pkgs/smartos-live/identity.nix { src = $tmp/repo; }).$1" 2>/dev/null
}

# "GitHub": acme/widget, branch main
git init -q --bare -b main "$tmp/gh/acme/widget.git"
git init -q -b main "$tmp/widget"
(cd "$tmp/widget" && echo w >w && git add -A && git commit -q -m w && git push -q "$tmp/gh/acme/widget.git" main)
widgetA=$(git -C "$tmp/widget" rev-parse HEAD)

# the overlay
git init -q -b main "$tmp/repo"
cd "$tmp/repo"
mkdir -p release pins pkgs/smartos-live
cp "$top/release/cut.sh" release/
cp "$top/pins/update.sh" pins/
cp "$top/pkgs/smartos-live/identity.nix" pkgs/smartos-live/
echo '{ "widget": { "owner": "acme", "repo": "widget", "branch": "main" } }' >pins/sources.json
echo '{}' >pins/pins.json
git add -A
GIT_COMMITTER_DATE=@1700000000 GIT_AUTHOR_DATE=@1700000000 git commit -q -m start

# refused NAME ARGS...: cut.sh ARGS fails, saying why (in $tmp/NAME.err), HEAD and the tree as they were
refused() {
    local name=$1 head tree
    shift
    head=$(git rev-parse HEAD)
    tree=$(git diff HEAD; git status --porcelain)
    if ! bash release/cut.sh "$@" >"$tmp/$name.out" 2>"$tmp/$name.err" && [ "$(git rev-parse HEAD)" = "$head" ] &&
        [ "$(git diff HEAD; git status --porcelain)" = "$tree" ] && [ -s "$tmp/$name.err" ]; then
        return 0
    fi
    sed 's/^/    /' "$tmp/$name.out" "$tmp/$name.err"
    return 1
}

stamp=20261001T000000Z
if bash release/cut.sh --stamp 20261001 >"$tmp/cut1.out" 2>&1 &&
    [ "$(git log -1 --format=%s)" = "release $stamp" ] &&
    [ "$(git log -1 --format='%ct %at')" = "$(epoch $stamp) $(epoch $stamp)" ] &&
    [ "$(field release/release.json stamp)" = $stamp ] &&
    [ "$(python3 -c 'import json; print(json.load(open("pins/pins.json"))["widget"]["rev"])')" = "$widgetA" ] &&
    [ -z "$(git status --porcelain)" ] && [ "$(git diff --name-only HEAD~1 | sort | tr '\n' ' ')" = "pins/pins.json release/release.json " ]; then
    ok "a release at a date: one commit at the stamp's time, the pins moved and release.json in it"
else
    bad "a release at a date"; sed 's/^/    /' "$tmp/cut1.out"
fi

password=$(field release/release.json password)
hash=$(field release/release.json hash)
if [[ $password =~ ^[A-HJ-NP-Za-km-z2-9]{16}$ ]] && [[ $hash == \$* ]] &&
    perl -e 'exit(crypt($ARGV[0], $ARGV[1]) eq $ARGV[1] ? 0 : 1)' "$password" "$hash"; then
    ok "release.json: a password of 16 letters and digits, and its hash (cryptpass's)"
else
    bad "release.json's password and hash: '$password' '$hash'"
fi

if [ "$(identity kind)" = '"release"' ] && [ "$(identity stamp)" = "\"$stamp\"" ] &&
    [ "$(identity release.hash)" = "\"$hash\"" ]; then
    ok "identity.nix: a release, the stamp, the hash"
else
    bad "identity.nix: $(identity kind) $(identity stamp)"
fi

if refused again --stamp 20261001 && grep -q 'after the last release' "$tmp/again.err" &&
    refused future --stamp 29991231 && grep -q 'future' "$tmp/future.err" &&
    refused shape --stamp 2026-10-02 && grep -q 'YYYYMMDD' "$tmp/shape.err"; then
    ok "refused: the last release's date again, a future date, a stamp not a stamp"
else
    bad "refusals of stamps"
fi

echo more >>pins/sources.json
if refused dirty --keep-pins && grep -q 'not clean' "$tmp/dirty.err"; then
    ok "refused: a changed tracked file"
else
    bad "a changed tracked file"
fi
git checkout -q pins/sources.json

# a commit after the release (now), then a stamp before it
echo x >x && git add x && git commit -q -m x
if refused early --stamp "$(python3 -c 'import time; print(time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(time.time() - 3600)))')" &&
    grep -q "HEAD's commit" "$tmp/early.err"; then
    ok "refused: a stamp before HEAD's commit"
else
    bad "a stamp before HEAD's commit"
fi

# the default stamp (now), keeping the pins although the branch has moved
(cd "$tmp/widget" && echo v >>w && git commit -q -am v && git push -q "$tmp/gh/acme/widget.git" main)
pins=$(cat pins/pins.json)
before=$(date -u +%Y%m%d)
if bash release/cut.sh --keep-pins >"$tmp/cut2.out" 2>&1 && s=$(field release/release.json stamp) &&
    [[ $s =~ ^[0-9]{8}T[0-9]{6}Z$ ]] && { [ "${s:0:8}" = "$before" ] || [ "${s:0:8}" = "$(date -u +%Y%m%d)" ]; } &&
    [ "$(cat pins/pins.json)" = "$pins" ] && [ "$(field release/release.json password)" != "$password" ] &&
    [ "$(identity kind)" = '"release"' ] && [ "$(git diff --name-only HEAD~1)" = release/release.json ]; then
    ok "the default stamp (now), --keep-pins: the pins as they were, a new password"
else
    bad "the default stamp, --keep-pins"; sed 's/^/    /' "$tmp/cut2.out"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
