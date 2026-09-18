#!/bin/bash
# linkwatch — install: script + timer, enabled; `--now` starts the timer at once (first tick in 30 s).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/linkwatch"
install -m 755 "$HERE/linkwatch" /usr/local/sbin/linkwatch
ln -sf "$HERE/linkwatch.service" /etc/systemd/system/linkwatch.service
ln -sf "$HERE/linkwatch.timer" /etc/systemd/system/linkwatch.timer
systemctl daemon-reload 2>/dev/null || true
systemctl enable linkwatch.timer 2>/dev/null || true
echo "linkwatch installed: linkwatch.timer enabled (effective at the next boot; 'install.sh --now' to start now)"
if [ "${1:-}" = --now ]; then
  systemctl restart linkwatch.timer
  echo "  linkwatch.timer $(systemctl is-active linkwatch.timer) · role: $(for i in eth0 wlan0; do [ -f /boot/wifi/$i-sync-STA.nmconnection ] && echo "slave($i)"; [ -f /boot/wifi/$i-sync-AP.nmconnection ] && echo "master($i)"; done | head -1)"
fi
