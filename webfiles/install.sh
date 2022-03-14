#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install php avahi-utils -y

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S php avahi --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi


ln -sf "$BASEPATH/webfiles.service" /etc/systemd/system/
ln -sf "$BASEPATH/webfiles" /usr/local/bin/

systemctl daemon-reload

mkdir -p /data/var/webfiles
cp -r "$BASEPATH/www" /data/var/webfiles

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [webfiles] web file manager
# webfiles
" >> /boot/starter.txt
fi
