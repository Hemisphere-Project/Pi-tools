#!/usr/bin/env bash
# flightbox-p4-desk — desk test of image/flightbox-p4 on plain image files: no
# root, no card (pi-tools#t-058 ⑥). Proves the layout, the refusals, the zero
# pass, and that growpart then grows /data (p3) up to p4 and leaves p4 alone —
# the step extendfs runs at a burned card's first boot.
#
#   bash bench/flightbox-p4-desk.sh        # exit 0 = every check green
#
# Not proven here: a real card in a reader (burn-batch --flightbox), and
# extendfs's own first boot on hardware — rastaos#t-017's fresh-burn boot.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
TOOL=image/flightbox-p4
command -v sfdisk >/dev/null || { echo "no sfdisk"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# a RastaOS-shaped card: boot (vfat) / root / data, MBR, 4 MiB grid
card() {  # card <file> <size>
    rm -f "$1"; truncate -s "$2" "$1"
    printf 'label: dos\nstart=8192,size=524288,type=c\nstart=532480,size=2097152,type=83\nstart=2629632,size=409600,type=83\n' \
        | sfdisk -q "$1" >/dev/null
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

echo "flightbox-p4 desk: $PASS ok, $FAIL failed"
[ "$FAIL" -eq 0 ]
