#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (use sudo)"
    exit 1
fi

# Determine Pi-tools directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/setup/installer.py" ]; then
    # Running from repo checkout
    PITOOLS_DIR="$SCRIPT_DIR"
else
    # Standard install to /opt/Pi-tools
    PITOOLS_DIR="/opt/Pi-tools"

    # Ensure git is available
    command -v git >/dev/null || { apt update && apt install -y git; }

    if [ -d "$PITOOLS_DIR/.git" ]; then
        echo "Updating Pi-tools..."
        git -C "$PITOOLS_DIR" pull --ff-only
    else
        echo "Cloning Pi-tools..."
        git clone https://github.com/Hemisphere-Project/Pi-tools.git "$PITOOLS_DIR"
    fi
fi

# Ensure python3
command -v python3 >/dev/null || { apt update && apt install -y python3; }

# Symlink to /opt if running from elsewhere
if [ "$PITOOLS_DIR" != "/opt/Pi-tools" ] && [ ! -e "/opt/Pi-tools" ]; then
    mkdir -p /opt
    ln -sfn "$PITOOLS_DIR" /opt/Pi-tools
fi

cd "$PITOOLS_DIR"
exec python3 -u setup/installer.py "$@"
