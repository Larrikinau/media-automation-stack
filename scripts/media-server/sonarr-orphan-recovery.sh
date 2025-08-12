#!/usr/bin/env bash
# Smart Orphan Recovery for Sonarr
# Detects orphaned TV shows in incoming directory and automatically re-adds them to Sonarr
# Handles cases where shows were removed from Sonarr but files still arrive later
set -euo pipefail

SONARR_API_URL="http://localhost:8989/api/v3"
SONARR_API_KEY="YOUR_SONARR_API_KEY_HERE"
TVDB_API_KEY="YOUR_TVDB_API_KEY_HERE"
INCOMING_DIR="/tank/IncomingTV"
LOG_FILE="$HOME/sonarr-orphan-recovery.log"

echo "$(date +'%F %T') Starting TV show orphan recovery scan" >> "$LOG_FILE"

# Check if incoming directory exists and has content
if [[ ! -d "$INCOMING_DIR" ]]; then
    echo "$(date +'%F %T') Incoming directory does not exist: $INCOMING_DIR" >> "$LOG_FILE"
    exit 0
fi

orphan_count=0

# Process each directory in incoming
find "$INCOMING_DIR" -maxdepth 1 -type d -name "*" ! -name "IncomingTV" | while read -r dir; do
    dir_name=$(basename "$dir")
    echo "$(date +'%F %T') Checking: $dir_name" >> "$LOG_FILE"
    
    # Check if any media files exist
    if ! find "$dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -print -quit | grep -q .; then
        echo "$(date +'%F %T') SKIP: No media files in $dir_name" >> "$LOG_FILE"
        continue
    fi
    
    # Extract potential show title from directory name
    # Remove common release patterns and episode info
    clean_title=$(echo "$dir_name" | sed -E 's/\.(S[0-9]+E[0-9]+).*//i' | sed -E 's/\.(720p|1080p|2160p|4K).*//i' | sed -E 's/\.(x264|x265|HEVC|H264).*//i' | sed -E 's/\.(WEBRip|HDTV|BluRay).*//i' | sed -E 's/-[A-Z0-9]+$//i' | tr '.' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    
    # Try to extract year if present
    year=""
    if [[ "$clean_title" =~ ([0-9]{4}) ]]; then
        year="${BASH_REMATCH[1]}"
        # Remove year from title for better search
        clean_title=$(echo "$clean_title" | sed "s/$year//g" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    fi
    
    echo "$(date +'%F %T') Extracted show title: '$clean_title' year: '$year'" >> "$LOG_FILE"
    
    # Check if this show already exists in Sonarr
    search_query=$(echo "$clean_title" | sed 's/ /%20/g')
    existing_series=$(curl -s "$SONARR_API_URL/series" -H "X-Api-Key: $SONARR_API_KEY")
    
    if echo "$existing_series" | jq -e --arg title "$clean_title" '.[] | select(.title | test($title; "i"))' > /dev/null 2>&1; then
        echo "$(date +'%F %T') EXISTS: '$clean_title' already in Sonarr" >> "$LOG_FILE"
        continue
    fi
    
    echo "$(date +'%F %T') ORPHAN: '$clean_title' not found in Sonarr, searching via Sonarr lookup..." >> "$LOG_FILE"
    
    # Use Sonarr's built-in series lookup (which uses TVDB/TMDB)
    lookup_results=$(curl -s "$SONARR_API_URL/series/lookup?term=$search_query" -H "X-Api-Key: $SONARR_API_KEY")
    
    if [[ $(echo "$lookup_results" | jq length) -gt 0 ]]; then
        # Get the first result (most likely match)
        series_data=$(echo "$lookup_results" | jq '.[0]')
        tvdb_id=$(echo "$series_data" | jq -r '.tvdbId')
        series_title=$(echo "$series_data" | jq -r '.title')
        first_aired=$(echo "$series_data" | jq -r '.firstAired')
        
        echo "$(date +'%F %T') FOUND: TVDB ID $tvdb_id - '$series_title' (first aired: $first_aired)" >> "$LOG_FILE"
        
        # Add series to Sonarr
        add_payload=$(echo "$series_data" | jq '. + {
            "qualityProfileId": 1,
            "monitored": true,
            "rootFolderPath": "/tank/Media/TV Shows",
            "addOptions": {
                "searchForMissingEpisodes": false,
                "monitor": "all"
            },
            "seasonFolder": true
        }')
        
        add_response=$(curl -s -X POST "$SONARR_API_URL/series" \
            -H "Content-Type: application/json" \
            -H "X-Api-Key: $SONARR_API_KEY" \
            -d "$add_payload")
        
        if echo "$add_response" | jq -e '.id' > /dev/null 2>&1; then
            echo "$(date +'%F %T') SUCCESS: Added '$series_title' to Sonarr" >> "$LOG_FILE"
            
            # Trigger immediate import scan for this series
            sleep 2
            curl -s -X POST "$SONARR_API_URL/command" \
                -H "Content-Type: application/json" \
                -H "X-Api-Key: $SONARR_API_KEY" \
                -d '{"name":"DownloadedEpisodesScan","path":"'$dir'"}' > /dev/null
            
            echo "$(date +'%F %T') TRIGGERED: Import scan for '$series_title'" >> "$LOG_FILE"
            ((orphan_count++))
        else
            echo "$(date +'%F %T') ERROR: Failed to add '$series_title' to Sonarr" >> "$LOG_FILE"
            echo "$(date +'%F %T') Response: $add_response" >> "$LOG_FILE"
        fi
    else
        echo "$(date +'%F %T') NOT_FOUND: No lookup match for '$clean_title'" >> "$LOG_FILE"
    fi
done

echo "$(date +'%F %T') TV show orphan recovery complete - recovered $orphan_count shows" >> "$LOG_FILE"
