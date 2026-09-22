#!/bin/bash
# usbfix — install: the USB-link watchdog (timer, every minute) and keep kernel messages out of
# rsyslog's tmpfs files. Effective at the next boot; `install.sh --now` starts it at once.
#   --no-rsyslog   leave rsyslog alone (default: imklog off + kern.* stop — the journal keeps them)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
NOW=0; RSYSLOG=1
for a in "$@"; do case "$a" in --now) NOW=1 ;; --no-rsyslog) RSYSLOG=0 ;; esac; done
chmod 755 "$HERE/usbfix"
install -m 755 "$HERE/usbfix" /usr/local/sbin/usbfix
ln -sf "$HERE/usbfix.service" /etc/systemd/system/usbfix.service
ln -sf "$HERE/usbfix.timer" /etc/systemd/system/usbfix.timer
systemctl daemon-reload 2>/dev/null || true
systemctl enable usbfix.timer 2>/dev/null || true
if [ "$RSYSLOG" = 1 ] && [ -f /etc/rsyslog.conf ]; then
  # Under a kernel storm rsyslog read ~7000 lines/s from /proc/kmsg and wrote them twice into the
  # 102 MB tmpfs (kern.log + syslog): full in a minute, CPU burnt for nothing. The persistent journal
  # (blackbox module) keeps kernel lines; blackbox reads the storm from the ring buffer anyway.
  sed -i -E 's/^(module\(load="imklog".*)$/#\1/; s/^(\$ModLoad imklog.*)$/#\1/' /etc/rsyslog.conf
  printf '%s\n' '# Pi-tools usbfix: kernel messages live in the journal, not in the tmpfs log files' 'kern.* stop' > /etc/rsyslog.d/00-kern-journal-only.conf
  [ "$NOW" = 1 ] && systemctl restart rsyslog 2>/dev/null || true
fi
echo "usbfix installed: usbfix.timer enabled (effective at the next boot; 'install.sh --now' to start now)$([ "$RSYSLOG" = 1 ] && echo '; rsyslog: kernel facility journal-only')"
if [ "$NOW" = 1 ]; then
  systemctl restart usbfix.timer
  echo "  usbfix.timer $(systemctl is-active usbfix.timer) · next $(systemctl list-timers --no-legend usbfix.timer | awk '{print $1, $2, $3}') · rsyslog $(systemctl is-active rsyslog 2>/dev/null)"
fi
