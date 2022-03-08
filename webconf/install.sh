#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    # apt install python3-liblo liblo7 cython3 python3-eventlet python3-markupsafe -y

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    # pacman -S python-pyliblo liblo cython python-eventlet python-markupsafe --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi

pip3 install -r requirements.txt
ln -sf "$BASEPATH/webconf.service" /etc/systemd/system/
ln -sf "$BASEPATH/webconf" /usr/local/bin/

systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [webconf] web configuration
# webconf
" >> /boot/starter.txt
fi