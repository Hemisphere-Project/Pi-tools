#!/usr/bin/env bash
# fleet-patch-hostapd.sh — patch existing RastaOS players to the hostapd AP fix.
#
# Run from the laptop. Converts each player's Wi-Fi hotspot from NetworkManager's
# wpa_supplicant AP path (unusable by Apple clients on the Broadcom fullmac chips)
# to hostapd, by installing the role-aware network-tools + hostapd and running
# setnet. Idempotent — safe to re-run. No reflash.
#
# Reach each player over SSH:
#   - via its hotspot, joined from a Linux laptop or Android phone (Macs cannot
#     join until they are patched), target root@10.0.0.1 ; or
#   - over ethernet, target root@<player-ip>.
#
# Because field clones can share an SSH host key (pi-tools#t-006), host-key
# checking is disabled here — this is a trusted LAN provisioning task.
#
#   Usage: fleet-patch-hostapd.sh [-n] [-r] [target ...]
#     -n   dry-run: preflight + show plan, change nothing
#     -r   reboot each player after patching (default: live switch, no reboot)
#     target   ssh target(s); default: root@10.0.0.1
#
#   HOSTAPD_DEB=/path/to/hostapd_*_armhf.deb   override the bundled .deb
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NT_DIR="$REPO_DIR/network-tools"
MODULE_FILES=(setnet 'hostapd@.service' module.ini)

HOSTAPD_DEB="${HOSTAPD_DEB:-$HOME/.cache/pitools-fleet/hostapd_2%3a2.7+git20190128+0c1e29f-6+deb10u4_armhf.deb}"
SSH_OPTS=(-o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
DEFAULT_TARGET="root@10.0.0.1"

DRY=0
REBOOT=0
while getopts "nrh" o; do
  case "$o" in
    n) DRY=1 ;;
    r) REBOOT=1 ;;
    *) sed -n '2,20p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("$DEFAULT_TARGET")

# ── Preconditions on the laptop ──────────────────────────────────────────────
for f in "${MODULE_FILES[@]}"; do
  [ -f "$NT_DIR/$f" ] || { echo "ERROR: missing module file $NT_DIR/$f"; exit 1; }
done
if [ ! -f "$HOSTAPD_DEB" ]; then
  echo "ERROR: hostapd .deb not found: $HOSTAPD_DEB"
  echo "  Get it from any player:  scp root@<player>:/var/cache/apt/archives/hostapd_*_armhf.deb ~/.cache/pitools-fleet/"
  echo "  or point HOSTAPD_DEB=/path/to/hostapd_*_armhf.deb"
  exit 1
fi

# The apply script that runs ON each player (rw → install → reconcile → ro).
read -r -d '' REMOTE_APPLY <<'REMOTE'
set -uo pipefail
STAGE=/tmp/pitools-patch
NT=/opt/Pi-tools/network-tools
REBOOT="${1:-0}"

finish_ro() { sync; ro >/dev/null 2>&1 || true; }
trap finish_ro EXIT

command -v rw >/dev/null 2>&1 || { echo "  FAIL: no rw/ro helper — not a RastaOS player?"; exit 2; }
[ -d "$NT" ] || { echo "  FAIL: $NT missing — Pi-tools not installed?"; exit 2; }

rw >/dev/null 2>&1 || { echo "  FAIL: cannot remount rootfs read-write"; exit 2; }

# 1. Role-aware network-tools module files.
cp "$STAGE/setnet" "$STAGE/hostapd@.service" "$STAGE/module.ini" "$NT/" || { echo "  FAIL: copy module files"; exit 2; }
chmod 755 "$NT/setnet"
echo "  module files updated"

# 2. hostapd (offline dpkg install; deps already present via wpasupplicant).
if command -v hostapd >/dev/null 2>&1; then
  echo "  hostapd already installed ($(hostapd -v 2>&1 | head -1))"
else
  dpkg -i "$STAGE"/hostapd_*.deb >/dev/null 2>&1 || { echo "  FAIL: hostapd dpkg -i"; exit 2; }
  echo "  hostapd installed"
fi

# 3. Per-interface service + neutralize the stock single-instance unit.
ln -sf "$NT/hostapd@.service" /etc/systemd/system/hostapd@.service
systemctl mask hostapd.service >/dev/null 2>&1 || true
systemctl daemon-reload
echo "  hostapd@.service installed, stock hostapd.service masked"

# 4. Reconcile: mode=ap profiles -> hostapd, the rest stay on NetworkManager.
echo "  running setnet..."
setnet 2>&1 | sed -n 's/^\[setnet\] \(AP \|Reconciling\).*/    &/p'

# 5. Verify each interface we set up as an AP.
ok=1
for drop in /etc/NetworkManager/conf.d/50-hostapd-*.conf; do
  [ -e "$drop" ] || continue
  ifc=$(basename "$drop" | sed -E 's/^50-hostapd-(.*)\.conf$/\1/')
  act=$(systemctl is-active "hostapd@$ifc" 2>/dev/null)
  typ=$(iw "$ifc" info 2>/dev/null | sed -n 's/.*type //p')
  ssid=$(sed -n 's/^ssid=//p' "/etc/hostapd/$ifc.conf" 2>/dev/null)
  if [ "$act" = active ] && [ "$typ" = AP ]; then
    echo "  VERIFY $ifc: hostapd active, AP up, ssid=$ssid  [OK]"
  else
    echo "  VERIFY $ifc: hostapd=$act type=$typ  [FAIL]"; ok=0
  fi
done
[ "$ok" = 1 ] || { echo "  RESULT: FAIL"; exit 3; }

if [ "$REBOOT" = 1 ]; then
  echo "  RESULT: OK — rebooting"
  ( sleep 1; systemctl reboot ) >/dev/null 2>&1 &
else
  echo "  RESULT: OK"
fi
REMOTE

# ── Per-target patch ─────────────────────────────────────────────────────────
patch_one() {
  local t="$1" host
  host=$(ssh "${SSH_OPTS[@]}" "$t" 'hostname' 2>/dev/null) || { echo "  UNREACHABLE"; return 1; }
  local owner
  owner=$(ssh "${SSH_OPTS[@]}" "$t" 'systemctl is-active "hostapd@*" >/dev/null 2>&1 && echo hostapd || echo wpa_supplicant' 2>/dev/null)
  echo "  host=$host  current-AP=$owner"

  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] would: stage module+deb -> rw -> install hostapd -> setnet -> verify -> ro"
    return 0
  fi

  ssh "${SSH_OPTS[@]}" "$t" 'rm -rf /tmp/pitools-patch && mkdir -p /tmp/pitools-patch' || { echo "  FAIL: staging dir"; return 1; }
  scp -q "${SSH_OPTS[@]}" "$NT_DIR/setnet" "$NT_DIR/hostapd@.service" "$NT_DIR/module.ini" "$HOSTAPD_DEB" "$t":/tmp/pitools-patch/ \
    || { echo "  FAIL: scp artifacts"; return 1; }
  ssh "${SSH_OPTS[@]}" "$t" "bash -s $REBOOT" <<< "$REMOTE_APPLY"
}

echo "== Pi-tools hostapd fleet patch =="
echo "   module : $NT_DIR"
echo "   hostapd: $(basename "$HOSTAPD_DEB")"
echo "   targets: ${TARGETS[*]}    dry-run=$DRY reboot=$REBOOT"
echo
pass=0; fail=0
for t in "${TARGETS[@]}"; do
  echo "== $t =="
  if patch_one "$t"; then pass=$((pass+1)); else fail=$((fail+1)); fi
  echo
done
echo "== done: $pass ok, $fail failed =="
[ "$fail" -eq 0 ]
