#!/usr/bin/env bash
# fleet-lib.sh — laptop-side primitives for walking a roster of player hotspots.
#
# Sourced by bench/fleet-run; it is a library, not a command. EVERYTHING here is
# laptop-side: it drives NetworkManager and ssh. Nothing in this file runs on a
# player, and nothing in it decides what to deploy — the caller supplies that.
#
# The three things it exists to get right:
#
#   1. IDENTITY, NEVER ADDRESS. Every player answers on 10.0.0.1, so a stale or
#      auto-joined *neighbour* association hands you a perfectly working shell on
#      the wrong machine (field, 2026-09-03). fleet_walk_one compares `hostname`
#      against the roster name and REFUSES to act on a mismatch. A write to the
#      wrong player is the one failure this tool cannot take back, so the assert
#      sits between the join and the command, always, including on a retry.
#   2. THE UPLINK SURVIVES. Profiles are created `ipv4.never-default` +
#      `ipv4.ignore-auto-dns` (+ `ipv6.method disabled`), so associating with a
#      player never steals the laptop's default route or its resolver.
#   3. A DEAD AP COSTS SECONDS, NOT THE PASS. Every wait is deadline-bounded: a
#      hotspot that is not on air is a `miss` on the table, and the walk moves on.
#      Three of six cold boots came up in the hostapd state only a power-cycle
#      clears (2026-09-08), so missing players are the normal case, not the alarm.
#
# The PSK is read from the environment or a laptop-local file and is NEVER
# committed. The fleet key was rotated on 2026-09-04; a profile made with the old
# one fails at the 4-way handshake and NetworkManager reports it as `no-secrets`.

# ---- knobs (all overridable from the environment) ---------------------------
FLEET_TARGET_DEFAULT="${FLEET_TARGET_DEFAULT:-root@10.0.0.1}"
FLEET_PSK_FILE="${FLEET_PSK_FILE:-$HOME/.config/pitools/fleet.psk}"
FLEET_IFACE="${FLEET_IFACE:-}"          # wifi device; auto-detected when empty
FLEET_SSH_KEY="${FLEET_SSH_KEY:-}"      # pin one identity (see Trap 3 below)
FLEET_STATIC="${FLEET_STATIC:-}"        # laptop host octet: 10.0.0.<n>/24

# Trap 3, 2026-09-08: with several identities loaded the agent offers them all and
# the player's MaxAuthTries cuts the attempt before the right key is reached — it
# reads as "keys not authorized, password only". FLEET_SSH_KEY pins one.
# BatchMode keeps a password prompt from stalling an unattended walk forever.
FLEET_SSH_OPTS=(-o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3
                -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
                -o LogLevel=ERROR -o BatchMode=yes)
[ -n "$FLEET_SSH_KEY" ] && FLEET_SSH_OPTS+=(-o IdentitiesOnly=yes -i "$FLEET_SSH_KEY")

# ---- outcome vocabulary -----------------------------------------------------
# ok          joined, identity matched, command exited 0
# fail        identity matched, command exited non-zero  (NOT retried: it ran)
# miss        hotspot not on air / association refused    (retryable)
# unreachable associated, but ssh never answered          (retryable)
# wrong-host  answered as another player — REFUSED to act (retryable)
# timeout     per-player budget spent                     (retryable)
# dry         --dry-run, nothing was touched
FLEET_RETRYABLE="miss unreachable wrong-host timeout"

FLEET_RESULTS=()                        # "name\tstate\trc\tsecs\tdetail" per player

# ---- small helpers ----------------------------------------------------------
# Progress goes to stderr, the result table to stdout: `fleet-run … > table.txt`
# keeps the product and lets the noise scroll past.
fleet_say()  { printf '%s\n' "$*" >&2; }
fleet_step() { printf '    %s\n' "$*" >&2; }
fleet_now()  { date +%s; }

fleet_have() { command -v "$1" >/dev/null 2>&1; }

# Preconditions for a REAL walk. --dry-run deliberately skips this: the plan must
# be readable on a machine with no radio and no nmcli at all.
fleet_require_tools() {
  local missing=""
  for t in nmcli ssh timeout; do fleet_have "$t" || missing="$missing $t"; done
  [ -z "$missing" ] || { fleet_say "ERROR: missing on this laptop:$missing"; return 1; }
  return 0
}

fleet_iface() {
  [ -n "$FLEET_IFACE" ] && { printf '%s' "$FLEET_IFACE"; return 0; }
  nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

fleet_psk() {
  [ -n "${FLEET_PSK:-}" ] && { printf '%s' "$FLEET_PSK"; return 0; }
  [ -r "$FLEET_PSK_FILE" ] && { head -n1 "$FLEET_PSK_FILE" | tr -d '\r\n'; return 0; }
  return 1
}

# ---- roster -----------------------------------------------------------------
# Whitespace-separated, `#` comments and blank lines ignored:
#
#     <name> [ssid] [target]
#
# `name` is the player's HOSTNAME and IS the identity the assert checks — it is
# the only column that must be right. `ssid` defaults to the name (renaming a
# player renames its SSID: the durable `hostrename@<name>` line in
# /boot/starter.txt), `target` defaults to root@10.0.0.1.
#
# Emits one `name<TAB>ssid<TAB>target` line per player.
fleet_roster_read() {
  local file="$1" line name ssid target n=0
  [ -r "$file" ] || { fleet_say "ERROR: roster not readable: $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    # shellcheck disable=SC2086  # deliberate: split the roster row on whitespace
    set -- $line
    [ $# -gt 0 ] || continue
    name="$1"; ssid="${2:-$1}"; target="${3:-$FLEET_TARGET_DEFAULT}"
    printf '%s\t%s\t%s\n' "$name" "$ssid" "$target"
    n=$((n + 1))
  done < "$file"
  [ "$n" -gt 0 ] && return 0
  fleet_say "ERROR: roster has no players: $file"
  return 1
}

# ---- NetworkManager ---------------------------------------------------------
fleet_profile_exists() { nmcli -t -f NAME con show 2>/dev/null | grep -qxF "$1"; }

# Create the profile if it is missing; if it already exists, enforce ONLY the
# three keys that are safety rather than taste — autoconnect off (so a blip
# cannot silently hand us a neighbour), and never-default/ignore-auto-dns (so the
# laptop keeps its own route and resolver). A hand-made profile keeps everything
# else it has.
fleet_profile_ensure() {
  local ssid="$1" iface psk
  if fleet_profile_exists "$ssid"; then
    nmcli con mod "$ssid" connection.autoconnect no \
      ipv4.never-default yes ipv4.ignore-auto-dns yes >/dev/null 2>&1 \
      || fleet_step "note: could not pin existing profile '$ssid' (left as it is)"
    return 0
  fi
  iface="$(fleet_iface)"
  [ -n "$iface" ] || { fleet_step "no wifi interface (set FLEET_IFACE)"; return 1; }
  psk="$(fleet_psk)" || {
    fleet_step "no PSK: set FLEET_PSK or write it to $FLEET_PSK_FILE (rotated 2026-09-04)"
    return 1
  }
  local add=(con add type wifi ifname "$iface" con-name "$ssid" ssid "$ssid"
             wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk"
             connection.autoconnect no
             ipv4.never-default yes ipv4.ignore-auto-dns yes ipv6.method disabled)
  # DHCP on the hotspot works, but the player is ALWAYS 10.0.0.1, so a static
  # laptop address removes one thing that can hang in "connecting (configuring)".
  [ -n "$FLEET_STATIC" ] && add+=(ipv4.method manual ipv4.addresses "10.0.0.${FLEET_STATIC}/24")
  nmcli "${add[@]}" >/dev/null 2>&1 || { fleet_step "nmcli con add failed for '$ssid'"; return 1; }
  fleet_step "created profile '$ssid'"
  return 0
}

fleet_leave() { [ -n "${1:-}" ] && nmcli con down "$1" >/dev/null 2>&1; return 0; }

# Leaving at the end of each cycle is the default because a laptop that stays
# associated is exactly how Trap 1 bites the NEXT pass. --keep-joined relaxes it
# for a one-player poke; it never relaxes the wrong-host drop, which is safety.
FLEET_KEEP="${FLEET_KEEP:-0}"
fleet_leave_unless_kept() { [ "$FLEET_KEEP" = 1 ] || fleet_leave "$1"; }

# Associate, bounded by the remaining budget. A refusal here is a `miss`, and a
# miss is the expected state of a player whose hostapd died in operation.
fleet_join() {
  local ssid="$1" deadline="$2" wait
  wait=$((deadline - $(fleet_now)))
  [ "$wait" -gt 0 ] || return 1
  [ "$wait" -gt 60 ] && wait=60
  nmcli --wait "$wait" con up "$ssid" >/dev/null 2>&1
}

# ---- ssh --------------------------------------------------------------------
# Ask the player who it is. Bounded, quiet, and the ONLY thing trusted at
# 10.0.0.1 before a command is allowed to run.
fleet_hostname_of() {
  local target="$1" budget="$2"
  [ "$budget" -gt 0 ] || return 1
  timeout "$budget" ssh "${FLEET_SSH_OPTS[@]}" "$target" 'hostname' 2>/dev/null
}

# Poll until the player answers or the deadline passes. Association comes up
# before sshd is reachable, so "joined" is not "usable".
fleet_wait_ssh() {
  local target="$1" deadline="$2" host budget
  while :; do
    budget=$((deadline - $(fleet_now)))
    [ "$budget" -gt 0 ] || return 1
    [ "$budget" -gt 12 ] && budget=12
    host="$(fleet_hostname_of "$target" "$budget")" && [ -n "$host" ] && {
      printf '%s' "$host"; return 0
    }
    sleep 2
  done
}

# ---- the walk ---------------------------------------------------------------
fleet_record() { FLEET_RESULTS+=("$(printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5")"); }

fleet_is_retryable() {
  case " $FLEET_RETRYABLE " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# fleet_walk_one <name> <ssid> <target> <command> <deadline-secs> <join-secs> <local?>
# One player, one outcome, recorded. Never returns non-zero for a player-level
# failure — the table is the report, and the pass keeps going.
fleet_walk_one() {
  local name="$1" ssid="$2" target="$3" cmd="$4" budget="$5" joinb="$6" runlocal="$7"
  local t0 deadline joindl host rc out state detail

  t0="$(fleet_now)"; deadline=$((t0 + budget)); joindl=$((t0 + joinb))
  [ "$joindl" -gt "$deadline" ] && joindl="$deadline"
  fleet_say "== $name  (ssid=$ssid target=$target)"

  if ! fleet_profile_ensure "$ssid"; then
    fleet_record "$name" miss - "$(( $(fleet_now) - t0 ))" "no usable profile"
    return 0
  fi
  if ! fleet_join "$ssid" "$joindl"; then
    fleet_step "not on air (or association refused) — moving on"
    fleet_record "$name" miss - "$(( $(fleet_now) - t0 ))" "no association"
    fleet_leave_unless_kept "$ssid"
    return 0
  fi
  fleet_step "associated"

  if ! host="$(fleet_wait_ssh "$target" "$deadline")"; then
    state=unreachable; detail="associated, no ssh"
    [ "$(fleet_now)" -ge "$deadline" ] && { state=timeout; detail="budget spent before ssh"; }
    fleet_step "$detail"
    fleet_record "$name" "$state" - "$(( $(fleet_now) - t0 ))" "$detail"
    fleet_leave_unless_kept "$ssid"
    return 0
  fi

  # THE ASSERT. Everything above this line is plumbing; this is the safety.
  if [ "$host" != "$name" ]; then
    fleet_step "REFUSED: answered as '$host', roster says '$name' — not running the command"
    fleet_leave "$host"          # drop the neighbour we actually landed on
    fleet_leave "$ssid"
    fleet_record "$name" wrong-host - "$(( $(fleet_now) - t0 ))" "answered as $host"
    return 0
  fi
  fleet_step "identity ok: $host"

  local budget_left=$((deadline - $(fleet_now)))
  if [ "$budget_left" -le 0 ]; then
    fleet_record "$name" timeout - "$(( $(fleet_now) - t0 ))" "budget spent before command"
    fleet_leave_unless_kept "$ssid"
    return 0
  fi

  if [ "$runlocal" = 1 ]; then
    out="$(FLEET_NAME="$name" FLEET_SSID="$ssid" FLEET_TARGET="$target" \
           timeout "$budget_left" sh -c "$cmd" 2>&1)"; rc=$?
  else
    out="$(timeout "$budget_left" ssh "${FLEET_SSH_OPTS[@]}" "$target" "$cmd" 2>&1)"; rc=$?
  fi
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    | /' >&2

  case "$rc" in
    0)   state=ok;      detail="command ok" ;;
    124) state=timeout; detail="command hit the ${budget}s budget" ;;
    255) state=unreachable; detail="ssh transport died mid-command" ;;
    *)   state=fail;    detail="command exited $rc" ;;
  esac
  fleet_step "$state ($detail)"
  fleet_record "$name" "$state" "$rc" "$(( $(fleet_now) - t0 ))" "$detail"
  fleet_leave_unless_kept "$ssid"
  return 0
}

# ---- the table --------------------------------------------------------------
# stdout, one line per player, in roster order. Retries REPLACE the first
# outcome, so the table always has exactly one row per player.
fleet_table() {
  local r name state rc secs detail w=4
  for r in "${FLEET_RESULTS[@]}"; do
    name="${r%%$'\t'*}"
    [ "${#name}" -gt "$w" ] && w="${#name}"
  done
  printf '%-*s  %-11s  %4s  %5s  %s\n' "$w" PLAYER OUTCOME RC SECS DETAIL
  for r in "${FLEET_RESULTS[@]}"; do
    IFS=$'\t' read -r name state rc secs detail <<< "$r"
    printf '%-*s  %-11s  %4s  %5s  %s\n' "$w" "$name" "$state" "$rc" "$secs" "$detail"
  done
}

fleet_count_state() {
  local want="$1" r n=0
  for r in "${FLEET_RESULTS[@]}"; do
    case "$r" in *$'\t'"$want"$'\t'*) n=$((n + 1)) ;; esac
  done
  printf '%s' "$n"
}

# Names whose outcome is retryable — the roster for the --retry-misses pass.
fleet_retry_names() {
  local r name state
  for r in "${FLEET_RESULTS[@]}"; do
    IFS=$'\t' read -r name state _ _ _ <<< "$r"
    fleet_is_retryable "$state" && printf '%s\n' "$name"
  done
}

# Drop a player's first-pass row so the retry can record the real one.
fleet_forget() {
  local name="$1" r keep=()
  for r in "${FLEET_RESULTS[@]}"; do
    case "$r" in "$name"$'\t'*) ;; *) keep+=("$r") ;; esac
  done
  FLEET_RESULTS=("${keep[@]+"${keep[@]}"}")
}

# A retry appends, so put the rows back in roster order before printing: the
# table is read as "the fleet", and a fleet that reshuffles itself by who failed
# is a table you have to re-read every time.
fleet_reorder() {
  local want r name ordered=()
  for want in "$@"; do
    for r in "${FLEET_RESULTS[@]}"; do
      name="${r%%$'\t'*}"
      [ "$name" = "$want" ] && { ordered+=("$r"); break; }
    done
  done
  FLEET_RESULTS=("${ordered[@]+"${ordered[@]}"}")
}
