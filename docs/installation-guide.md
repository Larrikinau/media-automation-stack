# Installation Guide

This guide will walk you through setting up the complete media automation stack from scratch.

## Prerequisites

### Hardware Requirements

- **Download Server**: 
  - Linux server/VM with reliable internet connection
  - Minimum 10GB storage for downloads processing
  - 2GB+ RAM recommended for parallel processing

- **Media Server**:
  - Linux server/VM with large storage capacity
  - ZFS or similar filesystem recommended for data integrity
  - 4GB+ RAM for running multiple services
  - SSH access from download server

### Software Prerequisites

Both servers should have:
- Ubuntu 20.04+ or similar Linux distribution
- SSH server configured and accessible
- Basic development tools (`curl`, `wget`, `unzip`)

## Download Server Setup

### 1. Install Required Packages

```bash
sudo apt update
sudo apt install -y \
    qbittorrent-nox \
    unrar-free \
    curl \
    wget
```

### 2. Install rclone

```bash
curl https://rclone.org/install.sh | sudo bash
```

### 3. Configure qBittorrent

**Start qBittorrent in daemon mode:**
```bash
# First, create a systemd service for qBittorrent
sudo tee /etc/systemd/system/qbittorrent-nox.service > /dev/null <<EOF
[Unit]
Description=qBittorrent Daemon
After=network.target

[Service]
User=$USER
Group=$USER
Type=simple
ExecStart=/usr/bin/qbittorrent-nox --webui-port=8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl enable qbittorrent-nox
sudo systemctl start qbittorrent-nox

# Check it's running
sudo systemctl status qbittorrent-nox
```

**Access the web interface:**
1. Open browser and go to `http://your-download-server-ip:8080`
2. **Default login credentials:**
   - Username: `admin`
   - Password: `adminadmin`
3. **⚠️ IMPORTANT: Change the password immediately!**
   - Go to Tools → Options → Web UI
   - Change username/password under "Authentication"

**Configure categories (crucial for automation):**
1. Go to **Categories** (left sidebar)
2. Right-click in empty space → "Add category"
3. Create these exact categories:
   - Name: `TV Shows` (case-sensitive!)
   - Save path: `/home/yourusername/downloads/qbittorrent/tv`
   - Name: `Movies` (case-sensitive!)
   - Save path: `/home/yourusername/downloads/qbittorrent/movies`

**Configure automation trigger:**
1. Go to **Tools → Options → Downloads**
2. Scroll to bottom: "Run external program on torrent completion"
3. ✅ Check the box
4. Enter exact command:
   ```
   /home/yourusername/rclone-sync-queue.sh "%F" "%L"
   ```
   **Replace `yourusername` with your actual username!**

**Set download paths:**
1. Go to **Tools → Options → Downloads**
2. Set "Default Save Path": `/home/yourusername/downloads/qbittorrent`
3. **🚨 CRITICAL**: Set "Torrent content layout" to "Create subfolder"
   - This setting is ESSENTIAL for automation scripts to work!
   - Without this, the rclone processing will fail
4. Create the directory:
   ```bash
   mkdir -p ~/downloads/qbittorrent/{tv,movies,complete}
   ```

### 4. Configure rclone

Set up SFTP connection to media server:

```bash
rclone config
```

When prompted:
1. Choose "New remote"
2. Name it `MEDIA_SERVER`
3. Choose "SFTP"
4. Enter your media server hostname/IP
5. Enter SSH username and authentication details
6. Test the connection

### 5. Deploy Scripts

```bash
# Create directory for scripts
mkdir -p ~/bin

# Copy scripts from this repository
cp scripts/download-server/* ~/bin/
chmod +x ~/bin/*.sh

# Create log directory
mkdir -p ~/.rclone-sync.locks
```

## Media Server Setup

### 1. Install Required Packages

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install basic dependencies
sudo apt install -y curl wget unzip software-properties-common
```

### 2. Create Directory Structure

```bash
# Create main directories
sudo mkdir -p /tank/{Media,IncomingTV,IncomingTV_staging,incomingmovies,IncomingMovies_staging}
sudo mkdir -p /usenet/{downloads,watch,complete,incomplete}

# Set permissions
sudo chown -R $USER:$USER /tank /usenet
```

### 3. Install Media Management Applications

#### Install Sonarr
```bash
# Add Sonarr repository
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2009837CBFFD68F45BC180471F4F90DE2A9B4BF8
echo "deb https://apt.sonarr.tv/ubuntu focal main" | sudo tee /etc/apt/sources.list.d/sonarr.list
sudo apt update
sudo apt install sonarr

# Start and enable service
sudo systemctl enable sonarr
sudo systemctl start sonarr
```

#### Install Radarr
```bash
# Download and install Radarr
cd /opt
sudo wget --content-disposition 'http://radarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64'
sudo tar -xvzf Radarr*.linux*.tar.gz
sudo chown -R $USER:$USER /opt/Radarr

# Create systemd service
sudo tee /etc/systemd/system/radarr.service > /dev/null <<EOF
[Unit]
Description=Radarr Daemon
After=syslog.target network.target

[Service]
User=$USER
Group=$USER
Type=simple
ExecStart=/opt/Radarr/Radarr -nobrowser -data=/var/lib/radarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Create data directory and start service
sudo mkdir -p /var/lib/radarr
sudo chown $USER:$USER /var/lib/radarr
sudo systemctl enable radarr
sudo systemctl start radarr
```

#### Install Prowlarr
```bash
# Download and install Prowlarr
cd /opt
sudo wget --content-disposition 'http://prowlarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64'
sudo tar -xvzf Prowlarr*.linux*.tar.gz
sudo chown -R $USER:$USER /opt/Prowlarr

# Create systemd service
sudo tee /etc/systemd/system/prowlarr.service > /dev/null <<EOF
[Unit]
Description=Prowlarr Daemon
After=syslog.target network.target

[Service]
User=$USER
Group=$USER
Type=simple
ExecStart=/opt/Prowlarr/Prowlarr -nobrowser -data=/var/lib/prowlarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Create data directory and start service
sudo mkdir -p /var/lib/prowlarr
sudo chown $USER:$USER /var/lib/prowlarr
sudo systemctl enable prowlarr
sudo systemctl start prowlarr
```

#### Install NZBGet
```bash
# Download and install NZBGet
cd /opt
sudo wget https://github.com/nzbget/nzbget/releases/download/v21.1/nzbget-21.1-bin-linux.run
sudo sh nzbget-21.1-bin-linux.run --destdir /opt/nzbget
sudo chown -R $USER:$USER /opt/nzbget

# Create systemd service
sudo tee /etc/systemd/system/nzbget.service > /dev/null <<EOF
[Unit]
Description=NZBGet Daemon
After=network.target

[Service]
User=$USER
Group=$USER
Type=forking
ExecStart=/opt/nzbget/nzbget -c /opt/nzbget/nzbget.conf -D
ExecStop=/opt/nzbget/nzbget -Q
ExecReload=/opt/nzbget/nzbget -O
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl enable nzbget
sudo systemctl start nzbget
```

#### Install Overseerr
```bash
# Install Overseerr via Snap (simplest method)
sudo snap install overseerr

# Start the service
sudo systemctl start snap.overseerr.daemon
sudo systemctl enable snap.overseerr.daemon
```

### 4. Configure Services

#### Sonarr (Port 8989)
1. Add root folder: `/tank/Media/TV Shows`
2. Add download client: qBittorrent (point to download server)
3. Set up monitoring folder: `/tank/IncomingTV`
4. Configure custom script: `/home/yourusername/cleanup-sonarr.sh`

#### Radarr (Port 7878)
1. Add root folder: `/tank/Media/Movies`
2. Add download client: qBittorrent (point to download server)
3. Set up monitoring folder: `/tank/incomingmovies`
4. Configure custom script: `/home/yourusername/cleanup-radarr.sh`

#### Prowlarr (Port 9696)
1. Add indexers (newsgroup and torrent)
2. Configure applications (Sonarr and Radarr)
3. Test connectivity

#### NZBGet (Port 6789)
1. Add newsgroup servers
2. Configure categories:
   - TV: `/tank/Media/TV Shows`
   - Movies: `/tank/Media/Movies`
3. Set up post-processing scripts

#### Overseerr (Port 5055)
1. Connect to Sonarr and Radarr
2. Configure user permissions
3. Set up request approval workflows
4. **Configure Cloudflare tunnel for secure external access** (see next section)

### 5. Deploy Cleanup Scripts

```bash
# Copy cleanup scripts
cp scripts/media-server/* ~/
chmod +x ~/*.sh
```

### 6. Optimize SSH for rclone

Edit `/etc/ssh/sshd_config`:

```bash
# Add these lines for rclone optimization
MaxSessions 100
MaxStartups 100:30:200
```

Restart SSH service:
```bash
sudo systemctl restart sshd
```

### 7. Set up Cloudflare Tunnel for Overseerr (Optional but Recommended)

Cloudflare tunnels provide secure external access to Overseerr without opening ports on your firewall.

#### Install cloudflared
```bash
# Download and install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
sudo mv cloudflared /usr/bin/
sudo chmod +x /usr/bin/cloudflared
```

#### Configure the tunnel
```bash
# Login to Cloudflare (opens browser)
cloudflared login

# Create a tunnel
cloudflared tunnel create overseerr-tunnel

# Create configuration directory
sudo mkdir -p /etc/cloudflared
```

#### Create tunnel configuration
Create `/etc/cloudflared/config.yml`:
```yaml
tunnel: overseerr-tunnel
credentials-file: /etc/cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: your-domain.com
    service: http://localhost:5055
  - service: http_status:404

warp-routing:
  enabled: false
```

#### Install as system service
```bash
# Install the service
sudo cloudflared service install

# Start the service
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

**Benefits of Cloudflare tunnel:**
- ✅ No firewall port opening required
- ✅ Free SSL certificates
- ✅ DDoS protection
- ✅ Access from anywhere securely

## Network Configuration

### Critical: Download Server IP Whitelisting

**⚠️ IMPORTANT**: Before starting any transfers, you must whitelist the download server's public IP address on your home network firewall/router.

**Why this is required:**
- rclone uses up to 96 concurrent SFTP connections for transfers
- Firewalls/IDS systems may interpret this as a DDoS attack
- Without whitelisting, transfers will fail intermittently or be blocked entirely

**How to implement:**

1. **Find your download server's public IP:**
   ```bash
   # On download server, check public IP
   curl ifconfig.me
   ```

2. **Configure firewall whitelist:**

   **UniFi Dream Machine Pro:**
   ```
   1. UniFi Network Controller → Security → IDS/IPS
   2. Click "Whitelist" tab
   3. Add download server IP address
   4. Save configuration
   ```

   **pfSense:**
   ```
   1. Firewall → Aliases → IP tab
   2. Create alias for download server IP
   3. Firewall → Rules → WAN
   4. Add rule: Allow TCP/22 from download server IP to media server IP
   ```

   **Generic Router:**
   ```
   1. Access router admin interface
   2. Find "Firewall" or "Security" settings
   3. Add rule allowing TCP port 22 from download server IP
   4. Apply changes
   ```

3. **Test connectivity:**
   ```bash
   # From download server, test SSH to media server
   ssh -v username@media-server-ip
   ```

### Server Firewall Rules

Download Server:
```bash
sudo ufw allow 8080  # qBittorrent web UI
sudo ufw allow ssh
```

Media Server:
```bash
sudo ufw allow 8989  # Sonarr
sudo ufw allow 7878  # Radarr
sudo ufw allow 9696  # Prowlarr
sudo ufw allow 6789  # NZBGet
sudo ufw allow 5055  # Overseerr
sudo ufw allow ssh   # Critical: SSH for rclone transfers
```

### DNS/Port Forwarding

If accessing services remotely, configure your router to forward the appropriate ports, or set up a reverse proxy with SSL certificates.

**Important:** The SSH port (22) forwarding to your media server is what enables the download server to transfer files. Ensure this is properly configured and that the download server IP is whitelisted.

## Testing the Installation

### 1. Test rclone Connection

From download server:
```bash
rclone lsd MEDIA_SERVER:/tank/
```

### 2. Test qBittorrent Integration

1. Add a test torrent in qBittorrent
2. Assign it to "TV Shows" or "Movies" category
3. Monitor logs: `tail -f ~/rclone-debug.log`

### 3. Test Service Connectivity

Check that all services are running:
```bash
sudo systemctl status sonarr radarr prowlarr nzbget
```

Access web interfaces:
- Sonarr: http://media-server:8989
- Radarr: http://media-server:7878
- Prowlarr: http://media-server:9696
- NZBGet: http://media-server:6789
- Overseerr: http://media-server:5055

## Security Considerations

1. **Change default passwords** for all web interfaces
2. **Use strong SSH keys** instead of passwords
3. **Configure VPN access** for remote management
4. **Regular security updates**:
   ```bash
   sudo apt update && sudo apt upgrade
   # Update applications as needed
   ```
5. **Backup configurations** regularly

## Next Steps

- Configure RSS feeds in qBittorrent
- Set up indexers in Prowlarr
- Add content requests in Overseerr
- Monitor system logs for any issues

For troubleshooting common issues, see [troubleshooting.md](troubleshooting.md).
