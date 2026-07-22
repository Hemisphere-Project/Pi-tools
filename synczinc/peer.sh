#!/bin/bash
export HOME=/root
CONFIG_HOME=/data/var/syncthing
DRIVEID_PATH=/data/var/sync-id
SYNC_PATH=/data/sync

# Boot (FAT) partition: /boot/firmware on modern Pi OS (Bookworm), /boot otherwise
BOOTDIR=$([ -d /boot/firmware ] && echo /boot/firmware || echo /boot)

cd "$(dirname "$(readlink -f "$0")")"

# MODE
MODE=${1:-peer}

# UNSYNC MODE
if [[ "$MODE" == "unsync" ]]; then
        echo ""
        echo ">>> Unsync ! <<<"
        echo ""
        SYNCSERVICE=$(grep '^synczinc' "$BOOTDIR/starter.txt" 2>/dev/null)
        [[ -n "$SYNCSERVICE" ]] && systemctl stop $SYNCSERVICE
        pkill syncthing 2>/dev/null
        rm -Rf "$CONFIG_HOME"
        rm -Rf "$SYNC_PATH"
        rm -f "$DRIVEID_PATH"
        sed -i '/^[^#]/ s/\(^.*synczinc.*$\)/#\ \1/' "$BOOTDIR/starter.txt" 2>/dev/null
        exit 0
fi

pkill syncthing 2>/dev/null

# COMMON API KEY (shared, committed key — tracked in SECURITY-REVIEW.md, deferred)
SYNC_API_KEY=$(cat key)

# CLONE DETECTION — fingerprint on the BARE disk serial (stable across a
# peer<->master mode change; the old "-$MODE" suffix false-triggered a wipe on
# every mode switch). An empty serial means "unknown" -> skip, never mis-trigger.
DRIVE=$(findmnt -n -o SOURCE --target /)
DRIVE_ID=$(udevadm info --name="$DRIVE" 2>/dev/null | sed -n 's/^E: ID_SERIAL=//p' | head -1)
[ -z "$DRIVE_ID" ] && DRIVE_ID=$(lsblk -no SERIAL "$DRIVE" 2>/dev/null | head -1)
LAST_DRIVE_ID=$(cat "$DRIVEID_PATH" 2>/dev/null)

if [ -z "$DRIVE_ID" ]; then
        echo ">>> Could not read a drive serial — skipping clone detection <<<"
elif [ "$DRIVE_ID" != "$LAST_DRIVE_ID" ]; then
        echo ">>> New drive detected (clone): regenerating syncthing identity <<<"
        rm -Rf "$CONFIG_HOME"
        # A master's /data/sync is the authoritative copy — NEVER auto-wipe it.
        # A demoted-master run (wrapper) sets SYNCZINC_KEEP_DATA=1 to preserve it.
        if [ "$MODE" == "master" ] || [ "${SYNCZINC_KEEP_DATA:-0}" == "1" ]; then
                echo "!!! authoritative /data/sync preserved — reconfigure/re-seed deliberately !!!"
        else
                rm -Rf "$SYNC_PATH"     # a peer re-syncs cleanly from the master
        fi
        echo "$DRIVE_ID" > "$DRIVEID_PATH"
else
        echo ">>> Drive-id is valid <<<"
fi

# Start syncthing with the forced API key
avahi-publish-service 'SyncZinc._'"$HOSTNAME" '_http._tcp.' 8384 &
STNODEFAULTFOLDER=1 syncthing -home="$CONFIG_HOME" -gui-apikey="$SYNC_API_KEY" -gui-address=0.0.0.0:8384
