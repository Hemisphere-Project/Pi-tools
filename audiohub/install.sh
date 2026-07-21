#!/bin/bash
# audiohub — always-on multi-output audio hub (absorbs audioselect).
# Idempotent: safe to re-run; preserves existing config; migrates installs
# made under the old 'hplayer-audio' module name.

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
    armv*)  cp "$BASEPATH/asound.conf-pi3" /etc/asound.conf ;;
    *)      echo "WARNING: no hub graph for $(uname -m) yet, /etc/asound.conf untouched" ;;
esac

# ── migrate from the transitional 'hplayer-audio' name ──
if systemctl list-unit-files 2>/dev/null | grep -q '^hplayer-audio@'; then
    echo "migrating hplayer-audio -> audiohub"
    systemctl disable --now 'hplayer-audio@jack' 'hplayer-audio@hdmi' 'hplayer-audio@usb' 2>/dev/null
fi
rm -f '/etc/systemd/system/hplayer-audio@.service' /usr/local/bin/hplayer-audio-fwd \
      /etc/modules-load.d/hplayer-audio.conf
if [ -f /etc/hplayer-audio.conf ] && [ ! -f /etc/audiohub.conf ]; then
    OLDLAT=$(sed -n 's/^latency_us=\([0-9]\+\).*/\1/p' /etc/hplayer-audio.conf | head -1)
    cp "$BASEPATH/audiohub.conf" /etc/audiohub.conf
    [ -n "$OLDLAT" ] && sed -i "s/^latency_us=.*/latency_us=$OLDLAT/" /etc/audiohub.conf
    rm -f /etc/hplayer-audio.conf
fi

# The contract file applications detect (kept if already present: it is config)
if [ ! -f /etc/audiohub.conf ]; then
    cp "$BASEPATH/audiohub.conf" /etc/audiohub.conf
fi

# loopback card at every boot, and right now
mkdir -p /etc/modules-load.d
echo snd-aloop > /etc/modules-load.d/audiohub.conf
modprobe snd-aloop

chmod +x "$BASEPATH/audiohub-fwd" "$BASEPATH/audiohub"
ln -sf "$BASEPATH/audiohub-fwd" /usr/local/bin/
ln -sf "$BASEPATH/audiohub" /usr/local/bin/
ln -sf "$BASEPATH/audiohub@.service" /etc/systemd/system/

# ── absorb audioselect: its udev rule rewrites /etc/asound.conf on every
# sound event and would clobber the hub graph on USB hotplug ──
if [ -e /etc/udev/rules.d/70-audioselect.rules ]; then
    echo "removing audioselect (absorbed by audiohub)"
    rm -f /etc/udev/rules.d/70-audioselect.rules
    udevadm control --reload 2>/dev/null
fi
rm -f '/etc/systemd/system/audioselect@.service' /usr/local/bin/audioselect 2>/dev/null

systemctl stop alsa-restore 2>/dev/null
systemctl mask alsa-restore 2>/dev/null
systemctl stop alsa-state 2>/dev/null
systemctl mask alsa-state 2>/dev/null

systemctl daemon-reload
systemctl enable audiohub@jack audiohub@hdmi audiohub@usb
systemctl restart audiohub@jack audiohub@hdmi audiohub@usb

echo "audiohub installed: $(head -1 /etc/asound.conf | cut -c3-22), forwarders enabled"
