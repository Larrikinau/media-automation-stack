# Network and Firewall Configuration

This document outlines the network configuration requirements for the media automation stack.

## Overview

The system requires secure communication between:
- **Download Server** (external/remote) ← qBittorrent, rclone upload
- **Media Server** (local/internal) ← Sonarr, Radarr, NZBGet, Plex

## Firewall Requirements

### Download Server IP Whitelisting

**Critical**: The external download server's IP address must be whitelisted on your home network firewall/router.

#### Why This is Required:
- rclone uses SFTP to transfer files from the download server to your media server
- High-volume transfers with up to 96 concurrent SFTP connections
- Firewalls may interpret this as a potential attack without whitelisting
- Failed connections can cause transfer failures and queue backups

#### Implementation:

**UniFi Dream Machine Pro (UDM Pro)**:
```
1. Access UniFi Network Controller
2. Navigate to Security → IDS/IPS
3. Add the download server IP to "Whitelist"
4. Alternatively: Security → Firewall → Rules
   - Create allow rule for download server IP
   - Action: Accept
   - Source: [Download Server IP]
   - Destination: [Media Server IP]
   - Port: 22 (SSH/SFTP)
```

**pfSense**:
```
1. Firewall → Aliases
   - Create alias for download server IP
2. Firewall → Rules → WAN
   - Add rule allowing SSH from download server
   - Source: Download Server IP
   - Destination: Media Server IP
   - Port: 22
```

**Generic Router/Firewall**:
```
1. Find "Port Forwarding" or "Firewall Rules"
2. Create rule allowing inbound connections:
   - Source IP: [Download Server Public IP]
   - Destination: [Media Server Local IP]
   - Protocol: TCP
   - Port: 22
   - Action: Allow
```

#### Important Notes:
- Use the **public IP** of your download server (not local/private)
- Check if your download server uses a static IP or DDNS
- Consider creating an SSH key pair instead of password authentication
- Monitor firewall logs for any blocked connections

### Port Requirements

#### Media Server (Internal)
```bash
# Core services
22/tcp    # SSH (for rclone SFTP transfers)
8989/tcp  # Sonarr web interface
7878/tcp  # Radarr web interface
9696/tcp  # Prowlarr web interface
6789/tcp  # NZBGet web interface
5055/tcp  # Overseerr web interface

# Optional services
32400/tcp # Plex Media Server
8181/tcp  # Tautulli (Plex monitoring)
```

#### Download Server (External)
```bash
8080/tcp  # qBittorrent web interface (if accessing remotely)
```

## SSH Configuration Optimizations

### Media Server (/etc/ssh/sshd_config)

Key optimizations for rclone performance:

```bash
# Connection handling for rclone's high concurrency
MaxSessions 100                    # Default: 10
MaxStartups 100:30:200            # Default: 10:30:100

# Connection persistence
ClientAliveInterval 60             # Keep connections alive
ClientAliveCountMax 3             # Retry attempts

# Security (recommended)
PasswordAuthentication no          # Use key authentication
PermitRootLogin no                # Disable root login
PubkeyAuthentication yes          # Enable key auth
```

**Apply changes:**
```bash
sudo systemctl reload sshd
```

### Download Server SSH Client (~/.ssh/config)

Optimize outbound connections:

```bash
Host media-server
    HostName your-media-server-domain.com
    User your-username
    Port 22
    IdentityFile ~/.ssh/id_rsa
    
    # Connection multiplexing for performance
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
    
    # Keep connections alive
    ServerAliveInterval 60
    ServerAliveCountMax 3
    
    # Compression (optional, may help with slow connections)
    Compression yes
```

Create socket directory:
```bash
mkdir -p ~/.ssh/sockets
```

## Network Performance Tuning

### TCP Window Scaling

For high-bandwidth transfers, ensure TCP window scaling is enabled:

```bash
# Check current settings
cat /proc/sys/net/ipv4/tcp_window_scaling

# Enable if not already (usually enabled by default)
echo 'net.ipv4.tcp_window_scaling = 1' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 16777216' >> /etc/sysctl.conf

# Apply changes
sudo sysctl -p
```

### Quality of Service (QoS)

Consider prioritizing media automation traffic:

**UniFi QoS**:
```
1. Network → Traffic Management
2. Create rule for media automation:
   - Source: Download Server IP
   - Destination: Media Server IP
   - Priority: High
   - Bandwidth: Allocate appropriate percentage
```

## Security Considerations

### VPN Alternative

For enhanced security, consider using a VPN instead of direct internet access:

1. **Site-to-Site VPN**: Connect download server location to home network
2. **Client VPN**: Download server connects via VPN client (WireGuard, OpenVPN)

**Benefits:**
- Encrypted traffic
- No need for port forwarding
- Better access control
- Easier firewall rules

### SSH Key Authentication

Generate and deploy SSH keys for passwordless authentication:

**On download server:**
```bash
# Generate key pair
ssh-keygen -t ed25519 -f ~/.ssh/media_server_key

# Copy public key to media server
ssh-copy-id -i ~/.ssh/media_server_key.pub user@media-server
```

**Update rclone config to use key:**
```bash
rclone config
# When prompted for authentication, specify key file path
```

### Fail2Ban

Protect against brute force attacks:

```bash
# Install fail2ban on media server
sudo apt install fail2ban

# Configure SSH protection
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Edit jail.local
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
```

## Monitoring

### Connection Monitoring

Monitor SSH connections and rclone activity:

```bash
# Check active SSH sessions
ss -tuln | grep :22

# Monitor rclone transfer logs
tail -f ~/rclone-debug.log

# Check for failed SSH attempts
sudo grep "Failed\|refused" /var/log/auth.log | tail -20
```

### Bandwidth Monitoring

Track transfer usage:

```bash
# Install vnstat for bandwidth monitoring
sudo apt install vnstat

# Monitor interface usage
vnstat -i eth0 -l

# Historical usage
vnstat -i eth0 -d
```

## Troubleshooting

### Common Network Issues

1. **Connection Refused**:
   - Check firewall rules
   - Verify SSH service is running
   - Confirm port 22 is accessible

2. **Too Many Connections**:
   - Increase MaxSessions in sshd_config
   - Check for stuck rclone processes
   - Clear SSH connection multiplexing sockets

3. **Slow Transfers**:
   - Verify QoS settings
   - Check network congestion
   - Adjust rclone concurrency settings
   - Monitor bandwidth utilization

4. **Firewall Blocks**:
   - Check IDS/IPS logs
   - Verify whitelist configuration
   - Monitor firewall rule hits
   - Consider rate limiting instead of blocking

### Testing Connectivity

```bash
# Test SSH connection from download server
ssh -v user@media-server

# Test SFTP specifically
sftp user@media-server

# Test rclone connection
rclone lsd MEDIA_SERVER:/tank/

# Test high concurrency
rclone copy test-file MEDIA_SERVER:/tmp/ --transfers 50 -v
```
