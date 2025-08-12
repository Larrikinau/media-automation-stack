#!/usr/bin/env bash
# Smart Orphan Recovery for Radarr
# Detects orphaned movies in incoming directory and automatically re-adds them to Radarr
# Handles cases where movies were removed from Radarr but files still arrive later
set -euo pipefail

RADARR_API_URL="http://localhost:7878/api/v3"
RADARR_API_KEY="YOUR_RADARR_API_KEY_HERE"
TMDB_API_KEY="YOUR_TMDB_API_KEY_HERE"
INCOMING_DIR="/tank/incomingmovies"
LOG_FILE="$HOME/radarr-orphan-recovery.log"

echo "$(date +'%F %T') Starting orphan recovery scan" >> "$LOG_FILE"

# Check if incoming directory exists and has content
if [[ ! -d "$INCOMING_DIR" ]]; then
    echo "$(date +'%F %T') Incoming directory does not exist: $INCOMING_DIR" >> "$LOG_FILE"
    exit 0
fi

orphan_count=0

# Process each directory in incoming
find "$INCOMING_DIR" -maxdepth 1 -type d -name "*" ! -name "incomingmovies" | while read -r dir; do
    dir_name=$(basename "$dir")
    echo "$(date +'%F %T') Checking: $dir_name" >> "$LOG_FILE"
    
    # Check if any media files exist
    if ! find "$dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -print -quit | grep -q .; then
        echo "$(date +'%F %T') SKIP: No media files in $dir_name" >> "$LOG_FILE"
        continue
    fi
    
    # Extract potential movie title from directory name
    # Remove common release patterns to get cleaner title
    clean_title=$(echo "$dir_name" | sed -E 's/\.(720p|1080p|2160p|4K).*//i' | sed -E 's/\.(x264|x265|HEVC|H264).*//i' | sed -E 's/\.(BluRay|BRRip|WEBRip|HDTV).*//i' | sed -E 's/-[A-Z0-9]+$//i' | tr '.' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    
    # Try to extract year if present
    year=""
    if [[ "$clean_title" =~ ([0-9]{4}) ]]; then
        year="${BASH_REMATCH[1]}"
        # Remove year from title for better search
        clean_title=$(echo "$clean_title" | sed "s/$year//g" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    fi
    
    echo "$(date +'%F %T') Extracted title: '$clean_title' year: '$year'" >> "$LOG_FILE"
    
    # Check if this movie already exists in Radarr
    search_query=$(echo "$clean_title" | sed 's/ /%20/g')
    existing_movies=$(curl -s "$RADARR_API_URL/movie" -H "X-Api-Key: $RADARR_API_KEY")
    
    if echo "$existing_movies" | jq -e --arg title "$clean_title" '.[] | select(.title | test($title; "i"))' > /dev/null 2>&1; then
        echo "$(date +'%F %T') EXISTS: '$clean_title' already in Radarr" >> "$LOG_FILE"
        continue
    fi
    
    echo "$(date +'%F %T') ORPHAN: '$clean_title' not found in Radarr, searching TMDB..." >> "$LOG_FILE"
    
    # Search TMDB for the movie
    tmdb_search_url="https://api.themoviedb.org/3/search/movie?api_key=$TMDB_API_KEY&query=$search_query"
    if [[ -n "$year" ]]; then
        tmdb_search_url="$tmdb_search_url&year=$year"
    fi
    
    tmdb_results=$(curl -s "$tmdb_search_url")
    
    if [[ $(echo "$tmdb_results" | jq -r '.total_results') -gt 0 ]]; then
        # Get the first result (most likely match)
        tmdb_id=$(echo "$tmdb_results" | jq -r '.results[0].id')
        movie_title=$(echo "$tmdb_results" | jq -r '.results[0].title')
        release_year=$(echo "$tmdb_results" | jq -r '.results[0].release_date' | cut -d'-' -f1)
        
        echo "$(date +'%F %T') FOUND: TMDB ID $tmdb_id - '$movie_title' ($release_year)" >> "$LOG_FILE"
        
        # Add movie to Radarr
        add_payload=$(cat <<EOF
{
    "tmdbId": $tmdb_id,
    "title": "$movie_title",
    "qualityProfileId": 1,
    "monitored": true,
    "minimumAvailability": "announced",
    "rootFolderPath": "/tank/Media/Movies",
    "addOptions": {
        "searchForMovie": false,
        "monitor": "movieOnly"
    }
}
EOF
)
        
        add_response=$(curl -s -X POST "$RADARR_API_URL/movie" \
            -H "Content-Type: application/json" \
            -H "X-Api-Key: $RADARR_API_KEY" \
            -d "$add_payload")
        
        if echo "$add_response" | jq -e '.id' > /dev/null 2>&1; then
            echo "$(date +'%F %T') SUCCESS: Added '$movie_title' to Radarr" >> "$LOG_FILE"
            
            # Trigger immediate import scan for this movie
            sleep 2
            curl -s -X POST "$RADARR_API_URL/command" \
                -H "Content-Type: application/json" \
                -H "X-Api-Key: $RADARR_API_KEY" \
                -d '{"name":"DownloadedMoviesScan","path":"'$dir'"}' > /dev/null
            
            echo "$(date +'%F %T') TRIGGERED: Import scan for '$movie_title'" >> "$LOG_FILE"
            ((orphan_count++))
        else
            echo "$(date +'%F %T') ERROR: Failed to add '$movie_title' to Radarr" >> "$LOG_FILE"
            echo "$(date +'%F %T') Response: $add_response" >> "$LOG_FILE"
        fi
    else
        echo "$(date +'%F %T') NOT_FOUND: No TMDB match for '$clean_title'" >> "$LOG_FILE"
    fi
done

echo "$(date +'%F %T') Orphan recovery complete - recovered $orphan_count movies" >> "$LOG_FILE"
