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

# Accept the folders an introducer (the fleet master) offers us. Syncthing's own
# autoAcceptFolders REFUSES when the target path already exists — and /data/sync/<show>
# is created by the player before the master's offer arrives, so a fresh clone sat
# forever on a pending "sync" folder ("Failed to auto-accept ... path conflict",
# kmini-002, 2026-09-12; kmini-001 never synced either). Poll the pending offers and
# add each one explicitly at /data/<id> (sendreceive, like the whole fleet).
accept_offers() {
        local api="http://127.0.0.1:8384/rest" h="X-API-Key: $SYNC_API_KEY"
        while sleep 20; do
                curl -fs -m 4 -H "$h" "$api/system/ping" >/dev/null 2>&1 || continue
                curl -fs -m 4 -H "$h" "$api/cluster/pending/folders" 2>/dev/null | python3 - "$api" "$SYNC_API_KEY" "$SYNC_PATH" <<'PY' 2>&1 | sed 's/^/[synczinc] /'
import json, sys, urllib.request
api, key, syncpath = sys.argv[1:4]
try:
    pending = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def call(path, data=None, method='GET'):
    req = urllib.request.Request(api + path, data=json.dumps(data).encode() if data is not None else None, method=method)
    req.add_header('X-API-Key', key); req.add_header('Content-Type', 'application/json')
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.loads(r.read() or b'null')
introducers = {d['deviceID'] for d in call('/config/devices') if d.get('introducer')}
have = {f['id'] for f in call('/config/folders')}
for fid, info in pending.items():
    offered = [d for d in info.get('offeredBy', {}) if d in introducers]
    if not offered or fid in have:
        continue
    path = syncpath if fid == 'sync' else '/data/' + fid
    call('/config/folders', {'id': fid, 'label': info['offeredBy'][offered[0]].get('label') or fid, 'path': path,
         'type': 'sendreceive', 'devices': [{'deviceID': d} for d in offered], 'fsWatcherEnabled': True}, 'POST')
    print(f"accepted folder '{fid}' at {path} from introducer {offered[0][:7]}")
PY
        done
}
accept_offers &

# Start syncthing with the forced API key
avahi-publish-service 'SyncZinc._'"$HOSTNAME" '_http._tcp.' 8384 &
STNODEFAULTFOLDER=1 syncthing -home="$CONFIG_HOME" -gui-apikey="$SYNC_API_KEY" -gui-address=0.0.0.0:8384
