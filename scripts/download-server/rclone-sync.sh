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
  
  # Calculate total RAR archive size for monitoring
  total_rar_size=$(find "$src_dir" -name "*.r[0-9]*" -o -name "*.rar" | xargs du -cb 2>/dev/null | tail -1 | cut -f1 || echo "0")
  echo "$(date +'%F %T') RAR_SIZE: Total archive size ${total_rar_size} bytes" >> "$DEBUG_LOG"
  
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
    extraction_start=$(date +%s)
    echo "$(date +'%F %T') EXTRACTING: $main_rar (estimated size: $total_rar_size bytes)" >> "$DEBUG_LOG"
    
    # Extract to the same directory with better error handling and progress tracking
    cd "$src_dir"
    
    # Use timeout for very large files to prevent indefinite hangs
    extraction_timeout=7200  # 2 hours max
    if [[ $total_rar_size -gt 10737418240 ]]; then  # >10GB
      extraction_timeout=14400  # 4 hours for very large files
    fi
    
    if timeout $extraction_timeout unrar e "$(basename "$main_rar")" >/dev/null 2>&1; then
      extraction_end=$(date +%s)
      extraction_time=$((extraction_end - extraction_start))
      echo "$(date +'%F %T') SUCCESS: RAR extraction completed in ${extraction_time}s" >> "$DEBUG_LOG"
      
      # Check if extraction produced media files
      media_files=()
      while IFS= read -r -d '' file; do
        media_files+=("$file")
      done < <(find "$src_dir" -maxdepth 1 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -print0)
      
      if [[ ${#media_files[@]} -gt 0 ]]; then
        echo "$(date +'%F %T') FOUND ${#media_files[@]} media file(s) after extraction" >> "$DEBUG_LOG"
        # List the media files found with sizes
        for file in "${media_files[@]}"; do
          file_size=$(stat -c%s "$file" 2>/dev/null || echo "unknown")
          echo "$(date +'%F %T') MEDIA: $(basename "$file") (${file_size} bytes)" >> "$DEBUG_LOG"
        done
      else
        echo "$(date +'%F %T') WARNING: No media files found after extraction" >> "$DEBUG_LOG"
      fi
    else
      extraction_end=$(date +%s)
      extraction_time=$((extraction_end - extraction_start))
      echo "$(date +'%F %T') ERROR: RAR extraction failed or timed out after ${extraction_time}s" >> "$DEBUG_LOG"
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
copy_start=$(date +%s)
echo "$(date +'%F %T') ➡️  COPY   $src_dir → $dst_stage" >> "$DEBUG_LOG"

# Adjust parameters based on file sizes and types
transfers=12
concurrency=96
buffer_size="256M"
timeout="10m"  # Increased from 5m
idle_timeout="10m"  # Increased from 5m

# For large extractions, reduce concurrency to prevent overwhelming the connection
if [[ "$rar_found" == true ]] && [[ $total_rar_size -gt 5368709120 ]]; then  # >5GB
  transfers=8
  concurrency=64
  timeout="20m"  # Much longer timeout for large files
  idle_timeout="15m"
  echo "$(date +'%F %T') NOTICE: Using reduced concurrency for large RAR content" >> "$DEBUG_LOG"
fi

if ! "$RCLONE" --config "$RCLONE_CFG" copy "$src_dir" "$dst_stage" \
    --transfers $transfers --multi-thread-streams 24 --multi-thread-cutoff 5M \
    --sftp-concurrency $concurrency --checkers 24 --sftp-use-fstat=false --use-mmap \
    --sftp-disable-hashcheck --buffer-size "$buffer_size" \
    --timeout "$timeout" --contimeout 2m --sftp-idle-timeout "$idle_timeout" \
    --retries 12 --retries-sleep 15s --low-level-retries 15 \
    "${exclude_args[@]}" \
    --ignore-checksum \
    --log-file "$HOME/rclone-sync.log" --log-level INFO; then
  
  copy_end=$(date +%s)
  copy_time=$((copy_end - copy_start))
  echo "$(date +'%F %T') ERROR: Copy to staging failed after ${copy_time}s" >> "$DEBUG_LOG"
  exit 1
fi

copy_end=$(date +%s)
copy_time=$((copy_end - copy_start))
echo "$(date +'%F %T') SUCCESS: Copy completed in ${copy_time}s" >> "$DEBUG_LOG"

# ── Fast server-side rename to live ─────────────────────────────────────────
move_start=$(date +%s)
echo "$(date +'%F %T') ➡️  MOVETO staging → live" >> "$DEBUG_LOG"

# Try moveto first (atomic rename if possible)
if "$RCLONE" --config "$RCLONE_CFG" moveto "$dst_stage" "$dst_live" \
    --timeout 5m --retries 5 --retries-sleep 10s \
    --log-file "$HOME/rclone-sync.log" --log-level INFO; then
  
  move_end=$(date +%s)
  move_time=$((move_end - move_start))
  echo "$(date +'%F %T') SUCCESS: moveto completed in ${move_time}s" >> "$DEBUG_LOG"
  
else
  
  echo "$(date +'%F %T') NOTICE: moveto failed – falling back to move" >> "$DEBUG_LOG"
  
  if "$RCLONE" --config "$RCLONE_CFG" move "$dst_stage/" "$dst_live" \
      --delete-empty-src-dirs \
      --timeout 10m --retries 8 --retries-sleep 15s \
      --log-file "$HOME/rclone-sync.log" --log-level INFO; then
    
    move_end=$(date +%s)
    move_time=$((move_end - move_start))
    echo "$(date +'%F %T') SUCCESS: move completed in ${move_time}s" >> "$DEBUG_LOG"
    
  else
    
    move_end=$(date +%s)
    move_time=$((move_end - move_start))
    echo "$(date +'%F %T') ERROR: Both moveto and move failed after ${move_time}s" >> "$DEBUG_LOG"
    
    # Check if files are still in staging
    if "$RCLONE" --config "$RCLONE_CFG" lsd "$dst_stage" >/dev/null 2>&1; then
      echo "$(date +'%F %T') WARNING: Files remain in staging directory" >> "$DEBUG_LOG"
    fi
    
    exit 1
  fi
fi

echo "$(date +'%F %T') 🎉 DONE  $dst_live" >> "$DEBUG_LOG"

# ── Cleanup extracted files (optional) ──────────────────────────────────────
# Uncomment the following lines if you want to delete extracted files after successful sync
# if [[ "$rar_found" == true ]]; then
#   echo "$(date +'%F %T') CLEANUP: Removing extracted files" >> "$DEBUG_LOG"
#   find "$src_dir" -maxdepth 1 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" \) -delete
# fi
