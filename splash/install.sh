#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"
pacman -S fbida --noconfirm --needed
ln -sf "$BASEPATH/splash.service" /etc/systemd/system/
ln -sf "$BASEPATH/splash" /usr/local/bin/

systemctl daemon-reload
systemctl enable splash

# FILE=/boot/starter.txt
# if test -f "$FILE"; then
# echo "## [splash] splash screen
# # splash
# " >> /boot/starter.txt
# fi