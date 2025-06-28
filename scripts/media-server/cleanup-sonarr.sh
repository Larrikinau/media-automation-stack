#!/usr/bin/env bash
set -euo pipefail
LOG="$HOME/cleanup-sonarr.log"

EVENT="${sonarr_eventtype:-}"
CLIENT="${sonarr_download_client:-}"

# ── figure out where Sonarr imported FROM ────────────────────────────────
SRC_PATH="${sonarr_sourcepath:-}"
[[ -z $SRC_PATH ]] && SRC_PATH="${sonarr_download_path:-}"
[[ -z $SRC_PATH ]] && SRC_PATH="${sonarr_folder_path:-}"
[[ -z $SRC_PATH ]] && SRC_PATH="${sonarr_sourcefolder:-}"

printf '%s  EVENT=%s  CLIENT=%s  SRC=%s\n' \
        "$(date '+%F %T')" "$EVENT" "$CLIENT" "$SRC_PATH" >>"$LOG"

# ── act only on completed qBittorrent imports ────────────────────────────
[[ $CLIENT == qBittorrent ]] || { echo "$(date '+%F %T')  skip – client=$CLIENT" >>"$LOG"; exit 0; }
[[ $EVENT  == Download || $EVENT == DownloadFolderImported ]] \
  || { echo "$(date '+%F %T')  skip – event=$EVENT" >>"$LOG"; exit 0; }
[[ -n $SRC_PATH ]] || { echo "$(date '+%F %T')  WARN – empty SRC_PATH" >>"$LOG"; exit 0; }

# ── decide which folder to purge ─────────────────────────────────────────
if [[ -d $SRC_PATH ]]; then   # Sonarr v4 passes the folder itself
    leftover_dir="$SRC_PATH"
else                          # Sonarr v3 passed a file—go up one level
    leftover_dir="$(dirname "$SRC_PATH")"
fi

# ── delete only within staging trees ─────────────────────────────────────
case "$leftover_dir" in
    /tank/IncomingTV/*|/tank/IncomingMovies/*)
        echo "$(date '+%F %T')  rm -rf $leftover_dir" >>"$LOG"
        rm -rf --one-file-system "$leftover_dir"
        ;;
    *)
        echo "$(date '+%F %T')  WARN – outside staging tree ($leftover_dir)" >>"$LOG"
        ;;
esac
