#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"
ln -sf "$BASEPATH/hostrename@.service" /etc/systemd/system/
ln -sf "$BASEPATH/hostrename" /usr/local/bin/

systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [hostrename] change name 
# hostrename@hberry-000
" >> /boot/starter.txt
fi

