#!/usr/bin/env bash
# Automated manual import for Radarr - handles long extraction timeouts
# This script automatically processes movies that appear in the incoming directory
# regardless of Radarr's download client timeout status
set -euo pipefail

RADARR_API_URL="http://localhost:7878/api/v3"
INCOMING_DIR="/tank/incomingmovies"
LOG_FILE="$HOME/radarr-manual-import.log"

echo "$(date +'%F %T') Starting manual import scan" >> "$LOG_FILE"

# Find directories in incoming that might contain completed movies
find "$INCOMING_DIR" -maxdepth 1 -type d -name "*" ! -name "incomingmovies" | while read -r movie_dir; do
    if [[ -z "$movie_dir" ]]; then
        continue
    fi
    
    # Check if directory contains video files
    if find "$movie_dir" -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" | grep -q .; then
        echo "$(date +'%F %T') Found video files in: $movie_dir" >> "$LOG_FILE"
        
        # Trigger Radarr manual import for this directory
        movie_name=$(basename "$movie_dir")
        echo "$(date +'%F %T') Triggering manual import for: $movie_name" >> "$LOG_FILE"
        
        # Use Radarr API to trigger a rescan that will find and import the files
        curl -s -X POST "$RADARR_API_URL/command" \
            -H "Content-Type: application/json" \
            -d '{"name":"RescanMovie"}' || true
            
        echo "$(date +'%F %T') Rescan command sent for: $movie_name" >> "$LOG_FILE"
    fi
done

echo "$(date +'%F %T') Manual import scan complete" >> "$LOG_FILE"
