# Cloudflare Tunnel Configuration

This configuration sets up Cloudflare as a secure external access path to Overseerr, ensuring your home network remains protected.

## Overview

Using Cloudflare tunnels provides:
- **Secure External Access**: No need to open ports directly on your firewall
- **DDOS Protection**: Cloudflare offers built-in DDOS mitigation
- **SSL Encryption**: Automatically provided by Cloudflare

## Tunnel Configuration

### Systemd Service

This is how the Cloudflare tunnel is started via the `cloudflared` utility on your media server:

```ini
[Unit]
Description=cloudflared
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel run --token YOUR_CLOUDFLARE_TUNNEL_TOKEN
Restart=on-failure
User=cloudflared

[Install]
WantedBy=multi-user.target
```

### Configuration Details

**Service Name**: cloudflared

- **Local Service Address**: `http://YOUR_LOCAL_IP:5055`
- **Cloudflare Tunnel Endpoint**: `https://your-domain.com`

**Cloudflare Tunnel Setup**:
1. **Create a Cloudflare account** if you do not already have one.
2. **Install cloudflared**:
   ```bash
   curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
   sudo mv cloudflared /usr/bin/
   sudo chmod +x /usr/bin/cloudflared
   ```
3. **Login and create a tunnel**:
   ```bash
   cloudflared login
   cloudflared tunnel create overseerr-tunnel
   ```
   Follow Cloudflare's instructions to authenticate the service to your account.
4. **Configure ingress rules** to direct traffic:
   Within `~/.cloudflared/config.yml`:
   ```yaml
   ingress:
     - hostname: your-domain.com
       service: http://YOUR_LOCAL_IP:5055
     - service: http_status:404
   warp-routing:
     enabled: false
   ```
5. **Start the service**:
   ```bash
   sudo systemctl enable cloudflared
   sudo systemctl start cloudflared
   ```

### Verification

1. Access **Overseerr** using your public Cloudflare URL: `https://your-domain.com`
2. Ensure your SSL certificate is active (provided automatically by Cloudflare).
