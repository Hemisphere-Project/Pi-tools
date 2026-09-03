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
# When the SSH session rides the very hotspot being swapped, the link drops for a
# few seconds while hostapd takes over. The remote apply ignores that HUP, journals
# itself to /tmp/pitools-patch/apply.log, and this script re-joins to fetch the
# outcome — so a dropped session is not a failed patch.
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
SSH_OPTS=(-o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
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

# The session we run in usually rides the hotspot we are about to swap: outlive
# the drop, and leave a journal + exit code the laptop can fetch once it re-joins.
trap '' HUP PIPE
exec > >(tee -p -a "$STAGE/apply.log") 2>&1
finish() { local rc=$?; sync; ro >/dev/null 2>&1 || true; echo "$rc" > "$STAGE/apply.rc"; }
trap finish EXIT

command -v rw >/dev/null 2>&1 || { echo "  FAIL: no rw/ro helper — not a RastaOS player?"; exit 2; }
[ -d "$NT" ] || { echo "  FAIL: $NT missing — Pi-tools not installed?"; exit 2; }

rw >/dev/null 2>&1 || { echo "  FAIL: cannot remount rootfs read-write"; exit 2; }

# Order matters: hostapd first, the module files LAST. A failure part-way must
# leave the player as it was — a new role-aware setnet without hostapd takes the
# interface away from NetworkManager at the next boot and leaves NO hotspot at
# all (oyiri-48, 2026-09-03: dpkg failed, reboot, dark player).

# 1. hostapd (offline dpkg install; deps already present via wpasupplicant).
#    The stock single-instance unit is masked up front: dpkg's postinst would
#    otherwise try to start it without a config.
systemctl mask hostapd.service >/dev/null 2>&1 || true
if dpkg-query -W -f='${Status}' hostapd 2>/dev/null | grep -q "install ok installed"; then
  echo "  hostapd already installed ($(hostapd -v 2>&1 | head -1))"
else
  if ! out=$(dpkg -i "$STAGE"/hostapd_*.deb 2>&1); then
    echo "  FAIL: hostapd dpkg -i"; echo "$out" | grep -iE "error|fail|cannot|unable|no space" | tail -4 | sed 's/^/    /'; exit 2
  fi
  echo "  hostapd installed"
fi

# 2. Per-interface service.
ln -sf "$NT/hostapd@.service" /etc/systemd/system/hostapd@.service
systemctl daemon-reload
echo "  hostapd@.service installed, stock hostapd.service masked"

# 3. Role-aware network-tools module files — last, setnet last of all.
cp "$STAGE/hostapd@.service" "$STAGE/module.ini" "$NT/" && cp "$STAGE/setnet" "$NT/setnet" \
  || { echo "  FAIL: copy module files"; exit 2; }
chmod 755 "$NT/setnet"
echo "  module files updated"

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
  local rc=$?
  [ "$rc" -ne 255 ] && return "$rc"

  # Transport died — expected when we ride the hotspot being swapped to hostapd.
  # The remote apply keeps going; re-join and fetch its outcome.
  # Every player answers on the same hotspot address, and a laptop that knows
  # several of them may auto-join a neighbour after the drop — so trust nothing
  # until the hostname matches the one we started on.
  echo "  ssh dropped (hotspot swap) — waiting for $host to come back..."
  local deadline=$((SECONDS + 150)) out h up
  while [ "$SECONDS" -lt "$deadline" ]; do
    sleep 5
    out=$(ssh "${SSH_OPTS[@]}" "$t" 'hostname; cut -d. -f1 /proc/uptime; cat /tmp/pitools-patch/apply.rc 2>/dev/null' 2>/dev/null) || continue
    { read -r h; read -r up; read -r rc; } <<< "$out"
    if [ "$h" != "$host" ]; then
      echo "  re-joined $h, not $host — re-join ${host}'s hotspot"
      # Best effort: the laptop profile is usually named after the SSID (= hostname).
      command -v nmcli >/dev/null 2>&1 && nmcli -t -f NAME con show 2>/dev/null | grep -qx "$host" \
        && nmcli con up "$host" >/dev/null 2>&1
      continue
    fi
    if [ -z "$rc" ]; then
      if [ "$up" -lt 90 ] 2>/dev/null; then
        echo "  $host rebooted (up ${up}s) — outcome lost with /tmp; re-run to VERIFY (idempotent)"
        return 0
      fi
      continue                             # still applying
    fi
    ssh "${SSH_OPTS[@]}" "$t" 'cat /tmp/pitools-patch/apply.log' 2>/dev/null | sed -n '/running setnet/,$p' | tail -n +2
    return "$rc"
  done
  echo "  FAIL: no outcome within 150s — re-run once the hotspot is back (idempotent)"
  return 1
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
