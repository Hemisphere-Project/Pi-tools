#!/bin/bash

BASEPATH="$(dirname "$(readlink -f "$0")")"
DISTRO=''

echo "$BASEPATH"
cd "$BASEPATH"

# poetry install
npm install
ln -sf "$BASEPATH/webconf.service" /etc/systemd/system/
ln -sf "$BASEPATH/webconf" /usr/local/bin/

systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [webconf] web configuration
# webconf
" >> /boot/starter.txt
fi