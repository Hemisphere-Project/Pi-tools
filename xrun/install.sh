#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

## xBIAN (DEBIAN / RASPBIAN / UBUNTU)
if [[ $(command -v apt) ]]; then
    DISTRO='xbian'
    echo "Distribution: $DISTRO"

    apt install -y xorg openbox lightdm lightdm-gtk-greeter

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

# Configure LightDM for manual start and autologin
sudo tee /etc/lightdm/lightdm.conf.d/50-hmini.conf > /dev/null <<EOL
[Seat:*]
autologin-user=hmini
autologin-session=openbox
greeter-show-manual-login=true
EOL

# Allow X run from remote
# sed -i '/^allowed_users=/c\allowed_users=anybody' /etc/X11/Xwrapper.config

# Disable automatic LightDM startup
systemctl mask --now lightdm.service

# Configure Openbox session
mkdir -p /etc/xdg/openbox
rm -f /etc/xdg/openbox/autostart
ln -sf "$BASEPATH/openbox-start" /etc/xdg/openbox/autostart

# Set permissions
chmod +x /etc/xdg/openbox/autostart


ln -sf "$BASEPATH/xrun" /usr/local/bin/
ln -sf "$BASEPATH/xstop" /usr/local/bin/
systemctl daemon-reload

