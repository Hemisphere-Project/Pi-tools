#!/bin/bash
# Zero-hardware smoke test of the forwarder pipeline: snd-aloop stands in for
# the hub loopback, the ALSA 'null' device stands in for a physical sink.
# PASS = an alsaloop holds for 5s of playback without dying.
set -u

command -v alsaloop >/dev/null || { echo "SKIP: alsa-utils missing"; exit 0; }
grep -q Loopback /proc/asound/cards 2>/dev/null || modprobe snd-aloop 2>/dev/null
grep -q Loopback /proc/asound/cards 2>/dev/null || { echo "SKIP: snd-aloop unavailable"; exit 0; }

aplay -q -D hw:Loopback,0,0 -c 8 -f S16_LE -r 48000 -d 6 /dev/zero &
FEED=$!
sleep 0.5
timeout 5 alsaloop -C hw:Loopback,1,0 -P null -r 48000 -f S16_LE -c 8 -t 30000 -S auto
RC=$?
kill $FEED 2>/dev/null; wait $FEED 2>/dev/null
# timeout's 124 = alsaloop survived the full window
[ "$RC" = "124" ] && { echo PASS; exit 0; }
echo "FAIL: alsaloop exited $RC"; exit 1
