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

    pacman -S --needed --noconfirm unzip npm
    pacman -S --needed --noconfirm djvulibre ghostscript libheif libjpeg libavif libjxl libraw librsvg libwebp libwmf libxml2 ocl-icd openexr openjpeg2 pango
    pacman -S --needed --noconfirm geoclue gst-libav gst-plugins-base gst-plugins-bad gst-plugins-good gst-plugins-ugly gst-plugin-wp
    pacman -S --needed --noconfirm alsa-utils
    pacman -S --needed --noconfirm wpewebkit

    pacman -S --needed --noconfirm weston
    groupadd weston
    groupadd weston-launch
    usermod -a -G wheel,games,power,optical,storage,scanner,lp,audio,video,render,weston,weston-launch pi
    
    pikaur -S cog --noconfirm

    mkdir -p ~/.config
echo "[core]
idle-time=0
repaint-window=15
require-input=false

[shell]
client=/home/pi/wpe
animation=none
close-animation=none
startup-animation=none
locking=false

[output]
name=
mode=
">~/.config/weston.ini


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


# pip3 install -r requirements.txt
ln -sf "$BASEPATH/kiosk" /usr/local/bin/
ln -sf "$BASEPATH/kiosk.service" /etc/systemd/system/
systemctl daemon-reload

echo "https://www.hemisphere-project.com/" > /boot/kiosk.url

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [kiosk] WPE WebKit/Cog kiosk from /boot/kiosk.url
# kiosk
" >> /boot/starter.txt
fi


echo "Kiosk INSTALLED"
echo
