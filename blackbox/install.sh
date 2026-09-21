#!/bin/bash
# blackbox v3 — install: journald in RAM (budgeted), journal-export trail on /data, per-minute state log.
#   install.sh          files + enable (effective at the next boot)
#   install.sh --now    also switch a RUNNING player over, without restarting HPlayer2
# v2 (2026-09-17) bound /data/var/log/journal over the tmpfs and let journald write the card in place:
# two SanDisk cards failed in three days (LEA S06-48-P rolled back, KOUAGOU's master aborted /data,
# 2026-09-18/21). v3 reverses that: journald writes RAM, journal-export appends to /data every 10 min
# and dumps the last 15 min on an anomaly (called by blackbox).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/blackbox" "$HERE/nowde-probe.py" "$HERE/journal-export"
ln -sf "$HERE/blackbox" /usr/local/bin/blackbox
ln -sf "$HERE/journal-export" /usr/local/bin/journal-export
ln -sf "$HERE/blackbox.service" /etc/systemd/system/blackbox.service
ln -sf "$HERE/blackbox.timer" /etc/systemd/system/blackbox.timer
ln -sf "$HERE/journal-export.service" /etc/systemd/system/journal-export.service
ln -sf "$HERE/journal-export.timer" /etc/systemd/system/journal-export.timer
mkdir -p /etc/systemd/journald.conf.d
rm -f /etc/systemd/journald.conf.d/blackbox.conf                      # v2: Storage=persistent on /data
cp "$HERE/journald-ram.conf" /etc/systemd/journald.conf.d/blackbox.conf
# v2 leftovers: the bind unit goes; its files on /data stay readable with `journalctl -D` until pruned
systemctl disable journal-persist.service 2>/dev/null || true
rm -f /etc/systemd/system/journal-persist.service /etc/systemd/system/sysinit.target.wants/journal-persist.service
systemctl daemon-reload 2>/dev/null || true
systemctl enable blackbox.timer journal-export.timer 2>/dev/null || true
echo "blackbox v3 installed: journald in RAM (32 MB), journal-export.timer + blackbox.timer enabled (next boot; --now to switch a running player)"
if [ "${1:-}" = --now ]; then
  # unbind /data from /var/log/journal if v2 bound it; journald then sees Storage=volatile and writes
  # /run/log/journal. The fdstore keeps every service's stdout stream across the restart.
  if findmnt -rn /var/log/journal >/dev/null 2>&1; then
    systemctl stop journal-persist.service 2>/dev/null || umount /var/log/journal 2>/dev/null || true
  fi
  MID=$(cat /etc/machine-id)
  if [ -d "/data/var/log/journal/$MID" ] && [ ! -d /data/var/log/journal-v2 ]; then
    mv /data/var/log/journal /data/var/log/journal-v2 2>/dev/null || true   # archive, read with journalctl -D
  fi
  systemctl restart systemd-journald
  systemctl start blackbox.timer journal-export.timer
  /usr/local/bin/journal-export >/dev/null 2>&1 || true
  sleep 1
  echo "  journal: $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]') in RAM · storage=$(grep -h '^Storage' /etc/systemd/journald.conf.d/*.conf | tail -1 | cut -d= -f2) · export: $(/usr/local/bin/journal-export status) · timers: bb=$(systemctl is-active blackbox.timer) export=$(systemctl is-active journal-export.timer) · persist unit: $(systemctl is-active journal-persist.service 2>/dev/null)"
fi
