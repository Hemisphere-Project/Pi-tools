#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"

pacman -S bluez bluez-utils bluez-libs usbutils python-pybluez --noconfirm --needed
echo "AutoEnable=true" >> /etc/bluetooth/main.conf

ln -sf "$BASEPATH/bluetooth-pi.service" /etc/systemd/system/
systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [bluetooth-pi] attach controller 
# bluetooth-pi
" >> /boot/starter.txt
fi

