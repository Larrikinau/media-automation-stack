# Large File Handling & RAR Extraction Issues

This guide addresses common issues with very large files (4K movies, 50GB+ torrents) and complex RAR archives that can take hours or days to extract.

## 🚨 The Problem: Radarr Timeout with Large RAR Files

### Symptoms
- Large 4K movies (40-100GB) download successfully
- RAR extraction takes 10+ hours (sometimes 24+ hours for 95+ part archives)
- Radarr shows "failed" download status
- Files eventually appear in `/tank/incomingmovies/` but are never processed
- Manual import required for completed files

### Root Cause
**Radarr timeout vs extraction reality**:
- **Radarr expects**: Downloads complete within hours
- **Reality**: Complex RAR extraction can take 24+ hours for very large files
- **Result**: Radarr gives up and marks download as "failed" while extraction is still running

## ✅ The Solution: Automated Import Recovery

This system provides a complete automated solution that handles even 24+ hour extractions without manual intervention.

### How It Works

1. **Torrent downloads** → **Long RAR extraction begins** (10-24+ hours)
2. **Radarr times out** and marks as "failed" (normal behavior)
3. **Extraction completes** → **rclone transfers files** → **Files arrive in `/tank/incomingmovies/`**
4. **Automated scanner runs** every 15 minutes checking for completed movies
5. **Radarr immediately imports** and moves files to final location

### Files Added to Your System

**Download Server (Remote)**:
```bash
# Enhanced rclone scripts with syntax fixes for large files
scripts/download-server/rclone-sync-queue.sh  # Fixed file size calculation
scripts/download-server/rclone-sync.sh        # Added Radarr trigger + fixes
```

**Media Server (Local)**:
```bash
# New automated import script
scripts/media-server/radarr-manual-import.sh  # Handles timeout recovery

# Cron job (automatically installed)
*/15 * * * * /home/USERNAME/radarr-manual-import.sh
```

## 🔧 Setup Instructions

### 1. Deploy Updated Scripts

**Download Server**:
```bash
# Copy the fixed scripts to your remote server
scp scripts/download-server/* user@download-server:~/
ssh user@download-server "chmod +x ~/*.sh"
```

**Media Server**:
```bash
# Copy the import automation script
scp scripts/media-server/radarr-manual-import.sh user@media-server:~/
ssh user@media-server "chmod +x ~/radarr-manual-import.sh"
```

### 2. Install Automated Import

```bash
# Add cron job for automated scanning every 15 minutes
ssh user@media-server
crontab -e

# Add this line:
*/15 * * * * /home/USERNAME/radarr-manual-import.sh
```

### 3. Update rclone Remote Name

Edit the rclone scripts to use your actual remote name:
```bash
# In rclone-sync.sh, replace MEDIA_SERVER with your actual rclone remote name
sed -i 's/MEDIA_SERVER/your_actual_remote_name/g' rclone-sync.sh
```

## 📊 Performance Expectations

### Normal Files (1-5GB)
- **RAR Extraction**: 10-120 seconds
- **Transfer**: 2-10 minutes  
- **Total Time**: \u003c15 minutes
- **Radarr Status**: ✅ Normal processing

### Large Files (20-50GB)
- **RAR Extraction**: 10-60 minutes
- **Transfer**: 10-30 minutes
- **Total Time**: 1-2 hours
- **Radarr Status**: ⚠️ May timeout but automation recovers

### Extreme Files (50GB+, 50+ RAR parts)
- **RAR Extraction**: 2-24+ hours
- **Transfer**: 30-60 minutes
- **Total Time**: 3-25+ hours  
- **Radarr Status**: ❌ Will timeout but automation handles completely

## 🐛 Troubleshooting

### Check if Automation is Working

```bash
# Check if import script is installed
crontab -l | grep radarr-manual-import

# Check recent log entries
tail -f ~/radarr-manual-import.log

# Manually trigger import scan
./radarr-manual-import.sh
```

### Check for Stuck Extractions

```bash
# On download server, check for running extractions
ssh download-server "ps aux | grep unrar"

# Check extraction logs
ssh download-server "tail -f ~/rclone-debug.log | grep EXTRACTING"
```

### Check Staging Directories

```bash
# Should be empty if system is working
find /tank/IncomingMovies_staging/ -name "*" | wc -l

# Check for files waiting to be imported
find /tank/incomingmovies/ -name "*.mkv" -o -name "*.mp4"
```

### Manual Recovery

If files are stuck in `/tank/incomingmovies/`:

```bash
# Trigger immediate import
~/radarr-manual-import.sh

# Or trigger Radarr rescan via API
curl -X POST "http://localhost:7878/api/v3/command" \
     -H "Content-Type: application/json" \
     -d '{"name":"RescanMovie"}'
```

## 📈 System Benefits

### Before Fix
- ❌ Large files failed automation
- ❌ Manual intervention required
- ❌ Inconsistent processing
- ❌ Files left in wrong directories

### After Fix  
- ✅ **Full automation** for any file size
- ✅ **No manual intervention** needed
- ✅ **Handles 24+ hour extractions**
- ✅ **Proper Radarr integration**
- ✅ **Correct file organization**

## 🎯 Best Practices

### For Ultra-Large Files (100GB+)
- Monitor disk space during extraction (files temporarily doubled)
- Consider upgrading download server CPU/RAM for faster extraction
- Ensure stable network connection for long transfers

### For Shared Seedboxes
- Be aware extraction may be slower due to resource sharing
- Consider extraction timeout limits on shared infrastructure
- Monitor for any provider-imposed limits

### Monitoring
- Check `~/radarr-manual-import.log` weekly for any issues
- Monitor staging directories to ensure they stay empty
- Review `~/rclone-debug.log` for extraction timing patterns

This solution provides **complete automation** for even the most extreme file sizes and complex RAR archives, ensuring your media automation works reliably regardless of extraction time.
