#!/bin/bash
# blackbox — install: persistent journal on /data (bind + journald budget) and the per-minute state log.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/blackbox"
ln -sf "$HERE/blackbox" /usr/local/bin/blackbox
ln -sf "$HERE/journal-persist.service" /etc/systemd/system/journal-persist.service
ln -sf "$HERE/blackbox.service" /etc/systemd/system/blackbox.service
ln -sf "$HERE/blackbox.timer" /etc/systemd/system/blackbox.timer
mkdir -p /etc/systemd/journald.conf.d
cp "$HERE/journald-persist.conf" /etc/systemd/journald.conf.d/blackbox.conf
mkdir -p /var/log/journal 2>/dev/null || true          # mount point inside the tmpfs /var/log (rorw)
systemctl daemon-reload 2>/dev/null || true
systemctl enable journal-persist.service blackbox.timer 2>/dev/null || true
echo "blackbox installed: journal-persist.service + blackbox.timer enabled (take effect at next boot; 'systemctl start journal-persist blackbox.timer && systemctl restart systemd-journald' to start now)"
