#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install -y xorg openbox xdotool python3-xdg

## ARCH Linux
elif [[ $(command -v pacman) ]]; then
    DISTRO='arch'
    echo "Distribution: $DISTRO"

    pacman -S xorg openbox --noconfirm --needed

## Plateform not detected ...
else
    echo "Distribution not detected:"
    echo "this script needs APT or PACMAN to run."
    echo ""
    echo "Please install manually."
    exit 1
fi

# Create 'hmini' user if missing
if ! id "hmini" &>/dev/null; then
    sudo useradd -m hmini
    echo "Created user: hmini"
fi

# Allow X run from remote
sed -i '/^allowed_users=/c\allowed_users=anybody' /etc/X11/Xwrapper.config

# Configure Openbox session
mkdir -p /etc/xdg/openbox
rm -f /etc/xdg/openbox/autostart
ln -sf "$BASEPATH/openbox-start" /etc/xdg/openbox/autostart

# Set permissions
chmod +x /etc/xdg/openbox/autostart

# xinit configuration
echo "exec openbox-session" > /root/.xinitrc
chmod +x /root/.xinitrc

ln -sf "$BASEPATH/xrun" /usr/local/bin/
ln -sf "$BASEPATH/xstop" /usr/local/bin/
systemctl daemon-reload

