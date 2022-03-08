#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install alsa alsa-utils -y

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S alsa alsa-utils --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi

ln -sf "$BASEPATH/rtpmidi.service" /etc/systemd/system/
ln -sf "$BASEPATH/rtpmidi" /usr/local/bin/

systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [rtpmidi] rtp Midi (CoreMidi)
# rtpmidi
" >> /boot/starter.txt
fi