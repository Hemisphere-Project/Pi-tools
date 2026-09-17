#!/bin/bash
# blackbox — install: persistent journal on /data (bind + journald budget) and the per-minute state log.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/blackbox" "$HERE/nowde-probe.py"
ln -sf "$HERE/blackbox" /usr/local/bin/blackbox
ln -sf "$HERE/journal-persist.service" /etc/systemd/system/journal-persist.service
ln -sf "$HERE/blackbox.service" /etc/systemd/system/blackbox.service
ln -sf "$HERE/blackbox.timer" /etc/systemd/system/blackbox.timer
mkdir -p /etc/systemd/journald.conf.d
cp "$HERE/journald-persist.conf" /etc/systemd/journald.conf.d/blackbox.conf
mkdir -p /var/log/journal 2>/dev/null || true          # mount point inside the tmpfs /var/log (rorw)
systemctl daemon-reload 2>/dev/null || true
systemctl enable journal-persist.service blackbox.timer 2>/dev/null || true
echo "blackbox installed: journal-persist.service + blackbox.timer enabled (effective at the next boot; 'install.sh --now' to start now)"
# --now: start on a running player WITHOUT losing this boot's journal. On rorw, journald has been
# writing to /var/log/journal/<mid> on the tmpfs since boot (Storage=auto found the dir); binding
# /data over it would only HIDE those files (journalctl goes blind, journald keeps writing to the
# hidden inodes). So: unbind if bound, copy the live files to /data, unlink the tmpfs copy, bind,
# then restart journald — the fdstore (FileDescriptorStoreMax=4224) keeps every service's stdout
# stream across the restart, HPlayer2 included. Journald rotates the copied "online" file into an
# archive and continues in a fresh one on /data. Loss: the seconds between copy and restart.
if [ "${1:-}" = --now ]; then
  MID=$(cat /etc/machine-id); D=/data/var/log/journal/$MID
  systemctl stop journal-persist.service 2>/dev/null
  mkdir -p /data/var/log/journal && chown root:systemd-journal /data/var/log/journal && chmod 2755 /data/var/log/journal
  for S in /var/log/journal/$MID /run/log/journal/$MID; do
    [ -d "$S" ] && [ ! -e "$D/system.journal" ] && mkdir -p "$D" && cp -a "$S/." "$D/" && rm -rf "$S" && echo "  rescued this boot's journal from $S ($(du -sh "$D" | cut -f1))"
  done
  systemctl start journal-persist.service && systemctl restart systemd-journald && systemctl start blackbox.timer
  sleep 2; echo "  journal: $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]') on $(findmnt -rn -o SOURCE /var/log/journal | cut -c1-40) · boots $(journalctl --list-boots 2>/dev/null | wc -l) · timer $(systemctl is-active blackbox.timer)"
fi
