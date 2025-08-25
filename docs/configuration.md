# Configuration Guide

This document provides detailed configuration instructions for all components of the media automation stack.

## qBittorrent Configuration

### Basic Settings

1. **Web UI Access**
   ```
   Default Username: admin
   Default Password: adminadmin (change immediately!)
   Port: 8080
   ```

2. **Downloads Configuration**
   ```
   Default Save Path: /home/username/downloads/qbittorrent
   Keep incomplete torrents in: /home/username/downloads/qbittorrent/incomplete
   Copy .torrent files to: /home/username/downloads/qbittorrent/torrents
   Torrent content layout: Create subfolder (CRITICAL for rclone scripts)
   ```

   **IMPORTANT**: The "Torrent content layout" setting must be set to "Create subfolder" 
   for the automation scripts to work properly. This is found under:
   Tools → Options → Downloads → Torrent content layout

3. **Categories Setup**
   - Create "TV Shows" category
   - Create "Movies" category
   - Create other categories as needed

4. **External Program Configuration**
   ```
   Run external program on torrent completion: ✓
   Program: /full/path/to/rclone-sync-queue.sh "%F" "%L"
   ```

### Advanced Settings

1. **Connection Limits**
   ```
   Global maximum number of connections: 200
   Maximum number of connections per torrent: 100
   Global maximum number of upload slots: 20
   Maximum number of upload slots per torrent: 4
   ```

2. **Speed Limits**
   - Set according to your internet connection
   - Consider setting alternative limits for different times

3. **BitTorrent Protocol**
   ```
   Enable DHT: ✓
   Enable PeX: ✓
   Enable LSD: ✓
   Encryption mode: Prefer encryption
   ```

## rclone Configuration

The system uses a dual rclone setup: a dedicated SFTP server on the media server and an SFTP client on the download server.

### Media Server: rclone SFTP Server

**Service Configuration:**

The media server runs a dedicated rclone SFTP service on port 8222:

```bash
# Systemd service: rclone-serve-sftp.service
/usr/bin/rclone serve sftp /tank \
  --addr 0.0.0.0:8222 \
  --authorized-keys /home/mediauser/.ssh/authorized_keys \
  --umask 0002 \
  --filter-from /etc/rclone/sftp-allowlist.rules \
  --log-file /home/mediauser/rclone-sftp.log \
  --log-level INFO
```

**Directory Allowlist (/etc/rclone/sftp-allowlist.rules):**

```bash
# Allow only staging directories
+ /IncomingTV/**
+ /IncomingTV_staging/**
+ /incomingmovies/**
+ /IncomingMovies_staging/**
+ /IncomingTV/
+ /IncomingTV_staging/
+ /incomingmovies/
+ /IncomingMovies_staging/
- /**
```

**Log Rotation (/etc/logrotate.d/rclone-sftp):**

```bash
/home/mediauser/rclone-sftp.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    copytruncate
}
```

### Download Server: rclone SFTP Client

**Remote Configuration:**

```bash
rclone config
```

Configuration parameters:
```
Name: media_server_sftp (or MEDIA_SERVER)
Type: sftp
Host: your-media-server-ip-or-hostname
User: mediauser
Port: 8222  # Important: Use dedicated SFTP port
key_file: /home/downloaduser/.ssh/rclone-sftp
shell_type: unix
```

**Important Notes:**
- Use port **8222** (not 22) to connect to the dedicated rclone SFTP server
- Paths are relative to `/tank` (no `/tank` prefix needed in remote paths)
- SSH key authentication is required (no password option)

### Performance Tuning

Key parameters used in automation scripts:
```bash
--transfers 8                     # Number of parallel transfers
--checkers 16                     # File existence checkers
--sftp-concurrency 32             # SFTP concurrent operations
--sftp-disable-hashcheck          # Skip hash verification for speed
--size-only                       # Compare by size only (faster)
--retries 5                       # Number of retries
--low-level-retries 10            # Low-level retry attempts
--retries-sleep 5s                # Wait between retries
--sftp-set-modtime=false          # Don't set modification times
--bwlimit off                     # No bandwidth limiting
--fast-list                       # Faster directory listings
```

**Server-Side Performance:**
- Atomic server-side moves (moveto operations)
- No data transfer for staging-to-live promotion
- Optimized for concurrent connections (up to 96)
- Comprehensive logging with automatic rotation

Adjust client parameters based on your network capabilities and server performance.

## Sonarr Configuration

### Initial Setup

1. **Root Folders**
   ```
   Path: /tank/Media/TV Shows
   ```

2. **Download Clients**
   ```
   Type: qBittorrent
   Host: download-server-ip
   Port: 8080
   Username: admin
   Password: your-password
   Category: tv-sonarr
   ```

3. **Import Lists** (Optional)
   - Configure Trakt, TMDb, or other sources
   - Set up automatic series monitoring

### Quality Profiles

Create custom quality profiles based on your preferences:

```
Custom Profile Example:
- HDTV-720p
- HDTV-1080p
- WEBDL-720p
- WEBDL-1080p
- Bluray-720p
- Bluray-1080p
```

### Folder Monitoring

```
Path: /tank/IncomingTV
Update Interval: 1 minute
Rescan Series Folder: After Manual Import
```

### Custom Scripts

```
Path: /home/username/cleanup-sonarr.sh
Arguments: (leave empty)
On Download: ✓
On Import: ✓
On Upgrade: ✓
```

## Radarr Configuration

### Initial Setup

1. **Root Folders**
   ```
   Path: /tank/Media/Movies
   ```

2. **Download Clients**
   ```
   Type: qBittorrent
   Host: download-server-ip
   Port: 8080
   Username: admin
   Password: your-password
   Category: movies-radarr
   ```

### Quality Profiles

```
Custom Profile Example:
- WEBDL-720p
- WEBDL-1080p
- WEBDL-2160p
- Bluray-720p
- Bluray-1080p
- Bluray-2160p
```

### Folder Monitoring

```
Path: /tank/incomingmovies
Update Interval: 1 minute
```

### Custom Scripts

```
Path: /home/username/cleanup-radarr.sh
Arguments: (leave empty)
On Download: ✓
On Import: ✓
On Upgrade: ✓
```

## Prowlarr Configuration

### Indexer Setup

1. **Torrent Indexers**
   - Choose 2 torrent indexers (mix of public/private recommended)
   - Configure API keys where required
   - Test connectivity

2. **Newsgroup Indexers**
   - Choose 2 newsgroup indexers on different networks
   - Include one indexer specialized for your local country content
   - Configure API keys
   - Set appropriate categories

### Application Sync

1. **Sonarr**
   ```
   Name: Sonarr
   Sync Level: Full Sync
   Server: http://sonarr:8989
   API Key: (from Sonarr settings)
   ```

2. **Radarr**
   ```
   Name: Radarr
   Sync Level: Full Sync
   Server: http://radarr:7878
   API Key: (from Radarr settings)
   ```

## NZBGet Configuration

### Server Configuration

1. **Primary Server (Different Backbone #1)**
   ```
   Active: Yes
   Name: Primary Provider
   Level: 0 (main)
   Host: news.your-primary-provider.com
   Port: 563
   Encryption: Yes
   Username: your-username
   Password: your-password
   Connections: 50
   ```

2. **Backup Server (Different Backbone #2)**
   ```
   Active: Yes
   Name: Backup Provider
   Level: 1 (backup)
   Host: news.your-backup-provider.com
   Port: 563
   Encryption: Yes
   Username: your-backup-username
   Password: your-backup-password
   Connections: 20
   ```

   **Important**: Choose providers on different backbones for maximum completion rates.

### High-Speed Processing Directory

**CRITICAL**: NZBGet uses `/usenet/` directory for high-speed processing:
- **Main Directory**: `/usenet/` (located on high-speed storage for fast RAR extraction)
- **Intermediate Directory**: `/usenet/intermediate` (temporary processing)
- **Queue Directory**: `/usenet/queue` (active downloads)
- **Temp Directory**: `/usenet/tmp` (extraction workspace)

### Categories - STAGING DIRECTORIES (REQUIRED)

**CRITICAL FIX**: NZBGet must use staging directories, not final media directories, for proper Radarr/Sonarr import workflow:

1. **TV Category**
   ```
   Name: TV
   Dest Dir: /tank/IncomingTV
   Aliases: tv,series,television
   Unpack: Yes
   Post Script: (none or custom script)
   ```

2. **Movies Category**
   ```
   Name: Movies
   Dest Dir: /tank/incomingmovies
   Aliases: movie,film,cinema
   Unpack: Yes
   Post Script: (none or custom script)
   ```

**INCORRECT Configuration (breaks automation):**
```
# DON'T DO THIS - bypasses Radarr/Sonarr import process
TV Dest Dir: /tank/Media/TV Shows
Movies Dest Dir: /tank/Media/Movies
```

**Correct Workflow**: NZBGet downloads to `/usenet/` → extracts/processes → moves to STAGING (`/tank/IncomingTV/` or `/tank/incomingmovies/`) → Radarr/Sonarr detect and import → final organization to `/tank/Media/`

This staging approach ensures proper metadata matching, naming conventions, and quality management through Radarr/Sonarr.

### Download Settings

```
Article Cache: 200 (MB)
Write Buffer: 1024 (KB)
Article Timeout: 60 (seconds)
URL Timeout: 60 (seconds)
Terminate Timeout: 600 (seconds)
```

### Post-Processing

```
Unpack: Yes
Delete Archive: Yes
Par Check: Auto
Par Repair: Yes
```

## Overseerr Configuration

### Initial Setup

1. **Plex Configuration**
   ```
   Hostname/IP: plex-server-ip
   Port: 32400
   Use SSL: No (unless configured)
   ```

2. **Application Services**

   **Sonarr:**
   ```
   Server Name: Sonarr
   Hostname/IP: sonarr-container-ip
   Port: 8989
   API Key: (from Sonarr settings)
   Quality Profile: HD-1080p
   Root Folder: /tank/Media/TV Shows
   ```

   **Radarr:**
   ```
   Server Name: Radarr
   Hostname/IP: radarr-container-ip
   Port: 7878
   API Key: (from Radarr settings)
   Quality Profile: HD-1080p
   Root Folder: /tank/Media/Movies
   ```

### User Management

1. **Default Permissions**
   ```
   Request: ✓
   Auto Approve: (admin only)
   Advanced Requests: (trusted users)
   ```

2. **Quotas**
   ```
   Movie Requests: 10 per 7 days
   TV Requests: 5 per 7 days
   ```

## SSH Optimization

### Server Configuration (/etc/ssh/sshd_config)

```bash
# Performance optimizations for rclone
MaxSessions 100
MaxStartups 100:30:200
ClientAliveInterval 60
ClientAliveCountMax 3

# Security (optional but recommended)
PermitRootLogin no
PasswordAuthentication no  # if using key auth
PubkeyAuthentication yes
```

### Client Configuration (~/.ssh/config)

```bash
Host media-server
    HostName your-media-server-ip
    User your-username
    IdentityFile ~/.ssh/id_rsa
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## Firewall Configuration

### Download Server (ufw)

```bash
sudo ufw allow ssh
sudo ufw allow 8080/tcp  # qBittorrent web UI
sudo ufw enable
```

### Media Server (ufw)

```bash
sudo ufw allow ssh
sudo ufw allow 8989/tcp  # Sonarr
sudo ufw allow 7878/tcp  # Radarr
sudo ufw allow 9696/tcp  # Prowlarr
sudo ufw allow 6789/tcp  # NZBGet
sudo ufw allow 5055/tcp  # Overseerr
sudo ufw allow 32400/tcp # Plex (if used)
sudo ufw enable
```

## Monitoring and Maintenance

### Log Rotation

Create log rotation configurations:

```bash
# /etc/logrotate.d/media-automation
/home/username/rclone-*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 username username
}

/home/username/cleanup-*.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
    create 644 username username
}
```

### System Monitoring

1. **Disk Space Alerts**
   ```bash
   # Add to crontab
   0 */6 * * * /usr/bin/df -h /tank | /usr/bin/awk 'NR==2{print $5}' | /usr/bin/sed 's/%//' | /usr/bin/awk '{if($1 > 80) print "Disk usage high: " $1"%"}' | /usr/bin/mail -s "Disk Space Alert" admin@domain.com
   ```

2. **Service Health Check**
   ```bash
   # Add to crontab
   */5 * * * * /usr/bin/docker ps --format "table {{.Names}}\t{{.Status}}" | /usr/bin/grep -v "Up" | /usr/bin/wc -l | /usr/bin/awk '{if($1 > 1) print "Docker services down"}' | /usr/bin/mail -s "Service Alert" admin@domain.com
   ```

## Backup Strategy

### Configuration Backups

```bash
#!/bin/bash
# backup-configs.sh

BACKUP_DIR="/backup/configs"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/$DATE"

# Backup Docker configs
cp -r /path/to/docker/configs/* "$BACKUP_DIR/$DATE/"

# Backup scripts
cp ~/rclone-sync*.sh "$BACKUP_DIR/$DATE/"
cp ~/cleanup-*.sh "$BACKUP_DIR/$DATE/"

# Backup rclone config (sanitized)
rclone config dump > "$BACKUP_DIR/$DATE/rclone-config.json"

# Create archive
tar -czf "$BACKUP_DIR/media-config-$DATE.tar.gz" -C "$BACKUP_DIR" "$DATE"
rm -rf "$BACKUP_DIR/$DATE"
```

### Automated Backups

```bash
# Add to crontab
0 2 * * 0 /home/username/backup-configs.sh
```

This creates weekly configuration backups every Sunday at 2 AM.
