#!/usr/bin/env bash
# burn-fsck-desk — desk test of burn-batch's phase 1 on an image FILE
# (pi-tools#t-062): a clean golden comes out byte-identical — sha256 AND mtime —
# and only a filesystem the read-only check finds unclean is ever written.
#
#   sudo bash bench/burn-fsck-desk.sh        # exit 0 green, 1 red, 2 could not run
#
# Root, for losetup: phase 1 runs on the real loop devices, not on a stub.
# Layer 1 builds a RastaOS-shaped image (p1 boot vfat, p2 rootfs ext4, p3 /data
# ext4) and runs `burn-batch --fsck-only` on it clean, then with each state the
# phase exists for, and under `-n --fsck-only` on a dirty one, which must name
# the repairs and write nothing (pi-tools#t-070). Layer 2 runs a REAL burn —
# phases 1 to 4, dd and cmp — onto a RAM card this script creates with the
# kernel's scsi_debug (removable, 300 MB) and removes after; it writes no other
# device. No scsi_debug → layer 2 is skipped, and says so.
#
# Not proven here: a real reader on a USB hub, a real SD card, a golden whose
# journal holds real transactions (debugfs only raises the needs_recovery flag).
#
# BURN_BATCH=<path> runs another copy of the tool (a mutation test).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
TOOL=${BURN_BATCH:-bench/burn-batch}
[ "$(id -u)" = 0 ] || { echo "needs root for losetup: sudo bash $0"; exit 2; }
for c in sfdisk mkfs.vfat mkfs.ext4 debugfs fsck.fat e2fsck losetup; do
    command -v "$c" >/dev/null || { echo "no $c"; exit 2; }
done
T=$(mktemp -d)
CARD_LOADED=0
cleanup() {
    [ "$CARD_LOADED" = 1 ] && { udevadm settle -t 10 2>/dev/null; modprobe -r scsi_debug 2>/dev/null; }
    rm -rf "$T"
}
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; [ -n "${OUT:-}" ] && tail -6 <<<"$OUT" | sed "s/^/       > /"; }
OUT=""
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# RastaOS-shaped: p1 boot FAT32, p2 rootfs, p3 /data — sectors of 512 B
P1=8192; P1N=131072; P2=139264; P2N=196608; P3=335872; P3N=131072
IMG=$T/golden.img
build() {
    rm -f "$IMG"; truncate -s 228M "$IMG"
    printf 'label: dos\nstart=%s,size=%s,type=c\nstart=%s,size=%s,type=83\nstart=%s,size=%s,type=83\n' \
        "$P1" "$P1N" "$P2" "$P2N" "$P3" "$P3N" | sfdisk -q "$IMG" >/dev/null
    mkdir -p "$T/root/etc" "$T/data/media"
    echo player-007 > "$T/root/etc/hostname"
    head -c 8M /dev/urandom > "$T/data/media/01_FILM.mp4"
    # p1 formatted in its own file, then laid in: mkfs.vfat --offset is dosfstools
    # 4.2's, and 4.1 (buster — the rig's players) refused it unheard, leaving p1
    # unformatted and cases 1-2 red there (pi-tools#t-070)
    rm -f "$T/p1fs"
    mkfs.vfat -F 32 -s 1 -n boot -h "$P1" -C "$T/p1fs" $(( P1N / 2 )) >/dev/null 2>&1 \
        || { echo "could not build the fixture: mkfs.vfat failed"; exit 2; }
    dd if="$T/p1fs" of="$IMG" bs=512 seek="$P1" conv=notrunc,sparse status=none; rm -f "$T/p1fs"
    mkfs.ext4 -q -F -L rootfs -E offset=$(( P2 * 512 )) -d "$T/root" "$IMG" $(( P2N / 2 ))K
    mkfs.ext4 -q -F -L data -E offset=$(( P3 * 512 )) -d "$T/data" "$IMG" $(( P3N / 2 ))K
    touch -d '2026-11-07 12:00' "$IMG"          # the golden's capture day
}
sha()   { sha256sum < "$IMG" | cut -d' ' -f1; }
mt()    { stat -c %y "$IMG"; }
part()  { dd if="$IMG" bs=512 skip="$1" count="$2" status=none | sha256sum | cut -d' ' -f1; }
ext()   { echo "$IMG?offset=$(( $1 * 512 ))"; }
sb()    { debugfs -c -R 'stats -h' "$(ext "$1")" 2>/dev/null | sed -n "s/^$2: *//p"; }
p1_clean() { dd if="$IMG" of="$T/p1" bs=512 skip="$P1" count="$P1N" status=none; fsck.fat -n "$T/p1" >/dev/null 2>&1; }
p3_clean() { case " $(sb "$P3" 'Filesystem features') " in *" needs_recovery "*) return 1 ;; esac
             [ "$(sb "$P3" 'Filesystem state')" = clean ] && e2fsck -fn "$(ext "$P3")" >/dev/null 2>&1; }
film_ok()  { debugfs -R "dump media/01_FILM.mp4 $T/out" "$(ext "$P3")" >/dev/null 2>&1 \
             && cmp -s "$T/out" "$T/data/media/01_FILM.mp4"; }
fsck_only() { OUT=$(bash "$TOOL" --fsck-only "$IMG" 2>&1); RC=$?; }
stable() {  # stable <label>: the next --fsck-only writes nothing
    local s m; s=$(sha); m=$(mt); fsck_only
    check "$1: a second run exits 0" '[ "$RC" = 0 ]'
    check "$1: a second run says not written" '[[ "$OUT" == *"image clean, not written"* ]]'
    check "$1: a second run leaves sha256 and mtime as they were" '[ "$(sha)" = "$s" ] && [ "$(mt)" = "$m" ]'
}

echo "== 1. clean golden — checked, never written"
build; S0=$(sha); M0=$(mt); LC0=$(sb "$P3" "Last checked")
check "precondition: p1 and p3 clean" 'p1_clean && p3_clean'
sleep 1                                     # a stamp would now read a later second
fsck_only
check "exit 0" '[ "$RC" = 0 ]'
check "says: image clean, not written" '[[ "$OUT" == *"image clean, not written"* ]]'
check "sha256 unchanged" '[ "$(sha)" = "$S0" ]'
check "mtime unchanged" '[ "$(mt)" = "$M0" ]'
check "p3 last-checked time not stamped" '[ -n "$LC0" ] && [ "$(sb "$P3" "Last checked")" = "$LC0" ]'
fsck_only
check "a second run: sha256 and mtime still the capture's" '[ "$(sha)" = "$S0" ] && [ "$(mt)" = "$M0" ]'

echo "== 2. /boot vfat dirty bit (the rw/ro helper's) — repaired, nothing else written"
build; printf '\001' | dd of="$IMG" bs=1 seek=$(( P1 * 512 + 65 )) conv=notrunc status=none
touch -d '2026-11-07 12:00' "$IMG"
check "precondition: fsck.fat -n finds it" '! p1_clean'
B2=$(part "$P2" "$P2N"); B3=$(part "$P3" "$P3N")
fsck_only
check "exit 0 — a repair that worked is not a failure" '[ "$RC" = 0 ]'
check "says: image repaired" '[[ "$OUT" == *"image repaired, clean now"* ]]'
check "p1 clean after" p1_clean
check "p2 and p3 bytes untouched" '[ "$(part "$P2" "$P2N")" = "$B2" ] && [ "$(part "$P3" "$P3N")" = "$B3" ]'
stable "dirty bit"

echo "== 3. /data unreplayed journal — e2fsck -fn alone says 0 here"
build; debugfs -w -R "feature needs_recovery" "$(ext "$P3")" >/dev/null 2>&1
touch -d '2026-11-07 12:00' "$IMG"
check "precondition: needs_recovery set" '! p3_clean'
check "precondition: e2fsck -fn exits 0 on it anyway" 'e2fsck -fn "$(ext "$P3")" >/dev/null 2>&1'
B1=$(part "$P1" "$P1N"); B2=$(part "$P2" "$P2N"); S=$(sha)
fsck_only
check "exit 0" '[ "$RC" = 0 ]'
check "names the journal" '[[ "$OUT" == *"unreplayed journal"* ]]'
check "image written (it had to be)" '[ "$(sha)" != "$S" ]'
check "p3 clean after" p3_clean
check "film intact" film_ok
check "p1 and p2 bytes untouched" '[ "$(part "$P1" "$P1N")" = "$B1" ] && [ "$(part "$P2" "$P2N")" = "$B2" ]'
stable "journal"

echo "== 4. /data superblock left not clean"
build; debugfs -w -R "ssv state 0" "$(ext "$P3")" >/dev/null 2>&1
check "precondition: state not clean" '[ "$(sb "$P3" "Filesystem state")" != clean ]'
fsck_only
check "exit 0, repaired" '[ "$RC" = 0 ] && [[ "$OUT" == *"image repaired"* ]]'
check "p3 clean after" p3_clean
stable "state"

echo "== 5. /data real damage — the film's blocks marked free"
build; BLK=$(debugfs -R "blocks media/01_FILM.mp4" "$(ext "$P3")" 2>/dev/null | awk '{print $1}')
debugfs -w -R "freeb $BLK 512" "$(ext "$P3")" >/dev/null 2>&1
check "precondition: e2fsck -fn finds errors" '! e2fsck -fn "$(ext "$P3")" >/dev/null 2>&1'
fsck_only
check "exit 0, repaired" '[ "$RC" = 0 ] && [[ "$OUT" == *"image repaired"* ]]'
check "p3 clean after" p3_clean
check "film intact" film_ok
stable "damage"

echo "== 6. rootfs (p2) unreplayed journal — warned, never written"
build; debugfs -w -R "feature needs_recovery" "$(ext "$P2")" >/dev/null 2>&1
touch -d '2026-11-07 12:00' "$IMG"; S=$(sha); M=$(mt)
fsck_only
check "exit 0" '[ "$RC" = 0 ]'
check "warns on p2's journal" '[[ "$OUT" == *"p2: ext4 — unreplayed journal (checked, never written)"* ]]'
check "image untouched: sha256 and mtime" '[ "$(sha)" = "$S" ] && [ "$(mt)" = "$M" ]'

echo "== 7. -n --fsck-only on an unclean image — repairs named, nothing written (pi-tools#t-070)"
build; printf '\001' | dd of="$IMG" bs=1 seek=$(( P1 * 512 + 65 )) conv=notrunc status=none
debugfs -w -R "feature needs_recovery" "$(ext "$P3")" >/dev/null 2>&1
touch -d '2026-11-07 12:00' "$IMG"; S=$(sha); M=$(mt)
check "precondition: p1 dirty bit set, p3 journal unreplayed" '! p1_clean && ! p3_clean'
sleep 1                                     # a write would now read a later second
OUT=$(bash "$TOOL" -n --fsck-only "$IMG" 2>&1); RC=$?
check "exit 0" '[ "$RC" = 0 ]'
check "checked on a read-only loop" '[[ "$OUT" == *"(read-only)"* ]]'
check "names p1's repair" '[[ "$OUT" == *"p1: vfat — "*" — would repair"* ]]'
check "names p3's repair" '[[ "$OUT" == *"p3: ext4 (data) — unreplayed journal — would repair"* ]]'
check "says nothing was written, repaired nothing" '[[ "$OUT" == *"nothing was written"* ]] && [[ "$OUT" != *repaired* ]]'
check "sha256 unchanged" '[ "$(sha)" = "$S" ]'
check "mtime unchanged" '[ "$(mt)" = "$M" ]'
check "still unclean after: p1 dirty, p3 journal" '! p1_clean && ! p3_clean'
check "no loop device left on the image" '[ -z "$(losetup -j "$IMG")" ]'
fsck_only
check "then --fsck-only without -n repairs it" '[ "$RC" = 0 ] && [[ "$OUT" == *"image repaired, clean now"* ]] && p1_clean && p3_clean'
S=$(sha); M=$(mt)
OUT=$(bash "$TOOL" -n --fsck-only "$IMG" 2>&1); RC=$?
check "-n on the repaired image: clean, not written" '[ "$RC" = 0 ] && [[ "$OUT" == *"image clean, not written"* ]] && [[ "$OUT" != *"would repair"* ]]'
check "-n on the repaired image: sha256 and mtime as they were" '[ "$(sha)" = "$S" ] && [ "$(mt)" = "$M" ]'

echo "== 8. a REAL burn onto a scsi_debug RAM card"
CARD=""
if lsmod | grep -q '^scsi_debug '; then
    echo "  skip — scsi_debug already loaded: not this script's card to write"
elif ! modprobe scsi_debug removable=1 dev_size_mb=300 num_tgts=1 max_luns=1 2>/dev/null; then
    echo "  skip — no scsi_debug module on this kernel"
else
    CARD_LOADED=1; udevadm settle -t 15 2>/dev/null
    for d in /sys/block/sd*; do
        [ "$(tr -d ' ' < "$d/device/model" 2>/dev/null)" = scsi_debug ] && CARD=${d##*/}
    done
    [ -n "$CARD" ] || bad "scsi_debug loaded but no card appeared"
fi
if [ -n "$CARD" ]; then
    build; S0=$(sha); M0=$(mt)
    BOUT=$(BURNBATCH_LOG="$T/burn.csv" bash "$TOOL" -y "$IMG" "/dev/$CARD" 2>&1); BRC=$?
    echo "$BOUT" | sed -n 's/^/    | /p' | grep -E 'phase|image|IDENTICAL|DIFFERS|cards|ok|FAIL' | head -12
    check "burn exits 0" '[ "$BRC" = 0 ]'
    check "phase 1 said: image clean, not written" '[[ "$BOUT" == *"image clean, not written"* ]]'
    check "the card is the image, byte for byte" 'cmp -s -n "$(stat -c %s "$IMG")" "/dev/$CARD" "$IMG"'
    check "after the burn: the golden's sha256 unchanged" '[ "$(sha)" = "$S0" ]'
    check "after the burn: the golden's mtime unchanged" '[ "$(mt)" = "$M0" ]'
    # a dirty golden: the burn repairs it ONCE and clones the repaired bytes
    debugfs -w -R "feature needs_recovery" "$(ext "$P3")" >/dev/null 2>&1
    BOUT=$(BURNBATCH_LOG="$T/burn.csv" bash "$TOOL" -y "$IMG" "/dev/$CARD" 2>&1); BRC=$?
    check "dirty golden: burn exits 0, phase 1 repaired" '[ "$BRC" = 0 ] && [[ "$BOUT" == *"image repaired, clean now"* ]]'
    check "dirty golden: the card holds the REPAIRED image" 'p3_clean && cmp -s -n "$(stat -c %s "$IMG")" "/dev/$CARD" "$IMG"'
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
