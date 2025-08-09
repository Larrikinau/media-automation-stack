#!/usr/bin/env bash
# Automated manual import for Radarr - scans incoming directory only
# This script uses DownloadedMoviesScan to process completed downloads
# without scanning the entire movie library
set -euo pipefail

RADARR_API_URL="http://localhost:7878/api/v3"
RADARR_API_KEY="YOUR_RADARR_API_KEY_HERE"
INCOMING_DIR="/tank/incomingmovies"
LOG_FILE="$HOME/radarr-manual-import.log"

echo "$(date +'%F %T') Starting DownloadedMoviesScan for incoming directory" >> "$LOG_FILE"

# Check if there are any directories in incoming
dir_count=$(find "$INCOMING_DIR" -maxdepth 1 -type d -name "*" ! -name "incomingmovies" | wc -l)
if [ "$dir_count" -eq 0 ]; then
    echo "$(date +'%F %T') No directories found in incoming" >> "$LOG_FILE"
    exit 0
fi

echo "$(date +'%F %T') Found $dir_count directories to process" >> "$LOG_FILE"

# Trigger DownloadedMoviesScan which specifically processes completed downloads
response=$(curl -s -X POST "$RADARR_API_URL/command" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $RADARR_API_KEY" \
    -d '{"name":"DownloadedMoviesScan","path":"'$INCOMING_DIR'"}' || echo "API_ERROR")

if [[ "$response" == "API_ERROR" ]]; then
    echo "$(date +'%F %T') ERROR: DownloadedMoviesScan API call failed" >> "$LOG_FILE"
else
    echo "$(date +'%F %T') SUCCESS: DownloadedMoviesScan triggered for $INCOMING_DIR" >> "$LOG_FILE"
fi

echo "$(date +'%F %T') Manual import scan complete" >> "$LOG_FILE"
