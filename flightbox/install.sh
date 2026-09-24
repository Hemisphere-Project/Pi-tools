#!/bin/bash
# flightbox — install: link the CLI, enable the boot-time tail-scan.
#   install.sh          files + enable (scan runs at the next boot)
#   install.sh --now    also scan immediately, against whatever partition exists right now
#
# Does NOT create the p4 partition — that's the live-migration unit, pi-tools#t-049. Installing
# flightbox on a box without it yet is safe and expected: every command degrades to "device
# absent" (`flightbox status`), and journal-export/blackbox fall back to their pre-flightbox /data
# path unchanged until #t-049 has run and a reboot has happened.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/flightbox"
ln -sf "$HERE/flightbox" /usr/local/bin/flightbox
ln -sf "$HERE/flightbox-scan.service" /etc/systemd/system/flightbox-scan.service
systemctl daemon-reload 2>/dev/null || true
systemctl enable flightbox-scan.service 2>/dev/null || true
echo "flightbox installed: /usr/local/bin/flightbox, flightbox-scan.service enabled (next boot)"
if [ "${1:-}" = --now ]; then
  systemctl start flightbox-scan.service
  echo "  $(/usr/local/bin/flightbox status)"
fi
