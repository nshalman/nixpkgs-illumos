#!/usr/bin/env bash
# usage: heredoc-path.sh /path/to/bash ; reports whether a 5.8 kB here-document goes through a pipe or a temp file
B=$1; T=$(mktemp -d); trap 'rm -rf $T' EXIT
{ echo 'wc -c <<EOF'; i=0; while [ $i -lt 116 ]; do echo "0123456789012345678901234567890123456789012345678"; i=$((i+1)); done; echo EOF; } > $T/s.sh
truss -f -t pipe,write,open,openat,unlink,unlinkat -o $T/tr "$B" $T/s.sh > /dev/null 2>&1
big=$(/usr/bin/egrep 'write\([0-9]+, .*, (5[0-9]{3}|[6-9][0-9]{3})\)' $T/tr | head -1)
echo "  large write: ${big:-none}"
if /usr/bin/egrep -q 'sh-thd|/tmp/.*O_(RDWR|WRONLY).*O_(CREAT|EXCL)' $T/tr; then echo "  PATH: temp file  ($(/usr/bin/egrep -o '"[^"]*sh-thd[^"]*"' $T/tr | head -1))"; else echo "  PATH: pipe ($(/usr/bin/egrep -c '^[0-9]+:\s+pipe\(' $T/tr) pipe calls, no temp file)"; fi
