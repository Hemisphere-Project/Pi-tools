#!/bin/bash
# hplayer-audio — always-on multi-output audio hub for HPlayer2 players.
# Idempotent: safe to re-run; preserves an existing /etc/hplayer-audio.conf.

BASEPATH="$(dirname "$(readlink -f "$0")")"
cd "$BASEPATH"

if [[ $(command -v apt) ]]; then
    apt install alsa-utils -y
elif [[ $(command -v pacman) ]]; then
    pacman -S alsa-utils --noconfirm --needed
else
    echo "Distribution not detected (needs APT or PACMAN)"; exit 1
fi

# ALSA graph (pi3 legacy/mmal for now — see the file header for the design)
case "$(uname -m)" in
    armv*)  cp "$BASEPATH/asound.conf-hub-pi3" /etc/asound.conf ;;
    *)      echo "WARNING: no hub graph for $(uname -m) yet, /etc/asound.conf untouched" ;;
esac

# The contract file HPlayer2 detects (kept if already present: it is config)
if [ ! -f /etc/hplayer-audio.conf ]; then
    cp "$BASEPATH/hplayer-audio.conf" /etc/hplayer-audio.conf
fi

# loopback card at every boot, and right now
mkdir -p /etc/modules-load.d
echo snd-aloop > /etc/modules-load.d/hplayer-audio.conf
modprobe snd-aloop

ln -sf "$BASEPATH/hplayer-audio-fwd" /usr/local/bin/
chmod +x "$BASEPATH/hplayer-audio-fwd"
ln -sf "$BASEPATH/hplayer-audio@.service" /etc/systemd/system/

# supersede audioselect: its udev rule rewrites /etc/asound.conf on every
# sound event and would clobber the hub graph on USB hotplug
if [ -e /etc/udev/rules.d/70-audioselect.rules ]; then
    echo "removing audioselect udev rule (superseded by hplayer-audio)"
    rm -f /etc/udev/rules.d/70-audioselect.rules
    udevadm control --reload 2>/dev/null
fi

systemctl stop alsa-restore 2>/dev/null
systemctl mask alsa-restore 2>/dev/null
systemctl stop alsa-state 2>/dev/null
systemctl mask alsa-state 2>/dev/null

systemctl daemon-reload
systemctl enable hplayer-audio@jack hplayer-audio@hdmi hplayer-audio@usb
systemctl restart hplayer-audio@jack hplayer-audio@hdmi hplayer-audio@usb

echo "hplayer-audio installed: graph $(head -c 60 /etc/asound.conf | head -1 | cut -c3-20), forwarders enabled"
