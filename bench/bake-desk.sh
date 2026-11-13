#!/usr/bin/env bash
# bake-desk.sh — image/rastaos-bake against a fixture 7.4 tree, from a keyboard (no card, no root).
#
#   bash bench/bake-desk.sh
#
# Builds the 7.4 shapes the bench readout of 13/11 found (stacked anna74 stamps, VERSION 7.0,
# fake-hwclock + rsync + nfs-client wired, DS3231 overlay on, resolv.conf a symlink, the hotspot
# profile in /boot/wifi and the store, _anna74-removed/), runs the recipe offline twice, and checks
# each defect is gone and the second run changes nothing. Proves the file edits, not a boot.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd); BAKE=$HERE/image/rastaos-bake
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
R=$T/root B=$T/boot pass=0 fail=0
ok()  { pass=$((pass+1)); echo "  ok   $*"; }
bad() { fail=$((fail+1)); echo "  FAIL $*"; }
chk() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }

mkdir -p "$R"/etc/systemd/system/{multi-user.target.wants,sysinit.target.wants,remote-fs.target.wants} \
         "$R"/etc/cron.hourly "$R"/etc/NetworkManager/system-connections/_anna74-removed \
         "$R"/run/resolvconf "$B"/wifi
S=$R/etc/systemd/system
ln -s /lib/systemd/system/fake-hwclock.service "$S/sysinit.target.wants/fake-hwclock.service"
ln -s /lib/systemd/system/rsync.service "$S/multi-user.target.wants/rsync.service"
ln -s /lib/systemd/system/nfs-client.target "$S/multi-user.target.wants/nfs-client.target"
ln -s /lib/systemd/system/nfs-client.target "$S/remote-fs.target.wants/nfs-client.target"
ln -s /lib/systemd/system/rpi-eeprom-update.service "$S/multi-user.target.wants/rpi-eeprom-update.service"
ln -s /lib/systemd/system/hplayer2@.service "$S/multi-user.target.wants/hplayer2@26-anna.service"
echo '#!/bin/sh' > "$R/etc/cron.hourly/fake-hwclock"
printf 'P1 2026-09-15: journald volatile\nanna74 2026-11-05: a\nanna74 2026-11-06: b\nanna74 2026-11-07: c\nanna74 2026-11-08: d\nanna74 2026-11-09: e\n' > "$R/etc/rastaos-patches.txt"
echo '7.0 -- bootstraped from bootstrap-raspbian-legacy.sh' > "$B/VERSION"
printf '[pi3]\nhdmi_mode=82\n[all]\ndtoverlay=i2c-rtc,ds3231\ndtparam=audio=on\n' > "$B/config.txt"
echo 'nameserver 127.0.0.1' > "$R/run/resolvconf/resolv.conf"; ln -s ../run/resolvconf/resolv.conf "$R/etc/resolv.conf"
printf '[main]\nplugins=keyfile\n' > "$R/etc/NetworkManager/NetworkManager.conf"
for f in eth0-dhcp wint-hotspot; do echo "[connection]" > "$B/wifi/$f.nmconnection"; cp "$B/wifi/$f.nmconnection" "$R/etc/NetworkManager/system-connections/"; done
echo psk > "$R/etc/NetworkManager/system-connections/_anna74-removed/wint-hmsphr.nmconnection"

echo "run 1"; "$BAKE" --root "$R" --boot "$B" > "$T/run1.log" 2>&1; rc1=$?; sed 's/^/    /' "$T/run1.log"
chk "run 1 exits 0" [ "$rc1" = 0 ]
chk "one anna74 line, the last one" [ "$(grep -c '^anna74 ' "$R/etc/rastaos-patches.txt")" = 1 ]
chk "the last anna74 line kept" grep -q '^anna74 2026-11-09: e$' "$R/etc/rastaos-patches.txt"
chk "older history kept" grep -q '^P1 2026-09-15' "$R/etc/rastaos-patches.txt"
chk "one rastaos75 line" [ "$(grep -c '^rastaos75 ' "$R/etc/rastaos-patches.txt")" = 1 ]
chk "VERSION says 7.5" grep -q '^7\.5 -- ' "$B/VERSION"
for u in fake-hwclock.service rpi-eeprom-update.service nfs-client.target rsync.service; do
  chk "$u masked" [ "$(readlink "$S/$u")" = /dev/null ]
  chk "$u unwired" [ -z "$(find "$S" -path "*.wants/$u" -o -path "*.requires/$u" | head -1)" ]
done
chk "hplayer2 left wired" [ -L "$S/multi-user.target.wants/hplayer2@26-anna.service" ]
chk "fake-hwclock cron gone" [ ! -e "$R/etc/cron.hourly/fake-hwclock" ]
chk "rtc overlay commented" grep -q '^#dtoverlay=i2c-rtc,ds3231' "$B/config.txt"
chk "no live rtc overlay" sh -c "! grep -qE '^[[:space:]]*dtoverlay=i2c-rtc' '$B/config.txt'"
chk "other config.txt lines intact" grep -qx 'dtparam=audio=on' "$B/config.txt"
chk "resolv.conf a real file" [ -f "$R/etc/resolv.conf" -a ! -L "$R/etc/resolv.conf" ]
chk "resolv.conf on 1.1.1.1" grep -qx 'nameserver 1.1.1.1' "$R/etc/resolv.conf"
chk "the old target untouched" grep -q 127.0.0.1 "$R/run/resolvconf/resolv.conf"
chk "NM dns=none" grep -qx 'dns=none' "$R/etc/NetworkManager/conf.d/90-rastaos-dns.conf"
chk "hotspot gone from /boot/wifi" [ ! -e "$B/wifi/wint-hotspot.nmconnection" ]
chk "hotspot gone from the store" [ ! -e "$R/etc/NetworkManager/system-connections/wint-hotspot.nmconnection" ]
chk "eth0-dhcp kept" [ -f "$B/wifi/eth0-dhcp.nmconnection" -a -f "$R/etc/NetworkManager/system-connections/eth0-dhcp.nmconnection" ]
chk "_anna74-removed gone" [ ! -e "$R/etc/NetworkManager/system-connections/_anna74-removed" ]

snap() { (cd "$T" && find root boot -printf '%p %l\n' | sort; cat root/etc/rastaos-patches.txt boot/VERSION boot/config.txt) | sed -E 's/^rastaos75 [0-9-]+/rastaos75 D/'; }
snap > "$T/s1"
echo "run 2"; "$BAKE" --root "$R" --boot "$B" > "$T/run2.log" 2>&1; rc2=$?; sed 's/^/    /' "$T/run2.log"
chk "run 2 exits 0" [ "$rc2" = 0 ]
chk "run 2 reports 0 changes" grep -q 'done — 0 change(s)' "$T/run2.log"
snap > "$T/s2"; chk "run 2 leaves the tree identical" cmp -s "$T/s1" "$T/s2"

chk "--only rejects an unknown step" sh -c "! '$BAKE' --root '$R' --boot '$B' --only nope >/dev/null 2>&1"
chk "--root without config.txt refuses (exit 2)" sh -c "'$BAKE' --root '$R' --boot '$T/none' >/dev/null 2>&1; [ \$? = 2 ]"
chk "--list names the steps" sh -c "'$BAKE' --list | grep -qx wifi"

echo "bake-desk: $pass ok, $fail failed"
[ "$fail" = 0 ]
