#!/bin/bash
#
# etc-release STAMP GITSTATUS: the platform's etc/release, as smartos-live's tools/build_etcrelease -v writes it: the
# build stamp and a year (theirs the year it runs in, here the build stamp's), followed by gitstatus.json.

set -euo pipefail

stamp=$1
printf '                     SmartOS %s x86_64\n' "$stamp"
printf '                    Copyright %s Edgecast Cloud LLC.\n' "${stamp:0:4}"
printf '\n  Built with the following components:\n\n'
cat "$2"
