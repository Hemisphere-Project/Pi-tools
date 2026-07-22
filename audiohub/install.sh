#!/bin/bash
# audiohub — always-on multi-output audio hub (absorbs audioselect).
# Idempotent: safe to re-run; preserves existing config; migrates installs
# made under the old 'hplayer-audio' module name.

BASEPATH="$(dirname "$(readlink -f "$0")")"
cd "$BASEPATH"

if [[ $(command -v apt) ]]; then
    apt install alsa-utils libasound2-plugins -y
elif [[ $(command -v pacman) ]]; then
    pacman -S alsa-utils alsa-plugins --noconfirm --needed
else
    echo "Distribution not detected (needs APT or PACMAN)"; exit 1
fi

# ALSA graph per platform — see each file's header for the design
GRAPH_OK=false
case "$(uname -m)" in
    armv*)   cp "$BASEPATH/asound.conf-pi3" /etc/asound.conf
             GRAPH_OK=true
             # asound.conf-pi3 names the LEGACY firmware cards
             # (Headphones/b1 = bcm2835 stack, the RastaOS-7.1 golden).
             # A KMS Pi (vc4-kms-v3d — what setup's own config.txt
             # writes) exposes vc4hdmi* cards instead: hdmiout would
             # dangle. No pi-kms graph exists yet — warn loudly.
             if grep -q "vc4hdmi" /proc/asound/cards 2>/dev/null; then
                 echo "WARNING: KMS audio stack detected (vc4hdmi*):"
                 echo "  asound.conf-pi3 targets the legacy bcm2835 cards"
                 echo "  (Headphones/b1) — hdmiout will NOT match. An"
                 echo "  asound.conf-pi-kms variant is needed (TODO)."
             fi ;;
    x86_64)  cp "$BASEPATH/asound.conf-x86" /etc/asound.conf; GRAPH_OK=true ;;
    *)       echo "WARNING: no hub graph for $(uname -m) yet, /etc/asound.conf untouched" ;;
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
if [ -e /etc/udev/rules.d/70-audioselect.rules ] || [ -L /etc/udev/rules.d/70-audioselect.rules ]; then
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
if [ "$GRAPH_OK" = true ]; then
    systemctl enable audiohub@jack audiohub@hdmi audiohub@usb
    systemctl restart audiohub@jack audiohub@hdmi audiohub@usb
    echo "audiohub installed: $(head -1 /etc/asound.conf | cut -c3-22), forwarders enabled"
else
    # No ALSA graph for this arch (e.g. aarch64 / pi-kms): enabling the forwarders
    # would just crash-loop them (alsaloop on missing PCMs). Leave them disabled
    # until a graph exists for this platform.
    systemctl disable audiohub@jack audiohub@hdmi audiohub@usb 2>/dev/null
    echo "audiohub: NO hub graph for $(uname -m) — forwarders left DISABLED (would"
    echo "          crash-loop). Provide an asound.conf hub graph and re-run."
fi
