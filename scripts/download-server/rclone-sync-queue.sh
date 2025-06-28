#!/usr/bin/env bash
# Limit rclone-sync.sh to 4 parallel runs, queueing any extras.
set -euo pipefail

LOCKDIR="$HOME/.rclone-sync.locks"
mkdir -p "$LOCKDIR"

# Try the four token files in order until we grab one.
while true; do
  for n in 1 2 3 4; do
    SLOT="$LOCKDIR/slot$n"
    exec 9>"$SLOT"               # create / open the slot file on FD 9
    if flock -n 9; then          # -n: non-blocking; succeeds if slot free
        ./rclone-sync.sh "$1" "$2"
        STATUS=$?
        flock -u 9               # release the token
        exit $STATUS
    fi
    exec 9>&-                    # close FD 9 before trying next slot
  done
  sleep 5                        # all slots busy — wait a moment, retry
done
