#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    #  TODO

    # RPi / RP64
    if [[ $(uname -m) = aarch64* || $(uname -m) = armv* ]]; then
        echo "ARM platform"
    fi

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S xorg-server xorg-apps xorg-xinit openbox --noconfirm --needed
    pacman -S chromium --noconfirm --needed

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


echo "exec openbox-session" > ~/.xinitrc

rm /etc/xdg/openbox/autostart
ln -sf "$BASEPATH/openbox-chromium" /etc/xdg/openbox/autostart

rm -Rf ~/.config/chromium
mkdir -p /data/var/chromium && ln -sf /data/var/chromium ~/.config/chromium

rm /root/.Xauthority
ln -sf /tmp/.Xauthority /root/.Xauthority


# pip3 install -r requirements.txt
ln -sf "$BASEPATH/kiosk" /usr/local/bin/
ln -sf "$BASEPATH/kiosk.service" /etc/systemd/system/
systemctl daemon-reload

echo "
URL=https://www.hemisphere-project.com/
ROTATE=normal
" > /boot/kiosk.conf

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [kiosk] WPE WebKit/Cog kiosk from /boot/kiosk.url
# kiosk
" >> /boot/starter.txt
fi


echo "Kiosk INSTALLED"
echo
