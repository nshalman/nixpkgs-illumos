#!/usr/bin/env bash
#
# release/cut.sh [--stamp YYYYMMDD | --stamp YYYYMMDDTHHMMSSZ] [--keep-pins] [NAME...]: cuts a release of the
# platform, as one commit of this checkout, which must be clean (nothing changed in tracked files):
#   - the pins moved to their branches' heads (../pins/update.sh, for the sources NAMEd, or all of them), unless
#     --keep-pins;
#   - release/release.json: the release's build stamp, and a root password (16 letters and digits, none easily
#     mistaken for another, as build-image makes one) with its hash, made here once (CRYPTPASS, default the platform's
#     /usr/lib/cryptpass, as build_live hashes it), so that every image of the release has the same /etc/shadow.
#     SmartOS publishes a build's root password beside it (SINGLE_USER_ROOT_PASSWORD.txt); it is no secret here.
# The commit is made at the stamp's time (author and committer), which is how the overlay's identity knows it for a
# release (pkgs/smartos-live/identity.nix): its images are stamped with it, the last digit the flavor's.
#
# The stamp is the date given (at midnight UTC) or the time given, or the time now; it may not be in the future (a
# build of a commit made after the release would be stamped before it), nor before HEAD's commit, nor at or before
# the last release's. Nothing is pushed.
#
# Needs git, nix and python3 on PATH, and to move the pins what pins/update.sh needs besides (a tar that reads
# standard input by default, e.g. GNU tar).

set -euo pipefail

top="$(cd "$(dirname "$0")/.." && pwd)"
cd "$top"

usage() {
    echo "usage: $0 [--stamp YYYYMMDD | --stamp YYYYMMDDTHHMMSSZ] [--keep-pins] [NAME...]" >&2
    exit 2
}
fail() {
    echo "release/cut.sh: $*" >&2
    exit 1
}

stamp= keep=
while [ $# -gt 0 ]; do
    case $1 in
        --stamp) [ $# -ge 2 ] || usage; stamp=$2; shift 2 ;;
        --keep-pins) keep=1; shift ;;
        -*) usage ;;
        *) break ;;
    esac
done

git diff --quiet HEAD -- || fail "the checkout is not clean: commit or put aside the changes to tracked files first"

case $stamp in
    "") stamp=$(date -u +%Y%m%dT%H%M%SZ) ;;
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) stamp=${stamp}T000000Z ;;
esac
[[ $stamp =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || fail "'$stamp' is not a build stamp: YYYYMMDD or YYYYMMDDTHHMMSSZ"
epoch=$(python3 -c 'import calendar, sys, time; print(calendar.timegm(time.strptime(sys.argv[1], "%Y%m%dT%H%M%SZ")))' "$stamp") ||
    fail "'$stamp' is not a time"
[ "$epoch" -le "$(date +%s)" ] || fail "$stamp is in the future"
[ "$epoch" -ge "$(git log -1 --format=%ct)" ] ||
    fail "$stamp is before HEAD's commit ($(git log -1 --format=%cd --date=iso-strict-local HEAD))"
if [ -f release/release.json ]; then
    last=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["stamp"])' release/release.json)
    [[ $stamp > $last ]] || fail "$stamp is not after the last release ($last)"
fi

pinned=
if [ -z "$keep" ]; then
    pinned=$(bash pins/update.sh "$@")
    echo "$pinned"
fi

# the password, as build-image makes one, and its hash
password=$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789')
password=${password:0:16}
[ ${#password} = 16 ] || fail "could not make a password"
hash=$("${CRYPTPASS:-/usr/lib/cryptpass}" "$password") || fail "could not hash the password"
[[ $hash == \$* ]] || fail "cryptpass gave '$hash', not a hash"

mkdir -p release
python3 -c '
import json, sys
json.dump({"stamp": sys.argv[2], "password": sys.argv[3], "hash": sys.argv[4]}, open(sys.argv[1], "w"), indent=2)
open(sys.argv[1], "a").write("\n")' release/release.json "$stamp" "$password" "$hash"

git add release/release.json pins/pins.json
{
    echo "release $stamp"
    if [ -n "$pinned" ]; then
        echo
        echo "$pinned"
    fi
} | GIT_AUTHOR_DATE="@$epoch +0000" GIT_COMMITTER_DATE="@$epoch +0000" git commit -q -F -

kind=$(nix-instantiate --eval --strict --json \
    -E "(import $top/pkgs/smartos-live/identity.nix { src = $top; }).kind" 2>/dev/null) || kind=
[ "$kind" = '"release"' ] || fail "committed $(git rev-parse --short HEAD), but the overlay's identity is $kind, not a release"
echo "release $stamp: $(git rev-parse --short HEAD) (not pushed); its root password is in release/release.json"
