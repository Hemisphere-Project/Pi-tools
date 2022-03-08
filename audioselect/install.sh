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


cp "$BASEPATH/asound.conf" /etc/asound.conf
ln -sf "$BASEPATH/audioselect.service" /etc/systemd/system/
ln -sf "$BASEPATH/audioselect" /usr/local/bin/
ln -sf "$BASEPATH/70-audioselect.rules" /etc/udev/rules.d/

systemctl daemon-reload

#systemctl enable audioselect
FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [audioselect] automated audio output on analog + usb (hotplug)
# audioselect
" >> /boot/starter.txt
fi

