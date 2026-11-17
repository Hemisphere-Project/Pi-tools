#!/usr/bin/env bash
# flightbox-p4-desk — desk test of image/flightbox-p4 on plain image files: no
# root, no card (pi-tools#t-058 ⑥). Proves the layout, the refusals, the zero
# pass, and that growpart then grows /data (p3) up to p4 and leaves p4 alone —
# the step extendfs runs at a burned card's first boot. And the extendfs
# refusal (pi-tools#t-060): a card whose root carries the extendfs of an image
# from before d17d886 (RastaOS 7.3/7.4 — it grows the LAST partition, which p4
# would be) is refused with nothing written, and `--check` says so about the
# image itself, read-only.
#
#   bash bench/flightbox-p4-desk.sh        # exit 0 = every check green
#
# Each card's p2 is a real ext4 (mkfs.ext4 -d, at p2's offset) holding an
# extendfs the way the installer leaves it: /opt/Pi-tools/extendfs/extendfs,
# linked from /usr/local/bin. "new" is THIS tree's extendfs — so the layout
# checks also prove the probe still recognises it — and "old" is d17d886^'s.
#
# Not proven here: a real card in a reader (burn-batch --flightbox), and
# extendfs's own first boot on hardware — rastaos#t-017's fresh-burn boot.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
TOOL=image/flightbox-p4
for c in sfdisk mkfs.ext4 debugfs; do command -v "$c" >/dev/null || { echo "no $c"; exit 2; }; done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# the root filesystems p2 can carry
rootfs() {  # rootfs <dir> <extendfs file>: the installer's layout
    mkdir -p "$1/opt/Pi-tools/extendfs" "$1/usr/local/bin"
    cp "$2" "$1/opt/Pi-tools/extendfs/extendfs"
    ln -s /opt/Pi-tools/extendfs/extendfs "$1/usr/local/bin/extendfs"
}
rootfs "$T/root-new" extendfs/extendfs
git show d17d886^:extendfs/extendfs >"$T/extendfs-old" 2>/dev/null \
    || { echo "no d17d886^ in this checkout's history: the 7.3/7.4 extendfs is the old fixture"; exit 2; }
rootfs "$T/root-old" "$T/extendfs-old"
mkdir -p "$T/root-none/usr/local/bin"          # a root with no extendfs installed

# a RastaOS-shaped card: boot (vfat) / root / data, MBR, 4 MiB grid
card() {  # card <file> <size> [new|old|none|raw]: what p2 holds (default new)
    rm -f "$1"; truncate -s "$2" "$1"
    printf 'label: dos\nstart=8192,size=524288,type=c\nstart=532480,size=2097152,type=83\nstart=2629632,size=409600,type=83\n' \
        | sfdisk -q "$1" >/dev/null
    [ "${3:-new}" = raw ] && return 0
    mkfs.ext4 -q -F -d "$T/root-${3:-new}" -E offset=$((532480*512)) "$1" 1048576K >/dev/null 2>&1 \
        || { echo "mkfs.ext4 -d failed (e2fsprogs >= 1.43 needed)"; exit 2; }
}
part() { sfdisk -d "$1" | grep -E "^[^ ]+$2 *:" ; }

C=$T/c.img; card "$C" 2051M     # not on the 4 MiB grid: the tail must round DOWN to it
# stale bytes where p4 will go: a reused card's old flightbox records
printf 'FLBXstale-record' | dd of="$C" bs=1 seek=$((3145728*512)) conv=notrunc status=none
md5_p3=$(dd if="$C" bs=512 skip=2629632 count=409600 status=none | md5sum)

out=$("$TOOL" "$C" 2>&1); rc=$?
check "lays out p4 (rc 0)" '[ $rc -eq 0 ]'
check "p4 at the 4 MiB-aligned tail, 512 MB, type da" \
      'part "$C" 4 | grep -q "start= *3145728, size= *1048576, type=da"'
check "p1-p3 entries untouched" \
      '[ "$(sfdisk -d "$C" | grep -E "img[123] *:" | md5sum)" = "$(card "$T/ref.img" 2051M; sfdisk -d "$T/ref.img" | grep -E "img[123] *:" | sed "s#$T/ref.img#$C#" | md5sum)" ]'
check "/data's bytes untouched" '[ "$(dd if="$C" bs=512 skip=2629632 count=409600 status=none | md5sum)" = "$md5_p3" ]'
check "stale tail bytes zeroed" '! dd if="$C" bs=512 skip=3145728 count=1 status=none | grep -q FLBX'

out=$("$TOOL" "$C" 2>&1); rc=$?
check "re-run is a no-op (rc 0, 'already')" '[ $rc -eq 0 ] && grep -q already <<<"$out"'
check "re-run leaves 4 partitions" '[ "$(sfdisk -d "$C" | grep -c "start=")" -eq 4 ]'

if command -v growpart >/dev/null; then
    growpart "$C" 3 >/dev/null 2>&1
    check "growpart grows /data up to p4's start" 'part "$C" 3 | grep -q "size= *516096,"'
    check "growpart leaves p4 as it was" 'part "$C" 4 | grep -q "start= *3145728, size= *1048576, type=da"'
else
    echo "  skip growpart checks (no cloud-guest-utils here)"
fi

S=$T/small.img; card "$S" 1600M
printf 'films' | dd of="$S" bs=1 seek=$((3000000*512)) conv=notrunc status=none   # /data's tail
"$TOOL" "$S" >/dev/null 2>&1; rc=$?
check "too-small card refused (rc 1), nothing written" '[ $rc -eq 1 ] && [ "$(sfdisk -d "$S" | grep -c "start=")" -eq 3 ]'
check "too-small card: /data not zeroed" 'dd if="$S" bs=512 skip=3000000 count=1 status=none | grep -q films'

F=$T/foreign.img; card "$F" 2G
echo "start=3200000, size=8192, type=83" | sfdisk --append -q "$F" >/dev/null
"$TOOL" "$F" >/dev/null 2>&1; rc=$?
check "foreign 4th partition refused (rc 1)" '[ $rc -eq 1 ] && part "$F" 4 | grep -q "size= *8192,"'

G=$T/gpt.img; rm -f "$G"; truncate -s 2G "$G"; printf 'label: gpt\nsize=524288\nsize=409600\n' | sfdisk -q "$G" >/dev/null
"$TOOL" "$G" >/dev/null 2>&1; rc=$?
check "GPT disk refused (rc 1)" '[ $rc -eq 1 ]'

TWO=$T/two.img; rm -f "$TWO"; truncate -s 2G "$TWO"; printf 'label: dos\nstart=8192,size=524288,type=c\nstart=532480,size=409600,type=83\n' | sfdisk -q "$TWO" >/dev/null
"$TOOL" "$TWO" >/dev/null 2>&1; rc=$?
check "2-partition disk refused (rc 1)" '[ $rc -eq 1 ] && [ "$(sfdisk -d "$TWO" | grep -c "start=")" -eq 2 ]'

FLIGHTBOX_P4_MB=6 "$TOOL" "$C" >/dev/null 2>&1; rc=$?
check "size not a multiple of 4 refused (rc 2)" '[ $rc -eq 2 ]'

# ── the extendfs refusal (pi-tools#t-060) ──
O=$T/old.img; card "$O" 2051M old
printf 'FLBXstale-record' | dd of="$O" bs=1 seek=$((3145728*512)) conv=notrunc status=none
md5_o=$(md5sum <"$O")
out=$("$TOOL" "$O" 2>&1); rc=$?
check "7.3/7.4 extendfs (d17d886^) refused (rc 1), says why" '[ $rc -eq 1 ] && grep -q "LAST partition" <<<"$out"'
check "7.3/7.4 extendfs: still 3 partitions" '[ "$(sfdisk -d "$O" | grep -c "start=")" -eq 3 ]'
check "7.3/7.4 extendfs: no zero pass (stale tail kept)" 'dd if="$O" bs=512 skip=3145728 count=1 status=none | grep -q FLBX'
check "7.3/7.4 extendfs: not one byte written" '[ "$(md5sum <"$O")" = "$md5_o" ]'

N=$T/none.img; card "$N" 2051M none
out=$("$TOOL" "$N" 2>&1); rc=$?
check "no extendfs on p2 refused (rc 1)" '[ $rc -eq 1 ] && grep -q "no extendfs" <<<"$out" && [ "$(sfdisk -d "$N" | grep -c "start=")" -eq 3 ]'

RAW=$T/raw.img; card "$RAW" 2051M raw
out=$("$TOOL" "$RAW" 2>&1); rc=$?
check "p2 with no filesystem refused (rc 1)" '[ $rc -eq 1 ] && grep -q "no extendfs" <<<"$out" && [ "$(sfdisk -d "$RAW" | grep -c "start=")" -eq 3 ]'

# a card that already got p4 before this check existed: refused, with the way back
A=$T/already.img; card "$A" 2051M old
echo "start=3145728, size=1048576, type=da" | sfdisk --append -q "$A" >/dev/null
out=$("$TOOL" "$A" 2>&1); rc=$?
check "old extendfs under an existing p4: refused (rc 1), names sfdisk --delete" '[ $rc -eq 1 ] && grep -q "sfdisk --delete" <<<"$out"'

# --check on the IMAGE itself (burn-batch's plan-time question): an image ends
# with /data, so no room is asked for, and nothing is written either way
I=$T/golden.img; card "$I" $((3039232*512)); md5_i=$(md5sum <"$I")
out=$("$TOOL" --check "$I" 2>&1); rc=$?
check "--check on a 7.5-shaped image: rc 0, nothing written" '[ $rc -eq 0 ] && [ "$(md5sum <"$I")" = "$md5_i" ]'
IO=$T/golden-old.img; card "$IO" $((3039232*512)) old; md5_io=$(md5sum <"$IO")
out=$("$TOOL" --check "$IO" 2>&1); rc=$?
check "--check on a 7.3/7.4 image: rc 1, says why, nothing written" '[ $rc -eq 1 ] && grep -q "LAST partition" <<<"$out" && [ "$(md5sum <"$IO")" = "$md5_io" ]'

echo "flightbox-p4 desk: $PASS ok, $FAIL failed"
[ "$FAIL" -eq 0 ]
