#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# rclone-sync.sh — Download server to media server upload script with wrapper stripping,
# RAR extraction, and fast server-side move.  Strips out "Incoming TV Shows" 
# and "Incoming Movies" wrappers, extracts RAR archives if present, so only 
# the real media files are synced.
# ---------------------------------------------------------------------------

DEBUG_LOG="$HOME/rclone-debug.log"
echo "$(date +'%F %T') INVOKE: raw_input=\"$1\" label=\"$2\"" >> "$DEBUG_LOG"

raw="$1"              # %F from qBittorrent (first file in torrent)
label="$2"

# ── Resolve initial source directory ────────────────────────────────────────
if [[ -f $raw ]]; then
  src_dir="$(dirname "$raw")"
else
  src_dir="$raw"
fi
name="$(basename "$src_dir")"

# ── Strip generic "Incoming …" wrappers ────────────────────────────────────
if [[ "$name" == "Incoming TV Shows" || "$name" == "Incoming Movies" ]]; then
  echo "$(date +'%F %T') NOTICE: Wrapper \"$name\" detected – diving one level" >> "$DEBUG_LOG"
  child="$(find "$src_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
  if [[ -n "$child" ]]; then
    src_dir="$child"
    name="$(basename "$src_dir")"
  fi
fi
echo "$(date +'%F %T') RESOLVED src=\"$src_dir\"" >> "$DEBUG_LOG"

# ── Check for and extract RAR archives ─────────────────────────────────────
rar_found=false

# Check if any .rar files exist
rar_files=("$src_dir"/*.rar)
if [[ -f "${rar_files[0]}" ]]; then
  echo "$(date +'%F %T') NOTICE: RAR archive detected – extracting" >> "$DEBUG_LOG"
  rar_found=true
  
  # Find the main RAR file (usually .rar, not .r00, .r01, etc.)
  main_rar=""
  for rar_file in "${rar_files[@]}"; do
    if [[ "$rar_file" =~ \.rar$ ]] && [[ ! "$rar_file" =~ \.r[0-9]+$ ]]; then
      main_rar="$rar_file"
      break
    fi
  done
  
  # If no main .rar found, just use the first one
  if [[ -z "$main_rar" ]]; then
    main_rar="${rar_files[0]}"
  fi
  
  if [[ -f "$main_rar" ]]; then
    echo "$(date +'%F %T') EXTRACTING: $main_rar" >> "$DEBUG_LOG"
    
    # Extract to the same directory
    cd "$src_dir"
    if unrar e "$(basename "$main_rar")" >/dev/null 2>&1; then
      echo "$(date +'%F %T') SUCCESS: RAR extraction completed" >> "$DEBUG_LOG"
      
      # Check if extraction produced media files
      media_files=()
      while IFS= read -r -d '' file; do
        media_files+=("$file")
      done < <(find "$src_dir" -maxdepth 1 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -print0)
      
      if [[ ${#media_files[@]} -gt 0 ]]; then
        echo "$(date +'%F %T') FOUND ${#media_files[@]} media file(s) after extraction" >> "$DEBUG_LOG"
        # List the media files found
        for file in "${media_files[@]}"; do
          echo "$(date +'%F %T') MEDIA: $(basename "$file")" >> "$DEBUG_LOG"
        done
      else
        echo "$(date +'%F %T') WARNING: No media files found after extraction" >> "$DEBUG_LOG"
      fi
    else
      echo "$(date +'%F %T') ERROR: RAR extraction failed" >> "$DEBUG_LOG"
      rar_found=false
    fi
  else
    echo "$(date +'%F %T') ERROR: Main RAR file not found" >> "$DEBUG_LOG"
    rar_found=false
  fi
else
  echo "$(date +'%F %T') INFO: No RAR files detected" >> "$DEBUG_LOG"
fi

# ── rclone configuration ───────────────────────────────────────────────────
RCLONE="$HOME/bin/rclone"
RCLONE_CFG="$HOME/.config/rclone/rclone.conf"

case "$label" in
  "TV Shows"|"tv shows"|"tv-shows"|"tv"|"series")
    dst_stage="MEDIA_SERVER:/tank/IncomingTV_staging/$name"
    dst_live="MEDIA_SERVER:/tank/IncomingTV/$name"
    ;;
  "Movies"|"movies"|"movie"|"film")
    dst_stage="MEDIA_SERVER:/tank/IncomingMovies_staging/$name"
    dst_live="MEDIA_SERVER:/tank/incomingmovies/$name"
    ;;
  *)
    echo "⚠️  Unknown label \"$label\" — skipping" >&2
    echo "$(date +'%F %T') SKIP: unknown label" >> "$DEBUG_LOG"
    exit 0
    ;;
esac

# ── Prepare rclone exclude filters ─────────────────────────────────────────
exclude_args=("--exclude" "Screens/**")

# If we extracted from RAR, exclude the RAR files to save bandwidth
if [[ "$rar_found" == true ]]; then
  exclude_args+=(
    "--exclude" "*.rar" 
    "--exclude" "*.r[0-9]*" 
    "--exclude" "*.sfv" 
    "--exclude" "*.par2"
    "--exclude" "*.par"
  )
  echo "$(date +'%F %T') NOTICE: Excluding RAR files from sync" >> "$DEBUG_LOG"
fi

# ── Copy to staging ─────────────────────────────────────────────────────────
echo "$(date +'%F %T') ➡️  COPY   $src_dir → $dst_stage" >> "$DEBUG_LOG"
"$RCLONE" --config "$RCLONE_CFG" copy "$src_dir" "$dst_stage" \
    --transfers 12 --multi-thread-streams 24 --multi-thread-cutoff 5M \
    --sftp-concurrency 96 --checkers 24 --sftp-use-fstat=false --use-mmap \
    --sftp-disable-hashcheck --buffer-size 256M \
    --timeout 5m --contimeout 1m --sftp-idle-timeout 5m \
    --retries 8 --retries-sleep 10s --low-level-retries 10 \
    "${exclude_args[@]}" \
    --ignore-checksum \
    --log-file "$HOME/rclone-sync.log" --log-level INFO

# ── Fast server-side rename to live ─────────────────────────────────────────
echo "$(date +'%F %T') ➡️  MOVETO staging → live" >> "$DEBUG_LOG"
"$RCLONE" --config "$RCLONE_CFG" moveto "$dst_stage" "$dst_live" \
    --log-file "$HOME/rclone-sync.log" --log-level INFO || {
  echo "$(date +'%F %T') NOTICE: moveto failed – falling back to move" >> "$DEBUG_LOG"
  "$RCLONE" --config "$RCLONE_CFG" move "$dst_stage/" "$dst_live" \
      --delete-empty-src-dirs \
      --log-file "$HOME/rclone-sync.log" --log-level INFO
}

echo "$(date +'%F %T') 🎉 DONE  $dst_live" >> "$DEBUG_LOG"

# ── Cleanup extracted files (optional) ──────────────────────────────────────
# Uncomment the following lines if you want to delete extracted files after successful sync
# if [[ "$rar_found" == true ]]; then
#   echo "$(date +'%F %T') CLEANUP: Removing extracted files" >> "$DEBUG_LOG"
#   find "$src_dir" -maxdepth 1 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -delete
# fi
