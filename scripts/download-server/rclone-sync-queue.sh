#!/usr/bin/env bash
# Limit rclone-sync.sh to 6 parallel runs with separate RAR extraction queue
set -euo pipefail

LOCKDIR="$HOME/.rclone-sync.locks"
RAR_LOCKDIR="$HOME/.rclone-rar.locks"
mkdir -p "$LOCKDIR" "$RAR_LOCKDIR"

DEBUG_LOG="$HOME/rclone-debug.log"
echo "$(date +'%F %T') QUEUE: Attempting to acquire slot for \"$1\" label=\"$2\"" >> "$DEBUG_LOG"

# Check if this is likely a large RAR file by examining the source
raw="$1"
if [[ -f $raw ]]; then
  src_dir="$(dirname "$raw")"
else
  src_dir="$raw"
fi

# Check for RAR files and estimate if this will be a large extraction
is_rar_job=false
if find "$src_dir" -name "*.rar" -print -quit | grep -q .; then
  # Calculate total RAR size to determine if this is a "large" job
  total_rar_size=$(find "$src_dir" -name "*.r[0-9]*" -o -name "*.rar" | xargs du -cb 2>/dev/null | tail -1 | cut -f1 || echo "0")
  # If total RAR size > 2GB, treat as large job (needs RAR slot)
  if [[ $total_rar_size -gt 2147483648 ]]; then
    is_rar_job=true
    echo "$(date +'%F %T') QUEUE: Large RAR detected (${total_rar_size} bytes), using RAR queue" >> "$DEBUG_LOG"
  fi
fi

# Try to acquire appropriate slot type
if [[ "$is_rar_job" == "true" ]]; then
  # Large RAR jobs: limit to 2 concurrent extractions to prevent resource exhaustion
  echo "$(date +'%F %T') QUEUE: Attempting RAR slot acquisition" >> "$DEBUG_LOG"
  while true; do
    for n in 1 2; do
      RAR_SLOT="$RAR_LOCKDIR/rar_slot$n"
      exec 8>"$RAR_SLOT"
      if flock -n 8; then
        echo "$(date +'%F %T') QUEUE: Acquired RAR slot $n" >> "$DEBUG_LOG"
        # Also need a regular slot for the upload phase
        for m in 1 2 3 4 5 6; do
          SLOT="$LOCKDIR/slot$m"
          exec 9>"$SLOT"
          if flock -n 9; then
            echo "$(date +'%F %T') QUEUE: Acquired regular slot $m for RAR job" >> "$DEBUG_LOG"
            ./rclone-sync.sh "$1" "$2"
            STATUS=$?
            flock -u 9
            flock -u 8
            echo "$(date +'%F %T') QUEUE: Released RAR slot $n and regular slot $m" >> "$DEBUG_LOG"
            exit $STATUS
          fi
          exec 9>&-
        done
        # Couldn't get regular slot, release RAR slot and try again
        flock -u 8
        exec 8>&-
        break
      fi
      exec 8>&-
    done
    echo "$(date +'%F %T') QUEUE: All RAR slots busy, waiting..." >> "$DEBUG_LOG"
    sleep 10  # Wait longer for RAR jobs
  done
else
  # Regular jobs: use normal 6-slot queue
  echo "$(date +'%F %T') QUEUE: Attempting regular slot acquisition" >> "$DEBUG_LOG"
  while true; do
    for n in 1 2 3 4 5 6; do
      SLOT="$LOCKDIR/slot$n"
      exec 9>"$SLOT"
      if flock -n 9; then
        echo "$(date +'%F %T') QUEUE: Acquired regular slot $n" >> "$DEBUG_LOG"
        ./rclone-sync.sh "$1" "$2"
        STATUS=$?
        flock -u 9
        echo "$(date +'%F %T') QUEUE: Released regular slot $n" >> "$DEBUG_LOG"
        exit $STATUS
      fi
      exec 9>&-
    done
    echo "$(date +'%F %T') QUEUE: All regular slots busy, waiting..." >> "$DEBUG_LOG"
    sleep 5
  done
fi
