#!/bin/bash
# hdmi-rehandshake — install: link the script, symlink + enable the oneshot (always on:
# it is a no-op when config.txt carries no explicit hdmi_group/hdmi_mode).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/hdmi-rehandshake"
ln -sf "$HERE/hdmi-rehandshake" /usr/local/bin/hdmi-rehandshake
ln -sf "$HERE/hdmi-rehandshake.service" /etc/systemd/system/hdmi-rehandshake.service
systemctl daemon-reload 2>/dev/null || true
systemctl enable hdmi-rehandshake.service 2>/dev/null || true
echo "hdmi-rehandshake installed and enabled"
