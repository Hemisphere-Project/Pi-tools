#!/bin/bash
BASEPATH="$(dirname "$(readlink -f "$0")")"

ln -sf "$BASEPATH/extendfs.service" /etc/systemd/system/
ln -sf "$BASEPATH/extendfs" /usr/local/bin/

systemctl daemon-reload

FILE=/boot/starter.txt
if test -f "$FILE"; then
echo "## [extendfs] Check if drive fingerprint changed, and resize last partition to fill FS
# extendfs
" >> /boot/starter.txt
fi
