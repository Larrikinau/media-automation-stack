# Security Hardening: Chroot Jail Implementation

## Overview

This guide describes how to implement a chroot jail to restrict seedbox SFTP access to only the required staging directories, providing complete filesystem isolation while maintaining normal local access to your media server.

## Why Implement a Chroot Jail?

When using a remote seedbox for downloads, the rclone SFTP connection typically has access to your entire filesystem. A chroot jail provides:

- **Complete filesystem isolation** - seedbox can only access designated directories
- **SFTP-only access** - no shell execution possible from seedbox
- **IP-based restrictions** - only applies to seedbox IP, local access remains unrestricted  
- **Zero lockout risk** - local admin access unaffected
- **Persistent configuration** - survives reboots and system updates

## Implementation

### 1. Create Chroot Directory Structure

```bash
# Create the chroot base directory
sudo mkdir -p /chroot/rclone-sftp

# Set proper ownership (required for chroot)
sudo chown root:root /chroot /chroot/rclone-sftp

# Create essential system directories inside chroot
sudo mkdir -p /chroot/rclone-sftp/{bin,dev,etc,lib,lib64,usr}

# Copy required SFTP binaries and libraries
sudo cp /usr/lib/openssh/sftp-server /chroot/rclone-sftp/usr/lib/openssh/
# (Copy other required libraries - see troubleshooting section)

# Create device nodes required for SFTP
sudo mknod /chroot/rclone-sftp/dev/null c 1 3
sudo mknod /chroot/rclone-sftp/dev/zero c 1 5

# Create staging directories at chroot root level
sudo mkdir -p /chroot/rclone-sftp/{incomingmovies,IncomingMovies_staging,IncomingTV,IncomingTV_staging}
```

### 2. Configure Bind Mounts

Create bind mounts to make your actual staging directories available inside the chroot:

```bash
# Create bind mounts
sudo mount --bind /tank/incomingmovies /chroot/rclone-sftp/incomingmovies
sudo mount --bind /tank/IncomingMovies_staging /chroot/rclone-sftp/IncomingMovies_staging
sudo mount --bind /tank/IncomingTV /chroot/rclone-sftp/IncomingTV
sudo mount --bind /tank/IncomingTV_staging /chroot/rclone-sftp/IncomingTV_staging

# Add to /etc/fstab for persistence across reboots
sudo tee -a /etc/fstab << 'EOF'

# Chroot bind mounts for seedbox rclone access
/tank/incomingmovies /chroot/rclone-sftp/incomingmovies none bind 0 0
/tank/IncomingMovies_staging /chroot/rclone-sftp/IncomingMovies_staging none bind 0 0
/tank/IncomingTV /chroot/rclone-sftp/IncomingTV none bind 0 0
/tank/IncomingTV_staging /chroot/rclone-sftp/IncomingTV_staging none bind 0 0
EOF
```

### 3. Configure SSH with IP-Based Restrictions

Add the following to `/etc/ssh/sshd_config` (replace `YOUR_SEEDBOX_IP` with your actual seedbox IP):

```bash
# Chroot for seedbox rclone-sftp access only
Match Address YOUR_SEEDBOX_IP User your-media-user
    ChrootDirectory /chroot/rclone-sftp
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
```

**Important:** The `Match Address` directive ensures chroot restrictions only apply to connections from your seedbox IP. Local connections remain unrestricted.

### 4. Restart SSH Service

```bash
# Test SSH configuration
sudo sshd -t

# Restart SSH daemon
sudo systemctl restart ssh
```

### 5. Update Seedbox rclone Configuration

On your seedbox, ensure rclone is configured to connect via SFTP to your media server using the restricted user account.

## Testing Your Implementation

### Test 1: Local Access (Should Work Normally)
```bash
ssh your-media-user@your-media-server "ls /"
# Expected: Normal filesystem access with shell
```

### Test 2: Seedbox SFTP Access (Should be Restricted)
From your seedbox:
```bash
sftp your-media-user@your-media-server
sftp> ls
# Expected: Only sees the 4 staging directories + system dirs (bin, dev, etc, lib, lib64, usr)
```

### Test 3: Directory Access Test
```bash
sftp your-media-user@your-media-server
sftp> cd incomingmovies
sftp> ls
# Expected: Should work and show contents of your staging directory
```

### Test 4: Filesystem Isolation Test
```bash
sftp your-media-user@your-media-server
sftp> cd ../../../home
# Expected: Should fail - directory not accessible
```

## Security Benefits

### Complete Filesystem Isolation
- Seedbox can only see designated staging directories
- No access to media libraries, system files, or user directories
- Even if seedbox is compromised, damage is limited to staging areas

### SFTP-Only Access
- No shell execution possible from seedbox
- Cannot run commands or scripts remotely
- Pure file transfer functionality only

### IP-Based Restrictions
- Chroot restrictions only apply to seedbox IP address
- Local SSH access remains completely unrestricted
- Zero risk of admin lockout

### Persistent Configuration
- Bind mounts survive reboots via fstab entries
- SSH configuration persists across system updates
- No manual intervention required after setup

## Troubleshooting

### Common Issues

**Issue:** "Permission denied" errors when connecting
**Solution:** Ensure chroot directory ownership is `root:root`

**Issue:** SFTP connection hangs or fails
**Solution:** Copy required libraries and binaries to chroot. Check with:
```bash
ldd /usr/lib/openssh/sftp-server
```

**Issue:** Bind mounts not working after reboot
**Solution:** Verify fstab entries and run `sudo mount -a`

**Issue:** Still seeing full filesystem from seedbox
**Solution:** Verify the seedbox IP matches exactly in the Match directive

### SSH Lockout Recovery

If SSH configuration causes lockout:

1. **Via Console Access:**
   - Access server console directly
   - Edit `/etc/ssh/sshd_config`
   - Comment out or remove the Match block
   - Restart SSH: `sudo systemctl restart ssh`

2. **Via Recovery Mode:**
   - Boot into recovery mode
   - Mount filesystem and edit SSH config
   - Reboot normally

## Integration with Existing Automation

This chroot implementation is fully compatible with existing rclone automation scripts. No changes are required to:

- Download server rclone sync scripts
- Media server import automation
- Sonarr/Radarr monitoring
- File processing workflows

The chroot jail operates transparently - your automation continues to work normally while providing enhanced security isolation.

## Alternative Approaches

### SSH Key Restrictions
While SSH key restrictions (`command=`, `restrict`) can limit access, they don't provide filesystem isolation. A compromised seedbox could still potentially access files outside staging directories.

### Reversed Connections
Some users prefer having the media server initiate connections to the seedbox. However, this requires:
- Custom listening ports on media server
- Firewall configuration for incoming connections
- May not be compatible with all seedbox hosting providers

The chroot jail approach works with any seedbox provider and doesn't require special network configuration.

## Conclusion

The chroot jail provides the strongest security isolation for seedbox rclone access while maintaining full compatibility with existing automation workflows. It's the recommended approach for users who want to minimize risk from potentially compromised seedboxes while keeping their automation systems intact.
