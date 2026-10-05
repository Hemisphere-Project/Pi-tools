#!/bin/bash
# flightbox — install: link the CLI, enable the boot-time tail-scan and the file-mode lazytime remount.
#   install.sh          files + enable (scan runs at the next boot)
#   install.sh --now    also scan immediately, against whatever ring exists right now
#
# Creates no ring. A card in service gets one with `flightbox reserve` (file mode, pi-tools#t-051:
# /data/.flightbox, 512 MB, one supervised zero-fill with the power on); a reflashed card gets p4
# from the golden image. Installing flightbox on a box with neither is safe and expected: every
# command degrades to "ring absent" (`flightbox status`), and journal-export/blackbox fall back to
# their pre-flightbox /data path unchanged. flightbox-lazytime.service does nothing until
# /data/.flightbox exists.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/flightbox"
ln -sf "$HERE/flightbox" /usr/local/bin/flightbox
ln -sf "$HERE/flightbox-scan.service" /etc/systemd/system/flightbox-scan.service
ln -sf "$HERE/flightbox-lazytime.service" /etc/systemd/system/flightbox-lazytime.service
systemctl daemon-reload 2>/dev/null || true
systemctl enable flightbox-scan.service flightbox-lazytime.service 2>/dev/null || true
echo "flightbox installed: /usr/local/bin/flightbox, flightbox-scan + flightbox-lazytime enabled (next boot)"
if [ "${1:-}" = --now ]; then
  systemctl start flightbox-lazytime.service || true
  systemctl start flightbox-scan.service
  echo "  $(/usr/local/bin/flightbox status)"
fi
