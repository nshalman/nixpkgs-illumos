#!/usr/bin/env bash
#
# ../pins/utc.nix, a time in seconds since 1970 as a UTC date, against GNU date for the same times: the stamp
# (YYYYMMDDTHHMMSSZ), the date (YYYY-MM-DD), the year and the month's name.
#
# usage: utc.sh   (needs nix-instantiate and GNU date on PATH)

set -uo pipefail

top="$(cd "$(dirname "$0")/.." && pwd)"

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

# the epoch; days around leap days and the ends of years and centuries; the pinned illumos-joyent commit's time
for t in 0 59 86399 86400 951782400 951868799 951868800 978307199 4107542399 4107542400 4102444799 \
         1789152667 1788374539 2147483647 4133980800 253402300799; do
    want="$(TZ=UTC LC_ALL=C date -d "@$t" '+%Y%m%dT%H%M%SZ %Y-%m-%d %Y %B')"
    if got=$(nix-instantiate --eval --strict --expr \
            "let u = import $top/pins/utc.nix $t; in \"\${u.stamp} \${u.date} \${toString u.year} \${u.monthName}\"" 2>&1); then
        got=${got#\"} got=${got%\"}
        if [ "$got" = "$want" ]; then
            ok "$t: $got"
        else
            bad "$t: utc.nix gives $got, date gives $want"
        fi
    else
        bad "$t: utc.nix does not evaluate: $got"
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
