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
# On a Pi the ARCH does not pick the graph — the CARDS do. The legacy
# firmware stack exposes Headphones + b1/b2 (bcm2835: the RastaOS-7.x
# golden, asound.conf-pi3); a KMS Pi (dtoverlay=vc4-kms-v3d — what
# setup/bootstrap.py's own config.txt writes) exposes vc4hdmi* for HDMI
# instead and keeps only the analog half of bcm2835 (asound.conf-pi-kms).
# Both spellings of the Pi arch land here on purpose: that same config.txt
# sets arm_64bit=1 on anything past Buster, so the installer's OWN reference
# platform reports aarch64 and used to fall through to "no graph at all".
pi_hdmi_card() {
    sed -n 's/^ *[0-9]* *\[\(vc4hdmi[0-9]*\) *\].*/\1/p' /proc/asound/cards 2>/dev/null | head -1
}

GRAPH_OK=false
case "$(uname -m)" in
    armv*|aarch64)
             KMSCARD="$(pi_hdmi_card)"
             if [ -n "$KMSCARD" ]; then
                 GRAPH="asound.conf-pi-kms"
             else
                 GRAPH="asound.conf-pi3"
             fi
             cp "$BASEPATH/$GRAPH" /etc/asound.conf
             GRAPH_OK=true
             if [ -n "$KMSCARD" ]; then
                 # Say it at install time, every time: this graph was written
                 # at a desk and has never been played (pi-tools#t-009 —
                 # no KMS Pi on the bench). Whoever installs it is very
                 # likely the first person to hear it.
                 echo "NOTE: KMS audio stack detected ($KMSCARD) -> asound.conf-pi-kms."
                 echo "      That graph is UNTESTED — never played on real hardware."
                 echo "      Read the header of $BASEPATH/$GRAPH before debugging"
                 echo "      silence; it lists what to check, in order."
                 # The graph hardcodes the FIRST HDMI port, house convention
                 # (same as asound.conf-x86's device-3 pick). A single-port
                 # Pi 3 names it plain 'vc4hdmi' and a second port is
                 # 'vc4hdmi1': hdmiout would dangle exactly the way it did
                 # under the pi3 graph, so name the one-line edit rather
                 # than let it be discovered as silence. Read the card the
                 # graph names out of the graph itself — no second copy of
                 # it to drift here.
                 GRAPHCARD=$(sed -n 's/.*slave\.pcm "hw:\(vc4hdmi[0-9]*\)".*/\1/p' /etc/asound.conf | head -1)
                 if [ -n "$GRAPHCARD" ] && [ "$KMSCARD" != "$GRAPHCARD" ]; then
                     echo "WARNING: the graph targets '$GRAPHCARD' but this Pi's HDMI card"
                     echo "         is '$KMSCARD' — hdmiout will NOT match. Fix with:"
                     echo "           sed -i 's/$GRAPHCARD/$KMSCARD/g' /etc/asound.conf"
                     echo "         and send the same edit back to $GRAPH if this"
                     echo "         board type is one we ship."
                 fi
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
    # one at a time: concurrent restarts can wedge a sink / race the vchiq
    # close (see README "Kernel hazard") — same rule as `audiohub apply`
    for u in audiohub@jack audiohub@hdmi audiohub@usb; do
        systemctl restart "$u"
        sleep 1
    done
    echo "audiohub installed: $(head -1 /etc/asound.conf | cut -c3-22), forwarders enabled"
else
    # No ALSA graph for this arch (Pi legacy, Pi KMS and x86 all have one now —
    # so this is an arch we have never shipped): enabling the forwarders would
    # just crash-loop them (alsaloop on missing PCMs). Leave them disabled
    # until a graph exists for this platform.
    systemctl disable audiohub@jack audiohub@hdmi audiohub@usb 2>/dev/null
    echo "audiohub: NO hub graph for $(uname -m) — forwarders left DISABLED (would"
    echo "          crash-loop). Provide an asound.conf hub graph and re-run."
fi
