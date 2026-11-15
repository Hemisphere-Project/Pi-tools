#!/bin/bash
# apfix — install: script + timer, enabled; `--now` starts the timer at once (first tick in 5 min).
# Opt-in: the installer runs this only with `apfix = yes` in pitools.txt (off by default, RastaOS 7.5).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
chmod 755 "$HERE/apfix"
install -m 755 "$HERE/apfix" /usr/local/sbin/apfix
ln -sf "$HERE/apfix.service" /etc/systemd/system/apfix.service
ln -sf "$HERE/apfix.timer" /etc/systemd/system/apfix.timer
systemctl daemon-reload 2>/dev/null || true
systemctl enable apfix.timer 2>/dev/null || true
bash "$HERE/../setup/module-manifest" record apfix "$HERE" || true   # what this pass laid down (#t-047)
echo "apfix installed: apfix.timer enabled (effective at the next boot; 'install.sh --now' to start now)"
if [ "${1:-}" = --now ]; then
  systemctl restart apfix.timer
  echo "  apfix.timer $(systemctl is-active apfix.timer)"
fi
