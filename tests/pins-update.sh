#!/usr/bin/env bash
#
# pins/update.sh against a local repository standing in for GitHub (PINS_URL_PREFIX), with its own sources.json and
# pins.json (PINS_DIR): a new pin, an unchanged branch, a moved branch, a name sources.json does not have, a
# submodule. The hash it
# writes is checked against the tree made by hand, with an executable, a symbolic link and a file .gitattributes
# keeps out of archives (export-ignore), as GitHub's archive leaves it out.
#
# usage: pins-update.sh (needs git, nix and python3 on PATH)

set -uo pipefail

top="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
# the tests run in $tmp/work: leave it first, as illumos' rm does not remove the current directory
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
nixHash() { nix --extra-experimental-features nix-command hash path --type sha256 "$1"; }
pin() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]])' "$tmp/pins/pins.json" "$@"; }

# the repository: acme/widget, branch main
git init -q --bare "$tmp/gh/acme/widget.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
echo widget >README
printf '#!/bin/sh\necho run\n' >run.sh && chmod +x run.sh
ln -s README link
echo secret >ignored
echo 'ignored export-ignore' >.gitattributes
git add -A && GIT_COMMITTER_DATE=@1700000000 git commit -q -m A
revA=$(git rev-parse HEAD)
git push -q "$tmp/gh/acme/widget.git" main

# the tree GitHub's archive of A has
mkdir "$tmp/treeA" && cp -a README run.sh link .gitattributes "$tmp/treeA/"
hashA=$(nixHash "$tmp/treeA")

mkdir "$tmp/pins"
cp "$top/pins/update.sh" "$tmp/pins/"
echo '{ "widget": { "owner": "acme", "repo": "widget", "branch": "main" } }' >"$tmp/pins/sources.json"
echo '{}' >"$tmp/pins/pins.json"
run() { PINS_DIR="$tmp/pins" PINS_URL_PREFIX="file://$tmp/gh" bash "$tmp/pins/update.sh" "$@"; }

if run widget >"$tmp/out1" 2>&1 && [ "$(pin widget rev)" = "$revA" ] && [ "$(pin widget date)" = 1700000000 ] &&
    [ "$(pin widget hash)" = "$hashA" ]; then
    ok "a new pin: rev, date (the commit's time) and hash (the archive's tree)"
else
    bad "a new pin"; sed 's/^/    /' "$tmp/out1"; cat "$tmp/pins/pins.json"
fi

cp "$tmp/pins/pins.json" "$tmp/before.json"
if run >"$tmp/out2" 2>&1 && cmp -s "$tmp/before.json" "$tmp/pins/pins.json" && grep -q "^widget: main at $revA, as pinned$" "$tmp/out2"; then
    ok "an unchanged branch leaves pins.json as it is"
else
    bad "an unchanged branch"; sed 's/^/    /' "$tmp/out2"
fi

echo more >>README && git commit -q -am B && revB=$(git rev-parse HEAD) && git push -q "$tmp/gh/acme/widget.git" main
if run widget >"$tmp/out3" 2>&1 && [ "$(pin widget rev)" = "$revB" ] && [ "$(pin widget hash)" != "$hashA" ] &&
    grep -q "^widget: main moved to $revB (from $revA)$" "$tmp/out3"; then
    ok "a moved branch is pinned at its new commit"
else
    bad "a moved branch"; sed 's/^/    /' "$tmp/out3"
fi

cp "$tmp/pins/pins.json" "$tmp/before.json"
if ! run gadget >"$tmp/out4" 2>&1 && grep -q "gadget" "$tmp/out4" && cmp -s "$tmp/before.json" "$tmp/pins/pins.json"; then
    ok "a name sources.json does not have fails and changes nothing"
else
    bad "an unknown name"; sed 's/^/    /' "$tmp/out4"
fi

# a submodule: acme/lib at sub/lib, which archives leave out (a gitlink), pinned with the pin at the commit the
# gitlink names, whatever lib's branch is at
git init -q --bare -b main "$tmp/gh/acme/lib.git"
git init -q -b main "$tmp/lib"
(cd "$tmp/lib" && echo lib >LIB && git add -A && git commit -q -m L && git push -q "$tmp/gh/acme/lib.git" main)
revL=$(git -C "$tmp/lib" rev-parse HEAD)
mkdir "$tmp/treeL" && cp "$tmp/lib/LIB" "$tmp/treeL/"
hashL=$(nixHash "$tmp/treeL")
git -c protocol.file.allow=always submodule -q add "file://$tmp/gh/acme/lib.git" sub/lib
git commit -q -m C && revC=$(git rev-parse HEAD) && git push -q "$tmp/gh/acme/widget.git" main
(cd "$tmp/lib" && echo later >>LIB && git commit -q -am L2 && git push -q "$tmp/gh/acme/lib.git" main)
sub() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["widget"]["submodules"]["sub/lib"][sys.argv[2]])' "$tmp/pins/pins.json" "$1"; }
if run widget >"$tmp/out5" 2>&1 && [ "$(pin widget rev)" = "$revC" ] && [ "$(sub url)" = "file://$tmp/gh/acme/lib.git" ] &&
    [ "$(sub rev)" = "$revL" ] && [ "$(sub hash)" = "$hashL" ]; then
    ok "a submodule is pinned with the pin: url, rev (the gitlink's) and hash (its archive's tree)"
else
    bad "a submodule"; sed 's/^/    /' "$tmp/out5"; cat "$tmp/pins/pins.json"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
