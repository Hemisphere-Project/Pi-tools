#!/bin/bash
# hdmi-rehandshake — install: link the script, symlink + enable the boot oneshot and the late
# timer (always on: both are no-ops when config.txt carries no explicit hdmi_group/hdmi_mode).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/hdmi-rehandshake"
ln -sf "$HERE/hdmi-rehandshake" /usr/local/bin/hdmi-rehandshake
for u in hdmi-rehandshake.service hdmi-rehandshake-late.service hdmi-rehandshake-late.timer; do
  ln -sf "$HERE/$u" /etc/systemd/system/$u
done
systemctl daemon-reload 2>/dev/null || true
systemctl enable hdmi-rehandshake.service hdmi-rehandshake-late.timer 2>/dev/null || true
echo "hdmi-rehandshake installed and enabled (boot pass + late timer)"
