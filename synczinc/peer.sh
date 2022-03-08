#!/bin/bash
export HOME=/root
CONFIG_HOME=/data/var/syncthing
SYNC_PATH=/data/sync
DRIVEID_PATH=/data/var/sync-id

pkill syncthing
cd "$(dirname "$(readlink -f "$0")")"

# MODE
MODE=${1:-peer}

# UNSYNC MODE
if [[ "$MODE" == "unsync" ]]; then
        echo ""
        echo ">>> Unsync ! <<<"
        echo ""
        # echo "Stop synczinc service launched by /boot/starter.txt"
        SYNCSERVICE=$(cat /boot/starter.txt | grep '^synczinc')
        [[ ! -z "$SYNCSERVICE" ]] && systemctl stop $SYNCSERVICE
        # echo "rm -Rf $CONFIG_HOME"
        rm -Rf $CONFIG_HOME
        # echo "rm -Rf $SYNC_PATH"
        rm -Rf $SYNC_PATH
        # echo "rm -f $DRIVEID_PATH"
        rm -f $DRIVEID_PATH
        # echo "Disable synczinc service in /boot/starter.txt"
        sed -i '/^[^#]/ s/\(^.*synczinc.*$\)/#\ \1/' /boot/starter.txt
        exit 0
fi

# COMMON API KEY
SYNC_API_KEY=$(cat key)
echo "common API key: $SYNC_API_KEY"

# CHECK IF SD HAS BEEN CLONED !
DRIVE=$(findmnt -n -o SOURCE --target /)
DRIVE_ID=$(udevadm info --name=$DRIVE | grep ID_SERIAL= | cut -d '=' -f2)-$MODE
LAST_DRIVE_ID=$(cat $DRIVEID_PATH)

if [[ $DRIVE_ID == $LAST_DRIVE_ID ]]
then
        echo ""
        echo ">>> Drive-id is valid <<<"
        echo ""
else
        echo ""
        echo ">>> New drive detected, clear syncthing config and data <<<"
        echo ""

        rm -Rf $CONFIG_HOME
        rm -Rf $SYNC_PATH
        echo $DRIVE_ID > $DRIVEID_PATH
fi

# Start syncthing with forced API-key
avahi-publish-service 'SyncZinc._'$HOSTNAME '_http._tcp.' 8384 &
STNODEFAULTFOLDER=1 syncthing -home=$CONFIG_HOME -gui-apikey="$SYNC_API_KEY" -gui-address=0.0.0.0:8384
