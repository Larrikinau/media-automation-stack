#!/usr/bin/env bash
set -euo pipefail
LOG="$HOME/cleanup-radarr.log"

EVENT="${radarr_eventtype:-}"
CLIENT="${radarr_download_client:-}"

# Locate the folder Radarr imported from
SRC_PATH="${radarr_moviefile_sourcefolder:-}"
[[ -z $SRC_PATH ]] && SRC_PATH="$(dirname "${radarr_moviefile_sourcepath:-}")"
[[ -z $SRC_PATH ]] && SRC_PATH="${radarr_movie_path:-}"

printf '%s  EVENT=%s  CLIENT=%s  SRC=%s\n' \
        "$(date '+%F %T')" "$EVENT" "$CLIENT" "$SRC_PATH" >> "$LOG"

# Only act on qBittorrent import events
[[ $CLIENT == qBittorrent ]] || { echo "$(date '+%F %T') skip – client=$CLIENT" >> "$LOG"; exit 0; }
[[ $EVENT  == Download || $EVENT == DownloadFolderImported ]] || { echo "$(date '+%F %T') skip – event=$EVENT" >> "$LOG"; exit 0; }
[[ -n $SRC_PATH ]] || { echo "$(date '+%F %T') WARN – empty SRC_PATH" >> "$LOG"; exit 0; }

# Delete only within incomingmovies (any case)
case "$SRC_PATH" in
  /tank/[Ii]ncoming[Mm]ovies/*)
        echo "$(date '+%F %T') rm -rf $SRC_PATH" >> "$LOG"
        rm -rf --one-file-system "$SRC_PATH"
        ;;
  *)
        echo "$(date '+%F %T') WARN – outside staging tree ($SRC_PATH)" >> "$LOG"
        ;;
esac
