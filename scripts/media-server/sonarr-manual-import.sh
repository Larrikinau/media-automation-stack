#!/usr/bin/env bash
# Automated manual import for Sonarr - scans incoming TV directory only
# This script uses DownloadedEpisodesScan to process completed downloads
# without scanning the entire TV library
set -euo pipefail

SONARR_API_URL="http://localhost:8989/api/v3"
SONARR_API_KEY="YOUR_SONARR_API_KEY_HERE"
INCOMING_DIR="/tank/IncomingTV"
LOG_FILE="$HOME/sonarr-manual-import.log"

echo "$(date +'%F %T') Starting DownloadedEpisodesScan for incoming directory" >> "$LOG_FILE"

# Check if there are any directories in incoming
dir_count=$(find "$INCOMING_DIR" -maxdepth 1 -type d -name "*" ! -name "IncomingTV" | wc -l)
if [ "$dir_count" -eq 0 ]; then
    echo "$(date +'%F %T') No directories found in incoming" >> "$LOG_FILE"
    exit 0
fi

echo "$(date +'%F %T') Found $dir_count directories to process" >> "$LOG_FILE"

# Trigger DownloadedEpisodesScan which specifically processes completed downloads
response=$(curl -s -X POST "$SONARR_API_URL/command" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $SONARR_API_KEY" \
    -d '{"name":"DownloadedEpisodesScan","path":"'$INCOMING_DIR'"}' || echo "API_ERROR")

if [[ "$response" == "API_ERROR" ]]; then
    echo "$(date +'%F %T') ERROR: DownloadedEpisodesScan API call failed" >> "$LOG_FILE"
else
    echo "$(date +'%F %T') SUCCESS: DownloadedEpisodesScan triggered for $INCOMING_DIR" >> "$LOG_FILE"
fi

echo "$(date +'%F %T') Manual import scan complete" >> "$LOG_FILE"
