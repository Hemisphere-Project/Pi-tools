#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install python3-pydbus -y

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S python-pydbus --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi


echo "#
#  List services that must be started by the starter !
#  To enable a service, uncomment by removing #
#

" > /boot/starter.txt 

ln -sf "$BASEPATH/starter.service" /etc/systemd/system/
ln -sf "$BASEPATH/starter" /usr/local/bin/

systemctl daemon-reload
systemctl enable starter

