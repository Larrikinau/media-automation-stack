# Troubleshooting Guide

This guide covers common issues and their solutions for the media automation stack.

## Quick Diagnostics

### Check System Status

```bash
# Check if all Docker services are running
docker ps

# Check staging directories (should be empty when working properly)
find /tank/IncomingTV/ /tank/IncomingTV_staging/ /tank/incomingmovies/ /tank/IncomingMovies_staging/ -type f | wc -l

# Check recent rclone logs
tail -20 ~/rclone-debug.log

# Check cleanup script logs
tail -20 ~/cleanup-sonarr.log
tail -20 ~/cleanup-radarr.log
```

### Check Disk Space

```bash
# Check overall disk usage
df -h /tank/

# Check inode usage (can cause issues even with free space)
df -i /tank/

# Check ZFS pool status (if using ZFS)
zpool status
```

## Common Issues

### 1. Files Not Uploading from Download Server

**Symptoms:**
- Downloads complete but never appear on media server
- rclone logs show connection errors

**Diagnosis:**
```bash
# Test rclone connection manually
rclone lsd MEDIA_SERVER:/tank/

# Check SSH connectivity
ssh username@media-server "ls -la /tank/"

# Check if queue is working
ls -la ~/.rclone-sync.locks/
```

**Solutions:**

1. **SSH Connection Issues:**
   ```bash
   # Re-configure rclone connection
   rclone config
   
   # Test with verbose output
   rclone -v lsd MEDIA_SERVER:/tank/
   ```

2. **Queue Lock Issues:**
   ```bash
   # Clear stuck locks
   rm -f ~/.rclone-sync.locks/slot*
   ```

3. **Script Permissions:**
   ```bash
   # Fix script permissions
   chmod +x ~/rclone-sync-queue.sh ~/rclone-sync.sh
   ```

### 2. qBittorrent Not Triggering Scripts

**Symptoms:**
- Torrents complete but scripts never run
- No entries in rclone-debug.log

**Diagnosis:**
```bash
# Check qBittorrent configuration
# Access web UI and verify "Run external program" is enabled

# Test script manually
./rclone-sync-queue.sh "/path/to/test/file" "TV Shows"
```

**Solutions:**

1. **Verify qBittorrent Configuration:**
   - External program: `/full/path/to/rclone-sync-queue.sh "%F" "%L"`
   - Make sure path is absolute, not relative

2. **Check Script Paths:**
   ```bash
   # Verify script locations
   which rclone-sync-queue.sh
   ls -la ~/rclone-sync-queue.sh
   ```

3. **Test with Simple Script:**
   ```bash
   # Create test script for debugging
   echo '#!/bin/bash' > ~/test-trigger.sh
   echo 'echo "$(date): $1 $2" >> ~/trigger-test.log' >> ~/test-trigger.sh
   chmod +x ~/test-trigger.sh
   ```

### 3. RAR Extraction Failures

**Symptoms:**
- Files upload but remain compressed
- Extraction errors in logs

**Diagnosis:**
```bash
# Check if unrar is installed
which unrar

# Test extraction manually
cd /path/to/rar/files
unrar t filename.rar  # Test archive
unrar e filename.rar  # Extract
```

**Solutions:**

1. **Install/Update unrar:**
   ```bash
   sudo apt update
   sudo apt install unrar-free
   # or for non-free version:
   sudo apt install unrar
   ```

2. **Check File Permissions:**
   ```bash
   # Ensure write permissions in download directory
   chmod 755 ~/downloads/qbittorrent/
   ```

3. **Multi-part RAR Issues:**
   - Script automatically detects main RAR file
   - Ensure all parts (.rar, .r00, .r01, etc.) are present

### 4. Sonarr/Radarr Not Importing Files

**Symptoms:**
- Files appear in staging directories but aren't imported
- Import errors in Sonarr/Radarr logs

**Diagnosis:**
```bash
# Check if services are running
docker ps | grep -E "sonarr|radarr"

# Check service logs
docker logs sonarr
docker logs radarr

# Check if monitoring folders are configured correctly
# Access Sonarr/Radarr web UI and verify root folders
```

**Solutions:**

1. **Verify Folder Permissions:**
   ```bash
   # Ensure proper ownership
   sudo chown -R 1000:1000 /tank/
   chmod -R 755 /tank/
   ```

2. **Check Root Folders:**
   - Sonarr: Should monitor `/tank/IncomingTV/`
   - Radarr: Should monitor `/tank/incomingmovies/`

3. **Manual Import:**
   - Use "Manual Import" in Sonarr/Radarr web UI
   - Check for naming/quality issues

### 5. NZBGet Download Issues

**Symptoms:**
- Newsgroup downloads failing
- Authentication errors

**Diagnosis:**
```bash
# Check NZBGet logs
docker logs nzbget

# Verify server configuration in web UI
# Test server connections in NZBGet settings
```

**Solutions:**

1. **Server Configuration:**
   - Verify newsgroup server credentials
   - Check SSL settings and ports
   - Test connection in NZBGet settings

2. **Network Issues:**
   ```bash
   # Test connectivity to newsgroup servers
   telnet news.server.com 563
   ```

### 6. High CPU/Memory Usage

**Symptoms:**
- System becoming slow or unresponsive
- Multiple rclone processes running

**Diagnosis:**
```bash
# Check running processes
ps aux | grep rclone
htop  # or top for process monitoring

# Check queue status
ls -la ~/.rclone-sync.locks/
```

**Solutions:**

1. **Queue Management:**
   ```bash
   # Kill stuck rclone processes
   pkill rclone
   
   # Clear locks
   rm -f ~/.rclone-sync.locks/slot*
   ```

2. **Optimize rclone Settings:**
   - Reduce `--transfers` and `--checkers` values
   - Adjust `--buffer-size` based on available RAM

### 7. Storage Performance Issues

**Symptoms:**
- Slow file transfers
- High disk I/O wait times

**Diagnosis:**
```bash
# Check I/O statistics
iostat -x 1

# Check ZFS ARC usage (if using ZFS)
cat /proc/spl/kstat/zfs/arcstats

# Check disk usage and fragmentation
df -h
zpool list
```

**Solutions:**

1. **ZFS Optimization:**
   ```bash
   # Adjust ARC size if needed
   echo $((8 * 1024 * 1024 * 1024)) > /sys/module/zfs/parameters/zfs_arc_max
   ```

2. **Reduce Concurrent Operations:**
   - Lower rclone transfer limits in scripts
   - Reduce queue size from 4 to 2 concurrent operations

## Log Analysis

### Key Log Files

1. **Download Server:**
   - `~/rclone-debug.log` - Main processing log
   - `~/rclone-sync.log` - Detailed rclone operations
   - `/var/log/syslog` - System logs

2. **Media Server:**
   - `~/cleanup-sonarr.log` - Sonarr cleanup operations
   - `~/cleanup-radarr.log` - Radarr cleanup operations
   - Docker container logs: `docker logs <container_name>`

### Log Patterns to Look For

**Success Patterns:**
```
INVOKE: raw_input="/path/file" label="TV Shows"
RESOLVED src="/path/to/content"
COPY /path/src → MEDIA_SERVER:/tank/staging
MOVETO staging → live
DONE /tank/IncomingTV/content
```

**Error Patterns:**
```
ERROR: connection failed
WARN - outside staging tree
skip – unknown label
RAR extraction failed
```

## Performance Optimization

### rclone Tuning

For slow networks:
```bash
# Reduce concurrency
--transfers 4 --checkers 8 --multi-thread-streams 4
```

For fast networks:
```bash
# Increase concurrency
--transfers 16 --checkers 32 --multi-thread-streams 8
```

### System Tuning

```bash
# Increase file descriptor limits
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Optimize SSH for rclone
echo "MaxSessions 100" >> /etc/ssh/sshd_config
echo "MaxStartups 100:30:200" >> /etc/ssh/sshd_config
```

## Getting Help

### Information to Gather

Before seeking help, collect:

1. **System Information:**
   ```bash
   uname -a
   docker --version
   rclone version
   ```

2. **Log Excerpts:**
   - Last 50 lines of relevant logs
   - Full error messages

3. **Configuration Details:**
   - Sanitized rclone config
   - Docker compose configuration
   - Service settings

### Community Resources

- [rclone Forum](https://forum.rclone.org/)
- [Sonarr Discord](https://discord.gg/M6BvZn5)
- [Radarr Discord](https://discord.gg/H6UfGKNw)
- [r/selfhosted](https://reddit.com/r/selfhosted)

Remember to sanitize any logs or configurations before sharing to remove sensitive information like IP addresses, usernames, and API keys.
