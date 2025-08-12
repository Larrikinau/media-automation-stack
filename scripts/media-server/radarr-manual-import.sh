#!/usr/bin/env bash
# Enhanced Radarr manual import with smart cleanup
# Triggers import scan and cleans up empty or release-pattern directories
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

# List directories before processing for debugging
find "$INCOMING_DIR" -maxdepth 1 -type d -name "*" ! -name "incomingmovies" | while read -r dir; do
    echo "$(date +'%F %T') FOUND: $(basename "$dir")" >> "$LOG_FILE"
done

# Trigger DownloadedMoviesScan which specifically processes completed downloads
response=$(curl -s -X POST "$RADARR_API_URL/command" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $RADARR_API_KEY" \
    -d '{"name":"DownloadedMoviesScan","path":"'$INCOMING_DIR'"}' || echo "API_ERROR")

if [[ "$response" == "API_ERROR" ]]; then
    echo "$(date +'%F %T') ERROR: DownloadedMoviesScan API call failed" >> "$LOG_FILE"
    exit 1
else
    echo "$(date +'%F %T') SUCCESS: DownloadedMoviesScan triggered for $INCOMING_DIR" >> "$LOG_FILE"
fi

# Wait a moment for import to process
sleep 5

# Smart cleanup: Remove empty directories and release-pattern directories after import
echo "$(date +'%F %T') Starting smart cleanup of processed directories" >> "$LOG_FILE"

find "$INCOMING_DIR" -maxdepth 1 -type d -name "*" ! -name "incomingmovies" | while read -r dir; do
    dir_name=$(basename "$dir")
    
    # Check if directory is empty or contains only non-media files
    media_count=$(find "$dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) | wc -l)
    
    if [ "$media_count" -eq 0 ]; then
        # Directory has no media files - safe to remove if it matches release patterns
        if [[ "$dir_name" =~ ^.*\.(720p|1080p|2160p|4K)|.*\.(x264|x265|HEVC|H264)|.*\.(BluRay|BRRip|WEBRip|HDTV)|.*-[A-Z0-9]+$ ]]; then
            echo "$(date +'%F %T') CLEANUP: Removing release directory: $dir_name" >> "$LOG_FILE"
            rm -rf "$dir"
        elif [ -z "$(find "$dir" -type f)" ]; then
            # Completely empty directory
            echo "$(date +'%F %T') CLEANUP: Removing empty directory: $dir_name" >> "$LOG_FILE"
            rmdir "$dir" 2>/dev/null || true
        else
            echo "$(date +'%F %T') KEEP: Non-media files present in: $dir_name" >> "$LOG_FILE"
        fi
    else
        echo "$(date +'%F %T') KEEP: Media files still present in: $dir_name" >> "$LOG_FILE"
    fi
done

echo "$(date +'%F %T') Manual import scan and cleanup complete" >> "$LOG_FILE"
