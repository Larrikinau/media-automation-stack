# Media Automation Stack

A complete end-to-end media automation system using BitTorrent and Newsgroups with automatic processing, extraction, and organization.

## 🌐 DESIGNED FOR REMOTE TORRENT SERVERS

**This system is specifically architected for situations where your BitTorrent downloading happens on a REMOTE server** (VPS, seedbox, dedicated server) that is **physically and network-separated** from your home media server.

### Why Remote Torrent Architecture?

- **🛡️ Legal Protection**: Download server can be in different jurisdiction
- **⚡ Performance**: Dedicated high-bandwidth server for torrenting  
- **🔒 Security**: Home network not directly exposed to P2P traffic
- **🏢 Reliability**: Professional server infrastructure for downloads
- **📡 Connectivity**: Avoid ISP throttling on home connection

### Two-Server Components:

1. **Download Server** (REMOTE/EXTERNAL) - Handles BitTorrent downloads and initial processing
2. **Media Server** (LOCAL/INTERNAL) - Final media management with Sonarr/Radarr/Plex

```
================================================================================
                         COMPLETE SYSTEM WORKFLOW
================================================================================

===========================================     ===============================
             LOCAL SERVER                                REMOTE SERVER
===========================================     ===============================
                                               
  USER REQUESTS                                  
  +-------------------------+                    
  |      Overseerr          |                    
  |   (Request Interface)   |                    
  +-------------------------+                    
            |
            v
  +-------------------------+
  |       Prowlarr         |--------\           +-------------------------+
  |   (Indexer Manager)     |         \          |   qBittorrent (Remote)  |
  | Decides: Torrent/Usenet |          \-------->|   Downloads & Process   |
  +-------------------------+                    +-------------------------+
        |          |                                          |
        |          |                                          |
        v          |                                          |
  +----------+     |                                          |
  |NEWSGROUP |     |                                          |
  |  PATH    |     |                                          v
  +----------+     |                            +-------------------------+
        |          |                            | File Processing        |
        |          |                            | RAR Extraction         |
        v          |                            | File Filtering         |
  +----------+     |                            +-------------------------+
  | NZBGet   |     |                                          |
  |Downloads |     |                                          |
  |/usenet/  |     |                                          v
  |(NVME)    |     |                            +-------------------------+
  +----------+     |                            |  rclone Upload (SFTP)   |
        |          |                            |  to LOCAL SERVER       |
        |          |                            +-------------------------+
        |          |                                          |
        |          |                                          |
        |          |          <===============================+
        |          |          |
        |          |          v
        |          |    +===========================+
        |          |    |    TORRENT STAGING        |
        |          |    |  IncomingTV_staging/      |
        |          |    |  IncomingMovies_staging/  |
        |          |    +===========================+
        |          |                  |
        |          |                  |
        |          |                  v
        |          |    +===========================+
        |          |    |   TORRENT INCOMING        |
        |          |    |  IncomingTV/              |
        |          |    |  incomingmovies/          |
        |          |    +===========================+
        |          |                  |
        |          +------------------+
        |                             |
        v                             v
  +===================================+
  |        Sonarr/Radarr              |
  |     Import & Move to Final        |
  +===================================+
                  |
                  v
  +===================================+
  |            Plex                   |
  |       Media Server                |
  |     Final Destination             |
  +===================================+

===========================================
```

## 🚀 Quick Start

### Prerequisites

- **Remote download server** (VPS, seedbox, dedicated server)
- **Local media server** (home server, NAS, VM)
- SSH access between both servers
- **Network configuration**: Download server IP whitelisted on home firewall/router
- **SSH optimization**: Media server configured for high-concurrency rclone transfers

### Setup Steps

**📚 For complete step-by-step instructions, see [Installation Guide](docs/installation-guide.md)**

Here's the high-level process:

#### 1. Download Server Setup (REMOTE)
   ```bash
   # Install required packages
   sudo apt update
   sudo apt install qbittorrent-nox unrar-free curl
   
   # Install rclone
   curl https://rclone.org/install.sh | sudo bash
   ```
   
   **Key Configuration Steps:**
   - Create qBittorrent systemd service for auto-start
   - Set up categories: "TV Shows" and "Movies" (case-sensitive!)
   - **CRITICAL**: Tools → Options → Downloads → Torrent content layout: Change to "Create subfolder"
   - Configure external program trigger: `/path/to/rclone-sync-queue.sh "%F" "%L"`
   - Set up rclone SFTP connection to media server
   
   See [rclone Configuration](#rclone-configuration) section below for detailed setup.

#### 2. Media Server Setup (LOCAL)
   ```bash
   # Install base packages
   sudo apt update && sudo apt upgrade -y
   sudo apt install curl wget unzip software-properties-common
   
   # Create directory structure
   sudo mkdir -p /tank/{Media,IncomingTV,IncomingTV_staging,incomingmovies,IncomingMovies_staging}
   sudo chown -R $USER:$USER /tank
   ```
   
   **Install Media Management Applications:**
   - **Sonarr** (TV Shows) - Port 8989
   - **Radarr** (Movies) - Port 7878  
   - **Prowlarr** (Indexer Management) - Port 9696
   - **NZBGet** (Newsgroup Downloads) - Port 6789
   - **Overseerr** (Request Interface) - Port 5055
     
     > **📍 Enhanced Content Filtering**: For families wanting comprehensive content filtering, an enhanced version with admin-controlled age rating controls is available: [overseerr-content-filtering](https://github.com/Larrikinau/overseerr-content-filtering). Features movie ratings (G, PG, PG-13, R, NC-17) and TV ratings (TV-Y, TV-Y7, TV-G, TV-PG, TV-14, TV-MA) with centralized admin management and global adult content blocking.
   
   **⚠️ CRITICAL: SSH Optimization Required**
   ```bash
   # Edit /etc/ssh/sshd_config
   MaxSessions 100        # Default: 10
   MaxStartups 100:30:200 # Default: 10:30:100
   sudo systemctl restart sshd
   ```

#### 3. Network Configuration
   **🚨 ABSOLUTELY CRITICAL:** Whitelist download server IP on home firewall
   ```bash
   # Find download server public IP
   curl ifconfig.me
   
   # Add this IP to your router/firewall whitelist
   # UniFi: Security → IDS/IPS → Whitelist
   # pfSense: Firewall → Rules → Allow SSH from download server IP
   ```

#### 4. Deploy and Configure Scripts
   ```bash
   # Download server scripts
   scp scripts/download-server/* user@download-server:~/
   ssh user@download-server "chmod +x ~/*.sh"
   
   # Media server scripts  
   scp scripts/media-server/* user@media-server:~/
   ssh user@media-server "chmod +x ~/*.sh"
   ```

#### 5. Application Configuration
   Each application needs specific setup:
   - **qBittorrent**: Categories, external program trigger
   - **Sonarr/Radarr**: Root folders, download clients, custom scripts
   - **Prowlarr**: Indexers (dual backbone newsgroups + mixed torrents)
   - **NZBGet**: Dual newsgroup servers, categories
   - **Overseerr**: Connect to Sonarr/Radarr, user management
   - **NZBGet**: Critical - Configure categories to output directly to final directories:
     - TV Category: `/tank/Media/TV Shows`
     - Movies Category: `/tank/Media/Movies`
     - Intermediate Directory: `/usenet/intermediate` (high-speed processing)

**🔧 Complete detailed instructions:** [Installation Guide](docs/installation-guide.md)

## 📁 Directory Structure & Component Mapping

```
media-automation-stack/
├── scripts/
│   ├── download-server/          # 🔧 REMOTE SERVER SCRIPTS
│   │   ├── rclone-sync-queue.sh  # → qBittorrent completion trigger
│   │   ├── rclone-sync.sh        # → File processing & upload to local server
│   │   └── README.md             # → Setup instructions for remote scripts
│   └── media-server/             # 🔧 LOCAL SERVER SCRIPTS
│       ├── cleanup-radarr.sh     # → Radarr post-import cleanup automation
│       ├── cleanup-sonarr.sh     # → Sonarr post-import cleanup automation
│       └── README.md             # → Setup instructions for local scripts
├── config/
│   ├── qbittorrent/              # ⚙️ qBittorrent (REMOTE SERVER)
│   │   └── qBittorrent.conf      # → Categories, external program trigger
│   ├── sonarr/                   # ⚙️ Sonarr (LOCAL SERVER)
│   │   └── config.xml            # → TV show management settings
│   ├── radarr/                   # ⚙️ Radarr (LOCAL SERVER)
│   │   └── config.xml            # → Movie management settings
│   ├── prowlarr/                 # ⚙️ Prowlarr (LOCAL SERVER)
│   │   └── config.xml            # → Indexer management & routing
│   ├── nzbget/                   # ⚙️ NZBGet (LOCAL SERVER)
│   │   └── nzbget.conf           # → Newsgroup server & category setup
│   ├── systemd/                  # ⚙️ System Services
│   │   └── qbittorrent-nox.service # → Auto-start qBittorrent daemon
│   ├── rclone.conf               # ⚙️ rclone (REMOTE→LOCAL Transfer)
│   ├── sshd_config.example       # ⚙️ SSH Optimization (LOCAL SERVER)
│   ├── cloudflare/               # ⚙️ Overseerr Secure Access
│   │   └── README.md             # → Cloudflare tunnel setup for Overseerr
│   └── network/                  # ⚙️ Network & Firewall
│       └── README.md             # → CRITICAL: IP whitelisting & SSH setup
├── docs/
│   ├── installation-guide.md     # 📚 Complete step-by-step setup
│   ├── configuration.md          # 📚 Detailed component configuration
│   └── troubleshooting.md        # 📚 Common issues & solutions
└── README.md                     # 📚 Main documentation & architecture
```

### 🔗 Component-to-File Quick Reference:

| Component | Location | Config Files | Scripts | Purpose |
|-----------|----------|--------------|---------|----------|
| **qBittorrent** | Remote Server | `config/qbittorrent/qBittorrent.conf` | `scripts/download-server/rclone-sync-*.sh` | Torrent downloads & processing |
| **Overseerr** | Local Server | `config/cloudflare/` | None | User request interface |
| **Prowlarr** | Local Server | `config/prowlarr/config.xml` | None | Indexer management & routing |
| **NZBGet** | Local Server | `config/nzbget/nzbget.conf` | None | Newsgroup downloads |
| **Sonarr** | Local Server | `config/sonarr/config.xml` | `scripts/media-server/cleanup-sonarr.sh` | TV show management |
| **Radarr** | Local Server | `config/radarr/config.xml` | `scripts/media-server/cleanup-radarr.sh` | Movie management |
| **rclone** | Remote→Local | `config/rclone.conf` | Used by download-server scripts | File transfer system |
| **SSH/Network** | Both Servers | `config/sshd_config.example`, `config/network/` | None | Performance & security |
| **Plex** | Local Server | Not included | None | Final media serving |

## ⚠️ CRITICAL: These Are REAL Working Configurations

**Unlike typical GitHub projects with generic examples, this repository contains the ACTUAL configuration files from a working production system.** 

These configs show:
- ✅ **Exact qBittorrent settings** that trigger automation scripts
- ✅ **Precise rclone parameters** optimized for 96 concurrent SFTP connections  
- ✅ **Real Sonarr/Radarr/NZBGet** configurations that work with the automation
- ✅ **Actual SSH optimizations** required for high-performance transfers
- ✅ **Native service configurations** from production system

**All sensitive data has been sanitized**, but the functional configuration structure is preserved.

## 🔄 Workflow Details

### 1. BitTorrent Download Phase (REMOTE Server)
- qBittorrent downloads torrents based on RSS feeds or manual additions
- Categories/labels determine content type: "TV Shows", "Movies", etc.
- On completion, triggers `rclone-sync-queue.sh`

### 2. File Processing (REMOTE Server)
- **Queue Management**: Uses lock files to limit to 4 parallel rclone operations
- **Label-Based Routing**: Torrent labels determine destination (TV Shows → IncomingTV_staging, Movies → IncomingMovies_staging)
- **Wrapper Stripping**: Removes generic "Incoming TV Shows"/"Incoming Movies" folders
- **RAR Extraction**: Automatically detects and extracts RAR archives
- **File Filtering**: Excludes screens, metadata, and RAR files from upload

### 3. Upload to Media Server (REMOTE → LOCAL)
- Uses rclone with SFTP for fast, parallel transfers
- **Two-stage process**: Upload to staging directories → server-side move to live directories
- Optimized for high concurrency (96 SFTP connections)
- Staging prevents incomplete transfers from triggering media management

### 4. Media Management (LOCAL Server)
- **Sonarr**: Monitors IncomingTV/ directory (NOT staging), imports to final library
- **Radarr**: Monitors incomingmovies/ directory (NOT staging), imports to final library  
- **Post-Import Cleanup**: Automated scripts remove source files after successful import
- **Two-Stage Process**: Files move from staging directories → incoming directories → Sonarr/Radarr processing
- **NZBGet Direct Path**: NZBGet downloads DIRECTLY to final /tank/Media/ directories, bypassing staging entirely

### 5. Content Request and Routing Process (LOCAL Server)
- **Overseerr**: Users submit content requests via web interface (**on local server, protected by Cloudflare tunnel**)
- **Prowlarr**: Central indexer manager running on local server, receives requests from Sonarr/Radarr
- **Smart Routing**: Prowlarr searches configured indexers and determines best source:
  - **Newsgroup route (local)**: Sends .nzb to NZBGet → downloads to /usenet/ (high-speed NVME) → extracts directly to final /tank/Media/ directories
  - **Torrent route (remote)**: Sends .torrent to qBittorrent on remote server → file processing → rclone upload to staging → server moves to incoming directories → Sonarr/Radarr import
- **Dual Source Strategy**: Two SEPARATE workflows - newsgroups bypass staging entirely, torrents use the staging system
- **Final Processing**: 
  - **Newsgroups**: NZBGet → direct to /tank/Media/TV Shows or /tank/Media/Movies (Sonarr/Radarr detect completed files)
  - **Torrents**: Staging → incoming directories (IncomingTV/, incomingmovies/) → Sonarr/Radarr import → final Plex media library
- **Indexer Diversity**: Dual newsgroup indexers on different backbones + mixed torrent sites (including local content specialists)

## 🎯 Key Features

- **Remote Torrent Architecture**: Designed for separated download/media servers
- **Parallel Processing**: Queue system prevents resource exhaustion
- **Smart Extraction**: Handles complex RAR archives automatically
- **Bandwidth Optimization**: Excludes unnecessary files from upload
- **Robust Error Handling**: Retries and fallback mechanisms
- **Two-Source Support**: Both BitTorrent and Newsgroups
- **Production-Ready**: Based on real working configurations
- **Secure External Access**: Overseerr protected via Cloudflare tunnel

## 🌐 Network Requirements

### CRITICAL: Download Server IP Whitelisting

**The remote download server's public IP address MUST be whitelisted on your home network firewall/router.**

Why this is essential:
- rclone transfers use up to 96 concurrent SFTP connections
- Without whitelisting, firewalls may block these as potential attacks
- Failed connections cause transfer failures and queue backups

**Implementation examples**:
- **UniFi UDM Pro**: Security → IDS/IPS → Add download server IP to whitelist
- **pfSense**: Firewall → Rules → Allow SSH from download server IP
- **Generic Router**: Port forwarding/firewall rules allowing TCP/22 from download server

### SSH Optimization

The media server requires SSH configuration changes for rclone performance:

```bash
# /etc/ssh/sshd_config
MaxSessions 100        # Default: 10
MaxStartups 100:30:200 # Default: 10:30:100
```

See [Network Configuration Guide](config/network/README.md) for complete details.

## 📡 rclone Configuration

**rclone is the backbone of this system** - it handles all file transfers from the remote download server to your local media server. Proper configuration is essential for reliable operation.

### Prerequisites

Before configuring rclone, ensure:
- **SSH access** between download server and media server works
- **SSH keys** generated (recommended for security)
- **Media server directories** exist (e.g., `/tank/IncomingTV/`, `/tank/incomingmovies/`)

**Generate SSH keys (if not already done)**:
```bash
# On download server
ssh-keygen -t rsa -b 4096 -C "rclone@download-server"

# Copy public key to media server
ssh-copy-id username@media-server-ip

# Test SSH connection
ssh username@media-server-ip
```

### Step-by-Step Setup

1. **Install rclone on download server**:
   ```bash
   curl https://rclone.org/install.sh | sudo bash
   ```

2. **Run interactive configuration**:
   ```bash
   rclone config
   ```

3. **Follow the interactive prompts**:
   ```
   e) Edit existing remote
   n) New remote
   d) Delete remote
   r) Rename remote
   c) Copy remote
   s) Set configuration password
   q) Quit config
   e/n/d/r/c/s/q> n
   ```
   **Choose: `n` (New remote)**

4. **Enter remote name**:
   ```
   name> MEDIA_SERVER
   ```
   **Use: `MEDIA_SERVER` (or your preferred name - this will be used in scripts)**

5. **Choose storage type**:
   ```
   Storage> sftp
   ```
   **Enter: `sftp` (for SSH file transfer)**

6. **Enter connection details**:
   ```
   host> your-media-server-ip-or-hostname
   user> your-media-server-username
   port> 22
   ```
   **Examples:**
   - Host: `192.168.1.100` or `media-server.local`
   - User: `mediauser` or `your-username`
   - Port: `22` (standard SSH port)

7. **Authentication setup**:
   
   **Option A - SSH Key (Recommended)**:
   ```
   key_file> /home/username/.ssh/id_rsa
   key_use_agent> false
   use_insecure_cipher> false
   disable_hashcheck> false
   ```
   
   **Option B - Password**:
   ```
   pass> your-password
   key_file> 
   key_use_agent> false
   ```

8. **Complete configuration**:
   ```
   Edit advanced config? (y/n) n
   Remote config
   --------------------
   [MEDIA_SERVER]
   type = sftp
   host = your-media-server-ip
   user = your-username
   port = 22
   --------------------
   y) Yes this is OK (default)
   e) Edit this remote
   d) Delete this remote
   ```
   **Choose: `y` (Yes this is OK)**

9. **Exit configuration**:
   ```
   e/n/d/r/c/s/q> q
   ```

### Example Configuration

See [`config/rclone.conf`](config/rclone.conf) for a complete working example with:
- SFTP connection settings
- SSH key authentication
- Performance optimizations
- Shell type specifications

### Performance Parameters Used in Scripts

The automation scripts use these optimized rclone parameters:
```bash
--transfers 12                    # Number of parallel transfers
--multi-thread-streams 24        # Streams per transfer
--multi-thread-cutoff 5M         # Minimum file size for multi-threading
--sftp-concurrency 96            # SFTP concurrent operations
--checkers 24                    # File existence checkers
--buffer-size 256M               # Transfer buffer size
--timeout 5m                     # Transfer timeout
--retries 8                      # Number of retries
--retries-sleep 10s              # Wait between retries
```

### Testing Your Configuration

```bash
# Test basic connectivity
rclone ls MEDIA_SERVER:/tank/

# Test upload performance
rclone copy /tmp/testfile MEDIA_SERVER:/tank/test/ -v

# Monitor transfer with progress
rclone copy large-file MEDIA_SERVER:/tank/test/ -P
```

### Troubleshooting

- **Connection refused**: Check SSH service on media server
- **Permission denied**: Verify SSH key permissions (600) and authentication
- **Slow transfers**: Review SSH optimization settings and network bandwidth
- **Timeouts**: Check firewall rules and IP whitelisting

## 🔧 Configuration

See the `config/` directory for REAL working configurations and `docs/` for setup guides:
- [Installation Guide](docs/installation-guide.md) - Step-by-step setup
- [Configuration Details](docs/configuration.md) - Detailed component config  
- [Network & Firewall Setup](config/network/README.md) - **CRITICAL** network requirements
- [Troubleshooting](docs/troubleshooting.md) - Common issues & solutions

## 🐛 Monitoring & Debugging

Key log files to monitor:
- **Download Server**: `~/rclone-debug.log`, `~/rclone-sync.log`
- **Media Server**: `~/cleanup-sonarr.log`, `~/cleanup-radarr.log`

Common checks:
```bash
# Check staging directories (should be empty)
find /tank/IncomingTV/ /tank/IncomingTV_staging/ /tank/incomingmovies/ /tank/IncomingMovies_staging/ -type f | wc -l

# Monitor rclone operations
tail -f ~/rclone-debug.log

# Check service status
ps aux | grep -E 'sonarr|radarr|nzbget|prowlarr'
```

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⚠️ Disclaimer

This software is provided for educational purposes. Users are responsible for complying with all applicable laws and regulations regarding content downloading and sharing.
