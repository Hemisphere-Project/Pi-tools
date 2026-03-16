#!/bin/bash
set -e
BASEPATH="$(dirname "$(readlink -f "$0")")"

echo "[tailscale] Installing Tailscale..."

# Install via official script
curl -fsSL https://tailscale.com/install.sh | sh

# Prepare persistent state directory on /data (writable partition)
mkdir -p /data/var/tailscale

# If tailscale has existing state, move it to /data
if [ -d /var/lib/tailscale ] && [ ! -L /var/lib/tailscale ]; then
    if [ "$(ls -A /var/lib/tailscale 2>/dev/null)" ]; then
        echo "[tailscale] Moving existing state to /data/var/tailscale"
        cp -a /var/lib/tailscale/* /data/var/tailscale/ 2>/dev/null || true
    fi
fi
mkdir -p /var/lib/tailscale

# Add fstab bind mount so /var/lib/tailscale uses the writable /data partition
# This is required for read-only root filesystem (rorw module)
if ! grep -q '/data/var/tailscale' /etc/fstab 2>/dev/null; then
    # If rorw is active, switch to rw first
    if command -v rw >/dev/null 2>&1; then
        rw
    fi

    echo '/data/var/tailscale                             /var/lib/tailscale none defaults,bind                                 0 0' >> /etc/fstab

    if command -v ro >/dev/null 2>&1; then
        ro
    fi
    echo "[tailscale] Added fstab bind mount for persistent state"
fi

# Apply the mount now
mount -a 2>/dev/null || true

# Symlink service and binary wrapper
ln -sf "$BASEPATH/tailscale-start" /usr/local/bin/
ln -sf "$BASEPATH/tailscale-start.service" /etc/systemd/system/

systemctl daemon-reload

# Don't auto-enable tailscaled — let starter.txt control it
systemctl disable tailscaled 2>/dev/null || true

echo "[tailscale] Installed. Run 'tailscale up' to authenticate."
echo "[tailscale] State persists in /data/var/tailscale (RO-filesystem safe)"
