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
  # Order matters (kouagou02/03, 2026-09-21): journald holds the persistent files open, so the bind
  # cannot be unmounted before journald has restarted on Storage=volatile. Restart first (the fdstore
  # keeps every service's stdout stream, HPlayer2 included), then unbind, then archive the v2 files.
  systemctl restart systemd-journald
  sleep 1
  if findmnt -rn /var/log/journal >/dev/null 2>&1; then
    umount /var/log/journal 2>/dev/null || umount -l /var/log/journal 2>/dev/null || true
  fi
  MID=$(cat /etc/machine-id)
  if [ -d "/data/var/log/journal/$MID" ] && [ ! -d /data/var/log/journal-v2 ]; then
    mv /data/var/log/journal /data/var/log/journal-v2 2>/dev/null || true   # archive, read with journalctl -D
  fi
  rm -rf /var/log/journal/*/ 2>/dev/null                                      # nothing must be left on the tmpfs dir
  systemctl start blackbox.timer journal-export.timer
  /usr/local/bin/journal-export >/dev/null 2>&1 || true
  sleep 1
  echo "  journal: $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]') in RAM · storage=$(grep -h '^Storage' /etc/systemd/journald.conf.d/*.conf | tail -1 | cut -d= -f2) · export: $(/usr/local/bin/journal-export status) · timers: bb=$(systemctl is-active blackbox.timer) export=$(systemctl is-active journal-export.timer) · persist unit: $(systemctl is-active journal-persist.service 2>/dev/null)"
fi
