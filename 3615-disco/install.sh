#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install python3-eventlet -y

    # RPi / RP64
    if [[ $(uname -m) = aarch64* || $(uname -m) = armv* ]]; then
        echo "ARM platform"
    fi

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S python-eventlet --noconfirm --needed

    # RPi / RP64
    if [[ $(uname -m) = armv* ]]; then
      echo "ARM platform"
    fi

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi


pip3 install -r requirements.txt
ln -sf "$BASEPATH/3615-disco" /usr/local/bin/
ln -sf "$BASEPATH/3615-disco.service" /etc/systemd/system/
systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [3615-disco] discovery web interface
# 3615-disco
" >> /boot/starter.txt
fi


echo "3615-disco INSTALLED"
echo