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


# Disable automatic LightDM startup
sudo systemctl disable lightdm.service

# Configure Openbox session
sudo mkdir -p /etc/xdg/openbox
sudo tee /etc/xdg/openbox/autostart > /dev/null <<'EOL'
#!/bin/bash

# Set X authority in tmpfs
export XAUTHORITY=/tmp/.Xauthority

# Configure multi-monitor layout (extended mode)
xrandr --auto
connected_outputs=$(xrandr | grep " connected" | cut -d' ' -f1)
if [ $(echo "$connected_outputs" | wc -l) -gt 1 ]; then
    xrandr --output $(echo "$connected_outputs" | head -1) --auto --primary
    for display in $(echo "$connected_outputs" | tail -n +2); do
        xrandr --output $display --auto --right-of $(echo "$connected_outputs" | head -1)
    done
fi

# Start applications (customize as needed)
# chromium --kiosk "http://your-url" &
# mpv --fs /path/to/video &
EOL

# Set permissions
sudo chmod +x /etc/xdg/openbox/autostart


ln -sf "$BASEPATH/xrun" /usr/local/bin/
ln -sf "$BASEPATH/xstop" /usr/local/bin/
systemctl daemon-reload

