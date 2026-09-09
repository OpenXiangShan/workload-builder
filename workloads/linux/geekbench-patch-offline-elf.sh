#!/usr/bin/env bash
set -euo pipefail

binary="${1:?usage: $0 BINARY}"

before=$( (LC_ALL=C grep -aob -- 'https://' "$binary" || true) | wc -l)
if [ "$before" -eq 0 ]; then
    echo "offline patch: no HTTPS endpoint found in $binary" >&2
    exit 1
fi

# Keep the URL length unchanged so all surrounding ELF offsets remain valid.
# `http://a` has the same eight bytes as `https://` and remains a valid URL.
perl -0pi -e 's#https://#http://a#g' "$binary"

after=$( (LC_ALL=C grep -aob -- 'https://' "$binary" || true) | wc -l)
if [ "$after" -ne 0 ]; then
    echo "offline patch: HTTPS endpoints remain in $binary" >&2
    exit 1
fi

exit 0
