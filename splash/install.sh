#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install fbi -y

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S fbida --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi



ln -sf "$BASEPATH/splash.service" /etc/systemd/system/
ln -sf "$BASEPATH/splash" /usr/local/bin/

systemctl daemon-reload
systemctl enable splash

# FILE=/boot/starter.txt
# if test -f "$FILE"; then
# echo "## [splash] splash screen
# # splash
# " >> /boot/starter.txt
# fi