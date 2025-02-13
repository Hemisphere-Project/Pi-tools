#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"

echo "$BASEPATH"
cd "$BASEPATH"

# install filebrowser
curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

ln -sf "$BASEPATH/filebrowser.service" /etc/systemd/system/
ln -sf "$BASEPATH/filebrowser" /usr/local/bin/

systemctl daemon-reload

mkdir -p /data/var/filebrother
# cp -r "$BASEPATH/www" /data/var/webfiles

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [filebrother] web file manager
# filebrother
" >> /boot/starter.txt
fi
