#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
cd "$BASEPATH"

npm install
ln -sf "$BASEPATH/3615-disco" /usr/local/bin/
ln -sf "$BASEPATH/3615-disco.service" /etc/systemd/system/
systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [3615-disco] discovery web interface
# 3615-disco
" >> /boot/starter.txt
fi

echo "3615-disco INSTALLED"
echo