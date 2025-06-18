#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install lockfile-progs dosfstools xfsprogs hfsprogs -y

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S lockfile-progs dosfstools xfsprogs --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi


mkdir -p /mnt/usb{0..7}

ln -sf "$BASEPATH/usbautomount" /usr/local/bin/
ln -sf "$BASEPATH/90-usbautomount.rules" /etc/udev/rules.d/
ln -sf "$BASEPATH/usbautomount@.service" /etc/systemd/system/

systemctl daemon-reload
udevadm control --reload-rules && udevadm trigger


