#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    echo "deb https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list
    curl -s https://syncthing.net/release-key.txt | sudo apt-key add -
    apt update
    apt install syncthing -y

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S syncthing --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi


pip3 install -r "$BASEPATH/requirements.txt"

ln -sf "$BASEPATH/synczinc@.service" /etc/systemd/system/
ln -sf "$BASEPATH/synczinc" /usr/local/bin/

systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [synczinc] Syncthing synchro, use synczinc@peer or synczinc@master
# synczinc@peer
" >> /boot/starter.txt
fi