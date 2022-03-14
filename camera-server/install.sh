#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
pacman -S v4l-utils nodejs npm --noconfirm --needed
cd "$BASEPATH/videopaint" && npm install

ln -sf "/opt/vc/bin/raspivid" /usr/local/bin/
ln -sf "$BASEPATH/camera-server.service" /etc/systemd/system/
ln -sf "$BASEPATH/camera-server" /usr/local/bin/

echo "
#
# Camera module #### BROKEN ON PI4 !
#
# start_file=start_x.elf
# fixup_file=fixup_x.dat
" >> /boot/config.txt

systemctl daemon-reload