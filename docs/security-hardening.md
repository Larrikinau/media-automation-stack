# Security Architecture: rclone SFTP Server

## Overview

This guide describes the dedicated rclone SFTP server implementation that provides secure, isolated file transfer access for remote download servers while maintaining excellent performance and reliability.

## Current Security Architecture

The system uses a dedicated `rclone serve sftp` instance that provides secure, controlled access to only the required staging directories without compromising system security.

### Key Components:
- **Dedicated SFTP Service**: Runs on port 8222, separate from system SSH
- **Directory Filtering**: Only exposes staging directories via allowlist
- **User Isolation**: Runs as dedicated user with minimal system privileges
- **Comprehensive Logging**: All operations logged with automatic rotation
- **Atomic Operations**: Server-side moves ensure data consistency

## Security Benefits

### Directory Access Control
- **Allowlist filtering** restricts access to only 4 designated directories:
  - `/tank/IncomingTV`
  - `/tank/IncomingTV_staging`
  - `/tank/incomingmovies`
  - `/tank/IncomingMovies_staging`
- **No system access** - cannot browse filesystem outside these directories
- **No configuration exposure** - scripts, configs, and system files are invisible

### Service Isolation
- **Separate port (8222)** - independent from system SSH service
- **Dedicated user context** - runs as `mediauser` with controlled permissions
- **No shell access** - pure SFTP functionality only, no command execution
- **Process isolation** - separate from other system services

### Network Security
- **SSH key authentication** - secure key-based access only
- **Connection logging** - all operations recorded for audit
- **Firewall friendly** - single port to manage and monitor
- **High performance** - optimized for concurrent connections

## Implementation Details

### Service Configuration

The rclone SFTP server runs as a systemd service with these key settings:

```bash
# Service command (effective configuration)
/usr/bin/rclone serve sftp /tank \
  --addr 0.0.0.0:8222 \
  --authorized-keys /home/mediauser/.ssh/authorized_keys \
  --umask 0002 \
  --filter-from /etc/rclone/sftp-allowlist.rules \
  --log-file /home/mediauser/rclone-sftp.log \
  --log-level INFO
```

### Directory Allowlist

The `/etc/rclone/sftp-allowlist.rules` file restricts access:

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

### Authentication Setup

SSH key authentication provides secure, automated access:

```bash
# On download server - generate SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/rclone-sftp

# Add public key to media server authorized_keys
cat ~/.ssh/rclone-sftp.pub >> /home/mediauser/.ssh/authorized_keys

# Set proper permissions
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

### Remote Configuration

Download server rclone configuration:

```ini
[media_server_sftp]
type = sftp
host = media-server-ip-address
user = mediauser
port = 8222
key_file = /home/downloaduser/.ssh/rclone-sftp
shell_type = unix
```

## Operational Security

### Logging and Monitoring

**Comprehensive logging** tracks all SFTP operations:

```bash
# View recent operations
tail -f /home/mediauser/rclone-sftp.log

# Search for specific transfers
grep "Copied\|Moved" /home/mediauser/rclone-sftp.log

# Monitor service status
systemctl status rclone-serve-sftp.service
```

**Log rotation** prevents disk space issues:
- Weekly rotation with compression
- 8 weeks retention
- Automatic cleanup via logrotate

### File System Permissions

**Proper ownership and permissions** ensure system security:

```bash
# Staging directories with group write access
drwxrwsr-x mediauser media-group /tank/IncomingTV/
drwxrwsr-x mediauser media-group /tank/IncomingTV_staging/
drwxrwsr-x mediauser media-group /tank/incomingmovies/
drwxrwsr-x mediauser media-group /tank/IncomingMovies_staging/

# Files created with group write via umask 0002
-rw-rw-r-- mediauser media-group media-files.mkv
```

### Atomic Operations

**Server-side moves** ensure data consistency:

```bash
# Two-stage process prevents incomplete transfers
# Stage 1: Upload to staging directory
rclone copy source/ media_server_sftp:/IncomingTV_staging/content/

# Stage 2: Server-side atomic move to live directory
rclone moveto media_server_sftp:/IncomingTV_staging/content media_server_sftp:/IncomingTV/content
```

**Benefits of atomic operations:**
- No partial files visible to Sonarr/Radarr during transfer
- Instant promotion from staging to live (seconds, not minutes)
- No network traffic for server-side moves
- Eliminates race conditions in media management

## Testing and Validation

### Connectivity Testing

```bash
# Test basic connectivity
rclone ls media_server_sftp:/

# Should show only 4 directories:
# IncomingTV/
# IncomingTV_staging/
# incomingmovies/
# IncomingMovies_staging/
```

### Security Validation

```bash
# Test directory isolation
rclone ls media_server_sftp:/home/  # Should fail
rclone ls media_server_sftp:/etc/   # Should fail
rclone ls media_server_sftp:/var/   # Should fail

# Test allowed directory access
rclone ls media_server_sftp:/IncomingTV/  # Should work
rclone ls media_server_sftp:/incomingmovies/  # Should work
```

### Performance Testing

```bash
# Test upload performance
rclone copy testfile media_server_sftp:/IncomingTV_staging/ -P

# Test server-side move performance
time rclone moveto media_server_sftp:/IncomingTV_staging/testfile media_server_sftp:/IncomingTV/testfile
# Should complete in ~0.032 seconds
```

## Troubleshooting

### Common Issues

**Issue: Connection refused on port 8222**
```bash
# Check service status
systemctl status rclone-serve-sftp.service

# Check port listening
ss -tln | grep :8222

# Restart if needed
sudo systemctl restart rclone-serve-sftp.service
```

**Issue: Permission denied during transfer**
```bash
# Check directory permissions
stat -c '%A %U:%G %n' /tank/IncomingTV/

# Fix permissions if needed
sudo chown -R mediauser:media-group /tank/IncomingTV*
sudo chmod -R 755 /tank/IncomingTV*
```

**Issue: Directory not visible**
```bash
# Check allowlist configuration
cat /etc/rclone/sftp-allowlist.rules

# Test filter rules
rclone ls media_server_sftp:/ --filter-from /etc/rclone/sftp-allowlist.rules
```

### Service Recovery

**If service fails to start:**

1. **Check configuration:**
   ```bash
   # Validate rclone config
   rclone config show media_server_sftp
   
   # Check authorized_keys
   cat /home/mediauser/.ssh/authorized_keys
   ```

2. **Restart dependencies:**
   ```bash
   # Ensure NFS mount is active
   findmnt /tank
   
   # Restart SSH if needed
   sudo systemctl restart sshd
   ```

3. **Reset service:**
   ```bash
   sudo systemctl stop rclone-serve-sftp.service
   sudo systemctl start rclone-serve-sftp.service
   sudo systemctl status rclone-serve-sftp.service
   ```

## Performance Optimization

### Concurrent Connections

The system is optimized for high-concurrency transfers:

- **96 concurrent SFTP connections** supported
- **Multiple transfer streams** per connection
- **Optimized buffer sizes** for large files
- **Retry logic** handles temporary network issues

### Network Configuration

**SSH daemon optimization** for high concurrency:

```bash
# /etc/ssh/sshd_config
MaxSessions 100        # Default: 10
MaxStartups 100:30:200 # Default: 10:30:100
```

**Firewall considerations:**

- Download server IP whitelisted on home firewall
- Port 8222 accessible from download server
- No additional ports required

## Comparison with Previous Approaches

### Advantages over Chroot Jail

| Aspect | rclone SFTP Server | Chroot Jail |
|--------|-------------------|-------------|
| **Setup Complexity** | Simple service configuration | Complex bind mounts & system setup |
| **Maintenance** | Automatic service management | Manual bind mount maintenance |
| **Performance** | Optimized for file transfers | Generic SFTP with overhead |
| **Logging** | Comprehensive transfer logs | Limited SSH logs only |
| **Updates** | No system modifications | Requires chroot maintenance |
| **Troubleshooting** | Clear service diagnostics | Complex multi-component debugging |

### Security Equivalence

Both approaches provide equivalent security isolation:
- ✅ Directory access restriction
- ✅ No shell access
- ✅ No system file exposure
- ✅ Authentication required
- ✅ Connection logging

## Migration Guide

For users migrating from chroot jail setup:

### 1. Remove Chroot Configuration

```bash
# Remove SSH Match directive from /etc/ssh/sshd_config
# Comment out or remove:
# Match Address YOUR_DOWNLOAD_SERVER_IP User your-media-user
#     ChrootDirectory /chroot/rclone-sftp
#     ForceCommand internal-sftp
#     AllowTcpForwarding no
#     X11Forwarding no

# Restart SSH
sudo systemctl restart sshd
```

### 2. Remove Bind Mounts

```bash
# Remove from /etc/fstab
sudo sed -i '/chroot.*rclone-sftp/d' /etc/fstab

# Unmount existing mounts
sudo umount /chroot/rclone-sftp/incomingmovies
sudo umount /chroot/rclone-sftp/IncomingMovies_staging
sudo umount /chroot/rclone-sftp/IncomingTV
sudo umount /chroot/rclone-sftp/IncomingTV_staging

# Remove chroot directory
sudo rm -rf /chroot
```

### 3. Deploy rclone SFTP Server

Follow the implementation steps above to deploy the new architecture.

### 4. Update Download Server Configuration

```bash
# Update rclone remote to use port 8222
rclone config
# Change port from 22 to 8222 for media_server_sftp remote
```

## Conclusion

The dedicated rclone SFTP server provides robust security isolation with superior performance and maintainability compared to traditional chroot jail approaches. It offers the same security benefits while being significantly easier to deploy, maintain, and troubleshoot.

This architecture is production-proven and provides the optimal balance of security, performance, and operational simplicity for automated media workflows.
