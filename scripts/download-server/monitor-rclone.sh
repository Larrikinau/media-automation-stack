#!/usr/bin/env bash
# Monitor rclone sync operations and queue status
set -euo pipefail

LOCKDIR="$HOME/.rclone-sync.locks"
RAR_LOCKDIR="$HOME/.rclone-rar.locks"
DEBUG_LOG="$HOME/rclone-debug.log"

echo "=== RCLONE SYNC MONITOR ===" 
echo "Time: $(date)"
echo

# Check active processes
echo "=== ACTIVE RCLONE PROCESSES ==="
if pgrep -f "rclone-sync" > /dev/null; then
    echo "Active rclone-sync processes:"
    ps aux | grep -E "rclone-sync|rclone.*copy|rclone.*move" | grep -v grep | while read line; do
        echo "  $line"
    done
else
    echo "No active rclone-sync processes"
fi
echo

# Check slot usage
echo "=== QUEUE SLOT STATUS ==="
mkdir -p "$LOCKDIR" "$RAR_LOCKDIR"

echo "Regular slots:"
for n in 1 2 3 4 5 6; do
    SLOT="$LOCKDIR/slot$n"
    if flock -n "$SLOT" -c "true" 2>/dev/null; then
        echo "  Slot $n: AVAILABLE"
    else
        echo "  Slot $n: BUSY"
    fi
done

echo
echo "RAR extraction slots:"
for n in 1 2; do
    RAR_SLOT="$RAR_LOCKDIR/rar_slot$n"
    if flock -n "$RAR_SLOT" -c "true" 2>/dev/null; then
        echo "  RAR Slot $n: AVAILABLE"
    else
        echo "  RAR Slot $n: BUSY"
    fi
done
echo

# Check staging directories on media server (if accessible)
echo "=== STAGING DIRECTORY STATUS ==="
RCLONE="$HOME/bin/rclone"
RCLONE_CFG="$HOME/.config/rclone/rclone.conf"

if [[ -f "$RCLONE" && -f "$RCLONE_CFG" ]]; then
    echo "Checking staging directories..."
    
    echo "TV Shows staging:"
    if "$RCLONE" --config "$RCLONE_CFG" lsd "MEDIA_SERVER:/tank/IncomingTV_staging/" 2>/dev/null | head -10; then
        :
    else
        echo "  (empty or inaccessible)"
    fi
    
    echo
    echo "Movies staging:"
    if "$RCLONE" --config "$RCLONE_CFG" lsd "MEDIA_SERVER:/tank/IncomingMovies_staging/" 2>/dev/null | head -10; then
        :
    else
        echo "  (empty or inaccessible)"
    fi
else
    echo "rclone not configured - cannot check staging directories"
fi
echo

# Show recent debug log entries
echo "=== RECENT DEBUG LOG (last 20 lines) ==="
if [[ -f "$DEBUG_LOG" ]]; then
    tail -20 "$DEBUG_LOG"
else
    echo "No debug log found at $DEBUG_LOG"
fi
echo

# Show summary of operations in progress
echo "=== OPERATIONS IN PROGRESS ==="
if [[ -f "$DEBUG_LOG" ]]; then
    echo "Recent operations:"
    grep -E "(EXTRACTING|COPY|MOVETO)" "$DEBUG_LOG" | tail -10 | while read line; do
        echo "  $line"
    done
    
    echo
    echo "Queued operations waiting for slots:"
    grep "waiting..." "$DEBUG_LOG" | tail -5 | while read line; do
        echo "  $line"
    done
else
    echo "No debug log available"
fi

echo
echo "=== END MONITOR ==="
